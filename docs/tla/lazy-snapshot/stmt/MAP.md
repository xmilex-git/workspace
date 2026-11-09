# A statement's MVCC snapshot taken lazily: invalidation, the lock-free build, COUNT-star statistics, vacuum

The user's question (2026-11-09): CUBRID does not take the MVCC snapshot when a SELECT starts
executing; verify that no result can be wrong because of that, and if one can, show it.

`LazySnapshot.tla` models one reader transaction (READ COMMITTED or REPEATABLE READ, several
statements, each a fixed sequence of scans and optimized `COUNT(*)` reads), writers that commit
through `mvcctable::complete_mvcc`, the reader's lazy `build_mvcc_info` step by step, and vacuum's
oldest-visible computation. Counts are abstracted to the set of transactions whose rows they hold.
The parallel heap scan's page set is `docs/tla/lazy-snapshot/px-heap-coverage`; where a parallel
statement builds the snapshot is `docs/tla/CBRD-27967`.

Code: develop `2d928e34b` (worktree `~/dev/cubrid-worktree/develop-2d928e34b`).

## Claim and sources

| # | Claim | Source |
|---|---|---|
| C1 | A statement's snapshot includes every transaction whose commit was acknowledged before the statement began (READ COMMITTED), or before the transaction's first statement (REPEATABLE READ): the lazy build is never older than the statement. | manual `sql/transaction.rst:1329` (READ COMMITTED: "creates a new snapshot with each executed statement"), `:348` ("An MVCCID is invalid if it is not committed before the snapshot is taken"); `db_vdb.c:6524-6537` ("Snapshot is obtained with the first fetch or execution on server and should be invalidated before executing a new statement") |
| C2 | Every scan of a statement returns exactly what the statement's snapshot sees: vacuum never removed a version the snapshot, built late, still needs. | `mvcc_table.cpp:262-275` (the `MVCCID_ALL_VISIBLE` comment), vacuum's contract (`vacuum.c:3133`) |
| C3 | An optimized `COUNT(*)` answers for the same snapshot as the statement's scans. | `log_tran_table.c:4670-4673` ("The statistics will be loaded at snapshot"); CBRD-26705 (REPEATABLE READ falls back to a scan because the statistics bypass MVCC, `query_executor.c:34338-34345`) |
| C4 | A snapshot is the committed set at one instant: the set the current status held after some commit. | `mvcc_table.cpp:293` ("repeat steps until a trans_status can be read successfully without a version change"); manual `:297` ("point in time consistent view") |
| C5 | REPEATABLE READ: one snapshot for the whole transaction. | manual `:370`; `log_tran_table.c:4057` (no invalidation at REPEATABLE READ) |
| C6 | The reader's transaction ends (its builds do not retry forever). | the retry loop terminates once no writer refills the entry it read |
| C7 | Vacuum's threshold never moves back. | `mvcc_table.cpp:644` (`assert (m_oldest_visible.load () <= oldest_visible)`), `:262-275` |

## Refinement map (model -> code)

