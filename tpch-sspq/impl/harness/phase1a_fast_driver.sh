#!/usr/bin/env bash
# TPCH-SSPQ implementation campaign `tpch-sspq-impl-r1-20260803`
# ============================================================================
# Phase 1A FAST fresh-baseline driver — IMPL-SSOT sections 3-c-1, 6-a-2, 6-d-1,
# 8-b, at the AMEND-G pin.
#
# AMEND-G supersedes, for Phase 1A only, the per-block server restart that
# section 3-c step 1 required and that phase1a_driver.sh (the AMEND-E driver)
# implemented. Phase 2's B -> P -> P -> B A/B regime (section 6-c) is UNCHANGED
# and still restarts per block, because it swaps binaries.
#
# WHY
# ---
# Measured on the abandoned restart-regime run, per-query cost was roughly
#     6 x ( 49 s + 33.7 x query_wall )
# Only 4 executions per block are on the measurement path (1 uncounted warmup +
# 3 measured). The remaining ~30 execution-equivalents per block are WARM
# re-convergence, incurred because every block restarted the server and so
# emptied the 8192M data buffer that section 6-a-2 pins. The restarts themselves
# are only ~49 s x 132 blocks ~= 1.8 h of a ~16 h projection; the re-convergence
# is the rest. This driver removes the restart, and with it the re-convergence:
# ~202 x wall becomes ~34 x wall.
#
# THE REGIME (section 3-c-1)
# --------------------------
#   sweep start : ONE cub_server, started once under `taskset -c 0-15
#                 numactl --membind=0` wrapping the mandated cubrid-server-ctl.sh
#                 so affinity and memory binding are inherited AT FORK, never
#                 applied post-hoc; ownership + all-TID affinity proved.
#   per query   : ownership + all-TID affinity re-proved at the QUERY BOUNDARY;
#                 WARM established ONCE and proved (not assumed); then 6 blocks
#                 x (1 uncounted warmup + 3 measured) with NO restart between
#                 blocks; then the canonical result + plan + perf capture.
#   per block   : the 6.0 core-s/s external-CPU gate is sampled and enforced,
#                 unchanged; cubrid.conf sha256 and CUBRID_TMP asserted;
#                 ownership + all-TID affinity + NUMA re-proved after the block.
#   sweep end   : ownership proved, server stopped once.
#
# Query order is Q01..Q06 FIRST (section 3-c-1 step 5), so the section 6-d-1
# restart-variance calibration against raw-restart-calibration/ becomes
# available as early as possible in the sweep.
#
# WHY A QUERY IS THE INVALIDATION UNIT FOR AFFINITY
# -------------------------------------------------
# Section 3-c-1: without a per-block restart, an off-target TID discovered at a
# query boundary may have been serving EARLIER blocks of that query undetected.
# The whole query is therefore invalidated and re-run on a fresh server -- and a
# fresh server is the only remedy, because resources.cpp:190 caches the affinity
# mask in a function-local static at server start, so post-hoc taskset provably
# cannot rebind the pool.
#
# RESUMABILITY
# ------------
# Completion is per query and is recorded by a durable marker file
#   ${RAW_ROOT}/raw/<QNN>/QUERY-COMPLETE.json
# written only after that query's blocks AND its reference capture have both
# finished. On start the driver skips every query whose marker exists. A query
# killed mid-flight has no marker, so its partial artifacts are overwritten and
# it is measured again from a clean WARM -- never half-salvaged. The marker
# records the block count, the pin and the server PID/start time it was
# collected under, so a resumed sweep that lands on a different server instance
# is visible in the evidence rather than silently averaged in.
#
# Usage: phase1a_fast_driver.sh [QNN ...]      (default: Q01..Q06 then Q07..Q22)
set -uo pipefail

HARNESS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# campaign_env.sh asserts CUBRID_TMP (never /tmp, section 6-a-2 / 8-e) and the
# pinned cubrid.conf sha256 at source time, and derives THRESHOLD from
# campaign_config.py rather than an inherited literal (section 8-b).
. "${HARNESS}/campaign_env.sh"

