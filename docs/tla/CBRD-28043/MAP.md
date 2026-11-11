# CBRD-28043 — every query heap scan is a sector-based heap scan

Read side of CBRD-28010: a query heap scan collects the heap's page bitmap at open (after the statement's
snapshot), decides from its page count whether to run in parallel or serially, and both read the bitmap in file
order instead of following the heap page links (D9). Model `SectorScan.tla` (two workers, or one when serial).
Terms (GLOSSARY.md): sector-based heap scan (섹터 기반 힙 스캔); today's serial scan is a 체인 순서 스캔
(chain-order heap scan); the model's `list` is the 페이지 비트맵 (page bitmap). Engine reference: develop
`2d1513a8a`; implementation branch `CBRD-28043` (`~/dev/cubrid-worktree/CBRD-28043`).

trace-exempt: design spec of D1..D13; the implementation's trace validation (cubrid-tla step 9) is not done in this issue

## Design tree (grilling ledger)

| # | Decision | State | Source | In the model |
|---|---|---|---|---|
| D1 | The read side is a sector-order serial heap full scan. Relinking the heap chain in compactdb is rejected: compactdb's heap work runs offline or under the class X lock (`heap_file.c:5806`); every page whose next/prev changes is rewritten (94% of pages for a table loaded with 32 workers: 200 GB read and close to 200 GB written for a 200 GB table, twice with the double write buffer); later DML scatters the links again; a relink within one sector is a full re-sort, because one sector's pages are spread over many worker batches. | settled | user, Q1 2026-11-11 | the scan walks `list` in page order (`Pick`) |
| D2 | A new issue (CBRD-28043, assignee cubrid-todo) carries this work; CBRD-28010 keeps the insert side (comment 4778335 links them). | settled | user, Q2 2026-11-11 | — |
| D3 | Acceptance: a table loaded with loaddb_worker_count=32 scans cold as fast as the SA-loaded table within noise; warm instructions:u within 1%; a rewind (nested-loop inner) fixes no file table page again (the third criterion replaced by Q12, 2026-11-11; it was "a small table's scan open fixes no more pages than today"). | settled | user, Q3 + Q12 2026-11-11 | `Rewind` reuses `list` (measured, not modeled) |
| D4 | The file table pages leave the collected list after the file header latch is released, by sort + binary search; the parallel heap scan gets the same change. | settled | user, Q4 2026-11-11 | `CollectList` (one step under the latch) then `Dedup` (own step, environment may act in between) |
| D5 | (superseded by D9, 2026-11-11) A table below parallel_scan_page_threshold (default 256 pages) and a class with no parallel heap scan (system class, MVCC-disabled class) keep the link order. The choice is made once at scan open from the page count the parallel decision already read (`heap_get_num_data_pages`, `px_scan.cpp:423`); a rewind keeps it. | settled | user, Q5 2026-11-11 | the model is the sector-order branch only; `Rewind` reuses `list` |
| D6 | Claims C1..C4; a READ COMMITTED snapshot rebuilt by a nested statement is accepted as the parallel heap scan accepts it (environment assumption A3). | settled | user, Q6 2026-11-11 | claims below |
| D7 | A listed page that is no longer a heap page of this table when fixed (freed, or freed and taken as a file table page) is skipped, as a freed page is; claim C5 is adopted. The skip already exists: the ordered fix with `OLD_PAGE_MAYBE_DEALLOCATED` unfixes a page whose type is not an ordered page type and returns `ER_PB_BAD_PAGEID` as a warning, as for a freed page (`pgbuf_ordered_unfix_reused_page`, `page_buffer.c:14158`, CBRD-27967 `2dac6ecc2`); the serial scan fixes its pages the same way and inherits it. Superseded 2026-11-11: Q7's "fix the parallel heap scan in this issue" is dropped, because the runtime run below showed the guard skipping the page (nothing to fix). | settled | user, Q7 2026-11-11; superseded by the runtime run 2026-11-11 | `Fix` skips a page whose type is not heap; mutant `assert_heap` removes the guard (develop before `2dac6ecc2`) |
| D8 | (superseded by D10, 2026-11-11) Scope: a query's forward `S_HEAP_SCAN` that went through the parallel decision (`scan_open_parallel_heap_scan`, server mode, no row lock) and runs serially, on both the `heap_next` path and the page-batch path (`scan_batch_next_page`). Excluded, link order kept: SA mode (`scan_open_parallel_heap_scan` is SERVER_MODE only), row-locking scans (`mvcc_select_lock_needed` returns before the page count, `px_scan.cpp:392`), backward (`heap_prev`), record-info and grouped (`heap_scanrange_next`) scans, internal callers (catalog, locator, the loaddb server loader), a partitioned class's root heap, a `NO_PARALLEL_SCAN` hint and every spec the parallel checker flags `ACCESS_SPEC_FLAG_NO_PARALLEL_SCAN` (`px_scan_checker.cpp`; all return before the page count, `px_scan.cpp:416`, so D5 keeps them in link order); statistics sampling and index build (`btree_load.c:5601`) already read in page list order. Extending to locking scans or SA mode needs its own page count (two more fixes, against acceptance D3) and is a follow-up issue if needed. | settled | user, Q8 2026-11-11 | the model is the in-scope scan; the excluded scans are unchanged code |

