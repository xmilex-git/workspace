# PxHashJoin — the parallel hash join's leader/worker protocol (CUBRID develop e98bdd885)

Scope: `src/query/parallel/px_hash_join/` and the shared `src/query/parallel/px_task_manager.cpp` at
CUBRID/cubrid develop `e98bdd885` (2026-11-05), read in the scratch worktree
`~/dev/cubrid-worktree/phj-tla-e98bdd885`. One spec models one parallel phase; the constant `Phase`
picks which:

| Phase | Leader | Worker task | Unit a worker claims |
|---|---|---|---|
| `split` | `build_partitions` (px_hash_join.cpp:44) | `split_task::execute` | a list page of the input (one pass; the outer and inner passes run the same protocol one after the other) |
| `join` | `execute_partitions` (px_hash_join.cpp:166) | `join_task::execute` | a partition context (`get_next_context`) |
| `probe` | `probe_execute` (px_hash_join.cpp:483) | `probe_task::execute` + `execute_inner/outer` | a page of the probe list |

The per-unit computation (hashing a tuple, `hjoin_execute` of one context, a probe against the hash
table) is abstracted to its observable effect on shared state: the partition a tuple lands in, the
context's result list, the rows a probe tuple emits.

## Claim and sources

| # | Claim | Source |
|---|---|---|
| C1 | Every unit (page or context) is handed to exactly one worker: the membuf region to the one CAS winner, each sector / context once. | `query_list.h:698` class comment of `sector_page_iterator` ("the CAS winner ... atomically claiming sectors"); `get_next_context` under `scan_mutex` |
| C2 | A split that succeeds leaves every input tuple in exactly the partition its key hashes to (NULL keys in the last partition of a NULL-fill join, dropped otherwise), however the workers interleave their temp-list flushes. | `split_task::execute` comments (px_hash_join_task_manager.cpp:240 "tuples with NULL in any join column are placed in the last partition"); CBRD-26719 PR #7068 / CBRD-26795 (parallel hash join gives the single-thread answer) |
| C3 | A parallel probe returns the serial probe's rows; for LEFT/ANTI/RIGHT joins every preserved row is emitted with its matches or once NULL-filled, because the probe side is always the preserved side. | `hjoin_init_context` (query_hash_join.c:2467-2515: LEFT/ANTI build = inner, RIGHT build = outer); `execute_outer` comments "NULL key on preserved side" |
| C4 | The phase returns an error iff some worker raised one, and the error it returns is one a worker raised (the first). | `task_manager::handle_error` (first `m_has_error.exchange` swaps its error into the main error context); `build_partitions` / `probe_execute` `error_exit` |
| C5 | No worker touches the leader's stack state (task_manager, shared split/join/probe info, sector scan) after the leader returns, and no worker frees the build hash table it shares. | `task_manager::join` predicate wait; `probe_task::execute` cleanup comment (px_hash_join_task_manager.cpp:810) "skip hash table — owned by single_context, must not be released here" |
| C6 | The transaction interrupt a failing worker raises to stop its peers is cleared before the query goes on. | `task_manager::handle_error` (`logtb_set_tran_index_interrupt (.., true)`) and every leader `error_exit` calling `clear_interrupt` |
| C7 | The phase finishes: the leader's join returns on every path, including every error path. | — (liveness of any query); `base_task::retire` always calls `end_task` |
| C8 | A user cancel that arrives during the phase is not swallowed: the query does not succeed with the cancel consumed. | `hjoin_try_partition` comment (query_hash_join.c:223) "except for ER_INTERRUPTED, never returns HASHJOIN_STATUS_ERROR" — an interrupt is not retried; `check_interrupt` comment |

## Refinement map (model -> code)

