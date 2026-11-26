#!/bin/bash
# run.sh <name> <multi|nosid|restart|faults|noscan|sessions|olddomain> — record one run of the instrumented build (tla4
# install) into trace/<name>.raw.  The token scenarios run both servers, the domain scenarios foldv2s0 only.
set -u
NAME="${1:?name}"; SC="${2:?scenario}"
WS=/home/cubrid/dev/workspace; S=$WS/.git_ignored_dir/scratch/fold-v2
INST=$HOME/optdebug/CUBRID-cas-fold-v2-tla4; DBDIR=$S/b4/db; A=foldv2s0; B=foldv2b
CTL=$WS/.claude/skills/cubrid-server-control/scripts/cubrid-server-ctl.sh
T=$S/b4/trace; H=$S/b4/smoke
export CUBRID="$INST" CUBRID_DATABASES="$DBDIR" PATH="$INST/bin:$PATH"
[ "$(command -v cubrid)" = "$INST/bin/cubrid" ] || { echo "ABORT: cubrid is $(command -v cubrid)"; exit 2; }
JAR="$INST/jdbc/cubrid_jdbc.jar"; [ -f "$JAR" ] || JAR=$HOME/release/CUBRID-cas-fold-v2/jdbc/cubrid_jdbc.jar
(cd $WS && CONF=$WS/.git_ignored_dir/conf/foldv2s0.conf CUBRID=$INST just conf > $T/$NAME.conf.out 2>&1) || { echo "ABORT: conf"; exit 2; }
case $SC in multi|nosid) MAX=2;; restart|noscan) MAX=1;; *) MAX=3;; esac
one() { # name port max keep shm
  cat <<EOC

[%$1]
SERVICE                 =ON
BROKER_PORT             =$2
MIN_NUM_APPL_SERVER     =$3
MAX_NUM_APPL_SERVER     =$3
APPL_SERVER_SHM_ID      =$5
LOG_DIR                 =log/broker/sql_log
ERROR_LOG_DIR           =log/broker/error_log
SQL_LOG                 =OFF
SESSION_TIMEOUT         =300
KEEP_CONNECTION         =$4
EOC
}
{ printf '[broker]\nMASTER_SHM_ID           =36790\nADMIN_LOG_FILE          =log/broker/cubrid_broker.log\n'
  one B4T 36701 $MAX ON 36791
  case $SC in sessions|expire) one B4TA 36702 1 AUTO 36792;; esac; } > "$INST/conf/cubrid_broker.conf"
mkdir -p $T/java; javac -d $T/java $H/B4Jdbc.java $H/B4Cancel.java || exit 2
jdbc() { p=$1; d=$2; shift 2; java ${JOPT:-} -cp "$T/java:$JAR" B4Jdbc "$p" "$d" dba "" "$@" 2>&1 | sed -u -E 's/\[CAS INFO[^]]*\]//; s/,\[SESSION-[0-9]+\]//; s/ +$//'; }
mark() { echo "TLATRACE $(python3 -c 'import time; print(time.monotonic_ns())') 0 $*" >> $T/$NAME.raw; }
broker() { cubrid broker "$1" < /dev/null > "$T/$NAME.broker-$1.out" 2>&1; }
bpid() { pgrep -u "$USER" -f "cub_server $B" | head -1; }
dom() { jdbc 36701 $A "SELECT o.a, s, q FROM b4o" "CREATE TABLE b4x$1 (o b4c, s SET OF b4c)" "INSERT INTO b4x$1 (o) SELECT b4c FROM b4c" "SELECT o.a FROM b4x$1" "DROP TABLE b4x$1" "COMMIT"; }
: > $T/$NAME.raw
export CUBRID_TLATRACE_OUT=$T/$NAME.raw
[ "$SC" = noscan ] && export CUBRID_TLA_B4_NO_SCAN=1
[ "$SC" = olddomain ] && export CUBRID_TLA_B4_OLD_DOMAIN=1
[ "$SC" = nosid ] && export CUBRID_TLA_B4_NO_SID=1
"$CTL" start $A > $T/$NAME.start-a.out 2>&1 || { echo "ABORT: start $A"; exit 2; }
case $SC in multi|nosid|restart|faults|noscan) "$CTL" start $B > $T/$NAME.start-b.out 2>&1 || { echo "ABORT: start $B"; exit 2; };; esac
broker start; sleep 1
{
case $SC in
multi|nosid)
  java -cp "$T/java:$JAR" B4Cancel 36701 $A $B & cp=$!
  sleep 4; JOPT=-Dct=60 jdbc 36701 $A "SELECT 1"
  wait $cp
  jdbc 36701 $A "ROWS SHOW SESSION STATUS" "SELECT SLEEP(8)" > $T/$NAME.victim.out & vp=$!
  sleep 3
  tok=$(awk '$2 == "ROW" {print $3; exit}' $T/$NAME.victim.out); sid=$(awk '$2 == "ROW" {print $8; exit}' $T/$NAME.victim.out)
  python3 $H/forge_cancel.py 36701 "$tok" sid $((sid + 1000)); python3 $H/forge_cancel.py 36701 "$tok" nosid
  wait $vp; cat $T/$NAME.victim.out
  ;;
