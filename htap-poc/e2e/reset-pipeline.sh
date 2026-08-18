#!/usr/bin/env bash
# Reset the CDC pipeline state for a fresh E2E run (#40):
#   1. stop + delete-offsets + delete the source connector (a same-name
#      re-registration would otherwise silently resume from the old anchor —
#      forbidden without a fresh snapshot, ADR 0004)
#   2. delete + recreate the data topics and the heartbeat topic
#   3. truncate the ClickHouse *_local tables (ADR 0005 — truncate only)
#   4. restart the sink connector so its consumer rejoins the fresh topics
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONNECT="${CONNECT_URL:-http://localhost:8083}"
SOURCE_NAME=cubrid-source-poc
SINK_NAME=clickhouse-sink-poc
TOPICS=(htapcdc.htapdb.t_order htapcdc.htapdb.t_item htapcdc.htapdb.t_typecorpus __debezium-heartbeat.htapcdc)

kafka () { podman exec htap-kafka /opt/kafka/bin/"$@"; }

echo "== source connector: stop -> delete offsets -> delete =="
if curl -fsS "$CONNECT/connectors/$SOURCE_NAME" >/dev/null 2>&1; then
    curl -fsS -X PUT "$CONNECT/connectors/$SOURCE_NAME/stop"
    for _ in $(seq 1 15); do
        state="$(curl -fsS "$CONNECT/connectors/$SOURCE_NAME/status" | python3 -c 'import json,sys;print(json.load(sys.stdin)["connector"]["state"])')"
        [ "$state" = STOPPED ] && break
        sleep 2
    done
    curl -fsS -X DELETE "$CONNECT/connectors/$SOURCE_NAME/offsets" && echo || echo "(no offsets to delete)"
    curl -fsS -X DELETE "$CONNECT/connectors/$SOURCE_NAME"
    echo "deleted $SOURCE_NAME"
else
    echo "$SOURCE_NAME not registered"
fi

echo "== topics: delete (purge) =="
# the sink's live consumer metadata-requests the data topics, so the broker
# auto-recreates them (auto.create.topics.enable) right after deletion — the
# net effect of a delete is "empty topic", which is exactly what we need
for t in "${TOPICS[@]}"; do
    kafka kafka-topics.sh --bootstrap-server localhost:9092 --delete --topic "$t" 2>/dev/null || true
done
echo "topics purged: ${TOPICS[*]}"

echo "== clickhouse: truncate =="
"$HERE/../sink/apply-ddl.sh" --truncate

echo "== sink: restart =="
curl -fsS -X POST "$CONNECT/connectors/$SINK_NAME/restart?includeTasks=true" || true
echo
echo "RESET DONE"
