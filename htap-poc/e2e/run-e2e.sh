#!/usr/bin/env bash
# E2E vertical slice (#40): write-stop snapshot (ADR 0005) -> connector
# streaming -> Kafka -> ClickHouse sink -> canonical views, asserting the
# three ticket completion criteria:
#   (a) only committed changes are visible (ABORT never lands)
#   (b) §7.7 convergence: same-PK multi-update, insert->delete,
#       delete->insert, PK change (old tombstone + new insert)
#   (c) no gap between snapshot and streaming (barrier boundary rows)
#
# Prereqs: infra up (../infra/up.sh), sink chain
# installed+registered (../sink/), connector plugin built (build-connector.sh
# + podman restart htap-connect), htapdb server running (cubrid-server-control).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONNECT="${CONNECT_URL:-http://localhost:8083}"
CUBRID="${CUBRID:-$HOME/htap-cdc/CUBRID-11.5-htapcdc}"
CUBRID_DATABASES="${CUBRID_DATABASES:-$HOME/htap-cdc/db}"
DB="${DB:-htapdb}"
SINK_GROUP=connect-clickhouse-sink-poc

csql_run () { # $1 = sql file
    env CUBRID="$CUBRID" CUBRID_DATABASES="$CUBRID_DATABASES" PATH="$CUBRID/bin:$PATH" \
        csql -u dba "$DB" -i "$1"
}
ch () { podman exec htap-clickhouse clickhouse-client --query "$1"; }

# ---- expected final state (must equal live CUBRID after the workload) ----
EXPECTED_ORDER=$'1\talice\t100\t2026-08-16 10:00:00.000\n2\tbob-streamed\t20.5\t2026-08-16 10:01:00.000\n5\tcarol\t7.77\t2026-08-16 11:00:00.000'
EXPECTED_ITEM=$'SKU-A\t10\t23\nSKU-B\t77\t0.5'
WANT="$EXPECTED_ORDER"$'\n--\n'"$EXPECTED_ITEM"

snapshot_views () {
    ch "SELECT * FROM htap.t_order ORDER BY id FORMAT TSV"
    echo "--"
    ch "SELECT * FROM htap.t_item ORDER BY sku FORMAT TSV"
}

echo "== 0. reset pipeline =="
"$HERE/reset-pipeline.sh"

echo "== 1. write stop + seed pre-snapshot state =="
# #70 (ADR 0011 D1): the connector account is non-DBA with per-table SELECT only;
# creation is idempotent (exists on reruns), the grants are re-issued by the seed
env CUBRID="$CUBRID" CUBRID_DATABASES="$CUBRID_DATABASES" PATH="$CUBRID/bin:$PATH" \
    csql -u dba "$DB" -c "CREATE USER cdc_e2e PASSWORD 'cdc_e2e'" >/dev/null 2>&1 || true
csql_run "$HERE/seed-cubrid.sql"

echo "== 2. register source connector (snapshot.mode=initial) =="
"$HERE/register-source.sh"

echo "== 3. wait for streaming phase (barrier handover) =="
STREAMING=""
for _ in $(seq 1 60); do
    # grep -c (not -q): -q's early exit SIGPIPEs podman and pipefail turns the
    # match into a failure
    n="$(podman logs --since 10m htap-connect 2>&1 | grep -cE "CUBRID CDC stream" || true)"
    if [ "${n:-0}" -gt 0 ]; then
        STREAMING=yes
        break
    fi
    sleep 2
done
[ -n "$STREAMING" ] || { echo "FAIL: connector never entered streaming" >&2; exit 1; }
echo "streaming entered — write stop may end"

echo "== 4. write resume: streaming workload (I/U/D x COMMIT/ABORT, §7.7) =="
csql_run "$HERE/streaming-workload.sql"

echo "== 5. wait for convergence =="
GOT=""
for _ in $(seq 1 60); do
    GOT="$(snapshot_views)"
    [ "$GOT" = "$WANT" ] && break
    sleep 3
done
echo "$GOT"
if [ "$GOT" != "$WANT" ]; then
    echo "FAIL: canonical views != expected" >&2
    diff <(echo "$WANT") <(echo "$GOT") >&2 || true
    exit 1
fi
echo "OK: committed-only + §7.7 convergence + no snapshot/streaming gap"

echo "== 6. §7.7 PK-change physical check (old PK tombstone arrived) =="
TOMB="$(ch "SELECT count() FROM htap.t_order_local WHERE id = 3 AND _is_deleted" || echo 0)"
echo "tombstone rows for old PK id=3: $TOMB (informational — background merges may collapse)"

echo "== 7. differential-lite: CUBRID row counts match canonical views =="
CUB_ORD="$(env CUBRID="$CUBRID" CUBRID_DATABASES="$CUBRID_DATABASES" PATH="$CUBRID/bin:$PATH" \
    csql -u dba "$DB" -c "SELECT COUNT(*) FROM t_order" | awk '/^ *[0-9]+ *$/{print $1}')"
CUB_ITM="$(env CUBRID="$CUBRID" CUBRID_DATABASES="$CUBRID_DATABASES" PATH="$CUBRID/bin:$PATH" \
    csql -u dba "$DB" -c "SELECT COUNT(*) FROM t_item" | awk '/^ *[0-9]+ *$/{print $1}')"
CH_ORD="$(ch "SELECT count() FROM htap.t_order")"
CH_ITM="$(ch "SELECT count() FROM htap.t_item")"
echo "t_order: cubrid=$CUB_ORD clickhouse=$CH_ORD / t_item: cubrid=$CUB_ITM clickhouse=$CH_ITM"
[ "$CUB_ORD" = "$CH_ORD" ] && [ "$CUB_ITM" = "$CH_ITM" ] || { echo "FAIL: row counts diverge" >&2; exit 1; }

echo "PASS"
