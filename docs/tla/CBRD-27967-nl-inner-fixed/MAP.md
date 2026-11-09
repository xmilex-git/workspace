# NlInnerFixed — page latches of a nested-loop chain whose innermost heap scan is fixed (CBRD-27967, PR 8438)

Design model, settled with the user in a grilling round on 2026-11-09, for a change carried by
CUBRID/cubrid#8438 (CBRD-27967; worktree `~/dev/cubrid-worktree/CBRD-27967`, commit `5bc4812c1` on `43c83d970`).
The grilling started from PR 8398 (CBRD-27926); the user moved the change to PR 8438 the same day.

Defect (measured on release develop `2d928e34b` and on PR 8398's head `175c6e716`): in
`SELECT /*+ ORDERED USE_NL(f) */ COUNT(*) FROM pc_corr c JOIN pc_fact f ON f.g=c.a WHERE c.b=7 AND c.c=7`
(outer index scan on `pc_corr(b)`, inner sequential heap scan of `pc_fact`, 206 pages, 20,000 rows) the inner
scan's trace reads `fetch: 161,648, readrows: 160,000` = 8 passes × 206 pages + one fix per row read; the same
table scanned alone fetches 206. `qexec_execute_mainblock_internal` (`query_executor.c` 22214-22267) turns the
fixed scan off for the whole chain when any spec is an index scan ("this is legacy and should be reconsidered"),
and the cached scan is allowed on the level-0 spec only (22312), so the inner `heap_next_internal`
(`heap_file.c:7666`) fixes its page for every row (SA gdb count: 4,044 fixes at that site for 4,000 rows + 44 pages).

## Decisions (user, 2026-11-09)

| # | Decision |
|---|---|
| D1 | The change goes into one existing PR, not a new one: PR 8438 (CBRD-27967). |
| D2 | The innermost sequential heap scan of a scan chain is a fixed scan even when another spec of the chain is an index scan. A heap scan that is not innermost is a cached scan (page copy, latch released). Index scans keep fixing per row. |
| D3 | The innermost fixed scan releases its page before control moves to another join level: after an early stop (a semi or anti join's first match, an outer join's single row) the scan's next call returns S_END and releases the page there. |
| D4 | No environment gate; always on. |
| D5 | Statements whose SP changes rows while scanning (CBRD-27590 cached scan misses the change, CBRD-27591 self latch wait) are left to CUBRID/cubrid#8182 (CBRD-27579: an SP called from SQL may not run DML); no gate here. |

## Claim and sources

| # | Claim | Source |
|---|---|---|
| C1 | No two or three threads wait for each other's page latches (no latch wait cycle). | `query_executor.c` 22216-22218 ("Fixed cannot be allowed while new scans start which also need to fix pages. This may lead to page deadlocks."), D2 |
| C2 | While the query works at another level (the outer index scan, the outer row's heap lookup, a middle row), the innermost scan holds no page. | D3 (the user's claim "어쨌든 fix를 놓고 join level을 이동") |
| C3 | One innermost pass fixes each of its pages once; one middle pass fixes the middle page once (develop: once per row). | D2, the defect above |
| C4 | A middle row read from a page copy reads the copy its own pass took. | D2 (a restarted scan may not read the previous outer row's copy: a header page copy's next link can name a page vacuum has since removed) |
| C5 | Every thread finishes (with weak fairness on each thread). | C1's liveness counterpart |

## Refinement map (model -> code)

| Model | Code | One step because |
|---|---|---|
| `RLeaf` | `btree_range_scan`: fixes the leaf, collects OIDs, unfixes the leaf and the parent before returning (`btree.c:30911-30936`) | the leaf is never held across the return |
| `RLookup`, `RLookupYield`, `RRefix` ("refix") | `scan_next_index_lookup_heap` -> `heap_get_visible_version` -> `pgbuf_ordered_fix` of the outer row's page (`PGBUF_ORDERED_HEAP_NORMAL`); the ordered fix unfixes held heap pages of a higher rank when it would wait, and refixes them while it holds the requested page | one call; the yield and refix are the ordered fix's own steps |
| `RMStart` | `scan_reset_scan_block` of the middle heap scan (`scan_manager.c:4337`); D2 adds `VPID_SET_NULL (&scan_cache->local_cache_vpid)` | |
| `RMRow`, `RMRowYield`, "mrefix" | `heap_next_internal` on a cached scan: page in the local copy (`heap_file.c:7651-7657`) or fix, copy (`7734`), unfix (`7951`) | the copy and unfix happen before the row is returned (assert at `heap_file.c:7955`) |
| `RIStart`, `RIStartYield` | `heap_next_internal` from a null OID: the header page first (`heap_file.c:7612-7617`); an old page still held is replaced as the old watcher and unfixed after the new fix (`7640-7670`) | |
| `RIRow` | a row of the held page (fixed: `cache_last_fix_page`) or fix-read-unfix (develop) | |
| `RINextPage` | `heap_vpid_next` + fix of the next page before the held one is released (`heap_file.c:7700-7722`, `OLD_PAGE_PREVENT_DEALLOC`) | |
| `RIEnd` | the chain's end: S_END with no page held (`heap_file.c:7713-7720`) | |
| `RIEarly` | the scan stops at its first match: `scan_handle_single_scan` sets `single_fetched` (QPROC_SINGLE_INNER: NL semi/anti inner; QPROC_SINGLE_OUTER), and the executor sets it for a memoized or surviving outer (`query_executor.c:12005`, `12009`, `12096`) | |
| `RIBack` | D3: `scan_handle_single_scan` (`scan_manager.c`), on the S_END a `single_fetched` scan returns without reading (QPROC_SINGLE_INNER / QPROC_SINGLE_OUTER), unfixes `scan_cache->page_watcher`; develop keeps the page until the next pass's `heap_next` (`Mutant = "no-reset-unfix"`). The reset itself comes too late: SA gdb on the defect query shows the order outer `scan_next_scan` -> inner `scan_reset_scan_block` -> inner rows, so the outer moves before the inner is reset | |
| `RONext` | the next outer row; at the query's end `heap_scancache_end` unfixes a held page | |
| `WStep` | a DML: the heap page (`locator_*` -> `heap_*`) then its index entry (`btree_*`), modeled with the heap page still held (the worst order); a relocation over two pages in rank order (`pgbuf_ordered_fix`); write latches only | |
| `VStep` | vacuum: the index, then the heap pages, one page at a time | |
| `WProg = "btree-holds-heap"` | not code: a heap page requested while a leaf is held, an edge no code takes (btree code unfixes before it reads the heap, `btree.c:26538`) | |

## Fault table

| Fault | Modeled as |
|---|---|
| error return, interrupt | not modeled: every error path unfixes through `heap_scancache_end` / `scan_end_scan`; a query that fails releases its pages before any other level runs |
| lock timeout, deadlock victim | not modeled as a latch wait: UPDATE/DELETE scans are never fixed (`COMPOSITE_LOCK`, `storage_common.h:374`, `query_executor.c:22219`); a SELECT ... FOR UPDATE row lock is tried conditionally and, when refused, the page is unfixed before the unconditional wait (`locator_lock_and_get_object_internal`, `locator_sr.c:13817-13840`), so no lock wait happens under a page latch |
| conditional latch failure | not modeled: the scans fix unconditionally; the ordered fix's conditional first try is part of `Yields` |
| OOM | not applicable: no allocation between the fix and the unfix |
| crash | not applicable: read-only scan |
| concurrent DML | `WStep` (heap, index, relocation, outer heap) |
| vacuum | `VStep` |
| page flush, replacement | not applicable: a fixed page is not a victim; flushing takes no page latch |
| HA log apply | `WStep` stands for the applier's DML |
| nested statement (SP) | D5: left to CUBRID/cubrid#8182; an SP's DML on a page the fixed scan holds would wait for its own latch (CBRD-27591) |
| a subquery run for each row of the innermost scan (a correlated subquery on its node, an uncorrelated one evaluated in a reguvar) | not modeled: excluded by the code. The new selection keeps the innermost scan unfixed when its node has a `dptr_list` or an `aptr_list` entry flagged `XASL_LINK_TO_REGU_VARIABLE` (`qexec_execute_mainblock_internal`), as the top node's checks already do for the whole chain; such a scan is a cached scan (measured: 161,648 -> 3,288 fetches) |
| temp list file writes of the parent while the inner page is held | not modeled: temp pages are private to the transaction; the single-table fixed scan already writes its list file under a held page |

## Mutants

| cfg | Change | Expected | Kills |
|---|---|---|---|
| `mutant-inner-unfixed` | develop: the innermost scan fixes per row | `IFixBound` | C3 |
| `mutant-middle-unfixed` | develop: the middle scan fixes per row | `MFixBound` | C3 |
| `mutant-no-reset-unfix` | the reset after an early stop keeps the page (develop's `scan_reset_scan_block`) | `LevelRelease` | C2 |
| `mutant-keep-copy` | the middle scan's reset keeps `local_cache_vpid` | `NoStale` | C4 |
| `mutant-btree-holds-heap` | no reset release, and a writer requests a heap page while holding a leaf | `NoWaitCycle` | C1 |
| `mutant-no-ordered` | no reset release, and the heap fix waits without yielding higher-ranked pages | `NoWaitCycle` | C1 |
| `mutant-liveness-btree-holds-heap` | as `mutant-btree-holds-heap`, checked for termination under weak fairness (`FairSpec`, `AllDone`) | deadlock | C5 |

C1 holds by either of two protections: the reset release (D3, C2), and the code's latch orders (the ordered fix
among heap pages, no btree-to-heap request). Each removed alone leaves C1 true: `btree-holds-heap` (D3 kept) and
`code-keep-held` / `code-keep-held-hclow` (the code's latch orders kept; 42,091 and 43,159 distinct states, both ranks of the outer heap) pass; the mutants remove both (cubrid-tla P74).

## Witnesses

| cfg | Outcome reached |
|---|---|
| `witness-early` | an early stop |
| `witness-copy-read` | a middle row read from the copy |
| `witness-w-waits-r`, `witness-v-waits-r` | a writer / vacuum waits for a page the reader holds |
| `witness-restart-held`, `witness-yield` | (with `no-reset-unfix`) a restart with a page held, an ordered-fix yield |

## Dead expressions

Pass cfgs of the design (`NlInnerFixed`, `hclow`, `liveness`, `scale-no3`, `btree-holds-heap`) leave these
unevaluated; each is the design's own consequence or a mutant-only branch:

- `NlInnerFixed.tla:112`, `NlInnerFixed.tla:113`, `NlInnerFixed.tla:125`, `NlInnerFixed.tla:129`, `NlInnerFixed.tla:140`, `NlInnerFixed.tla:141`, `NlInnerFixed.tla:143`, `NlInnerFixed.tla:144`, `NlInnerFixed.tla:157`, `NlInnerFixed.tla:166`, `NlInnerFixed.tla:174`, `NlInnerFixed.tla:175`, `NlInnerFixed.tla:176`: the ordered fix's yield and refix (`YieldTo`, `RLookupYield`, the refix branch of `RLookup`, `RRefix`,
  `RMRowYield`, the "mrefix" branch of `RMRow`, `RIStartYield`), and `NlInnerFixed.tla:180`, `RIStart` with an innermost page still
  held. Under C2 R holds no innermost page when it requests a page of another level (`RIEnd` and `RIBack` release
  it first), and inside the innermost pass it requests its pages in rank order (B1, then B2), so no request ever
  has a higher-ranked page to yield and no restart finds a page held. They fire once the release is removed:
  `witness-yield` and `witness-restart-held` (`Mutant = "no-reset-unfix"`), `code-keep-held-hclow` (the outer
  lookup's yield, which needs the outer heap ranked below the inner one), `mutant-no-ordered`. In the code the
  same branches are `pgbuf_ordered_fix`'s unfix-and-refix of held watchers (`page_buffer.c` `pgbuf_ordered_fix_debug`)
  and `heap_next_internal`'s replacement of a still-held page (`heap_file.c:7640-7670`), both kept for the other
  scans that use them.
- `NlInnerFixed.tla:185`, `NlInnerFixed.tla:192`, `NlInnerFixed.tla:209`: develop's per-row fix of the innermost scan (`RIStart`, `RIRow`, `RINextPage` with `IFixed` false), only under
  `Mutant = "inner-unfixed"` (`mutant-inner-unfixed`).
- `NlInnerFixed.tla:220`: the reset that keeps the page (`RIBack` without `ResetUnfix`), only under `Mutant = "no-reset-unfix"`
  (`mutant-no-reset-unfix`, `code-keep-held`).

`code-keep-held` and `code-keep-held-hclow` (the release removed, the code's latch orders kept) leave `NlInnerFixed.tla:185`, `NlInnerFixed.tla:192`, `NlInnerFixed.tla:209` and
`NlInnerFixed.tla:220` dead for the same reasons (develop's per-row branches; the release is what they remove), and `code-keep-held`
also `NlInnerFixed.tla:112`, `NlInnerFixed.tla:113`, `NlInnerFixed.tla:125`, `NlInnerFixed.tla:129`: with `HcLow = FALSE` the outer heap ranks above every inner page, so the lookup never yields; the hclow
cfg fires it.

## Bounds

`NO = 2` outer rows, `RPP = 2` rows per page, a two-page inner chain, one middle page, `EarlyStop`, both ranks of
the outer heap (`HcLow`, `hclow` cfg); scale `NO = 3`. The Apalache check (`NlInnerFixedInd.apalache-indinv`)
leaves `NO` and `RPP` over every natural >= 1 and `EarlyStop`, `HcLow` open; the thread and page sets are fixed.

trace-exempt: design before implementation (the record run below checked the design before `5bc4812c1` was
written). The implementation now exists, so trace validation (a TLATRACE run of the fix, unfix, early-stop release
and copy events on an instrumented build) is still owed; until then the implementation is tied to the model by the
runtime checks in Result.

## Result

- 2026-11-09, `tools/tla/tla-check docs/tla/CBRD-27926-nl-inner-fixed` (the directory's name before it moved to
  CBRD-27967; spec files unchanged since): `RESULT: OK`, run dir
  `.git_ignored_dir/scratch/tla/CBRD-27926-nl-inner-fixed-20261109-182424-1917693`.
- TLC (distinct states / depth): main 14,535 / 67, `hclow` 14,535 / 67, `liveness` 14,535 / 67, `scale-no3` 23,123 / 89,
  `btree-holds-heap` 6,108 / 59, `code-keep-held` 42,091 / 67, `code-keep-held-hclow` 43,159 / 67; mutants
  `inner-unfixed` (IFixBound, 228), `middle-unfixed` (MFixBound, 206), `no-reset-unfix` (LevelRelease, 125),
  `keep-copy` (NoStale, 1,496), `btree-holds-heap` (NoWaitCycle, 1,084), `no-ordered` (NoWaitCycle, 1,186),
  `liveness-btree-holds-heap` (deadlock, 1,563); witnesses early, copy-read, restart-held, v-waits-r, w-waits-r,
  yield reached.
- Apalache `NlInnerFixedInd.apalache-indinv`: IndInv inductive for every `NO >= 1`, `RPP >= 1`, both `EarlyStop`,
  both `HcLow` (1,716 s).
- TLAPS 요청 없음.
- spec sha256: `NlInnerFixed.tla` 575ced0685bc0e7b74c227222ad88acc2b1a7601d624180d4db47ff0a5240b3f,
  `NlInnerFixedInd.tla` 4bd7af33c00ef277944a060a2ca74baa0b56ca7b2d8c61454344f00b77088719.
- Runtime (release and optdebug of `5bc4812c1`, fast-cs-csql, 9 NL queries, 534 result lines): answers equal
  develop `2d928e34b` (0 differing lines). Inner fetch, develop -> change: 161,648 -> 1,648 (index outer, 206-page
  inner, 8 passes); 1,374,008 -> 14,008 (range); anti / outer join inner 231 -> 93, 240 -> 96; three-level middle
  heap 2,416 -> 16; inner with a correlated subquery (cached, not fixed) 161,648 -> 3,288. SA gdb: the early-stop
  release (`scan_handle_single_scan`) ran 3 times on an anti and a semi join.
- CTP on optdebug `CUBRID-CBRD-27967` (TC `tc/pr-8438`): sql 17,747 / 17,747, medium 975 / 975, 0 cores.
