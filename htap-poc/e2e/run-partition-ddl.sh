#!/usr/bin/env bash
# Partition e2e fault test (workspace#83 / #75 D11+D12): a partitioned table
# captured through the include list must
#   (1) route every partition's DML to the ROOT-name topic (snapshot + streaming),
#   (2) survive mid-stream ADD/REORGANIZE PARTITION and index/FK ALTERs (no halt),
#   (3) decode rows of a partition created AFTER root ALTERs correctly
#       (partition repr lineage != root repr lineage),
#   (4) halt (task FAILED, deterministic re-halt) on DROP PARTITION.
#
# Prereqs: infra up (../infra/up.sh), connector plugin built (build-connector.sh),
# htapdb server + broker running (cubrid-server-control / cubrid broker start).
# Uses its own connector instance + topic prefix; does not disturb cubrid-source-poc.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONNECT="${CONNECT_URL:-http://localhost:8083}"
# deliberately NOT ${CUBRID:-...}: login shells on this host export the campaign
# install (~/CUBRID) whose old csql classifies partition ALTERs as TABLE and
# poisons this test's DDL supplements; override with HTAP_CUBRID if needed
CUBRID="${HTAP_CUBRID:-$HOME/htap-cdc/CUBRID-11.5-htapcdc-prv}"
CUBRID_DATABASES="${CUBRID_DATABASES:-/home/cubrid/CUBRID/databases}"
DB="${DB:-htapdb}"
NAME=cubrid-source-part83
PREFIX=htappart83
TABLE=t_part83
TOPIC="$PREFIX.dba.$TABLE"

csql_c () { # $1 = sql text
    env CUBRID="$CUBRID" CUBRID_DATABASES="$CUBRID_DATABASES" PATH="$CUBRID/bin:$PATH" \
        csql -u dba "$DB" -c "$1"
}
task_state () {
    curl -fsS "$CONNECT/connectors/$NAME/status" \
        | python3 -c "import json,sys;t=json.load(sys.stdin)['tasks'];print(t[0]['state'] if t else 'PENDING')"
}
task_trace () {
    curl -fsS "$CONNECT/connectors/$NAME/status" \
        | python3 -c "import json,sys;print(json.load(sys.stdin)['tasks'][0].get('trace',''))"
}
KAFKA_BIN=/opt/kafka/bin
consume () { # full topic contents (value JSON, one per line)
    podman exec htap-kafka "$KAFKA_BIN/kafka-console-consumer.sh" --bootstrap-server localhost:19092 \
        --topic "$TOPIC" --from-beginning --timeout-ms 5000 2>/dev/null || true
}
wait_task () { # $1 = wanted state, $2 = tries (2s apart)
    for _ in $(seq 1 "$2"); do
        [ "$(task_state)" = "$1" ] && return 0
        sleep 2
    done
    return 1
}
wait_msg () { # $1 = grep pattern, $2 = tries; topic must eventually contain it
    for _ in $(seq 1 "$2"); do
        if consume | grep -q "$1"; then return 0; fi
        sleep 2
    done
    return 1
}

echo "== 0a. CDC session is single-consumer (cdc_Gl.conn) — stop other source connectors =="
MAIN=cubrid-source-poc
MAIN_WAS_RUNNING=""
if curl -fsS "$CONNECT/connectors/$MAIN/status" 2>/dev/null \
        | python3 -c 'import json,sys;s=json.load(sys.stdin);exit(0 if s["connector"]["state"]=="RUNNING" else 1)' 2>/dev/null; then
    MAIN_WAS_RUNNING=yes
    curl -fsS -X PUT "$CONNECT/connectors/$MAIN/stop" >/dev/null
    # wait for the CDC single-consumer session to actually release before we register
    # our own source — a still-RUNNING MAIN holds cdc_Gl and starves our barrier capture
    for _ in $(seq 1 15); do
        [ "$(curl -fsS "$CONNECT/connectors/$MAIN/status" | python3 -c 'import json,sys;print(json.load(sys.stdin)["connector"]["state"])' 2>/dev/null || echo x)" = STOPPED ] && break
        sleep 2
    done
    echo "stopped $MAIN for the duration of this test"
