#!/usr/bin/env bash
# Smoke test for the POC stack (ticket #34 완료 조건):
#   kafka:      create topic -> produce -> consume
#   clickhouse: HTTP ping + sample MergeTree insert/select
#   connect:    REST /connectors answers
set -euo pipefail

fail () { echo "SMOKE FAIL: $*" >&2; exit 1; }

KBIN=/opt/kafka/bin

echo "--- kafka: wait for broker"
for i in $(seq 1 60); do
    podman exec htap-kafka $KBIN/kafka-topics.sh --bootstrap-server localhost:9092 --list >/dev/null 2>&1 && break
    [ "$i" = 60 ] && fail "kafka broker not ready after 60s"
    sleep 1
done

echo "--- kafka: topic create/produce/consume"
podman exec htap-kafka $KBIN/kafka-topics.sh --bootstrap-server localhost:9092 \
    --create --if-not-exists --topic htap-smoke --partitions 1 --replication-factor 1
echo "hello-htap-$(date +%s)" | podman exec -i htap-kafka $KBIN/kafka-console-producer.sh \
    --bootstrap-server localhost:9092 --topic htap-smoke
MSG=$(podman exec htap-kafka $KBIN/kafka-console-consumer.sh --bootstrap-server localhost:9092 \
    --topic htap-smoke --from-beginning --max-messages 1 --timeout-ms 20000 2>/dev/null)
echo "consumed: $MSG"
[[ "$MSG" == hello-htap-* ]] || fail "kafka produce/consume mismatch"

echo "--- clickhouse: ping + MergeTree insert/select"
for i in $(seq 1 60); do
    PING=$(curl -fsS http://localhost:8123/ping 2>/dev/null || true)
    [ "$PING" = "Ok." ] && break
    [ "$i" = 60 ] && fail "clickhouse /ping not ready after 60s"
    sleep 1
done
podman exec htap-clickhouse clickhouse-client -q "
    CREATE TABLE IF NOT EXISTS smoke (id UInt32, v String) ENGINE = MergeTree ORDER BY id;
    INSERT INTO smoke VALUES (1, 'ok');
"
CNT=$(podman exec htap-clickhouse clickhouse-client -q "SELECT count() FROM smoke WHERE v='ok'")
echo "clickhouse rows: $CNT"
[ "$CNT" -ge 1 ] || fail "clickhouse insert/select failed"

echo "--- connect: REST /connectors"
for i in $(seq 1 120); do
    RESP=$(curl -fsS http://localhost:8083/connectors 2>/dev/null || true)
    [ -n "$RESP" ] && break
    [ "$i" = 120 ] && fail "connect REST not ready after 120s"
    sleep 1
done
echo "connectors: $RESP"

echo "SMOKE OK"
