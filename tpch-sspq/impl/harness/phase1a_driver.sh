#!/usr/bin/env bash
# TPCH-SSPQ implementation campaign `tpch-sspq-impl-r1-20260803`
# ============================================================================
# Phase 1A fresh baseline driver — IMPL-SSOT sections 3, 6-a-2, 6-c, 6-d, 8-b.
#
# AMEND-E: Phase 1A runs under ONE detached tmux session executing THIS checked-in
# script, which iterates Q01-Q22 and their blocks. No LLM is in the measurement
# loop. Session name is fixed:
#     tpch-sspq-impl-r1-20260803-phase1a-driver
#
# Per query, per block (section 3-c + 6-c):
#   1. stop any campaign server, then start a FRESH one from the base install with
#      taskset -c 0-15 + numactl --membind=0 applied at fork (section 3-a);
#   2. section 3-b ownership gate + all-TID affinity proof + NUMA record;
#   3. wait for a quiet SUT set (external <= THRESHOLD core-s/s, section 3-a);
#   4. prove WARM convergence with the per-query gate in warm_params.json;
#   5. run the contract block: 1 uncounted warmup + 3 measured statements on one
#      direct csql -C connection, all rows consumed into a campaign-owned sink;
#   6. the during-block external-load monitor decides CLEAN vs
#      INVALID_BACKGROUND_LOAD; an invalid block is preserved and retried;
#   7. re-verify all-TID affinity, ownership and NUMA after the block.
#
# Block count: 6 per query. Section 3-c requires a per-block median, within-block
# dispersion, block dispersion and a base-vs-base paired-CV noise floor but names
# no count; section 6-d fixes the paired design at "at least 3 B-P-P-B cycles,
# giving 6 block medians per variant". 6 base blocks = 3 base-vs-base pairs is the
# only reading that makes 3-c's paired CV the same statistic 6-d's MDE consumes.
#
# Usage: phase1a_driver.sh [QNN ...]     (default: Q01..Q22)
set -uo pipefail

HARNESS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${HARNESS}/campaign_env.sh"

QUERIES_TO_RUN=("$@")
if [ "${#QUERIES_TO_RUN[@]}" -eq 0 ]; then
  QUERIES_TO_RUN=(Q01 Q02 Q03 Q04 Q05 Q06 Q07 Q08 Q09 Q10 Q11 Q12 Q13 Q14 Q15 \
                  Q16 Q17 Q18 Q19 Q20 Q21 Q22)
fi

BLOCKS="${TPCH_SSPQ_BLOCKS:-$N_BLOCKS}"
MAX_ATTEMPTS="${TPCH_SSPQ_MAX_ATTEMPTS:-4}"
MAX_WAIT_S="${TPCH_SSPQ_MAX_WAIT_S:-1800}"

STATE="${RAW_ROOT}/work/BASELINE"
mkdir -p "$STATE"
DRIVER_LOG="${STATE}/phase1a-driver.log"

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" | tee -a "$DRIVER_LOG"; }

log "=== Phase 1A driver start pid=$$ campaign=${CAMPAIGN} pin=${IMPL_SSOT_COMMIT}"
log "    prefix=${CUBRID_HOME} conf=${CONF_SHA256} tmp=${CUBRID_TMP}"
log "    threshold=${THRESHOLD} core-s/s  blocks=${BLOCKS}  queries=${QUERIES_TO_RUN[*]}"

warm_param() {  # warm_param QNN KEY
  python3.11 -c "
import json,sys
d=json.load(open('${HARNESS}/warm_params.json'))
q=d['queries'].get(sys.argv[1], {})
print(q.get(sys.argv[2], d['defaults'][sys.argv[2]]))
" "$1" "$2"
}

restart_server() {  # restart_server IDENTITY_JSON_PREFIX
  local pre="$1"
  bash "${HARNESS}/server_ctl.sh" stop >> "$DRIVER_LOG" 2>&1
  sleep 2
  bash "${HARNESS}/server_ctl.sh" start "${pre}-identity-pre.json" >> "$DRIVER_LOG" 2>&1
  local rc=$?
  if [ "$rc" -ne 0 ]; then
    log "    SERVER START/IDENTITY FAILED rc=${rc} (see ${pre}-identity-pre.json)"
    return "$rc"
  fi
  return 0
}

