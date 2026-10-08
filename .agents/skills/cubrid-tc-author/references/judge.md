# Ground and judge

Read this whole file before Step 1. `<rundir>` = `/home/cubrid/dev/workspace/.git_ignored_dir/scratch/tc-author/CBRD-<N>/`.

## §1 Ground — collect the facts into `<rundir>/ground.md`

Run every command. Paste outputs into the run directory, then fill the template. A section with
nothing to say gets the word `none`, never an omission.

```bash
R=/home/cubrid/dev/workspace/.git_ignored_dir/scratch/tc-author/CBRD-<N>; mkdir -p "$R"
# 1. issue (json — the markdown form of `search` goes through an old pandoc on this host and can print a blank body)
cubrid-jira jql 'key = CBRD-<N>' --fields summary,description,comment,attachment,issuetype,status,customfield_210565,fixVersions --output json > "$R/issue.json"
jq -r '.issues[0].fields | .issuetype.name, .status.name, (.customfield_210565.value // "no QA Scenario field")' "$R/issue.json"
jq -r '.issues[0].fields.description' "$R/issue.json" > "$R/issue-description.txt"
jq -r '.issues[0].fields.comment.comments[] | "## \(.author.displayName) \(.created)\n\(.body)\n"' "$R/issue.json" > "$R/issue-comments.txt"
# 2. attachments (5 MiB gate is built in; oversize ones come back "skipped" — record them as unread)
cubrid-jira attachment CBRD-<N> --out "$R/attachments" --output json > "$R/attachments.json"
# 3. engine PR
gh pr view <PR> -R CUBRID/cubrid --json title,body,state,mergedAt,mergeCommit,headRefOid,baseRefName,files > "$R/pr.json"
jq -r .body "$R/pr.json" > "$R/pr-body.md"
gh pr diff <PR> -R CUBRID/cubrid > "$R/pr.diff"
gh api repos/CUBRID/cubrid/pulls/<PR>/comments --paginate > "$R/pr-review-comments.json"
# 4. the fix on develop (merged mode) — `merge_commit` from facts.md
git -C ~/dev/cubrid-worktree/develop fetch -q origin develop
git -C ~/dev/cubrid-worktree/develop show --stat <merge_commit> > "$R/fix-stat.txt"
```

Read, in this order: `issue-description.txt`, `issue-comments.txt`, every file under
`$R/attachments/` that is text (`.sql`, `.txt`, `.md`, `.log`, `.html` — read html as text), images
with the Read tool, `pr-body.md`, `pr.diff`. An attachment you did not read is listed with the reason
(`skipped: 5 MiB gate`, `binary`). **Never guess an attachment's content from its name** (QA
incident CUBRIDQA-1488).

Template for `ground.md`:

```markdown
# CBRD-<N> ground
- issue type: <Correct Error | Improve Function/Performance | Development Subject | Sub-task | ...>
- parent (Sub-task only): <key, type>
- QA Scenario: <value>   status: <value>
- engine PR: #<PR>, mode <merged|open>, fix sha <sha>, base <sha>
## Repro (verbatim SQL / steps from the issue; `none` if the issue has no repro)
## Expected after the fix (what the issue says must hold)
## Acceptance criteria / DoD (numbered, verbatim)
## Attachments
| file | read? | what it contains |
## Fix diff
| file | functions touched | what changed (one line each) |
## Spec changes stated by the PR (error codes, trace lines, parameters, hints, manual)
## Existing TCs for this area (grep below) — path and what they already pin
```

Existing-coverage grep (the same repro may already exist under another name):

```bash
git -C ~/dev/cubrid-tc-worktree/develop fetch -q origin develop
git -C ~/dev/cubrid-tc-worktree/develop grep -l -i -E '<table name|hint|function from the repro>' origin/develop -- sql | head
git -C ~/dev/cubrid-tc-ex-worktree/develop fetch -q origin develop
git -C ~/dev/cubrid-tc-ex-worktree/develop grep -l -i -E '<same>' origin/develop -- shell | head
```

Done when every template section is filled or `none`.

## §2 Judge — one verdict, by rule number

Read `pr.diff` function by function. For each changed function answer: **does it produce, filter,
compare, or merge values the user can see** (rows, aggregates, LIKE/predicate results, index
entries, error codes), or does it only change **time, I/O, memory, logging, scheduling**?

