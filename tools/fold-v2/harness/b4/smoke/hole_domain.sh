#!/bin/bash
# hole_domain.sh <install> <dbdir> <db> — a session caches a domain holding a class MOP of its workspace, ends, and
# later sessions resolve the same domains. Prints the server's liveness and new cores.
set -u
INST="${1:?install}"; DBDIR="${2:?dbdir}"; DB="${3:?db}"
WS=/home/cubrid/dev/workspace
CTL=$WS/.claude/skills/cubrid-server-control/scripts/cubrid-server-ctl.sh
HERE=$WS/.git_ignored_dir/scratch/fold-v2/b4/smoke
OUT=$HERE/out-hole-${TAG:-x}-$(date +%s)
SESSCONF=${SESSCONF:-$WS/.git_ignored_dir/conf/foldv2s0.conf}
mkdir -p "$OUT"
export CUBRID="$INST" CUBRID_DATABASES="$DBDIR" PATH="$INST/bin:$PATH"
[ "$(command -v cubrid)" = "$INST/bin/cubrid" ] || { echo "ABORT: cubrid is $(command -v cubrid)"; exit 2; }
JAR="$INST/jdbc/cubrid_jdbc.jar"; [ -f "$JAR" ] || JAR=$HOME/release/CUBRID-cas-fold-v2/jdbc/cubrid_jdbc.jar
BAK="$OUT/confbak"; mkdir -p "$BAK"; cp "$INST/conf/cubrid.conf" "$INST/conf/cubrid_broker.conf" "$BAK/"
broker() { cubrid broker "$1" < /dev/null > "$OUT/broker-$1.$(date +%s%N)" 2>&1; }
cleanup() { broker stop; "$CTL" stop "$DB" > "$OUT/final.stop" 2>&1; cp "$BAK/cubrid.conf" "$BAK/cubrid_broker.conf" "$INST/conf/"; }
trap cleanup EXIT
cat > "$OUT/cubrid_broker.conf" <<EOC
[broker]
MASTER_SHM_ID           =36790
ADMIN_LOG_FILE          =log/broker/cubrid_broker.log

[%B4]
SERVICE                 =ON
BROKER_PORT             =36701
MIN_NUM_APPL_SERVER     =5
MAX_NUM_APPL_SERVER     =5
APPL_SERVER_SHM_ID      =36791
LOG_DIR                 =log/broker/sql_log
ERROR_LOG_DIR           =log/broker/error_log
SQL_LOG                 =OFF
KEEP_CONNECTION         =ON
DIRECT_HANDOFF          =ON
EOC
(cd $WS && CONF=$SESSCONF CUBRID=$INST just conf > "$OUT/conf.out" 2>&1) || { echo "ABORT: conf"; exit 2; }
[ -n "${EXTRA_CONF:-}" ] && printf '%s\n' "$EXTRA_CONF" >> "$INST/conf/cubrid.conf"
cp "$OUT/cubrid_broker.conf" "$INST/conf/cubrid_broker.conf"
mkdir -p "$OUT/java"; javac -d "$OUT/java" "$HERE/B4Jdbc.java" > "$OUT/javac.out" 2>&1 || { echo "ABORT: javac"; exit 2; }
jdbc() { java -cp "$OUT/java:$JAR" B4Jdbc 36701 "$DB" dba "" "$@" 2>&1 | sed -E 's/\[CAS INFO[^]]*\]//; s/ +$//'; }
cores_before=$(ls /data/core/ 2>/dev/null | grep -c -E "cub_")
"$CTL" start "$DB" > "$OUT/start.out" 2>&1 || { echo "ABORT: server start"; cat "$OUT/start.out"; exit 2; }
spid=$(pgrep -u "$USER" -x cub_server -n)
csql -u dba "$DB" -c "DROP TABLE IF EXISTS b4o; DROP TABLE IF EXISTS b4c; CREATE TABLE b4c (a INT) DONT_REUSE_OID; CREATE TABLE b4o (o b4c, s SET OF b4c, q SEQUENCE OF b4c); INSERT INTO b4c VALUES (1); INSERT INTO b4o (o) SELECT b4c FROM b4c;" > "$OUT/fixture.out" 2>&1
broker start; sleep 1
for i in 1 2 3 4 5 6; do
  jdbc "SELECT o, s, q FROM b4o" "SELECT o.a FROM b4o" "CREATE TABLE b4x$i (o b4c, s SET OF b4c)" "INSERT INTO b4x$i (o) SELECT b4c FROM b4c" "SELECT COUNT(*) FROM b4x$i WHERE o IS NOT NULL" "DROP TABLE b4x$i" "COMMIT" > "$OUT/s$i.out"
  echo "session $i: $(tr '\n' '|' < "$OUT/s$i.out" | cut -c1-300)"
  kill -0 "$spid" 2>/dev/null || { echo "SERVER DIED after session $i"; break; }
done
sleep 2
cores_after=$(ls /data/core/ 2>/dev/null | grep -c -E "cub_")
echo "cores $cores_before -> $cores_after"; ls -t /data/core | head -$((cores_after - cores_before))
/usr/bin/grep -l -E 'CRASH|SIGSEGV|Assertion' "$INST"/log/server/${DB}_*.err 2>/dev/null | tail -2
echo "OUT $OUT"
