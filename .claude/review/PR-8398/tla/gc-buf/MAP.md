# GcBuf — the GROUP_CONCAT accumulator buffer and its remembered capacity (PR 8398, CBRD-27926)

Model of CUBRID/cubrid#8398 at `ea06eca48` (worktree `~/dev/cubrid-worktree/CBRD-27926`, merge-base
develop `0661d2c12`). The accumulator `DB_VALUE` owns a private-heap buffer; `db_string_append`
appends in place when the bytes fit the capacity the aggregate node remembers
(`info.group_concat.{buf, capacity}`), and otherwise `qstr_reserve` allocates the next size of the
doubling chain (64, 128, ...), clamped at `group_concat_max_len + 1`. The model checks that the
remembered capacity is never trusted for a buffer it was not measured on, across every site that
replaces the buffer, with the allocator handing a freed address back (ABA).

## Claim and sources

| # | Claim | Source |
|---|---|---|
| C1 | No byte is written past the accumulator's allocation or into freed memory, no copy reads freed memory, every free hits a live buffer on the heap that allocated it, and no buffer is dropped (memory safety of the in-place append under address reuse). | PR body, Implementation 3 ("누적 값의 버퍼가 기록과 다르면 크기를 모르는 것으로 보고 ... 해제된 주소가 다시 나올 수 있어서, 값을 바꾸는 자리에서는 크기를 0으로 되돌립니다"); `design.md` 상세 설계 "용량 기록"; `rehome_agg_value`'s heap contract comment (px_scan_result_handler.cpp) |
| C2 | The accumulator holds every byte appended so far, in order, and never more than `group_concat_max_len` (results unchanged). | JIRA Specification Changes ("GROUP_CONCAT 결과, 잘리는 위치, 잘림 경고는 바뀌지 않습니다"); JIRA AC 1; PR Remarks ("결과(길이, 내용, 잘림 경고, 오류)는 바뀌지 않습니다") |
| C3 | A buffer `qstr_reserve` grew is replaced only when the bytes do not fit, and by one at least twice as large or at the limit, so a group's allocation count is logarithmic in its result (fail-before: develop allocates on every append). | JIRA Implementation ("모자랄 때만 두 배로 키웁니다"); JIRA AC 2 (16,384 rows <= 2.5 x 8,192 rows); PR Implementation 1 |
| C4 | A live accumulator buffer is at most about twice its string (`<= max(64, 2 size + 1)`). | JIRA AC 3 ("cub_server 최대 메모리 증가가 결과 크기의 2배 이하") |
| C5 | A buffer `qstr_reserve` grew is at most `group_concat_max_len + 1` bytes. | JIRA Implementation ("버퍼는 group_concat_max_len을 넘겨 키우지 않습니다"); PR Implementation 1 |

