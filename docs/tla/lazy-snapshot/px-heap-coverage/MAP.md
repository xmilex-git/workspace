# Parallel heap scan: the pages collected once at open against the snapshot and vacuum

The user's question (2026-11-09): prove that the pages a parallel heap scan collects from the file
header once, and hands out to its workers, hold every page and row its MVCC snapshot can read, and
that no vacuum path removes them after the hand-out.

`PxHeapCoverage.tla` models the heap file's pages as free, heap data or file table pages, the
collect of `input_handler_heap::init_on_main`, the workers, other transactions, vacuum's row and
page removal, and the file manager's own table pages. It extends `docs/tla/parallel-scan/heap`
(page-granular, no page reuse) and `docs/tla/CBRD-27967` (where the snapshot is built) with page
reuse as a heap page or as a file table page.

Code: develop `2d928e34b` (worktree `~/dev/cubrid-worktree/develop-2d928e34b`).

## Claim and sources

| # | Claim | Source |
|---|---|---|
| C1 | Once a parallel heap scan has its bitmap and its snapshot, the bitmap holds the page of every row the snapshot sees. | CBRD-25447 (the same result as the serial scan); CBRD-27967 Expected Result; the user's question (2026-11-09) |
| C2 | While the scan runs, no row its snapshot sees is removed, and that row's page stays an allocated heap page (not deallocated, not reused). | vacuum's contract: remove only versions no live snapshot sees (`vacuum.c` `vacuum_heap_page`, `mvcctable::compute_oldest_visible_mvccid`); the user's question |
| C3 | Every bitmap page a worker fixes is a heap page of its heap, or a deallocated page it skips; never a page the file reused for something else. | `px_scan_input_handler_heap.cpp:139` comment "page valid at bitmap build time but deallocated since; ignorable" and the `PAGE_HEAP` assert at :148 |
| C4 | The scan returns exactly the rows its snapshot sees, each once. | CBRD-25447 |
| C5 | The scan finishes. | CBRD-27723 |

## Refinement map (model -> code)

