# FuncIdxCover — function index covering, key filter and routing decisions (PR #6466, CBRD-25984)

Engine head `f1f4f21ea` (worktree `~/dev/cubrid-worktree/pr6466-review`), merge-base `4e389935d`.
The change is a decision table spread over three layers that one thread runs in order for one query:
the optimizer decides covering and key filters per index entry, XASL generation drops covering for scans
under a list file and routes the indexed expression F to a pseudo attribute that reads the result kept in
the key, and the executor reads either that result or the raw argument. No state is shared between
threads (a parallel index scan worker runs its own XASL clone with the same regu lists), so the model
explores the inputs: the index shape, where the query uses F and its argument, the statement kind, the
result domain, the plan context, and whether rows share a key value that is not their own F value.

## Claim and sources

| # | Claim | Source |
|---|---|---|
| C1 | A function index scan covers a query that reads F (projection, key range, key filter) when the argument appears only inside F and the result is exact, and a covered scan that feeds the query directly reads F from the key. | JIRA CBRD-25984 body (Q2, Q4: covered scan and key filter); PR Purpose |
| C2 | Every consumer of F gets the value develop computes (`NO_COVERING_IDX` / `using index none` answer): projection, key filter, outer join ON / after-join terms, join and subquery terms, a self-join expression that prints like F, with no error and no abort. | PR Remarks ("결과 정확성은 NO_COVERING_IDX ... 대조"); JIRA AC; review threads 4476238580, 4476238599, 4476238604, 4476238824, 4476238977 (all accepted by the author) |
| C3 | A non-covering function index scan keeps a key filter on F when the result can be read from the key (routable statement, exact result). | PR Implementation `qo_index_forbids_key_filter`, `make_pred_from_plan` (commit 0cb8b988a) |
| C4 | Statements that re-read rows from the heap (UPDATE/DELETE/FOR UPDATE targets, click counter, CONNECT BY) never read the pseudo result. | PR Implementation `qo_is_func_index_routable`; heap_file.c assert in `heap_attrvalue_read` |
| C5 | A list-file plan (hash/merge input, sort under a join, sort-limit) turns covering off when the key lacks the argument, and a loose scan goes with it. | PR Implementation `pt_uncover_func_index_scans`; review thread 4476238824 |
| C6 | A plain index on the argument covers a query that reads F (F is recomputed from the key column). | PR Implementation `qo_is_coverage_index` (commit f1f4f21ea) |
| C7 | A function index whose expression the query does not read is decided as develop (FOR UPDATE / DELETE keep `(covers)` + key filter). | Review thread 4476238593, author reply 4477277719 (commit 814233513) |
| C8 | Under a concurrent UPDATE (commit or rollback) and vacuum, a covered projection and a non-covered key filter that read F from the key return what develop returns from the snapshot's heap version: the row once iff its snapshot version passes, never a version the snapshot cannot see, never a version vacuum removed. | PR Remarks ("클라이언트-서버 모드 2세션 ... MVCC 재평가와, 커버링이 아닌 키 필터를 쓰는 비잠금 조회의 커밋 전후 결과가 정확함"); JIRA A/C 4; user request 2026-11-06 (review grill Q5) |

## Refinement map (model -> code)

