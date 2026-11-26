#!/bin/bash
# one traced tracer run on the instrumented install: run.sh <name> <sql> <hold-seconds> [VAR=value ...]
set -u
NAME=$1; SQL=$2; HOLD=$3; shift 3
INST=$HOME/optdebug/CUBRID-cas-fold-v2-tla5
D=/home/cubrid/dev/workspace/.git_ignored_dir/scratch/fold-v2
OUT=$D/a5/trace; DB=foldv2s0; DBDIR=$D/smoke/db
export CUBRID=$INST CUBRID_DATABASES=$DBDIR PATH=$INST/bin:$PATH
CTL=/home/cubrid/dev/workspace/.claude/skills/cubrid-server-control/scripts/cubrid-server-ctl.sh
rm -f $OUT/$NAME.log $OUT/$NAME.tracer
/usr/bin/env "$@" CUBRID_TLATRACE_OUT=$OUT/$NAME.log CUBRID_M0_TRACER_SQL="$SQL" CUBRID_M0_TRACER_OUT=$OUT/$NAME.tracer \
  $CTL start $DB | grep '^RESULT'
spid=""; for p in $(pgrep -x cub_server); do [ "$(readlink /proc/$p/exe)" = "$(readlink -f $INST/bin/cub_server)" ] && spid=$p; done
for i in $(seq 1 60); do grep -qE 'M0_TRACER: (SUCCESS|FAIL)' $OUT/$NAME.tracer 2>/dev/null && break; sleep 1; done
sleep "$HOLD"
$CTL stop $DB | grep '^RESULT'
ls /data/core/core.*.$spid.* 2>/dev/null && echo "CORE pid $spid"
tail -1 $OUT/$NAME.tracer
echo "events: $(grep -c TLATRACE $OUT/$NAME.log 2>/dev/null)"
