# CBRD-27848 + CBRD-27968 — the descending index scan's step to the left leaf

PR #8423 carries both: the serial scan's conditional latch failure before the first key (CBRD-27848, `DescTree`)
and the parallel scan dispatcher's check of the last leaf handed out (CBRD-27968, `DescLeafDispatch`). Both models
refine the same abstract scan `DescScan` (user 2026-11-06: "병렬이나 직렬이나 접근이 개념적으로 같아야").

Engine: develop 21c6e635d (worktree `~/dev/cubrid-worktree/CBRD-27848`), CBRD-27851 (#8363, 51f3d13b7) applied.
Line numbers below are `src/storage/btree.c` at 21c6e635d.

Two modules:
- `DescScan` — the abstract design over key values: the scan reads from its start downward and returns the keys
  of its snapshot that are in range (W); other transactions only move the next record to read across values that
  hold no key of W (`Shift`). TLAPS proves its invariant for every N, W, Top (`DescScan_proofs.tla`).
- `DescTree` — the code-shaped model: a leaf chain with lower fences, the conditional latch, the unlatched gap,
  and other transactions' DML and vacuum (insert / vacuum an invisible key, split into a free page, merge a leaf
  into its left neighbour and free it, reuse of a freed page) under their write latches. Its pass cfgs check
  `AbsSpec` (refinement into `DescScan`), so the TLAPS result reaches it inside the cfg bounds (cubrid-tla P16).

- `DescLeafDispatch` (CBRD-27968) — the parallel dispatcher (develop 953e83256,
  `src/query/parallel/px_scan/index/px_scan_index_leaf_page_dispatcher.cpp`, below `dispatcher.cpp`): workers ask
  a shared dispatcher for leaves right to left; it remembers the last leaf handed out (VPID, LSA, smallest key) and
  fixes its left link next; vacuum merges and frees leaves, inserts split them into freed pages; page latches with
  waiters (a READ request queues behind a waiting writer). Its pass cfgs check `AbsSpec` (refinement into
  `DescScan`: the keys handed out, in order, are the abstract scan's reads). The finding and its first runtime
  reproduction (develop e98bdd885 probe build) are in `docs/tla/parallel-scan/index/MAP.md` (H2).

The first round's static model (`DescPrevLeaf`, fixed tree content, structure changes only as a "restart"
outcome) was replaced by `DescTree` on the user's request (2026-11-06: "각종 DML에 의한 split/VACUUM merge 등에
상황에도 괜찮음을 증명해").

## Claim and sources

| Claim | Kind | Statement | Source |
|---|---|---|---|
| C1 | equivalence | A descending index range scan returns the same rows in the same order as the same scan without latch contention, whatever the timing of the conditional latch on the left leaf | CBRD-27848 Expected Result; CBRD-27583 spec 14 (merges bound); user 2026-11-06 Q1/Q4 |
| C2 | safety | The start bound is never compared in the index's own domain without its bound (no ER_TP_CANT_COERCE, no assert) | CBRD-27848 Actual 3); ADR 0040 "엔진은 뻗지 않는다"; user 2026-11-06 Q4 |
| C3 | liveness | The scan ends, assuming other transactions write-latch the left leaf finitely often | CBRD-27851; user 2026-11-06 Q3/Q4 |

| C4 | safety | A descending parallel index scan hands out every key present in the index for the whole scan exactly once, while other transactions insert (splits, page reuse) and vacuum deletes (merges, page deallocation); its hand-outs, in order, are a `DescScan` behavior | CBRD-27968 Expected Result (`474552 / 1126000376280`); CBRD-26722 (same result as the serial scan); user 2026-11-06 round 1 Q2, Q6 |
| C5 | liveness | The parallel scan finishes and neither it nor the writers deadlock, under weak fairness per process and finitely many writer operations | CBRD-26863, CBRD-27737; user 2026-11-06 round 1 Q2 |
| C6 | safety | Neither a worker nor the dispatcher fixes a deallocated leaf as a live one | CBRD-27737 Expected Result; user 2026-11-06 round 1 Q2 |

## Decisions

| Round | Decision | State |
|---|---|---|
| 1 Q1 | Fix both the timing-dependent wrong answer and the -181/assert | settled 2026-11-06 |
| 1 Q2 | Special case restarts from the root (A); searching in place with the start's rule (B) rejected: a second copy of the merges rule in a shared helper (`btree_leaf_is_key_between_min_max`, 5 callers) | settled 2026-11-06 (`Fix = "restart"`) |
| 1 Q3 | C3 holds under finitely many write latches on the left leaf; starvation under an endless writer stream is not claimed (the normal path on fenced leaves already has it) | settled 2026-11-06 |
| 1 Q4 | Claims C1-C3 as above | settled 2026-11-06 |
| 2 Q5 | Wait for P (the existing unconditional fix and its freed/invalid/unlinked checks) before restarting; restarting at once could repeat root descents for as long as one writer holds P | settled 2026-11-06 |
| 2 Q6 | Builds, gdb injection harness fail-before/pass-after, CS optdebug run, CTP sql/medium + btree shell subset, trace validation after implementation, one sql TC pinning the uncontended answer | settled 2026-11-06 |

