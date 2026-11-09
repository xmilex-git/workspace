# CBRD-27579 — what an SP invoked inside a SQL statement or a trigger may do, and what else the engine must hold so that none of the linked defects happens

Model `SpInStmt.tla`. Engine: PR #8182 head `0f920af80` (merge of develop `2362424f2`), worktree
`~/dev/cubrid-worktree/pr8182-tla`; runtime probes on its optdebug install `~/optdebug/CUBRID-pr8182`
(`libcubrid.so.11.5` sha256 `a3b53adf9658531d…`, `libcubridsa.so.11.5` `e37ec757752757e9…`).

Purpose (user, 2026-11-09): a reference model of how CUBRID blocks this whole class of malfunction; every
Correct Error issue linked from CBRD-27579 (CBRD-27590, 27591, 27603, 27614) must not happen.

The design the model verifies = PR 8182's two rules and classification (G1, G1t, G2, CLS-*, EXEC) **plus three
protections PR 8182 does not have** (P2, P3, P4). Without P2 and P4 two of the linked defects still reproduce on
the PR build (H2, H3 below).

## Claim and sources

| # | Kind | Claim | Source |
|---|---|---|---|
| C1 | safety | An SP whose stack holds a running SQL statement or a client-evaluated SP expression, or a running trigger, never executes TCL (COMMIT, ROLLBACK, SAVEPOINT, 2PC, SET …) or DDL; it gets ER_SP_TCL_DDL_IN_QUERY / ER_SP_TCL_DDL_IN_TRIGGER | JIRA body "규칙 1"; table row by row |
| C2 | safety | An SP whose stack holds a running SQL statement or SP expression never executes DML (INSERT/UPDATE/DELETE/MERGE, INCR, OID put/drop, collection writes), whatever the table; ER_SP_DML_IN_QUERY | JIRA body "규칙 2", 10-20 comment "DML 을 테이블과 관계없이 막는 이유" |
| C3 | safety | Nothing the rule allows is rejected: CALL alone runs TCL/DDL/DML, a trigger action's CALL runs DML, SELECT and NEXT_VALUE and a Java URL connection run anywhere | JIRA body table and "허용을 유지하는 것" |
| C4 | safety | The transaction never ends (commit, rollback, unilateral abort) while a statement is running, and no running statement touches its temp files or snapshot after an end | CBRD-27603 (temp pages freed, assert/“fetching deallocated pageid”); CBRD-27579 11-06 comment (Daehyun Kim: snapshot reset, SIGSEGV at `locator_sr.c:13207`) |
| C5 | safety | A DDL never changes a class under a running statement | JIRA body "규칙 1" (DDL), problem list |
| C6 | safety | Nothing an SP waits for (its own request, or a URL connection it opened) waits on a page latch its suspended outer scan holds | CBRD-27591 (self latch wait, 300 s, debug assert) |
| C7 | equivalence | A row the outer scan returns is the row as it is when returned: a row deleted or changed earlier in the same statement is never returned from a stale copy | CBRD-27590 (cached scan returns deleted rows and old values; serial `current_val` 2 instead of 3) |
| C8 | safety | An index scan never fetches an OID deleted in place (SA) | CBRD-27614 (“Accessing deleted object”, optdebug assert `scan_manager.c:7073`) |
| C9 | equivalence | A query over t returns the same rows whatever the plan (heap/fixed, cached, index, materialized inline view) | CBRD-27614 comment 2026-10-13 (Il Han Song, cases 1–6) |

Superseded statements: Oracle-style mutating-table rule (1차) and the table-level variant (2차) are recorded in
the 11-06 comment by jongminwon; the 3차 rule (C1–C3) is the one in the body and the one modeled. The 11-06 proposal
(Hyung-Gyu Ryoo: table-level judgment) is not modeled as the design; see "Relaxation" below.

## Refinement map (model → code at 0f920af80)

