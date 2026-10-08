---
name: cubrid-tc-author
description: Author a CUBRID CTP testcase (sql or shell) for one CBRD issue or engine PR end to end — judge sql / shell / both / out of scope from the fix diff, write the case, prove it on the pre-fix, fix and latest-develop optdebug builds with containerized CTP, open the TC PR with a results table, assign one reviewer, and leave the JIRA comment the outcome calls for. Use when asked to "write a TC", "tc 만들어", "테스트케이스 작성", "add a testcase for CBRD-N / PR #N", or when a wayfinder ticket says to follow the TC authoring skill.
---

# cubrid-tc-author

Input: `CBRD-NNNNN` or an engine PR `#N` (CUBRID/cubrid). Output: one TC PR per issue with a
three-build results table and a reviewer, or a JIRA comment saying why there is no TC.
Everything runs without asking the user. Stop only at a **STOP** line below.

Every step ends with a `Done when` line. Do not start the next step before it holds.
All paths are literal; `<N>` is the CBRD number, `<PR>` the engine PR number.
Run directory for everything that is not the TC itself:
`/home/cubrid/dev/workspace/.git_ignored_dir/scratch/tc-author/CBRD-<N>/` (create it; never /tmp).

## Step 0 — resolve the input and the mode

1. `CBRD-<N>` given: find the engine PR with
   `gh pr list -R CUBRID/cubrid --search "CBRD-<N> in:title" --state all --json number,state,mergedAt,mergeCommit,headRefOid,baseRefName`.
   `#<PR>` given: `gh pr view <PR> -R CUBRID/cubrid --json title,state,mergedAt,mergeCommit,headRefOid,baseRefName`;
   the CBRD key is the `[CBRD-N]` prefix of the title.
2. Mode: `mergedAt` non-null → **merged mode**; `state == OPEN` → **open mode**. `--mode merged|open`
   in the arguments overrides. Several PRs for one key: take the merged one; if none is merged, the open one.
3. Write `mode`, `issue`, `pr`, `merge_commit` (merged mode) or `head_sha` + `base = origin/develop merge-base` (open mode)
   into `<rundir>/facts.md`. Every later step reads this file.

Done when `facts.md` holds mode, issue key, PR number, and the sha(s).

## Step 1 — ground (read everything, decide nothing yet)

Follow [references/judge.md](references/judge.md) §1. Produces `<rundir>/ground.md`: issue type,
QA fields, repro SQL, acceptance criteria, attachment list (each read or marked unread with reason),
the fix diff file list, and the spec changes the PR describes.

Done when `ground.md` has every section of the §1 template filled or explicitly "none".

## Step 2 — judge: sql / shell / both / out of scope

Follow [references/judge.md](references/judge.md) §2 (the decision table) and §3 (coverage list).
Every issue, small or large: run §4, the parallel Opus code reading through the Workflow tool,
before writing the coverage list (user, 2026-10-08). The coverage list comes from the code, not only
from the issue's scenarios.

Done when `<rundir>/judge.md` states one verdict with its rule number, and a coverage list whose
every row has a case number or an exclusion reason. Verdict `out of scope` → go to Step 7 (JIRA comment).

## Step 3 — write the case(s)

- sql: [references/sql-rules.md](references/sql-rules.md). shell: [references/shell-rules.md](references/shell-rules.md).
- Placement is decided by the **issue type** (judge.md §2 table), never by version.
- Before saving, run the checklist at the end of the rules file and fix every miss.

Done when the file(s) exist in the TC worktree, the checklist has no miss, and `git status` in that
worktree shows only the new files.

## Step 4 — verify on three builds

Follow [references/verify.md](references/verify.md): obtain the pre-fix, fix and latest-develop
optdebug installs, generate the answer on the fix build, run the case directory on all three in
parallel containers, run the fix build 3 times for determinism, and read verdicts from the runner.
Builds and CTP are delegated to a Workflow worker with the contract text from verify.md §0 pasted verbatim.

Done when `<rundir>/results.md` holds the table (build, sha, OK/NOK per case, cores) and the
expectation column matches the rule in verify.md §5 for every row. A **latest-develop regression**
(verify.md §6) → Step 7 with the regression comment; the PR is not opened.

## Step 5 — commit, push, open the TC PR

Follow [references/pr-and-jira.md](references/pr-and-jira.md) §1–§3 (branch and push per mode,
title, body template, inline design comments).

Done when the PR URL is in `<rundir>/results.md` and the inline review is posted.

## Step 6 — assign one reviewer

Follow [references/pr-and-jira.md](references/pr-and-jira.md) §4. Exactly one reviewer from the
team list: among the members who reviewed the engine PR, the one with the fewest pending review
requests now (engine + both TC repos); nobody from the team reviewed it → the whole team.

Done when `gh pr view <tc-pr> --json reviewRequests` lists the chosen team login. The QA logins
CODEOWNERS requests at PR creation (e.g. kwonhoil, ssihil) stay; never remove them.

## Step 7 — JIRA comment (only three kinds)

Follow [references/pr-and-jira.md](references/pr-and-jira.md) §5. Post only for: out of scope
(performance-only), no TC possible, latest-develop regression. A normal PR gets no JIRA comment.

Done when the comment URL is recorded, or `results.md` says "JIRA comment: none (normal PR)".

## Final report (same turn as the last step)

Print: verdict + rule, TC path(s), the three-build table, PR URL, reviewer, JIRA comment URL or
"none", and anything left undone with the reason. Delete extracted archive installs under
`~/optdebug/CUBRID-cbrd<N>-*` only after the table is written.
