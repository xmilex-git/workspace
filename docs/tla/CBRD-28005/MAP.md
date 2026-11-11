# CBRD-28005 — asynchronous read-ahead for scans: `AsyncRead` (who completes an I/O), `ReadStream` (the heap full scan over a read-ahead window), `OidBatch` (the index scan's heap reads), `BitmapScan` (the whole-range batch: parallel index phase, then parallel heap phase), `BatchJoin` (the batched nested-loop join as implemented), `BatchJoinDesign` (the design it was cut from)

Chosen design since 2026-11-10 (D34): read-ahead is an OS hint (`posix_fadvise`), reads stay synchronous; the scans read in file order where they can (page-list order, the whole-range batch of D25..D33) and hint ahead where they cannot. `AsyncRead` below models the io_uring alternative that was built, verified, trace-validated and then not chosen; `ReadStream` and `OidBatch` were written for that mechanism and are to be reworked for the hint (their claims C3..C7 stay). Original header: design spec for asynchronous (io_uring) page reads into CUBRID's page buffer, in two modules. `AsyncRead` settles who reaps a completed read (C1, C2). `ReadStream` is the heap full scan over a read-ahead window: page-list order, completion-order consumption, a finite frame pool, demotion to the LRU bottom (C1, C3, C4, C5, and C2 again with the frame pool). No implementation
yet: the code column names the develop site the design changes (origin/develop `37182deba`,
worktree `~/dev/cubrid-worktree/aio-design`) and the PostgreSQL site the pattern comes from
(`~/dev/postgres` `b0392c26bd3`).

trace-exempt: `ReadStream` and `OidBatch` are designs with no implementation yet (stages 2 and 3); `BatchJoinDesign` is the stage 4 design whose remaining parts (rows that span batches, semi and anti joins, the free order mode) are not implemented; `AsyncRead`, `BitmapScan` and `BatchJoin` are validated against recorded runs (`AsyncReadTrace`, `BitmapScanTrace`, `BatchJoinTrace`, below)

## Design tree (grilling ledger)

