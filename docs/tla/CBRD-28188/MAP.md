# PageVisibility — the page batch walk answers a heap record from its first word as the header walk would

Spec: `PageVisibility.tla` (state-shaped TLA+), its Apalache check `PageVisibilityInd.tla`, trace
validation `PageVisibilityTrace.tla` + `PageVisibilityTraceData.tla` (from `traces/`).
Code: `xmilex-git/cubrid` branch `CBRD-28188` at `aab8ac860` (develop `406d2d87a` + one commit, `src/storage/heap_file.c` +90/-9).
Ticket: CBRD-28188 (Improve). Origin: CBRD-26928 comment 4778581 (mode D of the PoC on `og12-pagevis` `fb1bccc55`).

## Claim and sources

| Claim | Statement | Kind | Source |
|---|---|---|---|
| C1 | Every record `heap_page_collect_visible ()` answers from its first word gets the answer the header walk (`heap_page_row_mvcc_header` + `snapshot_fnc` + repid search) gives it: a row, a skipped record, or the end of the chunk | equivalence | CBRD-28188 *Specification Changes* "질의 결과: 바뀌지 않습니다"; design.md "정확성 근거" |
| C1a | On a page whose `HEAP_CHAIN.max_mvccid` precedes the snapshot's `lowest_active_mvccid`, an inserted record is visible and a deleted one is not, whatever its ids | equivalence (premise of C1) | CBRD-28188 *Implementation* first paragraph; code comment at `heap_file.c:8545-8550` |
| C1b | A record with no MVCC id is visible to every snapshot | equivalence | `MVCC_IS_HEADER_ALL_VISIBLE` (`mvcc.h:95`), develop's walk skips `snapshot_fnc` for it |
| C1c | The heap header page (slot 0 = `HEAP_HDR_STATS`) is never judged | safety | design.md "헤더 페이지는 chain이 NULL"; `heap_file.c:8608` |
| C2 | A record the first word can answer for is not decoded (the work the change saves) | safety (ghost-free: a predicate over the state the call reads, P83) | CBRD-28188 *Description* last paragraph |

CBRD-26928 comment 4778581 measured mode D on the PoC; the ticket body and design.md (2026-11-18) are the latest statement.

## Refinement map (model -> code)

