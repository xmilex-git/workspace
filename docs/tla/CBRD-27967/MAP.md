# CBRD-27967 fix design — the statement's snapshot before every parallel heap scan's bitmap

Design spec for the fix of CBRD-27967 (H1 of `docs/tla/parallel-scan/heap`): under READ COMMITTED
the leader collects a parallel heap scan's page bitmap at open before the statement's MVCC snapshot
exists, and a transaction committing in between is seen only in part. This module abstracts page
latches away (one page read per step, as `PxHeapSnapshot` in `docs/tla/parallel-scan/heap`) and adds
what the fix must decide: where the snapshot is built, whether the leader's build is under
`m_px_lock_mutex`, and several parallel heap scans in one statement sharing the snapshot.

Code: develop `953e83256` (worktree `~/dev/cubrid-worktree/CBRD-27967`).

Implementation: branch CBRD-27967 `59805c39d` on develop `953e83256` (the trace runs below used `63a00a185`, the same change plus the D4 assert that D6 dropped; the assert held in every run). The latch-level code model `docs/tla/parallel-scan/heap/PxHeapScan.tla` still models develop and is not yet refined against this spec.

## Claim and sources

| # | Claim | Source |
|---|---|---|
| C1 | Each parallel heap scan of a statement returns exactly the rows of its heap visible to the statement's MVCC snapshot, each once, while other transactions insert (into pages allocated after open too) and delete and vacuum removes rows and empty pages. | CBRD-27967 Expected Result (B 전 또는 B 후 한 시점), CBRD-25447 (same result as the serial scan) |
| C2 | Once built, the statement's snapshot never changes while the statement runs: every scan of the statement, its leader and its workers read through one snapshot. Scope: statements without a nested statement (D6). | CUBRID manual `sql/transaction.rst` READ COMMITTED: "Transaction T1 creates a new snapshot with each executed statement" |
| C3 | Every parallel heap scan of the statement finishes. | CBRD-27723 (no deadlock with vacuum), and the fix must not add a wait |
| C4 | A parallel heap scan's worker never builds the snapshot: it reuses the one its leader built before collecting the bitmap. Scope: statements without a nested statement (D6). | grilling 2026-11-06 Q5 (the user: the leader alone builds); scope narrowed by Q7 |

## Decisions (grilling 2026-11-06)

| # | Decision | Rejected alternative and why | Model |
|---|---|---|---|
| D1 | Claims C1-C4, scope the parallel heap scan; the no-deallocated-read property stays in the code model `docs/tla/parallel-scan/heap` (the fix does not touch the read path) | parallel index scan: `init_on_main` evaluates key ranges and the root header only, the leaf descent is at the first `next`; parallel list scan: reads a list file finished before its open | fault table rows |
| D2 | The leader builds the snapshot in `input_handler_heap::init_on_main` right before `file_get_all_data_sectors` (px_scan_input_handler_heap.cpp:63), for every isolation level (a no-op when one exists) | `qexec_execute_query` for every isolation (`fix-query-start`): passes C1-C4 too, but every READ COMMITTED statement (INSERT VALUES included) would build a snapshot and move its vacuum horizon earlier | `SnapshotAt = "collect"` in the main cfg |
| D3 | The leader's build is under `m_px_lock_mutex`: `manager::open` sets `m_px_orig_thread_entry = m_thread_p` (px_scan.cpp:1784-1787) before `init_on_main`, so `logtb_get_mvcc_snapshot` takes its existing locked branch | an unlocked build relies on no other thread of the statement building at the same time (`fix-unlocked-no-other` passes only with `OtherPx = FALSE`; no such path was found in the code, but nothing enforces it) | `LeaderLock = TRUE`; `mutant-unlocked-leader` |
| D4 | ~~An optdebug assert that the snapshot is already valid before the heap worker's `scan_start_scan`~~ dropped by D6: the worker keeps `scan_start_scan`'s build for a snapshot a nested statement invalidated. Leader-only building stays the design for statements without a nested statement (C4). | making every parallel operator's workers reuse only (px_query, hash/merge join, GROUP BY, sort, index/list scans): every launch site would have to build first; out of this ticket | C4, `WorkerReuses` |
| D6 | (Q7, 2026-11-06) A statement whose SP runs SQL from the client gets its snapshot invalidated mid-statement (`db_execute_statement` -> `tm_Tran_invalidate_snapshot` -> `network_sr.c:924 logtb_invalidate_snapshot_data`), and the nested statement builds a new one that the outer scans then read through. Measured on the fix probe build: `select /*+ parallel(4) */ f27967 (b.id), b.id from t b where b.id < 4` logged one `snapshot_built` per SP call after `L_open snapshot_valid=1`. This is develop's READ COMMITTED behavior and stays: C2 and C4 are scoped to statements without a nested statement, and D4's assert is dropped (a worker starting after the first SP call would find the snapshot invalid). | keep the assert (a rare optdebug abort on a valid query); pin the outer statement's snapshot against nested statements (changes READ COMMITTED for SP-bearing statements; a separate ticket) | `Nested`; `witness-nested-changes-snapshot`, `witness-nested-worker-builds` |
| D5 | The serial heap scan and every other scan type keep building the snapshot in `scan_start_scan` (scan_manager.c:4033, 4141) | building at every heap scan's open for uniformity: the serial scan follows the page chain and needs no early snapshot, heap would differ from index, and two callers of `scan_open_heap_scan` drop its return value (query_executor.c:11019, 12954) | not modeled (no page set is fixed) |