| # | Observation from the diff and the issue | Verdict | Where |
|---|---|---|---|
| R1 | A user-visible value or error changes — or the values stay and a non-numeric trace line appears or disappears (CBRD-27177: GROUPBY gains `parallel workers`) — AND the new path shows a non-numeric trace token (`gather: buildvalue`, `MEMOIZE`, `semi join`, `method: hybrid`, `PARTITION`) or a plan shape, AND no server restart / second session / server-side observation is needed | **sql** | by issue type (table below) |
| R2 | The change needs any of: a `cubrid.conf` parameter that `SET SYSTEM PARAMETERS` cannot change, a server restart, two or more concurrent sessions, backup/restore or another utility, a count of workers/pages/readkeys (CTP masks every digit in a plan/trace), server pid / core / error-log observation | **shell** | by issue type |
| R3 | R1 holds for the result and R2 holds for a separate observation (e.g. a value fix plus a leak that only a server statistic shows) | **both** — one sql case for the value, one shell case for the observation | both trees |
| R4 | The diff changes only time / I/O / memory / logging and the result and trace text are identical before and after — no row, error, or trace token differs | **out of scope (performance only)** → Step 7 comment "성능 TC 필요" | — |
| R5 | A value-producing function changed (R1 kind) but the new path has **no switch** (no hint, no parameter) to run the old path for a reference twin. Look for a dispatch guard first: an input that sends the same query to the old path is a twin (CBRD-27181: a multi-byte ESCAPE absent from the patterns forces the old LIKE loop) | **sql, correctness TC**: literal expected values, pre-fix build also OK; the results table says so | by issue type |
| R6 | No case reproduces the defect **deterministically** on the pre-fix optdebug build: the pre run is NOK in fewer than 3 of 3 CTP runs, using only mechanisms existing shell/sql TCs already use (parameters, hints, utilities, concurrent sessions, bounded loops). A debug assert that fires deterministically on optdebug is observable, since CI runs optdebug; a race that fires only sometimes is not | **no TC possible** → Step 7 comment "TC 불가 사유" naming the triggers tried | — |

Rules apply in order R6, R4, R3, R2, R1/R5. Write the chosen rule number into `judge.md`.
R6 is about determinism (user, 2026-10-08: "확정적으로 재현하는 tc가 아니라면 굳이 추가해야하나"). Before
choosing it for a race, survey how existing private-ex shell TCs force similar timing and try that; a
probabilistic case (CBRD-27293: pre NOK in 2 of 3 CTP runs) is not added. A run counts as NOK when the
runner fails it — a NOK line or a core; CTP reruns a failed shell case, so the `.result` alone can read OK.
Mechanisms existing shell TCs use, and their limits: parameters and restarts, concurrent sessions,
bounded loops, `fault_injection_test` (random aborts on btree/log paths only), `kill -STOP` (stops a
client such as cub_cas, never a server thread), `checkpoint_sleep_msecs` (slows every build alike); no TC
attaches gdb. A race that needs a server thread held inside a short wait is R6 when none of these can
widen that wait (CBRD-27293: backup checkpoint flush wait vs shutdown wakeup).
R4 is decided by **reading the code**, never by the issue type alone: CBRD-27181 (LIKE fast path)
is an "improvement" whose changed function compares strings, so it is R5, not R4 (user, 2026-10-08).
A memory leak at a fixed allocation site is R2, not R4: judge it with `enable_memory_monitoring=yes` and
`cubrid memmon`, summing the `<file>.c:` lines of two idle snapshots taken after a warm-up (tc-ex
cbrd_25717_sector_memleak, cbrd_25854, cbrd_27217). R4 stays for time and footprint changes.

