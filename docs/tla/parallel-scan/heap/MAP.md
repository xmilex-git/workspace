# Parallel heap scan — the snapshot's rows, once each, against INSERT, DELETE and vacuum's page removal

Code: develop `e98bdd885`. The spec is spread over CBRD-25447 (parallel heap scan: the same result
as the serial scan), CBRD-26722 (heap, index and list behind one parallel scan), CBRD-26012
(partitions), CBRD-26615 (page I/O), CBRD-26863/CBRD-27737 (Expected Results under concurrent DML
and vacuum) and CBRD-27723 (deadlock with vacuum removing an empty heap page). Each claim is what
those issues require of every run.

## Claim and sources

| # | Claim | Source |
|---|---|---|
| C1 | The scan returns exactly the rows visible to the statement's MVCC snapshot, each once, while other transactions insert (new pages) and delete and vacuum removes rows and empty pages. | CBRD-25447 (same result as the serial scan), CBRD-26722, CBRD-26863 / CBRD-27737 Expected Results |
| C2 | The scan finishes; it does not deadlock with vacuum removing an empty page. | CBRD-27723 |
| C3 | No worker reads a page vacuum has deallocated since the bitmap was collected. | CBRD-27723 (`OLD_PAGE_MAYBE_DEALLOCATED` skip) |

## Refinement map (model -> code)

| Model | Code | One step because |
|---|---|---|
| `L_snapshot` | `query_executor.c:23117-23122` (`qexec_execute_query`): `logtb_get_mvcc_snapshot` only when isolation >= REPEATABLE READ; `SnapshotPoint = "before_open"` is the candidate fix (the same call before open under READ COMMITTED) | one call under the transaction's own descriptor |
| `L_open` | `px_scan.cpp:370 scan_open_parallel_heap_scan` -> `manager::open` (`px_scan.cpp:495`) -> `px_scan_input_handler_heap.cpp:57 init_on_main` -> `file_manager.c:12615 file_get_all_data_sectors`, then `ftab_set::split (parallelism)` (line 73) | the file's sector table is read under the file header latch |
| `W_start` | `px_scan_task.cpp:206 scan_start_scan` -> `log_tran_table.c:4378 logtb_get_mvcc_snapshot`: the first worker builds the snapshot when the leader has not (`snap = 0`) | the snapshot is built under `m_px_lock_mutex` |
| `W_next` | `px_scan_input_handler_heap.cpp:115-120`: release the current page first (CBRD-27723) | one unfix |
| `W_fix` | `px_scan_input_handler_heap.cpp:122 pgbuf_ordered_fix (OLD_PAGE_MAYBE_DEALLOCATED)`; a deallocated page returns `ER_PB_BAD_PAGEID` and is skipped | one fix |
| `W_read` | the worker's slot iteration over the latched page with the snapshot's visibility check | the page's read latch excludes insert, delete and vacuum |
| `L_join` | the leader waits for every worker | |
| inserter | `heap_insert`: X latch on the target page, a new page when needed (`file_alloc`) | the insert's commit is one step (`clock`) |
| deleter | `heap_delete` and its commit | same |
| vacuum `V_loop` | `vacuum.c:1592 vacuum_heap_page`: rows whose delete committed before every live snapshot are removed | under the page's X latch |
| vacuum `V_page` | `heap_file.c:3332 heap_remove_page_on_vacuum`: the header and the chain neighbours X-latched (lines 3384-3424), the page re-checked, `file_dealloc` (line 3579) or give up | the page is X-latched for the re-check and the dealloc |
| `readCnt`, `readDealloc` | ghosts: times a row was returned; a read of a deallocated page | — |

`PxHeapSnapshot.tla` is the snapshot-level spec (latches gone, one page read per step). Every
`PxHeapScan` cfg checks `AbsSpec` (`PxHeapScan` refines `PxHeapSnapshot`) with

| Abstract | Concrete |
|---|---|
| `owner` | each bitmap page's worker (`Mine`) |
| `started` | the worker has passed `W_start` |
| `left` | the worker's `todo` plus a fixed but unread page |
| `rounds` | vacuum's `rounds`, plus 1 while it is in `V_page` |
| the rest | the same variables |