| Model | Code | One step because |
|---|---|---|
| `StmtBegin` | compile (`db_vdb.c:1768 pt_class_pre_fetch` -> `locator_sr.c:11971 logtb_tran_prepare_count_optim_classes`: classes of `SELECT COUNT(*) FROM t` marked `COS_TO_LOAD`), then `db_execute_statement`/`db_execute_and_keep_statement` (`db_vdb.c:5500, 5572`, CAS `cas_execute.c:1204` etc.) -> `db_invalidate_mvcc_snapshot_before_statement` sets `tm_Tran_invalidate_snapshot = 1` (`db_vdb.c:6549`, READ COMMITTED only) | client-side, before any server request of the execution |
| `Exec` | the first request after it carries the flag (`client_support.cpp:276/284`); `network_sr.c:924-927` -> `log_tran_table.c:4052 logtb_invalidate_snapshot_data`: READ COMMITTED, `valid = false` and `logtb_tran_reset_count_optim_state` (:4066-4067) | the request's thread before the request runs |
| `NeedBuild`, `ScanRead` | `scan_manager.c:4033/4141 scan_start_scan` -> `log_tran_table.c:4378 logtb_get_mvcc_snapshot`: builds when `!snapshot.valid` (:4397-4399); the scan's visibility check `mvcc_satisfies_snapshot` | the test and the build are one caller; parallel threads lock `m_px_lock_mutex` (CBRD-27967) |
| `CountRead` | `query_executor.c qexec_evaluate_aggregates_optimize`: marks the class `COS_TO_LOAD`, builds a snapshot if none, answers from the class's statistics (`query_aggregate.cpp btree_get_unique_statistics_for_count`); before the fix (`StatsFix = FALSE`) it also loads them late when they are not loaded (CBRD-26571) and uses them unchecked | under `m_px_lock_mutex` for parallel UNION branches |
| `BSlot` | `mvcc_table.cpp:276` slot := `MVCCID_ALL_VISIBLE` when it holds none | one atomic store |
| `BReadG` | `:283` (or `:290`) `crt_status_lowest_active = m_current_status_lowest_active_mvccid` | one atomic load |
| `BSetSlot` | `:285` slot := `crt_status_lowest_active` | one atomic store |
| `BPos` | `:294 index = m_trans_status_history_position.load ()` | one atomic load |
| `BVer` | `:299 trans_status_version = trans_status.m_version.load ()`; `TornFix` (candidate) also rejects an entry being refilled | one atomic load |
| `BCopy` | `:300 copy_to (THREAD_UNSAFE)`, one MVCCID's bit per step | plain reads of a buffer a writer may be refilling |
| `BStats` | `mvcc_table.cpp build_mvcc_info` -> `logtb_load_global_statistics_to_tran` -> `log_tran_table.c logtb_tran_load_global_stats_func` -> `logtb_get_global_unique_stats` (per-index mutex only): classes `COS_TO_LOAD` (with the fix also `COS_LOADING`, so a retry of the loop loads them again) become `COS_LOADED` before the fix, `COS_LOADING` with it | each class's load is one read of global statistics a commit publishes under its own mutex |
| `BCheck` | the version recheck of the copied entry ending the retry loop; `snapshot.valid = true` and, with the fix, `snapshot.status_version = trans_status_version` | one atomic load, then the reader's own fields |
| `BConf` | the fix: after the loop, `logtb_confirm_global_statistics (thread_p, trans_status_version)`: `COS_LOADING` -> `COS_LOADED` if `mvcctable::get_current_status_version ()` (`m_current_trans_status.m_version`) equals the snapshot's version, else -> `COS_TO_LOAD` (`logtb_tran_confirm_cos_func`) | one atomic load, then the transaction's own hash under `m_px_lock_mutex` |
| `CountLate`, `CountConf` | the fix, `qexec_evaluate_aggregates_optimize` when the class is not `COS_LOADED` on a valid snapshot: `logtb_load_global_statistics_to_tran` (late, `COS_LOADING`), then `logtb_confirm_global_statistics (thread_p, snapshot.status_version)`; still not `COS_LOADED` -> `is_scan_needed` (a scan answers) | the load reads global statistics, the confirm one atomic load; both under `m_px_lock_mutex` |
| `StmtEnd`, `TEnd` | end of the statement; the transaction's commit: `log_tran_table.c:4421 logtb_complete_mvcc`, `:4458 reset_transaction_lowest_active` | |
| `WBegin`, `WOp` | `get_new_mvccid` at the first change (`mvcc_table.cpp:578`); `heap_insert_logical` / `heap_delete_logical` | the MVCCID order against the begin order is left free (any permutation) |
| `WLock` ... `WUnlock` | `mvcc_table.cpp:466 complete_mvcc` under `m_active_trans_mutex`: `WStart` = `next_trans_status_start` (`:449` version stored first), `WStats` = `:477 logtb_tran_update_all_global_unique_stats`, `WInactive` = `:483 set_inactive_mvccid`, `WFill` = `next_tran_status_finish` copy (one bit per step), `WPos` = `:461` position store | each a separate store; readers take no lock |
| `WAdvance` | `:520-536` after the mutex: lowest active of the published entry, kept if `m_version` still equals its version, `advance_oldest_active` (CAS max); the model takes any lower bound of the entry's lowest active | the code's exact value is one of them |
| `WAck` | `log_manager.c:5300 log_append_commit_log` ... the client's answer | |
| `VReadG`, `VSlot`, `VStore` | `vacuum.c:3038` -> `mvcc_table.cpp:637 update_global_oldest_visible` -> `:360 compute_oldest_visible_mvccid`: G first (:364), then each slot, waiting while one holds `MVCCID_ALL_VISIBLE` (:371, :395); `:645` store | atomic loads; one vacuum master |
| `VRemove(r)` | `vacuum.c:3133` a block is vacuumed only when its newest MVCCID precedes the threshold; `vacuum_heap_page` removes the version | under the page latch |
| trace events | `traces/probe.diff`: `Invalidate` (`logtb_invalidate_snapshot_data`), `Build` (end of `build_mvcc_info`), `StatsLoad` (`logtb_create_unique_stats_from_repr`, `where=build|late`), `StatsPublish`, `Complete` (inside `complete_mvcc` under the mutex), `OldestVisible` | inside each step |

