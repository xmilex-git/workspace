#!/bin/bash
# gate-smoke.sh <mode> [tag]: every smoke of the earlier stages (b2/gate-smoke.sh: wire51, B1a, B1b, B2), the login
# smoke of the CBRD-27445 merge, and the B3 smoke, one after another on one install.
m="${1:?mode}"; t="${2:-b3-$m}"; WS=/home/cubrid/dev/workspace; S=$WS/.git_ignored_dir/scratch/fold-v2; I=/home/cubrid/$m/CUBRID-cas-fold-v2
cd $WS || exit 2
bash $S/b2/gate-smoke.sh $m $t > $S/b3/gate-prev-$t.out 2>&1; r1=$?
/usr/bin/grep -E '^(wire51|b1a|b1b|b2) |FAIL|SMOKE|LISTENER|cores' $S/b3/gate-prev-$t.out | cut -c1-200
TAG=$t bash $S/m647/smoke_m647.sh $I $S/smoke/db foldv2s0 > $S/b3/gate-m647-$t.log 2>&1; r2=$?
echo "m647 $t rc=$r2 $(/usr/bin/grep -E '^SMOKE' $S/b3/gate-m647-$t.log)"; /usr/bin/grep -E '^CASE [0-9]+ FAIL' $S/b3/gate-m647-$t.log | cut -c1-200
TAG=$t bash $S/b3/smoke/smoke_b3.sh $I $S/smoke/db foldv2s0 > $S/b3/gate-b3-$t.log 2>&1; r3=$?
echo "b3 $t rc=$r3 $(/usr/bin/grep -E '^SMOKE' $S/b3/gate-b3-$t.log)"; /usr/bin/grep -E '^CASE [0-9]+ FAIL|^CORES|^ABORT' $S/b3/gate-b3-$t.log | cut -c1-300
sha256sum $I/lib/libcubrid.so.11.5
ss -ltn | /usr/bin/grep -E ':(1707|367[0-9][0-9])\b' && echo "LISTENER LEFT"
exit $((r1 + r2 + r3))