## Properties

| Name | Kind | Statement | Claim |
|---|---|---|---|
| `TypeOK` | invariant | variable types | — |
| `SameAsSnapshot` | invariant | when the scan is done, each row was returned once if visible to the snapshot and never otherwise | C1 |
| `NoDuplicate` | invariant | no row is returned twice, at any time | C1 |
| `AbsSpec` | refinement | every step is a `PxHeapSnapshot` step | C1 |
| `ScanFinishes` | liveness; WF per scan process and on `V_page` | the scan ends | C2 |
| (deadlock check) | TLC | no reachable state without a successor before the end | C2 |
| `NoDeallocatedRead` | invariant | no worker reads a deallocated page | C3 |
| `IndInv` | inductive invariant of `PxHeapSnapshot`, early-snapshot variant | implies `SameAsSnapshot`; TLAPS-proved for any workers, pages and rows | C1 |

## Fault model

| Fault | Modeled as |
|---|---|
| concurrent INSERT, committed at any point, on any page including one allocated after open | inserter |
| concurrent DELETE, committed at any point | deleter (may stop at any time) |
| vacuum removes rows, then an emptied page; gives up for any reason | vacuum `either` branches and `V_page`'s nondeterministic give-up, at most `VacuumRounds` passes |
| a worker or the leader is slow at any point | any interleaving |
| READ COMMITTED vs REPEATABLE READ | `Isolation` |
| crash / kill -9 | not modeled: a scan is read-only and dies with the server |

## Mutants

| cfg | Change | Expected | Kills |
|---|---|---|---|
| `PxHeapScan.mutant-lazy-snapshot` | READ COMMITTED with the snapshot built by the first worker, i.e. the candidate fix reverted (this is the code as it stands: H1) | `SameAsSnapshot` violated | C1 |
| `PxHeapScan.mutant-reread-page` | a page stays in the worker's list after it is read once | refinement of `PxHeapSnapshot` fails | C1 |
| `PxHeapScan.mutant-hold-current` | the worker keeps its current page while it fixes the next one (before CBRD-27723) | deadlock with vacuum | C2 |
| `PxHeapScan.mutant-no-dealloc-skip` | a page deallocated since the bitmap is read instead of skipped | `NoDeallocatedRead` violated | C3 |

## Findings

| # | Finding | Evidence |
|---|---|---|
| H1 | Under READ COMMITTED (the default) the leader collects the page bitmap at open before the statement's MVCC snapshot exists; the first worker builds the snapshot later. A transaction that commits in between, with rows on a page allocated after open, is visible to the snapshot but its rows on the new page are never read: the scan returns part of a committed transaction (a fractured read). | `PxHeapScan.cfg` (the code): `SameAsSnapshot` violated in 17 steps. Runtime on the probe build (below): 5 of 5 runs with a 5 s delay after open; session A counted 5004 rows, 4 of them from session B's committed 2000-row transaction; session C counted 7000 serial and parallel. Recorded trace `traces/h1-race-run1.log` (`L_open snapshot_valid=0`, then `snapshot_built p=px_worker`) is a behavior of the code cfg (`witness-trace-race-run1`) and is refused on the fix (`reject-race-run1-on-fix`). |
| H1 fix (candidate) | build the snapshot (`logtb_get_mvcc_snapshot`) before the bitmap is collected, for every isolation level | `fix-snapshot-before-open.cfg` passes with `AbsSpec`; TLAPS proves `IndInv` for the early-snapshot variant |

## Witnesses

| cfg | Reached state |
|---|---|
| `PxHeapScan.witness-vacuum-dealloc` | vacuum deallocated a bitmap page during the scan |
| `PxHeapScan.witness-new-page` | an insert allocated a page outside the bitmap during the scan |
| `PxHeapSnapshotTrace.witness-trace-race-run1` | the recorded H1 run is a behavior of the code (READ COMMITTED, lazy snapshot) |
| `PxHeapSnapshotTrace.reject-race-run1-on-fix` | the same run is refused by the candidate fix (it stops at the `L_open` event with `snapshot_valid=0`) |

## Dead expressions (pass cfg)

Line numbers are in the translated module.