Byte-level equality of the result fields with `db_string_concatenate` (collation, codeset, BIT
lengths, pad characters, precision) is a decision table over value classes, not a protocol; it is
checked at runtime (TC #4024 on CI, the develop vs head SA comparison), not in this model.

## Refinement map (model -> code at ea06eca48)

| Model | Code | One step because |
|---|---|---|
| `heap`, `hp`, `filled`, `grown` | the private-heap / malloc allocations; `hp` the heap that allocated them (`db_private_alloc` under `db_change_private_heap`); `grown` = made by `qstr_reserve` | the allocator is thread-safe; an allocation never returns a live address, any free address may come back |
| `str[n]`, `size[n]`, `typ[n]` | `db_get_string (agg_p->accumulator.value)` (NULL -> 0), `db_get_string_size`, VARCHAR/VARBIT vs the CHAR/BIT start value | |
| `ibuf[n]`, `icap[n]` | `agg_p->info.group_concat.buf`, `.capacity` (xasl_aggregate.hpp) | |
| `pv[n]`, `ps[n]`, `mid[n]` | an in-flight `qdata_concatenate_dbval` call: the bytes to append, the spare bytes still to add (`db_string_append_zero_bytes`), the codeset branch's pending append | |
| `Init` | `stx_build_aggregate_type`: `buf = NULL`, `capacity = 0` | |
| `OInit` | `query_aggregate.cpp:qdata_initialize_aggregate_list` (`capacity = 0`), from `qexec_start_mainblock_iterations` (BUILDVALUE) and `qexec_gby_start_group` (GROUP BY dimension list) | one node, one thread |
| `RowStart(n, v)` | the entry of one `qdata_concatenate_dbval` call from `qdata_group_concat_first_value` / `qdata_group_concat_value`; for the first value: `db_value_domain_init`, `db_string_make_empty_typed_string` (1-byte alloc), `capacity = 0` | the node is owned by one thread for the whole call (serial executor thread, a px worker on its own clone, or the merging worker under `writer_results_mutex` while the coordinator waits in `read ()`) |
| `AppendCall(n)` | `qdata_group_concat_capacity` (pointer check), `qdata_concatenate_dbval`'s truncation, `qdata_append_chars_to_dbval` -> `db_string_append` (CHAR path `db_string_concatenate` + `capacity = 0`; `qstr_reserve` in place / grow), then `info.group_concat.buf = db_get_string` | same; the spare bytes split off as `ZeroAppend` because the caller records `buf` only after them |
| `ZeroAppend(n)` | `db_string_append_zero_bytes` -> `qstr_reserve` (no pointer check), then the caller records `buf` | same |
| `Coerce(n)` | `db_string_append`'s codeset branch on `string1` (`*string1 = temp; *capacity = 0`); the append after it reads `capacity_p` without a pointer check (`mid`) | same |
| `Grow` / `InPlace` / `Fail` | `string_opfunc.c:qstr_reserve`: chain size, clamp `MAX (needed, limit)`, `db_private_alloc`, `memcpy`, `pr_clear_value` (free on the current heap), `*capacity`; `db_private_alloc` NULL | inside the call above |
| `StartPar` | `px_scan.cpp`: `rehome_agg_list (BORROW)` -> `rehome_node<PT_GROUP_CONCAT>` (`capacity = 0`, `rehome_agg_value`: clone on heap 0, free on the coordinator heap) | coordinator thread before any worker runs |
| `WRun(w)` | a worker task starts on clone `w`: `initialize_node<PT_GROUP_CONCAT>` sets `curr_cnt = 0` and keeps the clone's `info.group_concat`; the clone pool hands a cleared clone to another task of the same pass (recorded: clone `...d8019150` cleared at seq 251, taken again at seq 252), at most `TM` tasks per pass | the task's own thread; the clone is not shared while a task holds it |
| `WMerge(w)` | `finalize_node<PT_GROUP_CONCAT>` under `writer_results_mutex` on heap 0: `curr_cnt == 0` nothing; `orig curr_cnt > 0` -> `qdata_group_concat_value (orig, cur value)` (separator + value: two `RowStart`/`AppendCall` of `o`); else `capacity = 0` + `pr_clone_value` | mutex held for the whole merge |
| `MergeDone` | the end of that merge, mutex released | |
| `WClear(w)` | `qexec_clear_agg_list` on the worker's clone (`pr_clear_value` of `accumulator.value`, worker heap); `info.group_concat` stays | |
| `Restore` | `read ()`: `rehome_agg_list (RESTORE)` (clone on the coordinator heap, free on heap 0, `capacity = 0`) | coordinator after every worker reported |
| `OEnd` | the group's end: `qdata_finalize_aggregate_list` (no buffer change), then `qexec_clear_agg_list` (BUILDVALUE, clear) or `qexec_gby_finalize_group_dim` (`*g_outp->accumulator.value = *d_aggp->accumulator.value; PRIM_SET_NULL`: moved to the output list) | |
| `ExtFreeA(a)` | the output list node's `pr_clear_value` (before the next move, or at its own clear) | |
| `ErrEnd` | a failing query: `rehome_agg_list (DISCARD)` on heap 0 during a pass, `qexec_clear_xasl` otherwise, and the workers' clones cleared | |
| `Terminating` | the last execution is over | |

Callers of the protocol's entry points (code-index `callers`): `qdata_concatenate_dbval` <- `qdata_group_concat_first_value`, `qdata_group_concat_value` (only); those two <- `qdata_evaluate_aggregate_list`, `qdata_finalize_aggregate_list` (ORDER BY / DISTINCT replay, starts with `first_value`), `accumulate_node`, `finalize_node`; `qdata_initialize_aggregate_list` <- `qexec_start_mainblock_iterations`, `qexec_gby_start_group`. Hash GROUP BY never takes GROUP_CONCAT (`pt_is_hash_agg_eligible`), the parallel GROUP BY workers take only COUNT/SUM/AVG/MIN/MAX (`qexec_gby_px` agg check), analytic functions have no GROUP_CONCAT.

## Properties

| Name | Kind | Statement | Claim |
|---|---|---|---|
| `NoOverflow` | invariant | ghost `ovf`: an in-place write or a grown buffer's write past its allocation | C1 |
| `NoUseAfterFree` | invariant | ghost `uaf`: a copy reads a freed buffer | C1 |
| `NoBadFree`, `RightHeap`, `NoLeak`, `NoOrphan` | invariants | every free hits a live buffer on its own heap; no owned buffer is dropped; every live allocation has exactly one owner | C1 |
| `Intact` | invariant | `size <= Max` and the node's buffer holds `size` valid bytes | C2 |
| `NoSlowGrowth` | invariant | ghost `slow`: a grown buffer replaced though the bytes fit, or by one smaller than twice it and below the limit | C3 |
| `MemBound` | invariant | `heap[str] <= max(Base, 2 size + 1)` | C4 |
| `Clamped` | invariant | `grown[a] => heap[a] <= Limit` | C5 |
| `IndInv` | inductive invariant | the above plus `R_*` (live and disjoint buffers, the capacity is the allocation of a grown buffer it was recorded for, phase facts) | C1-C5 |

## Fault model

| Fault | Modeled as |
|---|---|
| allocation failure in `qstr_reserve` (OOM), `ER_QPROC_STRING_SIZE_TOO_BIG` | `Fail` at every growth (AppendCall, ZeroAppend), then `ErrEnd`; the value stays unchanged (`qstr_reserve` allocates before it frees) |
| allocation failure of the first value's empty string, of a rehome or a clone | not modeled: the node holds no new buffer and the query fails into `ErrEnd`'s clears, which the model has |
| interrupt / worker error during a parallel pass | `ErrEnd` from any state with `err` (DISCARD on heap 0, worker clones cleared) |
| NULL value or separator (`oracle_style_empty_string` empty string) | not modeled: the call returns before appending; it runs the pointer check and records `buf`, which can only drop a capacity |
| address reuse (a freed buffer's address handed out again) | every allocation picks any free address, the just-freed ones included |
| concurrent workers | `Workers` (clones) with independent rows; merges one at a time (`merger`), other tasks still running meanwhile; a clone runs again in the same pass after it was cleared (`WRun`) |
| crash / kill -9, DML, vacuum, latches, locks, checkpoint, HA | not applicable: the accumulator is private memory of one query |
| spurious wakeup | not applicable: no condition wait in the mapped code |

## Mutants

| cfg | Change (code) | Expected | Kills |
|---|---|---|---|
| `mutant-develop` | fail-before: every append allocates the exact size (develop's `qdata_add_chars_to_dbval` + `pr_clone_value`) | `NoSlowGrowth` violated | C3 |
| `mutant-no-reset-first` | `qdata_group_concat_first_value` keeps `capacity` (the 1-byte empty string lands on a worker clone's stale `buf`) | `NoOverflow` | C1 |
| `mutant-no-reset-rehome` | `rehome_node` keeps `capacity` (two rehomes with no append between; the second clone lands on the freed `buf`) | `NoOverflow` | C1 |
| `mutant-no-reset-coerce` | the codeset branch keeps `*capacity` (the append in the same call skips the pointer check) | `NoOverflow` | C1 |
| `mutant-no-term` | `qstr_reserve` asked for the bytes without the terminator | `NoOverflow` | C1 |
| `mutant-free-before-copy` | `pr_clear_value` before the `memcpy` | `NoUseAfterFree` | C1 |
| `mutant-no-free-old` | the old buffer is not freed | `NoOrphan` | C1 |
| `mutant-wrong-heap-merge` | `finalize_node` without `db_change_private_heap (thread_p, 0)` | `RightHeap` | C1 |
| `mutant-no-copy` | the grown buffer is not filled from the old one | `Intact` | C2 |
| `mutant-no-buf-record` | the caller never records `buf` (every append forgets the capacity) | `NoSlowGrowth` | C3 |
| `mutant-twice-need` | `new_capacity = 2 * needed` | `MemBound` | C4 |
| `mutant-no-clamp` | no `MAX (needed, limit)` clamp | `Clamped` | C5 |
