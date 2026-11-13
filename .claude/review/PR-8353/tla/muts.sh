#!/bin/bash
cd /home/cubrid/dev/workspace/.git_ignored_dir/scratch/pr8353-tla
for m in nodesc unsigned offset_noclass offset_nodel nonleaf_pnt pagebounds_image guard_conv; do
  sed "s/Mutation = \"none\"/Mutation = \"$m\"/" small.cfg > mut_$m.cfg
  bash tlc.sh mut_$m.cfg mut_$m.out
  echo "$m rc=$? $(/usr/bin/grep -m1 -oE 'Invariant [A-Za-z]+ is violated|No error has been found|Assumption.*false' mut_$m.out)"
done