| Model | Code (e98bdd885) | One step because |
|---|---|---|
| `key` | the join-key values of each input tuple (`hjoin_fetch_key`) | constant input |
| `pushed`, `L_push` | `task_manager::push_task` (px_task_manager.cpp:46) in the leader's push loop | `++m_active_tasks` under `m_active_tasks_mutex`; the worker can start once `worker_manager::push_task` queued it |
| `active` | `task_manager::m_active_tasks` (and `worker_manager::m_active_tasks`, decremented first in `end_task`) | the counter is only compared with 0 and changed by ±1 under the mutex, so the set of not-yet-ended tasks represents it |
| `W_start` | `cubthread` worker picks the task; `task_execution_guard` | worker-local |
| `W_check` | `m_task_manager.has_error () \|\| m_task_manager.check_interrupt (thread_ref)` at the top of each page / context loop (px_hash_join_task_manager.cpp:149, 525, 903, 1193) | `has_error` is one atomic load; `check_interrupt` is `logtb_is_interrupted_tran (.., clear = true, ..)`: read-and-clear of `tdes->interrupt`, then `er_set (ER_INTERRUPTED)` |
| `W_claim` (`mb = 0`) | `get_next_page` first call: `membuf_claimed.compare_exchange_strong` (list_file.c:3839) | one CAS |
| `W_claim` (`1 <= mb <= NM`) | the CAS winner's sequential walk of the membuf pages (`m_membuf_index++`) | worker-local cursor; the pages are read-only |
| `W_claim` (`next`) | `next_sector_index.fetch_add (1)` (list_file.c:3887); in `join`, `get_next_context` under `scan_mutex` (px_hash_join_task_manager.cpp:597) | one fetch-add / one critical section; a sector holds one page in the model |
| `W_claim` (end) | `get_next_page` returns NULL with `failed () == false`; `get_next_context` returns NULL in `S_AFTER` | same step as the exhausted fetch-add |
| `W_proc` (fail) | `m_page_iter.failed ()`, `qfile_assemble_overflow_tuple`, `hjoin_fetch_key`, `qfile_add_tuple_to_list`, `qfile_open_list`, spawn errors, `hjoin_execute`, `hjoin_probe_key`, `hjoin_eval_pred` = `V_ERROR`, `hjoin_add_tuple_to_list_id` | each error return branches to `handle_error` |
| `W_proc` (split) | `qdata_hash_scan_key` -> `part_id`, `qfile_add_tuple_to_list (temp_part_list_id[part_id])` | the temp list is worker-local |
| `W_proc` (probe) | `hjoin_probe_key` on the shared `single_context` hash table, `hjoin_add_tuple_to_list_id` into the context's own list | the table is read-only during the phase (`mht_get_hls` / `mht_get_next_hls` are const, `fhs_search` read-latches); the context list is worker-owned |
| `W_proc` (join) | `hjoin_execute (m_manager, context)` | the context and its partition lists belong to the claiming worker |
| `W_fl` | the full-temp flush (px_hash_join_task_manager.cpp:297) and the final per-partition merge (:410), and the overflow-tuple append (:262): under `part_mutexes[part_id]`, append to the part list if it has tuples, else destroy it and adopt the temp list | everything between lock and unlock of one partition mutex |
| `W_merge` | the `for (part_index ...)` merge loop after the input ends with no local error | worker-local loop; each partition's critical section is a `W_fl` step |
| `W_err` | `task_manager::handle_error`: `m_has_error.exchange (true)` (px_task_manager.cpp:80) | one atomic exchange |
| `W_swap` | the winner's `m_main_error_context...swap (get_thread_local_error ())` and `notify_stop` | only the winner writes the main error context; the leader reads it after `join`, ordered by `m_active_tasks_mutex` |
| `W_rearm` | `logtb_set_tran_index_interrupt (&thread_ref, tran_index, true)` | one write of `tdes->interrupt` |
| `W_cleanup`, `W_pclean` | split: destroy remaining temp lists; probe: `hash_table = nullptr` then `hjoin_scan_clear` (px_hash_join_task_manager.cpp:815-828) | worker-local state; the shared table pointer is detached before the clear |
| `W_end` | `base_task::retire` -> `task_manager::end_task` (px_task_manager.cpp:57) | `--m_active_tasks` and `notify_all` under the mutex |
| `L_join` | `task_manager::join` (px_task_manager.cpp:69): `wait (lock, [] { return m_active_tasks == 0; })`, then `wait_workers` | the predicate is re-checked under the mutex; `notify_stop` wakes the leader but does not end the wait |
| `L_after` | `if (task_manager.has_error ())` -> `error_exit`: `clear_interrupt` + `er_errid ()`; otherwise `hjoin_merge_qlist` of each context in index order | leader-only after the join |
| `L_free` | the phase returns: `task_manager`, `shared_info`, the sector scan (stack objects) end; `hjoin_clear_manager` frees the hash table at query end | leader-only |
| `L_fallback` | `hjoin_try_partition` `error_exit` (query_hash_join.c:1253-1260): `ER_INTERRUPTED` -> `HASHJOIN_STATUS_ERROR`; any other error -> `er_clear ()` and the single-threaded hash join, which consumes a pending interrupt or runs to completion | leader-only |
| `U_cancel` | `xlogtb_set_interrupt` from the client -> `logtb_set_tran_index_interrupt (.., true)` | one write of `tdes->interrupt` |
| `cnt`, `owner`, `failed`, `uaf`, `cancelled`, `fellBack` | ghosts | |

