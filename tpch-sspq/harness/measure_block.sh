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
# A controlled-plan variant (SSOT section 16 F_plan anchor) is measured through the
# SAME gate as the native block, with SQL_FILE/VARIANT_TAG passed down to
# warm_establish.py and headline_run.py. Variant artifacts are tagged
# <engine>-<variant> so they can never overwrite the native block. For PostgreSQL a
# variant is expressed through PGOPTIONS in the environment, so pass SQL_FILE as "-".
#
# Usage: measure_block.sh QNN cubrid|postgresql [MAX_ATTEMPTS] [MAX_WAIT_S] [SQL_FILE|-] [VARIANT_TAG]
set -uo pipefail

QNN="${1:?usage: measure_block.sh QNN cubrid|postgresql [MAX_ATTEMPTS] [MAX_WAIT_S] [SQL_FILE|-] [VARIANT_TAG]}"
ENGINE="${2:?}"
MAX_ATTEMPTS="${3:-6}"
MAX_WAIT_S="${4:-1800}"
SQL_OVERRIDE="${5:--}"
VARIANT="${6:-native}"
if [ "$VARIANT" = native ]; then LABEL="$ENGINE"; else LABEL="${ENGINE}-${VARIANT}"; fi
THRESHOLD=1.5
QUIET_N=6          # consecutive quiet samples required before starting
QUIET_INTERVAL=2.0 # seconds per gate sample

CAMPAIGN=tpch-sspq-fk-r1-20260730
RAW_ROOT="/data/tpch-sspq/${CAMPAIGN}"
W="${RAW_ROOT}/work/${QNN}"
HARNESS=/home/cubrid/dev/workspace/tpch-sspq/harness
mkdir -p "$W/sink"

# Stale-canonical-file guard. When every attempt is rejected this script exits
# non-zero but used to leave the PREVIOUS run's canonical artifacts in place, so a
# caller that copies "$W/${QNN}-${LABEL}-headline.json" into a per-block name after
# a failed invocation silently records the earlier block a second time. That
# happened on Q05: two "new" CUBRID blocks were byte-identical copies of an
# already-invalidated block. Remove the canonical names up front so a rejected run
# leaves nothing to copy and the mistake becomes a missing file instead of a
# duplicated measurement.
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

  # SSOT section 12: "WARM is proved, not assumed" / "a failed WARM gate ...
  # restarts at warmup". Drive the engine to its own steady state first, in a
  # separate uncounted connection, so the contract block below is not timed on a
  # decay curve or on residency inherited from the previous stage. Nothing this
  # produces is ever a headline value. Q04 is the first query that needed it:
  # PostgreSQL was still 2.1% above steady state at the third measured statement
  # and CUBRID's level moved 4.2% with the preceding workload.
  python3.11 "${HARNESS}/warm_establish.py" "$QNN" "$ENGINE" "${WARM_STATEMENTS:-20}" "$SQL_OVERRIDE" "$VARIANT" \
      > "$W/${QNN}-${LABEL}-warm-attempt${attempt}.log" 2>&1
  wrc=$?
  cp -f "$W/${QNN}-${LABEL}-warm.json" "$W/${QNN}-${LABEL}-warm-attempt${attempt}.json" 2>/dev/null
  wverdict="$(python3.11 -c "import json,sys;d=json.load(open(sys.argv[1]));print(('CONVERGED' if d['converged'] else 'NOT_CONVERGED'), d['verdict'], 'after', d['converged_after_statements'], 'steady', d['steady_state_median_s'])" "$W/${QNN}-${LABEL}-warm.json" 2>/dev/null)"
  echo "  warm_establish rc=${wrc} ${wverdict}"
  if [ "$wrc" -ne 0 ]; then
    # Not a hard stop: WARM is a state the engine can be driven into, and the
    # next attempt starts from the state this one already left behind. Retry
    # like a rejected load gate, and keep the failed trace as evidence.
    echo "${QNN} ${LABEL}: attempt ${attempt} WARM NOT ESTABLISHED (rc=${wrc}); block not timed — retrying"
    continue
  fi

  LOAD="$W/${QNN}-${LABEL}-bgload-attempt${attempt}.json"
  nohup python3.11 "${HARNESS}/bgload_monitor.py" "$LOAD" 0.25 "$THRESHOLD" \
      > "$W/${QNN}-${LABEL}-bgload-attempt${attempt}.log" 2>&1 &
  MON=$!
  sleep 0.5

  python3.11 "${HARNESS}/headline_run.py" "$QNN" "$ENGINE" "$SQL_OVERRIDE" "$VARIANT" \
      > "$W/${QNN}-${LABEL}-headline-attempt${attempt}.log" 2>&1
  hrc=$?

  kill -TERM "$MON" 2>/dev/null
  wait "$MON" 2>/dev/null
  sleep 0.3

  cp -f "$W/${QNN}-${LABEL}-headline.json" "$W/${QNN}-${LABEL}-headline-attempt${attempt}.json" 2>/dev/null
  cp -f "$W/sink/${QNN}-${LABEL}-headline.out" "$W/sink/${QNN}-${LABEL}-headline-attempt${attempt}.out" 2>/dev/null

  verdict="$(python3.11 -c "import json,sys;print(json.load(open(sys.argv[1]))['verdict'])" "$LOAD" 2>/dev/null)"
  extmax="$(python3.11 -c "import json,sys;print(json.load(open(sys.argv[1]))['external_max'])" "$LOAD" 2>/dev/null)"
  extmean="$(python3.11 -c "import json,sys;print(json.load(open(sys.argv[1]))['external_mean'])" "$LOAD" 2>/dev/null)"
  echo "  headline_rc=${hrc} load_verdict=${verdict} external_mean=${extmean} external_max=${extmax}"
  python3.11 -c "
import json,sys
d=json.load(open(sys.argv[1]))
print('  times:', d.get('statement_times_all'), 'median=', d.get('median_s'))
" "$W/${QNN}-${LABEL}-headline.json" 2>/dev/null

  if [ "$hrc" -eq 0 ] && [ "$verdict" = "CLEAN" ]; then
    cp -f "$LOAD" "$W/${QNN}-${LABEL}-bgload.json"
    echo "${QNN} ${LABEL}: block ACCEPTED on attempt ${attempt} (load CLEAN, external_max=${extmax})"
    exit 0
  fi
  echo "${QNN} ${LABEL}: attempt ${attempt} REJECTED (headline_rc=${hrc}, ${verdict}) — retrying"
  python3.11 - "$W" "$QNN" "$LABEL" "$attempt" "$verdict" "$extmax" <<'PY'
import json, sys
w, qnn, eng, att, verdict, extmax = sys.argv[1:7]
json.dump({"campaign_id": "tpch-sspq-fk-r1-20260730", "qnn": qnn, "engine": eng,
           "attempt": int(att), "valid": False, "invalid_reason": verdict,
           "external_max_core_s_per_s": extmax,
           "note": "SSOT section 9: external SUT-set load crossed 1.5 core-s/s during the block"},
          open(f"{w}/{qnn}-{eng}-headline-attempt{att}-INVALID.json", "w"), indent=2, sort_keys=True)
PY
done

echo "${QNN} ${LABEL}: all ${MAX_ATTEMPTS} attempts rejected"
exit 1
