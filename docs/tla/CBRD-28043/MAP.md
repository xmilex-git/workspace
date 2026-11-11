# CBRD-28043 — serial heap full scan in sector order

Read side of CBRD-28010: the serial heap full scan reads pages in file order (sector by sector, as the
parallel heap scan does) instead of following the heap page links. Model `SectorScan.tla`. Terms (GLOSSARY.md): this scan is a sector-based heap scan (섹터 기반 힙 스캔); today's serial scan is a 체인 순서 스캔 (chain-order heap scan); the model's `list` is the 페이지 비트맵 (page bitmap). Engine reference:
develop `e30370dc0` (`~/dev/cubrid-worktree/develop-e30370dc0`). No implementation exists yet.

trace-exempt: design spec before the implementation exists; the implementation's spec adds the trace and refines this one (cubrid-tla step 9)

## Design tree (grilling ledger)

| # | Decision | State | Source | In the model |
|---|---|---|---|---|
| D1 | The read side is a sector-order serial heap full scan. Relinking the heap chain in compactdb is rejected: compactdb's heap work runs offline or under the class X lock (`heap_file.c:5806`); every page whose next/prev changes is rewritten (94% of pages for a table loaded with 32 workers: 200 GB read and close to 200 GB written for a 200 GB table, twice with the double write buffer); later DML scatters the links again; a relink within one sector is a full re-sort, because one sector's pages are spread over many worker batches. | settled | user, Q1 2026-11-11 | the scan walks `list` in page order (`Pick`) |
| D2 | A new issue (CBRD-28043, assignee cubrid-todo) carries this work; CBRD-28010 keeps the insert side (comment 4778335 links them). | settled | user, Q2 2026-11-11 | — |
| D3 | Acceptance: a table loaded with loaddb_worker_count=32 scans cold as fast as the SA-loaded table within noise; warm instructions:u within 1%; a small table's scan open fixes no more pages than today. | settled | user, Q3 2026-11-11 | — (measured, not modeled) |
| D4 | The file table pages leave the collected list after the file header latch is released, by sort + binary search; the parallel heap scan gets the same change. | settled | user, Q4 2026-11-11 | `CollectList` (one step under the latch) then `Dedup` (own step, environment may act in between) |
| D5 | A table below parallel_scan_page_threshold (default 256 pages) and a class with no parallel heap scan (system class, MVCC-disabled class) keep the link order. The choice is made once at scan open from the page count the parallel decision already read (`heap_get_num_data_pages`, `px_scan.cpp:423`); a rewind keeps it. | settled | user, Q5 2026-11-11 | the model is the sector-order branch only; `Rewind` reuses `list` |
| D6 | Claims C1..C4; a READ COMMITTED snapshot rebuilt by a nested statement is accepted as the parallel heap scan accepts it (environment assumption A3). | settled | user, Q6 2026-11-11 | claims below |
| D7 | A listed page that is no longer a heap page of this table when fixed (freed, or freed and taken as a file table page) is skipped, as a freed page is; claim C5 is adopted. The parallel heap scan, which reads the same page bitmap through the same fix, gets the same skip in this issue (the new serial path adds another way into its defect). Before the fix, the hole is reproduced on develop with an environment-gated delay in a scratch build, its TLATRACE log showing the counterexample's steps. | settled | user, Q7 2026-11-11 | `Fix` skips a page whose type is not heap; develop's parallel scan asserts `PAGE_HEAP` there: mutant `assert_heap` |
| D8 | Scope: a query's forward `S_HEAP_SCAN` that went through the parallel decision (`scan_open_parallel_heap_scan`, server mode, no row lock) and runs serially, on both the `heap_next` path and the page-batch path (`scan_batch_next_page`). Excluded, link order kept: SA mode (`scan_open_parallel_heap_scan` is SERVER_MODE only), row-locking scans (`mvcc_select_lock_needed` returns before the page count, `px_scan.cpp:392`), backward (`heap_prev`), record-info and grouped (`heap_scanrange_next`) scans, internal callers (catalog, locator, the loaddb server loader), a partitioned class's root heap, a `NO_PARALLEL_SCAN` hint and every spec the parallel checker flags `ACCESS_SPEC_FLAG_NO_PARALLEL_SCAN` (`px_scan_checker.cpp`; all return before the page count, `px_scan.cpp:416`, so D5 keeps them in link order); statistics sampling and index build (`btree_load.c:5601`) already read in page list order. Extending to locking scans or SA mode needs its own page count (two more fixes, against acceptance D3) and is a follow-up issue if needed. | settled | user, Q8 2026-11-11 | the model is the in-scope scan; the excluded scans are unchanged code |

