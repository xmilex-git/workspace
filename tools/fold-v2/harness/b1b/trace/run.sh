#!/bin/bash
# run.sh <name> <resume|intran|probe|expire> — record one run of the instrumented build (tla1b install) and convert it.
set -u
NAME="${1:?name}"; SC="${2:?scenario}"
WS=/home/cubrid/dev/workspace; S=$WS/.git_ignored_dir/scratch/fold-v2
INST=$HOME/optdebug/CUBRID-cas-fold-v2-tla1b; DBDIR=$S/smoke/db; DB=foldv2s0
CTL=$WS/.claude/skills/cubrid-server-control/scripts/cubrid-server-ctl.sh
T=$S/b1b/trace; PORT=36701
export CUBRID="$INST" CUBRID_DATABASES="$DBDIR" PATH="$INST/bin:$PATH"
[ "$(command -v cubrid)" = "$INST/bin/cubrid" ] || { echo "ABORT: cubrid is $(command -v cubrid)"; exit 2; }
JAR="$INST/jdbc/cubrid_jdbc.jar"
(cd $WS && CONF=$WS/.git_ignored_dir/conf/foldv2s0.conf CUBRID=$INST just conf > $T/$NAME.conf.out 2>&1) || { echo "ABORT: conf"; exit 2; }
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
mkdir -p $T/java; javac -d $T/java $S/b1b/smoke/B1bJdbc.java || exit 2
: > $T/$NAME.raw
export CUBRID_TLATRACE_OUT=$T/$NAME.raw
broker() { cubrid broker "$1" < /dev/null > "$T/$NAME.broker-$1.out" 2>&1; }
"$CTL" start "$DB" > $T/$NAME.start.out 2>&1 || { echo "ABORT: server start"; exit 2; }
broker start; sleep 1
case "$SC" in
  probe)
    ADOPT=$(ls "${CUBRID_TMP:-/tmp}"/*_adopt_"$DB" | head -1)
    python3 $S/b1b/smoke/probe_auto.py $PORT $DB dba "" "$ADOPT" b1b "$JAR" $T/java > $T/$NAME.out 2>&1; rc=$?
    broker stop; broker start; sleep 1
    python3 $S/b1b/smoke/probe_auto.py $PORT $DB dba "" "$ADOPT" b1b "$JAR" $T/java "$(sed -n 's/^BLOB //p' $T/$NAME.out)" >> $T/$NAME.out 2>&1 || rc=1 ;;
  expire) java -cp $T/java:$JAR B1bJdbc $PORT $DB expire 135 > $T/$NAME.out 2>&1; rc=$? ;;
  *) java -cp $T/java:$JAR B1bJdbc $PORT $DB "$SC" > $T/$NAME.out 2>&1; rc=$? ;;
esac
sleep 1
broker stop
"$CTL" stop "$DB" > $T/$NAME.stop.out 2>&1
unset CUBRID_TLATRACE_OUT
echo "scenario rc=$rc $(tail -1 $T/$NAME.out | cut -c1-100)"
python3 $S/b1b/events.py $T/$NAME.raw $T/$NAME.log 2> $T/$NAME.consts; cat $T/$NAME.consts; echo "events rc=$? raw=$(wc -l < $T/$NAME.raw) log=$(wc -l < $T/$NAME.log)"
