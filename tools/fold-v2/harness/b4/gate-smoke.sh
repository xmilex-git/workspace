#!/bin/bash
# gate-smoke.sh <mode> [tag]: every smoke of the earlier stages (b3/gate-smoke.sh: wire51, B1a, B1b, B2, login, B3)
# and the B4 smoke, one after another on one install.
m="${1:?mode}"; t="${2:-b4-$m}"; WS=/home/cubrid/dev/workspace; S=$WS/.git_ignored_dir/scratch/fold-v2; I=/home/cubrid/$m/CUBRID-cas-fold-v2
cd $WS || exit 2
bash $S/b3/gate-smoke.sh $m $t > $S/b4/gate-prev-$t.out 2>&1; r1=$?
/usr/bin/grep -E '^(wire51|b1a|b1b|b2|m647|b3) |FAIL|LISTENER|cores' $S/b4/gate-prev-$t.out | cut -c1-220
TAG=$t bash $S/b4/smoke/smoke_b4.sh $I $S/b4/db > $S/b4/gate-b4-$t.log 2>&1; r2=$?
echo "b4 $t rc=$r2 $(/usr/bin/grep -E '^SMOKE' $S/b4/gate-b4-$t.log)"; /usr/bin/grep -E '^CASE [0-9]+ FAIL|^CORES|^ABORT|^INFO' $S/b4/gate-b4-$t.log | cut -c1-300
sha256sum $I/lib/libcubrid.so.11.5
ss -ltn | /usr/bin/grep -E ':(1707|367[0-9][0-9])\b' && echo "LISTENER LEFT"
exit $((r1 + r2))
