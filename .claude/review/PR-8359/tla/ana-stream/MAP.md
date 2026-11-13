# AnaStream — PR 8359 (CBRD-27683) analytic streaming, head 4166ec0ac (r3, 2026-11-11)

Engine worktree read: `~/dev/cubrid-worktree/pr8359-instr` at `4166ec0acfd77dc129fcda04d6ec82d2aabb490d`
(merge-base `36c7433d8`). r3: the PR's code is byte-identical to r2's `3501715f1` (`git diff aeae2b25f 4166ec0ac` is
empty: `7e1bf7c69` added a guard, `4166ec0ac` removed it); the base moved over develop `36c7433d8` (CBRD-27989), which
makes `qexec_analytic_eval_instnum_pred` read the group's `is_skip_sort` instead of the xasl flag (`IntermStage`). One leader thread runs `sort_listfile`'s put callback; no state is shared with
another thread, so every step boundary is a function boundary of the leader's code.

## Claim and sources

| Claim | Statement | Kind | Source |
|---|---|---|---|
| C1 | Every row the streaming path writes is the existing path's row at that place: the same row, the same function values, the same ROWNUM; a run without an error writes every row | equivalence | PR body Remarks "이 PR은 결과를 바꾸지 않는 것이 목적"; JIRA CBRD-27683 AC2 (결과 동일) |
| C2 | The waiting rows in memory (tuples and their row values) stay within `max_agg_hash_size`; rows past it, with their row values, go to list files, so memory does not grow with the group | safety | PR body Implementation ("그룹이 커도 메모리는 늘지 않습니다"); commit a5de05793 and 3501715f1 messages; review reply 4488912879 |
| C3 | The spill list files exist only while rows are spilled; each flush destroys them, and none is left after the clear on the normal end or on an error | safety | change's own correctness (no temp-file leak); `qexec_analytic_stream_drop_spill`, `qexec_analytic_stream_clear` |
| C4 | An evaluation group whose waiting functions end their groups at different keys stays on the existing path | safety | PR body (`qexec_analytic_can_stream`: "기다리는 함수들의 경계(키 수)가 같을 때"); JIRA AC3 |
| C5 | inst_num () deferred to the group stage (SELECT ROWNUM) is evaluated right before the row is written, in output order | equivalence | PR body Implementation ("행을 쓰기 직전에 합니다. `update_group_result`가 평가하던 순서와 같습니다") |
| C6 | Every run ends (cleared) | liveness | change's own correctness |

## Refinement map

| Action | Code (`src/query/query_executor.c` at 3501715f1) | Variables | One step because |
|---|---|---|---|
| `Init` | `qexec_execute_analytic`: `qexec_initialize_analytic_state`, `analytic_state.is_streaming = qexec_analytic_can_stream (...)`; the existing path (`!is_streaming`) is the reference RefOut | rows, F, skip, streaming, all | leader-private setup before `sort_listfile` |
| `Key` | `qexec_analytic_put_next`: `qexec_analytic_eval_instnum_pred (..., ANALYTIC_INTERM_PROC)` at the top of the row, then the per-function loop: `!is_same_group` -> `qexec_analytic_stream_finalize_group (..., false)` for a non-final-at-row function + `start_group (reinit)`; same partition, new sort key -> `qexec_analytic_save_key` (RN/RK/DR), `start_group (false)` (PR), `stream_finalize_group (true)` + `start_group (false)` (aggregates); sets `group_ended` | ended, sv, grp, skc, cnt, dr, inum, pc | leader-private; the flush it may lead to is the next step |
| `Put` | `qexec_analytic_stream_flush` loop body: area record or `qfile_scan_list_next` on `stream->spill` and `stream->spill_vals`, `fetch_val_list`, `qexec_analytic_stream_put_row` (values into `out_value`, `qexec_analytic_eval_instnum_pred (..., ANALYTIC_GROUP_PROC)`, `qexec_insert_tuple_into_list`) | out, inum, fl, err | one waiting row per iteration; the trace logs each |
| `FlushEnd` | end of `qexec_analytic_stream_flush`: `area_used = 0`, `area_rows = 0`, `qexec_analytic_stream_drop_spill` | area, spill, spillVals, files, pc | straight-line code after the loop |
| `Add` | `qexec_analytic_add_tuple`: `fetch_val_list`, `qdata_evaluate_analytic_func` per function, counters ++, then `qexec_analytic_stream_add_row`: row values, immediate `put_row` (no waiting function), area append, or `qfile_open_list` (first spill) + `qfile_add_values_tuple_to_list` + `qfile_add_tuple_to_list` | grp, skc, rk, dr, cnt, area, spill, spillVals, files, out, i | leader-private |
| `End` | `qexec_execute_analytic` after `sort_listfile`: `stream_finalize_group (false)` for the waiting functions, `qexec_analytic_stream_flush` | sv, pc, ret | straight-line code |
| `Clear` | `qexec_clear_analytic_state` -> `qexec_analytic_stream_clear`: free `area`, `drop_spill`, free `spill_dbvals`, `row_vals` | files, area, spill, pc | called once on every exit (normal and `exit_on_error`) |

