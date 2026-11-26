#!/bin/bash
# one traced tracer run on the instrumented install: run.sh <name> <sql> <hold-seconds> [VAR=value ...]
# CSQL="<stmts>" in the env runs them through a CS csql session while the server is up (the worker run).
set -u
NAME=$1; SQL=$2; HOLD=$3; shift 3
INST=${INST:-$HOME/optdebug/CUBRID-cas-fold-v2-tla8}
D=/home/cubrid/dev/workspace/.git_ignored_dir/scratch/fold-v2
OUT=$D/a8/trace; DB=foldv2s0; DBDIR=$D/smoke/db
export CUBRID=$INST CUBRID_DATABASES=$DBDIR PATH=$INST/bin:$PATH
CTL=/home/cubrid/dev/workspace/.claude/skills/cubrid-server-control/scripts/cubrid-server-ctl.sh
rm -f $OUT/$NAME.log $OUT/$NAME.tracer $OUT/$NAME.csql
/usr/bin/env "$@" CUBRID_TLATRACE_OUT=$OUT/$NAME.log CUBRID_M0_TRACER_SQL="$SQL" CUBRID_M0_TRACER_OUT=$OUT/$NAME.tracer \
  $CTL start $DB | grep '^RESULT'
spid=""; for p in $(pgrep -x cub_server); do [ "$(readlink /proc/$p/exe)" = "$(readlink -f $INST/bin/cub_server)" ] && spid=$p; done
for i in $(seq 1 60); do grep -qE 'M0_TRACER: (SUCCESS|FAIL)' $OUT/$NAME.tracer 2>/dev/null && break; sleep 1; done
if [ -n "${CSQL:-}" ]; then (cd $DBDIR && timeout 60 csql -u dba -c "$CSQL" $DB > $OUT/$NAME.csql 2>&1 < /dev/null); fi
sleep "$HOLD"
$CTL stop $DB | grep '^RESULT'
ls /data/core/core.*.$spid.* 2>/dev/null && echo "CORE pid $spid"
# a crashed server leaves the install's master (auto_restart may also have revived the server once): stop it by pid
sleep 3
for p in $(pgrep -u $USER -x cub_server); do [ "$(readlink /proc/$p/exe)" = "$(readlink -f $INST/bin/cub_server)" ] && { echo "revived server $p: stop"; $CTL stop $DB | grep '^RESULT'; }; done
for p in $(pgrep -u $USER -x cub_master); do [ "$(readlink /proc/$p/exe)" = "$(readlink -f $INST/bin/cub_master)" ] && { echo "master $p left: SIGTERM"; kill -TERM $p; }; done
grep -E 'M0_TRACER: (SUCCESS|S[0-9]+ FAIL)' $OUT/$NAME.tracer | tail -2 | cut -c1-200
[ -f $OUT/$NAME.csql ] && tail -3 $OUT/$NAME.csql
echo "events: $(grep -c TLATRACE $OUT/$NAME.log 2>/dev/null)"
