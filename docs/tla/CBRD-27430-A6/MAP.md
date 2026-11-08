# CBRD-27430 A6 — a REVOKE recompiles other sessions' prepared statements

Map [CAS 폴드 재이식 지도](https://github.com/xmilex-git/workspace/issues/618), ticket
[A6 TLA+ 검증·이식](https://github.com/xmilex-git/workspace/issues/627). In the folded server the compile and
its authorization check run in the server, and a prepared statement skips both on re-execution. A6 makes a
REVOKE invalidate the plans other sessions keep, so their recompile checks the authorization again.

Code: fork branch `cas-fold-v2` at `07b856c43` (worktree `~/dev/cubrid-worktree/cas-fold-v2`). Line numbers
below are at `07b856c43`.

## Claim and sources

| # | Claim | Source |
|---|---|---|
| C1 | A grantee transaction that begins after a REVOKE committed runs no plan on the class the REVOKE took away — neither a new prepare nor a prepared statement kept from before. | [#118](https://github.com/xmilex-git/workspace/issues/118) D2 (REVOKE bumps the class schema version, the recompile re-runs the compile-time check) and the Resolution's premise "새 prepare는 다음 tran 경계부터 올바르게 막힌다"; user decision 2026-11-08 on H1: the authorization check reads the latest committed grants (`LC_FETCH_COMMITTED_VERSION`), so a REPEATABLE READ transaction that began before the REVOKE is refused too |
| C2 | The Au_cache bits are reset at every transaction end, per session. | #118 D6; `work_space.c` transaction callback (`Au_cache` reset on commit/abort) |
| C3 | A DROP of a class with grants revokes them (touching the class) before it frees the class's disk structures. | old fold fix wf171 ([#171](https://github.com/xmilex-git/workspace/issues/171)): the touch rebuilds the representation through `transfer_disk_structures` |
| C4 | An execution that holds the class lock never runs an XASL cache entry a schema change removed. | `xasl_cache.c:1113-1118` comment ("Without the locks, we cannot guarantee the entry will remain valid (somebody holding SCH_M_LOCK may invalidate it)") — the machinery D2 relies on |
| C5 | Reading the grants takes no lock, so a REVOKE never waits for a grantee transaction because of it. | `LC_FETCH_COMMITTED_VERSION` definition (`locator.h:185` "no lock, no transaction snapshot", CBRD-27369); user decision 2026-11-08 ("락·스냅샷 없음") |

GRANT does not bump (#118 D2: widening a privilege endangers no plan); not modeled.

## Refinement map (model -> code)

| Model | Code | One step because |
|---|---|---|
| `RUpdate` | `authenticate_grant.cpp au_revoke_class`: `au_fetch_instance (auth, AU_FETCH_UPDATE)` and `obj_inst_lock (auth, 1)` (605) take X on the grantee's authorization instance; `set_put_element` / `drop_grant_entry`, `delete_auth` | the grants live in that instance, X-locked to the commit; the update is invisible to other transactions until `RCommit` |
| `RTouch` | `au_revoke_class` -> `sm_touch_class` (707): `dbt_edit_class` takes SCH_M on the class; the class flush `locator_update_force` -> `xcache_remove_by_oid` (`locator_sr.c:6130`) marks every entry of the class deleted | SCH_M excludes every grantee's SCH_S / IS on the class from the lock grant to the commit's unlock |
| `RCommit` | `log_manager.c log_commit_local`: `logtb_complete_mvcc` (5255) | the MVCCID leaves the active set: a snapshot or committed read from now on sees the REVOKE |
| `RCleanup` | `log_commit_local` -> `log_cleanup_modified_class_list` (5282) -> `log_cleanup_modified_class` -> `xcache_remove_by_oid` (5182) | under SCH_M still |
| `RUnlock` | `log_commit_local`: `lock_unlock_all` (5305) | releases SCH_M and X |
| `RAbort` | the REVOKE fails (SCH_M lock timeout, deadlock victim, an error of the touch) and rolls back: `log_abort_local` -> `log_cleanup_modified_class_list` | one rollback; the grants keep their committed value |
| `SBegin`, `SStmt`, `SNext` | the tracer's / CAS's transaction and statement starts; RC: `db_invalidate_mvcc_snapshot_before_statement` (`db_vdb.c`) drops the statement snapshot | session-private |
| `SAuOther`, `SSkipOther` | the authorization check of another class before this class's lock: an earlier statement of the transaction, or under RC a view or synonym resolved after `pt_class_pre_fetch` (`db_vdb.c:1782` locks every class of the statement before `pt_compile`) | reads only; with the committed read it leaves no state (it built the snapshot the pre-A6 read used: mutant `snapshot-auth`) |
| `SPLock` | `pt_class_pre_fetch` / `au_fetch_class_internal` -> `locator_fetch_class` (SCH_S), held to the end of the transaction | one lock request; waits while SCH_M is held |
| `SAu` | `authenticate_access_class.cpp:885 check_authorization`: the Au_cache bits, else `authenticate_cache::update` (`authenticate_cache.cpp:127`): DBA / owner shortcut, then (SERVER_MODE) the read version set to `LC_FETCH_COMMITTED_VERSION` and the workspace snapshot version bumped (212), groups (216) and `apply_grants` over the user's and each group's authorization (248, 286); the class's bits only (`apply_grants`, `authenticate_grant.cpp:1542`) | the bits are computed while the session holds the class lock (`au_fetch_class_internal` locks before `check_authorization`), so no REVOKE of the class commits between the read and the cached bits' use in the transaction |
| (committed read, no lock) | `locator_lock_and_doesexist` (`locator_cl.c:1904`) caches no lock for a committed read; `locator_decide_operation_type` (`locator_sr.c:14580`) turns a requested S/IS into `S_SELECT` for it | without them the existence check of the "authorization" value took S on the authorization instance (mutant `committed-locks`) and the client then never fetched it again in the transaction (mutant `cached-lock`) |
| `SIns` | `query_manager.c xqmgr_prepare_query`: `xcache_find_sha1 (PREPARE)` finds a live entry, else `xcache_insert` (1121) | under the session's class lock |
| `SELook` | `xasl_cache.c xcache_find_xasl_id_for_execute`: `xcache_find_sha1 (EXECUTE)`, `time_stored` compare (1068); not found -> `ER_QPROC_INVALID_XASLNODE`, recompile | lock-free lookup; the entry may be removed right after |
| `SELock` | the related-object lock loop (1113-1143), IS on the class | waits while SCH_M is held |
| `SECheck` | the `XCACHE_ENTRY_MARK_DELETED` check after the locks (1146): removed -> recompile; else the plan runs | under the class lock |
| `SCommit`, `SAbort` | the session's commit / rollback (a lock wait timeout or deadlock victim while waiting): `lock_unlock_all`, snapshot dropped, Au_cache reset by the workspace's transaction callback | session-private |
| `DRevoke` | `schema_manager.c sm_delete_class_mop`: `au_object_revoke_all_privileges` (13910) -> `au_revoke` -> `au_revoke_class` -> `sm_touch_class` | under the DROP's SCH_M |
| `DFree` | `transfer_disk_structures (op, class_, NULL)` (13921) frees the indexes | under the DROP's SCH_M |
| `View` | the latest committed grant state (the REVOKE's MVCCID committed or not) | |
| `snap`, `auc`, `sLock`, `auS`, `wsAuth` | `tdes->mvccinfo.snapshot` as seen by the grant read; the Au_cache bits of the class; the SCH_S/IS lock; an S lock on the authorization instance; the workspace's cached lock on it | |
| `xdel`, `live`, `handle` | `cache_flag & XCACHE_ENTRY_MARK_DELETED`; the entry `xcache_find_sha1` returns; the prepared statement's `XASL_ID` | |
| `tranAfter`, `xpost`, `bad`, `badDel`, `dropCrash` | ghosts | — |

Callers of the entry points (code-index `callers`): `au_revoke_class` <- `au_revoke` <- `db_revoke`,
`db_revoke_object` (REVOKE), `au_user_revoke_all_privileges` (DROP USER: a revoke of another user's grants —
same steps), `au_object_revoke_all_privileges` (DROP CLASS / DROP PROCEDURE: `DRevoke`). `authenticate_cache::
update` <- `check_authorization`, `au_get_class_privilege` (same read). `xcache_find_xasl_id_for_execute` <-
`xqmgr_execute_query` (`SELook`..`SECheck`), `parallel_scan::task::clone_xasl` (a PX worker of a query whose
leader already holds the class locks: fault table). `xcache_remove_by_oid` <- `locator_update_force`
(`RTouch`), `log_cleanup_modified_class` (`RCleanup`), `locator_delete_force_internal` (DROP: the class is
gone, its prepared statements fail), `xserial_decache`, `xsynonym_remove_xasl_by_oid` (not this class's
authorization).

## Properties

| Name | Kind | Statement | Claim |
|---|---|---|---|
| `TypeOK` | invariant | variable types | — |
| `NoRevokedRun` | invariant | no `SECheck` runs a plan in a grantee transaction that began after `RCommit` | C1, C2 |
| `NoDropCrash` | invariant | the DROP's touch never follows the free | C3 |
| `NoRemovedRun` | invariant | no `SECheck` runs an entry marked deleted | C4 |
| `NoGranteeAuthLock` | invariant | no grantee holds S on its authorization instance | C5 |
| `IndInv` | invariant | inductive strengthening (main cfg and Apalache) | C1–C5 |

## Fault model

| Fault | Modeled | Where / why not |
|---|---|---|
| error return of the REVOKE (lock timeout on SCH_M, deadlock victim, touch error) | yes | `RAbort` from `updated` and `locked` |
| grantee lock wait timeout / deadlock victim | yes | `SAbort` from `plock` and `elock` |
| compile error other than authorization | no | ends the statement like a refusal (`SAu` -> `end`); no state of these claims |
| interrupt (KILL) of either session | no | ends the statement or the transaction: the same exits as `RAbort` / `SAbort` |
| OOM in `xcache_insert` | no | the statement fails before a handle exists (`query_manager.c:1123-1132`) |
| crash / `kill -9` | no | the XASL cache, Au_cache and workspaces are memory only; recovery rolls the REVOKE back or keeps it committed, both states the model has |
| concurrent DML on the class | no | DML takes IX on the class; no different exclusion from SCH_M than IS |
| vacuum | no | removes versions no snapshot sees; the committed read and the class lock do not depend on it |
| checkpoint, HA apply | no | not on these paths (HA's read-only transactions: B3) |
| PX worker re-finding the entry (`clone_xasl`) | no | the leader holds the class lock for the whole query, so no touch removes the entry meanwhile |
| a second REVOKE / GRANT | no | one REVOKE is the claim's unit; a GRANT widens and is not checked by a plan |
| fairness | — | no liveness claim |

## Mutants

| cfg | Re-enables | Expected | Claim |
|---|---|---|---|
| `mutant-snapshot-auth` | the grant read through the transaction snapshot (pre-fix, `07b856c43^` + old A6) | violation `NoRevokedRun` | C1 (H1) |
| `mutant-cached-lock` | the existence check caches S, so the grants are never fetched again in the transaction (before `locator_cl.c:1904`) | violation `NoRevokedRun` | C1 |
| `mutant-committed-locks` | the committed read takes S on the authorization instance (before `locator_sr.c:14580`) | violation `NoGranteeAuthLock` | C5 |
| `mutant-no-touch` | no `sm_touch_class` (develop) | violation `NoRevokedRun` | C1 |
| `mutant-touch-no-lock` | the touch removes the entries without SCH_M | violation `NoRevokedRun` | C1 |
| `mutant-no-au-reset` | Au_cache kept across transactions | violation `NoRevokedRun` | C2 |
| `mutant-no-recheck` | no `MARK_DELETED` check after the locks | violation `NoRemovedRun` | C4 |
| `mutant-drop-free-first` | the old DROP order (free, then revoke) | violation `NoDropCrash` | C3 |

## Witnesses

| cfg | Outcome that must be reachable |
|---|---|
| `witness-kept-recompiled` | a kept handle finds its entry removed after the REVOKE committed and recompiles |
| `witness-refused-after` | a transaction that began after the commit is refused at the check |
| `witness-refused-in-old-tran` | a REPEATABLE READ transaction that began before the commit is refused after it (the committed read) |
| `witness-revoke-aborted` | the REVOKE rolls back |

## Counterexamples (correct variant) and their classification

| Cfg / variant | Trace | Class |
|---|---|---|
| first model, code as ported (`snapshot-auth`): violation `NoRevokedRun` | S1 starts a transaction and reads (snapshot sees the grant), REVOKE updates, touches, commits, cleans, unlocks; S1 locks the class, the check passes through the old snapshot, inserts; S1 commits; next transaction runs the kept handle | **Hole H1**, every step maps to code; runtime reproduction below |
| first model, a fix that restricts entries compiled through an old snapshot: violation `IndInv` | RC: statement 1 compiled through an old snapshot (view path) caches the bits; statement 2 of the same transaction has a fresh snapshot but uses the cached bits and inserts an unrestricted entry | the snapshot-based restriction does not cover the Au_cache; the option was dropped (user chose the committed read) |

## Findings

| # | Defect | Model | Runtime | Fixed by |
|---|---|---|---|---|
| H1 | A REPEATABLE READ transaction that began before a REVOKE committed compiles the class after the commit (the grant read goes through its snapshot), and the plan serves the kept statement in later transactions | `mutant-snapshot-auth` | smoke case 36 on the A6-as-ported optdebug build: `S1 kept re-execute value = 1`; release build of the same code, lock probe: REVOKE at ~1 s, S1 compile after it passes, kept re-execute in the next transaction returns 1 | the committed read (`authenticate_cache.cpp:212`) — case 36: compile refused `-494` |
| H2 | The committed read of the first fix took S on the grantee's authorization instance through the existence check of the "authorization" value (IS requested for an object of unknown class, `locator_decide_operation_type` kept `S_SELECT_WITH_LOCK` for a committed read), so the REVOKE waited for the grantee's transaction | `mutant-committed-locks` | `cubrid lockdb` during case 36: tran 1 (grantee) holds S on `_db_authorization` 0\|1025\|41, tran 2 (REVOKE) blocked on X; gdb stack `check_authorization -> authenticate_cache::update -> au_get_object -> obj_get -> get_object_value -> locator_does_exist_object -> xlocator_does_exist -> xlocator_fetch -> locator_get_object -> lock_object (lock=S)` | `locator_sr.c:14580` |
| H3 | With H2 fixed the client still cached S for that object (`cache_lock.fetch_version_type = DIRTY`), skipped the server on later reads in the transaction and checked the class against the grants of the first read | `mutant-cached-lock` | case 36 after H2's fix: REVOKE no longer blocked, S1's compile after it passed again (`kept re-execute value = 1`); gdb: the second update's `locator_fetch_instance` of 0\|1025\|41 never reached `xlocator_fetch` | `locator_cl.c:1904` — case 36: compile refused `-494`, the REVOKE not blocked |

## Dead expressions

| Expression | Why |
|---|---|
| `RevokeRecompile.tla:167` (`RCleanup`'s `ELSE UNCHANGED <<xdel, live>>`) | mutant-only branch (`no-touch`) |

## Bounds

Main: NS = 2, MaxStmt = 3, AllowRR = TRUE (each transaction RC or RR). Scale: NS = 2, MaxStmt = 4 (NS = 3 did not finish in reasonable time on this host). Apalache:
IndInv inductive at NS = 2, MaxStmt = 3 (the entry-id range `1..MaxId` needs constant bounds, P42's known
issue). TLAPS: not used — the safety argument is lock exclusion plus "no check passes after the commit", the
state is finite and symmetric per session, and the risk lay in the code mapping (which trace validation and
the runtime probes cover), not in generalizing the session count.

## Trace validation

Instrumented scratch worktree of `07b856c43` (`~/dev/cubrid-worktree/cas-fold-v2-tla6`, optdebug install
`~/optdebug/CUBRID-cas-fold-v2-tla6`, both removed after recording; patch: workspace scratch
`fold-v2/a6/instrument.py`, `instrumented.diff`). Events: `RUpdate` after the grants are updated in
`au_revoke_class`, `RTouch` after `xcache_remove_by_oid` in `locator_update_force`, `RCommit` after
`logtb_complete_mvcc`, `RCleanup` after `xcache_remove_by_oid` in `log_cleanup_modified_class`, `RUnlock` after
`lock_unlock_all` (revoker only, traced class only); `SPLock` + `SAu ok` at the first `check_authorization` of
the traced class in a compile (its SCH_S is already held, so no conflicting step can fall between the lock and the
event), `SIns new` in `xqmgr_prepare_query`, `SELook found` / `SELock` / `SECheck run` in
`xcache_find_xasl_id_for_execute`, `SCommit` at `log_commit_local` entry (before the locks go); `DRevoke` /
`DFree` in `sm_delete_class_mop`. One mutex-ordered `seq`. Runner `fold-v2/a6/trace/run.sh` (the class OID from
`trace/getoid.sh`, a `cubrid lockdb` of the class locks).

| Run | Scenario | Events | cfg | Result |
|---|---|---|---|---|
| `traces/rr-refused.log` | smoke 36: grantee (RR) reads another class, REVOKE commits, grantee compiles the class | 7 | `witness-trace-rr-refused` | accepted |
| `traces/kept-recompiled.log` | smoke 34: grantee compiles, runs, commits; REVOKE; the kept statement finds its entry gone, the recompile is refused | 16 | `witness-trace-kept-recompiled` | accepted |
| `traces/drop.log` | smoke 37: DROP of an indexed class with a grant | 2 | `witness-trace-drop` | accepted |
| `traces/kept-found-after-revoke.log` | kept-recompiled with event 13 flipped to `found=1` (an entry found after the REVOKE committed) | 16 | `reject-kept-found-after-revoke` | refused |

Not reached by a run: `RAbort` and `SAbort` (a lock timeout or deadlock is a fault, modeled), the `SECheck`
recompile branch (an entry found before the touch and removed while the execution waited for its lock — a
window the touch's flush makes a few instructions wide), `SIns new=0` (a second session preparing the same text
while the entry lives).

## Result

- Date 2026-11-08. `tools/tla/tla-check docs/tla/CBRD-27430-A6` → `RESULT: OK`, run dir
  `.git_ignored_dir/scratch/tla/CBRD-27430-A6-20261108-124204-2376973`.
- `RevokeRecompile.cfg`: pass, 3,675,804 states / 905,133 distinct, depth 47.
- `scale-4stmt`: pass, 13,062,136 / 3,127,161, depth 57.
- Mutants 8/8 rejected (`snapshot-auth`, `cached-lock`, `no-touch`, `touch-no-lock`, `no-au-reset` →
  `NoRevokedRun`; `committed-locks` → `NoGranteeAuthLock`; `no-recheck` → `NoRemovedRun`; `drop-free-first` →
  `NoDropCrash`). Witnesses 4/4 reached.
- `apalache-indinv`: IndInv inductive (Apalache 0.62.4, NS = 2, MaxStmt = 3).
- TLAPS: not used (Bounds).
- Trace: 3 runs accepted, 1 corrupted run refused (build `07b856c43` + instrumentation, optdebug).
- Spec sha256: `RevokeRecompile.tla` 5fbd17ddd829f94f4244a2311aae8362d66a28e1c925952399b4ef32de3e2bfe,
  `RevokeRecompileTrace.tla` ba973d6337648dae5a67cd485d6d9358a3a7ae725e5effe5f39636959980b0a3,
  `RevokeRecompileTraceData.tla` be6cd77dd069161c255c48d41972a206203411d80ac22ce58eedf892c8785e74.
- Engine: `cas-fold-v2` `07b856c43`; smoke 37/37 on its optdebug and release builds.