Callers of the entry points (code-index `callers`): `qexec_analytic_stream_add_row` <- `qexec_analytic_add_tuple`;
`qexec_analytic_stream_flush` <- `qexec_analytic_put_next`, `qexec_execute_analytic`; `qexec_analytic_stream_put_row` <-
`stream_add_row`, `stream_flush`; `qexec_analytic_stream_clear` <- `qexec_clear_analytic_state`. Exit paths: an error in
`put_next` sets `analytic_state->state` and the sort stops (`Add`/`Put` fault); interrupt and lock timeout arrive as an
error from a list-file call (same fault); the skip-sort path returns before `qexec_analytic_can_stream` (not streaming).

Abstractions: values are modeled per kind (`RefVal`); RN/RK/DR values come from `qdata_evaluate_analytic_func` as the
counters `grp`/`rk`/`dr`; NTILE/PERCENT_RANK are modeled by the arguments `put_row` passes to
`qexec_analytic_evaluate_ntile_function` / `..._cume_dist_percent_rank_function` (position, partition rows, sort key
start), compared with the arguments the existing path passes. An aggregate's value is the COUNT accumulator. Memory is
counted in rows (all records of a run have one `rec_len`; the trace runs have equal-length tuples). A fault resets the
counters (nothing reads them after an error; the code leaves them until the clear).

## Fault model

| Fault | Modeled as |
|---|---|
| error return of `qfile_open_list`, `qfile_add_*_to_list`, the immediate `put_row` (OOM, temp-volume full, interrupt) | `Add` fault branch at every row: `err`, files possibly opened, `pc = "err"` -> `Clear` |
| error in the flush (`fetch_val_list`, `qexec_insert_tuple_into_list` e.g. division by zero, `qfile_scan_list_next`) | `Put` fault branch at every waiting row -> `FlushEnd` (drops the spill) -> `err` -> `Clear` |
| `qfile_open_list_scan` failure at the first spilled row | same as the `Put` fault (the loop breaks before the row is written) |
| interrupt / lock timeout / deadlock victim | arrive as an error of the calls above; same branches |
| inst_num () predicate | not modeled on the streaming path: `qexec_analytic_can_stream` returns false when `is_last_run && instnum_pred != NULL`; for earlier runs `qexec_analytic_eval_instnum_pred` returns before evaluating; so `is_output_rec` is TRUE on every streaming row (the `assert` in `stream_add_row`) |
| SELECT ROWNUM (`XASL_INSTNUM_FLAG_EVAL_DEFER`) with the xasl's `XASL_ANALYTIC_SKIP_SORT` flag set by an earlier, index-ordered evaluation group | `IntermStage`: on base `36c7433d8` never true for a streaming group (a skip-sort group returns before `qexec_analytic_can_stream`); the old base's xasl-flag rule is `mutant-base-xasl-flag` (H1 of r2) |
| crash / kill -9, DML, vacuum, latches, locks, checkpoint, HA | not applicable: list files are temporary files of one query; restart resets the temp volumes |
| concurrent threads, spurious wakeup | not applicable: the leader alone runs the put callback; no wait |
| parallel sort | not applicable to the model: `put_next` is called by the leader in sorted order either way |