| Model | Code | One step because |
|---|---|---|
| `ScanCall(p)` (stutter; answers = `FastDecide`) | `heap_page_collect_visible ()` `heap_file.c:8552-8754`: page judgment `:8608-8616`, first word `:8646`, word row `:8652`, word delete `:8659`, header walk `:8666-8729` | the page is held under a read latch (`heap_scan_pb_latch_and_fetch (... PGBUF_LATCH_READ ...)` `:8582`) or is the scan's local copy (`HEAP_SCAN_IS_LOCAL_CACHE_READ`) for the whole call; chain and records are read inside it; every writer below holds the write latch |
| `Passed(p)` | `snapshot->snapshot_fnc == mvcc_satisfies_snapshot && spage_get_record (slot 0) && length == sizeof (HEAP_CHAIN) && MVCC_ID_PRECEDES (max_mvccid, lowest_active_mvccid)` `:8609-8612` | read once per call |
| `WordRow`, `WordDel` | `(word & word_mask) == word_want`, `page_precedes_snapshot && (word & delid_bit) != 0` | — |
| `w \in Repids` (want) | `word_want`: `repids[0]` `:8566`, then the repid of a row the header walk accepted `:8727` | `word_want` only takes repids the walk accepted (membership checked `:8703-8723`), so it is always one of `repids[]`, which is also why the header walk skips the `repids[]` search for a record of `word_want`'s repid (`:8703-8704`); with `n_repids == 0` `repid_bits = 0` and every repid matches (trace: `nrep=0` maps to the want) |
| `DevDecide`, `DevRes`, `InSnap`, `ByMe` | `mvcc_satisfies_snapshot ()` `mvcc.c:156-269`, `mvcc_is_id_in_snapshot ()` `mvcc.c:91-108`, `MVCC_IS_REC_INSERTED_BY_ME` / `DELETED_BY_ME` `mvcc.h:118-123`; the walk's TOO_NEW + `prev_version_lsa` split `:8692-8701` | — |
| `rel` record | `REC_RELOCATION`, `REC_BIGONE` home slots `:8647-8651` (the header is on the forward page) | — |
| `Insert(t,p,s)` | `heap_insert_logical ()` -> `heap_log_insert_physical ()` -> `heap_mvcc_log_insert ()` `:17826-17887` -> `heap_page_update_chain_after_mvcc_op ()` `:26542-26622`; also a `REC_ASSIGN_ADDRESS` filled in place (`catcls_insert_instance ()` `catalog_class.c:3943`, `ER_HEAP_NODATA_NEWADDRESS` `locator_sr.c:6197`): `heap_update_home ()` logs it `RVHF_UPDATE_NOTIFY_VACUUM` (`:24769`), an MVCC op, and `heap_log_update_physical ()` raises the chain (`:25029`) | record and chain change under one write latch, logged together |
| `Delete(t,p,s)` | `heap_delete_home ()` -> `heap_mvcc_log_delete ()`; `heap_delete_relocation ()` / `heap_delete_bigone ()` raise the home page through `heap_mvcc_log_home_no_change ()` `:21267-21280` / `heap_mvcc_log_home_change_on_delete ()` `:21232-21256` | same |
| `Update(t,p,s)` (`rl`: the new version moves to a forward page or back home) | `heap_update_home ()`, `heap_update_relocation ()`, `heap_update_bigone ()` with an MVCC op: `heap_log_update_physical ()` with `RVHF_UPDATE_NOTIFY_VACUUM` on the home page `:25015-25045`, or `heap_mvcc_log_home_no_change ()` for the home page when only the forward record changes | same |
| `InplaceOld(t,p,s)` | `UPDATE_INPLACE_OLD_MVCCID` (`heap_object_upgrade_domain ()` `:19380-19755`, under SCH_M): `heap_update_adjust_recdes_header ()` keeps the ids (`:22302` branch), `RVHF_UPDATE`, no chain update | the ids it writes are the record's own, and every id that record ever carried raised its home page (`Update`, `Delete` rows above) |
| `InplaceCurHome` (mutant only) | none on an MVCC class: census below | — |
| `Commit(t)` | `logtb_complete_mvcc ()` `log_tran_table.c:4490-4552` | the id leaves the active set in one step |
| `AbortStart`, `Undo(t,p,s)`, `AbortDone` | rollback: `heap_rv_mvcc_undo_delete ()` `:18115-18157`, the undo of insert/update (`heap_rv_undo_*`), then `logtb_complete_mvcc ()`; the chain is never lowered | one undo record per step under the page write latch; the id stays active until the end |
| `Vacuum(p,s)` | `vacuum_heap_record ()` `vacuum.c:2374-2500`: removes a committed delete below the threshold, clears INSID + prev version of a committed insert below it; chain untouched | under the page write latch |
| `TakeSnap`, `DropSnap` | `logtb_get_mvcc_snapshot ()` -> `mvcctable::build_mvcc_info ()` (`mvcc_table.cpp:226-335`: `snapshot.lowest_active_mvccid = crt_status_lowest_active` `:333`); a statement end or a nested statement's rebuild (`logtb_invalidate_snapshot_data`) | the snapshot is the scan's for the whole call |
| `Crash` | restart recovery: losers undone, every id completed; redo of an MVCC op re-raises the chain (`heap_page_rv_chain_update ()` `:26633-26685`, callers `heap_rv_mvcc_redo_insert`, `heap_rv_mvcc_redo_delete_home`, `heap_rv_redo_update_and_update_chain`, `heap_rv_update_chain_after_mvcc_op`, `heap_rv_mvcc_redo_redistribute`) | the chain value after recovery is the one before the crash |
| `LowNow` | `m_current_status_lowest_active_mvccid` (the first id not completed) | — |
| `maxm[p]` | `HEAP_CHAIN.max_mvccid` (`heap_file.c:286`), raised only through `heap_page_update_chain_after_mvcc_op ()` (6 callers: `heap_mvcc_log_insert`, `heap_mvcc_log_delete`, `heap_mvcc_log_home_change_on_delete`, `heap_mvcc_log_home_no_change`, `heap_log_update_physical`, `heap_mvcc_log_redistribute`) and its redo twin; reset to `MVCCID_NULL` only on a page with no record (`heap_vpid_alloc`, `heap_alloc_new_page(s)`, `heap_create_bestspace`, `heap_update_bestspace_chain`, `heap_reuse` after `heap_delete_all_page_records`/`heap_reinitialize_page`, their redo) | — |

