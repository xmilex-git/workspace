---
name: cubrid-pr-sync
description: Synchronizes a CUBRID engine PR branch and its public and private TC branches with each repository's develop branch. Use when the user provides a CUBRID/cubrid PR number or URL and asks to update, refresh, or sync all three PR branches.
---

# CUBRID 3-repo PR Sync

Update these three branches from one CUBRID engine PR number:

- the engine PR head branch from `CUBRID/cubrid:develop`
- `CUBRID/cubrid-testcases:tc/pr-<number>` from its `develop`
- `CUBRID/cubrid-testcases-private-ex:tc/pr-<number>` from its `develop`

Terms: **sync** = this three-repo merge of each develop into the PR's three branches; **OVERLAP** = a file that a behind branch and its develop both changed since their merge base (the script stops, exit 3); **intent check** = listing what the PR and each overlapping develop commit set out to do and checking every item against the merged code. The syncs behind every `(P<n>)` are in `PITFALLS.md`.

## Run

Develop content reaches a PR only through this three-repo sync — never `git merge origin/develop` into one of the three branches alone; a single-repo merge that already exists is dropped (stash, reset to the remote tip, sync, fast-forward, pop), and before the sync the engine side is checked with `git merge-tree --write-tree HEAD origin/develop`, knowing that a clean merge-tree does not prove the merged head builds. (P1)

When the user supplies a PR number or `https://github.com/CUBRID/cubrid/pull/<number>`, run immediately without asking for repository paths or confirmation:

```bash
bash .agents/skills/cubrid-pr-sync/scripts/sync.sh <PR-number-or-URL>
```

The script requires an authenticated `gh` with push access to all three target repositories. It performs a full preflight before writing, pins each `develop` tip, creates merge commits only for branches that are behind, fails fast on the first merge error, and verifies that every target contains its pinned `develop` commit. It never rebases or force-pushes.

The preflight stops on an **overlap**: a file that a behind branch and develop both changed since their merge base. GitHub merges server-side and pushes at once, before anything builds, so an overlap that merges cleanly can still break the build or carry one fix twice (PR 8009 against #7991, 2026-10-01). On an overlap the script prints `OVERLAP` lines, merges nothing, and exits 3; continue with [Overlap](#overlap).

Report the script's per-repository `MERGED` or `SKIPPED` result and final verification; when the engine branch was `MERGED`, say that nothing has built its new head yet. Do not wait for GitHub Actions or CircleCI; mention that new checks may still be running.

If a run partially succeeds, fix the reported conflict or permission problem and rerun the same input. Already-current branches are skipped.

An engine PR at `mergeStateStatus: BLOCKED` with an approved review and a `Check TC PRs` FAILURE titled "TC changes are not on TC develop yet" is the TC Merge Gate's 15-minute `resweep` posting into another check suite on the same head — a later gate success lands elsewhere and never clears it; the fix is moving the head (any push, for example this sync's merge), and after an engine PR close/reopen the recreated empty draft TC PRs block the gate until they are closed and the failed gate job is re-run. (P4)

## Overlap

Merge locally against the develop tips the `STOPPED` line prints, and push only what has built and passed:

1. Merge those tips into the local engine PR branch and both local `tc/pr-<number>` branches, resolving any conflict by hand. When the script reported GitHub's 300-file limit instead of file names, list the shared files locally with `comm -12` over `git diff --name-only <merge-base> <branch>` and `git diff --name-only <merge-base> <develop>`.
2. Read develop's change to every overlapping file beside the PR's. A clean merge breaks in two ways: develop changed the signature of a function the PR calls, or both sides fixed one defect differently.
3. List what the PR set out to do and what each develop commit that touched an overlapping file set out to do. Check every item against the merged code and the TCs that cover it, and bring any conflict between the two to the user before building.
4. Build the merged engine on optdebug and gate it with CTP: `TC_REF=<local public-tc merge sha>` for sql and medium, and the local private-ex merge sha for the PR's shell cases (delegated per the `cubrid-build` and `ctp-run` skills). When the user's request already includes `/run all`, an OVERLAP is handled with the local merges, conflict resolution, the intent check and `-fsyntax-only` of the changed TUs (optdebug and release compile commands) only — then confirm the develop tips are unchanged, push all three, rerun the script (SKIPPED/VERIFIED), post `/run all`, and read the CI run; without a `/run all` ask, the local optdebug build and CTP gate of step 4 apply. (P2)
5. Push all three, check that the develop tips still equal the ones the script printed, and rerun the script: every repository must show `SKIPPED` and `VERIFIED`. If develop moved, the rerun would merge the new commits unbuilt; redo the local merges instead.
6. When the engine merge conflicts or the engine branch carries unpushed local commits, all three merges are done locally against develop tips pinned once (engine conflicts by hand; each TC repo's develop into its local `tc/pr-<N>`), the gate runs with `TC_REF=<local merge sha>` (the runner resolves local commits), all three are pushed, and the script runs only to verify (every repo SKIPPED/VERIFIED); if develop moved after the pin, the local merges are redone rather than letting the script merge new commits unbuilt. (P3)
