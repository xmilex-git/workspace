#!/bin/bash
# one traced tracer run on the instrumented install: run.sh <name> <sql> [VAR=value ...]
# with DEADLOCK=1 a CS csql session takes the rows in the opposite order so the two sessions deadlock
set -u
NAME=$1; SQL=$2; shift 2
INST=$HOME/optdebug/CUBRID-cas-fold-v2-tla
D=/home/cubrid/dev/workspace/.git_ignored_dir/scratch/fold-v2
OUT=$D/a3/trace; DB=foldv2s0; DBDIR=$D/smoke/db
export CUBRID=$INST CUBRID_DATABASES=$DBDIR PATH=$INST/bin:$PATH
CTL=/home/cubrid/dev/workspace/.claude/skills/cubrid-server-control/scripts/cubrid-server-ctl.sh
rm -f $OUT/$NAME.log $OUT/$NAME.tracer $OUT/$NAME.csql
/usr/bin/env "$@" CUBRID_TLATRACE_OUT=$OUT/$NAME.log CUBRID_M0_TRACER_SQL="$SQL" CUBRID_M0_TRACER_OUT=$OUT/$NAME.tracer \
  $CTL start $DB | grep '^RESULT'
spid=""; for p in $(pgrep -x cub_server); do [ "$(readlink /proc/$p/exe)" = "$(readlink -f $INST/bin/cub_server)" ] && spid=$p; done
if [ "${DEADLOCK:-0}" = 1 ]; then
  (cd $DBDIR && timeout 60 csql -u dba --no-auto-commit -c "UPDATE a3d SET x = 2 WHERE id = 2; SELECT SLEEP (4); UPDATE a3d SET x = 2 WHERE id = 1; COMMIT;" $DB > $OUT/$NAME.csql 2>&1 < /dev/null) &
  cpid=$!
fi
for i in $(seq 1 60); do grep -qE 'M0_TRACER: (SUCCESS|FAIL)' $OUT/$NAME.tracer 2>/dev/null && break; sleep 1; done
[ "${DEADLOCK:-0}" = 1 ] && wait $cpid
$CTL stop $DB | grep '^RESULT'
ls /data/core/core.*.$spid.* 2>/dev/null && echo "CORE pid $spid"
tail -3 $OUT/$NAME.tracer; [ -f $OUT/$NAME.csql ] && tail -3 $OUT/$NAME.csql
echo "events: $(grep -c TLATRACE $OUT/$NAME.log 2>/dev/null)"
