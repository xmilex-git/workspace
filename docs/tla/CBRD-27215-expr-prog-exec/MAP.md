# ExprProgExec — an expression program reads its own execution's binds on a reused clone

Code: develop `be0a9ab1f` (CBRD-27215 expression programs `b8199438e` #7658, generation-time images from
CBRD-27361 `309265e6d`). `expr_compile.c` (`expr_prog_enter_execution` 7264, `expr_prog_prepare` 7296,
`expr_prog_reset` 7769), `query_opfunc.c` (`qdata_release_valptr_list_prog` 482), `query_executor.c`
(`qexec_clear_agg_list` 2447, `qexec_clear_pred` 1906), `query_manager.c` (`qmgr_allocate_query_entry` 283).

## Claim and sources

| # | Claim | Source |
|---|---|---|
| C1 | Every row a program evaluates reads the host-variable values of its own execution, also when two executions of one cached clone carry the same query_id. | `expr_compile.c:7276` ("a new execution rebinds the host variables, so their steps run once more"); `query_opfunc.c` `qdata_release_valptr_list_prog` header ("re-arms the prologues for that next execution"); `query_manager.c:333-337` (query_id per transaction, wraps at SHRT_MAX, reset at line 670) |
| C2 | A slot value is released by the thread whose private heap holds it. | `expr_prog_reset` comment ("the slot values may own memory of the executing thread's private heap: release them in the request that allocated them") |

## Refinement map (model -> code)

| Model | Code | One step because |
|---|---|---|
| `cph`, `Take` | `xcache_find_xasl_id_for_execute` hands a pooled clone to an execution; `xcache_retire_clone` returns it | the clone has one user at a time (the xcache pool) |
| `qid` | `vd->xasl_state->query_id` from `qmgr_allocate_query_entry` | fixed for the execution |
| `pdone`, `svalid`, `stamp` | `EXPR_PROG.prologue_done`, `exec_stamp_valid`, `exec_stamp` | single owner (the executing thread) |
| `slot`, `sowner` | the host-variable prologue's output slots, their values allocated on the executing thread's private heap | single owner |
| `Row` | `expr_prog_eval` -> `expr_prog_prepare` (skip when `exec_stamp_valid && exec_stamp == query_id`, else `expr_prog_enter_execution` and the prologue steps) | the thread's own row |
| `EndExec` | the execution's final clear: `qexec_clear_xasl (is_final)` -> `qdata_release_valptr_list_prog` / `qexec_clear_agg_list` / `qexec_clear_pred` -> `expr_scan_pred_reset` -> `expr_prog_reset` (slots cleared, `prologue_done` and `exec_stamp_valid` false), then the retire | on the executing thread, before the clone returns to the pool |

## Properties

| Name | Kind | Statement | Claim |
|---|---|---|---|
| `NoStaleBind` | invariant | no row reads a bind of another execution | C1 |
| `NoCrossThreadFree` | invariant | no slot value released by another thread | C2 |
| `IndInv` | inductive invariant | implies both; TLAPS-proved for any threads, query ids and executions | C1, C2 |

## Fault model and environment assumptions

| Fault | Modeled as |
|---|---|
| error return, interrupt | `EndExec` at any row: the error exit's clear is final too |
| query_id collision | `Take` picks any query_id, the previous one included (the witness reaches it) |
| a clone taken by another thread | `Take` picks any thread |
| lock timeout, latch failure, OOM, crash, spurious wakeup, DML, vacuum, checkpoint, HA apply | not applicable to a program's per-execution state |
| a correlated subquery's non-final clear | not modeled: it keeps the slots within one execution, where the binds do not change |
| program homes | assumed: every program the generation-time images create sits on a list or predicate the final clear resets (census below) |

