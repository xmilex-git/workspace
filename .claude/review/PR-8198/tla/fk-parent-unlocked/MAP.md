# FkParentUnlocked — PR 8198 (CBRD-27463) at fbaae2592

Model of the lock-free foreign-key existence check against a parent DELETE's three phases
(collect, wait out writers, lock/re-check/act) and the in-place RESTRICT check.
One parent key P, one child table, writers `w1 w2` (up to K statements each), deleter `d`.

## Claim and sources

| Claim | Kind | Sentence (property) | Source |
|---|---|---|---|
| C1 | safety | (NoOrphan) once the parent DELETE commits, no committed child row refers to P (CASCADE and RESTRICT) | JIRA A/C "RESTRICT 와 NO ACTION 에서 고아 없음", "CASCADE 와 SET NULL 에서 고아 없음"; design.md §3 |
| C3 | safety | (NoParentRowLock) the child's existence check holds no lock on the parent row | JIRA Summary, A/C "lockdb 가 부모 행에 S 락을 보이지 않는다"; PR body §1 |
| C4 | safety | (NoNewcomerWait) the parent statement never waits for the writer of an entry inserted after phase 1 read the key (a new row, or a slot an undone insert freed) | PR body §3 "수집 뒤 새로 들어온 삽입은 부모의 삭제 표시에서 기다리므로 부모 쪽은 그 삽입을 기다리지 않는다", "삽입을 되돌려 비워진 슬롯을 다른 행이 차지하면 ... 건너뛴다" (fbaae2592) |
| C5 | safety | (NoP1WaitHoldingChild) the writer of a row unchanged since phase 1 is never waited for while another child is locked | PR body §3 단계 2, commit 39631cfe9 "Wait out child writers before a cascade locks any child" |
| C6 | safety | (HeapFirst) phase 2 never passes a row whose X holder is blocked before stamping it | JIRA comment 2026-11-07 수정 2, commit a9f1fefef "Update the heap before the indexes in an UPDATE" |

Acknowledged, not claimed (PR Remarks, JIRA "이 이슈에 넣지 않는 것"): the parent statement waiting for a writer that
waits on the mark or the parent row (deadlock, a victim is rolled back); child-only cycles through unstamped X holders
or writers that arrive after phase 2. The model lets the detector pick a victim and checks C1 holds after it.

## Refinement map

