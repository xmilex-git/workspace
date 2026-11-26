#!/bin/bash
# probe_cap.sh <install> <dbdir> — MAX_NUM_APPL_SERVER=1, two databases behind one broker. A session of db B stays
# open over a broker restart; then a driver connects to db A. Prints how long that connect waited.
set -u
INST="${1:?install}"; DBDIR="${2:?dbdir}"; A=foldv2s0; B=foldv2b
WS=/home/cubrid/dev/workspace
CTL=$WS/.claude/skills/cubrid-server-control/scripts/cubrid-server-ctl.sh
HERE=$WS/.git_ignored_dir/scratch/fold-v2/b4/smoke
OUT=$HERE/out-cap-${TAG:-x}-$(date +%s)
SESSCONF=${SESSCONF:-$WS/.git_ignored_dir/conf/foldv2s0.conf}
mkdir -p "$OUT"
export CUBRID="$INST" CUBRID_DATABASES="$DBDIR" PATH="$INST/bin:$PATH"
[ "$(command -v cubrid)" = "$INST/bin/cubrid" ] || { echo "ABORT: cubrid is $(command -v cubrid)"; exit 2; }
JAR="$INST/jdbc/cubrid_jdbc.jar"; [ -f "$JAR" ] || JAR=$HOME/release/CUBRID-cas-fold-v2/jdbc/cubrid_jdbc.jar
BAK="$OUT/confbak"; mkdir -p "$BAK"; cp "$INST/conf/cubrid.conf" "$INST/conf/cubrid_broker.conf" "$BAK/"
broker() { cubrid broker "$1" < /dev/null > "$OUT/broker-$1.$(date +%s%N)" 2>&1; }
cleanup() { broker stop; "$CTL" stop $A > "$OUT/final.stop" 2>&1; "$CTL" stop $B >> "$OUT/final.stop" 2>&1; cp "$BAK/cubrid.conf" "$BAK/cubrid_broker.conf" "$INST/conf/"; }
trap cleanup EXIT
cat > "$OUT/cubrid_broker.conf" <<EOC
[broker]
MASTER_SHM_ID           =36790
ADMIN_LOG_FILE          =log/broker/cubrid_broker.log

[%B4]
SERVICE                 =ON
BROKER_PORT             =36701
MIN_NUM_APPL_SERVER     =1
MAX_NUM_APPL_SERVER     =1
APPL_SERVER_SHM_ID      =36791
LOG_DIR                 =log/broker/sql_log
ERROR_LOG_DIR           =log/broker/error_log
SQL_LOG                 =OFF
KEEP_CONNECTION         =ON
DIRECT_HANDOFF          =ON
EOC
(cd $WS && CONF=$SESSCONF CUBRID=$INST just conf > "$OUT/conf.out" 2>&1) || { echo "ABORT: conf"; exit 2; }
cp "$OUT/cubrid_broker.conf" "$INST/conf/cubrid_broker.conf"
mkdir -p "$OUT/java"; javac -d "$OUT/java" "$HERE/B4Jdbc.java" > "$OUT/javac.out" 2>&1 || { echo "ABORT: javac"; exit 2; }
jdbc() { d=$1; shift; java -cp "$OUT/java:$JAR" B4Jdbc 36701 "$d" dba "" "$@" 2>&1 | sed -E 's/\[CAS INFO[^]]*\]//; s/ +$//'; }
for d in $A $B; do "$CTL" start $d > "$OUT/start-$d.out" 2>&1 || { echo "ABORT: start $d"; cat "$OUT/start-$d.out"; exit 2; }; done
broker start; sleep 1
jdbc $B "SELECT 1" "SLEEP 20" "SELECT 2" > "$OUT/hold.out" &
hp=$!; sleep 3
[ "${RESTART:-1}" = 1 ] && { broker stop; broker start; sleep 1; }
t0=$(date +%s); jdbc $A "SELECT 1" > "$OUT/one.out"; t1=$(date +%s)
wait $hp
echo "connect to $A while a session of $B is open: waited $((t1 - t0))s: $(tr '\n' '|' < "$OUT/one.out" | cut -c1-120)"
echo "survivor: $(tr '\n' '|' < "$OUT/hold.out" | cut -c1-120)"
echo "OUT $OUT"