fi
restore_main () {
    if [ -n "$MAIN_WAS_RUNNING" ]; then
        curl -fsS -X PUT "$CONNECT/connectors/$MAIN/resume" >/dev/null 2>&1 || true
        echo "resumed $MAIN"
    fi
}
trap restore_main EXIT

echo "== 0. cleanup previous run (stop -> delete offsets -> delete, ADR 0004) =="
if curl -fsS "$CONNECT/connectors/$NAME" >/dev/null 2>&1; then
    curl -fsS -X PUT "$CONNECT/connectors/$NAME/stop" >/dev/null || true
    for _ in $(seq 1 15); do
        st="$(curl -fsS "$CONNECT/connectors/$NAME/status" | python3 -c 'import json,sys;print(json.load(sys.stdin)["connector"]["state"])' 2>/dev/null || echo '')"
        [ "$st" = STOPPED ] && break
        sleep 2
    done
    curl -fsS -X DELETE "$CONNECT/connectors/$NAME/offsets" >/dev/null 2>&1 || true
    curl -fsS -X DELETE "$CONNECT/connectors/$NAME" >/dev/null 2>&1 || true
fi
podman exec htap-kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:19092 \
    --delete --topic "$TOPIC" >/dev/null 2>&1 || true
csql_c "DROP TABLE IF EXISTS $TABLE" >/dev/null

echo "== 1. seed: partitioned table WITH root ALTER history, rows in p0/p1 =="
csql_c "CREATE TABLE $TABLE (id INT PRIMARY KEY, v INT, note VARCHAR(16))
        PARTITION BY RANGE (id) (
          PARTITION p0 VALUES LESS THAN (100),
          PARTITION p1 VALUES LESS THAN (200))" >/dev/null
# root ALTER before capture: bumps root+p0+p1 repr to 2; partitions added later start at repr 1
csql_c "ALTER TABLE $TABLE ADD COLUMN extra INT DEFAULT 0" >/dev/null
csql_c "GRANT SELECT ON $TABLE TO cdc_e2e" >/dev/null
csql_c "INSERT INTO $TABLE VALUES (10, 1, 'p0-snap', 41), (110, 2, 'p1-snap', 42)" >/dev/null
# the snapshot barrier resolves by second-resolution timestamp and may replay the last
# couple of seconds (ADR 0006) — keep the seed root ALTER out of the replayed window, or
# it arrives in the stream and (correctly) triggers a DDL halt. 3s is too tight under a
# loaded back-to-back suite run (measured: intermittent halt on the seed ADD COLUMN);
# 12s puts the pre-capture DDL safely outside any second-resolution replay window.
sleep 12

echo "== 2. register dedicated source connector (include=dba.$TABLE) =="
python3 - "$HERE/cubrid-source.json" <<'EOF' | curl -fsS -X PUT -H 'Content-Type: application/json' -d @- "$CONNECT/connectors/cubrid-source-part83/config" >/dev/null
import json, sys
cfg = json.load(open(sys.argv[1]))["config"]
cfg.update({
    "topic.prefix": "htappart83",
    "table.include.list": "dba.t_part83",
})
for k in [k for k in cfg if k.startswith("transforms")]:
    del cfg[k]
print(json.dumps(cfg))
EOF

echo "== 3. snapshot rows reach the ROOT-name topic =="
wait_task RUNNING 30 || { echo "FAIL: task never RUNNING"; task_trace; exit 1; }
wait_msg '"note":"p0-snap"' 45 || { echo "FAIL: p0 snapshot row missing on $TOPIC"; echo "-- task status:"; curl -fsS "$CONNECT/connectors/$NAME/status"; echo; echo "-- trace:"; task_trace; echo "-- topic dump:"; consume | head; exit 1; }
consume | grep -q '"note":"p1-snap"' || { echo "FAIL: p1 snapshot row missing"; exit 1; }
echo "OK: both partitions' snapshot rows on $TOPIC"

