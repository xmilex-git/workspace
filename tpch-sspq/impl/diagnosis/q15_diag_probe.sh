#!/usr/bin/env bash
# Q15 parallel non-arming diagnosis probe — handoff task 2, READ-ONLY.
#
# LABEL: attribution/diagnostic evidence, NOT A/B evidence.
#   - No source modification, no rebuild, no gdb: preserved install/IMP-015 only.
#   - IMPL-SSOT section 6-c block discipline (B->P->P->B, 3 measured runs) and the
#     quiet-gate blocking are NOT applied; bgload is recorded only.
#   - No number here may be cited as a performance A/B result.
#
# HYPOTHESIS UNDER TEST
# ---------------------
# The main group-by fallback sort never arms because sort_check_parallelism()
# returns at external_sort.c:5232 (`if (px == NULL || px->hash_eligible) return 1;`)
# — i.e. `gby_px.hash_eligible` is 1 at query_executor.c:5682 (IMP-015) — because in
# the parallel-heap-scan mergeable-list gather path the LEADER's
# agg_hash_context->state is still its initial HS_ACCEPT_ALL (query_executor.c:27911),
# while the trace's `hash: partial` label is FORCED unconditionally at
# px_scan_result_handler.cpp:635.  The trace label and the gate input are different
# fields and they disagree in exactly this path.
#
# FALSIFIABLE PREDICTIONS
#   Leg A  Q15 view body, parallel scan (default)  -> trace `hash: partial`, GROUPBY SERIAL
#   Leg B  Q15 view body, /*+ NO_PARALLEL_SCAN */  -> trace `hash: true`   (label differs on
#          identical SQL/data/binary => the parallel-path label is not the leader state)
#   Leg C  high-selectivity group-by, parallel scan     -> `hash: partial`, GROUPBY SERIAL
#   Leg D  same SQL, /*+ NO_PARALLEL_SCAN */            -> `hash: partial`, GROUPBY PARALLEL
#   C vs D is the decisive pair: identical SQL except the scan hint, identical binary
#   and data, both labelled `hash: partial`, opposite group-by-sort arming.  That
#   isolates the cause to the leader's runtime agg_hash_context->state and therefore
#   to external_sort.c:5232, and it excludes the size gate (5237-5243), the
#   px->parallelism hint (5238-5239) and try_reserve_workers (5244), all of which sit
#   DOWNSTREAM of the 5232 return and are identical across C and D.
#
# Usage: q15_diag_probe.sh preflight|start|legs|q15full|stop
set -uo pipefail

HARNESS=/home/cubrid/dev/tpch-sspq-impl-r1/harness
OUT=/data/tpch-sspq/tpch-sspq-impl-r1-20260803/work/BASELINE/q15-diagnosis
QUERIES=/home/cubrid/dev/workspace/tpch-sspq/queries

export TPCH_SSPQ_IMPL_VARIANT=IMP-015     # the binary the observation was made on
. "${HARNESS}/campaign_env.sh"            # asserts CUBRID_TMP + pinned cubrid.conf sha256

mkdir -p "$OUT"
cd "$OUT" || exit 1                       # keep csql.err out of the harness dir
STAGE="${1:?usage: q15_diag_probe.sh preflight|start|legs|q15full|stop}"
stamp() { date -u +%Y%m%dT%H%M%SZ; }
srv_pid() { pgrep -f "cub_server ${CUBRID_DB}" | head -1; }

csql_run() {   # csql_run <sql-file> <out-file>
  taskset -c "$SUT_CPUS" "${CUBRID_HOME}/bin/csql" -C -u dba "${CUBRID_DB}" \
      --no-pager -i "$1" > "$2" 2>&1
}

# 3-month window identical to the Q15 view body (queries/q15_create_view-cubrid.sql).
WINDOW="l_shipdate >= date '1996-01-01' and l_shipdate < DATE_ADD(DATE '1996-01-01', INTERVAL 3 MONTH)"