Census of program homes (read at `be0a9ab1f`, not run): images are written for every `OUTPTR_LIST`
(`xts_process_outptr_list`) and aggregate list. Reset at the final clear: `xasl->outptr_list`, `g_outptr_list`,
`a_outptr_list`, `a_outptr_list_ex`, `a_outptr_list_interm`, `connect_by.prior_outptr_list`
(`qdata_release_valptr_list_prog`), aggregate operand programs (`qexec_clear_agg_list`), scan predicates
(`qexec_clear_pred`). Not reset: `cls_node.cls_output_val_list` (covering-index output, evaluated through
`scan_dump_key_into_tuple` and `btree_dump_curr_key`) and `insert.valptr_lists`. A covering-index output list
holds key-position leaves, for which `expr_valptr_prog_keep` writes no program ("a program that would only
repeat leaf fetches ... is not written"), so no program is expected there; the insert lists never reach
`qdata_valptr_prog_ensure` (its callers are `qdata_copy_valptr_list_to_tuple` and `qdata_collect_tuple_values`,
none on the insert path). Neither was checked at runtime.

## Mutants

| cfg | Change | Expected | Kills |
|---|---|---|---|
| `mutant-no-reset` | the final clear does not reach the program (`expr_prog_reset` skipped) | `NoStaleBind` violated: the next execution with the same query_id skips the prologue | C1 |
| `mutant-no-reset-xfree` | the same | `NoCrossThreadFree` violated: another thread's prologue overwrites (releases) the old slot value | C2 |
| `mutant-reset-keeps-stamp` | `expr_prog_reset` clears the slots but leaves `exec_stamp_valid` | `NoStaleBind` violated: reads an empty slot | C1 |

## Witnesses

| cfg | Reached state |
|---|---|
| `witness-qid-collision` | an execution took the clone with the previous execution's query_id and every row still read its own bind |

## Dead expressions (pass cfgs)

| Line | Why never evaluated |
|---|---|
| ExprProgExec.tla:76 | `EndExec`'s `no_reset` branch: mutant `no_reset` only |

## Bounds and limits

- TLC: 2 threads, query ids {1, 2}, 3 executions of 2 rows; scale 3 threads, ids {1, 2, 3}, 4 executions.
- TLAPS: C1 and C2 for any threads, ids and executions.
- Not covered: the program's steps and kernels (a decision table per type, not modeled); nested programs
  (`expr_prog_reset` recurses into `EXPR_KID_nested_prog`, read, not modeled); the page batch's packed cells
  (`eval_prog_row_external`, a per-row flag consumed by the next `qdata_valptr_prog_ensure`).

## Counterexamples

| cfg | Classification |
|---|---|
| — | none from a correct-variant cfg |

## Result

2026-11-06, `tools/tla/tla-check docs/tla/CBRD-27215-expr-prog-exec`: `RESULT: OK`. Run dir
`.git_ignored_dir/scratch/tla/CBRD-27215-expr-prog-exec-20261106-011823-2322299`; TLC tla2tools 1.8.0, TLAPS tlapm 1.4.5.

| cfg | Result | States (distinct) | Depth |
|---|---|---|---|
| main | pass | 221 (111) | 8 |
| scale-4exec | pass | 1051 (397) | 10 |
| inductive-indinv | pass | 2994 (1080) | 1 |
| mutant-no-reset | violation `NoStaleBind` | 67 | 6 |
| mutant-no-reset-xfree | violation `NoCrossThreadFree` | 134 | 7 |
| mutant-reset-keeps-stamp | violation `NoStaleBind` | 77 | 6 |
| witness-qid-collision | violation `NotCollided` (reached) | 81 | 6 |

TLAPS: `ExprProgExec_proofs.tla` 131/131 obligations proved, none omitted. Under tlapm 1.6.0-pre the step at 23:87
times out (ADR 0045); the record above is 1.4.5.

```
5fe6bd6af8761e092411fc2bcf1f6bf65ebc1976d5ef2dc456e05428d774c15b  ExprProgExec.tla
4a8c5ecdd0d2b55a708edc0e34480ff26531dbd86007a72748c9a294fef74c86  ExprProgExec_proofs.tla
```

Engine: develop `be0a9ab1f`, read only; no trace run (not a latch, lock or worker protocol: the clone has one
user at a time through the xcache pool).
