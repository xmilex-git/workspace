#!/bin/bash
# smoke_b1b.sh <install> <dbdir> <db> — B1b KEEP_CONNECTION=AUTO smoke through a DIRECT_HANDOFF=ON broker with one slot.
# Rewrites the install's cubrid.conf (session conf) and cubrid_broker.conf; restores both on exit.
# Cases: 1 two JDBC clients share the one slot by yields, each keeps its session variable (resume)
#        2 a session inside a transaction is not yielded: the second connect waits for the commit
#        3 raw wire: yield closes the idle connection; wrong password / wrong secret refused; resume answers the
#          same session; a RESET on the control channel yields (then the broker is restarted: the probe's
#          channel took the broker's SESSION_ENDs)
#        4 a kept session nobody resumes expires: a new session (session_state_timeout=60 in the session conf)
#        5 server stop with a kept session and an open one: no core
# ONLY="n m" runs a subset.
set -u
INST="${1:?install}"; DBDIR="${2:?dbdir}"; DB="${3:?db}"
WS=/home/cubrid/dev/workspace
CTL=$WS/.claude/skills/cubrid-server-control/scripts/cubrid-server-ctl.sh
HERE=$WS/.git_ignored_dir/scratch/fold-v2/b1b/smoke
OUT=$HERE/out-$(basename "$(dirname "$INST")")
SESSCONF=$WS/.git_ignored_dir/conf/foldv2s0.conf
PORT=36701
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
cat > "$INST/conf/cubrid_broker.conf" <<EOC
[broker]
MASTER_SHM_ID           =36790
ADMIN_LOG_FILE          =log/broker/cubrid_broker.log

[%B1B]
SERVICE                 =ON
BROKER_PORT             =$PORT
MIN_NUM_APPL_SERVER     =1
MAX_NUM_APPL_SERVER     =1
APPL_SERVER_SHM_ID      =36791
LOG_DIR                 =log/broker/sql_log
ERROR_LOG_DIR           =log/broker/error_log
SQL_LOG                 =OFF
SESSION_TIMEOUT         =300
KEEP_CONNECTION         =AUTO
DIRECT_HANDOFF          =ON
EOC
mkdir -p "$OUT/java"; javac -d "$OUT/java" "$HERE/B1bJdbc.java" > "$OUT/javac.out" 2>&1 || { echo "ABORT: javac"; cat "$OUT/javac.out"; exit 2; }
jdbc() { java -cp "$OUT/java:$JAR" B1bJdbc $PORT "$DB" "$@"; }
cores_before=$(ls /data/core/ 2>/dev/null | grep -c -E "cub_|cub_broker|java")

"$CTL" start "$DB" > "$OUT/start.out" 2>&1 || { echo "ABORT: server start"; cat "$OUT/start.out"; exit 2; }
broker start; sleep 1

if run 1; then
  jdbc resume > "$OUT/c1.out" 2>&1 && ok 1 "$(grep -E 'B connected' "$OUT/c1.out")" || bad 1 "$(tail -3 "$OUT/c1.out" | tr '\n' ' ')"
fi
if run 2; then
  jdbc intran > "$OUT/c2.out" 2>&1 && ok 2 "$(grep -E 'B connected' "$OUT/c2.out")" || bad 2 "$(tail -3 "$OUT/c2.out" | tr '\n' ' ')"
fi
if run 3; then
  ADOPT=$(ls "${CUBRID_TMP:-/tmp}"/*_adopt_"$DB" 2>/dev/null | head -1)
  python3 "$HERE/probe_auto.py" $PORT "$DB" dba "" "$ADOPT" b1b "$JAR" "$OUT/java" > "$OUT/c3.out" 2>&1; r3=$?
  broker stop; broker start; sleep 1
  [ $r3 -eq 0 ] && python3 "$HERE/probe_auto.py" $PORT "$DB" dba "" "$ADOPT" b1b "$JAR" "$OUT/java" "$(sed -n 's/^BLOB //p' "$OUT/c3.out")" >> "$OUT/c3.out" 2>&1 \
    && ok 3 "$(grep -c '^PROBE:' "$OUT/c3.out") probe lines" || bad 3 "$(tail -2 "$OUT/c3.out" | tr '\n' ' ')"
fi
if run 4; then
  jdbc expire 135 > "$OUT/c4.out" 2>&1 && ok 4 "$(grep -E 'after the timeout' "$OUT/c4.out")" || bad 4 "$(tail -3 "$OUT/c4.out" | tr '\n' ' ')"
fi
if run 5; then
  jdbc resume > "$OUT/c5-a.out" 2>&1
  (java -cp "$OUT/java:$JAR" B1bJdbc $PORT "$DB" expire 30 > "$OUT/c5-hold.out" 2>&1) &
  hp=$!
  sleep 5
  t0=$(date +%s); "$CTL" stop "$DB" > "$OUT/c5.stop" 2>&1; src=$?; t1=$(date +%s)
  wait $hp
  if [ $src -eq 0 ] && ! pgrep -u "$(id -u)" -f "cub_server $DB" > /dev/null; then ok 5 "stop with a kept session took $((t1 - t0))s"
  else bad 5 "stop rc=$src"; fi
fi
cores_after=$(ls /data/core/ 2>/dev/null | grep -c -E "cub_|cub_broker|java")
[ "$cores_after" -eq "$cores_before" ] || { echo "CORES: $cores_before -> $cores_after"; FAIL=$((FAIL+1)); }
grep -l -i 'assert' "$INST"/log/server/*.err 2>/dev/null | head -3
echo "SMOKE_B1B: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
