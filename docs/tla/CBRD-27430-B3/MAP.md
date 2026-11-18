# CBRD-27430 B3 — a session is the client type of its broker, on a server of any HA state

Map [CAS 폴드 재이식 지도](https://github.com/xmilex-git/workspace/issues/618), ticket
[B3 TLA+ 검증·이식](https://github.com/xmilex-git/workspace/issues/634). A CAS connected to the server as the
client type of its broker's ACCESS_MODE and REPLICA_ONLY. Three things kept its writes off a server that must
not take them: the client library's own counter, the server's check of every request marked
CHECK_DB_MODIFICATION, and the reset of its database connection at a transaction boundary, after which its host
loop ran again. B3 gives a session in the server the same three, and the host loop's strict pass becomes the
admission check at session establishment.

Code: fork branch `cas-fold-v2`, B3 commit `bc25ddf0f` (worktree `~/dev/cubrid-worktree/cas-fold-v2`). Line numbers
below were moved to `f9e3e6637` (develop `ce985257b` merged: its KILL change dropped one argument of the
in-process kill stub; plus the SP code attribute load fix; no model step changed).

## Claim and sources

| # | Claim | Source |
|---|---|---|
| C1 | No write is applied in a transaction whose gate (`tdes->disable_modifications`) is set; a session never changes the server's gate, and the gate of a read_only server stays set; a commit or rollback the reset table refuses closes the driver connection at that boundary, and no transaction starts on it afterwards. | [#121](https://github.com/xmilex-git/workspace/issues/121) Resolution "생존 확인": per-statement 안전망(-581)·reset 테이블 무변경 상속; D3 "reset은 서버가 트랜잭션 경계에서 커넥션 종료"; ticket #634 C1; `network_sr.c:917` (the wire's check of CHECK_DB_MODIFICATION requests), `network_interface_sr.cpp:468` (`reset_on_commit`) |
| C2 | Session establishment refuses exactly the client type and HA state combinations the reset table closes at the first boundary, and a replica-only broker on a server that is no replica; every refusal for the HA state reaches the driver as an error it goes to its next altHost on. | #121 D2 (엄격 단일-pass = `xtran_should_connection_reset` 테이블의 사전 적용), D3 (거절은 드라이버 whitelist에 걸리는 형태); ticket #634 C2 |
| C3 | A session's entry points refuse its writes while it is inside a builtin method call and when its broker is read-only or slave-only, whatever other sessions do; nothing but its own counter refuses it there. A session resumed through a broker of another access mode is the new broker's client type. | #121 D8 (클라이언트-절반 전역 폐기); ticket #634 C3; A5 handover in the ticket body (`db_Disable_modifications` 세션 상태로); [ADR 0060](../../adr/) (세션 재개) |
| C4 | Every write of a session ends as it did for a CAS of the same broker on the CS server: refused at an entry point, refused by the server (rolled back, `reset_on_commit`), or applied. | CLAUDE.md "A statement that runs on develop keeps running"; develop run of the same statements through CAS processes (`fold-v2/b3/smoke/smoke_b3.sh`, `FOLD=0`) |

C4 replaces the letter of #121 D8 ("CHECK_MODIFICATION_* 매크로는 `tdes->disable_modifications`로 일원화"):
the old implementation seeded the transaction's gate to 1 for read-only client types, which refuses on the
server what a CAS of a read-only broker ran (`SELECT serial.NEXT_VALUE`, a savepoint). The comparison cfg
`mutant-d8-tdes` is that design; it violates `SameAsClient`. The session owns the counter instead, as the CAS
process did (decision put to the user, see `## Result`).

## Refinement map (model -> code)

| Model | Code | One step because |
|---|---|---|
| `Connect(s, t)` | `broker_direct.cpp:1414` puts `shm->access_mode`, `replica_only_flag` into the handoff body; `adoption.cpp:729` `synthesize_client_type`, `:730` `css_increment_num_conn` of that type; `driver_session.cpp:571` `conn->client_type` | the handoff is one message; the type is a value of the session from here |
| `Admit(s, d)` | `driver_session.cpp:693` `admission_check (type, css_ha_server_state (), replica, css_is_ha_repl_delayed ())` (`:230`) | one unlocked read of `ha_Server_state` and one of the delay flag, passed by value |
| `Register(s)` | `driver_session.cpp:771` `db_restart_ex` / `:763` `boot_resume_client`: `boot_cl.c:1568` raises the session's counter (read-only type or read_only), `boot_cl.c:1813` sets it for a resumed context; `boot_sr.c:3358` `css_check_ha_server_state_for_client (FROM_REGISTER)` refuses a normal client on to-be-standby; `logtb_clear_tdes` (`log_tran_table.c:1663-1667`) seeds the gate; `driver_session.cpp:781` turns the refusal into CAS_ER_FREE_SERVER | session-private but for one read of `ha_Server_state` and one of the server's gate; the model reads both in this step |
| `Begin(s)` | the first request of a transaction (`cas_dispatch.c`: `con_status = CON_STATUS_IN_TRAN`) | session-private |
| `MBegin(s)`, `MEnd(s)` | `query_method.cpp:483-485` `db_disable_modification ()` ... `db_enable_modification ()` (`db_admin.c:1459-1475`) on `csc_db ()->disable_modifications` (`db.h:111`) | session-private: the bracket thread is the only writer of its context |
| `Write(s, k)`, outcome `cl` | the `CHECK_MODIFICATION_*` macros of `db.h:171-185` read `db_Client_disable_modifications` | session-private |
| `Write(s, k)`, outcomes `sv` / `ok`, k in ddl, wire | `network_interface_cl.c:249` `modification_is_refused` after `enter_server ()` in the 26 stubs of the requests `network_sr.c` marks CHECK_DB_MODIFICATION (lines 1217 ... 11319) and in `locator_force`, `stats_update_statistics`, `tran_server_commit`; `exit_server` (`:217`) rolls back (`abort_tran_on_error`) and sets `conn->reset_on_commit` (`:230`) | the gate is the transaction's own field, written by its own thread at its boundaries |
| `Write(s, k)`, outcomes `sv` / `ok`, k in dml, srv | `CHECK_MODIFICATION_NO_RETURN` (`log_impl.h:214`) in `query_executor.c:21992-22191` and `serial.c:470`, `:999`; the error returns through `exit_server` | same |
| `End1(s)` | `network_interface_cl.c:3060` `tran_server_commit` / `:3160` `tran_server_abort`: `logtb_has_updated` (`:3124`, `:3201`), `xtran_server_commit` / `xtran_server_abort` (the transaction ends, `logtb_clear_tdes` seeds the gate from the server's) | one unlocked read of the server's gate |
| `End2(s, d)` | `xtran_should_connection_reset` (`transaction_sr.c:729`, called at `network_interface_cl.c:3140`, `:3207`): reads `ha_Server_state`, the delay flag, `conn->reset_on_commit`; `db_Connect_status = RESET`; `cas_execute.c:1085` `reset_flag`, `cas_function.c:187` FN_KEEP_SESS ends the request loop | one unlocked read of `ha_Server_state`; the rest is the session's |
| `Leave(s, y)` | `driver_session.cpp:882-921`: rollback and end of the session unless yielded, `boot_unregister_client` -> `boot_sr.c` `css_check_ha_server_state_for_client (FROM_UNREGISTER)`: on to-be-standby with one normal client left, `css_transit_ha_server_state (STANDBY)` (`server_support.c:1689`); the counter goes with the client context unless the context is kept | the transit runs under CSECT_HA_SERVER_STATE (`server_support.c:1611`); the count is `logtb_count_clients` under the transaction table's csect |
| `GateDis` after `Leave` | `server_support.c:1694` `logtb_disable_update` after the transit, outside the csect | its own step: the model's `pendDis` |
| `Demote1`, `Demote2` | `css_change_ha_server_state (STANDBY)` (`server_support.c:1767`): first transit (active or maintenance -> to-be-standby), then, still under the csect, `logtb_count_clients () == 0` -> standby | `hbMid`: the csect is held from the first transit to the function's end |
| `Promote1`, `Promote2` | `css_change_ha_server_state (ACTIVE)`: standby -> to-be-active, then active when the log appliers are done (`css_check_ha_log_applier_done`), or later from `css_notify_ha_log_applier_state` (`server_support.c:1986`) | each transit under the csect |
| `Maint` | `css_change_ha_server_state (MAINTENANCE)`: standby -> maintenance | under the csect |
| `GateDis`, `GateEn` | `logtb_disable_update` (`log_tran_table.c:3450`) at `server_support.c:1873`, `:2003`; `logtb_enable_update` (`:3436`, a no-op on a read_only server) at `:1836`, `:1887`, `:1991` | one store to the server's `db_Disable_modifications` |
| `ha`, `gG` | `ha_Server_state` (`server_support.c:123`); the server's `db_Disable_modifications` | |
| `ty`, `cnt`, `inM` | `conn->client_type` and `tdes->client.client_type`; `csc_db ()->disable_modifications`; inside `obj_send_array` of `method_invoke_builtin_internal` | |
| `base`, `upd`, `hu`, `roc`, `rst` | `tdes->disable_modifications`; `logtb_has_updated`; the `has_updated` local; `conn->reset_on_commit`; `csc_db ()->connect_status == RESET` | |
| `kept` | the session's client context kept after a yield (`session_claim_kept_context`, B1b) | |
| `bref`, `rocRef`, `badW`, `leak`, `spur`, `div`, `missed`, `sessG`, `admBad`, `ref`, `w*` | ghosts: what the CS server would hold for a CAS, the violations, the last refusal's kind, the witnesses | — |

Callers of the entry points (code-index `callers`): `tran_server_commit` <- `tran_commit`; `tran_server_abort` <-
`tran_abort` (every boundary of a session; the server-side auto-commit of `stran_server_auto_commit_or_abort` is
a wire handler a session never runs). `xtran_should_connection_reset` <- the two above and the three wire
handlers (CS clients). `db_disable_modification` <- `boot_restart_client`, `method_invoke_builtin_internal`
(`boot_restart_client_sub` is CS only). `logtb_disable_update` <- `boot_restart_server` (read_only),
`css_change_ha_server_state`, `css_check_ha_server_state_for_client`, `css_notify_ha_log_applier_state`.
`css_transit_ha_server_state` <- the same three. `admission_check`, `synthesize_client_type` <- the session
thread and the adoption channel only.

## Properties

| Property | Claim | Kind |
|---|---|---|
| `NoGatedWrite` | C1 | safety: no write applied with the transaction's gate set |
| `ServerGateOwned` | C1 | safety: no session writes the server's gate |
| `ReadOnlyHolds` | C1 | safety: the gate of a read_only server is set in every state |
| `ResetHonoured` | C1 | safety: a boundary the reset table refuses (with the `reset_on_commit` the CS server would hold) sets RESET |
| `NoTranAfterReset` | C1 | safety: no transaction on a connection in RESET |
| `AdmitMatchesTable` | C2 | safety: every admission decision equals `RefTable` (replica mismatch or the reset table with has_updated, without `reset_on_commit`) |
| `RefusalRetryable` | C2 | safety: no HA refusal is a DBMS error |
| `NoWriteInRegion` | C3 | safety: no entry-point write applied inside a method call or for a read-only type |
| `NoForeignRefusal` | C3 | safety: no entry-point refusal without the session's own reason |
| `SameAsClient` | C4 | equivalence: the outcome of every write equals the CS client's and server's |
| `IndInv` | all | the above with `TypeOK`, `InvOff`, `InvKept`, `InvCnt`, `InvRegion`, `InvBase`, `InvRoc`, `InvRst`, `InvWos`, `InvG`, `InvMid`, `InvHu`; inductive by Apalache |

No liveness claim: the drain of a to-be-standby server has no bound on develop either (#121 "demotion의 무한
드레인") and B3 changes nothing in it.

## Fault table

| Fault | Modeled |
|---|---|
| error return | the refusals are the modeled outcomes of `Write`, `Admit`, `Register`. A failed commit (`xtran_server_commit` returns another state) still runs the reset table, as `stran_server_commit_internal` does. Login failures of `Register` other than the HA refusal (password, unknown user) end the connection before any modeled state exists (B1b's `Auth`). |
| interrupt / query cancel | not applicable: no loop of the change checks an interrupt. A killed session (B2 `StatsKill`) leaves through `Leave`. |
| lock timeout, deadlock victim | a unilateral abort rolls back like the `sv` outcome without `reset_on_commit` (`need_to_abort_tran`: the same branch for ER_LK_UNILATERALLY_ABORTED); the gate is seeded again from the server's, which `Write`'s `sv` branch and `End1` both do. Not a separate action. |
| conditional latch failure, checkpoint, page flush, vacuum, concurrent DML, HA log apply, nested statement | not applicable: the change reads no page, snapshot or replicated state. |
| OOM | `ws_abort_transaction` reads the session's counter (`work_space.c:299`): a read-only session's AREA failure stays an OOM error (A8). No allocation is added. |
| crash / `kill -9` | not applicable: the gates and the HA state are volatile; a restarted server boots idle -> active (or by its heartbeat) and every session is gone. |
| spurious wakeup | not applicable: no condition wait. |
| HA state change at any point | modeled: `Demote1`, `Demote2`, `Promote1`, `Promote2`, `Maint`, `GateDis`, `GateEn` interleave with every session step; `Admit`, `Register`, `End1`, `End2` each read the shared state once. |
| the unregistering session's late `logtb_disable_update` | modeled (`pendDis`): a promotion between the transit and the store leaves an active server's gate set. Develop has the same window (`server_support.c:1689-1694`, outside the csect); no property of B3 reads it, and the model keeps no invariant tying `gG` to `ha`. |
| replication delay | modeled as the input `d` of `Admit` and `End2` on a standby. No run reaches it (it needs a log applier): see Trace validation. |
| quota seat | not modeled: `css_increment_num_conn` and `css_decrement_num_conn` take the same type on every path (`adoption.cpp:730`, `:801`, `:834`; `driver_session.cpp` exits before a conn entry; `css_free_conn` by `conn->client_type`), read in the code. |
| LOB storage requests | not modeled and not ported: the six `es_posix_*` requests are marked CHECK_DB_MODIFICATION on the wire, and the client half of a session calls `xes_posix_*` directly (`es.c`). Ticketed on the map. |

Environment assumptions: none needed (no liveness). The HA state changer and the drivers get no fairness.

## Mutants

| cfg | Variant | Rejected by | Claim |
|---|---|---|---|
| `mutant-shared-global` | `cas-fold-v2` before B3: the client half and the server share one `db_Disable_modifications` (a read-only boot and a method call raise it; the session's end lowers nothing) | `ServerGateOwned` | C1 |
| `mutant-shared-global-foreign` | same | `NoForeignRefusal` (another session's method call, or a read-only session that ever connected, refuses me) | C3 |
| `mutant-enable-ignores-ro` | `logtb_enable_update` without its read_only test, on a read_only HA server that is promoted | `ReadOnlyHolds` | C1 |
| `mutant-no-boundary-gate` | the client half enters the server half without the wire's check | `NoGatedWrite` | C1 |
| `mutant-no-reset` | commit and rollback do not ask the reset table (`cas-fold-v2` before B3) | `ResetHonoured` | C1 |
| `mutant-no-roc` | `exit_server` does not set `reset_on_commit` | `ResetHonoured` | C1, C4 |
| `mutant-reset-no-close` | RESET does not end the request loop | `NoTranAfterReset` | C1 |
| `mutant-lenient-admit` | a read-write broker admitted on a standby (the lenient second pass #121 D2 rejected) | `AdmitMatchesTable` | C2 |
| `mutant-no-maint-row` | no maintenance row (the old implementation before its review fix F3) | `AdmitMatchesTable` | C2 |
| `mutant-no-tbs-row` | no to-be-standby row | `AdmitMatchesTable` | C2 |
| `mutant-reg-dbms` | the registration's to-be-standby refusal reaches the driver as a DBMS error (the old implementation) | `RefusalRetryable` | C2 |
| `mutant-resume-keeps`, `-foreign` | a resumed context keeps the counter of the broker it was made through | `NoWriteInRegion`, `NoForeignRefusal` | C3 |
| `mutant-d8-tdes` | #121 D8 as implemented before: the entry points read the transaction's gate plus the method depth, and the gate is seeded 1 for read-only types | `SameAsClient` | C4 |

## Witnesses

`witness-applied` (a write is applied), `witness-exempt-write` (a replica-only read-write broker writes on a
replica whose gate is set), `witness-roc-reset` (a reset caused by a server refusal), `witness-resumed`,
`witness-reset`, `witness-refused` (admission or registration refuses), `witness-drained` (a demotion reaches
standby with the gate set), `witness-standby-with-session` (a transaction is open on a standby whose gate is
set: the inherited window of a transaction that began before).

## Dead expressions

| Expression | Why |
|---|---|
| `HaGate.tla:259` (`THEN /\ gG' = (IF gG + Raise(ty[s]) > 2 * NS + 1 THEN gG ELSE gG + Rai`) | mutant-only branch (`shared_global`): the session writes the server's gate |
| `HaGate.tla:260` (`/\ sessG' = (sessG \/ Raise(ty[s]) > 0)`) | mutant-only branch (`shared_global`): the session writes the server's gate |
| `HaGate.tla:261` (`/\ UNCHANGED cnt`) | mutant-only branch (`shared_global`): the session writes the server's gate |
| `HaGate.tla:279` (`THEN gG' = (IF gG > 2 * NS THEN gG ELSE gG + 1) /\ sessG' = TRUE /\ UN`) | mutant-only branch (`shared_global`): the session writes the server's gate |
| `HaGate.tla:288` (`THEN gG' = (IF gG > 0 THEN gG - 1 ELSE 0) /\ sessG' = TRUE /\ UNCHANGE`) | mutant-only branch (`shared_global`): the session writes the server's gate |
| `HaGate.tla:364` (`THEN UNCHANGED cnt             \* nothing lowers what the boot raised:`) | mutant-only branch (`shared_global`): the session writes the server's gate |
| `HaGate.tla:179` (`/\ ha' = "tbs" /\ hbMid' = TRUE`) | the HA state changer's steps, dead only in `nonha-readonly` (a server without HA takes no state change; `uncovered-ok` in the cfg) and, for 192-198 (`Promote1`, `Promote2`), in `replica` (a replica is never promoted) |
| `HaGate.tla:180` (`/\ UNCHANGED <<gG, pendDis, pendEn>> /\ UNCHANGED HaVars`) | the HA state changer's steps, dead only in `nonha-readonly` (a server without HA takes no state change; `uncovered-ok` in the cfg) and, for 192-198 (`Promote1`, `Promote2`), in `replica` (a replica is never promoted) |
| `HaGate.tla:185` (`/\ hbMid' = FALSE`) | the HA state changer's steps, dead only in `nonha-readonly` (a server without HA takes no state change; `uncovered-ok` in the cfg) and, for 192-198 (`Promote1`, `Promote2`), in `replica` (a replica is never promoted) |
| `HaGate.tla:186` (`/\ IF Clients = {} THEN ha' = "standby" /\ pendDis' = TRUE ELSE UNCHAN`) | the HA state changer's steps, dead only in `nonha-readonly` (a server without HA takes no state change; `uncovered-ok` in the cfg) and, for 192-198 (`Promote1`, `Promote2`), in `replica` (a replica is never promoted) |
| `HaGate.tla:187` (`/\ UNCHANGED <<gG, pendEn>> /\ UNCHANGED HaVars`) | the HA state changer's steps, dead only in `nonha-readonly` (a server without HA takes no state change; `uncovered-ok` in the cfg) and, for 192-198 (`Promote1`, `Promote2`), in `replica` (a replica is never promoted) |
| `HaGate.tla:192` (`/\ ha' = "tba"`) | the HA state changer's steps, dead only in `nonha-readonly` (a server without HA takes no state change; `uncovered-ok` in the cfg) and, for 192-198 (`Promote1`, `Promote2`), in `replica` (a replica is never promoted) |
| `HaGate.tla:193` (`/\ UNCHANGED <<gG, pendDis, pendEn, hbMid>> /\ UNCHANGED HaVars`) | the HA state changer's steps, dead only in `nonha-readonly` (a server without HA takes no state change; `uncovered-ok` in the cfg) and, for 192-198 (`Promote1`, `Promote2`), in `replica` (a replica is never promoted) |
| `HaGate.tla:197` (`/\ ha' = "active" /\ pendEn' = TRUE`) | the HA state changer's steps, dead only in `nonha-readonly` (a server without HA takes no state change; `uncovered-ok` in the cfg) and, for 192-198 (`Promote1`, `Promote2`), in `replica` (a replica is never promoted) |
| `HaGate.tla:198` (`/\ UNCHANGED <<gG, pendDis, hbMid>> /\ UNCHANGED HaVars`) | the HA state changer's steps, dead only in `nonha-readonly` (a server without HA takes no state change; `uncovered-ok` in the cfg) and, for 192-198 (`Promote1`, `Promote2`), in `replica` (a replica is never promoted) |
| `HaGate.tla:203` (`/\ ha' = "maint" /\ pendEn' = TRUE`) | the HA state changer's steps, dead only in `nonha-readonly` (a server without HA takes no state change; `uncovered-ok` in the cfg) and, for 192-198 (`Promote1`, `Promote2`), in `replica` (a replica is never promoted) |
| `HaGate.tla:204` (`/\ UNCHANGED <<gG, pendDis, hbMid>> /\ UNCHANGED HaVars`) | the HA state changer's steps, dead only in `nonha-readonly` (a server without HA takes no state change; `uncovered-ok` in the cfg) and, for 192-198 (`Promote1`, `Promote2`), in `replica` (a replica is never promoted) |
| `HaGate.tla:206` (`GateDis == /\ pendDis /\ gG' = 1 /\ pendDis' = FALSE`) | the HA state changer's steps, dead only in `nonha-readonly` (a server without HA takes no state change; `uncovered-ok` in the cfg) and, for 192-198 (`Promote1`, `Promote2`), in `replica` (a replica is never promoted) |
| `HaGate.tla:207` (`/\ UNCHANGED <<ha, pendEn, hbMid>> /\ UNCHANGED HaVars`) | the HA state changer's steps, dead only in `nonha-readonly` (a server without HA takes no state change; `uncovered-ok` in the cfg) and, for 192-198 (`Promote1`, `Promote2`), in `replica` (a replica is never promoted) |
| `HaGate.tla:209` (`GateEn == /\ pendEn /\ gG' = (IF ROMode /\ Mutant # "enable_ignores_ro`) | the HA state changer's steps, dead only in `nonha-readonly` (a server without HA takes no state change; `uncovered-ok` in the cfg) and, for 192-198 (`Promote1`, `Promote2`), in `replica` (a replica is never promoted) |
| `HaGate.tla:210` (`/\ UNCHANGED <<ha, pendDis, hbMid>> /\ UNCHANGED HaVars`) | the HA state changer's steps, dead only in `nonha-readonly` (a server without HA takes no state change; `uncovered-ok` in the cfg) and, for 192-198 (`Promote1`, `Promote2`), in `replica` (a replica is never promoted) |
| `HaGate.tla:247` (`THEN /\ ph' = [ph EXCEPT ![s] = "off"]`) | the registration refused on to-be-standby, dead only in `nonha-readonly` (the state stays active) |
| `HaGate.tla:248` (`/\ ref' = [ref EXCEPT ![s] = IF Mutant = "reg_dbms" THEN "dbms" ELSE "`) | the registration refused on to-be-standby, dead only in `nonha-readonly` (the state stays active) |
| `HaGate.tla:249` (`/\ UNCHANGED <<cnt, base, bref, kept, gG, sessG, wResumed, roc, rocRef`) | the registration refused on to-be-standby, dead only in `nonha-readonly` (the state stays active) |
| `HaGate.tla:361` (`THEN ha' = "standby" /\ pendDis' = TRUE`) | the unregistering session's transit to standby, dead only in `nonha-readonly` |

## Bounds

Main: `NS = 2`, all four client types (RW, RO, SO, replica-only RW), all four write kinds, an HA server that
starts active. `replica`: a replica server (standby, gate set). `nonha-readonly`: a server without HA
(active, no state change) with read_only. `scale-3`: three sessions with two types (RW, RO) and two write kinds
(dml, wire) — the full alphabet at `NS = 3` did not finish (7.7M distinct states at depth 19 of a search whose
`NS = 2` depth is 36). The read-only and slave-only replica-only types are not modeled: they take the RO and SO
rows plus the replica check of RWR. The Apalache check covers every value of `IsReplica`, `ROMode`, `HaInit`,
`GInit`, `HaMoves` at `NS = 2`.

## Trace validation

Instrumented build of `bc25ddf0f` (`fold-v2/b3/instrument.py`, diff `fold-v2/b3/trace/instrumented.diff`, adds
lines only), install `~/optdebug/CUBRID-cas-fold-v2-tla3`, runs by `fold-v2/b3/trace/run.sh <name> <scenario>`
(`B3Trace.java`), converted by `fold-v2/b3/events.py`, cfgs by `fold-v2/b3/trace/mk.py`.

Stimulus, not the code under test: with `CUBRID_TLA_B3_HB` set, `cubrid changemode` skips its ha_mode check and
the server runs the requested change with `heartbeat = true`, so a server without a heartbeat process takes the
transitions of `css_change_ha_server_state`; `CUBRID_TLA_B3_ADMIT_DELAY_MS` sleeps after the admission check.

Renaming and synthesis in `events.py`: a session thread takes the lowest free slot, or the slot of the session
id it resumes; `AdmitIn` (the values `admission_check` received) and `Admit` (its answer) are one `Admit`;
events between a passed admission and `Register` (the boot's own raise, checks and commit) are inside
`Register`; `Begin` is written before the first step of a transaction; the check of a committing transaction
that wrote (between `End0` and `End1`) is inside `End1`; the rollback of a connection that is closing after a
reset is inside `Leave`; a `LeaveTransit` puts the `Leave` there, ahead of the session's `GateDis`; the HA
steps and gate stores of the boot (idle -> active, read_only) are the model's `Init`. There is no hidden step.

| Run | Covers |
|---|---|
| `gates` | `Connect`, `Admit` (admitted; a slave-only broker refused on an active server), `Register`, `Begin`, `Write` at all four sites (`cl`, `ok`), `MBegin`, `MEnd`, `End1`, `End2`, `Leave` |
| `readonly` | read_only server: `Write` refused at the entry point, at the fold boundary and in the serial code (`sv`), also after another session logged out |
| `demote` | `Demote1`, `Demote2` (clients left), admission refused on to-be-standby and standby, the reset of a commit that wrote on to-be-standby, `Leave` with the transit, `GateDis`, a server refusal on a standby and the `reset_on_commit` reset, `Promote1`, `Promote2`, `GateEn`, the reset of a slave-only session on an active server |
| `maint` | `Demote2` to standby with no client, `Maint`, admission refused in maintenance, maintenance -> standby |
| `regrace` | a registration refused after the admission passed (to-be-standby in the window): `Register` with `retry = 1`; the driver got -10017 |
| `resume` | a session made through a read-only AUTO broker yields and is resumed through a read-write AUTO broker: `Register` with `resumed = 1`, `cnt = 0`, and its INSERT runs |

Rejected runs: `ro-write-applied` (a read-only session's entry-point refusal logged as applied),
`gated-write-applied` (a savepoint on a read_only server logged as applied), `reset-missed` (the to-be-standby
reset logged as no reset), `standby-admitted` (a read-write broker logged as admitted on a standby),
`gate-not-set` (`logtb_disable_update` dropped).

Not reached by a run: the replication delay input (`d = 1`; needs a log applier), the replica-only type on a
replica server and the promotion completed by `css_notify_ha_log_applier_state` (need a replica / an applier),
a write refused inside a method call (the builtin methods call no entry point that checks). They are left to
the final gate's `ha_shell` and `ha_repl` suites (map Notes).

## Result

2026-11-18, `tools/tla/tla-check docs/tla/CBRD-27430-B3`: **`RESULT: OK`**, 38 cfgs PASS, run dir
`.git_ignored_dir/scratch/tla/CBRD-27430-B3-20261118-102846-266408` (copy of the verdicts: tooling scratch
`fold-v2/b3/tla-check-record.out`). The Result section was written after the run; the spec and cfg files are the
run's.

| cfg | Verdict | States (generated / distinct) | Depth |
|---|---|---|---|
| `HaGate` (the claims' invariants + `IndInv`) | pass | 14,586,127 / 1,943,155 | 36 |
| `HaGate.replica` | pass | 5,373,528 / 719,586 | 31 |
| `HaGate.nonha-readonly` | pass | 21,581 / 4,225 | 21 |
| `HaGate.scale-3` (3 sessions, `TypesC` {RW, RO}, `KindsC` {dml, wire}) | pass | 690,877,570 / 93,878,699 | 46 |
| 14 mutant cfgs | each the expected violation | 48 … 105,497 generated | 4 … 13 |
| 8 witness cfgs | each reached | 87 … 49,565 generated | 5 … 11 |
| `HaGate.apalache-indinv` | pass: `IndInv /\ Next => IndInv'` | Apalache, 7 s | — |
| 6 `witness-trace-*` cfgs | accepted (the whole run consumed) | 27 … 96 states | = events + 1 |
| 5 `reject-*` cfgs | refused | 18 … 75 states | — |

TLAPS: not requested. Engine: `cas-fold-v2` `f9e3e6637`; the traces were recorded on an optdebug build of
`bc25ddf0f` plus the instrumentation (tooling scratch `fold-v2/b3/instrument.py`, `trace/instrumented.diff`), with
`cubrid changemode` standing for the heartbeat (`CUBRID_TLA_B3_HB`). Not reached at runtime, left to the final
gate's ha_shell: the replication delay input, a replica-only type on a replica, a promotion the appliers end, a
write refused inside a method call.

Decision put to the user (2026-11-18): the session owns the counter (`csc_db ()->disable_modifications`) instead
of #121 D8's transaction gate; the user chose the session-owned counter (ADR 0063).

Gate on `f9e3e6637`: optdebug libcubrid `272108b7caf8…`, release `ad7557d6d3b5…`: wire 51/51, B1a 5/5, B1b 5/5,
B2 13/13, login 4/4, B3 5/5 on both; memory check (optdebug, `use_system_malloc=yes`, `MALLOC_CHECK_=3
MALLOC_PERTURB_=165`): B3 5/5, login 4/4, wire 51/51, B2 13/13, no new core. The same statements through the CAS
of a develop install and through fold sessions: 0 differing lines.