| Line | Why never evaluated |
|---|---|
| PxHeapScan.tla:274 | `L_snapshot` without an early snapshot: the pass cfgs are REPEATABLE READ or the fix; the code cfg (READ COMMITTED) takes it and fails C1 (H1) |
| PxHeapScan.tla:302 | `W_start` building the snapshot: the lazy READ COMMITTED path of the code cfg and `mutant-lazy-snapshot` only |
| PxHeapScan.tla:316 | `hold_current_while_fixing_next` mutant branch of `W_next` |
| PxHeapScan.tla:333, PxHeapScan.tla:334, PxHeapScan.tla:335 | `no_dealloc_skip` mutant branch of `W_fix`, with the ghost `readDealloc' = TRUE` that flags a C3 violation |

## Bounds and limits

- TLC: 2 workers, 3 pages (2 initial rows, 1 new row), 3 vacuum passes; the scale cfg runs 3
  workers. TLAPS covers C1 of `PxHeapSnapshot` (early snapshot) for any workers, pages and rows;
  the latch-level model is tied to it by the TLC refinement check only.
- C2 is checked by TLC only (no PTL back end for TLAPS on this host).
- Not modeled: partitions (CBRD-26012: one heap per partition, the same rule per heap), the
  row-by-row gather and list files (CBRD-27217), lock requests by workers (CBRD-26194), overflow
  records (read under the home page's latch).
- The probe build: develop `e98bdd885` + TLATRACE lines and an env-gated delay after open
  (`CUBRID_TLA_PX_OPEN_DELAY_MS`), optdebug, libcubrid sha256 `92a09d252ee8a48c2e1de36585db54d2ed386375f56b81f2ad8dc39aac376c9e`
  (H1 was reproduced on the earlier probe build `e22b6bc2...` of the same source plus the same probes).

## Result
2026-11-05, `tools/tla/tla-check --workers 8 docs/tla/parallel-scan/heap`: **RESULT: FAILED (1)** —
the one failure is `PxHeapScan` (the code, READ COMMITTED): `SameAsSnapshot` violated at depth 18
(H1). Every other cfg ends as expected. Run dir
`.git_ignored_dir/scratch/tla/heap-20261105-205635-1962937`.

| cfg | Result | Distinct states | Depth |
|---|---|---|---|
| `PxHeapScan` | **`SameAsSnapshot` violated (H1)** | 961,884 | 18 |
| `PxHeapScan.rr` (REPEATABLE READ) | pass, refines `PxHeapSnapshot` | 1,753,160 | 30 |
| `PxHeapScan.fix-snapshot-before-open` | pass, refines `PxHeapSnapshot` | 1,753,160 | 30 |
| `PxHeapScan.scale-3-workers` | pass | 7,207,138 | 33 |
| `PxHeapScan.mutant-lazy-snapshot` | `SameAsSnapshot` violated (killed) | 937,589 | 18 |
| `PxHeapScan.mutant-reread-page` | refinement fails (killed) | 5,147 | 8 |
| `PxHeapScan.mutant-hold-current` | deadlock (killed) | 1,437,831 | 22 |
| `PxHeapScan.mutant-no-dealloc-skip` | `NoDeallocatedRead` violated (killed) | 83,002 | 12 |
| `witness-new-page` / `witness-vacuum-dealloc` | reached | 218 / 11,292 | 6 / 9 |
| `PxHeapSnapshot` | pass | 360,630 | 16 |
| `PxHeapSnapshot.inductive-indinv` | pass (IndInv inductive) | 861,978 | 12 |
| `PxHeapSnapshotTrace.witness-trace-race-run1` | the recorded H1 run is accepted | 42 | 4 |
| `PxHeapSnapshotTrace.reject-race-run1-on-fix` | the same run is refused by the fix | 1,564 | 7 |

TLAPS: `PxHeapSnapshot_proofs.tla` 278/278 obligations proved, none omitted (C1 for the
early-snapshot variant, any workers, pages and rows). C2 and C3 are TLC only.

Spec sha256: `PxHeapScan.tla` 99519c15…, `PxHeapSnapshot.tla` a11395eb…,
`PxHeapSnapshot_proofs.tla` 36d103d8… (full list in the run dir's summary).