## Properties

| Name | Kind | Statement | Claim |
|---|---|---|---|
| `NoStaleRead` | invariant (ghost `badStale`, set at a scan) | the writers acknowledged before the statement are in the snapshot | C1 |
| `ScanMatchesSnapshot` | invariant (`badScan`) | a scan returns `{r : Visible(r)}` (no visible version removed) | C2 |
| `CountMatchesSnapshot` | invariant (`badCount`) | the loaded statistics hold exactly the snapshot's writers | C3 |
| `ConsistentCut` | invariant (`badCut`, set at `BCheck`) | the snapshot's committed set is a value `histv[v]` the current status held | C4 |
| `RRStable` | invariant (`snapChanged`) | no rebuild after the first statement under REPEATABLE READ | C5 |
| `ReaderEnds` | liveness, WF on the reader and each writer | `<>(rpc = "end")` | C6 |
| `OVMonotone` | invariant (`badOV`) | `VStore` never stores a smaller threshold | C7 |
| `IndInv` | inductive invariant of the fixes | implies C1-C5 and C7 (Apalache: inductive at `CInit`) | C1-C5, C7 |

## Fault model

| Fault | Modeled as |
|---|---|
| commits at any point of a build (between any two of its loads, during the copy) | writers' steps interleave freely |
| the history ring wraps during a build | `H = 2` in the main and `witness-torn-copy` cfgs; `code-*` use `H = 4` (no wrap within two commits, as 2048 in the code needs 2048 commits) |
| a build's retry | `BVer` (busy, `TornFix`) and `BCheck` failures go back to `BReadG` |
| a statement executed with no invalidation (a path that does not set the flag) | `mutant-no-invalidate`; every `db_execute_*` entry sets it (`db_vdb.c:5500, 5572, 5700, 5727, 5741`) |
| several statements per transaction; snapshot valid at the next statement's first request | `NStmt = 2`; `Exec` invalidates and resets the count state |
| vacuum racing the reader's slot | `VReadG`/`VSlot`/`VStore` at every point, waiting on `MVCCID_ALL_VISIBLE` |
| an SP's SQL invalidating the snapshot mid-statement | not modeled: `docs/tla/CBRD-27967` D6 (measured on develop: the outer statement continues on the nested statement's snapshot) |
| parallel threads of one statement building the snapshot | not modeled here: `docs/tla/CBRD-27967` (`m_px_lock_mutex`) and `docs/tla/lazy-snapshot/px-heap-coverage` |
| rollback | not modeled: a rolled-back writer completes with `committed = false` and its versions are undone; the reader treats it as completed and its rows as never inserted/deleted |
| crash between `complete_mvcc` and `LOG_COMMIT` (`log_manager.c:5255` before `:5300`) | not modeled: the reader's results die with the server; recovery is out of this question's scope |
| a writer's own slot (`complete_mvcc :497-510`) | not modeled: it only holds vacuum back further |
| a commit by a transaction with no MVCCID publishing unique statistics (`log_tran_table.c logtb_complete_mvcc`, the `else` branch) | not modeled: without an MVCCID it changed no MVCC row; the version is not raised there, so statistics of non-MVCC (catalog) classes can move under a confirmed load, as their scans see the latest committed rows anyway |
| statistics deltas of an index being built online (`log_manager.c` `btree_is_btid_online_index` branch) | not modeled: an index under construction is not chosen for the COUNT-star optimization, and its class's DDL lock excludes the reader's statement |
| the order of the version raise and the statistics publish as seen by the reader | the writer raises `m_current_trans_status.m_version` (seq_cst `fetch_add`, `next_trans_status_start`) before `logtb_tran_update_all_global_unique_stats` publishes under each index's mutex; the reader reads the statistics under the same mutex, then loads the version (seq_cst): a publish the reader saw implies the raise is visible to its version load |
| interrupt, lock timeout, OOM in the build | not modeled: `logtb_load_global_statistics_to_tran` failing sets `ER_MVCC_CANT_GET_SNAPSHOT` and the build proceeds (`:303-307`); the statement fails or the class stays not loaded |

