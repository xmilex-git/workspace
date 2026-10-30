# PITFALLS — cross-step rules and the TCs that produced them

The sql form rules and their past cases live in `references/sql-pitfalls.md` (seven rules, walked per
file in Step 3) and `references/shell-rules.md`; this file holds the rules that sit between steps
(judging, oracles, the bot branch, CI). Each `P<n>` is one rule. The **Rule** line is the exact
sentence SKILL.md carries at the step named in **Applies at**; keep the two byte-identical.
**Source** is where the lesson lived before it was folded in here (auto-memory slugs are deleted
once absorbed; kept for traceability only).

Adding a case: one `Case (YYYY-MM-DD):` line under the rule it confirms, in the session that hit it.
A new rule only when no rule fits — then add the sentence to SKILL.md in the same commit.

## Judging (Step 2)

### P1 — re-execution defects live on the CS path
- Rule: A re-execution, prologue or cached-program defect is probed through `csql -C` (a CS client) and written as a CTP **shell** case, because a CTP sql case runs through JDBC and `csql -S` does not pack values, so both can pass on a server that returns the previous execution's value.
- Applies at: Step 2
- Case (2026-10-15, PR 7658): `prepare st from 'select (? + 1) * n …'` executed with 1, 10, 100 returned the previous value on the PR head in csql -C (3 runs) and in a CTP shell case, but correct values in csql -S and in the same SQL as a CTP sql case. The per-execution array was db_private_alloc'd and freed; when the next execution got the same block back the stale pointer read the right value. The CS-only diffs were in the compare files but not in the session summary, so the review nearly posted without its most serious finding.
- Source: memory:stale-read-defects-need-cs-csql-path

