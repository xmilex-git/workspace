# PITFALLS — the rules in SKILL.md and the reviews that produced them

Each `P<n>` is one rule. The **Rule** line is the exact sentence SKILL.md carries at the step named in
**Applies at**; keep the two byte-identical (`rg -F "<rule>"` finds both). **Case** is the review or
user correction that paid for the rule. **Source** is where the lesson lived before it was folded in
here (auto-memory slugs are deleted once absorbed; kept for traceability only).

Adding a case: one `Case (YYYY-MM-DD):` line under the rule it confirms, in the session that hit it.
A new rule only when no rule fits — then add the sentence to SKILL.md in the same commit.

## Context (Step 2)

### P1 — develop drift since the merge-base
- Rule: Early in every review, run `git log --oneline <merge-base>..origin/develop -- <changed dirs>`; when a commit there touches the same subsystem, run the PR's TC dirs on the latest develop CI tarball as well, and a NOK caused by a TC branch older than the engine's develop base gets no comment.
- Applies at: Step 2
- Case (2026-10-08, PR 8085): the PR's CI and the fail-before run both used its merge-base; #8051 had merged that morning into the same memoize code. `tc/pr-8085` on the latest develop tarball showed two runtime-decided answers that would flip after the sync — a blocking TC finding the merge-base evidence could not show.
- Case (2026-10-13, PR 7834): the user on skew NOKs: "어차피 자기 버전에 맞는 tc 커밋따라갈거니까 리뷰달지말고".
- Source: memory:review-check-develop-drift, memory:unspecified-order-change-needs-spec-note

