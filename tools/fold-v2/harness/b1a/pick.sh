#!/bin/bash
# pick.sh <sha>...: cherry-pick -n each, dropping unit_tests/** paths; stop at a real conflict
cd ~/dev/cubrid-worktree/cas-fold-v2
for s in "$@"; do
  git cherry-pick -n $s >/dev/null 2>&1
  for f in $(git diff --name-only --diff-filter=U; git diff --cached --name-only) ; do
    case $f in unit_tests/server_compile/*) git rm -q --cached -f "$f" 2>/dev/null; rm -f "$f";; esac
  done
  rm -rf unit_tests/server_compile 2>/dev/null
  u=$(git diff --name-only --diff-filter=U)
  if [ -n "$u" ]; then echo "$s CONFLICT: $u"; exit 1; fi
  echo "$s ok"
done