### P2 — a parallel temp scan may be unreachable on the fix build
- Rule: When the fix commit is from 2026-06/07 and a check needs a parallel temp or list scan, probe the fix build first with a throwaway shell probe copied into the TC worktree (then removed) — a check that passes only on latest develop cannot separate pre from fix.
- Applies at: Step 2
- Case (2026-10-08, CBRD-26839, map #394 ticket #397): on the 85984d18d optdebug build (2026-06-08) none of 13 derived-table shapes (no_merge plain / WHERE / expression / GROUP BY / count / max / sum / ORDER BY … LIMIT) ran its list scan in parallel, even reading all 500,000 rows; the same queries print a parallel `temp` line on fbaee9282. The enabling commit was not bisected (CBRD-27292, 09-01, is a candidate). The TC dropped its temp checks.
- Source: memory:px-temp-scan-unreachable-on-june-builds

### P3 — QA's conventions are the yardstick
- Rule: When a TC convention is in question (placement by issue type, header length, ORDER BY, cleanup, determinism), the QA team's own rules are the source: for shell, the rulebook in the TC worktree (`AGENTS.md`, `shell/AGENTS.md`, `shell/rules/test-perspectives.md`, `shell/rules/writing-rules.md`; `references/shell-rules.md` lists where we differ); for sql, `git -C ~/dev/cubrid-agent pull` (clone of github.com/tw-kang/cubrid-agent) and read `skills/qa/create-sql/SKILL.md`, `skills/qa/author-testcase/SKILL.md`, `skills/qa/review-testcase/SKILL.md` (the lint our TC PRs face); cite them and the CUBRIDQA ticket numbers.
- Applies at: Step 1
- Case (2026-10-08, #411): the user: "이거 어딘가에 clone해놓고 편하게 봐. 자주 참조할거같으니." CTP's own docs are `~/cubrid-testtools/CTP/../doc/{sql_guide,shell_guide}.md`. A host without the clone: `git clone https://github.com/tw-kang/cubrid-agent ~/dev/cubrid-agent`.
- Case (2026-10-30, CUBRIDQA-1686): QA merged the shell rulebook into private-ex develop (PR 4585); it replaced `skills/in-progress/create-shell` as the shell yardstick, and the user decided where we differ (optdebug only, half-year by TC date, empty draft kept, `kill -INT` on a saved pid, shell_perf for R4).
- Source: memory:cubrid-agent-clone-reference

## Oracles (Step 3)

### P4 — trace numbers need a trace-off oracle
- Rule: A check on a traced `fetch:` count compares it with `SHOW EXEC STATISTICS ALL` `data_page_fetches` of a second, trace-off execution of the same plan (`set @collect_exec_stats = 1`; within 0.8..1.25; one csql run cannot give both, because SHOW TRACE / SHOW EXEC STATISTICS restart the watch), and hash-join parallelism is read from the line after `PROBE (`, not from the `HASHJOIN (` line.
- Applies at: Step 3
- Case (2026-10-11, workspace#428 trace-accuracy shell TC): shell-rules say never use fetch, but for a trace-accuracy defect fetch is the subject; these two oracles made it deterministic (fix 12/12 OK over 6 runs, pre 7 NOK every run on develop be683e04c optdebug, 200k-row t, thresholds 32). statdump `Num_data_page_fetches` also counts vacuum of the just-loaded tables, so it only serves against a big query. Deterministic pre-fix NOKs seen: parallel SCAN rows = readrows; NL parallel outer SCAN `readrows: 0, rows: 0`; SELECT fetch 1828 vs 71723; GROUPBY page < 4 × 150; hash aggregation readrows 10011 instead of 16000; partitioned parallel scan without `"parallel heap"` in JSON.
- Source: memory:trace-tc-oracles

### P5 — a shell TC's failure path is proven with a negative control
- Rule: To prove a shell case records failures, build a negative control without a worktree — `read-tree` into a temporary `GIT_INDEX_FILE`, `hash-object -w` the changed file, `update-index --cacheinfo`, `write-tree`, `commit-tree` — force one check to fail (its expected value +1), never push the commit, run it with `TC_REF=<that sha>`, then `git worktree remove` the runner's tc-worktree for that sha; and count the `.result` lines against the number of `write_ok`/`write_nok` calls (one line per check).
- Applies at: Step 4
- Case (2026-09-30, PR 8009's shell TC cbrd_27484.sh): a helper assigned `result_file="$2"` without `local`, so every later verdict went to that file and the case's `rm -f *.log` deleted them; the `.result` had 1 line for 7 checks while the xtrace in `out/result/shell/current_runtime_logs/test_local.log` showed all 7 `write_ok` calls. CTP reads only the `.result`, so the case reported `[OK]` whatever the later checks found.
- Source: memory:ctp-shell-result-file-global

## The bot branch (Step 5)

### P6 — push to `tc/pr-<N>` only after the bot's chore commit
- Rule: Push to `tc/pr-<N>` only once its head is the bot's "chore: Initialize TC branch" commit (or the draft TC PR exists); fetch it with `+refs/heads/tc/pr-N:refs/remotes/origin/tc/pr-N`; after an engine PR close/reopen the branches are recreated without the TC commits, so cherry-pick the old commit onto the new branch and copy the old PR's title, body and inline comments; when the bot's private-ex job times out (branch == develop, no chore commit), push the TC commits first and then `gh run rerun <run> -R CUBRID/cubrid --failed`.
- Applies at: Step 5
- Case (2026-10-07, #8120): the bot creates the branch by API and pushes its chore commit about a minute later with `--force-with-lease`; a TC commit pushed as soon as `git ls-remote` saw the branch made the bot's push fail ("stale info"), the private-ex job failed and no draft TC PR appeared. Recovery: `gh run rerun --failed` skips creation and creates the draft PR (#4334).
- Case (2026-10-12, #8138): closing the engine PR made "TC Branch Finalize" close both TC PRs and delete both branches; reopening recreated them from the current develop (#3699 → #3733, #4376 → #4402) without the TC commits.
- Case (2026-10-26, #8274): the private-ex job's `git clone` ran past the 10-min job limit ("TC Branch Sync Failed"); `gh run rerun --failed` then failed with "No commits between develop and tc/pr-<N>" until the TC commits were pushed first.
- Source: memory:tc-pr-branch-is-bot-created-upstream

## CI (After the PR)

### P7 — a shell-only TC fix reruns, it does not rerun the suite
- Rule: When the engine commit is unchanged and only shell TC files changed, post `/run rerun <previous run id>` on the engine PR — it reruns just that run's cases on the latest TC branch content in minutes; a full `/run shell` (~2 h) only when the engine commit changed or a case outside the previous run needs coverage.
- Applies at: After the PR — reviews
- Case (2026-10-26, private-ex#4511 / CI-only PR #8272): a shapes-only fix was followed by a second full `/run shell`; the user: "다음부턴 shell 만 수정할경우 run rerun 으로 실행하면 그 건만 최신으로 수행되니 그렇게 해."
- Source: memory:ci-shell-fix-use-run-rerun
