# Parallel index scan leaf dispatcher — every leaf once, no freed leaf fixed, against splits, vacuum merges and page reuse

Code: develop `e98bdd885`, `src/query/parallel/px_scan/index/px_scan_index_leaf_page_dispatcher.cpp`
(below: `dispatcher.cpp`) and `src/storage/btree.c`. The spec the claims come from is spread over
CBRD-26722 (parallel scan over index, heap and list), CBRD-27100 (when the index path runs),
CBRD-26863 (index scan vs concurrent DML/DDL), CBRD-27737 (vacuum merges the next leaf before the
scan fixes it) and CBRD-27738 (descending scan vs a left-leaf split). Each claim is what those
issues' Expected Results require of every run, not of one test.

## Claim and sources

| # | Claim | Source |
|---|---|---|
| C1 | Every key present in the index for the whole scan is returned exactly once, ascending and descending, while other transactions insert (splits, page reuse) and vacuum deletes (merges, page deallocation). | CBRD-26722 (same result as the serial scan), CBRD-27738 Expected Result (`2097152 / 21990243041280` on every run) |
| C2 | The scan finishes and neither it nor the writers deadlock (latches are taken top-down and left to right). | CBRD-26863, CBRD-27737 |
| C3 | No worker or the dispatcher fixes a deallocated leaf as a live one, including when a worker stops early. | CBRD-27737 Expected Result (the server keeps running; core at `pgbuf_fix_debug` on a freed page) |

## Refinement map (model -> code)

| Model | Code | One step because |
|---|---|---|
| `W_ask` + `W_lock` | `dispatcher.cpp:231 lock_holding`: a held leaf that is not the frontier is released before waiting for `m_leaf_mutex`; the frontier's holder spins on `try_lock` | the frontier check and the unfix are one thread's actions under its own latch |
| `W_dispatch` | `dispatcher.cpp:287 dispatch_next_leaf`, under `m_leaf_mutex` | the mutex |
| `D_root`, `D_leaf` | `dispatcher.cpp:39 descend_to_first_leaf`: root then child latch-coupled, the leaf handed out | one latch acquisition per step |
| `D_fix_next` | `dispatcher.cpp:375` `pgbuf_fix (m_current_leaf_vpid, OLD_PAGE)` of the saved right link, frontier still latched | one fix |
| `D_fix_prev` | `dispatcher.cpp:517 fix_prev_leaf`: `OLD_PAGE_MAYBE_DEALLOCATED` fix, trusted only if `next_vpid == m_last_leaf_vpid` (line 533) | one fix plus a header read under its latch |
| `D_saved` | `dispatcher.cpp:541 resume_after_last_key` -> `btree.c:19384 btree_locate_key_from_saved_leaf` (saved leaf, LSA unchanged) | one fix |
| `D_reroot`, `D_reroot_leaf` | the same function's descent from the root for `m_last_key` | latch-coupled descent |
| `D_desc_take` | `dispatcher.cpp:458 save_last_leaf` (VPID, LSA, smallest key) | under the mutex |
| `D_publish` | `dispatcher.cpp:274 get_next_page_with_fix`: `m_frontier.store (chain_goes_on ? out_page : nullptr)`; the worker's previous leaf released when the new one is held | under the mutex |
| `W_stop` | `dispatcher.cpp:255 release_leaf` (LIMIT, error, reset): the frontier's holder ends the chain under the mutex; `dispatcher.cpp:616 signal_chain_ended` ends it the same way at a range's upper bound | under the mutex |
| `W_read` | `px_scan_index_leaf_slot_walker.cpp scan_next_slot` over the held leaf | the leaf's read latch |
| writer insert/split | `btree.c:32273 btree_split_node_and_advance`: root X, leaf X, then its right neighbour; the upper keys move to a fresh right leaf (`file_alloc`, lowest free page) | latches held until the split is applied |
| writer delete/merge | `btree.c:35699 btree_merge_node_and_advance`: parent, the left leaf, the emptied right leaf, its right neighbour, all X; the right leaf is merged into the left and `file_dealloc`ed | same |
| `fixFreed` | ghost: a fix of a page that is not in use, as a live leaf | — |
| `readCnt` | ghost: times each key was returned | — |

`PxIndexFrontier.tla` abstracts the ascending frontier rule (C3) from this model; the ascending
cfgs check `FrontierSpec` (`PxIndexLeafDispatch` refines `PxIndexFrontier`) with

