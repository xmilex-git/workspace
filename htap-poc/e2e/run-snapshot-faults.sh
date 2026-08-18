#!/usr/bin/env bash
# Online-snapshot fault verification (#64, ADR 0009 D2): four scenarios that
# confirm the write-stop-free initial snapshot (barrier LSA -> RR view -> scan,
# view established strictly after the barrier) converges under faults. CUBRID
# is the oracle — every scenario ends in diff-check.sh reaching 0 mismatch.
#
#   SN1  continuous committed INSERT/UPDATE/DELETE (+ ABORT txns) running from
#        before registration until after streaming handover -> diff-check 0
#   SN2  commits injected INTO the two barrier windows, deterministically via
#        the internal.snapshot.test.pause.{before,after}.barrier.ms hooks:
#        marker A before the barrier capture (pre-fix loss window), marker B
#        between barrier and scan view -> both markers land, diff-check 0
#   SN3  rows DELETEd after the barrier while the RR view still holds them ->
#        snapshot emits the rows, streaming replays the DELETEs, rows are
#        finally absent -> diff-check 0
#   SN4  Connect worker hard-killed mid-snapshot (during the after-barrier
#        pause) -> snapshot reruns on restart and converges -> diff-check 0
#
# Prereqs: infra up, sink registered, connector plugin built from the
# standalone repo (build-connector.sh + podman restart htap-connect),
# htapdb server running. Usage: run-snapshot-faults.sh [sn1 sn2 sn3 sn4]
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONNECT="${CONNECT_URL:-http://localhost:8083}"
CUBRID="${CUBRID:-$HOME/htap-cdc/CUBRID-11.5-htapcdc}"
CUBRID_DATABASES="${CUBRID_DATABASES:-$HOME/htap-cdc/db}"
DB="${DB:-htapdb}"
SOURCE_NAME=cubrid-source-poc

SCRATCH="$HERE/../../.git_ignored_dir/scratch/snapfaults.$$"
mkdir -p "$SCRATCH"
trap 'rm -rf "$SCRATCH"' EXIT

csql_file () { env CUBRID="$CUBRID" CUBRID_DATABASES="$CUBRID_DATABASES" PATH="$CUBRID/bin:$PATH" \
    csql -u dba "$DB" -i "$1" >/dev/null; }
csql_c () { env CUBRID="$CUBRID" CUBRID_DATABASES="$CUBRID_DATABASES" PATH="$CUBRID/bin:$PATH" \
    csql -u dba "$DB" -c "$1"; }
ch () { podman exec htap-clickhouse clickhouse-client --query "$1"; }