for QNN in "${QUERIES_TO_RUN[@]}"; do
  QDIR="${RAW_ROOT}/raw/${QNN}"
  W="${RAW_ROOT}/work/${QNN}"
  mkdir -p "$QDIR" "$W/sink"
  log "########## ${QNN} — ${BLOCKS} blocks ##########"

  WWIN="$(warm_param "$QNN" window)"
  WTOL="$(warm_param "$QNN" level_tol)"
  WSPR="$(warm_param "$QNN" spread_sanity)"
  WMAX="$(warm_param "$QNN" max_statements)"
  export TPCH_SSPQ_WARM_WINDOW="$WWIN"
  export TPCH_SSPQ_WARM_LEVEL_TOL="$WTOL"
  export TPCH_SSPQ_WARM_SPREAD="$WSPR"
  export TPCH_SSPQ_WARM_MAX="$WMAX"
  export WARM_STATEMENTS="$WMAX"
  export WARM_SESSIONS="$WMAX"
  log "  warm gate: window=${WWIN} level_tol=${WTOL} spread=${WSPR} max=${WMAX}"

  for b in $(seq 1 "$BLOCKS"); do
    BP="${QDIR}/block${b}"
    log "  --- ${QNN} block ${b}/${BLOCKS}"

    # (1)(2) fresh server + section 3-a/3-b gates BEFORE the block
    if ! restart_server "$BP"; then
      python3.11 -c "
import json,sys
json.dump({'campaign_id':'${CAMPAIGN}','qnn':'${QNN}','block':${b},'valid':False,
           'invalid_reason':'SERVER_START_OR_IDENTITY_FAILED',
           'note':'IMPL-SSOT section 3-a/3-b gate did not pass; block not measured'},
          open('${BP}-INVALID.json','w'), indent=2, sort_keys=True)"
      log "    block ${b} INVALID (server gate)"
      continue
    fi

    # (3)-(6) the gated contract block
    if [ "$QNN" = "Q15" ]; then
      bash "${HARNESS}/q15_gated_block.sh" cubrid "$MAX_ATTEMPTS" "$MAX_WAIT_S" \
          >> "$DRIVER_LOG" 2>&1
    else
      bash "${HARNESS}/measure_block.sh" "$QNN" cubrid "$MAX_ATTEMPTS" "$MAX_WAIT_S" \
          >> "$DRIVER_LOG" 2>&1
    fi
    brc=$?

    # (7) section 3-a/3-b gates AFTER the block — late-spawned pooled threads are
    # the known failure mode, so the all-TID check is repeated, not assumed.
    bash "${HARNESS}/server_ctl.sh" identity "${BP}-identity-post.json" \
        >> "$DRIVER_LOG" 2>&1
    prc=$?

    if [ "$brc" -eq 0 ] && [ "$prc" -eq 0 ]; then
      cp -f "$W/${QNN}-cubrid-headline.json" "${BP}-headline.json"
      cp -f "$W/${QNN}-cubrid-warm.json"     "${BP}-warm.json"
      cp -f "$W/${QNN}-cubrid-bgload.json"   "${BP}-bgload.json"
      cp -f "$W/sink/${QNN}-cubrid-headline.out" "${BP}-headline.out"
      log "    block ${b} ACCEPTED"
    else
      reason="MEASURE_BLOCK_REJECTED"
      [ "$prc" -eq 3 ] && reason="OFF_CPUSET_TID_AFTER_BLOCK"
      [ "$prc" -eq 4 ] && reason="SERVER_NOT_CAMPAIGN_OWNED_AFTER_BLOCK"
      python3.11 -c "
import json,sys
json.dump({'campaign_id':'${CAMPAIGN}','qnn':'${QNN}','block':${b},'valid':False,
           'invalid_reason':'${reason}','measure_block_rc':${brc},
           'post_identity_rc':${prc}},
          open('${BP}-INVALID.json','w'), indent=2, sort_keys=True)"
      log "    block ${b} INVALID reason=${reason} brc=${brc} prc=${prc}"
      # preserve every attempt's evidence for audit (section 8-e)
      cp -f "$W"/${QNN}-cubrid-*attempt*.json "$QDIR/" 2>/dev/null
    fi
  done

  # Per-query reference capture on the base binary: canonical result set
  # (section 6-b), plan estimated vs actual rows and perf counters (section 6-c).
  log "  --- ${QNN} reference capture (correctness reference + plan + perf)"
  restart_server "${QDIR}/reference" >> "$DRIVER_LOG" 2>&1
  python3.11 "${HARNESS}/reference_capture.py" "$QNN" >> "$DRIVER_LOG" 2>&1
  log "  --- ${QNN} reference capture rc=$?"
done

log "=== Phase 1A driver: stopping campaign server"
bash "${HARNESS}/server_ctl.sh" stop >> "$DRIVER_LOG" 2>&1
log "=== Phase 1A driver COMPLETE pid=$$"
touch "${STATE}/PHASE1A-DRIVER-DONE"
