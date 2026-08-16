#!/usr/bin/env bash
# Start the POC stack: Kafka (KRaft, single node) + Kafka Connect (Debezium
# base image) + ClickHouse, as three rootless-podman containers on one
# network. Idempotent: already-running containers are left alone.
#
# Data lives under $HTAP_DATA (default ~/htap-data) — never /tmp.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/versions.env"

HTAP_DATA="${HTAP_DATA:-$HOME/htap-data}"
NET=htap-net

mkdir -p "$HTAP_DATA/kafka" "$HTAP_DATA/clickhouse" \
         "$HTAP_DATA/connect-plugins/debezium-connector-cubrid" \
         "$HTAP_DATA/connect-plugins/clickhouse-kafka-connect"

podman network exists "$NET" || podman network create "$NET"

running () { podman container exists "$1" && [ "$(podman inspect -f '{{.State.Running}}' "$1")" = true ]; }

if running htap-kafka; then
    echo "kafka: already running"
else
    podman rm -f htap-kafka >/dev/null 2>&1 || true
    podman run -d --name htap-kafka --network "$NET" --network-alias kafka \
        --cgroupns=private \
        -p 9092:9092 \
        -v "$HTAP_DATA/kafka":/var/lib/kafka/data:Z,U \
        -e KAFKA_NODE_ID=1 \
        -e KAFKA_PROCESS_ROLES=broker,controller \
        -e KAFKA_LISTENERS=INTERNAL://0.0.0.0:19092,EXTERNAL://0.0.0.0:9092,CONTROLLER://0.0.0.0:9093 \
        -e KAFKA_ADVERTISED_LISTENERS=INTERNAL://kafka:19092,EXTERNAL://localhost:9092 \
        -e KAFKA_CONTROLLER_QUORUM_VOTERS=1@kafka:9093 \
        -e KAFKA_CONTROLLER_LISTENER_NAMES=CONTROLLER \
        -e KAFKA_LISTENER_SECURITY_PROTOCOL_MAP=INTERNAL:PLAINTEXT,EXTERNAL:PLAINTEXT,CONTROLLER:PLAINTEXT \
        -e KAFKA_INTER_BROKER_LISTENER_NAME=INTERNAL \
        -e KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR=1 \
        -e KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR=1 \
        -e KAFKA_TRANSACTION_STATE_LOG_MIN_ISR=1 \
        -e KAFKA_GROUP_INITIAL_REBALANCE_DELAY_MS=0 \
        -e KAFKA_LOG_DIRS=/var/lib/kafka/data \
        "$KAFKA_IMAGE"
    echo "kafka: started ($KAFKA_IMAGE)"
fi

if running htap-clickhouse; then
    echo "clickhouse: already running"
else
    podman rm -f htap-clickhouse >/dev/null 2>&1 || true
    podman run -d --name htap-clickhouse --network "$NET" --network-alias clickhouse \
        --cgroupns=private \
        -p 8123:8123 -p 9000:9000 \
        --ulimit nofile=262144:262144 \
        -v "$HTAP_DATA/clickhouse":/var/lib/clickhouse:Z,U \
        -v "$HERE/clickhouse/users.d/htap-sink.xml":/etc/clickhouse-server/users.d/htap-sink.xml:ro,Z \
        "$CLICKHOUSE_IMAGE"
    echo "clickhouse: started ($CLICKHOUSE_IMAGE)"
fi

if running htap-connect; then
    echo "connect: already running"
else
    podman rm -f htap-connect >/dev/null 2>&1 || true
    # CUBRID native client libs for the source connector's JNA binding (#40):
    # mounted OUTSIDE plugin.path (workspace#32 — JNA dlopen()s them itself) and
    # exposed via LD_LIBRARY_PATH. cubrid-host resolves to the host's LAN IP:
    # rootless netavark neither forwards the bridge gateway to host services nor
    # resolves host.containers.internal to a reachable address here.
    # the whole install, not just lib/: lib/libcascci.so.11.2 is a symlink
    # into ../cci/lib/, which must resolve inside the container too
    CUBRID_INSTALL="${CUBRID_INSTALL:-$HOME/htap-cdc/CUBRID-11.5-htapcdc}"
    CUBRID_HOST_IP="${CUBRID_HOST_IP:-$(ip route get 1.1.1.1 | awk '{for(i=1;i<NF;i++) if($i=="src") print $(i+1)}' | head -1)}"
    podman run -d --name htap-connect --network "$NET" --network-alias connect \
        --cgroupns=private \
        --add-host "cubrid-host:$CUBRID_HOST_IP" \
        -p 8083:8083 \
        -v "$HTAP_DATA/connect-plugins/debezium-connector-cubrid":/kafka/connect/debezium-connector-cubrid:Z,U \
        -v "$HTAP_DATA/connect-plugins/clickhouse-kafka-connect":/kafka/connect/clickhouse-kafka-connect:Z,U \
        -v "$CUBRID_INSTALL":/opt/cubrid:ro,Z \
        -e LD_LIBRARY_PATH=/opt/cubrid/lib \
        -e CUBRID=/opt/cubrid \
        -e BOOTSTRAP_SERVERS=kafka:19092 \
        -e GROUP_ID=htap-connect \
        -e CONFIG_STORAGE_TOPIC=htap_connect_configs \
        -e OFFSET_STORAGE_TOPIC=htap_connect_offsets \
        -e STATUS_STORAGE_TOPIC=htap_connect_statuses \
        ${OFFSET_FLUSH_INTERVAL_MS:+-e OFFSET_FLUSH_INTERVAL_MS="$OFFSET_FLUSH_INTERVAL_MS"} \
        "$CONNECT_IMAGE"
    echo "connect: started ($CONNECT_IMAGE)"
fi

echo "UP — run smoke.sh to verify"
