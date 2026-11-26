#!/bin/bash
# gate-mc.sh: the memory check — the wire smoke and the B2 smoke once more on the optdebug install, the server on the
# system allocator (use_system_malloc=yes in the session conf the smokes apply and restore) with glibc's checks on
# in the server, csql -S, the broker and the clients.
WS=/home/cubrid/dev/workspace; S=$WS/.git_ignored_dir/scratch/fold-v2; I=/home/cubrid/optdebug/CUBRID-cas-fold-v2
export MALLOC_CHECK_=3 MALLOC_PERTURB_=165 SESSCONF=$S/b2/foldv2s0-mc.conf
cd $WS || exit 2
before=$(ls /data/core/ 2>/dev/null | wc -l)
TAG=mc ENVX="MALLOC_CHECK_=3 MALLOC_PERTURB_=165" bash $S/smoke/smoke.sh $I $S/smoke/db foldv2s0 > $S/b2/gate-wire51-mc.log 2>&1; r1=$?
echo "wire51 mc rc=$r1 pass=$(/usr/bin/grep -c -E '^case[0-9]+ PASS' $S/b2/gate-wire51-mc.log) fail=$(/usr/bin/grep -c -E '^case[0-9]+ FAIL' $S/b2/gate-wire51-mc.log)"
/usr/bin/grep -E '^case[0-9]+ FAIL' $S/b2/gate-wire51-mc.log | cut -c1-200
TAG=mc ENVX="MALLOC_CHECK_=3 MALLOC_PERTURB_=165" bash $S/b2/smoke/smoke_b2.sh $I $S/smoke/db foldv2s0 > $S/b2/gate-b2-mc.log 2>&1; r2=$?
echo "b2 mc rc=$r2"; /usr/bin/grep -E "^CASE|^SMOKE|ABORT" $S/b2/gate-b2-mc.log | cut -c1-160
/usr/bin/grep -c "use_system_malloc" $I/conf/cubrid.conf | sed 's/^/use_system_malloc lines left in the install conf: /'
echo "cores before=$before after=$(ls /data/core/ 2>/dev/null | wc -l)"
exit $((r1 + r2))
