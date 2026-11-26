#!/bin/bash
# probe_lock.sh <tag> <case> <sql> <extra env> <class> <wait seconds>: run one smoke case with the connections left open,
# dump the lock table while they are, and print the holders of <class>.
cd /home/cubrid/dev/workspace/.git_ignored_dir/scratch/fold-v2/smoke
ONLY=$2 TAG=$1 SQLX="$3" EXTRA_ENV="$4" bash smoke.sh /home/cubrid/optdebug/CUBRID-cas-fold-v2 $PWD/db foldv2s0 > ../b2/$1.log 2>&1 &
sleep "$6"
export CUBRID=/home/cubrid/optdebug/CUBRID-cas-fold-v2 CUBRID_DATABASES=$PWD/db PATH=/home/cubrid/optdebug/CUBRID-cas-fold-v2/bin:$PATH
cat out-$1/case$2.out
cubrid lockdb foldv2s0 > ../b2/$1.lockdb 2>&1
/usr/bin/grep -n "Class = $5" -A8 ../b2/$1.lockdb | cut -c1-140
echo "objects locked: $(/usr/bin/grep -c '^OID' ../b2/$1.lockdb)"
wait
tail -n 1 ../b2/$1.log
