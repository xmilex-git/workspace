# PxClearLists — PR 8436 (CBRD-27959) per-row clear of a parallel UNION ALL arm, head 1e5fcd7ca

Code: PR head `1e5fcd7caab5df76616bf04238a9f67facc07271` (merge-base develop `38c931e7d`), `src/query/query_executor.c`,
worktree `~/dev/cubrid-worktree/pr8436-review`. Parallel subquery execution (`px_query_execute`, CBRD-26104) runs
the aptr siblings of a set operation at once; the trace shows arm 1 on the request thread and arm 2 on a worker.

## Claim and sources

| # | Claim | Kind | Source |
|---|---|---|---|
| C1 | An arm's IN check reads the list file its subquery made for this row; no thread reads a list file another thread freed or reused | safety | JIRA CBRD-27959 Expected Result (12 rows, no crash); PR body Purpose (UAF/double free of the other arm's list) |
| C2 | No temp file is freed twice | safety | PR body Purpose ("같은 임시 파일이 두 번 해제") |
| C3 | After its per-row clear an arm holds no list of its correlated subqueries | safety | `qexec_clear_all_lists` comment ("clear all the dptr_list result LIST FILES in the XASL tree per iteration"); PR body Implementation ("결과가 같습니다") |
| C4 | The query leaves no list temp file behind | safety | PR body Implementation (qexec_clear_xasl at the end cleans up) |
| C5 | The query finishes | liveness | any query |

## Refinement map (model -> code, head)

Every step is one thread's code between two touches of the shared XASL memory (`xasl->list_id` of a subquery) or of
the temp file list; nothing locks the subquery's list_id, which is the defect class.

| Model | Code | One step because |
|---|---|---|
| `Start(a)` | `parallel_query_execute::execute_job_internal` -> `qexec_execute_mainblock` (arm a > 1, worker) / the request thread (arm 1, and every arm when serial) | no shared write |
| `Trunc(a)` | eval_pred of the IN over the `XASL_LINK_TO_REGU_VARIABLE` subquery -> `qexec_execute_dptr_list (truncate)` / its on-demand path -> `qexec_clear_head_lists_with_truncate` -> `qexec_clear_xasl_head`: `qfile_close_list`, `qfile_destroy_list` (frees the temp file, resets the list_id) | one destroy of one list |
| `Create(a)` | `qexec_execute_mainblock (subquery)`: `qexec_start_mainblock_iterations` opens the list on a temp file (`qmgr_create_new_temp_file`, freed files reused) | one creation |
| `Use(a)` | the IN check scans the list (`eval_pred` over the list scan) | reads its own list only |
| `EndRow(a)` | `qexec_intprt_fnc` -> `qexec_clear_all_lists (arm)` -> `qexec_clear_scan_all_lists (arm->scan_ptr)` -> `qexec_clear_head_lists (scan->dptr_list)` -> `qexec_clear_xasl_head`; develop's loop over `xasl->next` (Mutant develop) reached the next arm's scan_ptr | the frees of one clear |
| `RowDone(a)` | return of `qexec_clear_all_lists`, next outer row | no shared write |
| `Final` | `qexec_execute_query` -> `qexec_clear_xasl` on the request thread after the jobs ended (backtrace in the trace run) | after the join |

Functions of the diff: `qexec_clear_all_lists` only. Its bptr/fptr loops visit the same blocks develop's recursion
over `bptr_list`/`fptr_list` (walking their `next`) visited; those blocks carry no list file of their own besides
their dptr lists, which the per-arm subquery stands for: not modeled separately (fault table).

## Fault model

| Fault | Modeled as |
|---|---|
| error return | not modeled: an error ends the query and `qexec_clear_xasl` runs; the per-row clear is not on the error path |
| interrupt / cancel | same as an error |
| lock timeout, deadlock victim, latch | not applicable: list files of one query |
| OOM | not modeled (temp file creation failure = error) |
| crash / kill -9 | not applicable: temp files are dropped at restart |
| spurious wakeup | not applicable |
| concurrent DML / vacuum / checkpoint / HA | not applicable to the list files |
| other arms of the same query | the parallel arms (`Parallel = TRUE`), the serial order (`Parallel = FALSE`) |
| temp file reuse | `Create` takes any free file, including one another arm freed |
| bptr / fptr children | not modeled: same set of blocks as develop (code reading, refinement map) |

## Properties

`NoUseAfterFree` (C1), `NoDoubleFree` (C2), `RowClean` (C3), `NoLeak` (C4), `Terminates` (C5, `liveness` cfg), `IndInv`.

## Mutants