### Census: writers of an MVCC id into a REC_HOME header without a chain update

`UPDATE_INPLACE_CURRENT_MVCCID` callers (2026-11-18, `406d2d87a` = the change's base; the change touches no writer): `boot_db_parm_update_heap ()` (root class: MVCC disabled, ids stripped), `tde_update_keyinfo ()` (NULL class: MVCC disabled), `catcls_insert_instance ()` (fills its own `REC_ASSIGN_ADDRESS`: NOTIFY_VACUUM raises), `disk_update_instance ()` (compactdb, SA: ids stripped), `locator_insert_force ()` `:5668` (the record its own insert just raised), `locator_update_force ()` `:5990`, `:6089`, `:6303` (class records of the root class or MVCC-disabled classes), `:6197` (`ER_HEAP_NODATA_NEWADDRESS`: a `REC_ASSIGN_ADDRESS`, NOTIFY_VACUUM raises). Catalog rows a DDL changes go through `catcls_update_catalog_classes ()` with `UPDATE_INPLACE_NONE` (`xlocator_force` `:7892`), an MVCC update. SA mode and bulk (`is_bulk_op`) inserts strip the ids (`heap_insert_adjust_recdes_header ()` `:22151-22180`). Runtime check of the first suspicion (ALTER on a table, its `_db_class` row read by another session while the ALTER is open): develop release `6a1bb273f` and the change's optdebug both answered 1 row, no assert (`.git_ignored_dir/scratch/cbrd28188/hole/`). The model keeps the excluded writer as mutant `inplace_current_home`.

## Properties

| Property | Claim | Kind |
|---|---|---|
| `EquivNow` | C1, C1a, C1b, C1c | invariant: in every state the scanner can read, `FastDecide = DevDecide` for every page, record and want |
| `NoDecodeWhenAnswered` | C2 | invariant |
| `IndInv` | all (inductive) | conjuncts `TypeInd`, `IdsAllocated`, `StatusIds`, `OwnerOk`, `RecIds`, `IdBound`, `SnapOk`, `EquivNow`, `NoDecodeWhenAnswered` |

`IdBound` (every id a data page holds or may restore is at most its `max_mvccid`) is the premise the change reads from develop's writers; `RecIds` (an id on a record is committed or the holder's) and `SnapOk` (an id below `lowest_active` is completed in the snapshot) carry the rest.

## Fault model and environment assumptions

| Fault | Modeled? |
|---|---|
| error return | not applicable: the change adds no call that returns an error (`spage_get_record` of slot 0 failing leaves the page unjudged: the header walk) |
| interrupt / query cancel | not applicable: no loop or wait added; the walk's chunk ends as before |
| lock timeout, deadlock victim | modeled as `AbortStart` + `Undo` + `AbortDone` at any point of a writer |
| conditional latch failure | not applicable: the call takes no new latch |
| OOM | not applicable: no allocation |
| crash / `kill -9` | `Crash` (losers rolled back, chain as before; MaxCrash = 1) |
| spurious wakeup | not applicable: no wait |
| concurrent DML | `Insert`, `Delete`, `Update`, `InplaceOld`, rollbacks, by every transaction including the scanner, on the data page and the header page |
| vacuum | `Vacuum` on every record whose id is below the threshold (`OldestVis`); simplification: vacuum skips a record with an uncommitted change (it only removes ids, which moves a record toward the word answer, never away) |
| checkpoint, page flush, page replacement | not applicable: the call holds the page; a flush does not change chain or records |
| HA log apply | not applicable: the slave applies through ordinary transactions (the writers above) |
| nested statement | `TakeSnap` at any time replaces the READ COMMITTED snapshot between calls (P55); within a call the scan reads one snapshot |

