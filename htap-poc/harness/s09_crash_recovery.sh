#!/usr/bin/env bash
# s09 crash recovery (ticket #44, ADR 0004 premise 2).
#
# Holds a csql session open with uncommitted DML, kill -9's cub_server,
# restarts it (recovery undoes the txn), runs one committed marker txn,
# then extracts the whole window with cdclogdump. The dump answers:
# does the recovery-undone trid ever get an ABORT DCL in the stream?
#
# kill -9 on cub_server is intentional here (the crash IS the scenario);
# every normal start/stop goes through the server-control wrapper.
#
#   CUBRID=$HOME/htap-cdc/CUBRID-11.5-htapcdc \
#   CUBRID_DATABASES=$CUBRID/databases PATH=$CUBRID/bin:$PATH \
#   ./s09_crash_recovery.sh [dbname]
set -euo pipefail

DB="${1:-htapdb}"
: "${CUBRID:?CUBRID env var required (isolated htap install)}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
DUMPDIR="$HERE/../dumps"
SCRATCH="$REPO_ROOT/.git_ignored_dir/scratch/htap-dumps"
DUMP="$HERE/cdclogdump"
SERVER_CTL="$REPO_ROOT/.claude/skills/cubrid-server-control/scripts/cubrid-server-ctl.sh"

[ -x "$DUMP" ] || { echo "ERROR: $DUMP not built — run: make -C $HERE CUBRID=\$CUBRID" >&2; exit 1; }
[ -x "$SERVER_CTL" ] || { echo "ERROR: server-control wrapper not found: $SERVER_CTL" >&2; exit 1; }
mkdir -p "$DUMPDIR" "$SCRATCH"

PID="$(pgrep -f "cub_server ${DB}\$" || true)"
[ -n "$PID" ] || { echo "ERROR: cub_server $DB not running — start it first" >&2; exit 1; }

t0=$(( $(date +%s) - 2 ))
echo "== start_ts=$t0  cub_server pid=$PID"

# Open a csql session, feed the uncommitted DML, and KEEP THE SESSION OPEN
# (fd 3 holds the fifo writer) so the txn is still in flight at kill time.
FIFO="$SCRATCH/s09.fifo"
CSQL_LOG="$SCRATCH/s09.csql.log"
rm -f "$FIFO"; mkfifo "$FIFO"
csql -u dba --no-pager "$DB" < "$FIFO" > "$CSQL_LOG" 2>&1 &
CSQL_PID=$!
exec 3> "$FIFO"
cat "$HERE/scenarios/s09_crash_recovery.sql" >&3
sleep 3   # let the DML reach the server before the crash

echo "== kill -9 cub_server (pid $PID) — simulated crash"
kill -9 "$PID"
sleep 2

exec 3>&-                      # release the dead session
wait "$CSQL_PID" 2>/dev/null || true
rm -f "$FIFO"

echo "== restart (recovery runs here)"
# cub_master may auto-restart cub_server before we do — measured on the first
# run (#44): start then reports "already running" with exit=1. Either way the
# only thing that matters is that recovery ran and the server is up.
if ! "$SERVER_CTL" start "$DB"; then
    pgrep -f "cub_server ${DB}\$" > /dev/null \
        || { echo "ERROR: cub_server $DB not running after start attempt" >&2; exit 1; }
    echo "== cub_master had already auto-restarted the server"
fi

# Post-restart evidence: the crashed txn's rows must be gone (recovery undo),
# and one committed marker txn shows how trids look after restart.
csql -u dba --no-pager -c "SELECT sku FROM t_item WHERE sku LIKE 'SKU-CRASH%' OR sku = 'SKU-POSTCRASH';" "$DB"
csql -u dba --no-pager -c "DELETE FROM t_item WHERE sku = 'SKU-POSTCRASH'; INSERT INTO t_item VALUES ('SKU-POSTCRASH', 903, 9.03);" "$DB"

sleep 2
"$DUMP" -d "$DB" -t "$t0" -i 5 > "$DUMPDIR/s09_crash_recovery.dump"
echo "== dump: $DUMPDIR/s09_crash_recovery.dump ($(grep -c '^ITEM' "$DUMPDIR/s09_crash_recovery.dump" || true) items)"

# The verdict is read off the dump: find the crashed trid's DML items and
# check whether any DCL for that trid follows.
grep -n 'SKU-CRASH\|SKU-POSTCRASH\|DCL' "$DUMPDIR/s09_crash_recovery.dump" || true
echo "S09 DONE"
