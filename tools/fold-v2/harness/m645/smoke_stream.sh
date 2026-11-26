#!/bin/bash
# smoke_b1a.sh <install> <dbdir> <db> — B1a direct-handoff smoke through a DIRECT_HANDOFF=ON broker.
# Rewrites the install's cubrid.conf (session conf) and cubrid_broker.conf; restores both on exit.
# Cases: 1 raw-wire probe (connect, health check, cancel, anti-spoof, a real request)
#        2 JDBC basic (DDL, bound DML, commit, out-of-band cancel, reconnect)
#        3 a survivor across a broker restart holds its slot, and its end frees it (MAX_NUM_APPL_SERVER=1)
#        4 a server restart frees the dead sessions' slots
#        5 server stop with an adopted session open: the stop drains it, no core
# ONLY="n m" runs a subset.
set -u
INST="${1:?install}"; DBDIR="${2:?dbdir}"; DB="${3:?db}"
WS=/home/cubrid/dev/workspace
CTL=$WS/.claude/skills/cubrid-server-control/scripts/cubrid-server-ctl.sh
HERE=$WS/.git_ignored_dir/scratch/fold-v2/b1a/smoke
M=$WS/.git_ignored_dir/scratch/fold-v2/m645
OUT=$M/out-stream-$(basename "$(dirname "$INST")")
SESSCONF=$WS/.git_ignored_dir/conf/foldv2s0.conf
PORT=36201
rm -rf "$OUT"; mkdir -p "$OUT"
export CUBRID="$INST" CUBRID_DATABASES="$DBDIR" PATH="$INST/bin:$PATH"
[ "$(command -v cubrid)" = "$INST/bin/cubrid" ] || { echo "ABORT: cubrid is $(command -v cubrid)"; exit 2; }
JAR="$INST/jdbc/cubrid_jdbc.jar"; [ -f "$JAR" ] || JAR=$HOME/release/CUBRID-cas-fold-v2/jdbc/cubrid_jdbc.jar
BAK="$OUT/confbak"; mkdir -p "$BAK"; cp "$INST/conf/cubrid.conf" "$INST/conf/cubrid_broker.conf" "$BAK/"
PASS=0; FAIL=0
run() { case " ${ONLY:-$1} " in *" $1 "*) return 0;; esac; return 1; }
ok() { echo "CASE $1 PASS $2"; PASS=$((PASS+1)); }
bad() { echo "CASE $1 FAIL $2"; FAIL=$((FAIL+1)); }
broker() { BRD_DEBUG_LOG=$OUT/brd.log cubrid broker "$1" < /dev/null > "$OUT/broker-$1.$(date +%s%N)" 2>&1; }
cleanup() {
  broker stop
  "$CTL" stop "$DB" > "$OUT/final.stop" 2>&1
  cp "$BAK/cubrid.conf" "$BAK/cubrid_broker.conf" "$INST/conf/"
}
trap cleanup EXIT

(cd $WS && CONF=$SESSCONF CUBRID=$INST just conf > "$OUT/conf.out" 2>&1) || { echo "ABORT: conf"; exit 2; }
cat > "$INST/conf/cubrid_broker.conf" <<EOF
[broker]
MASTER_SHM_ID           =36290
ADMIN_LOG_FILE          =log/broker/cubrid_broker.log

[%B1A]
SERVICE                 =ON
BROKER_PORT             =$PORT
MIN_NUM_APPL_SERVER     =1
MAX_NUM_APPL_SERVER     =1
APPL_SERVER_SHM_ID      =36291
LOG_DIR                 =log/broker/sql_log
ERROR_LOG_DIR           =log/broker/error_log
SQL_LOG                 =OFF
SESSION_TIMEOUT         =300
KEEP_CONNECTION         =ON
DIRECT_HANDOFF          =ON
EOF
mkdir -p "$OUT/java"; javac -d "$OUT/java" "$HERE/B1aJdbc.java" > "$OUT/javac.out" 2>&1 || { echo "ABORT: javac"; exit 2; }
jdbc() { java -cp "$OUT/java:$JAR" B1aJdbc $PORT "$DB" "$@"; }
cores_before=$(ls /data/core/ 2>/dev/null | grep -c -E "cub_|cub_broker|java")

"$CTL" start "$DB" > "$OUT/start.out" 2>&1 || { echo "ABORT: server start"; cat "$OUT/start.out"; exit 2; }
broker start; sleep 1

python3 "$M/probe_stream.py" $PORT "$DB" dba "" > "$OUT/stream.out" 2>&1 && ok 1 "$(tr '\n' ' ' < "$OUT/stream.out")" || bad 1 "$(tr '\n' ' ' < "$OUT/stream.out")"
cores_after=$(ls /data/core/ 2>/dev/null | grep -c -E "cub_|cub_broker|java")
[ "$cores_after" -eq "$cores_before" ] || { echo "CORES: $cores_before -> $cores_after"; FAIL=$((FAIL+1)); }
grep -l -i 'assert' "$INST"/log/server/*.err 2>/dev/null | head -3
echo "SMOKE_M645_STREAM: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
