#!/bin/bash
# print "<name> <vol|page|slot>" for a6q, a6t: a tracer session holds their class locks while lockdb dumps them
INST=$HOME/optdebug/CUBRID-cas-fold-v2-tla6; D=/home/cubrid/dev/workspace/.git_ignored_dir/scratch/fold-v2; DB=foldv2s0
CTL=/home/cubrid/dev/workspace/.claude/skills/cubrid-server-control/scripts/cubrid-server-ctl.sh
export CUBRID=$INST CUBRID_DATABASES=$D/smoke/db PATH=$INST/bin:$PATH
/usr/bin/env CUBRID_M0_TRACER_PRE='SELECT COUNT(*) FROM dba.a6q, dba.a6t; SELECT SLEEP (4)' CUBRID_M0_TRACER_SQL='SELECT 1' \
  CUBRID_M0_TRACER_OUT=$D/a6/trace/getoid.tracer "$CTL" start $DB > /dev/null 2>&1
sleep 2
cubrid lockdb -o $D/a6/trace/getoid.lockdb $DB > /dev/null 2>&1
sleep 4
"$CTL" stop $DB > /dev/null 2>&1
awk '/^OID =/{gsub(/ /,""); o=substr($0,5)} /Object type: Class = dba\.a6[qt]\./{n=$NF; sub(/^dba\./,"",n); sub(/\.$/,"",n); print n, o}' $D/a6/trace/getoid.lockdb
