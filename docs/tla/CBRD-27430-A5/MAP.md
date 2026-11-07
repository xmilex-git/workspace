# CBRD-27430 A5 — the sysprm and boot lifecycle of the folded server's sessions

Map [CAS 폴드 재이식 지도](https://github.com/xmilex-git/workspace/issues/618), ticket
[A5 TLA+ 검증·이식](https://github.com/xmilex-git/workspace/issues/626). A4 gave every session its own client
context (csc); A5 makes the rest of the client half's process state safe for concurrent sessions: the modules every
session shares are initialized once by the server boot (so a session boot takes no lock), the client parameters a
session sets stay its own (and the plan-cache key prints them), a SET in a folded session follows the CS client's
scope rules, and the csc teardown frees the session's whole client state.

The model `CscParams` extends the A4 module `CscSessions` (linked from `docs/tla/CBRD-27430-A4`, constant
`ServerInit = TRUE`): A4's lifecycle steps drive A5's state through two hooks (registration seeds the session's
parameter array, a teardown frees its client state), and A5's work steps run in the session's bracket. The attacher
and A4's own work steps (statement, enter, RR lock, fetch, rollback, transfer, session call) stay in A4's cfgs
(`docs/tla/CBRD-27430-A4`, ServerInit FALSE and TRUE in its Apalache check); A5's cfgs keep checking A4's lifecycle
claims under the new boot.

Code: fork branch `cas-fold-v2`, A5 commit on `6d2aa5b02` (worktree `~/dev/cubrid-worktree/cas-fold-v2`). The old
implementation (`cas-merge` @ `cdb9da11e`: `d862ffde57`, `99bf777afa`, `7a1e38f574`, `4468544f7d`, `20769e6c19`,
`a5a5c9d69a`, `217d938b8c`, `2bdd1c4255`, `8581400956`, `67c6fe88c5`, `25055ec10c`, the A5 parts of `0ce32dc71f`,
`63c3134c9a` and `093a5b3b25`) was read and compared against this model and develop; Findings lists what was kept,
changed and dropped.

## Claim and sources

| # | Claim | Source |
|---|---|---|
| C1 | A client parameter one session sets is visible to that session's client half and to no other session; a client parameter of the conf reaches every session's client half; a cached plan runs only under the parameter values its key printed; a server-only parameter stays one process value. | #112 decisions #113 ④, #134, #159 (map #620 verdict, A5 claim C1 "세션 간 파라미터 격리 (CAS 등가)"); CS: each CAS process held its client's parameters, the server's XASL cache key carries `sysprm_print_parameters_for_qry_string` |
| C2 | The client-half modules every session shares (areas, SHOW metadata, static methods, the dynamic loader, login name, IP, root class header) are initialized once before the first session uses them and outlive every session; a session boot writes no process state. | #620 A5 claim C2 ("공유 client init은 첫 세션 진입 전에 끝난다"); A4 handover in #626's body (tracer boot mutex to be replaced by the engine's own boot) |
| C3 | The csc teardown frees the session's client state (savepoints, triggers, authorization, schema descriptors, query results, kept trees) before `ws_final` frees the MOPs it refers to, so nothing leaks per session and nothing is freed after its MOPs. | #620 A5 claim C3; A4 handover in #626's body (what `csc_teardown` does not free yet); develop's `boot_finalize_client_sub` (`boot_cl.c`, CBRD-26779) fixes the order for a connection's client state |
| C4 | Every free of the session's memory lands on the heap it came from. | #620 A5 claim C4; carried by A4's `NoForeignFree` (A4 C4) through the new teardown, which runs in the client hat |
| C5 | A SET SYSTEM PARAMETERS in a folded session follows the CS client's rules: a server parameter needs a DBA and is applied by the server's rules, a client-only one is applied (not refused). | CS client rules in `sysprm_generate_new_value` / `db_set_system_parameters`; old `a5a5c9d69a` / `217d938b8c` (workspace#176 결함 6, 11) |

## Refinement map (model -> code)

Line numbers below are at the A5 commit.

| Model | Code | One step because |
|---|---|---|
| `ServerInit` (Init: areas live, `showH = SharedHeap`) | `boot_sr.c:2696` `boot_restart_server` → `boot_initialize_client_modules` (`boot_cl.c:1193`): login name, IP (`boot_initialize_ip`), `ws_area_init`/`obt_area_init`/`classobj_area_init` (set and value areas stayed in `boot_restart_server`), static methods, `dl_initiate_module`, SHOW metadata in `boot_Shared_client_context`; before `session_states_init` and the accept loop | runs on the boot thread before any session thread exists |
| `TBootLock`, `TAreaCheck`, `TAreaMake` (pass-through) | `server_compile_tracer.cpp tracer_session`: `db_restart_ex` with no lock; `ws_init` skips the area inits under SERVER_MODE (`work_space.c:2412`), `boot_client_common` skips the shared modules, `boot_register_and_init_client` skips `tp_init`, intl defaults, `oid_set_root`, class OID cache, `es_init`, SHOW metadata (`BOOT_INIT_SHARED_MODULES`, `boot_cl.c:1265`), `boot_restart_client` skips the string compression flag and the loader (`boot_cl.c:1514`), `db_restart` skips static methods and SIGFPE (`db_admin.c:1137`), `sm_init` writes the root class header once (`schema_manager.c:2039`, a magic static) | no shared write left |
| `RegHook` (`sv'[s] = gv`) | `network_interface_cl.c:4811 csession_find_or_create_session` → `sysprm_alloc_session_parameters_from_defaults` (`system_parameter.c:11566`) copies the process values into the session's array | under the session's creation, before any other thread reaches the session |
| `gv` at Init (`BootVal`) | `prm_load_by_section` loads the client-only parameters too (`system_parameter.c:6893`) | server boot |
| `TSet(s, c)` | `db_set_system_parameters` (`db_admin.c`): `sysprm_validate_change_parameters` → `sysprm_generate_new_value` with the CS client's scope rules in a bracket in the client hat (`SYSPRM_IS_CLIENT_HALF`, `system_parameter.c:973`, `:9098`, value checks `:9152`); a DBA-only server parameter → `sysprm_change_server_parameters` (folded x-call, server hat: the server's rules, `sysprm_change_parameter_values` `:7885`) writes `prm_Def`; a session parameter → `sysprm_set_value_internal` writes the session's array; the client leg (`sysprm_change_parameter_values`, client hat: the client's rules) writes the client parameters; `prm_set_integer_value`/`_bool_`/`_float_` (`:11128`, `:11169`, `:11210`) write the session's copy (SET TRACE, the optimization level); SET OPTIMIZATION COST → `qo_plan_set_cost_fn` writes `csc_current ()->qo_cost_overrides` (`query_planner.c:9110`) | inside the session's bracket (A4 C1); the session's array is owned by its session; `prm_Def` writes are the server's own (DBA) |
| `TRead(s)`, getter path (one step reads every class through the three paths: each read is of the session's own copy or of a process value only a DBA's SET writes, so their order in the bracket changes nothing) | `prm_get_*_value` → `prm_get_value` → `sysprm_get_session_value (id, PRM_CLIENT_ONLY_SESSION (id))` (`system_parameter.c:11013`, `:11039`): the session's copy for a server-session parameter, and for a client-only session parameter in a bracket in the client hat; the cost function `qo_plan_cost_fn` (`query_planner.c:621`) | inside the bracket |
| `TRead(s)`, validator path | `sysprm_validate_escape_char_parameters` reads through the getters (`system_parameter.c:7636`) | |
| `TRead(s)`, plan dump path | `qo_plan_dump_cost_params` reads `prm_get_float_value`/`prm_get_integer_value` | |
| `TCompile(s)` | `parse_tree_cl.c:3131` appends `sysprm_print_parameters_for_qry_string` (session values for the client half, `system_parameter.c:12750`) to the hash text; `xqmgr_prepare_query` looks the XASL cache up by it | the cache is the server's, MT-safe |
| `TShow(s)` | `show_meta.c showstmt_get_metadata` reads `show_Metas` | |
| `TAlloc(s)` | a statement leaves client state: `tran_savepoint_internal` (`user_savepoint_list`), trigger caches, `au` caches, `sm_Descriptors`, an open `Qres_table` entry, a kept tree (`db_Kept_trees`) | inside the bracket |
| `TearHook` | `client_session_context.cpp:183` `csc_teardown`: `tran_free_savepoint_list`, `tr_final`, `au_final`, `sm_final`, `db_final_client_query_result`, `db_prepared_tree_free_all`, then `ws_final (false)` (`:192`) | inside the bracket of the retiring thread (A4) |
| `gv`, `sv`, `want`, `wantG` | `prm_Def[].value`, `session_state.session_parameters`, ghosts | |
| `cache`, `showH`, `res` | the XASL cache entries keyed by the printed parameters, the heap holding `show_Metas`' attributes, the session's client state | |
| `prmBad`, `planBad`, `authBad`, `parityBad`, `showUaf`, `leak`, `tearUaf`, `refusedNonDba`, `planHit`, `ownRead`, `resFreed`, `bootCC`, `cap` | ghosts (`bootCC`/`cap`: the old CAS restore's function statics) | — |

Callers of the protocol entry points: `boot_initialize_client_modules` — `boot_restart_server`;
`boot_finalize_client_modules` — `boot_server_all_finalize` (SHUTDOWN_ALL in SERVER_MODE, after
`session_states_finalize` retired every session); `sysprm_get_session_value` — `prm_get_value`, `prm_set_integer_value`,
`prm_set_bool_value`, `prm_set_float_value`, `sysprm_print_parameters_for_qry_string`; `csc_teardown` — A4's callers
(`csc_deactivate` on the orphan path, `csc_retire_and_delete`). Exit paths: a failed `boot_initialize_client_modules`
fails the server boot (`goto error`); a teardown of a context whose boot failed before `ws_init` takes the
`heap_id` branch, after `ws_init` the finals run on empty state (`tr_object_map`, descriptors, results and kept trees
NULL); the shared context's retire at shutdown has no MOP table (heap branch).

## Properties

| Name | Kind | Statement | Claim |
|---|---|---|---|
| `SessionParams` | invariant | every read by a session's client half returns what it set (or the conf value), never another session's; a server-only read returns the last DBA SET | C1 |
| `PlanKey` | invariant | a cache hit runs a plan compiled under the values its key printed | C1 |
| `NoShowUaf` | invariant | no SHOW reads metadata of a torn-down session heap | C2 |
| `AreaOnce` (A4) | invariant | the shared areas are created once and never freed under a session | C2 |
| `NoLeak`, `TearOrder` | invariants | a torn-down context leaves no client state, and none is freed after `ws_final` | C3 |
| `NoForeignFree` (A4) | invariant | every free hits the heap the chunk came from | C4 |
| `ScopeRules` | invariant | a non-DBA SET of a server parameter is refused, a client-only SET is applied | C5 |
| `TypeOK`, `Excl`, `NoUAF`, `NoWaitFreed`, `NoNest`, `TornOnce` (A4) | invariants | A4's lifecycle claims under the server boot | A4 C1–C3, C5 |
| `AllFreed` (A4) | liveness | every csc is eventually deleted | A4 C5 |
| `IndInv5` | invariant | A4's `IndInv` and `R5` (Apalache) | all |

## Fault model

| Fault | Modeled | Where / why not |
|---|---|---|
| error return of a call | partly | a refused SET (`TSet` refusal, non-DBA) changes no value; a boot failure is A4's `TBootFail`; `boot_initialize_client_modules` failing fails the server boot (no session) |
| interrupt | no | an error return of a call inside the bracket |
| lock timeout, deadlock victim | no | A4 (`TRollback`); parameters and teardown take no lock |
| OOM | no | `sysprm_alloc_session_parameters_from_defaults` failing fails the session creation (A4 boot failure); a failed `new client_session_context` at server boot fails the boot |
| crash / `kill -9` | no | parameters, caches and the client state are process memory |
| concurrent SET of a server parameter by two DBAs | no | one process value written by the server's own `sysprm_change_parameter_values`, the same as a CS server serving two clients |
| server shutdown | not as a step | `boot_server_all_finalize` runs `boot_finalize_client_modules` after `session_states_finalize` retired every context and no session thread is left |
| session expiry | yes (A4 `DScan`) | the teardown hook runs on the daemon's retire too |
| a session reading the process value of a client-only non-session parameter | as census | the client-only parameters without `PRM_CLIENT_COMPILE` have no reader in the folded client half (census below); a SET of one writes `prm_Def`, read by nobody in the server |

## Mutants

| Mutant | cfg | Re-enables | Expected | Claim |
|---|---|---|---|---|
| `lazy_init` | `mutant-lazy-init` | session boots initialize the shared areas with no lock (A4's code without the tracer's boot mutex) | `AreaOnce` | C2 |
| `show_in_session` | `mutant-show-in-session` | the first boot builds the SHOW metadata in its own workspace heap (A4 and develop under the fold) | `NoShowUaf` | C2 |
| `no_conf_load` | `mutant-no-conf-load` | the server skips the client-only parameters of the conf (develop's `prm_load_by_section`) | `SessionParams` | C1 |
| `no_readthrough` | `mutant-no-readthrough` | the client half reads a client-only session parameter from `prm_Def` (A4: the write lands in the session, the read misses it) | `SessionParams` | C1 |
| `cc_process` | `mutant-cc-process` | a client-compile parameter (ansi_quotes) stays a process value that a bracket SET writes (old `a5a5c9d69a` without `8581400956`) | `SessionParams` | C1 |
| `cas_restore` | `mutant-cas-restore` | `cc_process` plus the old CAS restore (`cdb9da11e:cas_execute.c:617-630`): the first session captures the process value, every later session start writes it back | `SessionParams` | C1 |
| `raw_validator` | `mutant-raw-validator` | the escape validator reads `prm_Def` (develop, old `2bdd1c4255` before) | `SessionParams` | C1 |
| `raw_plandump` | `mutant-raw-plandump` | the plan dump's tuned-cost check reads `prm_Def` (old `25055ec10c` before) | `SessionParams` | C1 |
| `shared_cost` | `mutant-shared-cost` | SET OPTIMIZATION COST writes the shared plan vtable (develop's `qo_plan_set_cost_fn`) | `SessionParams` | C1 |
| `hat_blind` | `mutant-hat-blind` | the client's rules in the folded server leg too (old `a5a5c9d69a` before `217d938b8c`): a DBA's SET of a server parameter is skipped | `SessionParams` | C1, C5 |
| `key_process` | `mutant-key-process` | the plan-cache key prints `prm_Def` (develop's printer under the fold) | `PlanKey` | C1 |
| `server_scope` | `mutant-server-scope` | the server's scope rules in a bracket (A4): a non-DBA SET of a server parameter is applied, a client-only one refused | `ScopeRules` | C5 |
| `a4_teardown` | `mutant-a4-teardown` | A4's `csc_teardown` (no savepoint, trigger, authorization, schema, result, kept-tree finals) | `NoLeak` | C3 |
| `ws_first` | `mutant-ws-first` | `ws_final` before the finals that walk the MOPs | `TearOrder` | C3 |
| `no_route` (A4) | `mutant-no-route` | the client half's private allocations on the thread's heap (A1–A3): the teardown's frees miss the session heap | `NoForeignFree` | C4 |

## Witnesses

| cfg | Outcome reached |
|---|---|
| `witness-dba-refused` | a non-DBA session's SET of a server parameter was refused |
| `witness-plan-hit` | a session ran a cached plan (same printed values) |
| `witness-own-read` | a session read back a value it set |
| `witness-res-freed` | a teardown freed a session's client state |

## Counterexamples (correct variant) and their classification

1. Apalache inductive check: a state with `ServerInit` and no areas (unreachable: the server boot created them
   before any session). `IndInv` strengthened in A4's `R_area` (`ServerInit => areaCnt = 1`), never the spec. No TLC
   counterexample in a correct-variant cfg.

## Findings

- **H1 (A4 code, fixed)**: the first session's boot built the SHOW metadata (`showstmt_metadata_init`) in its own
  workspace heap, and A4's teardown destroys that heap: a later session's SHOW reads freed memory.
  `mutant-show-in-session` fails `NoShowUaf`; smoke case 32 is the runtime check (fail-before on the pre-fix build).
  The old implementation built it in a never-retired boot context too (`99bf777afa`); A5 builds it at server boot.
- **H2 (A4 code, fixed)**: in a bracket the SET scope check used the server's rules (`sysprm_generate_new_value`
  SERVER_MODE block), so a non-DBA session's `SET SYSTEM PARAMETERS 'group_concat_max_len=...'` was applied without the
  DBA check CS has (rc never `PRM_ERR_NOT_FOR_CLIENT`), and a client-only non-session parameter (ansi_quotes) was
  refused. `mutant-server-scope`; smoke case 30.
- **H3 (A4 code, fixed)**: a client-only session parameter's SET landed in the session's array while the client half
  read `prm_Def` (lost write, `mutant-no-readthrough`, smoke case 26); the conf's client parameters never reached the
  server (`mutant-no-conf-load`, smoke case 25); SET OPTIMIZATION COST mutated the plan vtables every session shares
  (`mutant-shared-cost`).
- **H4 (A4 code, fixed)**: the XASL cache key (`sysprm_print_parameters_for_qry_string`, called by the client half
  at `parse_tree_cl.c:3131`) printed `prm_Def`, not the session's values, so two sessions with different session
  parameters (`timezone`) built the same key and the second ran the first one's plan with the first one's folded
  `DATETIMETZ` literal. `mutant-key-process` fails `PlanKey`; smoke case 29 is the runtime check (fail-before:
  `'+09:00'` in both sessions). The printer now prints the session's value under the client hat
  (`system_parameter.c:12750`).
- **Old implementation, changed in the port**: the read-through of client-only session parameters applies only to
  the client half (a bracket in the client hat), not to every thread with a session: the server half keeps the
  process value it always read (`query_executor.c` default-expression TO_CHAR language, `css_check_magic`'s TCP
  timeout, `pl_session.cpp`), so a CS client's server half behaves as on develop. The old CAS restore of ansi_quotes
  (`cas_execute.c:617-630`, the census defect handed to this stage) is not ported: ansi_quotes is a session parameter
  now (`mutant-cas-restore` records why the restore cannot work: it rewrites the process value under a running
  session). The plan-cache key's `cost=` component and the client-compile flag on more `PRM_FOR_QRY_STRING`
  parameters (`8581400956`) are not ported: two CS clients share the server's XASL cache the same way on develop. The
  NaN check for client float parameters (`67c6fe88c5`) is not ported: a CS client accepts NaN the same way.
  `keyword.c`'s table sort is a magic static on develop already; the debug-only verifier flags stay plain bools
  (a benign double verification). `parser_support.c`'s `ignore_trailing_space` static is a process constant on
  develop (`PRM_FORCE_SERVER`, not changeable).
- **Spec note (conf-only behavior change)**: the server now loads the client-only parameters of `cubrid.conf`, so a
  conf that sets `tcp_connection_timeout`, `intl_date_lang`, `intl_number_lang` or `intl_collation` also changes the
  server half's reads of them (`css_check_magic`, the default-expression TO_CHAR language, the PL session's
  parameters); on develop the server half read the built-in default. Without such a conf line nothing changes.

## Per-session state table (census)

The process state a session boot or a folded session's client half wrote before A5, and where it lives now.

| State | A5 | Why |
|---|---|---|
| `Objlist_area`, `Template_area` ×2, `Assignment_area` (and the server's `Set_*_Area`, `Value_area`) | server boot | created once before any session (C2); the A4 guards in the four `*_area_init` are gone |
| `lang_*`, `tz_*`, `msgcat_System`, `area_List`, `locator_Keep`, `tsc`, `tp_Domain_area`, `oid_Root_class_oid`, cached class OIDs, `es_*`, `pr_Enable_string_compression` | server boot | `boot_restart_server` initializes them for the server; a session boot no longer calls the inits (`area_init` set a warning each time, `dl_initiate_module` raced on `dl_Loader`) |
| `show_Metas` | server boot, `boot_Shared_client_context` | its attributes live in that context's heap until `boot_finalize_client_modules` (H1) |
| `Static_method_table` | server boot | `db_install_static_methods` once; `db_restart` pushed every session's copy onto the shared list without a lock |
| SIGFPE handler (`prev_sigfpe_handler`) | the server's | `db_restart` no longer replaces the server's handler, `db_shutdown` no longer restores it |
| `boot_Client_id_buffer`, `boot_Ip_address` | server boot | read once (`getuserid`, `gethostbyname_uhost`); every session's credential points at them |
| `sm_Root_class` header, `sm_Root_class_hfid` | first boot, once | the same database constants; a magic static serializes the one write |
| `boot_Set_client_at_exit`, `boot_Process_id` | CS/SA only | the folded server plants no client exit handler |
| `prm_Def` client parameters | per session | session arrays for server-session, client-only session and client-compile parameters (`PRM_CLIENT_COMPILE`: query dump, reset_tr_parser, insert mode, host variable late binding and peeking, oracle-style outer join, ansi_quotes, pipes_as_concat, mysql trigger names, require_like_escape_character, like term selectivity, XASL dump, unicode in/out normalization, merge join, object print format, histogram bucket count, plan cache bind sensitivity and variants, the five `cost_*`, row snapshot max rows, workspace memory report); server-only parameters one process value (DBA) |
| plan cost functions (`all_vtbls[i]->cost_fn`) | csc `qo_cost_overrides` | SET OPTIMIZATION COST per session; the vtables stay immutable under SERVER_MODE |
| `user_savepoint_list`, `tr_*` lists and object map, `au` caches, `sm_Descriptors`, `Current_Schema`, virtual query caches, `Qres_table` storage, `db_Kept_trees` | csc, freed by `csc_teardown` | C3 |
| `db_Preferred_hosts`, `db_Connect_order`, `db_Max_num_delayed_hosts_lookup`, host status list | unreachable until B1 | writers are `cas_execute.c` (`db_set_preferred_hosts`) and the CS connect path |
| `perfmon_Iscollecting_stats`, `perfmon_Stat_info` | unreachable until B1/B5 | `CUB_THREAD_LOCAL` is empty under SERVER_MODE; the callers (`histo_start`/`_stop`/`_print`) are csql session commands and CAS functions |
| `ddl_log.c` statics (`ddl_audit_handle`, `ddl_logging_enabled`, `is_first_initialized`) | unreachable until A7/B1/B5 | callers are CAS, csql, loaddb and `method_callback.cpp` |
| client-only non-session parameters without `PRM_CLIENT_COMPILE` (`dl_fork`, unloaddb/loaddb knobs, `auto_restart_server`, HA ones, `optimizer_reserve_*`) | process value | no reader in the folded client half (`dynamic_load.c` is the shared loader, the rest are utilities, the master or HA tools) |
| `db_Disable_modifications` (read-only client type) | B3 | the HA toggle stage |

## Dead expressions

| Line | Expression | Why TLC never evaluates it in the pass cfgs |
|---|---|---|
| CscParams.tla:104 | `RegHook` `cas_restore` restore branch | mutant-only (`cas_restore`); `mutant-cas-restore` fires it |
| CscParams.tla:105 | `RegHook` `cas_restore` capture branch | as line 104 |
| CscParams.tla:144 | `TSet` `server_scope` refusal of a client-only SET | mutant-only (`server_scope`); `mutant-server-scope` fires it |
| CscParams.tla:145 | as line 144 | as line 144 |
| CscParams.tla:146 | as line 144 | as line 144 |

## Bounds

Main: `N = 2` sessions (session 1 a DBA, session 2 not) + daemon, `MaxWork = 2`, `Attach = FALSE`; scale:
`MaxWork = 3`. IndInv: Apalache with `N = 2` fixed and every `MaxWork`. One parameter per class, two values (conf,
SET); the cache keyed by the one query-string parameter.

## Trace validation

Instrumented scratch worktree `~/dev/cubrid-worktree/cas-fold-v2-tla5` (detached at `47b9b6b21`, the A5 commit; patch
`.git_ignored_dir/scratch/fold-v2/a5/instrument.py`: A4's lifecycle events from `a4/instrument.py` without its boot
lock and area events, which A5 removed, plus `Set`), install `~/optdebug/CUBRID-cas-fold-v2-tla5`, runner
`a5/trace/run.sh`. `Set p= cls= ok=` is logged at the end of `db_set_system_parameters` for each assignment of a
watched parameter (`no_backslash_escapes` = ss, `create_table_reuseoid` = co, `oracle_style_outerjoin` = cc,
`group_concat_max_len` = sv), `ok=0` when the SET was refused. Not logged: the client half's reads, compiles, SHOWs and
the client state it leaves (`TRead`, `TCompile`, `TShow`, `TAlloc`) and `TDoneWork`, `TNotAdopted`, and the boot-lock and
area steps that have no code left under ServerInit — hidden in the trace spec. Trace cfgs use `MaxWork = 3`.

| Run | Scenario | Events | Result |
|---|---|---|---|
| `traces/two-set.log` | 2 sessions; S1 (DBA) sets group_concat_max_len and no_backslash_escapes, S2 (user `A5N`) sets group_concat_max_len and is refused; the server stops and the shutdown retires both contexts | 31 | accepted (`witness-trace-two-set`) |
| `traces/two-end.log` | 2 sessions each set oracle_style_outerjoin and create_table_reuseoid and end their session from inside the bracket (`CUBRID_M0_TRACER_END=1`): the teardown runs at the bracket exit | 24 | accepted (`witness-trace-two-end`) |
| `traces/two-set-nondba-applied.log` | `two-set` with S2's refusal logged as applied (`ok=1`) | 31 | refused (`reject-nondba-applied`) |

Actions no run reaches: `TBootFail`, `TRAct`, `TRTear` (no boot failure injected), `TLateOp`, `TReread` (A4 mutant-only),
the `cost` class (SET OPTIMIZATION COST is not logged; smoke cases cover it only through the model).

## Result

- 2026-11-08, `tools/tla/tla-check --workers 8 docs/tla/CBRD-27430-A5`: `RESULT: OK` (25 cfgs), run dir
  `.git_ignored_dir/scratch/tla/CBRD-27430-A5-20261107-235306-2107307`.
- spec sha256: `4fb99693df90becf69540a55a3a686d027933d096243e7f7af6b16c24abebf51  CscParams.tla`,
  `670dd2522b53bae6cced155073cf0b41cb69555ccf1948f8c49a9b9e974d1e7e  CscSessions.tla` (A4's, through the symlink),
  `a704139d13d252e3b0b6e5f6417759dee724680a3e0417ce00c7c781f18150e1  CscParamsTrace.tla`,
  `3d6d1bce3c3b9ede11565261854fb7e88116f543137323a224717378a93be0dd  CscParamsTraceData.tla` (cfgs in the run's
  `summary.txt`).
- Correct variant: `CscParams` 5,521,770 states / 2,102,103 distinct, depth 44; `.scale-work3` 60,734,410 /
  21,998,541, depth 46 (4139 s).
- Mutants: 15 cfgs, each rejected with the expected invariant violation. Witnesses: 4 reached. IndInv5: Apalache
  inductive check pass.
- Trace: 2 runs accepted, 1 corrupted run refused. Engine `47b9b6b21` + instrumentation
  (`.git_ignored_dir/scratch/fold-v2/a5/trace/instrumented.diff`), install `~/optdebug/CUBRID-cas-fold-v2-tla5`
  (removed after the run).
- Gate builds of `47b9b6b21`: `libcubrid.so.11.5` sha256 optdebug `aa09207d68615d94…`, release `734ffff325014dd5…`;
  smoke 33/33 on both.
- TLAPS: 요청 없음.
