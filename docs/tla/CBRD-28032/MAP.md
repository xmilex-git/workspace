# CBRD-28032 bitmap heap scan — design ledger (grill-with-tla)

Spec directory of the bitmap heap scan's second design round (2026-11-18). It starts from `BitmapScan`, the model
of the implementation in `docs/tla/CBRD-28005/` (the code at CUBRID `a29e041a4`, the port of that implementation
onto develop `406d2d87a`); the decisions below replace parts of it and are written into the spec as they settle.

trace-exempt: the design of this round has no implementation yet; `BitmapScan` as copied here was trace-validated in `docs/tla/CBRD-28005/` (section "Trace validation (`BitmapScan`, ...)") against the code it models.

## Design tree (grilling ledger)

| Id | Decision | State | In the model |
|---|---|---|---|
| E1 | `index_scan_oid_bitmap_size` is removed. The scan's memory bound is the index scan OID buffer (`index_scan_oid_buffer_size`, default 4 pages = 64 KB with 16K pages, at most 16 pages); what does not fit spills to a temp file. | settled 2026-11-18 (the user) | open: the spill form (round 1) |
| E2 | No lossy page: every marked row is exact, nothing is marked by page, the index condition is never checked again on the heap row. | settled 2026-11-18 (the user) | to remove: `lossy`, `pagebm`, the recheck |
| E3 | The optimizer decides at plan time whether an index scan runs as a bitmap heap scan; no on/off parameter; what it decides runs (D26, D42 of CBRD-28005; the CBRD-28032 body). | settled 2026-11-11 | not modeled (the model starts from a scan planned as a bitmap heap scan) |
| E4 | Filtered, function and prefix indexes are in scope: with no lossy page (E2) the index condition is never checked again on the heap row, which was the only reason they were kept out (`bitmap_index_is_plain`). | settled 2026-11-18 (the user, round 1 Q3) | to add: a filtered-index row is not filtered again in the heap step (witness) |
| E5 | The heap's sector list with each sector's allocated-page mask is taken before the index step (`file_get_all_data_sectors`, as today); the index step attaches a slot bitmap to each page it marks; what spills goes to a temp file in a compact fixed-length record format, not the list file tuple format (the user: as fixed-length sort keys are concatenated). | settled 2026-11-18 (the user, round 1 Q1) | open: record, memory owner, temp storage, heap-step merge (round 2) |
| E6 | Leaf splits and merges during the index step must not make the OIDs found differ from what the sector list and the snapshot allow: to be modeled (the user, round 1 Q1). | settled 2026-11-18 (to model) | open: claims C7, C8 (round 2) |
| E7 | Each index-step worker marks into a buffer of its own, of the OID buffer's size; no bitmap shared between workers while marking (replaces D36's shared atomic-OR bitmap). | settled 2026-11-18 (the user, round 2 Q5) | to change: `Mark` writes the worker's own buffer |
| E8 | Claims C7 (an OID of a key present for the whole scan is found whatever splits and vacuum merges happen during the index step; an OID found twice is returned once) and C8 (an OID outside the sector list, or on a page the list shows unallocated, belongs to a row the snapshot does not see). A snapshot rebuilt by a nested statement and the statement's own inserts are environment assumptions (CBRD-27579, as CBRD-28043 D15), shown by a cfg that drops the assumption. | settled 2026-11-18 (the user, round 2 Q8) | to add |
| E9 | A plan that ends up using the index's key order (skip ORDER BY / GROUP BY) is not a bitmap heap scan: the flag is dropped when the order use is decided. Claim C9. | settled 2026-11-18 (the user, round 2 Q9) | not modeled (plan-time rule) |
| E10 | The heap step sees, per sector it takes, the marked pages and each page's slot bitmap, each sector and each page written once, and reads them in that order; no merge of sorted runs (the user, round 2 Q4, Q7). | settled 2026-11-18 | open: what the temp file holds between the two steps (round 3) |
| E11 | Between the steps the temp file holds marks grouped by sector range (round 3 Q10 option B): fixed-length marks appended per range; the heap step builds each range's sector image (page mask, slot bitmaps, each once) from them and reads the heap in sector order. | superseded by E18; was settled 2026-11-18 (the user) | to add: `Flush`, `BuildImage` |
| E12 | Memory bound, amending E1: every structure of the scan (marks, sector list, images) lives in temp files with a memory buffer of 20 pages (`TEMP_FILE_MEMBUF_KEY_BUFFER`, `index_scan_key_buffer_pages`, the covering scan's key buffer) and spills to temp file pages beyond it; nothing is held outside that bound, the sector list included (round 3 Q10, Q12). | settled 2026-11-18 (the user) | open: which files (round 4) |
| E13 | Index workers write their own marks (E7); in the heap step nobody writes, so heap workers read every worker's marks without a lock (round 3 Q11). | settled 2026-11-18 (the user) | the barrier (`TakeSector` after every `idone`) is what makes the reads lock-free |
| E14 | A range image's width per page is the highest slot marked in that range, recorded exactly while the marks are written (round 4 Q15: "그렇게 해봐"). | superseded by E18; was settled 2026-11-18 (the user) | to add: `width`; mutant `stale-width` |
| E15 | The optimizer's row estimate decides only the plan (cost); no size, layout or correctness of the scan depends on it or on the heap header's estimates (the user's doubt, round 4). Sizes come from the sector count at scan start and from the marks actually written. | settled 2026-11-18 | nothing in the model reads an estimate |
| E16 | Spill, no lossy page, confirmed after measurement (round 5 Q20 a). Measured on perf-node0, run `20261118-161919-248`, release `b3e8d4823cde`, TPC-H SF10 lineitem by `l_partkey`, parallel(4), 12G buffer, cold / hot seconds: 0.1% plain 1.6 / 0.03, row bits 2.0 / 0.05, pages only (320 KB bound) 2.3 / 0.59; 1% plain 11.6 / 0.26, row bits 6.0 / 0.27, pages only 10.0 / 3.78; 10% plain 25.5 / 2.96, row bits 13.5 / 1.54, pages only 16.0 / 6.97. A bound of 20 pages with lossy pages makes every scan of a table that size pages-only, which is slower than the plain lookup on a hot buffer at every selectivity measured. Filtered, function and prefix indexes returned the plain lookup's rows under a whole-page recheck (optdebug `BM_ANY_INDEX` experiment, 4 queries, 0 differing lines), so E4 holds either way. | settled 2026-11-18 (the user) | E2 stands |
| E17 | The index step appends a fixed 4-byte mark per OID to the worker's own buffer and never writes a bitmap; the heap step ORs a range's marks into that range's image. No sort; the gate measures the hot `instructions:u` increase against the row-bit implementation (round 6 Q22). | superseded by E18; was settled 2026-11-18 (the user) | to add: `Append`, `Flush`, `BuildImage` |
| E18 | The bitmap is built while the index is read, not from appended marks afterwards: fixed length, every sector of the list with its 64 pages, a fixed width per page of 582 slot bits (twice the 291 tuples an 8K page of PostgreSQL holds), no measured width, no range images (the user, round 7: "append 방식의 한계가 느껴져"). Supersedes E11, E14, E17; E2 (no lossy page), E12 (20-page memory buffer, then temp file) and E16 stand. | layout superseded by E22 (entries for marked pages only); "built while the index is read" stands; was settled 2026-11-18 (the user) | open: a slot at or beyond the width, shared or per-worker bitmaps, the per-mark temp page fix (round 8) |
| E19 | The width is 640 slot bits a page (10 words, 80 bytes); refines E18's 582 (round 8 Q27). | settled 2026-11-18 (the user) | constant `Width` |
| E20 | An OID whose slot number is at or beyond the width is not marked in the bitmap: each worker keeps such OIDs in a temp list of its own; after the index step the lists are put together and those rows are looked up apart from the bitmap's rows, exactly, each once (round 8 Q28 a; expected to be rare). The plan does not change during execution. | settled 2026-11-18 (the user) | to add: `over`, the lookup of the merged list; mutants `drop-over`, `over-twice` |
| E21 | Each index-step worker marks a bitmap of its own (no lock, no shared word while marking); the heap worker that takes a section of sectors ORs every worker's bitmap for that section, position by position, and reads the marked pages; nothing is merged by the main thread and the merged bits are not written back (round 8 Q29 a with the recommended merge owner). Replaces E7's buffer wording and E13. | settled 2026-11-18 (the user) | to change: `bm` per worker, `TakeSection` ORs after the barrier; mutant `merge-before-barrier` |
| E22 | The bitmap is a hash table of page entries, as PostgreSQL builds it: an entry exists only for a page that got a mark, keyed by the page (sector, page 0..63 of the sector), holding the page's 640 slot bits (E19); the index step finds the entry by a hash lookup and creates it on the first mark. Spill to temp files and the merge of the workers' tables follow the hash join's partitioning (`query_hash_join.c`: `hjoin_check_partition`, `hjoin_split_qlist`). Replaces E18's dense layout over every page of the sector list. | settled 2026-11-18 (the user, round 9) | open: the partition function, the spilled record, the partition count (round 10) |
| E23 | The partition count grows while the scan runs, as PostgreSQL's hash join grows its batches (`nodeHash.c` `ExecHashIncreaseNumBatches`): it starts at 1 with everything in the in-memory hash table and doubles when the table fills its 20 pages; the lowest partition stays in memory, entries and later marks of the other partitions go to that partition's temp records; a partition whose records were written under a smaller count is divided again when it is loaded. Partitions are ranges of heap position, so doubling halves a range and a record stays or moves to a later partition only (round 10 Q36', "일단 이렇게 하자"). | superseded by E30; was settled 2026-11-18 (the user) | open: one count for all workers or one each, the record (Q35), the partition function (Q34) |
| E24 | The partition count is one value for the whole scan: when a worker doubles it, every worker uses the new count from its next mark on; records written under a smaller count sit in a wider partition's records and are divided when that partition is loaded (round 11 Q37). | superseded by E30; was settled 2026-11-18 (the user) | to add: shared `nparts`, `Double`, `Load` dividing a stale partition; mutants `no-redivide`, `count-per-worker` |
| E25 | The over-width list of E20 is an ordinary list file with one OID column per worker; after the partitions are done one worker unions the lists, sorts them by OID, drops duplicates and looks each OID up (round 11 Q30). | settled 2026-11-18 (the user) | `over` is a set per worker, the lookup takes their union |
| E26 | Partitions are slices of the sector list with equal numbers of sectors; doubling halves every slice at its middle sector; an OID's partition is found in an array of the slices' first sector addresses. A sector the heap got after the list was taken falls into the nearest slice and its rows are rejected by the heap step's visibility check (round 11 Q34). The hash key is the page (volume, page number). | settled 2026-11-18 (the user) | `PartOf`; C8 holds by the visibility check alone |
| E27 | A spilled entry is written as one fixed 16-byte record per non-zero word: page number 4 bytes, word number 1 byte (0..9), 3 bytes unused, the word's 64 slot bits; loading a partition reads its records in order and ORs each into the in-memory hash entry of its page (round 11 Q35 b). | settled 2026-11-18 (the user) | `Spill` writes (page, word, bits); `Load` ORs |
| E28 | The CPU prices of the new steps (mark, record write and read, merge, row lookup on a held page) are measured on the implemented build as ratios of `instructions:u` per row to a full scan's row, the existing CPU unit of `qo_sscan_cost`; `cost_heap_fetch_per_oid` is not used for the bitmap path; no constant is guessed and no parameter added (round 11 Q33). | settled 2026-11-18 (the user) | not modeled (gate item) |
| E29 | The optimizer's cost of a bitmap heap scan has one term per step of the execution: the index part as `qo_iscan_cost` computes it; a mark per row; when the estimated marked pages exceed what the workers' hash tables hold, 16-byte records written and read sequentially (per row, plus half of that once more for records divided again); a sort of the page entries; the marked heap pages once each at a unit price between random and sequential (`random - (random - seq) * sqrt (P / T)`); a row lookup on the held page per row. The cheaper of this and the plain index scan's cost is the plan's cost; a plan that turns out to use the key order drops the flag (E9). Prices by E28 (round 12 Q38). | settled 2026-11-18 (the user) | not modeled (plan-time rule) |
| E30 | The partition count is fixed when the scan starts, from the heap's page count taken from the sector list: pages / entries a table holds, rounded up to a power of two, at most 256; a table too large for that gets a second level (the heap worker divides its partition 256 ways once more). A worker keeps every page in its table until the table is full for the first time, then switches once: the table holds the lowest partition only and the rest are records. No doubling, no shared count, no record written under a smaller count. Measured reason (prototype `.git_ignored_dir/scratch/cbrd28032/proto/bmhash.cpp`, lineitem shape 729,600 pages x 82 rows, 4 workers, memory only, no page buffer): with doubling 60-80% (1%) and 41-45% (10%) of the 16-byte records were written under a smaller count and had to be divided again, and at 1% every one of the 64 partitions overflowed the heap worker's table (295,517 records written again); with the count set to 256 from the first overflow no record was written again. Structure cost in `instructions:u` per row (index step + merge + sort): 568 at 1%, 253 at 10%, against 84 and 39 for one shared atomic bitmap. Supersedes E23, E24 (round 13 Q39). | settled 2026-11-18 (the user) | `Switch`, `Units`, `TwoLevel`; mutants `evict-lost`, `no-redivide` |
| E31 | A record of E27 is first gathered in the worker's memory, 4,096 records (64 KB, the OID buffer's default size) at a time; a full batch is distributed by partition in one counting pass and appended to that partition's chain of pages in the worker's temp file (one file a worker, each page linked to the next, about 1,020 records a 16K page). The worker writes its last batch before it leaves the index step. Measured on perf-node0 (runs `20261118-202041-248` records in memory, `20261118-203134-248` sorted batch, `20261118-212647-248` counting pass, release `558d04423bf5` / `5e1837c88d28` / `a1547c0c8747`): 10% of lineitem SF10 hot with a 12G buffer 1.57-1.59 s / 1.99-2.01 s / 1.61-1.63 s, so the temp pages cost 0.04 s and the sort had cost 0.4 s. | settled 2026-11-18 (the user: "temp로 보내는거 만들고 성능테스트서버 실험해") | store `"stg"`, action `Flush`, guard of `IdxFinish`; mutant `no-flush` |
| E30a | Correction of E30's count: a partition is a run of whole sectors, so the count is the smallest power of two for which (sectors / count, rounded up) x 64 pages fits a table, not pages / entries (a count from pages alone overflowed the table on a small heap: "Internal system failure" with a 100-entry table). | found 2026-11-18 on the prototype | `Units` are whole quarters; nothing else changes |

## Claim and sources

| Id | Claim | Source |
|---|---|---|
| C6 | Every OID an index scan collected whose row its snapshot sees is returned exactly once, and nothing else is returned; a row vacuum removed between the index read and the heap read is skipped. | CBRD-28005 MAP C6 (grilling Q33 2026-11-10); CBRD-28032 body, Acceptance Criteria 1 |
| C4 | A scan that ends early (LIMIT, interrupt, error) or runs to its end leaves no heap page fixed and no leaf latched. | CBRD-28005 MAP C4 (grilling Q15 2026-11-10) |
| C7 | An OID of a key present for the whole scan is recorded whatever merges of leaves other transactions cause during the index step; an OID recorded twice (two keys of one row, two workers) is returned once. | the user, round 2 Q8 (E8) |
| C8 | A row inserted after the statement's snapshot is not returned, wherever its page lies; stated for a statement whose snapshot is not rebuilt while it runs (environment assumption, CBRD-27579). | the user, round 2 Q8 (E8), round 11 Q34 (E26) |

## Refinement map

The code is the prototype in the CBRD-28032 worktree (uncommitted, behind the experiment switch `BM_HASH`); the second level of partitions (`Divide`, `TakeRedo`) and the list file of E25 (the lists are vectors there) are not implemented in it.

| Model | Code | One step because |
|---|---|---|
| `TakeLeaf`, `EndLeaf`, `fheld`, `lastDisp` | `px_scan_index_leaf_page_dispatcher.cpp` (`m_frontier`, the hand-out under `m_leaf_mutex`) | the next leaf is fixed under the dispatcher's mutex while the frontier's worker still holds its latch |
| `MergeLR` | another transaction's `btree_merge_node` under both leaves' write latches | a merge holds both latches for the whole move |
| `MarkRow` | `leaf_slot_walker::process_oid` -> `input_handler_index::bh_mark` | the worker's own table, record batch and list: no other thread reads them before the barrier |
| `Switch` | `bh_mark`, the branch where `bh_table::get` returns no entry for the first time | same: the worker's own table |
| `Flush` | `input_handler_index::bh_flush` (a full batch in `bh_stage`; the last one from `task` before `bitmap_leave_index_phase`) | the worker's own temp file; pages are fixed and let go inside the call |
| `IdxFinish`, `Barrier` | `bitmap_leave_index_phase`, `bitmap_wait_index_phase` | the count of workers still in the index step, under the handler's mutex |
| `TakeUnit` | `bh_take_partition` (atomic counter) then `bh_load_partition` | the counter hands a partition to one worker; after the barrier nobody writes the tables or the temp pages |
| `TakeOver` | `bh_take_over` (atomic flag), sort and unique of the lists | one worker gets the flag |
| `FixPage`, `SkipFreedPage` | `leaf_slot_walker::fix_bitmap_page` (`OLD_PAGE_MAYBE_DEALLOCATED`) | one page fix |
| `LookupRow` | `slot_iterator_index::next_bitmap_row` -> `lookup_heap_row` (`heap_get_visible_version`) | the page stays fixed by this worker |
| `ReleasePage`, `EndUnit` | `release_bitmap_page`, the end of the partition's loop in `task::bitmap_heap_phase` | the worker's own fix |
| `Vacuum`, `FreePage` | vacuum's heap cleanup and `file_dealloc` of an emptied heap page | the page's write latch |
| `Abort` | the interrupt code set by a worker, read by every loop of `task`; the temp files freed in the handler's destructor | the interrupt is one atomic store |

## Fault model

| Fault | In the model |
|---|---|
| error return, interrupt / query cancel, OOM | `Abort`, enabled in every state of a run (`MaxErrors`); C4 holds after it |
| lock timeout, deadlock victim | not applicable: the scan takes no lock of its own (the index scan's key and row visibility are read under MVCC) |
| conditional latch failure | not applicable: the heap step fixes its pages unconditionally; the dispatcher's wait for the frontier is the code of CBRD-28005, unchanged |
| crash / `kill -9` | not modeled: the scan writes temp files only, which the server removes at restart; the orphan check after an abnormal end is a runtime check of the implementation ticket |
| spurious wakeup | the barrier's wait re-reads the count under the mutex (`bitmap_wait_index_phase`); the model's `Barrier` is that predicate |
| concurrent DML | `MergeLR` (leaf merge), r5 (a row inserted after the snapshot, on a page of a new sector), r1 and r7 (two keys of one row) |
| vacuum | `Vacuum`, `FreePage` |
| checkpoint, page flush, page replacement | not applicable: a page is read only while fixed |
| HA log apply | not applicable: the scan reads through MVCC as any index scan |
| nested statement (SP SQL from the client) | `RebuildSnap`, the environment C8 excludes (`witness-snapshot-rebuilt` shows the row it lets through; CBRD-27579) |

Fairness: weak fairness on each worker's steps (`Fairness`); `Switch` and the environment (`Merge`, `Vacuum`, `FreePage`, `Abort`) get none. Liveness `Ends` is checked in `BitmapHash.live` at the smallest bound.

## Properties

| Property | Kind | Claim |
|---|---|---|
| `NoExtraRow` | invariant | C6, C8 |
| `AllRowsReturned` | invariant | C6, C7 |
| `NoPageHeld`, `NoFreedPageHeld` | invariant | C4 |
| `Ends` | liveness (`BitmapHash.live`) | the scan ends or is stopped |
| `IndInv` | inductive invariant: `BitmapHash.apalache-indinv` (Apalache, `TwoLevel` both ways, any `MaxErrors`), and an invariant of the TLC pass cfgs | all of the above but `Ends` |

`IndInv` is not vacuous: without its conjunct `FrontierLatched` Apalache returns a counterexample to induction for `Recorded` (a merge moves leaf l3's keys into the leaf already read; run `vac28032-split-20261119-000018`).

## Mutants

| Cfg | Wrong variant | Expected | Claim |
|---|---|---|---|
| `BitmapHash.mutant-no-barrier` | a heap worker takes a partition while index workers still mark (1 index worker, 1 heap worker, no error: larger bounds did not end in 30 minutes) | violation `AllRowsReturned` | C6 |
| `BitmapHash.mutant-no-flush` | a worker leaves the index step with records still in its memory, never written to the temp pages | violation `AllRowsReturned` | C6 (E31) |
| `BitmapHash.mutant-evict-lost` | the entries a full table lets go are dropped instead of written as records | violation `AllRowsReturned` | C6 (E27, E30) |
| `BitmapHash.mutant-no-or` | loading a partition counts a row once per table or record set that holds it instead of ORing them | violation `NoExtraRow` (r1: two keys, two workers) | C6, C7 |
| `BitmapHash.mutant-unit-twice` | a partition stays in the hand-out list | violation `NoExtraRow` | C6 |
| `BitmapHash.mutant-no-redivide` | a worker that keeps the lowest part of a two-level partition drops the records of the rest | violation `AllRowsReturned` | C6 (E30, second level) |
| `BitmapHash.mutant-no-heap-visibility` | the heap step trusts the mark and skips the visibility check | violation `NoExtraRow` (r5: inserted after the snapshot; r8: deleted before it) | C6, C8 |
| `BitmapHash.mutant-drop-over` | the over-width lists are never looked up | violation `AllRowsReturned` (r7) | C6 (E20) |
| `BitmapHash.mutant-over-twice` | the over-width lists are looked up without dropping duplicates | violation `NoExtraRow` (r7: two keys, two workers) | C6, C7 (E25) |
| `BitmapHash.mutant-release-frontier` | the worker of the frontier leaf lets it go before the next leaf is fixed | violation `AllRowsReturned` (a merge moves the next leaf's keys into the leaf already read) | C7 |
| `BitmapHash.mutant-no-release` | the worker does not let go of a marked page it fixed | violation `NoPageHeld` | C4 |
| `BitmapHash.mutant-no-freed-skip` | a worker that finds a marked page deallocated has no way past it (no error allowed, so that the stuck worker is a deadlock) | deadlock | C6 |
| `BitmapHash.mutant-fix-freed` | a marked page is fixed as one that must exist although vacuum deallocated it | violation `NoFreedPageHeld` | C4, C6 |

## Witnesses

| Cfg | Outcome that must be reachable |
|---|---|
| `BitmapHash.witness-full-run` | the scan ran to its end |
| `BitmapHash.witness-in-memory-run` | a scan no worker of which filled its table ran to its end (no temp record) |
| `BitmapHash.witness-switched-run` | a scan every worker of which switched to the lowest partition ran to its end |
| `BitmapHash.witness-mixed-run` | a scan ran to its end with one worker switched and another still holding every page in its table |
| `BitmapHash.witness-spilled-run` | a scan with temp records ran to its end |
| `BitmapHash.witness-handed-on` | a heap worker handed the upper part of a two-level partition on |
| `BitmapHash.witness-merged-run` | a scan ran to its end although leaves were merged during the index step |
| `BitmapHash.witness-over-looked` | the over-width row was returned |
| `BitmapHash.witness-row-skipped` | the heap step is about to skip a marked row its snapshot does not see |
| `BitmapHash.witness-page-held` | a worker holds a marked page while it reads its rows |
| `BitmapHash.witness-freed-page` | a scan ran to its end past a page vacuum had deallocated |
| `BitmapHash.witness-snapshot-rebuilt` | with the snapshot rebuilt while the scan runs (the environment C8 excludes) a row inserted after the statement's snapshot is returned: `NoExtraRow` fails |

## Dead expressions (pass cfg)

| Lines | Action | Why TLC does not evaluate them in a pass cfg |
|---|---|---|
| `BitmapHash.tla:350`, `BitmapHash.tla:351`, `BitmapHash.tla:352`, `BitmapHash.tla:353`, `BitmapHash.tla:354`, `BitmapHash.tla:355`, `BitmapHash.tla:356`, `BitmapHash.tla:357`, `BitmapHash.tla:358` | `TakeRedoU` | one level of partitions in this cfg: nothing is handed on; `BitmapHash.scale-twolevel` (TwoLevel = TRUE) evaluates it |
| `BitmapHash.tla:365`, `BitmapHash.tla:366`, `BitmapHash.tla:367`, `BitmapHash.tla:368`, `BitmapHash.tla:369`, `BitmapHash.tla:370`, `BitmapHash.tla:371`, `BitmapHash.tla:372`, `BitmapHash.tla:373`, `BitmapHash.tla:374`, `BitmapHash.tla:375` | `Divide` | one level of partitions in this cfg: no partition is divided again; `BitmapHash.scale-twolevel` evaluates it |
| `BitmapHash.tla:469`, `BitmapHash.tla:470`, `BitmapHash.tla:471`, `BitmapHash.tla:472` | `RebuildSnap` | `Rebuild` is FALSE in every pass cfg: the snapshot is rebuilt only in the environment C8 excludes; `BitmapHash.witness-snapshot-rebuilt` evaluates it |
| `BitmapHash.tla:475`, `BitmapHash.tla:476`, `BitmapHash.tla:477`, `BitmapHash.tla:478`, `BitmapHash.tla:479`, `BitmapHash.tla:480`, `BitmapHash.tla:481`, `BitmapHash.tla:482`, `BitmapHash.tla:483`, `BitmapHash.tla:484`, `BitmapHash.tla:485`, `BitmapHash.tla:486`, `BitmapHash.tla:487`, `BitmapHash.tla:488`, `BitmapHash.tla:489`, `BitmapHash.tla:490`, `BitmapHash.tla:491` | `Abort` | `MaxErrors` is 0 in `BitmapHash.live` and `BitmapHash.scale-3h`; the main cfg (MaxErrors = 1) evaluates it |

## Result

`tools/tla/tla-check docs/tla/CBRD-28032` on 2026-11-19: `RESULT: OK`, 30 cfgs (run dir `.git_ignored_dir/scratch/tla/CBRD-28032-20261119-000508-2959571`).

- `BitmapHash`: 5,585,538 distinct states, depth 54; `BitmapHash.scale-twolevel` 8,475,552; `BitmapHash.scale-3h` (three heap workers, no error) 48,015,762 in 3,952 s; `BitmapHash.live` (`Ends`) 737,682.
- 13 mutants rejected as expected, 12 witnesses reached.
- `BitmapHash.apalache-indinv`: `IndInv` inductive for both values of `TwoLevel` and any `MaxErrors` (47 s).
- TLAPS: not requested.
- Not covered by this model: the plan choice (E3, E9, E29), the cost prices (E28), a crash (fault table), three index workers, and trace validation (`trace-exempt`): the prototype is experiment code, the implementation ticket records its runs against this spec.