No ADR: the placement is a few lines and easy to move; the rule ("whoever fixes the page set builds the snapshot first") goes into the code comment and the JIRA design.md.

## Refinement map (model -> code)

| Model | Code | One step because |
|---|---|---|
| `QueryStart` | `query_executor.c:23118-23123 qexec_execute_query`: `logtb_get_mvcc_snapshot` when isolation >= REPEATABLE READ (`SnapshotAt = "query_start"`: for every isolation) | one call before `qexec_execute_mainblock`; no worker exists yet |
| `LeaderSnap(s)` | the fix: `logtb_get_mvcc_snapshot` by the leader before `px_scan_input_handler_heap.cpp:63 file_get_all_data_sectors`; `log_tran_table.c:4391-4405` test-and-build under `m_px_lock_mutex` | the mutex makes the test and the build one step (`LeaderLock = TRUE`) |
| `LeaderTest(s)`, `LeaderWrite(s)` | the same call with `thread_p->m_px_orig_thread_entry == NULL`: `log_tran_table.c:4397` tests `snapshot.valid` and `4399 build_mvcc_info` builds without the mutex | two steps: nothing excludes another builder between the test and the build |
| `Collect(s)` | `px_scan.cpp:1727` `manager::open` -> `px_scan_input_handler_heap.cpp:57 init_on_main`: `file_get_all_data_sectors` (line 63), `ftab_set::split (parallelism)` (line 73); callers `query_executor.c:10991` (`qexec_open_scan`) and `12925` (partition reopen) | the file's sector table is read under the file header latch |
| `Start(s, w)` | `px_scan.cpp:1884 start_tasks` from the first `manager::next`; `px_scan_task.cpp:251 scan_start_scan` -> `scan_manager.c:4033 logtb_get_mvcc_snapshot` (the worker's `m_px_orig_thread_entry` is the leader, `px_scan_task.cpp:100`, so it locks) | test-and-build under `m_px_lock_mutex` |
| `ReadPage(s, w, i)` | `px_scan_input_handler_heap.cpp get_next_vpid_with_fix`: `pgbuf_ordered_fix (OLD_PAGE_MAYBE_DEALLOCATED)`, a deallocated page skipped (`ER_PB_BAD_PAGEID`), then the slot iteration with the snapshot's visibility check | the page's read latch excludes insert, delete and vacuum (latch-level steps in `PxHeapScan.tla`) |
| `Finish(s)` | the leader's join of the scan's workers (`manager::next` reaching the end) | |
| `OtherBuild` | another parallel operator's worker of the same statement calling `logtb_get_mvcc_snapshot`: px_query workers (`px_query_task.cpp:124`, the leader set to itself at `px_query_executor.cpp:309`), task-manager workers (`px_task_manager.hpp:92`), `query_executor.c:7510` | under `m_px_lock_mutex` (the worker's orig entry is the leader) |
| `Insert`, `Delete` | `heap_insert` (a new page by `file_alloc` when needed) and `heap_delete`, each with its commit | the commit is one step (`clock`) |
| `VacuumRows`, `VacuumPage` | `vacuum.c vacuum_heap_page`; `heap_file.c heap_remove_page_on_vacuum` -> `file_dealloc` | under the page's X latch |
| `snap` | `tdes->mvccinfo.snapshot` (one per transaction; `valid` false = 0); READ COMMITTED invalidates it at the next statement (`network_sr.c:924 logtb_invalidate_snapshot_data`, flag from `db_vdb.c:6549`) | |
| `readCnt` | ghost: times a row was returned | — |
| trace event `snapshot_built` | probe in `log_tran_table.c logtb_get_mvcc_snapshot`, printed right after `build_mvcc_info` while the build still holds `m_px_lock_mutex` when taken | the build step (`QueryStart`, `LeaderSnap`, `Start`, `OtherBuild` with `snap = 0`) |
| trace event `L_open snapshot_valid=` | probe at the end of `scan_open_parallel_heap_scan` (after `manager::open` returned, before the env-gated delay) | `Collect`: no step of the statement builds a snapshot between `init_on_main` and the print (the leader thread runs both; workers start at the first `next`) |