emit_leg_sql() {  # emit_leg_sql <hint> <group-by-shape: low|high> <file>
  local hint="$2" shape="$3" f="$4"
  {
    printf 'SET TRACE ON;\n'
    if [ "$shape" = "low" ]; then
      # Q15's own grouping: 2.27M rows -> 100k groups, selectivity ~0.044 < 0.5,
      # so a LEADER-side hash pass never trips the abort at query_executor.c:4842.
      printf 'select count(*) from (select %s l_suppkey, sum(l_extendedprice * (1 - l_discount))\n' "$hint"
      printf '  from lineitem where %s group by l_suppkey) t;\n' "$WINDOW"
    else
      # Unique grouping: selectivity 1.0 > HASH_AGGREGATE_VH_SELECTIVITY_THRESHOLD (0.5)
      # with tuple_count > 2000, so a LEADER-side hash pass DOES abort to HS_REJECT_ALL
      # at query_executor.c:4845.
      printf 'select count(*) from (select %s l_orderkey, l_linenumber, sum(l_extendedprice * (1 - l_discount))\n' "$hint"
      printf '  from lineitem where %s group by l_orderkey, l_linenumber) t;\n' "$WINDOW"
    fi
    printf 'SHOW TRACE;\n'
  } > "$f"
}

case "$STAGE" in

preflight)
  {
    echo "stage=preflight ts=$(stamp)"
    echo "CUBRID_HOME=$CUBRID_HOME"
    echo "CUBRID_DB=$CUBRID_DB port=$CUBRID_PORT"
    echo "CUBRID_TMP=$CUBRID_TMP"
    echo "conf_sha256=$(sha256sum "${CUBRID_HOME}/conf/cubrid.conf" | cut -d' ' -f1) (pinned $CONF_SHA256)"
    echo "cub_server_sha256=$(sha256sum "${CUBRID_HOME}/bin/cub_server" | cut -d' ' -f1)"
    echo "cub_server_buildid=$(readelf -n "${CUBRID_HOME}/bin/cub_server" 2>/dev/null | awk '/Build ID/{print $3}')"
    echo "SUT_CPUS=$SUT_CPUS MEMBIND=$MEMBIND_NODE THRESHOLD=$THRESHOLD(recorded only)"
    echo "impl_ssot_commit=$IMPL_SSOT_COMMIT blob=$IMPL_SSOT_BLOB"
    echo "--- pre-existing cub_master (section 3-b evidence) ---"
    for p in $(pgrep -x cub_master); do
      echo "master_pid=$p exe=$(readlink -f "/proc/$p/exe" 2>/dev/null) start=$(ps -o lstart= -p "$p" 2>/dev/null | tr -s ' ')"
      tr '\0' '\n' < "/proc/$p/environ" 2>/dev/null | grep -E '^CUBRID(_TMP)?=' | sed 's/^/  env /'
    done
  } > "${OUT}/preflight.txt" 2>&1
  bash "${HARNESS}/server_ctl.sh" identity "${OUT}/identity-before.json" \
      > "${OUT}/identity-before.txt" 2>&1
  cat "${OUT}/preflight.txt"
  echo "--- identity-before (tail)"; tail -6 "${OUT}/identity-before.txt"
  ;;

start)
  bash "${HARNESS}/server_ctl.sh" start "${OUT}/identity-after-start.json" \
      > "${OUT}/server-start.txt" 2>&1
  rc=$?
  echo "start rc=$rc"; tail -14 "${OUT}/server-start.txt"
  [ "$rc" -eq 0 ] || exit "$rc"
  timeout 70 python3.11 "${HARNESS}/bgload_monitor.py" "${OUT}/bgload-start.json" 0.25 \
      > "${OUT}/bgload-start.txt" 2>&1 || true
  echo "--- bgload (recorded only)"; tail -3 "${OUT}/bgload-start.txt"
  ;;

