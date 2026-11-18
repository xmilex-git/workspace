# CBRD-27430 B1b — KEEP_CONNECTION=AUTO in the folded server: a session yields its slot and is resumed

Map [CAS 폴드 재이식 지도](https://github.com/xmilex-git/workspace/issues/618), ticket
[B1b TLA+ 검증·이식](https://github.com/xmilex-git/workspace/issues/632). An AUTO broker's session that waits for
a request at a boundary where nothing of the connection would be lost may be told to leave its client: the session
thread closes the driver connection, keeps the server session with its client context, and gives the handoff slot
back (a **yield**; the CAS's CHANGE CLIENT). The client's next connection presents the driver session it was given
and goes on with the kept session (a **resume**).

Code: fork branch `cas-fold-v2`, B1b commit on `7327db817` (worktree `~/dev/cubrid-worktree/cas-fold-v2`); the
line numbers below are at that commit. Old implementation: `cas-merge` @ `cdb9da11e`, the attribution table's late
B1 commits `8eff88291c` (detach/resume by a nonce), `dedb016f13` (executor reuse), `a6e936fe26` (arbitration, slots
borrowed across databases), `ae4a8e6081` (a consumed demand handed back), `c5cda0993a` (broker reset); diffs in the
tooling scratch `fold-v2/b1b/*.diff`.

What this stage took from the old implementation and what it did not:

- **Resume rides develop's session secret, not a new nonce.** develop's CBRD-27434 (`7d9720559`, not in the old
  branch) put an 8-byte session secret in the last 8 bytes of the 20-byte driver session — the bytes the old code
  used for its nonce — and made a kept session's timeout run from the moment its client left, with a second check
  under the state mutex before the daemon erases it. The old `auto_nonce`, `auto_detached`, `auto_expires` and
  `auto_user` fields are not ported: a yield is develop's keep-session end (`session_state_destroy (keep)`), marked
  `csc_kept`; a resume is one claim under the state mutex.
- **One protocol for one and for many databases.** The old dispatcher set a `yield_requested` flag when one database
  held the slots and switched to YIELD_TRY + IDLE_WATCH when several did. Only YIELD_TRY + IDLE_WATCH is ported:
  the flag, its exchange races and the hand-back of `ae4a8e6081` are gone, and TLC shows the claims hold without
  them (`AutoSession.live.cfg`, the mutants `no-watch-scan` and `no-idle-hint`).
- **No executor reuse** (user decision 2026-11-17): a session thread per handed-over connection, as in B1a.

## Claim and sources

The feature has no design ticket in [CAS 통합 지도](https://github.com/xmilex-git/workspace/issues/112); the claims
were put to the user and confirmed on 2026-11-17 (ticket #632, Q1–Q7).

| # | Claim | Source |
|---|---|---|
| C1 | A kept session is taken up by at most one connection, and only with the session's server key and secret, by the session's user, after the password login. A connection that loses, or whose login fails, does not change the session and gets an error, not a new session. | user Q1; develop CBRD-27434 (session secret, `ER_SES_SESSION_SECRET_MISMATCH`); old `8eff88291c` `session_auto_claim` |
| C2 | A session is torn down exactly once, and never while a connection is attached to it. A resume that arrives after the session was removed starts a new session without an error. The timeout is counted from the yield. | user Q2; develop `session_remove_expired_sessions` (second check under the lock); A4 claim "one teardown per context" |
| C3 | A dispatcher's demand yields one session at most (safety). A dispatcher waiting for a slot does not stay behind a session of its broker that waits idle (liveness, under weak fairness of the session threads, the control channel threads and the dispatcher). A yield that arrives after its dispatcher left is allowed. | user Q5; old `a6e936fe26`, `ae4a8e6081` |
| C4 | A session thread starts with no thread-local state of another session. | user Q6 (no executor reuse); B1a's reliance on empty `CAS_TLS` (`need_database_reconnect ()`, `cas_server_session_slot_begin`) |
| C5 | The broker's slots are the connections it handed over, whatever database they went to: a yield gives exactly its one slot back (SESSION_END), and a dispatcher of one database may be served by a yield in another. | user Q7; B1a C1 |
| C6 | A session is yielded only while it waits for a request with no transaction, no holdable cursor, no XA prepare and no method/SP callback resource; a request that arrives after the yield is not executed. | user Q3; legacy `cas_network.c` CHANGE CLIENT, `cas.c` `restart_is_needed`; old `csc_prepare_detach` |
| C7 | The resumed connection finds the session's client state as the yield left it (session variables and parameters, workspace, current schema); a kept session holds no connection, slot, transaction index or thread. CAS statement handles are not kept. | user Q4; legacy CAS change (the driver prepares again) |
| C8 | After a broker reset every session of the broker that is ever idle yields at its next idle point and keeps its session; a session that is never idle (KEEP_CONNECTION=ON) keeps its connection. | user Q7; old `c5cda0993a`; develop CBRD-27612 |

## Refinement map (model -> code)

| Model | Code | One step because |
|---|---|---|
| `BStart`, `BTop` | `brd_dispatch_job` → `brd_wait_for_slot` (`broker_direct.cpp:1271`): the loop top reads `slots_used` and `idle_hint_generation` (`:1285`) | under `slots_mutex` |
| `Admitted` (in `BTop`, `BSlot`) | the HANDOFF and its ACK (B1a's `DAdmit` … `SHSpawn`, `docs/tla/CBRD-27430-B1a`) | B1a's model; here one step |
| `BTry(d)`, `BTryRep` | `channel_request (YIELD_TRY)` to one owner and its reply (`:1080`) | one request and its reply on the channel (`request_mutex`) |
| `BWatch` | `channel_send (IDLE_WATCH, 1)` to every owner (`:1096`) | the sends are the dispatcher's own; the servers read them in order |
| `BSlot`, `BHint`, `BTimeout`, `Cancel` | `slots_cv.wait_until` returns (`:1103`): a slot, a hint, the deadline; then `IDLE_WATCH, 0` (`:1113`) | under `slots_mutex`; the cancels are queued behind the watch |
| `hint` | `idle_hint_generation != seen_hint`; the reader counts IDLE_HINTs (`:384`) | under `slots_mutex` |
| `EReset(d)` | a RESET message on the control channel (`msg_op::RESET`) — its sender, `cubrid broker reset` through the broker's session control socket, is B2 | — |
| `CStart(d)` | `channel_thread_run` reads one message and enters its handler (`adoption.cpp` switch) | the channel thread handles one message at a time |
| `CTCas(d, u)` | `handle_yield_try` (`adoption.cpp:881`): `state.compare_exchange_strong (idle, yielded)` on one registry entry | one atomic; the pass holds `registry_mutex`, so the set of entries is fixed |
| `CTWake(d)` | `wake_session` (`:386`) writes the eventfd through a `binding_pin`, then YIELD_TRY_REPLY | the write; the pin keeps the descriptor open (B1a's pin/drain) |
| `CW1`, `CWScan`, `CWX` | `handle_idle_watch` (`:773`): `watch_requested.store` (`:782`), the scan for an idle binding, `watch_requested.exchange (false)` (`:801`) then IDLE_HINT | each an atomic (the scan reads atomics of bindings that change under it; its result is one read of "some binding idle") |
| `CRMark(d, u)`, `CRCas(d)` | `handle_reset` (`:811`): `reset_requested.store (true)` (`:821`), then the compare-and-swap idle → yielded and the wake | two atomics on one binding |
| `Create(t)` | `db_restart_ex` (`driver_session.cpp:771`): the client boot creates the session; `session_adopt_client_context` | the session is not reachable by another connection before its id and secret are sent |
| `Claim(t)` | `session_claim_kept_context` (`session.c:3056`): key, find, secret, `csc_kept && ref_count == 0`, then `csc_kept = false`, `active_time`, the reference and the conn entry (`:3090`) | under the session's state mutex (the hash map's `find` returns it locked) |
| `Swap(t)` | `csc_deactivate`, `csc_retire_and_delete` of the thread's own context, `csc_activate (kept)` (`driver_session.cpp:737-740`) | `bracket_mutex` of the kept context |
| `Auth(t)` | `boot_resume_client` (`boot_cl.c:1782`): the user is the context's, `boot_register_client` (the fold boundary records the password proof CBRD-27445 asks for on the session's own connection, `network_interface_cl.c:4208`), `au_login` checks the password, commit; a failure aborts and unregisters | the thread's own bracket and transaction |
| `Top(t, c)` | the request loop's condition (`driver_session.cpp:480-485`) and `registry_auto_ready`'s `state.store (idle)` (`adoption.cpp:566`) | the condition reads the thread's own state; the store is one atomic |
| `Rst(t)` | `reset_requested.load ()`, the compare-and-swap idle → yielded, `wake_session` (`adoption.cpp:567-572`) | a load and a compare-and-swap of the thread's own binding; either order with `CRCas` leaves it yielded |
| `Wch(t)`, `Wx(t)` | `watch_requested.load () && state.load () == idle` and `watch_requested.exchange (false)` + IDLE_HINT (`adoption.cpp:573-578`) | the reads, then one atomic |
| `WakeSeen(t)` | `read_buffer`'s poll returns the wake descriptor and the binding is yielded (`cas_network.c:604-610`) | the thread's own descriptor |
| `Request(t)` | a request header was read; `registry_auto_begin_request` (`adoption.cpp:582`, called at `cas_conn_helpers.c:263`): compare-and-swap idle → busy, or the binding is yielded and the connection ends as CHANGE CLIENT (`cas_dispatch.c:510`) | one atomic |
| `Exec(t)` | `cas_process_request` runs the function | the thread's own session |
| `ClientClose(t)` | `net_read_int_keep_con_auto` returns an error (the peer closed, the socket failed) | — |
| `Finish(t)` | `registry_auto_finish` (`adoption.cpp:607`): `state.exchange (closing)` (`:614`) | one atomic |
| `EndSession(t)` | `driver_session.cpp:877-896`: rollback unless yielded, `db_set_keep_session (yielded)`, `ux_end_session` → `session_state_destroy` (`session.c:874`; keep: `active_time`, `csc_kept` at `:907`; else uninit and erase, the context orphaned inside its own bracket); after a failed login `session_rekeep_client_context` (`session.c:3108`) | under the state mutex |
| `FreeConn(t)` | `css_free_conn` (`driver_session.cpp:927`): `session_state_decrease_ref_count` | an atomic decrement |
| `Deact(t)` | `csc_deactivate` (`driver_session.cpp:936`): an orphaned context is torn down and deleted | `bracket_mutex` (A4) |
| `Send(t)` | `registry_session_finished` (`driver_session.cpp:948`, `adoption.cpp:621`): the registry erase, SESSION_END | `registry_mutex`; the slot accounting is B1a's |
| `Timeout(s)` | `time (NULL) - active_time >= session_state_timeout` for a kept session | the environment |
| `XScan(s)` | `session_remove_expired_sessions` (`session.c:1040`) iterating, `session_check_timeout` (`:1165`); the active connections' session ids are read once per pass | the iterator holds the entry's state mutex |
| `XRecheck` | the second `session_check_timeout` under the state mutex (`session.c:1113`) | the state mutex, kept until the erase |
| `XTear` | `session_state_uninit` → `csc_retire_and_delete` (`session.c:422`) enters the context's bracket, tears it down; `erase_locked` | `bracket_mutex`, then the erase under the state mutex |
| `pc`, `st`, `wake`, `rreq` | the session thread's position; `session_binding::state`, the eventfd, `reset_requested` | |
| `att`, `ref`, `kept`, `present`, `exp` | `conn->session_p`, `session_state::ref_count`, `csc_kept`, the hash map entry, `active_time` against the timeout | |
| `holder`, `cx`, `orphan`, `tear` | `client_session_context::bracket_mutex`, the thread's active context, `orphaned`, a ghost | |
| `wreq[d]` | `auto_group::watch_requested` of the broker on server d | |
| `q`, `qn` | the control channel socket d (broker → server), read in order by one thread | |
| `slotsUsed`, `slot` | `brd::manager::slots_used`, the token table | |
| `clean`, `yld`, `obs`, `verK`, `resumed`, `fail`, `dirtyStart`, `jobYields`, `badExec`, `expInUse`, `failDestroyed`, `tlsDirty`, `crossYield` | ghosts and the thread's local flags | — |

Callers of the protocol entry points (code-index `callers`): `registry_auto_ready` — `request_loop` only;
`registry_auto_begin_request` — `net_read_int_keep_con_auto` only (the read path of every request of an AUTO
session, in and out of a transaction); `registry_auto_is_yielded` — `read_buffer` only; `registry_auto_finish` —
`driver_session_run`'s `retire` label, which every exit path of the thread after `claim_entry` reaches;
`session_claim_kept_context`, `session_rekeep_client_context`, `boot_resume_client` — `driver_session_run` only.
`session_state_destroy (keep = true)` is reached in the server only through `db_end_session` with
`db_set_keep_session (true)`, which `driver_session_run` sets to `yielded` right before the call.

## Properties

| Property | Kind | Claim |
|---|---|---|
| `OneAttachment` (`ref` is the number of attached connections, at most one) | safety | C1, C7 |
| `NoIntruder` (no attachment with a wrong secret; no resumed connection runs with a failed login) | safety | C1 |
| `FailedLoginKeeps` | safety | C1 |
| `OneTeardown`, `NoExpiryInUse`, `AttachedIsPresent`, `ContextAlive` | safety | C2 |
| `OneYieldPerDemand` | safety | C3 |
| `NoStuck` (`Stuck ~> ~Stuck`, `FairSpec`) | liveness | C3 |
| `StartClean` | safety | C4 |
| `SlotExact` | safety | C5 |
| `CleanDetach`, `NoExecAfterYield` | safety | C6 |
| `Retained`, `KeptHoldsNothing` | safety | C7 |
| `NoParkedReset` | safety | C8 |
| `WakeMeansYielded` | safety | the wait ends on the wake descriptor only for a yield (`cas_network.c:607`) |

## Fault model

| Fault | Modelled | Where |
|---|---|---|
| error return | yes | the login of a resume (`Auth` fails → the session is kept again); the claim's refusals; the admission deadline (`BTimeout`) |
| error return: the boot of a new session fails, `eventfd` fails, the connect reply cannot be written | no | the thread goes to `retire` with no session or with `registered`: the session is ended (not kept), the same path as `ClientClose` → `EndSession` (destroy) |
| the client closes or the socket fails | yes | `ClientClose` at every wait |
| YIELD_TRY reply timeout (`CHANNEL_REPLY_TIMEOUT_SEC`) | no | the dispatcher treats it as "no" and kills the channel (B1a); a session the server yields afterwards is a late yield, allowed by C3 |
| the eventfd write fails | not applicable | a non-blocking eventfd write of 1 fails only at a counter of 2^64 - 2 |
| spurious wakeup | yes | `WakeSeen` on a binding that is not yielded stays in the wait (`goto retry_poll`); `BHint` on a stale hint tries again |
| OOM | no | `registry_auto_enable` and `handle_idle_watch` catch `bad_alloc`: the session is refused, the watch is not set (the dispatcher's deadline ends its wait) |
| crash / `kill -9` of the server | not applicable | kept sessions are memory only; a client's next connection presents another server key and starts a new session (`session_claim_kept_context`'s key check) |
| broker restart | B1a | the token table is re-synced (B1a); watch and hint state is per channel and starts empty |
| interrupt / query cancel | not applicable | a session that waits for a request runs no query |
| lock timeout, deadlock victim, conditional latch, vacuum, checkpoint, HA log apply, concurrent DML, nested statement | not applicable | no page, lock or snapshot is read by the protocol; `boot_resume_client`'s login runs in the thread's own transaction and a failure there is `Auth` failing |
| environment: a daemon pass is shorter than `session_state_timeout` | assumed | `Timeout` is not enabled inside a pass (`~snapTaken`); a pass reads memory only, the minimum timeout is one minute |
| environment: an attached session's `active_time` | assumed | an attached session is on the active connections' list, which refreshes it (`session_check_timeout`); the model lets only a kept, unreferenced session time out |
| fairness (C3) | assumed | weak fairness of every session thread's own steps, of each control channel thread and of the dispatcher; none for drivers, resets, the daemon and the deadline. The session thread and the channel thread run to their next blocking point; the dispatcher's wait is a condition variable signalled by the reader |

## Mutants

| cfg | `Mutant` | Removes | Violates | Claim |
|---|---|---|---|---|
| `mutant-no-excl` | `no_excl` | the claim's `csc_kept && ref_count == 0` | `OneAttachment` | C1 |
| `mutant-no-secret` | `no_secret` | the secret comparison | `NoIntruder` | C1 |
| `mutant-no-auth` | `no_auth` | the login of a resume | `NoIntruder` | C1 |
| `mutant-fail-destroys` | `fail_destroys` | the re-keep after a failed login (the session is ended) | `FailedLoginKeeps` | C1 |
| `mutant-no-renew` | `no_renew` | `active_time` renewed by the claim | `NoExpiryInUse` | C2 |
| `mutant-no-recheck` | `no_recheck` | the daemon's second check under the state mutex | `NoExpiryInUse` | C2 |
| `mutant-retry-after-claim` | `retry_after_claim` | the dispatcher only waiting after a YIELD_TRY said yes | `OneYieldPerDemand` | C3 |
| `mutant-no-watch-scan` | `no_watch_scan` | the scan for an already idle session after the watch is published | `NoStuck` | C3 |
| `mutant-no-idle-hint` | `no_idle_hint` | the session reading the watch request when it goes idle | `NoStuck` | C3 |
| `mutant-reuse` | `reuse` | a fresh thread per connection | `StartClean` | C4 |
| `mutant-leak-on-yield` | `leak_on_yield` | SESSION_END of a yielded session | `SlotExact` | C5 |
| `mutant-idle-dirty` | `idle_dirty` | the boundary condition before `registry_auto_ready` | `CleanDetach` | C6 |
| `mutant-no-begin` | `no_begin` | `registry_auto_begin_request` | `NoExecAfterYield` | C6 |
| `mutant-fresh-ctx` | `fresh_ctx` | the swap to the kept context | `Retained` | C7 |
| `mutant-no-reset-check` | `no_reset_check` | the session reading `reset_requested` when it goes idle | `NoParkedReset` | C8 |
| `mutant-reset-no-cas` | `reset_no_cas` | the reset yielding a session that is idle now | `NoParkedReset` | C8 |

## Witnesses

| cfg | Outcome |
|---|---|
| `witness-resumed` | a resumed connection runs a request on a session that already ran one |
| `witness-expired-fresh` | a connection that presented a removed session runs on a new one |
| `witness-rejected` | a connection with the right secret is refused because the session is attached |
| `witness-login-failed` | a failed login leaves the session kept |
| `witness-cross-yield` | a dispatcher of one database is admitted after a yield in another |
| `witness-hinted` | a hint arrives while the dispatcher watches |
| `witness-reset-yield` | a reset yields a session (no dispatcher ever waits: `MaxSlots = NT`) |
| `witness-lost-request` | a request arrives after the yield and is not executed |
| `witness-expired` | the daemon removes a kept session |

## Counterexamples (correct variant) and their classification

None from a correct-variant cfg. Two model errors found while writing the spec, fixed in the spec:

- `Create`'s guard evaluated `present[0]`: a disjunction is not short-circuited when TLC splits an action.
- The first YIELD_TRY model scanned for an idle binding and then swapped it (two steps, a retry on failure); the code
  makes one pass with a compare-and-swap per entry, and answers "no" when every swap failed although a binding went
  idle behind the pass. The model now takes the code's pass (`CTCas (d, u)` over `rset`), and the liveness still
  holds because the watch that follows a "no" scans again.

## Findings

Differences from the old implementation that the model or the reading decided (each a port decision, none a hole
reproduced at runtime, since the old code is not built here):

- **F1 (old `handle_idle_watch`)**: the old watch was dropped when no AUTO session of the broker had registered yet
  (`auto_pressure.find` → return), so a dispatcher that watched while every slot holder was still connecting was
  never hinted. The port creates the broker's group on the watch (`auto_group_of`).
- **F2 (old `registry_auto_ready (false)`)**: the old loop stored `busy` over a `yielded` binding after the request
  returned; the port never stores over `yielded` (only `registry_auto_finish` leaves it).
- **F3 (old `try_yield_idle`)**: a YIELD_TRY whose wake could not be written answered "no" although the session was
  yielded, so the dispatcher went on to a second session. The port answers "yes" whenever the swap succeeded.

## Dead expressions

Lines of `AutoSession.tla` the main cfg never evaluates; `tla-check` lists them per cfg.

| Line | Expression | Why it is dead |
|---|---|---|
| AutoSession.tla:281 | `Cancel`'s `UNCHANGED <<q, qn>>` as used by `BHint` | mutant-only: `BHint` fires with the watch on; only `retry_after_claim` enters it without one |
| AutoSession.tla:425 | `Create`: no session id left, the connection is refused | a model bound, not code (session ids are 32 bits): reached only with more connections than `NS`; fires in `scale-nt3` |
| AutoSession.tla:426 | the same branch's `UNCHANGED` | as above |
| AutoSession.tla:628 | `XScan`: a session past its timeout that is on the active connections' list gets its `active_time` refreshed | mutant-only (`no_renew`): the model lets only a kept, unreferenced session time out, and the claim renews `active_time`; in the code the branch serves attached sessions (`session_check_timeout`, `session.c:1165`), which the model keeps out of `exp` (Fault model, "an attached session's `active_time`") |

## Bounds

| cfg | NT | NS | ND | MaxSlots | MaxReq | MaxPass | MaxResets | QMax |
|---|---|---|---|---|---|---|---|---|
| `AutoSession.cfg`, `AutoSession.live.cfg` | 2 | 2 | 1 | 1 | 1 | 1 | 1 | 3 |
| `AutoSession.scale-nt3.cfg` | 3 | 2 | 1 | 1 | 1 | 1 | 1 | 3 |
| `AutoSession.scale-nd2.cfg` | 2 | 2 | 2 | 1 | 1 | 1 | 1 | 3 |
| `AutoSession.apalache-indinv.cfg` (`CInit`) | 2 | 2 | 1 | 1 | 1 | Nat | Nat | 3 |
| `AutoSession.apalache-indinv3.cfg` (`CInit3`) | 3 | 3 | 2 | 2 | 2 | Nat | Nat | 3 |

- Threads are interchangeable until they start, so `BStart` starts the least one that has not started (a symmetry
  reduction written into the action; TLC's SYMMETRY is not used, the liveness cfg needs the same spec).
- Two threads are a yielding session and its dispatcher's connection, or a kept session's two claimants; the third
  thread of `scale-nt3` adds a second claimant beside a holder and a third session id's exhaustion. Two databases
  (`scale-nd2`, `witness-cross-yield`, `CInit3`) add the dispatcher's pass over two owners.
- `IndInv`'s inductiveness is checked by Apalache for every value of `MaxPass` and `MaxResets`; the sizes of the role
  sets and the bounds that are domains or codomains of functions (`MaxReq`, `QMax`) are fixed per cfg. The liveness
  property is checked by TLC inside the main cfg's bounds only.
- Not modelled: the handoff itself and the token table (B1a's model: `Admitted` and `Send` are its admission and
  SESSION_END), the control channel's death and the broker's restart (B1a), SSL, the access log and the sql log
  (B2), CAS statement handles (thread-local, gone with the thread), more than one broker (groups are per broker
  name; a second broker's sessions are another instance of the model).

## Trace validation

Instrumented build: scratch worktree of `d564c755e` (`cas-fold-v2-tla1b`), optdebug, libcubrid
``526cc2beb905…``; instrumentation `fold-v2/b1b/instrument.py` (97 added lines, no line removed;
`instrumented.diff`), runner `fold-v2/b1b/trace/run.sh`, converter `fold-v2/b1b/events.py`. The broker and the server
append to one file; the converter orders the lines by CLOCK_MONOTONIC and renames dispatch jobs to threads (in
dispatch order, the model's `BStart` order), tokens to the admitted jobs in order, session ids to 1..NS in creation
order. A broker of one slot (`MAX_NUM_APPL_SERVER=1`, `KEEP_CONNECTION=AUTO`), one database.

Steps the converter derives from a logged evaluation, each bounded by what the model can take:

- `BStart`'s session and credential are read ahead from the thread's own `Claim`/`Auth` events (the dispatcher does
  not know them).
- `CTCas (d, u)` failing is logged as "try u" with no "ok" before the pass's next entry; `Wx` taking nothing
  (the controller took the request first) is the thread's `Wch go=1` with no `Wx` before its next event.
- A request that ends the loop (CON_CLOSE) is `Exec`, `Top (FALSE)`, `ClientClose`; the read after a `WakeSeen` is
  dropped (the model leaves the wait at the wake). `EReset` precedes the `CStart` of a RESET; `Timeout (s)` precedes
  the daemon pass that scans s, `XEndPass` follows a pass that scanned.
- A connection refused at the claim logs no `Finish`/`FreeConn`/`Deact` (it never left the claim in the model).

| cfg | Run | Events | Verdict |
|---|---|---|---|
| `witness-trace-resume` | two JDBC clients share the slot: 4 yields by YIELD_TRY, 4 resumes, each keeps its session variable | 225 | accepted |
| `witness-trace-intran` | a client holds a transaction: YIELD_TRY answers no, IDLE_WATCH, the commit, IDLE_HINT, YIELD_TRY yes | 120 | accepted |
| `witness-trace-probe` | raw wire: yield, a resume with a wrong password (the session kept again), with a wrong secret (refused), the right one; RESET yields; resume after a broker restart | 101 | accepted |
| `witness-trace-expire` | a kept session nobody resumes: the daemon's scan, second check and teardown; the client's next connection starts a new session | 92 | accepted |
| `reject-auth-flipped` | the probe run with the failed login logged as a success | — | refused at event 60 |
| `reject-yield-flipped` | the resume run with the first yielded `Finish` logged as an ordinary end | — | refused at event 39 |
| `reject-wake-without-cas` | the resume run with the first successful compare-and-swap of a YIELD_TRY dropped | — | refused at event 35 |

Actions no accepted run takes: `CWX` (the watch's own scan finding a session idle: in the recorded runs the session
went idle after the scan and sent the hint itself, `Wx`), `BTimeout` (a 60-second admission wait; the rejection is
B1a's), `Request` losing to a yield (a request in flight at the yield; `witness-lost-request` reaches it in the
model). Two databases are not recorded (one server in the runs).

## Result

2026-11-17, `tools/tla/tla-check docs/tla/CBRD-27430-B1b`: **`RESULT: OK`**, 38 cfgs PASS, run dir
`.git_ignored_dir/scratch/tla/CBRD-27430-B1b-20261117-141118-3374099` (copy of the verdicts: tooling scratch
`fold-v2/b1b/tla-check-record.out`). The Result section was written after the run; the spec and cfg files are the
run's.

| cfg | Verdict | States (generated / distinct) | Depth |
|---|---|---|---|
| `AutoSession` (16 invariants + `IndInv`) | pass | 706,024 / 288,207 | 61 |
| `AutoSession.live` (`NoStuck`, `FairSpec`) | pass | 706,024 / 288,207 | 61 |
| `AutoSession.scale-nd2` | pass | 2,155,627 / 830,484 | 61 |
| `AutoSession.scale-nt3` | pass | 68,219,331 / 23,409,425 | 84 |
| 16 mutant cfgs | each the expected violation (14 invariants, 2 liveness) | 245 … 642,976 generated | 8 … 51 |
| 9 witness cfgs | each reached | 302 … 196,844 generated | 8 … 25 |
| `AutoSession.apalache-indinv` (`CInit`), `AutoSession.apalache-indinv3` (`CInit3`) | pass: `IndInv /\ Next => IndInv'` | Apalache, 39 s and 65 s | — |
| 4 `witness-trace-*` cfgs | accepted (the whole run consumed) | 93, 121, 102, 226 states | = events + 1 |
| 3 `reject-*` cfgs | refused | 60, 35, 39 states | — |

TLAPS: not requested. Engine: `cas-fold-v2` `d564c755e`; trace build libcubrid `526cc2beb905…` (optdebug, scratch
worktree of that commit, removed after the runs). Gate builds: optdebug libcubrid `aaffbceb2d72…`, release
`1f779e1f31de…`.

spec sha256:

```
5d515572385fa361d592b1758cd7fbf13667b44cc97b32d22e1a1aabb8cc5cbd  AutoSession.tla
58b762721597a30b1408a9920ee4091b4b73c3d62853f27b7ffde822234b4dc5  AutoSessionTrace.tla
23b69b32fac45ea0169eb1017038b0d401d24ed9ec4e17b89944a7d0f3326eed  AutoSessionTraceData.tla
e900b117a2082e5813120878d5a6253d23f1e86d7abe38e1f21e54227df74495  AutoSession.cfg
```