| Model action | Code (fbaae2592) | Shared state | One step because |
|---|---|---|---|
| WInsHeap | `locator_insert_force` heap insert | heap row header (insid) | home page latch |
| WInsEntry | `locator_add_or_remove_index_internal` FK `btree_insert` | FK index entry | FK leaf latch |
| WChkPass / WChkFail / chk wait | `locator_check_foreign_key` -> `xbtree_find_unique_fk_existence` -> `btree_key_find_and_lock_unique_of_unique` (`lock_found_object=false`), `btree_key_wait_out_conflicting_writer` | PK key entry (delete mark) | PK leaf latch; the wait is `logtb_wait_for_tran_end` with no latch |
| WUpdAcq | select-phase lock + `locator_lock_and_get_object` owner wait, before `locator_update_force` | row X lock, row stamp | lock manager; folded (see fault table) |
| WUpdStamp | `locator_update_force` -> `heap_update_logical` (moved before index update) | heap header | home page latch |
| chk after WUpdStamp (updfk) | `locator_update_force` -> `locator_check_foreign_key (att_id)`; skipped when no FK column is SET (`locator_index_has_attr`) | — | as WChk |
| WStmtEnd | READ COMMITTED statement row-lock release (CBRD-27034) | row X | lock manager |
| WStmtFault | statement rollback (interrupt, unique violation, savepoint) | heap/entry undo, slot freed | log undo per record |
| WCommit / WAbort | `xtran_server_commit/abort` | tran state, MVCCID lock | — |
| DLock | parent row X from the DELETE's select phase | parent X | lock manager |
| DMark | `btree_mvcc_delete` in `locator_add_or_remove_index_internal` before `locator_check_primary_key_delete` | PK key mark | PK leaf latch |
| DCollect | `locator_collect_children_of_key` -> `locator_scan_fk_key` with `locator_satisfies_child_of_locked_parent` / `locator_satisfies_restrict_entry` / `locator_satisfies_child_being_written`; `locator_kept_note_inserts` | FK entries, `insr` | one leaf: FK leaf latch (assumption: a key's entries fit one leaf and its overflow chain is read under the latch walk) |
| DP2 / DP2Wait | `locator_wait_out_collected_writers` -> `locator_wait_out_child_writer` (`locator_peek_last_header`, `locator_is_other_row`, `logtb_wait_for_tran_end`) | heap header | home page latch per peek |
| DRCheck / DRWait | `locator_check_restrict_in_place` -> `btree_find_foreign_key` (seen list, `deferred_writer`) -> `btree_fk_object_does_exist` (`locator_lock_object_unless_ours`) | FK entries, child S | FK leaf latch per scan; wait outside |
| DP3 | `locator_keep_referring_children` -> `locator_gathered_row_gone`, `locator_lock_gathered_child` | child X | lock manager |
| DP3Read / DP3Wait | `locator_lock_gathered_child` locked read, `locator_child_still_refers` | heap header | home page latch |
| DAct / DCommit | cascade delete of kept children; commit | row/entry delid, PK key gone | — |
| DFail | ER_FK_RESTRICT, statement and transaction rollback | mark undone | — |
| Victim | deadlock detector (`lock_detect_local_deadlock`), infinite lock timeout -> whole transaction rolled back | — | — |

## Fault table

| Fault | Modeled | Where / why not |
|---|---|---|
| error return | partly | WStmtFault (statement failure at chk / statement end); OOM paths of phase 1/2 not modeled (code returns the error before any child is locked: `locator_collect_children_of_key`) |
| interrupt | yes | WStmtFault while the check waits |
| lock timeout, deadlock victim | yes | Victim on any wait cycle among d, w1, w2 |
| conditional latch failure | n/a | no conditional latch in the mapped code changes |
| OOM | no | see error return |
| crash | n/a | no new durable write order; recovery undoes as rollback |
| spurious wakeup | n/a | no condition wait; `logtb_wait_for_tran_end` is a lock wait |
| concurrent DML | yes | writers insert, update, set FK, roll back, reuse slots |
| vacuum | no | an entry vacuumed after phase 1 is a committed-deleted child, which phase 3 skips; not modeled |
| checkpoint / page replacement | n/a | no page held across steps |
| HA log apply | no | `LOG_CHECK_LOG_APPLIER` skips RESTRICT; repl_update_lsa save/restore not modeled |
| nested statement | n/a | the scans use no snapshot (current state) |

Not modeled (claims outside this model): self-referencing PK UPDATE (c95b7ee1e), `repl_update_lsa` restore,
partition root comparison, multi-parent cycles (the a9f1fefef repro used two parents; C6 states the order instead),
REPEATABLE READ, `locator_kept_add` memory-to-list spill, `locator_lock_object_unless_ours` owner bypass (RESTRICT on
our own child behind a waiting updater), loaddb rows.

## Mutants

| Mutant | Claim | Removes | Expect |
|---|---|---|---|
| lock_parent_s | C3 | develop: the check holds S on the parent row | violation NoParentRowLock |
| check_before_entry (cascade, restrict) | C1 | child checks before publishing its FK entry | violation NoOrphan |
| scan_before_mark | C1 | parent reads children before the mark | violation NoOrphan |
| exclude_inserting | C1 | CBRD-27464 enumeration (inserting children excluded) without the parent row lock | violation NoOrphan |
| lock_before_wait | C5 | phase 2 removed (before 39631cfe9) | violation NoP1WaitHoldingChild |
| heap_after_index | C6 | UPDATE stamps the heap after its FK check (before a9f1fefef) | violation HeapFirst |
| no_seen_filter | C4 | RESTRICT waits every entry being inserted | violation NoNewcomerWait |
| no_inserter_compare | C4 | phase 2/3 take a reused slot's row as the gathered one (before fbaae2592) | violation NoNewcomerWait |

## Witnesses

cascade deletes a child whose insert it waited out; RESTRICT fails on a committed child; RESTRICT commits;
a deadlock victim is chosen; a reused slot is skipped.

## Dead expressions

- Mutant-only: FkParentUnlocked.tla:133 (the `lock_parent_s` arm of WChkPass).
- FkParentUnlocked.tla:176 — `DUnchangedW`, an UNCHANGED tuple TLC reports by its definition line.
- RESTRICT arms, dead in the CASCADE cfgs (main, scale-ns4): FkParentUnlocked.tla:239 FkParentUnlocked.tla:240
  FkParentUnlocked.tla:243 FkParentUnlocked.tla:244 FkParentUnlocked.tla:245 FkParentUnlocked.tla:246
  FkParentUnlocked.tla:247 FkParentUnlocked.tla:252 FkParentUnlocked.tla:253; they fire in the restrict cfgs.
- `DAbortCore`'s undo of delids and of a live mark, dead in the CASCADE cfgs: FkParentUnlocked.tla:293
  FkParentUnlocked.tla:294 FkParentUnlocked.tla:295 FkParentUnlocked.tla:296 FkParentUnlocked.tla:298. The parent
  statement acts (DAct) and commits in the next step after its last wait, so a victim never has acted
  (`locator_check_primary_key_delete ()` acts on the kept children only after the last locked read); the restrict
  cfgs reach DFail through this operator.
- CASCADE phase 3 and DAct, dead in the restrict cfgs (restrict, scale-restrict-ns4): FkParentUnlocked.tla:258
  FkParentUnlocked.tla:261 FkParentUnlocked.tla:262 FkParentUnlocked.tla:263 FkParentUnlocked.tla:264
  FkParentUnlocked.tla:269 FkParentUnlocked.tla:271 FkParentUnlocked.tla:272 FkParentUnlocked.tla:273
  FkParentUnlocked.tla:274 FkParentUnlocked.tla:277 FkParentUnlocked.tla:278 FkParentUnlocked.tla:282
  FkParentUnlocked.tla:283 FkParentUnlocked.tla:284 FkParentUnlocked.tla:285.

## Trace validation

Instrumented build: scratch worktree `~/dev/cubrid-worktree/pr8198-instr` at fbaae2592 plus 89 added lines
(`TLATRACE` events, `src/base/tla_trace.hpp`), optdebug install `~/optdebug/CUBRID-pr8198-instr`
(libcubrid `f31b3681`). Events: WInsHeap, WInsEntry, WChkPass/WChkFail, WUpdStamp, DMark, DCollect (slots and
inserters), DP2 (slot, writer, other-row skip), DP2Wait, DRCheck, DRWait, DP3 (skip), DP3Read (kept), DAct,
DFail, Commit/Abort before `log_commit`/`log_abort`. `traces/normalize.py` renames tran indexes, OIDs (sorted to
slots) and MVCCIDs to the model's names. CS mode, one server, key 7.

| Run | Shape | Result |
|---|---|---|
| A | CASCADE, initial child + uncommitted insert; phase 2 waits the inserter, both deleted | accepted |
| B | CASCADE, newcomer insert after the mark is not waited; the waited inserter rolls back, phase 3 skips its slot; newcomer fails ER_FK_INVALID | accepted |
| C | RESTRICT, inserter waited, then commits; in-place check finds it, DFail | accepted |
| D | RESTRICT, inserter rolls back; check passes, parent deleted | accepted |
| E | CASCADE, non-key UPDATE of the child stamped before phase 2; phase 2 waits it | accepted |
| F | CASCADE, inserter undoes its insert to a savepoint, a newcomer takes the same OID; phase 2 skips it as another row (fbaae2592) | accepted |
| reject-check-pass-after-parent-gone | B with the newcomer's check passing after the parent committed | refused |
| reject-collect-before-mark | A with DCollect before DMark | refused |
| reject-wait-ends-before-commit | A with DP2Wait before the inserter's commit | refused |
| reject-wait-on-reused-slot | F with phase 2 waiting the newcomer in the reused slot | refused |

Hidden (not logged): WStart, WEnd, WUpdAcq, WStmtEnd, WStmtFault, WInsHeapLost, DLock, empty-phase DP2/DP3,
DP3Read's wait branch, DP3Wait. Actions no run reached: DRWait (after phase 2 waited every seen writer, a
single-FK RESTRICT key has no writer left for the in-place check to wait, except a delete-in-progress that phase 1
also saw), DP3Wait (a writer arriving between phase 2 and phase 3 needs a timed injection), Victim, WStmtFault
as a logged action (F rolls back to a savepoint, hidden).

