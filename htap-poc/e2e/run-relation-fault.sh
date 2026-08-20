#!/usr/bin/env bash
# 관계 identity fail-closed 실 e2e (workspace#82 D2/D5) — #81 종착에서 리뷰 BLOCKER-5로 추가.
#
# 이전 리뷰(#48)의 원 P0 장애 경로를 synthetic unit이 아니라 실제 엔진 pair에서 재현한다:
#   S1. committed DML → extractor lag → DROP  → empty relation announce halt (D2)
#   S2. committed DML → extractor lag → RENAME → include-list mismatch halt   (D5)
#
# "extractor lag"의 실체: 커넥터의 read cursor는 정지 시 anchor에 얼어붙는다. 커넥터가
# 멈춘 동안 committed DML을 넣고 DROP/RENAME 하면, 그 committed 변경은 얼어붙은 cursor
# 뒤에 lag된 채 남고 테이블은 서버에서 이미 사라지거나 이름이 바뀐다. 재개 시 새 세션은
# anchor부터 재-announce 하는데, announce 이름은 엔진이 extraction 시점에 live로 resolve
# 하므로(ADR 0011 D4) → DROP은 빈 이름, RENAME은 새 이름으로 도착한다. 따라서
# "connector-down → DROP/RENAME → restart"와 "extractor lag → DROP/RENAME"은 커넥터가
# 보는 조건이 동일하다 — 이 스크립트는 정지/재개로 그 조건을 결정론적으로 만든다.
#
# 핵심 correctness 성질(리뷰가 요구): lag된 committed 변경이 empty/renamed 관계로 조용히
# 오라우팅되지 않는다 — 커넥터는 publish 전에 halt하고 anchor를 DDL 이전에 고정해
# 재시작이 결정론적으로 re-halt한다. 이 스크립트는 halt·re-halt·sink 무변화를 assert한다.
#
# 전제: infra up, 커넥터 플러그인 빌드, htapdb(wire v2 엔진)+broker 기동.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONNECT="${CONNECT_URL:-http://localhost:8083}"
CUBRID="${HTAP_CUBRID:-$HOME/htap-cdc/CUBRID-11.5-htapcdc-prv}"
CUBRID_DATABASES="${CUBRID_DATABASES:-/home/cubrid/CUBRID/databases}"
DB="${DB:-htapdb}"
NAME=cubrid-source-relfault
PREFIX=htaprelf
FAILED=0
fail() { echo "  [FAIL] $*"; FAILED=1; }
ok()   { echo "  [OK] $*"; }

csql_c () {
    env CUBRID="$CUBRID" CUBRID_DATABASES="$CUBRID_DATABASES" PATH="$CUBRID/bin:$PATH" \
        csql -u dba "$DB" -c "$1"
}
task_state () {
    curl -fsS "$CONNECT/connectors/$NAME/status" \
        | python3 -c "import json,sys;t=json.load(sys.stdin)['tasks'];print(t[0]['state'] if t else 'PENDING')" 2>/dev/null || echo PENDING
}
conn_state () {
    curl -fsS "$CONNECT/connectors/$NAME/status" \
        | python3 -c "import json,sys;print(json.load(sys.stdin)['connector']['state'])" 2>/dev/null || echo GONE
}
task_trace () {
    curl -fsS "$CONNECT/connectors/$NAME/status" \
        | python3 -c "import json,sys;print(json.load(sys.stdin)['tasks'][0].get('trace',''))" 2>/dev/null || true
}
KAFKA_BIN=/opt/kafka/bin
topic_count () { # $1 = topic
    podman exec htap-kafka "$KAFKA_BIN/kafka-console-consumer.sh" --bootstrap-server localhost:19092 \
        --topic "$1" --from-beginning --timeout-ms 5000 2>/dev/null | grep -c . || true
}
wait_task () { for _ in $(seq 1 "$2"); do [ "$(task_state)" = "$1" ] && return 0; sleep 2; done; return 1; }
wait_conn () { for _ in $(seq 1 "$2"); do [ "$(conn_state)" = "$1" ] && return 0; sleep 2; done; return 1; }
wait_msg () { for _ in $(seq 1 "$2"); do podman exec htap-kafka "$KAFKA_BIN/kafka-console-consumer.sh" \
        --bootstrap-server localhost:19092 --topic "$3" --from-beginning --timeout-ms 4000 2>/dev/null \
        | grep -q "$1" && return 0; sleep 2; done; return 1; }