## Properties

| Name | Kind | Statement | Claim |
|---|---|---|---|
| `TypeOK` | invariant | variable types | — |
| `SameAsSnapshot` | invariant | when a scan is done, each row of its heap was returned once if visible to the snapshot and never otherwise | C1 |
| `SnapshotStable` | action property | `[][snap # 0 => snap' = snap]_vars` | C2 |
| `StatementFinishes` | liveness, `WF_vars(ScanStep)`, `WF_vars(OtherBuild)` | `<>AllDone` | C3 |
| (deadlock check) | TLC | no reachable state without a successor before the end | C3 |
| `WorkerReuses` | action property | `[][\A s, w : Start(s, w) => snap # 0]_vars` | C4 |
| `IndInv` | inductive invariant of the fix | implies `SameAsSnapshot`, the step `snap # 0 => snap' = snap` and the step `Start(s, w) => snap # 0` | C1, C2, C4 |

## Fault model

| Fault | Modeled as |
|---|---|
| concurrent INSERT on any page, including one allocated after a scan's open, committed at any point | `Insert` |
| concurrent DELETE, committed at any point | `Delete` |
| vacuum removes rows deleted before every live snapshot, then deallocates an emptied page | `VacuumRows`, `VacuumPage`, at most `VacuumRounds` |
| several parallel heap scans in one statement, open in any order or at the same time (partitions, joins, px_query subqueries) | `Scans`, every interleaving |
| another thread of the statement builds the snapshot first | `OtherBuild` (`OtherPx`) |
| the leader's build races another builder | `LeaderTest`/`LeaderWrite` (`LeaderLock = FALSE`) |
| an SP's SQL from the client invalidates the statement's snapshot mid-statement (READ COMMITTED) | `NestedInvalidate` (`Nested = TRUE`), out of the claims' scope (D6): the witnesses show it changes the snapshot and lets a late worker rebuild it, as on develop |
| READ COMMITTED vs REPEATABLE READ | `Isolation` |
| error at open (`file_get_all_data_sectors`, OOM) | not modeled: the scan fails before any row is returned, and the snapshot stays valid for the statement |
| interrupt, lock timeout, deadlock victim | not modeled: a parallel heap scan takes no row lock (`px_scan.cpp:392`, `mvcc_select_lock_needed` falls back to the serial scan) and an interrupt ends the statement with an error |
| crash / kill -9 | not applicable: a scan is read-only |
| parallel index scan, parallel list scan | not applicable: the index's `init_on_main` evaluates key ranges and the root header only (`px_scan_input_handler_index.cpp:32`, leaf descent at the first `next`, `m_descent_done = false`); a list scan reads a list file finished before its open |

## Mutants

| cfg | Change | Expected | Kills |
|---|---|---|---|
| `mutant-code` | READ COMMITTED, the snapshot built by the first worker (the code, H1) | `SameAsSnapshot` violated | C1 |
| `mutant-unlocked-leader` | the leader's build at open without `m_px_lock_mutex` while another operator's worker builds | `SnapshotStable` violated | C2 |
| `mutant-collect-without-build` | the leader requires a valid snapshot before collecting but does not build one | deadlock | C3 |
| `mutant-worker-builds` | READ COMMITTED with the snapshot built by the first worker (the code) | `WorkerReuses` violated | C4 |

## Witnesses

