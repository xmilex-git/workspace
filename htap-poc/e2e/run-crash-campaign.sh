#!/usr/bin/env bash
# #46 Gate B: partial-publish crash campaign.
#
# Deterministically injects a Connect JVM kill (podman kill = SIGKILL) into
# the publish window of a 30k-row single transaction and proves the #45 fix:
# after restart the pipeline must reach keyed-full-row-diff 0 mismatch with
# zero loss, and every duplicate must carry the SAME _version.
#
# Crash points (ticket #46), each judged from live topic observation
# (background console consumers counting produced records + the flushed
# source-offset anchor `seq` from htap_connect_offsets):
#   cp1  zero-published crash: kill BEFORE the COMMIT is issued (the txn's
#        DMLs are already in the log and buffered; nothing enqueued) — the
#        same recovery state as "COMMIT read, publish not yet started"
#   cp2  mid-publish: 0 < produced < N AND a mid-publish offset flush has
#        been observed; assert the flushed anchor seq <= txn-start seq
#        (the #45 invariant, observed from outside the JVM)
#   cp3  all N produced, but BEFORE the post-txn anchor is flushed
#        (no heartbeat-carried offset commit yet)
#   cp4  post-txn anchor flushed (seq >= c0+N): kill AFTER durability —
#        restart must NOT republish (final produced count stays N)
#   cp5  interleaved: T1 start -> T2 start -> T1 COMMIT -> kill mid-publish
#        of T1 while T2 is still open; T2 commits while Connect is down
#
# Each (crash point, run) cycle starts from a fresh pipeline (reset ->
# seed -> snapshot -> streaming) so cycles are independent. RUNS=3 by
# default: every crash point must pass 3 consecutive times.
#
# Timing-miss (the kill landed outside the intended window) is retried up to
# MAX_TRIES per cycle; a verification failure (mismatch, loss, divergent
# _version) aborts the whole campaign — that is the result.
#
# Prereqs: infra up with OFFSET_FLUSH_INTERVAL_MS=1000 (see infra/up.sh),
# connector plugin built from the #45 fix (build-connector.sh), htapdb up.
set -Eeuo pipefail   # -E so the ERR trap fires inside functions too

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONNECT="${CONNECT_URL:-http://localhost:8083}"
CUBRID="${CUBRID:-$HOME/htap-cdc/CUBRID-11.5-htapcdc}"
CUBRID_DATABASES="${CUBRID_DATABASES:-$HOME/htap-cdc/db}"
DB="${DB:-htapdb}"
SOURCE_NAME=cubrid-source-poc
SINK_NAME=clickhouse-sink-poc
ORDER_TOPIC=htapcdc.dba.t_order
HB_TOPIC=__debezium-heartbeat.htapcdc
OFFSETS_TOPIC=htap_connect_offsets

N="${N:-30000}"            # rows in the single crash-target transaction
RUNS="${RUNS:-3}"          # consecutive passes required per crash point
MAX_TRIES="${MAX_TRIES:-4}" # timing-miss retries per cycle
SCENARIOS=(${SCENARIOS:-cp1 cp2 cp3 cp4 cp5})

EVIDENCE="$HERE/evidence"
mkdir -p "$EVIDENCE"
LOG="$EVIDENCE/issue-46-crash-campaign.log"
SCRATCH="$HERE/../../.git_ignored_dir/scratch/crash.$$"
mkdir -p "$SCRATCH"

CONSUMER_PIDS=()
SESSION_A=""
SESSION_B=""

cleanup () {
    stop_counters || true
    close_session 7 || true
    close_session 8 || true
}
trap cleanup EXIT

log () { echo "$(date +%H:%M:%S) $*" | tee -a "$LOG"; }
# set -e aborts are otherwise silent — name the dying command in the log
trap 'log "ERR trap: line $LINENO: $BASH_COMMAND (rc=$?)"' ERR

csql_exec () { # $1 = sql file
    env CUBRID="$CUBRID" CUBRID_DATABASES="$CUBRID_DATABASES" PATH="$CUBRID/bin:$PATH" \
        csql -u dba "$DB" -i "$1" >/dev/null
}
kafka () { podman exec htap-kafka /opt/kafka/bin/"$@"; }

