#!/usr/bin/env bash
# Fault / restart / duplicate verification (#41), §1.3 items 8~9.
# Runs four scenarios against a LIVE converged pipeline (run-e2e.sh PASS
# state) and asserts diff-check.sh reaches 0 mismatch after each:
#   S1  source task restart mid-stream   (Connect REST task restart)
#   S2  Connect worker hard restart      (podman restart = JVM kill;
#       offset anchor resume, at-least-once replay from anchor — ADR 0004)
#   S3  ClickHouse outage while writes continue, then recovery
#   S4  duplicate delivery of the SAME batches: sink stopped, its consumer
#       group offsets reset to earliest, resumed — the whole topic history
#       is redelivered; deterministic _version makes RMT converge, so the
#       canonical views must come out BYTE-IDENTICAL (not just diff-clean)
#
# Every scenario also runs an ABORT txn so committed-only survives faults.
# CUBRID is the oracle — no hardcoded expected state; loss shows up as a
# diff-check row-count/checksum mismatch after the convergence window.
#
# Prereqs: run-e2e.sh has passed (connectors registered+RUNNING, views
# converged), htapdb server running.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONNECT="${CONNECT_URL:-http://localhost:8083}"
CUBRID="${CUBRID:-$HOME/htap-cdc/CUBRID-11.5-htapcdc}"
CUBRID_DATABASES="${CUBRID_DATABASES:-$HOME/htap-cdc/db}"
DB="${DB:-htapdb}"
SOURCE_NAME=cubrid-source-poc
SINK_NAME=clickhouse-sink-poc
SINK_GROUP=connect-clickhouse-sink-poc
TOPICS=(htapcdc.htapdb.t_order htapcdc.htapdb.t_item)

SCRATCH="$HERE/../../.git_ignored_dir/scratch/faults.$$"
mkdir -p "$SCRATCH"
trap 'rm -rf "$SCRATCH"' EXIT

csql_file () { # $1 = sql file
    env CUBRID="$CUBRID" CUBRID_DATABASES="$CUBRID_DATABASES" PATH="$CUBRID/bin:$PATH" \
        csql -u dba "$DB" -i "$1" >/dev/null
}
ch () { podman exec htap-clickhouse clickhouse-client --query "$1"; }
kafka () { podman exec htap-kafka /opt/kafka/bin/"$@"; }

status_json () { curl -fsS "$CONNECT/connectors/$1/status"; }
conn_state () { status_json "$1" | python3 -c 'import json,sys;print(json.load(sys.stdin)["connector"]["state"])'; }
task_state () { status_json "$1" | python3 -c 'import json,sys;s=json.load(sys.stdin)["tasks"];print(s[0]["state"] if s else "NONE")'; }

wait_connect_up () {
    for _ in $(seq 1 60); do
        curl -fsS "$CONNECT/connectors" >/dev/null 2>&1 && return 0
        sleep 2
    done
    echo "FAIL: Connect REST never came back" >&2; exit 1
}

ensure_running () { # $1 = connector name; resume if stopped/paused, restart failed tasks
    for _ in $(seq 1 30); do
        c="$(conn_state "$1" 2>/dev/null || echo DOWN)"
        t="$(task_state "$1" 2>/dev/null || echo DOWN)"
        [ "$c" = RUNNING ] && [ "$t" = RUNNING ] && return 0
        case "$c" in STOPPED|PAUSED) curl -fsS -X PUT "$CONNECT/connectors/$1/resume" || true ;; esac
        [ "$t" = FAILED ] && { curl -fsS -X POST "$CONNECT/connectors/$1/tasks/0/restart" || true; }
        sleep 3
    done
    echo "FAIL: $1 never reached RUNNING (connector=$c task=$t)" >&2
    status_json "$1" >&2 || true
    exit 1
}

converge () { # poll diff-check until 0 mismatch
    for _ in $(seq 1 40); do
        "$HERE/diff-check.sh" --quiet 2>/dev/null && { echo "converged: diff-check 0 mismatch"; return 0; }
        sleep 3
    done
    echo "FAIL: no convergence within window — final diff:" >&2
    "$HERE/diff-check.sh" >&2 || true
    exit 1
}

