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

Report the script's per-repository `MERGED` or `SKIPPED` result and final verification. Do not wait for GitHub Actions or CircleCI; mention that new checks may still be running.

If a run partially succeeds, fix the reported conflict or permission problem and rerun the same input. Already-current branches are skipped.