| D9 | Every query heap scan reads in sector order. At open it takes the statement's snapshot and collects the page bitmap first (`scan_heap_scan_collect_page_list`, sorted by VSID: file order), then the parallel decision counts the bitmap's pages (no `heap_get_num_data_pages`), and the parallel workers or the serial scan read that one bitmap. `parallel_scan_page_threshold` only decides parallel or serial. | settled | user 2026-11-11 ("모든 힙스캔이 섹터 기반으로 읽고 ... 처음에 무조건 섹터를 수집해서 병렬에 쓰든 직렬에 쓰든") | `TakeSnapshot` → `CollectList` → `Dedup` → `Decide` → workers |
| D10 | Scope: every forward `S_HEAP_SCAN` the query executor opens (`qexec_open_scan`, `qexec_init_next_partition`): any table size, SA and CS mode, row-locking scans (FOR UPDATE, UPDATE/DELETE), a `NO_PARALLEL_SCAN` hint and specs the parallel checker refuses, a partitioned class's root heap. Excluded, link order kept: record-info scans (`S_HEAP_SCAN_RECORD_INFO`), grouped scans (`heap_scanrange_next`; the bitmap still serves a parallel grouped scan), engine-internal `heap_next` callers. | settled | user, Q9 2026-11-11 | the model is one such scan |
| D11 | A class without snapshots (root class, MVCC-disabled class) keeps the link order: C1 rests on the snapshot taken before the bitmap. | settled | user, Q10 2026-11-11 | not modeled (A4) |
| D12 | A sector-based scan reads forward only: `scan_end_scan` no longer flips its direction (the flip let a nested-loop inner alternate with `heap_prev`). | settled | user, Q11 2026-11-11 | `Rewind` restarts the forward walk |
| D13 | A rewind of the parallel heap scan splits the bitmap of the open again (the manager keeps it) instead of collecting a new one, like the serial scan. | settled | user, Q13 2026-11-11 | `Rewind` keeps `list` and `mode` |

## Claim and sources

| # | Claim | Source |
|---|---|---|
| C1 | A pass that ends without an error, parallel or serial, returns every row the scan's start snapshot sees, and no other row; the same rows a link-order scan returns. Rows inserted, deleted, vacuumed, pages freed and reallocated during the scan included. | user, Q6 2026-11-11 |
| C2 | No row is returned twice in one pass, across the parallel workers included. | user, Q6 2026-11-11 |
| C3 | When the scan ends (end of list or an error) no worker holds a page. | user, Q6 2026-11-11 |
| C4 | The scan ends. | user, Q6 2026-11-11 |
| C5 | A page that is not a heap page of this table is never read as one. | user, Q7 2026-11-11 |

## Refinement map (model -> code)

Code at branch `CBRD-28043` (develop `2d1513a8a` + the change).