| Model | Code | One step because |
|---|---|---|
| `QueryStart` | `query_executor.c:23120-23124 qexec_execute_query`: `logtb_get_mvcc_snapshot` when isolation >= REPEATABLE READ (`SnapshotAt = "query_start"`) | one call before any scan opens |
| `LeaderSnap` | PR #8438 (CBRD-27967): `logtb_get_mvcc_snapshot` in `init_on_main` before `file_get_all_data_sectors` (`SnapshotAt = "collect"`); not in develop | test-and-build under `m_px_lock_mutex` |
| `Collect` | `px_scan.cpp:1727 manager::open` -> `px_scan_input_handler_heap.cpp:57 init_on_main` -> `file_manager.c:12615 file_get_all_data_sectors`: fixes the file header with a read latch (:12626), walks the partial table (:12668-12671) and the full table (:12684-12687) with the header fixed, subtracts the file table pages (:12698-12711), unfixes (:12713); then `ftab_set::split` | every `file_alloc`/`file_dealloc` of the file takes the header's write latch (`file_perm_alloc`, `file_perm_dealloc` run with `page_fhead` write-fixed), so the read latch makes the walk one step |
| `Start(w)` | `px_scan_task.cpp` `scan_start_scan` -> `scan_manager.c:4033 logtb_get_mvcc_snapshot` (builds the snapshot when none exists: `SnapshotAt = "worker_start"`, develop READ COMMITTED) | under `m_px_lock_mutex` |
| `ReadPage(w, p)` | `px_scan_input_handler_heap.cpp:85 get_next_vpid_with_fix`: `pgbuf_ordered_fix (OLD_PAGE_MAYBE_DEALLOCATED, PGBUF_LATCH_READ)` (:122); a deallocated page returns `ER_PB_BAD_PAGEID` and is skipped (:126-141); a heap page is read by `px_scan_slot_iterator.cpp:117 heap_next_1page` with the snapshot's visibility check. A page reused as a file table page is fixed (it is allocated); in `pgbuf_ordered_fix` it has no heap group and reaches `assert_release (false)` (`page_buffer.c:12570`): optdebug aborts, release reads it on as a heap page (`foreign`) | the read latch excludes insert, delete and vacuum on the page |
| `Finish` | the leader's join of its workers at the end of `manager::next` | |
| `Insert(r, p)` | `heap_insert_logical` on a heap page, or on a page `heap_vpid_alloc` -> `file_alloc` -> `file_perm_alloc` gives the heap (the first free page of the first partial sector; the model takes any free page), and the commit | the commit is one step (`clock`) |
| `Delete(r)` | `heap_delete_logical` and the commit | same |
| `VacuumRows(p)` | `vacuum.c vacuum_heap_page`: versions whose delete MVCCID precedes the oldest visible MVCCID (`OldestVisible`: the snapshot holds it back once built; `docs/tla/lazy-snapshot/stmt` C2 proves that threshold protocol) | under the page's write latch |
| `VacuumPage(p)` | `vacuum.c:1853-1862`: a page left with no record and in `HEAP_PAGE_VACUUM_ONCE` status -> `heap_file.c:3332 heap_remove_page_on_vacuum`: header, previous and next pages write-fixed, re-check of emptiness (:3440) and of waiters (:3451, :3463), `file_dealloc` -> `file_perm_dealloc` (`file_manager.c:6290`) | the page stays write-latched from the re-check to the dealloc |
| `FtabAlloc(p)` | `file_manager.c:6505 file_perm_dealloc` (the partial table has no room for a sector moving from the full table) and `file_table_append_full_sector_page` -> `file_perm_alloc (FILE_ALLOC_TABLE_PAGE)`: a free page of the file's first partial sector becomes a `PAGE_FTAB` page | under the file header's write latch |
| `FtabFree(p)` | `file_manager.c:6409` a merged full-table page deallocated | same |
| sector release | `disk_unreserve_ordered_sectors` only in `file_destroy` (`file_manager.c:4311`) and `file_create`'s rollback (:3871): a sector of a live heap file never moves to another file; `file_destroy` of a heap needs the class's SCH_M lock, which the scan's class lock excludes | not modeled (no page leaves the file) |
| `foreign` | ghost: a worker fixed a bitmap page that is a file table page now | — |
| trace `Collect` / `Fix` / `Alloc` / `Dealloc` | probes in `init_on_main` after the collect, in `get_next_vpid_with_fix` right after the fix (page type, -1 when not fixed), at the end of `file_perm_alloc` and `file_perm_dealloc` for heap files (`traces/probe.diff`) | inside the step |

## Properties

| Name | Kind | Statement | Claim |
|---|---|---|---|
| `TypeOK` | invariant | variable types | — |
| `Coverage` | invariant | `opened /\ snap > 0 => every row visible to snap has home[r] \in bitmap` | C1 |
| `NoLoss` | invariant | `snap > 0 /\ ~done => every row visible to snap is not gone and its page is a heap page` | C2 |
| `HeapOnly` | invariant | `~foreign` | C3 |
| `SameAsSnapshot` | invariant | when the scan is done, each row was returned once if visible and never otherwise | C4 |
| `ScanFinishes` | liveness, `WF_vars(ScanStep)` | `<>done` | C5 |
| `IndInv` | inductive invariant of the fix | implies C1-C4 (`PxHeapCoverage_proofs.tla`) | C1-C4 |

## Fault model

| Fault | Modeled as |
|---|---|
| concurrent INSERT on any page, a new page included, committed at any point | `Insert` |
| concurrent DELETE committed at any point | `Delete` |
| vacuum removes rows below its threshold, then deallocates an emptied page | `VacuumRows`, `VacuumPage`, at most `VacuumRounds` |
| a deallocated page given back to the heap for new rows | `Insert` into a `free` page |
| a deallocated page reused as a file table page, a table page freed again | `FtabAlloc`, `FtabFree` |
| a sector returned to the disk and reserved by another file | not applicable: only `file_destroy` unreserves sectors of a permanent file (`file_manager.c:4311`), excluded by the class lock |
| READ COMMITTED (develop), the PR #8438 fix, REPEATABLE READ | `SnapshotAt` |
| an SP's SQL invalidating the snapshot mid-statement | not modeled here: `docs/tla/CBRD-27967` D6 (out of the claims' scope there too) |
| error at open (`file_get_all_data_sectors`, OOM), interrupt, lock timeout | not modeled: the scan fails before returning rows; a parallel heap scan takes no row lock |
| crash / kill -9 | not applicable: the scan is read-only |
| UPDATE that relocates a row | not modeled: the row keeps its home slot (`REC_RELOCATION`); `heap_next_1page` skips `REC_NEWHOME` records, so the new home page, in the bitmap or not, adds nothing; the home page stays non-empty so vacuum keeps it |
| overflow records | not modeled: read through the home page under its latch |

