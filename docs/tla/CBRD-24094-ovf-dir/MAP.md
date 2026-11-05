# CBRD-24094 / CBRD-27401 — OID-ordered overflow chains with a separator directory, COMPACT, scan resume by OID

Code: develop `21c6e635d` (2026-11-05), `src/storage/btree.c` (below `btree.c`, line numbers of that
commit). The feature is PR #7447 (CBRD-24094, merged as `10a1df3e6`) with its follow-up PR #7899
(CBRD-27401, `ALTER INDEX ... COMPACT` and the range-scan resume by OID, `0c310e25c`). The models
cover one key of a non-unique index: its leaf record, its overflow data pages, the OID directory,
the writers that change them and a range scan that stops in the middle of the key.

| Module | What it is |
|---|---|
| `OvfDirChain.tla` | code-level model of the chain and the directory: insert (routed sorted insert, grow right, split, directory birth, directory tail append and split), physical removal (vacuum, rollback) with page unlink, directory entry removal, head pull-up and directory teardown, the leaf swap, COMPACT pulls, and the lookup `btree_ovf_dir_find_oid` as an operator |
| `OvfOrder.tla` | abstract order model (pages as sets, separators); `OvfDirChain` refines it (`OrderSpec`), its `IndInv` is TLAPS-proved in `OvfOrder_proofs.tla` |
| `OvfScanResume.tla` | extends `OvfDirChain` with a range scan whose OID buffer fills mid-key and resumes by OID while the writers run between iterations |
| `OvfScanResumeTrace.tla` | trace validation of a recorded run (`traces/h1a-run2.log`) against `OvfScanResume` |

## Claim and sources

| # | Claim | Source |
|---|---|---|
| C1 | Every object in a key's overflow chain is found by `btree_ovf_dir_find_oid` (no spurious ER_BTREE_UNKNOWN_KEY), also for same-OID runs straddling pages and OIDs below the first page's stored separator. | PR #7447 body (설계: 라우팅, 재사용 OID 중복 런의 물러남); `btree.c:13373` comment (head catch-all); CBRD-24094 comment 2026-10-13 (-407 deterministic case fixed) |
| C2 | The chain stays globally OID-ordered; the directory exists iff the chain grew to two pages (kept on shrink), its entries follow the chain order, every data page header carries the head, separators do not descend after the head's entry 0. | `btree.c:13087-13099` invariants comment; PR #7447 body |
| C3 | A COMPACT pull (merge or redistribution) keeps every object routable and the directory sorted; a raised separator stays within (max of the left page, min of the page]. | PR #7899 body (핵심 연산); `btree.c:14904-14920`, `btree.c:15004-15012` |
| C4 | No structural change (split, grow, page removal, directory pull-up, COMPACT, leaf swap) loses or duplicates an object. | CBRD-24094 AC "인덱스 스캔 결과가 순차 스캔과 일치" |
| C5 | After a crash and recovery the index still matches the heap: every structural change is atomic (one system operation), and a crash leaves the old or the new state. | CBRD-24094 AC "롤백/crash recovery 후에도 일치"; PR #7899 "a crash in the middle leaves either the merged or the un-merged state" (`btree.c:14916`) |
| C6 | A range scan interrupted in the middle of a key and resumed by OID returns every object visible to its snapshot exactly once, while pages are split, merged or freed in between. | PR #7899 body ("페이지가 병합·분할·반납되어도 정확하며 ... 중복 반환 가능성도 함께 없어집니다"); `btree.c:15455-15461`, `btree.c:30840-30847`, `btree.c:30989-30995` |
| C7 | The scan finishes. | — (liveness of any scan) |

## Refinement map (model -> code)

