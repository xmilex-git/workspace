#!/bin/bash
# For each non-merge commit in origin/develop..TIP, record the first-parent commit (merge or direct) that introduced it.
set -euo pipefail
R=/home/cubrid/dev/cubrid-worktree/develop
TIP=cdb9da11e
OUT=/home/cubrid/dev/workspace/.git_ignored_dir/scratch/fold-v2
cd $R
: > $OUT/raw.tsv
git rev-list --first-parent --reverse origin/develop..$TIP | while read fp; do
  np=$(git rev-list --no-walk --parents $fp | wc -w)
  subj=$(git log -1 --format=%s $fp)
  if [ "$np" -gt 2 ]; then
    for c in $(git rev-list --no-merges --reverse $fp^1..$fp^2 ^origin/develop); do
      echo -e "$c\t${fp:0:10}\tM\t$subj" >> $OUT/raw.tsv
    done
  else
    echo -e "$fp\t${fp:0:10}\tD\t$subj" >> $OUT/raw.tsv
  fi
done
wc -l $OUT/raw.tsv
cut -f1 $OUT/raw.tsv | sort | uniq -d | wc -l
