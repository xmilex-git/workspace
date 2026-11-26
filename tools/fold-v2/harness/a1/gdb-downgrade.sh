#!/bin/bash
# hit count of the deleted-class downgrade (object_domain.c WS_SET_DELETED) while the tracer runs one SQL
# usage: gdb-downgrade.sh <install> <dbdir> <db> <sql> <line>
INST=$1; export CUBRID=$INST CUBRID_DATABASES=$2 PATH=$INST/bin:$PATH; DB=$3
OUT=$(dirname "$0")/gdb-downgrade.out; rm -f $OUT.tracer
cd $2
cub_master >/dev/null 2>&1; sleep 2
MPID=$(for p in $(pgrep -x cub_master); do [ "$(readlink /proc/$p/exe)" = "$(readlink -f $INST/bin/cub_master)" ] && echo $p; done)
echo "master pid=$MPID"
CUBRID_M0_TRACER_SQL="$4" CUBRID_M0_TRACER_OUT=$OUT.tracer timeout 300 gdb -batch -nx \
  -ex 'set pagination off' -ex 'set confirm off' -ex 'handle SIGPIPE SIGUSR1 SIGUSR2 nostop noprint pass' \
  -ex 'set $n=0' -ex 'set breakpoint pending on' \
  -ex "break object_domain.c:$5" -ex 'commands 1
silent
set $n=$n+1
continue
end' \
  -ex 'break csc_deactivate' -ex 'commands 2
printf "DOWNGRADE_HITS=%d\n", $n
kill
quit
end' \
  -ex run --args $INST/bin/cub_server $DB > $OUT.gdb 2>&1; /usr/bin/grep -E "DOWNGRADE_HITS|SIGSEGV|SIGABRT|exited" $OUT.gdb
cat $OUT.tracer
[ -n "$MPID" ] && kill -TERM $MPID
