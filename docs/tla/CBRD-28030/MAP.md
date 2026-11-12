# CBRD-28030 — an index scan started again from the root reads every key from its leaf record

Model `KeyRewind.tla`: one thread runs `NOut` sessions over one B-tree scan structure (`BTREE_SCAN`, "bts").
A session is the inner index scan for one outer row of a SEMI/ANTI join, or one direction of an index
MIN/MAX boundary scan. The B-tree fills the OID buffer key by key (leaf record, then overflow pages); a full
buffer stops the key inside its overflow chain and marks it partially processed (`is_key_partially_processed`);
the consumer reads the buffer in order and stops at its first matching object; the scan is then rewound
(`BTREE_RESET_SCAN`) or reset (`bts_reset_scan`) and the next session starts again from the root.

Engine sha: develop 60361fe7b (worktree `~/dev/cubrid-worktree/CBRD-28030`, branch `CBRD-28030`); the fix is
one statement in `btree_range_scan_start` (decision D2). Runtime evidence of the defect: develop 956e1c19f
optdebug (`~/optdebug/CUBRID-28030-base`, libcubrid `6362398a…`) and release (`~/release/CUBRID-develop-956e1c19f-gha`),
SA, `.git_ignored_dir/scratch/cbrd28030/probe1/`.

## Claim and sources

| # | Claim | Source |
|---|---|---|
| C1 | A query whose inner index scan stops at its first matching row returns what a full read of the range returns: SEMI JOIN emits an outer row iff a matching inner row exists, ANTI JOIN iff none does, and an index MIN/MAX boundary scan returns the MIN/MAX of the full range. | CBRD-28030 Expected Result (the NO_UNNEST answer); 11.4.6 answers of the MIN/MAX probe (`probe1/r11.4.6.minmax2.out`); user, round 1 |
| C2 | After a rewind (`BTREE_RESET_SCAN`) or a reset (`bts_reset_scan`) the index scan hands the consumer its range's objects in key order, none skipped and none repeated, and a scan that reaches its end has handed all of them. | `bts_reset_scan` comment "reset b-tree scan (clear progress)"; btree.c interrupt comment ("resuming after the anchor can neither skip nor repeat a visible object", CBRD-27401); user, round 1 |
| C3 | The leaf record of a key is skipped, and the scan resumes in its overflow chain, only for the key whose resume position the previous iteration of the same scan saved. | `btree_range_scan_select_visible_oids` resume branch comment ("Key was not fully processed. Resume from its current overflow"); user, round 1 |

## Decisions

| # | Decision | Settled by |
|---|---|---|
| D1 | Claims C1–C3 as written above; C1 covers the index MIN/MAX boundary scan found during the grill. | user, round 1 (Q1) |
| D2 | The fix clears the mark where a scan starts from the root: `btree_range_scan_start` sets `is_key_partially_processed = false` (model `Fix = "start"`). Rejected: `BTREE_RESET_SCAN` only (`mutant-macro-only-flip`: the MIN/MAX reset keeps the mark); clearing at every `btree_range_scan` call (`mutant-clear-every-call`: a buffer resume reads the leaf record twice). Equivalent but not chosen: `BTREE_RESET_SCAN` + `bts_reset_scan` (`fix-macro-bts` passes; two sites, and a future reset path could miss it again). | user, round 1 (Q2); `KeyRewind.cfg` |
| D3 | Both defects are fixed under CBRD-28030, retitled to name SEMI/ANTI JOIN and index MIN/MAX; links: regression of CBRD-26872 (SEMI/ANTI) and of CBRD-24890 (MIN/MAX). | user, round 1 (Q3); probes below |

## Refinement map (model -> code, develop 60361fe7b)