## Properties

| Property | Claim | Where |
|---|---|---|
| `OutPrefix` | C1, C5 | every state |
| `Complete` | C1 | every state |
| `MemBound` | C2 | every state |
| `SpillFiles`, `NoLeak` | C3 | every state |
| `Terminates` | C6 (needs `WF_vars(Next)`: the leader keeps running its own loop) | main, scale |
| `IndInv` | inductive invariant implying all of the above (except liveness) | main, scale, inductive |
| C4 | no state predicate of its own: a group that should not stream breaks `OutPrefix` when it does (mutant-keys) | |

## Mutants

| cfg | Change (code) | Expected | Kills |
|---|---|---|---|
| `mutant-vals-in-memory` | fail-before of the review finding (c378e3c23): spilled rows' row values stay in a memory array (`spill_vals` realloc) | `MemBound` | C2 |
| `mutant-no-cap` | no `area_max` check: every waiting row stays in the area | `MemBound` | C2 |
| `mutant-spill-first` | the flush reads the spill list before the area | `OutPrefix` | C1 |
| `mutant-flush-after-add` | `group_ended` flush after `qexec_analytic_add_tuple` (the row that ended the group joins it) | `OutPrefix` | C1 |
| `mutant-keys` | `qexec_analytic_can_stream` without the equal-keys check | `OutPrefix` | C4 |
| `mutant-vals-skew` | every spilled row reads the first spilled row's values | `OutPrefix` | C1 |
| `mutant-pr-pos` | PERCENT_RANK's row value is its partition position, not its sort key group start | `OutPrefix` | C1 |
| `mutant-clear-no-drop` | `qexec_analytic_stream_clear` without `drop_spill` | `NoLeak` | C3 |
| `mutant-flush-no-drop` | `qexec_analytic_stream_flush` without `drop_spill` | `SpillFiles` | C3 |
| `mutant-rownum-at-add` | inst_num () evaluated when the row is added instead of in `put_row` | `OutPrefix` | C5 |
| `mutant-no-flush-at-end` | `qexec_execute_analytic` without the final flush | `Complete` | C1, C6 |
| `mutant-base-xasl-flag` | r3: the old base (953e83256) `qexec_analytic_eval_instnum_pred` reads `XASL_ANALYTIC_SKIP_SORT` of the xasl, not the group's `is_skip_sort` | `OutPrefix` | C1, C5 |

Surviving mutant (not modeled, explained): the save/restore of `is_output_rec` around the group-stage evaluation in
`qexec_analytic_stream_put_row` and its `if (group_is_output_rec)` -- both flags are TRUE on every streaming row
(fault table, inst_num () predicate row), so removing either changes no run. Reported as a question in the review.

## Witnesses

| cfg | Outcome reached |
|---|---|
| `witness-spill-read` | a spilled row with row values is read back from the INT list and written |
| `witness-nt-flush` | NTILE rows written at the partition's end |
| `witness-end-flush` | the final flush after the sort |
| `witness-err-files` | an error with spill files open, before the clear |
| `witness-immediate` | a row written at once (no waiting function) |
| `witness-existing` | a group left on the existing path |
| `witness-mixed-wait` | RN/RK/DR row values and an aggregate value in one spilled flush |

## Dead expressions

| Line | Why |
|---|---|
| AnaStream.tla:155 | mutant-only branch (`Mutant = "flush-after-add"`), fired by `mutant-flush-after-add` |
| AnaStream.tla:165 | mutant-only branch (`Mutant = "flush-after-add"`), fired by `mutant-flush-after-add` |

