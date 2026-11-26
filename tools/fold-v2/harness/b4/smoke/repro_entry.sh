#!/bin/bash
# repro_entry.sh <install> <dbdir> <db> — a fold session's thread gives its thread entry back with the session's
# private LRU index still on it; the next request worker that claims the entry serves a connection without a session
# (optdebug: assert in css_server_task::execute).  Rounds: a fold login that ends, the request workers time out
# (thread_worker_timeout_seconds=4 in the session conf), a CS csql connects.
# Each round: 40 CS csql together (every request-worker core runs a task; 4 s later its worker stops), then 8 fold
# sessions open together (broker MAX 8) and end (their entries go back on top of the free stack), then a CS csql
# connects: the new request worker claims an entry from the top.
set -u
INST="${1:?install}"; DBDIR="${2:?dbdir}"; DB="${3:?db}"
WS=/home/cubrid/dev/workspace
CTL=$WS/.claude/skills/cubrid-server-control/scripts/cubrid-server-ctl.sh
HERE=$WS/.git_ignored_dir/scratch/fold-v2/b4/smoke
M647=$WS/.git_ignored_dir/scratch/fold-v2/m647
OUT=$HERE/out-${TAG:-$(basename "$(dirname "$INST")")}-$(date +%s)
SESSCONF=${SESSCONF:-$WS/.git_ignored_dir/conf/foldv2s0.conf}
PORT=36701
mkdir -p "$OUT"
export CUBRID="$INST" CUBRID_DATABASES="$DBDIR" PATH="$INST/bin:$PATH"
[ "$(command -v cubrid)" = "$INST/bin/cubrid" ] || { echo "ABORT: cubrid is $(command -v cubrid)"; exit 2; }
JAR="$INST/jdbc/cubrid_jdbc.jar"; [ -f "$JAR" ] || JAR=$HOME/release/CUBRID-cas-fold-v2/jdbc/cubrid_jdbc.jar
BAK="$OUT/confbak"; mkdir -p "$BAK"; cp "$INST/conf/cubrid.conf" "$INST/conf/cubrid_broker.conf" "$BAK/"
PASS=0; FAIL=0
run() { case " ${ONLY:-$1} " in *" $1 "*) return 0;; esac; return 1; }
ok() { echo "CASE $1 PASS $2"; PASS=$((PASS+1)); }
bad() { echo "CASE $1 FAIL $2"; FAIL=$((FAIL+1)); }
broker() { cubrid broker "$1" < /dev/null > "$OUT/broker-$1.$(date +%s%N)" 2>&1; }
cleanup() {
  broker stop
  "$CTL" stop "$DB" > "$OUT/final.stop" 2>&1
  cp "$BAK/cubrid.conf" "$BAK/cubrid_broker.conf" "$INST/conf/"
}
trap cleanup EXIT

(cd $WS && CONF=$SESSCONF CUBRID=$INST just conf > "$OUT/conf.out" 2>&1) || { echo "ABORT: conf"; exit 2; }
cat > "$INST/conf/cubrid_broker.conf" <<EOC
[broker]
MASTER_SHM_ID           =36790
ADMIN_LOG_FILE          =log/broker/cubrid_broker.log

[%M647]
SERVICE                 =ON
BROKER_PORT             =$PORT
MIN_NUM_APPL_SERVER     =8
MAX_NUM_APPL_SERVER     =8
APPL_SERVER_SHM_ID      =36791
LOG_DIR                 =log/broker/sql_log
ERROR_LOG_DIR           =log/broker/error_log
SQL_LOG                 =OFF
SESSION_TIMEOUT         =300
KEEP_CONNECTION         =ON
DIRECT_HANDOFF          =ON
EOC
mkdir -p "$OUT/java"; javac -d "$OUT/java" "$M647/M647Jdbc.java" > "$OUT/javac.out" 2>&1 || { echo "ABORT: javac"; cat "$OUT/javac.out"; exit 2; }
jdbc() { java -cp "$OUT/java:$JAR" M647Jdbc $PORT "$DB" "$@" 2>&1; }
cores_before=$(ls /data/core/ 2>/dev/null | grep -c -E "cub_|cub_broker|java")

"$CTL" start "$DB" > "$OUT/start.out" 2>&1 || { echo "ABORT: server start"; cat "$OUT/start.out"; exit 2; }
# fixture through CS csql as dba (itself a login over the wire)
csql -u dba "$DB" -c "DROP USER IF EXISTS u647; DROP USER IF EXISTS n647; CREATE USER u647 PASSWORD 'pw647'; CREATE USER n647;" > "$OUT/fixture.out" 2>&1 \
  || { csql -u dba "$DB" -c "CREATE USER u647 PASSWORD 'pw647'" >> "$OUT/fixture.out" 2>&1; csql -u dba "$DB" -c "CREATE USER n647" >> "$OUT/fixture.out" 2>&1; }
broker start; sleep 1
trans() { cubrid tranlist "$DB" < /dev/null > "$OUT/tranlist.$1" 2>&1; grep -c -i "u647" "$OUT/tranlist.$1"; }

spid=$(pgrep -u "$USER" -f "cub_server $DB" | head -1)
for r in 1 2 3; do
  # every request-worker core serves a wire client once, then its worker times out (4 s) and gives its entry back
  ps=""; for k in $(seq 1 40); do timeout 60 csql -u dba "$DB" -c "SELECT SLEEP(1)" > /dev/null 2>&1 & ps="$ps $!"; done; wait $ps
  sleep 6
  ps=""; for k in 1 2 3 4 5 6 7 8; do jdbc dba "" hold > "$OUT/r$r-hold$k.out" & ps="$ps $!"; done; wait $ps
  held=$(cat "$OUT"/r$r-hold*.out | grep -c "USER=DBA")
  sleep 1
  timeout 60 csql -u dba "$DB" -c "SELECT 1" > "$OUT/r$r-csql.out" 2>&1; rc=$?
  if [ $rc -eq 0 ] && kill -0 "$spid" 2>/dev/null; then ok $r "fold sessions=$held; csql rc=0"; else bad $r "fold sessions=$held; csql rc=$rc $(tail -1 "$OUT/r$r-csql.out" | cut -c1-120)"; break; fi
done
sleep 2; ls /data/core/ | grep -E "\.$spid\." | sed 's/^/CORE /'
cores_after=$(ls /data/core/ 2>/dev/null | grep -c -E "cub_|cub_broker|java")
[ "$cores_after" -eq "$cores_before" ] || { echo "CORES: $cores_before -> $cores_after"; FAIL=$((FAIL+1)); }
grep -l -i 'assert' "$INST"/log/server/*.err 2>/dev/null | head -3
echo "REPRO_ENTRY: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