| cfg | Change (code) | Expected | Kills |
|---|---|---|---|
| `mutant-develop` | merge-base: `qexec_clear_all_lists` walks `xasl->next` and clears the next arm's subquery list | `NoUseAfterFree` | C1 |
| `mutant-row-keep-id` | the per-row clear destroys the file but leaves the list_id naming it | `NoDoubleFree` | C2 |
| `mutant-no-own-clear` | the per-row clear skips the arm's own subquery lists | `RowClean` | C3 |
| `mutant-trunc-no-free` | the truncation forgets the previous list without destroying it | `NoLeak` | C4 |
| `mutant-no-final` | no `qexec_clear_xasl` | liveness | C5 |

`serial-develop` (expect pass): develop's walk is harmless when the arms run one after another — the next arm has not
started, which is why the defect appeared with parallel subquery execution.

## Witnesses

| cfg | Outcome |
|---|---|
| `witness-two-active` | both arms' IN checks run at the same time |

## Dead expressions

None reported for the pass cfgs (record run below).

## Bounds

- main: NA = 2 arms, NR = 2 outer rows, NI = 2 subquery executions per row, NF = 3 temp files, parallel.
- serial, serial-develop: the same, serial. scale: NA = 3, NF = 4. liveness: main bounds.
- Apalache `apalache-indinv`: `INIT IndInv`, NA = 2, NF = 3, NR and NI over 1..3, both modes.

## Trace validation

Instrumented scratch worktree `~/dev/cubrid-worktree/pr8436-instr` = 1e5fcd7ca + `.git_ignored_dir/scratch/pr8436/tla/instrument.py`
(TLATRACE at `qexec_clear_xasl_head`'s destroy = Free with thread, xasl and temp file; at `qexec_intprt_fnc`'s
`qexec_clear_all_lists` = EndRow / EndRowDone; an Exec line in `qexec_execute_dptr_list` never fires because the IN
subquery is `XASL_LINK_TO_REGU_VARIABLE`; a later incremental build added a backtrace on Free under `CUBRID_TLA_BT`),
optdebug, prefix `~/optdebug/CUBRID-pr8436-tla`, libcubrid.so sha256 `f34547836f9c4221...`. CS server, port 1700, conf
`parallelism=24`, `max_parallel_workers=100`; the JIRA repro tables; `;trace on` shows `parallel workers: 2`.
`traces/conv.py` maps the raw log (`traces/raw-*.log`) to arm events. Hidden: Start, Create, Use, an empty truncation.

| Run | SQL | cfg | Result |
|---|---|---|---|
| par1, par2 | JIRA repro (two arms, correlated IN), parallel; two interleavings (108 differing event lines) | `witness-trace-par1`, `-par2` | accepted (depth 112) |
| ser | the same with `NO_PARALLEL_SUBQUERY` in both arms | `witness-trace-ser` | accepted |
| corrupted par1: arm 1's per-row clear also frees arm 2's list (develop's pattern) | | `reject-next-arm-free` | refused |
| corrupted par1: one truncation free of arm 2 dropped | | `reject-drop-trunc` | refused |

The cross-thread free in par1/par2 (arm 2's result list freed by the request thread) is `Final`: its backtrace is
`qexec_clear_xasl <- qexec_execute_query <- xqmgr_execute_query`, after both arms ended.

## Counterexamples

| cfg | Classification |
|---|---|
| `apalache-indinv` (while writing) | CTI from unreachable states (an arm waiting with executions counted); IndInv strengthened with the pc/row/ex conjuncts |
| `mutant-double-trunc` (dropped) | survived: the creation overwrites the list_id before any second free; replaced by `mutant-row-keep-id` |

## Findings

None.

## Result

- 2026-11-11, `tools/tla/tla-check .claude/review/PR-8436/tla/px-clear-lists` -> `RESULT: OK` (17 cfgs), run dir
  `.git_ignored_dir/scratch/tla/px-clear-lists-20261111-150719-1654639`.
- main 5,395 / 2,121 distinct, depth 36; scale (3 arms) 869,991 / 205,823, depth 53; serial 279 / 198; liveness pass;
  Apalache IndInv inductive (NA = 2, NF = 3, NR, NI in 1..3, both modes); 5 mutants rejected; 1 witness reached.
- Trace: 3 runs accepted (2 parallel, 1 serial), 2 corrupted runs refused, on 1e5fcd7ca + TLATRACE, optdebug.
- TLAPS 요청 없음.
- spec sha256: `38595d2a...0aee5bccb` PxClearLists.tla, `c02580e6...ef9e7046384` PxClearListsTrace.tla, `25306561...ac420619c4`
  PxClearListsTraceData.tla.
