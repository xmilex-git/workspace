# CBRD-27430 A7 — the method/SP callback of a folded session terminates in-process

Map [CAS 폴드 재이식 지도](https://github.com/xmilex-git/workspace/issues/618), ticket
[A7 TLA+ 검증·이식](https://github.com/xmilex-git/workspace/issues/628). Until A7 a folded session's stored procedure
or method could not run: the PL executor raises its callbacks (SQL semantics while a PL/CSQL routine compiles,
INTERNAL_JDBC queries and transaction ends while a routine runs, the builtin C method protocol) toward "the client"
over the connection, and a folded session's thread has none. A7 terminates the callback on the thread that raised it,
inside the session's activation bracket (the SA shape), and makes the state the callback touches the session's own.

The model `MethodFold` extends the A4 module `CscSessions` (linked from `docs/tla/CBRD-27430-A4`, constant
`ServerInit = TRUE` as in A5). A4's lifecycle steps drive A7's state through one hook (registration creates the pl
session, a teardown retires the session's callback handler, the session's uninit deletes the pl session); A7's steps
are one statement per tracer that calls a stored procedure, plus one parallel-scan worker per session. The attacher
and A4's own work steps stay in A4's cfgs.

Code: fork branch `cas-fold-v2`, A7 commits `c54a1b4ef` and `d5ccd9ad8` on `07b856c43` (worktree `~/dev/cubrid-worktree/cas-fold-v2`). The old
implementation (`cas-merge` @ `cdb9da11e`: the 23 commits the attribution table gives A7, `d1a4e00c59` …
`dc6a0c3184`, diffs in the tooling scratch `fold-v2/a7/old-*.diff`) was read and compared against this model and
develop; Findings lists what was kept, changed and dropped.

## Claim and sources

| # | Claim | Source |
|---|---|---|
| C1 | A callback raised on a thread that holds a session's bracket is dispatched on that thread, under that bracket, without a second activation; the session's pl session admits that thread; a thread without a bracket keeps the wire path, and a parallel-query worker never reaches the seam. | #112 decisions #120 D2/D7 (map #620 verdict, A7 claim C1); old `d1a4e00c59`; develop `pl_execution_stack_context.cpp` `reject_client_callback` (CBRD-27299) |
| C2 | The callback handler (query handles holding the session's workspace values) and the builtin methods' runtime arguments are the session's: only a thread in that session's bracket uses or frees them; a transaction boundary defers the handles and the outermost dispatch exit frees the deferred ones (no handle a dispatch still executes is freed under it); csc_teardown retires the rest inside the bracket before `ws_final`; the pl session's delete touches none of them. | #120 D8 (map #620 A7 claim C2); old `d1a4e00c59`, `5bf656350b`; CS `deferred_flush_guard` (`network_cl.c`) |
| C3 | Every exit of a dispatch (normal, refused too deep, an error status) puts back the hat, the libcas depth and the error stack: each pop finds its own frame, the client half's clear-all stops at the dispatch's frame, and the server executor resumes in the server hat with the error state it had (a callback error the routine handled does not reach it; an error the dispatch returns does). | map #620 A7 claim C3; old `5bf656350b`, `5635c93b9f`, `5e2883487e`; CS: the callback ran in the CAS process, whose error stack the server never saw |
| C4 | `execute_info` deletes only the `call_info` that `unpack ()` allocated, never a query handler's own member. | map #620 A7 claim C4 (#170); old `4b53eb90ef` |
| C5 | The outer query's parallel-scan workers unpack the outer query's XASL, never a nested query's or a freed one, and after a nested query the thread's unpack info is the outer query's again. | old `be0e48c66e` (px_scan assert under in-process nested PL SQL) |
| C6 | A transaction end inside a dispatch leaves the suspended outer executor's page fixes in place. | old `1f2724d558`, `d573718bdb`; CS: the CAS ended the transaction on another server thread, which held none of them |

## Refinement map (model -> code)

Line numbers are at the A7 commit.

| Model | Code | One step because |
|---|---|---|
| `TStart(s)` | `xqmgr_execute_query` → `qmgr_process_query` installs the outer XASL's unpack info (`query_manager.c`), `qexec_execute_query` starts; a parallel heap scan starts its workers (`px_scan.cpp` `start`); `fetch_peek_dbval` reaches a `TYPE_SP` regu (`fetch.c`) with the executor's scan pages fixed | the tracer thread's own state; the workers are launched, their clone is `PClone` |
| `TNext(s)` | the routine's next callback: `execution_stack::send_data_to_client_recv` again from the same `cubpl::executor` (one dispatch per prepare, execute, fetch, …), from the outer executor between callbacks or inside a nested query whose routine still runs | no shared state; the next `TCall` does the work |
| `TCall(s)` | `cubpl::executor` → `cubpl::get_session` (`pl_session.cpp:47`, the gate admits `csc_bracket_is_active ()`) → `session_get_pl_session` (session lookup) → `xs_callback_send_and_receive` → `xs_callback_send` (`network_callback_sr.cpp`): with a bracket, `method_dispatch` (`query_method.cpp`): `db_on_server = 0`, `er_stack_push`, `er_dispatch_floor = er_stack_depth ()`, `tran_begin_libcas_function`, the depth check: above the limit `ER_SP_TOO_MANY_NESTED_CALL` (`deep`), except a `METHOD_CALLBACK_CHANGE_RIGHTS` notification (`rights`, `method_is_change_rights`), which does no work | thread-local state and the csc (bracket held, A4 C1); the pl session lookup takes the session mutex, the pl session lives while the session is registered |
| `TQuery1(s)` | `callback_handler::prepare` / `execute` (`method_callback.cpp`) on `get_callback_handler ()` (the csc's, created on first use) → `db_execute` → folded `qmgr_execute_query` → `qmgr_process_query`: saves the caller's unpack info, installs the nested one (one-shot stream or NULL for a cached clone); a nested query that calls a routine re-enters `TCall` with the handle's execute on the stack | the csc's handler (bracket); the thread's unpack info is read by the workers only through the query entry (`PClone`) |
| `TQuery2(s)` | end of `qmgr_process_query`: one-shot tree freed (`query_entry->xasl_buf_info = NULL` first), `set_xasl_unpack_info_ptr (thread_p, outer_unpack_info)`; the handle's execute returns through the handle | thread-local |
| `TErr(s)` | the callback's query fails: `m_error_ctx` packs the error into the response (`xs_pack_and_queue (METHOD_RESPONSE_ERROR, …)`), the dispatch status stays `NO_ERROR`, the client half's `er_set` is the thread's current error | thread-local |
| `TCommit(s)` | `callback_handler::end_transaction` → `tran_commit`/`tran_abort` (`transaction_cl.c`): `free_query_handle_all (true)` moves the handles to the deferred list (`db_admin.c`, `execute_statement.c`), `er_stack_clear_above (csc_er_stack_floor ())` (was `er_stack_clearall`), the folded `xtran_server_commit` → `lock_unlock_all` → `pgbuf_unfix_all`, which returns at once inside a dispatch (`page_buffer.c`, `csc_in_method_dispatch ()`) | the csc's handler and the thread's own error stack and fixes |
| `TDone`, `TExit(s)` | `method_dispatch_internal` returns; `tran_end_libcas_function`; at depth 0 `free_deferred_query_handler` (between `er_stack_push`/`pop`); `er_dispatch_floor` restored; `er_stack_pop` (status `NO_ERROR`) or `er_stack_pop_and_keep_error`; `db_on_server` restored; `xs_callback_send` returns `er_errid ()` for an error status; `xs_callback_receive` takes the response off the csc handler's queue | the thread's own state and the csc |
| `TResume(s)` | the executor reads the response (`func (buffer)`), `fetch.c` checks `er_errid ()` after `executor.execute`, normalizes an object result (`method_result_to_server_semantics`), and goes on with its fixed pages | thread-local |
| `TEnd(s)` | end of `qexec_execute_query` (the parallel scans closed: workers joined), end of `qmgr_process_query` | the workers are joined before |
| `PClone(s)` | `px_scan_task.cpp` worker start: `stx_map_stream_to_xasl` from `m_query_entry->xasl_buf_info` under the main thread's `m_px_lock_mutex` (was the main thread's `xasl_unpack_info_ptr`); `px_scan.cpp` checks the same field at the scan start | the field is set before the scan starts and cleared after the workers joined |
| `Hook`, `pls` | `session.c:782` `new PL_SESSION` at session creation; `session_state_uninit` `delete session->pl_session_p` after `csc_retire_and_delete` (`session.c:387`) | under the session's creation / uninit |
| `Hook`, handler retire | `csc_teardown` (`client_session_context.cpp`): `method_callback_session_final ()` (`clear_all_query_handlers`, delete) and `method_runtime_args_session_final ()` after `sm_final`, before `db_final_client_query_result` and `ws_final` — the order of `boot_finalize_client_sub` | inside the bracket of the retiring thread (A4) |
| `hq`, `hd`, `hl` | `callback_handler::m_query_handlers`, `m_deferred_query_free_handler`, `client_session_context::method_callback_handler` | |
| `dep`, `hat`, `er`, `cur`, `flr`, `fr` | `tm_context::libcas_depth`, `db_on_server`, the thread's `cuberr::context` stack and current error, `client_session_context::er_dispatch_floor`, `method_dispatch`'s locals | |
| `uxi`, `fix`, `pw`, `xf` | `thread_p->xasl_unpack_info_ptr`, the thread's page holders, the scan's worker, a server frame below the callback | |
| `crossH`, `hUaf`, `erBad`, `erLeak`, `hatBad`, `plUaf`, `xaslBad`, `pageUaf`, `ciBad`, `wireFail`, `gateRefused`, witnesses | ghosts | — |

Callers of the protocol entry points: `xs_callback_send` — `xs_callback_send_args` (`method_invoke_group::prepare`),
`xs_callback_send_and_receive` (`method_invoke_group::execute`, `execution_stack::send_data_to_client_recv`);
`method_dispatch` — `xs_callback_send` (SERVER_MODE, SA_MODE); `get_callback_handler` — `method_dispatch_internal`,
`xs_get_data_queue`, `xs_callback_receive`, `db_commit_transaction`/`db_abort_transaction`/`db_2pc` (`db_admin.c`),
`do_commit`/`do_rollback` (`execute_statement.c`); `method_callback_session_final` — `csc_teardown`,
`method_callback_final` (`boot_finalize_client_sub`, `boot_client_all_finalize` when a bracket is held);
`csc_in_method_dispatch` — `pgbuf_unfix_all`, `lock_suspend`, `IS_IN_METHOD_OR_JSP_CALL` (`query_manager.c`).
Exit paths of the dispatch: a refused depth (`ER_SP_TOO_MANY_NESTED_CALL`, `TCall` deep → `TExit`), an error from
`method_dispatch_internal` (status kept), a pack failure (`xs_pack_and_queue` returns `er_errid ()`, an error
status), an interrupt (an error return of the callback's query: `TErr` or an error status). Every one goes through
the single exit block of `method_dispatch`.

## Properties

| Name | Kind | Claim |
|---|---|---|
| `InProcess` | safety | C1 |
| `NoNest` (A4) | safety | C1 (no second activation) |
| `OwnHandles` | safety | C2 |
| `NoHandleLeak` | safety | C2 |
| `ErBalanced` | safety | C3 |
| `CallInfoOwned` | safety | C4 |
| `OuterXasl` | safety | C5 |
| `OuterFixes` | safety | C6 |
| `NoPlUaf` | safety | C2 (the pl session a callback reaches lives) |
| A4's `Excl`, `NoUAF`, `NoWaitFreed`, `NoForeignFree`, `AreaOnce`, `TornOnce`, `AllFreed` | safety, liveness | A4 claims under the A7 steps |
| `IndInv7` | inductive | all of the above |

## Fault model

| Fault | Modeled | Where / why not |
|---|---|---|
| error return of a callback query | yes | `TErr` (the error in the response, status `NO_ERROR`) |
| error status of a dispatch | yes | the refused depth (`TCall` deep, DeepAt=1 cfgs); `method_dispatch_internal` errors and a pack failure take the same exit block (`TExit` with `st # "ok"`) |
| interrupt | as an error | the callback's query returns `ER_INTERRUPTED` (`TErr`), or the PL session reports it at `get_session` (an error return before the dispatch: no state changed) |
| lock timeout, deadlock victim of a callback query | as an error | the query fails (`TErr`); `lock_suspend`'s victim path calls `pgbuf_unfix_all`, which returns inside a dispatch like `TCommit` (`OuterFixes`) |
| a nested query waiting for a lock while the outer executor holds page fixes | no (equivalence) | the latch-holding wait existed in CS: the outer executor's thread held the same fixes while the CAS ran the callback's query on another server thread; the fold has the same fixes and the same wait. `lock_suspend`'s assert is skipped inside a dispatch (`shortcut:` comment) |
| OOM | no | `new callback_handler` failing throws out of the dispatch (as in CS's CAS); a failed `db_private_alloc` in `qmgr_server_db_values` returns an error before the session variable is set |
| crash / `kill -9` | no | handlers, runtime arguments and the error stack are process memory |
| session expiry while a routine runs | yes (A4) | `DScan` needs `ref = 0`; the tracer holds its connection's reference while it runs a statement (`Life` waits for `sp = "idle"`) |
| the session ended from inside its bracket, then a routine | yes | `TCall` with `sst # "live"`: `session_get_pl_session` finds no session and the call fails |
| a parallel-query worker reaching the seam | no (code fact) | `execution_stack::send_data_to_client*` refuses with `ER_SP_PARALLEL_ENABLE_NO_SQL` on a px worker before `xs_callback_send` (`pl_execution_stack_context.cpp:54`); a px worker holds no bracket |
| `METHOD_CALLBACK_CHANGE_RIGHTS` at the depth limit | no | exempt from the depth check (`method_is_change_rights`); a notification with no reply, no state |
| `ddl_log.c` statics reached through `callback_handler::prepare`/`execute` | no (code fact) | `ddl_logging_enabled` is written only by `logddl_check_ddl_audit_param`, whose callers are CAS, csql and loaddb (`cas_common_main.c:1250`, `csql.c:3327`, `load_db.c:649`), none in the server: the callbacks read a `false` nobody writes (B1 handover) |
| `db_make_method_error` / `db_get_method_error_msg` empty under SERVER_MODE | no (code fact) | no caller in the engine: only a user's native C method calls them, and the folded server refuses those before linking (`sm_dynamic_link_class`) |
| `dl_*`, `db_static_links` | no (code fact) | written by `dl_initiate_module` / `db_install_static_methods` at server boot only (A5); with native methods refused no session links |
| server shutdown | not as a step | `session_states_finalize` retires every context (A4) |

## Mutants

| Mutant | Re-enables | Violates | Claim |
|---|---|---|---|
| `wire` | the callback takes the wire path in a bracket (the A6 code) | `InProcess` | C1 |
| `gate_worker` | `cubpl::get_session` admits only `TT_WORKER` (the A6 code) | `InProcess` | C1 |
| `reactivate` | the dispatch activates the csc again | `NoNest` | C1 |
| `process_handler` | one handler for the process (develop's `static CUB_THREAD_LOCAL`, empty under SERVER_MODE: the A6 code) | `OwnHandles` | C2 |
| `handler_on_pl` | the handler lives on `cubpl::session`, retired by its delete in `session_state_uninit` | `OwnHandles` | C2 |
| `no_retire` | `csc_teardown` does not retire the handler | `NoHandleLeak` | C2 |
| `drain_each_exit` | the deferred handles are freed at every dispatch exit | `OwnHandles` | C2 |
| `no_drain` | the deferred handles are never freed before the teardown | `NoHandleLeak` | C2 |
| `no_isolation` | no error-stack frame around the dispatch | `ErBalanced` | C3 |
| `clearall` | the client half's clear-all reaches below the floor | `ErBalanced` | C3 |
| `err_keeps_hat` | an error exit leaves the client hat on | `ErBalanced` | C3 |
| `ci_compile` | `~execute_info` deletes `call_info` under SERVER_MODE (the A6 code) | `CallInfoOwned` | C4 |
| `thread_ptr` | the workers unpack the main thread's current unpack info (the A6 code) | `OuterXasl` | C5 |
| `no_restore` | `qmgr_process_query` leaves the nested unpack info on the thread (the A6 code) | `OuterXasl` | C5 |
| `sweep` | `pgbuf_unfix_all` sweeps inside a dispatch (the A6 code) | `OuterFixes` | C6 |

## Witnesses

| Cfg | Outcome reached |
|---|---|
| `witness-caught` | a callback query fails and the routine goes on |
| `witness-deep` | a dispatch above the depth limit is refused (DeepAt = 1) |
| `witness-drained` | the outermost exit frees deferred handles |
| `witness-retired` | a teardown retires a handler holding handles |
| `witness-clone-nested` | a worker clones while a nested query owns the thread's unpack info |
| `witness-commit-in` | a transaction ends inside a dispatch while the outer executor holds a fix |
| `witness-rights-over` | a change-rights notification above the limit is dispatched, not refused (DeepAt = 1) |

## Counterexamples (correct variant) and their classification

| Counterexample | Class | Resolution |
|---|---|---|
| IndInv7 violated after `TEnd1`/`TEnd2` then `TCall`: the session ended from inside its bracket, then a routine reads the freed pl session | model error | `cubpl::get_session` looks the pl session up through `session_get_pl_session` (`session.c:3395`), which finds no session after `session_state_uninit`: the call fails, no pointer is kept. `TCall` got the `sst # "live"` branch |
| mutant `err_keeps_hat` survived | missing property input, not a guard | only the refused depth gave an error status, and only at depth ≥ 2, where the client hat is right anyway; `method_dispatch_internal`'s error return (a builtin method's `ER_SM_INVALID_METHOD_ENV`, a pack failure) is now a `TDone` choice at every depth, and the mutant fails at depth 1 |
| Apalache: IndInv7 not inductive (six rounds) | IndInv too weak | each pre-state was unreachable (a handler `freed` before the teardown, `disp` at depth 0, a call at the maximum depth, a saved error at the outermost frame, a dispatch in an ended session, an error exit without its error); each became an IndInv7 conjunct, which the main cfg checks on every reachable state |
| trace `nested` refused at event 9 (a second `Call` after a level's `Exit` inside one nested query) | model error | a routine sends one callback per prepare, execute and fetch, each a dispatch of its own; `TNext` added |
| trace `deep` refused at event 91 (a dispatch at depth 16 not refused) | model error | the change-rights exemption ported from the old `dc6a0c3184`; `TCall` got the `rights` choice above the limit, and the trace spec reads `deep` from the frame's status |

## Findings

Kept from the old implementation (re-derived against this model and develop): the seam in `xs_callback_send` /
`xs_callback_receive`; `method_dispatch` under SERVER_MODE (hat, libcas depth, error-stack frame and floor,
outermost drain, pop or pop-and-keep, change-rights exemption, `er_errid ()` returned for an error status); the
per-session handler and runtime arguments with their retire in `csc_teardown`; `er_stack_depth` /
`er_stack_clear_above` and the floor-bounded clear-all of `transaction_cl.c`; the `cubpl::get_session` gate; the
recursion-depth asserts of `xqmgr_execute_query` / `xqmgr_prepare_and_execute_query` (`IS_IN_METHOD_OR_JSP_CALL` =
`csc_in_method_dispatch ()`); the qlist balance stand-down while callback resources are retained; the unpack-info
restore and the query-entry stream for parallel scan workers; `pgbuf_unfix_all` / `lock_suspend` inside a dispatch;
`owns_call_info`; `method_struct_value`'s bracket gate (A1 handover); `pl_call`'s result initialization; the object
normalization at the session-variable, method-result and `TYPE_SP` edges; the native method refusal (ADR 0049).

Changed: the session-variable normalization reuses `qmgr_server_db_values` (CBRD-27583's helper) instead of a copy;
`has_retained_resources` scans the handle slots (the old counter came with the B1 AUTO work); the handler retire
runs where `boot_finalize_client_sub` frees it (after `sm_final`, before the query results); `method_callback_final`
under SERVER_MODE retires the calling bracket's handler; the fold execute paths return the result clone's qlist
count (`qfile_update_qlist_count (-1)`), and both places that count a cursor's list on close (`pl_query_cursor.cpp`,
develop's newer `pl_executor.cpp` path) skip it on a bracket thread, where the list was created and counted.

Dropped: `88cf5d5e9` (the optimizer level is a session parameter since A5); `9c1ef7cd3` (develop's
`session_clear_pl_session_interrupt`, CBRD-27299, does it); `ab8e51e6a`'s `SUPPORT_XA` preset (a build option, not
fold logic); the tracer's scenario code and the unit tests (the smoke script and this model replace them).

Also kept (second commit `d5ccd9ad8`, from the old `093a5b3b25`, which the attribution gave A7 for this part):
the folded compile sets the signature's `is_deterministic` and `is_parallel_enabled` and applies the subquery-cache
exclusion of a routine that is not DETERMINISTIC, as the CS client does (develop set them under CS_MODE only). Smoke
case 47: `SUM` of a correlated subquery over such a routine is 3 on `c54a1b4ef` (one call per cache key), 6 after,
and 6 through a CS csql session on the same server. Compile-side only: no step of this model.

New: the SP code attribute map (`sp_code.cpp`) is a function-local static: four sessions calling their first routine
at once crashed on its lazy fill (smoke case 45, SIGSEGV in `_M_find_before_node <attr_idx_map>`). A develop defect
the fold made visible: [workspace #630](https://github.com/xmilex-git/workspace/issues/630).

The model found no hole in the ported code; its mutants that are the A6 code (`wire`, `gate_worker`,
`process_handler`, `ci_compile`, `thread_ptr`, `no_restore`, `sweep`) fail as the A6 build did at runtime:
smoke cases 38–46 on the A6 release build (`07b856c43`) cored in `xs_callback_send_args (thread_p=0x0)` (7 cases)
and linked the native method (-390 instead of -237).

## Per-session state table (census)

| State | Before A7 | After A7 |
|---|---|---|
| `cubmethod::handler` (`method_callback.cpp`) | `static CUB_THREAD_LOCAL` — one process object under SERVER_MODE, reached by every folded COMMIT (`db_commit_transaction`) | `client_session_context::method_callback_handler` |
| `runtime_args` (`query_method.cpp`) | not compiled in SERVER_MODE | `client_session_context::method_runtime_args` |
| er floor | — | `client_session_context::er_dispatch_floor` |
| `tm_libcas_depth` | csc (A4) | unchanged |
| `xs_method_eid` | `thread_local` (A4) | unused in SERVER_MODE (CS only) |
| `attr_idx_map` (`sp_code.cpp`) | lazily filled static | magic static |
| `ddl_log.c` statics | process | unchanged, never enabled in the server (fault table; B1 handover) |
| `dl_*`, `db_static_links` | written at server boot (A5) | unchanged, read only |

## Dead expressions

| Expression | Why |
|---|---|
| `MethodFold.tla:222`, `MethodFold.tla:223` (`TCall`'s `gate_worker` branch) | mutant-only branch |
| `MethodFold.tla:225`, `MethodFold.tla:226` (`TCall`'s `wire` branch) | mutant-only branch |

## Bounds

Main: N = 2 sessions, MaxWork = 2 (a statement and an end of session from inside the bracket), MaxDepth = 2,
DeepAt = 2, MaxOps = 2, one statement environment (a one-shot outer XASL with a parallel-scan worker, a fixed page,
a server error frame: the case every claim needs; the others only check less). Deep: DeepAt = 1 (the refused depth
and the change-rights exemption). Scale: MaxOps = 3. Apalache: IndInv7 inductive at N = 2, MaxDepth = 2,
DeepAt ∈ {1, 2}, MaxOps = 2 (the record fields' ranges need constant bounds). The real limit
(METHOD_MAX_RECURSION_DEPTH, depth 16) is covered by the `deep` trace, not by TLC. TLAPS: not used — the user
allowed it if needed; the state is finite and symmetric per session, the claims are per-thread stack discipline
plus A4's bracket exclusion (already checked there), and the risk lay in the code mapping, which the five traces
(one at depth 16) and the fail-before smoke cover.

## Trace validation

Instrumented scratch worktree of `c54a1b4ef` (the follow-up `d5ccd9ad8` changes only the compile of a routine's
signature and the subquery-cache key, no instrumented or mapped code) (`~/dev/cubrid-worktree/cas-fold-v2-tla7`, optdebug install
`~/optdebug/CUBRID-cas-fold-v2-tla7`, removed after recording; patch: workspace scratch `fold-v2/a7/instrument.py`,
`trace/instrumented.diff`). Events on tracer threads only: `Call` after the depth check in `method_dispatch`
(`deep=1` refused), `Exit` at its return (`drain=1` freed deferred handles), `Query1` / `Query2` at the start and end
of `qmgr_process_query` inside a dispatch (`csc_in_method_dispatch ()`), `Commit` where `pgbuf_unfix_all` returns
inside a dispatch. One mutex-ordered `seq`. Runner `fold-v2/a7/trace/run.sh`. The trace spec leaves the A4
lifecycle hidden, and narrows two hidden choices to what the runs did (sound for acceptance): a dispatch's end is
the NO_ERROR one (`TDoneOk`; no run printed an error status but the logged refusal), and a logged nested query runs
a cached XASL (`uxi' = "nil"`: a callback's query is a prepared statement).

| Run | Scenario | Events | cfg | Result |
|---|---|---|---|---|
| `traces/nested.log` | `SELECT a7h (3)`: a routine whose query calls another routine (two levels) | 24 | `witness-trace-nested` | accepted |
| `traces/commit.log` | `CALL a7c ()`: COMMIT in a cursor loop (three drains at the outermost exit) | 39 | `witness-trace-commit` | accepted |
| `traces/caught.log` | `SELECT a7g (2)`: the routine catches NO_DATA_FOUND | 12 | `witness-trace-caught` | accepted |
| `traces/deep.log` | `SELECT a7r (20)`: recursion to depth 16, refused there, change-rights notifications at 16 | 186 | `witness-trace-deep` | accepted |
| `traces/two.log` | two sessions run `SELECT a7f (2)` at once | 24 | `witness-trace-two` | accepted |
| `traces/nested-no-query2.log` | `nested` without event 19 (the level-1 query's end) | 23 | `reject-nested-no-query2` | refused |

Not reached by a run: `TErr` (left out of the hidden steps), a one-shot nested XASL, a parallel-scan worker's clone
during a nested query (smoke case 46 runs one, not traced).

## Result

- Date 2026-11-08. `tools/tla/tla-check docs/tla/CBRD-27430-A7` → `RESULT: OK`, run dir
  `.git_ignored_dir/scratch/tla/CBRD-27430-A7-20261108-164310-3099698`.
- `MethodFold.cfg`: pass, 26,181,853 states / 8,091,380 distinct, depth 84 (with `AllFreed`).
- `deep`: pass, 50,397,425 / 16,107,736, depth 84 (with `AllFreed`).
- `scale-ops3`: pass, 282,148,223 / 78,997,956, depth 92 (safety only, as A6's scale cfg).
- Mutants 15/15 rejected (`wire`, `gate_worker` → `InProcess`; `reactivate` → `NoNest`; `process_handler`,
  `handler_on_pl`, `drain_each_exit` → `OwnHandles`; `no_retire`, `no_drain` → `NoHandleLeak`; `no_isolation`,
  `clearall`, `err_keeps_hat` → `ErBalanced`; `ci_compile` → `CallInfoOwned`; `thread_ptr`, `no_restore` →
  `OuterXasl`; `sweep` → `OuterFixes`). Witnesses 7/7 reached.
- `apalache-indinv`: IndInv7 inductive (Apalache 0.62.4, N = 2, MaxDepth = 2, DeepAt ∈ {1, 2}, MaxOps = 2).
- TLAPS: not used (Bounds).
- Trace: 5 runs accepted (one of two sessions, one at depth 16), 1 corrupted run refused (build `c54a1b4ef` +
  instrumentation, optdebug).
- Spec sha256: `CscSessions.tla` 670dd2522b53bae6cced155073cf0b41cb69555ccf1948f8c49a9b9e974d1e7e,
  `MethodFold.tla` 890500a6af6e61148ed19a3c1d3aea22eac8ddda308773d323298c7449eb3667,
  `MethodFoldTrace.tla` 5cdc086a4514c4bb12405cc2476bcfaea72914b617dadc4908143d74b081582d,
  `MethodFoldTraceData.tla` 26dff3f935dc0b62d75bb8dc2ff484709a401ed75301c0e0ff3386a44ef39e03.
- Engine: `cas-fold-v2` `d5ccd9ad8`; smoke 48/48 on its optdebug and release builds.
