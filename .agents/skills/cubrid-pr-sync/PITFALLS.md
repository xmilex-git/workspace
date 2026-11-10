# PITFALLS — the rules in SKILL.md and the syncs that produced them

Each `P<n>` is one rule. The **Rule** line is the exact sentence SKILL.md carries at the step named in
**Applies at**; keep the two byte-identical. **Source** is where the lesson lived before it was folded
in here (auto-memory slugs are deleted once absorbed; kept for traceability only).

Adding a case: one `Case (YYYY-MM-DD):` line under the rule it confirms, in the session that hit it.
A new rule only when no rule fits — then add the sentence to SKILL.md in the same commit.

### P1 — three repos or none
- Rule: Develop content reaches a PR only through this three-repo sync — never `git merge origin/develop` into one of the three branches alone; a single-repo merge that already exists is dropped (stash, reset to the remote tip, sync, fast-forward, pop), and before the sync the engine side is checked with `git merge-tree --write-tree HEAD origin/develop`, knowing that a clean merge-tree does not prove the merged head builds.
- Applies at: Run
- Case (2026-09-29, PR #7866): testcases develop was merged into `tc/pr-7866` alone to pick up `cbrd_26473.answer_cci`; the user: "develop 머지할거면 세 레포 다 머지하는 /cubrid-pr-sync 를 사용해야한다??" The three branches are validated as a set in CI; one repo ahead is engine↔testcases skew (ctp-run P3).
- Case (2026-10-01, PR 8009 against #7991): the pushed merge `0a9e157a3` did not compile against #7991's new `new_memoize_storage (…, bool match_only)` and duplicated #7991's memo renewal; `1fbdbe1c4` fixed it. The user asked for the intent check ("7991 이 하고자 했던 일과 8009가 하고자 하는 일이 전부 해결되는지를 봐야할거같네"), which became the Overlap section.
- Case (2026-11-02, PR 8317 review round): following the general "fetch and rebase before committing" rule, the lead rebased the pushed engine branch onto develop alone and gated that build; the CTP run on the un-synced `tc/pr-8317` gave 69 NOKs that were only develop's new trace and plan text, and pushing would have needed a force-push. The branch was rebuilt as fork head + the new commit, the three develop tips merged locally (P3) and the gate rerun with `TC_REF=<local tc merge sha>`.
- Source: memory:develop-merge-via-pr-sync

### P2 — on OVERLAP, CI gates when the user asked for `/run all`
- Rule: When the user's request already includes `/run all`, an OVERLAP is handled with the local merges, conflict resolution, the intent check and `-fsyntax-only` of the changed TUs (optdebug and release compile commands) only — then confirm the develop tips are unchanged, push all three, rerun the script (SKIPPED/VERIFIED), post `/run all`, and read the CI run; without a `/run all` ask, the local optdebug build and CTP gate of step 4 apply.
- Applies at: Overlap
- Case (2026-10-27, PR 8207 sync #4): the sync stopped on OVERLAP, the local merge was done, and the skill's local optdebug+CTP gate was launched; the user: "어이 로컬 ctp하지말고 /run all로 검증해라" — CI runs the same suites, so the local gate only delayed the push.
- Source: memory:pr-sync-overlap-verify-via-run-all (this rule replaced an unconditional step 4 on 2026-10-28)

### P3 — when the script cannot merge
- Rule: When the engine merge conflicts or the engine branch carries unpushed local commits, all three merges are done locally against develop tips pinned once (engine conflicts by hand; each TC repo's develop into its local `tc/pr-<N>`), the gate runs with `TC_REF=<local merge sha>` (the runner resolves local commits), all three are pushed, and the script runs only to verify (every repo SKIPPED/VERIFIED); if develop moved after the pin, the local merges are redone rather than letting the script merge new commits unbuilt.
- Applies at: Overlap
- Case (#374, PR 8022 against #7866): the engine branch had local commits not yet pushed, so the server-side script could not be used; the three local merges, a `TC_REF=<sha>` gate and a verify-only script run were the path.
- Source: memory:develop-merge-via-pr-sync

### P4 — BLOCKED with green checks is a stale sweep
- Rule: An engine PR at `mergeStateStatus: BLOCKED` with an approved review and a `Check TC PRs` FAILURE titled "TC changes are not on TC develop yet" is the TC Merge Gate's 15-minute `resweep` posting into another check suite on the same head — a later gate success lands elsewhere and never clears it; the fix is moving the head (any push, for example this sync's merge), and after an engine PR close/reopen the recreated empty draft TC PRs block the gate until they are closed and the failed gate job is re-run.
- Applies at: Run
- Case (2026-10-08, #8058): the rollup kept the sweep's FAILURE although the gate workflow had succeeded; a user PAT cannot post check runs, so only a new head cleared it. Close/reopen (`tc-branch-finalize.yml`, `tc-branch-sync.yml`): closing deletes both `tc/pr-<N>` branches and their draft PRs; reopening recreates them from TC develop with new drafts; wait for the finalize run before reopening or the sync skips "branch exists" and the finalize deletes it afterwards; `/run` needs `tc/pr-<N>` to exist but not an open TC PR.
- Source: memory:tc-merge-gate-stale-sweep-check

### P5 — a passed run is left alone; a mismatch moves the TC branch back
- Rule: A PR whose `/run all` or `/run rerun` passed is left as it is and gets no develop sync; when the engine head and a `tc/pr-<N>` branch disagree (the TC branch carries a newer develop's testcases than the engine head), the TC branch is moved back to the develop line the engine head was built on instead of merging develop into all three
- Applies at: Run, before any `/run`
- Case (2026-11-10, #8470): after `/run rerun` was posted, develop had moved 6 commits that overlapped all 11 files of the PR, and the sync script stopped on OVERLAP; merging would have cost a local merge, build and gate of all three repos. The user: "rerun 통과하면 sync 하지말고 그냥 두자. 앞으로도. 만약 엔진 - tc 어긋남이 발생하면 tc 브랜치를 develop 선으로 후퇴시키는 방안으로 앞으로는 처리하자." Moving a pushed TC branch back needs a force-push or a rebuilt branch: confirm the push with the user the first time.
