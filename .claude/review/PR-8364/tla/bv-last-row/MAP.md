# BvLastRow — a BUILDVALUE whose output reads its scan's column (PR 8364, CBRD-27870)

Engine: CUBRID/cubrid PR #8364 head `f65d0c0fa` (merge-base `e98bdd885`). `Mutant = "none"` is the head; `Mutant = "fix"` is the candidate the review asks for (keep the generation's `agg_optimized`, drop the count-only and checker exclusions and the debug assert; keep the batch exclusion and the per-row copy). One execution of a BUILDVALUE
(aggregates, no GROUP BY) from XASL generation to the final clear. Single thread: the flagged block never
runs a parallel scan (`CANNOT_PARALLEL_SCAN`), and a parallel aptr task that runs the block clears it in
the same thread (`qexec_clear_xasl_for_parallel_aptr`, `px_query_task.cpp` `execute_job_internal`).

## Claim and sources

| # | Claim | Source |
|---|---|---|
| C1 | When the output list reads a scan column, the value it reads on the serial loop and in place of the page batch is the last source row that passed the filters, NULL when none passed; on the paths that never fetch a row (statistics/index evaluation, count-only, parallel gather) it is NULL, as on develop and before #8196 (`OutputIsLastPassed`, `DoneHasOutput`). | JIRA CBRD-27870 Expected Result (the #8196 regression); user decision 2026-11-06 (review r3 grill Q6) superseding the PR body's "집계 빠른 길" and parallel claims |
| C2 | The output list never reads a slot whose page was unfixed or whose attribute-cache buffer was freed (`NoDanglingRead`). | PR body "직렬 행 루프도 ... 놓은 페이지나 해제된 버퍼"; comment of `qexec_keep_last_row` |
| C3 | The aggregates the server compiles are those the streamed operand image covers, and the debug assert in `qexec_intprt_fnc` never fires (`ImageMatchesServer`). | PR body (agg_optimized cleared at generation, before `xts_save_agg_prog_image`); review r1 Blocking (thread 4464626986) |
| C4 | A failed copy of a row ends the query with its error; it is never turned into a NULL output (`CopyErrorNotLost`). | PR body ("복제는 타입의 `setval ()` 로 해서, 실패하면 질의가 그 오류로 끝납니다"); greptile thread 4440984864 |
| C5 | `last_row` is freed at the final clear on success and on error, and no buffer is freed twice after the slot takes the copy over (`NoLeakNoDoubleFree`). | `qexec_restore_last_row` / `qexec_clear_last_row` comments; CLAUDE.md engine rule (no leak, owner frees) |
| C6 | A block whose output reads no scan column takes the same path as develop (`OtherQueriesUnchanged`). | PR body Remarks "그 밖의 질의는 그대로입니다" |
| C7 | Every execution reaches the final clear (`Terminates`, under `WF_vars(Next)`). | `qexec_execute_query` clears on both exits |
| C8 | The flagged block keeps develop's aggregate evaluation (statistics/index MIN/MAX/COUNT, count-only index scan) and parallel scan; only the page batch declines it (`OptimizationsKept`). | user decision 2026-11-06 (review r3 grill Q3, Q6): a hidden column's value is not bought by turning off develop's optimizations |

## Refinement map (model -> code)

