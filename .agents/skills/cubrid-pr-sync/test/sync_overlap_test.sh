#!/usr/bin/env bash
# sync_overlap_test.sh — sync.sh's overlap preflight, offline: a stub `gh` answers every
# API call from a state dir, so nothing reaches GitHub.
#
# Usage: bash sync_overlap_test.sh [<sync.sh>]   (default: this skill's script)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL="$(cd "$HERE/.." && pwd)"
SYNC="${1:-$SKILL/scripts/sync.sh}"
REPO="$(git -C "$SKILL" rev-parse --show-toplevel)"
SCRATCH_BASE="$REPO/.git_ignored_dir/scratch/pr-sync-selftest"
mkdir -p "$SCRATCH_BASE"
SCRATCH="$(mktemp -d "$SCRATCH_BASE/overlap.XXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT
PASS=0; FAIL=0
ok () { PASS=$((PASS + 1)); printf '[PASS] %s\n' "$*"; }
bad () { FAIL=$((FAIL + 1)); printf '[FAIL] %s\n' "$*" >&2; }

BIN="$SCRATCH/bin"
STATE="$SCRATCH/state"
mkdir -p "$BIN"
cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
# Answers sync.sh's `gh api` calls from $STUB_STATE, printing what its --jq would print.
set -u
[ "${1:-}" = api ] || exit 2
shift
method=GET endpoint="" jq="" base=""
while [ $# -gt 0 ]; do
  case "$1" in
    --method) method=$2; shift 2 ;;
    --jq) jq=$2; shift 2 ;;
    -f) case "$2" in base=*) base=${2#base=} ;; esac; shift 2 ;;
    --silent) shift ;;
    *) endpoint=$1; shift ;;
  esac
done
S=$STUB_STATE
key () { printf '%s' "$1" | tr '/' '_'; }
kind=other
case "$endpoint" in
  repos/*/compare/*) if [[ $jq == *behind_by* ]]; then kind=behind; else kind=files; fi ;;
esac
echo "$method $endpoint $kind" >> "$S/calls.log"
case "$endpoint" in
  repos/CUBRID/cubrid/pulls/*)
    cat "$S/pr" ;;
  repos/*/merges)
    repo=${endpoint#repos/}; repo=${repo%/merges}
    echo "merged-$(key "$repo")" > "$S/sha/$(key "$repo")__$(key "$base")" ;;
  repos/*/branches/*)
    rest=${endpoint#repos/}; repo=${rest%%/branches/*}; branch=${rest#*/branches/}
    cat "$S/sha/$(key "$repo")__$(key "$branch")" ;;
  repos/*/compare/*)
    rest=${endpoint#repos/}; repo=${rest%%/compare/*}; range=${rest#*/compare/}
    if [ "$kind" = behind ]; then
      case "${range#*...}" in merged-*) echo 0 ;; *) cat "$S/behind/$(key "$repo")" ;; esac
    else
      [ -e "$S/fail_files" ] && exit 1
      f="$S/files/$(key "$repo")__$(key "$range")"
      if [ -e "$f" ]; then cat "$f"; else echo 0; fi
    fi ;;
  repos/*)
    echo true ;;
  *) exit 2 ;;
esac
STUB
chmod +x "$BIN/gh"

key () { printf '%s' "$1" | tr '/' '_'; }
sha () { echo "$3" > "$STATE/sha/$(key "$1")__$(key "$2")"; }
behind () { echo "$2" > "$STATE/behind/$(key "$1")"; }
# files <repo> <base...head> <name>...: what GitHub lists for that compare
files () { local f="$STATE/files/$(key "$1")__$(key "$2")"; shift 2; { echo $#; printf '%s\n' "$@"; } > "$f"; }

# Every branch behind develop by default, and no file changed on both sides.
setup () {
  rm -rf "$STATE"; mkdir -p "$STATE/sha" "$STATE/behind" "$STATE/files"
  printf 'open\ndevelop\nfork/cubrid\nfeature\nhttps://github.com/CUBRID/cubrid/pull/1\n' > "$STATE/pr"
  sha CUBRID/cubrid develop E_DEV; sha fork/cubrid feature E_TIP
  sha CUBRID/cubrid-testcases develop P_DEV; sha CUBRID/cubrid-testcases tc/pr-1 P_TIP
  sha CUBRID/cubrid-testcases-private-ex develop X_DEV; sha CUBRID/cubrid-testcases-private-ex tc/pr-1 X_TIP
  behind fork/cubrid 6; behind CUBRID/cubrid-testcases 3; behind CUBRID/cubrid-testcases-private-ex 9
  files fork/cubrid E_DEV...E_TIP src/query/query_executor.c src/query/px_scan_task.cpp
  files fork/cubrid E_TIP...E_DEV src/query/memoize.hpp src/query/plan_generation.c
  files CUBRID/cubrid-testcases P_DEV...P_TIP sql/_36_guava/cbrd_1/cases/cbrd_1.sql
  files CUBRID/cubrid-testcases P_TIP...P_DEV sql/_36_guava/cbrd_2/cases/cbrd_2.sql
  files CUBRID/cubrid-testcases-private-ex X_DEV...X_TIP shell/_06/cbrd_1/cases/cbrd_1.sh
  files CUBRID/cubrid-testcases-private-ex X_TIP...X_DEV shell/_25_unstable/x/cases/x.sh
}
run () { PATH="$BIN:$PATH" STUB_STATE="$STATE" bash "$SYNC" 1 > "$SCRATCH/out" 2>&1; rc=$?; }
merges () { grep -c '^POST .*/merges ' "$STATE/calls.log" || true; }