| # | Decision | Status | Where in the model |
|---|---|---|---|
| D1 | First target: reads of large cold-cache heap scans only. Writes (DWB, flush, checkpoint) are out; random heap reads from index scans / NL inner (b) follow only if (a) pays off; log flush out. | settled 2026-11-10 (Q1) | scope: reads only, no write actions |
| D2 | Buffered I/O stays (OS page cache); io_uring only issues many reads at once. O_DIRECT out of scope. | settled 2026-11-10 (Q2) | not modeled (no cache layer) |
| D3 | Completions are reaped by the ring's owner and by any thread asleep on a page whose I/O that ring holds (per-thread ring + per-ring completion mutex; `IORING_SETUP_DEFER_TASKRUN`/`SINGLE_ISSUER` not used). Rejected options below. | settled 2026-11-10 (Q3, Q7); ADR 0054 | `Reaper = "any_waiter"` (`AsyncRead.cfg`, `AsyncRead.live.cfg`) |
| D4 | `io_method = sync \| io_uring` system parameter, default `sync`; a failed `io_uring_setup` logs and falls back to `sync`. io_uring only: no `worker` method (kernels without io_uring, such as el8's 4.18, stay on `sync`). Ring flags: `IORING_SETUP_COOP_TASKRUN` at most, never `DEFER_TASKRUN`/`SINGLE_ISSUER` (D3). | settled 2026-11-10 (Q4, Q14) | not modeled (setup) |
| D5 | liburing bundled in `3rdparty/CMakeLists.txt` (pinned URL + SHA256), `WITH_LIBURING`; dev builds on this host use nixpkgs liburing 2.14 (nolibc build, kernel 6.9). | settled 2026-11-10 (Q5) | not modeled (build) |
| D6 | Spec in `docs/tla/CBRD-28005/`; a CBRD draft is written from it at the end, filed only on approval. | settled 2026-11-10 (Q6) | — |
| D7 | A thread never sleeps with staged, unsubmitted SQEs; implemented structurally: a read-ahead call submits everything it staged before it returns. | settled 2026-11-10 (Q8) | `DeferSubmit` is mutant-only; IndInv `StagedOnlyInsideReadAhead` |
| D7b | A scan sleeps for a victim frame only with an empty ring: it reaps its own completions first, since its own frames under I/O may be the only future victims. | found by the model, settled 2026-11-10 (Q23) | `WaitFrame` guard; `ReadStream.mutant-frame-wait-with-io` |
| D7a | Inside a refill the thread never sleeps either: read-ahead does not wait for a victim frame (no free frame at once -> the refill stops, read-ahead is a hint) and does not wait on a page another thread has under I/O (it only notes the page). | settled 2026-11-10 (Q19) | the read stream model (to write): finite frame pool |
| D8 | A thread submits and drains its own ring before it returns to the thread pool (query end, interrupt, error). | settled 2026-11-10 (Q9) | `Finish` guard; `mutant-no-drain`, `mutant-drop-on-interrupt` |
| D9 | Two layers: read-ahead (I/O, below `pgbuf_fix`) feeds the page batch (row computation, one page = one chunk). A heap full scan has no row order to keep: it is designed for speed (pages may be consumed in any order). | settled 2026-11-10 (Q10) | the read stream model (to write) |
| D10 | Page-list order replaces chain order (option A) for: the query heap full scan (XASL heap scan, page batch and row mode), index build, statistics, unloaddb. Kept in chain order: catalog access, checkdb, classes without MVCC, tables under a size threshold. The switch happens only when `io_method` is not `sync` (default `sync` keeps today's order and CTP answers). | settled 2026-11-10 (Q11, Q16) | the read stream model (to write) |
| D11 | A page read ahead and not yet fixed stays an ordinary unfixed valid page (may be victimized and read again); read-ahead depth is capped. | settled 2026-11-10 (Q12) | `Victimize` of a valid frame, `IssueRead` again |
| D12 | "(a) pays off" = cold-cache TPC-H SF10 Q1/Q6 wall time down >= 20% and warm-cache instructions:u regression <= 1%. Measured on this development host (kernel 6.9, NVMe, xfs), not on the perf servers (kernel 4.18, no io_uring). | settled 2026-11-10 (Q13, Q14) | — |
| D13 | Reads go through the page buffer; no buffer-pool bypass (a private read has no BCB claim, so a concurrent flush of the page can be read torn, and there is no page checksum to catch it). | settled 2026-11-10 (Q17) | — |
| D14 | Read-ahead depth, combined-read size and the small-table threshold are system parameters (depth up to 1 GB). Effective depth = min(parameter, buffer size / 8 / the query's scan workers), adaptive from 1 page. Default depth = PostgreSQL's shape, about 2.1 MB (136 pages of 16 KB: 17 reads of 128 KB). Measurement compares exactly two depths, 2.1 MB and 200 MB. Research: `docs/research/async-io-read-ahead-sizing.md`. | settled 2026-11-10 (Q18, Q21) | `W` (window), `NFrames` in `ReadStream` |
| D15 | A full scan gives up the pages it read as soon as it unfixes them: they go to the LRU bottom (`PGBUF_BCB_MOVE_TO_LRU_BOTTOM_FLAG`), so they are the next victims and need no flush. Only pages the scan read itself, only for a table larger than 1/4 of the buffer; a page that was already in the buffer keeps its place. The scan-owned frame ring (PostgreSQL `BAS_BULKREAD`) was not chosen. | settled 2026-11-10 (Q17, Q20) | `bottom`, `reader` in `ReadStream`; C5 |

| D16 | Index-driven heap reads use one device, the OID batch fetch: OIDs are collected in bounded batches (from one index range scan, later from a batch of nested-loop outer rows), grouped by heap page, the pages read ahead, and each page's matching rows processed as one page batch chunk. Where the index order is needed (ORDER BY skipped through the index, ordered LIMIT) only the read-ahead is used and the lookup stays in key order. No optimizer-chosen bitmap heap scan path. An executor change: recorded on CBRD-28005, implemented under its own issue. | settled 2026-11-10 (Q24, Q25, Q26); measurements in `docs/research/async-io-read-ahead-sizing.md` (Q7, Q9, Q20 cold time is index-driven random reads) | `OidBatch` (one index range scan per thread; the batch of nested-loop outer rows is not modeled) |
| D17 | A completion (reap) only turns the BCB valid or failed and wakes waiters; the heap-side work on a page (page batch, row processing) is done by the scanning thread, which takes whichever page of its window is ready first. It is not run inside the completion callback, because any thread asleep on the page may run that callback (D3) and the scan's state is private to its thread. | settled 2026-11-10 (Q27) | `ReapOne` touches only the BCB; `Fix`, `Process` by the scan (`ReadStream`, `OidBatch`) |
| D18 | No accumulator thread: the scanning thread (each worker of a parallel index scan) alternates three things — process a ready page, accumulate more OIDs and issue their reads while the window has room, wait for a completion when nothing is ready and the window is full. Accumulation continues while earlier reads are in flight, bounded by the window. PostgreSQL builds the whole bitmap before any heap read (`nodeBitmapHeapscan.c` `MultiExecProcNode`; parallel: one process builds, the others sleep until `BM_FINISHED`), and Gather only collects result tuples. | settled 2026-11-10 (Q28) | `Accumulate*`, `Fix`, `Process`, `SleepOnPage` in `OidBatch` |
| D19 | Nested-loop joins that follow an index (TPC-H Q7 type) get true outer-row batching, not read-ahead hints: N outer rows are collected, the inner lookups of the batch are done together, their OIDs grouped by heap page and processed as page batch chunks (D16's second source of OIDs). Where the plan relies on the order (ORDER BY skip, GROUP BY skip, a merge above), the batch keeps the outer order. The executor change (`qexec_execute_scan` re-opens the inner scan per outer row; memoize, semi/anti join, partitions, LIMIT) is its own design round. | settled 2026-11-10 (Q30: the user chose B over the recommended hint variant, "with ORDER BY skip and the like in mind") | `BatchJoinDesign`: `AddOuter`, `CloseBatch`, `EmitOne` (C8) |
| D20 | The first version batches one join level: the outer rows of one nested-loop step against its own inner scan. Chaining batches across levels (customer -> orders -> lineitem) is decided after measuring. | settled 2026-11-10 (Q31) | `BatchJoinDesign` models one join level |
| D21 | D19's first version covers inner and left outer joins, semi and anti joins and a partitioned inner; they are modeled together, in one model (adding a case later multiplies the branches). A following join and FOR UPDATE scans keep the row-at-a-time path. | settled 2026-11-10 (Q34: the user widened the recommended scope) | `BatchJoinDesign`: `jt` over inner, left, semi, anti; the partitioned inner as `PartStart` (a row's entries span two partitions) |
| D22 | The order mode of a batch is fixed when the plan is generated: order kept where the plan relies on it (ORDER BY skip, GROUP BY skip, an input a parent expects sorted), free (first page to arrive first) otherwise. | settled 2026-11-10 (Q35) | `BatchJoinDesign`: `mode` fixed in `Init` |
| D23 | Memoize stays on a batched inner (the optimizer attaches it to nearly every nested-loop inner: `plan_generation.c` clears it only when `qo_nl_inner_memoize_is_useless`): each outer row of a batch is checked against the memoize storage first, only the misses are looked up, and their results are stored. | settled 2026-11-10 (Q36: the user corrected the premise "memoize means repeating keys") | `BatchJoinDesign`: the memoize check in `AddOuter`, the copy `hitm`, `MemoDrop` |
| D24 | A batch is as large as the OID buffer: outer rows are collected until their inner lookups fill it. No growth from one row. | settled 2026-11-10 (Q37) | `BatchJoinDesign`: `BufCap` |
| D25 | The OID batch fetch gets a second mode, the whole-range batch (what PostgreSQL calls a bitmap heap scan): every OID of the key range is collected first, then the heap is read in file order, each page once, by parallel workers. One executor device with two modes; it amends D16's "no bitmap heap scan path". Modeled together with the bounded batch. | settled 2026-11-10 (Q39) | `BitmapScan` (index phase, then heap phase) |
| D26 | Whether an index scan runs as a whole-range batch is fixed when the plan is generated (non-covering, no order needed, no early stop by LIMIT, estimated matching rows above a threshold); never switched during execution. | settled 2026-11-10 (Q40) | `BitmapScan` models a scan already planned as a whole-range batch; the plan-time rule is not modeled |
| D27 | The whole-range batch has no memory budget, as the sector collection of today's parallel heap scan has none ("large batch = OLAP query = no limit"). Its OIDs are not kept as a list to sort: the heap's sectors are taken first (`file_get_all_data_sectors`, as the parallel heap scan does) and each OID is recorded in its sector's bitmap, so the heap phase walks the sectors in file order with no sort. Amended by D36 (2026-11-10): the bitmap has a bound, `max_hash_list_scan_size`; above it the bitmap holds one bit per page. | settled 2026-11-10 (Q39, Q41: the user's proposal) | `BitmapScan`: `bm`, `pagebm` hold marks, not an OID list; `lossy` is the bound exceeded |
| D28 | A batched nested-loop join closes its batch when the OID buffer is full or when the stored outer rows reach the same size in bytes. | settled 2026-11-10 (Q42) | `BatchJoinDesign`: `MaxOuter` (rows instead of bytes) |
| D29 | The whole-range batch records rows exactly: per sector the 64-bit page mask, per touched page a slot bitmap. The heap phase reads only marked pages and looks only at marked rows; there is no page-level (lossy) form and no recheck of the index condition. Amended by D36 (2026-11-10): exact only while the bitmap fits the bound and the slot is inside the bitmap's width; otherwise the page is marked as a whole, every row of it is read and the index condition is checked again on the heap row. | settled 2026-11-10 (Q43) | `BitmapScan`: `bm` (row bits), `pagebm` (page bits), `Lookup`'s recheck; mutants `no-recheck`, `both-paths` |
| D30 | An OID whose page is not in the sector list taken at the start is dropped: with the statement's snapshot taken before the list, rows on pages allocated later are invisible to it (the argument of today's parallel heap scan, `px_scan_input_handler_heap.cpp:init_on_main`). Classes without MVCC do not use this mode (as D10). | settled 2026-11-10 (Q44) | `BitmapScan`: `ListedSectors`, `Mark` drops r5, `VisibleListed`; mutant `late-sector-list` |
| D31 | (superseded by D32 the same day) The index phase of a whole-range batch is one thread walking the key range, only the heap phase is parallel, and the existing parallel index scan is deprecated. | Q45 2026-11-10, withdrawn by the user | — |
| D32 | The parallel index scan stays (also for covering scans and the parallel GROUP BY skip merge: Q46 (a)). In a whole-range batch it is the index phase: its workers take leaf pages as today, check key range, key filter and visibility, and record each OID in a sector bitmap of their own (no heap lookup, nothing shared, so no synchronization while filling). When every index worker has finished, the worker bitmaps are merged (OR per sector and page) and the scan goes on as a parallel heap phase over the merged bitmap, sectors handed to workers as the parallel heap scan does. Amended by D36 (2026-11-10): the workers mark one shared bitmap by atomic OR, not a bitmap each. | settled 2026-11-10 (the user's redesign after Q45/Q46) | `BitmapScan`: `Mark(w)` on the shared `bm`/`pagebm`; mutant `nonatomic-or` |
| D33 | The worker bitmaps are merged lazily and in parallel: the heap-phase worker that takes sector S ORs the index workers' entries for S; no thread merges the whole bitmap. No heap worker takes a sector before every index worker has finished. Amended by D36 (2026-11-10): with one shared bitmap there is no merge; the barrier stays. | settled 2026-11-10 (Q47) | `BitmapScan`: `TakeSector` (the barrier), `ExamCount` |
| D34 | The read-ahead mechanism is a hint to the OS, `posix_fadvise (POSIX_FADV_WILLNEED)` on the pages a scan is about to read that are not in the buffer; the reads themselves stay the synchronous path of today. io_uring is not used: it is kept as the recorded alternative (`io_uring-alternative/`, ADR 0054, the `AsyncRead` model and its traces). Measured reason: on scattered 16 KB reads the hint reaches the same I/O concurrency as io_uring on SATA and NVMe, and io_uring wins only for one copy-bound thread with `IOSQE_ASYNC` at about three times the CPU (`docs/research/async-io-read-ahead-sizing.md`). With it D3, D4, D5, D7, D7a, D7b and D8 (rings, who reaps, no sleep with staged requests, drain before the pool) and claims C1 and C2 apply to the alternative only: a hinted page has no frame, no owner and no completion. | settled 2026-11-10 (Q48, Q49; ADR 0055) | not modeled (no shared state); `AsyncRead` = the alternative |
| D35 | The result of an outer row that spanned batches is memoized when its last batch closes (the matches of the earlier batches are carried anyway). | settled 2026-11-10 (the user: "넣어") | `BatchJoinDesign`: `Storable`, `StoreVal`; mutant `memo-partial` |
| D36 | The sector bitmap is one shared bitmap: outside it the ordered sector list, inside it bits only, marked by the index workers with atomic OR (no per-worker bitmaps, no merge). Its memory bound is `max_hash_list_scan_size` (the hash size bound of hash list scans and hash joins: default 8 MB, at most 128 MB, part of the XASL cache key). When the exact bitmap would be larger, the bitmap holds one bit per page, as PostgreSQL's lossy pages: the heap phase reads every row of a marked page and checks the index condition again. (1) Exact or pages-only is decided once when the scan opens, from the sector count and the bitmap's width, never switched during the scan: the sector list is known before the first mark, so the bitmap's size is known then (the user, 2026-11-10; PostgreSQL's switch during the build, `tidbitmap.c` `tbm_lossify`, and row bits allocated per sector on its first mark were put to the user and not taken). (2) A slot number beyond the exact bitmap's width marks its page as a whole (no separate OID list); the width is D37. | settled 2026-11-10 (the user: atomic OR; above `max_hash_list_scan_size` one bit per page as PostgreSQL); (1) confirmed by the user 2026-11-10 ("처음에 다 아는데": decided at open); (2) settled with D37; amended 2026-11-11 (the user: "hash list scan size말고 ... 16MB로 기본값을 늘리자. 용도가 다른것같네", then chose a parameter of its own over the existing OID buffer size): the bound is `index_scan_oid_bitmap_size` (new, default 16 MB, 0 to 1 GB, changeable per session), not `max_hash_list_scan_size` | `BitmapScan`: `lossy` (fixed in `Init`), `Wide`, `bm`, `pagebm`, `Mark`, `ExamCount`, `Lookup` |
| D37 | The exact bitmap's width per page is computed when the scan opens, from values known then: width = min(slot bound of a page, floor(`max_hash_list_scan_size` in bits / (sectors x 64))), rounded down to a multiple of 64; when that is below 64 the bitmap is pages-only (this is the one decision of D36 (1)). A slot number at or beyond the width marks its page as a whole (no separate OID list). With the default 8 MB and 16K pages: the full width (1,408 bits) up to 47,662 pages (745 MiB), lineitem of the TPC-H scratch DB (about 731,000 pages, about 82 rows a page) 91.8 -> 64 bits = 5.85 MB with slots 64 and above marking the page, pages-only above 1,048,576 pages (16 GiB). Not taken: the slot bound as a fixed width (PostgreSQL: `MaxHeapTuplesPerPage`, an offset beyond it is an error, `tidbitmap.c:382`; there only touched pages take an entry, here every page takes the width: 129 MB for lineitem), a fixed 64 or 128, a width from the heap header's row estimate (`heap_file.c` `heap_hdr_stats`), a separate list for the OIDs beyond the width. Code facts behind it: a default table reuses deleted slots from the lowest (`slotted_page.c` `spage_find_free_slot`, `create_table_reuseoid` default yes); a `DONT_REUSE_OID` table keeps a deleted slot as a 4-byte `REC_MARKDELETED` entry, so its slot numbers pass the count of live rows. | settled 2026-11-10 (the user, after the lineitem calculation under this rule and the default of the parameter: "굿. 8MB로 깔고가자"); amended 2026-11-11 by the lead, to whom the user left the judgment after the measurements ("각각 한번씩만 재서 판단해줄래"): the width is not rounded down to a multiple of 64 (lineitem: 93 bits, every row marked exactly; with 64 bits the pages with a slot of 64 or more were read as a whole and the hot run took 2.5 s instead of 0.53 s), below 64 bits a page the bitmap is still pages-only; confirmed by the user 2026-11-11 ("64의배수로 내리는건 안해야겠네") | `BitmapScan`: `Wide` (a row whose slot is beyond the width), `lossy`; the width is not a value of the model |
| D38 | Stage 4 as implemented (`nl_join_batch`, a server parameter, default no). Every step of a nested-loop chain whose inner is a plain index scan with a heap lookup (one key or one range; not covering, no multi-range optimization, no index skip scan, no key limit, no FOR UPDATE) holds the outer rows that reach it, as copies of the outer's value list, and reads the inner index for each at once. The batch closes when the stored OIDs reach its target (16 OIDs for the first batch of a join, twice as many each time up to one OID buffer: a join that stops after a few rows reads few rows ahead), when the stored rows reach the same size in bytes (D28), when a row has more OIDs than one OID buffer, or when the outer scan ends. At the close the heap pages of every stored OID are named to the OS (D34's hint), and the rows are joined in the order they came through the unchanged row path, each finding its OIDs read already. A key memoize holds, a null join value and a row with more OIDs than one buffer are held without OIDs and answered by the row path. After a batch with nothing to hint (every page in the buffer, or one page) the following outer rows are joined row at a time, 64 at first and twice as many each time up to 65,536. Kept row at a time: semi, anti and following joins (cut from D21), an outer that is not a table scan, an outer with correlated subqueries or path expressions, a first scan with its own row-loop work (instnum, an if or after-join predicate, CONNECT BY, GROUP BY skip: the first scan marks the row that starts a key for the join row that follows). Not implemented from the design: the free order mode (D22: the join always keeps the outer order), rows that span batches (D35: such a row is joined by the row path, which reads and hints its own OID buffers), chaining across levels (D20: a level's batch is joined when its outer's rows for the current row of the level above end). | implemented 2026-11-11 on the user's "묶음 조인도 진행해"; engine commit `e802abfa7` (fork branch `CBRD-28005-aio`); the user's answer to the reduced scope is D39 | `BatchJoin`: `AddOuter` (read or deferred), `PassRow`, `CloseBatch`, `OpenRow`, `RowDone`, `Restart` |
| D39 | User decisions on the batched join (2026-11-11). (1) The reduced scope of D38 is not enough as it is: TPC-H Q9 and Q20 must get faster too ("Q9 와 Q20도 빠르게 하는게 아니면 의미가 없어"). Q9's largest read is the first join step inside the workers of a parallel scan, which D38 does not batch; Q20's is the index lookup of a correlated subquery run per outer row. Both are to be added. (2) Statements whose snapshot a nested statement rebuilds keep batching; C8 is stated for a statement whose snapshot is not rebuilt. (3) Errors of rows read up to one batch ahead are accepted and documented. (4) The trace token `nlbatch` stays. (5) The `BitmapScan` model supplements handed over by another session (review notes of 2026-11-11, points 3 to 7) are not done. | settled 2026-11-11 (the user's answers to Q1..Q5) | C8's wording; `BatchJoin` is unchanged by (2)..(5); (1) is open work |

### Rejected completion mechanisms (D3)

| Option | Verdict | Reason |
|---|---|---|
| (iii) only the issuer reaps its ring | rejected by TLC | `mutant-owner-only` violates C2: T2 reads p1 ahead and sleeps on X; T1 holds X and sleeps on p1; the CQE sits in T2's ring and only T2 may reap it. The query hangs until it is cancelled. |
| (ii) a completion daemon reaps every ring | verified (`option-daemon.cfg`, `option-daemon-live.cfg`), not chosen | every completion costs a context switch through the daemon before the waiter wakes, and one daemon is the bottleneck at high IOPS; its advantages (no drain rule D8, frames nobody waits for get completed) are bought by D8 in the chosen design. Kept as the comparison cfgs; it is also the shape a `worker` I/O method would have (the thread that performs the read completes it). |
| SQEs left staged when the read-ahead call returns (staging decoupled from submit; in PostgreSQL the rule "no blocking with staged IOs" is a discipline on the block-number callback and on `StartReadBuffers` inside `read_stream_look_ahead`, opt-in by `READ_STREAM_USE_BATCHING`) | rejected | a thread that sleeps with staged SQEs hangs its waiters under either reaper (`mutant-block-with-staged`, `mutant-daemon-block-with-staged`). Nothing is lost: PostgreSQL's batch also spans exactly one look-ahead call (`read_stream.c:666` enter, `:745` exit), and so does ours — one refill stages every SQE of the window and submits once (`io_uring_submit`, or `io_uring_submit_and_wait` when the scan must wait anyway). CUBRID's page source is an in-memory sector list, so no foreign code runs between staging and submit and the rule is an assert at the function's exit. |

## Claim and sources

| # | Claim | Source |
|---|---|---|
| C1 | A buffer frame is never reused (victimized, reassigned to another page) while a read into it is in flight. | user, grilling Q9 2026-11-10; PostgreSQL `src/backend/storage/aio/README.md` "AIO Callbacks" (stage callbacks pin the buffer for the AIO subsystem) |
| C3 | A heap full scan returns every row its snapshot sees exactly once, in no defined order; a page deallocated before it is read is skipped. | user, grilling Q10, Q11, Q15 2026-11-10 |
| C4 | A scan that ends early (LIMIT, interrupt, error) leaves no page fixed, drains its ring and leaves no frame under I/O. | user, grilling Q15 2026-11-10 |
| C5 | A full scan demotes to the LRU bottom only pages it read itself; a page that was already in the buffer is never demoted by the scan. | user, grilling Q20 2026-11-10 (conditions of option a) |
| C6 | Every OID an index scan collected whose row its snapshot sees is processed exactly once; a row vacuum removed between the index read and the heap read is skipped, as today's lookup does. | user, grilling Q33 2026-11-10 (proposed with Q27) |
| C7 | Where the index order is needed, rows leave in key order. | user, grilling Q33 2026-11-10 (proposed with Q27) |
| C8 | A batched nested-loop join returns the same rows, the same number of times, as the row-at-a-time join; in order-kept mode in the same order. An outer row of a left outer join with no inner match leaves exactly once. Stated for a statement whose snapshot is not rebuilt while it runs (a nested statement under READ COMMITTED rebuilds it; such statements are batched all the same); an error raised by a row read up to one batch ahead is reported also when the row-at-a-time join would have stopped before that row. | user, grilling Q38 2026-11-10; the two limits: user 2026-11-11 |
| C2 | A page I/O some thread waits for eventually completes and wakes the waiter, even when the issuing thread is asleep on a latch or lock, interrupted or failed; after every thread returns to the pool no frame stays under I/O. | user, grilling Q3 and Q9 2026-11-10; PostgreSQL README "Deadlock and Starvation Dangers due to AIO" |

## Refinement map (model -> code)

`AsyncRead` is the model of the stage 1 code (engine worktree `~/dev/cubrid-worktree/CBRD-28005`, branch `CBRD-28005-aio` on origin/develop `2dd94e32a`, uncommitted); the rows name `file:function`. The two other modules are still designs.

| Model | Code | One step because |
|---|---|---|
| `bcb[p]` `absent/io/valid` | `valid`: the page's BCB is in its hash chain. `io`: an entry for the VPID is in the hash anchor's buffer lock chain, either a thread's own `buf_lock_table` slot (`aio_owner = -1`, the thread reads the page itself: `page_buffer.c:pgbuf_lock_page`) or a `PGBUF_AIO_READ` (`aio_owner` = the reading thread's index: `page_buffer.c:pgbuf_read_ahead`). `absent`: neither | hash anchor mutex |
| `owner[p]` | `PGBUF_BUFFER_LOCK.aio_owner` of the entry, or the thread whose `buf_lock_table` slot it is | hash anchor mutex |
| `sq`, `inflight`, `cq` | `file_io.c` `fileio_aio_ring`: `staged` (prepared SQEs), the kernel, the ring's CQ; one ring per thread entry index (`fileio_aio_get_my_ring`). A read a thread does itself (`fileio_read` under its buffer lock) is modeled as an I/O in its own ring that it reaps itself | the ring is written only by its owner; the CQ is read under `cq_mutex` |
| `ReadAhead` | `pgbuf_read_ahead`: with a frame already claimed (`pgbuf_allocate_bcb (…, can_wait = false)`), the page is looked up again and its `PGBUF_AIO_READ` linked into the buffer lock chain; the request is staged by `fileio_aio_prepare_read` | hash anchor mutex (lookup + link); the frame is in no list and its VPID is null, so no other thread reaches it |
| `InlineComplete` | `pgbuf_read_ahead`: the page was in the double write buffer (`dwb_read_page`), or `fileio_aio_prepare_read` failed; `pgbuf_aio_read_done` runs in the call | same as `ReapOne` |
| `SubmitNow` | `pgbuf_read_ahead` -> `fileio_aio_submit` (`io_uring_submit` until `staged = 0`) before it returns | one syscall; `staged` is the owner's |
| `DeferSubmit`/`Submit` | no code: `pgbuf_read_ahead` has no exit that leaves `staged > 0` (assert in `fileio_aio_submit`) | mutant only |
| `TakeX`/`NoLock`/`BlockOnX`/`WakeX`/`ReleaseX` | any latch or lock the thread may wait on between its page-buffer calls (page latch in `pgbuf_fix`, lock manager) | abstract resource |
| `PickPage`/`NoFix` | the thread's own choice of the next page to fix | thread-local |
| `FixValid` | `pgbuf_fix_release`: the page was found in the hash chain (`pgbuf_search_hash_chain`, `pgbuf_lockfree_fix_ro`) | BCB mutex or the lock-free fix count |
| `IssueRead` | `pgbuf_claim_bcb_for_fix` -> `pgbuf_lock_page` returns `PGBUF_LOCK_HOLDER`: the thread's `buf_lock_table` slot enters the chain and the thread reads the page (`fileio_read`) | hash anchor mutex |
| `SleepOnPage`/`WakePage`, `waitRing[t]` | `pgbuf_lock_page` finds an entry for the VPID: for a thread's own read (`aio_owner = -1`) it sleeps on the entry (`pgbuf_sleep`) and is woken by `pgbuf_unlock_page`; for a read ahead it copies `aio_owner` (`waitRing`), lets the hash anchor mutex go and reaps that ring (next row); both return `PGBUF_LOCK_WAITER` and the fix starts over | condition wait: release-and-sleep, wake-and-look-up-again; `aio_owner` is read under the hash anchor mutex |
| `ReapOne` | `pgbuf_aio_read_done`: read ok -> `pgbuf_insert_into_hash_chain` + `pgbuf_unlock_page` (entry out of the chain) + LRU; failed -> `pgbuf_put_bcb_into_invalid_list` + `pgbuf_unlock_page`. For a thread's own read the same two exits are in `pgbuf_fix_release`/`pgbuf_claim_bcb_for_fix` | hash anchor mutex: the page turns `valid` (or `absent`) and leaves `io` in one critical section |
| `ReapOwn` | the owner calls `fileio_aio_reap (own index)`: at the start of `pgbuf_read_ahead` (no wait), in `pgbuf_lock_page` when the page it fixes is its own read ahead, in `fileio_aio_submit` on `-EBUSY`, in `pgbuf_aio_drain` | `cq_mutex` of the ring |
| `ReapForWaiter` | `pgbuf_lock_page`: the entry found is a read ahead of another thread -> `fileio_aio_reap (aio_owner, PGBUF_AIO_WAIT_MSECS)` (`io_uring_wait_cqe_timeout` on the owner's ring; needs `IORING_FEAT_EXT_ARG`, checked in `fileio_aio_initialize_once`). It processes whatever that ring holds, also when the page it came for was completed by another thread after it let the hash anchor mutex go | `cq_mutex` of the owner's ring |
| `DaemonReap` | design option not implemented | comparison cfgs only |
| `DeviceComplete` | the kernel posts a CQE | environment |
| `Victimize` | `pgbuf_delete_from_hash_chain` (`pgbuf_victimize_bcb`, invalidation): only a BCB in a hash chain is reachable; a frame under a read ahead is in no list | BCB mutex + hash anchor mutex |
| `Interrupt` | `logtb_is_interrupted` / an error on the thread while it waits: the fix fails and the request ends through the same drain | |
| `Loop` | the request goes on (next sector of `px_scan_input_handler_heap.cpp:get_next_vpid_with_fix`, next fix) | thread-local |
| `Finish` | `pgbuf_aio_drain` at the end of a request or task: `network_sr.c:net_server_request`, `thread_entry_task.cpp:entry_manager::recycle_context` and `retire_context` | loops `fileio_aio_reap (own)` until `fileio_aio_pending` is 0; `inflight` drops only after the completion functions ran |
| `Reuse` | the pool hands the thread its next task or request | |

Code outside this model: `pgbuf_allocate_bcb` drains the thread's own ring before it sleeps for a victim frame (D7b; `ReadStream`'s `WaitFrame`, traced with stage 2).

