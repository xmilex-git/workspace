#!/bin/bash
# gate-mc.sh: the memory check — the B3 smoke and the login smoke once more on the optdebug install, the server on
# the system allocator (use_system_malloc=yes in the session conf the smokes apply and restore) with glibc's checks
# on in the server, the broker and the clients. (The wire and B2 smokes: b2/gate-mc.sh.)
WS=/home/cubrid/dev/workspace; S=$WS/.git_ignored_dir/scratch/fold-v2; I=/home/cubrid/optdebug/CUBRID-cas-fold-v2
export MALLOC_CHECK_=3 MALLOC_PERTURB_=165 SESSCONF=$S/b2/foldv2s0-mc.conf
cd $WS || exit 2
before=$(ls /data/core/ 2>/dev/null | wc -l)
TAG=mc bash $S/b3/smoke/smoke_b3.sh $I $S/smoke/db foldv2s0 > $S/b3/gate-b3-mc.log 2>&1; r1=$?
echo "b3 mc rc=$r1 $(/usr/bin/grep -E '^SMOKE' $S/b3/gate-b3-mc.log)"; /usr/bin/grep -E '^CASE [0-9]+ FAIL|^CORES|^ABORT' $S/b3/gate-b3-mc.log | cut -c1-300
TAG=mc bash $S/m647/smoke_m647.sh $I $S/smoke/db foldv2s0 > $S/b3/gate-m647-mc.log 2>&1; r2=$?
echo "m647 mc rc=$r2 $(/usr/bin/grep -E '^SMOKE' $S/b3/gate-m647-mc.log)"
/usr/bin/grep -c "use_system_malloc" $I/conf/cubrid.conf | sed 's/^/use_system_malloc lines left in the install conf: /'
echo "cores before=$before after=$(ls /data/core/ 2>/dev/null | wc -l)"
exit $((r1 + r2))