setup; run
if [ "$rc" -eq 0 ] && [ "$(merges)" -eq 3 ] && [ "$(grep -c '^VERIFIED' "$SCRATCH/out")" -eq 3 ]; then
  ok "no overlap: all three branches are merged and verified"
else
  bad "no overlap: rc=$rc merges=$(merges)"; cat "$SCRATCH/out" >&2
fi

setup
files fork/cubrid E_TIP...E_DEV src/query/memoize.hpp src/query/query_executor.c
run
if [ "$rc" -eq 3 ] && [ "$(merges)" -eq 0 ] && grep -q '^OVERLAP  engine' "$SCRATCH/out" \
   && grep -q '^ *src/query/query_executor.c$' "$SCRATCH/out" \
   && ! grep -q 'src/query/memoize.hpp' "$SCRATCH/out"; then
  ok "engine overlap: names only the shared file, merges nothing, exits 3"
else
  bad "engine overlap: rc=$rc merges=$(merges)"; cat "$SCRATCH/out" >&2
fi

setup
printf '300\n' > "$STATE/files/$(key CUBRID/cubrid-testcases)__P_TIP...P_DEV"
run
if [ "$rc" -eq 3 ] && [ "$(merges)" -eq 0 ] && grep -q '^OVERLAP  public-tc .*300+ files' "$SCRATCH/out"; then
  ok "GitHub's 300-file limit counts as an overlap"
else
  bad "300-file limit: rc=$rc merges=$(merges)"; cat "$SCRATCH/out" >&2
fi

setup; touch "$STATE/fail_files"; run
if [ "$rc" -ne 0 ] && [ "$rc" -ne 3 ] && [ "$(merges)" -eq 0 ] && grep -q 'cannot list the files' "$SCRATCH/out"; then
  ok "a failed file listing stops the run before any merge"
else
  bad "failed file listing: rc=$rc merges=$(merges)"; cat "$SCRATCH/out" >&2
fi

setup
behind fork/cubrid 0; behind CUBRID/cubrid-testcases 0; behind CUBRID/cubrid-testcases-private-ex 0
files fork/cubrid E_TIP...E_DEV src/query/query_executor.c
run
if [ "$rc" -eq 0 ] && [ "$(merges)" -eq 0 ] && ! grep -q ' files$' "$STATE/calls.log" \
   && [ "$(grep -c '^SKIPPED' "$SCRATCH/out")" -eq 3 ]; then
  ok "current branches: no overlap check, all SKIPPED"
else
  bad "current branches: rc=$rc merges=$(merges)"; cat "$SCRATCH/out" >&2
fi

printf 'RESULT: %d PASS / %d FAIL\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
