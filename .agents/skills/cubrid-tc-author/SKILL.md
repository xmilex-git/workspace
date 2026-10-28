---
name: cubrid-tc-author
description: >-
  Author a CUBRID CTP testcase (sql or shell) for one CBRD issue or engine PR end to end — judge sql / shell / both / out of scope from the fix diff, write the case, prove it on the pre-fix, fix and latest-develop optdebug builds with containerized CTP, open the TC PR with a results table, assign one reviewer (only when the engine PR is already merged into develop), and leave the JIRA comment the outcome calls for. Also the yardstick for reviewing another author's TC PR (review mode: judge and pitfalls only, no reviewer, nothing pushed). Use when asked to "write a TC", "tc 만들어", "테스트케이스 작성", "add a testcase for CBRD-N / PR #N", to review a TC PR against these rules, or when a wayfinder ticket says to follow the TC authoring skill.
---

# cubrid-tc-author

Input: `CBRD-NNNNN` or an engine PR `#N` (CUBRID/cubrid); or another author's TC PR to review.
Output: one TC PR per issue with a three-build results table and a reviewer (merged engine PR only),
or a JIRA comment saying why there is no TC; in review mode, a review report and nothing else.
Everything runs without asking the user. Stop only at a **STOP** line below.

Every step ends with a `Done when` line. Do not start the next step before it holds.
All paths are literal; `<N>` is the CBRD number, `<PR>` the engine PR number.
Run directory for everything that is not the TC itself:
`/home/cubrid/dev/workspace/.git_ignored_dir/scratch/tc-author/CBRD-<N>/` (create it; never /tmp).

Terms: **pre / fix / dev** = the three optdebug builds a case is proven on (the commit before the fix, the fix, latest develop); **bot branch** = `tc/pr-<N>`, created by app/cubrid-tc-sync-bot when engine PR N opens, in each testcases repo; **positive control** = the answer line or control probe that proves the server saw the shape the case claims (`key range:` count, `rewritten query`, `parallel workers`, …); **negative control** = a deliberately failing variant proving the case can fail; **three-point run** = the case directory on pre, fix and dev in parallel containers. The rules between steps and the TCs behind them are in `PITFALLS.md` (`(P<n>)` below); the sql form rules with their cases are `references/sql-pitfalls.md`.

## Step 0 — resolve the input and the mode

1. `CBRD-<N>` given: find the engine PR with
   `gh pr list -R CUBRID/cubrid --search "CBRD-<N> in:title" --state all --json number,state,mergedAt,mergeCommit,headRefOid,baseRefName`.
   `#<PR>` given: `gh pr view <PR> -R CUBRID/cubrid --json title,state,mergedAt,mergeCommit,headRefOid,baseRefName`;
   the CBRD key is the `[CBRD-N]` prefix of the title.