Every writer of a key's chain and directory holds that key's leaf page WRITE latch from its leaf fix
to its end (insert, delete, vacuum, rollback, COMPACT: `btree.c:14915`, `btree.c:13096`); overflow
and directory pages are fixed under it. A range scan holds the leaf READ latch (`bts->C_page`) for
a whole iteration over the key (`btree.c:30845`) and none between iterations (`btree.c:30486`
`btree_range_scan` unfixes `C_page` at the iteration's end). So one writer operation is one step,
one scan iteration is one step, and they interleave only between steps.

| Model | Code | One step because |
|---|---|---|
| `Insert` (leaf) | `btree_key_insert_new_object`: the object goes to the leaf record while it has room | leaf write latch |
| `Insert` (first overflow page) | `btree_key_append_object_as_new_overflow` (`btree.c:12765`): header with NULL `dir_vpid` | leaf write latch |
| `AppendOvf` | `btree_ovf_dir_append_object` (`btree.c:14772`): single-page path or `btree_ovf_dir_locate` (`btree.c:13287`), then `btree_key_append_object_to_overflow` (`btree.c:12902`) with `btree_insert_object_ordered_by_oid` (`btree.c:3890`, `InsOrdered`/`BSI`) | leaf write latch |
| `Grow` | `btree_ovf_dir_grow_chain` (`btree.c:14509`): grow right iff the target is the last page and the OID exceeds its last (`btree.c:14564`), else split at `num/2`; directory birth with two entries; `btree_ovf_dir_insert_entry` (`btree.c:13749`, `DirInsert`: in place, new tail page, or split) | one system operation under the leaf write latch |
| `Locate` | `btree_ovf_dir_locate` (`btree.c:13287`): advance while the next directory page's entry 0 does not exceed the OID, binary search for the rightmost separator not above it, head entry 0 as -infinity (`btree.c:13379`) | read of directory pages under the leaf latch |
| `InPage` | `btree_find_oid_from_ovfl` (`btree.c:16459`): early outs on the first and last object, then a search | one page |
| `Find`, `Walk` | `btree_ovf_dir_find_oid` (`btree.c:13481`): single-page path, else route and step back while the OID does not exceed the page's first object | under the leaf latch |
| `Remove` (chain) | `btree_find_oid_and_its_page` (`btree.c:16028`) then `btree_overflow_remove_object` (`btree.c:37157`): last object of a page frees it, unlinks it (leaf link or previous page), `btree_ovf_dir_remove_entry` (`btree.c:13932`, `DirRemove`: in place, head pull-up, unlink) or `btree_ovf_dir_destroy` (`btree.c:14177`) | one system operation under the leaf write latch |
| `Remove` (leaf, single object) | `btree_leaf_remove_object` (`btree.c:37368`) -> `btree_replace_first_oid_with_ovfl_oid` (`btree.c:11209`): the first page's last object replaces the leaf's object, the removed object is put in the first page at its OID-ordered position (`btree_record_replace_object`, `btree.c:38577`), the swap system operation commits (`btree.c:11345`), then that object is removed (`btree_overflow_remove_object`) | two durable halves under one leaf write latch: one step without the crash fault, two (`Remove`, `SwapDone`) with it |
| `CrashRecover` | crash after the swap's system operation commit; recovery and the restarted vacuum job remove the object by lookup; vacuum tolerates "not found" (`btree.c:36383`) | the crash ends the latch hold |
| `PullAt` | `btree_ovf_compact_pull` (`btree.c:15057`): partial move (append prefix, `btree_ovf_dir_set_separator` `btree.c:14936` with its four asserts, `SetSepBad`) or merge (unlink, `file_dealloc`, `btree_ovf_dir_remove_entry`); pairs and counts chosen by `btree_ovf_compact_chain` (`btree.c:15216`), modeled as any pair and any count the back-off allows | one system operation per pull under the leaf write latch |
| `SStart`, `KeyIter` | `btree_range_scan_select_visible_oids` (`btree.c:30706`) at a key start: leaf objects, then the chain from the first page; `O_last_visible_oid` reset (`btree.c:30910`) | leaf read latch over the iteration |
| `ChainIter` (stop) | buffer full before the next page (`btree.c:30975`); anchor `O_last_oid := O_last_visible_oid` (`btree.c:30996`, set per accepted object `btree.c:31147`); a stop needs an object accepted in this iteration: a key starts only with room for its leaf objects plus one full overflow page (`btree.c:30774` with `btree.c:29694`), a resumed iteration starts empty | leaf read latch |
| `SResume`, `ResumePoint`, `FwdFrom` | `btree_ovf_scan_locate_resume` (`btree.c:15470`, called at `btree.c:30848`): route the anchor, walk forward to the first object greater than it | leaf read latch |
| `vis` | snapshot check (`btree.c:31135`); at most one version of an OID is visible; vacuum never removes an object a live snapshot sees | — |
| `Env` | any `OvfDirChain` writer step between scan iterations; removals only of objects the snapshot does not see | — |
| `RemoveSwapFirst` | candidate fix F1: the swap takes the first page's first (smallest) object | — |
| `DFix = "first_page_fallback"` | candidate fix F2: a miss in `btree_ovf_dir_find_oid` also searches the first data page | — |
| `bad`, `stale`, `seen`, `ret`, `dup` | ghosts: assertion / error outcomes, objects left by a crash, structural events reached, objects returned, a double return | — |

`OrderSpec` maps `OvfDirChain` to `OvfOrder`: `np = Len(chain)`, `cont[r] = Range(data[chain[r]])`,
`sep[r]` = the r-th directory entry's separator in chain order (0 without a directory), pages after
`np` empty. Every `OvfDirChain` step is an `OvfOrder` step (`AddFirst`, `Ins`, `SplitIns`,
`GrowRight`, `Rem`, `RemPage`, `Merge`, `Redist`) or leaves the chain unchanged (leaf inserts and
removals).

Callers of the protocol entry points (P11): `btree_ovf_dir_find_oid` <- `btree_find_oid_and_its_page`
(delete, vacuum, undo, unique/FK paths); `btree_ovf_dir_append_object` <- `btree_key_append_object_into_ovf`;
`btree_ovf_compact_chain` <- `xbtree_compact_overflow` (`btree.c:15778`), with its interrupt check between pulls
(each pull is its own system operation, so stopping there is the model's "no more pulls");
`btree_ovf_scan_locate_resume` <- `btree_range_scan_select_visible_oids` only. The scan's other exits
(LIMIT `key_limit_upper`, ISS, MRO, covered index without a hard limit, interrupt) end the scan or never
stop mid-key; they are not modeled because they cannot reach the resume path.

## Properties

| Name | Kind | Statement | Claim |
|---|---|---|---|
| `TypeOK` | invariant | variable types | — |
| `Shape` | invariant | one chain, no empty or overfull page, leaf non-empty while the chain exists | C2 |
| `Sorted` | invariant | the chain is globally OID-ordered | C2, C5 |
| `DirMatch`, `DirSorted` | invariant | directory follows the chain, headers stamped, separators non-descending after entry 0 | C2 |
| `Routable` | invariant | `Find(o)` returns the page of every chain object | C1 |
| `Content` | invariant | leaf and chain hold exactly the live objects, none twice | C4 |
| `NoBad` | invariant | no lookup miss, no directory or `set_separator` assert, no object lost across a crash | C1, C3, C5 |
| `OrderSpec` | refinement | `OvfDirChain` steps are `OvfOrder` steps | C2, C3 |
| `IndInv` (`OvfOrder`) | inductive invariant | order conjuncts `R_shape`, `R_disj`, `R_sorted`, `R_lower`, `R_upper`, `R_mono`; TLAPS-proved; implies `AbsRoutable` | C1, C2, C3 |
| `NoDup`, `ExactlyOnce` | invariant | the scan returns no object twice; when done it returned exactly the visible objects | C6 |
| `NoResumeError` | invariant | the resume never fixes a freed page | C6 |
| `ScanFinishes` | liveness, WF on `SResume` | a stopped scan finishes | C7 |

## Fault model

| Fault | Modeled as |
|---|---|
| error return | not modeled: every structural change runs in one system operation that aborts on error (`log_sysop_abort`, e.g. `btree.c:14753`), leaving the pre-state the model already has |
| interrupt / query cancel | COMPACT checks the interrupt between pulls; each pull is its own system operation, so an interrupt is "no further `PullAt`", which every state allows. A scan's interrupt or LIMIT ends it before any resume |
| lock timeout, deadlock victim | not applicable: the protocol takes latches only (unconditional, top-down leaf -> overflow -> directory) |
| conditional latch failure | not applicable: every fix in the mapped code is `PGBUF_UNCONDITIONAL_LATCH` |
| OOM | not applicable: no allocation on the mapped paths (stack buffers) |
| crash / kill -9 | modeled at the only point where a key operation commits a system operation and then continues: between the halves of the leaf swap (`CrashSwap`, `CrashRecover`). Every other structural change is one system operation (atomic under crash) |
| spurious wakeup | not applicable: no condition wait |
| concurrent DML | modeled: `Insert`, `Remove` of any object between scan iterations, at any point of the structure |
| vacuum | modeled: `Remove` of objects the snapshot does not see, including the leaf swap |
| checkpoint, page flush, page replacement | not applicable: every page is fixed while it is read or written |
| HA log apply | not applicable: a slave replays the same operations through the same code |
| capacity | the scan's stop condition is modeled from the code's buffer checks (`ChainIter`): a stop needs an accepted chain object |

## Mutants

| cfg | Change | Expected | Kills |
|---|---|---|---|
| `OvfDirChain.mutant-no-catch-all` | head entry 0 compared as a real separator (the pre-`5be8a1730` code) | `Routable` violated | C1 |
| `OvfDirChain.mutant-no-step-back` | a miss is final | `Routable` violated | C1 |
| `OvfDirChain.mutant-adv-strict` | directory pages advance only while the next entry 0 is below the OID | `Routable` violated | C1 |
| `OvfDirChain.mutant-grow-right-any` | grow right without checking that the OID exceeds the last | `Sorted` violated | C2 |
| `OvfDirChain.mutant-no-set-sep` | a partial COMPACT move leaves the separator | `Sorted` violated | C3 |
| `OvfDirChain.mutant-swap-keep` | the swap leaves the moved object in the page too | `Content` violated | C4 |
| `OvfDirChain.mutant-no-fallback` | crash between the swap halves, no first-page fallback (the code: fail-before of F2) | `Sorted` violated | C5 |
| `OvfScanResume.mutant-page-resume` | resume from the page after the last page with a visible object (the pre-CBRD-27401 code) | `NoResumeError` violated | C6 |
| `OvfScanResume.mutant-anchor-processed` | anchor on the last processed object instead of the last visible one | `ExactlyOnce` violated | C6 |
| `OvfScanResume.mutant-resume-blocked` | the resume never runs while the leaf holds an object | deadlock: the stopped scan has no step once the writers are done | C7 |

Surviving mutants (the guard is not needed for the properties; reported as questions, not defects):

| Change | Result | Reading |
|---|---|---|
| `split_le`: the new object equal to the split separator goes to the lower half | all invariants hold (147,845 states) | either half keeps the order; `OvfOrder.SplitIns` allows both |
| `no_backoff`: a partial COMPACT move may split a same-OID run | all invariants hold (154,525 states) | the separator still bounds the page from below; the code comment's "strictly greater ... so the separator stays a lower bound" (`btree.c:15372`) is stronger than routing needs; `OvfOrder.Redist` allows `<=` |
| `stop_empty`: a resumed iteration may stop before accepting an object | `ScanFinishes` holds | such a stop changes no variable (same anchor, same resume point), so it is a stutter and `WF(SResume)` still forces a step that progresses; the model cannot express a livelock of empty stops. The code rules it out by the capacity checks (`btree.c:30774`, `30975`: a resumed iteration starts with an empty buffer). C7 is killed by `resume-blocked` instead |

## Witnesses

| cfg | Reached state |
|---|---|
| `OvfDirChain.witness-stepback` | a removal found its object only after stepping back (same-OID run across pages) |
| `OvfDirChain.witness-pullup` | the head directory page emptied and pulled the next page up |
| `OvfDirChain.witness-dirsplit` | a full directory page split |
| `OvfDirChain.witness-dirtail` | a new tail directory page appended |
| `OvfDirChain.witness-partial` | COMPACT moved part of a page and raised its separator |
| `OvfDirChain.witness-merge` | COMPACT merged a page away |
| `OvfDirChain.witness-swap` | the leaf swap moved an overflow object into the leaf |
| `OvfScanResume.witness-compact-while-suspended` | COMPACT moved objects while a scan was stopped in the key |
| `OvfScanResumeTrace.witness-trace-h1a-run2` | the recorded run `traces/h1a-run2.log` is a behavior of `OvfScanResume` |
| `OvfScanResumeTrace.reject-swap-before-pull` | the same run with the swap moved before COMPACT is refused (at the swap: the model moves the anchor, the log a pulled object) |

## Counterexamples and findings

| Id | Cfg | Classification | Runtime |
|---|---|---|---|
| H1 | `OvfScanResume.cfg` (code, `ExactlyOnce`) | **hole, confirmed** — introduced by CBRD-27401 | reproduced twice (below) |
| H2 | `OvfDirChain.crash-swap.cfg` (code, `Sorted`) | **hole, confirmed** — the directory routing (CBRD-24094) cannot find what the crash leaves | reproduced (below) |
| — | first `crash-swap` model put the removed object at the page's end | model error: `btree_record_replace_object` re-inserts it in OID order (`btree.c:38577`); two crash runs with that layout recovered cleanly | 2 runs, `CrashAfterSwap` logged, chain sorted after recovery |
| — | first `OvfScanResume` let a key-start iteration stop with no chain object accepted (anchor NULL) | model error: the key-start check reserves a full overflow page (`btree.c:30774`, `btree.c:29694`), so the first page and any stop need an accepted object; the H1 run with anchor NULL was never reachable | the first H1 attempt stopped before the key instead (trace `n_before=0`) |

**H1 — a range scan loses a visible row when COMPACT and vacuum run while it is stopped in a key.**
Trace (TLC, 9 steps; code steps in brackets): the scan accepts page 1's objects and stops before
page 2 (anchor = page 1's last visible object) [`btree.c:30975`, `30996`]; COMPACT pulls page 2's
prefix into page 1 [`btree_ovf_compact_pull`]; vacuum removes the leaf's only object, so the swap moves
page 1's last object, an unprocessed visible one, into the leaf [`btree.c:11209`]; the resume routes
the anchor and continues in the chain [`btree_ovf_scan_locate_resume`], but the leaf record is never
read again for a partially processed key [`btree.c:30882`]: the moved object is not returned. Before
CBRD-27401 nothing moved an unprocessed object to the end of the first page, which is the comment's
point 3/4 (`btree.c:30812-30837`); COMPACT adds the move. `OvfScanResume.no-compact.cfg` passes.

Runtime (optdebug of `21c6e635d` + scratch instrumentation, fingerprint `025329474e72…`, conf
`parallelism=1`, `index_scan_oid_buffer_pages` default 4): key 0 with 7,400 rows, key 1 built by
CREATE INDEX (pages of 678 objects), leaf reduced to one deleted row, page 1 halved; `SELECT id FROM t
WHERE k <= 1 USING INDEX idx(+)` with an 8 s pause at the resume (`CUBRID_TLA_RESUME_DELAY_MS`), COMPACT
and the vacuum gate opened in the pause. Run 1: 9,973 of 9,974 rows, lost id 1969, `ScanStop
anchor=0|4693|393`, `Pull left=0|4751 nmove=274 ... moved_last=0|4695|496`, `Swap moved=0|4695|496`; run 2
(`traces/h1a-run2.log`): 9,973 of 9,974, lost id 2409. A fresh scan returns all 9,974 rows (the row is in
the leaf): the loss is per scan, the index is intact.

Candidate fix F1 (`Fix = "swap_first"`): the swap takes the first page's first (smallest) object, which
is never above the anchor while the anchor is in the chain, and once the anchor itself is in the leaf
no further swap can happen during the scan. `OvfScanResume.fix-swap-first.cfg` (with `ScanFinishes`)
and `OvfScanResume.scale-versions.cfg` pass. Not built or run on the engine.

**H2 — a crash between the halves of the leaf swap leaves an object vacuum cannot find.** Trace (TLC,
7 steps): leaf object D (inserted into the leaf record, OID above page 2's separator), chain of two
pages; vacuum removes D: the swap puts page 1's last object in the leaf and D into page 1 at its OID
order, i.e. at page 1's end, above page 2 [`btree.c:11312`, `38577`]; the swap's system operation
commits [`btree.c:11345`]; crash before the second half. After recovery the restarted vacuum looks D up:
`btree_ovf_dir_locate` routes it to page 2 (separator <= D), page 2's first object is below D, so no
step back: not found, which vacuum tolerates [`btree.c:36383`]. D stays in page 1, the chain is no
longer OID-ordered and the entry is never vacuumed. The pre-CBRD-24094 linear search scans every page
and would find D (code reading of the legacy loop in `btree_find_oid_and_its_page`; not run on an older
build).

Runtime (same build, crash injected by `CUBRID_TLA_CRASH_AFTER_SWAP` = log flush and `_exit` right after
the swap's commit): table `t5`, D = `1|1351|204` above every chain object; after the master's restart and
a vacuum pass, page 1 still ends with `1|1351|204` while page 2 starts at `1|1348|62`;
`cubrid checkdb -C --check-btree-entries` then aborted the optdebug server in
`vacuum_check_not_vacuumed_rec_header` (`vacuum.c:7455`) on "not vacuumed BTREE record with
oid=1|1351|204 ... delete_id=69, oldest_mvcc_id=70" (core `core.transaction.2277231`, stack through
`btree_range_scan_select_visible_oids`).

Candidate fix F2 (`DFix = "first_page_fallback"`): `btree_ovf_dir_find_oid` searches the first data
page after a miss (the swap only ever writes there). `OvfDirChain.fix-first-page-fallback.cfg` passes
(295,683 states). Not built or run on the engine.

## Dead expressions (pass cfgs)

TLC reports coverage per call site, so a line of an operator body is listed when one of its call sites
never runs under the cfg's constants, even if another call site covers it.

| Lines | Cfgs | Why never evaluated |
|---|---|---|
| `OvfDirChain.tla:172`, `OvfDirChain.tla:173`, `OvfDirChain.tla:174`, `OvfDirChain.tla:177`, `OvfDirChain.tla:178`, `OvfDirChain.tla:179`, `OvfDirChain.tla:180`, `OvfDirChain.tla:181`, `OvfDirChain.tla:182`, `OvfDirChain.tla:183`, `OvfDirChain.tla:184` | main, scale, fix-first-page-fallback | `RemoveObjAt`'s body at the call site the cfg's `CrashSwap` excludes: `SwapDone` and `CrashRecover` (enabled only with `CrashSwap = TRUE`) in main and scale, the plain swap (line 258) in the fallback cfg. The same lines run at `Remove`'s lookup call site (removals, page frees, directory removal: witnesses dirsplit, pullup, swap) |
| `OvfDirChain.tla:250`, `OvfDirChain.tla:251`, `OvfDirChain.tla:252`, `OvfDirChain.tla:253` | main, scale | the crash branch of the leaf swap: `CrashSwap = FALSE` (it runs in `crash-swap` and `fix-first-page-fallback`) |
| `OvfDirChain.tla:255`, `OvfDirChain.tla:256` | main, scale, fix-first-page-fallback | the `swap_keep` mutant branch |
| `OvfDirChain.tla:258` | fix-first-page-fallback | the non-crash swap: that cfg runs with `CrashSwap = TRUE` |
| `OvfDirChain.tla:261`, `OvfDirChain.tla:262` | all OvfDirChain pass cfgs | violation ghost: a removal whose lookup misses its object (`unknown_key`). It would break `NoBad`; correct routing never misses (`Routable`, C1) |
| `OvfDirChain.tla:272`, `OvfDirChain.tla:273`, `OvfDirChain.tla:278`, `OvfDirChain.tla:287` | main, scale | `SwapDone` and `CrashRecover`, enabled only with `CrashSwap = TRUE` (`uncovered-ok` in these cfgs) |
| `OvfDirChain.tla:282`, `OvfDirChain.tla:283`, `OvfDirChain.tla:284`, `OvfDirChain.tla:285` | fix-first-page-fallback | violation ghost: recovery cannot find the swapped-out object (`crash_swap_lost`, H2). It fires in `crash-swap.cfg`; the fallback finds the object |
| `OvfScanResume.tla:114`, `OvfScanResume.tla:115`, `OvfScanResume.tla:116` | fix-swap-first, no-compact, scale-versions | `resume_freed_page`: only the `page_resume` mutant resumes from a saved page (`mutant-page-resume` reaches it) |
| `OvfScanResume.tla:128`, `OvfScanResume.tla:129`, `OvfScanResume.tla:131` | no-compact | `RemoveSwapFirst`: the candidate fix F1, enabled only with `Fix = "swap_first"` |

## Bounds and limits

- `OvfDirChain`: 3 OIDs x 2 versions, page capacity 2, directory page capacity 2, leaf capacity 1 (the
  leaf record holds one object; a swap happens whenever it is removed with a chain); scale: 4 OIDs x 2.
  `OvfScanResume`: 4 OIDs x 1 version (scale: 3 x 2 with the fix). `OvfOrder`: 3 pages, 2x2 objects
  (scale 4 pages, 3x2); TLAPS: any number of pages and objects.
- TLAPS covers C1-C3 on `OvfOrder` (order invariants); they reach `OvfDirChain` through `OrderSpec`, checked
  by TLC inside its bounds. The directory mechanics (binary search, directory page split / pull-up,
  header stamps) are TLC only. C4-C7 are TLC only.
- The model trusts the in-page search to find an object in a sorted page (`InPage` past the early outs),
  and that every writer holds the leaf write latch for its whole operation.
- Not modeled: unique indexes (legacy chains), the loader's bulk chain construction (the trace starts from
  a loaded state), multi-volume OIDs beyond the ordering, MVCC info updates in place (no structural effect).

## Result

- 2026-11-06, `tools/tla/tla-check --workers 16 --stretch 4 docs/tla/CBRD-24094-ovf-dir`:
  **`RESULT: FAILED (2)`**: exactly the code cfgs of the confirmed holes, `OvfDirChain.crash-swap`
  (H2, `Sorted`, depth 7) and `OvfScanResume` (H1, `ExactlyOnce`, depth 12). Every other cfg is PASS.
  Run dir `.git_ignored_dir/scratch/tla/CBRD-24094-ovf-dir-20261106-020658-2359677`.
- Pass cfgs (states generated/distinct, depth):

  | cfg | states | depth |
  |---|---|---|
  | `OvfDirChain` (with `PROPERTY OrderSpec`) | 1,064,087 / 147,845 | 33 |
  | `OvfDirChain.scale-page-cap-3` | 196,027 / 27,511 | 24 |
  | `OvfDirChain.fix-first-page-fallback` (F2) | 1,359,763 / 295,683 | 36 |
  | `OvfOrder` | 4,498 / 201 | 6 |
  | `OvfOrder.scale-4-pages` | 167,025 / 3,460 | 10 |
  | `OvfOrder.inductive-indinv` | 3,420 / 150 | 1 |
  | `OvfScanResume.no-compact` (with `ScanFinishes`) | 95,916 / 36,651 | 30 |
  | `OvfScanResume.fix-swap-first` (F1, with `ScanFinishes`) | 341,080 / 124,043 | 35 |
  | `OvfScanResume.scale-versions` (F1) | 71,261,695 / 15,733,543 | 45 |

- 10 mutants and 8 witnesses PASS (each reaches its expected error); trace witness `h1a-run2` accepted
  (13 states, `i = 8`), `reject-swap-before-pull` refused.
- TLAPS `OvfOrder_proofs.tla`: 1,257 obligations, 1,257 proved, 0 OMITTED (tlapm 1.4.5, stretch 4). The same
  file also proves 1,257/1,257 on the tlapm 1.6.0-pre candidate of ADR 0045. The temporal conclusion
  `Spec => []IndInv` is left to INV1 (cubrid-tla P2, 1.4.5).
- Spec sha256: `OvfDirChain.tla` ac0b30b7…, `OvfOrder.tla` ac08f81b…, `OvfOrder_proofs.tla` 5527e8d7…,
  `OvfScanResume.tla` 66436d21…, `OvfScanResumeTrace.tla` 07351957…, `OvfScanResumeTraceData.tla`
  79b37153… (full lines in the run's `summary.txt`).
- Engine: develop `21c6e635d`; runtime reproductions and the trace on the optdebug build of that sha
  with scratch instrumentation (worktree `tla-cbrd24094-21c6e635d`, uncommitted), libcubrid fingerprint
  `025329474e72…`.
