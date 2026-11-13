# PR #8431 (CBRD-27972) — COMPACT appends to a key's overflow chain only while its leaf record holds a stable object

Code: PR head `6cc3c42d4` (merge-base develop `953e83256`), `src/storage/btree.c` (below `btree.c`, line
numbers of the PR head). The defect is H1 of `docs/tla/CBRD-24094-ovf-dir` (filed from that model as
CBRD-27972): a range scan stopped in the middle of a key (OID buffer full) resumes in the chain after its
anchor and never re-reads the leaf record; COMPACT pulls unread objects to the end of the first overflow
page, and vacuum's leaf swap moves the first page's last object into the leaf, so the scan loses that row.

The PR does not take the model's candidate fix F1 (swap the first page's first object). It gates COMPACT:
`xbtree_compact_overflow` compacts a key's chain only while the key's leaf record holds a stable object
(`btree_compact_leaf_has_stable_object`: no delete MVCCID, insert MVCCID neither the caller's nor an active
one), checked under the same leaf WRITE latch as the pulls of that round, and not at all for indexes of
MVCC-disabled classes.

| File | Role |
|---|---|
| `OvfDirChain.tla`, `OvfOrder.tla`, `OvfScanResume.tla` | copied unchanged from `docs/tla/CBRD-24094-ovf-dir` (sha256 in `## Result`); the chain, the directory, COMPACT pulls, the stop-and-resume scan |
| `OvfScanStable.tla` | extends `OvfScanResume` with each object's MVCC state, the vacuum horizon of the scan's snapshot, and the PR's guard |
| `OvfGuard.tla` | the PR's argument in five booleans; its inductive invariant is checked by Apalache, and `OvfScanStable` refines it (`GuardRefined`) |
| `OvfScanStableTrace.tla`, `OvfScanStableTraceData.tla` | trace validation of two runs of the instrumented PR head |

## Claim and sources

| # | Claim | Source |
|---|---|---|
| C1 | A range scan stopped in the middle of a key returns every object its snapshot sees exactly once while COMPACT, vacuum, rollback, inserts and deletes run during the stop. | JIRA CBRD-27972 Expected Result ("인덱스 스캔이 9,974행을 모두 돌려줍니다"); PR body Purpose |
| C2 | No leaf swap during the stop moves an object the scan has not returned. | PR note in `xbtree_compact_overflow` ("no swap can happen during the lifetime of a scan that was interrupted before the append"); comment added in `btree_replace_first_oid_with_ovfl_oid` |
| C3 | The stable-object check is what makes C2 hold: a stable leaf object cannot be vacuumed while a snapshot older than the check exists, the check counts neither deleted (DELID set) nor uncommitted objects, and it is repeated at every leaf latch acquisition, also after a yield. | PR note; PR body Implementation bullets 1-2; `btree_compact_leaf_has_stable_object` comments |
| C4 | COMPACT never compacts an index of a class without MVCC (whose objects are removed physically, so no leaf object is ever stable), so it adds no way to lose a row there. | PR note ("their indexes are not compacted at all"); PR body bullet 3 |
| C5 | The stopped scan finishes. | `OvfScanResume` C7 (liveness of any scan) |

## Refinement map (model -> code)

Inherited rows (the chain, the directory, the scan, `Remove`, `PullAt`) are `docs/tla/CBRD-24094-ovf-dir/MAP.md`
"Refinement map", re-read at the PR head: the PR changes none of those functions' code.