Placement by **issue type** (QA rule, CUBRIDQA-1486 — two PRs were sent back for a version-based
placement; a Sub-task takes its parent's type):

| issue type | sql | shell (cubrid-testcases-private-ex) |
|---|---|---|
| Correct Error | `sql/_13_issues/_26_2h/cases/cbrd_<N>.sql` + `answers/cbrd_<N>.answer` (flat `cases/`, half-year of **today**) | `shell/_06_issues/_26_2h/cbrd_<N>/cases/cbrd_<N>.sh` |
| every other type (Improve, Development Subject, Task, Sub-task of those) | `sql/_36_guava/cbrd_<N>/cases/cbrd_<N>.sql` + `answers/` | `shell/_40_guava/cbrd_<N>/cases/cbrd_<N>.sh`; several cases: `shell/_40_guava/cbrd_<N>/cbrd_<N>_<keyword>/cases/cbrd_<N>_<keyword>.sh` (the shapes private-ex develop uses) |

Several files for one issue: `cbrd_<N>_<keyword>.sql` in the same `cases/`; shell: one directory
per script, directory name = script name.

`judge.md` template:

```markdown
# CBRD-<N> judge
- verdict: <sql|shell|both|out of scope|no TC possible>  rule: R<k>
- why (2-4 lines citing the function(s) in the diff)
- reference twin: <hint/parameter that runs the old path, or "none → literal expected values (R5)">
- trace token(s) that prove the new path: <token> / shell observation: <what is measured>
- placement: <path(s)>
## Coverage list (§3)
| # | item (from AC / PR / diff branch) | case | or exclusion reason |
```

## §3 Coverage list — every row has a case number or a reason

Sources, in this order, each item one row:
1. the issue's acceptance criteria and attached scenarios (`*_testcases.sql`, `test_*.sql`);
2. the engine PR body's list of behaviors;
3. **branches in the diff**: each hint, parameter, type family (int / numeric / string / date),
   partitioned vs not, parallel on vs off, empty input, NULL, error path;
4. **boundaries of every changed branch**, read from the code, not from the issue: for each condition
   in the new or changed function, the input just below, at, and just above it (a limit N → N and
   N+1; a length check → shorter, equal, longer; a loop that can stop early → stop at the first, a
   middle and the last position; a fallback or dispatch guard → both sides). One row per condition,
   naming the line it tests. The issue's scenarios come from the author and miss the author's own
   blind spots (user, 2026-10-08, CBRD-27181: depth tested at 150/300 but not 256/257);
5. the repro itself (always case 1 or the first case after setup).

Rows without a case need a reason a reviewer accepts: "timing only (R4)", "needs debug assert",
"covered by case 3", "CBRD-27572 assert on develop makes it crash CI". A row with neither blocks Step 3.
Model for the table: cubrid-testcases#3527's "첨부 21개 시나리오 → 케이스 매핑표".

## §4 Parallel code reading before the coverage list — every issue

Trigger: **every issue, small or large** (user, 2026-10-08: "작든 크든 그걸로 해야되는데"; a one-file
fix gets one reader). Split the diff by area, read each area with an **Opus, effort high** agent in
parallel through the `Workflow` tool, and let the lead judge the candidates. The issue's scenarios
are an input, never a replacement: CBRD-27181's TC followed the attached test plan and missed the
boundaries of its own code (depth 256/257, memchr candidate retry, escape forms).

1. Split `pr.diff` into area files, one per changed source file (`git -C ~/dev/cubrid-worktree/develop
   diff <base>..<fix> -- <file>`, saved as `<rundir>/diff-<file basename>.patch`); with more than 8 source
   files, one per top-level `src/<dir>` instead. Build files (CMakeLists) are not areas.
2. Workflow script: one `agent(prompt, { model: 'opus', effort: 'high', phase: 'Extract' })` per patch,
   all in `parallel(...)`. Prompt for each (fill the brackets):

```
You read one part of the engine diff for CBRD-<N> (engine PR #<PR>): the file <rundir>/diff-<dir>.patch.
Issue summary: <2 lines>. Expected behavior after the fix: <2 lines>.
List every place in this patch where a SQL statement could observe a different result, error code,
plan shape, or trace token than before the fix. For each: the function, the condition that reaches
it (hint, parameter, data shape, type, partition, parallel), one SQL statement that reaches it, and
how a test would see it (result value / error / trace token). Also list conditions that this patch
handles but a SQL statement cannot observe (say why). Output: a markdown table with columns
function | condition | SQL | observable as | note. Then list the boundaries of every condition in
the new or changed code (input just below, at and just above it; both sides of every fallback or
dispatch guard; early exit at the first, a middle and the last position) as rows of the same table.
First line of your output: RESULT: <row count>.
Read only; do not edit files. Use tools/code-index/code-index <workspace> body <function> for context.
```

3. The lead merges the tables, drops duplicates and unobservable rows (they become exclusion
   reasons), and writes the coverage list of §3. Mark a row unreachable when SQL cannot get there: a
   parallel scan opens only on the outermost spec, and `scan_ptr` / `dptr_list` subtrees (join inner
   sides, correlated subqueries) are forced serial on every point
   (`process_xasl_node_recursive_force_cannot_parallel`), so rows about their rescans are excluded (CBRD-27217).
   Write the merged list as `R<n> | condition (file:line) | case | exclusion`, so a later round can
   replace rows by number. The lead, not the agents, decides what becomes a case.