## Properties

| Name | Kind | Statement | Claim |
|---|---|---|---|
| `TypeOK` | invariant | variable types | — |
| `ExactlyOnce` | invariant | `cnt[v] <= 1` for every unit | C1 |
| `Complete` | invariant | a successful, non-fallback phase yields `ExpParts` (split) / `ExpOut` (join, probe) | C1, C2, C3 |
| `NoLostError` | invariant | once returned, `res # "ok"` iff a worker failed, and `res` is a raised error | C4 |
| `NoUseAfterFree` | invariant | `~uaf` | C5 |
| `NoLeakedInterrupt` | invariant | without a user cancel, the interrupt flag is clear when the query ends | C6 |
| `LeaderFinishes` | liveness, WF on every worker and the leader | `<>(pc[Leader] = "Done")` | C7 |
| `CancelHonored` | invariant | a cancelled query ends with an error or with the interrupt still pending | C8 |
| `IndInv` | inductive invariant | implies ExactlyOnce, NoUseAfterFree, NoLostError, NoLeakedInterrupt; TLAPS-proved for any constants, with `Spec => []IndInv` through PTL | C1, C4, C5, C6 |

## Fault model

| Fault | Modeled as |
|---|---|
| error return | `W_proc` fail branch (every per-unit call listed in the map), `W_fl` fail branch (`qfile_append_list`, `qfile_copy_list_id`, `qfile_reopen_list_as_append_mode`, `qfile_add_tuple_to_list` under the partition mutex) |
| interrupt / query cancel | `U_cancel` at any time before the query ends; `W_check` consumes it at every loop top |
| lock timeout, deadlock victim | not applicable: the phase takes no lock-manager locks (list files of its own query) |
| conditional latch failure | not applicable: list pages are fixed unconditionally by `qmgr_get_old_page`; a fix failure is the `W_proc` error branch |
| OOM | `W_proc` fail branch (`db_private_alloc`, `qdata_alloc_hscan_key`, spawn); the leader's allocations precede the push and have no concurrency |
| crash / kill -9 | not modeled: temp list files do not survive a restart; no state outlives the process |
| spurious wakeup | absorbed: `join` waits with a predicate, so a spurious wakeup re-checks `m_active_tasks == 0` (`L_join` is the predicate) |
| concurrent DML | not applicable: the inputs are the query's own list files |
| vacuum | not applicable: list files are not MVCC heap pages |
| checkpoint, page flush, page replacement | not applicable to the protocol: every page is fixed while it is read |
| HA log apply | not applicable: query execution state is not replicated |
| stale thread-local error | assumed absent: every callee that returns `NO_ERROR` leaves `er_errid () == NO_ERROR` (`ASSERT_NO_ERROR_OR_INTERRUPTED`), and `entry_manager::recycle_context` runs `er_clear ()` after every task (thread_entry_task.cpp:92) |

## Mutants