| 27968 r1 Q1 (D1) | The dispatcher trusts the left leaf L only while the last leaf C is unchanged: with L still latched, fix C, compare its LSA with the one saved at hand-out, unfix; a mismatch unfixes L and resumes from the last key. Rejected: relocating from the root at every leaf (the root descent lands on C and follows the same link) | settled 2026-11-06 (`Fix = "lsa_held"`) |
| 27968 r1 Q2 (D3) | Claims C4-C6; one key range; C5 under weak fairness per process and finitely many writer operations | settled 2026-11-06 |
| 27968 r1 Q3 (D4) | Trace validation on the fix's instrumented build; runtime fail-before (cited: e98bdd885 probe build, 136 rows missed) and pass-after with the env-gated delay at fix_prev_leaf | settled 2026-11-06 |
| 27968 r2 Q4 (D2) | C is latched unconditionally, left to right as the serial scan's fallback does. Rejected: a conditional latch with a failure resuming from the saved leaf (`btree_locate_key_from_saved_leaf` fixes C unconditionally anyway) or from the root (the descent lands on C: `witness-stall-on-reroot`) | settled 2026-11-06 |
| 27968 r2 Q5 | Performance gate: release A/B in `instructions:u` of a descending parallel scan without DML (fix vs the same head without CBRD-27968); the contended case (inserts at the index's right end) is reported, not gated; the frontier-style fast path (keep C latched by its worker, conditional latch on L) is a follow-up only if that report shows the wait | settled 2026-11-06 |
| 27968 r2 Q6 | One spec directory for PR #8423: `DescLeafDispatch` refines `DescScan` like `DescTree` | settled 2026-11-06 |
| — | CTP runs only as the PR's `/run all`, not locally | user 2026-11-06 |

Exploration before Q2 (TLC, removed variants): searching in place with the start's rule passed C1/C2 too; under an
endless writer stream and weak fairness it ended on unfenced leaves where the restart starves, while on fenced
leaves the existing normal path starves for every variant (`btree_split_node` inserts a lower fence for every key
type, 17862-17893). Restarting without waiting passed C1/C2.

## Refinement map (model -> code)

| Model | Code | One step because |
|---|---|---|
| `Start` (`Below(T)`) | `btree_range_scan_start` 29710: clears `force_restart_from_root` (29727), `btree_locate_key` with `equal_as` DB_LT exclusive / DB_GT inclusive (29755-29758), consumed when exclusive and found (29774), `slot_id--` when not found descending (29767); stands just below the threshold T on the tree as it is now | root-to-leaf latch coupling: the leaf is latched while its parent still is, so the position is exact for the tree at that moment; waits for a write-latched leaf |
| `Start` under `Mutant = "noclear"` | 29786-29799 restart branch with the request left set (pre-CBRD-27851) | — |
| `Resume` (`Below(curKey)`) | `btree_range_scan_resume` 29819: clears the request (29834-29838), `btree_locate_key_from_saved_leaf` on `cur_key` from the root, consumed; not found → the next smaller key | as start |
| `ScanRecord` | `btree_range_scan_advance_over_filtered_keys`: fence skipped (30107-30115), `btree_range_scan_read_record` sets `cur_key`, `btree_apply_key_range_and_filter` (descending: the opposite limit only), `is_scan_started` at the first key that passes (29802); its OIDs are returned when the snapshot sees them | C read-latched for the whole record |
| `ScanEnd` | `VPID_ISNULL (&next_vpid)` → `end_scan` (30012-30017) | C latched |
| `PrevLatched` | `fix_prev_leaf`: `pgbuf_fix` conditional on P (C's `prev_vpid`) succeeds (30159-30172), C unfixed | P and C latched across the swap |
| `PrevLatchFails` | the conditional fix returns NULL; `btree_check_decompress_key`, C unfixed (30176-30180) | C released |
| `GapRequestP` | `pgbuf_fix_if_not_deallocated` on P requested (30182) | from the release of C to this request nothing is latched: other transactions may free, reuse or split P and C here |
| `GapFixP` (freed / reused / unlinked) | P deallocated (30188-30192), not a valid leaf (30194-30200), `next_vpid != C` (30203-30210) → `force_restart_from_root` | under P's latch |
| `GapFixP` (design) | after the linked check: `!is_scan_started && DB_IS_NULL (&cur_key)` → unfix P, `force_restart_from_root` (replaces 30214-30233 for that case) | under P's latch, then released |
| `GapFixP` (other) | a key was read: fix C (30214) | P held while C is requested; P linked to C keeps C allocated (freeing C rewrites P's `next_vpid`) |
| `GapLinked` | normal path: `btree_leaf_is_key_between_min_max` / `btree_search_leaf_page` on `cur_key` in C, then P: FOUND at slot > 1 → slot - 1, slot 1 → P's last slot, BETWEEN → first bigger - 1, SMALLER → search P, BIGGER / NOTFOUND → restart (30238-30365) | P and C latched |
| `GapLinked` under `Fix = "code"` | special case 30223-30233: `pr_clone_value (lower_key, &cur_key)`, `search_key.bound` set, `equal_as` DB_EQ: FOUND at any key of the equal run (5645-5656, 5838-5850); re-entry compares the clone without bound (`btree_compare_own_values` 23464-23465) | P and C latched |
| `Restart` | `btree_range_scan` 30515-30560: `is_scan_started` false → start, else resume | no latch held |
| `WriterLatch` + `WriterApply` | another transaction's operation under the write latches of the leaves it changes: insert / vacuum a key (`btree_insert` / vacuum's `btree_delete`, one leaf), `btree_split_node` (the leaf, the new page, the right neighbour's `prev_vpid`), `btree_merge_node` (both leaves, the right neighbour's `prev_vpid`; the merged page is deallocated and may be reused by a later split) | one operation under its latches; page latch waiters are granted in order, so a writer arriving after the scan's unconditional request waits behind it |
| keys of the snapshot never leave | MVCC: a key deleted after the snapshot keeps its record until vacuum, and vacuum removes only what no snapshot sees; a key inserted after the snapshot is invisible (`Inv`) | — |
| `chain`, `content` | the leaf chain (`next_vpid` / `prev_vpid`) and each page's records | changed only under write latches |
| `curKey`, `started`, `force`, `result` | `bts->cur_key` (`NoKey` = NULL, `Clone` = clone of `key_range.lower_key`), `is_scan_started`, `force_restart_from_root`, keys handed to `key_func` | single owner |
| `err` | ER_TP_CANT_COERCE (release) / `assert (false)` (debug) in `btree_compare_own_values` | — |
| `Abs` mapping | `g` = value of the next non-fence record at or below (C, slot); in the gap, the value at the moment C was released (`gg`); `emitted` = returned keys; `hasCur`/`cpos` = `cur_key` holds a key and its value | — |

Callers of the protocol entry points (P11): `btree_range_scan_descending_fix_prev_leaf` has one caller,
`btree_range_scan_advance_over_filtered_keys` (30025); it is reached from `btree_range_scan_start`,
`btree_range_scan_resume` and the key loop of `btree_range_scan` (30590-30615), all handled by `Restart`'s two
branches. Exits: end of range/index → `ScanEnd`; error returns of the fixes → fault table; interrupt → fault table;
ILS (loose index scan) → `bts_reset_scan` on restart, a start again (30547), same as the pre-start restart.

### DescLeafDispatch (CBRD-27968), `dispatcher.cpp` at 039ec8fa9, `btree.c` at 953e83256

| Model | Code | One step because |
|---|---|---|
| `W_ask` | `dispatcher.cpp:231 lock_holding`: descending has no frontier (`get_next_page_with_fix` stores `nullptr` when `is_desc_index`, :281), so the held leaf is unfixed before waiting for `m_leaf_mutex` | the thread's own latch |
| `W_lock`, `W_dispatch` | `dispatcher.cpp:287 dispatch_next_leaf` under `m_leaf_mutex`; `m_leaf_ended` -> `S_END` | the mutex |
| `D_root`, `D_leaf` | `dispatcher.cpp:39 descend_to_first_leaf`, then `save_last_leaf (new_range)` (:349) | latch-coupled descent; one acquisition per step |
| `D_fix_prev` | `dispatcher.cpp:518 fix_prev_leaf`: `OLD_PAGE_MAYBE_DEALLOCATED` fix of `m_current_leaf_vpid`; kept only if a valid leaf whose `next_vpid == m_last_leaf_vpid` | one fix and a header read under L's latch |
| `D_check_last` | the fix (D1, D2): with L held, `pgbuf_fix (m_last_leaf_vpid, OLD_PAGE_MAYBE_DEALLOCATED, READ, UNCONDITIONAL)`, `LSA_EQ` with `m_last_leaf_lsa` (:556), unfix C; a mismatch unfixes L | one fix and one header read under C's latch, L still latched |
| `D_resume` | `dispatcher.cpp:566 resume_after_last_key` (`!m_last_key_valid`: restart the range) | under the mutex |
| `D_saved` | `btree.c:19384 btree_locate_key_from_saved_leaf`: `pgbuf_fix_if_not_deallocated` of the saved leaf; LSA unchanged -> chain from it; a valid leaf whose min..max holds the key -> its slot (FOUND / BETWEEN) | one fix |
| `D_reroot`, `D_reroot_leaf` | the same function's descent from the root for `m_last_key` | latch-coupled descent |
| `W_retry` | `goto retry` (:391) | under the mutex |
| `D_desc_take` | `save_last_leaf` (:419): VPID, LSA, smallest key | under the mutex |
| `D_publish` | `get_next_page_with_fix` returns, the mutex is released | under the mutex |
| `W_read` | `px_scan_index_leaf_slot_walker.cpp scan_next_slot`: the worker keeps the leaf latched while it returns the leaf's rows | the leaf's read latch |
| `W_stop` | `dispatcher.cpp:255 release_leaf` (LIMIT, error, reset) | the worker's own latch |
| writer insert | `btree.c:32273 btree_split_node_and_advance`: descends with `nonleaf_latch_mode = PGBUF_LATCH_READ`, X on the leaf; a split restarts with write latches (`btree.c:32413, 32685`: a failed promotion restarts, a successful one is the restart without the gap) | latches held until the operation is applied |
| writer split | root X, leaf X, its right neighbour X; `btree.c:17755 btree_split_node` logs the new right page with `RVBT_COPYPAGE` (a fresh LSA, also on a reused page) and the right neighbour's `prev_vpid` (`btree.c:24067 btree_set_vpid_previous_vpid`) | same |
| writer delete / merge | vacuum's delete descends with READ on non-leaves; an emptied leaf restarts with write latches (`btree.c:35782`); `btree.c:35699 btree_merge_node_and_advance`: parent, left leaf, emptied right leaf, its right neighbour, all X; `btree.c:11988 btree_merge_node`, then `file_dealloc` | same |
| `xw`, `rootW` | `page_buffer.c:6329-6349 pgbuf_latch_bcb_upon_fix`: a READ request on a READ-latched page with a waiter, from a thread that is not a holder, blocks | — |
| `lsa` | page LSA: every logged change of a page advances it | — |
| `gen`, `lastGen`, `readCnt`, `fixFreed`, `reuseCaught`, `benignReject` | ghosts | — |
| `Abs` mapping | `g` = the pending hand-out's key, else the largest key in the index below the last key handed out (0 once ended); `emitted` = stable keys handed out (`handedW`, at `D_publish`); `hasCur`/`cpos` = the last key handed out (`absCpos`); `pc` = start before the descent, done once a worker sees the end (`seenEnd`) | — |

Callers (P11): `fix_prev_leaf` and `resume_after_last_key` are called only from `dispatch_next_leaf` (:383, :387),
which is called from `get_next_page_with_fix` (the workers' next-leaf request). Exits: the end of the chain or range
-> `m_leaf_ended` (`W_retry`, `W_dispatch`); an error return of a fix -> fault table; LIMIT / error / reset ->
`release_leaf` (`W_stop`); a range's upper bound -> `signal_chain_ended` (one range modeled, fault table).

## Properties

| Name | Module | Kind | Statement | Claim |
|---|---|---|---|---|
| `ResultIsPrefix` | DescTree | invariant | what was returned is a prefix of the expected descending answer | C1 |
| `CompleteAnswer` | DescTree | invariant | a scan that ends without error returned the whole answer | C1 |
| `NoBoundlessCompare` | DescTree | invariant | no bound-less comparison of the bound clone | C2 |
| `ScanEnds` | DescTree | liveness | the scan reaches done (`MaxWrites` operations) | C3 |
| `AbsSpec` | DescTree | refinement | every step is a `DescScan` step or stutters | C1 |
| `Complete`, `Descending` | DescScan | invariant, action property | at done the returned set is W; each returned key lies below every key returned before | C1 |
| `IndInv` | DescScan | inductive invariant | TLAPS-proved for every N, W, Top | C1 |
| `StableOnce` | DescLeafDispatch | invariant | when every worker is done (none stopped early), each stable key was read exactly once | C4 |
| `NoStableDuplicate` | DescLeafDispatch | invariant | no stable key is read twice, at any time | C4 |
| `AbsSpec` | DescLeafDispatch | refinement | every step is a `DescScan` step or stutters (the hand-outs, in order, are the abstract reads) | C4 |
| `ScanFinishes` | DescLeafDispatch | liveness, WF per process | every worker reaches Done | C5 |
| (deadlock check) | DescLeafDispatch | TLC | no reachable state without a successor before the end | C5 |
| `NoFreedFix` | DescLeafDispatch | invariant | no freed leaf is fixed as live | C6 |

C2 is a TLC result of `DescTree` only: the abstract spec has no clone to compare.

## Fault model and environment assumptions

| Fault | Modeled as |
|---|---|
| conditional latch failure on P | `PrevLatchFails`, whenever the writer holds P, at every leaf boundary |
| P or C freed, reused or unlinked in the gap | `WriterApply` of a merge (the freed page keeps stale records) or a split into a freed page, whenever the scan holds neither page (`gap0`, `start`, `resume`, and around the pages it holds) |
| key inserted in the gap or below the scan's position | `WriterApply` of an insert of an invisible key, anywhere the order allows, including a key at or above the bound landing below the scan's position |
| key vacuumed | `WriterApply` of a vacuum of an invisible key, including the scan's `cur_key` (resume then finds the next smaller key) |
| error return of `pgbuf_fix` / `pgbuf_fix_if_not_deallocated` on P or C | not modeled: the scan returns the error (30183-30187, 30215-30220) and the query fails; no answer is produced |
| interrupt | not modeled: checked in the caller between keys; ends the query with an error, no partial answer counts |
| lock timeout, deadlock victim | not applicable: page latches only; the scan holds no lock across this protocol |
| OOM | not applicable to the design (no allocation in the restart path); `pr_clone_value` disappears with it |
| crash / `kill -9` | not applicable: read-only scan state |
| spurious wakeup | not applicable: no condition wait |
| concurrent DML / vacuum | the operations above, one at a time, `MaxWrites` of them; keys of the scan's snapshot are never inserted or removed (MVCC) |
| checkpoint, HA apply | not applicable: page latches like any writer |
| fairness | scan steps WF; a writer's operation completes (WF); `MaxWrites` operations (C3's assumption, Q3) |
| DescLeafDispatch: concurrent INSERT | a churn key into its leaf; a split when the leaf is full (restart with write latches), into any free page, including one a merge just freed |
| DescLeafDispatch: vacuum / DELETE | a churn key out; an emptied leaf is merged into its left leaf (restart with write latches) and freed |
| DescLeafDispatch: a worker stops early (LIMIT, error, interrupt) | `W_ask` -> `W_stop` when `EarlyStop` |
| DescLeafDispatch: latch waiters | a writer waiting for X blocks new READ requests (`xw`, `rootW`) |
| DescLeafDispatch: more than one key range | not modeled: each range starts with `descend_to_first_leaf` and `save_last_leaf (new_range)` (`dispatcher.cpp:349`), which rebuild `m_last_leaf_vpid`, `m_last_leaf_lsa`, `m_last_key`; the check acts within one range |
| DescLeafDispatch: error return of a fix | not modeled: `fix_prev_leaf` and `resume_after_last_key` return it, `dispatch_next_leaf` ends the chain (`m_leaf_ended`, `S_ERROR`) and the query fails |
| DescLeafDispatch: crash / `kill -9`, lock timeout, OOM, spurious wakeup | not applicable: a read-only scan under page latches and one mutex, no allocation in the check, no condition wait |
| DescLeafDispatch: fairness | WF per process; finitely many writer operations (`WriterOps`, C5's assumption) |

## Mutants

| cfg | Change | Expected | Kills |
|---|---|---|---|
| `DescTree.mutant-code-excl` | develop's special case (clone + DB_EQ), exclusive bound | `ResultIsPrefix` violated: returns keys equal to X | C1 |
| `DescTree.mutant-code-incl` | the same, inclusive bound (the start lands in C past a separator) | `ResultIsPrefix` violated: loses equal keys at P's end | C1 |
| `DescTree.mutant-code-refines` | the same, checked only against `AbsSpec` | refinement violated | C1 |
| `DescTree.mutant-code-boundless` | the same, a second conditional latch failure after the clone | `NoBoundlessCompare` violated (CBRD-27848 Actual 3) | C2 |
| `DescTree.mutant-noclear` | the design without CBRD-27851 (start keeps the restart request) | `ScanEnds` violated: start repeats forever | C3 |
| `DescTree.mutant-nolinkcheck` | the design without P's freed / unlinked checks (30188-30210) | `ResultIsPrefix` violated: a split of P in the gap puts a leaf between P and C, which the normal path skips | C1 |
| `DescLeafDispatch.mutant-code` | the code before CBRD-27968: the left link trusted by VPID only (`Fix = "none"`) | `StableOnce` violated (merge, then reuse by the left leaf's split) | C4 |
| `DescLeafDispatch.mutant-code-refines` | the same, checked only against `AbsSpec` | refinement violated | C4 |
| `DescLeafDispatch.mutant-check-unheld` | C's LSA compared before L is fixed, no latch held across | `StableOnce` violated | C4 |
| `DescLeafDispatch.mutant-check-right-first` | C fixed and kept, then L (right to left) | deadlock | C5 |
| `DescLeafDispatch.mutant-merge-right-first` | a merge latches the right leaf before the left one | deadlock | C5 |
| `DescLeafDispatch.mutant-trust-prev-link` | the left link used without any check (before CBRD-27738) | `NoFreedFix` violated | C6 |

Surviving mutant: dropping the special-case guard (restart on every conditional latch failure) violates nothing in
the first-round model — the caller resumes a started scan from `cur_key`. The guard is kept on purpose: it confines
the change to the case CBRD-27848 is about and leaves the normal path's in-place search (no root descent) as it is.

## Witnesses

| cfg | Reached state |
|---|---|
| `DescTree.witness-special` | the special case restarted the scan |
| `DescTree.witness-answer-after-special` | a scan that took the special case returned a nonempty complete answer |
| `DescTree.witness-split-in-gap` | a leaf split while the scan held no latch in the gap |
| `DescTree.witness-merge-in-gap` | a leaf merged (and its page freed) while the scan held no latch in the gap |
| `DescTree.witness-gaprestart-after-start` | a started scan found P freed or unlinked and resumed from `cur_key` |
| `DescScan.witness-returned` | the abstract scan returned a nonempty answer |
| `DescLeafDispatch.witness-reuse-caught` | the check refused a reused C that L links to (the H2 interleaving caught) |
| `DescLeafDispatch.witness-benign-reject` | the check refused a C changed in place (cost only) |
| `DescLeafDispatch.witness-merged` | a leaf was merged away while a worker was scanning |
| `DescLeafDispatch.witness-stall-on-last` | the dispatcher, holding L and the mutex, waits for C behind a writer while a worker reads C (the D2 cost) |
| `DescLeafDispatch.witness-stall-on-reroot` | the same wait under the rejected `lsa_cond_root` variant: the root descent lands on C |

## Dead expressions (pass cfgs)

| Line | Why never evaluated |
|---|---|
| DescTree.tla:146 | `Start`'s `noclear` branch: mutant `noclear` only |
| DescTree.tla:157 | `Resume`: exclusive cfgs only — W = {1, 2} sits in the first leaf, so no started scan meets a leaf boundary at MaxWrites 3; fires in the inclusive cfgs and the gap-restart witness |
| DescTree.tla:158 | as 157 |
| DescTree.tla:159 | as 157 |
| DescTree.tla:167 | the fence branch of `ScanRecord`: unfenced cfgs have no fence |
| DescTree.tla:199 | `Restart` at `GapLinked`'s call site (the normal path's BIGGER / NOTFOUND): not reached at MaxWrites 3; reached in `scale-4-writes` (MaxWrites 4) |
| DescTree.tla:200 | `Restart`'s `started` branch at `GapFixP`'s special-case call site: the guard requires `~started` (reached through the freed / unlinked call site) |
| DescTree.tla:201 | `Restart`'s not-started branch at `GapLinked`'s call site: the normal path runs with a key read, and a filtered key before the first returned one only exists in the scale layout, where the normal path restart is reached started |
| DescTree.tla:213 | `GapFixP`'s fix-C branch: exclusive cfgs only, as 157 |
| DescTree.tla:220 | `GapLinked`'s `code` special case: `Fix = "code"` (mutants) only |
| DescTree.tla:221 | as 220 |
| DescTree.tla:223 | as 220 |
| DescTree.tla:224 | as 220 |
| DescTree.tla:225 | as 220 |
| DescTree.tla:228 | the bound-less comparison: `cur_key` is a clone only under `Fix = "code"` (violation ghost) |
| DescTree.tla:229 | as 228 |
| DescTree.tla:231 | the normal path's restart (BIGGER / NOTFOUND): as 199; the whole normal path is dead in the exclusive cfgs, as 157 |
| DescTree.tla:232 | as 231 |
| DescTree.tla:233 | as 231 |
| DescTree.tla:234 | as 231 |
| DescLeafDispatch.tla:560, DescLeafDispatch.tla:562, DescLeafDispatch.tla:608, DescLeafDispatch.tla:609, DescLeafDispatch.tla:610, DescLeafDispatch.tla:621, DescLeafDispatch.tla:622, DescLeafDispatch.tla:623, DescLeafDispatch.tla:624, DescLeafDispatch.tla:625, DescLeafDispatch.tla:648, DescLeafDispatch.tla:649, DescLeafDispatch.tla:650 | mutant branches `check_unheld` / `check_right_first` (`D_check_first`, `D_fix_last_first`, the release of the held last leaf); evaluated in their mutant cfgs |
| DescLeafDispatch.tla:1114, DescLeafDispatch.tla:1155, DescLeafDispatch.tla:1171 | `merge_right_first` mutant branches (`X_del_mutant`, the right leaf already X-latched in `X_del_rwait` / `X_del_right`) |
| DescLeafDispatch.tla:646 | `D_fix_prev` handing L out without the last-leaf check: `Fix = "none"` (`mutant-code`) and the mutants only |
| DescLeafDispatch.tla:665, DescLeafDispatch.tla:666, DescLeafDispatch.tla:667, DescLeafDispatch.tla:668, DescLeafDispatch.tla:669 | the conditional latch on C failing: the rejected `lsa_cond` / `lsa_cond_root` variants only (`witness-stall-on-reroot`) |
| DescLeafDispatch.tla:696, DescLeafDispatch.tla:697, DescLeafDispatch.tla:698 | `skipSaved` (relocate from the root on a failed conditional latch): `lsa_cond_root` only |
| DescLeafDispatch.tla:523, DescLeafDispatch.tla:524, DescLeafDispatch.tla:862, DescLeafDispatch.tla:863, DescLeafDispatch.tla:864, DescLeafDispatch.tla:865, DescLeafDispatch.tla:866 | `W_stop`, the early stop: dead where `EarlyStop = FALSE`; `DescLeafDispatch.early-stop` evaluates it |
| DescLeafDispatch.tla:876, DescLeafDispatch.tla:877 | `W_end` releasing a held leaf: every path into `W_end` has released it already (`W_ask` unfixes the held leaf before `W_lock` in a descending scan, `dispatcher.cpp:231 lock_holding`; `W_stop` unfixes it, `dispatcher.cpp:255 release_leaf`); a defensive branch |
| DescLeafDispatch.tla:715, DescLeafDispatch.tla:716, DescLeafDispatch.tla:717, DescLeafDispatch.tla:718, DescLeafDispatch.tla:719, DescLeafDispatch.tla:720 | `D_saved` with the saved leaf's LSA unchanged: `D_resume` is reached only after the last-leaf check saw C changed, or after the link check failed; the link breaks only by a split of L, a merge of L into its left leaf, or L's page freed and reused, and each of them rewrites C's `prev_vpid` (`btree.c:24067 btree_set_vpid_previous_vpid`, logged), so C's LSA has changed. In the code `btree_locate_key_from_saved_leaf`'s unchanged branch serves the range restart and resumes outside this protocol |
| DescLeafDispatch.tla:737, DescLeafDispatch.tla:738 | `D_saved` locating the last key in C with nothing below it and C leftmost: the leftmost leaf is never merged away (`btree.c:36130`: a child's right neighbour is merged into the child), so a leaf with a left neighbour keeps one; a C without one was the leftmost when handed out, and that hand-out ended the scan (`D_desc_take`) |
| DescLeafDispatch.tla:691, DescLeafDispatch.tla:692, DescLeafDispatch.tla:693, DescLeafDispatch.tla:694 | the range restart (`!m_last_key_valid`): dead in `cap-2` / `gap-cap-2` (no hand-out of an empty leaf before a link change at those bounds); fires in `DescLeafDispatch.cfg` (an emptied, not yet merged rightmost leaf handed out first) |
| DescLeafDispatch.tla:724, DescLeafDispatch.tla:725, DescLeafDispatch.tla:726, DescLeafDispatch.tla:727, DescLeafDispatch.tla:728 | `D_saved` handing C out again from the slot below the last key (a key inserted into C below the last key after the hand-out): dead under `Layout = "tight"` (each leaf's lower bound is its smallest key, so no key lands below the last key in C); fires in `DescLeafDispatch.gap-cap-2` |
| DescLeafDispatch.tla:783, DescLeafDispatch.tla:784, DescLeafDispatch.tla:799, DescLeafDispatch.tla:800, DescLeafDispatch.tla:801 | the root descent landing on the leftmost leaf with nothing below the last key, and `W_retry` ending there: needs the last leaf merged into an emptied leftmost leaf; dead under `Layout = "tight"` (the leftmost leaf keeps stable key 2); fires in `DescLeafDispatch.gap-cap-2` |
| DescLeafDispatch.tla:951, DescLeafDispatch.tla:952, DescLeafDispatch.tla:953, DescLeafDispatch.tla:954, DescLeafDispatch.tla:955, DescLeafDispatch.tla:956, DescLeafDispatch.tla:957, DescLeafDispatch.tla:958, DescLeafDispatch.tla:959, DescLeafDispatch.tla:969, DescLeafDispatch.tla:970, DescLeafDispatch.tla:971, DescLeafDispatch.tla:972, DescLeafDispatch.tla:981, DescLeafDispatch.tla:982, DescLeafDispatch.tla:983, DescLeafDispatch.tla:984, DescLeafDispatch.tla:994, DescLeafDispatch.tla:995, DescLeafDispatch.tla:996, DescLeafDispatch.tla:997, DescLeafDispatch.tla:1007, DescLeafDispatch.tla:1008, DescLeafDispatch.tla:1009, DescLeafDispatch.tla:1010, DescLeafDispatch.tla:1020, DescLeafDispatch.tla:1022, DescLeafDispatch.tla:1023, DescLeafDispatch.tla:1024, DescLeafDispatch.tla:1035, DescLeafDispatch.tla:1036, DescLeafDispatch.tla:1038, DescLeafDispatch.tla:1039, DescLeafDispatch.tla:1040, DescLeafDispatch.tla:1050, DescLeafDispatch.tla:1051, DescLeafDispatch.tla:1052, DescLeafDispatch.tla:1053, DescLeafDispatch.tla:1054, DescLeafDispatch.tla:1055, DescLeafDispatch.tla:1056, DescLeafDispatch.tla:1057, DescLeafDispatch.tla:1058, DescLeafDispatch.tla:1059, DescLeafDispatch.tla:1060, DescLeafDispatch.tla:1061, DescLeafDispatch.tla:1062, DescLeafDispatch.tla:1063, DescLeafDispatch.tla:1186, DescLeafDispatch.tla:1202 | the split path (`X_ins_root` .. `X_split_apply`), the full-pool skip and a merge without a right neighbour: dead in `cap-2` / `gap-cap-2` (with two keys per leaf no leaf fills within 3 operations); all fire in `DescLeafDispatch.cfg` |

## Bounds and limits

- `DescTree` base: 4 page ids, 3 keys per leaf; snapshot keys {1,2,4,5,7,8} in 3 leaves, X merges {4,5}, DML may
  insert the invisible keys {3,6,9}; both bound kinds, with and without lower fences; 3 operations of other
  transactions. Scale: snapshot keys {1,2,4,5,6,8,9}, X merges {4,5,6}, key 2 filtered, 4 operations.
- `DescScan`: TLC N = 9 (scale 11), inductive N = 5; TLAPS for every N, W, Top.
- One operation of other transactions at a time (their own latch protocol is not under test); a root-to-leaf
  descent is one step (latch coupling).
- Not covered: the normal path's own starvation under an endless writer stream (pre-existing, Q3); ascending
  scans (no conditional latch); non-leaf pages (only the descent's result is modeled).
- `DescTree` trace layout (trace cfgs only): six one-key leaves, so a recorded scan can cross four leaf boundaries.
- Trace validation checks the protocol skeleton only: record reads, the end of the scan and other transactions'
  operations are hidden (the real index holds thousands of keys); see "Trace validation".
- `DescLeafDispatch`: 2 workers, one writer, 4 page ids, keys {1..5} with stable keys {2, 4}, one key per leaf
  (`Cap = 1`), 3 writer operations; scale 3 workers and 4 writer operations; `cap-2` two keys per leaf (invariants
  and liveness only: `AbsSpec` maps one key per hand-out). One key range.

## Trace validation

Instrumented build: scratch worktree `~/dev/cubrid-worktree/CBRD-27848-trace` = df7cc0a37 + `tla_trace`
(TLATRACE lines to `$CUBRID_TLATRACE_FILE`, one per refinement-map action, emitted inside the step under the
latch it records) + env-gated fault injection (`CUBRID_TLA_INJ_CONDFAIL`: the listed fix_prev_leaf conditional
latch calls return no page; `CUBRID_TLA_INJ_DEALLOC`: the following unconditional fix sees the page freed). optdebug
install `~/optdebug/CUBRID-cbrd27848-trace` (libcubrid 9a5e2747…). Runs on a CS server (port 1712), one server
start per run, SQL from the CBRD-27848 attachment (A, B, C) and a multi-leaf same-type scan (D).

| cfg | run | events | covers |
|---|---|---|---|
| `witness-trace-a-inj1` | A exclusive literal, 1 conditional failure (0 rows) | 6 | Start, PrevLatchFails before the first key, GapRequestP, GapFixP special, restart, PrevLatched |
| `witness-trace-a-bind-inj1` | A exclusive bind (0 rows) | 6 | the same through a host variable |
| `witness-trace-c-incl-inj1` | C inclusive, bulk-loaded index without fences (100 rows) | 6 | the special case on an inclusive limit |
| `witness-trace-b-inj12` | B, two failures in a row (0 rows) | 10 | the special case twice (the old -181 / assert path) |
| `witness-trace-a-dealloc` | A, failure + P freed (0 rows) | 6 | GapFixP unlinked before the first key → start |
| `witness-trace-d-inj2` | D, failure after keys were read (1999 rows) | 7 | GapFixP fixc, GapLinked pos (normal path), fence → PrevLatched |
| `witness-trace-d-inj23` | D, two failures after keys were read | 11 | the normal path twice |
| `witness-trace-d-dealloc` | D, failure + P freed after keys were read | 7 | GapFixP unlinked → Resume |
| `reject-special-searches-in-place` | a-inj1 with the special case continuing to fix C (the pre-fix path) | — | refused |
| `reject-no-start-after-special` | a-inj1 without the restart's Start | — | refused |
| `reject-fixc-before-first-key` | d-inj2 with the failure claimed before any key was read | — | refused |

Not reached by a recorded run: `GapLinked o=restart` (the normal path's BIGGER / NOTFOUND needs the leaf's keys to
change while unlatched; TLC covers it with `WriterApply` in the gap, `witness-merge-in-gap`, `witness-split-in-gap`).
Raw logs: `traces/*.log` (D logs cut before the run's second query).

### DescLeafDispatch (CBRD-27968)

Instrumented build: scratch worktree `~/dev/cubrid-worktree/CBRD-27968-trace` = 039ec8fa9 + `tla_trace` in
`dispatcher.cpp` (TLATRACE lines to `$CUBRID_TLATRACE_FILE` under `m_leaf_mutex`: `D_leaf`, `D_fix_prev o=linked|unlinked`,
`D_check_last o=unchanged|changed`, `D_desc_take`) + `TLAINFO` lines on stderr at `btree_get_new_page` and the merge's
`file_dealloc` + an env-gated delay at the first `fix_prev_leaf` call (`CUBRID_TLA_PX_DESC_DELAY_US`,
`CUBRID_TLA_PX_DESC_DELAY_AT`); patch kept as `.git_ignored_dir/scratch/cbrd27968/CBRD-27968-trace-instrumentation.patch`.
optdebug install `~/optdebug/CUBRID-cbrd27968-trace` (libcubrid 72d59cf2e571de1c), CS server on port 1716,
`parallel_scan_page_threshold=1`, table of 1500 keys (3 leaves), `parallel(2) use_desc_idx`, one server start per run.

| cfg | run | events | covers |
|---|---|---|---|
| `DescLeafDispatchTrace.witness-trace-dispatch-nodml` | no DML (1500 rows) | 7 | D_leaf, D_fix_prev linked, D_check_last unchanged, D_desc_take |
| `DescLeafDispatchTrace.witness-trace-dispatch-benign` | 8 s delay at the first check; the top key deleted meanwhile (1500 rows) | 9 | D_check_last changed (C changed in place) -> resume, the chain continued from C |
| `DescLeafDispatchTrace.witness-trace-dispatch-unlinked1` | 8 s delay; 50 keys inserted into L, one split (1500 rows); `Layout = "gap"` (a churn key fits in L's range) | 11 | D_fix_prev unlinked -> resume -> the new leaf handed out |
| `DescLeafDispatchTrace.reject-dispatch-changed-as-unchanged` | benign with `changed` flipped to `unchanged` | — | refused |
| `DescLeafDispatchTrace.reject-dispatch-no-last-check` | nodml without its `D_check_last` events (the code before CBRD-27968) | — | refused |

Runtime pass-after of the H2 interleaving on the same build (`.git_ignored_dir/scratch/cbrd27968/runs/fix9`, the
CBRD-27968 Repro with the deletes' log block filled before Q starts): `btree_merge left=6128 right=6126`, then
`btree_alloc page=6126` (L's split reuses C's page), then `D_fix_prev o=linked`, `D_check_last o=changed`,
`D_desc_take page=6126 slot=544` (the reused page handed out from the slot below the last key); Q returned
474552 / 1126000376280 (all stable rows), no assert. That run has 1481 events (494 hand-outs), beyond the model's
four pages, so it is runtime evidence, not a trace cfg.

## Counterexamples

| cfg | Classification |
|---|---|
| exploration `y-restart-*-wf` (endless writer, WF) | not a hole: C3's assumption excludes it (Q3); the normal path on fenced leaves has the same loop |
| — | none from a correct-variant cfg of the final model |
| `DescLeafDispatch.mutant-code` (the code before CBRD-27968) | hole H2, confirmed at runtime: develop e98bdd885 probe build 474416 / 1125355077360 (136 stable rows missed) with `btree_merge left=13744 right=13742`, `btree_alloc page=13742`, the link trusted with C's LSA changed (`docs/tla/parallel-scan/index/MAP.md`); the dispatcher is unchanged from e98bdd885 to 953e83256. Again on 3ab733f60 (PR #8423 without the CBRD-27968 commit) + the same instrumentation and delay (`~/optdebug/CUBRID-cbrd27968-baseprobe`, libcubrid 5230fc620994c3aa, run `.git_ignored_dir/scratch/cbrd27968/runs/base1`): `btree_merge left=6128 right=6126`, `btree_alloc page=6126`, `link_trusted last=6126 lsa=changed`, Q 474416 / 1125355077360; the fix build on the same sequence (run `fix9`) returns 474552 / 1126000376280 |
| — | none from a correct-variant cfg of `DescLeafDispatch`; model errors fixed on the way: the check skipped under `merge_right_first` (the mutant tested the wrong thing), writers holding the root X for a whole operation (hid the reroot's wait on C), a vacuum delete merging in the same operation (hid empty leaves handed out, the range restart) |

## Result

2026-11-06, `tools/tla/tla-check --workers 16 docs/tla/CBRD-27848` -> **RESULT: OK**
(run dir `.git_ignored_dir/scratch/tla/CBRD-27848-20261106-150642-53952`; TLAPS 요청 없음 in this run, so
`DescScan_proofs.tla` was not re-proved: its earlier result below stands for the unchanged `DescScan.tla`, sha256
5c27d040...). Engine: PR #8423 head 039ec8fa9 on develop 953e83256 (3ab733f60 CBRD-27848, 039ec8fa9 CBRD-27968);
`btree.c` is identical between f846c3634 and 953e83256, so the `DescTree` coordinates at 21c6e635d still hold.

| cfg | Result | States (distinct) | Depth |
|---|---|---|---|
| DescLeafDispatch (C4 C5 C6 + `AbsSpec`) | pass | 756392 (288615) | 88 |
| DescLeafDispatch.early-stop | pass | 1527174 (561705) | 88 |
| DescLeafDispatch.scale-3-workers (3 workers, 4 ops) | pass | 35570991 (10517099) | 113 |
| DescLeafDispatch.cap-2 / gap-cap-2 | pass | 370229 (140936) / 714230 (269245) | 66 / 69 |
| DescLeafDispatch.mutant-code | violation `StableOnce` | 458361 (171763) | 58 |
| DescLeafDispatch.mutant-code-refines | refinement (`DescScan`) | 290423 (109877) | 45 |
| DescLeafDispatch.mutant-check-unheld | violation `StableOnce` | 654041 (248744) | 59 |
| DescLeafDispatch.mutant-check-right-first / merge-right-first | deadlock | 61853 (24483) / 97285 (38386) | 30 / 33 |
| DescLeafDispatch.mutant-trust-prev-link | violation `NoFreedFix` | 55644 (21976) | 29 |
| DescLeafDispatch.witness-reuse-caught / benign-reject / merged / stall-on-last / stall-on-reroot | reached | 376331 / 36433 / 6681 / 8035 / 14803 | 47 / 26 / 18 / 18 / 21 |
| DescLeafDispatchTrace.witness-trace-dispatch-nodml / benign / unlinked1 | accepted | 24970 / 72426 / 136362 | 23 / 39 / 45 |
| DescLeafDispatchTrace.reject-dispatch-changed-as-unchanged / no-last-check | refused (pass) | 66977 / 60259 | — |
| DescTree, DescScan and their cfgs | as before (DescTree 25045 (13654), DescScan 319 (47)) | — | — |

`DescLeafDispatch`'s inductive safety reaches `DescScan`'s IndInv (Apalache/TLC inductive cfg
`DescScan.inductive-indinv`, TLAPS-proved earlier) only through `AbsSpec`, which TLC checks inside the cfg bounds
(cubrid-tla P16); `DescLeafDispatch` has no inductive invariant of its own. Spec sha256 (this run):
`DescLeafDispatch.tla` d9f9f59d..., `DescLeafDispatchTrace.tla` a5785947..., `DescLeafDispatchTraceData.tla` c460dbe2...,
`DescScan.tla` 5c27d040..., `DescTree.tla` ca149e2e... (full list in the run dir's summary).

### Earlier result (CBRD-27848 alone)

2026-11-06, `tools/tla/tla-check docs/tla/CBRD-27848` → `RESULT: OK`
(run dir `.git_ignored_dir/scratch/tla/CBRD-27848-20261106-085756-2942136`). Engine: develop 21c6e635d (btree.c identical
at f846c3634); implementation df7cc0a37 on branch CBRD-27848.

| cfg | Result | States (distinct) | Depth |
|---|---|---|---|
| DescTree (incl, fenced, 3 ops) | pass: C1 C2 C3 + `AbsSpec` | 25045 (13654) | 28 |
| DescTree.excl-fenced | pass | 10315 (5008) | 21 |
| DescTree.incl-unfenced | pass | 20606 (11397) | 24 |
| DescTree.excl-unfenced | pass | 8822 (4431) | 20 |
| DescTree.scale-4-writes | pass | 68374 (35882) | 34 |
| DescTree.mutant-code-excl | violation `ResultIsPrefix` | 1617 (821) | 10 |
| DescTree.mutant-code-incl | violation `ResultIsPrefix` | 1687 (981) | 11 |
| DescTree.mutant-code-boundless | violation `NoBoundlessCompare` | 2059 (1071) | 21 |
| DescTree.mutant-code-refines | refinement (`DescScan` action property) | 1151 (691) | 9 |
| DescTree.mutant-noclear | liveness (`ScanEnds`) | 1640 (795) | 11 |
| DescTree.mutant-nolinkcheck | violation `ResultIsPrefix` | 11101 (6346) | 14 |
| DescTree.witness-special / answer-after-special / split-in-gap / merge-in-gap / gaprestart-after-start | reached | 683 / 17660 / 123 / 762 / 11645 | 7 / 16 / 5 / 8 / 13 |
| DescScan / scale-incl-filter / inductive-indinv | pass | 319 (47) / 558 (67) / 479 (151) | 7 / 7 / 1 |
| DescScan.witness-returned | reached | 263 (47) | 7 |
| DescScan_proofs.tla | TLAPS 279/279 obligations proved (InitInv, StepInv, Safe `Spec => []IndInv`, InvSafe, DescendingSafe) | — | — |

| DescTreeTrace.witness-trace-* (8 runs) | accepted (`TraceNotDone` violated) | 1215–2525 states | 10–25 |
| DescTreeTrace.reject-* (3 corrupted runs) | refused (pass) | 1181–2053 states | — |

spec sha256: DescScan.tla 5c27d040…, DescScan_proofs.tla adc48302…, DescTree.tla ca149e2e…, DescTreeTrace.tla
dc46ee0b… (full list in the run dir's `summary.txt`).

Trace validation: done on df7cc0a37 + instrumentation (libcubrid 9a5e2747…), 8 runs accepted, 3 corrupted runs
refused (section "Trace validation").