### ReadStream

| Model | Code (develop today -> design) | One step because |
|---|---|---|
| `todo`, `win`, `gone`, `got` | the scan's page list (`file_get_all_data_sectors` sector bitmaps, as `px_scan_input_handler_heap.cpp` uses them), the read-ahead window, the pages processed and the pages whose rows were returned | single owner (the scanning thread) |
| `bcb`, `owner`, `inflight`, `cq`, `res` | as in AsyncRead | BCB mutex, ring-local |
| `reader[p]` | design: a BCB mark "read by this scan's read stream" (who loaded the frame) | BCB mutex |
| `bottom` | the LRU bottom: `PGBUF_BCB_MOVE_TO_LRU_BOTTOM_FLAG` -> `pgbuf_lru_add_bcb_to_bottom` at unfix (`page_buffer.c`) | LRU list mutex |
| `Used`, `Eligible`, `Victims`, `TakeFrame` | `pgbuf_allocate_bcb` -> victim search; a fixed frame or a frame under I/O is not victimizable (`pgbuf_is_bcb_victimizable`) | BCB mutex of the victim |
| `RefillRead` | design: the read stream takes the next page of the list, claims a frame without waiting and stages + submits its read in the same call (D7, D7a) | hash anchor mutex + BCB mutex; one `io_uring_submit` per refill |
| `RefillNote` | the page is in the buffer, under another thread's read, or no frame is free at once: the stream only notes it | hash anchor mutex (lookup) |
| `ReadNow`, `FixNeed`, `ReadFailed` | the scan needs a window page that is not in the buffer: the ordinary `pgbuf_fix` read path through the ring; the frame is reserved for the fixer (`need`), which gets the page fixed when the read completes or reads again when it failed | BCB mutex |
| `WaitFrame`/`WakeFrame` | `pgbuf_allocate_bcb` waiting for a direct victim | condition wait |
| `SleepOnPage`/`WakePage`/`ReapForWaiter`/`ReapOwn` | as in AsyncRead | |
| `Fix` | `pgbuf_fix (OLD_PAGE_MAYBE_DEALLOCATED, PGBUF_LATCH_READ)` of a valid page | BCB mutex |
| `Process` | the page batch chunk or the row loop over the fixed page, then `pgbuf_unfix`; a deallocated page is skipped (`px_scan_input_handler_heap.cpp` page-type check) | under the page's read latch; the unfix ends the step |
| `EarlyEnd` | LIMIT reached, `logtb_is_interrupted`, an error on the scan | |
| `End`/`Finish` | end of the page list; the scan closes and drains its ring (D8) | |
| `Dealloc` | `heap_remove_page_on_vacuum`: only a page with no row any snapshot sees | write latch on the page |

### OidBatch

| Model | Code (develop today -> design) | One step because |
|---|---|---|
| `nextk`, `pend` | the index scan's position and its OID buffer: `scan_next_index_scan` -> `btree_range_scan` filling `INDX_SCAN_ID.oid_list` (`scan_manager.c`; `index_scan_oid_buffer_pages`) | single owner (the scanning thread) |
| `win` | design: the heap pages of the pending OIDs, grouped (page -> slots) | single owner |
| `gone`, `got` | OIDs processed, rows returned | single owner |
| `AccumulateRead`/`AccumulateNote` | design: the next OID from the index joins the batch and its heap page's read is issued at once (no wait: D7a); today the OID buffer is filled by one `btree_range_scan` call | the index leaf is read under its latch; frame claim under the BCB mutex |
| `Wanted`, `Chunk` | design: every window page and all its pending OIDs (order free), or only the page and OID of the smallest pending key (key order: `multi_range_opt`, ORDER BY skipped through the index) | — |
| `Fix`/`Process` | today `scan_next_index_lookup_heap` per OID (`heap_get_visible_version` by OID); design: one fix per page and the page's pending OIDs as one page batch chunk | under the page's read latch; the unfix ends the step |
| `ReadNow`/`FixNeed`/`ReadFailed`, `WaitFrame`, `SleepOnPage`, `Reap*`, `EarlyEnd`, `End`, `Finish` | as in ReadStream | |
| `Vacuum` | `vacuum_heap_page` removing a record no snapshot sees while its index entry is still there; the lookup finds no visible version and skips | write latch on the page |

### BitmapScan

Implemented 2026-11-10 behind `bitmap_heap_scan` (server parameter, default no). Differences from the decisions, to settle: the choice is made where the scan is promoted to a parallel index scan, not at plan generation (D26); not used for a filtered index, a function index, a prefix index, a covering scan, a count-only scan, a GROUP BY skip scan, a multi-range or index skip scan.

| Model | Code (worktree `~/dev/cubrid-worktree/CBRD-28005`, branch `CBRD-28005-aio`, uncommitted; `src/query/parallel/px_scan/`) | One step because |
|---|---|---|
| `ListedSectors`, `secTodo` | `px_scan_input_handler_index.cpp` `bitmap_init_on_main`: `logtb_get_mvcc_snapshot`, then `file_get_all_data_sectors` into `m_bm_sectors` (sorted by volume and sector); the hand-out is `bitmap_take_sector` (`m_bm_next_sector.fetch_add`) | the list is written by the leader before any worker starts; the hand-out is one atomic fetch-add |
| `leafTodo`, `TakeLeaf`, `EndLeaf` | the parallel index scan's leaf hand-out, unchanged: `leaf_page_dispatcher::get_next_page_with_fix`, and the shared overflow chains (`overflow_chain_pool`); a leaf of the model stands for a leaf page or an overflow page | the hand-out is under the dispatcher's mutex |
| `pend`, `Mark`, `bm`, `pagebm` | `leaf_slot_walker::process_oid` while `m_bm_index_phase`: `input_handler_index::bitmap_mark` sets the row bit (`m_bm_rows[...].fetch_or`) or, when the bitmap holds pages only or the slot is beyond the width, the page bit (`m_bm_whole[s].fetch_or`), then the page's bit in `m_bm_touched`; an OID whose sector or page is not in `m_bm_sectors` is dropped | each bit is one `fetch_or`; the second word (`m_bm_touched`) is read by nobody before the barrier, so the two writes of a mark are one step for every reader |
| `lossy`, `Wide` | `bitmap_init_on_main`: `m_bm_row_bits` = min(slot bound, `index_scan_oid_bitmap_size` in bits / pages), 0 (pages only) below 64 (D37); `Wide`: `oid->slotid >= m_bm_row_bits` in `bitmap_mark` | leader only, before any worker starts |
| `IdxFinish`, `idone` | `task::bitmap_heap_phase`: `slot_iterator_index::end_bitmap_index_phase` (the last leaf is let go), then `bitmap_leave_index_phase` (`m_bm_index_pending` under `m_bm_mutex`); a worker that stops inside its index phase leaves it after the loop of `task::loop` | the count changes under the mutex |
| `TakeSector`, `ExamCount` | `bitmap_wait_index_phase` (waits for `m_bm_index_pending == 0` under `m_bm_mutex`), then `bitmap_take_sector`; the taker reads `bitmap_touched`, `bitmap_whole`, the row bits (`bitmap_next_row`) of its sector; a sector with no touched page is passed without a page read | the mutex of the barrier orders every mark before every read; after it the bitmap is read-only |
| `FixPage`, `held`, `ReleasePage` | `slot_iterator_index::set_bitmap_page` -> `leaf_slot_walker::fix_bitmap_page`: every marked page, by row bits or as a whole, is fixed into the scan cache's watcher with `OLD_PAGE_MAYBE_DEALLOCATED` before its rows are read (a row lookup fixes its page with `OLD_PAGE` in `heap_prepare_object_page`: on a deallocated page that is an assertion in a debug build and `ER_HEAP_UNKNOWN_OBJECT` in a release build); `release_bitmap_page` at the page's last row in `next_bitmap_row`, on an error, and in `slot_iterator_index::finalize` | the watcher belongs to the worker's own scan cache |
| `SkipFreedPage` | `fix_bitmap_page` gets no page (`ER_PB_BAD_PAGEID`, cleared): `m_bm_page_on` stays false and the page's marks are passed without a lookup | the fix reads the page type under the page latch |
| `FreePage`, `freed` | environment: `vacuum_heap_page` -> `heap_remove_page_on_vacuum` -> `file_dealloc` -> `pgbuf_dealloc_page` (the page type becomes unknown), only for a page the one vacuum it was waiting for emptied (page vacuum status `HEAP_PAGE_VACUUM_ONCE`: one MVCC operation on the page since it was last vacuumed) | the page's write latch: never while a scan holds the page |
| `Lookup` | `slot_iterator_index::next_bitmap_row`: on the page fixed before, a row bit -> `leaf_slot_walker::process_bitmap_row` -> `process_oid` (the lookup takes the held page from the scan cache and hands it back: `cache_last_fix_page` is set around it, so the page is not fixed once more per row) (`heap_get_visible_version`, then `finish_heap_row`: data filter, the rest of the columns); a page marked as a whole -> `next_whole_page_row` (`heap_next_1page` for every home record the snapshot sees, the range condition `range_pred` and the key filter `key_pred` evaluated on the heap row as `locator_mvcc_reevaluate_filters` does, then `finish_heap_row`); a page with its whole bit set is never read through its row bits | the worker reads its own sector's pages; a row is read under the page latch |
| `EndSector` | the end of the page loop of one sector in `task::bitmap_heap_phase` | worker-local |
| `Abort` | an error or interrupt sets the query's interrupt code (`m_interrupt`): `bitmap_wait_index_phase` returns false, the loops of `bitmap_heap_phase` and `task::loop` break, `task::finalize` runs; the bitmap is freed by `~input_handler_index` on the leader after the workers ended | the interrupt code is atomic; each worker stops at its next check |
| `Vacuum`, `gone` | environment: vacuum removes a version no snapshot sees while its index entry may still be read (`vacuum_heap_record`; `heap_get_visible_version` then returns `S_DOESNT_EXIST` for the empty slot, as it does for a version newer than the snapshot, and `S_SNAPSHOT_NOT_SATISFIED` for a deleted version still there) | page latch |

### BatchJoin