## Claim and sources

| # | Claim | Source |
|---|---|---|
| C1 | A pass that ends without an error returns every row the scan's start snapshot sees, and no other row; the same rows a link-order scan returns. Rows inserted, deleted, vacuumed, pages freed and reallocated during the scan included. | user, Q6 2026-11-11 |
| C2 | No row is returned twice in one pass. | user, Q6 2026-11-11 |
| C3 | When the scan ends (end of list or an error) it holds no page. | user, Q6 2026-11-11 |
| C4 | The scan ends. | user, Q6 2026-11-11 |
| C5 | A page that is not a heap page of this table is never read as one. | user, Q7 2026-11-11 |

## Refinement map (model -> code)

Code sites are where the implementation will sit; the parallel heap scan is the existing code the serial scan reuses.

| Model | Code (develop e30370dc0) | Protection | One step because |
|---|---|---|---|
| `TakeSnapshot` | `logtb_get_mvcc_snapshot` called before the list (`px_scan_input_handler_heap.cpp:64`, CBRD-27967) | transaction-local | private state |
| `CollectList` | `file_get_all_data_sectors` (`file_manager.c:12597`): header page read latch held from `:12607` to the unfix at `:12707`, file table pages fixed one by one through `file_extdata_apply_funcs` | file header read latch: `file_alloc` (header write latch, `file_alloc` body) and `file_dealloc` wait | no alloc, dealloc or file table growth can interleave while the header latch is held |
| `Dedup` | the loop at `file_manager.c:12683-12696` today (under the latch); after D4 on private arrays after the unfix | private arrays | touches no shared state |
| `Pick` | `get_next_vpid_with_fix` next set bit of the sector bitmap (`px_scan_input_handler_heap.cpp:105-118`) | private list | private state |
| `Release` | `pgbuf_ordered_unfix` of the held page before the next fix (`:121-124`, CBRD-27723) | page latch released | one latch operation |
| `Fix` | `pgbuf_ordered_fix (OLD_PAGE_MAYBE_DEALLOCATED, READ)` (`:126`); a freed page returns NULL with `ER_PB_BAD_PAGEID` as a warning (`page_buffer.c:2596`); the page type check (`:149` asserts `PAGE_HEAP`; D7) | page read latch | the type is read under the latch the fix takes |
| `Read` | `heap_next_1page` / `heap_next` over the held page's slots with the snapshot | page read latch held | the page cannot change while read-latched |
| `Finish` | scan end / `finalize` unfixes the held page (`:180-186`) | — | one latch operation |
| `Abort` | `ER_INTERRUPTED` or another fix error (`:132-141`), interrupt checks of the scan loop | — | — |
| `Rewind` | scan reset of a nested-loop inner (`scan_reset_scan_block`) | private | private state |
| `InsertInto` | `heap_insert` into a page with room; commit | page write latch | the page latch serializes it with `Read` (guard `p # held`) |
| `InsertNewPage` | `heap_alloc_new_page` → `file_alloc` → `file_perm_alloc` takes the first partial sector's lowest free page (`file_manager.c:5117-5131`) | header write latch | alloc is one step under the header latch |
| `Delete` | MVCC delete of an existing row; commit | page write latch | — |
| `Vacuum` | vacuum removes a version no active snapshot sees | page write latch | — |
| `FreePage` | vacuum removes an emptied heap page: unlink, `file_dealloc` | header write latch + page write latch | dealloc is one step under the header latch |
| `GrowFtab` | `file_table_add_full_sector` → `file_perm_alloc (FILE_ALLOC_TABLE_PAGE_FULL_SECTOR)` (`file_manager.c:5025`): the new file table page comes from the first partial sector, so it can be a heap page vacuum freed | header write latch | one step under the header latch |