Environment: no fairness (only safety claims). Ids are handed out in order (`TakeId`), one lifecycle per writer transaction, the scanner restarts after a crash.

## Mutants

All expect `violation EquivNow` unless noted; each passes in the main cfg's constants.

| Mutant | Claim | Removes | Caught (distinct states, depth) |
|---|---|---|---|
| `judge_le` | C1a | `<` of the page judgment becomes `<=` (an active id equal to `lowest_active`) | 929, 4 |
| `judge_header` | C1c | the slot-0 length check: the header page judged with `max_mvccid = 0` | 1235, 4 |
| `no_repid` | C1 | `repid_bits` in `word_mask` | 1241, 4 |
| `no_insid_bit` | C1b | `OR_MVCC_FLAG_VALID_INSID` in the unjudged page's mask | 799, 5 |
| `skip_del_any_page` | C1a | `page_precedes_snapshot &&` before the delete skip | 1356, 5 |
| `no_raise_update` | C1 (premise IdBound) | the chain update of an MVCC update (`heap_log_update_physical ()` `:25029`) | 1357, 4 |
| `reloc_no_home_raise` | C1 (premise IdBound) | the home-page raise of a relocated record's update/delete (`heap_mvcc_log_home_no_change ()`), so `InplaceOld` brings ids home above the chain | 9264, 6 |
| `inplace_current_home` | C1 (premise IdBound) | adds a writer develop does not have (census above): current MVCCID in place on a REC_HOME record, no chain update | 1893, 5 |
| `always_decode` (expects `violation NoDecodeWhenAnswered`) | C2 | the word answer (C2) | 422, 4 |

The mutants under 1,000 distinct states are not vacuous passes (P67): each is a detected violation at depth 4-5, the shortest path to an id the judgment misreads.

## Witnesses

| Witness | Outcome | Reached (distinct states, depth) |
|---|---|---|
| `NotFastIdRow` | a judged page answers a record that still carries an INSID from its word | 3836, 6 |
| `NotFastDel` | a deleted record skipped from its word | 6909, 5 |
| `NotFailedOwnPage` | the scanner's own change keeps a page unjudged | 348, 4 |
| `NotPassedAfterCrash` | after a crash a judged page answers an id-carrying record from its word | 11206, 6 |
| `NotMovedHomeFast` | a record moved home by `InplaceOld` is answered from its word | 39964, 6 |

## Dead expressions (pass cfgs)

| Line | Why never evaluated |
|---|---|
| PageVisibility.tla:151, PageVisibility.tla:152, PageVisibility.tla:153, PageVisibility.tla:154 | `TakeId`'s and `Own`'s bodies under `InplaceCurHome` (mutant `inplace_current_home` only): TLC counts an operator body per call site; evaluated under `Insert`, `Delete`, `Update`, `InplaceOld` |
| PageVisibility.tla:174 | `Delete`'s `UNCHANGED maxm` branch: mutant `reloc_no_home_raise` only |
| PageVisibility.tla:187 | `Update`'s `UNCHANGED maxm` branch: mutants `no_raise_update` and `reloc_no_home_raise` only |
| PageVisibility.tla:206, PageVisibility.tla:208 | `InplaceCurHome`: mutant `inplace_current_home` only (no such writer in develop, census above) |
| PageVisibility.tla:273, PageVisibility.tla:274, PageVisibility.tla:275, PageVisibility.tla:276, PageVisibility.tla:277, PageVisibility.tla:278, PageVisibility.tla:279, PageVisibility.tla:280, PageVisibility.tla:281 | `Crash`'s body in `PageVisibility.scale-3tx.cfg`, which sets `MaxCrash = 0` (crashes are checked by `PageVisibility.cfg`) |

