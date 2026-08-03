#!/usr/bin/env bash
# IMP-015 section 6-c/6-d performance A/B driver.
#
# Phase G (the gate): Q10, 3 balanced cycles B->P->P->B = 12 gated blocks.
# Each block: restart the campaign server on that block's binary via
# server_ctl.sh (section 3-a taskset 0-15 + numactl --membind=0 from process
# start, section 3-b ownership), then measure_block.sh Q10 (section 3-a quiet
# pre-gate, per-block WARM proof, bgload monitor during the block,
# 1 uncounted warmup + 3 measured on one connection), then stop the server and
# move the canonical artifacts to a per-block directory.
#
# Phase S (corroboration + negative controls): one balanced cycle B->P->P->B.
# Per block: Q15 via its session-unit gated block, then Q01 Q03 Q05 Q11 Q16 Q18
# via measure_block.sh, all on the block's single server instance. Two block
# medians per variant per query — labelled corroboration/controls, NOT the
# primary gate estimate.
#
# B = install/base (immutable), P = install/IMP-015. Variant selection is
# TPCH_SSPQ_IMPL_VARIANT, which campaign_config.py maps to the install prefix.
#
# Usage: imp015_ab.sh [gate|stream|all]
set -uo pipefail

HARNESS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="${1:-all}"

AB_BASE=/data/tpch-sspq/tpch-sspq-impl-r1-20260803/work/IMP-015/ab
mkdir -p "$AB_BASE"
STATE="$AB_BASE/driver-state.log"
log() { echo "$(date -u +%Y%m%dT%H%M%SZ) $*" | tee -a "$STATE"; }

with_variant() { # with_variant VARIANT cmd...
  local v="$1"; shift
  TPCH_SSPQ_IMPL_VARIANT="$v" "$@"
}

server_start() { with_variant "$1" bash "$HARNESS/server_ctl.sh" start; }
server_stop()  { with_variant "$1" bash "$HARNESS/server_ctl.sh" stop; }

move_block_artifacts() { # QNN LABELDIR
  local qnn="$1" dest="$2"
  local w="/data/tpch-sspq/tpch-sspq-impl-r1-20260803/work/$qnn"
  mkdir -p "$dest"
  cp -f "$w/${qnn}-cubrid-headline.json" "$w/${qnn}-cubrid-warm.json" \
        "$w/${qnn}-cubrid-bgload.json" "$dest/" 2>/dev/null || true
  cp -f "$w/sink/${qnn}-cubrid-headline.out" "$dest/" 2>/dev/null || true
}

gated_block() { # VARIANT QNN DEST  (measure_block path)
  local v="$1" qnn="$2" dest="$3"
  log "block start qnn=$qnn variant=$v dest=$dest"
  server_start "$v" || { log "SERVER START FAILED variant=$v"; return 9; }
  local rc=0
  if [ "$qnn" = Q15 ]; then
    with_variant "$v" bash "$HARNESS/q15_gated_block.sh" cubrid 6 1800 || rc=$?
  else
    with_variant "$v" bash "$HARNESS/measure_block.sh" "$qnn" cubrid 6 1800 || rc=$?
  fi
  server_stop "$v"
  move_block_artifacts "$qnn" "$dest"
  log "block end qnn=$qnn variant=$v rc=$rc"
  return "$rc"
}

stream_block() { # VARIANT IDX — one server instance, Q15 + controls
  local v="$1" idx="$2" rc=0
  log "stream block $idx variant=$v start"
  server_start "$v" || { log "SERVER START FAILED variant=$v"; return 9; }
  for qnn in Q15 Q01 Q03 Q05 Q11 Q16 Q18; do
    local qrc=0
    if [ "$qnn" = Q15 ]; then
      with_variant "$v" bash "$HARNESS/q15_gated_block.sh" cubrid 6 1800 || qrc=$?
    else
      with_variant "$v" bash "$HARNESS/measure_block.sh" "$qnn" cubrid 6 1800 || qrc=$?
    fi
    move_block_artifacts "$qnn" "$AB_BASE/stream/block$(printf %02d "$idx")-$v/$qnn"
    log "stream block $idx variant=$v qnn=$qnn rc=$qrc"
    [ "$qrc" -ne 0 ] && rc="$qrc"
  done
  server_stop "$v"
  log "stream block $idx variant=$v end rc=$rc"
  return "$rc"
}

fail() { log "DRIVER FAILED: $*"; exit 1; }

if pgrep -x cub_server >/dev/null; then
  fail "a cub_server is already running — ownership gate (3-b) refuses to start"
fi

if [ "$MODE" = gate ] || [ "$MODE" = all ]; then
  i=0
  for cycle in 1 2 3; do
    for v in base IMP-015 IMP-015 base; do
      i=$((i+1))
      gated_block "$v" Q10 "$AB_BASE/Q10/block$(printf %02d $i)-$v" \
        || fail "Q10 gated block $i ($v) failed"
    done
  done
  log "PHASE G COMPLETE: 12 Q10 gated blocks"
fi

if [ "$MODE" = stream ] || [ "$MODE" = all ]; then
  # STREAM_START allows resuming an interrupted stream cycle at block N
  # (earlier completed blocks' artifacts are already promoted per-block).
  START="${STREAM_START:-1}"
  i=0
  for v in base IMP-015 IMP-015 base; do
    i=$((i+1))
    [ "$i" -lt "$START" ] && continue
    stream_block "$v" "$i" || fail "stream block $i ($v) failed"
  done
  log "PHASE S COMPLETE (from block $START): stream blocks (Q15 + Q01/Q03/Q05/Q11/Q16/Q18)"
fi

log "IMP015-AB DRIVER DONE ($MODE)"