echo "== 4. streaming DML on existing partitions routes to root =="
csql_c "INSERT INTO $TABLE VALUES (20, 3, 'p0-stream', 43)" >/dev/null
wait_msg '"note":"p0-stream"' 30 || { echo "FAIL: streaming p0 insert missing"; exit 1; }
echo "OK: streaming DML on root-name topic"

echo "== 5. mid-stream ADD PARTITION passes; NEW partition rows decode correctly =="
csql_c "ALTER TABLE $TABLE ADD PARTITION (PARTITION p2 VALUES LESS THAN (300))" >/dev/null
csql_c "INSERT INTO $TABLE VALUES (210, 4, 'p2-new', 44)" >/dev/null
wait_msg '"note":"p2-new"' 30 || { echo "FAIL: new-partition insert missing/undecodable"; task_trace; exit 1; }
consume | grep '"note":"p2-new"' | grep -q '"extra":44' || { echo "FAIL: new-partition row misdecoded"; exit 1; }
[ "$(task_state)" = RUNNING ] || { echo "FAIL: ADD PARTITION halted the task"; task_trace; exit 1; }
echo "OK: ADD PARTITION no-halt + divergent-repr partition row decoded (extra=44)"

echo "== 6. mid-stream REORGANIZE PARTITION passes =="
csql_c "ALTER TABLE $TABLE REORGANIZE PARTITION p2 INTO (
          PARTITION p2a VALUES LESS THAN (250),
          PARTITION p2b VALUES LESS THAN (300))" >/dev/null
csql_c "INSERT INTO $TABLE VALUES (260, 5, 'p2b-reorg', 45)" >/dev/null
wait_msg '"note":"p2b-reorg"' 30 || { echo "FAIL: post-REORG insert missing"; task_trace; exit 1; }
[ "$(task_state)" = RUNNING ] || { echo "FAIL: REORGANIZE PARTITION halted the task"; task_trace; exit 1; }
echo "OK: REORGANIZE PARTITION no-halt"

echo "== 7. index/FK ALTERs pass (encoding-safe reclassification, D10) =="
csql_c "ALTER TABLE $TABLE ADD INDEX idx_v (v)" >/dev/null
csql_c "ALTER TABLE $TABLE DROP INDEX idx_v" >/dev/null
csql_c "INSERT INTO $TABLE VALUES (30, 6, 'post-idx', 46)" >/dev/null
wait_msg '"note":"post-idx"' 30 || { echo "FAIL: post-index-ALTER insert missing"; task_trace; exit 1; }
[ "$(task_state)" = RUNNING ] || { echo "FAIL: index ALTER halted the task"; task_trace; exit 1; }
echo "OK: ADD/DROP INDEX no-halt"

echo "== 8. DROP PARTITION halts (fail-fast), restart re-halts deterministically =="
csql_c "ALTER TABLE $TABLE DROP PARTITION p2b" >/dev/null
wait_task FAILED 30 || { echo "FAIL: DROP PARTITION did not halt"; exit 1; }
task_trace | grep -qi "ddl" || { echo "FAIL: halt trace does not mention DDL"; task_trace; exit 1; }
echo "-- halt trace head:"; task_trace | head -3
curl -fsS -X POST "$CONNECT/connectors/$NAME/tasks/0/restart" >/dev/null
wait_task FAILED 30 || { echo "FAIL: restart did not re-halt"; exit 1; }
echo "OK: DROP PARTITION halt + deterministic re-halt"

echo "== 9. cleanup =="
curl -fsS -X DELETE "$CONNECT/connectors/$NAME" >/dev/null || true

echo "PASS"
