#!/bin/bash
# mkdb.sh: recreate the smoke databases the 11-24 disk cleanup removed (smoke/db: foldv2s0; b4/db: foldv2s0 + foldv2b),
# with the optdebug install under the session conf, then restore the install conf.
set -u
WS=/home/cubrid/dev/workspace; S=$WS/.git_ignored_dir/scratch/fold-v2; I=$HOME/optdebug/CUBRID-cas-fold-v2
cd $WS || exit 2
CONF=$WS/.git_ignored_dir/conf/foldv2s0.conf CUBRID=$I just conf > $S/b4/mkdb-conf.out 2>&1 || { echo "conf failed"; exit 2; }
D=$S/smoke/db; [ -e $D/foldv2s0 ] && { echo "exists: $D/foldv2s0"; exit 2; }
mkdir -p $D/foldv2s0 && cd $D/foldv2s0 && CUBRID=$I CUBRID_DATABASES=$D PATH=$I/bin:$PATH cubrid createdb --db-volume-size=128M --log-volume-size=64M foldv2s0 en_US.utf8 < /dev/null > ../createdb.log 2>&1; echo "smoke/db foldv2s0 rc=$?"
D=$S/b4/db; mkdir -p $D/lob && cd $D && for db in foldv2s0 foldv2b; do CUBRID=$I CUBRID_DATABASES=$D PATH=$I/bin:$PATH cubrid createdb --db-volume-size=64M --log-volume-size=64M -L $D/lob $db en_US.utf8 < /dev/null > ../createdb-$db.out 2>&1; echo "b4/db $db rc=$?"; done
cut -c1-90 $S/smoke/db/databases.txt $S/b4/db/databases.txt
cp $S/b2/confbak/optdebug/cubrid.conf $I/conf/cubrid.conf
du -sh $S/smoke/db $S/b4/db