## Properties

| Property | Kind | Claim |
|---|---|---|
| `NoExtraRow` | invariant | C1 |
| `AllRowsReturned` | invariant | C1 |
| `NoDuplicate` | invariant | C2 |
| `NoPageHeld` | invariant | C3 |
| `Ends` | liveness (`SectorScan.live.cfg`), WF on the scan's steps | C4 |
| `NoForeignRead` | invariant | C5 |
| `IndInv` | inductive invariant (Apalache `SectorScan.apalache-indinv.cfg`) | all safety claims are conjuncts |

## Fault model and environment assumptions

| Fault | Modeled | Where |
|---|---|---|
| error return | yes | `Abort` from every walk step; `MaxErrors = 1` |
| interrupt / query cancel | yes | same as error (`Abort`) |
| lock timeout, deadlock victim | n/a | the scan takes no row lock (MVCC read); row-locking scans keep the link order (D8) |
| conditional latch failure | n/a | the fixes are unconditional |
| OOM | n/a | the list allocation fails before the walk; no page is held (`file_get_all_data_sectors` frees and returns) |
| crash / `kill -9` | n/a | a read-only scan writes nothing durable |
| spurious wakeup | n/a | no condition wait |
| concurrent DML | yes | `InsertInto`, `InsertNewPage`, `Delete` on every page but the held one |
| vacuum | yes | `Vacuum`, `FreePage`; A1 below |
| checkpoint, page flush, page replacement | n/a | a page not held may be replaced; the next fix reads it again, the content is the same |
| HA log apply | n/a | applies on a slave like DML from one transaction: covered by the DML actions |
| nested statement (SP SQL from the client) | assumption A3 | not modeled; accepted (D6) |
| file table growth | yes | `GrowFtab` (once) |

Environment assumptions:
- A1: vacuum never removes a version an active snapshot sees (`Vacuum` guard `r \notin snapVis`); so a page holding such a row is never freed.
- A2: a sector stays reserved to its file until the file is destroyed: a freed page is reallocated only by the same file, as a heap page or a file table page. The table cannot be dropped or truncated while the scan holds its class lock.
- A3: under READ COMMITTED a nested statement may rebuild the snapshot mid-statement (`logtb_invalidate_snapshot_data`); rows committed on pages allocated after the list are then not returned, as in the parallel heap scan. Not modeled.
- The environment gets no fairness; its budget is finite (two inserts, deletes of the two starting live rows, one file table growth), so `Ends` needs WF on the scan steps only.

## Mutants