## Mutants

| cfg | Change | Expected | Kills |
|---|---|---|---|
| `mutant-no-invalidate` | the client never sets the flag | `NoStaleRead` violated | C1 |
| `mutant-vacuum-ignores-slot` | vacuum's threshold ignores the reader's slot | `ScanMatchesSnapshot` violated | C2 |
| `mutant-stats-outside-status` | the statistics are global, loaded apart from the status (the code) | `CountMatchesSnapshot` violated | C3 |
| `mutant-no-recheck` | the build accepts its copy without the version recheck | `ConsistentCut` violated | C4 |
| `mutant-pos-before-fill` | a commit publishes the position before filling the entry | `ConsistentCut` violated | C4 |
| `mutant-rr-invalidate` | REPEATABLE READ invalidates at each statement | `RRStable` violated | C5 |
| `mutant-busy-stuck` | an entry stays busy after its commit | liveness (`ReaderEnds`) | C6 |
| `mutant-build-no-conf` | the build's statistics become `COS_LOADED` without the version check | `CountMatchesSnapshot` violated | C3 |
| `mutant-late-no-conf` | the late load's statistics become `COS_LOADED` without the version check | `CountMatchesSnapshot` violated | C3 |
| `mutant-pos-check` | the check compares the version of the entry at the history position instead of the current status version (an in-flight commit has raised the latter and published its statistics, not yet the former) | `CountMatchesSnapshot` violated | C3 |
| `mutant-no-allvisible` | the slot is set straight to G, without `MVCCID_ALL_VISIBLE` first | `OVMonotone` violated | C7 |
| `mutant-vacuum-no-wait` | vacuum does not wait on `MVCCID_ALL_VISIBLE` | `OVMonotone` violated | C7 |

## Witnesses

| cfg | Reached state |
|---|---|
| `witness-torn-copy` | the code with a ring of 2 entries: a build copies an entry while a later commit refills it and accepts the copy (Q1) |
| `LazySnapshotTrace.witness-trace-count-run3-on-code` | the recorded H3 run is a behavior of the code |

## Findings