| cfg | Reached state |
|---|---|
| `witness-row-on-new-page` | a committed row lives on a page allocated after its scan's open |
| `witness-other-built-first` | another operator's worker built the snapshot before any leader |
| `witness-dealloc-during-scan` | vacuum deallocated a bitmap page while its scan ran |
| `witness-all-scans-read` | every scan finished having returned a row |
| `witness-nested-changes-snapshot` | with `Nested = TRUE` the statement's snapshot changes (`SnapshotStable` violated): develop's READ COMMITTED behavior with an SP running SQL |
| `witness-nested-worker-builds` | with `Nested = TRUE` a worker starts after the invalidation and builds a new snapshot (`WorkerReuses` violated): why D4's assert was dropped |

## Trace validation

Probe = `traces/probe.diff` (the two TLATRACE lines and `CUBRID_TLA_PX_OPEN_DELAY_MS`), applied to scratch worktrees of develop `953e83256` (libcubrid `0d312019602df0200f4ef5ae8393cc427bbea3918ccb5f6f7fc6311f605ff45e`) and the fix `63a00a185` (`bd9908cc3bc8100ac68028ecc17af6df01cbfacbd8cbd0a0d0608866dbfd9dc1`), optdebug. Scenario: CBRD-27967's repro (5000-row `t`, 2000-row `src`), delay 5000 ms, session B's `insert ... select /*+ no_parallel_scan */` so B itself is not delayed. Only the statement A's events (tran=1) are kept; B's are its own transaction (`Insert`/`Delete`, hidden).

| cfg | Run | Result |
|---|---|---|
| `PxHeapRcSnapshotTrace.witness-trace-fix-run1` | `traces/fix-run1.log` (fix): `snapshot_built`, then `L_open snapshot_valid=1`; A returned `5000 0 1` | accepted by the fix (`SnapshotAt = "collect"`) |
| `PxHeapRcSnapshotTrace.witness-trace-base-run2-on-code` | `traces/base-run2.log` (develop): `L_open snapshot_valid=0`, then a worker's `snapshot_built`; A returned `5003 4 0` | accepted by the code (`SnapshotAt = "worker_start"`) |
| `PxHeapRcSnapshotTrace.reject-base-run2-on-fix` | the develop run | refused by the fix at its first event |

Runtime: develop probe 3/3 runs `5003 4 0` (B's delete seen, 4 of its 2000 inserted rows seen: the ones on pages that existed at open), fix probe 3/3 runs `5000 0 1`; serial and parallel counts afterwards 6999 in every run.

## Dead expressions (pass cfg)

Line numbers are in `PxHeapRcSnapshot.tla`.

| Line | Why never evaluated |
|---|---|
| PxHeapRcSnapshot.tla:140, PxHeapRcSnapshot.tla:141, PxHeapRcSnapshot.tla:142 | `LeaderSnap`'s effect: in `fix-query-start` and `rr` the snapshot exists before open (`QueryStart`), so the leader does not build; in `fix-unlocked-no-other` the leader builds unlocked (`LeaderTest`, `LeaderWrite`). The main, scale and two-scans cfgs fire it. |
| PxHeapRcSnapshot.tla:147, PxHeapRcSnapshot.tla:148 | `LeaderTest`'s effect: the unlocked build, enabled only with `LeaderLock = FALSE` (`fix-unlocked-no-other`, `mutant-unlocked-leader`) |
| PxHeapRcSnapshot.tla:153, PxHeapRcSnapshot.tla:154, PxHeapRcSnapshot.tla:155 | `LeaderWrite`'s effect: same as `LeaderTest` |
| PxHeapRcSnapshot.tla:193, PxHeapRcSnapshot.tla:194, PxHeapRcSnapshot.tla:195 | `OtherBuild`'s effect in `fix-unlocked-no-other` (`OtherPx = FALSE`: no other operator builds) |
| PxHeapRcSnapshot.tla:200, PxHeapRcSnapshot.tla:201 | `NestedInvalidate`'s effect: every pass cfg has `Nested = FALSE` (the claims' scope, decision D6); `witness-nested-changes-snapshot` and `witness-nested-worker-builds` fire it |
| PxHeapRcSnapshot.tla:230, PxHeapRcSnapshot.tla:231, PxHeapRcSnapshot.tla:232 | `VacuumPage`'s effect in `two-scans` (`VacuumRounds = 1`: one pass cannot both remove a row and free its page); every single-scan cfg (`VacuumRounds = 2`) fires it |

## Bounds and limits