# ---------- interactive csql sessions over FIFOs (fd 7 = A, fd 8 = B) ----------
open_session () { # $1 = fd
    local fifo="$SCRATCH/sess$1.fifo"
    mkfifo "$fifo"
    env CUBRID="$CUBRID" CUBRID_DATABASES="$CUBRID_DATABASES" PATH="$CUBRID/bin:$PATH" \
        csql -u dba "$DB" < "$fifo" > "$SCRATCH/sess$1.out" 2>&1 &
    eval "exec $1>\"$fifo\""
}
send_sql () { # $1 = fd, rest = statement
    local fd="$1"; shift
    echo "$*" >&"$fd"
}
close_session () { # $1 = fd
    eval "exec $1>&-" 2>/dev/null || return 0
    rm -f "$SCRATCH/sess$1.fifo"
}

# ---------- connect lifecycle ----------
wait_connect_up () {
    for _ in $(seq 1 60); do
        curl -fsS "$CONNECT/connectors" >/dev/null 2>&1 && return 0
        sleep 2
    done
    echo "FAIL: Connect REST never came back" >&2; exit 1
}
conn_state () { curl -fsS "$CONNECT/connectors/$1/status" | python3 -c 'import json,sys;print(json.load(sys.stdin)["connector"]["state"])'; }
task_state () { curl -fsS "$CONNECT/connectors/$1/status" | python3 -c 'import json,sys;s=json.load(sys.stdin)["tasks"];print(s[0]["state"] if s else "NONE")'; }
ensure_running () {
    for _ in $(seq 1 30); do
        local c t
        c="$(conn_state "$1" 2>/dev/null || echo DOWN)"
        t="$(task_state "$1" 2>/dev/null || echo DOWN)"
        [ "$c" = RUNNING ] && [ "$t" = RUNNING ] && return 0
        case "$c" in STOPPED|PAUSED) curl -fsS -X PUT "$CONNECT/connectors/$1/resume" >/dev/null || true ;; esac
        [ "$t" = FAILED ] && { curl -fsS -X POST "$CONNECT/connectors/$1/tasks/0/restart" || true; }
        sleep 3
    done
    echo "FAIL: $1 never reached RUNNING" >&2; exit 1
}

# ---------- topic observation ----------
start_counters () {
    : > "$SCRATCH/cnt.order"; : > "$SCRATCH/cnt.hb"; : > "$SCRATCH/offsets.txt"
    podman exec htap-kafka /opt/kafka/bin/kafka-console-consumer.sh \
        --bootstrap-server localhost:9092 --topic "$ORDER_TOPIC" \
        > "$SCRATCH/cnt.order" 2>/dev/null &
    CONSUMER_PIDS+=($!)
    podman exec htap-kafka /opt/kafka/bin/kafka-console-consumer.sh \
        --bootstrap-server localhost:9092 --topic "$HB_TOPIC" \
        > "$SCRATCH/cnt.hb" 2>/dev/null &
    CONSUMER_PIDS+=($!)
    podman exec htap-kafka /opt/kafka/bin/kafka-console-consumer.sh \
        --bootstrap-server localhost:9092 --topic "$OFFSETS_TOPIC" \
        --property print.key=true \
        > "$SCRATCH/offsets.txt" 2>/dev/null &
    CONSUMER_PIDS+=($!)
    sleep 3   # let the consumers join before the action starts
}
stop_counters () {
    # the .sh wrapper execs java, so match the java class — then kill the
    # podman-exec clients so `wait` cannot block on them
    podman exec htap-kafka pkill -f ConsoleConsumer 2>/dev/null || true
    [ "${#CONSUMER_PIDS[@]}" -gt 0 ] && kill "${CONSUMER_PIDS[@]}" 2>/dev/null || true
    [ "${#CONSUMER_PIDS[@]}" -gt 0 ] && wait "${CONSUMER_PIDS[@]}" 2>/dev/null || true
    CONSUMER_PIDS=()
}
order_count () { wc -l < "$SCRATCH/cnt.order"; }
hb_count ()    { wc -l < "$SCRATCH/cnt.hb"; }
flushed_seq () { # latest flushed streaming-anchor seq for our source, or -1
    # grep exits 1 on no-match — with pipefail that would kill the caller
    { grep "$SOURCE_NAME" "$SCRATCH/offsets.txt" 2>/dev/null || true; } \
        | python3 -c '
import sys, json
seq = -1
for line in sys.stdin:
    parts = line.rstrip("\n").split("\t", 1)
    if len(parts) != 2 or not parts[1].strip() or parts[1].strip() == "null":
        continue
    try:
        v = json.loads(parts[1])
    except json.JSONDecodeError:
        continue
    if isinstance(v, dict) and "seq" in v:
        seq = v["seq"]
print(seq)'
}
offsets_lines () { grep -c "$SOURCE_NAME" "$SCRATCH/offsets.txt" 2>/dev/null || true; }

