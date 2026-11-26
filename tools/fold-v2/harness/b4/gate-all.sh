#!/bin/bash
# gate-all.sh <tag>: the B4 gate on both installs, then the memory check on optdebug (B4 smoke, login smoke and the
# thread-entry repro with use_system_malloc=yes in the session conf and glibc's checks on).
t="${1:?tag}"; WS=/home/cubrid/dev/workspace; S=$WS/.git_ignored_dir/scratch/fold-v2; I=$HOME/optdebug/CUBRID-cas-fold-v2
cd $WS || exit 2
for m in optdebug release; do
  bash $S/b4/gate-smoke.sh $m $t-$m > $S/b4/gate-$t-$m.out 2>&1; echo "== gate $m rc=$?"; cut -c1-220 $S/b4/gate-$t-$m.out
  TAG=$t-$m bash $S/b4/smoke/repro_entry.sh $HOME/$m/CUBRID-cas-fold-v2 $S/smoke/db foldv2s0 > $S/b4/repro-entry-$t-$m.log 2>&1; echo "repro_entry $m rc=$? $(/usr/bin/grep -E '^REPRO|^CORE' $S/b4/repro-entry-$t-$m.log | tr '\n' ' ')"
done
before=$(ls /data/core | wc -l)
export MALLOC_CHECK_=3 MALLOC_PERTURB_=165 SESSCONF=$S/b4/foldv2s0-mc.conf
TAG=$t-mc bash $S/b4/smoke/smoke_b4.sh $I $S/b4/db > $S/b4/gate-$t-mc.log 2>&1; echo "== mc b4 rc=$? $(/usr/bin/grep -E '^SMOKE' $S/b4/gate-$t-mc.log)"; /usr/bin/grep -E '^CASE [0-9]+ FAIL|^CORES|^ABORT' $S/b4/gate-$t-mc.log | cut -c1-300
TAG=$t-mc bash $S/m647/smoke_m647.sh $I $S/smoke/db foldv2s0 > $S/b4/gate-$t-mc-m647.log 2>&1; echo "mc m647 rc=$? $(/usr/bin/grep -E '^SMOKE|^CORES' $S/b4/gate-$t-mc-m647.log | tr '\n' ' ')"
TAG=$t-mc bash $S/b4/smoke/repro_entry.sh $I $S/smoke/db foldv2s0 > $S/b4/gate-$t-mc-repro.log 2>&1; echo "mc repro_entry rc=$? $(/usr/bin/grep -E '^REPRO|^CORE' $S/b4/gate-$t-mc-repro.log | tr '\n' ' ')"
echo "mc cores $before -> $(ls /data/core | wc -l); use_system_malloc lines left in install conf: $(/usr/bin/grep -c use_system_malloc $I/conf/cubrid.conf)"
ss -ltn | /usr/bin/grep -E ':(1707|367[0-9][0-9])\b' && echo "LISTENER LEFT"
for m in optdebug release; do echo "$m $(sha256sum $HOME/$m/CUBRID-cas-fold-v2/lib/libcubrid.so.11.5 | cut -c1-12)"; done