| Model | Code | One step because |
|---|---|---|
| `req[i] = "stmt"` and the depth it adds | `network_cl.c:1405` `net_client_request_with_callback` (METHOD_CALL case) `sp_depth_guard sql_guard (sp_In_sql_depth)` — the callbacks of QM_QUERY_EXECUTE, QM_QUERY_PREPARE_AND_EXECUTE (`network_interface_cl.c:7701,7873`); SA: `query_method.cpp:182` `method_dispatch` guard under `sp_Sa_query_request`, set in `qmgr_execute_query` / `qmgr_prepare_and_execute_query` (`network_interface_cl.c:7792,7911`), cleared in the SA PL_CALL (`:11637`) | single client thread; the guard is scoped to one callback dispatch, nested dispatches nest inside it |
| `req[i] = "call"` | PL_CALL through `net_client_request_method_callback` (`network_interface_cl.c:11584`), whose METHOD_CALL dispatch (`network_cl.c:1825`) adds no depth | same |
| `req[i] = "expr"` | `jsp_cl.cpp:817` `jsp_call_stored_procedure` guard when `call_or_expr == PT_IS_MTHD_EXPR`; reached from `parse_evaluate.c:1390` `pt_evaluate_tree_internal` (client-evaluated expressions: trigger conditions) | same |
| `trig` | `trigger_manager.c:4583` `execute_activity` `sp_depth_guard trigger_guard (sp_In_trigger_depth)` | same |
| `Decision`, `CodeAllows` | `sp_context_rules.cpp:151` `sp_check_statement_allowed`, called at execute: `method_query_handler.cpp:740` (execute), `:593` (prepare_call), `method_callback.cpp:233` (end_transaction), `:477` (oid_put), `:505` (OID_DROP), `:534` (collection writes) | a check then the statement, on one client thread with no shared state |
| `Cat(o)` | `sp_context_rules.cpp:36` `sp_stmt_category_of`, stored at prepare (`method_query_handler.cpp:862,926`); EXECUTE of a PREPAREd INCR / method-on-target via `prepare_info` (`db_vdb.c` `do_process_prepare_statement`) | category depends on the SQL text only |
| `prep` (EXEC mutant only) | the SQL handler reused per SQL text in a transaction (`method_query_handler.cpp`); the design keeps only the category there | — |
| `ScanMode`, `acc` | `query_executor.c:22215–22310` (fixed = innermost block unless `XASL_NO_FIXED_SCAN`, index or correlated subquery; cached gate = level-0 spec), `query_executor.c:10870` `qexec_is_cached_scan_eligible` (`!fixed`), `xasl_generation.c:11446` (`XASL_NO_FIXED_SCAN` for a serial operator only) | decided once at open |
| `Latched` | a fixed heap scan keeps its page fixed between `scan_next` calls; the SP of the row runs under it (CBRD-27591 debug stack; this file's H2 stack) | — |
| `ReadRow` (read) | `scan_next_heap_scan` (fixed: PEEK; cached: `heap_next_1page` copy), `scan_next_index_lookup_heap` (`heap_get_visible_version` per buffered OID) | one record read under one fix |
| `ReadRow` dangling | `scan_manager.c:7027–7073` S_DOESNT_EXIST unhandled (CBRD-27614 comment, MyungHwan Oh) | — |
| direct `NEXT_VALUE` (stmtSnv) / `nextval` op | `serial.c:444` `xserial_get_next_value` → `:940` `heap_get_visible_version` → `heap_prepare_object_page` write latch (H2 stack) | one heap update under one write latch |
| `delT` / `updT` effect | `locator_delete_force` / `locator_update_force` → `heap_prepare_object_page` (CBRD-27591 stack) | same |
| `commit` effect | `method_callback.cpp:233` → `db_commit_transaction` → server `log_commit` → `log_manager.c:5264` `file_tempcache_drop_tran_temp_files`, `:5255` `logtb_complete_mvcc` → `log_tran_table.c:4469` `curr_mvcc_info->reset ()` | one request |
| `aborts` (lockwait, selfW timeout) | `lock_manager.c:2369` `lock_set_error_for_aborted`; `page_buffer.c:7458–7476` (timeout: `assert (0)` on optdebug, ER_LK_UNILATERALLY_ABORTED on release); `network_interface_sr.cpp:398–413` `return_error_to_client` → `tran_server_unilaterally_abort_tran` → `log_abort` | the failing request's return |
| `abortPend` (P3, not in code) | design: keep `tdes->tran_abort_reason` set and the interrupt raised, abort only from the request that unwinds the outermost statement (`need_to_abort_tran`'s existing re-set at `network_interface_sr.cpp:349–359`) | — |
| `WFire` / `WWrite` | `execute_statement.c:9956` (`server_update` false when the class has an update trigger): the target rows are read into a list file first, triggers fire per row on the client | — |
| `url` | Java SP `jdbc:cubrid:` connection: another session and transaction | — |

Every entry point's callers: `sp_check_statement_allowed` has the six call sites above;
`sp_depth_guard` the four above. `fetch.c:1902` (`cubpl::executor` from a regu variable) is the only server-side
SP invocation; it runs inside XASL evaluation, i.e. inside a query-execution request. `xmethod_invoke_fold_constants`
(`network_interface_sr.cpp:11520`) is `#if 0`.

## Properties

| Name | Checked by | Claim |
|---|---|---|
| `Rule1`, `Rule2`, `NoOverReject` | TLC, Apalache (IndInv) | C1, C2, C3 |
| `NoTxnEndMidStmt`, `NoUseAfterEnd` | TLC, Apalache | C4 |
| `NoDdlMidStmt` | TLC, Apalache | C5 |
| `NoSelfWait`, `NoCrossWait` | TLC, Apalache | C6 |
| `NoStaleRead` | TLC, Apalache | C7 |
| `NoDanglingOid` | TLC, Apalache | C8 |
| `PlanIndependent` | TLC, Apalache | C9 |

The latch waits of C6 end in the code only by `page_latch_timeout_in_msecs`; the model turns the wait into the
ghost `selfWait` / `crossWait` and the timeout's abort, so C6 is a safety property, not liveness.

## The protections

| Id | What | Where | In PR 8182 |
|---|---|---|---|
| G1 | TCL / DDL rejected while `sp_In_sql_depth > 0` | `sp_check_statement_allowed` | yes |
| G1t | TCL / DDL rejected while `sp_In_trigger_depth > 0` | same | yes |
| G2 | DML rejected while `sp_In_sql_depth > 0` | same | yes |
| CLS-SA | SA counts callbacks under a query execution | `sp_Sa_query_request` | yes |
| CLS-EXPR | a client-evaluated SP expression counts as SQL | `jsp_cl.cpp:817` | yes |
| CLS-INHERIT | the depth is inherited by nested calls (a counter, not the innermost request) | the guards | yes |
| EXEC | judged at every execute, not cached with the reused handler | `method_query_handler.cpp:740` | yes |
| **P2** | **no page latch held across an SP call**: `XASL_NO_FIXED_SCAN` for a block whose predicates or select list call an SP (as `xasl_generation.c:11446` already does for serial operators). The single-table scan then becomes a cached scan, which copies the page and holds no latch | `xasl_generation.c` | **no** |
| **P3** | **a unilateral abort raised while a statement is running is deferred**: the failing nested request returns ER_LK_UNILATERALLY_ABORTED, the transaction keeps `tran_abort_reason` and the interrupt, every further request of it fails, and `log_abort` runs from the request that unwinds the outermost statement | `network_interface_sr.cpp` `return_error_to_client` | **no** (aborts at the nested request's return) |
| **P4** | **no cached scan of db_serial** in a statement that can write it (a serial operator or an SP call) | `query_executor.c:22310` cached gate | **no** |

## Fault model and environment assumptions

| Fault | Where | Modeled |
|---|---|---|
| error return | every SP leaf op (rejection, abort, URL timeout) | `err`, `Catch` (the SP handles it) or `Propagate` (the statement fails) |
| interrupt / query cancel | — | not applicable: a cancel fails the statement, it does not end the transaction; the deferred abort (P3) is modeled through `abortPend` |
| lock timeout, deadlock victim | an SP's SELECT waiting on another transaction | `lockwait` (CS only: SA has no other transaction) |
| conditional latch failure | — | not applicable: the paths here fix unconditionally |
| OOM | — | not applicable: PR 8182 allocates nothing on its paths |
| crash / kill -9 | — | not applicable: nothing durable is written between two steps of the model |
| spurious wakeup | — | not applicable: no condition wait in the model |
| concurrent DML | another transaction writing the scanned page | `url` (the SP's own URL connection); other sessions share its latch effect, see Bounds |
| vacuum | — | not applicable: the outer snapshot keeps every version it reads; the SP's own MVCC deletes are the `delT` op |
| checkpoint, page flush, page replacement | — | not applicable: the scan's page is fixed (fixed) or copied (cached) across the SP call |
| HA log apply | — | not applicable: a slave rejects writes |
| nested statement (SP SQL from the client) | every SP op | the subject of the model (`req`, `SpLeaf`) |

Environment: every statement in the model calls an SP or NEXT_VALUE (a statement without them has no in-statement
writer and no callback). Triggers fire only on the client after the DML read its targets (`execute_statement.c:9956`).

## Mutants

| cfg | Removes | Expect | Claim |
|---|---|---|---|
| `mutant-g1-27603` / `-use` / `-ddl` / `-rule` | G1 | `NoTxnEndMidStmt` / `NoUseAfterEnd` / `NoDdlMidStmt` / `Rule1` | C4, C5, C1 |
| `mutant-g1t` / `-use` | G1t | `NoTxnEndMidStmt` / `NoUseAfterEnd` | C4 |
| `mutant-g2-rule` / `-27590` / `-27614` / `-plan` | G2 | `Rule2` / `NoStaleRead` / `NoDanglingOid` / `PlanIndependent` | C2, C7, C8, C9 |
| `mutant-g2-p2-27591` | G2 and P2 | `NoSelfWait` | C6 — the DML self-wait holds by either: G2 rejects the write, P2 leaves no latch (cubrid-tla P74) |
| `mutant-cls-sa-27614` | CLS-SA | `NoDanglingOid` | C8, C2 |
| `mutant-cls-expr` | CLS-EXPR | `Rule2` | C2 |
| `mutant-cls-inherit` | CLS-INHERIT | `NoStaleRead` | C7, C2 |
| `mutant-exec` | EXEC (decision cached at prepare) | `Rule2` | C2 |
| `mutant-over-reject` | adds DML-IN-TRIG (over-strict) | `NoOverReject` | C3 |
| `mutant-p2-url` | P2 | `NoCrossWait` | C6 |
| `mutant-p3-abort-now` / `-use` | P3 | `NoTxnEndMidStmt` / `NoUseAfterEnd` | C4 |
| `mutant-p4` | P4 | `NoStaleRead` | C7 |

The pre-PR behavior (develop) is the union G1, G1t, G2, P2, P3, P4: each linked defect fails on one of the mutants
above (27603 → `mutant-g1-27603`, 27591 → `mutant-g2-p2-27591`, 27590 → `mutant-g2-27590`, 27614 →
`mutant-g2-27614`, the 11-06 snapshot case → `mutant-g1-use`).

## Code cfgs (PR 8182 as it is: Off = {P2, P3, P4})

| cfg | Expect | Status |
|---|---|---|
| `code-pr8182-rules` | pass | C1, C2, C3, C5, C8, C9 hold on PR 8182 |
| `code-h2-serial-latch` | pass | **fails: H2, confirmed at runtime** |
| `code-h3-serial-cached` | pass | **fails: H3, confirmed at runtime** |

The candidate fix for both is the main cfg (`SpInStmt.cfg`, Off = {}).

## Witnesses

`witness-dml-call` (CALL alone runs DML), `-dml-trig` (a trigger action's CALL runs DML), `-rej-dml-sql`,
`-rej-tcl-trig`, `-rej-ddl-sql`, `-nest-then-allowed` (call p → p's SELECT g () → g's DML rejected, then p's own
DML runs), `-nextval-sql`, `-url-sql`, `-sel-sql`, `-tcl-call`, `-stmt-done`, `-abort-deferred` (P3 fails the
statement and aborts after it), `-write-skips-deleted` (a trigger's DML deletes a target row the outer UPDATE has
not reached; the UPDATE skips it), `-direct-nextval-done` (stmtSnv completes on a plain scan).

## Dead expressions (pass cfgs)

| Cfg | Line | Expression | Why dead |
|---|---|---|---|
| `SpInStmt`, `scale-n3-d3` | `SpInStmt.tla:194–196` | `ReadRow`'s `useAfterEnd` branch | violation ghost: only after a transaction ended under the scan; fired by `mutant-g1-use`, `mutant-p3-use` (and live in `code-pr8182-rules`, where P3 is absent) |
| `SpInStmt`, `scale-n3-d3` | `SpInStmt.tla:255–256` | `WWrite`'s `useAfterEnd` branch | violation ghost; fired by `mutant-g1t-use` |
| `code-pr8182-rules` | `SpInStmt.tla:219–220`, `252–253`, `307–308`, `329–331` | the `abortPend` branches of `AfterSp`, `WWrite`, `SpLeaf`, `SpOp` | P3 only: PR 8182 never defers an abort (`abortPend` stays FALSE when `"P3" \in Off`) |

## Bounds and limits

- TLC: N = 2 rows, nesting MaxD = 2, K = 2 SQL per SP invocation, both modes, all eight tops; scale N = 3, MaxD = 3.
- Apalache (`apalache-indinv`): IndInv inductive with N, MaxD, K fixed at 2 (`CInit`); the integer contents
  (row versions, positions, budgets) range over all integers.
- One page per scanned class: the multi-page partial staleness of CBRD-27590 ("600-row table: 10 rows saw the
  change") is the same mechanism per page and is not modeled separately.
- INSERT into the scanned table (CBRD-27614 comment case 6) is a DML like `delT` for the gate; not modeled
  separately.
- Other sessions writing a page the outer fixed scan holds across a long SP wait behind it like `url` does; P2
  removes that wait too. Not modeled as its own process.
- Java default connection with `pl_transaction_control=no` ignores COMMIT (unchanged); not modeled.
- The client-side error bookkeeping of a unilateral abort (H1 runtime finding) is outside the model.

## Relaxation (Hyung-Gyu Ryoo, 11-06) — what the model says

The cases the 11-06 proposal wants to open (an SP inside DML writing an unrelated table) touch no class the outer
statement reads, so C6–C9 do not depend on G2 for them; only C2 (the rule) does. A table-level G2 needs the set
of classes the outer statement (and every statement above it on the stack) reads and writes, and P2 and P4 still
apply. That variant is not modeled here.

## Trace validation

Not done (미완). PR 8182 implements G1, G1t, G2 and the classification, so this is a model of code and needs
trace validation (cubrid-tla P50): instrument `sp_check_statement_allowed`, the four depth guards and the
trigger guard, record the witness scenarios, and check them against a trace spec. P2, P3 and P4 have no
implementation yet.

## Counterexamples and findings

| Id | Cfg | Classification | Runtime |
|---|---|---|---|
| H2 | `code-h2-serial-latch` | hole: `SELECT s.name, f () FROM db_serial s` with `f` running `SELECT s_b.NEXT_VALUE` — the outer single-table scan of db_serial is fixed (no serial operator in the statement itself, `xasl_generation.c:11446` does not fire), NEXT_VALUE is allowed by the rule and write-latches the same page | **reproduced** 2026-11-09 on the PR optdebug build, `page_latch_timeout_in_msecs=10000`: server assert `page_buffer.c:7461` in `pgbuf_block_bcb` ← `heap_prepare_object_page` ← `xserial_get_next_value_internal` (`serial.c:940`), core `cub_server_20261109172539.876.coredump`; CBRD-27591's signature |
| H3 | `code-h3-serial-cached` | hole: the NL driving scan of db_serial is cached (`P4` absent); NEXT_VALUE — direct or inside an SP — bumps s_b after the page was copied | **reproduced**: direct `s_b.NEXT_VALUE` → s_b `current_val` 2 (heap 3); through `f_nv ()` → 4 (heap 5); CBRD-27590's serial case, unchanged by PR 8182 |
| H1 | `mutant-p3-abort-now` | hole candidate: the SP's SELECT is the deadlock victim while the outer statement runs; `return_error_to_client` aborts at the nested request's return, the SP may catch the error and the outer statement continue | **partly reproduced**: two sessions (B: ALTER u, then ALTER ta; A: `SELECT id, f_rd (id) FROM ta`, `f_rd` reads u with an exception handler): A chosen victim (-72, "Set interrupt"), then **csql aborts** with `execute_statement.c:15254 do_select_internal: Assertion er_errid () != NO_ERROR` (core `csql_20261109172337.820.coredump`); the server stayed up and its log shows no "query … is in progress, including an SP" line, so whether `log_abort` ran before the outer statement unwound is [VERIFY] |
| — | acceptance | — | on the PR build: CBRD-27603 / 11-06 / 27591 / 27590 / 27614 (SA) repros all end in ER_SP_* errors, server up; CALL alone DML runs; SA and CS trigger CALL deleting an unreached target row: the UPDATE skips it ("3 rows affected"), as plain trigger SQL does |

## Result

**Unfinished (미완)**, stopped 2026-11-09 for handoff. No single record run of `tools/tla/tla-check` finished: the
final run was stopped by the user's request, so the numbers below come from two partial runs.

- TLC, run dir `.git_ignored_dir/scratch/tla/CBRD-27579-20261109-173146-1734773` (spec text the same as the files
  here apart from `CInit` moving to `SpInStmtInd.tla` and the main/scale CONSTANTS put on one line):
  `SpInStmt` pass, 41150 distinct states, depth 26; `scale-n3-d3` pass, 673089 distinct, depth 73;
  `code-pr8182-rules` pass, 39077 distinct; `code-h2-serial-latch` violation `NoSelfWait` (expected pass → H2);
  `code-h3-serial-cached` violation `NoStaleRead` (expected pass → H3); all 22 mutants hit the expected
  violation; all 14 witnesses reached.
- Apalache IndInv (`SpInStmtInd`, N = MaxD = K = 2): every conjunct passed in `tools/tla/apalache-split` groups
  (5 groups, 9–112 s each; runs `.git_ignored_dir/scratch/tla/CBRD-27579-split-20261109-1735*`); the
  single-cfg record run was not completed.
- TLAPS 요청 없음. Trace validation not done.
- Spec sha256: `SpInStmt.tla` 372cd6b6…, `SpInStmtInd.tla` 59e36ef8….