kill_connect () { podman kill htap-connect >/dev/null; log "  >> podman kill htap-connect (SIGKILL)"; }
restart_connect () {
    podman start htap-connect >/dev/null
    wait_connect_up
    ensure_running "$SOURCE_NAME"
    ensure_running "$SINK_NAME"
}

# ---------- per-cycle pipeline prep ----------
register_campaign_source () {
    # ticket #46: small queue/batch so the 30k publish is a wide crash window.
    # retried: right after a kill/restart cycle the worker may still be
    # rebalancing and answer the PUT with a transient 409
    for _ in $(seq 1 15); do
        if python3 -c '
import json, sys
cfg = json.load(open(sys.argv[1]))["config"]
cfg["max.queue.size"] = "64"
cfg["max.batch.size"] = "16"
print(json.dumps(cfg))' "$HERE/cubrid-source.json" \
            | curl -fsS -X PUT -H 'Content-Type: application/json' -d @- \
                "$CONNECT/connectors/$SOURCE_NAME/config" >/dev/null 2>&1; then
            return 0
        fi
        sleep 3
    done
    log "FAIL: could not (re)register the source connector"; exit 1
}

prep_cycle () { # fresh pipeline: reset -> seed -> snapshot -> streaming -> baseline
    local reset_ok=""
    for _ in 1 2 3; do   # same transient-409 exposure as the register PUT
        if "$HERE/reset-pipeline.sh" > "$SCRATCH/reset.log" 2>&1; then reset_ok=yes; break; fi
        sleep 5
    done
    [ -n "$reset_ok" ] || { log "FAIL: reset-pipeline.sh (tail): $(tail -3 "$SCRATCH/reset.log" | tr '\n' ' ')"; exit 1; }
    log "  prep: reset ok"
    csql_exec "$HERE/seed-cubrid.sql"
    cat > "$SCRATCH/bulkseed.sql" <<'EOF'
DROP TABLE IF EXISTS bulk_seed;
CREATE TABLE bulk_seed (i INT PRIMARY KEY);
EOF
    for i in $(seq 1 200); do echo "INSERT INTO bulk_seed VALUES ($i);" >> "$SCRATCH/bulkseed.sql"; done
    csql_exec "$SCRATCH/bulkseed.sql"
    local since
    since="$(date -u +%Y-%m-%dT%H:%M:%S)"
    register_campaign_source
    local streaming=""
    for _ in $(seq 1 60); do
        n="$(podman logs --since "$since" htap-connect 2>&1 | grep -cE 'CUBRID CDC stream' || true)"
        [ "${n:-0}" -gt 0 ] && { streaming=yes; break; }
        sleep 2
    done
    [ -n "$streaming" ] || { log "FAIL: connector never entered streaming"; exit 1; }
    ensure_running "$SINK_NAME"
    for _ in $(seq 1 100); do
        "$HERE/diff-check.sh" --quiet 2>/dev/null && break
        sleep 3
    done
    "$HERE/diff-check.sh" --quiet 2>/dev/null || { log "FAIL: baseline never converged"; exit 1; }
    start_counters
    # anchor seq before the crash-target txn (c0): flushed within ~6s via heartbeat
    C0=-1
    for _ in $(seq 1 20); do
        C0="$(flushed_seq)"
        [ "$C0" -ge 0 ] && break
        sleep 1
    done
    [ "$C0" -ge 0 ] || { log "FAIL: no baseline offset flush observed"; exit 1; }
}

bulk_sql () { # $1 = output file, $2 = with_commit(yes|no), $3 = pk base
    cat > "$1" <<EOF
;autocommit off
INSERT INTO t_order SELECT $3 + ROWNUM, 'bulk-' || CAST(ROWNUM AS VARCHAR), 1.2345, DATETIME'2026-08-16 12:00:00.000' FROM bulk_seed a, bulk_seed b WHERE ROWNUM <= $N;
EOF
    [ "$2" = yes ] && echo "COMMIT;" >> "$1"
}