| Model | Code | One step because |
|---|---|---|
| `PullS` (`Guard` then `Pull`) | `xbtree_compact_overflow`: `spage_get_record` of the key's slot, `btree_read_record`, `btree_record_process_objects (..., btree_compact_leaf_has_stable_object, &has_stable)`, then `btree_ovf_compact_chain` -> `btree_ovf_compact_pull`, all while `leaf_page` stays fixed with `PGBUF_LATCH_WRITE` | the check and every pull of the round run under one leaf write latch; the round ends at `pgbuf_unfix_and_init (thread_p, leaf_page)` and the next round re-fixes through `btree_compact_fix_leaf` and runs the check again before any pull. A round's several pulls are several `PullS` steps, each with the guard true: nothing else runs between them |
| `CompactSkip` | `if (!has_stable)`: `(*pairs_skipped)++`, the key's resume state cleared, `slot++` | same latch round |
| `StableAs` | `btree_compact_leaf_has_stable_object`: `BTREE_MVCC_INFO_IS_DELID_VALID` -> not stable; `BTREE_MVCC_INFO_HAS_INSID` with `logtb_is_current_mvccid` or `logtb_is_active_other_mvccid` -> not stable; otherwise stable | pure read of the leaf record |
| `Guard` (class check) | `mvcc_is_mvcc_disabled_class (&btid_int.topclass_oid)` -> return before the leaf walk | once per COMPACT |
| `st` "ins" | insert MVCCID current or active; an aborting transaction stays active through its rollback (`log_abort_local`: `log_rollback` before `logtb_complete_mvcc`), so its object is "ins" until removed | — |
| `CommitIns`, `CommitDel` | `logtb_complete_mvcc` of the inserter / deleter | one MVCC table update |
| `DeleteS`, `AbortDel` | MVCC delete sets the object's delete MVCCID in the key; its undo clears it | leaf write latch |
| `RemoveS`, `Removable`, `Protected` | rollback of an uncommitted insert, or vacuum of a committed delete -> `btree_leaf_remove_object`; the swap (`btree_replace_first_oid_with_ovfl_oid`) only when the removed object is the leaf record's only one (`offset_to_object == 0` and `offset_to_last_object == 0`) and the key has a chain. Vacuum removes a delete only below the oldest visible MVCCID, which an active snapshot holds at or below its lowest active MVCCID: every object stable at some point after the scan's snapshot was taken is deleted, if at all, by a transaction the snapshot treats as active or future, so vacuum keeps it until the scan ends (`prot`) | leaf write latch |
| `SStartS` | `btree_range_scan_select_visible_oids` at a key start with the statement's snapshot: it sees committed inserts whose delete is not committed (`VisNow`) | leaf read latch over the iteration |
| `SResumeS` | `btree_ovf_scan_locate_resume` | leaf read latch |
| `CompactCheck`, `cok` | none: the `stale_check` mutant only (a check answer reused after the latch was released) | — |
| `pulled`, `lostg` | ghosts: a pull during the current stop; a swap moved an unreturned object | — |

`GuardRefined` maps `OvfScanStable` to `OvfGuard`: `u = pulled`, `ls` = the leaf holds a stable object (false
for a class without MVCC), `lp` = during the stop the leaf holds an object of `vis \cup prot`, `lost = lostg`.

Callers (P11): `btree_compact_leaf_has_stable_object` <- `xbtree_compact_overflow` only;
`btree_replace_first_oid_with_ovfl_oid` <- `btree_leaf_remove_object` only (code-index `callers`, PR head);
`xbtree_compact_overflow` <- the `ALTER INDEX ... COMPACT` request handler only.

## Properties

| Name | Kind | Statement | Claim |
|---|---|---|---|
| `NoDup`, `ExactlyOnce` | invariant | no object returned twice; when done the scan returned exactly the visible objects | C1 |
| `NoCompactNoMvcc` | invariant | no pull (merge or partial move) ever runs on an index of a class without MVCC | C4 |
| `NoResumeError` | invariant | the resume never fixes a freed page | C1 |
| `NoLostSwap` | invariant | no swap during a stop moved an unreturned object | C2 |
| `StableProtected` | invariant | during a stop every stable object is in `vis \cup prot` | C3 |
| `Safety` | invariant | `OvfDirChain` structure (`Shape`, `Sorted`, `DirMatch`, `DirSorted`, `Routable`, `Content`, `NoBad`), kept as a regression check | — |
| `GuardRefined` | refinement | every `OvfScanStable` step is an `OvfGuard` step: a loss needs a pull during the stop, a pull needs a stable leaf object, a stable object during the stop is protected | C2, C3 |
| `IndInv` (`OvfGuard`) | inductive invariant | `TypeOK`, `NoLost`, `UProt` (a pull during the stop implies a protected leaf object), `LsProt`, `USusp`, `LpSusp`; Apalache over every state | C2, C3 |
| `ScanFinishes` | liveness, WF on `SResumeS` | a stopped scan finishes | C5 |

## Fault model

| Fault | Modeled as |
|---|---|
| error return | the check's `btree_record_process_objects` error and every COMPACT error go to `exit` before a pull of that round: "no `PullS`", which every state allows |
| interrupt / query cancel | COMPACT checks the interrupt between rounds; stopping is "no further `PullS`" |
| lock timeout, deadlock victim | not applicable: COMPACT takes no lock on the key (latches only) |
| conditional latch failure | not applicable: unconditional leaf fixes |
| OOM | not applicable: no allocation on the check path |
| crash / kill -9 | not modeled here: the PR changes no durable write. The crash between the swap's halves is CBRD-27973 (H2 of the source model), which this PR does not address |
| spurious wakeup | not applicable |
| concurrent DML | modeled: inserts (uncommitted), commits, deletes (DELID), their commit and rollback, rollback removal, at every point between steps |
| vacuum | modeled: removal of committed deletes outside the scan's horizon, including the leaf swap |
| checkpoint, page flush, page replacement | not applicable: every page is fixed for the whole step |
| HA log apply | not applicable |
| nested statement (SP SQL from the client) | not modeled: a rebuilt READ COMMITTED statement snapshot (`logtb_invalidate_snapshot_data`) moves the scan's horizon forward; then the scan's own result set (`vis`) is no longer one snapshot's, so C1 is undefined for develop as well. Named in the report as not covered |

