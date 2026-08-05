#!/usr/bin/env bash
# IMP-005 section 6-c/6-d performance A/B driver (modelled on imp015_ab.sh).
#
# IMP-005 is the enabler candidate: the parallel trace merge stops merging a
# nested-loop scan_ptr chain k times per sibling tree. It is a STATISTICS-ONLY
# change, so the A/B is a NULL GUARD, not an improvement hunt (see
# worktrees/IMP-005/implementation-plan.md "Verdict criteria"): the accepted
# outcome is "no regression", and a CI containing 1.0 is the EXPECTED result.
#
# Phase G (the gate): Q09, 3 balanced cycles B->P->P->B = 12 gated blocks.
#   Q09 is the gate query because (a) it is one of the plan's five deep-NL trace
#   targets, (b) its trace probe showed the largest per-node duplication factors
#   actually removed by the patch (2x at depth 8, 3x at depth 10), and (c) its
#   pinned fast-regime paired CV (0.002788) gives the tightest corrected MDE per
#   unit of measurement time among the targets (4.27% at the user-decided
#   combination rule (c), max factor 15.3158).
# Phase S (corroboration + negative controls): one balanced cycle B->P->P->B
#   over the other 21 queries, i.e. the remaining trace targets (Q05 Q07 Q08
#   Q21), every other q_relations query (Q03 Q04 Q06 Q10 Q11 Q12 Q13 Q15 Q17
#   Q19) and every negative control (Q01 Q02 Q14 Q16 Q18 Q20 Q22). Two block
#   medians per variant per query — corroboration and the 7-c 3% non-target
#   regression check, NOT the primary gate estimate.
#
# Per block, section 6-c is followed in order: restart the campaign server on
# that block's binary through server_ctl.sh (section 3-a taskset 0-15 +
# numactl --membind=0 from process start, section 3-b ownership + all-TID
# affinity gate at start), prove WARM for that block with the query's pinned
# warm parameters, run the gated block (quiet pre-gate, bgload monitor,
# 1 uncounted warmup + 3 measured on one connection), re-verify ownership and
# all-TID affinity AFTER the block, then stop the server.
#
# B = install/base (immutable), P = install/IMP-005. Variant selection is
# TPCH_SSPQ_IMPL_VARIANT, which campaign_config.py maps to the install prefix.
#
# Resumable: a block whose destination already holds a headline JSON is skipped,
# so an interrupted run continues instead of overwriting evidence.
#
# Usage: imp005_ab.sh [gate|stream|all]
set -uo pipefail

HARNESS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="${1:-all}"
PATCH_VARIANT=IMP-005
GATE_QNN=Q09
STREAM_QUERIES=(Q15 Q01 Q02 Q03 Q04 Q05 Q06 Q07 Q08 Q10 Q11 Q12 Q13 Q14 \
                Q16 Q17 Q18 Q19 Q20 Q21 Q22)
MAX_ATTEMPTS="${TPCH_SSPQ_MAX_ATTEMPTS:-4}"
MAX_WAIT_S="${TPCH_SSPQ_MAX_WAIT_S:-1800}"

AB_BASE=/data/tpch-sspq/tpch-sspq-impl-r1-20260803/work/IMP-005/ab
mkdir -p "$AB_BASE"
STATE="$AB_BASE/driver-state.log"
log() { echo "$(date -u +%Y%m%dT%H%M%SZ) $*" | tee -a "$STATE"; }
fail() { log "DRIVER FAILED: $*"; exit 1; }

with_variant() { # with_variant VARIANT cmd...
  local v="$1"; shift
  TPCH_SSPQ_IMPL_VARIANT="$v" "$@"
}

server_start() { # server_start VARIANT IDENTITY_JSON
  with_variant "$1" bash "$HARNESS/server_ctl.sh" start "$2"
}
server_stop() { with_variant "$1" bash "$HARNESS/server_ctl.sh" stop; }
server_identity() { # server_identity VARIANT OUT_JSON
  with_variant "$1" bash "$HARNESS/server_ctl.sh" identity "$2"
}

warm_param() { # warm_param QNN KEY
  python3.11 -c "
import json,sys
d=json.load(open('${HARNESS}/warm_params.json'))
q=d['queries'].get(sys.argv[1], {})
print(q.get(sys.argv[2], d['defaults'][sys.argv[2]]))
" "$1" "$2"
}