legs)
  P="$(srv_pid)"; [ -n "$P" ] || { echo "FATAL no cub_server"; exit 1; }
  #                 leg  hint                        shape
  for spec in "A::low" "B:/*+ NO_PARALLEL_SCAN */:low" "C::high" "D:/*+ NO_PARALLEL_SCAN */:high"; do
    leg="${spec%%:*}"; rest="${spec#*:}"; hint="${rest%:*}"; shape="${rest##*:}"
    emit_leg_sql "$leg" "$hint" "$shape" "${OUT}/leg${leg}.sql"
    # uncounted warmup on the same statement, then the traced run
    csql_run "${OUT}/leg${leg}.sql" "${OUT}/leg${leg}-warmup.out"
    T0=$(date +%s.%N)
    csql_run "${OUT}/leg${leg}.sql" "${OUT}/leg${leg}-trace.out"
    T1=$(date +%s.%N)
    echo "leg${leg} hint='${hint}' shape=${shape} traced_wall=$(echo "$T1 - $T0" | bc)" \
        | tee -a "${OUT}/legs.wall"
    echo "--- leg${leg} SCAN/GROUPBY lines"
    grep -E 'SCAN \(table|parallel workers|GROUPBY' "${OUT}/leg${leg}-trace.out" | sed 's/^/    /'
  done
  ;;

q15full)
  P="$(srv_pid)"; [ -n "$P" ] || { echo "FATAL no cub_server"; exit 1; }
  printf 'select count(*) from db_class where class_name = %s;\n' "'revenue0'" > "${OUT}/view-check.sql"
  csql_run "${OUT}/view-check.sql" "${OUT}/view-before.out"
  echo "--- view absent before (expect 0)"; grep -v '^$' "${OUT}/view-before.out" | tail -3
  { cat "${QUERIES}/q15_create_view-cubrid.sql"
    cat "${QUERIES}/q15_select-cubrid.sql"
    cat "${QUERIES}/q15_drop_view-cubrid.sql"; } > "${OUT}/q15-warmup.sql"
  csql_run "${OUT}/q15-warmup.sql" "${OUT}/q15-warmup.out"
  { cat "${QUERIES}/q15_create_view-cubrid.sql"
    printf '\nSET TRACE ON;\n'
    cat "${QUERIES}/q15_select-cubrid.sql"
    printf '\nSHOW TRACE;\n'
    cat "${QUERIES}/q15_drop_view-cubrid.sql"; } > "${OUT}/q15-trace.sql"
  T0=$(date +%s.%N)
  csql_run "${OUT}/q15-trace.sql" "${OUT}/q15-trace.out"
  T1=$(date +%s.%N)
  echo "q15 traced_wall=$(echo "$T1 - $T0" | bc)" | tee "${OUT}/q15.wall"
  csql_run "${OUT}/view-check.sql" "${OUT}/view-after.out"
  echo "--- view dropped after (expect 0)"; grep -v '^$' "${OUT}/view-after.out" | tail -3
  echo "--- q15 SCAN/GROUPBY lines"
  grep -E 'SCAN \(table|parallel workers|GROUPBY' "${OUT}/q15-trace.out" | sed 's/^/    /'
  ;;

stop)
  timeout 70 python3.11 "${HARNESS}/bgload_monitor.py" "${OUT}/bgload-end.json" 0.25 \
      > "${OUT}/bgload-end.txt" 2>&1 || true
  bash "${HARNESS}/server_ctl.sh" identity "${OUT}/identity-before-stop.json" \
      > "${OUT}/identity-before-stop.txt" 2>&1
  bash "${HARNESS}/server_ctl.sh" stop > "${OUT}/server-stop.txt" 2>&1
  echo "stop rc=$?"; tail -8 "${OUT}/server-stop.txt"
  ;;

*) echo "unknown stage $STAGE"; exit 2 ;;
esac