Environment assumptions: no fairness on writers or COMPACT; weak fairness on `SResumeS` only (C5).

## Mutants

| cfg | Mutation | Expected | Claim |
|---|---|---|---|
| `OvfScanStable.mutant-merge-base` | `GFix = "none"`: COMPACT pulls whatever the leaf holds (the merge-base `953e83256`) | `ExactlyOnce` violated (H1 again) | C1, C2 |
| `OvfScanStable.mutant-stale-check` | the stable answer is taken in an earlier latch round and reused after a yield | `ExactlyOnce` violated | C3 |
| `OvfScanStable.mutant-delid-stable` | the check ignores the delete MVCCID | `ExactlyOnce` violated | C3 |
| `OvfScanStable.mutant-uncommitted-stable` | the check ignores an uncommitted insert | `ExactlyOnce` violated | C3 |
| `OvfScanStable.mutant-no-class-check` | an index of an MVCC-disabled class is compacted (every object "stable" to the callback) | `NoCompactNoMvcc` violated | C4 |
| `OvfScanStable.mutant-env-vacuum-ignores-snapshot` | vacuum removes a delete newer than the scan's snapshot (the environment fact C3 relies on) | `ExactlyOnce` violated | C3 |
| `OvfScanStable.mutant-resume-blocked` | the resume never runs while the leaf holds an object | `ScanFinishes` violated (liveness: the MVCC delete/abort cycle keeps the writers running, so the stuck scan is a lasso, not a deadlock) | C5 |
| `OvfGuard.mutant-no-guard` | a pull without a stable leaf object | `NoLost` violated | C2 |

## Witnesses

| cfg | Outcome reached |
|---|---|
| `OvfScanStable.witness-pull-while-susp` | with the fix, COMPACT still pulls during a stop (the guard does not just disable COMPACT) |
| `OvfScanStable.witness-skip` | with the fix, COMPACT skips a key it could have pulled |
| `OvfGuard.witness-pull` | the abstract pull during a stop |

## Dead expressions

| Line | cfg | Why never evaluated |
|---|---|---|
| `OvfScanStable.tla:56`, `OvfScanStable.tla:67` | every cfg with MVCC | TLC counts the arms of `Mvcc (o, from, to)` per caller: the `AddProt` arm is dead in the `DeleteS` and `CommitDel` contexts, the `UNCHANGED prot` arm in the `CommitIns` and `AbortDel` contexts; each arm is live in the other two |
| `OvfScanStable.tla:98`, `OvfScanStable.tla:99` | every cfg but `mutant-stale-check` | `CompactCheck`: the `stale_check` mutant only (`GMutant = "stale_check"`) |
| `OvfScanStable.tla:66`, `OvfScanStable.tla:68` | `no-mvcc-class` | `Mvcc` needs `~NoMvcc`: a class without MVCC has no MVCC state change |
| `OvfScanStable.tla:91`, `OvfScanStable.tla:92` | `no-mvcc-class` | `PullS` after `Guard`: the PR's class check refuses every pull (C4); `mutant-no-class-check` reaches it |
| `OvfScanStable.tla:107`, `OvfScanStable.tla:108`, `OvfScanStable.tla:133`, `OvfScanStable.tla:134` | `finishes` at NOid = 3 (first run only) | with three objects the chain never has two pages while the scan is stopped; the recorded `finishes` runs at NOid = 4 |

## Counterexamples and findings

| cfg | Classification | Evidence |
|---|---|---|
| `mutant-merge-base` | expected: H1 (CBRD-27972) on the merge-base behavior, depth 12 | JIRA runtime repro on develop `21c6e635d` (3/3 lost one row); `21c6e635d..953e83256` has no `btree.c` commit |
| `mutant-stale-check` | expected: the check passes in an earlier latch round (leaf stable), the leaf object is deleted and committed, the scan starts and stops, COMPACT pulls on the stale answer, vacuum swaps the pulled object into the leaf, the row is lost (depth 16) | model only |
| first `no-mvcc-class` run (`NoLostSwap`) | **pre-existing, outside the PR**: with physical deletes the scan's processed first page is deleted whole, the next page becomes the first, then the leaf's only object is deleted and the swap moves an unread object into the leaf; no COMPACT step in the trace (depth 9). Built-in indexes of MVCC-disabled classes (root, `db_serial`, `_db_collation`, `db_ha_apply_info`) are all PK/unique, which keep legacy chains and are never compacted. Not reproduced at runtime; asked of the author (grill decision) | model only |
| first `no-class-check` (`ExactlyOnce` passed vacuously) | model error: `vis` was protected for MVCC-disabled classes too; fixed by letting such objects go at any time and stating C4 as `NoCompactNoMvcc` | 884 states before the fix |