export_warm_params() { # export_warm_params QNN
  local qnn="$1" wwin wtol wspr wmax
  wwin="$(warm_param "$qnn" window)";        wtol="$(warm_param "$qnn" level_tol)"
  wspr="$(warm_param "$qnn" spread_sanity)"; wmax="$(warm_param "$qnn" max_statements)"
  export TPCH_SSPQ_WARM_WINDOW="$wwin" TPCH_SSPQ_WARM_LEVEL_TOL="$wtol"
  export TPCH_SSPQ_WARM_SPREAD="$wspr"  TPCH_SSPQ_WARM_MAX="$wmax"
  export WARM_STATEMENTS="$wmax" WARM_SESSIONS="$wmax"
  log "  warm gate $qnn: window=$wwin level_tol=$wtol spread=$wspr max=$wmax"
}

# Per-query gate refinements, only ever STRICTER/FINER than the defaults, as
# documented in measure_block.sh: Q07's neighbour load arrives in phases, so its
# quiet run-up is lengthened; Q17's block is sub-second, so its load sampler is
# made finer than 0.25 s.
export_block_gate_params() { # export_block_gate_params QNN
  unset TPCH_SSPQ_QUIET_N TPCH_SSPQ_QUIET_INTERVAL TPCH_SSPQ_BGLOAD_INTERVAL
  case "$1" in
    Q07) export TPCH_SSPQ_QUIET_N=30 TPCH_SSPQ_QUIET_INTERVAL=2.0 ;;
    Q17) export TPCH_SSPQ_BGLOAD_INTERVAL=0.05 ;;
  esac
}

promote_block_artifacts() { # QNN DEST
  local qnn="$1" dest="$2"
  local w="/data/tpch-sspq/tpch-sspq-impl-r1-20260803/work/$qnn"
  mkdir -p "$dest"
  cp -f "$w/${qnn}-cubrid-headline.json" "$w/${qnn}-cubrid-warm.json" \
        "$w/${qnn}-cubrid-bgload.json" "$dest/" 2>/dev/null || true
  cp -f "$w/sink/${qnn}-cubrid-headline.out" "$dest/" 2>/dev/null || true
}

block_done() { # block_done QNN DEST
  [ -s "$2/$1-cubrid-headline.json" ]
}

run_one_query() { # run_one_query VARIANT QNN DEST  (server already up)
  local v="$1" qnn="$2" dest="$3" rc=0
  export_warm_params "$qnn"
  export_block_gate_params "$qnn"
  if [ "$qnn" = Q15 ]; then
    with_variant "$v" bash "$HARNESS/q15_gated_block.sh" cubrid \
      "$MAX_ATTEMPTS" "$MAX_WAIT_S" || rc=$?
  else
    with_variant "$v" bash "$HARNESS/measure_block.sh" "$qnn" cubrid \
      "$MAX_ATTEMPTS" "$MAX_WAIT_S" || rc=$?
  fi
  promote_block_artifacts "$qnn" "$dest"
  return "$rc"
}

gated_block() { # gated_block VARIANT QNN DEST
  local v="$1" qnn="$2" dest="$3" rc=0
  if block_done "$qnn" "$dest"; then
    log "block SKIP (already present) qnn=$qnn variant=$v dest=$dest"
    return 0
  fi
  mkdir -p "$dest"
  log "block start qnn=$qnn variant=$v dest=$dest"
  server_start "$v" "$dest/identity-start.json" \
    || { log "SERVER START/IDENTITY FAILED variant=$v"; return 9; }
  run_one_query "$v" "$qnn" "$dest" || rc=$?
  # section 6-c step 6: re-verify all-TID affinity and ownership AFTER the block
  server_identity "$v" "$dest/identity-end.json" || rc=$((rc == 0 ? 8 : rc))
  server_stop "$v"
  log "block end qnn=$qnn variant=$v rc=$rc"
  return "$rc"
}

stream_block() { # stream_block VARIANT IDX — one server instance, many queries
  local v="$1" idx="$2" rc=0
  local bdir="$AB_BASE/stream/block$(printf %02d "$idx")-$v"
  local pending=0 qnn
  for qnn in "${STREAM_QUERIES[@]}"; do
    block_done "$qnn" "$bdir/$qnn" || pending=1
  done
  if [ "$pending" -eq 0 ]; then
    log "stream block $idx variant=$v SKIP (all queries already present)"
    return 0
  fi
  mkdir -p "$bdir"
  log "stream block $idx variant=$v start"
  server_start "$v" "$bdir/identity-start.json" \
    || { log "SERVER START/IDENTITY FAILED variant=$v"; return 9; }
  for qnn in "${STREAM_QUERIES[@]}"; do
    if block_done "$qnn" "$bdir/$qnn"; then
      log "stream block $idx variant=$v qnn=$qnn SKIP (already present)"
      continue
    fi
    local qrc=0
    run_one_query "$v" "$qnn" "$bdir/$qnn" || qrc=$?
    log "stream block $idx variant=$v qnn=$qnn rc=$qrc"
    [ "$qrc" -ne 0 ] && rc="$qrc"
  done
  server_identity "$v" "$bdir/identity-end.json" || rc=$((rc == 0 ? 8 : rc))
  server_stop "$v"
  log "stream block $idx variant=$v end rc=$rc"
  return "$rc"
}