| Model | Code | One step because |
|---|---|---|
| `rlo[s]`, `rhi[s]` | the key range of session s: `bts->key_range` (SEMI inner: `i.k = o.k`, one key; MIN/MAX: `k > 0`) | data, fixed per session |
| `M[s]` | the objects the consumer's predicates accept (the inner's data filter holds the join term) | data |
| objects `Base(k)+1 .. Base(k)+KeyLen(k)` | key k's OIDs: leaf record first (`LeafOf`), then overflow pages (`PgCnt`) in chain order | data; every object visible (fault table) |
| `started` | `bts->is_scan_started` | single owner (the query's thread) |
| `ck`, `kcons` | the current key (`C_vpid`/`slot_id`, `cur_key`) and `key_status == BTS_KEY_IS_CONSUMED` | single owner |
| `flag` | `bts->is_key_partially_processed` | single owner |
| `anchor`, `lastvis` | `bts->O_last_oid`, `bts->O_last_visible_oid` (object ids) | single owner |
| `ovp` | `bts->O_vpid` (0 = NULL; else the key whose chain it is in) | single owner |
| `pg` | the overflow page `btree_range_scan_select_visible_oids` processes next (`overflow_vpid`), as its ordinal in the chain | local |
| `buf`, `bufv` | `bts->n_oids_read_last_iteration`, the OID buffer `index_scan_idp->oid_list->oidp` | single owner |
| `cons` | `isid->curr_oidno` + 1, the consumer's position in the buffer (`scan_next_index_scan`) | single owner |
| `CAP`, `SOFT` | `oid_list->capacity` (`BTS_IS_HARD_CAPACITY_ENOUGH`), `oid_list->max_oid_cnt` (`BTS_IS_SOFT_CAPACITY_ENOUGH`); both `ISCAN_OID_BUFFER_COUNT` = 8192 at default `bt_oid_nbuffers` | constants |
| `Start` | `btree.c` `btree_range_scan_start`: positions on the range's first key from the root; with `Fix = "start"` clears `is_key_partially_processed` (the fix) | one call, no shared state |
| `Advance`, `EndScan` | `btree_range_scan_advance_over_filtered_keys`; end of range: `end_scan`, `is_scan_started = false`, `C_vpid` NULL (`btree_range_scan` end) | |
| `ResumeKey` | `btree_range_scan` → `btree_range_scan_resume` on the key the last iteration stopped in | |
| `SoftStop` | `btree_range_scan_select_visible_oids`: not partially processed, `n > 0 && n <= soft && n + leaf + first overflow page > soft` → `end_one_iteration` | |
| `LeafFill` | same function, not partially processed: `btree_record_process_objects (BTREE_LEAF_NODE)`, then `O_last_visible_oid` NULL and `overflow_vpid = leaf_rec_info.ovfl` | |
| `KeyResume` | same function, partially processed: non-unique `btree_ovf_scan_locate_resume` (by `O_last_oid` in the current key's chain, from its first page when NULL); unique: the page after `O_vpid` (`pgbuf_fix (O_vpid)`); then `is_key_partially_processed = false` | |
| `Interrupt` | same function, overflow loop: `!BTS_IS_HARD_CAPACITY_ENOUGH (n + oid_count)` → `O_vpid` set, `O_last_oid = O_last_visible_oid`, `is_key_partially_processed = true`, `end_one_iteration` | |
| `PageFill` | same function, overflow loop: `btree_record_process_objects (BTREE_OVERFLOW_NODE)`, next page | |
| `KeyDone` | same function end: `O_vpid` NULL, `key_status = BTS_KEY_IS_CONSUMED` | |
| `Consume` | `scan_next_index_scan` reads `curr_oidno`; a row the predicates accept: `scan_next_scan_local` `QPROC_SINGLE_INNER` sets `single_fetched` (SEMI/ANTI), `qexec_intprt_fnc` finishes MIN or MAX | |
| `NextIter` | buffer drained: `scan_next_index_scan` → `call_get_next_index_oidset` → `btree_range_scan` (resets `end_one_iteration`, `n_oids_read_last_iteration`) | |
| `EndNoMatch` | the scan returns `S_END` with no row | |
| `Rewind` | `query_executor.c` `qexec_reset_sa_inner_scan_block` → `scan_manager.c` `scan_reset_scan_block` (`S_INDX_SCAN`, not grouped) → `btree.h` `BTREE_RESET_SCAN`: clears `P/C/O_vpid`, `O_last_oid`, `O_last_visible_oid`, `cur_key`, `is_scan_started`; keeps `is_key_partially_processed` | |
| `Flip` | `query_executor.c` `qexec_intprt_fnc`, `ACCESS_SPEC_FLAG_ONLY_MIN_MAX_SCAN`: flips `use_desc_index`, `bts_reset_scan` (clears `is_scan_started`, `C_vpid`; keeps `is_key_partially_processed`, `O_vpid`, `O_last_oid`), `position = S_GO_BACKWARD` → `scan_next_index_scan` restarts the scan | |
| `Fix = "none" / "macro" / "macro_bts"` | develop / `BTREE_RESET_SCAN` clears the mark / it and `bts_reset_scan` clear it | options of D2 |
| `Mutant = "clear_every_call"` | `btree_range_scan` entry clears the mark | mutant |
| `bad`, `lost`, `nread`, `nopos`, `res`, `hitIn`, `resumed`, `ex` | ghosts: order break, objects left unread at end (`nread`, the objects the session read, differs from its range size), resume without a saved position for this key, the session's answer, where its match lay, a resume happened, the next object scan order expects | |

Callers of the entry points (code-index, 60361fe7b): `BTREE_RESET_SCAN` — `scan_reset_scan_block` only;
`scan_reset_scan_block` — `qexec_reset_sa_inner_scan_block` (SEMI/ANTI inner, called from `qexec_execute_scan`,
`qexec_execute_nljoin_with_memoize`, `qexec_execute_sa_anti_survive`, `qexec_intprt_fnc`,
`qexec_next_scan_block_iterations`, `parallel_scan::task::row_body`) and `qexec_next_scan_block_iterations` (after
`S_END`, where the mark is already false); `bts_reset_scan` — `qexec_intprt_fnc` (MIN/MAX turn), `btree_range_scan`
(ILS restart) and `btree_select_visible_object_for_range_scan` (ILS: covering, never partially processed, see
fault table). `btree_range_scan_start` is reached only from `btree_range_scan` when `!is_scan_started`.

## Properties

| Name | Kind | Statement | Claim |
|---|---|---|---|
| `SemiAntiCorrect` | invariant | every finished session's answer (match / no match) equals whether its range holds a matching object | C1 |
| `ScanInOrder` | invariant | every object put into the buffer is the next one of the range in scan order | C2 |
| `ScanComplete` | invariant | a session that reached the end of its range read all of it | C2 |
| `ResumeOwnKey` | invariant | `KeyResume` runs only with `O_vpid` saved for the current key | C3 |
| `IndInv` | inductive invariant | `TypeOK`, `InvBuf`, `InvRange`, `InvCk`, `InvKeyStart`, `InvPartial`, `InvPage`, `InvConsumed`, `InvNotStarted`, `InvEnd`, `InvStartedPc`, `InvFix`, `InvBufObjs`, `InvNoMatchYet`, `InvRes`, `InvResCur`, `InvRead`, and the four claims | C1–C3 |

`M[s]` is empty or one object: a skipped object that is the only match exposes every skip, and C2 makes C1 hold
for any match set (the answer depends only on which objects the scan hands over before it stops).

## Fault model and environment assumptions

| Fault | Modeled as |
|---|---|
| error return | not modeled: an error from `pgbuf_fix`, `btree_ovf_scan_locate_resume` or `btree_record_process_objects` ends the query (`ASSERT_ERROR`, `goto exit_on_error`); no answer to compare. Develop's unique-index resume after a rewind (`pgbuf_fix (O_vpid = NULL)`) is this class: C3's `nopos` flags the state that leads to it (pre-27401 build asserts in `pgbuf_is_valid_page`, `probe1/pre27401.semi2.out`) |
| interrupt / query cancel | not applicable: ends the query |
| lock timeout, deadlock victim | not applicable: a read scan under MVCC takes no row lock |
| conditional latch failure | not applicable: every fix here is unconditional |
| OOM | not applicable: no allocation on the changed path |
| crash / `kill -9` | not applicable: the scan state is private memory of one query |
| spurious wakeup | not applicable: no wait |
| concurrent DML, vacuum | not modeled: every object is visible. The resume across concurrent DML and vacuum is CBRD-27401's design (anchor by OID, leaf latch held across the re-fix); this change only removes a mark at a start from the root, where no resume position is used |
| checkpoint, flush, replacement | not applicable: pages are re-fixed by VPID at every step |
| HA log apply | not applicable |
| nested statement (SP SQL) | not applicable: no snapshot is read on the changed path |
| MRO, count-only, covering, ILS, ISS early out | not applicable: `BTS_IS_INDEX_MRO`, `BTS_NEED_COUNT_ONLY` skip the capacity checks (`assert (!is_key_partially_processed)`), a covering scan has no hard limit (`BTS_IS_HARD_CAPACITY_ENOUGH` is `true`), so none of them sets the mark |
| `force_restart_from_root` (descending) | not applicable: the restart keeps `is_scan_started` (resume path) except for ILS, which is covering |
| buffer size | `SOFT = CAP` (default `bt_oid_nbuffers`: `max_oid_cnt = capacity = ISCAN_OID_BUFFER_COUNT`); a smaller parameter only makes `SOFT < CAP`, which the model allows (`ASSUME CAP >= SOFT`) but no cfg runs |

## Mutants

| cfg | Change | Expected | Kills |
|---|---|---|---|
| `mutant-develop` | `Fix = "none"`, rewinds only (develop SEMI/ANTI) | `SemiAntiCorrect` violated: session 1 (keys 1..2) fills leaf + page 1 of key 1, stops at page 2 (mark set), matches; session 2 on key 2 skips its leaf record | C1 |
| `mutant-develop-order` | same | `ScanInOrder` violated | C2 |
| `mutant-develop-complete` | same | `ScanComplete` violated | C2 |
| `mutant-develop-pos` | same | `ResumeOwnKey` violated | C3 |
| `mutant-develop-flip` | `Fix = "none"`, MIN/MAX turn only | `SemiAntiCorrect` violated | C1 (MIN/MAX) |
| `mutant-develop-leaf-only-key` | develop, 3 keys, key 2 has no overflow page | `SemiAntiCorrect` violated (the key with no chain is skipped whole: `probe1` Q4) | C1 |
| `mutant-macro-only-flip` | `Fix = "macro"` (the old design.md) with MIN/MAX turns | `SemiAntiCorrect` violated | D2 |
| `mutant-clear-every-call` | `Fix = "start"` + every `btree_range_scan` call clears the mark | `ScanInOrder` violated: the buffer resume re-reads the leaf record | C2, D2 |

## Witnesses

| cfg | Outcome reached |
|---|---|
| `witness-stopped-partial` | a session stops with the mark set (the defect's precondition) |
| `witness-leaf-after-ovf` | session 1 matches in the overflow chain, session 2 in the leaf record (JIRA Q1) |
| `witness-resumed-match` | a match after a buffer resume (C2's resume path) |
| `witness-flip-stale` | a MIN/MAX turn leaves the mark set before the next start, which the fix clears |

## Option cfgs (D2)

| cfg | Result |
|---|---|
| `fix-macro` | pass with rewinds only (`uncovered-ok: Flip`) |
| `fix-macro-bts` | pass |

## Bounds

Main: `NK = 2, LeafN = 1, PG = 2, NPG = 2, OvfKeys = {1, 2}, SOFT = CAP = 3, NOut = 2`, both reset kinds.
Scale: `scale-npg3` (3 pages), `scale-3-sessions` (`NOut = 3`), `scale-3-keys` (`NK = 3`, key 2 without a chain).
IndInv: Apalache at the main sizes (`CInit`; `1..NObj` needs constant bounds, P59).

## Dead expressions

| cfg | Lines | Why |
|---|---|---|
| `fix-macro` | KeyRewind.tla:229, KeyRewind.tla:230, KeyRewind.tla:231, KeyRewind.tla:232, KeyRewind.tla:246, KeyRewind.tla:247 | `NextSession` as instantiated in `Flip`, and `Flip`'s own body: the option is checked with `ResetKinds = {"rewind"}`, so `Flip` never fires (its `Rewind` instance of `NextSession` is live) |

## Trace validation

Instrumented build: `~/dev/cubrid-worktree/CBRD-28030-instr` (60361fe7b + the fix + TLATRACE lines, additions only:
`btree.c` Start/Call/EndScan/SoftStop/LeafFill/KeyResume/Interrupt/PageFill/KeyDone, `scan_manager.c` Rewind/Row,
`query_executor.c` Flip), `~/optdebug/CUBRID-28030-instr`. Runs: SA, `CUBRID_TLA_TRACE=<log>`,
`.git_ignored_dir/scratch/cbrd28030/trace/n1..n5.sql`; raw logs `traces/raw/n*.log.xz`; `traces/make-data.sh`
(`traces/convert.py`) writes `KeyRewindTraceData.tla`. The run's key structure replaces the model's uniform sizes
(cfg overrides `LeafOf`, `PgCnt`, `NPg`, `KeyLen`, `Base`, `PageStart`, `AnchorNext`, `BufMax`); `CAP = SOFT = 8192`.
Hidden (not logged, deterministic): `Consume` of a non-matching OID, `Advance`, `ResumeKey`, `EndNoMatch`.

| cfg | Run | What it covers |
|---|---|---|
| `witness-trace-n1` | SEMI, two outer rows on key 6500, matches in the leaf record (v = 1, 2) | Start (stale=1 cleared on session 2), LeafFill, PageFill, Interrupt, Row, Rewind |
| `witness-trace-n2` | SEMI, outer row 2 on key 7000 (no chain) | session 1 resumes in the chain (Call, KeyResume), KeyDone of a key without pages |
| `witness-trace-n3` | ANTI on key 6500 | NOT EXISTS path, same steps |
| `witness-trace-n4` | index MIN/MAX boundary scan, `max(k)` with `v > 0` | Flip (flag=1), Start stale=1 cleared, MAX key 2 read from its leaf record, descending into key 1 |
| `witness-trace-n5` | range scan over keys 1 (15000 rows) and 2 (3000 rows), no row returned | KeyResume at page 12, SoftStop before key 2, EndScan |
| `reject-stale-off` | n1 with session 2's Start reporting stale=0 | refused: the model carries the mark from session 1 |
| `reject-skip-leaf` | n2 with session 2's LeafFill replaced by develop's KeyResume at page 1 | refused: with the fix the start clears the mark, so no resume is possible |
| `reject-count-off` | n5 with one more object in a page | refused: the page sizes come from the run |

Not reached by a run: `Fix`/`Mutant` alternatives (not code), the foreign-anchor branch of `KeyResume` (with the
fix no resume follows a restart).

## Result

2026-11-12, `tools/tla/tla-check docs/tla/CBRD-28030` → `RESULT: OK`, run dir
`.git_ignored_dir/scratch/tla/CBRD-28030-20261112-131257-1620030`.

| cfg | Expect | States (distinct) / depth |
|---|---|---|
| `KeyRewind` | pass | 41712/39534, 68 |
| `scale-npg3` | pass | 100530/96480, 96 |
| `scale-3-keys` | pass | 198737/188369, 76 |
| `scale-3-sessions` | pass | 2136618/2028807, 102 |
| `fix-macro-bts` | pass | 41712/39534, 68 |
| `fix-macro` | pass | 36267/35178, 68 |
| `mutant-develop` | violation SemiAntiCorrect | 23101, 22 |
| `mutant-develop-order` | violation ScanInOrder | 9814, 10 |
| `mutant-develop-complete` | violation ScanComplete | 22525, 22 |
| `mutant-develop-pos` | violation ResumeOwnKey | 8725, 9 |
| `mutant-develop-flip` | violation SemiAntiCorrect | 13023, 12 |
| `mutant-develop-leaf-only-key` | violation SemiAntiCorrect | 61570, 12 |
| `mutant-macro-only-flip` | violation SemiAntiCorrect | 14402, 12 |
| `mutant-clear-every-call` | violation ScanInOrder | 11776, 11 |
| `witness-stopped-partial` / `-leaf-after-ovf` / `-resumed-match` / `-flip-stale` | violation (reached) | 5458 / 14864 / 16760 / 6547 |
| `KeyRewindTrace.witness-trace-n1..n5` | violation TraceNotDone (run accepted) | 33 / 13993 / 14038 / 35 / 15042 |
| `KeyRewindTrace.reject-stale-off` / `-skip-leaf` / `-count-off` | pass (run refused) | 17 / 13989 / 3 |
| `apalache-indinv` | pass (IndInv inductive at the main sizes) | Apalache |

TLAPS: 요청 없음 (P48).

Spec sha256 (summary.txt):

```
5af1ce6802d5b6af3294d4e7be82e683fdb71892e556e9cfcb95be153127c080  KeyRewind.tla
f93b9ee9530d7dea2e748f0c4091f4e9284e452112bae1d5d85c763c3e941169  KeyRewindTrace.tla
b64654c570afc2352bdd27b8ccd8e616e7642b1b65fba2b2ff03af15f18003d9  KeyRewindTraceData.tla
```

Engine: fix on develop 60361fe7b (branch `CBRD-28030`); trace runs on `~/optdebug/CUBRID-28030-instr` (the same sha
+ the fix + TLATRACE lines). Runtime: develop 956e1c19f optdebug/release fail Q1–Q5 of the JIRA repro, the fix
optdebug/release and 11.4.6 pass them (`.git_ignored_dir/scratch/cbrd28030/repro/`).