| Model | Code (f1f4f21ea) | One step because |
|---|---|---|
| `Plan` cover | `query_graph.c:qo_is_coverage_index` (7668): seg loop (7711-7788) with `QO_SEG_FUNC_INDEX` skip (7768) and `qo_seg_used_only_in_func_index` (7441) for an argument missing from the key; function index block (7790-7839): `qo_find_func_index_seg` NULL -> true, `qo_is_func_index_routable` (7584), type/collation gates, `qo_is_func_index_key_result_exact` (7612: `qo_is_session_dependent_expr` 7558, `fi_domain`), sarg-class term loop (7825-7838) | runs once per index entry in `qo_discover_indexes` (8387) on the client, single thread, before any plan |
| `Plan` mixed | `qo_seg_used_raw_walk` (7318): a printed match is skipped only when `pt_is_join_expr` is false and its spec is the column's spec | part of the cover decision |
| `Plan` kf | `query_planner.c:qo_index_forbids_key_filter` (2177) via `qo_is_func_index_key_filter_routable` (7642); `plan_generation.c:make_pred_from_plan` (2020) same predicate for the MRO forced copy | one call per scan plan |
| `Gen` icover, loose | `xasl_generation.c:pt_uncover_func_index_scans` (9887): a covered function index scan under a list file with a node segment missing from the key loses `index_cover` and `index_loose` | called from `pt_collect_func_index_cover` in `pt_to_buildlist_proc` before the spec list is built |
| `Gen` fic | `pt_make_func_index_cover` (9833): routable, F segment present, pseudo attribute added | one call per class spec |
| `Gen` rsel | `pt_collect_func_index_cover` (9960) registers covered scans read directly (not under SORT-LIMIT, merge/hash, NL outer sort), skipped for GROUP BY / aggregates (`pt_to_buildlist_proc`) | |
| `Gen` rkf | `pt_to_class_spec_list`: key filter built with `func_idx_cover_list = fi_cover`; `pt_remove_func_index_attrs` (10174) KEY_ARGS / COVERED_ARGS / RESULT | |
| `Exec` projection | `btree.c:btree_attrinfo_read_dbvalues` (20545) `FUNC_INDEX_RESULT_ATTRID` -> `midxkey[func_index_col_id]`; `scan_manager.c:scan_dump_key_into_tuple` (8852) MRO passes `indx_cov.func_index_col_id` | a read of one key, no latch held across rows that the decision depends on |
| `Exec` key filter | `query_evaluator.c:eval_key_filter` (3432) `is_func_result` reads `midxkey[func_idx_col_id]` | |
| `Exec` err | `heap_file.c:heap_attrvalue_read` (11615) asserts and fails on the pseudo attribute | |
| `Exec` abort | `plan_generation.c:qo_is_index_loose_scan` (3790) `assert (index_cover == true)` | |
| `stale` | B-tree keeps one key per group of equal keys; the stored value is the first row's (`btree.c` key insert appends OIDs to an equal key) | environment input |

## Properties

| Name | Kind | Statement | Claim |
|---|---|---|---|
| `TypeOK` | invariant | variable types | — |
| `Equiv` | invariant | after execution every row's consumers are right, no error, no abort | C2, C4, C5 |
| `CoverWhenSafe` | invariant | the JIRA case is covered | C1 |
| `RouteWhenSafe` | invariant | its direct projection is routed | C1 |
| `KfWhenSafe` | invariant | non-covering key filter on an exact routable F | C3 |
| `PlainCover` | invariant | plain index on the argument covers | C6 |
| `NoFAsDevelop` | invariant | F not read -> develop's cover decision | C7 |
| `IndInv` | inductive invariant | decisions equal their defining formulas phase by phase; Apalache-inductive and proved by TLAPS | C1-C7 |

## Fault model and environment assumptions