wait_order_count () { # $1 = target, $2 = timeout seconds -> 0 if reached
    local deadline=$(( $(date +%s) + $2 ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        [ "$(order_count)" -ge "$1" ] && return 0
        sleep 0.05
    done
    return 1
}

# ---------- post-crash verification (shared by all scenarios) ----------
verify_cycle () { # $1 = cycle tag
    local tag="$1"
    for _ in $(seq 1 90); do
        "$HERE/diff-check.sh" --quiet 2>/dev/null && break
        sleep 5
    done
    if ! "$HERE/diff-check.sh" > "$SCRATCH/diff.$tag" 2>&1; then
        cat "$SCRATCH/diff.$tag" | tee -a "$LOG" >&2
        log "VERIFY FAIL ($tag): keyed diff mismatch after convergence window"
        return 2
    fi
    local div_o div_i dup_o dup_i
    div_o="$(podman exec htap-clickhouse clickhouse-client --query "SELECT count() FROM (SELECT id, _version FROM htap.t_order_local GROUP BY id, _version HAVING uniqExact(cityHash64(coalesce(toString(customer),'\\N'), coalesce(toString(amount),'\\N'), coalesce(toString(created_at),'\\N'), _op, toString(_is_deleted))) > 1)")"
    div_i="$(podman exec htap-clickhouse clickhouse-client --query "SELECT count() FROM (SELECT sku, _version FROM htap.t_item_local GROUP BY sku, _version HAVING uniqExact(cityHash64(coalesce(toString(qty),'\\N'), coalesce(toString(price),'\\N'), _op, toString(_is_deleted))) > 1)")"
    dup_o="$(podman exec htap-clickhouse clickhouse-client --query "SELECT count() FROM (SELECT id, _version FROM htap.t_order_local GROUP BY id, _version HAVING count() > 1)")"
    dup_i="$(podman exec htap-clickhouse clickhouse-client --query "SELECT count() FROM (SELECT sku, _version FROM htap.t_item_local GROUP BY sku, _version HAVING count() > 1)")"
    if [ "$div_o" != 0 ] || [ "$div_i" != 0 ]; then
        log "VERIFY FAIL ($tag): divergent content under same (pk,_version): t_order=$div_o t_item=$div_i"
        return 2
    fi
    local produced final_seq
    produced="$(order_count)"
    final_seq="$(flushed_seq)"
    log "  verify($tag): diff=0 divergent=0 raw-dup-groups(order=$dup_o,item=$dup_i) produced=$produced flushed_seq=$final_seq (c0=$C0)"
    # offset dump evidence: first/last flushed offsets of the cycle
    {
        echo "== $tag (c0=$C0, produced=$produced) =="
        grep "$SOURCE_NAME" "$SCRATCH/offsets.txt" | head -3
        echo "  ..."
        grep "$SOURCE_NAME" "$SCRATCH/offsets.txt" | tail -3
    } >> "$EVIDENCE/issue-46-offset-dumps.txt"
    return 0
}

# ---------- scenarios: return 0 pass, 1 timing-miss (retry), 2 verify-fail ----------
scenario_cp1 () { # zero-published crash: kill before COMMIT, commit after kill
    open_session 7
    send_sql 7 ";autocommit off"
    send_sql 7 "INSERT INTO t_order SELECT 100000 + ROWNUM, 'bulk-' || CAST(ROWNUM AS VARCHAR), 1.2345, DATETIME'2026-08-16 12:00:00.000' FROM bulk_seed a, bulk_seed b WHERE ROWNUM <= $N;"
    sleep 5   # DML executed + streamed into the buffer (uncommitted)
    local d_kill
    d_kill="$(order_count)"
    kill_connect
    if [ "$d_kill" != 0 ]; then
        log "  cp1 timing miss: $d_kill records already produced before kill"
        close_session 7; return 1
    fi
    send_sql 7 "COMMIT;"
    sleep 1
    close_session 7
    log "  cp1: killed with 0 produced, COMMIT executed while Connect was down"
    restart_connect
    verify_cycle cp1 || return 2
    [ "$(order_count)" -eq "$N" ] || { log "VERIFY FAIL (cp1): produced $(order_count) != $N"; return 2; }
    return 0
}

scenario_cp2 () { # mid-publish kill after a mid-publish offset flush
    bulk_sql "$SCRATCH/bulk.sql" yes 100000
    local off0
    off0="$(offsets_lines)"
    csql_exec "$SCRATCH/bulk.sql"
    local lo=$(( N / 10 )) hi=$(( N * 7 / 10 )) d flushed_mid=-1
    while :; do
        d="$(order_count)"
        [ "$d" -ge "$hi" ] && break
        if [ "$d" -ge "$lo" ] && [ "$(offsets_lines)" -gt "$off0" ]; then
            flushed_mid="$(flushed_seq)"
            kill_connect
            break
        fi
        sleep 0.05
    done
    d="$(order_count)"
    if [ "$flushed_mid" -lt 0 ] || [ "$d" -le 0 ] || [ "$d" -ge "$N" ]; then
        log "  cp2 timing miss: produced=$d at kill decision (flush seen: $([ "$flushed_mid" -ge 0 ] && echo yes || echo no))"
        [ "$flushed_mid" -lt 0 ] && kill_connect   # kill anyway so the cycle can be retried cleanly
        restart_connect
        return 1
    fi
    log "  cp2: killed mid-publish at produced=$d/$N, mid-flushed anchor seq=$flushed_mid (c0=$C0)"
    # the #45 invariant, observed from outside: the anchor persisted while the
    # commit was mid-publish must not have advanced past the txn start
    if [ "$flushed_mid" -gt $(( C0 + 300 )) ]; then
        log "VERIFY FAIL (cp2): mid-publish flushed anchor seq=$flushed_mid advanced past txn start (c0=$C0)"
        restart_connect
        return 2
    fi
    restart_connect
    verify_cycle cp2 || return 2
    local produced
    produced="$(order_count)"
    [ "$produced" -ge "$N" ] || { log "VERIFY FAIL (cp2): produced $produced < $N — loss"; return 2; }
    log "  cp2: replay produced $(( produced - N )) duplicate records over N=$N — all same-_version (checked above)"
    return 0
}

scenario_cp3 () { # all produced, kill before the post-txn anchor is flushed
    bulk_sql "$SCRATCH/bulk.sql" yes 100000
    csql_exec "$SCRATCH/bulk.sql"
    wait_order_count "$N" 120 || { log "  cp3 timing miss: publish never reached N"; return 1; }
    local seq_at_n
    seq_at_n="$(flushed_seq)"
    kill_connect
    if [ "$seq_at_n" -gt $(( C0 + 300 )) ]; then
        log "  cp3 timing miss: post-txn anchor (seq=$seq_at_n) already flushed before kill (c0=$C0)"
        restart_connect
        return 1
    fi
    log "  cp3: killed at produced=N=$N with last flushed anchor seq=$seq_at_n (c0=$C0) — post-txn anchor not yet durable"
    restart_connect
    verify_cycle cp3 || return 2
    local produced
    produced="$(order_count)"
    [ "$produced" -ge "$N" ] || { log "VERIFY FAIL (cp3): produced $produced < $N — loss"; return 2; }
    log "  cp3: full-txn replay expected — produced=$produced (duplicates $(( produced - N )), all same-_version)"
    return 0
}

scenario_cp4 () { # kill after the post-txn anchor is durable: no republish allowed
    bulk_sql "$SCRATCH/bulk.sql" yes 100000
    csql_exec "$SCRATCH/bulk.sql"
    wait_order_count "$N" 120 || { log "  cp4 timing miss: publish never reached N"; return 1; }
    local seq_now=-1
    for _ in $(seq 1 30); do   # heartbeat (<=5s) + flush (<=1s) + consumer latency
        seq_now="$(flushed_seq)"
        [ "$seq_now" -ge $(( C0 + N )) ] && break
        sleep 1
    done
    [ "$seq_now" -ge $(( C0 + N )) ] || { log "  cp4 timing miss: post-txn anchor never flushed (seq=$seq_now)"; return 1; }
    kill_connect
    log "  cp4: killed after post-txn anchor durable (flushed seq=$seq_now >= c0+N=$(( C0 + N )))"
    restart_connect
    sleep 20   # give a wrong implementation time to republish
    local produced
    produced="$(order_count)"
    if [ "$produced" -ne "$N" ]; then
        log "VERIFY FAIL (cp4): expected NO republish after durable anchor, produced=$produced != $N"
        return 2
    fi
    verify_cycle cp4 || return 2
    log "  cp4: zero republish after restart (produced stayed $N)"
    return 0
}

scenario_cp5 () { # interleaved: T1 start -> T2 start -> T1 COMMIT -> kill mid-publish; T2 commits while down
    open_session 7   # T1
    open_session 8   # T2
    send_sql 7 ";autocommit off"
    send_sql 8 ";autocommit off"
    send_sql 7 "INSERT INTO t_order VALUES (200000, 't1-marker', 1.0000, NULL);"   # T1 start
    sleep 1
    send_sql 8 "INSERT INTO t_order VALUES (210000, 't2-row', 2.0000, NULL);"      # T2 start (after T1)
    sleep 1
    # bulk PK range 300001.. must NOT contain T2's id 210000 — a collision
    # would block T1's insert on T2's uncommitted unique-key lock forever
    send_sql 7 "INSERT INTO t_order SELECT 300000 + ROWNUM, 'bulk-' || CAST(ROWNUM AS VARCHAR), 1.2345, DATETIME'2026-08-16 12:00:00.000' FROM bulk_seed a, bulk_seed b WHERE ROWNUM <= $N;"
    send_sql 7 "COMMIT;"                                                            # T1 commits, T2 still open
    local t1n=$(( N + 1 )) lo=$(( N / 10 )) hi=$(( N * 7 / 10 )) d flushed_mid=-1
    local deadline=$(( $(date +%s) + 180 ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        d="$(order_count)"
        [ "$d" -ge "$hi" ] && break
        if [ "$d" -ge "$lo" ]; then
            flushed_mid="$(flushed_seq)"
            kill_connect
            break
        fi
        sleep 0.05
    done
    d="$(order_count)"
    if [ "$d" -le 0 ] || [ "$d" -ge "$t1n" ]; then
        log "  cp5 timing miss: produced=$d at kill decision"
        close_session 7; close_session 8
        restart_connect
        return 1
    fi
    log "  cp5: killed mid-publish of T1 at produced=$d/$t1n (T2 open), mid-flushed anchor seq=$flushed_mid (c0=$C0)"
    if [ "$flushed_mid" -ge 0 ] && [ "$flushed_mid" -gt $(( C0 + 300 )) ]; then
        log "VERIFY FAIL (cp5): mid-publish flushed anchor seq=$flushed_mid advanced past T1 start (c0=$C0)"
        close_session 7; close_session 8
        restart_connect
        return 2
    fi
    send_sql 8 "COMMIT;"   # T2 commits while Connect is down
    sleep 1
    close_session 7; close_session 8
    restart_connect
    verify_cycle cp5 || return 2
    local produced
    produced="$(order_count)"
    [ "$produced" -ge $(( t1n + 1 )) ] || { log "VERIFY FAIL (cp5): produced $produced < $(( t1n + 1 )) — loss"; return 2; }
    return 0
}

# ---------- campaign driver ----------
log "==== #46 crash campaign start: N=$N RUNS=$RUNS scenarios=${SCENARIOS[*]} ===="
FAILED=0
for sc in "${SCENARIOS[@]}"; do
    for run in $(seq 1 "$RUNS"); do
        passed=""
        for try in $(seq 1 "$MAX_TRIES"); do
            log "== $sc run $run/$RUNS try $try =="
            prep_cycle
            set +e
            "scenario_$sc"; rc=$?
            set -e
            stop_counters
            if [ "$rc" = 0 ]; then
                log "PASS: $sc run $run"
                passed=yes; break
            elif [ "$rc" = 2 ]; then
                log "CAMPAIGN FAIL: $sc run $run — verification failure (not a timing miss)"
                FAILED=1; break 3
            fi
            log "  ($sc run $run try $try was a timing miss — retrying)"
        done
        [ -n "$passed" ] || { log "CAMPAIGN FAIL: $sc run $run never hit its crash window in $MAX_TRIES tries"; FAILED=1; break 2; }
    done
done

if [ "$FAILED" = 0 ]; then
    log "==== CAMPAIGN PASS: all scenarios (${SCENARIOS[*]}) x $RUNS consecutive runs, 0 mismatch, 0 loss, duplicates same-_version only ===="
else
    log "==== CAMPAIGN FAIL ===="
    exit 1
fi