## Bounds

- main: NR = 4 rows, NP = 2 partitions, NK = 2 sort keys, AreaMax = 1, up to MaxF = 2 functions of 7 kinds, faults on.
- scale: NR = 5, AreaMax = 2, MaxF = 3.
- inductive: TLC `INIT IndInv` at NR = 3 (Apalache does not fit: the spec builds sequences as functions
  `[1..n -> Row]` and `[j \in 1..o |-> ...]` and then applies `Len`/`Append` to them, and Apalache types `Seq(a)` and
  `Int -> a` apart; `MaxOf` uses CHOOSE over an integer set).
- skip-rownum / mutant-base-xasl-flag: main bounds with `SkipFlags = {TRUE, FALSE}`.

## Trace validation

r3: instrumented scratch worktree `~/dev/cubrid-worktree/pr8359-instr` = 4166ec0ac + the same `instrument.py` (kept in
`.git_ignored_dir/scratch/pr8359/evidence/r2/tla/`), prefix `~/optdebug/CUBRID-pr8359-tla`, libcubrid.so sha256
`5a6f1c712347783de096310a8596024cdeb3e60a2b5d77d52aa36a14efc71d59`; runs `.git_ignored_dir/scratch/pr8359/r1111/tla/run`. t1-t5 are identical to r2 except
`seq`; t6 now logs `inum=1..12` at the group stage (r2: `inum=5,9,12` at the flush). The corrupted runs are rebuilt from
the r3 runs: t1 line 35 rv 9 -> 10, t1 line 19 spill -> area, t6 line 11 inum 1 -> 5 (the old base's number).

r2: instrumented scratch worktree `~/dev/cubrid-worktree/pr8359-tlatrace` = 3501715f1 + `.git_ignored_dir/scratch/pr8359/r2/tla/instrument.py`
(TLATRACE at Begin, Key, Add, Put, FlushEnd, End, Clear; file from `CUBRID_TLA_TRACE_FILE`), optdebug, prefix
`~/optdebug/CUBRID-pr8359-tla`, libcubrid.so sha256 `ece5ec49...b3eb897`. CS server on port 1700, `max_agg_hash_size=32K`.
Every action of the spec is logged; none is hidden.

| Run | SQL (tables in `traces/`, `tw`: 15 rows, VARCHAR(4000) random hex) | cfg | Result |
|---|---|---|---|
| t1 | `row_number () over (partition by p order by k)`, `max (s) over (partition by p)`; reclen 4040 -> AreaMax 8, 4 rows spilled with their row values | `witness-trace-spill` | accepted (51 states) |
| t2 | `ntile (3)`, `percent_rank ()` over (partition by p order by k) | `witness-trace-ntpr` | accepted |
| t3 | `count (*) over (partition by p order by k)`, `rank ()` | `witness-trace-cokey` | accepted |
| t4 | `row_number ()`, `dense_rank ()` (row_vals[0] is DENSE_RANK's) | `witness-trace-immediate` | accepted |
| t5 | t1 with `1 / (row_number () ... - 10)`: division by zero at the 10th row, a spilled row | `witness-trace-error` | accepted |
| t6 | H1 query on `s1` (index `s1_a`): Put logs `inum=1..12` (r2 on the old base: `inum=5` for rows 1..4) | `witness-trace-skip` | accepted |
| corrupted t1: first spilled row reads rv 10 | | `reject-spill-vals` | refused at depth 35 |
| corrupted t1: 9th row kept in the area | | `reject-area-overflow` | refused at depth 19 |
| corrupted t6: first flushed row reads ROWNUM 5 (the old base's number) | | `reject-skip-group-stage` | refused at depth 11 |

`AnaStreamTraceData.tla` is generated by `tools/tla/trace2tla`; one line `EXTENDS Integers` was added for the logged `-1`.

## Findings

r3 (4166ec0ac): none. H1 below is closed by develop `36c7433d8` (CBRD-27989, the root cause named in r2); its code cfg
`skip-rownum` now passes and the old base's rule fails as `mutant-base-xasl-flag` (`OutPrefix`).

r2 — H1 (hole, runtime-reproduced): with SELECT ROWNUM and an earlier evaluation group ordered by an index
(`XASL_ANALYTIC_SKIP_SORT` on the xasl), `qexec_analytic_eval_instnum_pred` reads the xasl-wide flag and evaluates
inst_num () at the intermediate stage for the last, sorted group too. develop then writes every row with the last
number; the head writes a row as soon as it is evaluated (no waiting function: ROWNUM 1..N) or at its group's flush
(the number of the row that ended the group). Code cfg `skip-rownum` fails (`OutPrefix`, counterexample: F = {RK},
2 rows, row 1 written with ROWNUM 1, develop 2). Runtime (CI optdebug tarballs, SA): `p1` develop `12` on all 12 rows,
head `5,5,5,5,9,9,9,9,12,12,12,12`; `p3` (RANK only) develop `12` x 12, head `1..12`; trace t6 shows the
intermediate-stage numbers at the flush. Candidate fix `fix-skip-existing` (`can_stream` refuses the shape) passes;
the root cause is develop's (the flag is read from the xasl, not from `analytic_state->is_skip_sort`).

## Counterexamples

| cfg | Classification |
|---|---|
| `skip-rownum` (r2) | hole H1, closed in r3 by the base: every step maps to code (`Key` = INTERM-stage eval at the top of `put_next`; `Add` immediate put); runtime-reproduced |
| `inductive-indinv` (during writing) | IndInv too weak (a waiting row already written); strengthened with `GStart`; not a spec change |

## Result

- 2026-11-08, `tools/tla/tla-check .claude/review/PR-8359/tla/ana-stream` -> `RESULT: FAILED (1)`: the one failing cfg
  is `skip-rownum`, the code cfg of hole H1 (runtime-reproduced); every other cfg passes as expected.
- Run dir `.git_ignored_dir/scratch/tla/ana-stream-20261108-154554-2749645`.
- main 59,095 states / 47,279 distinct, depth 19; scale 263,194 / 210,400, depth 22; inductive (TLC, NR = 3)
  262,080 initial states / 120,342 distinct; fix-skip-existing 64,975 / 51,199; 11 mutants rejected; 7 witnesses reached.
- TLAPS 요청 없음.
- Trace: 6 runs accepted, 3 corrupted runs refused, on engine 3501715f1 + TLATRACE, optdebug, libcubrid.so
  `ece5ec492da3b208999b61497839d3d7699f887444a02c56a6fe15f78b3eb897`.
- spec sha256: `8ecc5a14...12145` AnaStream.tla, `fb181c68...11232` AnaStreamTrace.tla, `02487dc1...1d8da` AnaStreamTraceData.tla.

r3 (2026-11-11, head 4166ec0ac on develop 36c7433d8):
- `tools/tla/tla-check .claude/review/PR-8359/tla/ana-stream` -> `RESULT: OK` (32 cfgs), run dir
  `.git_ignored_dir/scratch/tla/ana-stream-20261111-145204-1551206`.
- main 59,095 / 47,279 distinct, depth 19; scale 263,194 / 210,400, depth 22; inductive (TLC, NR = 3) 262,080 initial /
  120,342 distinct; skip-rownum 118,190 / 94,558 (now pass); 12 mutants rejected (base-xasl-flag added); 7 witnesses.
- Trace: 6 runs accepted, 3 corrupted runs refused, on 4166ec0ac + TLATRACE, optdebug.
- TLAPS 요청 없음.
- spec sha256: `8375e694...4e4278` AnaStream.tla, `fb181c68...11232` AnaStreamTrace.tla, `bcb0ba98...adf224` AnaStreamTraceData.tla.