# Per-scenario writes. $1 = scenario id (1..4), $2 = phase (1|2).
# ids are namespaced <sid>01/<sid>02/<sid>99 so scenarios never collide.
workload () {
    local sid="$1" phase="$2" f="$SCRATCH/w${1}p${2}.sql"
    if [ "$phase" = 1 ]; then
        cat > "$f" <<EOF
;autocommit off
INSERT INTO t_order VALUES (${sid}01, 'f${sid}-a', ${sid}.1000, DATETIME'2026-08-16 12:0${sid}:00.000');
UPDATE t_item SET qty = qty + 1 WHERE sku = 'SKU-A';
COMMIT;
-- ABORT txn: must never reach ClickHouse, fault or not
INSERT INTO t_order VALUES (${sid}99, 'ghost${sid}', 0.0001, NULL);
DELETE FROM t_item WHERE sku = 'SKU-B';
ROLLBACK;
EOF
    else
        cat > "$f" <<EOF
;autocommit off
INSERT INTO t_order VALUES (${sid}02, 'f${sid}-b', ${sid}.2000, NULL);
UPDATE t_order SET customer = 'f${sid}-a2' WHERE id = ${sid}01;
COMMIT;
DELETE FROM t_order WHERE id = ${sid}02;
COMMIT;
EOF
    fi
    csql_file "$f"
    echo "  wrote workload s${sid} phase ${phase}"
}

snapshot_views () {
    ch "SELECT * FROM htap.t_order ORDER BY id FORMAT TSV"
    echo "--"
    ch "SELECT * FROM htap.t_item ORDER BY sku FORMAT TSV"
}

echo "== S0. preconditions: connectors RUNNING, baseline diff-check =="
ensure_running "$SOURCE_NAME"
ensure_running "$SINK_NAME"
"$HERE/diff-check.sh" || { echo "FAIL: baseline not converged — run run-e2e.sh first" >&2; exit 1; }

echo "== S1. source task restart mid-stream =="
workload 1 1
curl -fsS -X POST "$CONNECT/connectors/$SOURCE_NAME/tasks/0/restart"
workload 1 2
ensure_running "$SOURCE_NAME"
converge

echo "== S2. Connect worker hard restart (JVM kill) =="
workload 2 1
podman restart htap-connect >/dev/null
wait_connect_up
ensure_running "$SOURCE_NAME"
ensure_running "$SINK_NAME"
workload 2 2
converge

echo "== S3. ClickHouse outage during writes, then recovery =="
podman stop htap-clickhouse >/dev/null
workload 3 1
workload 3 2
sleep 10
podman start htap-clickhouse >/dev/null
for _ in $(seq 1 30); do ch "SELECT 1" >/dev/null 2>&1 && break; sleep 2; done
ensure_running "$SINK_NAME"
converge

echo "== S4. duplicate delivery: sink offsets reset to earliest =="
BEFORE="$(snapshot_views)"
curl -fsS -X PUT "$CONNECT/connectors/$SINK_NAME/stop"
for _ in $(seq 1 15); do
    [ "$(conn_state "$SINK_NAME")" = STOPPED ] && break
    sleep 2
done
sleep 3   # group membership must drain before offsets can be reset
for t in "${TOPICS[@]}"; do
    kafka kafka-consumer-groups.sh --bootstrap-server localhost:9092 \
        --group "$SINK_GROUP" --topic "$t" --reset-offsets --to-earliest --execute
done
curl -fsS -X PUT "$CONNECT/connectors/$SINK_NAME/resume"
ensure_running "$SINK_NAME"
# wait for full redelivery: consumer group lag back to 0 on the data topics
for _ in $(seq 1 40); do
    LAG="$(kafka kafka-consumer-groups.sh --bootstrap-server localhost:9092 \
        --group "$SINK_GROUP" --describe 2>/dev/null \
        | awk '$2 ~ /^htapcdc\./ {s+=$6} END {print s+0}')"
    [ "$LAG" = 0 ] && break
    sleep 3
done
echo "  redelivery drained (lag=$LAG)"
converge
AFTER="$(snapshot_views)"
if [ "$BEFORE" != "$AFTER" ]; then
    echo "FAIL: canonical views changed after duplicate redelivery" >&2
    diff <(echo "$BEFORE") <(echo "$AFTER") >&2 || true
    exit 1
fi
echo "  canonical views byte-identical before/after redelivery"

echo "== final differential check =="
"$HERE/diff-check.sh"
echo "PASS: all 4 fault scenarios converged with 0 mismatch"
