---
name: cubrid-pr-sync
description: Synchronizes a CUBRID engine PR branch and its public and private TC branches with each repository's develop branch. Use when the user provides a CUBRID/cubrid PR number or URL and asks to update, refresh, or sync all three PR branches.
---

# CUBRID 3-repo PR Sync

Update these three branches from one CUBRID engine PR number:

- the engine PR head branch from `CUBRID/cubrid:develop`
- `CUBRID/cubrid-testcases:tc/pr-<number>` from its `develop`
- `CUBRID/cubrid-testcases-private-ex:tc/pr-<number>` from its `develop`

## Run

When the user supplies a PR number or `https://github.com/CUBRID/cubrid/pull/<number>`, run immediately without asking for repository paths or confirmation:

```bash
bash .agents/skills/cubrid-pr-sync/scripts/sync.sh <PR-number-or-URL>
```

The script requires an authenticated `gh` with push access to all three target repositories. It performs a full preflight before writing, pins each `develop` tip, creates merge commits only for branches that are behind, fails fast on the first merge error, and verifies that every target contains its pinned `develop` commit. It never rebases or force-pushes.

The preflight stops on an **overlap**: a file that a behind branch and develop both changed since their merge base. GitHub merges server-side and pushes at once, before anything builds, so an overlap that merges cleanly can still break the build or carry one fix twice (PR 8009 against #7991, 2026-10-01). On an overlap the script prints `OVERLAP` lines, merges nothing, and exits 3; continue with [Overlap](#overlap).

Report the script's per-repository `MERGED` or `SKIPPED` result and final verification; when the engine branch was `MERGED`, say that nothing has built its new head yet. Do not wait for GitHub Actions or CircleCI; mention that new checks may still be running.

If a run partially succeeds, fix the reported conflict or permission problem and rerun the same input. Already-current branches are skipped.

## Overlap

Merge locally against the develop tips the `STOPPED` line prints, and push only what has built and passed:

1. Merge those tips into the local engine PR branch and both local `tc/pr-<number>` branches, resolving any conflict by hand. When the script reported GitHub's 300-file limit instead of file names, list the shared files locally with `comm -12` over `git diff --name-only <merge-base> <branch>` and `git diff --name-only <merge-base> <develop>`.
2. Read develop's change to every overlapping file beside the PR's. A clean merge breaks in two ways: develop changed the signature of a function the PR calls, or both sides fixed one defect differently.
3. List what the PR set out to do and what each develop commit that touched an overlapping file set out to do. Check every item against the merged code and the TCs that cover it, and bring any conflict between the two to the user before building.
4. Build the merged engine on optdebug and gate it with CTP: `TC_REF=<local public-tc merge sha>` for sql and medium, and the local private-ex merge sha for the PR's shell cases.
5. Push all three, check that the develop tips still equal the ones the script printed, and rerun the script: every repository must show `SKIPPED` and `VERIFIED`. If develop moved, the rerun would merge the new commits unbuilt; redo the local merges instead.