2. Mode: `mergedAt` non-null → **merged mode**; `state == OPEN` → **open mode**. `--mode merged|open`
   in the arguments overrides. Several PRs for one key: take the merged one; if none is merged, the open one.
   No engine PR yet because the TC is written while the issue is being fixed (the fix lives on a local
   engine branch) → **open mode** too, with `pr` = pending until the engine PR is opened.
   **TCs made while fixing an issue ride the engine PR's bot branch** (user, 2026-10-11): every new or
   changed TC file — a new case, an existing case or answer the fix changes, another issue's TC that
   gains a case — goes into the `tc/pr-<PR>` branch the bot creates when the engine PR is opened, in
   the repo that holds the file (sql → cubrid-testcases, shell → cubrid-testcases-private-ex). Never a
   후속 TC PR from the fork for such an issue; the 후속 TC PR is only for an issue whose engine PR is
   already merged (merged mode).
   **A TC PR by another author given to review** → **review mode**: Steps 1–3 are the yardstick
   (ground the issue, judge the verdict and coverage, walk the pitfall rules against the PR's files);
   Step 4 only where the review needs runtime evidence. Steps 5–7 never run: no push, no PR, no
   reviewer, no JIRA comment — the output is the review report.
3. Write `mode`, `issue`, `pr`, `merge_commit` (merged mode) or `head_sha` + `base = origin/develop merge-base` (open mode;
   before the engine PR exists, `head_sha` is the local engine branch head) into `<rundir>/facts.md`.
   Every later step reads this file.

Done when `facts.md` holds mode, issue key, PR number, and the sha(s).

## Step 1 — ground (read everything, decide nothing yet)

Follow [references/judge.md](references/judge.md) §1. Produces `<rundir>/ground.md`: issue type,
QA fields, repro SQL, acceptance criteria, attachment list (each read or marked unread with reason),
the fix diff file list, and the spec changes the PR describes.

When a TC convention is in question (placement by issue type, header length, ORDER BY, cleanup, determinism), the QA team's own skills are the source: `git -C ~/dev/cubrid-agent pull` (clone of github.com/tw-kang/cubrid-agent) and read `skills/qa/create-sql/SKILL.md`, `skills/qa/author-testcase/SKILL.md`, `skills/qa/review-testcase/SKILL.md` (the lint our TC PRs face) and `skills/in-progress/create-shell/SKILL.md`; cite them and the CUBRIDQA ticket numbers. (P3)

Done when `ground.md` has every section of the §1 template filled or explicitly "none".

## Step 2 — judge: sql / shell / both / out of scope

Follow [references/judge.md](references/judge.md) §2 (the decision table) and §3 (coverage list).
Every issue, small or large: run §4, the parallel Opus code reading through the Workflow tool,
before writing the coverage list (user, 2026-10-08). The coverage list comes from the code, not only
from the issue's scenarios.

- A re-execution, prologue or cached-program defect is probed through `csql -C` (a CS client) and written as a CTP **shell** case, because a CTP sql case runs through JDBC and `csql -S` does not pack values, so both can pass on a server that returns the previous execution's value. (P1)
- When the fix commit is from 2026-06/07 and a check needs a parallel temp or list scan, probe the fix build first with a throwaway shell probe copied into the TC worktree (then removed) — a check that passes only on latest develop cannot separate pre from fix. (P2)

Done when `<rundir>/judge.md` states one verdict with its rule number, and a coverage list whose
every row has a case number or an exclusion reason. Verdict `out of scope` → go to Step 7 (JIRA comment).

## Step 3 — write the case(s)

- sql: [references/sql-rules.md](references/sql-rules.md) (the form) and
  [references/sql-pitfalls.md](references/sql-pitfalls.md) (seven rules, each with the past cases that
  made it — read before writing). shell: [references/shell-rules.md](references/shell-rules.md).
- Placement is decided by the **issue type** (judge.md §2 table), never by version.
- A check on a traced `fetch:` count compares it with `SHOW EXEC STATISTICS ALL` `data_page_fetches` of a second, trace-off execution of the same plan (`set @collect_exec_stats = 1`; within 0.8..1.25; one csql run cannot give both, because SHOW TRACE / SHOW EXEC STATISTICS restart the watch), and hash-join parallelism is read from the line after `PROBE (`, not from the `HASHJOIN (` line. (P4)
- Before saving, walk the seven pitfall rules against every sql file and write `<rundir>/pitfalls.md`
  (one row per rule per file: `n/a`, `clear` with the answer token or probe as evidence, or `hit →
  case`); then run the checklist at the end of the rules file and fix every miss.

Done when the file(s) exist in the TC worktree, `<rundir>/pitfalls.md` has its 7 rows per sql file
with no open `hit`, the checklist has no miss, and `git status` in that worktree shows only the new files.

## Step 4 — verify on three builds

Follow [references/verify.md](references/verify.md): obtain the pre-fix, fix and latest-develop
optdebug installs, generate the answer on the fix build, run the case directory on all three in
parallel containers, run the fix build 3 times for determinism, and read verdicts from the runner.
Builds and CTP are delegated to a Workflow worker with the contract text from verify.md §0 pasted verbatim.
To prove a shell case records failures, build a negative control without a worktree — `read-tree` into a temporary `GIT_INDEX_FILE`, `hash-object -w` the changed file, `update-index --cacheinfo`, `write-tree`, `commit-tree` — force one check to fail (its expected value +1), never push the commit, run it with `TC_REF=<that sha>`, then `git worktree remove` the runner's tc-worktree for that sha; and count the `.result` lines against the number of `write_ok`/`write_nok` calls (one line per check). (P5)

Done when `<rundir>/results.md` holds the table (build, sha, OK/NOK per case, cores) and the
expectation column matches the rule in verify.md §5 for every row. A **latest-develop regression**
(verify.md §6) → Step 7 with the regression comment; the PR is not opened.

## Step 5 — commit, push, open the TC PR

Follow [references/pr-and-jira.md](references/pr-and-jira.md) §1–§3 (branch and push per mode,
title, body template, inline design comments).
Push to `tc/pr-<N>` only once its head is the bot's "chore: Initialize TC branch" commit (or the draft TC PR exists); fetch it with `+refs/heads/tc/pr-N:refs/remotes/origin/tc/pr-N`; after an engine PR close/reopen the branches are recreated without the TC commits, so cherry-pick the old commit onto the new branch and copy the old PR's title, body and inline comments; when the bot's private-ex job times out (branch == develop, no chore commit), push the TC commits first and then `gh run rerun <run> -R CUBRID/cubrid --failed`. (P6)

Done when the PR URL is in `<rundir>/results.md` and the inline review is posted.

## Step 6 — assign one reviewer (merged mode only)

A reviewer is assigned only when the engine PR is already merged into develop (`mode: merged` in
`facts.md`, user 2026-10-14). Open mode (the TC rides the engine PR's bot branch) and review mode
get no reviewer: write "no reviewer: <open mode|review mode>" in `<rundir>/reviewer.md`.

`mode: merged` → follow [references/pr-and-jira.md](references/pr-and-jira.md) §4. Exactly one reviewer from the team list:
among the members who reviewed the engine PR, the one with the fewest pending review requests now
(engine + both TC repos); nobody from the team reviewed it → the whole team.

Done when `reviewer.md` holds the skip line (open or review mode), or `gh pr view <tc-pr> --json
reviewRequests` lists the chosen team login (merged mode). The QA logins CODEOWNERS requests at
PR creation (e.g. kwonhoil, ssihil) stay; never remove them.

## Step 7 — JIRA comment (only three kinds)

Follow [references/pr-and-jira.md](references/pr-and-jira.md) §5. Post only for: out of scope
(performance-only), no TC possible, latest-develop regression. A normal PR gets no JIRA comment.

Done when the comment URL is recorded, or `results.md` says "JIRA comment: none (normal PR)".

## After the PR — reviews

Greptile or Codex comments on an opened TC PR: [references/pr-and-jira.md](references/pr-and-jira.md) §6
(check the reviewed commit and existing replies first; a real gap goes through Steps 3-4 again).
A human reviewer's find goes the same way.
When the engine commit is unchanged and only shell TC files changed, post `/run rerun <previous run id>` on the engine PR — it reruns just that run's cases on the latest TC branch content in minutes; a full `/run shell` (~2 h) only when the engine commit changed or a case outside the previous run needs coverage. (P7) Every miss a review or a three-point run exposes adds
one past-case line under its rule in `references/sql-pitfalls.md` (or shell-rules.md), in the
tooling repo, in the same work that fixes the TC: `CBRD-N (date, caught by ...): wrote → ran or
missed → fix`. A find that fits no rule gets a new rule, never a loose fact.

## Final report (same turn as the last step)

Print: verdict + rule, TC path(s), the three-build table, PR URL, reviewer, JIRA comment URL or
"none", and anything left undone with the reason. Delete extracted archive installs under
`~/optdebug/CUBRID-cbrd<N>-*` only after the table is written.