echo "== 0a. CDC 단일 consumer — 기존 소스 정지 =="
MAIN=cubrid-source-poc
MAIN_WAS_RUNNING=""
if curl -fsS "$CONNECT/connectors/$MAIN/status" 2>/dev/null \
        | python3 -c 'import json,sys;exit(0 if json.load(sys.stdin)["connector"]["state"]=="RUNNING" else 1)' 2>/dev/null; then
    MAIN_WAS_RUNNING=yes; curl -fsS -X PUT "$CONNECT/connectors/$MAIN/stop" >/dev/null
    # wait for the CDC single-consumer session to actually release (see run-partition-ddl.sh);
    # poll MAIN explicitly — conn_state() is bound to this suite's own $NAME
    for _ in $(seq 1 15); do
        [ "$(curl -fsS "$CONNECT/connectors/$MAIN/status" | python3 -c 'import json,sys;print(json.load(sys.stdin)["connector"]["state"])' 2>/dev/null || echo x)" = STOPPED ] && break
        sleep 2
    done
    echo "stopped $MAIN"
fi
restore_main () { [ -n "$MAIN_WAS_RUNNING" ] && curl -fsS -X PUT "$CONNECT/connectors/$MAIN/resume" >/dev/null 2>&1 || true; }
trap restore_main EXIT

cleanup_conn () { # $1 = connector name
    if curl -fsS "$CONNECT/connectors/$1" >/dev/null 2>&1; then
        curl -fsS -X PUT "$CONNECT/connectors/$1/stop" >/dev/null || true
        for _ in $(seq 1 15); do
            [ "$(curl -fsS "$CONNECT/connectors/$1/status" | python3 -c 'import json,sys;print(json.load(sys.stdin)["connector"]["state"])' 2>/dev/null || echo x)" = STOPPED ] && break; sleep 2
        done
        curl -fsS -X DELETE "$CONNECT/connectors/$1/offsets" >/dev/null 2>&1 || true
        curl -fsS -X DELETE "$CONNECT/connectors/$1" >/dev/null 2>&1 || true
    fi
}

register () {
    local include="$1"
    python3 - "$HERE/cubrid-source.json" "$include" "$PREFIX" <<'EOF' | curl -fsS -X PUT -H 'Content-Type: application/json' -d @- "$CONNECT/connectors/$NAME/config" >/dev/null
import json, sys
cfg = json.load(open(sys.argv[1]))["config"]
cfg.update({"topic.prefix": sys.argv[3], "table.include.list": sys.argv[2]})
for k in [k for k in cfg if k.startswith("transforms")]:
    del cfg[k]
print(json.dumps(cfg))
EOF
}

