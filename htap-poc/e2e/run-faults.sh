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
# offsets snapshot helpers (#46 Gate D): sum CURRENT-OFFSET / LOG-END-OFFSET
# over the data-topic partitions of the sink group
group_describe () { kafka kafka-consumer-groups.sh --bootstrap-server localhost:9092 --group "$SINK_GROUP" --describe 2>/dev/null; }
committed_sum () { group_describe | awk '$2 ~ /^htapcdc\./ {s+=$4} END {print s+0}'; }
end_sum ()       { group_describe | awk '$2 ~ /^htapcdc\./ {s+=$5} END {print s+0}'; }

BEFORE="$(snapshot_views)"
END_BEFORE="$(end_sum)"
COMMITTED_BEFORE="$(committed_sum)"
echo "  before reset: committed=$COMMITTED_BEFORE end=$END_BEFORE"
[ "$COMMITTED_BEFORE" = "$END_BEFORE" ] || { echo "FAIL: S4 precondition — sink not fully caught up before reset" >&2; exit 1; }
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
COMMITTED_RESET="$(committed_sum)"
echo "  after reset: committed=$COMMITTED_RESET (must be rewound to earliest)"
[ "$COMMITTED_RESET" -lt "$END_BEFORE" ] || { echo "FAIL: offset reset did not rewind (committed=$COMMITTED_RESET end=$END_BEFORE)" >&2; exit 1; }
curl -fsS -X PUT "$CONNECT/connectors/$SINK_NAME/resume"
ensure_running "$SINK_NAME"
# wait for full redelivery: consumer group lag back to 0 on the data topics
for _ in $(seq 1 40); do
    LAG="$(group_describe | awk '$2 ~ /^htapcdc\./ {s+=$6} END {print s+0}')"
    [ "$LAG" = 0 ] && break
    sleep 3
done
# Gate D (#46): the drain loop must END at lag 0 — a timed-out loop used to
# fall through and let a partially-redelivered state pass
[ "$LAG" = 0 ] || { echo "FAIL: redelivery never drained (lag=$LAG)" >&2; exit 1; }
END_AFTER="$(end_sum)"
COMMITTED_AFTER="$(committed_sum)"
echo "  redelivery drained: lag=0 committed=$COMMITTED_AFTER end=$END_AFTER"
[ "$COMMITTED_AFTER" = "$END_AFTER" ] || { echo "FAIL: committed=$COMMITTED_AFTER != end=$END_AFTER after redelivery" >&2; exit 1; }
[ "$END_AFTER" = "$END_BEFORE" ] || { echo "FAIL: data-topic end offsets moved during S4 ($END_BEFORE -> $END_AFTER)" >&2; exit 1; }

# Gate D (#46): raw RMT evidence — redelivered rows must be byte-equal to the
# first delivery, i.e. no (pk, _version) group may hold >1 distinct row
# content ("duplicates carry the SAME _version"). Duplicate counts are
# recorded as evidence; background merges may have collapsed them already,
# so a zero count is a warning, not a failure.
DUP_ORDER="$(ch "SELECT count() FROM (SELECT id, _version FROM htap.t_order_local GROUP BY id, _version HAVING count() > 1)")"
DUP_ITEM="$(ch "SELECT count() FROM (SELECT sku, _version FROM htap.t_item_local GROUP BY sku, _version HAVING count() > 1)")"
DIVERGENT_ORDER="$(ch "SELECT count() FROM (SELECT id, _version FROM htap.t_order_local GROUP BY id, _version HAVING uniqExact(cityHash64(coalesce(toString(customer),'\\N'), coalesce(toString(amount),'\\N'), coalesce(toString(created_at),'\\N'), _op, toString(_is_deleted))) > 1)")"
DIVERGENT_ITEM="$(ch "SELECT count() FROM (SELECT sku, _version FROM htap.t_item_local GROUP BY sku, _version HAVING uniqExact(cityHash64(coalesce(toString(qty),'\\N'), coalesce(toString(price),'\\N'), _op, toString(_is_deleted))) > 1)")"
echo "  raw RMT duplicate (pk,_version) groups: t_order=$DUP_ORDER t_item=$DUP_ITEM"
[ "$((DUP_ORDER + DUP_ITEM))" -gt 0 ] || echo "  WARN: no raw duplicates visible (background merges may have collapsed them)"
[ "$DIVERGENT_ORDER" = 0 ] && [ "$DIVERGENT_ITEM" = 0 ] || {
    echo "FAIL: same (pk,_version) with divergent content — t_order=$DIVERGENT_ORDER t_item=$DIVERGENT_ITEM" >&2; exit 1; }
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