| Abstract | Concrete |
|---|---|
| `started` | `descentDone` |
| `frontier` | `NoPage` once `ended`; the publishing worker's `out` between `D_fix_next` and `D_publish`; else `frontier` |
| `current` | `NoPage` before the descent or once `ended`; else `current` |
| `protected` | the frontier is read-latched by some worker |
| `inUse`, `nxt`, `fixFreed` | the same |
| `Mutant` | `release_frontier` when the concrete mutant is; else `none` |

## Properties

| Name | Kind | Statement | Claim |
|---|---|---|---|
| `TypeOK` | invariant | variable types | — |
| `StableOnce` | invariant | when every worker is done (none stopped early), each stable key was returned exactly once | C1 |
| `NoStableDuplicate` | invariant | no stable key is returned twice, at any time | C1 |
| `ScanFinishes` | liveness, WF per process | every worker reaches Done | C2 |
| (deadlock check) | TLC | no reachable state without a successor before the end | C2 |
| `NoFreedFix` | invariant | no freed leaf is fixed as live | C3 |
| `FrontierSpec` | refinement | ascending steps are `PxIndexFrontier` steps | C3 |
| `FInv` | inductive invariant of `PxIndexFrontier` | implies `NoFreedFix`; TLAPS-proved for any finite set of leaves | C3 |

## Fault model

| Fault | Modeled as |
|---|---|
| concurrent INSERT | writer `either` branch 1: the key into its leaf, a split when the leaf is full, a fresh page from the free pool (reuse of a freed page) |
| vacuum / DELETE | writer branch 2: a churn key out; when its leaf empties, a merge into the left leaf and `file_dealloc` |
| a worker stops early (LIMIT, error, interrupt) | `W_ask` -> `W_stop` when `EarlyStop` |
| a worker is slow / the dispatcher mutex is contended | any interleaving; `W_lock` spins as the code does |
| page reuse | `X_split_alloc` picks any free page, including the one a merge just freed |
| crash / kill -9 | not modeled: a scan is read-only and dies with the server |
| more than one key range, overflow OID chains, unique stats | not modeled (see Bounds and limits) |

## Mutants

| cfg | Change | Expected | Kills |
|---|---|---|---|
| `PxIndexLeafDispatch.mutant-trust-prev-link` | descending: the saved left link is fixed and used without the back-link check (before CBRD-27738) | `StableOnce` violated | C1 |
| `PxIndexLeafDispatch.mutant-merge-right-first` | a merge latches the right leaf before the left one | deadlock | C2 |
| `PxIndexLeafDispatch.mutant-release-frontier` | the frontier's holder releases it before its right leaf is fixed (before CBRD-27737) | `NoFreedFix` violated | C3 |
| `PxIndexLeafDispatch.mutant-stop-keeps-chain` | a worker that stops on the frontier releases it without ending the chain | `NoFreedFix` violated | C3 |
| `PxIndexFrontier.mutant-release-frontier` | the abstract release | `NoFreedFix` violated | C3 |

## Findings

| # | Finding | Evidence |
|---|---|---|
| H2 | Descending, `fix_prev_leaf` trusts the saved left link by VPID only (`dispatcher.cpp:533`). When the last leaf handed out (C) is merged into its left neighbour L, freed, and L's next split reuses C's page, L links "back" to the reused page and the dispatcher hands out L although the upper keys moved to the reused page were never returned. The serial scan re-checks the key against C (`btree.c:30142 btree_range_scan_descending_fix_prev_leaf`). | `PxIndexLeafDispatch.desc.cfg`: `StableOnce` violated. Runtime on the probe build (below): 474416 / 1125355077360 returned instead of 474552 / 1126000376280; 136 stable rows missed; TLATRACE `btree_merge left=13744 right=13742`, `btree_alloc page=13742`, `link_trusted last=changed`. |
| H2 fix (candidate) | also require the last leaf to be in use with its saved LSA, fixed left to right as the serial scan does (`Fix = "check_last_lsa"`) | `desc-fix.cfg` and `desc-fix-early-stop.cfg` pass |

## Witnesses

| cfg | Reached state |
|---|---|
| `PxIndexLeafDispatch.witness-merged` | a leaf was merged away while a worker was scanning |
| `PxIndexLeafDispatch.witness-split` | a split allocated page 4 while a worker was scanning |

## Dead expressions (pass cfg)

Line numbers are in the translated module.