## Bounds and limits

- Main: `Tx = {r, t1}` (the scanner writes too), one data page and the header page, one slot each, `Reps = {1, 2}`, `Repids = {1}`, `MaxCrash = 1`, `MaxId = 3`, symmetry none needed beyond `WriterSym`.
- Scale: `Tx = {r, t1, t2}`, `MaxCrash = 0` (22.8 M distinct states, depth 17). A two-slot TLC run (`NS = 2`, crash 1) passed 80 M distinct states at depth 8 without ending and was stopped; two slots per page are covered by the Apalache inductive check (`NS = 2`, every state IndInv admits).
- Apalache: `PageVisibilityInd.apalache-indinv.cfg`, `Tx = {r, t1}`, `NS = 2`, `MaxCrash = 2`, `MaxId = 4` (Apalache needs a constant id range, P59).
- Not modeled: sub-transaction ids (`logtb_is_current_mvccid` also matches sub-ids: the code and the model give the same answer for an id below `lowest_active`, so only the equality of the two walks is claimed); parallel heap scan workers call the same function with their own snapshot copy (`px_scan_task.cpp:894`), one more reader of the same shape.

## Trace validation

Instrumented scratch worktree `~/dev/cubrid-worktree/CBRD-28188-trace` at `aab8ac860` + 117 added lines (`git diff | grep -E '^-[^-]'` empty); optdebug install `~/optdebug/CUBRID-CBRD-28188-trace`. Events: `ScanCall` (one per call that holds an MVCC snapshot: page, header page or not, `max_mvccid`, `lowest_active_mvccid`, own MVCCID, the judgment) and `Decide` (one per record answered: rel, ins, del, prev, repid, want, the in-snapshot bits of the ids, `nrep`, `inrep`, the path, the answer, and develop's answer computed from the decoded header).

The trace spec validates the reader step: every logged answer and path must be `FastDecideIn` / `DevDecideIn` / `WordRowIn` / `WordDelIn` of the logged record, the logged judgment must be `PassedIn`, and every id on a data-page record must be at most the page's `max_mvccid` (`IdBound` on every record the run read). Writer steps are not logged; they reach the trace only through the record contents.

| Run | Events | Coverage |
|---|---|---|
| `traces/run1.log` (CS, 4 sessions, `hole/trace-run.sh`: 300 rows of 500 bytes, uncommitted insert/delete of another session, own view, rollback, committed delete before vacuum, repeatable read across a delete and an update, vacuum, ALTER ADD COLUMN, relocation and overflow updates, the scanner's own insert/delete) | 3453 (85 ScanCall, 3368 Decide) | judged pages 56, unjudged 29, header page 23 calls; paths: word row 2696, word delete 67, header walk row 273 / skip 312 / end of chunk 14, relocated 6 |
| `traces/flipped-fast.log` (event 2220's answer row -> skip) | reject | stops at depth 2220 |
| `traces/max-at-low.log` (event 243's `max_mvccid` set to `lowest_active`, judgment kept) | reject | stops at depth 243 |

The query results of the scenario equal develop release `6a1bb273f`'s (14 queries).

## Counterexamples

| Cfg | Classification |
|---|---|
| first draft, `PageVisibility.cfg` with an in-place writer on any REC_HOME record (2026-11-18 15:10) | model error: the writer `InplaceCur` stood for `UPDATE_INPLACE_CURRENT_MVCCID` on any record; the census shows no such writer on an MVCC class (catalog rows a DDL changes use `UPDATE_INPLACE_NONE`, `locator_sr.c:7892`), and the runtime probe did not reproduce it. Kept as mutant `inplace_current_home` |
| first draft trace spec, every event (rc 75) | model error: an operator primed in the trace spec re-read `TraceLog[i+1]` with `i'`; the decision operators now take the snapshot, own id and chain value as arguments (`*In`) and the trace spec evaluates them without primes |

## Result

2026-11-18 17:20-18:00, `tools/tla/tla-check --workers 12 docs/tla/CBRD-28188`: **RESULT: OK**, run dir `.git_ignored_dir/scratch/tla/CBRD-28188-20261118-172035-2416443`.

| Cfg | Verdict | Distinct states / depth | Time |
|---|---|---|---|
| `PageVisibility` | pass (TypeOK, EquivNow, NoDecodeWhenAnswered, IndInv) | 4,472,968 / 16 | 161 s |
| `PageVisibility.scale-3tx` | pass | 22,826,918 / 17 | 403 s |
| 9 mutants | each violated as expected (table above) | 422-9,264 / 4-6 | 1-2 s |
| 5 witnesses | each reached (table above) | 348-39,964 / 4-6 | 1-2 s |
| `PageVisibilityInd.apalache-indinv` | pass (IndInv inductive, Apalache 0.62.4) | — | 682 s |
| `PageVisibilityTrace.witness-trace-run1` | accepted (3,453 events consumed) | 3,699 / 3,454 | 880 s |
| `PageVisibilityTrace.reject-flipped-fast` | refused at event 2220 | 2,465 / 2,220 | 258 s |
| `PageVisibilityTrace.reject-max-at-low` | refused at event 243 | 488 / 243 | 30 s |

TLAPS: not requested (P48).

Spec sha256 (run's `summary`):

```
d4291f4fb01858357de01b6f5f45a60d1f19a44088e34ffa1dc6acb050ef552f  PageVisibility.tla
d30f86d10ae54de00d17e9d25c014ae9268d63509bb2b455a38e65fa85bc0b5c  PageVisibilityInd.tla
ce94c47d67caa4d0b27750371d9e666034c25bad267c631d5fcd07e95064c3f8  PageVisibilityTrace.tla
d1bf86206d54362357d995484eef780231cb6cbb4200a58e52dc48f9ece9d6b7  PageVisibilityTraceData.tla
```

Engine: `aab8ac860` (draft PR CUBRID/cubrid#8614); trace recorded on its instrumented optdebug build (`~/optdebug/CUBRID-CBRD-28188-trace`). Gate of the same sha: optdebug libcubrid `9645c80a...`, release `6fa1a427...`; CTP sql 17,821 + medium 975, 0 NOK (`sql-20261118T080537Z-2293632`).

```
TLA+ 검증: 통과 — docs/tla/CBRD-28188
- 속성: C1 equivalence TLC 통과, IndInv 귀납성 Apalache (CBRD-28188 Specification Changes)
        C1a/C1b/C1c equivalence·safety TLC 통과 (EquivNow의 경우들), IndInv 귀납성 Apalache
        C2 safety TLC 통과, IndInv 귀납성 Apalache (CBRD-28188 Description)
- 결함: 없음 (in-place writer 의심은 census와 런타임 프로브로 모델 오류로 판정, mutant inplace_current_home으로 남김)
- mutant: 9개 모두 위반 검출 / 살아남은 mutant: 없음
- 경계: Tx={r,t1}, 데이터 페이지 1 + 헤더 페이지 1, 슬롯 1, MaxCrash 1; scale Tx={r,t1,t2}; IndInv 귀납성은 Apalache로 NS=2, MaxCrash=2, MaxId=4(역할 집합 크기 고정); liveness 주장 없음
- trace validation: 수용 1건(3,453 이벤트), 거부 2건 — 읽는 쪽 단계와 IdBound 전제를 검증, writer 단계는 레코드 내용으로만 반영
- 반례: 초안 2건, 둘 다 모델 오류로 분류(Counterexamples 표)
```
