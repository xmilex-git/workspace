# CBRD-27848 — descending scan, conditional latch failure on the left leaf before the first key

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

The first round's static model (`DescPrevLeaf`, fixed tree content, structure changes only as a "restart"
outcome) was replaced by `DescTree` on the user's request (2026-11-06: "각종 DML에 의한 split/VACUUM merge 등에
상황에도 괜찮음을 증명해").

## Claim and sources

| Claim | Kind | Statement | Source |
|---|---|---|---|
| C1 | equivalence | A descending index range scan returns the same rows in the same order as the same scan without latch contention, whatever the timing of the conditional latch on the left leaf | CBRD-27848 Expected Result; CBRD-27583 spec 14 (merges bound); user 2026-11-06 Q1/Q4 |
| C2 | safety | The start bound is never compared in the index's own domain without its bound (no ER_TP_CANT_COERCE, no assert) | CBRD-27848 Actual 3); ADR 0040 "엔진은 뻗지 않는다"; user 2026-11-06 Q4 |
| C3 | liveness | The scan ends, assuming other transactions write-latch the left leaf finitely often | CBRD-27851; user 2026-11-06 Q3/Q4 |

## Decisions

| Round | Decision | State |
|---|---|---|
| 1 Q1 | Fix both the timing-dependent wrong answer and the -181/assert | settled 2026-11-06 |
| 1 Q2 | Special case restarts from the root (A); searching in place with the start's rule (B) rejected: a second copy of the merges rule in a shared helper (`btree_leaf_is_key_between_min_max`, 5 callers) | settled 2026-11-06 (`Fix = "restart"`) |
| 1 Q3 | C3 holds under finitely many write latches on the left leaf; starvation under an endless writer stream is not claimed (the normal path on fenced leaves already has it) | settled 2026-11-06 |
| 1 Q4 | Claims C1-C3 as above | settled 2026-11-06 |
| 2 Q5 | Wait for P (the existing unconditional fix and its freed/invalid/unlinked checks) before restarting; restarting at once could repeat root descents for as long as one writer holds P | settled 2026-11-06 |
| 2 Q6 | Builds, gdb injection harness fail-before/pass-after, CS optdebug run, CTP sql/medium + btree shell subset, trace validation after implementation, one sql TC pinning the uncontended answer | settled 2026-11-06 |

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

## Mutants

| cfg | Change | Expected | Kills |
|---|---|---|---|
| `DescTree.mutant-code-excl` | develop's special case (clone + DB_EQ), exclusive bound | `ResultIsPrefix` violated: returns keys equal to X | C1 |
| `DescTree.mutant-code-incl` | the same, inclusive bound (the start lands in C past a separator) | `ResultIsPrefix` violated: loses equal keys at P's end | C1 |
| `DescTree.mutant-code-refines` | the same, checked only against `AbsSpec` | refinement violated | C1 |
| `DescTree.mutant-code-boundless` | the same, a second conditional latch failure after the clone | `NoBoundlessCompare` violated (CBRD-27848 Actual 3) | C2 |
| `DescTree.mutant-noclear` | the design without CBRD-27851 (start keeps the restart request) | `ScanEnds` violated: start repeats forever | C3 |
| `DescTree.mutant-nolinkcheck` | the design without P's freed / unlinked checks (30188-30210) | `ResultIsPrefix` violated: a split of P in the gap puts a leaf between P and C, which the normal path skips | C1 |

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

## Counterexamples

| cfg | Classification |
|---|---|
| exploration `y-restart-*-wf` (endless writer, WF) | not a hole: C3's assumption excludes it (Q3); the normal path on fenced leaves has the same loop |
| — | none from a correct-variant cfg of the final model |

## Result

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