# csql drops csql.err into its cwd; keep it out of the checked-in harness dir.
mkdir -p "${RAW_ROOT}/work/BASELINE"
cd "${RAW_ROOT}/work/BASELINE" || exit 1

QUERIES_TO_RUN=("$@")
if [ "${#QUERIES_TO_RUN[@]}" -eq 0 ]; then
  # Calibration set first (section 3-c-1 step 5 / section 6-d-1).
  QUERIES_TO_RUN=(Q01 Q02 Q03 Q04 Q05 Q06 \
                  Q07 Q08 Q09 Q10 Q11 Q12 Q13 Q14 Q15 \
                  Q16 Q17 Q18 Q19 Q20 Q21 Q22)
fi

BLOCKS="${TPCH_SSPQ_BLOCKS:-$N_BLOCKS}"
MAX_ATTEMPTS="${TPCH_SSPQ_MAX_ATTEMPTS:-4}"
MAX_WAIT_S="${TPCH_SSPQ_MAX_WAIT_S:-1800}"
QUERY_ATTEMPTS="${TPCH_SSPQ_QUERY_ATTEMPTS:-2}"

STATE="${RAW_ROOT}/work/BASELINE"
SWEEP="${RAW_ROOT}/raw/_sweep"
mkdir -p "$STATE" "$SWEEP"
DRIVER_LOG="${STATE}/phase1a-fast-driver.log"

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" | tee -a "$DRIVER_LOG"; }

# --- preflight: fingerprints, before anything is started ---------------------
# Section 6-a: the base binary is immutable and its sha256 was recorded. A
# rebuilt or swapped install/base is a stop-and-report condition, not something
# to measure around. Section 6-a-2: the installed cubrid.conf must be the pinned
# file byte for byte (campaign_env.sh already asserted it; asserted again here so
# the value lands in this driver's own log).
preflight() {
  local conf_got srv_got srv_want
  conf_got="$(sha256sum "${CUBRID_HOME}/conf/cubrid.conf" | cut -d' ' -f1)"
  srv_got="$(sha256sum "${CUBRID_HOME}/bin/cub_server" | cut -d' ' -f1)"
  srv_want="$(python3.11 -c "
import sys; sys.path.insert(0,'${HARNESS}')
import campaign_config as c; print(c.BASE_CUB_SERVER_SHA256)")"
  log "  preflight cubrid.conf sha256 = ${conf_got}"
  log "  preflight cub_server  sha256 = ${srv_got}"
  if [ "$conf_got" != "$CONF_SHA256" ]; then
    log "  FATAL cubrid.conf sha256 mismatch (pinned ${CONF_SHA256}) — section 6-a-2"
    return 1
  fi
  if [ "$srv_got" != "$srv_want" ]; then
    log "  FATAL cub_server sha256 mismatch (pinned ${srv_want}) — section 6-a"
    return 1
  fi
  log "  preflight OK — both fingerprints match the pin"
  return 0
}

# --- the one server instance -------------------------------------------------
start_sweep_server() {  # start_sweep_server OUT_PREFIX
  local pre="$1"
  bash "${HARNESS}/server_ctl.sh" stop >> "$DRIVER_LOG" 2>&1
  sleep 2
  bash "${HARNESS}/server_ctl.sh" start "${pre}-identity.json" >> "$DRIVER_LOG" 2>&1
  local rc=$?
  if [ "$rc" -ne 0 ]; then
    log "  SERVER START/IDENTITY FAILED rc=${rc} (see ${pre}-identity.json)"
    return "$rc"
  fi
  SERVER_PID="$(pgrep -f "cub_server ${CUBRID_DB}" | head -1)"
  log "  server up pid=${SERVER_PID} (single instance for the whole sweep)"
  return 0
}

