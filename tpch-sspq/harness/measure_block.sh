#!/usr/bin/env bash
# TPCH-SSPQ FK campaign (tpch-sspq-fk-r1-20260730) — gated measurement block runner.
#
# SSOT section 9: "If external CPU on the SUT set is above 1.5 core-seconds per second
# before a run, wait. If it crosses the threshold during a run, mark
# INVALID_BACKGROUND_LOAD." This wrapper enforces both halves around one engine
# headline block:
#
#   1. wait for a quiet window (external <= threshold for QUIET_N consecutive samples);
#   2. start harness/bgload_monitor.py on the collector CPUs;
#   3. run harness/headline_run.py for the block (untouched, still the only timer);
#   4. stop the monitor and read its verdict;
#   5. CLEAN -> promote the attempt to the canonical artifact names and stop.
#      INVALID_BACKGROUND_LOAD -> keep the attempt as invalid evidence and retry.
#
# Every attempt is preserved (headline JSON, sink, load trace) so that discarded
# blocks remain auditable instead of vanishing.
#
# Usage: measure_block.sh QNN cubrid|postgresql [MAX_ATTEMPTS] [MAX_WAIT_S]
set -uo pipefail

QNN="${1:?usage: measure_block.sh QNN cubrid|postgresql [MAX_ATTEMPTS] [MAX_WAIT_S]}"
ENGINE="${2:?}"
MAX_ATTEMPTS="${3:-6}"
MAX_WAIT_S="${4:-1800}"
THRESHOLD=1.5
QUIET_N=6          # consecutive quiet samples required before starting
QUIET_INTERVAL=2.0 # seconds per gate sample

CAMPAIGN=tpch-sspq-fk-r1-20260730
RAW_ROOT="/data/tpch-sspq/${CAMPAIGN}"
W="${RAW_ROOT}/work/${QNN}"
HARNESS=/home/cubrid/dev/workspace/tpch-sspq/harness
mkdir -p "$W/sink"

for attempt in $(seq 1 "$MAX_ATTEMPTS"); do
  echo "=== ${QNN} ${ENGINE} attempt ${attempt}/${MAX_ATTEMPTS} — waiting for quiet SUT set"
  python3.11 "${HARNESS}/wait_quiet.py" "$THRESHOLD" "$QUIET_N" "$QUIET_INTERVAL" "$MAX_WAIT_S"
  gate_rc=$?
  if [ "$gate_rc" -ne 0 ]; then
    echo "${QNN} ${ENGINE}: gate did not pass (rc=${gate_rc}); no measurement started"
    exit "$gate_rc"
  fi

  LOAD="$W/${QNN}-${ENGINE}-bgload-attempt${attempt}.json"
  nohup python3.11 "${HARNESS}/bgload_monitor.py" "$LOAD" 0.25 "$THRESHOLD" \
      > "$W/${QNN}-${ENGINE}-bgload-attempt${attempt}.log" 2>&1 &
  MON=$!
  sleep 0.5

  python3.11 "${HARNESS}/headline_run.py" "$QNN" "$ENGINE" \
      > "$W/${QNN}-${ENGINE}-headline-attempt${attempt}.log" 2>&1
  hrc=$?

  kill -TERM "$MON" 2>/dev/null
  wait "$MON" 2>/dev/null
  sleep 0.3

  cp -f "$W/${QNN}-${ENGINE}-headline.json" "$W/${QNN}-${ENGINE}-headline-attempt${attempt}.json" 2>/dev/null
  cp -f "$W/sink/${QNN}-${ENGINE}-headline.out" "$W/sink/${QNN}-${ENGINE}-headline-attempt${attempt}.out" 2>/dev/null

  verdict="$(python3.11 -c "import json,sys;print(json.load(open(sys.argv[1]))['verdict'])" "$LOAD" 2>/dev/null)"
  extmax="$(python3.11 -c "import json,sys;print(json.load(open(sys.argv[1]))['external_max'])" "$LOAD" 2>/dev/null)"
  extmean="$(python3.11 -c "import json,sys;print(json.load(open(sys.argv[1]))['external_mean'])" "$LOAD" 2>/dev/null)"
  echo "  headline_rc=${hrc} load_verdict=${verdict} external_mean=${extmean} external_max=${extmax}"
  python3.11 -c "
import json,sys
d=json.load(open(sys.argv[1]))
print('  times:', d.get('statement_times_all'), 'median=', d.get('median_s'))
" "$W/${QNN}-${ENGINE}-headline.json" 2>/dev/null

  if [ "$hrc" -eq 0 ] && [ "$verdict" = "CLEAN" ]; then
    cp -f "$LOAD" "$W/${QNN}-${ENGINE}-bgload.json"
    echo "${QNN} ${ENGINE}: block ACCEPTED on attempt ${attempt} (load CLEAN, external_max=${extmax})"
    exit 0
  fi
  echo "${QNN} ${ENGINE}: attempt ${attempt} REJECTED (headline_rc=${hrc}, ${verdict}) — retrying"
  python3.11 - "$W" "$QNN" "$ENGINE" "$attempt" "$verdict" "$extmax" <<'PY'
import json, sys
w, qnn, eng, att, verdict, extmax = sys.argv[1:7]
json.dump({"campaign_id": "tpch-sspq-fk-r1-20260730", "qnn": qnn, "engine": eng,
           "attempt": int(att), "valid": False, "invalid_reason": verdict,
           "external_max_core_s_per_s": extmax,
           "note": "SSOT section 9: external SUT-set load crossed 1.5 core-s/s during the block"},
          open(f"{w}/{qnn}-{eng}-headline-attempt{att}-INVALID.json", "w"), indent=2, sort_keys=True)
PY
done

echo "${QNN} ${ENGINE}: all ${MAX_ATTEMPTS} attempts rejected"
exit 1