| cfg | Change | Expected | Kills |
|---|---|---|---|
| `mutant-unlocked-dispenser` | the sector fetch-add / `scan_mutex` counter as a read step and a write step | `ExactlyOnce` violated | C1 |
| `mutant-membuf-no-cas` | `membuf_claimed` tested and set in two steps instead of one CAS | `ExactlyOnce` violated | C1 |
| `mutant-unlocked-flush` | append-or-adopt decided on a part list tuple count read outside `part_mutexes[p]` | `Complete` violated (an adopt overwrites another worker's flush) | C2 |
| `mutant-preserved-build` | the build side is the preserved side (RIGHT join with build = inner): unmatched build rows decided per worker | `Complete` violated | C3 |
| `mutant-end-before-error` | a failing worker ends its task before `handle_error` | `NoLostError` violated | C4 |
| `mutant-early-join` | `join` returns on `notify_stop` (`has_error`) instead of waiting for `m_active_tasks == 0` | `NoUseAfterFree` violated | C5 |
| `mutant-worker-frees-table` | `probe_task` clears its hash_scan without detaching the shared table | `NoUseAfterFree` violated | C5 |
| `mutant-no-clear-interrupt` | the leader's `error_exit` skips `clear_interrupt` | `NoLeakedInterrupt` violated | C6 |
| `mutant-lost-end-on-error` | a failing worker skips `end_task` | deadlock: the leader waits in `L_join` forever | C7 |
| `mutant-check-no-rearm` | a worker that consumes the interrupt in `check_interrupt` stops quietly instead of reporting it | `CancelHonored` violated (probe) | C8 |

## Witnesses

| cfg | Reached state |
|---|---|
| `witness-worker-error` | the query ends with a worker's error |
| `witness-fallback` | a split error falls back to the single-threaded join, which succeeds |
| `witness-cancel` | a user cancel during the phase ends the query with `ER_INTERRUPTED` |
| `witness-both-dispensers` | one worker takes the membuf region and another a sector, and the probe succeeds |
| `witness-lost-cancel-split` | **C8 does not hold for `split`** on the correct model (see Counterexamples) |

## Counterexamples

### `witness-lost-cancel-split` — hole candidate (question, not reproduced)

Correct variant, `Phase = "split"`, 2 workers, 2 pages (`PxHashJoin.witness-lost-cancel-split.cfg`), 24 states:

| # | Step | Code |
|---|---|---|
| 1 | leader pushes both split tasks | `build_partitions` -> `task_manager.push_task` (px_hash_join.cpp:84-88) |
| 2 | w2 claims page 1 | `sector_page_iterator::get_next_page` fetch-add (list_file.c:3887) |
| 3 | the user cancels: `tdes->interrupt = 1` | `xlogtb_set_interrupt` -> `logtb_set_tran_index_interrupt` |
| 4 | w2 fails on page 1 with an error other than `ER_INTERRUPTED` (temp file append, overflow assembly, key coercion) | `split_task::execute` -> `m_task_manager.handle_error` |
| 5 | w2 wins `m_has_error.exchange`, swaps its error into the leader, re-sets the interrupt | px_task_manager.cpp:80-84 |
| 6 | w1 sees `has_error ()` first and stops without calling `check_interrupt` | px_hash_join_task_manager.cpp:149 (short-circuit `\|\|`) |
| 7 | both end; the leader's join returns; `has_error ()` -> `error_exit` -> `clear_interrupt` consumes `tdes->interrupt` — the user's cancel with it | px_hash_join.cpp:150, px_task_manager.cpp:115-122 |
| 8 | `hjoin_try_partition` sees an error other than `ER_INTERRUPTED`, `er_clear ()`, falls back to `HASHJOIN_STATUS_SINGLE` | query_hash_join.c:1253-1260 |
| 9 | the single-threaded join finds no interrupt pending and the query completes with rows | `hjoin_execute` |

Every step maps to code and no protection forbids the interleaving: the transaction has one interrupt
bit, and `clear_interrupt` cannot tell the bit a worker raised to stop its peers from the bit the
user raised. The window is from the first worker error to the leader's `clear_interrupt`; the loss
needs a non-interrupt worker error in the split phase in that window, and the single-threaded retry
must then succeed (a deterministic data error such as a key coercion failure fails again and is
reported, so only transient errors — temp space, a page fetch — lose the cancel). The join and probe
phases have no fallback and return the worker's error, so C8 holds there (`CancelHonored` is in
`PxHashJoin.probe.cfg`, `probe-inner.cfg`, `join.cfg`).

Classification: **hole**, pending a runtime reproduction (inject a split-worker error after a
cancel on an instrumented optdebug build, `cubrid-diagnose`). Until then it is a question.

