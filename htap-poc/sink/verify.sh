#!/usr/bin/env bash
# Ticket #39 completion check, end to end:
#   1. reset state (truncate *_local, re-apply DDL)
#   2. produce the I/U/D samples
#   3. assert the canonical FINAL views reach the expected state
#   4. produce the SAME samples again (duplicate redelivery)
#   5. assert the canonical views are byte-identical to step 3
# Prereqs: infra up, sink plugin installed, connector registered
# (install-sink-plugin.sh + register-sink.sh).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GROUP=connect-clickhouse-sink-poc   # sink connectors consume as connect-<name>

ch () { podman exec htap-clickhouse clickhouse-client --query "$1"; }

EXPECTED_ORDER=$'1\talice\t99.5\t2026-08-16 03:00:00.123\n3\tcarol-updated\t7.77\t2026-08-16 02:00:00.000'
EXPECTED_ITEM=$'A\t7\t1.5'
WANT="$EXPECTED_ORDER"$'\n--\n'"$EXPECTED_ITEM"

snapshot_views () {
    ch "SELECT * FROM htap.t_order ORDER BY id FORMAT TSV"
    echo "--"
    ch "SELECT * FROM htap.t_item ORDER BY sku FORMAT TSV"
}

# Wait until the sink's consumer group has consumed+committed everything.
# Raw-row counts are NOT usable as a signal: RMT background merges collapse
# physical rows at any time. Offset commit interval is 60s, so be patient.
wait_for_lag_zero () {
    for _ in $(seq 1 45); do
        lag="$(podman exec htap-kafka /opt/kafka/bin/kafka-consumer-groups.sh \
                 --bootstrap-server localhost:9092 --describe --group "$GROUP" 2>/dev/null \
               | awk 'NR>1 && $6 ~ /^[0-9]+$/ {s+=$6} END {print s+0}')"
        [ "$lag" = 0 ] && return 0
        sleep 3
    done
    echo "TIMEOUT: consumer group $GROUP still lagging" >&2
    return 1
}

echo "== 1. reset =="
"$HERE/apply-ddl.sh" --truncate

echo "== 2. produce samples =="
"$HERE/produce-samples.sh"

echo "== 3. canonical state after first delivery =="
FIRST=""
for _ in $(seq 1 30); do
    FIRST="$(snapshot_views)"
    [ "$FIRST" = "$WANT" ] && break
    sleep 2
done
echo "$FIRST"
if [ "$FIRST" != "$WANT" ]; then
    echo "FAIL: canonical views != expected" >&2
    diff <(echo "$WANT") <(echo "$FIRST") >&2 || true
    exit 1
fi
echo "OK: upsert / snapshot-vs-CDC / tombstone / FINAL as expected"

echo "== 4. duplicate redelivery =="
wait_for_lag_zero    # first batch fully committed, so redelivery is a true duplicate
"$HERE/produce-samples.sh"
wait_for_lag_zero

echo "== 5. canonical state must be unchanged =="
SECOND="$(snapshot_views)"
if [ "$SECOND" != "$FIRST" ]; then
    echo "FAIL: duplicate redelivery changed the canonical views" >&2
    diff <(echo "$FIRST") <(echo "$SECOND") >&2 || true
    exit 1
fi
echo "OK: duplicate redelivery is a no-op on the canonical views"
echo "PASS"