## Trace validation

Build: PR head `6cc3c42d4` + `tla-evidence-21c6e635d.patch` (CBRD-27972 attachment, applied cleanly) + one line
`tla_trace_ev ("a=CompactCheck first_page=%d|%d stable=%d", ...)` after the stable check, optdebug
`~/optdebug/CUBRID-pr8431-instr`, libcubrid fingerprint `71764065edf7d65e...`; worktree `~/dev/cubrid-worktree/pr8431-instr`
(uncommitted); conf `parallelism=1`, `max_parallel_workers=1`; runs `.git_ignored_dir/scratch/pr8431/run{A,B}`.

| cfg | Run | Result |
|---|---|---|
| `witness-trace-runA-skip` | JIRA h1_repro.sh unchanged (leaf object deleted and committed before the scan, vacuum gated, 8 s resume delay): `ScanStop`, `CompactCheck stable=0` on key 1, `Swap` of the anchor, `Resume`; 9,974/9,974 | accepted (`i = 5`) |
| `witness-trace-runB-pull` | h1b_repro.sh: the leaf object stays stable, COMPACT during the stop, then the leaf row deleted and vacuum opened, 20 s delay: `CompactCheck stable=1`, 4 `Pull`, `Resume`, then `Swap` (seq 71 after `Resume` seq 65); 9,975/9,975 | accepted (`i = 8`) |
| `reject-runA-flip` | run A with the check answer flipped to 1 | refused at `CompactCheck` (depth 2) |
| `reject-runB-swap-early` | run B with the `Swap` moved before the `Resume` | refused at `Swap`: the object was stable during the stop (`Protected`) (depth 7) |

## Bounds and limits

- Main: NOid = 4, NVer = 1, PageCap = 2, DirCap = 2 (leaf capacity 1, as `OvfDirChain`). Scale: NOid = 3, NVer = 2.
- `IndInv` inductiveness by Apalache on `OvfGuard` (booleans, no integer bound); the step from the code-level model to
  `OvfGuard` is TLC's refinement check inside the main bounds.
- Not modeled: a rebuilt READ COMMITTED statement snapshot (nested statement), scans without an MVCC snapshot,
  the crash between the swap's halves (CBRD-27973), the `pairs_skipped` / `keys_compacted` counters.
- TLAPS 요청 없음.

## Result

**미완** (2026-11-09, session stopped by the user before the scale and liveness cfgs finished and before the
whole-directory record run). Per-cfg runs (`tools/tla/tla-check --only`, run dirs `.git_ignored_dir/scratch/tla/ovf-compact-stable-20261109-*`):

| cfg | Verdict | states generated / distinct, depth |
|---|---|---|
| `OvfScanStable` (fix, invariants + `GuardRefined`) | pass (dead lines 56, 67, 98, 99, explained above) | 3,734,364 / 917,557, 35 |
| `OvfScanStable.no-mvcc-class` | pass (dead lines explained) | 73,959 / 19,201, 27 |
| `mutant-merge-base`, `-stale-check`, `-delid-stable`, `-uncommitted-stable`, `-env-vacuum-ignores-snapshot` | `ExactlyOnce` violated each | 57,505 / 22,792 d12; 1,067,181 / 310,569 d16; 409,897 / 142,249 d15; 52,402 / 20,220 d13; 415,632 / 139,722 d16 |
| `mutant-no-class-check` | `NoCompactNoMvcc` violated | 267 / 143, 7 |
| `mutant-resume-blocked` | liveness violated | 26,802 / 11,901, 10 |
| `witness-pull-while-susp`, `witness-skip` | reached | 7,018 / 2,803 d9; 651 / 342 d7 |
| `OvfGuard`, `OvfGuard.mutant-no-guard`, `OvfGuard.witness-pull` | pass, violated, reached | 45 / 9; 60 / 11; 32 / 8 |
| `OvfGuard.apalache-indinv` | pass (Apalache) | 22 s |
| 4 trace cfgs | 2 accepted, 2 refused (above) | |
| `OvfScanStable.scale-versions` | **stopped**: no violation in 13,320,474 distinct states (44,021,915 generated), queue 4,757,576 | |
| `OvfScanStable.finishes` (liveness, NOid = 4) | **stopped**: no violation in 165,284 distinct states, queue 92,269 | |

Left: run the scale and liveness cfgs to completion (each about 2 h at this host's load), then
`tools/tla/tla-check .claude/review/PR-8431/tla/ovf-compact-stable` once for the `RESULT:` line.