## Dead expressions (pass cfgs)

| Line | Why never evaluated |
|---|---|
| PxHashJoin.tla:410 | mutant-only: `check_no_rearm` branch of W_check (the correct variant goes to W_err) |
| PxHashJoin.tla:428, PxHashJoin.tla:429, PxHashJoin.tla:430, PxHashJoin.tla:431 | mutant-only: `membuf_no_cas` read half of the membuf claim |
| PxHashJoin.tla:454, PxHashJoin.tla:455, PxHashJoin.tla:456, PxHashJoin.tla:457 | mutant-only: `unlocked_dispenser` read half of the sector fetch_add |
| PxHashJoin.tla:482, PxHashJoin.tla:483, PxHashJoin.tla:484, PxHashJoin.tla:485, PxHashJoin.tla:486, PxHashJoin.tla:487, PxHashJoin.tla:488, PxHashJoin.tla:489, PxHashJoin.tla:490, PxHashJoin.tla:491, PxHashJoin.tla:499, PxHashJoin.tla:500, PxHashJoin.tla:501, PxHashJoin.tla:502, PxHashJoin.tla:503, PxHashJoin.tla:504, PxHashJoin.tla:505, PxHashJoin.tla:506, PxHashJoin.tla:507, PxHashJoin.tla:508, PxHashJoin.tla:509, PxHashJoin.tla:510 | mutant-only labels W_cas_write / W_fa_write (`membuf_no_cas`, `unlocked_dispenser`) |
| PxHashJoin.tla:549, PxHashJoin.tla:550, PxHashJoin.tla:551, PxHashJoin.tla:552, PxHashJoin.tla:573, PxHashJoin.tla:574, PxHashJoin.tla:575, PxHashJoin.tla:576, PxHashJoin.tla:578, PxHashJoin.tla:579, PxHashJoin.tla:580, PxHashJoin.tla:581, PxHashJoin.tla:582 | mutant-only: `unlocked_flush` read in W_fl and its label W_fl_write |
| PxHashJoin.tla:590, PxHashJoin.tla:591, PxHashJoin.tla:592, PxHashJoin.tla:593, PxHashJoin.tla:594 | mutant-only: `end_before_error` branch of W_err |
| PxHashJoin.tla:679 | W_end ELSE branch: `ended[self]` is TRUE only after the `end_before_error` branch, so mutant-only |
| PxHashJoin.tla:723 | mutant-only: `no_clear_interrupt` branch of L_after |
| PxHashJoin.tla:423, PxHashJoin.tla:424, PxHashJoin.tla:425 | W_claim with NM = 0: dead in the cfgs with a membuf (NM = 1); fires in `join` (NM = 0) |
| PxHashJoin.tla:434, PxHashJoin.tla:435, PxHashJoin.tla:436, PxHashJoin.tla:437, PxHashJoin.tla:438, PxHashJoin.tla:439, PxHashJoin.tla:440, PxHashJoin.tla:441, PxHashJoin.tla:442, PxHashJoin.tla:443, PxHashJoin.tla:444 | W_claim's correct CAS on the membuf: dead in `join` (NM = 0); fires in the NM = 1 cfgs |
| PxHashJoin.tla:447, PxHashJoin.tla:448, PxHashJoin.tla:449, PxHashJoin.tla:450, PxHashJoin.tla:451, PxHashJoin.tla:452 | W_claim taking a membuf row: dead in `join` (NM = 0); fires in the NM = 1 cfgs |
| PxHashJoin.tla:524, PxHashJoin.tla:525, PxHashJoin.tla:526, PxHashJoin.tla:527, PxHashJoin.tla:528, PxHashJoin.tla:529, PxHashJoin.tla:530, PxHashJoin.tla:531, PxHashJoin.tla:532 | W_proc split branch (append to temp, maybe flush): dead in `probe`, `probe-inner`, `join`; fires in the split cfgs |
| PxHashJoin.tla:534, PxHashJoin.tla:535, PxHashJoin.tla:536 | W_proc probe branch: dead in the split cfgs and `join`; fires in `probe`, `probe-inner` |
| PxHashJoin.tla:537, PxHashJoin.tla:538, PxHashJoin.tla:539, PxHashJoin.tla:540 | W_proc join branch (`ctx` row): dead in the split and probe cfgs; fires in `join` |
| PxHashJoin.tla:553, PxHashJoin.tla:554, PxHashJoin.tla:555, PxHashJoin.tla:556, PxHashJoin.tla:557, PxHashJoin.tla:558, PxHashJoin.tla:559, PxHashJoin.tla:561, PxHashJoin.tla:562, PxHashJoin.tla:563, PxHashJoin.tla:564, PxHashJoin.tla:565, PxHashJoin.tla:566, PxHashJoin.tla:567 | W_fl (split-only label): dead in `probe`, `probe-inner`, `join` |
| PxHashJoin.tla:629, PxHashJoin.tla:630, PxHashJoin.tla:643, PxHashJoin.tla:644, PxHashJoin.tla:645, PxHashJoin.tla:646, PxHashJoin.tla:647, PxHashJoin.tla:648, PxHashJoin.tla:649, PxHashJoin.tla:650, PxHashJoin.tla:651 | W_cleanup -> W_merge and W_merge (split-only): dead in `probe`, `probe-inner`, `join` |
| PxHashJoin.tla:659, PxHashJoin.tla:660 | W_pclean split branch: dead in `probe`, `probe-inner`, `join` |
| PxHashJoin.tla:662, PxHashJoin.tla:664 | W_pclean probe branch: dead in the split cfgs and `join`; fires in `probe`, `probe-inner` |
| PxHashJoin.tla:666, PxHashJoin.tla:667 | W_pclean join branch: dead in the split and probe cfgs; fires in `join` |
| PxHashJoin.tla:746, PxHashJoin.tla:748, PxHashJoin.tla:749, PxHashJoin.tla:750, PxHashJoin.tla:751 | L_fallback split branch (`hjoin_try_partition` retry): dead in `probe`, `probe-inner`, `join`; fires in the split cfgs |