- TLC: main and variant cfgs 1 scan, 2 workers, 2 pages (1 initial row, 1 new row), 2 vacuum passes, another operator's builder; `scale-3-workers` 3 workers; `two-scans` 2 scans of 1 worker each, 1 vacuum pass (two scans with two workers each did not finish: 9.3 M distinct states at depth 15 after 25 min, the queue still growing).
- Apalache (`apalache-indinv`): IndInv inductive with 2 scans, 2 workers, 2 pages fixed and the vacuum rounds and the clock open.
- TLAPS: C1, C2 and C4 for every number of scans, workers, pages and rows, for statements without a nested statement (`~Nested`, D6), for every fix variant (`Fix`: the snapshot before every collect, the leader's build locked whenever it builds); C3 (liveness) is TLC only, inside the bounds above (no fairness proof, decision Q4).
- The model abstracts page latches (one page read per step); the latch-level steps, the deallocated-page skip and the CBRD-27723 deadlock freedom are in `docs/tla/parallel-scan/heap/PxHeapScan.tla`, which the implementation's model must extend with the fix and refine this spec (cubrid-tla step 9).
- Not modeled: an error at open (the statement fails before any row is returned), partitions beyond "one scan per heap" (each partition is a scan of its own heap), overflow records, worker lock requests (a parallel heap scan takes none).

## Result

2026-11-06, `tools/tla/tla-check --prove --workers 16 docs/tla/CBRD-27967`: **RESULT: OK**. Run dir
`.git_ignored_dir/scratch/tla/CBRD-27967-20261106-152705-233626`. Engine: develop `953e83256`, fix `59805c39d`
(optdebug libcubrid `4b236c78258878270b4411f148a7592d084a5430f765b2ffcce96cd8cf8a1572`, release
`3050046579fb2f9e7598b2a63281b8c5bd8e1a66ffb5d18ebe012490978bb6a4`); trace runs on the probe builds above.

| cfg | Result | States / distinct | Depth |
|---|---|---|---|
| `PxHeapRcSnapshot` (the fix: collect, locked leader, another builder) | pass | 68,135 / 20,882 | 15 |
| `fix-query-start` (D2's rejected alternative) | pass | 67,222 / 20,554 | 14 |
| `rr` (REPEATABLE READ, as develop) | pass | 67,222 / 20,554 | 14 |
| `fix-unlocked-no-other` (D3's alternative, no other builder) | pass | 29,998 / 10,532 | 15 |
| `scale-3-workers` | pass | 305,883 / 82,440 | 16 |
| `two-scans` | pass | 18,415,459 / 4,551,506 | 22 |
| `mutant-code` (H1) | `SameAsSnapshot` violated (killed) | 12,171 / 5,299 | 9 |
| `mutant-unlocked-leader` | `SnapshotStable` violated (killed) | 641 / 430 | 8 |
| `mutant-collect-without-build` | deadlock (killed) | 397 / 203 | 7 |
| `mutant-worker-builds` | `WorkerReuses` violated (killed) | 156 / 127 | 6 |
| `witness-nested-changes-snapshot` / `witness-nested-worker-builds` | reached | 141 / 763 | 6 / 7 |
| `witness-row-on-new-page`, `-other-built-first`, `-dealloc-during-scan`, `-all-scans-read` | reached | — | — |
| `PxHeapRcSnapshotTrace.witness-trace-fix-run1` / `-base-run2-on-code` | accepted | 211 / 135 | 6 / 6 |
| `PxHeapRcSnapshotTrace.reject-base-run2-on-fix` | refused | 174 / 102 | 6 |
| `apalache-indinv` | IndInv inductive | — | 1 step |

TLAPS (tlapm `efe4f2d`): `PxHeapRcSnapshot_proofs.tla` 2253/2253 obligations proved, none omitted —
`InitInv`, `StepInv`, `Safe` (`Spec => []IndInv`), `InvSafe` (C1), `StableSafe` (C2), `ReuseSafe` (C4), for
`~Nested`. C3 is TLC only.

Spec sha256: `PxHeapRcSnapshot.tla` 246f6717bf2c546437283d69dbc85fbd574c11cf7a89c1757365df23c8e5a01c,
`PxHeapRcSnapshot_proofs.tla` f16ab3427da5eda0e30e08dff9c5e3509c8429edb6b403628ea55c1562f04c13,
`PxHeapRcSnapshotTrace.tla` 0d04887b1c545bba1dd12764d00617e0ec3092d038a5c364544bd925cbe136eb.
