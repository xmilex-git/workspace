#!/bin/bash
# start the server with case 36's tracer env, dump locks while S2's REVOKE waits, stop
INST=${INST:-$HOME/optdebug/CUBRID-cas-fold-v2}; DB=foldv2s0; S=/home/cubrid/dev/workspace/.git_ignored_dir/scratch/fold-v2
CTL=/home/cubrid/dev/workspace/.claude/skills/cubrid-server-control/scripts/cubrid-server-ctl.sh
export CUBRID=$INST CUBRID_DATABASES=$S/smoke/db PATH=$INST/bin:$PATH
(cd $S/smoke/db && csql -S -u dba -c "grant select on dba.a6q to a6u" $DB < /dev/null > /dev/null 2>&1)
/usr/bin/env CUBRID_M0_TRACER_SESSIONS=2 CUBRID_M0_TRACER_USER_S1=A6U CUBRID_M0_TRACER_ISOLATION_S1=RR \
  CUBRID_M0_TRACER_PRE_S1='SELECT COUNT(*) FROM dba.a6o; SELECT SLEEP (6)' CUBRID_M0_TRACER_REEXEC_DELAY_S1=1 \
  CUBRID_M0_TRACER_START_DELAY_S2=9 CUBRID_M0_TRACER_PRE_S2='REVOKE SELECT ON dba.a6q FROM a6u' CUBRID_M0_TRACER_SQL_S2='SELECT 1' \
  CUBRID_M0_TRACER_SQL='SELECT COUNT(*) FROM dba.a6q' CUBRID_M0_TRACER_OUT=$S/a6/lockprobe.out "$CTL" start $DB > $S/a6/lockprobe.start 2>&1
sleep 3
cubrid lockdb -o $S/a6/lockprobe.lockdb $DB > /dev/null 2>&1
sleep 12
"$CTL" stop $DB > $S/a6/lockprobe.stop 2>&1
grep RESULT $S/a6/lockprobe.start $S/a6/lockprobe.stop