Every line dead in all six pass cfgs (main, split-inner, probe, probe-inner, join, scale-3-workers) is in a mutant-only row; the others fire in the cfg of their phase. No row is a hole.

## Bounds and limits

- TLC: 2 workers, 3 units (1 membuf page), 3 partitions, every key assignment over {k1, k2, NULL}
  for split and probe, both NullFill values (`PxHashJoin.cfg`, `split-inner`, `probe`, `probe-inner`,
  `join`); scale: 3 workers, 2 units (`scale-3-workers`). Mutants and witnesses: 2 workers, 2 units.
- Inductive check (TLC from every IndInv state): `inductive-indinv` (join, 2 workers, 1 unit, no
  membuf) and `inductive-split-1w` (split, 1 worker, 1 unit, 1 membuf page); 2 workers in split or
  probe do not enumerate (PITFALLS P23). TLAPS covers every size.
- TLAPS: `IndInv` is inductive and implies ExactlyOnce, NoUseAfterFree, NoLostError and
  NoLeakedInterrupt for any workers, units, membuf size, partitions, phase and NullFill (C1, C4, C5,
  C6), and `Safe == Spec => []IndInv` is proved through PTL. The proof is generated (one lemma per
  action, one step per IndInv part, a branching action per branch of its effect) and split into
  `PxHashJoin_proofs_base` (helper lemmas, InitInv, InvSafe), `_lead`, `_wsimple`, `_claim`, `_proc`,
  `_rest` (the StepInv lemmas) and `PxHashJoin_proofs` (StepInv, Safe).
- TLC only, inside the bounds above: `Complete` (C2, C3), `CancelHonored` (C8) and the liveness C7.
- Assumptions the proof adds to the cfgs' model values: `Workers # {}` and `"none" \notin Workers`
  (the CAS owner sentinel).
- One split pass: the outer and inner passes of `build_partitions` reuse one `task_manager`, and the
  inner pass runs only when the outer one had no error, so the second pass starts from the state
  the model ends in with `res = "ok"`.
- A sector holds one page; within a sector the pages a worker walks are worker-local.
- `next` stops at `NU + 1` (the real fetch-add keeps counting past `sector_cnt`; every value past it
  means "end").
