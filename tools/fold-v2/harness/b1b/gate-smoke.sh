#!/bin/bash
# gate-smoke.sh <mode>: 51-case tracer smoke, the B1a broker smoke (KEEP_CONNECTION=ON) and the B1b smoke (AUTO)
m="${1:?mode}"; WS=/home/cubrid/dev/workspace; S=$WS/.git_ignored_dir/scratch/fold-v2; I=/home/cubrid/$m/CUBRID-cas-fold-v2
cd $WS || exit 2
CONF=$WS/.git_ignored_dir/conf/foldv2s0.conf CUBRID=$I just conf > $S/b1b/gate-conf-$m.out 2>&1 || { echo "conf failed"; exit 2; }
cp $S/smoke/smoke.sh $S/b1b/smoke.sh.run-$m
bash $S/b1b/smoke.sh.run-$m $I $S/smoke/db foldv2s0 > $S/b1b/gate-smoke51-$m.log 2>&1; r1=$?
echo "smoke51 $m rc=$r1 pass=$(/usr/bin/grep -c -E '^case[0-9]+ PASS' $S/b1b/gate-smoke51-$m.log) fail=$(/usr/bin/grep -c -E '^case[0-9]+ FAIL' $S/b1b/gate-smoke51-$m.log) $(tail -1 $S/b1b/gate-smoke51-$m.log | cut -c1-80)"
bash $S/b1a/smoke/smoke_b1a.sh $I $S/smoke/db foldv2s0 > $S/b1b/gate-b1a-$m.log 2>&1; r2=$?
echo "b1a $m rc=$r2"; cut -c1-220 $S/b1b/gate-b1a-$m.log
bash $S/b1b/smoke/smoke_b1b.sh $I $S/smoke/db foldv2s0 > $S/b1b/gate-b1b-$m.log 2>&1; r3=$?
echo "b1b $m rc=$r3"; cut -c1-220 $S/b1b/gate-b1b-$m.log
cp $S/b1b/confbak/$m/cubrid.conf $S/b1b/confbak/$m/cubrid_broker.conf $I/conf/
sha256sum $I/lib/libcubrid.so.11.5
ss -ltn | /usr/bin/grep -E ':(1707|36701)\b' && echo "LISTENER LEFT"
exit $((r1 + r2 + r3))
