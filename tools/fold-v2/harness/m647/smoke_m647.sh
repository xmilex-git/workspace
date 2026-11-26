#!/bin/bash
# smoke_m647.sh <install> <dbdir> <db> — logins after the develop merge that brought the server's password
# challenge (CBRD-27445), through a DIRECT_HANDOFF=ON broker (fold sessions) and through CS csql (the wire).
# Rewrites the install's cubrid.conf (session conf) and cubrid_broker.conf; restores both on exit.
# Cases: 1 fold login with the right password (a user with a password, one without, dba)
#        2 fold login refused: wrong password, password given to a user without one, unknown user; 10 refused
#          logins leave no transaction behind and the next right login works
#        3 CS csql over the wire: right password in, wrong password refused
#        4 user switch inside a fold session: non-DBA with the right password switches, with a wrong one stays;
#          dba switches without a password
# ONLY="n m" runs a subset.
set -u
INST="${1:?install}"; DBDIR="${2:?dbdir}"; DB="${3:?db}"
WS=/home/cubrid/dev/workspace
CTL=$WS/.claude/skills/cubrid-server-control/scripts/cubrid-server-ctl.sh
HERE=$WS/.git_ignored_dir/scratch/fold-v2/m647
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
MIN_NUM_APPL_SERVER     =2
MAX_NUM_APPL_SERVER     =2
APPL_SERVER_SHM_ID      =36791
LOG_DIR                 =log/broker/sql_log
ERROR_LOG_DIR           =log/broker/error_log
SQL_LOG                 =OFF
SESSION_TIMEOUT         =300
KEEP_CONNECTION         =ON
DIRECT_HANDOFF          =ON
EOC
mkdir -p "$OUT/java"; javac -d "$OUT/java" "$HERE/M647Jdbc.java" > "$OUT/javac.out" 2>&1 || { echo "ABORT: javac"; cat "$OUT/javac.out"; exit 2; }
jdbc() { java -cp "$OUT/java:$JAR" M647Jdbc $PORT "$DB" "$@" 2>&1; }
cores_before=$(ls /data/core/ 2>/dev/null | grep -c -E "cub_|cub_broker|java")

"$CTL" start "$DB" > "$OUT/start.out" 2>&1 || { echo "ABORT: server start"; cat "$OUT/start.out"; exit 2; }
# fixture through CS csql as dba (itself a login over the wire)
csql -u dba "$DB" -c "DROP USER IF EXISTS u647; DROP USER IF EXISTS n647; CREATE USER u647 PASSWORD 'pw647'; CREATE USER n647;" > "$OUT/fixture.out" 2>&1 \
  || { csql -u dba "$DB" -c "CREATE USER u647 PASSWORD 'pw647'" >> "$OUT/fixture.out" 2>&1; csql -u dba "$DB" -c "CREATE USER n647" >> "$OUT/fixture.out" 2>&1; }
broker start; sleep 1
trans() { cubrid tranlist "$DB" < /dev/null > "$OUT/tranlist.$1" 2>&1; grep -c -i "u647" "$OUT/tranlist.$1"; }

if run 1; then
  a=$(jdbc u647 pw647 login | tail -1); b=$(jdbc n647 "" login | tail -1); c=$(jdbc dba "" login | tail -1)
  [ "$a" = "USER=U647" ] && [ "$b" = "USER=N647" ] && [ "$c" = "USER=DBA" ] && ok 1 "$a $b $c" || bad 1 "u647: $a | n647: $b | dba: $c"
fi
if run 2; then
  a=$(jdbc u647 wrong login | tail -1); b=$(jdbc n647 extra login | tail -1); c=$(jdbc nobody647 x login | tail -1); d=$(jdbc u647 "" login | tail -1)
  for i in 1 2 3 4 5 6 7 8 9 10; do jdbc u647 "bad$i" login > /dev/null; done
  left=$(trans left); e=$(jdbc u647 pw647 login | tail -1)
  jdbc u647 pw647 hold > /dev/null & hp=$!; sleep 3; held=$(trans held); wait $hp   # control: an open session is counted
  echo "wrong: $a | extra: $b | unknown: $c | empty: $d | left=$left held=$held | then: $e" > "$OUT/c2.out"
  case "$a|$b|$c|$d" in ERR=*"|"ERR=*"|"ERR=*"|"ERR=*) r=0;; *) r=1;; esac
  [ $r -eq 0 ] && [ "$left" = "0" ] && [ "$held" -ge 1 ] && [ "$e" = "USER=U647" ] && ok 2 "$(cut -c1-300 "$OUT/c2.out")" || bad 2 "$(cut -c1-400 "$OUT/c2.out")"
fi
if run 3; then
  a=$(csql -u u647 -p pw647 "$DB" -c "SELECT CURRENT_USER" 2>&1 | grep -c "U647")
  csql -u u647 -p wrong "$DB" -c "SELECT CURRENT_USER" > "$OUT/c3-wrong.out" 2>&1; rc=$?
  [ "$a" -ge 1 ] && [ $rc -ne 0 ] && ! grep -q "U647" "$OUT/c3-wrong.out" && ok 3 "csql right in; wrong: $(tail -1 "$OUT/c3-wrong.out" | cut -c1-120)" || bad 3 "right=$a wrong rc=$rc $(tail -1 "$OUT/c3-wrong.out" | cut -c1-120)"
fi
if run 4; then
  jdbc n647 "" switch u647 pw647 > "$OUT/c4-right.out"; jdbc n647 "" switch u647 wrong > "$OUT/c4-wrong.out"; jdbc dba "" switch u647 "" > "$OUT/c4-dba.out"
  if grep -q "^SWITCH USER=U647" "$OUT/c4-right.out" && grep -q "^SWITCH ERR=" "$OUT/c4-wrong.out" && grep -q "^AFTER USER=N647" "$OUT/c4-wrong.out" && grep -q "^SWITCH USER=U647" "$OUT/c4-dba.out"; then
    ok 4 "$(grep '^SWITCH ERR' "$OUT/c4-wrong.out" | cut -c1-120)"
  else bad 4 "right: $(tail -1 "$OUT/c4-right.out") | wrong: $(tr '\n' ' ' < "$OUT/c4-wrong.out" | cut -c1-200) | dba: $(tail -1 "$OUT/c4-dba.out")"; fi
fi
cores_after=$(ls /data/core/ 2>/dev/null | grep -c -E "cub_|cub_broker|java")
[ "$cores_after" -eq "$cores_before" ] || { echo "CORES: $cores_before -> $cores_after"; FAIL=$((FAIL+1)); }
grep -l -i 'assert' "$INST"/log/server/*.err 2>/dev/null | head -3
echo "SMOKE_M647: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