| Model | Code | Protection | One step because |
|---|---|---|---|
| `TakeSnapshot` | `scan_heap_scan_collect_page_list` → `logtb_get_mvcc_snapshot` (`scan_manager.c`), called from `qexec_open_scan` and `qexec_init_next_partition` before the parallel decision | transaction-local (`m_px_lock_mutex` once a px manager has run) | private state |
| `CollectList` | `file_get_all_data_sectors` (`file_manager.c:12597`): header page read latch held from `:12608` to the unfix, file table pages fixed through `file_extdata_apply_funcs` | file header read latch: `file_alloc`, `file_dealloc` (header write latch) wait | no alloc, dealloc or file table growth can interleave |
| `Dedup` | after the unfix: `qsort` + `bsearch` of the file table sectors on private arrays (D4); then the bitmap is sorted by VSID | private arrays | touches no shared state |
| `Decide` | `scan_open_parallel_heap_scan (..., page_list, num_data_pages)`: row lock needed, partitioned root, `ACCESS_SPEC_FLAG_NO_PARALLEL_SCAN`, no bitmap → serial; else `compute_parallel_degree` on the bitmap's count, then `try_reserve_workers`; parallel: `manager::take_page_list`; serial: `scan_open_heap_scan` then `scan_heap_scan_take_page_list` | private | decided once, before any worker starts |
| `Pick` | serial: the cursor `page_list_sect`/`page_list_pgoffset` (`scan_heap_next_listed_page`); parallel: `input_handler_heap::init_on_main` splits the bitmap into sector sets handed out by the atomic `m_splited_ftab_set_idx`, each worker walks its set (`get_next_vpid_with_fix`). The model's shared cursor hands pages out in file order; a worker fixes its page at any later time, so every per-page interleaving of the split is a model run | atomic index / private cursor | one atomic step |
| `Release` | `heap_page_list_fix_next`: `pgbuf_ordered_unfix` of the held page before the next fix (CBRD-27723) | page latch released | one latch operation |
| `Fix` | `heap_page_list_fix_next`: `pgbuf_ordered_fix (OLD_PAGE_MAYBE_DEALLOCATED, READ)`; a freed page returns NULL with `ER_PB_BAD_PAGEID` as a warning (`page_buffer.c:2596`); a page allocated again as a type ordered fix does not handle (a file table page) is unfixed with the same warning (`pgbuf_ordered_unfix_reused_page`, `page_buffer.c:14158`); a bestspace page is let go | page read latch | the type is read under the latch the fix takes |
| `Read` | serial: `heap_next_1page` over the held page (`scan_heap_next_listed_row`, the page batch's `scan_batch_collect_chunk`); parallel: `slot_iterator` → `heap_next_1page` | page read latch held | the page cannot change while read-latched |
| `Finish` | serial: `scan_heap_next_listed_page` lets the held page go at the bitmap's end; parallel: `input_handler_heap::finalize` | — | one latch operation |
| `Abort` | `ER_INTERRUPTED` or a fix error: serial `S_ERROR`; parallel `m_interrupt_p->set_code`, the other workers stop at their next step | interrupt flag | — |
| `Join` | serial: the scan's `S_END`; parallel: `manager::wait_for_workers` | — | — |
| `Rewind` | serial: `scan_reset_scan_block` resets the cursor, keeps `page_list` (D5, D12); parallel: `scan_reset_scan_block_parallel_heap_scan` → `manager::reset` → `open` → `init_on_main` splits `m_page_list` again (D13) | private | private state |
| `InsertInto` | `heap_insert` into a page with room; commit | page write latch | the page latch serializes it with `Read` (guard: not a held page) |
| `InsertNewPage` | `heap_alloc_new_page` → `file_alloc` → `file_perm_alloc` takes the first partial sector's lowest free page | header write latch | alloc is one step under the header latch |
| `Delete` | MVCC delete of an existing row; commit | page write latch | — |
| `Vacuum` | vacuum removes a version no active snapshot sees | page write latch | — |
| `FreePage` | vacuum removes an emptied heap page: unlink, `file_dealloc` (only a page whose vacuum status is once and one object was vacuumed, `vacuum.c:1830`) | header write latch + page write latch | dealloc is one step under the header latch |
| `GrowFtab` | two sites, both `file_perm_alloc` on the first partial sector's lowest free page, so the new file table page can be a heap page vacuum freed: (1) a sector becoming full overflows the full table, `file_table_add_full_sector` → `FILE_ALLOC_TABLE_PAGE_FULL_SECTOR` (`file_manager.c:5025`); (2) a dealloc moves a full sector to a partial table with no room, `file_perm_dealloc` → `FILE_ALLOC_TABLE_PAGE` (`file_manager.c:6468`) | header write latch | one step under the header latch |

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
| error return | yes | `Abort` from every walk step of either worker; `MaxErrors = 1` |
| interrupt / query cancel | yes | same as error (`Abort`) |
| lock timeout, deadlock victim | n/a | the walk takes no lock of its own; a row-locking scan's lock waits happen per row after `Read`, outside the page walk (D10) |
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
- A4: a class without snapshots keeps the link order (D11); not modeled.
- The serial scan's runs are a subset of the parallel runs (worker 2 may find the bitmap exhausted); `Decide` still takes both branches.
- The environment gets no fairness; its budget is finite (two inserts, deletes of the two starting live rows, one file table growth), so `Ends` needs WF on the scan steps only.

## Mutants

| Cfg | Removes | Expected | Claim |
|---|---|---|---|
| `mutant-late-snapshot` | snapshot before the bitmap (`scan_heap_scan_collect_page_list`, CBRD-27967) | `AllRowsReturned` | C1 |
| `mutant-revisit` | the walk past the last page handed out (`p > taken`) | `NoDuplicate` | C2 |
| `mutant-revisit-live` | the same | `Ends` (liveness) | C4 |
| `mutant-no-release` | the unfix at scan end | `NoPageHeld` | C3 |
| `mutant-fix-freed` | the deallocated-page check of the fix (an `OLD_PAGE` fix) | `NoForeignRead` | C5 |
| `mutant-assert-heap` | the reused-page check of the ordered fix (`page_buffer.c:14161`; develop before CBRD-27967 `2dac6ecc2`) | `NoForeignRead` | C5 |
| `mutant-no-dedup-assert-heap` | the dedup and the page type check together (either alone restores C5: P74) | `NoForeignRead` | C5 |
| `mutant-no-visibility` | the snapshot check on the page's rows | `NoExtraRow` | C1 |
| `mutant-rewind-keep-cur` | the cursor reset of a rewind | `AllRowsReturned` | C1 |
| `mutant-no-shared-cursor` | the shared cursor: each parallel worker walks the whole bitmap (a split that gives a sector to two workers) | `NoDuplicate` | C2 |

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
| `witness-serial-finished` | a serial pass ends without an error |
| `witness-parallel-finished` | a parallel pass ends without an error with both workers having read a page |

## Dead expressions (pass cfg)

| Line | Cfg | Why it is never evaluated |
|---|---|---|
| SectorScan.tla:221 | all pass cfgs | the snapshot after the list: mutant `late_snapshot` only |
| SectorScan.tla:301 | all pass cfgs | a freed page read as a heap page: mutant `fix_freed` only |
| SectorScan.tla:306 | all pass cfgs | a file table page read as a heap page: mutants `assert_heap`, `no_dedup_assert_heap` only |
| SectorScan.tla:265, SectorScan.tla:266 | `live` | a pick after another worker's error: `MaxErrors = 0` in the liveness cfg (P68: smallest bound); the main cfg reaches it (`witness-aborted`) |
| SectorScan.tla:340, SectorScan.tla:341, SectorScan.tla:342, SectorScan.tla:343, SectorScan.tla:344, SectorScan.tla:345 | `live` | `Abort` is disabled by `MaxErrors = 0` in the liveness cfg; the main cfg fires it |

## Bounds and limits

- Main: 5 pages (page 1 the file header, 2/3/5 heap, 4 free), rows 1..5 (3 at the start), 2 rows per page, 2 workers, 1 rewind, 1 error. Scale: 6 pages (one more free page). Liveness: 4 rows, no error (P68).
- Not modeled: the link-order scans (D10, D11); the parallel decision's count and degree (both branches taken); rows spanning pages (overflow records live in another file); the page-batch walk's chunks; the read-ahead hint (CBRD-28031).

## Counterexamples and divergences

| Cfg | Trace | Class |
|---|---|---|
| `mutant-assert-heap` (the ordered fix without its reused-page check, develop before `2dac6ecc2`) | r1 on page 2 deleted and vacuumed (page 2 empty, still allocated) → snapshot → list {1,2,3,5}, file table pages {1} → vacuum frees page 2 (`file_dealloc`) → the file table grows and `file_perm_alloc` takes the lowest free page: page 2 becomes a file table page (`file_manager.c:5025`, or `:6468` when a dealloc overflows the partial table) → dedup removes only page 1 → the walk fixes page 2 and reads it as a heap page. 9 steps, depth 14. | first read as a hole candidate in develop's parallel heap scan; superseded 2026-11-11: the map had missed the guard. Runtime run on develop `2d1513a8a` + TLATRACE (optdebug, `.git_ignored_dir/scratch/cbrd28043-repro/trace-r3.log`): 45,001-page table, one row per page, 703 rows deleted one per sector, vacuum held until the scan's list, then: `ListReady` seq 240 (page 0\|4703 listed) → `FreePage` 0\|4703 seq 270 → `GrowFtab` 0\|4703 (partial table overflow in `file_perm_dealloc`) seq 1256 → `FtabPageInit` ptype=FTAB seq 1257 → `Fix` 0\|4703 seq 1470 returned `ER_PB_BAD_PAGEID` (no `PAGE_UNKNOWN` branch: the reused-page check) → skipped; SUM/COUNT equal to the expected 44,297 rows. Not a hole: C5 holds on develop by the reused-page check. |

## Result

2026-11-12, `tools/tla/tla-check --workers 12 docs/tla/CBRD-28043`: **RESULT: OK** (24 cfgs, all PASS). Run dir
`.git_ignored_dir/scratch/tla/CBRD-28043-20261112-003513-3789990`, log `.git_ignored_dir/scratch/cbrd28043-impl/tla-record-v2.log`.
Engine refined: `03de9026c` (develop `956e1c19f` + 1; same diff as the checked `f7493acdf`), optdebug libcubrid sha256
`a7e8b0e711976b1d29fd7e3dfac844055a1928780f1df195ca53e628caf6f61b`. No trace validation (trace-exempt above).
The D1..D8 model's earlier record run was `CBRD-28043-20261111-184348-2659175` (superseded by D9..D13).

| cfg | Result | States / distinct | Depth |
|---|---|---|---|
| `SectorScan` | pass | 159,474,214 / 45,233,389 | 59 |
| `SectorScan.scale-6p` | pass | 308,436,655 / 87,040,676 | 67 |
| `SectorScan.live` | pass | 8,558,898 / 2,824,497 | 58 |
| `SectorScan.apalache-indinv` | IndInv inductive | — | 1 step |
| `SectorScan.mutant-assert-heap` | `NoForeignRead` violated (killed) | 607,994 / 222,992 | 15 |
| `SectorScan.mutant-fix-freed` | `NoForeignRead` violated (killed) | 286,978 / 111,548 | 14 |
| `SectorScan.mutant-late-snapshot` | `AllRowsReturned` violated (killed) | 7,513,350 / 2,440,723 | 19 |
| `SectorScan.mutant-no-dedup-assert-heap` | `NoForeignRead` violated (killed) | 43,366 / 18,570 | 11 |
| `SectorScan.mutant-no-release` | `NoPageHeld` violated (killed) | 440,881 / 165,497 | 14 |
| `SectorScan.mutant-no-shared-cursor` | `NoDuplicate` violated (killed) | 1,449,782 / 481,610 | 16 |
| `SectorScan.mutant-no-visibility` | `NoExtraRow` violated (killed) | 136,018 / 55,761 | 13 |
| `SectorScan.mutant-revisit` | `NoDuplicate` violated (killed) | 1,364,157 / 454,193 | 16 |
| `SectorScan.mutant-revisit-live` | liveness violated (killed) | 1,279,184 / 380,313 | 33 |
| `SectorScan.mutant-rewind-keep-cur` | `AllRowsReturned` violated (killed) | 24,871,178 / 7,669,323 | 24 |
| `SectorScan.witness-aborted` | reached | 31,494 / 13,619 | 11 |
| `SectorScan.witness-deleted-after-snap-returned` | reached | 839,597 / 293,514 | 17 |
| `SectorScan.witness-finished` | reached | 5,122,869 / 1,647,560 | 19 |
| `SectorScan.witness-new-page-row-returned` | reached | 262,465 / 101,079 | 12 |
| `SectorScan.witness-parallel-finished` | reached | 18,178,110 / 5,650,681 | 23 |
| `SectorScan.witness-reused-read` | reached | 883,182 / 310,031 | 14 |
| `SectorScan.witness-rewound-finished` | reached | 19,455,869 / 6,059,608 | 22 |
| `SectorScan.witness-serial-finished` | reached | 4,828,428 / 1,548,767 | 19 |
| `SectorScan.witness-skipped-foreign` | reached | 586,287 / 215,276 | 14 |
| `SectorScan.witness-skipped-freed` | reached | 291,942 / 113,277 | 14 |

Dead expressions: lines 221, 301, 306 in every pass cfg; also 265, 266, 340–345 in `live` (MaxErrors = 0) — each
explained in the table above.
