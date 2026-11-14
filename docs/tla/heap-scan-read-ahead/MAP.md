# heap-scan-read-ahead — read-ahead for the serial sector-based heap scan (workspace #642)

Split from CBRD-28043 (PR CUBRID/cubrid #8497) on 2026-11-14: the batch read of a stretch of listed pages and the
loader threads that read the next sectors into the buffer while the serial walk works. Trial implementation: fork
branch `heap-scan-read-ahead` (`abc4c1fbb`, on `3328953d3`). The sector-based scan itself (the page bitmap, the
walk in file order) is `docs/tla/CBRD-28043/`; its decisions D1..D17 and claims C1..C5 keep their numbers here.
Models: `PageBatchRead.tla` (two batch readers and one single-page fixer over one run of pages),
`ReadAheadHandoff.tla` (how a loaded page stays in the buffer until the walk takes it).

trace-exempt: design spec of a trial implementation (workspace #642); the implementation's trace validation (cubrid-tla step 9) belongs to the issue that carries the code

## Design tree (grilling ledger)

| # | Decision | State | Source | In the model |
|---|---|---|---|---|
| D18 | A sector-based scan that reaches the first page of a stretch of listed pages (consecutive set bits of a sector's bitmap, 64 at most) reads the stretch into the buffer with one read when that page is not in the buffer (`pgbuf_load_page_run`), then fixes the pages one at a time as before. The stretch is read whole from the first sector on (no ramp: a scan that ends early leaves at most one sector, 1 MB, read for nothing). The batch reader buffer-locks every page of the run first, not waiting: a page in the buffer or being read ends the run (the option "read into a private area and copy page by page without buffer locks" is struck: mutant `no_lock`). BCBs come from the invalid list and the LRU lists only; a shortage shortens the run. The double write buffer is looked up before the volume is read, page by page; a page it holds is not read from the volume. The pages enter the buffer unfixed; nothing is reported, a page left out meets its reason in its fix. | trial: in the issue's scope only if the perf servers show a gain (user 2026-11-14) | user 2026-11-14 ("모델해서 구현하고 성능테스트서버에서 성능빨라지는지 확인하고"; Q2 "응"; Q3 "full scan인데 8장부터 시작할 이유가?") | `PageBatchRead.tla`: `BLock` → `BAlloc`/`BAllocShort` → `BDwb` → `BRead` → `BInstall` |
| D19 | The serial walk of a heap of 16 sectors or more is read ahead by loader threads: each takes the next sector from a shared cursor, at most a fixed number of sectors ahead of the walk, and loads it with D18's batch read; the walk keeps its file order (it waits on a page's buffer lock, or reads a sector no loader took). The loaders are parallel query workers reserved for the scan; none available means no read-ahead. Parallel heap scan workers do not use the batch read. Measured on perf-node1 (release, 2.4 GB table, medians): serial cold 4.06 s → 1.50 s with 8 loaders (2.22 s with 4), hot 1.14 = 1.14, parallel cold 1.12 = 1.12. | trial; the loader count and where the workers come from are open (Q1 2026-11-14) | user 2026-11-14 ("미리읽기 해봐") | `PageBatchRead.tla`: the batch readers are the loaders, the fixer is the walk |
| D20 | How a page a loader read stays in the buffer until the walk takes it. Struck by the model: raising the fix count without a latch (`mutant-fcnt-pin`: a page nobody latches would have a fix count, which `pgbuf_latch_bcb_upon_fix` assumes never happens; an unfix by another thread finds no holder, `pgbuf_unlatch_thrd_holder`); the loader keeping a read latch until the walk has passed (`mutant-latch-pin`: a writer of that page waits as long as the walk stands still). handing the loader's fix (its holder entry) over to the walk's thread (`mutant-holder-handoff`: the holder problem goes, but the walk then holds read latches on up to the read-ahead distance of pages it has not reached, and a writer of any of them waits as long as the walk stands still; safe otherwise, `witness-handoff-ends`). Left: no protection (the walk reads an evicted page again; `ReadAheadHandoff.cfg`), or a "do not evict" mark the walk's fix clears (`option-flag`), which needs the cleanup after the loaders have ended (`mutant-cleanup-before-join`, `mutant-stop-keeps`) and a read-ahead distance the buffer can spare (`mutant-depth-over-buffer`). | open (user 2026-11-14: "핀(fix) 해서 넘기는 방안 검토", "모델 tla+로만들어서") | — | `ReadAheadHandoff.tla`, constant `Option` |
| D21 | No direct I/O (O_DIRECT) for the read-ahead. | settled | user 2026-11-14 ("direct도 못써") | the reads go through the OS cache: not a model step |
| D22 | A loaded page is not pinned for the walk: no protection (D20's option `none`). | settled | user 2026-11-14 ("pin 넣지말고") | `ReadAheadHandoff.cfg` |
| D23 | The read-ahead is not part of CBRD-28043; it is carried by workspace #642 on its own branch. | settled | user 2026-11-14 | — |

## Claim and sources

| # | Claim | Source |
|---|---|---|
| C6 | A page in the buffer holds the page's latest content: a batch read never puts an older copy of a page into the buffer. | user, Q2 2026-11-14; `pgbuf_claim_bcb_for_fix` (the double write buffer is read before the volume, `page_buffer.c`) |
| C7 | A page is buffer-locked and loaded only while it is not in the buffer: one BCB per page. | `pgbuf_lock_page` (today's miss path); user, Q2 2026-11-14 |
| C8 | A batch reader that ended, on any path (run cut short, BCB shortage, read error, page not put into the buffer), holds no buffer lock and no BCB. | user, Q2/Q3 2026-11-14 |
| C9 | Every batch reader and every fixer waiting for a page of a run ends: no lost wakeup, no deadlock. | user, Q2 2026-11-14 |
| C10 | A page nobody latches has fix count 0. | `pgbuf_latch_bcb_upon_fix` (`page_buffer.c`: an idle BCB is taken with fix count 0), `pgbuf_simple_fix`'s warning ("cannot be mixed with general fix") |
| C11 | When a walk and its loaders have ended, on any path (end of the bitmap, a LIMIT, an error), no page is left protected for them. | user 2026-11-14 (review of the handoff) |
| C12 | While a walk stands still (it waits for its client) a writer still gets the write latch of any page the walk does not hold, and another thread still gets a BCB. | user 2026-11-14 (review of the handoff); assumption A8 |
| C13 | The walk and its loaders end. | D19 |

## Refinement map (model -> code)

`PageBatchRead.tla` (D18). Code at `~/dev/cubrid-worktree/CBRD-28043`, fork branch `heap-scan-read-ahead` `abc4c1fbb`.

| Model | Code | Protection | One step because |
|---|---|---|---|
| `BStart` | `heap_page_list_fix_next` (`heap_file.c`): at the first page of a stretch of set bits (offset 0, the bit before unset, or the page after the file header) calls `pgbuf_load_page_run (vpid, bit64_count_trailing_ones (bitmap >> offset))` | private | private state |
| `BLock` | `pgbuf_load_page_run`, first loop: under `hash_anchor->hash_mutex` walks the hash chain and the buffer lock chain; neither holds the page → links `buf_lock_run_table[thread index * 64 + i]` into the lock chain; else the run ends | the page's hash mutex | check and link under one hold of the hash mutex, one page at a time; no mutex is held between two pages |
| `BAlloc` | second loop: `pgbuf_get_bcb_from_invalid_list`, else `pgbuf_get_victim` + `pgbuf_victimize_bcb`; the BCB's VPID is set NULL, its latch INVALID and its mutex released (a thread holds one BCB mutex at a time, `pgbuf_bcbmon_lock`) | BCB mutex, LRU and invalid list mutexes | one BCB leaves the lists per step |
| `BAllocShort` | the same loop's `break` (no BCB without waiting), then `pgbuf_unlock_page (..., true)` for the pages past `n_bcbs` | hash mutex per page | the model unlocks the tail in one step; the code page by page, each under its own hash mutex and independent |
| `BDwb` | third loop: `dwb_read_page` per page into the BCB's page area | the double write buffer slot's mutex | one page per step |
| `BRead` | `fileio_read_page_run` (`file_io.c`): one `preadv` for each stretch the double write buffer did not give | none on the volume; the pages are buffer-locked | modeled one page per step, a superset of the one-call read |
| `BReadError` | `fileio_read_page_run` returns NULL (or a TDE decryption fails): the install loop takes the `!ok` branch for every page: `pgbuf_put_bcb_into_invalid_list`, `pgbuf_unlock_page (..., true)` | BCB mutex, hash mutex | the model releases all in one step; the code page by page, independent |
| `BInstall (TRUE)` | last loop: BCB mutex, VPID and latch set, `pgbuf_insert_into_hash_chain`, `pgbuf_unlock_page (..., false)` (wakes `next_wait_thrd`), LRU add, BCB mutex released | BCB mutex + hash mutex | the page enters the chain and its lock leaves under one hold of the hash mutex |
| `BInstall (FALSE)` | the page's identifier does not match after `pgbuf_set_bcb_page_vpid`: `pgbuf_put_bcb_into_invalid_list`, `pgbuf_unlock_page (..., true)` | the same | — |
| `FLookup`, `FWake`, `FAlloc`, `FAllocFail`, `FDwb`, `FRead`, `FInstall` | today's miss path, unchanged: `pgbuf_search_hash_chain`, `pgbuf_lock_page` (holder, or sleep on the lock's wait list), `pgbuf_allocate_bcb`, `dwb_read_page`, `fileio_read`, `pgbuf_insert_into_hash_chain`, `pgbuf_unlock_page` (`pgbuf_fix`, `pgbuf_claim_bcb_for_fix`) | hash mutex, BCB mutex | as the code's mutex holds |
| `Modify` | any write under a page write latch (`pgbuf_set_dirty`) | page latch | — |
| `Flush` | `pgbuf_bcb_flush_with_wal` → `dwb_add_page`: the page's copy enters a double write buffer slot | BCB mutex, slot | — |
| `DwbWrite`, `DwbRemove` | the double write buffer flush writes the block's pages to their volumes, then removes the slots from `slots_hashmap` | — | two steps: a reader between them still finds the slot |
| `Evict` | `pgbuf_get_victim` + `pgbuf_victimize_bcb` of a clean unfixed page by any thread | BCB mutex, hash mutex | — |

`ReadAheadHandoff.tla` (D20) is a design model of the options, not of code: only `Option = "none"` exists in the branch (`pgbuf_load_page_run` puts the pages into the LRU list unfixed).

| Model | Code | Protection | One step because |
|---|---|---|---|
| `LSkip`, `LPick`, `LInstall` | `scan_heap_read_ahead_loader` (`scan_manager.c`) → `heap_page_list_load_sector` → `pgbuf_load_page_run` (modeled a page at a time; `PageBatchRead` has the run) | the page's buffer lock from pick to install | the walk and the writer wait for a page being read |
| `LOff` | the loader's loop ends on `state->stop` | atomic flag | — |
| `ScanFix` | `heap_page_list_fix_next`: unfix the held page, fix the next (`pgbuf_ordered_fix`) | page latch | the walk holds no page between two fixes |
| `ScanStop`, `ScanCleanup` | `scan_heap_read_ahead_stop`: `stop` set, `worker_manager::release_workers` waits for the loaders, then the state is freed | — | two steps: the loaders run between them |
| `Evict` | `pgbuf_get_victim` by any thread | BCB mutex | — |
| `WWant`, `WGrant`, `WRelease` | any `pgbuf_fix (..., PGBUF_LATCH_WRITE)` and its unfix | page latch | — |
| `OFix` | `pgbuf_allocate_bcb` for a page of another file | — | — |

## Properties

| Property | Kind | Claim |
|---|---|---|
| `NoStale` (`PageBatchRead`) | invariant | C6 |
| `OneCopy` | invariant | C7 |
| `NoLockLeft`, `BcbConserved` | invariant | C8 |
| `Ends` (`PageBatchRead.live.cfg`), deadlock check of every cfg | liveness, WF on the readers' and the fixer's steps | C9 |
| `IndInv` (`PageBatchRead.apalache-indinv.cfg`) | inductive invariant | C6, C7, C8 are conjuncts |
| `IdleHasNoFix` (`ReadAheadHandoff`) | invariant | C10 |
| `NoProtectionLeft` | invariant | C11 |
| `WriterEnds`, `OtherEnds` (`still*.cfg`, no fairness on the walk) | liveness | C12 |
| `Ends` (`ReadAheadHandoff.live*.cfg`) | liveness | C13 |
| `IndInv` (`ReadAheadHandoff.apalache-indinv.cfg`, both left options, Depth 1 and 2) | inductive invariant | C11 is a conjunct |

## Fault model and environment assumptions

Faults of `PageBatchRead` (D18):

| Fault | Modeled | Where |
|---|---|---|
| error return | yes | `BReadError` (read error, TDE failure), `BInstall (FALSE)` (identifier mismatch), `FAllocFail` |
| interrupt / query cancel | n/a | `pgbuf_load_page_run` checks no interrupt and waits for nothing; the fix after it does |
| lock timeout, deadlock victim | n/a | no lock manager lock; buffer locks are taken without waiting |
| conditional latch failure | n/a | no page latch is taken |
| OOM | n/a | no allocation: BCB pointers and the I/O vector are on the stack, the buffer lock entries are preallocated at boot |
| BCB shortage | yes | `BAllocShort` at any page of the run |
| crash / `kill -9` | n/a | the batch read writes nothing |
| spurious wakeup | n/a | the fixer's wait is `pgbuf_sleep` on its thread entry, resumed only by `pgbuf_unlock_page` or an interrupt; an interrupted waiter returns to its caller's retry, as today |
| concurrent DML | yes | `Modify` of any buffered page |
| vacuum | n/a | a page deallocated since the bitmap is `BInstall` of its old content (the fix's maybe-deallocated check follows) or `BInstall (FALSE)` |
| checkpoint, page flush, page replacement | yes | `Flush`, `DwbWrite`, `DwbRemove`, `Evict` |
| HA log apply | n/a | writes pages as DML does (`Modify`) |
| nested statement | n/a | reads no snapshot |

- A6: a page that is not in the buffer is not written: its volume copy and its double write buffer slot change only by the double write buffer's own flush (`DwbWrite`, `DwbRemove`). So a buffer-locked page's latest content is in the slot if there is one, else on the volume (`Durable`, `Contents`).
- A7: batch readers never wait for a buffer lock; only single-page fixers wait, for the lock holder's unlock. The fixer gets weak fairness with the readers (`WF_vars(Threads)`); the environment gets none and its budget is finite (`MaxVer`).

- A8: a serial walk may stand still for any time between two pages (its rows go to a client that does not fetch), and may never stop; so C12 is checked with no fairness on the walk (`SpecStill`). Every other thread is weakly fair.
- `ReadAheadHandoff` faults: the walk stops at any page (`ScanStop`: LIMIT, error, interrupt); a loader finishes the page it is reading after the stop (`LInstall` has no stop check); eviction of any unprotected page at any time. Not applicable: crash (nothing durable), lock manager locks, OOM (no allocation in the handoff).

## Mutants

| Cfg | Removes | Expected | Claim |
|---|---|---|---|
| `PageBatchRead.mutant-no-lock` | the buffer locks of the run (read into a private area, put in when the page is not in the buffer) | `NoStale` | C6 |
| `PageBatchRead.mutant-dwb-after-read` | the order: the volume is read before the double write buffer is looked up | `NoStale` | C6 |
| `PageBatchRead.mutant-read-over-dwb` | the exclusion of double write buffer pages from the volume read | `NoStale` | C6 |
| `PageBatchRead.mutant-lock-over-buffered` | the "in the buffer" check before the buffer lock | `OneCopy` | C7 |
| `PageBatchRead.mutant-short-keeps-lock` | the unlock of the pages that got no BCB | `NoLockLeft` | C8 |
| `PageBatchRead.mutant-error-keeps-lock` | the unlock on a read error | `NoLockLeft` | C8 |
| `PageBatchRead.mutant-error-keeps-bcb` | the return of the BCBs on a read error | `BcbConserved` | C8 |
| `PageBatchRead.mutant-no-wake` | the wakeup of the lock's waiters at unlock | deadlock | C9 |
| `ReadAheadHandoff.mutant-fcnt-pin` | the latch of the loader's pin (option `fcnt_pin`) | `IdleHasNoFix` | C10 |
| `ReadAheadHandoff.mutant-stop-keeps` | the cleanup of the marks when the walk ends | `NoProtectionLeft` | C11 |
| `ReadAheadHandoff.mutant-cleanup-before-join` | the wait for the loaders before the cleanup | `NoProtectionLeft` | C11 |
| `ReadAheadHandoff.mutant-latch-pin` | (option `latch_pin`) the loader keeps a read latch until the walk passed | `WriterEnds` (liveness) | C12 |
| `ReadAheadHandoff.mutant-holder-handoff` | (option `handoff`) the loader fixes the page and hands its holder entry to the walk's thread: the walk then holds read latches on pages it has not reached | `WriterEnds` (liveness) | C12 |
| `ReadAheadHandoff.mutant-depth-over-buffer` | (option `flag`) the spare BCB beyond the marked pages: Depth 2 with 3 BCBs | `WriterEnds` / `OtherEnds` (liveness) | C12 |
| `ReadAheadHandoff.mutant-loader-ignores-stop` | the loader's stop check | `Ends` (liveness) | C13 |

## Witnesses

| Cfg | Outcome that must be reachable |
|---|---|
| `PageBatchRead.witness-batch-two` | a batch puts two pages into the buffer |
| `PageBatchRead.witness-from-dwb` | a batch page comes from the double write buffer |
| `PageBatchRead.witness-shrunk` | a batch shortened by a BCB shortage still puts a page in |
| `PageBatchRead.witness-woke-after` | a fixer that waited for a batch page is woken and finishes a fix |
| `PageBatchRead.witness-cut-locked` | a run ends at a page another thread is reading |
| `PageBatchRead.witness-dropped` | a batch page is not put into the buffer |
| `PageBatchRead.witness-errored` | a batch ends on a read error and everything ends |
| `PageBatchRead.witness-all-done` | both batch readers and the fixer end |
| `ReadAheadHandoff.witness-reread` | (no protection) the walk reads again a page a loader had put into the buffer |
| `ReadAheadHandoff.witness-handoff-ends` | (option `handoff`) the safety properties hold and everything ends when the walk does not stand still |
| `ReadAheadHandoff.witness-marked` | (option `flag`) a page is marked |
| `ReadAheadHandoff.witness-stopped-early` | a walk stops before the last page and everything ends |
| `ReadAheadHandoff.witness-all-done` | the walk, the loader, the writer and the other thread end |

## Dead expressions (pass cfg)

| Line | Cfg | Why it is never evaluated |
|---|---|---|
| PageBatchRead.tla:304, PageBatchRead.tla:305, PageBatchRead.tla:306, PageBatchRead.tla:307, PageBatchRead.tla:308, PageBatchRead.tla:309, PageBatchRead.tla:310, PageBatchRead.tla:312 | `PageBatchRead.live` | `BReadError` is disabled by `MaxErrors = 0` in the liveness cfg (P68: smallest bound); the main cfg fires it (`witness-errored`) |
| PageBatchRead.tla:207, PageBatchRead.tla:208, PageBatchRead.tla:209, PageBatchRead.tla:210, PageBatchRead.tla:211 | `PageBatchRead.live` | `Reset` as called from `BReadError` (TLC counts an operator's body per call site); its calls from `BInstall` and `FInstall` fire |
| ReadAheadHandoff.tla:149, ReadAheadHandoff.tla:150 | all `ReadAheadHandoff` pass cfgs | `LRelease`: the loader holds a read latch only under the struck option `latch_pin` (`mutant-latch-pin`) |

## Bounds and limits

- `PageBatchRead`: main 3 pages of one run, 2 content versions, 3 BCBs, 2 batch readers (a run of up to 3 pages each, any start page) and one single-page fixer doing 2 fixes, 1 read error. Scale: 4 pages, runs of up to 4. Liveness: 2 pages, 2 BCBs, 1 fix, no error (P68). Not modeled: the hint to the OS for the next sector (`heap_page_list_hint_sector`: nothing is read into the buffer, no state the scan or the buffer uses), the LRU position of the loaded pages, TDE decryption other than as a failure, temporary volumes (not read in runs), more than one waiter per page (each waiter is woken by the same unlock).
- `ReadAheadHandoff`: 3 pages, read-ahead distance 2, 3 BCBs (4 for the option `flag`: two marked pages, the writer's and the other thread's), one loader, one writer, one other thread. Scale: 4 pages, 4 BCBs. Not modeled: where a loaded page sits in the LRU list (it changes how likely an eviction is, not whether it can happen), several loaders (`PageBatchRead`), the batch read's steps.

## Counterexamples and divergences

| Cfg | Trace | Class |
|---|---|---|
| `ReadAheadHandoff.mutant-holder-handoff` | the walk stands at page 0 → a writer asks for page 1's write latch → the loader loads page 1, fixes it with a read latch and hands the fix to the walk's thread → the same for page 2 → the walk never reads page 1, so the latch stays and the writer waits for ever | design option struck (C12) |
| `ReadAheadHandoff.mutant-depth-over-buffer` | (option `flag`, distance 2, 3 BCBs) pages 2 and 3 are loaded and marked, the other thread took the third BCB → the walk stops, the loader ends, the marks stay until the cleanup → a writer of page 1 finds no BCB: nothing can be evicted | a constraint of the option `flag`, not adopted (D22) |

## Result

`tools/tla/tla-check --workers 12 docs/tla/heap-scan-read-ahead`, 2026-11-14: `RESULT: OK`, 40 cfgs (run dir `.git_ignored_dir/scratch/tla/heap-scan-read-ahead-20261114-162413-4177547`, log `.git_ignored_dir/scratch/cbrd28043-s2/tla-record-readahead.log`).
`PageBatchRead` main 124,242,275 states generated / 26,532,484 distinct, depth 61; scale (4 pages) 199,502,848 / 39,725,350, depth 67; 8 mutants killed, 8 witnesses reached, liveness and the Apalache inductive check pass.
`ReadAheadHandoff` main 97,424 / 26,848, depth 21; scale 685,100 / 160,856; 7 mutants killed (three of them the struck options), 5 witnesses reached, the standing-still and liveness cfgs and the Apalache inductive check pass.
Spec sha256 at the run: `PageBatchRead.tla` 7a858e26e138a8ac…, `ReadAheadHandoff.tla` 24e3a0caaf01de87… (this Result section was written after the run, so MAP.md's hash differs from the run's).
Trace-exempt: design spec of a trial implementation (fork branch `heap-scan-read-ahead` `abc4c1fbb`); TLAPS not requested.