| # | Finding | Evidence |
|---|---|---|
| H3 | READ COMMITTED, optimized `COUNT(*)`: the global unique statistics are loaded after the status copy and outside `m_active_trans_mutex`, and `build_mvcc_info`'s version recheck only detects a ring wrap, not a newer commit. A commit landing between `copy_to` (`mvcc_table.cpp:300`) and `logtb_load_global_statistics_to_tran` (`:303`) is counted by `COUNT(*)` but invisible to the same statement's snapshot. The late load added by CBRD-26571 (`query_executor.c:34404-34411`, when the class was not `COS_TO_LOAD` at the build) widens the window to the time between the build and the count. | `code-rc.cfg`: `CountMatchesSnapshot` violated. Runtime on the probe build (optdebug libcubrid `22f9a67d…`, `CUBRID_TLA_BUILD_STATS_WAIT_MS=4000` holds the build after the copy until a commit publishes): `SELECT (SELECT COUNT(*) FROM t WHERE id >= 0) AS c_scan, (SELECT COUNT(*) FROM t) AS c_opt` returned `c_scan = 100, c_opt = 101` in 3 of 3 runs while session B inserted one row; run 3's events: A `Build` copied `pos=4`, B `StatsPublish`/`Complete pos=5`, A `StatsLoad oids=101 where=build`, A `Build lowest=89 hi=89` (B's MVCCID 89 invisible). Elapsed: A 5.26 s, B 4.26 s after its start (both held by the injection). The late-load path was observed too (`StatsLoad where=late` right after a build) but its window closed before B committed in these runs. |
| H3 fix (decided 2026-11-09, PR #8438) | statistics loaded by the build or late are `COS_LOADING` until `logtb_confirm_global_statistics` finds the current status version equal to the snapshot's (`snapshot.status_version`); a mismatch puts the class back to `COS_TO_LOAD` and `COUNT(*)` scans. Rejected: loading under `m_active_trans_mutex` (class representation and partition lookups under the commit mutex), retrying the build, turning the optimization off under READ COMMITTED; and checking the entry at the history position (`mutant-pos-check`) | `StatsFix`: main, `rr`, `pr-rc` (`TornFix = FALSE`, the PR's code), scale cfgs pass; mutants above killed |
| Q1 | (question, not reproduced) The history entry's version is stored before its data (`next_trans_status_start`, `:449`) and the reader compares the version it loaded with itself (`:299`, `:309`). If the ring of 2048 entries wraps between the reader's position load (`:294`) and its version load, the reader can load the new version, copy a half-refilled entry, and accept it: a snapshot that sees a later commit and misses an earlier one. Needs 2048 commits between two adjacent atomic loads of one thread. | `witness-torn-copy` (ring of 2 entries, 2 writers) reaches it; `TornFix` (an entry marked busy while refilled, rejected at both loads) passes. No runtime reproduction attempted. |
| — | Lazy acquisition itself (C1, C2, C5, C7) holds on the code: a statement's snapshot is never older than the statement, and vacuum's `MVCCID_ALL_VISIBLE` handshake keeps every version a late-built snapshot needs. | `code-rc`/`code-rr` pass those invariants |

Related, outside this model: CBRD-27967 (parallel heap scan collects pages before the READ COMMITTED snapshot; fix PR #8438 not in develop `2d928e34b`), CBRD-27967 D6 (an SP's SQL changes the outer statement's snapshot), and H2 of `docs/tla/lazy-snapshot/px-heap-coverage`.

## Dead expressions (pass cfg)

| Line | Why never evaluated |
|---|---|
| LazySnapshot.tla:274 | `WAdvance` finding its entry refilled: needs two more commits after the advancing writer's within a ring of 2, so three writers; `scale-3-writers` fires it |
| LazySnapshot.tla:304 | `Exec` invalidating a valid snapshot: REPEATABLE READ never sets the flag (`rr`, `code-rr`), and with one statement (`scale-3-writers`) no snapshot exists at the first request; the main cfg fires it at the second statement |
| LazySnapshot.tla:333, LazySnapshot.tla:334, LazySnapshot.tla:335, LazySnapshot.tla:336 | `CountRead` under REPEATABLE READ (`rr`, `code-rr`): `Kind` turns COUNT-star into a scan, as `query_executor.c qexec_evaluate_aggregates_optimize` falls back to one for `isolation >= TRAN_REPEATABLE_READ`; the RC cfgs fire it |
| LazySnapshot.tla:372 | `BVer` rejecting a busy entry with no `TornFix` (`pr-rc`, `code-rr`, `code-rc`): the code has no busy mark; the main cfg fires it |
| LazySnapshot.tla:392, LazySnapshot.tla:393 | `BStats` loading statistics under REPEATABLE READ: no class is marked (no COUNT-star optimization) |
| LazySnapshot.tla:394 | `BStats` with nothing to load in `scale-3-writers`: with one statement whose program holds a COUNT-star, the class is always marked (or still `COS_LOADING` on a retry) when the build reaches it; the main cfg fires it at the second statement |
| LazySnapshot.tla:408, LazySnapshot.tla:409 | `BCheck`'s retry with `H = 4` (`pr-rc`, `code-rr`): with two commits the ring never wraps, so the entry a build read is never refilled; the main cfg (`H = 2`) fires it |
| LazySnapshot.tla:422, LazySnapshot.tla:425, LazySnapshot.tla:426 | `BConf` in `code-rr` (and `code-rc`): the code has no statistics check after the build (`StatsFix = FALSE`, `BCheck` goes straight to `op`); the fix cfgs fire it |
| LazySnapshot.tla:433, LazySnapshot.tla:434 | `CountLate` under REPEATABLE READ (`rr`): no COUNT-star optimization; the RC fix cfgs fire it |
| LazySnapshot.tla:441, LazySnapshot.tla:442, LazySnapshot.tla:443, LazySnapshot.tla:444, LazySnapshot.tla:445, LazySnapshot.tla:446, LazySnapshot.tla:447, LazySnapshot.tla:448, LazySnapshot.tla:449 | `CountConf` under REPEATABLE READ (`rr`): reached only from `CountLate`; the RC fix cfgs fire both branches |

## Bounds and limits

- TLC: 2 writers, 1 initial row, 2 statements of `<<scan, count>>`, ring of 2 entries, 2 vacuum rounds; `scale-3-writers` 3 writers.
- Apalache (`apalache-indinv`): `IndInv` inductive with 2 writers, ring of 2, 2 statements of 2 reads, both isolation levels, the vacuum budget open.
- TLAPS: not complete for the decided fix (see Result); C1-C7 are TLC-bounded, IndInv Apalache-inductive at `CInit`.
- MVCCIDs are assigned to writers in any order (an over-approximation of `get_new_mvccid`'s order), the advance of G takes any lower bound of the published entry's lowest active, and a writer commits once (`curVer <= NW`).

## Trace validation

Probe = `traces/probe.diff` on develop `2d928e34b` (the count runs used the build before the worker-delay probe was added: optdebug libcubrid `22f9a67d…`). `traces/count-run3.log` is run 3 of the H3 reproduction, projected onto the reader's statement (its `Invalidate`, `StatsLoad`, `Build`) and the writer's commit (`StatsPublish`, `Complete`); the writer's own snapshot events are left out (writers do not read in the model). MVCCIDs, positions and versions are shifted by the run's bases (`IdBase = 89`, `PosBase = 4`, `OidsBase = 100`). The fix runs used PR #8438 head `9286face3` + the same probe + a `Confirm` line in `logtb_confirm_global_statistics` (scratch worktree `~/dev/cubrid-worktree/CBRD-27967-instr`, optdebug libcubrid `44f2ce35…`, `CUBRID_TLA_BUILD_STATS_WAIT_MS=4000`); `traces/count-fix-run1.log` is its run 1, projected the same way. The earlier `reject-count-run3-on-fix` cfg was dropped: the fix accepts run 3's events up to its build (the load is legal; the confirm, which run 3 does not log, discards it).

| cfg | Run | Result |
|---|---|---|
| `LazySnapshotTrace.witness-trace-count-run3-on-code` | run 3 | accepted by the code (`StatsFix = FALSE`) |
| `LazySnapshotTrace.witness-trace-count-fix-run1-on-fix` | run 1 of the fix | accepted by the fix: `StatsLoad oids=101 where=build` -> `Confirm ver=1 cur=2 ok=0 where=build` -> `Build` -> `StatsLoad where=late` -> `Confirm ok=0 where=late` (the count scans) |
| `LazySnapshotTrace.reject-count-fix-run1-corrupt-on-fix` | run 1 of the fix with the build's `Confirm` set to `ok=1` | refused: the current version (2) is past the snapshot's (1), so the fix cannot keep the statistics |

## Result

2026-11-09 (after the H3 fix decision), `tools/tla/tla-check --workers 12 docs/tla/lazy-snapshot/stmt`, run dir
`.git_ignored_dir/scratch/tla/stmt-20261109-085514-711226`: every mutant, witness, trace and Apalache cfg ended as expected, and
`code-rc` fails as recorded (cubrid-tla P9: develop READ COMMITTED, `CountMatchesSnapshot` violated at depth 20, H3, fixed by PR #8438's
second commit). That run also failed `rr` and `code-rr` on actions REPEATABLE READ never fires (no `uncovered-ok` lines yet) and
`scale-3-writers` on one unexplained dead line (394); after adding the `uncovered-ok` lines to the two cfgs and the line to the dead
expressions table, `rr` and `code-rr` were rerun with `--only` and pass; `scale-3-writers` (3879 s) was not rerun: only MAP.md changed for it,
and its states, depth and dead lines are those below. The spec is the same in both runs.

| cfg | Result | States / distinct | Depth |
|---|---|---|---|
| `LazySnapshot` (`StatsFix`, `TornFix`, ring of 2) | pass | 7,593,617 / 2,329,180 | 65 |
| `rr` | pass | 2,259,520 / 686,515 | 56 |
| `pr-rc` (`StatsFix`, no `TornFix`, ring of 4: the PR's code) | pass | 6,417,125 / 1,971,868 | 65 |
| `scale-3-writers` | pass | 109,641,560 / 27,476,760 | 66 |
| `code-rc` (develop READ COMMITTED) | **`CountMatchesSnapshot` violated (H3)** | 37,481 / 12,384 | 20 |
| `code-rr` (develop REPEATABLE READ) | pass | 1,825,312 / 557,539 | 53 |
| 13 mutants | each violates its property (see Mutants; `mutant-busy-stuck` liveness) | | |
| `witness-torn-copy` | reached (Q1) | 277,633 / 91,364 | 30 |
| `apalache-indinv` | IndInv inductive | — | 1 step |
| `LazySnapshotTrace.witness-trace-count-run3-on-code` | accepted | 538 / 316 | 23 |
| `LazySnapshotTrace.witness-trace-count-fix-run1-on-fix` | accepted | 717 / 408 | 28 |
| `LazySnapshotTrace.reject-count-fix-run1-corrupt-on-fix` | refused | 593 / 336 | 23 |

TLAPS: not complete; stopped by the user's decision on 2026-11-09 (TLC, Apalache and trace validation are the record). The proof for the
earlier candidate fix (statistics stored in each history entry) reached 4716 of 4993 obligations (SMT timeouts). A proof of the decided fix
(generator `.git_ignored_dir/scratch/lazysnap/gen/genproof_a5.py` + `overrides_a5.py`, with lemmas `NoFlightStats`, `SnapCommitted`,
`CountOK`, `ScanOK`, `StaleOK`) proved 4097 of 4103 obligations for the reader's and the fix's actions and WLock/WStart; the full module was not
finished, so no proof module is in this directory. C1-C7 hold here
inside the TLC bounds above, and IndInv is inductive by Apalache at the `CInit` constants.

Spec sha256: `LazySnapshot.tla` ea247d9d750d4e9a0877aaac730a1757c537d0d46b3c54fc4d2b8726df9ee037,
`LazySnapshotTrace.tla` 001e42d787130278657be5138f2d5e4e5f95adeb6b0a1039aed470d2dd1c8317,
`LazySnapshotTraceData.tla` 65386ed35294832fca6cafe9b87542237a80e73060b0036d3f3fb41175c1752d.
Engine: develop `2d928e34b` (probe build optdebug libcubrid `22f9a67d…` for the H3 runs); the fix, PR #8438 head `9286face3` (probe build
optdebug `44f2ce35bedc39fbe413fc311b24c1503b8365f98e26860a379663921a15165b`; gate builds without the probe optdebug
`1d0060deb893b339207d3fcefdf24dbe7c9eddbecf87e43b507a6e4c3d53c2f2`, release `d829c43b959bd64910689462c0401abe92b16db6a83553bbadf3fb3d91f906a0`).
