#!/bin/bash
# run.sh <name> <gates|readonly|demote|maint|regrace|resume> — record one run of the instrumented build (tla3 install)
# and convert it.
set -u
NAME="${1:?name}"; SC="${2:?scenario}"
WS=/home/cubrid/dev/workspace; S=$WS/.git_ignored_dir/scratch/fold-v2
INST=$HOME/optdebug/CUBRID-cas-fold-v2-tla3; DBDIR=$S/smoke/db; DB=foldv2s0
CTL=$WS/.claude/skills/cubrid-server-control/scripts/cubrid-server-ctl.sh
T=$S/b3/trace
export CUBRID="$INST" CUBRID_DATABASES="$DBDIR" PATH="$INST/bin:$PATH"
[ "$(command -v cubrid)" = "$INST/bin/cubrid" ] || { echo "ABORT: cubrid is $(command -v cubrid)"; exit 2; }
JAR="$INST/jdbc/cubrid_jdbc.jar"; [ -f "$JAR" ] || JAR=$HOME/release/CUBRID-cas-fold-v2/jdbc/cubrid_jdbc.jar
(cd $WS && CONF=$WS/.git_ignored_dir/conf/foldv2s0.conf CUBRID=$INST just conf > $T/$NAME.conf.out 2>&1) || { echo "ABORT: conf"; exit 2; }
[ "$SC" = readonly ] && echo "read_only=yes" >> "$INST/conf/cubrid.conf"
one() { # name port access_mode shm keep max
  cat <<EOC

[%$1]
SERVICE                 =ON
BROKER_PORT             =$2
MIN_NUM_APPL_SERVER     =$6
MAX_NUM_APPL_SERVER     =$6
APPL_SERVER_SHM_ID      =$4
LOG_DIR                 =log/broker/sql_log
ERROR_LOG_DIR           =log/broker/error_log
SQL_LOG                 =OFF
SESSION_TIMEOUT         =300
KEEP_CONNECTION         =$5
ACCESS_MODE             =$3
DIRECT_HANDOFF          =ON
EOC
}
{ printf '[broker]\nMASTER_SHM_ID           =36790\nADMIN_LOG_FILE          =log/broker/cubrid_broker.log\n'
  one B3RW 36701 RW 36791 ON 4; one B3RO 36702 RO 36792 ON 4; one B3SO 36703 SO 36793 ON 4
  one B3ARO 36704 RO 36794 AUTO 1; one B3ARW 36705 RW 36795 AUTO 1; } > "$INST/conf/cubrid_broker.conf"
mkdir -p $T/java; javac -d $T/java $T/B3Trace.java || exit 2
broker() { cubrid broker "$1" < /dev/null > "$T/$NAME.broker-$1.out" 2>&1; }
"$CTL" start "$DB" > $T/$NAME.fixture-start.out 2>&1 || { echo "ABORT: server start"; exit 2; }
if [ "$SC" != readonly ]; then
  csql -u dba "$DB" -c "DROP TABLE IF EXISTS b3t; DROP TABLE IF EXISTS b3d; DROP SERIAL IF EXISTS b3s; CREATE TABLE b3t (a INT); CREATE SERIAL b3s; INSERT INTO b3t VALUES (0);" > $T/$NAME.fixture.out 2>&1
fi
"$CTL" stop "$DB" > $T/$NAME.fixture-stop.out 2>&1
: > $T/$NAME.raw
export CUBRID_TLATRACE_OUT=$T/$NAME.raw CUBRID_TLA_B3_HB=1
[ "$SC" = regrace ] && export CUBRID_TLA_B3_ADMIT_DELAY_MS=4000
"$CTL" start "$DB" > $T/$NAME.start.out 2>&1 || { echo "ABORT: server start"; exit 2; }
broker start; sleep 1
java -cp $T/java:$JAR B3Trace $DB "$SC" > $T/$NAME.out 2>&1; rc=$?
sleep 1
broker stop
"$CTL" stop "$DB" > $T/$NAME.stop.out 2>&1
unset CUBRID_TLATRACE_OUT CUBRID_TLA_B3_ADMIT_DELAY_MS CUBRID_TLA_B3_HB
echo "scenario rc=$rc"; cut -c1-150 $T/$NAME.out
python3 -I $S/b3/events.py $T/$NAME.raw $T/$NAME.log 2> $T/$NAME.consts; echo "events rc=$? $(cat $T/$NAME.consts) raw=$(wc -l < $T/$NAME.raw) log=$(wc -l < $T/$NAME.log)"