| Model | Code (`f65d0c0fa`) | One step because |
|---|---|---|
| inputs `readsScan` | `xasl_generation.c:pt_buildvalue_output_reads_scan` (an output regu `TYPE_CONSTANT` whose `dbvalptr` is a slot of the block's or a `scan_ptr`'s `val_list`) | client-side, one thread |
| inputs `optimizable` | `xasl_generation.c:pt_to_aggregate` sets `agg_optimized` (MIN/MAX/COUNT answerable from index/statistics) | client-side |
| inputs `countStar`, `batchable`, `parallelable`, `alwaysFalse` | `qexec_intprt_fnc` count-only test; `qexec_batch_eligible`'s other questions; `px_scan_checker.cpp` other flags; `buildvalue->is_always_false` | facts of the plan, fixed before execution |
| `Gen` | `xasl_generation.c:pt_to_buildvalue_proc`: `XASL_SET_FLAG (xasl, XASL_OUTPUT_READS_SCAN)` and `agg_p->flag.agg_optimized = false` | client-side, before `xts_save_agg_prog_image` streams the image (`aggOpt`) |
| `Path` | `query_executor.c:qexec_intprt_fnc`: the `!NDEBUG` assert, `qexec_evaluate_aggregates_optimize` -> `return S_SUCCESS` ("fast"), the `PT_COUNT_STAR` test with `!XASL_OUTPUT_READS_SCAN` ("count"); `qexec_batch_eligible` ("batch"); `px_scan_checker.cpp` `CANNOT_PARALLEL_SCAN` at generation ("gather") | every condition reads only the unpacked XASL; no shared state |
| `srvAggOpt` | `agg_ptr->flag.agg_optimized` after unpack (`stream_to_xasl.c` `stx_build_aggregate_type`); the `server_clear` mutant is `bfc323a9a`'s clear in `qexec_intprt_fnc` | |
| `mismatch` | `expr_compile.c:expr_agg_prog_settle` `assert (expr_image_same_prog (prog, here))` at the first aggregate evaluation | ghost |
| `Row(p)` | one `scan_next_scan` success in `qexec_intprt_fnc` (the filter-batch iterator `scan_batch_open_filter` hands out one row per call too), `fetch_val_list` (`pr_clear_value` of an owned slot, then `pr_share_value` peek), the predicates, `qexec_end_one_iteration` -> `qdata_evaluate_aggregate_list` -> `qexec_keep_last_row` | the slot changes only here and the copy reads it before the next `scan_next_scan`; nothing else touches the slot between |
| `RowKeepFail` | `qexec_keep_last_row` returns the `db_private_alloc` (`ER_OUT_OF_VIRTUAL_MEMORY`) or `setval` error -> `GOTO_EXIT_ON_ERROR` | the error ends the iteration |
| `Close` | the scan ends (`scan_end_scan` in `qexec_next_scan_block` / the clear): page unfixed, attribute cache freed (`heap_attrinfo_read_dbvalues`) | |
| `Restore` | `qexec_end_buildvalueblock_iterations` -> `qexec_restore_last_row` (`pr_clear_value (v->val)`, move `last_row[i]`, `db_make_null (&last_row[i])`; else `db_make_null (v->val)`) | before the output list is evaluated in the same function |
| `Output` | the output list read in `qexec_end_buildvalueblock_iterations` | |
| `Clear` | `qexec_clear_xasl` (is_final) from `qexec_execute_query` on both exits: `qexec_clear_last_row`, then `qexec_clear_db_val_list` | |
| `lrAlloc`, `keptHas`, `keptRow` | `buildvalue->last_row`, `last_row_kept`, the copied values | |
| `shared`, `doubleFree`, `uaf`, `copyFailed`, `assertFail` | ghosts | |
| `lp` | ghost: the last source row that passed the filters, enumerated on every path | the claims' answer, independent of the path |

