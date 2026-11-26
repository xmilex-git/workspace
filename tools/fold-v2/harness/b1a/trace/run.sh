#!/bin/bash
# one traced run on the instrumented install: run.sh <name> <scenario>
#   basic     raw-wire probe (connect, health check, QC cancel valid + bogus, a request) + JDBC basic (cancel), stop
#   survivor  JDBC hold 25, broker restart, JDBC one (waits for the survivor's slot), stop
#   stopopen  JDBC hold 40, server stop with the session open
# Leaves trace/<name>.raw (merged TLATRACE lines) and trace/<name>.log (model events, events.py).
set -u
NAME=$1; SCEN=$2
INST=${INST:-$HOME/optdebug/CUBRID-cas-fold-v2-tla1a}
WS=/home/cubrid/dev/workspace
B=$WS/.git_ignored_dir/scratch/fold-v2/b1a
OUT=$B/trace; DB=foldv2s0; DBDIR=$WS/.git_ignored_dir/scratch/fold-v2/smoke/db
CTL=$WS/.claude/skills/cubrid-server-control/scripts/cubrid-server-ctl.sh
PORT=36201
export CUBRID=$INST CUBRID_DATABASES=$DBDIR PATH=$INST/bin:$PATH CUBRID_TLATRACE_OUT=$OUT/$NAME.raw
rm -f $OUT/$NAME.raw $OUT/$NAME.log $OUT/$NAME.*.out
JAR=$HOME/release/CUBRID-cas-fold-v2/jdbc/cubrid_jdbc.jar
JDIR=$B/smoke/out-optdebug/java
[ -f $JDIR/B1aJdbc.class ] || { mkdir -p $JDIR; javac -d $JDIR $B/smoke/B1aJdbc.java; }
jdbc() { java -cp "$JDIR:$JAR" B1aJdbc $PORT $DB "$@"; }
broker() { cubrid broker "$1" < /dev/null > $OUT/$NAME.broker-$1.out 2>&1; }
cp $INST/conf/cubrid.conf $INST/conf/cubrid_broker.conf $OUT/ 2>/dev/null
(cd $WS && CONF=$WS/.git_ignored_dir/conf/foldv2s0.conf CUBRID=$INST just conf > /dev/null 2>&1)
cp $B/smoke/broker.conf $INST/conf/cubrid_broker.conf
$CTL start $DB | grep '^RESULT'
spid=""; for p in $(pgrep -x cub_server); do [ "$(readlink /proc/$p/exe)" = "$(readlink -f $INST/bin/cub_server)" ] && spid=$p; done
broker start; sleep 1
case $SCEN in
  basic)
    python3 $B/smoke/probe_direct.py $PORT $DB dba "" > $OUT/$NAME.probe.out 2>&1; tail -1 $OUT/$NAME.probe.out
    jdbc basic > $OUT/$NAME.jdbc.out 2>&1; tail -1 $OUT/$NAME.jdbc.out ;;
  survivor)
    jdbc hold 25 > $OUT/$NAME.hold.out 2>&1 & hp=$!
    sleep 4; broker stop; broker start; sleep 1
    t0=$(date +%s); jdbc one > $OUT/$NAME.one.out 2>&1; echo "one waited $(( $(date +%s) - t0 ))s: $(tail -1 $OUT/$NAME.one.out)"
    wait $hp; tail -1 $OUT/$NAME.hold.out ;;
  stopopen)
    jdbc hold 40 > $OUT/$NAME.hold.out 2>&1 & hp=$!
    sleep 4 ;;
esac
sleep 1
$CTL stop $DB | grep '^RESULT'
[ "$SCEN" = stopopen ] && wait $hp
broker stop
ls /data/core/core.*.$spid.* 2>/dev/null && echo "CORE pid $spid"
cp $OUT/cubrid.conf $OUT/cubrid_broker.conf $INST/conf/ 2>/dev/null
python3 $B/events.py $OUT/$NAME.raw $OUT/$NAME.log
echo "events: $(grep -c . $OUT/$NAME.log)"