The implemented join (D38): engine worktree `~/dev/cubrid-worktree/CBRD-28005`, branch `CBRD-28005-aio`, on top of `4c4e04f7b`. One thread runs a join (the statement's thread, or a parallel worker with its own XASL clone and its own batch), so the steps are the points where an error, an interrupt, the consumer's stop or memoize's own decision can fall between them.

| Model | Code | One step because |
|---|---|---|
| `kind`, `AddOuter` | `qexec_execute_scan` -> `qexec_nl_batch_add` (`query_executor.c`): the outer's value list is copied into `QEXEC_NL_BATCH.vals`; `scan_index_nl_batch_collect` (`scan_manager.c`) reads the inner index once (`call_get_next_index_oidset`) and copies the OIDs into `QEXEC_NL_BATCH.oids`; the scan function returns S_END so the outer goes on to its next row | single owner (the XASL clone's thread) |
| `AddOuter("read")`: `NumEntries <= BufCap` | `scan_index_nl_batch_collect`: complete only when the search ended (`BTREE_END_OF_SCAN`), i.e. the key's OIDs fit one OID buffer | the leaf is read under its latch |
| `AddOuter("defer")` | `qexec_nl_batch_add`: `oid_cnt = -1` for a key memoize holds (`memoize::storage::has_key`), a null join value, a search that did not end (which also closes the batch), a scan that cannot be read ahead while rows are held | single owner |
| `AddOuter`: `Used < BufCap`, `ArrayBound` | `qexec_nl_batch_add` returns S_END when `n_oids >= oid_target` (at most one OID buffer); the array holds two buffers (`oid_cap`), and `scan_index_nl_batch_collect` asserts the room | single owner |
| `MaxOuter` | `qexec_nl_batch_add`: `bytes >= oid_target * sizeof (OID)` (D28) | single owner |
| `PassRow` | `qexec_nl_batch_add` returns S_DOESNT_EXIST with nothing held (the scan cannot be read ahead, or the back-off after a batch with nothing to hint): `qexec_execute_scan` runs the row path and remembers it in `passing` | single owner |
| `CloseBatch` | `qexec_execute_scan`: `scan_index_nl_batch_read_ahead` -> `pgbuf_read_ahead` (the hint), `replaying = true`; the outer scan's end reaches it as `flush` from `qexec_execute_scan_outer` (a scan below the first) or `qexec_next_root_row` (the first scan: one more pass of the row loop of `qexec_intprt_fnc`) | single owner |
| `OpenRow`: `valrow` | `qexec_nl_batch_open_row`: the held values are copied back into the outer's value list | single owner |
| `OpenRow`: `slice` | `qexec_nl_batch_open_row`: `qexec_reset_sa_inner_scan_block`, then `INDX_SCAN_ID.nl_slice`, `nl_slice_cnt` (-1 for a deferred row) | single owner |
| `RunRow`: memoize, the stored OIDs, the row's own search | `qexec_execute_scan_row` (the row path, unchanged): `qexec_execute_nljoin_with_memoize` -> `memoize_get`; else `scan_next_index_scan` takes the slice (`scan_index_take_nl_slice`) or searches the index; `memoize_put` as today | single owner |
| `EmitOne` | the row path returns S_SUCCESS: the join row goes to the next scan or to the block's output | single owner |
| `RowDone`: `slice` | `qexec_execute_scan`: the row path returned S_END; `nl_slice_cnt = -1` (OIDs memoize left untaken are not the next row's) | single owner |
| `EndBatch` | `qexec_execute_scan`: `qexec_nl_batch_drop_rows` | single owner |
| `MemoDrop` | memoize disables itself on a miss when its hit ratio is low or its budget is used (`memoize.cpp`), and `memoize_get`/`memoize_put` free the storage (`clear_memoize_storage`): inside a memoize call of the row path, or between two outer rows | happens inside a memoize call of the same thread |
| `Stop` | S_ERROR from any call, or the consumer stops asking (LIMIT, a single-row subquery) | — |
| `Restart` | the plan clone runs again (a correlated subquery per outer row, the next execution from the plan cache): `qexec_execute_mainblock_internal` frees the batch of every scan of the block before it opens the scans (`qexec_nl_batch_free`); `qexec_clear_xasl` frees it at the end of an execution; `scan_open_index_scan` starts with no slice | single owner |
| not modeled | which scans batch (`qexec_nl_batch_arm`, `scan_index_nl_batch_ok`), more than one batching step in a chain (each has its own batch; a step's batch is joined when its outer's rows end), a partitioned inner (the block iterator runs the whole outer scan once per partition, each pass with its own batches), the batch target's growth and the back-off (both only choose when `CloseBatch` and `PassRow` happen), the hint itself | checked by result parity (the join smoke of 38 statements on both builds, CTP sql and medium with the option on) |
### BatchJoinDesign

The design the implemented join (`BatchJoin`, above) was cut from; rows that span batches, semi and anti joins and the free order mode have no implementation. The join is run by one thread (the join level's own executor thread), so the steps are the points where an error, an interrupt or memoize's own decision can fall between them.

| Model | Code (develop today -> design) | One step because |
|---|---|---|
| `next`, `AddOuter` | today `qexec_execute_scan` (`query_executor.c`) takes one outer row and opens the inner scan for it; design: outer rows are stored until the batch closes (D19) | single owner |
| the memoize check in `AddOuter`, `hitm` | `qexec_execute_nljoin_with_memoize` -> `memoize_get` (`query_executor.c`, `memoize.cpp`); design: checked for every outer row before its index walk (D23), a hit keeps a copy of (or a pin on) the stored result until its rows are emitted | single owner |
| `lo`, `hi`, `resume` | the inner index scan filling the OID buffer: `scan_next_index_scan` -> `btree_range_scan` into `INDX_SCAN_ID.oid_list`; design: the buffer is shared by the batch's outer rows, and a row whose entries do not fit resumes its range scan in the next batch (as today's index scan resumes when the OID buffer is full) | single owner; the leaf is read under its latch |
| `PartStart` | a partitioned inner: the entries of one outer row come from the partitions' local indexes one after another (`qexec_execute_scan`'s partition loop); the resume point is a position inside one partition | single owner |
| `CloseBatch`: heap read | `scan_next_index_lookup_heap` per OID today; design: the buffer's heap pages are hinted and read in page order | under each page's read latch |
| `CloseBatch`: `acc`, `accRow` | design: whether the continuing outer row already matched (left outer, semi, anti need it), and its matches when the result is memoized | single owner |
| `CloseBatch`: store | `memoize_put` (`memoize.cpp`) for a finished outer row | single owner |
| `EmitOne` | the join row handed to the parent; order-kept mode emits in outer order, then index order (D22) | single owner |
| `MemoDrop` | memoize disables itself on a miss when its hit ratio is low or its budget is used (`memoize.cpp` `can_insert`), and the caller frees the storage (`clear_memoize_storage`, `query_executor.c`) | happens inside a memoize call of the same thread |
| `Abort` | error or interrupt at any point | — |

## Properties

| Name | Kind | Statement | Claim |
|---|---|---|---|
| `TypeOK` | invariant | variable types | — |
| `NoFrameReuseInIO` | invariant | `~uaf` | C1 |
| `AllComplete` | liveness (WF on threads, device, daemon) | eventually always: every thread done and no frame under I/O | C2 |
| `IndInv` | inductive invariant | ring partition, I/O-owner agreement, SQEs staged only inside a read-ahead call (D7), lock holder shape, C1 | C1 |

OidBatch:

| Name | Kind | Statement | Claim |
|---|---|---|---|
| `AtMostOnce` | invariant | no OID is processed twice | C6 |
| `Complete` | invariant | a scan that ran to the end returned every OID of `Vis` | C6 |
| `KeyOrder` | invariant | in key order no OID is processed after a larger one | C7 |
| `NoFixAfterEnd` | invariant | a scan in `drain`/`done` holds no fix | C4 |
| `AllComplete` | liveness (WF on scans and device) | eventually always: every scan done and no frame under I/O | C2, C4 |
| `IndInv` | inductive invariant | the invariants above plus ring, frame-pool, window = pages of the pending OIDs, key, coverage, order, fix, need, sleep and end shapes | C4, C6, C7 |

ReadStream:

| Name | Kind | Statement | Claim |
|---|---|---|---|
| `NoFrameReuse` | invariant | no frame under I/O or fixed is taken as a victim | C1 |
| `AtMostOnce` | invariant | no scan processes a page twice | C3 |
| `Complete` | invariant | a scan that ran to the end of its list returned every page of `Vis` | C3 |
| `NoFixAfterEnd` | invariant | a scan in `drain`/`done` holds no fix | C4 |
| `NoForeignDemotion` | invariant | a scan demotes only pages it read; no page that was in the buffer is at the LRU bottom | C5 |
| `AllComplete` | liveness (WF on scans and device) | eventually always: every scan done and no frame under I/O | C2, C4 |
| `IndInv` | inductive invariant | the five invariants above plus ring, reader, bottom, frame-pool, list-partition, coverage, fix, sleep and end shapes | C1, C3, C4, C5 |
| `BitmapScan.NoExtraRow` | invariant | no row is returned twice; no row the snapshot does not see or the data filter rejects is returned | C6 |
| `BitmapScan.AllRowsReturned` | invariant | a scan that ran to its end returned every visible row the filter accepts | C6 |
| `BitmapScan.NoPageHeld` | invariant | a scan that ended, finished or stopped by an error or interrupt, holds no heap page | C4 (for the whole-range batch, also at the normal end) |
| `BitmapScan.NoFreedPageHeld` | invariant | no worker holds, so none reads, a page vacuum deallocated | C6 (a row vacuum removed is skipped; its page may be gone too) |
| `BitmapScan.Ends` | liveness (WF on index and heap workers) | the scan finishes or is aborted | C6 (the barrier does not block the heap phase forever) |
| `BitmapScan.IndInv` | inductive invariant | the two invariants plus mark shape (a row bit only for an index entry of a listed sector inside the width, none in pages-only mode), leaf shape, the barrier, final bitmap, visible-rows-marked (row bit or page bit), one-worker-per-sector, row fate, vacuum-removes-invisible, abort shape | C6 |
| `BatchJoin.NoExtra` | invariant | no join row the row-at-a-time join does not return, and none twice (a NULL-extended row at most once, only for an outer row with no match) | C8 |
| `BatchJoin.AllReturned` | invariant | a join that ran to its end returned every row of the row-at-a-time join | C8 |
| `BatchJoin.InOrder` | invariant | a join row leaves only after every row before it (outer order, then index order) | C8 |
| `BatchJoin.ArrayBound` | invariant | the stored OIDs never exceed the batch's array of two OID buffers | C8 (no write past the array) |
| `BatchJoin.Ends` | liveness (WF on the join's steps), own cfg | the execution finishes or is stopped | C8 |
| `BatchJoin.IndInv` | inductive invariant | the four invariants plus the batch's shape (held rows are the last rows that arrived, in one run), what each outer row has returned (a finished row everything, a held row nothing, the open row what is not waiting), the open row's order, memoized results equal the matches | C8 |
| `BatchJoinDesign.NoExtra` | invariant | no join row the row-at-a-time join does not return, and none twice (a NULL-extended row at most once, only for an outer row with no match) | C8 |
| `BatchJoinDesign.AllReturned` | invariant | a join that ran to its end returned every row of the row-at-a-time join | C8 |
| `BatchJoinDesign.InOrder` | invariant | order-kept mode: a join row leaves only after every row before it (outer order, then index order) | C8, C7 |
| `BatchJoinDesign.Ends` | liveness (WF on the join's steps) | the join finishes or is aborted | C8 |
| `BatchJoinDesign.IndInv` | inductive invariant | the three invariants plus batch shape, the carried matches, memoized results equal the matches, the rows each outer row has given so far, emission order | C8 |

## Fault model and environment assumptions

| Fault | Modeled as |
|---|---|
| error return | `DeviceComplete` posts `err` (up to `MaxErrors`); the frame goes back to `absent` and readers issue again |
| interrupt / query cancel | `Interrupt`, once per thread, in `lock`, `waitX`, `fix`, `sleepPage` |
| lock timeout, deadlock victim | covered by `Interrupt` (the thread leaves its wait) |
| conditional latch failure | n/a at this level (the abstract resource X is unconditional) |
| OOM | n/a: rings and SQEs are preallocated at server start (D4) |
| crash / `kill -9` | n/a: reads only, nothing durable |
| spurious wakeup | `WakePage` rechecks `bcb # "io"`; `WakeX` takes X atomically |
| concurrent DML | n/a here (page content not modeled); the read stream model adds it |
| vacuum | n/a here; the read stream model adds page deallocation |
| checkpoint, page flush, page replacement | `Victimize` of a valid frame (up to `MaxVictims`) |
| HA log apply | n/a (reads of the local buffer) |
| nested statement | n/a (no snapshot read) |
| device fairness | `WF_vars(DeviceComplete)`: a submitted read completes eventually (assumption confirmed by the user, Q9) |
| thread fairness | `WF_vars(ThreadStep(t))`: a runnable thread runs (assumption confirmed by the user, Q9) |
| fixer reservation (ReadStream) | a frame `pgbuf_fix` is reading into stays reserved for that fixer until it is fixed (`need`, `Reserved`), as today's read path adds its fix before it lets the BCB go (`page_buffer.c` `pgbuf_fix`: `add_fcnt` right after `pgbuf_claim_bcb_for_fix`). With it no fairness beyond WF on the scans and the device is assumed. |
| vacuum (ReadStream) | `Dealloc` of a page outside `Vis`, up to `MaxDealloc`, never while the page is fixed |
| page replacement (ReadStream) | on demand, by the scans' own frame claims (`TakeFrame`), LRU bottom first |
| daemon fairness | `WF_vars(DaemonReap)` (only enabled under `Reaper = "daemon"`) |
| error, interrupt (BitmapScan) | `Abort` at any point of either phase, up to `MaxErrors`; every worker stops |
| vacuum (BitmapScan) | `Vacuum` removes a row no snapshot sees (r4, r8) at any time; its index entry may still be read. `FreePage` deallocates a listed page whose rows are all removed (p3, the page of r8), at any time no worker holds it; a worker that comes to it passes it (`SkipFreedPage`) |
| concurrent DML (BitmapScan) | r5: a row inserted after the sector list was taken, on a page outside the list, with an index entry the scan reads; invisible because the snapshot is older than the list (D30). Rows moved by an update keep their OID. Classes without MVCC do not use the mode |
| worker fairness (BitmapScan) | `WF_vars(IdxStep(w))`, `WF_vars(HeapStep(h))` |
| lock timeout, conditional latch, OOM (BitmapScan) | each is an error return: `Abort` |
| crash, checkpoint, page replacement, HA apply (BitmapScan, BatchJoin, BatchJoinDesign) | not applicable: the bitmap and the batch are private memory of one statement; pages are read through `pgbuf_fix` as today |
| nested statement (BatchJoin, BatchJoinDesign) | not modeled, and C8 does not hold across it: the pre-read of a held row (`scan_index_nl_batch_collect`) reads the inner index under the statement snapshot, which a nested statement (SP SQL from the client, `network_sr.c` `logtb_invalidate_snapshot_data`) rebuilds under READ COMMITTED; the row-at-a-time join searches the next outer row after the rebuild, the batched join read the held rows before it. The same exposure exists today inside one OID buffer of one outer row. `pass` is fixed for the plan, so the models cannot see it. Such statements keep batching and C8 is stated without them (D39, the user 2026-11-11) |
| nested statement (BitmapScan) | the workers read the statement's snapshot through `scan_cache.mvcc_snapshot`, a pointer to `tdes->mvccinfo.snapshot` (`logtb_get_mvcc_snapshot`). Under READ COMMITTED a request of the same transaction that arrives while the scan runs (SQL of a stored procedure called per row) invalidates it (`net_server_request` -> `logtb_invalidate_snapshot_data`) and the next `logtb_get_mvcc_snapshot` rebuilds it in place. A row marked under the old snapshot may then be invisible at its lookup, removed by vacuum, its page deallocated: modeled as `Mark` of a row outside `Vis`, `Vacuum`, `FreePage`, `SkipFreedPage`. Not modeled: `Vis` itself changing (a row only the rebuilt snapshot sees comes out of a page read as a whole and of no other page); the index scan without the bitmap mixes the two snapshots the same way. With one snapshot for the whole scan the leaf's own check leaves such rows unmarked, so these steps are not reached. No run with a nested statement was recorded |
| error, interrupt, early stop (BatchJoin) | `Stop` in the collect and replay phases, up to `MaxErrors`; rows may still be held |
| re-execution of the cached plan (BatchJoin) | `Restart`, up to `MaxExec` executions: the batch is XASL state, so a second execution must start with nothing held (mutant `keep-batch`) |
| memoize giving up (BatchJoin) | `MemoDrop` at any point of the collect and replay phases: the stored results are freed, a row deferred for its key is answered by its own index search |
| vacuum, concurrent DML (BatchJoin) | which inner rows the snapshot sees and the filter accepts is fixed for the plan (`pass`, any subset); the pre-read and the row path read under the same statement snapshot, and a pre-read OID whose row vacuum removed is a lookup that finds nothing, as for an OID buffer today |
| OOM (BatchJoin) | an allocation failure in `qexec_nl_batch_add` is an error return before the row is handed on: `Stop` |
| fairness (BatchJoin) | `WF_vars(Step)`: the join's own thread runs |
| error, interrupt (BatchJoinDesign) | `Abort` in the collect and emit phases, up to `MaxErrors` |
| memoize giving up (BatchJoinDesign) | `MemoDrop` at any point of the collect phase: the stored results are freed |
| vacuum, concurrent DML (BatchJoinDesign) | which inner rows the snapshot sees and the filter accepts is fixed at the start (`pass`, any subset); a row vacuum removed is a row outside `pass` |
| fairness (BatchJoinDesign) | `WF_vars(Step)`: the join's own thread runs |

## Mutants

| cfg | Change | Expected | Kills |
|---|---|---|---|
| `mutant-owner-only` | only the issuer reaps its ring (option iii) | liveness: issuer asleep on X, X's holder asleep on the issuer's page, the CQE unreaped; only a query interrupt ends it | C2 |
| `mutant-block-with-staged` | a thread sleeps with staged SQEs (any_waiter) | liveness: the page's read is never submitted | C2 |
| `mutant-daemon-block-with-staged` | the same under a daemon | liveness (as in the row above, with the deadlock check off: the sleeping thread's state has no step, and TLC reported it as a deadlock in one run under load, 2026-11-11, and as the liveness failure in the others) | C2 |
| `mutant-drop-on-interrupt` | an interrupted thread leaves without submitting/draining | deadlock | C2 |
| `mutant-no-drain` | a thread returns to the pool with I/O in its ring (any_waiter) | deadlock: frame stays under I/O | C2 |
| `mutant-victim-in-io` | page replacement takes a frame under I/O | violation `NoFrameReuseInIO` | C1 |

OidBatch:

| cfg | Change | Expected | Kills |
|---|---|---|---|
| `OidBatch.mutant-double-process` | processed OIDs stay pending | violation `AtMostOnce` | C6 |
| `OidBatch.mutant-skip-valid-page` | an OID whose page is already valid is not given a window page ("nothing to read") | liveness: the OID stays pending for ever, the scan never ends | C6 |
| `OidBatch.mutant-drop-on-victim` | a window page that left the buffer is dropped with its pending OIDs | violation `Complete` | C6 |
| `OidBatch.mutant-completion-order-in-key-mode` | key order asked, pages processed as they complete | violation `KeyOrder` | C7 |
| `OidBatch.mutant-leak-fix` | an early end keeps the fixed page | violation `NoFixAfterEnd` | C4 |
| `OidBatch.mutant-no-drain` | the scan returns to the pool with reads in its ring | deadlock | C4, C2 |

ReadStream:

| cfg | Change | Expected | Kills |
|---|---|---|---|
| `ReadStream.mutant-double-consume` | a processed page stays in the window | violation `AtMostOnce` | C3 |
| `ReadStream.mutant-drop-on-victim` | a window page that left the buffer is dropped instead of read again | violation `Complete` | C3 |
| `ReadStream.mutant-skip-other-io` | a page another thread is reading is left out of the window | violation `Complete` | C3 |
| `ReadStream.mutant-leak-fix` | an early end keeps the fixed page | violation `NoFixAfterEnd` | C4 |
| `ReadStream.mutant-no-drain` | the scan returns to the pool with reads in its ring | deadlock (a frame stays under I/O) | C4, C2 |
| `ReadStream.mutant-frame-wait-with-io` | a scan sleeps for a victim frame with completions in its own ring | liveness: its own frames are the only victims and nobody reaps them | C2 (D7b) |
| `ReadStream.mutant-victim-in-io` | page replacement takes a frame under I/O | violation `NoFrameReuse` | C1 |
| `ReadStream.mutant-victim-fixed` | page replacement takes a fixed frame | violation `NoFrameReuse` | C1 |
| `ReadStream.mutant-demote-any` | the scan demotes every page it processed | violation `NoForeignDemotion` | C5 |
| `BitmapScan.mutant-no-barrier` | a heap worker takes a sector while index workers still mark (1 index worker, 1 heap worker: the bound of 2 and 2 did not end in 12 minutes) | violation `AllRowsReturned` (a row marked after its sector was handed out) | C6 (D33) |
| `BitmapScan.mutant-nonatomic-or` | a mark is a load and a store of the bitmap word instead of one atomic OR | violation `AllRowsReturned` (r2's bit lost under another worker's store of the same word) | C6 (D36) |
| `BitmapScan.mutant-sector-twice` | a sector stays in the hand-out list | violation `NoExtraRow` | C6 |
| `BitmapScan.mutant-no-heap-visibility` | the heap phase trusts the mark and skips the visibility check | violation `NoExtraRow` (r4: deleted before the snapshot, index entry still there) | C6 (D29) |
| `BitmapScan.mutant-no-recheck` | the heap phase returns every visible row of a page marked as a whole without checking the index condition | violation `NoExtraRow` (r6: on the page, outside the key range) | C6 (D36) |
| `BitmapScan.mutant-both-paths` | on a page marked as a whole the heap phase also follows the page's row bits | violation `NoExtraRow` (r3 returned twice) | C6 (D36) |
| `BitmapScan.mutant-no-release` | the worker does not let go of a marked page it fixed (the first implementation: optdebug assertion `PGBUF_IS_CLEAN_WATCHER` in `heap_scancache_quick_end`, 2026-11-10) | violation `NoPageHeld` | C4 |
| `BitmapScan.mutant-late-sector-list` | the sector list is taken before the snapshot | violation `AllRowsReturned` (r5 is visible but on a page outside the list); the defect CBRD-27967 fixed for the parallel heap scan | C6 (D30) |
| `BitmapScan.mutant-no-freed-skip` | a worker that finds a marked page deallocated has no way past it | deadlock (the sector never ends) | C6 |
| `BitmapScan.mutant-fix-freed` | a marked page is fixed as one that must exist although vacuum deallocated it (the row lookup's own fix: the first implementation of the row-bit path, optdebug assertion in `pgbuf_fix` under `heap_prepare_object_page`, 2026-11-11) | violation `NoFreedPageHeld` | C6 |
| `BatchJoin.mutant-no-restore` | the held row's values are not put back: the row path runs with the values of the last row collected | violation `NoExtra` | C8 |
| `BatchJoin.mutant-stale-slice` | OIDs a row left untaken (memoize answered) stay with the scan: neither the row's end nor the next deferred row clears them (two code sites: `qexec_execute_scan` after S_END, `qexec_nl_batch_open_row`; the claim holds by either) | violation `NoExtra` | C8 |
| `BatchJoin.mutant-partial-as-complete` | a pre-read that filled the OID buffer without ending the search is taken for the row's whole answer | violation `AllReturned` | C8 |
| `BatchJoin.mutant-no-flush` | the rows held when the outer scan ends are forgotten | violation `AllReturned` | C8 |
| `BatchJoin.mutant-no-close-at-half` | rows are taken while the stored OIDs already fill one buffer | violation `ArrayBound` | C8 |
| `BatchJoin.mutant-replay-any-order` | the held rows are joined in any order | violation `InOrder` | C8 |
| `BatchJoin.mutant-keep-batch` | a second execution of the plan starts with the rows the first one held when it stopped | violation `NoExtra` | C8 (cubrid-tla P70) |
| `BatchJoinDesign.mutant-no-carry` | a continuing outer row forgets that it matched in an earlier batch | violation `NoExtra` (a NULL-extended row after matches; a semi-join row twice; an anti-join row with a match) | C8 |
| `BatchJoinDesign.mutant-no-last` | the no-match decision is taken per batch, not at the row's last entry | violation `NoExtra` | C8 |
| `BatchJoinDesign.mutant-resume-next-outer` | a row whose entries did not fit is not resumed | violation `AllReturned` | C8 |
| `BatchJoinDesign.mutant-resume-partition-start` | the row resumes at the start of the partition it stopped in | violation `NoExtra` (an entry twice) | C8 (D21) |
| `BatchJoinDesign.mutant-free-emit` | order-kept mode emits in heap-read order | violation `InOrder` | C8, C7 (D22) |
| `BatchJoinDesign.mutant-memo-partial` | a row that spanned batches memoizes only its last batch's matches | violation `AllReturned` (a later row with the same key) | C8 (D23) |
| `BatchJoinDesign.mutant-hit-by-reference` | a memoize hit reads the stored result when the batch closes, after memoize may have freed it | violation `AllReturned` | C8 (D23) |

## Witnesses

| cfg | Reached state |
|---|---|
| `witness-waiter-reaps` | a thread reaped another thread's ring |
| `witness-read-ahead-hit` | a thread fixed a page whose frame a read ahead filled (`ra`) |
| `witness-error-retry` | a page whose read failed was issued again |

OidBatch:

| cfg | Reached state |
|---|---|
| `OidBatch.witness-page-revisited` | a scan fixes a page it already processed for an earlier OID |
| `OidBatch.witness-vacuumed-skipped` | an OID was processed without returning a row |
| `OidBatch.witness-accumulated-in-flight` | a scan accumulated a second OID while its read was in flight (D18) |
| `OidBatch.witness-held-back-by-order` | key order: another window page is ready while the page of the smallest key is not |
| `OidBatch.witness-full-run` | a scan ran to the end of its key range |

ReadStream:

| cfg | Reached state |
|---|---|
| `ReadStream.witness-completion-order` | a scan holds a page fixed while another page of its window is still under I/O |
| `ReadStream.witness-recycled-bottom` | a frame claim took a frame from the LRU bottom |
| `ReadStream.witness-dealloc-skipped` | a scan processed a deallocated page without returning rows |
| `ReadStream.witness-slept-on-frame` | a scan slept for a victim frame |
| `ReadStream.witness-full-run` | a scan ran to the end of its list |
| `BitmapScan.witness-mixed-page` | a page marked as a whole (a slot beyond the width) that also carries a row bit |
| `BitmapScan.witness-rechecked` | the index condition rejected a row of a page marked as a whole |
| `BitmapScan.witness-page-held` | a worker holds a marked page while it reads its rows |
| `BitmapScan.witness-freed-page` | a scan ran to its end past a marked page vacuum had deallocated |
| `BitmapScan.witness-pages-only-run` | a scan whose bitmap holds pages only ran to its end |
| `BitmapScan.witness-oid-dropped` | an OID outside the sector list was dropped |
| `BitmapScan.witness-row-skipped` | the heap phase skipped a marked row (removed by vacuum or invisible) |
| `BitmapScan.witness-full-run` | the scan ran to its end |
| `BatchJoin.witness-memo-hit` | memoize answered an outer row |
| `BatchJoin.witness-slice-taken` | the scan took a row's stored OIDs |
| `BatchJoin.witness-defer-scan` | a deferred row was answered by its own index search (`BufCap = 2`: the three k1 entries do not fit) |
| `BatchJoin.witness-passed` | an outer row was joined at once, nothing held |
| `BatchJoin.witness-untaken-slice` | memoize answered a read row: its stored OIDs were left |
| `BatchJoin.witness-drop-held` | memoize gave up, and a row deferred was then answered by its own search |
| `BatchJoin.witness-null-row` | a left outer join returned a NULL-extended row |
| `BatchJoin.witness-flush` | the outer scan ended with rows held and they were joined |
| `BatchJoin.witness-full-run` | the join ran to its end |
| `BatchJoin.witness-stopped-held` | an execution stopped with rows held |
| `BatchJoin.witness-second-done` | the second execution of the plan ran to its end |
| `BatchJoinDesign.witness-spanned` | an outer row's entries did not fit the batch |
| `BatchJoinDesign.witness-three-batches` | an outer row spans three batches (`BufCap = 1`) |
| `BatchJoinDesign.witness-carried-match` | a continuing row carries a match from an earlier batch |
| `BatchJoinDesign.witness-memo-hit` | an outer row was answered by memoize |
| `BatchJoinDesign.witness-drop-with-hit` | memoize gave up while a hit row was waiting in the batch |
| `BatchJoinDesign.witness-null-row` | a left outer join emitted a NULL-extended row |
| `BatchJoinDesign.witness-full-run` | the join ran to its end |

## Dead expressions (pass cfg)

| Line | Why never evaluated |
|---|---|
| AsyncRead.tla:187 | `DeferSubmit` body: only `mutant-block-with-staged` / `mutant-daemon-block-with-staged` leave a read-ahead call with SQEs staged (D7) |
| AsyncRead.tla:188 | same |
| AsyncRead.tla:300 | `Loop` body: dead only in `scale-3t` (`MaxRounds = 0`: three threads, one round each); fires in `AsyncRead.cfg` and `scale-rounds` |
| AsyncRead.tla:301 | same |
| AsyncRead.tla:302 | same |
| AsyncRead.tla:308 | `Reuse` body: dead only in `scale-3t` (`MaxRounds = 0`); fires in `AsyncRead.cfg` and `scale-rounds` |
| AsyncRead.tla:309 | same |
| AsyncRead.tla:310 | same |
| AsyncRead.tla:332 | `ReapOne` body (CQ removal), counted by TLC at its call sites; the live call sites `ReapOwn`/`ReapForWaiter`/`DaemonReap` evaluate it |
| AsyncRead.tla:333 | `ReapOne` body (BCB update), same |
| AsyncRead.tla:334 | `ReapOne` body (owner cleared), same |
| AsyncRead.tla:349 | `ReapForWaiter` effect: dead only in the `option-daemon*` cfgs (`Reaper = "daemon"`); fires in `AsyncRead.cfg` (`witness-waiter-reaps`) |
| AsyncRead.tla:350 | same |
| AsyncRead.tla:372 | `DaemonReap` effect: dead under `Reaper = "any_waiter"`; fires in `option-daemon*` |
| AsyncRead.tla:385 | `Victimize` branch of `mutant-victim-in-io` only |
| AsyncRead.tla:386 | the `uaf` ghost flagging C1's violation; dead because C1 holds |
| AsyncRead.tla:387 | same mutant-only branch |
| AsyncRead.tla:388 | same mutant-only branch |
| ReadStream.tla:208 | `RefillNote` branch of `mutant-skip-other-io` only |
| ReadStream.tla:209 | same |
| ReadStream.tla:252 | `DropAbsent` body: `mutant-drop-on-victim` only |
| ReadStream.tla:253 | same |
| ReadStream.tla:254 | same |
| OidBatch.tla:258 | `DropAbsent` body: `mutant-drop-on-victim` only |
| OidBatch.tla:259 | same |
| OidBatch.tla:260 | same |
| OidBatch.tla:261 | same |
| BitmapScan.tla:217 | `MarkLoad` body: the load-and-store form of a mark exists only under `mutant-nonatomic-or`; the design marks with one atomic OR (D36) |
| BitmapScan.tla:218 | `MarkLoad` body: the load-and-store form of a mark exists only under `mutant-nonatomic-or`; the design marks with one atomic OR (D36) |
| BitmapScan.tla:219 | `MarkLoad` body: the load-and-store form of a mark exists only under `mutant-nonatomic-or`; the design marks with one atomic OR (D36) |
| BitmapScan.tla:220 | `MarkLoad` body: the load-and-store form of a mark exists only under `mutant-nonatomic-or`; the design marks with one atomic OR (D36) |
| BitmapScan.tla:225 | `MarkStore` body: the load-and-store form of a mark exists only under `mutant-nonatomic-or`; the design marks with one atomic OR (D36) |
| BitmapScan.tla:226 | `MarkStore` body: the load-and-store form of a mark exists only under `mutant-nonatomic-or`; the design marks with one atomic OR (D36) |
| BitmapScan.tla:227 | `MarkStore` body: the load-and-store form of a mark exists only under `mutant-nonatomic-or`; the design marks with one atomic OR (D36) |
| BitmapScan.tla:228 | `MarkStore` body: the load-and-store form of a mark exists only under `mutant-nonatomic-or`; the design marks with one atomic OR (D36) |

## Trace validation (`AsyncRead`, stage 1 code)

Instrumented build: scratch worktree `~/dev/cubrid-worktree/CBRD-28005-instr` = origin/develop `2dd94e32a` + the stage 1 patch + `TLATRACE` lines (never committed), optdebug, install `~/optdebug/CUBRID-CBRD-28005-instr`. Events go to the file named by `CUBRID_TLA_TRACE_FILE` for the pages of `CUBRID_TLA_TRACE_PAGES`; each takes its `seq` from one atomic counter inside the step it records. The traced pages are the whole heap of the scanned table (154 pages), so every page that is read ahead is logged.

| Event | Emitted at | Under |
|---|---|---|
| `ReadAhead` | `pgbuf_read_ahead`: the `PGBUF_AIO_READ` enters the buffer lock chain | hash anchor mutex |
| `InlineComplete` (`err`) | `pgbuf_unlock_page` reached from `pgbuf_read_ahead`'s own call of `pgbuf_aio_read_done` | hash anchor mutex |
| `SubmitNow` | `pgbuf_read_ahead`, before `fileio_aio_submit` (ahead of the syscall, so no completion is logged before it) | owner thread |
| `IssueRead` | `pgbuf_lock_page`: the thread's `buf_lock_table` slot enters the chain | hash anchor mutex |
| `SleepOnPage` (`o` = ring owner) | `pgbuf_lock_page`: the entry found is another thread's read ahead; logged every time the thread looks the page up and finds it so | hash anchor mutex |
| `Reap` (`o` = ring owner, `err`) | `pgbuf_unlock_page`: the entry leaves the chain (after `pgbuf_insert_into_hash_chain` when the read was ok) | hash anchor mutex |
| `FixValid` | `pgbuf_fix_release` at `fast_path`: the page is fixed | the fix itself (the page cannot be replaced) |
| `Victimize` | `pgbuf_delete_from_hash_chain` | BCB mutex + hash anchor mutex |
| `Finish` | after `pgbuf_aio_drain` in `net_server_request`, `recycle_context`, `retire_context`, for a thread that logged an event since its last `Finish` | owner thread |

Not logged, taken by the trace spec only for the thread of the next event and towards that event: `NoReadAhead`, `NoLock`, `PickPage`, `NoFix`, `WakePage`, `ReleaseX`, `Loop`, `Reuse`; a `SleepOnPage` event of a thread already asleep on that page for that ring is a look-up that found nothing new (no step); `DeviceComplete` only for the page the next `Reap` names. `TakeX`/`BlockOnX`/`WakeX` (the abstract lock), `Interrupt`, `Submit`, `DeferSubmit` and `DaemonReap` are never taken by a trace.

| Run (`traces/`) | What it covers | Events |
|---|---|---|
| `ok.log` | one parallel heap scan (4 workers) on a cold buffer, then again on the warm buffer | 629: `ReadAhead` 153, `Reap` 154, `SubmitNow` 3, `IssueRead` 1, `FixValid` 310, `Finish` 8 |
| `waiter.log` | two parallel scans and one serial scan at once on a cold buffer | 818; 26 `SleepOnPage`; 99 of the 154 `Reap` by a thread other than the ring owner (`ReapForWaiter`) |
| `fail.log` | one read-ahead completion fails (`CUBRID_TLA_FAIL_PAGE`): `Reap err=1`, then the fixing thread reads the page itself | 631 |
| `prepfail.log` | one request cannot be staged (`CUBRID_TLA_PREPFAIL_PAGE`): `InlineComplete err=1`, the rest of that call's pages are read by the fixing threads (59 `IssueRead`) | 631 |
| `victim.log` | the table is scanned, a larger table pushes its pages out of the 128M buffer (155 `Victimize`), it is scanned again | 1101 |
| `reap-before-request.log` | corrupted `ok.log`: a page's `Reap` moved in front of its `ReadAhead` | refused |
| `reap-dropped.log` | corrupted: one `Reap` removed (the page is fixed while still under I/O) | refused |
| `outcome-flipped.log` | corrupted: one successful `Reap` marked failed (the page is fixed although its read failed) | refused |
| `finish-undrained.log` | corrupted: a thread's `Finish` moved in front of the last `Reap` of its own ring (D8) | refused |

Every run returned the same query result as `io_method=sync` (`12000`, `72006000`, `1800000`). Actions no run reaches: `InlineComplete` with `err=0` (the page's image is in the double write buffer: needs a page flushed but not yet synced, and the test conf runs with `double_write_buffer_size=0`), `Interrupt` (not logged). Limits of the mapping: a thread whose own read fails and whose next logged event is a fix of another page would be refused (the model has no step that gives a fix up other than `Interrupt`); the injected failures are followed by a retry of the same page, so no run takes that path.

## Trace validation (`BitmapScan`, the bitmap heap scan code)

Instrumented build: scratch worktree `~/dev/cubrid-worktree/CBRD-28005-instr` = origin/develop `e30370dc0` + the working tree of `CBRD-28005` as of 2026-11-11 after the page fix of the heap phase (`fix_bitmap_page` for every marked page, `process_bitmap_row`, `index_scan_oid_bitmap_size`) + instrumentation (never committed; `.git_ignored_dir/scratch/aio-bench/bmtrace/instrument2.py` adds it, lines only: the diff has the 7 deleted lines of the working tree and no other), optdebug, install `~/optdebug/CUBRID-CBRD-28005-instr`. Events go to the file named by `CUBRID_TLA_TRACE_FILE`, `seq` from one global atomic counter.

| Event | Emitted at | Under |
|---|---|---|
| `Open`, `Sector` | `input_handler_index::bitmap_init_on_main` after the bitmap is allocated: the row bits and every listed sector with its page mask | leader, before any worker starts |
| `Mark` (`oid`, `kind` = `row`, `page`, `drop`) | `bitmap_mark`, after the atomic ORs (or at either drop: the sector is not in the list, the page was not allocated when the list was taken) | the worker's own mark; no reader before the barrier |
| `IdxFinish` | `bitmap_leave_index_phase` | `m_bm_mutex` |
| `TakeSector` (`sect`) | `task::bitmap_heap_phase`, after `bitmap_take_sector` | the taker (the hand-out is an atomic fetch-add) |
| `FixPage` (`page`) | `leaf_slot_walker::fix_bitmap_page`, the page is fixed | the page's read latch, held from here |
| `PageGone` (`page`) | `fix_bitmap_page`, the fix found the page deallocated | after the failed fix |
| `Lookup` (`oid`, `res` = `invisible`, `gone`, `recheck`, `filtered`, `out`) | `process_oid` (`invisible`: `S_SNAPSHOT_NOT_SATISFIED`, the row's version is deleted for the snapshot; `gone`: `S_DOESNT_EXIST`, the slot is empty or its only version is newer than the snapshot), `next_whole_page_row` (the index condition rejects the heap row), `finish_heap_row` (the data filter rejects it; the row is returned) | page latch |
| `ReleasePage` (`page`) | `slot_iterator_index::next_bitmap_row`, before `release_bitmap_page` at the end of the page | the page's read latch, still held |
| `EndSector` | `bitmap_heap_phase`, after the sector's last page (or at once when the sector has no mark) | worker-local |
| `Stop` | a worker leaves `bitmap_heap_phase` or `task::loop` with the interrupt raised; the last `Stop` of a run is the model's `Abort` | worker-local |
| `Vacuum` (`oid`) | `vacuum_heap_record`, after `spage_vacuum_slot` of the home slot (every record vacuum removes, of any table) | the page's write latch |
| `FreePage` (`page`) | `pgbuf_dealloc_page`, after the page type is set to unknown (every page deallocated, of any file) | the page's write latch |

Injection, in the instrumented build only, each off unless its environment variable is set: `CUBRID_TLA_BM_LEAF_FILTER_OFF` (the leaf and overflow-page callbacks `collect_oid_callback`, `ovf_collect_oid_callback` hand every index entry to the mark, also one the snapshot does not see), `CUBRID_TLA_BM_AFTER_LIST_DELAY_MS` (a pause after `file_get_all_data_sectors`), `CUBRID_TLA_BM_HEAP_PHASE_DELAY_MS` (a pause of every worker between the barrier and its first sector). The first is needed because with one snapshot for the whole scan the leaf's own check leaves every row the snapshot does not see unmarked: a dropped OID, a marked row found invisible, removed by vacuum, or on a deallocated page are then reached only when the snapshot changes under the scan (fault table, nested statement). The switch stands in for that change: the model lets the leaf mark any index entry.

The universe of a run is the run's own (`traces/bitmap/bitmap2tla.py` builds `BitmapScanTraceData`; the cfg substitutes it for the enumerated rows of `BitmapScan`): a row is an OID, the rows are the marked OIDs and the rows read on pages marked as a whole, `Vis` the rows a lookup found a visible version of, `DataOk` every row no lookup filtered out, `IdxRows` the marked OIDs, `Wide` the OIDs marked by page while the bitmap has row bits. A leaf of the trace is everything one worker marked (the leaf and overflow pages it walked are not logged; that walk is the parallel index scan's and is not changed). Not logged, taken by the trace spec only towards the next event: a worker taking and ending its leaf, and the lookup of a marked row the snapshot does not see on a page read as a whole (the page walk passes it without a call). Vacuum threads log every removal and every deallocation; `traces/bitmap/*.log` keep those of the scanned heap's sectors, and the generator keeps the rows of the universe and the listed pages.

| Run (`traces/bitmap/`) | What it covers | Events consumed |
|---|---|---|
| `exact.log` | 301 OIDs marked by row, 88 pages fixed and released, rows looked up in page order by 4 workers over 2 sectors; 30 filtered, 271 returned | 786 |
| `pages.log` | the bitmap holds pages only: 1 mark, the page read as a whole (228 rows: 227 rejected by the index condition, 1 returned) | 239 |
| `mixed.log` | row bits and page marks in one scan (width 100: 1 mark by row, 2 by page; 457 lookups) | 474 |
| `abort.log` | an error in the key filter (division by zero) during the index phase: no heap phase | 155 |
| `abort2.log` | an error in the data filter during the heap phase: 266 lookups, then both heap workers stop (one inside a page: 78 fixed, 77 released by `ReleasePage`) | 729 |
| `drop.log` | leaf check off, pause after the sector list while another session inserts 170 rows of the key range and commits: 144 OIDs dropped (90 on pages of the listed sector allocated after the list, 54 in a sector outside the list), 26 on listed pages marked and found without a version (`gone`), 10 rows deleted before the scan marked and found `invisible` (vacuum held back by an open REPEATABLE READ transaction, their `Vacuum` after the scan), 91 returned | 446 |
| `vacuum.log` | leaf check off, 60 rows deleted before the scan and marked; pause before the heap phase while vacuum removes them (60 `Vacuum`); the pages stay (13 rows a page): 60 lookups `gone`, 61 returned | 338 |
| `freed.log` | the same with one row a page: vacuum removes 20 marked rows and deallocates their 20 pages (`FreePage`) before the heap phase; row bits: 20 `PageGone`, 41 pages fixed, 41 returned | 267 |
| `pagegone.log` | as `freed.log` with a bitmap of pages only: 61 pages marked, 20 `PageGone`, 41 read as a whole | 267 |
| `mixed.log`, the first `ReleasePage` removed | corrupted: a page is not released (the defect of the first implementation) | refused |
| `exact.log`, a `Lookup` repeated | corrupted: a marked row looked up twice | refused |
| `exact.log`, an `IdxFinish` removed | corrupted: a sector taken while a worker is still in its index phase | refused |
| `exact.log`, a `Lookup` removed | corrupted: a page released with a marked visible row not looked up | refused |
| `pagegone.log`, the first `FreePage` removed | corrupted: a page passed as gone that was not deallocated | refused |
| `freed.log`, the first `Vacuum` removed | corrupted: a page deallocated while a row on it was not removed | refused |

Every run returned the same query result as the scan without the bitmap (`exact` to `abort2`), or as a heap scan with the same condition run just before it (`drop` 91 rows, `vacuum` 61, `freed` and `pagegone` 41). Every action of the refinement map is in an accepted run. The runs were recorded again on the final code (the lookup reusing the held page). The first `freed` run, on the build before the page fix, ended in the optdebug assertion of `pgbuf_fix` (`OLD_PAGE` on a deallocated page, under `heap_prepare_object_page` <- `heap_get_visible_version` <- `process_oid`): a hole of the row-bit path the model did not have (it had no page deallocation), fixed by `fix_bitmap_page` for every marked page, modeled as `FixPage` before every `Lookup`, and kept as `mutant-fix-freed`. Not recorded: a run in which the snapshot changes under the scan without the injection (a nested statement). Larger runs (3,700 events over pages of 230 to 330 rows) were recorded on an earlier build and not checked: TLC ran over 13 minutes on one and overflowed its stack on two (900 rows).

## Trace validation (`BatchJoin`, the batched nested-loop join code)

Instrumented build: scratch worktree `~/dev/cubrid-worktree/CBRD-28005-instr` = origin/develop `e30370dc0` + the working tree of `CBRD-28005` (the pushed bitmap scan commit and the uncommitted batched join) + instrumentation (never committed; `.git_ignored_dir/scratch/aio-bench/nlbtrace/instrument-nlb.py`, `-nlb2.py`, `-nlb3.py`, `-nlb4.py` add it, lines only), installed at `~/optdebug/CUBRID-CBRD-28005-instr`. Events are `TLATRACE seq= a= p=` lines written by `bm_tla_event` (one global sequence counter).

| Event | Emitted at | Model action |
|---|---|---|
| `Arm` (`x`: the inner XASL node) | `qexec_nl_batch_arm`, the scan batches | the first one of a node starts the run, each later one is `Restart` |
| `Hold` (`o`: the outer row's ordinal in the execution, `kind` = `read`, `defer`) | `qexec_nl_batch_add`, the row is stored and its pre-read done | `AddOuter(kind)` with `next = o` |
| `Pass` (`o`) | `qexec_nl_batch_add` returns S_DOESNT_EXIST | `PassRow` with `next = o` |
| `Close` | `qexec_execute_scan`, before the hint | `CloseBatch` |
| `Open` (`o`) | `qexec_execute_scan`, after `qexec_nl_batch_open_row` | `OpenRow` with `cur' = o` |
| `MemoHit`, `TakeSlice`, `Scan` | `qexec_execute_nljoin_with_memoize` (the first get of a row answered), `scan_index_take_nl_slice`, `scan_next_index_scan` before its own index search | how the row of the last `Open` or `Pass` was answered: `how'` = `memo`, `slice`, `scan` |
| `Emit` (`o`) | the row path returned S_SUCCESS | `EmitOne` with `cur = o` |
| `RowDone` (`o`) | the row path returned S_END | `RowDone` with `cur = o` (followed by `EndBatch` for a passed row) |
| `EndBatch` | `qexec_execute_scan`, before `qexec_nl_batch_drop_rows` | `EndBatch` |
| `MemoClear` | `clear_memoize_storage` with a storage | `MemoDrop` when it falls between two events of the join (the clear at the end of an execution is left out); placed before the `Open` or `Pass` whose memoize call caused it |
| `Error` | the row path returned S_ERROR | `Stop` |
| (none) | the consumer stops asking (LIMIT) | `Stop`, taken unlogged before a `Restart` |

Injection, in the instrumented build only, each off unless its environment variable is set: `CUBRID_TLA_NLB_CAP` (the batch's OID target, and a pre-read that finds more OIDs counts as one that did not end: the model's `BufCap`; the b-tree's own OID buffer is not shrunk, it must hold a leaf record's OIDs), `CUBRID_TLA_NLB_ROWS` (the stored-rows bound in rows: the model's `MaxOuter`), `CUBRID_TLA_NLB_NO_BACKOFF` (no rows joined row at a time after a batch with nothing to hint: every page of the five-row tables is in the buffer), `CUBRID_TLA_NLB_MEMO_DROP_AT` (memoize reports itself full at the n-th new key it is asked for).

The runs join the model's own tables (`nlbtrace/load.sql`: `bo` with five rows and the keys 1 2 1 3 2, `bi` with three rows for key 1 and one for key 2, an index on `bi (k)`), serial, memoize attached by the optimizer. The join type and the inner rows the statement's filter accepts are given to `traces/join/nlb2tla.py` per run; a join row is logged by its outer row, and the model decides how many each outer row returns, so a run with a missing or an extra join row is refused.

| Run (`traces/join/`) | What it covers | Events |
|---|---|---|
| `inner.log` (`BufCap` 3, `MaxOuter` 3) | three batches: a read row filling the target; read, deferred (memoize holds its key) and read rows closed by the row bound; the last row at the outer scan's end (flush); stored OIDs taken, memoize hits | 36 |
| `left.log` (3, 3) | left outer join whose filter rejects the k2 row: NULL-extended rows for the k2 and k3 outer rows | 37 |
| `nofit.log` (2, 2) | the k1 pre-read finds three OIDs, more than the target: held deferred, the batch closed, the row answered by its own index search; a data filter rejecting one k1 row | 34 |
| `untaken.log` (8, 5) | all five rows in one batch; memoize answers the second k1 and k2 rows, whose stored OIDs are left untaken | 32 |
| `memodrop.log` (8, 5) | memoize gives up at the third row: the row takes its stored OIDs, the rest of the batch runs without memoize | 32 |
| `dropheld.log` (3, 3) | memoize gives up at a row held deferred for its key: the row is answered by its own index search | 36 |
| `restart.log` (8, 5) | a scalar subquery with LIMIT 1 run for two outer rows: each execution stops after one join row with five rows held, the next starts with none | 22 |
| `error.log` (3, 3) | a division by zero in the inner data filter during the first row | 7 |
| `backoff.log` (3, 3) | no injection of the back-off: after the first batch the four other rows are joined row at a time (`Pass`) | 28 |
| `inner.log`, the first `Close` removed | corrupted: a row opened while the batch is still collecting | refused |
| `inner.log`, the second `Emit` removed | corrupted: a join row missing | refused |
| `inner.log`, the first `Emit` repeated | corrupted: a join row twice | refused |
| `inner.log`, the first `RowDone` removed | corrupted: the next row opened inside a row | refused |
| `inner.log`, the third row said to take stored OIDs | corrupted: a deferred row has none | refused |
| `left.log`, the fifth `Emit` removed | corrupted: a NULL-extended row missing | refused |
| `restart.log`, the `Restart` removed | corrupted: an outer row arrives twice in one execution | refused |
| `untaken.log`, the second `Open` repeated | corrupted: a row opened twice | refused |

Every run returned the same rows as the statement with `nl_join_batch=no`. Every action of `BatchJoin` is in an accepted run. Not in a recorded run: more than one batching step, a partitioned inner, a parallel first scan (result parity only, see the refinement map).

## Bounds and limits

- BitmapScan TLC: 2 index workers, 2 heap workers, 3 leaves, 8 rows on 3 listed pages (two sectors; one page holds a single removable row and can be deallocated) and 1 unlisted, exact and pages-only bitmaps both (`lossy` chosen in `Init`), `MaxErrors = 1`; scale: 3 and 3 workers. Liveness at the base bound. Apalache's `CInit` fixes the worker sets (2 and 2); `MaxErrors` over all naturals.
- BitmapScan does not model: the plan-time choice (D26), the bitmap's layout in memory and the arithmetic of its width (D37: the model has `Wide` for a slot beyond it), relocated rows on a page marked as a whole (the heap phase walks home records as a heap scan does), key filter and visibility checks inside the index phase beyond "an invisible entry may be left out", read hints (no shared state), a deallocated page the same file uses again (as a heap page its new rows belong to transactions the snapshot does not see; as a page of the file's allocation table `pgbuf_ordered_fix` reports it as gone: `pgbuf_ordered_unfix_reused_page`, CBRD-27967), an index over several heaps (class hierarchy), values of key columns used outside the scan.
- BatchJoin TLC: 5 outer rows (keys k1 k2 k1 k3 k2), 3 + 1 + 0 index entries; inner and left outer join, every subset of passing inner rows, memoize on or off: all chosen in `Init`; two executions of the plan (`MaxExec = 2`), one stop (`MaxErrors = 1`). `BufCap = 3`, `MaxOuter = 3`; scale: `BufCap = 2, MaxOuter = 2` (the k1 rows do not fit) and `BufCap = 5, MaxOuter = 4`; the liveness cfg at `BufCap = 2, MaxOuter = 2`. Apalache's `CInit`: `BufCap` over 1..8, `MaxOuter` over 1..5, any `MaxErrors` and `MaxExec`; IndInv is checked one conjunct per cfg (`BatchJoin.apalache-<Conjunct>`, each `INIT IndInv`, `INVARIANT <Conjunct>`), 146 s to 332 s each on this host.
- BatchJoin does not model: which scans batch, more than one batching step in a chain, a partitioned inner, the bytes of the stored outer rows (`MaxOuter` counts rows), the batch target's growth and the back-off, the heap pages and the hint; `CloseBatch` may close at any time rows are held, which covers every closing rule of the code.
- BatchJoinDesign TLC: 5 outer rows (keys k1 k2 k1 k3 k2), 3 + 1 + 0 index entries, the k1 entries in two partitions; every join type, both order modes, every subset of passing inner rows, memoize on or off: all chosen in `Init`. `BufCap = 2`, `MaxOuter = 2`; scale: `BufCap = 1, MaxOuter = 3` and `BufCap = 5, MaxOuter = 4`. Apalache's `CInit`: `BufCap` over 1..8, `MaxOuter` over 1..5 (the index holds 8 entries and the outer side 5 rows, so larger values behave as 8 and 5). IndInv is checked one conjunct per cfg (`BatchJoinDesign.apalache-<Conjunct>`, each `INIT IndInv`, `INVARIANT <Conjunct>`): the single cfg did not finish in 30 minutes on this host.
- BatchJoinDesign does not model: more than one join level (D20), the following join and FOR UPDATE (row at a time, D21), the bytes of the stored outer rows (`MaxOuter` counts rows), which partitions pruning leaves, the heap pages and read hints of the batch (the heap read is part of `CloseBatch`), correlated subqueries of the inner, the outer side's own scan.

- OidBatch TLC: 2 scans over the same 3-OID key range on 2 heap pages (OID 1 and 3 on one page), window 2 pages, batch 2 OIDs, 1 frame, one row vacuumable, `MaxErrors = 1`, both orders; scale: 4 OIDs, batch 3. Liveness at the base bound, both orders.
- OidBatch does not model: the index side (leaf latches, leaf reads, the scan resuming on a changed leaf), the batch of nested-loop outer rows (D16's second source of OIDs), DML moving a row (the OID stays valid: relocation is followed from the home page as today), the LRU bottom (index-driven pages are not demoted).

- ReadStream TLC: 2 scans over the same 3-page list, window 2, 2 frames, one page hot at the start, one page deallocatable, `MaxErrors = 1`; scale: window 3 (wider than the 2 frames). Liveness at the base bound only.
- ReadStream does not model: the latch or lock wait of AsyncRead (X), combined reads (one SQE for adjacent pages: a run completes or fails page by page here), the adaptive depth (any depth up to `W` is explored), the size condition of D15 (every table is "large"), DML on the pages (page content is abstract: `Vis`).

- AsyncRead TLC: 2 threads, 2 pages, `MaxErrors = 1`, `MaxVictims = 1`, `MaxRounds = 1` (each thread may start over once: `Loop` inside a request or `Reuse` after the pool); scale: 3 threads with `MaxRounds = 0`, and 2 threads with `MaxRounds = 2`.
- One abstract lock X stands for every latch or lock a scan thread may sleep on.
- Liveness (`AllComplete`) is checked at the 2-thread bound only (`live`, `option-daemon-live`); the 3-thread scale cfg checks the invariants.
- Apalache's `CInit` fixes `Reaper = "any_waiter"`: IndInv is inductive for that option with `MaxErrors`, `MaxVictims` over all naturals; the daemon option is a TLC comparison.
- Not modeled (each a pending decision or a later model):
  - a finite frame pool: frames under I/O cannot be victims, so read-ahead depth needs a cap against the buffer size (PostgreSQL limits pins per backend); today a thread that finds no victim errors out after a timeout (`pgbuf_allocate_bcb`), it does not hang;
  - the waiter's wait is level-triggered (`WakePage` enabled whenever the BCB left `io`): the BCB-mutex condition-wait protocol and the kernel wait on another thread's ring (`io_uring_wait_cqe` under the ring's completion mutex) are refined by the implementation spec;
  - cancelling staged SQEs instead of submitting them at an interrupt;
  - page content, snapshots, DML, vacuum, deallocated pages: the read stream model.

## Counterexamples and divergences

- Trace divergence (2026-11-10, `waiter.log`, first recording): the trace spec refused the first `Reap` by a thread other than the ring owner. Mapped to code: T1 fixes p, finds it under T2's read ahead (`pgbuf_lock_page`), lets the hash anchor mutex go; T2 reaps p itself; T1 enters `fileio_aio_reap (T2)` and processes T2's other completions. The model allowed `ReapForWaiter` only while the page T1 wants is still under I/O. Classified as a model error (the model was narrower than the code; no claim is at risk: a completion is processed once, under `cq_mutex`, by whoever holds it). Fixed in the model: `waitRing[t]` is the ring T1 read at `SleepOnPage`, `ReapForWaiter` reaps that ring whatever became of the page, `WakePage` fires when the page left I/O or changed rings (IndInv `WaitRingShape`). The instrumentation logs `SleepOnPage` since then. All `AsyncRead` cfgs were rerun.

- CTIs (2026-11-10, `BitmapScan.apalache-indinv`), both from states the scan cannot reach, IndInv strengthened: (1) a row returned while its sector was still in the hand-out list (`RowOnce` now ties a returned row to a handed-out sector and a held sector's row to "looked up or returned"); (2) a visible row among the removed ones (`GoneInvisible`); after the D36 rewrite (3) a worker holding a leaf that is still in the hand-out list with pending entries that are not the leaf's (`LeafShape` now ties `pend` to the leaf's entries).

## Review notes (2026-11-10 self-review after the first RESULT: OK)

- Fixed: the `hit` ghost fired on any fix of a valid page; it now requires the frame to come from a read ahead (`ra`), so `witness-read-ahead-hit` shows a read ahead being consumed.
- Fixed: `mutant-owner-only` and the two `block-with-staged` mutants were first expected as deadlocks and survived, because an unfair `Interrupt` stays enabled in the stuck state; they are liveness violations (the query hangs until someone cancels it) and are checked against `AllComplete`.
- Checked and kept: WF on the whole `ThreadStep(t)` is enough because no thread action repeats without consuming state (a staged set, a CQE, an error or victim budget).

## Review notes (2026-11-11, points handed over by another session after comparing with the merged parallel scan models)

Compared against: `PxHeapRcSnapshot`, `NlInnerFixed` and the lazy-snapshot H2 model (CBRD-27967, PR 8438), `PxHeapScan` (CBRD-27723, PR 8235), `PxIndexLeafDispatch` (CBRD-27737/38), `DescLeafDispatch` (CBRD-27848/27968, PR 8423). The engine base `e30370dc0` holds those fixes. Each point was read against the code of `CBRD-28005` before anything was changed; none is a code defect found by a run.

| # | Point | Verdict after reading the code | State |
|---|---|---|---|
| 1 | `BatchJoin`: the nested-statement row of the fault table says not applicable, but `scan_index_nl_batch_collect` reads the inner index under the statement snapshot, which a nested statement (SP SQL from the client, `net_server_request` -> `logtb_invalidate_snapshot_data`) rebuilds under READ COMMITTED. The row-at-a-time join searches outer row 2 after the call, the batched join read rows 2..k before it | valid. The same exposure exists today inside one OID buffer of one outer row (the index is read, then the rows are returned one by one); the batch widens it to the held rows. C8 cannot hold across a rebuilt snapshot | fault row corrected; such statements keep batching, C8 is stated without them (D39) |
| 2 | `BatchJoin`: errors of rows read ahead are not in C8; `Stop` does not tell a consumer's stop from an error of a row the row-at-a-time join would not have reached | valid as a model gap. Measured on the release build: with `nl_join_batch=no` the statement `... where o.k = i.k and o.id > 0 and 100 / (o.id - 30) <> 0 limit 50` already fails with a division by zero although 50 join rows exist before outer row 30 (the heap scan evaluates a page, the index scan an OID buffer of keys ahead), so reading ahead with errors is today's behavior for the outer side; a statement that succeeds without the option and fails with it was not reproduced (on data in the buffer the back-off returns to row at a time) | accepted by the user and written into C8 (D39) |
| 3 | `BitmapScan`: a deallocated page reused (as the file's table page, or by the same heap for new rows) is not modeled; no mutant for the page-type check | the code is safe: `fix_bitmap_page` fixes with `pgbuf_ordered_fix (OLD_PAGE_MAYBE_DEALLOCATED)`, which unfixes a page that came back with a page type ordered fix does not handle (`pgbuf_ordered_unfix_reused_page`) and reports it as deallocated; a page reused by the same heap holds rows newer than the snapshot. The model does not name this protection | not done: the user decided against these supplements (D39) |
| 4 | `BitmapScan`: `FreePage` is one step, and the second page a relocated or overflow row needs (ordered fix may release and fix again the held page) is not in the map | valid model gap; the lookup goes through `heap_get_visible_version` with the scan cache's watcher, as the row scan of `NlInnerFixed` does | not done: the user decided against these supplements (D39) |
| 5 | `BitmapScan`: the model has separate index and heap workers; in the code the same workers run both phases, the barrier counts `m_bm_index_pending = parallelism`, a worker leaves the index phase at one of two sites guarded by `bitmap_left_index_phase`, and a failed start is opened only by the leader's JOB_ENDED | the description matches the code. `start_tasks` pushes exactly `m_parallelism` tasks, and its failure path sets JOB_ENDED and drains, so no worker waits forever. The model cannot express a double leave or a worker that never started | not done: the user decided against these supplements (D39) |
| 6 | `BitmapScan`: `Abort` stops every worker and empties the bitmap in one step; in the code each worker stops at its next check and the leader frees the bitmap after the join | valid model gap | not done: the user decided against these supplements (D39) |
| 7 | `BitmapScan`: the leaves of the index phase are a fixed set; the reliance on the verified leaf dispatch models is written only as "unchanged" | valid: an assumption to state (the bitmap is an OR, so at-least-once coverage of the key range is enough); overflow chains inherit the open defects CBRD-27972 and CBRD-27973 | not done: the user decided against these supplements (D39) |
| 8 | The `RESULT: OK` count includes `AsyncRead`, `ReadStream` and `OidBatch`, models of the io_uring alternative that is not in the pushed commit; the pushed hint path (`scan_index_read_ahead`, the parallel leaf walker's hint) has no model | valid: the header says so, the Result entries did not | stated in the Result entry of this date |
| 9 | `BatchJoin`: "not modeled: which scans batch" should name, per refusal of `qexec_nl_batch_arm`, the inputs it keeps out | valid | table below |

### What keeps a scan row at a time (`qexec_nl_batch_arm`, `qexec_nl_batch_add`, `scan_index_nl_batch_ok`)

| Condition | Input it keeps out, and why |
|---|---|
| inner is a semi, anti or following join (`XASL_IS_PER_OUTER_ROW`) | EXISTS / NOT EXISTS / IN rewritten to a join, and the join that follows one: they stop at the first match and are re-entered per outer row with their own state (`single_fetched`) |
| inner is not an index scan of a class (`TARGET_CLASS`, `ACCESS_METHOD_INDEX`) | a heap scan, a list scan, a set, a dblink or a method scan as inner: no OIDs to read ahead |
| inner FOR UPDATE, an inner scan that locks or changes rows (`mvcc_select_lock_needed`, `scan_op_type`) | SELECT FOR UPDATE, UPDATE and DELETE targets: the row is locked when it is looked up |
| inner is covering, multi-range optimization, index skip scan, count only, GROUP BY skip, key limit, a key list or several ranges, a class without MVCC, a grouped or backward scan | scans whose OID buffer is not "the key's rows in key order" or that never look the heap up |
| outer has correlated subqueries, a path expression or a function scan (`dptr_list`, `bptr_list`, `fptr_list`) | values of the outer row that live outside its value list would not be put back |
| outer is not a class or list scan; the outer scan locks its rows | a set, dblink, JSON table, method or show scan as outer; an UPDATE/DELETE target as outer |
| first scan: an if predicate, an after-join predicate, a hash join runtime filter, a CONNECT BY, an iteration bound, a block that is neither a list nor a value block | work the first scan's row loop does per row, which the pass that joins the rows left at its end skips |
| first scan: GROUP BY skip | the first scan marks the row that starts a key for the join row that follows it |

## Result

- 2026-11-11 (batched join), by parts, no whole-directory record run yet: `BatchJoin` (the implemented join, D38; engine commit `e802abfa7`) passes its cfgs in `--only` runs, each `RESULT: PARTIAL` with 0 failed. Main `BufCap = 3, MaxOuter = 3`, two executions: 393730/165194 states (depth 52), run dir `CBRD-28005-20261111-102159-659142`; scale `BufCap = 2, MaxOuter = 2` 243472/101520 and `BufCap = 5, MaxOuter = 4` 728622/308694 (`...-102455-668153`); `live` (`Ends`, two executions) pass (`...-104037-681477`). Mutants: 7 rejected (`no-restore`, `stale-slice`, `keep-batch` by `NoExtra`; `partial-as-complete`, `no-flush` by `AllReturned`; `no-close-at-half` by `ArrayBound`; `replay-any-order` by `InOrder`), `...-102005-648847`. Witnesses: 11 reached (`...-102113-654576`). Apalache: IndInv as 9 per-conjunct cfgs, all pass, 146 s to 332 s (`...-102158-658292`). `BatchJoinTrace`, on runs recorded again on the final code: 9 recorded runs accepted, 8 corrupted runs refused (`CBRD-28005-20261111-105747-815545`). `BatchJoinDesign` (the former `BatchJoin`, renamed, not otherwise changed) was last run under its old name in the entry below. Two whole-directory runs of this date were stopped before their end (the directory has 176 cfgs; the first reached 11 passes, the second 10, none failed): the record run is owed after the next change of the join code (D39 (1)). Scope of the counts in the entries below: `AsyncRead`, `ReadStream` and `OidBatch` model the io_uring alternative, which is not in the pushed code; the pushed hint path (`scan_index_read_ahead`, the parallel leaf walker's hint) has no model. TLAPS 요청 없음.
- 2026-11-11 (later), `tools/tla/tla-check docs/tla/CBRD-28005/`: `RESULT: OK`, run dir `.git_ignored_dir/scratch/tla/CBRD-28005-20261111-035728-2947084`, 128 cfgs, 128 PASS, 0 FAIL. The record run on the final files: the nine bitmap traces recorded again on the pushed code (fork `CBRD-28005-aio` `4c4e04f7b` + instrumentation; the row lookup reuses the held page), the two `AsyncRead` block-with-staged mutants with the deadlock check off (the run before this one, `...-033953-2536864`, stopped, had reported one of them as `deadlock` beside a CTP run). No spec change since the entry below.
- 2026-11-11, `tools/tla/tla-check docs/tla/CBRD-28005/`: `RESULT: OK`, run dir `.git_ignored_dir/scratch/tla/CBRD-28005-20261111-021015-544795`, 128 cfgs, 128 PASS, 0 FAIL (AsyncRead 16, AsyncReadTrace 9, ReadStream 18, OidBatch 18, BitmapScan 22, BitmapScanTrace 15, BatchJoin 30). The record run after the last spec, cfg and MAP edit: `BitmapScan` with page deallocation (`FreePage`, `SkipFreedPage`, `freed`) and the page fix before every lookup (`FixPage`, `ReleasePage` for every marked page); main 770874/130392 states (depth 37), `live` pass at the same bound, scale 3 + 3 workers 3556666/519636 (depth 38), IndInv by Apalache. Mutants: 10 rejected (the 8 before, `no-freed-skip` by deadlock, `fix-freed` by `NoFreedPageHeld`; `no-barrier` at 1 + 1 workers). Witnesses: 8 reached (`freed-page` new). Trace validation of the bitmap code: 9 recorded runs accepted, 6 corrupted runs refused (section above). TLAPS 요청 없음.
  - Counterexample classified (hole, reproduced and fixed): the first `freed` trace run crashed the instrumented optdebug server in `pgbuf_fix` (`OLD_PAGE` fix of a deallocated page under `heap_get_visible_version`). The model had no page deallocation, so it could not show it. With `FreePage` in the model the old row-bit path is `mutant-fix-freed`; the code now fixes every marked page with `OLD_PAGE_MAYBE_DEALLOCATED` first (`fix_bitmap_page`). Reached only with the leaf's snapshot check switched off (injection); in a release build the old path cleared `ER_HEAP_UNKNOWN_OBJECT` and passed the row.
- 2026-11-10 (night), `tools/tla/tla-check docs/tla/CBRD-28005/`: `RESULT: OK`, run dir `.git_ignored_dir/scratch/tla/CBRD-28005-20261110-205229-46110`, 108 cfgs, 108 PASS, 0 FAIL (AsyncRead 16, AsyncReadTrace 9, ReadStream 18, OidBatch 18, BitmapScan 17, BatchJoin 30). This is the record run after the last spec, cfg and MAP edit of BitmapScan (D36) and BatchJoin (D35); the per-model numbers are in the entries below. The trace cfgs of the io_uring alternative pass again: 5 recorded runs accepted, 4 corrupted runs refused. TLAPS 요청 없음.
- 2026-11-10 (late), per-cfg runs with `--only` (each `RESULT: PARTIAL`, 0 failed), before the record run above:
  - BitmapScan (C6; D36 form: shared bitmap, atomic OR, pages-only above the bound), run dirs `.git_ignored_dir/scratch/tla/CBRD-28005-20261110-203304-34566` and the three reruns of the pass cfgs after their `uncovered-ok` lines: main 69282/14296 states (depth 28), `live` pass at the same bound, scale 3 + 3 workers 336482/57252 (depth 29). Mutants: 7 rejected (`no-barrier`, `nonatomic-or`, `late-sector-list` by `AllRowsReturned`; `sector-twice`, `no-heap-visibility`, `no-recheck`, `both-paths` by `NoExtraRow`). Witnesses: 6 reached. Apalache: `BitmapScan.apalache-indinv` pass (41 s).
  - BatchJoin (C8; D35: a spanning row is memoized), run dirs `...-203128-32412` (main), `...-203613-39418` (TLC), `...-203152-33183` and `...-203728-41423` (Apalache): main 20092/12240 states (depth 25), `live` pass, scale `BufCap = 1` 27607/16580 (depth 35), `BufCap = 5` 17101/9870 (depth 21). Mutants: 7 rejected (`no-carry`, `no-last`, `resume-partition-start` by `NoExtra`; `resume-next-outer`, `memo-partial`, `hit-by-reference` by `AllReturned`; `free-emit` by `InOrder`). Witnesses: 7 reached. Apalache: IndInv as 12 per-conjunct cfgs, all pass (303 s to 1022 s each).
  - TLAPS 요청 없음. Trace validation: exempt (designs with no implementation).
  - ADR: `docs/adr/0056-whole-range-batch-shared-sector-bitmap.md`.
- 2026-11-10, `tools/tla/tla-check docs/tla/CBRD-28005/`: `RESULT: OK`, run dir `.git_ignored_dir/scratch/tla/CBRD-28005-20261110-163852-3112385`, 51 cfgs (AsyncRead, ReadStream, OidBatch). The nested-loop read-ahead (round 8, Q30/Q31) has no model yet.
- OidBatch, TLC: order free 421452/127333 states (depth 32), key order 158788/49881 (depth 35); `live` and `key-live` pass at the same bounds; scale 4 OIDs 1978248/577442 (depth 36). Mutants: 6 rejected (C4, C6 x3, C7, deadlock); witnesses: 5 reached. Apalache: `OidBatch.apalache-indinv` (order free) and `OidBatch.apalache-indinv-key` pass.
- AsyncRead, TLC: main 155759/49593 states (depth 28); `live` (C2) pass at the same bound; scale 3 threads 5532878/1275470 (depth 34); `option-daemon` and `option-daemon-live` 188193/46097 (depth 26). Mutants: 6 rejected (3 liveness, 2 deadlock, 1 `NoFrameReuseInIO`); witnesses: 3 reached.
- ReadStream, TLC: main 10644453/2523410 states (depth 33); `live` (C2, C4) pass at the same bound; scale window 3: 15576811/3463212 (depth 32). Mutants: 9 rejected (5 invariant violations for C1, C3, C4, C5; 2 `Complete`; 1 deadlock; 1 liveness); witnesses: 5 reached.
- Apalache: `AsyncRead.apalache-indinv` and `ReadStream.apalache-indinv` pass (IndInv inductive; role sets, `W = 2`, `NFrames = 2` fixed; the fault budgets over all naturals).
- Counterexample classified: the first `ReadStream.live` run failed (two scans holding the same page fixed and reading other pages forever). Model error: the code processes a page it fixed and unfixes it in straight line, and a read the scan needs happens inside `pgbuf_fix`, which reserves the frame for the fixer (`page_buffer.c` `pgbuf_fix`: `add_fcnt` right after `pgbuf_claim_bcb_for_fix`). Fixed by `need`/`Reserved`/`FixNeed` and by `ReadNow` requiring no held fix; no fairness beyond WF was added.
- TLAPS 요청 없음. Trace validation: exempt (design with no implementation).
- Environment fact (2026-11-10, perf run `20261110-145106-248`): perf-node0 runs kernel `4.18.0-553.63.1.el8_10`; `io_uring_setup` returns ENOSYS; `/home` is ext4 on a rotational RAID volume (SMC3108); no sudo, so the OS page cache cannot be dropped there.
- Measurements (I/O ceiling on NVMe and SATA SSD, TPC-H Q1/Q7/Q9/Q20 cold, OS-warm and hot): `docs/research/async-io-read-ahead-sizing.md`.
