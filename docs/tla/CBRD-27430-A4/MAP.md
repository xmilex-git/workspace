# CBRD-27430 A4 — one client workspace per session in the folded server

Map [CAS 폴드 재이식 지도](https://github.com/xmilex-git/workspace/issues/618), ticket
[A4 TLA+ 검증·이식](https://github.com/xmilex-git/workspace/issues/625). A4 is the stage where several in-process
sessions first run the client half at once: every client-half module global becomes a field of the session's
`client_session_context` (csc), reached only through an activation bracket that holds the csc's
`bracket_mutex`; `session_state` owns the csc and retires it. The model checks the bracket and the csc's life
(create, adopt, bracket, end, orphan, expiry retire, teardown, delete), the heap a client-half allocation lands
on, the process-shared areas, and the per-session client transaction flags A3 handed over.

Code: fork branch `cas-fold-v2`, A4 commit on `a4e52fdb1` (worktree `~/dev/cubrid-worktree/cas-fold-v2`). The
old implementation (`cas-merge` @ `cdb9da11e`: `c90ec1b5af`, `a2ca2d589d`, `042495732d`, the A5 commits
`cdea44b397` and `f86a00469a` for allocation routing and the teardown hat, the audit sweep `0ce32dc71f` for the
nesting abort and the method error message) was read and compared against this model; what the model rejects is
listed under Findings.

## Claim and sources

| # | Claim | Source |
|---|---|---|
| C1 | A session's client-half state (workspace and MOPs, `tm_Tran_*`, schema and trigger managers, connection identity) is touched only by the thread whose bracket holds that session's csc, one thread at a time. | #112 decision #123 D2–D3 (map #618 Notes: "브래킷 = 워크스페이스 소유"); A1 claim (wf173 D7) handed in #625's body; `client_session_context.hpp` |
| C2 | No thread is inside, waits for, or deletes a csc that was deleted: the csc lives while a thread holds a session reference through which it can reach it or holds its bracket (orphan protocol, the "no concurrent worker can reach this session" premise of `session_state_uninit`). | #123 D3, #133; #620 verdict A4 row (`session_state_uninit`, a retiring thread waiting on `bracket_mutex`) |
| C3 | Brackets never nest: a thread ending its own session from inside the csc never re-activates it (orphaned instead), and any other nesting aborts instead of self-deadlocking. | #620 A1 claim (bracket balance) in #625's body; old audit sweep `0ce32dc71f` (assert + abort) |
| C4 | Every free lands on the heap its chunk came from (client-half private memory lives in the session's workspace heap, whatever thread frees it), and the process-shared areas are created once and outlive every session's use. | #123 D5 and ALLOC-08 (cpp-perf-rules); A3 handover (#625 body: ROLLBACK and deadlock victim abort in `mspace_free`); CS/SA `db_private_alloc` (`memory_alloc.c`: `db_ws_alloc` while `!db_on_server`) |
| C5 | Every csc is eventually torn down exactly once and deleted, through the orphan path or the session's expiry. | #123 D3, #133 (liveness of the orphan path) |
| C6 | The RC snapshot flag and the RR lock mirror the boundary reads per call (`tm_Tran_invalidate_snapshot`, `tm_Tran_rep_read_lock`) are per session: one session's statement start or RR lock never reaches another session's enter or prefetch. | A3 handover in #625's body (both `CUB_THREAD_LOCAL`, empty under SERVER_MODE); A3 model `docs/tla/CBRD-27430-A3` claims C1, C4 (one session) |

## Refinement map (model -> code)

Line numbers below are at the A4 commit.

| Model | Code | One step because |
|---|---|---|
| `TNew(s)` | `server_compile_tracer.cpp tracer_session`: `new client_session_context ()` | thread-local object until activated |
| `Acquire` (`TAct`, `TRAct`, `AAct`, `DAct`) | `client_session_context.cpp csc_activate`: nesting check (`tl_Csc_active != NULL` → assert + `abort ()`), `bracket_mutex.lock ()`, `tl_Csc_active = ctx` | the thread-local write follows the lock with no shared access between; the wait is the label staying enabled-but-blocked (`AcqTarget`) |
| `TBootLock(s)`, `ReleaseBoot` | `tracer_Boot_mutex` around `db_restart_ex` and `boot_unregister_client` (client boot is not reentrant until A5) | a mutex |
| `TAreaCheck(s)`, `TAreaMake(s)` | `work_space.c ws_area_init` (and `pr_area_init`, `obt_area_init`, `classobj_area_init`): `if (<area> != NULL) return` under SERVER_MODE, else `area_create` | check and create are two steps, serialized only by the boot mutex |
| `TReg(s)` | `db_restart_ex` succeeded: `boot_register_client` created the session with the conn's reference (`session_state_create`, `session_state_increase_ref_count`); the boot loaded classes through the client half (`set_get_element` → `db_private_alloc` in the client hat) | under the boot mutex |
| `TBootFail(s)` | `db_restart_ex` failed after `ws_init` built the areas; `ws_init`'s error path (SERVER_MODE: no `*_area_final`) | fault |
| `TAdopt(s)` | `session.c session_adopt_client_context`: `state_p->csc_p = csc` | written by the session's only referencing thread before any other thread can find the csc |
| `TStmt`, `TEnter1`, `TEnter2` | `db_vdb.c db_invalidate_mvcc_snapshot_before_statement` sets `tm_Tran_invalidate_snapshot`; `network_interface_cl.c enter_server` consumes it (A3); both now `csc_tm ()` fields | inside the bracket (C1) |
| `TRR(s)` | `network_interface_cl.c tran_lock_rep_read`, mirror `tm_Tran_rep_read_lock` (`csc_tm ()`) | inside the bracket |
| `TFetch(s)` | a class fetch / value container: `db_private_alloc` with `!db_on_server` inside a bracket → `db_ws_alloc` (`memory_alloc.c DB_PRIVATE_IS_CLIENT_HALF`) | one call |
| `TRollback(s)` | `transaction_cl.c tran_abort` / `tran_abort_only_client` → `ws_abort_mops` → `ws_decache` → `classobj_free_class_constraints` → `db_ws_free` (`quick_fit.c`, heap `csc_ws ()->heap_id`) | inside the bracket |
| `TXfer(s)` | a server-half allocation of a call freed by the client half after the call (assumption A-XFER: none) | — |
| `TSessOp(s)`, `TEnd1(s)` | a session call taking the session mutex (`sessions.states_hashmap.find`, `session_state_destroy`) | the session mutex |
| `TEnd2(s)`, `AEnd2`, `EndSess` | `session.c session_state_destroy`: `session_state_decrease_ref_count`; busy → unlock; last → `session_state_uninit` → `csc_retire_and_delete` (`tl_Csc_active == ctx` → `orphaned = true`) → `erase_locked` | under the session mutex |
| `TUnreg(s)` | tracer `boot_unregister_client` then `css_free_conn` → `css_shutdown_conn` → `session_state_decrease_ref_count` | the decrement is one atomic step |
| `Deact` (`TDeact`, `ADeact`) | `csc_deactivate`: `orphaned` read once, `csc_teardown` if set, `tl_Csc_active = NULL` | under the bracket |
| `Unlock` | `csc_deactivate`: `bracket_mutex.unlock ()` | one release |
| `Del` | `csc_deactivate`: `delete ctx` when the value read before the unlock was set | the context is unreachable (C2) |
| `Reread` (mutant) | the old `csc_deactivate` (`cdb9da11e:client_session_context.cpp:88`): `if (ctx->orphaned)` after the unlock | — |
| `Teardown(t, c)` | `csc_teardown`: `db_on_server = 0` for its extent, `pt_free_label_table`, plan dump name, method error, execution plan, `ws_final (false)` (decaches through `db_ws_free`, value containers through `db_private_free`, destroys the session's lea heap); shared areas stay | under the bracket |
| `TNotAdopted`, `TRTear` | tracer: `csc_deactivate`, then `csc_retire_and_delete` when not adopted | no session can reach it |
| `ARef`, `ARead`, `AWork`, `AUnref` | another request on the session: `session_check_session` (reference under the entry mutex), `csc_p` read, its bracket, its reference drop. **No such caller exists in A4** (only the tracer brackets); the role is the B1 dispatch the orphan protocol is designed for | the reference is taken under the session mutex |
| `DScan`, `DUninit`, `DAct`, `DTear`, `DDel`, `DErase` | `session.c session_remove_expired_sessions` (re-check under the mutex kept to `erase_locked`) → `session_state_uninit` → `csc_retire_and_delete` (`csc_activate`, `csc_teardown`, unlock, `delete`); at shutdown `session_states_finalize` → `states_hashmap.destroy` → `session_state_uninit` on the shutdown thread (same steps, no other thread) | the session mutex is held from the scan to the erase |
| `cst`, `orphan`, `owner`, `active` | the csc object, `orphaned`, `bracket_mutex`, `tl_Csc_active` | |
| `sst`, `ref`, `smx`, `cscp` | the session in `sessions.states_hashmap`, `ref_count`, `session_p->mutex`, `csc_p` | |
| `clsH`, `pvH` | the heap of a class's constraint arrays (freed by `db_ws_free`) and of a value container (freed by `db_private_free`): heap `s` = `csc_ws ()->heap_id` of csc `s`, `100 + t` = `thread_p->private_heap_id` of thread `t` | |
| `areaCnt`, `areaLive` | `Objlist_area` / `Value_area` / `Template_area` / `Assignment_area` (`work_space.c`, `object_primitive.c`, `object_template.c`, `class_object.c`) | |
| `inv`, `rrMir`, `rrHeld`, `fresh` | `csc_tm ()->tran_invalidate_snapshot`, `->tran_rep_read_lock`, the RR lock on the server, the snapshot of the running statement | |
| `uaf`, `nested`, `badFree`, `areaUaf`, `stale`, `unstable`, `rrBad`, `viaOrphan`, `daemonWaited`, `busyEnd` | ghosts | — |

Callers of the protocol entry points: `csc_activate` — `tracer_session`, `csc_retire_and_delete`; `csc_retire_and_delete`
— `session_state_uninit`, `tracer_session` (not adopted); `session_adopt_client_context` — `tracer_session`;
`session_state_uninit` — `session_state_destroy`, `session_remove_expired_sessions`, the hashmap's `uninit` at
`session_states_finalize`. Exit paths of `csc_activate`/`csc_deactivate`: the nesting abort (`NoNest`); every other
path reaches the unlock.

## Properties

| Name | Kind | Statement | Claim |
|---|---|---|---|
| `TypeOK` | invariant | variable types | — |
| `Excl` | invariant | no two threads are inside one csc | C1 |
| `NoUAF` | invariant | no thread is inside, deactivates, deletes or re-reads a deleted csc | C2 |
| `NoWaitFreed` | invariant | no thread waits in `csc_activate` for a deleted csc | C2 |
| `NoNest` | invariant | no nested activation | C3 |
| `NoForeignFree` | invariant | every free hits the heap the chunk came from | C4 |
| `AreaOnce` | invariant | the shared areas are created once and never freed under a session | C4 |
| `TornOnce` | invariant | a deleted csc was torn down exactly once | C2, C5 |
| `FreshSnapshot`, `StableSnapshot`, `RRMirror` | invariants | A3's C1/C4 per session under two sessions | C6 |
| `AllFreed` | liveness | every csc is eventually deleted | C5 |
| `IndInv` | invariant | inductive strengthening (Apalache) | all |

## Fault model

| Fault | Modeled | Where / why not |
|---|---|---|
| error return of a call | partly | client-half errors stay inside the bracket and change no lifecycle state; the boot failure is `TBootFail` (no session, creator retires); a failed adoption leaves the same state as a boot failure |
| interrupt | no | an interrupt is an error return of a call inside the bracket |
| lock timeout | no | an error return inside the bracket |
| deadlock victim | yes, as `TRollback` | the victim's client reaction (`tran_abort_only_client` → `ws_abort_mops`) is the rollback's free path; the server-side abort is A3's model |
| OOM | no | `new client_session_context` throws before anything is shared; a failed `db_ws_alloc` is an error return |
| crash / `kill -9` | no | the csc is process memory; nothing durable |
| spurious wakeup | no | `std::mutex` |
| concurrent DML / vacuum | no | the server half's concern (the workspace caches only) |
| session expiry | yes | `DScan` (nondeterministic timeout); shutdown's `session_states_finalize` maps to the same steps |
| a second request on the same session | yes | the attacher (B1's dispatch; no A4 caller) |
| a session ended by a thread outside its csc | no | in A4 only a bracket holder ends a folded session (`EndSess` precondition); a wire client's session has `csc_p = NULL` |
| server half handing a chunk to the client half for freeing | as assumption A-XFER | `mutant-xfer`: with hat routing such a free hits the wrong heap (`mspace_free` aborts: fail-fast, never silent); census A-XFER below |

## Mutants

| Mutant | cfg | Re-enables | Expected | Claim |
|---|---|---|---|---|
| `no_mutex` | `mutant-no-mutex` | the A1–A3 bracket (`tl_Csc_active` only, no `bracket_mutex`) | `Excl` | C1 |
| `reread` | `mutant-reread` | the old `csc_deactivate` re-reading `ctx->orphaned` after the unlock | `NoUAF` | C2 |
| `a_unref_early` | `mutant-attach-unref-early` | a request dropping its session reference before taking the bracket | `NoWaitFreed` | C2 |
| `retire_reactivate` | `mutant-retire-reactivate` | `csc_retire_and_delete` without the self check (`c90ec1b5af` before `a2ca2d589d`) | `NoNest` | C3 |
| `no_route` | `mutant-no-route` | `db_private_alloc` on the thread's private heap in the client half (A1–A3: the A3 ROLLBACK core) | `NoForeignFree` | C4 |
| `tear_sv_hat` | `mutant-tear-server-hat` | teardown in the retiring thread's hat (`c90ec1b5af` before `f86a00469a`) | `NoForeignFree` | C4 |
| (Xfer) | `mutant-xfer` | a server-half chunk freed by the client half | `NoForeignFree` | C4 (assumption A-XFER) |
| `no_area_guard` | `mutant-no-area-guard` | unconditional `*_area_create` (A1–A3) | `AreaOnce` | C4 |
| `no_boot_lock` | `mutant-no-boot-lock` | concurrent client boots | `AreaOnce` | C4 |
| `err_frees_areas` | `mutant-err-frees-areas` | `ws_init`'s error path finalizing the shared areas | `AreaOnce` | C4 |
| `tear_frees_areas` | `mutant-tear-frees-areas` | a teardown finalizing the shared areas (`ws_final`'s sub-client branch) | `AreaOnce` | C4 |
| `no_delete` | `mutant-no-delete` | a retire that never deletes | `AllFreed` (liveness) | C5 |
| `sessop_unref` | `mutant-sessop-unref` | a session call after the conn dropped the session, inside the bracket | deadlock (daemon holds the session mutex and waits for the bracket) | C2, C5 |
| `shared_tm` | `mutant-shared-tm-stale`, `-unstable`, `-rr` | `tm_Tran_invalidate_snapshot` / `tm_Tran_rep_read_lock` process-global (A3) | `FreshSnapshot`, `StableSnapshot`, `RRMirror` | C6 |

## Witnesses

| cfg | Outcome reached |
|---|---|
| `witness-orphan` | a csc deleted through the orphan path (the session ended from inside it) |
| `witness-daemon-waited` | the expiry retire waited for a bracket the session's last client still held |
| `witness-busy-end` | a session end from inside the csc found another reference and left the session alive |
| `witness-bootfail-retired` | a csc no session adopted was retired by its creator |

## Counterexamples (correct variant) and their classification

1. Apalache inductive-check counterexamples while IndInv was built (unreachable starting states: an attacher
   target outside the session set, an area check that saw the area before it existed, an attacher inside a
   csc its tracer still held, two orphan holders of one csc, an orphan holder at `del` with a deleted csc):
   IndInv strengthened each time, never the spec. No TLC counterexample in a correct-variant cfg.

## Findings

- **H1 (old implementation, avoided in the port)**: the old `csc_deactivate` read `ctx->orphaned` again after
  `bracket_mutex.unlock ()`. A thread leaving a csc it did not orphan, while the session-expiry daemon waits for
  that bracket (the session's last reference already dropped), races the daemon's teardown and `delete`: the
  re-read is a use after free. `mutant-reread` is that code and fails `NoUAF`; the port reads the flag once
  before the unlock. Not reproduced at runtime (the window is the instructions between the unlock and the read,
  and the expiry needs `session_state_timeout` to pass after the reference drop); the port is the fix, the mutant
  records the defect.
- **A-XFER (assumption, fail-fast)**: allocation routing follows the hat (`!db_on_server` inside a bracket → the
  session heap). A chunk the server half of a call allocates (thread heap) and the client half frees after the
  call (session heap) would hit the wrong heap; `mspace_free` aborts on it (no silent corruption). The smoke and
  CTP runs are the census; the SA build routes such frees by a header instead.

## Per-session state table (census)

Writable data objects of the SERVER_MODE client-half objects (`readelf` over `cubrid.dir`, script
`.git_ignored_dir/scratch/fold-v2/a4/census.sh`, before/after lists `census-before.tsv`, `census-after.tsv`).
"csc" = a field of the session's context, reached through the bracket; "thread" = `thread_local`, the state lives
for one call on one thread; "shared" = process-wide by design; later stages own the rest.

| State | A4 | Why |
|---|---|---|
| `ws_Mop_table`, `ws_Mop_table_size`, `ws_Resident_classes`, `ws_Commit_mops`, `ws_Stats`, `ws_Num_dirty_mop`, `ws_Error_ignore_list/count`, `Ws_dirty`, `Null_object`, `Classname_cache`, `ws_MVCC_snapshot_version`, `ws_Defer_free`, `ws_Deferred_instances/classes`, `ws_Heap_id` (quick_fit), `oid_Next_tempid` | csc `ws` | the MOP closed system and its heap (C1, C4) |
| `tm_Tran_*` (incl. `tm_Tran_invalidate_snapshot`, `tm_Tran_rep_read_lock`), `tm_Tran_latest_query_status`, `tm_Query_timeout_info`, `tm_libcas_depth`, `user_savepoint_list` | csc `tm` | client transaction state (C6) |
| `Current_Schema`, `sm_Descriptors`, `sm_Root_class_mop`, `local/global_schema_version` | csc `sm` | MOPs of the session's workspace |
| `tr_*` (stack, caches, deferred lists, `tr_Execution_enabled`, `tr_object_map`), `do_/cdc_Trigger_involved` | csc `tr` | trigger caches hold MOPs; one session's `db_disable_trigger` stays its own |
| `obt_Enable_autoincrement`, `obt_Last_insert_id_generated`, `obj_Template_traversal`, `template_savepoint_count` | csc `obt` | |
| `db_Connect_status`, `db_Session_id`, `db_Session_secret`, `db_Keep_session`, `db_Row_count`, `db_Database_name`, `db_Program_name`, `db_Client_ip_addr`, `db_Client_type`, `db_Client_statement_type`, `is_doing_end_session`, `Qres_table`, `db_Execution_plan(_length)`, `db_Kept_trees` | csc `db` | connection identity and the session's query results; `db_Connect_status` outside a bracket is a process value (server threads) |
| `boot_Server_credential`, `obj_Method_call_level`, `obj_Method_error_msg`, `ib_thread_count`, the five savepoint-name counters (`execute_statement.c`) | csc | |
| `xs_method_eid`, `db_compile_statement_local::seed`, `cursor_open::empty_list_id`, `call_cnt`/`is_prepare_call`, `get_user_name::namebuf`, `g_open_buffer_control_flags`, `qo_*` plan counters and free list, `xts_*` (incl. develop's `xts_Index_stream`, `xts_Outptr_share_spec`, `xts_Agg_share_spec`), `__gv_locator_repl`, `bind_fp_active_*`, `row_snapshot_read::in_read` | thread | one call on one thread |
| `QO_INFINITY` | constant | `HUGE_VAL` at static init |
| `Objlist_area`, `Value_area`, `Template_area` ×2, `Assignment_area`, `Set_Ref_Area`, `Set_Obj_Area` | shared | MT-safe areas, created once (#123 D5) |
| `sm_Root_class`, `sm_Root_class_hfid`, `oid_*` class OIDs, `tp_*` domains and types | shared | the same database constants from every session (domain interning: B4) |
| `btree_Load_no_logging_index` | shared, read-only `false` | written only by loaddb |
| `db_Disable_modifications` | shared | HA toggle (B3) |
| `boot_*` statics (`boot_Process_id`, `boot_Client_id_buffer`, …), `db_Preferred_hosts`/`db_Connect_order`/host status, `prm_*`, `perfmon_Iscollecting_stats`/`perfmon_Stat_info`, `ddl_log.c` statics, `tz_*` | A5 | boot/sysprm lifecycle; serialized by the tracer's boot mutex in A4 |
| `cubmethod::handler`, `db_static_links`, `dl_*` | A7 | method/SP termination |
| `lc_Is_siginterrupt` | B5 | client signal state |
| `tp_Sub_client_domains`, `sysprm_Sub_client_session_params`, `boot_Is_sub_client`, `db_Is_sub_client_registered` | unreachable | applylogdb sub-clients only (`boot_Is_sub_client` is false in the server) |

develop's `MULTI_CONN_TO_A_SERVER` (CBRD-26779) marked most of these `CUB_THREAD_LOCAL`, which is empty under
SERVER_MODE; every marked one is in a row above. The globals `row_snapshot_cl.cpp` saves and restores around its
nested statement (`do_Trigger_involved`, the row count cache, `TM_TRAN_WAIT_MSECS`, …) are csc fields now and its
save/restore works on them unchanged.

## Dead expressions

| Line | Expression | Why TLC never evaluates it in the pass cfgs |
|---|---|---|
| CscSessions.tla:146 | `Goto` (operator line) | its uses in mutant-only branches: the nesting abort of `Acquire` and `EndSess` (`retire_reactivate`), `TLateOp` (`sessop_unref`), `AUnrefEarly` (`a_unref_early`), `TReread`/`AReread` (`reread`); every other use evaluates it |
| CscSessions.tla:154 | `Acquire` nesting branch | no correct-variant activation finds the thread inside a bracket (`R_bracket`: `active[t] = 0` at every acquire label); the code aborts there (`csc_activate`, assert + `abort ()`); `mutant-retire-reactivate` reaches the same abort through `EndSess` |
| CscSessions.tla:155 | `Acquire` nesting branch | as line 151 |
| CscSessions.tla:156 | `Acquire` `no_mutex` branch | mutant-only (`no_mutex`); `mutant-no-mutex` fires it |
| CscSessions.tla:197 | `Unlock` `no_mutex` branch | mutant-only (`no_mutex`) |
| CscSessions.tla:202 | `Reread` | mutant-only action (`reread`, the old `csc_deactivate`); `mutant-reread` fires it |
| CscSessions.tla:203 | `Reread` | as line 199 |
| CscSessions.tla:224 | `EndSess` busy branch, `AEnd2` context | the attacher's end is always the session's last reference: it holds the bracket only after the tracer's `csc_deactivate`, which follows the tracer's `css_free_conn` (`TUnreg` before `TDeact`; `R_attach`: an attacher inside the csc has its tracer at `del`/`na`/`done` with `connRef` false). In the `TEnd2` context the branch fires (`witness-busy-end`) |
| CscSessions.tla:225 | `EndSess` busy branch, `AEnd2` context | as line 221 |
| CscSessions.tla:230 | `EndSess` `retire_reactivate` branch | mutant-only; `mutant-retire-reactivate` fires it |
| CscSessions.tla:231 | `EndSess` `retire_reactivate` branch | as line 227 |
| CscSessions.tla:244 | `SetInv` `shared_tm` branch | mutant-only; the `mutant-shared-tm-*` cfgs fire it |
| CscSessions.tla:246 | `SetMir` `shared_tm` branch | mutant-only |
| CscSessions.tla:251 | `Touch` (operator line), `TXfer` context | `TXfer` is disabled with `Xfer = FALSE` (assumption A-XFER); `mutant-xfer` fires it; every other use evaluates it |
| CscSessions.tla:252 | `Touch`, `TXfer` context | as line 248 |
| CscSessions.tla:275 | `TBootLock` `no_boot_lock` branch | mutant-only; `mutant-no-boot-lock` fires it |
| CscSessions.tla:298 | `ReleaseBoot` `no_boot_lock` branch | mutant-only |
| CscSessions.tla:339 | `Step` (operator line), `TXfer` context | as line 248 |
| CscSessions.tla:353 | `Enter` flag-set branch, `TEnter2` context | the flag is consumed by the statement's first enter (`R_tm`: `inv[s]` only at `enter1`); in the `TEnter1` context it fires. Under `shared_tm` another session's start sets it (`mutant-shared-tm-unstable`) |
| CscSessions.tla:354 | `Enter` flag-set branch, `TEnter2` context | as line 348 |
| CscSessions.tla:356 | `Enter` flag-set branch, `TEnter2` context | as line 348 |
| CscSessions.tla:357 | `Enter` flag-clear branch, `TEnter1` context | the statement start always sets the session's flag before its first enter (`R_tm`); in the `TEnter2` context it fires. Under `shared_tm` another session consumes it first (`mutant-shared-tm-stale`) |
| CscSessions.tla:358 | `Enter` flag-clear branch, `TEnter1` context | as line 352 |
| CscSessions.tla:377 | `TRR` mirror-set branch (main cfg only) | a second `tran_lock_rep_read` in one transaction needs two work steps; `MaxWork = 1` in `CscSessions.cfg`. `CscSessions.scale-work2` (`MaxWork = 2`) evaluates it |
| CscSessions.tla:407 | `TXfer` | disabled with `Xfer = FALSE` (assumption A-XFER); `mutant-xfer` fires it |
| CscSessions.tla:410 | `TXfer` | as line 402 |
| CscSessions.tla:465 | `TLateOp` | mutant-only action (`sessop_unref`); `mutant-sessop-unref` reaches it |
| CscSessions.tla:485 | `TReread` | mutant-only action (`reread`) |
| CscSessions.tla:550 | `AUnrefEarly` | mutant-only action (`a_unref_early`); `mutant-attach-unref-early` fires it |
| CscSessions.tla:551 | `AUnrefEarly` | as line 545 |
| CscSessions.tla:553 | `AUnrefEarly` | as line 545 |
| CscSessions.tla:597 | `AReread` | mutant-only action (`reread`) |

## Bounds

Main: `N = 2` sessions (+ attacher + daemon), `MaxWork = 1`; scale: `MaxWork = 2`. IndInv: Apalache with
`N = 2` fixed and every `MaxWork`, both `Attach` and both `ServerInit` values. Every A4 cfg sets `ServerInit = FALSE`
(the tracer's boot lock, areas created by the first boot); the A5 model `docs/tla/CBRD-27430-A5` extends this module
with `ServerInit = TRUE` (the server boot creates the areas, no boot lock).

## Trace validation

Instrumented scratch worktree `~/dev/cubrid-worktree/cas-fold-v2-tla` (detached at `6d2aa5b02`, the A4 commit;
patch `.git_ignored_dir/scratch/fold-v2/a4/instrument.py`), install `~/optdebug/CUBRID-cas-fold-v2-tla`. Events go to
`CUBRID_TLATRACE_OUT` under one mutex that also assigns `seq`; only contexts a tracer created are logged
(`tla_id`), `p` is the tracer session (1..N) or 0 for any other thread.

Events: `New`, `BootLock`, `Reg`, `Adopt`, `Unreg` (tracer, `Reg` and `BootLock` under `tracer_Boot_mutex`);
`AreaCheck saw=` / `AreaMake` (`ws_area_init`, under the boot mutex); `Acquire c=` (`csc_activate`, after the lock);
`Deact c= orph=`, `Unlock` (`csc_deactivate`, before the unlock), `Del del=` (after it); `End1` / `End2 orph=0`
(`session_state_destroy`, under the session mutex), `End2 orph=1` (`csc_retire_and_delete`'s self branch); `Scan`,
`Uninit`, `Erase` (`session_state_uninit` on a thread outside the csc), `Tear` (before the unlock in
`csc_retire_and_delete`), `DDel` (after the `delete`). Not logged: the client-half work inside the bracket
(`TStmt`, `TEnter*`, `TRR`, `TFetch`, `TRollback`, `TSessOp`) and the steps with no code point of their own
(`TDoneWork`, `TNotAdopted`) — hidden in the trace spec.

| Run | Scenario | Events | Result |
|---|---|---|---|
| `traces/two-shutdown.log` | 2 sessions `SELECT COUNT(*) FROM a4r`; server stopped at once: the shutdown thread retires both contexts (`session_states_finalize`) | 34 | accepted (`witness-trace-two-shutdown`) |
| `traces/two-end.log` | 2 sessions `SELECT ? + ?` bound 30,12, `CUBRID_M0_TRACER_END=1`: each session ends from inside its bracket, the context is orphaned and deleted at the bracket exit | 26 | accepted (`witness-trace-two-end`) |
| `traces/two-expire.log` | as `two-shutdown`, server kept 130 s past the tracer with `session_state_timeout=60` | 34 | accepted (`witness-trace-two-expire`) |
| `traces/two-end-end2-dropped.log` | `two-end` without its `End2 orph=1` events | 24 | refused (`reject-end2-dropped`) |

`p=0` does not tell the session-control daemon from the shutdown thread, so `two-expire` shows the same steps as
`two-shutdown` without proving which thread retired; the smoke's case 24 (same hold) ran the server past the expiry
without a core or an assertion. Actions no run reaches: `TBootFail`, `TRAct`, `TRTear` (no boot failure was
injected), the attacher (`ARef` … `AUnref`: no A4 caller; B1), `TEnd2` busy (needs a second reference: B1),
`TLateOp`, `TReread`, `AReread`, `AUnrefEarly` (mutant-only).

## Result

- 2026-11-07, `tools/tla/tla-check docs/tla/CBRD-27430-A4`: `RESULT: OK` (27 cfgs), run dir
  `.git_ignored_dir/scratch/tla/CBRD-27430-A4-20261107-212533-1925838` (rerun after A5 added the `ServerInit`
  constant, `FALSE` in every A4 cfg; the first run was `CBRD-27430-A4-20261107-194650-1886692`).
- spec sha256: `670dd2522b53bae6cced155073cf0b41cb69555ccf1948f8c49a9b9e974d1e7e  CscSessions.tla`,
  `f9869d510bf972d00863a13ef7e1bcce03a65e2e86a2ea1036895927310c9da4  CscSessionsTrace.tla` (cfgs in the run's
  `summary.txt`; this section was written after the run).
- Correct variant: `CscSessions` 1,280,323 states / 421,923 distinct, depth 50; `.scale-work2` 8,245,835 /
  2,569,329, depth 53.
- Mutants: 16 cfgs, each rejected as expected (14 invariant violations, 1 deadlock, 1 liveness). Witnesses: 4
  reached. IndInv: Apalache inductive check pass.
- Trace: 3 runs accepted, 1 corrupted run refused. Engine `6d2aa5b02` + instrumentation, install
  `~/optdebug/CUBRID-cas-fold-v2-tla`.
- TLAPS: 요청 없음.