## Mutants

| cfg | Change | Expected | Kills |
|---|---|---|---|
| `mutant-worker-start` | the snapshot built by the first worker (develop READ COMMITTED, CBRD-27967) | `Coverage` violated | C1 |
| `mutant-collect-misses-page` | the collect keeps any subset of the heap pages | `Coverage` violated | C1 |
| `mutant-vacuum-ignores-snapshot` | vacuum's threshold ignores the scan's snapshot | `NoLoss` violated | C2 |
| `mutant-dealloc-nonempty` | vacuum deallocates a page that still has a row | `NoLoss` violated | C2 |
| `mutant-no-ptype-check` | a bitmap page reused as a table page is not skipped (the code) | `HeapOnly` violated | C3 |
| `mutant-no-dealloc-skip` | a deallocated bitmap page is read instead of skipped | `HeapOnly` violated | C3 |
| `mutant-collect-without-build` | the leader waits for a snapshot it never builds | deadlock | C5 |

C4 is killed by `mutant-worker-start` too (`SameAsSnapshot` fails on the same run once the scan ends; `docs/tla/CBRD-27967` `mutant-code`).

## Witnesses

| cfg | Reached state |
|---|---|
| `witness-ftab-reuse` | a bitmap page is a file table page while the scan runs (fix variant: the worker skips it) |
| `witness-dealloc-during-scan` | vacuum deallocated a bitmap page while the scan runs |
| `witness-row-on-new-page` | a committed row lives on a page allocated after the collect |
| `witness-read-row` | the scan finished having returned a row |
| `PxHeapCoverageTrace.witness-trace-release-run8-on-code` / `-on-fix` | the recorded H2 run is a behavior of the code and of the fix |

## Findings

