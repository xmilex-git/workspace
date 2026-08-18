#!/usr/bin/env bash
# Blocking snapshot over the Kafka signal channel (#65, ADR 0009 D4·D6):
# an `execute-snapshot` type=BLOCKING signal re-snapshots one table while the
# pipeline keeps running — streaming pauses at a batch boundary, the snapshot
# reuses the live anchor as its barrier (rows carry _version=0 so replayed CDC
# always wins), then streaming resumes from the same anchor. Duplicate events
# from the anchor replay are harmless by RMT convergence — diff-check is the
# oracle, as everywhere else.
#
#   BS1  seed + initial snapshot + streaming baseline -> mutate t_item ->
#        Kafka signal BLOCKING [t_item] -> pause/snapshot/resume observed in
#        logs -> post-snapshot DML on t_item AND t_order still streams ->
#        diff-check 0
#
# Prereqs: infra up, sink registered, connector plugin built from the
# standalone repo (build-connector.sh + podman restart htap-connect),
# htapdb server running. Usage: run-blocking-snapshot.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONNECT="${CONNECT_URL:-http://localhost:8083}"
CUBRID="${CUBRID:-$HOME/htap-cdc/CUBRID-11.5-htapcdc}"
CUBRID_DATABASES="${CUBRID_DATABASES:-$HOME/htap-cdc/db}"
DB="${DB:-htapdb}"
SOURCE_NAME=cubrid-source-poc
SIGNAL_TOPIC=htapcdc-signals
TOPIC_PREFIX=htapcdc            # signal key must equal topic.prefix (KafkaSignalChannel)

SCRATCH="$HERE/../../.git_ignored_dir/scratch/blocksnap.$$"
mkdir -p "$SCRATCH"
trap 'rm -rf "$SCRATCH"' EXIT

csql_file () { env CUBRID="$CUBRID" CUBRID_DATABASES="$CUBRID_DATABASES" PATH="$CUBRID/bin:$PATH" \
    csql -u dba "$DB" -i "$1" >/dev/null; }
csql_c () { env CUBRID="$CUBRID" CUBRID_DATABASES="$CUBRID_DATABASES" PATH="$CUBRID/bin:$PATH" \
    csql -u dba "$DB" -c "$1"; }
kafka () { podman exec htap-kafka /opt/kafka/bin/"$@"; }

T0="$(date -Is)"
mark_logs () { T0="$(date -Is)"; }
connect_logs () { podman logs --since "$T0" htap-connect 2>&1; }
wait_log () { # $1 = extended-regex pattern, $2 = timeout seconds
    local i
    for i in $(seq 1 "$2"); do
        local n; n="$(connect_logs | grep -cE "$1" || true)"
        if [ "${n:-0}" -gt 0 ]; then return 0; fi
        sleep 1
    done
    echo "FAIL: log pattern never appeared: $1" >&2
    return 1
}

wait_connect_up () {
    local i
    for i in $(seq 1 60); do
        curl -fsS "$CONNECT/connectors" >/dev/null 2>&1 && return 0
        sleep 2
    done
    echo "FAIL: Connect REST never came back" >&2; return 1
}

wait_converged () { # $1 = timeout iterations (x3s)
    local i
    for i in $(seq 1 "$1"); do
        if "$HERE/diff-check.sh" --quiet >/dev/null 2>&1; then
            echo "diff-check: 0 mismatch"
            return 0
        fi
        sleep 3
    done
    echo "FAIL: diff-check never reached 0 mismatch" >&2
    "$HERE/diff-check.sh" >&2 || true
    return 1
}

register () {
    python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))["config"]))' \
        "$HERE/cubrid-source.json" > "$SCRATCH/cfg.json"
    local i
    for i in $(seq 1 30); do
        curl -fsS -X PUT -H 'Content-Type: application/json' \
            -d @"$SCRATCH/cfg.json" "$CONNECT/connectors/$SOURCE_NAME/config" >/dev/null && return 0
        sleep 2
    done
    echo "FAIL: connector registration never succeeded" >&2
    return 1
}

send_signal () { # $1 = signal JSON (value); key is the connector logical name
    # podman exec -i: the producer reads the signal from stdin
    printf '%s|%s\n' "$TOPIC_PREFIX" "$1" | podman exec -i htap-kafka /opt/kafka/bin/kafka-console-producer.sh \
        --bootstrap-server localhost:9092 --topic "$SIGNAL_TOPIC" \
        --property parse.key=true --property key.separator='|' >/dev/null
}

echo "==== BS1: blocking snapshot of t_item via Kafka signal ===="

wait_connect_up

# a 1-partition signal topic (ADR 0009 D6); idempotent if it already exists
kafka kafka-topics.sh --bootstrap-server localhost:9092 --create \
    --topic "$SIGNAL_TOPIC" --partitions 1 --replication-factor 1 2>/dev/null || true

"$HERE/reset-pipeline.sh" >/dev/null
csql_file "$HERE/seed-cubrid.sql"
mark_logs
register
wait_log "Captured snapshot barrier LSA" 120
wait_log "CUBRID CDC stream" 180
wait_converged 60

# mutate the snapshot target while streaming so the re-snapshot has real work,
# and prove afterwards that the replayed CDC still wins over _version=0 rows
csql_c "UPDATE t_item SET qty = qty + 100 WHERE sku = 'SKU-A'; \
        INSERT INTO t_item VALUES ('SKU-BS1', 11, 1.2300); \
        DELETE FROM t_item WHERE sku = 'SKU-B'" >/dev/null
wait_converged 60

mark_logs
send_signal '{"id":"bs1-'"$$"'","type":"execute-snapshot","data":{"type":"BLOCKING","data-collections":["htapdb.t_item"]}}'
wait_log "Requested 'BLOCKING' snapshot" 120
wait_log "Streaming paused for an on-demand blocking snapshot" 60
wait_log "Blocking snapshot reuses anchor .* snapshot rows carry seq 0" 60
wait_log "Snapshot ended with" 180
wait_log "Streaming resumed after the blocking snapshot" 60

# streaming must still be live after the resume — on the re-snapshotted table
# and on an untouched one alike
csql_c "UPDATE t_item SET qty = qty + 1 WHERE sku = 'SKU-BS1'; \
        INSERT INTO t_order VALUES (777001, 'post-blocking', 7.7700, DATETIME'2026-08-18 00:00:00.000')" >/dev/null
wait_converged 90

echo "PASS: BS1"