Entry points checked with code-index `callers` at `f65d0c0fa`: `qexec_end_one_iteration` (11 sites: batch emit/scan chain excluded by `qexec_batch_eligible`; merge join, CONNECT BY results and the intprt loop all keep per row), `qexec_end_buildvalueblock_iterations` (one: `qexec_end_mainblock_iterations`), `qexec_clear_xasl` (query end, clone decache/retire, px scan task), `qexec_clear_xasl_for_parallel_aptr` (the task that ran the block), `scan_check_parallel_scan_possible` (called in `pt_to_buildvalue_proc` after the flag), `agg_optimized` writers (generation `pt_to_aggregate`, this PR's clear; server writes in `qexec_evaluate_aggregates_optimize` and CONNECT BY clear only lower it on blocks where generation left it set, which the flag excludes).

## Fault model

| Fault | Modeled | Why |
|---|---|---|
| OOM / `setval` error in `qexec_keep_last_row` | yes, `RowKeepFail` at every kept row | the only new allocation |
| error elsewhere in the row loop (predicate, aggregate) | no | develop path unchanged; ends at the same `Clear` as `RowKeepFail` |
| interrupt | no | raised as an error through the same exit |
| concurrent DML / vacuum | no | the slot's validity is per scan position, which the model makes invalid at `Close`; MVCC visibility is unchanged by the PR |
| crash / `kill -9` | no | `last_row` is private-heap memory of one request; nothing persisted |
| re-execution (correlated subquery, cached clone) | no | `start_mainblock` resets `last_row_kept`, `Restore` and `Clear` reset it too; `fetch_val_list` clears an owned slot before it peeks the next row |
| parallel aptr task | no | the task that runs the block clears it (`qexec_clear_xasl_for_parallel_aptr`) |
| lock timeout, deadlock victim, HA apply, checkpoint | n/a | no lock or page latch is added |

Fairness: `WF_vars(Next)`; the code runs the steps in one thread without waiting.

## Mutants

| Cfg | Mutant | Claim it breaks | Result |
|---|---|---|---|
| `mutant-base-null` | merge-base `e98bdd885`: no flag | C1 (NULL on the batch/gather/fast/count paths) | violation `OutputIsLastPassed` |
| `mutant-base-dangling` | merge-base | C2 (serial loop reads the unfixed slot) | violation `NoDanglingRead` |
| `mutant-server-clear` | `bfc323a9a` (review r1): clear `agg_optimized` on the server | C3 | violation `ImageMatchesServer` |
| `mutant-gen-no-agg-clear` | head without the generation clear | C3 (debug assert) | violation `ImageMatchesServer` |
| `mutant-keep-after-scan` | first head `ac9d895db`: copy after the scan | C2 | violation `NoDanglingRead` |
| `mutant-no-batch-guard` | `qexec_batch_eligible` ignores the flag | C1 | violation `OutputIsLastPassed` |
| `mutant-head-drops-optimizations` | the head itself against C8 | C8 | violation `OptimizationsKept` |
| `mutant-no-restore-null` | `Restore` leaves the slot when no row was kept | C2 | violation `NoDanglingRead` |
| `mutant-clone-null` | copy with `pr_clone_value` | C4 | violation `CopyErrorNotLost` |
| `mutant-restore-no-null` | `Restore` keeps `last_row[i]` | C5 (double free) | violation `NoLeakNoDoubleFree` |
| `mutant-no-clear-last-row` | final clear skips `last_row` | C5 (leak) | violation `NoLeakNoDoubleFree` |
| `mutant-flag-always` | every BUILDVALUE flagged | C6 | violation `OtherQueriesUnchanged` |
| `mutant-error-no-clear` | the error exit skips the clear | C7 | deadlock |

Not a mutant: `buildvalue->last_row_kept = false` in `qexec_start_mainblock_iterations`. `Restore` and `Clear` reset it on every exit, so no claim depends on it (defensive; not modeled).

## Witnesses

`witness-value-out` (a value read), `witness-null-out` (NULL read, no row passed), `witness-copy-error` (the error exit), `witness-fast`, `witness-batch`, `witness-gather`, `witness-count` (an unflagged block still takes each develop path), `witness-fix-flagged-fast` (the fix answers a flagged block from the index and reads NULL): all reached.

## Dead expressions

- `BvLastRow.tla:175`: the `clone_null` branch of `RowKeepFail`; mutant-only (`mutant-clone-null`).
- `BvLastRow.tla:186`, `BvLastRow.tla:187`: the `keep_after_scan` branch of `Close`; mutant-only (`mutant-keep-after-scan`).

## Bounds

Main cfg `N = 3` source rows, scale `N = 4`, for the head and the fix; all 64 input classes (6 booleans). Apalache `apalache-indinv` (head) and `apalache-indinv-fix`: `IndInv /\ Next => IndInv'` for every `N >= 1`. TLAPS (`BvLastRow_proofs.tla`, `Mutant \in {"none", "fix"}`): `Init => IndInv`, `IndInv /\ [Next]_vars => IndInv'`, `IndInv => C1..C6`, `Mutant = "fix" /\ IndInv => C8`, `Spec => []IndInv`, for every `N`. C7 is TLC-only (no fairness proof). The path order follows the code: the parallel decision (generation) precedes the page batch (decided in the scan, or inside the workers by `px_scan_task.cpp` `task::initialize`).

Not covered: the values of more than one slot (the model tracks one hidden column; `qexec_keep_last_row` copies every slot in the same loop), a join's `scan_ptr` chain (same copy loop over the chain), CONNECT BY (aggregates over the hierarchy list, kept per row by `qexec_iterate_connect_by_results`).

## Findings

H1 (code cfg `BvLastRow.cfg` and `BvLastRow.scale-4-rows.cfg` fail on C8, kept failing per cubrid-tla P9): the head sends a flagged block whose develop path is the statistics/index evaluation, the count-only scan or the parallel gather to the serial loop. Every step maps to `f65d0c0fa` (`pt_to_buildvalue_proc` clears `agg_optimized`, `qexec_intprt_fnc` count-only `!XASL_OUTPUT_READS_SCAN`, `px_scan_checker.cpp` `CANNOT_PARALLEL_SCAN`). Runtime reproduction: release CI tarballs, SA, 1,000,000-row `big (g)` with an index, `insert into tt (id) select max(s.g) + 1 from big s on duplicate key update c = s.c`: develop `e98bdd885` (`libcubridsa.so` f1647e1a…) 1.309G/1.310G/1.314G instructions:u (csql start alone 1.30G), `c` NULL; head (0c768756…) 3.98G/4.02G/4.01G (start alone 1.25G), `c` = 'v999739' (the last row in scan order, not the MAX row's 'v1000000'). Candidate fix cfgs `fix-candidate`, `scale-4-rows-fix` pass. Posted as review 5794917472 (REQUEST_CHANGES).

## Trace validation

Instrumented scratch worktree `~/dev/cubrid-worktree/pr8364-tla` (removed 2026-11-06; `.git_ignored_dir/scratch/pr8364/instrument.py` re-applies the patch) at `f65d0c0fa` (+93 lines of `TLATRACE` in `xasl_generation.c` and `query_executor.c`, never committed), optdebug install `~/optdebug/CUBRID-pr8364-tla` (removed), `libcubridsa.so` sha256 `bb86bdc96c27c91236f3f1056c6a4f8936e332f741e1eebb9bfc5d7d06d9b1c2`, SA mode (`csql -S`), one statement per run, tables of 3 rows.

| Run | Statement | Events | Result |
|---|---|---|---|
| `ok` | ODKU, heap source, `WHERE s.g < 3` | Gen f=1, Path serial, Keep 1, 2, Close, Restore kept=1, Output null=0, Free | accepted; `t.id=3` gets `'b'` |
| `nopass` | ODKU, `WHERE s.g > 10` | Gen f=1, Path serial, Close, Restore kept=0, Output null=1 | accepted; `t.id=2` gets NULL |
| `minidx` | ODKU, WHERE-less MIN over an indexed table (Case 8 shape) | Gen f=1 ao=0, Path serial, Keep 1, 2, 3, Close, Restore kept=1, Output null=0, Free | accepted; `t.id=4` gets `'z'` |
| `fast` | `select max(g) from si` | Gen f=0 ao=1, Path fast | accepted |
| `heapcount` | `select count(*) from s where g > 0` | Gen f=0, Path batch | accepted |
| `corrupt-ok-restore-flipped` | `ok` with kept=0 | | rejected |
| `corrupt-minidx-keep-after-close` | `minidx` with the last Keep after Close | | rejected |
| `corrupt-nopass-value-out` | `nopass` with null=0 | | rejected |

Actions no run reached: `RowKeepFail` (needs an OOM injection), Path `count` and `gather` (an unflagged block; the flagged block cannot reach them).

## Result

- 2026-11-06, `tools/tla/tla-check --prove --workers 8`, toolchain `mcnrlar201f0kiwhaz2d8pfxhbl6h3zb-tla-tools`, run dir `.git_ignored_dir/scratch/tla/bv-last-row-20261106-113442-3715985`: `RESULT: FAILED (2)` -- only the head's code cfgs `BvLastRow` and `BvLastRow.scale-4-rows` (violation `OptimizationsKept`, finding H1, runtime-reproduced); every other cfg as expected.
- TLC: head violates C8 at depth 3 (179 states); fix candidate 1520/1240 states depth 10, `scale-4-rows-fix` 1996/1572 depth 11, IndInv in both; 13 mutants rejected; 8 witnesses reached; dead expressions 175, 186, 187 (explained above).
- Apalache `apalache-indinv` (head) and `apalache-indinv-fix`: IndInv inductive for every `N >= 1`.
- TLAPS (tlapm 1.6.0-pre `efe4f2d`): 921/921 obligations proved (`InitInv`, `StepInv` by action and IndInv conjunct, `InvSafe` C1-C6, `FixKeepsOptimizations` C8 for the fix, `Spec => []IndInv`), head and fix together.
- Trace validation: 5 runs of the instrumented `f65d0c0fa` optdebug build accepted, 3 corrupted runs rejected.
- spec sha256: `BvLastRow.tla` 215953194b675b96762f26679f15e450ac8d6ea5d87f47f7f9e8299a6e4ddfdb, `BvLastRow_proofs.tla` 17139eee9d7a2fda0a5bf61945ede386fe83220c959e4f6c169ddbd083902b99, `BvLastRowTrace.tla` d9157fe72945621339603b34d9411a2f0700228a2d5ff323958ed931c650e4cb, `BvLastRowTraceData.tla` 022091e68c69febf1812d7e0513d7b5a0217997e05caa03c82e4af5f8cf40cf0.