# Section 3-b + 3-a gate, recorded. rc 0 OK / 3 OFF_CPUSET / 4 BLOCKED / 5 FREE.
identity_gate() {  # identity_gate OUT_JSON LABEL
  bash "${HARNESS}/server_ctl.sh" identity "$1" >> "$DRIVER_LOG" 2>&1
  local rc=$?
  local ntid noff
  ntid="$(python3.11 -c "
import json,sys
try:
  d=json.load(open(sys.argv[1])); print((d.get('all_tid_affinity') or {}).get('n_tids'))
except Exception: print('?')" "$1" 2>/dev/null)"
  noff="$(python3.11 -c "
import json,sys
try:
  d=json.load(open(sys.argv[1])); print((d.get('all_tid_affinity') or {}).get('n_off_sut'))
except Exception: print('?')" "$1" 2>/dev/null)"
  log "  identity[$2] rc=${rc} tids=${ntid} off_sut=${noff}"
  return "$rc"
}

warm_param() {  # warm_param QNN KEY
  python3.11 -c "
import json,sys
d=json.load(open('${HARNESS}/warm_params.json'))
q=d['queries'].get(sys.argv[1], {})
print(q.get(sys.argv[2], d['defaults'][sys.argv[2]]))
" "$1" "$2"
}

log "=== Phase 1A FAST driver start pid=$$ campaign=${CAMPAIGN}"
log "    pin=${IMPL_SSOT_COMMIT} blob=${IMPL_SSOT_BLOB}  (AMEND-G)"
log "    prefix=${CUBRID_HOME} tmp=${CUBRID_TMP}"
log "    threshold=${THRESHOLD} core-s/s (section 3-a, explicit from the pin)"
log "    blocks/query=${BLOCKS}  queries=${QUERIES_TO_RUN[*]}"

preflight || { log "=== ABORT: preflight failed"; exit 2; }

# --- sweep start -------------------------------------------------------------
log "########## SWEEP START — starting the single campaign server ##########"
if ! start_sweep_server "${SWEEP}/sweep-start"; then
  log "=== ABORT: sweep server would not start (section 6-a-2: a memory failure is"
  log "    stop-and-report, NEVER a silent data_buffer_size reduction)"
  exit 3
fi
identity_gate "${SWEEP}/sweep-start-gate.json" "sweep-start"
case $? in
  0) : ;;
  *) log "=== ABORT: sweep-start ownership/affinity gate did not pass"; exit 4 ;;
esac

# --- the sweep ---------------------------------------------------------------
for QNN in "${QUERIES_TO_RUN[@]}"; do
  QDIR="${RAW_ROOT}/raw/${QNN}"
  W="${RAW_ROOT}/work/${QNN}"
  mkdir -p "$QDIR" "$W/sink"

  # ---- resumability: a completed query is never re-measured ----
  if [ -f "${QDIR}/QUERY-COMPLETE.json" ]; then
    log "########## ${QNN} — SKIPPED, already complete (resume) ##########"
    continue
  fi

  for qattempt in $(seq 1 "$QUERY_ATTEMPTS"); do
    log "########## ${QNN} — ${BLOCKS} blocks (query attempt ${qattempt}/${QUERY_ATTEMPTS}) ##########"

    # ---- query-boundary gate (section 3-c-1) ----
    # This is what replaces the per-block restart as the ownership/drift proof.
    # The TID pool is fully grown by now (~126-132 TIDs), so this sample is the
    # meaningful one; a check taken seconds after start sees only ~26-32 TIDs.
    identity_gate "${QDIR}/query-start-identity.json" "${QNN} query-start"
    grc=$?
    if [ "$grc" -eq 3 ]; then
      # Off-target TID. The whole QUERY is invalid, and only a fresh server can
      # rebind the pool (resources.cpp:190). Restart and retry the query.
      log "  ${QNN} OFF_CPUSET at query boundary — query INVALID, restarting server and re-running"
      python3.11 -c "