restart|noscan)
  jdbc 36701 $B "SELECT 1" "SLEEP 15" "SELECT 2" & hp=$!
  sleep 3; broker stop; broker start; sleep 1
  JOPT=-Dct=60 jdbc 36701 $A "SELECT 1"
  wait $hp
  ;;
faults)
  JOPT=-Dct=90 jdbc 36701 $B "SELECT 1" "COMMIT" "SLEEP 40" "SELECT 2" & hp=$!
  sleep 2; sp=$(bpid); kill -STOP $sp; mark XHang db=$B
  JOPT=-Dct=12 jdbc 36701 $B "SELECT 1"
  jdbc 36701 $A "SELECT 1"
  mark XUnhang db=$B; kill -CONT $sp; sleep 2
  jdbc 36701 $B "SELECT 1"
  kill -9 $sp; mark XCrash db=$B; sleep 2
  jdbc 36701 $B "SELECT 1"
  "$CTL" start $B > $T/$NAME.restart-b.out 2>&1
  jdbc 36701 $B "SELECT 1"
  wait $hp
  ;;
sessions)
  dom 1; dom 2
  dom 3 & p3=$!; dom 4; wait $p3
  JOPT=-Dct=90 jdbc 36702 $A "SELECT o.a FROM b4o" "COMMIT" "SLEEP 6" "SELECT o.a FROM b4o" "COMMIT" & ap=$!
  sleep 2; JOPT=-Dct=90 jdbc 36702 $A "SELECT o.a FROM b4o" "COMMIT"
  wait $ap
  JOPT=-Dct=90 jdbc 36702 $A "SELECT o.a FROM b4o" "COMMIT" "SLEEP 80" & kp=$!
  sleep 2; JOPT=-Dct=90 jdbc 36702 $A "SELECT 1" "COMMIT"
  wait $kp
  ;;
expire)
  # a kept session nobody resumes: its client stays silent past session_state_timeout (60 s) and a daemon tick
  JOPT=-Dct=90 jdbc 36702 $A "SELECT o.a FROM b4o" "COMMIT" "SLEEP 150" & kp=$!
  sleep 2; JOPT=-Dct=90 jdbc 36702 $A "SELECT o.a FROM b4o" "COMMIT"
  wait $kp
  ;;
olddomain)
  dom 1; dom 2
  csql -u dba $A -c "SELECT o FROM b4o" > /dev/null 2>&1
  dom 3
  ;;
esac
} > $T/$NAME.out 2>&1
sleep 1
broker stop
"$CTL" stop $A > $T/$NAME.stop.out 2>&1; "$CTL" stop $B >> $T/$NAME.stop.out 2>&1
unset CUBRID_TLATRACE_OUT CUBRID_TLA_B4_NO_SCAN CUBRID_TLA_B4_OLD_DOMAIN CUBRID_TLA_B4_NO_SID
cut -c1-150 $T/$NAME.out | head -30
echo "raw=$(wc -l < $T/$NAME.raw) cores=$(ls /data/core | wc -l)"
