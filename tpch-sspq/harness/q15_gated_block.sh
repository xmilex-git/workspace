#!/usr/bin/env bash
# TPCH-SSPQ FK campaign (tpch-sspq-fk-r1-20260730) — Q15 gated measurement block.
#
# Identical gate policy to measure_block.sh (SSOT section 9 quiet-window pre-gate,
# bgload_monitor.py during the block, CLEAN/INVALID_BACKGROUND_LOAD verdict, every
# attempt preserved, canonical names removed up front so a rejected run leaves
# nothing to copy). The only difference is the unit: Q15's repeated unit is the
# three-statement logical session (SSOT section 6), so warm establishment and the
# headline block both go through harness/q15_session.py instead of
# warm_establish.py + headline_run.py.
#
# Usage: q15_gated_block.sh cubrid|postgresql [MAX_ATTEMPTS] [MAX_WAIT_S]
set -uo pipefail

ENGINE="${1:?usage: q15_gated_block.sh cubrid|postgresql [MAX_ATTEMPTS] [MAX_WAIT_S]}"
MAX_ATTEMPTS="${2:-6}"
MAX_WAIT_S="${3:-1800}"
QNN=Q15
# A controlled variant (TPCH_SSPQ_Q15_VARIANT + TPCH_SSPQ_Q15_CREATE_FILE or
# PGOPTIONS) is measured through this SAME gate as the native block, and every
# artifact carries the variant tag so it can never overwrite the native block.
VARIANT="${TPCH_SSPQ_Q15_VARIANT:-native}"
if [ "$VARIANT" = native ]; then LABEL="$ENGINE"; else LABEL="${ENGINE}-${VARIANT}"; fi
THRESHOLD=6.0
QUIET_N="${TPCH_SSPQ_QUIET_N:-6}"
QUIET_INTERVAL="${TPCH_SSPQ_QUIET_INTERVAL:-2.0}"
# Q15 gate parameters are measured, see work/Q15/q15-warm-gate-params.txt.
export TPCH_SSPQ_WARM_WINDOW="${TPCH_SSPQ_WARM_WINDOW:-6}"
WARM_SESSIONS="${WARM_SESSIONS:-20}"

CAMPAIGN=tpch-sspq-fk-r1-20260730
RAW_ROOT="/data/tpch-sspq/${CAMPAIGN}"
W="${RAW_ROOT}/work/${QNN}"
HARNESS=/home/cubrid/dev/workspace/tpch-sspq/harness
mkdir -p "$W/sink"

rm -f "$W/${QNN}-${LABEL}-headline.json" "$W/${QNN}-${LABEL}-warm.json" \
      "$W/${QNN}-${LABEL}-bgload.json" "$W/sink/${QNN}-${LABEL}-headline.out"

for attempt in $(seq 1 "$MAX_ATTEMPTS"); do
  echo "=== ${QNN} ${LABEL} attempt ${attempt}/${MAX_ATTEMPTS} — waiting for quiet SUT set"
  python3.11 "${HARNESS}/wait_quiet.py" "$THRESHOLD" "$QUIET_N" "$QUIET_INTERVAL" "$MAX_WAIT_S"
  gate_rc=$?
  if [ "$gate_rc" -ne 0 ]; then
    echo "${QNN} ${LABEL}: gate did not pass (rc=${gate_rc}); no measurement started"
    exit "$gate_rc"
  fi

  python3.11 "${HARNESS}/q15_session.py" warm "$ENGINE" "$WARM_SESSIONS" \
      > "$W/${QNN}-${LABEL}-warm-attempt${attempt}.log" 2>&1
  wrc=$?
  cp -f "$W/${QNN}-${LABEL}-warm.json" "$W/${QNN}-${LABEL}-warm-attempt${attempt}.json" 2>/dev/null
  python3.11 -c "
