# heap-scan-read-ahead — read-ahead for the serial sector-based heap scan (workspace #642)

Split from CBRD-28043 (PR CUBRID/cubrid #8497) on 2026-11-14: the batch read of a stretch of listed pages and the
loader threads that read the next sectors into the buffer while the serial walk works. Trial implementation: fork
branch `heap-scan-read-ahead` (`abc4c1fbb`, on `3328953d3`). The sector-based scan itself (the page bitmap, the
walk in file order) is `docs/tla/CBRD-28043/`; its decisions D1..D17 and claims C1..C5 keep their numbers here.
Models: `PageBatchRead.tla` (two batch readers and one single-page fixer over one run of pages),
`ReadAheadHandoff.tla` (how a loaded page stays in the buffer until the walk takes it), `ReadAheadPool.tla` (where the
read-ahead gets its threads: one server-wide pool, D24).

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
| D24 | The loaders are not parallel query workers reserved per scan: one server-wide read-ahead pool of 10 threads (a cubthread worker pool registered with `REGISTER_WORKERPOOL`; its threads start when a request comes and leave after 5 s without one, `thread_worker_pool_impl.hpp` idle timeout). A walk asks the pool to read a sector ahead of it; the request is a copy of the sector (volume, sector, page bitmap) and holds nothing of the walk, so a walk ends without waiting for its requests. The pool takes a request only while one of its threads is free (`worker_pool_task_capper::try_task`): a refused request is not queued and the walk reads that sector itself when it gets there. Struck: per-scan adaptive loaders from the parallel query workers (A: needs a reserve-one/release-one API beside `worker_manager`'s one-shot reservation and a lifetime rule between a retiring loader and the walk's end, and still competes with parallel queries for `max_parallel_workers`); reading the heap through `mmap` outside the page buffer (C: no less kernel CPU on a cold read, measured; the warm gain needs the page unchanged while its rows are read, i.e. a buffer lock held across the walk's work, which makes other readers wait on a walk that stands still, A8). | settled (user 2026-11-15 "B로 가고"); the pool size is D26's parameter | user 2026-11-15; measurement `.git_ignored_dir/scratch/mmap-probe/results.txt` | `ReadAheadPool.tla`: `WReq` (try_task), `TLock`/`TDone`/`TErr` (a pool thread), `Slots` |
| D25 | The read-ahead distance of a walk starts at one sector and follows feedback ("처음엔 1개로 올리다가, 점점 늘려가면서 조절"; PostgreSQL `read_stream.c`): after a sector the walk waited for (another thread was reading it) or read itself, the distance doubles, never beyond the sectors entered (C15) nor 16; after more than 16 sectors in a row found in the buffer it goes down by one per sector. Struck: double at every sector entered (`mutant-ramp-each`), PostgreSQL's rule without the cap by the sectors entered (`mutant-wait-uncapped`: 10 requests after 4 cold sectors). Compared: `walked` (grows with the walk's progress, never shrinks; `option-walked`, `option-long-walked`). A sector read itself because the pool refused it does not count (C18, `CountRefused = FALSE`). | settled (round 3 Q1 "응") | user 2026-11-15 | constant `Ramp = "wait_capped"`, `WaitWin`, `WWait`, `mcause` |
| D26 | The pool's upper bound is a hidden server parameter (working name `heap_read_ahead_threads`), default 8, at most 32 (PostgreSQL's `io_max_workers` default and `MAX_IO_WORKERS`); 0 turns the read-ahead off. Default on is a feature-specific exception to the house rule (a new engine path is default off), recorded in workspace #642: the measured cold gain is the issue's purpose and C14 keeps the hot path unchanged. | settled | user 2026-11-15 (round 2 Q4; round 5 "PG처럼 8,32로두자") | constant `Slots` |
| D27 | The pool's size follows the cubthread worker pool as it is: one core, one resident thread, a thread started at once when a request finds no free one, every other thread leaving after 5 s without a request (`worker_impl::get_new_task`); a thread that finished a request waits for the next one, so one thread takes a walk's sectors one after another, one request per sector. No controller like PostgreSQL's (`io_min_workers`, one launch per `io_worker_launch_interval`): its signal is a submission queue, and this pool has none (`try_task`). | settled | user 2026-11-15 (round 4 Q1 "응") | `Slots` is the bound; thread start and exit are not modeled (no state a claim reads) |
| D28 | No size threshold: every serial sector-based walk reads ahead (the trial's "16 sectors or more" goes). The distance starts at one sector, C15 bounds what an early end wastes, and C14 sends nothing for sectors in the buffer. | settled | user 2026-11-15 (round 5 Q1, "언급없는건 추천대로") | `S` is any size |
| D29 | A serial walk run by a worker thread (a parallel subquery's) reads ahead too: the pool needs no reservation, so the reason to keep it off (a worker reserving workers) is gone. | settled | user 2026-11-15 (round 5 Q2) | a walk is a walk, whichever thread runs it |
| D30 | Only D26's parameter turns the read-ahead off; `parallelism` and the `NO_PARALLEL_SCAN` hint do not touch it. | settled | user 2026-11-15 (round 5 Q4) | — |
| D31 | A walk run again (the inner scan of a nested loop join, `scan_reset_scan_block`, `scan_start_scan`) starts again at distance 1, as PostgreSQL's `read_stream_reset` ("Start off assuming data is cached"). A cached inner sends nothing (C14); a cold one grows again by feedback. The issue's "do not start the next pass when this one had nothing to read" is not needed. | settled | user 2026-11-15 (round 5 Q5) | a pass is a walk: its state starts from `Init`'s values (two walks, `NW = 2`) |
| D32 | The workers of a parallel heap scan do not read ahead; only a serial walk does (D29). Measured cold on perf-node0 (run 20261115-130112-248, trial build ec26894fca74bd1f with per-worker loaders, orders SF10 2.4 GB, 6 runs each, medians): at equal thread counts more scan workers beat loaders: 4 threads: parallel 4 1.43 s, parallel 2 + one loader each 1.56 s; 6: parallel 2 + two loaders each 1.64 s; 8: parallel 8 1.10 s, parallel 4 + one loader each 1.33 s, parallel 2 + three loaders each 1.47 s, serial + 8 loaders 1.51 s; parallel 2 alone 2.08 s, serial alone 3.64 s. A loader helps a parallel scan (2.08 -> 1.47..1.64, 1.43 -> 1.33) but the same thread spent as a scan worker helps more, so the threads go to `parallelism`. On the SATA SSD of the development host every configuration except the serial scan without loaders took 4.41..4.47 s (device bandwidth), so it could not separate them. | settled | user 2026-11-15 ("로더붙힐바에 병렬 늘리는게 이득 ... 굳이 이거 진행안해도되겠다") | the model has no parallel scan; a walk is serial |

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
| C14 | A walk over a table whose sectors all stay in the buffer sends the read-ahead pool no request. | user 2026-11-14 ("버퍼에 많은 경우도 있으니 적응적으로"); round 2 Q2 2026-11-15 accepted (the walk checks the sector's first listed page; in scan order it is the oldest page of the sector in the LRU, so it is the first to leave). Prior art: PostgreSQL `bufmgr.c` `StartReadBuffersImpl` pins every block ahead and issues I/O only for misses, `read_stream.c` decays the distance to 1 and takes `fast_path` on an all-hit scan (b0392c26bd3); a pin ahead is struck here (D20, C10) |
| C15 | A walk that ends after entering k sectors has sent at most 2k+1 read-ahead requests (a scan ended early by a LIMIT reads little for nothing). | user, Q3 2026-11-15 ("응") |
| C16 | Nothing reads a walk's memory after the walk ended; the walk's end waits for no request. | D24 (the request is a copy); round 2 Q3 2026-11-15 accepted |
| C17 | A walk never waits for a read-ahead thread: a request the pool cannot take now is dropped. | D24 (`try_task`); round 2 Q3 2026-11-15 accepted |
| C18 | A sector the walk read itself because the pool refused its request does not make the walk's read-ahead distance grow: when the pool is full, a longer distance only adds refused requests. | user 2026-11-15 (round 4 Q2 "응") |

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

`ReadAheadPool.tla` (D24, D25) is a design model: the pool does not exist in the branch (the trial reserves 8 parallel query workers per scan). The code sites below are where the design puts each step.

| Model | Code (planned) | Protection | One step because |
|---|---|---|---|
| `WEnter` | `scan_heap_next_listed_page` at page offset 0 (today's `scan_heap_read_ahead` call): the distance and the last sector to ask for | private to the walk | private state |
| `WReq` | per sector up to the target: the hot check (a hash lookup of the sector's first listed page), then `worker_pool_task_capper::try_task` with a request holding a copy of the sector | the capper's mutex (`thread_worker_pool_taskcap.cpp`) | the free-thread check and the hand-over are one hold of that mutex |
| `WReqEnd`, `WNext`, `WStop` | the walk's own control flow; `WStop` is `scan_end_scan` / an error / an interrupt, which frees nothing a request uses | private | — |
| `WFix`, `WReadDone`, `WReadErr` | `heap_page_list_fix_next`: the page is in the buffer, or buffer-locked by another reader (`pgbuf_lock_page` waits), or read by the walk's own `pgbuf_load_page_run` (D18) | the page's hash mutex and buffer lock (`PageBatchRead`) | a sector is the unit here; `PageBatchRead` has the pages |
| `TLock`, `TDone`, `TErr` | the pool thread: `heap_page_list_load_sector` → `pgbuf_load_page_run` on the copied sector; the run ends at a page in the buffer or being read | as `PageBatchRead`'s `BLock` .. `BInstall`, `BReadError` | — |
| `Evict` | `pgbuf_get_victim` of a page no walk holds | BCB mutex | — |

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
| `Ends` (`ReadAheadPool.live.cfg`) | liveness, WF on each walk's steps but `WStop` and on each pool thread | C13 |
| `HotNoRequest` | invariant | C14 |
| `WasteBound` | invariant | C15 |
| `NoUseAfterEnd` | invariant (ghost `uaf`) | C16 |
| `NoSlotWait` | invariant | C17 |
| `NoGrowOnRefused` | invariant (ghost `grewOnRefused`) | C18 |
| `IndInv` (`ReadAheadPool.apalache-indinv.cfg`, `Ramp = "wait_capped"`, S 3, 2 walks, 2 threads, MaxWin 1..16, evictions and errors any number) | inductive invariant | C14, C15, C16, C17, C18 are conjuncts |

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
- `ReadAheadPool` faults: a read error of a pool thread (`TErr`: the sector goes back out, nothing is reported) and of the walk (`WReadErr`: the scan ends with the error); a walk stops at any step but its own read (`WStop`: LIMIT, error, interrupt); eviction of a sector no walk holds (`Evict`); the pool refuses a request when no thread is free (`WReq`). Not applicable: lock timeout and deadlock victim (no lock manager lock), conditional latch (none taken), OOM (a refused allocation of the request is a refused request), crash (nothing durable), spurious wakeup (`try_task` never waits), concurrent DML, vacuum and checkpoint (as `PageBatchRead`: the batch read keeps C6 for any page), HA and nested statements (no snapshot read). Not modeled: server shutdown, which must stop the pool before the page buffer goes (a fault-table row for the implementation).
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
| `ReadAheadPool.mutant-ramp-each` (was `long`, the correct variant until round 2 struck Ramp "each") | walk enters sectors 1, 2, 3 with distances 1, 2, 4 and asks for sectors 2..7 → enters sector 4: distance 8, target 12 → asks for 8..12: 10 requests after 4 sectors (> 2·4+1). A `LIMIT` stopping there leaves 8 sectors read for nothing | design conflict between D25's rule and C15: round 2 question |
| `ReadAheadHandoff.mutant-loader-ignores-stop` | the loader's stop check | `Ends` (liveness) | C13 |
| `ReadAheadPool.mutant-err-keeps-lock` | the release of the buffer lock when a pool thread's read fails | `Ends` (liveness: the walk waits for the sector for ever) | C13 |
| `ReadAheadPool.mutant-no-hot-check` | the walk's check that the sector is already in the buffer | `HotNoRequest` | C14 |
| `ReadAheadPool.mutant-no-ramp` | the ramp: the longest distance from the first sector (the trial's 16) | `WasteBound` | C15 |
| `ReadAheadPool.mutant-task-reads-scan` | the copy: the request reads the walk's state (where the walk is, to skip a passed sector) | `NoUseAfterEnd` | C16 |
| `ReadAheadPool.mutant-push-blocks` | `try_task`: the walk waits for a free thread (`push_task`) | `NoSlotWait` | C17 |
| `ReadAheadPool.mutant-ramp-each` | (struck rule, D25) the distance doubles at every sector entered | `WasteBound` | C15 |
| `ReadAheadPool.mutant-count-refused` | a sector the walk read itself because the pool refused it counts as a wait | `NoGrowOnRefused` | C18 |
| `ReadAheadPool.mutant-wait-uncapped` | (option, round 3) the distance doubles after every sector the walk waited for, with no cap by the sectors entered (PostgreSQL's `read_stream.c` rule) | `WasteBound` | C15 |

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
| `ReadAheadPool.witness-used` | a walk finds a sector a pool thread put into the buffer |
| `ReadAheadPool.witness-cross` | ... one another walk's request put there (two scans share the pool's work) |
| `ReadAheadPool.witness-stale` | a request starts after its walk passed its sector |
| `ReadAheadPool.witness-refused` | the pool refuses a request and the walk goes on |
| `ReadAheadPool.witness-hot-done` | a walk over a table all in the buffer ends |
| `ReadAheadPool.witness-shrunk` | a walk's distance goes down after sectors found in the buffer |
| `ReadAheadPool.witness-all-done` | every walk and every request end |

## Dead expressions (pass cfg)

| Line | Cfg | Why it is never evaluated |
|---|---|---|
| PageBatchRead.tla:304, PageBatchRead.tla:305, PageBatchRead.tla:306, PageBatchRead.tla:307, PageBatchRead.tla:308, PageBatchRead.tla:309, PageBatchRead.tla:310, PageBatchRead.tla:312 | `PageBatchRead.live` | `BReadError` is disabled by `MaxErrors = 0` in the liveness cfg (P68: smallest bound); the main cfg fires it (`witness-errored`) |
| PageBatchRead.tla:207, PageBatchRead.tla:208, PageBatchRead.tla:209, PageBatchRead.tla:210, PageBatchRead.tla:211 | `PageBatchRead.live` | `Reset` as called from `BReadError` (TLC counts an operator's body per call site); its calls from `BInstall` and `FInstall` fire |
| ReadAheadHandoff.tla:149, ReadAheadHandoff.tla:150 | all `ReadAheadHandoff` pass cfgs | `LRelease`: the loader holds a read latch only under the struck option `latch_pin` (`mutant-latch-pin`) |
| ReadAheadPool.tla:228, ReadAheadPool.tla:229 | all `ReadAheadPool` pass cfgs | the blocking push's branch, taken only by `mutant-push-blocks` |
| ReadAheadPool.tla:214, ReadAheadPool.tla:215, ReadAheadPool.tla:216 | `ReadAheadPool.option-long-walked`, `option-long-wait-capped` | the hot skip: with one walk starting cold, the sector after the last one asked for is put into the buffer only by the walk itself, after it asked (`req` only grows); the main cfg fires it (`Start = "any"`, two walks) |

## Bounds and limits

- `PageBatchRead`: main 3 pages of one run, 2 content versions, 3 BCBs, 2 batch readers (a run of up to 3 pages each, any start page) and one single-page fixer doing 2 fixes, 1 read error. Scale: 4 pages, runs of up to 4. Liveness: 2 pages, 2 BCBs, 1 fix, no error (P68). Not modeled: the hint to the OS for the next sector (`heap_page_list_hint_sector`: nothing is read into the buffer, no state the scan or the buffer uses), the LRU position of the loaded pages, TDE decryption other than as a failure, temporary volumes (not read in runs), more than one waiter per page (each waiter is woken by the same unlock).
- `ReadAheadHandoff`: 3 pages, read-ahead distance 2, 3 BCBs (4 for the option `flag`: two marked pages, the writer's and the other thread's), one loader, one writer, one other thread. Scale: 4 pages, 4 BCBs. Not modeled: where a loaded page sits in the LRU list (it changes how likely an eviction is, not whether it can happen), several loaders (`PageBatchRead`), the batch read's steps.

- `ReadAheadPool`: main 3 sectors, 2 walks, 2 pool threads, distance up to 2, 1 eviction, 1 read error, any start (each sector in or out). Scale: 4 sectors, the claims' invariants without IndInv (IndInv is checked on every reachable state of the main cfg and inductively over every value of the integer constants by Apalache; with it the scale run timed out at 1800 s after 35.5M distinct states, the queue still growing (run heap-scan-read-ahead-20261115-131600-391021)). Liveness: 2 sectors, 1 thread (P68). `mutant-ramp-each`/`mutant-wait-uncapped`/`option-long-*`: 12 sectors, one walk, 1 thread, distance up to 8, cold start (the ramp needs the length). Not modeled: the pages of a sector (`PageBatchRead`), the pool's 5 s idle exit (a thread count, not a state any claim reads), several tables.

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

`ReadAheadPool` (2026-11-15) has no whole-directory `RESULT: OK` yet: the record run was stopped by the user. Last results per cfg: run `heap-scan-read-ahead-20261115-131600-391021` (`RESULT: FAILED (6)`): 56 cfgs PASS, among them `ReadAheadPool.apalache-indinv` (12 s), the 9 mutants and the 7 witnesses; main (with IndInv) 33,391,282 states generated / 8,686,827 distinct, depth 41, and live, option-walked, option-long-walked, option-long-wait-capped got pass from TLC but failed the completeness check on dead-expression line numbers MAP.md had not updated (fixed since: 228, 229 and 214..216); scale-4s timed out at 1800 s with IndInv. `--only ReadAheadPool.scale-4s` without IndInv, run `heap-scan-read-ahead-20261115-151728-419628`: PASS, 1,053,893,090 / 250,506,879, depth 54, 7937 s. Open: one whole-directory record run after these edits.