import json
json.dump({'campaign_id':'${CAMPAIGN}','qnn':'${QNN}','query_attempt':${qattempt},
           'valid':False,'invalid_reason':'OFF_CPUSET_TID_AT_QUERY_BOUNDARY',
           'note':'IMPL-SSOT section 3-c-1: a single off-target TID invalidates the '
                  'affected QUERY, not just the block, because without a per-block '
                  'restart the thread may have served earlier blocks undetected'},
          open('${QDIR}/QUERY-INVALID-attempt${qattempt}.json','w'), indent=2, sort_keys=True)"
      start_sweep_server "${SWEEP}/restart-${QNN}-attempt${qattempt}" || {
        log "=== ABORT: server would not restart after OFF_CPUSET"; exit 3; }
      continue
    elif [ "$grc" -ne 0 ]; then
      log "=== ABORT: ${QNN} query-boundary ownership gate rc=${grc} (3-b BLOCKED/FREE)"
      exit 4
    fi

    # ---- WARM once per query (section 3-c-1 step 2) ----
    WWIN="$(warm_param "$QNN" window)";        WTOL="$(warm_param "$QNN" level_tol)"
    WSPR="$(warm_param "$QNN" spread_sanity)"; WMAX="$(warm_param "$QNN" max_statements)"
    export TPCH_SSPQ_WARM_WINDOW="$WWIN" TPCH_SSPQ_WARM_LEVEL_TOL="$WTOL"
    export TPCH_SSPQ_WARM_SPREAD="$WSPR"  TPCH_SSPQ_WARM_MAX="$WMAX"
    export WARM_STATEMENTS="$WMAX" WARM_SESSIONS="$WMAX"
    log "  warm gate: window=${WWIN} level_tol=${WTOL} spread=${WSPR} max=${WMAX}"

    # A quiet SUT set before the warm run too: warming under a 16 core-s/s
    # neighbour spike converges to the wrong steady state and then every block
    # inherits it.
    python3.11 "${HARNESS}/wait_quiet.py" "$THRESHOLD" 6 2.0 "$MAX_WAIT_S" \
        >> "$DRIVER_LOG" 2>&1

    # Q15's repeated unit is the three-statement LOGICAL SESSION (create view /
    # select / drop view), not the statement — IMPL-SSOT section 3-c / 6-b, and
    # section 3-c-1 leaves that explicitly unchanged. warm_establish.py is
    # statement-scoped and has no Q15 mode, so pointing it at Q15 times the DDL
    # statements too: the first sweep measured "steady 0.003 s, spread 335899%"
    # and Q15's WARM gate could never converge, costing the query all six blocks.
    # q15_gated_block.sh already routes Q15 through q15_session.py for exactly
    # this reason; AMEND-G moved WARM out of the block without carrying that
    # branch across, so it is carried here.
    warm_ok=0
    for wtry in 1 2 3; do
      if [ "$QNN" = "Q15" ]; then
        WARM_SESSIONS="$WMAX" python3.11 "${HARNESS}/q15_session.py" warm cubrid "$WMAX" \
            > "$W/${QNN}-cubrid-warm-query-try${wtry}.log" 2>&1
        wrc=$?
        AFTER_KEY=converged_after_sessions
      else
        python3.11 "${HARNESS}/warm_establish.py" "$QNN" cubrid "$WMAX" - native \
            > "$W/${QNN}-cubrid-warm-query-try${wtry}.log" 2>&1
        wrc=$?
        AFTER_KEY=converged_after_statements
      fi
      cp -f "$W/${QNN}-cubrid-warm.json" "${QDIR}/${QNN}-warm-query-try${wtry}.json" 2>/dev/null
      wv="$(python3.11 -c "
import json,sys
d=json.load(open(sys.argv[1]))
print(('CONVERGED' if d['converged'] else 'NOT_CONVERGED'), d['verdict'],
      'after', d.get(sys.argv[2]), 'steady', d['steady_state_median_s'])