import json,sys
d=json.load(open(sys.argv[1]))
print('  warm:', 'CONVERGED' if d['converged'] else 'NOT_CONVERGED', '|', d['verdict'])
print('  warm steady median=', d['steady_state_median_s'], 'after', d['converged_after_sessions'], 'sessions')
" "$W/${QNN}-${LABEL}-warm.json" 2>/dev/null
  echo "  warm rc=${wrc}"
  if [ "$wrc" -ne 0 ]; then
    echo "${QNN} ${LABEL}: attempt ${attempt} WARM NOT ESTABLISHED (rc=${wrc}); block not timed — retrying"
    continue
  fi

  LOAD="$W/${QNN}-${LABEL}-bgload-attempt${attempt}.json"
  nohup python3.11 "${HARNESS}/bgload_monitor.py" "$LOAD" 0.25 "$THRESHOLD" \
      > "$W/${QNN}-${LABEL}-bgload-attempt${attempt}.log" 2>&1 &
  MON=$!
  sleep 0.5

  python3.11 "${HARNESS}/q15_session.py" headline "$ENGINE" \
      > "$W/${QNN}-${LABEL}-headline-attempt${attempt}.log" 2>&1
  hrc=$?

  kill -TERM "$MON" 2>/dev/null
  wait "$MON" 2>/dev/null
  sleep 0.3

  cp -f "$W/${QNN}-${LABEL}-headline.json" "$W/${QNN}-${LABEL}-headline-attempt${attempt}.json" 2>/dev/null
  cp -f "$W/sink/${QNN}-${LABEL}-headline.out" "$W/sink/${QNN}-${LABEL}-headline-attempt${attempt}.out" 2>/dev/null

  VFIELD="${TPCH_SSPQ_LOAD_VERDICT:-verdict}"
  verdict="$(python3.11 -c "import json,sys;print(json.load(open(sys.argv[1]))[sys.argv[2]])" "$LOAD" "$VFIELD" 2>/dev/null)"
  strict="$(python3.11 -c "import json,sys;print(json.load(open(sys.argv[1]))['verdict'])" "$LOAD" 2>/dev/null)"
  extmax="$(python3.11 -c "import json,sys;print(json.load(open(sys.argv[1]))['external_max'])" "$LOAD" 2>/dev/null)"
  extmaxc="$(python3.11 -c "import json,sys;print(json.load(open(sys.argv[1]))['external_max_contract_window'])" "$LOAD" 2>/dev/null)"
  extmean="$(python3.11 -c "import json,sys;print(json.load(open(sys.argv[1]))['external_mean'])" "$LOAD" 2>/dev/null)"
  echo "  headline_rc=${hrc} gate_field=${VFIELD} load_verdict=${verdict} strict_verdict=${strict} external_mean=${extmean} external_max=${extmax} external_max_1s=${extmaxc}"
  python3.11 -c "
import json,sys
d=json.load(open(sys.argv[1]))
print('  session totals:', d.get('session_totals_s'), '-> measured', d.get('measured_session_totals_s'),
      'median=', d.get('median_s'))
print('  select only   :', d.get('select_only',{}).get('median_s'), ' view_state:', d.get('view_state'))
" "$W/${QNN}-${LABEL}-headline.json" 2>/dev/null

  if [ "$hrc" -eq 0 ] && [ "$verdict" = "CLEAN" ]; then
    cp -f "$LOAD" "$W/${QNN}-${LABEL}-bgload.json"
    echo "${QNN} ${LABEL}: block ACCEPTED on attempt ${attempt} (gate ${VFIELD} CLEAN, strict=${strict}, external_max=${extmax}, external_max_1s=${extmaxc})"
    exit 0
  fi
  echo "${QNN} ${LABEL}: attempt ${attempt} REJECTED (headline_rc=${hrc}, ${verdict}) — retrying"
  python3.11 - "$W" "$QNN" "$LABEL" "$attempt" "$verdict" "$extmax" "$VFIELD" "$strict" "$extmaxc" <<'PY'
import json, sys
w, qnn, eng, att, verdict, extmax, vfield, strict, extmaxc = sys.argv[1:10]
json.dump({"campaign_id": "tpch-sspq-fk-r1-20260730", "qnn": qnn, "engine": eng,
           "attempt": int(att), "valid": False, "invalid_reason": verdict,
           "gate_field": vfield,
           "strict_per_sample_verdict": strict,
           "external_max_core_s_per_s": extmax,
           "external_max_contract_window_core_s_per_s": extmaxc,
           "note": "SSOT section 9: external SUT-set load crossed 6.0 core-s/s during the block"},
          open(f"{w}/{qnn}-{eng}-headline-attempt{att}-INVALID.json", "w"), indent=2, sort_keys=True)
PY
done

echo "${QNN} ${LABEL}: all ${MAX_ATTEMPTS} attempts rejected"
exit 1
