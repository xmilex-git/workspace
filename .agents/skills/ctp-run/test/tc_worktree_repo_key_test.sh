#!/usr/bin/env bash
# tc_worktree_repo_key_test.sh — testcase worktrees are keyed by the suite's repository.
# The cubrid-testcases and cubrid-testcases-private-ex checkouts are both named develop;
# each must keep its own tc/pr-<N> worktree, and a worktree that another clone left at a
# repository's path must be refused, not reset.
#
# Usage: bash tc_worktree_repo_key_test.sh [<ctp_run.sh>]   (default: this skill's runner)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL="$(cd "$HERE/.." && pwd)"
ORCH="${1:-$SKILL/scripts/ctp_run.sh}"
REPO="$(git -C "$SKILL" rev-parse --show-toplevel)"
SCRATCH_BASE="$REPO/.git_ignored_dir/scratch/ctp-run-selftest"
mkdir -p "$SCRATCH_BASE"
SCRATCH="$(mktemp -d "$SCRATCH_BASE/tcwt.XXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT
PASS=0; FAIL=0
ok () { PASS=$((PASS + 1)); printf '[PASS] %s\n' "$*"; }
bad () { FAIL=$((FAIL + 1)); printf '[FAIL] %s\n' "$*" >&2; }

# shellcheck disable=SC1090
. <(sed -n '/^materialize_tc_worktree() {/,/^}/p; /^materialize_tc_worktree_unlocked() {/,/^}/p' "$ORCH")
declare -F materialize_tc_worktree >/dev/null && declare -F materialize_tc_worktree_unlocked >/dev/null \
  || { bad "materialize_tc_worktree functions missing in $ORCH"; exit 1; }
info () { :; }
warn () { :; }
die () { printf 'die: %s\n' "$*" >&2; exit 1; }

G=(git -c user.name=selftest -c user.email=selftest@localhost -c advice.detachedHead=false)

# make_repo <checkout dir> <origin name>: develop and tc/pr-1, pushed to a local bare origin
make_repo () {
  local dir="$1" origin="$SCRATCH/origin/$2.git"
  mkdir -p "$dir"
  "${G[@]}" -C "$dir" init -q -b develop
  echo "$2 develop" > "$dir/file"
  "${G[@]}" -C "$dir" add file && "${G[@]}" -C "$dir" commit -qm develop
  "${G[@]}" -C "$dir" checkout -qb tc/pr-1
  echo "$2 pr-1" > "$dir/file"
  "${G[@]}" -C "$dir" commit -qam pr-1
  "${G[@]}" -C "$dir" checkout -q develop
  git clone -q --bare "$dir" "$origin"
  git -C "$dir" remote add origin "$origin"
}

WT="$SCRATCH/tc-worktrees"
# materialize <suite repository> <checkout> <ref> <name>: under set -e, as in the runner;
# writes "<worktree> <sha>" to $SCRATCH/<name>.out and the failure to <name>.err
materialize () {
  ( set -e
    SUITE_TCREPO="$1"; TC_REF="$3"; TC_REF_SRC="selftest"; TC_SHA=""; TC_WORKTREE=""
    materialize_tc_worktree "$2" "$3" "$WT"
    printf '%s %s\n' "$TC_WORKTREE" "$TC_SHA" ) > "$SCRATCH/$4.out" 2> "$SCRATCH/$4.err"
}

TC_SQL="$SCRATCH/sql/develop"     # same basename, like ~/dev/cubrid-tc-worktree/develop
TC_SHELL="$SCRATCH/shell/develop" # and ~/dev/cubrid-tc-ex-worktree/develop
make_repo "$TC_SQL" cubrid-testcases
make_repo "$TC_SHELL" cubrid-testcases-private-ex
sha_sql="$(git -C "$TC_SQL" rev-parse tc/pr-1)"
sha_shell="$(git -C "$TC_SHELL" rev-parse tc/pr-1)"

# The incident order: the shell repo's worktree first, then a sql run on the same PR ref.
materialize cubrid-testcases-private-ex "$TC_SHELL" tc/pr-1 shell; rc_shell=$?
materialize cubrid-testcases "$TC_SQL" tc/pr-1 sql; rc_sql=$?
if [ "$rc_shell" -eq 0 ] && [ "$rc_sql" -eq 0 ]; then
  ok "both repositories materialize tc/pr-1 under one worktree root"
else
  bad "materialize failed: shell rc=$rc_shell sql rc=$rc_sql: $(cat "$SCRATCH/shell.err" "$SCRATCH/sql.err")"
fi
read -r wt_shell _ < "$SCRATCH/shell.out" || wt_shell=""
read -r wt_sql _ < "$SCRATCH/sql.out" || wt_sql=""
if [ -n "$wt_sql" ] && [ -n "$wt_shell" ] && [ "$wt_sql" != "$wt_shell" ]; then
  ok "each repository has its own worktree ($wt_sql, $wt_shell)"
else
  bad "worktree paths collide or are missing: sql='$wt_sql' shell='$wt_shell'"
fi
if [ "$(git -C "$wt_sql" rev-parse HEAD 2>/dev/null)" = "$sha_sql" ] \
   && [ "$(git -C "$wt_shell" rev-parse HEAD 2>/dev/null)" = "$sha_shell" ]; then
  ok "each worktree is at its own repository's tc/pr-1"
else
  bad "a worktree is not at its repository's tc/pr-1"
fi

materialize cubrid-testcases "$TC_SQL" tc/pr-1 sql2; rc=$?
read -r wt_sql2 _ < "$SCRATCH/sql2.out" || wt_sql2=""
if [ "$rc" -eq 0 ] && [ "$wt_sql2" = "$wt_sql" ]; then
  ok "a second run reuses the repository's worktree"
else
  bad "the second run did not reuse $wt_sql (rc=$rc, got '$wt_sql2'): $(cat "$SCRATCH/sql2.err")"
fi

# A second clone with the same suite repository reaches the same path and must stop there.
TC_CLONE="$SCRATCH/clone/develop"
make_repo "$TC_CLONE" cubrid-testcases-clone
materialize cubrid-testcases "$TC_CLONE" tc/pr-1 clone; rc=$?
if [ "$rc" -ne 0 ] && grep -q 'is not a worktree of' "$SCRATCH/clone.err"; then
  ok "a worktree of another clone at the repository's path is refused"
else
  bad "another clone's worktree was not refused (rc=$rc): $(cat "$SCRATCH/clone.err")"
fi
if [ "$(git -C "$wt_sql" rev-parse HEAD 2>/dev/null)" = "$sha_sql" ]; then
  ok "the refused worktree is left as it was"
else
  bad "the refused worktree was changed"
fi

printf 'RESULT: %d PASS / %d FAIL\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