| Item | Modeled as / why not |
|---|---|
| error return (OOM in `pt_add_func_index_result_attr`, `pt_make_val_list`, `pt_alloc_packing_buf`) | not modeled: `pt_make_func_index_cover` returns NULL, so nothing is routed; a covered scan whose F was not routed reads the argument from the key and fails the query (`btree_attrinfo_read_dbvalues` ER_GENERIC_ERROR) rather than return a wrong value |
| interrupt, lock timeout, deadlock, crash, vacuum, checkpoint, HA | not applicable: compile-time decisions; at run time the key read is the same as a covered plain column (MVCC visibility from the key's OID, unchanged) |
| concurrent DML on a covered row | same as develop's covering of plain columns; non-covered key filter rows are fetched from the heap after the filter (unchanged MVCC path) |
| statement re-evaluation (UPDATE/DELETE/FOR UPDATE, click counter, CONNECT BY) | modeled: `heapStmt`; err when the pseudo attribute reaches the heap re-read |
| signed zero (`-0.0` and `0.0` compare equal and share a key) | modeled: `negZero` under constant `NegZero`; head has no gate: `FuncIdxCover.negzero.cfg` is the hole, `fix-negzero` the candidate gate |
| trailing spaces in a string result | not a merge: probe `p1.sql` B on f1f4f21ea showed `'a'` and `'a  '` as two keys (develop and head same answers) |
| single-column function index key, raw argument requested | not modeled: no head path asks a single-column key for the raw argument (covering needs the argument only inside F, which removes it from the rest list when routed, and a list-file scan is uncovered); the `btree_attrinfo_read_dbvalues` check turns such a request into an error, defense only |
| parallel index scan | same decisions; the PX leaf walker passes `func_index_col_id` like the serial scan (unchanged since the 11-04 review) |
| other columns of the query | `extraCol`: a column that is neither key nor argument; other key columns are assumed in the key |
| session dependence beyond the listed operators (`tz_offset`) | outside: time-dependent rather than session-dependent; recorded, not modeled |

## Mutants

| cfg | Change | Expected | Kills |
|---|---|---|---|
| `mutant-develop` | merge-base: F used -> no covering, no non-covering key filter, no routing | `CoverWhenSafe` | C1 |
| `mutant-no-sarg-class` | 05b46aefe: any single-node term skipped (outer join during/after) | `Equiv` | C2 |
| `mutant-no-join-expr` | 05b46aefe: a self-join expression printed like F counts as F | `Equiv` | C2 |
| `mutant-no-domain-gate` | no `fi_domain` covering/collation gate | `Equiv` | C2 |
| `mutant-no-session-gate` | no `qo_is_session_dependent_expr` | `Equiv` | C2 |
| `mutant-gate-before-fseg` | 05b46aefe: routable gate also for an index whose F is not read | `NoFAsDevelop` | C7 |
| `mutant-loose-kept` | d7ce3af72: uncover keeps `index_loose` | `Equiv` (abort) | C5 |
| `mutant-mro-minus1` | 05b46aefe: `scan_dump_key_into_tuple` passes -1 | `Equiv` (err) | C1, C2 |
| `mutant-no-uncover` | no `pt_uncover_func_index_scans` | `Equiv` | C5 |
| `mutant-no-routable` | no `qo_is_func_index_routable` | `Equiv` (err) | C4 |
| `mutant-kf-no-exact` | non-covering key filter without the exact-result check | `Equiv` | C3 |
| `mutant-kf-develop` | a7185cdf4: non-covering function index forbids every key filter | `KfWhenSafe` | C3 |
| `mutant-plain-no-skip` | 18e0dd3e3: a plain index rejects a query that reads F | `PlainCover` | C6 |
| `FuncIdxMvcc.mutant-no-snapshot` | the entry's MVCC ids are not tested against the snapshot | `NoWrongRow` | C8 |
| `FuncIdxMvcc.mutant-heap-latest` | the heap fetch reads the latest committed version | `NoWrongRow` | C8 |
| `FuncIdxMvcc.mutant-vac-early` | vacuum ignores the active snapshot | `ResultOK` | C8 |

## Witnesses

| cfg | Reached state |
|---|---|
| `witness-routed-cover` | a covered scan reads F from the key for its projection |
| `witness-noncover-kf` | a non-covered scan reads F from the key in its key filter |
| `witness-uncovered` | a covering decision dropped under a list file |
| `witness-plain-cover-with-f` | a plain index covers a query that reads F |
| `witness-stale-safe` | a row whose key value is not its own F is answered from the heap |

## Counterexamples

| cfg | Class | Trace | Runtime |
|---|---|---|---|
| `negzero` (expect pass, fails `Equiv`) | Hole H1: every step maps to code. `qo_is_func_index_key_result_exact` passes a DOUBLE result; the B-tree keeps one key for `-0.0` and `0.0` (equal by compare); `rsel`/`rkf` read the first row's value for the second row | Init `funcIdx, useF, fInSel or fInSarg, negZero, stale[2]`; Plan `cover`/`kf`; Gen `rsel`/`rkf`; Exec `ok[2] = FALSE` | reproduced: `(i, ceil(d))` rows `-0.5`, `0`; head optdebug and release return `'-0'` twice, the key filter `= '0'` returns 0 rows, `NO_COVERING_IDX` + `like '-%'` 2 rows; develop `'-0','0'`, 1, 1 (`.git_ignored_dir/scratch/pr6466/r3/p1.*`) |

The candidate fix, `fix-negzero` (the result gate also refuses a result domain whose equal keys can differ in sign, FLOAT/DOUBLE), passes. It costs covering for every FLOAT/DOUBLE function result (`sqrt`, the PR's main case); the author decides between it, a narrower gate (functions that can yield `-0`), or recording the plain-column precedent.

## Dead expressions (pass cfg)

None reported by `tools/tla/tla-check` for `FuncIdxCover.cfg` and `FuncIdxCover.scale-3rows.cfg`.

## Bounds and limits

- TLC main: every combination of the 18 input booleans that satisfies `InputOK`, NR = 2 rows (196 608 distinct states, depth 4). Scale: NR = 3 (344 064).
- Apalache inductive: `IndInv /\ Next => IndInv'` at NR = 2, every other input symbolic.
- TLAPS: `InitInv`, `StepInv` (one lemma per action), `InvSafe` (`IndInv => Equiv /\ CoverWhenSafe /\ RouteWhenSafe /\ KfWhenSafe /\ PlainCover /\ NoFAsDevelop`) and `SpecSafe` (`Spec => []IndInv`) for Mutant = "none" under NegZero = FALSE, for every NR >= 1: 70/70 obligations on tlapm efe4f2d. The environment assumption NegZero = FALSE is exactly the hole H1.
- Not modeled: other columns of the key beyond F and its argument (assumed key columns), two scan nodes of one query reading F (the NL outer/inner routing is per spec id; self-join mixing is the `mixed` input), the cost model (soheejung-cs 4476238835).

## Trace validation

- Build: scratch worktree `~/dev/cubrid-worktree/pr6466-tlatrace` = f1f4f21ea + `tla_trace` (porting.c) called in `pt_to_class_spec_list` (Gen: cover_segments, index_cover after uncover, key filter present, fi_cover, routed, loose), `btree_attrinfo_read_dbvalues` (KeyRead on the pseudo attribute, MIDXKEY and single key) and `eval_key_filter` (KfRead); optdebug `~/optdebug/CUBRID-pr6466-tlatrace`, libcubrid.so `97140e48...`; SA mode, one csql per query.
- Data: `.git_ignored_dir/scratch/pr6466/trace/setup.sql` (t `(i, j, sqrt(d))` 2 rows, u, t3/t4 `(k, sqrt(d))`, tz `(i, to_datetime_tz(s))`, pd with `(d)` and `(sqrt(d))`).
- Hidden actions: Plan, Exec.

| cfg | run | verdict |
|---|---|---|
| `witness-trace-cover` | `select j, sqrt(d) from t where i > 0 and sqrt(d) > 1` (Gen, KfRead, KeyRead, KfRead) | accepted |
| `witness-trace-kf` | `select p from t where i > 0 and sqrt(d) > 1` (non-covering key filter, 2 KfRead) | accepted |
| `witness-trace-hash` | `/*+ use_hash */ t.j, sqrt(t.d), u.k ... t.i = u.k` (covered, then uncovered) | accepted |
| `witness-trace-upd` | `select i, j from t where i > 0 for update` (F not read: develop decision) | accepted |
| `witness-trace-outer` | `t3 left join t4 ... where sqrt(i.d) is null` (after-join term: no cover) | accepted |
| `witness-trace-tz` | `select i, to_datetime_tz(s) from tz where i = 1` (domain gate) | accepted |
| `witness-trace-plain` | `select sqrt(d) from pd where d > 0 using index i_d` (plain index covers) | accepted |
| `reject-cover-flipped` | `cover` run with `cover=1` changed to `cover=0` | refused |

Not covered by a run: `mixed`, `agg`, `mro`, `looseHint`, `sess` inputs (each is reached by TLC and by the TC PR's `[11-*]`, `[12-*]` cases, not by an instrumented run).

## Result

- 2026-11-06, `tools/tla/tla-check --prove --workers 8`, toolchain `mcnrlar201f0kiwhaz2d8pfxhbl6h3zb-tla-tools`: `RESULT: FAILED (1)`, run dir `.git_ignored_dir/scratch/tla/func-index-cover-20261106-105552-3585712`. The one failure is `FuncIdxCover.negzero` (hole H1, kept failing per cubrid-tla P9); every other cfg and the proof pass.
- TLC: main 202 752 / 196 608 states (depth 4), scale 374 784 / 344 064; 13 mutants rejected; 5 witnesses reached; `fix-negzero` passes (423 936 / 393 216).
- Apalache 0.62.4: IndInv inductive (NR = 2).
- TLAPS: 70/70 obligations proved (tlapm efe4f2d, 21 s).
- Trace validation: 7 runs accepted, 1 corrupted run refused.
- Engine: head f1f4f21ea; trace build f1f4f21ea + instrumentation (`97140e48`).

# FuncIdxMvcc — reading F from the key under concurrent UPDATE, rollback and vacuum (claim C8)

Added at the user's request (review grill Q5, 2026-11-06). The decision model above assumes a key value is the
value of a row the snapshot sees; this module checks that assumption against the MVCC protocol that both new
paths ride on (the covered projection and, new in 0cb8b988a, the key filter of a non-covered scan).

## Refinement map (model -> code)

| Model | Code (f1f4f21ea) | One step because |
|---|---|---|
| `Begin` | `heap_update` -> `btree_update` (btree.c): `btree_mvcc_delete` marks the old key's entry with the updater's MVCCID, `btree_insert` adds the new key's entry with insert MVCCID | the updater holds the row's X lock; each B-tree change is one leaf modification under its latch; the reader's step reads one entry under its own latch, so the two never interleave inside a step |
| `Commit` / `Abort` | `xtran_server_commit` / `xtran_server_abort` (rollback undoes the insert and the delete mark) | one log record ends the transaction; the snapshot reads the transaction table |
| `Vacuum(e)` | `btree_vacuum_object` (entry) and heap vacuum, for a delete MVCCID older than the oldest active snapshot (`vacuum_is_mvccid_vacuumed`) | vacuum works on a leaf under its latch |
| `Start` | the snapshot taken at statement start (`logtb_get_mvcc_snapshot`), before `btree_range_scan` | one call |
| `Scan` | `btree_range_scan`: `btree_apply_key_range_and_filter` (key filter, `eval_key_filter` reading F from the key) then `btree_select_visible_object_for_range_scan` (snapshot test on the entry's MVCC ids, btree.c:30488), then the covered dump (`btree_dump_curr_key`) or the OID list for the heap fetch with the same snapshot | one leaf record under the leaf latch |
| `Finish` | end of range | |
| `HeapVer` | `heap_get_visible_version` with the scan's snapshot | |

## Properties

| Name | Kind | Statement | Claim |
|---|---|---|---|
| `ResultOK` | invariant | at the end: the row is returned once iff its snapshot version passes, not lost | C8 |
| `NoWrongRow` | invariant | at every step: nothing returned is a version the snapshot cannot see, no duplicate, no vacuumed version | C8 |
| `IndInv` | inductive invariant | U1-U8 (updates in order), E1-E6 (index entries), D1-D8 (reader); Apalache-inductive, TLAPS-proved | C8 |

## Fault model

| Item | Modeled as / why not |
|---|---|
| rollback of the updater | modeled: `Abort` |
| vacuum | modeled: `Vacuum(e)` at any step, gated by the oldest active snapshot |
| updater crash / server crash | not modeled: recovery rolls back the active update (same effect as `Abort`) before any reader runs |
| two updaters on the row | not modeled: the row X lock serializes them (`Begin` only when `cur = 0`) |
| reader's own updates in the same transaction | not modeled: this review scans with a read-only reader; own-write visibility is the snapshot's (unchanged by the PR) |
| leaf split / merge moving the entry during the scan | not modeled: the scan resumes by key (unchanged by the PR, CBRD-27848 model covers the descending restart) |
| several rows sharing a key value (signed zero, H1) | not here: FuncIdxCover `negzero` |
| interrupt, lock timeout, OOM in the scan | an error return ends the query; nothing returned is wrong |

## Mutants

| cfg | Change | Expected | Kills |
|---|---|---|---|
| `FuncIdxMvcc.mutant-no-snapshot` | the entry's MVCC ids are not tested against the snapshot | `NoWrongRow` | C8 |
| `FuncIdxMvcc.mutant-heap-latest` | the heap fetch reads the latest committed version, not the snapshot's | `NoWrongRow` | C8 |
| `FuncIdxMvcc.mutant-vac-early` | vacuum ignores the active snapshot | `ResultOK` | C8 |

## Witnesses

| cfg | Reached state |
|---|---|
| `FuncIdxMvcc.witness-old-version-read` | the reader returns a version an update committed after its snapshot had deleted |
| `FuncIdxMvcc.witness-noncover-kf-old-version` | the same through a non-covered key filter |
| `FuncIdxMvcc.witness-new-entry-skipped` | the reader passes over the entry of a version its snapshot cannot see |
| `FuncIdxMvcc.witness-vacuumed` | vacuum removes an entry |
| `FuncIdxMvcc.witness-aborted` | an update rolls back |

## Bounds and proof

- TLC main: NU = 2 updates (4 672 distinct states, depth 12), every `fv`, `covered`, `kfOn`; scale NU = 3 (38 912).
- Apalache inductive at NU = 2. IndInv strengthenings the counterexamples asked for: the active update's new entry is alive (E2), only `cur` is active (U4).
- TLAPS: InitInv, VisIff (`Visible(e) <=> e = vs` while scanning), one lemma per action with each of the 22 IndInv conjuncts as its own step, InvSafe, `Spec => []IndInv`, for every NU >= 1: 670/670 on tlapm efe4f2d.

## Trace validation

- Build: the same scratch worktree, plus `tla_trace` in `btree_update` (Begin: MVCCID, new key's F x 100), `btree_range_scan` (Start, then a one-shot 4 s pause when `CUBRID_TLA_DELAY_FILE` exists, after the snapshot and before any latch), `btree_select_visible_object_for_range_scan` (Vis: key's F x 100, snapshot result), `btree_vacuum_object` (Vacuum: delete MVCCID), `xtran_server_commit` / `xtran_server_abort` (the updater's transaction only); optdebug libcubrid.so `62798389...`; CS mode server on port 1716 (released), two csql sessions.
- Extraction keeps the events of the test index (root page 705) and the updater's Commit/Abort; other indexes' scans (catalog, the junk table that drives vacuum) are other scans, not this model's.
- Runs (`.git_ignored_dir/scratch/pr6466/mvcc/run.sh`): table `m (i, d, p)`, index `(i, sqrt(d))`, row `(1, 4, 'a')`; the updater updates through `p`, which has no index.

| cfg | run | verdict |
|---|---|---|
| `FuncIdxMvccTrace.witness-trace-commit` | non-covered `select p ... where i = 1 and sqrt(d) > 1`; snapshot, then `d = 9` committed, then Vis 200 (visible), Vis 300 (invisible), reader returns `'a'`; later Vacuum of the MVCCID 8 delete | accepted |
| `FuncIdxMvccTrace.witness-trace-abort` | covered `select sqrt(d) ...`; snapshot, then `d = 16` rolled back, Vis 300 (visible), reader returns 3.0 | accepted |
| `FuncIdxMvccTrace.reject-old-invisible` | the commit run with the old entry's visibility flipped | refused |

Not covered by a run: a vacuum during the scan (vacuum waits for the active snapshot; the model's `vac-early` mutant is the only way in).

## Final result (both modules)

- 2026-11-06, `tools/tla/tla-check --prove --workers 8`: `RESULT: FAILED (1)`, run dir `.git_ignored_dir/scratch/tla/func-index-cover-20261106-120711-3766369`; 46 checks PASS. The one failure is `FuncIdxCover.negzero`, hole H1 kept failing (cubrid-tla P9).
- TLAPS: `FuncIdxCover_proofs` 70/70, `FuncIdxMvcc_proofs` 689/689 (tlapm efe4f2d).
- Trace: FuncIdxCover 7 accepted / 1 refused (SA, `97140e48`); FuncIdxMvcc 2 accepted / 1 refused (CS, `62798389`).
