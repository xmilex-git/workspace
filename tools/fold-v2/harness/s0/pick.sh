#!/bin/bash
# cherry-pick S0 commits in order, dropping unit_tests/**; stop on a conflict outside unit_tests
cd ~/dev/cubrid-worktree/cas-fold-v2 || exit 1
for c in "$@"; do
  if ! git cherry-pick --no-commit "$c" >/dev/null 2>&1; then
    if git diff --name-only --diff-filter=U | grep -qv '^unit_tests/'; then
      echo "CONFLICT at $c"; git diff --name-only --diff-filter=U; exit 3
    fi
  fi
  git reset -q HEAD -- unit_tests 2>/dev/null; git checkout -q HEAD -- unit_tests 2>/dev/null
  git clean -fdq -- unit_tests/server_compile 2>/dev/null
  git cherry-pick --quit 2>/dev/null
  if git diff --cached --quiet; then echo "EMPTY $c"; continue; fi
  git commit -q -C "$c" && echo "OK $c $(git log -1 --format=%h)"
done
