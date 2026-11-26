#!/bin/bash
# gate-smoke.sh <mode>: 51-case tracer smoke then the B1a broker smoke on the merged head
m="${1:?mode}"; WS=/home/cubrid/dev/workspace; S=$WS/.git_ignored_dir/scratch/fold-v2; I=/home/cubrid/$m/CUBRID-cas-fold-v2
cd $WS || exit 2
CONF=$WS/.git_ignored_dir/conf/foldv2s0.conf CUBRID=$I just conf > $S/b1a/gate-conf-$m.out 2>&1 || { echo "conf failed"; exit 2; }
cp $S/smoke/smoke.sh $S/b1a/smoke.sh.run-$m
bash $S/b1a/smoke.sh.run-$m $I $S/smoke/db foldv2s0 > $S/b1a/gate-smoke51-$m.log 2>&1; r1=$?
echo "smoke51 $m rc=$r1 pass=$(/usr/bin/grep -c -E '^case[0-9]+ PASS' $S/b1a/gate-smoke51-$m.log) fail=$(/usr/bin/grep -c -E '^case[0-9]+ FAIL' $S/b1a/gate-smoke51-$m.log) $(tail -1 $S/b1a/gate-smoke51-$m.log | cut -c1-80)"
bash $S/b1a/smoke/smoke_b1a.sh $I $S/smoke/db foldv2s0 > $S/b1a/gate-b1a-$m.log 2>&1; r2=$?
echo "b1a $m rc=$r2"; cat $S/b1a/gate-b1a-$m.log | cut -c1-220
cp $S/b1a/confbak/$m/cubrid.conf $S/b1a/confbak/$m/cubrid_broker.conf $I/conf/
sha256sum $I/lib/libcubrid.so.11.5
ss -ltn | /usr/bin/grep -E ':(1700|36001)\b' && echo "LISTENER LEFT"