" "$W/${QNN}-cubrid-warm.json" "$AFTER_KEY" 2>/dev/null)"
      log "  WARM try ${wtry} rc=${wrc} ${wv}"
      if [ "$wrc" -eq 0 ]; then warm_ok=1; cp -f "$W/${QNN}-cubrid-warm.json" \
          "${QDIR}/${QNN}-warm.json" 2>/dev/null; break; fi
    done
    if [ "$warm_ok" -ne 1 ]; then
      log "  ${QNN} WARM NOT ESTABLISHED after 3 tries — query attempt failed"
      python3.11 -c "
import json
json.dump({'campaign_id':'${CAMPAIGN}','qnn':'${QNN}','query_attempt':${qattempt},
           'valid':False,'invalid_reason':'WARM_NOT_CONVERGED_AT_QUERY_LEVEL'},
          open('${QDIR}/QUERY-INVALID-attempt${qattempt}.json','w'), indent=2, sort_keys=True)"
      continue
    fi

    # ---- the blocks: NO restart between them ----
    accepted=0
    for b in $(seq 1 "$BLOCKS"); do
      BP="${QDIR}/block${b}"
      log "  --- ${QNN} block ${b}/${BLOCKS}"

      # Pre-block ownership/affinity record (section 3-b: before AND after every
      # block; unchanged by AMEND-G).
      identity_gate "${BP}-identity-pre.json" "${QNN} b${b} pre"
      irc=$?
      if [ "$irc" -ne 0 ]; then
        log "    block ${b} INVALID (pre-block gate rc=${irc})"
        python3.11 -c "
import json
json.dump({'campaign_id':'${CAMPAIGN}','qnn':'${QNN}','block':${b},'valid':False,
           'invalid_reason':'PRE_BLOCK_GATE_RC_${irc}'},
          open('${BP}-INVALID.json','w'), indent=2, sort_keys=True)"
        continue
      fi

      # The gated contract block. TPCH_SSPQ_SKIP_WARM=1 is the AMEND-G change:
      # the server has not been restarted since WARM was proved for this query,
      # so the engine cannot have left that state, and re-proving it per block is
      # exactly the cost this regime exists to remove. The 6.0 core-s/s gate,
      # the quiet pre-gate and the during-block load monitor are UNCHANGED and
      # still enforced per block.
      if [ "$QNN" = "Q15" ]; then
        TPCH_SSPQ_SKIP_WARM=1 bash "${HARNESS}/q15_gated_block.sh" cubrid \
            "$MAX_ATTEMPTS" "$MAX_WAIT_S" >> "$DRIVER_LOG" 2>&1
      else
        TPCH_SSPQ_SKIP_WARM=1 bash "${HARNESS}/measure_block.sh" "$QNN" cubrid \
            "$MAX_ATTEMPTS" "$MAX_WAIT_S" >> "$DRIVER_LOG" 2>&1
      fi
      brc=$?

      identity_gate "${BP}-identity-post.json" "${QNN} b${b} post"
      prc=$?

      if [ "$brc" -eq 0 ] && [ "$prc" -eq 0 ]; then
        cp -f "$W/${QNN}-cubrid-headline.json" "${BP}-headline.json"
        cp -f "${QDIR}/${QNN}-warm.json"       "${BP}-warm.json"
        cp -f "$W/${QNN}-cubrid-bgload.json"   "${BP}-bgload.json"
        cp -f "$W/sink/${QNN}-cubrid-headline.out" "${BP}-headline.out"
        rm -f "${BP}-INVALID.json"
        accepted=$((accepted + 1))
        log "    block ${b} ACCEPTED"
      else
        reason="MEASURE_BLOCK_REJECTED"
        [ "$prc" -eq 3 ] && reason="OFF_CPUSET_TID_AFTER_BLOCK"
        [ "$prc" -eq 4 ] && reason="SERVER_NOT_CAMPAIGN_OWNED_AFTER_BLOCK"
        python3.11 -c "