### P2 — a TC-only PR is reviewed on CI evidence
- Rule: A TC-only PR is reviewed on gha-ci evidence from a draft CI-only engine PR (one `--allow-empty` commit on develop pushed to the fork, `tc/pr-<M>` filled after the bot's init commit lands, `/run sql` or `/run shell`), never on a local run alone; re-fetch the TC PR head right before posting and close the engine PR afterwards.
- Applies at: Step 2
- Case (2026-10-06, cubrid-testcases#3642 / private-ex#4312): I proposed skipping CI because a local optdebug run already showed the result; the user: "Q3 작업 생략하지말고 하고, CI가 optdebug로 도니까, 이게 크래시가 나면 안되거든? Q3 작업을 증거로 리뷰 하자." A case that crashes cub_server on CI's optdebug build is a problem for the TC PR even when the crash is a known engine defect (CBRD-27557).
- Case (2026-10-14, #8163): pushing `tc/pr-<M>` during the bot's ~73 s clone made its `--force-with-lease` fail ("TC Branch Sync Failed") and no private-ex draft PR appeared. Wait for the bot's init commit first. Closing the engine PR makes the bot close its TC PRs and delete both `tc/pr-<M>` branches.
- Case (#4431): the author's develop merge resolved the planned Blocking item during the hours-long CI wait; the item was dropped only because the head was re-fetched before posting.
- Source: memory:tc-only-pr-review-ci-evidence

## Reading the diff (Step 3)

### P3 — an assert is a claim about every call site
- Rule: For every new assert in the diff, name its call sites and the state at each; an invariant that cannot be shown from the code is a finding asking the author to drop it or narrow it to the branch where it holds.
- Applies at: Step 3
- Case (2026-10-04, #377 gate 1, self-caught): `assert ((item->flags & DOMAIN_PLAN_ITEM_COMPARES) != 0)` inside a helper the stream walk calls for every arith node; items without compares are the normal case. I called it "belt and braces" and passed it; release was unaffected, the optdebug CTP gate found it at once — one full gate (~45 min, 190 GB of cores).
- Source: memory:review-asserts-are-claims

### P4 — "under sysop → serial" is settled
- Rule: In PX reviews, "a transaction inside a system operation runs its query serially" is settled — its false positives (nondeterministic degree, missing `parallel workers` trace lines) are not findings, while a worker-spawning path that skips the sysop gate is.
- Applies at: Step 3
- Case (PR 8046, CBRD-27492 grill): I proposed narrowing `compute_parallel_degree()`'s `is_under_sysop()` gate to the statement-level sysop because sibling workers' internal sysops (temp file creation) also fire it. The user: "걍 sysop 랑 엮여있는 작업중에 병렬질의를 안하는게 근본적으로 맞는 처리임", and on the plan-level MERGE block: "직렬로 막는게 맞는데, 그럼 이걸 논의할 필요가있나?"
- Source: memory:no-parallel-under-sysop-principle

### P5 — worker → leader error handoff
- Rule: In worker→leader error propagation, the leader adopts a worker's error only after its wait for every worker, in its own thread (the px_scan pattern: the worker moves its message into a holder; the leader swaps it into its thread-local error context afterwards) — a swap from the worker into a running leader is a finding.
- Applies at: Step 3
- Case (2026-10-11, CBRD-27592): the no-logging index build's worker swapped its -670 into the leader while the leader served page refills; optdebug `file_header_sanity_check` (`er_stack_push`/`pop` inside `file_alloc_multiple`) dropped it in the pushed level, and `sbtree_load_index` hit `ASSERT_ERROR` with no error (1 of 5 runs, 3 M rows). The user, approving the holder redesign: "px scan 쪽 방식이 맞는거야."
- Source: memory:px-error-handoff-store-then-adopt

### P6 — XASL streams are an on-disk format
- Rule: A field added to the `regu_variable` / arith / `pred_expr` / domain stream must answer disk compatibility (filter-index `pred_stream` and function-index `expr_stream` are stored in the catalog with the same `stx_*` codec; only the XASL header and access-spec layouts are memory-only), and a "should never happen" boundary must not reuse `ER_QPROC_INVALID_XASLNODE`, which makes the client drop the xasl_id and silently recompile.
- Applies at: Step 3
- Case (2026-09-22, map #312 / #318): both facts were found while charting the domain-pin campaign (`class_object.c:847`, `db_vdb.c:2277`); Strategy A (domains in the stream) rested on the first, the verification-boundary design on the second. Adding a bit to the already-packed `regu->flags` int is layout-neutral.
- Source: memory:xasl-stream-layout-is-on-disk-and-invalid-xaslnode-recompiles

### P7 — Windows is not a constraint on develop
- Rule: CUBRID builds no Windows target from guava (11.5; CBRD-26051 removed the CircleCI and Jenkins Windows jobs), so a Windows link or API limit is a finding only for a backport to a pre-11.5 branch — check the target branch first.
- Applies at: Step 4
- Case (2026-10-08, PR 8120): the first fix bound a NUL-terminated copy because `cascci.def` does not export `cci_bind_param_ex`; a reviewer proposed `_ex`; the user pointed out Windows is EOL, so the copy had no justification left. The CCI sub-drivers (ODBC, OLEDB, ADO.NET; APIS-1006) still ship for Windows — client only.
- Source: memory:windows-unsupported-from-guava

### P8 — prototypes sit in definition order
- Rule: In a CUBRID `.c` file the static prototype block lists functions in definition order, grouped by topic with blank lines — a relocated declaration goes where its definition falls, and the whole PR is grepped for the same pattern so one comment fixes every instance.
- Applies at: Step 3b
- Case (2026-09-22, PR 7866, youngjinj: "함수 선언 위치가 적절하지 않아 보이는데"): I moved the prototype to the end of the block; the user: "그게 기존 큐브리드 코드 컨벤션과 맞아?? 좀 자세히 보고 처리하지". An amend, a force-push and a reply edit to fix. Check: dump `^static .*\(` order against `^[a-z_0-9]+ \(` order with awk.
- Source: memory:prototype-placement-follows-definition-order

### P9 — develop's behavior is a measurement
- Rule: A statement about what develop does is made only after running it on a develop build with a discriminating row (a value that matches only if the claimed mechanism is true), and a root-cause ask is answered with the code-level cause, the fix and the gate in one pass.
- Applies at: Step 3
- Case (2026-10-25, PR 8213 Q19): I claimed "develop cuts 35203 to '3'" without testing; the user: "develop이 숫자를 저렇게 잘라서 비교한다고??", then "뭐 자꾸 안한게 생기냐, 근본원인코드 파악해서 develop이랑 스펙 맞춰". The claim and its rationale (numeric compare) were both false.
- Source: memory:verify-develop-claims-before-stating

### P10 — a truncated diff proves nothing
- Rule: When a comparison decides a verdict, print the number of differing lines per file (`diff a b | grep -c '^[<>]'`) or the full diff, and truncate only after the remainder is confirmed to be the same class of difference.
- Applies at: Step 3c
- Case (2026-10-20, CBRD-27583 7c): `diff | head -8` showed only the two expected `typeof` lines; lines 22–34 — analytic MAX/MIN over the retyped column returning NULL in release, a real wrong answer — were cut off and found one build later.
- Source: memory:truncated-diff-hides-defects

### P11 — an order SQL does not define is not a defect
- Rule: Before calling a changed row order a defect, cite what the SQL standard, vendor docs and the CUBRID manual guarantee (for CONNECT BY: parent-then-children only; root and sibling order is not), confirm the guaranteed part still holds, and downgrade to a request that the JIRA spec record the order change and the TC answers follow.
- Applies at: Step 4
- Case (2026-10-13, PR 7834): the user asked "connect by가 어떤 순서를 지키는게 db의 스펙아니야?"; Oracle, Db2, Informix and the CUBRID manual guarantee only the hierarchical order. Then: "내리지만, jira에 spec 변경에 추가해달라고 작성하자."
- Source: memory:unspecified-order-change-needs-spec-note

### P12 — a regression-fix PR restores, it does not repair
- Rule: On a PR that undoes what an earlier change broke, a finding is compared first against develop's answer on the equivalent plan; the same answer on develop is "pre-existing, out of scope" — unless the PR's own change adds a new way into that defect, or the fix the user asked for is not real without it, in which case it is fixed in the PR at the root.
- Applies at: Step 4
- Case (2026-10-12, PR 8130 / CBRD-27590): bot reviews flagged a LIMIT shortfall and rows moved out of the key range; both gave the same answer on develop's heap-reading index scan. I had approved a recheck and coded a LIMIT give-back (dead: the btree clears its position at key limit) — a wasted gate round. The user: "이 pr에서 고치려고 하는건 그 전 pr 때문에 영향받아 동작이 바뀌는것을 고친거잖아 … develop에도 이미 있던 결함을 고치려고 하는거 아냐? 그러면 처리할 필요가없어."
- Case (2026-10-12, PR 8140): a qlist-count mismatch on the clone-failure path the PR added; fault injection showed the server died there first on a develop-old `QFILE_FREE_AND_INIT_LIST_ID`. I called it out of scope; the user: "따로 등록이 아니라 어디 이슈에서 같이고쳐야하는거아냐?" — fixed in the PR.
- Source: memory:regression-pr-scope-excludes-preexisting

## Runtime verification (Step 3c)

### P13 — verdicts on query output
- Rule: A pass/fail verdict on query output comes from robust aggregates (`COUNT`, `SUM(CAST … AS NUMERIC(38,0))`, `MIN`, `MAX`) plus the actual rows a top-level SELECT returns to the client, never from an md5 of raw output.
- Applies at: Step 3c
- Case (SSOT §1.1, §1.3): raw-stdout md5 and `MD5(GROUP_CONCAT())` flagged row-order and format differences as corruption, and `;trace on` lines mixed into the rows made timing differences look like mismatches; an aggregate-only harness missed rows dropped on the client transfer path, and a hash-match miss in a 1:1 join never showed in the aggregate.
- Source: CUBRID_SSOT.md §1 실수 1, 3

### P14 — parallel must be proven
- Rule: A parallel path counts as exercised only when `;trace on` shows `parallel workers: N>1` (`;plan detail` does not show it); forcing serial needs both `parallelism=1` and `max_parallel_workers=1`.
- Applies at: Step 3c
- Case (SSOT §1.2): "serial == parallel passed" when both sides were serial — `parallelism=1` alone left the parallel sort at 8 workers via `max_parallel_workers`; an aggregate wrapper (`COUNT(*) FROM (SELECT DISTINCT …)`) silently serialized the inner operator and dropped its ORDER BY.
- Source: CUBRID_SSOT.md §1 실수 2

### P15 — races and fixes are counted
- Rule: A nondeterministic failure is judged by N repetitions (the FAIL and the PASS alike), and a fix is shown fail-before-fix and pass-after by the same method; a theoretical race is a finding only once it is shown reachable.
- Applies at: Step 3c
- Case (SSOT §1.4, §1.5): a single PASS was used to clear a nondeterministic regression; a fix landed without a prior failure capture and the wrong root cause stayed on record for the next worker.
- Source: CUBRID_SSOT.md §1 실수 4, 5

### P16 — what each verification tool cannot see
- Rule: Live verification runs on a CS-mode optdebug server (release compiles asserts and `er_log_debug` out; the resource tracker's leak checks are per-request in CS mode only, so an SA `csql -S` pass proves nothing about leaks), and gdb is never verification evidence — code-path proof is a `perf record -p <pid>` symbol band, a counter or an A/B output, and attaching gdb to a live `cub_server` is banned.
- Applies at: Step 3c
- Case (SSOT §1.6): a selftest passed in SA mode while the same query crashed a live server; heap corruption in release was a silent SIGSEGV with a 0-byte core. 2026-08-06: a gdb attach session itself produced a `core.cub_server` during CBRD-27181 QA — live attach banned since; offline core reading stays allowed. Without 64-bit libasan the ASAN gate is `valgrind --leak-check=full --track-origins=yes`.
- Source: CUBRID_SSOT.md §1 실수 6

### P17 — gha-ci flakes
- Rule: Before calling a gha-ci NOK the PR's, scan `failed.list` of the recent runs on other PRs and read the case's trace in its shard's `ctp_log.tgz`; a case failing on unrelated PRs is a flake or a develop defect (`/run rerun <run id>`), a 2-of-2 on one head is a signal, and a local `just ctp shell` timeout (720 s) is no proof that CI (1200 s) fails the case.
- Applies at: Step 3c
- Case (2026-10-01 → 10-27, PRs 8022/8034/8106/8137/8159/8213/8235): recurring PR-independent shell cases — `bug_bts_14305` (`kill 1` on a background csql), `temp_enc_06` (two server starts straddle a minute boundary, so the two TDE lines land in two `.err` files; 8 of 161 runs), `bug_bts_15156` (`cub_server` > 18 % CPU in a 5 s `top` sample), `bug_bts_15489` (vacuum sleep 60 s), `cbrd_20759/hide_cubrid_replay` (55 runs), `issue_11202_temp_volume_create` (41), `bug_bts_6199`, `cbrd_23768`, `bug_bts_13242` (lockdb dump timing), `cbrd_26564` (8 of 14 runs across six PRs), `cbrd_23842_cdc/oper03` (LSA arithmetic), `cbrd_23990_qcache_overflow` (a TC assumption: `qfile_list_cache_cleanup` skips entries another transaction holds open), `cbrd_26123` (`grep -o "0.00"` matches a pid containing 0000), `_enhance_1006` (loaddb error-report race, 3 of 5600), `cbrd_26280` (loaddb -C status-poll race), `cbrd_21506_backupdb` (`restrack_assert` MIDXKEY leak during online index × backupdb, 12 of 1460 runs), `cbrd_27120` (CBRD-27263 `pgbuf_fix` fast path vs vacuum waiters, 1 of 122). sql: `_01_no_data_filter.sql` (heap order of a LIMIT-offset subquery without ORDER BY), `cbrd_25717` ×9 + two shell cases (TC answers made on an older build + a develop core, every run since 2026-10-02 until fixed). CI "stuck" with the build contexts pending after a cancelled run: `gh api repos/CUBRID/cubrid/commits/<sha>/statuses`, then post `/run all` again.
- Case (2026-10-10, PR 8022 b3dca26dd): `cbrd_25717_agg_inline_view_parallel` `memory+hybrid` → `memory` failed 4/4 in CI on that head and 0/13 on other heads (Fisher p≈0.0004) while 8/8 passed locally on 64 CPUs. I first called it the flake. Resolved by the 32k TC (#3661); a local pass on 64 CPUs does not clear a head that fails in 8-CPU CI pods.
- Case (2026-10-14, PR 8159): `cbrd_27401` ran 907 s alone, so a loaded 50-shard run crossed CTP's 1200 s limit (13 of 30 runs); reverted and resubmitted without `--check-btree-entries`.
- Case (2026-10-29, PR 8311 8f644ec56): all 11 `sql/_36_guava/cbrd_27381/*` cases NOK in run 40824940519. The TC had merged into testcases develop (876b70cb1, 05:18Z) while its engine PR #8209 was still open, so every PR whose `tc/pr-N` synced develop after that fails the whole dir; #8318 (run 40827759161) failed the same 11. A whole-dir NOK of one CBRD: look up that CBRD's engine PR state before reading traces.
- Source: memory:gha-ci-shell-flaky-cases, memory:gha-ci-cancel-leaves-build-pending

## Rendering and posting (Step 6)

### P18 — `NIT:` marks trivia only
- Rule: `NIT:` labels only a trivial item (a stray blank line, a typo, a naming nit); a Non-blocking finding with substance — a coverage gap, a description claim the code contradicts — carries no label and is written in the suggestion voice (`~는 어떨까요?`).
- Applies at: Step 6
- Case (PR 8046): following the old Step 6 mapping ("every Non-blocking → `NIT:`"), the index-scan coverage comment went out labelled `NIT:`; the user, before posting: "2번째는 NiT가 아냐. 그것만 수정하고 제출해줘 리뷰."
- Source: memory:nit-only-for-trivial-review-items (this rule replaced the earlier mapping on 2026-10-28)

### P19 — no process asks to other teams
- Rule: On another team's PR, missing JIRA attachments (`design.md` / `test.md`), a missing regression TC and absent CI stay out of the post-ready comments by default — they are recorded in the local report's tables, and posting one is a grill question whose recommended answer is "don't post".
- Applies at: Step 6
- Case (2026-10-20, PR 8215 / CBRD-27670, beyondykk9): the user struck the attachment ask ("달지마. 다른팀 컨벤션은 달라."), both author questions, the regression-TC ask (both TC PRs were empty drafts) and the "/run all, gha-ci has not run" ask ("둘다 달지 마").
- Source: memory:review-no-process-asks-other-teams

### P20 — an alternative-architecture proposal gets an issue, not a promise
- Rule: When a reviewer proposes a different architecture as a follow-up, the reply states the principle the PR protects, says the structure is open under that principle, and closes with "이슈로 올려 <reviewer>님께 assign, 검토 부탁" — no commitment to implement; the user decides whether to file it.
- Applies at: Step 6
- Case (2026-10-08, PR 8022, shparkcubrid's compile-time bind-type-signature plans): "리팩토링 하면 된다는 식" read as a promise to do the work; the user wanted the proposer to own the evaluation and the merge unblocked. Filed by the user as CBRD-27583 (assignee shpark).
- Source: memory:design-proposal-reply-issue-and-assign

### P21 — "it looks cut off" is about the user's client
- Rule: When the user says a posted comment looks cut off, first establish the client they read it on (GitHub's Android app clips paragraphs that hold inline code), report server-side integrity as its own fact ("stored in full"), and write phone-read text as plain paragraphs without inline code or bold.
- Applies at: Step 6
- Case (2026-09-28, TC PR #3590): 39 comments verified byte-identical through REST, GraphQL and body_html, reported "not cut"; the user answered with a phone screenshot: "이게 안잘린거라고??".
- Source: memory:check-display-where-user-reads

### P25 — heads are re-fetched right before posting
- Rule: Right before posting, every PR's head is fetched again: a moved engine head is compared by `git range-diff` and an identical patch is posted at the new head with `commit_id` updated, while a moved TC head is re-read and a finding it already fixed is dropped and the event recomputed (an evidence-backed Approve needs the new answer run).
- Applies at: Step 6
- Case (2026-10-30, PR #8318 CBRD-27794): between analysis and posting the author rebased the engine PR (c75b1c11a -> 72ad4e886, range-diff all `=`) and pushed TC commit a5fc0dd91 that deleted the stray file behind the planned Request changes; the TC was approved after a one-case `just ctp sql` PASS with 0-line diff on the new answer.
- Source: session 2026-10-30 PR 8318 review

## Replying on your own PR

### P22 — replies read like a CUBRID reviewer
- Rule: Replies on the user's own PR follow `voice-guide.md` (§1b tone): Korean, identifiers in backticks, actor-subject sentences, results with build and row counts (`debug 빌드: … / release 빌드: …`), no `문제:`/`원인:` labels, no evaluative words, no emoji, ending on a fact or a question; when the user finds an explanation hard to follow, go one decision at a time with the actual SQL.
- Applies at: Replying on your own PR
- Case (2026-10-27, PR #8213 round 10): after the decisions the user said "말투는 /cubrid-pr-review 말투" — the tone, not the review procedure.
- Source: memory:pr-replies-use-pr-review-voice

### P23 — an external review is verified before it is acted on
- Rule: A review the user pastes is not turned straight into fixes: every finding is checked statically at the reviewed SHA and at runtime, and reported with verdict, measurement, the intent behind the code (which decision, which ticket) and what was missed then, before any edit.
- Applies at: Replying on your own PR
- Case (2026-09-27, map #312 review): the user first asked to register the review as a ticket, then mid-turn: "리뷰 검토 및 실제 결함이 맞는지 원래 어떤 의도로 코드를 작성했고 그때 뭘빼먹었는지 검토해서 나한테 보고해". Verification changed the picture: F2 was 31× slower than develop at K=1024 (heavier than the review's P2), Q1 was a lost handover (#336 → #340), and a new boundary surfaced.
- Source: memory:verify-external-review-before-acting

### P24 — reviewer-suggested asserts
- Rule: A reviewer-suggested assert goes in its own commit and is gated by optdebug CTP; one that fires is removed and the reply quotes the SQL case; no assert is added to develop-origin behavior the PR only moved (reply "develop 에서도 나는 동작, 별도 이슈"); every accepted change keeps develop's error code and message.
- Applies at: Replying on your own PR
- Case (2026-10-06, PR 8022 round): the user: "일단 넣어보고 assert 터지면 빼는걸로 하자. ctp sql 돌려보고 리뷰어 추가제안한 assert 가 터지는 건의 sql 케이스를 가져와서 이 건에서 터지니 안넣겠다. 라고 반박하고 안터지면 넣고." and "assert를 넣었을때 optdebug 기준으로 core 가 발생하는 sql tc가 있는거아냐? 그거 넣으면 내가 pr을 어캐머지하냐?" Upstream CI runs the TCs on optdebug, so one firing assert blocks the merge.
- Source: memory:reviewer-asserts-try-then-drop