- Not modeled: the per-unit computation itself (hashing, `hjoin_execute`, predicate evaluation);
  `qfile` list internals beyond append-or-adopt; the `num_interrupts` counter of
  `logtb_set_tran_index_interrupt` / `logtb_is_interrupted_tdes`, whose read-check-write is not atomic
  across the workers that set and clear the same `tdes->interrupt` (it only feeds `continue_checking`).
- The model trusts that `m_active_tasks`, the partition lists and the context dispenser are touched
  only under their mutexes; a change that moves any of them out invalidates the rows above.

## Trace validation

Not done. The task verifies existing develop code rather than a change under review; a trace check
needs an instrumented optdebug build of `e98bdd885` with `TLATRACE` events at every row above. It is
the next step if the C8 hole is taken to reproduction, since the same build can inject the split
error.

## Result

- 2026-11-06, `tools/tla/tla-check --workers 16 --stretch 4 docs/tla/parallel-hash-join`: `RESULT: OK`,
  run dir `.git_ignored_dir/scratch/tla/parallel-hash-join-20261106-043752-2448559`.
  The first run (`-20261106-025330-2404484`) failed on missing `uncovered-ok` lines, the dead-expression
  table, and 122 prover timeouts under a load average of ~96 on 64 cores; each proof module had
  proved in full when run alone, and `--stretch 4` with `\* timeout: 5400` per module cleared them.
- Toolchain `pkpvq91yw7b91465jplq1nvhkrv4z34c-tla-tools` (tla2tools 1.8.0, tlapm 1.6.0-pre). Engine: `e98bdd885` (read only; no build, no trace).
- TLC (states generated / distinct, depth):

| cfg | result | states | depth |
|---|---|---|---|
| main (split, NullFill, 2 workers, NU 3, NM 1, NP 3) | pass | 9177219 / 3928284 | 48 |
| split-inner | pass | 5125683 / 2204526 | 46 |
| probe | pass | 772929 / 356346 | 34 |
| probe-inner | pass | 772929 / 356346 | 34 |
| join (NM 0) | pass | 28189 / 13023 | 34 |
| scale-3-workers (NU 2) | pass | 39466686 / 12530760 | 56 |
| inductive-indinv (join, 2 workers) | pass | 103723008 / 31072256 | 1 |
| inductive-split-1w | pass | 5159424 / 2104320 | 1 |
| 10 mutants | each rejected as expected (Mutants table) | | |
| 5 witnesses | each reached, incl. `witness-lost-cancel-split` (C8) | | |

- TLAPS (tlapm 1.6.0-pre): 2776/2776 obligations proved, none OMITTED: `_base` 70, `_lead` 300,
  `_wsimple` 449, `_claim` 655, `_proc` 628, `_rest` 576, `PxHashJoin_proofs` 98
  (`Safe == Spec => []IndInv` through LS4, `InvSafe` gives ExactlyOnce, NoUseAfterFree, NoLostError,
  NoLeakedInterrupt for any worker set and any NU, NM, NP).
- Spec sha256 (summary.txt):

```
b483c0d69690166166c6582bc4a17baea6695c0b528f6bfb1ddbe28a0212e24d  PxHashJoin.tla
5624aa0ee3cc3f047e6bddb7bc437510df3c12c6c9188d4ce61ad839d9a44d4c  PxHashJoin_proofs.tla
5f7a5a13519b3172f7d98a5686e0c1e7ac85be57447af46a6d28fa4280ab1091  PxHashJoin_proofs_base.tla
c0c98a89dd0acc7c876aa8a95b963a92a20ce8e7b95070e99e0894790eb9a115  PxHashJoin_proofs_claim.tla
9175923a17bbd758ac00da5f01004b84691f769c877bba16ddfcecbbe14d35be  PxHashJoin_proofs_lead.tla
1ead15b881e3aff1c6ce32884a038841b8fb7c532baceb68edf59d611e2f5a25  PxHashJoin_proofs_proc.tla
d40dde1b2ac723bdce0731e29a92c40ed80d96565663bae9087960a04765857f  PxHashJoin_proofs_rest.tla
eec8b6c2e0f10784cb37e4b0b2e2450fa1f479ad035583e12baf89673dd799f9  PxHashJoin_proofs_wsimple.tla
```
