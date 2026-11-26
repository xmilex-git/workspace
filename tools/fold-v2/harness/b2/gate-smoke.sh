#!/bin/bash
# gate-smoke.sh <mode> [tag]: the wire smoke (the 51 cases the tracer ran), the B1a smoke (KEEP_CONNECTION=ON), the
# B1b smoke (AUTO) and the B2 smoke, one after another on one install.  ENVX is passed on to the wire and B2 smokes.
m="${1:?mode}"; t="${2:-$m}"; WS=/home/cubrid/dev/workspace; S=$WS/.git_ignored_dir/scratch/fold-v2; I=/home/cubrid/$m/CUBRID-cas-fold-v2
cd $WS || exit 2
TAG=$t bash $S/smoke/smoke.sh $I $S/smoke/db foldv2s0 > $S/b2/gate-wire51-$t.log 2>&1; r1=$?
echo "wire51 $t rc=$r1 pass=$(/usr/bin/grep -c -E '^case[0-9]+ PASS' $S/b2/gate-wire51-$t.log) fail=$(/usr/bin/grep -c -E '^case[0-9]+ FAIL' $S/b2/gate-wire51-$t.log)"
/usr/bin/grep -E '^case[0-9]+ FAIL' $S/b2/gate-wire51-$t.log | cut -c1-200
CONF=$WS/.git_ignored_dir/conf/foldv2s0.conf CUBRID=$I just conf > $S/b2/gate-conf-$t.out 2>&1 || { echo "conf failed"; exit 2; }
bash $S/b1a/smoke/smoke_b1a.sh $I $S/smoke/db foldv2s0 > $S/b2/gate-b1a-$t.log 2>&1; r2=$?
echo "b1a $t rc=$r2"; cut -c1-200 $S/b2/gate-b1a-$t.log | tail -n 8
bash $S/b1b/smoke/smoke_b1b.sh $I $S/smoke/db foldv2s0 > $S/b2/gate-b1b-$t.log 2>&1; r3=$?
echo "b1b $t rc=$r3"; cut -c1-200 $S/b2/gate-b1b-$t.log | tail -n 12
cp $S/b2/confbak/$m/cubrid.conf $S/b2/confbak/$m/cubrid_broker.conf $I/conf/
TAG=$t bash $S/b2/smoke/smoke_b2.sh $I $S/smoke/db foldv2s0 > $S/b2/gate-b2-$t.log 2>&1; r4=$?
echo "b2 $t rc=$r4"; /usr/bin/grep -E "^CASE|^SMOKE|ABORT|new cores" $S/b2/gate-b2-$t.log | cut -c1-200
sha256sum $I/lib/libcubrid.so.11.5
ss -ltn | /usr/bin/grep -E ':(1707|367[0-9][0-9])\b' && echo "LISTENER LEFT"
ls /data/core/ 2>/dev/null | /usr/bin/grep -c "cub_" | sed 's/^/cores named cub_: /'
exit $((r1 + r2 + r3 + r4))