| Cfg | Removes | Expected | Claim |
|---|---|---|---|
| `mutant-late-snapshot` | snapshot before the list (CBRD-27967) | `AllRowsReturned` | C1 |
| `mutant-revisit` | the walk past the current page (`p > cur`) | `NoDuplicate` | C2 |
| `mutant-revisit-live` | the same | `Ends` (liveness) | C4 |
| `mutant-no-release` | the unfix at scan end | `NoPageHeld` | C3 |
| `mutant-fix-freed` | the deallocated-page check of the fix (an `OLD_PAGE` fix) | `NoForeignRead` | C5 |
| `mutant-assert-heap` | the page type check (develop's parallel scan asserts `PAGE_HEAP` and reads on) | `NoForeignRead` | C5 |
| `mutant-no-dedup-assert-heap` | the dedup and the page type check together (either alone restores C5: P74) | `NoForeignRead` | C5 |
| `mutant-no-visibility` | the snapshot check on the page's rows | `NoExtraRow` | C1 |
| `mutant-rewind-keep-cur` | the cursor reset of a rewind | `AllRowsReturned` | C1 |

## Witnesses

| Cfg | Outcome that must be reachable |
|---|---|
| `witness-finished` | a pass ends without an error |
| `witness-rewound-finished` | a rewound pass ends |
| `witness-skipped-freed` | the walk skips a page freed after the list |
| `witness-skipped-foreign` | the walk skips a page freed and taken as a file table page after the list |
| `witness-reused-read` | the walk reads a page freed and reallocated as a heap page after the list (its rows invisible) |
| `witness-deleted-after-snap-returned` | a row deleted after the snapshot is returned |
| `witness-new-page-row-returned` | a row inserted before the snapshot into a newly allocated page is returned |
| `witness-aborted` | a scan stops on an error |

## Dead expressions (pass cfg)

| Line | Why it is never evaluated |
|---|---|
| SectorScan.tla:203 | the snapshot after the list: mutant `late_snapshot` only |
| SectorScan.tla:261 | a freed page read as a heap page: mutant `fix_freed` only |
| SectorScan.tla:266 | a file table page read as a heap page: mutants `assert_heap`, `no_dedup_assert_heap` only |

## Bounds and limits

- Main: 5 pages (page 1 the file header, 2/3/5 heap, 4 free), rows 1..5 (3 at the start), 2 rows per page, 1 rewind, 1 error. Scale: 6 pages, 6 rows.
- Not modeled: the link-order branch (D5) and the choice between the branches; rows spanning pages (overflow records live in another file); the page-batch walk's chunks; the read-ahead hint (CBRD-28031).

## Counterexamples and divergences

| Cfg | Trace | Class |
|---|---|---|
| `mutant-assert-heap` (develop's parallel heap scan behavior at `px_scan_input_handler_heap.cpp:149`) | r1 on page 2 deleted and vacuumed (page 2 empty, still allocated) → snapshot → list {1,2,3,5}, file table pages {1} → vacuum frees page 2 (`file_dealloc`) → the file table grows and `file_perm_alloc` takes the lowest free page: page 2 becomes a file table page (`file_manager.c:5025`) → dedup removes only page 1 → the walk fixes page 2 (`OLD_PAGE_MAYBE_DEALLOCATED` succeeds: the page is allocated) and reads it as a heap page. 9 steps, depth 14. | hole candidate in develop's parallel heap scan (debug: `assert (ptype == PAGE_HEAP)`; release: heap slot reads on a file table page); every step maps to code; not reproduced at runtime yet (P17). The dedup cannot prevent it: the page became a file table page after the list. Design answer D7: skip the page; the parallel heap scan is fixed in this issue after the reproduction. |

## Result

`tools/tla/tla-check docs/tla/CBRD-28043` on 2026-11-11 (evidence `.git_ignored_dir/scratch/tla/CBRD-28043-20261111-184348-2659175/`, spec sha256 `7f7f95cb…` of `SectorScan.tla`): **RESULT: OK**, 22 cfgs PASS, 0 FAIL; trace validation skipped (trace-exempt, design spec).

- Main: 1,671,901 distinct states, depth 52; liveness `Ends`: same state space, pass; scale 6 pages: 14,753,113 distinct states, depth 61.
- 9 mutants rejected (C1 by late-snapshot, no-visibility, rewind-keep-cur; C2 revisit; C3 no-release; C4 revisit-live; C5 fix-freed, assert-heap, no-dedup-assert-heap); 8 witnesses reached.
- Apalache: `IndInv` inductive over every value of `MaxRewind`, `MaxErrors` (37 s).
- Dead expressions 203, 261, 266: mutant-only branches (table above).
- The only MAP edit after this run is the Terms line rename (sector-based heap scan) and this section.