# --- preflight ---------------------------------------------------------------
# Section 6-a: base binary immutability is asserted against the pinned sha256;
# the patch binary's fingerprint is recorded and, on a resumed run, asserted
# unchanged, so a rebuilt P mid-A/B is a stop-and-report instead of a silent
# variant swap. Section 6-a-2: both installs' cubrid.conf must be the pinned
# file byte for byte.
preflight() {
  python3.11 - "$AB_BASE" "$PATCH_VARIANT" <<'PY'
import hashlib, json, os, sys
sys.path.insert(0, os.environ["HARNESS"])
import campaign_config as c
ab, patch = sys.argv[1], sys.argv[2]
root = os.path.join(c.CAMPAIGN_ROOT, "install")
out = {"campaign_id": c.CAMPAIGN, "imp_id": "IMP-005",
       "impl_ssot_commit": c.IMPL_SSOT_COMMIT, "impl_ssot_blob": c.IMPL_SSOT_BLOB,
       "cubrid_base_sha": c.CUBRID_BASE_SHA, "variants": {}}
for v in ("base", patch):
    prefix = os.path.join(root, v)
    c.assert_prefix_allowed(prefix)
    conf = c.assert_conf_sha(prefix)
    fp = {}
    for name in ("cub_server", "cub_master", "csql"):
        fp[name] = c.sha256_file(os.path.join(prefix, "bin", name))
    out["variants"][v] = {"prefix": prefix, "conf_sha256": conf,
                          "binary_sha256": fp}
b = out["variants"]["base"]["binary_sha256"]["cub_server"]
if b != c.BASE_CUB_SERVER_SHA256:
    raise SystemExit(f"FATAL install/base cub_server sha256 {b} != pinned "
                     f"{c.BASE_CUB_SERVER_SHA256} (section 6-a)")
p = out["variants"][patch]["binary_sha256"]["cub_server"]
if p == b:
    raise SystemExit("FATAL patch cub_server is byte-identical to base — "
                     "the A/B would compare B against B")
path = os.path.join(ab, "binary-fingerprints.json")
if os.path.exists(path):
    old = json.load(open(path))
    for v in ("base", patch):
        o = old["variants"][v]["binary_sha256"]
        n = out["variants"][v]["binary_sha256"]
        if o != n:
            raise SystemExit(f"FATAL {v} binaries changed since this A/B "
                             f"started: {o} -> {n} (section 6-a)")
else:
    with open(path, "w") as f:
        json.dump(out, f, indent=2, sort_keys=True)
print(f"preflight OK base={b[:12]} patch={p[:12]} conf pinned on both")
PY
}

export HARNESS
log "=== IMP-005 A/B driver start pid=$$ mode=$MODE"
preflight || fail "preflight failed (section 6-a / 6-a-2)"

if pgrep -x cub_server >/dev/null; then
  fail "a cub_server is already running — ownership gate (3-b) refuses to start"
fi

if [ "$MODE" = gate ] || [ "$MODE" = all ]; then
  i=0
  for cycle in 1 2 3; do
    for v in base "$PATCH_VARIANT" "$PATCH_VARIANT" base; do
      i=$((i + 1))
      gated_block "$v" "$GATE_QNN" \
        "$AB_BASE/$GATE_QNN/block$(printf %02d $i)-$v" \
        || fail "$GATE_QNN gated block $i ($v) failed"
    done
  done
  log "PHASE G COMPLETE: 12 $GATE_QNN gated blocks"
fi

if [ "$MODE" = stream ] || [ "$MODE" = all ]; then
  START="${STREAM_START:-1}"
  i=0
  for v in base "$PATCH_VARIANT" "$PATCH_VARIANT" base; do
    i=$((i + 1))
    [ "$i" -lt "$START" ] && continue
    stream_block "$v" "$i" || fail "stream block $i ($v) failed"
  done
  log "PHASE S COMPLETE (from block $START): ${#STREAM_QUERIES[@]} queries per block"
fi

log "IMP005-AB DRIVER DONE ($MODE)"
