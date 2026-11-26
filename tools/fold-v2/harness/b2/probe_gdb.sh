#!/bin/bash
# probe_gdb.sh: one wire session (autocommit off: select, close, commit) under gdb; prints func_code and con_status
# at the point the dispatcher fills the response's status byte.
cd /home/cubrid/dev/workspace/.git_ignored_dir/scratch/fold-v2/smoke
INST=/home/cubrid/optdebug/CUBRID-cas-fold-v2
rm -f out-dbgg/case1.start
ONLY=1 TAG=dbgg SQLX="SELECT COUNT(*) FROM a6t" EXTRA_ENV="CUBRID_M0_TRACER_START_DELAY=25 CUBRID_M0_TRACER_LINGER=3" bash smoke.sh $INST $PWD/db foldv2s0 > ../b2/dbgg.log 2>&1 &
until /usr/bin/grep -q "^RESULT: OK" out-dbgg/case1.start 2>/dev/null; do sleep 1; done
p=""; for q in $(pgrep -x cub_server); do [ "$(readlink /proc/$q/exe)" = "$(readlink -f $INST/bin/cub_server)" ] && p=$q; done
cat > ../b2/dbgg.gdb <<EOG
set pagination off
set breakpoint pending on
break net_write_stream
commands
silent
printf "WRITE con_status=%d keep=%d autocommit_flag=%d\n", as_info->con_status, as_info->cur_keep_con, as_info->cci_default_autocommit
bt 3
continue
end
continue
EOG
timeout 50 gdb -p $p -batch -x ../b2/dbgg.gdb > ../b2/dbgg.out 2>&1
wait
/usr/bin/grep "^FC=" ../b2/dbgg.out
tail -n 1 ../b2/dbgg.log