| Line | Why never evaluated |
|---|---|
| PxIndexLeafDispatch.tla:457, PxIndexLeafDispatch.tla:486, PxIndexLeafDispatch.tla:487, PxIndexLeafDispatch.tla:488, PxIndexLeafDispatch.tla:519, PxIndexLeafDispatch.tla:520, PxIndexLeafDispatch.tla:521, PxIndexLeafDispatch.tla:522, PxIndexLeafDispatch.tla:523, PxIndexLeafDispatch.tla:524, PxIndexLeafDispatch.tla:526, PxIndexLeafDispatch.tla:527, PxIndexLeafDispatch.tla:528, PxIndexLeafDispatch.tla:530, PxIndexLeafDispatch.tla:531, PxIndexLeafDispatch.tla:532, PxIndexLeafDispatch.tla:533, PxIndexLeafDispatch.tla:534, PxIndexLeafDispatch.tla:535, PxIndexLeafDispatch.tla:536, PxIndexLeafDispatch.tla:560, PxIndexLeafDispatch.tla:561, PxIndexLeafDispatch.tla:562, PxIndexLeafDispatch.tla:571, PxIndexLeafDispatch.tla:573, PxIndexLeafDispatch.tla:574, PxIndexLeafDispatch.tla:575, PxIndexLeafDispatch.tla:576, PxIndexLeafDispatch.tla:577, PxIndexLeafDispatch.tla:579, PxIndexLeafDispatch.tla:580, PxIndexLeafDispatch.tla:582, PxIndexLeafDispatch.tla:583, PxIndexLeafDispatch.tla:584, PxIndexLeafDispatch.tla:585, PxIndexLeafDispatch.tla:586, PxIndexLeafDispatch.tla:587, PxIndexLeafDispatch.tla:588, PxIndexLeafDispatch.tla:595, PxIndexLeafDispatch.tla:596, PxIndexLeafDispatch.tla:597, PxIndexLeafDispatch.tla:598, PxIndexLeafDispatch.tla:599, PxIndexLeafDispatch.tla:607, PxIndexLeafDispatch.tla:608, PxIndexLeafDispatch.tla:609, PxIndexLeafDispatch.tla:610, PxIndexLeafDispatch.tla:611, PxIndexLeafDispatch.tla:612, PxIndexLeafDispatch.tla:613, PxIndexLeafDispatch.tla:614, PxIndexLeafDispatch.tla:615 | descending-only paths (`D_fix_prev`, the saved leaf, the reroot, `D_desc_take`, `W_retry`), dead in the ascending cfgs; the descending cfgs evaluate them, except the rows below |
| PxIndexLeafDispatch.tla:436, PxIndexLeafDispatch.tla:437, PxIndexLeafDispatch.tla:438, PxIndexLeafDispatch.tla:439, PxIndexLeafDispatch.tla:456, PxIndexLeafDispatch.tla:490, PxIndexLeafDispatch.tla:499, PxIndexLeafDispatch.tla:500, PxIndexLeafDispatch.tla:501, PxIndexLeafDispatch.tla:502, PxIndexLeafDispatch.tla:503, PxIndexLeafDispatch.tla:504, PxIndexLeafDispatch.tla:505, PxIndexLeafDispatch.tla:506, PxIndexLeafDispatch.tla:507, PxIndexLeafDispatch.tla:508, PxIndexLeafDispatch.tla:646, PxIndexLeafDispatch.tla:647, PxIndexLeafDispatch.tla:661, PxIndexLeafDispatch.tla:662 | ascending-only paths (`W_lock` releasing a leaf that stopped being the frontier, `D_fix_next`, the frontier's release at `W_stop` and `W_end`), dead in the descending cfgs: there the frontier is always `NoPage` and `W_ask` releases every held leaf |
| PxIndexLeafDispatch.tla:499 | also the ghost `fixFreed' = TRUE` that flags a C3 violation; dead in every cfg where C3 holds (fires in the `mutant-release-frontier` and `mutant-stop-keeps-chain` cfgs) |
| PxIndexLeafDispatch.tla:419, PxIndexLeafDispatch.tla:420, PxIndexLeafDispatch.tla:649, PxIndexLeafDispatch.tla:650, PxIndexLeafDispatch.tla:651, PxIndexLeafDispatch.tla:652, PxIndexLeafDispatch.tla:653, PxIndexLeafDispatch.tla:654 | `W_stop`, the early stop: dead in the cfgs with `EarlyStop = FALSE`; `early-stop.cfg` and `desc-fix-early-stop.cfg` evaluate it |
| PxIndexLeafDispatch.tla:526, PxIndexLeafDispatch.tla:527, PxIndexLeafDispatch.tla:528 | descending restart when nothing was handed out yet: the last leaf handed out always holds a key (only the first leaf can empty, and handing out the first leaf ends the scan); unreachable with one key range |
| PxIndexLeafDispatch.tla:530, PxIndexLeafDispatch.tla:531, PxIndexLeafDispatch.tla:545, PxIndexLeafDispatch.tla:546, PxIndexLeafDispatch.tla:547, PxIndexLeafDispatch.tla:548, PxIndexLeafDispatch.tla:549, PxIndexLeafDispatch.tla:550, PxIndexLeafDispatch.tla:551, PxIndexLeafDispatch.tla:552 | `D_saved`, resume from the saved leaf with its LSA unchanged: every split or merge that breaks the left leaf's link to the last leaf C also rewrites C's prev link (`btree.c:24083 btree_set_vpid_previous_vpid`, logged), so C's LSA has changed and the dispatcher reroots. In the code `btree_locate_key_from_saved_leaf`'s unchanged branch is reached only through events outside this model (the fixed page is no longer a valid leaf, an error) |
| PxIndexLeafDispatch.tla:582, PxIndexLeafDispatch.tla:583, PxIndexLeafDispatch.tla:595, PxIndexLeafDispatch.tla:596 | the reroot ending the chain: the leaf at the last key holds nothing below it and has no left neighbour; it needs an emptied first leaf into which a one-churn-key leaf, already handed out, was merged; the stable key 2 in the first leaf's range rules it out (dead also with `WriterOps = 4` and `5`) |
| PxIndexLeafDispatch.tla:769, PxIndexLeafDispatch.tla:800 | `merge_right_first` mutant branches of `X_del_leaf` and `X_del_right` |
| PxIndexFrontier.tla:61, PxIndexFrontier.tla:62 | `Unprotect`: release mutant only |

## Bounds and limits

- TLC: 2 workers, 4 pages, keys {1..5} with stable keys {2, 4}, a leaf capacity of 1 key, 3 writer
  operations; the scale cfg runs 3 workers and 4 writer operations. TLAPS covers C3's frontier rule
  for any finite set of leaves (`PxIndexFrontier_proofs.tla`); C1 is checked by TLC only.
- C2 is checked by TLC only (no PTL back end for TLAPS on this host).
- One key range over the whole index: `m_current_range_idx`, multi-range descents, overflow OID
  chains (CBRD-26863) and the unique-stats table (CBRD-27367) are outside this model.
- The model trusts `file_alloc`/`file_dealloc` and the page buffer: a fix of a freed page is a ghost
  flag, not a crash.

## Result
2026-11-05, `tools/tla/tla-check --workers 8 docs/tla/parallel-scan/index`: **RESULT: FAILED (1)** —
the one failure is `PxIndexLeafDispatch.desc` (the code, descending): `StableOnce` violated at
depth 44 (H2). Every other cfg ends as expected. Run dir
`.git_ignored_dir/scratch/tla/index-20261105-204710-1947472`.

| cfg | Result | Distinct states | Depth |
|---|---|---|---|
| `PxIndexFrontier` | pass | 1,638 | 3 |
| `PxIndexFrontier.inductive-finv` | pass (FInv inductive) | 212 | 1 |
| `PxIndexFrontier.scale-5-leaves` | pass | 14,682 | 3 |
| `PxIndexFrontier.mutant-release-frontier` | `NoFreedFix` violated (killed) | 4,291 | 5 |
| `PxIndexLeafDispatch` (ascending, refines `PxIndexFrontier`) | pass | 112,768 | 54 |
| `PxIndexLeafDispatch.early-stop` | pass | 217,862 | 54 |
| `PxIndexLeafDispatch.scale-3-workers` | pass | 4,107,387 | 64 |
| `PxIndexLeafDispatch.desc` | **`StableOnce` violated (H2)** | 115,876 | 44 |
| `PxIndexLeafDispatch.desc-fix` | pass | 149,778 | 65 |
| `PxIndexLeafDispatch.desc-fix-early-stop` | pass | 285,588 | 65 |
| `mutant-release-frontier` / `mutant-stop-keeps-chain` | `NoFreedFix` violated (killed) | 9,735 / 18,205 | 22 / 24 |
| `mutant-trust-prev-link` | `StableOnce` violated (killed) | 55,628 | 33 |
| `mutant-merge-right-first` | deadlock (killed) | 5,719 | 20 |
| `witness-merged` / `witness-split` | reached | 439 / 170 | 10 / 8 |

TLAPS: `PxIndexFrontier_proofs.tla` 84/84 obligations proved, none omitted (`InitInv`, `StepInv`,
`InvSafe`: C3 for any finite set of leaves, through the TLC-checked refinement for the dispatcher).
C1 (each key once) and C2 (termination) are TLC only, within the bounds above.

Spec sha256: `PxIndexFrontier.tla` 059f53ae…, `PxIndexFrontier_proofs.tla` 02598b7f…,
`PxIndexLeafDispatch.tla` 5255d590… (full list in the run dir's summary).