T0="$(date -Is)"
mark_logs () { T0="$(date -Is)"; }
connect_logs () { podman logs --since "$T0" htap-connect 2>&1; }
wait_log () { # $1 = extended-regex pattern, $2 = timeout seconds
    local i
    for i in $(seq 1 "$2"); do
        # grep -c, not -q: -q's early exit SIGPIPEs podman under pipefail
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

register_with () { # $@ = extra key=value config overrides
    python3 - "$HERE/cubrid-source.json" "$@" <<'EOF' > "$SCRATCH/cfg.json"
import json, sys
cfg = json.load(open(sys.argv[1]))["config"]
for kv in sys.argv[2:]:
    k, v = kv.split("=", 1)
    cfg[k] = v
print(json.dumps(cfg))
EOF
    local i
    for i in $(seq 1 30); do
        curl -fsS -X PUT -H 'Content-Type: application/json' \
            -d @"$SCRATCH/cfg.json" "$CONNECT/connectors/$SOURCE_NAME/config" >/dev/null && return 0
        sleep 2
    done
    echo "FAIL: connector registration never succeeded" >&2
    return 1
}

reseed () {
    wait_connect_up || return 1
    "$HERE/reset-pipeline.sh" >/dev/null
    csql_file "$HERE/seed-cubrid.sql"
    csql_file "$HERE/seed-bulk.sql"
}

# ---- SN1: continuous committed+aborted DML across the whole snapshot ----
writer_loop () {
    local i=500000
    cat > "$SCRATCH/abort.sql" <<'SQL'
;autocommit off
INSERT INTO t_order VALUES (999999, 'ghost', 9.9900, DATETIME'2026-08-17 00:00:00.000');
UPDATE t_item SET qty = -1 WHERE sku = 'SKU-A';
ROLLBACK;
SQL
    while [ -f "$SCRATCH/writer.on" ]; do
        csql_c "INSERT INTO t_order VALUES ($i, 'writer', $((i % 97)).5000, DATETIME'2026-08-17 01:00:00.000'); \
                UPDATE t_order SET amount = amount + 1 WHERE id = $((100000 + i % 60000)); \
                DELETE FROM t_order WHERE id = $((i - 3)); \
                UPDATE t_item SET qty = qty + 1 WHERE sku = 'SKU-A'" >/dev/null 2>&1 || true
        csql_file "$SCRATCH/abort.sql" || true
        i=$((i + 1))
    done
}

sn1 () {
    echo "==== SN1: snapshot under continuous DML (fault test ①) ===="
    reseed || return 1
    : > "$SCRATCH/writer.on"
    writer_loop & local wpid=$!
    sleep 2                       # writes demonstrably precede registration
    mark_logs
    register_with || return 1
    wait_log "Captured snapshot barrier LSA" 120 || return 1
    wait_log "CUBRID CDC stream" 180 || return 1
    sleep 5                       # writes demonstrably continue past handover
    rm -f "$SCRATCH/writer.on"; wait "$wpid" 2>/dev/null || true
    wait_converged 90 || return 1
    local ghosts
    ghosts="$(csql_c "SELECT COUNT(*) FROM t_order WHERE id = 999999" | grep -oE '^ *[0-9]+ *$' | tr -d ' ' | head -1)"
    ch_ghosts="$(ch "SELECT count() FROM htap.t_order FINAL WHERE id = 999999")"
    [ "${ghosts:-0}" = 0 ] && [ "$ch_ghosts" = 0 ] || { echo "FAIL: aborted ghost row landed (cub=$ghosts ch=$ch_ghosts)" >&2; return 1; }
    echo "SN1 PASS"
}

# ---- SN2: commits injected into the barrier windows (fault test ②) ----
sn2 () {
    echo "==== SN2: commit injection barrier-window (fault test ②) ===="
    reseed || return 1
    mark_logs
    register_with \
        "internal.snapshot.test.pause.before.barrier.ms=8000" \
        "internal.snapshot.test.pause.after.barrier.ms=8000" || return 1
    # window A: metadata RR view already open, barrier not yet captured —
    # pre-fix this commit was in neither snapshot nor stream (the loss window)
    wait_log "TEST PAUSE 8000 ms before barrier capture" 120 || return 1
    csql_c "INSERT INTO t_order VALUES (910001, 'windowA', 1.0000, DATETIME'2026-08-17 02:00:00.000')" >/dev/null
    echo "injected marker 910001 into window A (pre-barrier)"
    # window B: barrier captured, pre-barrier view discarded, scan view not yet open
    wait_log "TEST PAUSE 8000 ms after barrier capture" 60 || return 1
    csql_c "INSERT INTO t_order VALUES (910002, 'windowB', 2.0000, DATETIME'2026-08-17 02:01:00.000')" >/dev/null
    echo "injected marker 910002 into window B (post-barrier, pre-view)"
    wait_log "CUBRID CDC stream" 180 || return 1
    local i a b
    for i in $(seq 1 40); do
        a="$(ch "SELECT count() FROM htap.t_order FINAL WHERE id = 910001")"
        b="$(ch "SELECT count() FROM htap.t_order FINAL WHERE id = 910002")"
        [ "$a" = 1 ] && [ "$b" = 1 ] && break
        sleep 3
    done
    if [ "$a" != 1 ] || [ "$b" != 1 ]; then
        echo "FAIL: barrier-window marker lost (windowA=$a windowB=$b) — loss window exists" >&2
        return 1
    fi
    echo "both barrier-window markers present in ClickHouse"
    wait_converged 90 || return 1
    echo "SN2 PASS"
}

# ---- SN3: DELETE after barrier, row still in the RR view (fault test ③) ----
sn3 () {
    echo "==== SN3: post-barrier DELETE finally erased (fault test ③) ===="
    reseed || return 1
    mark_logs
    register_with || return 1
    wait_log "Captured snapshot barrier LSA" 120 || return 1
    # the scan view is open once the first table export starts; rows deleted
    # from now on are still emitted by the snapshot (RR) and must be erased by
    # the streamed DELETEs
    wait_log "Exporting data from table" 60 || return 1
    csql_c "DELETE FROM t_order WHERE id = 1; DELETE FROM t_order WHERE id = 132768; DELETE FROM t_item WHERE sku = 'SKU-B'" >/dev/null
    echo "deleted t_order ids 1,132768 + t_item SKU-B during the scan"
    wait_log "CUBRID CDC stream" 180 || return 1
    local i n
    for i in $(seq 1 40); do
        n="$(ch "SELECT count() FROM htap.t_order FINAL WHERE id IN (1,132768)")$(ch "SELECT count() FROM htap.t_item FINAL WHERE sku='SKU-B'")"
        [ "$n" = "00" ] && break
        sleep 3
    done
    [ "$n" = "00" ] || { echo "FAIL: post-barrier deleted rows still visible ($n)" >&2; return 1; }
    echo "deleted rows are absent from the canonical views"
    wait_converged 90 || return 1
    echo "SN3 PASS"
}

# ---- SN4: hard kill mid-snapshot, rerun converges (fault test ④) ----
sn4 () {
    echo "==== SN4: worker hard-kill mid-snapshot, rerun (fault test ④) ===="
    reseed || return 1
    mark_logs
    register_with "internal.snapshot.test.pause.after.barrier.ms=20000" || return 1
    wait_log "TEST PAUSE 20000 ms after barrier capture" 120 || return 1
    # delta the rerun must cover, committed after the (doomed) first barrier
    csql_c "INSERT INTO t_order VALUES (920001, 'prekill', 3.0000, DATETIME'2026-08-17 03:00:00.000'); UPDATE t_item SET qty = 777 WHERE sku = 'SKU-A'" >/dev/null
    echo "killing htap-connect mid-snapshot (inside the after-barrier pause)"
    podman restart htap-connect >/dev/null
    wait_connect_up || return 1
    mark_logs
    wait_log "Captured snapshot barrier LSA|Snapshot completed|CUBRID CDC stream" 300 || return 1
    wait_log "CUBRID CDC stream" 300 || return 1
    csql_c "INSERT INTO t_order VALUES (920002, 'postkill', 4.0000, DATETIME'2026-08-17 03:01:00.000')" >/dev/null
    wait_converged 120 || return 1
    echo "SN4 PASS"
}

SCENARIOS=("${@:-sn1 sn2 sn3 sn4}")
FAILED=0
for s in ${SCENARIOS[@]}; do
    "$s" || { echo "SCENARIO $s FAILED" >&2; FAILED=1; break; }
done
[ "$FAILED" = 0 ] && echo "ALL SNAPSHOT FAULT SCENARIOS PASS"
exit "$FAILED"