## Bounds

Writers 2, K 2 statements each, NS 3 slots (scale NS 4), one parent key, InitChild TRUE for CASCADE and FALSE for
RESTRICT (a committed initial child would fail every RESTRICT DELETE).

## Result

- Date: 2026-11-10. Run dir: `.git_ignored_dir/scratch/tla/fk-parent-unlocked-20261110-172630-3299704`.
- `RESULT: FAILED (1)` — the only failure is the completeness line "no inductive cfg": IndInv and its Apalache
  check are not written. Every one of the 30 cfgs passes its expectation.
- TLC: main CASCADE 8,067,548 distinct states depth 41; restrict 4,009,731 depth 33; scale-ns4 23,305,032 depth 42;
  scale-restrict-ns4 11,807,188 depth 33; 10 mutants violated as expected; 6 witnesses reached.
- Trace validation: 6 runs accepted, 4 corrupted runs refused, on the instrumented fbaae2592 build (libcubrid
  `f31b3681`).
- TLAPS: not requested.
- Spec sha256:
  - `32f86ac79ba81b0768e51e3baa192b6acc3868f9cb8cc7737004d31ccef40f25  FkParentUnlocked.tla`
  - `889ff0947a608edb1d71e91d63d02f95dbb465b07292ff9b70c07bdc06fae413  FkParentUnlockedTrace.tla`
  - `52383b642638833c31ae882f362ae64262b1a34ba011f02cbea9fc5e3355fae3  FkParentUnlockedTraceData.tla`