| # | Finding | Evidence |
|---|---|---|
| H1 | (known, CBRD-27967) READ COMMITTED: the bitmap is collected before the snapshot; a transaction committing in between is seen only in part. Fixed by PR #8438 (not in develop `2d928e34b`). | `code-rc.cfg`: `Coverage` violated; runtime in `docs/tla/CBRD-27967` (develop 3/3 `5003 4 0`) |
| H2 | After the hand-out, vacuum deallocates a bitmap page whose rows the snapshot sees deleted, and the heap file reuses that page as a file table page (`file_perm_dealloc` -> `file_perm_alloc (FILE_ALLOC_TABLE_PAGE)` when the partial table has no room). The worker's `OLD_PAGE_MAYBE_DEALLOCATED` fix succeeds on it: optdebug aborts in `pgbuf_ordered_fix` (`page_buffer.c:12570 assert_release (false)`); release reads the table page as a heap page, logs `slot 0 on page ... is not allocated` (ER -46) and assertion notifications, and the query returns without an error. No row the snapshot sees is lost (C2 holds); what fails is C3. Independent of the snapshot's placement: the reproduction ran under REPEATABLE READ. | `code-rr.cfg`: `HeapOnly` violated. Runtime on the probe builds (4K pages, 12000 one-row pages = 188 sectors, one row per sector deleted and committed before A's snapshot, A's workers held 40 s by `CUBRID_TLA_PX_WORKER_DELAY_MS`): optdebug run 7 (libcubrid `5e8092d7…`) `Collect` -> `Dealloc page=16451` -> `Alloc page=16451 kind=table` -> SIGABRT, core `core.parallel-query.151134` frame `pgbuf_ordered_fix_debug` :12570 with `req_vpid = 16451`; release run 8 (libcubrid `49801571…`) `Dealloc page=4867` -> `Alloc page=4867 kind=table` -> `Fix page=4867 ptype=1`, server log `slot 0 on page 4867 ... is not allocated`, A returned 11813 (= 12000 - 187) |
| H2 fix (decided 2026-11-09, PR #8438) | `pgbuf_ordered_fix` with `OLD_PAGE_MAYBE_DEALLOCATED` unfixes a page whose type is not an ordered type (heap, overflow) and returns `ER_PB_BAD_PAGEID` as for a deallocated page (`pgbuf_ordered_unfix_reused_page`, at each of its three fixes of the requested page, under the page latch); the worker skips it as a deallocated page. The type is read under the latch the fix holds, so the check and the fix are one `ReadPage` step | main cfg passes; TLAPS proves C1-C4 with it |

## Dead expressions (pass cfg)

| Line | Why never evaluated |
|---|---|
| PxHeapCoverage.tla:143 | `Collect`'s `collect_misses_page` mutant branch; `mutant-collect-misses-page` fires it |
| PxHeapCoverage.tla:133, PxHeapCoverage.tla:134, PxHeapCoverage.tla:135 | `LeaderSnap`'s effect in `rr` and `code-rr` (REPEATABLE READ: the snapshot exists from `QueryStart`) and `code-rc` (develop: no leader build); the main and scale cfgs fire it |

## Bounds and limits

- TLC: 2 workers, 3 pages (2 initial rows, 1 new row), 2 vacuum passes, 1 table-page allocation; `scale-3-workers` 3 workers.
- Apalache (`apalache-indinv`): `IndInv` inductive with 2 workers, 3 pages, 3 rows fixed, the vacuum and table-page budgets open.
- TLAPS: C1-C4 for any number of workers, pages and rows, for the fix (`SnapshotAt # "worker_start"`, `PtypeCheck`). C5 is TLC only.
- The model abstracts page latches (one page read per step); the latch-level steps and the CBRD-27723 deadlock freedom are in `docs/tla/parallel-scan/heap/PxHeapScan.tla`.
- The vacuum threshold is abstracted to "the built snapshot holds it back"; `docs/tla/lazy-snapshot/stmt` checks the threshold protocol itself (slots, `MVCCID_ALL_VISIBLE`, the lazy build).

## Trace validation

Probe = `traces/probe.diff` on develop `2d928e34b` (scratch worktree `~/dev/cubrid-worktree/lazysnap-instr`); runs on a 4K-page database. `traces/release-run8.log` is run 8 projected onto three bitmap pages (4867 reused as a table page, 7747 deallocated and skipped, 16768 kept); `traces/release-run8-corrupt.log` deallocates 16768, whose row the snapshot sees. The fix runs used PR #8438 head `9286face3` + the same probe + a `Reused` line in `pgbuf_ordered_unfix_reused_page` (scratch worktree `~/dev/cubrid-worktree/CBRD-27967-instr`, release libcubrid `7cabaa1a…`, optdebug `44f2ce35…`); `traces/release-fix-run1.log` is release run 1 projected onto 16451 (reused as a table page), 16515 (deallocated) and 18861 (kept). The probe's `Reused` line carries no process field; the projection gives it the worker of the next `Fix` of the same page (`p=W4225`).

| cfg | Run | Result |
|---|---|---|
| `PxHeapCoverageTrace.witness-trace-release-run8-on-code` | release run 8 | accepted by the code (`PtypeCheck = FALSE`) |
| `PxHeapCoverageTrace.reject-release-run8-on-fix` | release run 8 (develop) | refused by the fix at `Fix page=4867 ptype=1`: with the fix the reused page comes back unfixed and the worker logs -1 |
| `PxHeapCoverageTrace.witness-trace-release-fix-run1-on-fix` | release run 1 of the fix | accepted by the fix: `Dealloc page=16451` -> `Alloc page=16451 kind=table` -> `Reused vpid=16451 ptype=1` (`pgbuf_ordered_unfix_reused_page`) -> `Fix page=16451 ptype=-1` |
| `PxHeapCoverageTrace.reject-dealloc-live-page` | the corrupted run | refused at the deallocation of a page with a visible row |

## Result

2026-11-09 (after the H2 fix decision and the fix-build trace), `tools/tla/tla-check --prove --workers 12 docs/tla/lazy-snapshot/px-heap-coverage`:
**RESULT: FAILED (2)** — the two failures are the code cfgs of the confirmed holes (cubrid-tla P9): `code-rc` (develop READ COMMITTED,
`Coverage` violated, H1 = CBRD-27967, fixed by PR #8438's first commit) and `code-rr` (develop REPEATABLE READ, `HeapOnly` violated, H2,
fixed by its second commit). Every other cfg ends as expected. Run dir `.git_ignored_dir/scratch/tla/px-heap-coverage-20261109-101121-711225`.

| cfg | Result | States / distinct | Depth |
|---|---|---|---|
| `PxHeapCoverage` (the fix: snapshot before collect, reused page skipped) | pass | 3,062,945 / 815,192 | 18 |
| `rr` (REPEATABLE READ with the skip) | pass | 3,054,231 / 812,528 | 17 |
| `scale-3-workers` | pass | 20,565,494 / 4,934,796 | 19 |
| `code-rc` (develop READ COMMITTED) | **`Coverage` violated (H1)** | 475 / 365 | 6 |
| `code-rr` (develop REPEATABLE READ) | **`HeapOnly` violated (H2)** | 333,771 / 112,645 | 11 |
| `mutant-worker-start`, `-collect-misses-page` | `Coverage` violated (killed) | 761 / 512, 200 / 158 | 6, 5 |
| `mutant-vacuum-ignores-snapshot`, `-dealloc-nonempty` | `NoLoss` violated (killed) | 1,753 / 1,166, 542 / 386 | 6, 6 |
| `mutant-no-ptype-check`, `-no-dealloc-skip` | `HeapOnly` violated (killed) | 244,810 / 89,283, 144,439 / 53,517 | 10, 10 |
| `mutant-collect-without-build` | deadlock (killed) | 5,164 / 2,346 | 9 |
| `witness-ftab-reuse`, `-dealloc-during-scan`, `-row-on-new-page`, `-read-row` | reached | — | 9, 8, 6, 10 |
| `apalache-indinv` | IndInv inductive | — | 1 step |
| `PxHeapCoverageTrace.witness-trace-release-run8-on-code` | accepted | 88,945 / 23,265 | 14 |
| `PxHeapCoverageTrace.witness-trace-release-fix-run1-on-fix` | accepted | 89,942 / 23,737 | 16 |
| `PxHeapCoverageTrace.reject-release-run8-on-fix` | refused | 89,379 / 23,487 | 15 |
| `PxHeapCoverageTrace.reject-dealloc-live-page` | refused | 89,195 / 23,367 | 14 |

TLAPS (tlapm `efe4f2d`): `PxHeapCoverage_proofs.tla` 1613/1613 obligations proved, none omitted (1070 s) —
`InitInv`, `StepInv`, `Safe` (`Spec => []IndInv`), `CoverageSafe` (C1), `NoLossSafe` (C2), `HeapOnlySafe` (C3),
`SameSafe` (C4) for the fix. C5 is TLC only.

Spec sha256: `PxHeapCoverage.tla` 4df9555cd8cfe02132e7262ae382a2609fdb256ea0dc6b5f9f2e565ca914a8a2,
`PxHeapCoverage_proofs.tla` 6d156069803cb8dd5d7ad006e24634519af4289d04b4a4e7238b000ba7a10740,
`PxHeapCoverageTrace.tla` fd90f487d416de21db15fa5e076633efcaf16bd66d7ed4a33fb0b33f7f6c5a63,
`PxHeapCoverageTraceData.tla` 1cbe58ad3ab2924462a2679d749cb7b524e2cbb57c682d0210b46dee0fcd6197.
Engine: develop `2d928e34b` (probe builds optdebug libcubrid `5e8092d78a1b9d5dffd897c644689984bfc157768ce4ccc14577978993114e93`,
release `4980157165dfc6c4b051bcc8c7fad7d14b7a2343b2f4a922ef172fc192b3beb2`); the fix, PR #8438 head `9286face3` (probe builds
optdebug `44f2ce35bedc39fbe413fc311b24c1503b8365f98e26860a379663921a15165b`, release
`7cabaa1a792e87145f8831fc5b6b3902ef89867bb47cb7e7f482ab1119f4313a`; gate builds without the probe optdebug
`1d0060deb893b339207d3fcefdf24dbe7c9eddbecf87e43b507a6e4c3d53c2f2`, release `d829c43b959bd64910689462c0401abe92b16db6a83553bbadf3fb3d91f906a0`).
