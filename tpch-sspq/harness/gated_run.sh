#!/usr/bin/env bash
# TPCH-SSPQ FK campaign (tpch-sspq-fk-r1-20260730) — load-gated non-headline stage runner.
#
# Same SSOT section 9 gate as harness/measure_block.sh, for the diagnostic stages whose
# numbers still depend on CPU contention (stage 14.7 telemetry, stage 14.8 perf): wait
# for a quiet SUT set, monitor external load for the whole stage, and report the verdict
# so a contaminated diagnostic run can be discarded instead of quietly averaged in.
#
# Usage: gated_run.sh QNN LABEL MAX_ATTEMPTS -- COMMAND [ARGS...]
set -uo pipefail

QNN="${1:?usage: gated_run.sh QNN LABEL MAX_ATTEMPTS -- COMMAND [ARGS...]}"
LABEL="${2:?}"
MAX_ATTEMPTS="${3:-3}"
shift 3
[ "${1:-}" = "--" ] && shift

CAMPAIGN=tpch-sspq-fk-r1-20260730
W="/data/tpch-sspq/${CAMPAIGN}/work/${QNN}"
HARNESS=/home/cubrid/dev/workspace/tpch-sspq/harness
THRESHOLD=6.0
mkdir -p "$W"

for attempt in $(seq 1 "$MAX_ATTEMPTS"); do
  echo "=== ${QNN} ${LABEL} attempt ${attempt}/${MAX_ATTEMPTS}"
  python3.11 "${HARNESS}/wait_quiet.py" "$THRESHOLD" 6 2.0 1800
  if [ $? -ne 0 ]; then
    echo "${LABEL}: gate did not pass; stage not started"
    exit 3
  fi

  LOAD="$W/${LABEL}-bgload.json"
  nohup python3.11 "${HARNESS}/bgload_monitor.py" "$LOAD" 0.25 "$THRESHOLD" \
      > "$W/${LABEL}-bgload.log" 2>&1 &
  MON=$!
  sleep 0.5

  "$@"
  rc=$?

  kill -TERM "$MON" 2>/dev/null
  wait "$MON" 2>/dev/null
  sleep 0.3

  # SSOT section 9 threshold, evaluated on the field the caller selects:
  # `verdict` (strict per-sample, the Q01-Q06 rule and the default) or
  # `verdict_contract_window` (the same 1.5 core-s/s on the contract's own
  # per-second unit). Both are always recorded in the load JSON.
  VFIELD="${TPCH_SSPQ_LOAD_VERDICT:-verdict}"
  verdict="$(python3.11 -c "import json,sys;print(json.load(open(sys.argv[1]))[sys.argv[2]])" "$LOAD" "$VFIELD" 2>/dev/null)"
  strict="$(python3.11 -c "import json,sys;print(json.load(open(sys.argv[1]))['verdict'])" "$LOAD" 2>/dev/null)"
  extmax="$(python3.11 -c "import json,sys;print(json.load(open(sys.argv[1]))['external_max'])" "$LOAD" 2>/dev/null)"
  extmaxc="$(python3.11 -c "import json,sys;print(json.load(open(sys.argv[1]))['external_max_contract_window'])" "$LOAD" 2>/dev/null)"
  echo "  ${LABEL}: rc=${rc} gate_field=${VFIELD} load_verdict=${verdict} strict_verdict=${strict} external_max=${extmax} external_max_1s=${extmaxc}"

  if [ "$rc" -eq 0 ] && [ "$verdict" = "CLEAN" ]; then
    echo "${LABEL}: ACCEPTED on attempt ${attempt}"
    exit 0
  fi
  cp -f "$LOAD" "$W/${LABEL}-bgload-attempt${attempt}-REJECTED.json" 2>/dev/null
  echo "${LABEL}: attempt ${attempt} REJECTED (rc=${rc}, ${verdict}) — retrying"
done

echo "${LABEL}: all ${MAX_ATTEMPTS} attempts rejected"
exit 1