run_scenario () { # $1=label $2=table $3=post-stop-DDL $4=halt-grep $5=include
    local label="$1" table="$2" ddl="$3" halt_re="$4" include="$5"
    local topic="$PREFIX.dba.$table"
    echo "== $label =="
    cleanup_conn "$NAME"
    podman exec htap-kafka "$KAFKA_BIN/kafka-topics.sh" --bootstrap-server localhost:19092 --delete --topic "$topic" >/dev/null 2>&1 || true
    csql_c "DROP TABLE IF EXISTS $table" >/dev/null 2>&1

    echo "  1. seed committed rows + converge snapshot/stream"
    csql_c "CREATE TABLE $table (id INT PRIMARY KEY, note VARCHAR(32)); COMMIT;" >/dev/null
    csql_c "GRANT SELECT ON $table TO cdc_e2e" >/dev/null
    csql_c "INSERT INTO $table VALUES (1,'seed-1'),(2,'seed-2'); COMMIT;" >/dev/null
    sleep 3
    register "$include"
    wait_task RUNNING 30 || { fail "$label: task never RUNNING"; task_trace; return; }
    wait_msg '"note":"seed-1"' 30 "$topic" || { fail "$label: snapshot row missing"; task_trace; return; }
    # a streaming change while running, to prove the stream is live before we freeze it
    csql_c "INSERT INTO $table VALUES (3,'live-3'); COMMIT;" >/dev/null
    wait_msg '"note":"live-3"' 30 "$topic" || { fail "$label: live streaming row missing"; task_trace; return; }
    ok "$label: baseline converged (snapshot + live stream)"

    echo "  2. STOP connector (freeze read cursor = extractor lag)"
    curl -fsS -X PUT "$CONNECT/connectors/$NAME/stop" >/dev/null
    wait_conn STOPPED 20 || { fail "$label: connector did not STOP"; return; }
    sleep 3   # let the task fully drain before we call the cursor frozen (avoid a stop race)
    # baseline captured AFTER the freeze settles: any later appearance of the lagged row is a real leak
    local before_count; before_count="$(topic_count "$topic")"

    echo "  3. committed DML (now lagging, strictly after freeze) + server-side DDL while stopped"
    csql_c "INSERT INTO $table VALUES (4,'lagged-secret'); COMMIT;" >/dev/null
    csql_c "$ddl" >/dev/null 2>&1 || { fail "$label: post-stop DDL failed"; return; }

    echo "  4. RESUME → fresh session re-announces from anchor, resolves names live"
    curl -fsS -X PUT "$CONNECT/connectors/$NAME/resume" >/dev/null
    wait_task FAILED 40 || { fail "$label: did NOT fail-closed (silent divergence risk!)"; echo "   state=$(task_state)"; task_trace | head -3; return; }
    local trace; trace="$(task_trace)"
    echo "$trace" | grep -qiE "$halt_re" \
        && ok "$label: fail-closed halt with expected cause" \
        || { fail "$label: halted but wrong cause (expected /$halt_re/)"; echo "   trace: $(echo "$trace" | head -1)"; }
    echo "   -- halt trace head: $(echo "$trace" | head -1)"

    echo "  5. deterministic re-halt on task restart"
    curl -fsS -X POST "$CONNECT/connectors/$NAME/tasks/0/restart" >/dev/null
    wait_task FAILED 30 && ok "$label: deterministic re-halt" || fail "$label: did not re-halt"

    echo "  6. no silent divergence: lagged committed row never published to its topic"
    local after_count; after_count="$(topic_count "$topic")"
    # topic may not even exist after DROP; either way the lagged 'lagged-secret' must not appear
    if podman exec htap-kafka "$KAFKA_BIN/kafka-console-consumer.sh" --bootstrap-server localhost:19092 \
            --topic "$topic" --from-beginning --timeout-ms 5000 2>/dev/null | grep -q 'lagged-secret'; then
        fail "$label: lagged committed row LEAKED to topic after fail-closed — divergence"
    else
        ok "$label: lagged row not published (halt precedes publish) [topic $before_count→$after_count msgs]"
    fi
    cleanup_conn "$NAME"
    echo
}

# S1: DROP → empty announce halt (workspace#82 D2)
run_scenario "S1 committed DML → lag → DROP → fail-closed halt" \
    t_relf_drop \
    "DROP TABLE t_relf_drop" \
    "does not exist|dropped or renamed|empty names|dropped server-side|relation announce" \
    "dba.t_relf_drop"

# S2: RENAME → include-list mismatch halt (workspace#82 D5).
# include list stays the OLD name; the rename makes the announce carry the new name.
run_scenario "S2 committed DML → lag → RENAME → fail-closed halt" \
    t_relf_ren \
    "RENAME TABLE t_relf_ren AS t_relf_ren_new" \
    "does not exist|dropped or renamed|not in 'table.include.list'|renamed server-side|misattributed" \
    "dba.t_relf_ren"
# tidy the renamed leftover
csql_c "DROP TABLE IF EXISTS t_relf_ren_new" >/dev/null 2>&1 || true

if [ "$FAILED" -ne 0 ]; then echo "판정: FAIL"; exit 1; fi
echo "PASS — 원 P0 장애 경로(DROP/RENAME under extractor lag)가 실 엔진 pair에서 fail-closed로 차단됨"
