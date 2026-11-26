#!/bin/bash
# one traced tracer run on the instrumented install: run.sh <name> <traced class OID vol|page|slot (trace/getoid.sh) | -> <sql> [VAR=value ...]
set -u
NAME=$1; CLS=$2; SQL=$3; shift 3
INST=$HOME/optdebug/CUBRID-cas-fold-v2-tla6
D=/home/cubrid/dev/workspace/.git_ignored_dir/scratch/fold-v2
OUT=$D/a6/trace; DB=foldv2s0; DBDIR=$D/smoke/db
export CUBRID=$INST CUBRID_DATABASES=$DBDIR PATH=$INST/bin:$PATH
CTL=/home/cubrid/dev/workspace/.claude/skills/cubrid-server-control/scripts/cubrid-server-ctl.sh
COID=""
if [[ "$CLS" == *"|"* ]]; then COID=$CLS
elif [ "$CLS" != "-" ]; then
  COID=$(cd $DBDIR && csql -S -u dba -l -c "select class_of from _db_class where class_name = '$CLS'" $DB < /dev/null 2>/dev/null \
         | /usr/bin/grep -oE '[0-9]+\|[0-9]+\|[0-9]+' | head -1)
  [ -n "$COID" ] || { echo "ABORT: no OID for $CLS"; exit 2; }
fi
echo "class $CLS oid $COID"
rm -f $OUT/$NAME.log $OUT/$NAME.tracer
/usr/bin/env "$@" CUBRID_TLATRACE_OUT=$OUT/$NAME.log CUBRID_TLATRACE_CLASS="$COID" CUBRID_M0_TRACER_SQL="$SQL" \
  CUBRID_M0_TRACER_OUT=$OUT/$NAME.tracer $CTL start $DB | grep '^RESULT'
spid=""; for p in $(pgrep -x cub_server); do [ "$(readlink /proc/$p/exe)" = "$(readlink -f $INST/bin/cub_server)" ] && spid=$p; done
for i in $(seq 1 60); do grep -qE 'M0_TRACER: (SUCCESS|FAIL [0-9])' $OUT/$NAME.tracer 2>/dev/null && break; sleep 1; done
$CTL stop $DB | grep '^RESULT'
ls /data/core/core.*.$spid.* 2>/dev/null && echo "CORE pid $spid"
tail -1 $OUT/$NAME.tracer
echo "events: $(grep -c TLATRACE $OUT/$NAME.log 2>/dev/null)"