import json
json.dump({'campaign_id':'${CAMPAIGN}','qnn':'${QNN}','block':${b},'valid':False,
           'invalid_reason':'${reason}','measure_block_rc':${brc},
           'post_identity_rc':${prc}},
          open('${BP}-INVALID.json','w'), indent=2, sort_keys=True)"
        log "    block ${b} INVALID reason=${reason} brc=${brc} prc=${prc}"
        cp -f "$W"/${QNN}-cubrid-*attempt*.json "$QDIR/" 2>/dev/null
        if [ "$prc" -eq 3 ]; then
          # An off-target TID after a block condemns the whole query (3-c-1).
          log "  ${QNN} OFF_CPUSET after block ${b} — abandoning query attempt, restarting server"
          start_sweep_server "${SWEEP}/restart-${QNN}-b${b}" || {
            log "=== ABORT: server would not restart after OFF_CPUSET"; exit 3; }
          accepted=-1
          break
        fi
      fi
    done

    if [ "$accepted" -lt 0 ]; then
      log "  ${QNN} query attempt ${qattempt} abandoned (OFF_CPUSET) — retrying query"
      continue
    fi
    if [ "$accepted" -eq 0 ]; then
      log "  ${QNN} query attempt ${qattempt} produced ZERO accepted blocks — retrying query"
      continue
    fi

    # ---- per-query canonical capture (unchanged, section 3-c-1 step 4) ----
    log "  --- ${QNN} reference capture (correctness reference + plan + perf)"
    python3.11 "${HARNESS}/reference_capture.py" "$QNN" >> "$DRIVER_LOG" 2>&1
    rcrc=$?
    log "  --- ${QNN} reference capture rc=${rcrc}"

    # ---- query-end boundary gate ----
    identity_gate "${QDIR}/query-end-identity.json" "${QNN} query-end"
    erc=$?

    # ---- durable completion marker: the resumability contract ----
    python3.11 -c "
import json, os, sys, time
sys.path.insert(0, '${HARNESS}')
import campaign_config as cfg
qd = '${QDIR}'
ident = {}
p = os.path.join(qd, 'query-end-identity.json')
if os.path.exists(p):
    d = json.load(open(p))
    s = d.get('cub_server') or {}
    ident = {'pid': s.get('pid'), 'start_time_utc': s.get('start_time_utc'),
             'classification': d.get('classification'),
             'n_tids': (d.get('all_tid_affinity') or {}).get('n_tids'),
             'n_off_sut': (d.get('all_tid_affinity') or {}).get('n_off_sut')}
json.dump({
    'campaign_id': cfg.CAMPAIGN, 'qnn': '${QNN}',
    'regime': 'AMEND-G fast Phase 1A: one continuous cub_server instance, '
              'no per-block restart, WARM established once per query',
    'impl_ssot_commit': cfg.IMPL_SSOT_COMMIT,
    'impl_ssot_blob': cfg.IMPL_SSOT_BLOB,
    'blocks_accepted': ${accepted}, 'blocks_requested': ${BLOCKS},
    'query_attempt': ${qattempt},
    'reference_capture_rc': ${rcrc},
    'query_end_gate_rc': ${erc},
    'server_at_completion': ident,
    'completed_utc': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
}, open(os.path.join(qd, 'QUERY-COMPLETE.json'), 'w'), indent=2, sort_keys=True)"
    log "########## ${QNN} COMPLETE — ${accepted}/${BLOCKS} blocks accepted ##########"
    break
  done
done

# --- sweep end ---------------------------------------------------------------
log "########## SWEEP END ##########"
identity_gate "${SWEEP}/sweep-end-gate.json" "sweep-end"
log "=== stopping the campaign server (once, at sweep end)"
bash "${HARNESS}/server_ctl.sh" stop >> "$DRIVER_LOG" 2>&1
log "=== Phase 1A FAST driver COMPLETE pid=$$"
touch "${STATE}/PHASE1A-FAST-DRIVER-DONE"
