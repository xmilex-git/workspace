# CBRD-27430 B2 — what a CAS did for its connection, done by the folded server's session

Map [CAS 폴드 재이식 지도](https://github.com/xmilex-git/workspace/issues/618), ticket
[B2 TLA+ 검증·이식](https://github.com/xmilex-git/workspace/issues/633). A CAS process read its broker's conf from
the broker's shared memory, wrote the `<broker>_<its number>` log files, checked ACCESS_CONTROL, ended TLS, showed
its counters in `cubrid broker status` and was the thing `broker_changer`, `cubrid broker reset` and a kill acted
on. In the folded server a session is a thread of `cub_server`, so each of these has an owner and a protection of
its own. Five models, one per shared state:

| Module | Shared state | Claims |
|---|---|---|
| `ConfigPush` | a broker's conf: its shared memory, the copies in HANDOFF and SESSION_CONFIG, a server's latest, a session's binding and thread | C6, C7 |
| `AclTable` | the server's access control table and its load | C2 |
| `LogLease` | the index in a session's log file names | C5 |
| `StatsKill` | a session's SHOW SESSION STATUS row, its registry entry and its descriptor | C4, C8 |
| `SslAck` | what the broker and the server send an SSL client before TLS | C1 |

Code: fork branch `cas-fold-v2`, B2 commit `b78af44d4` on `46c8e2e49` (worktree
`~/dev/cubrid-worktree/cas-fold-v2`); the line numbers below were
moved to `f9e3e6637` (develop `ce985257b` merged, no model step changed). Old implementation: `cas-merge` @
`cdb9da11e`, the attribution table's B2 commits (36 commits, 17 files; per-file lines in the tooling scratch
`fold-v2/b2/lines/`).

What this stage took from the old implementation and what it did not:

- **The broker's conf travels with the session, not as server parameters** (user decision 2026-11-17). The old code
  made 16 `cas_*` server parameters and a fixed `shm_appl` stub. Here every value a CAS read from its broker's shared
  memory is a field of `session_config`, carried by the HANDOFF and again by a SESSION_CONFIG when broker_changer
  changes it; only the three ACCESS_CONTROL parameters are server parameters.
- **A seq orders the copies.** The old code had no ordering; the model showed a SESSION_CONFIG the broker gave up on
  can be handled after a later one (Findings 1).
- **The log index is a lock file of the host**, not an allocator of the server: one broker hands sessions to several
  servers and its sessions outlive its restart.
- **No shared `SSL_CTX`.** The old code kept one context and reloaded it (the ticket's claim candidate C3). develop's
  `cas_init_ssl` (`cas_ssl.c:97`) makes a context per connection and frees it with the connection; the port keeps
  that, so there is no reload and no claim (`rg shared_ctx src` finds nothing).
- **A reader of SHOW SESSION STATUS never reads a session's slot** (user decision 2026-11-17): the session publishes
  a copy of its row at request boundaries. The old code read the slot of another thread with no synchronization.

## Claim and sources

| # | Claim | Source |
|---|---|---|
| C1 | An SSL client is sent its ack (the four zero bytes it starts TLS on) only once a server holds its connection, and it is sent one answer: the ack or an error code, never an ack and then an error. A cleartext client is acked at once, as before, and may get an error after it. | [B2 구현 계획](https://github.com/xmilex-git/workspace/issues/139) B2-D9; develop `cas_common_main.c:189` (the CAS's ack) and `:215` (`cas_init_ssl` right after it); the driver gives the ServerHello one second after the ack; ticket #633 candidate C1 |
| C2 | An access check is decided by one table of one load, with that load's failed mark: never a part of two loads. A file that cannot be read in full allows nobody (loopback excepted). Once a reload has returned, a check uses the file as it was at that reload or later. | [#116](https://github.com/xmilex-git/workspace/issues/116) D6; #139 B2-D8; ticket #633 candidate C2; legacy `broker_acl.c` |
| C4 | A row SHOW SESSION STATUS returns is one whole publication of a registered session, never a session's counters read in the middle of a request. | #116 D10; #139 B2-D10; ticket #633 candidate C4 and its "torn fields" question; user decision 2026-11-17 (row copy at a request boundary under a per-session mutex) |
| C5 | No two sessions of one broker have the same log index while either has its log files open, whichever servers of the host they run in; an index is free again when its session closed its files, and when its server was killed. | #139 B2-D1, B2-D2 (the allocator they describe is replaced); legacy `<broker>_<as_index + 1>.sql.log`; `flock(2)` (the lock belongs to the open file description; the kernel drops it with the process) |
| C6 | After broker_changer was told a change is delivered, no session of the broker works with an older conf, except one that has the newer conf waiting for its next request boundary. A session's conf only moves to a later one. Under fair session threads a delivered change is applied by every session that stays. | user decision 2026-11-17 (the broker's conf only, by HANDOFF); legacy: every CAS read the shared memory broker_changer wrote; #116 D9 (superseded: no `cas_*` server parameter) |
| C7 | A change reaches the sessions that outlived a restart of their broker, and broker_changer is told when a server did not answer ("some sessions keep the previous setting"). | B1a (a session outlives its broker); legacy `broker_changer` printed OK only after the change was in place |
| C8 | A kill shuts down only the open connection of the session that has the transaction: never a descriptor number that was closed and given to another connection. | B1a's pin/drain (`binding_pin`, `docs/tla/CBRD-27430-B1a`); legacy: killtran ended the CAS's connection through its client entry |

The ticket's third candidate ("reloading the SSL context does not free a context a session uses") is not a claim of
this port: there is no shared context (see above).

Not modeled, with the code fact: the SQL log's idle flush is a POSIX timer per session thread
(`cas_log.c:1527` `SIGEV_THREAD_ID`, develop CBRD-27413), whose handler runs on the thread that owns the log
buffers — one owner, no shared state. The histogram of a thin csql and the `cas_*` parameters a direct csql would
need are B5's.

## Refinement map (model -> code)

`ConfigPush` (broker `broker_direct.cpp`, broker_changer `broker_admin_pub.c`, server `adoption.cpp`):

| Model | Code | One step because |
|---|---|---|
| `AChange` | `admin_conf_change` writes the shared memory, then `admin_session_control (…, BRD_CONTROL_CONFIG)` (`broker_admin_pub.c:1213`, called at `:2763`) asks on the broker's session control socket | the write is one field of the shared memory; the request is counted when it is sent (the model's `pushReq`) |
| `BRestart` | the broker process ends and `brd_init` (`:1135`) runs in a new one: `config_seq` starts at the clock's microseconds (`:1151`), no channel | a new process; the shortcut comment at `:1147` names its limit (the clock going back) |
| `DStart`, `DSnap` | `brd_dispatch_job` (`:1347`) → `config_snapshot (*m, body.config)` (`:1401`): the shared memory and `++config_seq` (`:964`) | under `config_mutex`; the mutant `snap_unlocked` splits the two |
| `DSend`, `DReply`, `DTimeout` | `channel_request (HANDOFF)` (`:1420`) and its return (`:1423`) | one request and its reply on the channel (`request_mutex`); a timeout leaves the message with the server |
| one dispatcher | dispatch jobs run on several threads | each job's snapshot is one step and its message is delivered in any order, so jobs that overlap reach the states of jobs that follow one another with `DTimeout` between them (which changes only `known`, read by the mutant `no_dial_all`) |
| `CStart` | `control_thread_run` (`:1060`) accepts a request (peer uid checked, `:1081`) and calls `control_broadcast` (`:996`) | the control thread serves one request at a time |
| `CDial` | every adoption socket is dialed (`:1015`), then the live channels are the targets | under `channels_mutex` for the list |
| `CSnap` | `config_snapshot (m, config)` in `control_broadcast` | under `config_mutex` |
| `CSend (d)`, `CReply (d)`, `CTimeout (d)` | `channel_request (SESSION_CONFIG)` (`:1047`) per target, one after another | one request and its reply; a failure marks the push incomplete |
| `CDone` | `control_broadcast` returns the sessions reached or -1; `admin_session_control` prints the partial-delivery message | the reply on the control socket |
| `SHandoff (m)` | `handle_handoff` (`adoption.cpp:681`): under `registry_mutex` the session's conf is the newer of `latest_config[broker]` and the HANDOFF's (`:778`), then the entry is registered (`:796`) | under `registry_mutex` |
| `SRefuse (m)` | the reject paths of `handle_handoff`, and the undo when HANDOFF_ACK cannot be sent (`:818`) | no entry is left |
| `SConfigBegin (m)` | `handle_session_config` (`:967`, dispatched at `:1153`) takes `registry_mutex` and raises `latest_config` | under `registry_mutex` |
| `SWrite (s)` | `if (config.seq <= binding.config.seq) continue; binding.config = config;` (`:988`, `:992`) | under the binding's `control_mutex` |
| `SFlag (s)` | `binding.config_changed.store (true)` (`:994`) | one atomic, after the mutex was released: its own step |
| `SConfigEnd (m)` | the handler leaves `registry_mutex` and sends SESSION_CONFIG_REPLY | the reply follows the last write |
| `TClear (s)` | `registry_take_config` (`:423`): `config_changed.exchange (false)` (`:426`), called at a request boundary (`cas_dispatch.c:546`) | one atomic |
| `TRead (s)` | `config = current_session->config` (`:431`), then `cas_server_session_config_take` (`cas_server_support.cpp:144`) applies it to the thread's `cas_session_cfg` | under `control_mutex`; the thread-local copy has one owner |
| `TFinish (s)` | `registry_session_finished` (`:621`) erases the entry (`:639`) | under `registry_mutex` |

`AclTable` (`cas_server_support.cpp`):

| Model | Code | One step because |
|---|---|---|
| `FEdit (bad)` | the administrator rewrites `cas_access_control_file` or an ip file | outside the server |
| `LStart (l)` | `cas_server_acl_reload` (`:442`) takes `cas_Acl_load_mutex` (`:446`); callers: `acl_reload` (`adoption.cpp:399`, from `cubrid server acl reload`) and the first check | the mutex |
| `LParse (l)` | `cas_acl_parse (table)` (`:450`) into the loader's own table | no shared state but the file |
| `LSwap (l)` | `cas_Acl_table.swap (table)` (`:459`), `cas_Acl_load_failed`, `cas_Acl_loaded` | under `cas_Acl_mutex`; then `cas_Acl_load_mutex` is released |
| `CCheck (c)` | `cas_server_acl_check` (`:471`, called at `driver_session.cpp:677`): the mark and the table | under `cas_Acl_mutex` (`:548`) |
| `CAgain (c)` | the next connection | — |

`LogLease` (`cas_server_support.cpp`, `driver_session.cpp`):

| Model | Code | One step because |
|---|---|---|
| `SBegin (s)`, `STry (s)` | `cas_server_session_log_begin` (`:198`, called at `driver_session.cpp:586`): `flock (fd, LOCK_EX \| LOCK_NB)` on `var/cas_log_slots/<broker>_<N>.lock`, N from 1 (`:288`) | one system call per index; the kernel decides |
| `SOpen (s)` | `cas_log_open`, `cas_slow_log_open` (`driver_session.cpp:595`), the DDL log by its first line | the session's own files |
| `SClose (s)` | `logddl_destroy`, `cas_log_close`, `cas_slow_log_close` (`driver_session.cpp:913`) | the session's own files |
| `SRelease (s)`, `SDone (s)` | `cas_server_session_slot_end` (`:251`, called at `driver_session.cpp:916`) closes the lock file (`:318`) | one system call |
| `Crash (p)` | `kill -9` of a `cub_server` | the kernel closes its descriptors |

`StatsKill` (`adoption.cpp`, `driver_session.cpp`):

| Model | Code | One step because |
|---|---|---|
| `SNew (s, f)` | `handle_handoff` registers the binding with the descriptor it received (`:794`) | under `registry_mutex` |
| `SPublish (s)` | `publish_stats` (`driver_session.cpp:429`) → `registry_publish_stats` (`:494`): after the login and after every return of `cas_process_request` | under the binding's `control_mutex` |
| `SReqA (s)`, `SReqB (s)` | a request changes the thread's `as_info` counters one after another (`cas_dispatch.c`, `cas_common_execute.c`) | the slot is the thread's own; two steps so that a reader of the slot could see them apart |
| `SCleanup (s)`, `SDrain (s)` | `registry_begin_session_cleanup` (`:371`): `closing = true` (`:390`), wait for `users == 0`, `client_fd = -1` (`:393`) | under the binding's `mutex`; the wait is its own step |
| `SErase (s)` | `registry_session_finished` erases the entry (`:639`) | under `registry_mutex` |
| `SClose (s)` | `close (params.client_fd)` (`driver_session.cpp:954`), after the erase | one system call |
| `RBegin`, `RRow (s)`, `REnd` | `registry_stats_snapshot` (`:447`, from `server_support.c:312`): `rows[count++] = binding.stats` (`:467`) | `registry_mutex` for the scan, `control_mutex` per row |
| `KBegin`, `KPin (s)`, `KShut`, `KEnd` | `registry_shutdown_session` (`:474`, from `connection_sr.c:1359`): `binding_pin` (`:488`), `shutdown (pin.client_fd, SHUT_RD)` (`:492`) | `registry_mutex` for the scan; the pin holds `SDrain` back |
| a pin that finds another transaction | the scan pins every entry to read its transaction index and unpins it | it shuts nothing down and only delays that session's `SDrain`; not a step of the model |

`SslAck` (`broker_direct.cpp`, `adoption.cpp`, `driver_session.cpp`):

| Model | Code | One step because |
|---|---|---|
| `BPark` | `brd_park_client` (`:1214`): an SSL client is queued for `DIRECT_HANDOFF_SSL_DB` with no ack (`:1229`); a cleartext client is acked and its db_info awaited | the receiver thread owns the connection |
| `BPeeked`, `BPeekTimeout` | `park_complete` (`:790`), `park_drop` (`:838`) | the peek thread owns it |
| `BDequeue`, `BDial`, `BSlot` | `brd_dispatch_job` (`:1347`): `channel_get_or_dial` (`:1379`), `brd_wait_for_slot` (`:1392`) | B1a's steps; here each one step |
| `BRequest (sent)` | `channel_request (HANDOFF)` with the descriptor (`:1420`); `fd_transferred` says whether it left | one request |
| `SHandle (ok)` | `handle_handoff`: registered and HANDOFF_ACK (`adoption.cpp:820`), or HANDOFF_REJECT | under `registry_mutex` |
| `BAck` | HANDOFF_ACK read: the ack to an SSL client (`:1446`), then the broker closes its copy | the dispatch thread owns the broker's copy |
| `BReject`, `BReplyTimeout`, `SLate` | HANDOFF_REJECT: the error code; no reply (`:1423`): nothing is sent after the descriptor left | as above |
| after the ack | `cas_init_ssl` in the session thread (`driver_session.cpp:603`) | the session owns the connection |

## Properties

| Property | Kind | Claim | Module |
|---|---|---|---|
| `AckAfterHandoff`, `OneAnswer`, `AnswerShape` | safety | C1 | `SslAck` |
| `OneTable`, `Fresh` | safety | C2 | `AclTable` |
| `RowWhole`, `RowPublished` | safety | C4 | `StatsKill` |
| `KillRight`, `FdConsistent` | safety | C8 | `StatsKill` |
| `Exclusive`, `OpenUnderLease`, `LockIsHolder` | safety | C5 | `LogLease` |
| `NoStale`, `ThreadBehindBinding`, `SeqOrdersConf` | safety | C6, C7 | `ConfigPush` |
| `Applied` | liveness (`ConfigPush.live`, weak fairness of `TClear`, `TRead`, `SWrite`, `SFlag`) | C6 | `ConfigPush` |
| `IndInv` | inductive invariant of each module (Apalache, `CInit`) | all | every module |

C7's two halves are `NoStale` under a restart (the mutants `no_dial_all` and `seq_restart` break it) and the
witness `partial` (a push that is answered as not delivered).

## Fault model

| Fault | Answer |
|---|---|
| error return | modeled: HANDOFF refused (`SRefuse`, `SHandle (FALSE)`), the server not up (`BDial (FALSE)`), no slot (`BSlot (FALSE)`), the HANDOFF not sent (`BRequest (FALSE)`), a file that cannot be read (`FEdit (TRUE)` → `lbad`) |
| message given up (timeout) | modeled: `DTimeout`, `CTimeout`, `BReplyTimeout`; the message may still be handled (`net` keeps it) |
| interrupt / query cancel | not applicable: no step of these models runs a query; a kill is `StatsKill`'s `K*` |
| lock timeout, deadlock victim | not applicable: no lock manager lock; the mutexes are taken in one order (`registry_mutex` → a binding's `control_mutex`; `cas_Acl_load_mutex` → `cas_Acl_mutex`) |
| conditional latch failure | modeled where there is one: `flock (LOCK_NB)` failing is `STry` moving to the next index |
| OOM | `handle_session_config`'s `bad_alloc` sends no reply: the broker's `CTimeout`. `cas_acl_parse`'s `bad_alloc` is a failed load (`lbad`). `handle_handoff`'s is a reject |
| crash / `kill -9` | modeled: a server (`Crash` in `LogLease`), the broker (`BRestart`). A server's crash ends its sessions, so `ConfigPush` and `StatsKill` have nothing to keep |
| spurious wakeup | the one condition wait is `drained.wait (…, users == 0)`: `SDrain` is enabled by the predicate only |
| concurrent DML, vacuum, checkpoint, HA log apply, nested statement | not applicable: no page, record or snapshot is read |
| broker restart | modeled: `BRestart` (`ConfigPush`); the lease outlives it by construction (`LogLease` has no broker) |
| fairness | `Applied` needs weak fairness of the session's `TClear`/`TRead` (a session that gets a request) and of the handler's `SWrite`/`SFlag`; the environment (broker_changer, restarts, timeouts) has none |

## Mutants

| cfg | What it removes | Rejected by | Claim |
|---|---|---|---|
| `ConfigPush.mutant-no-seq-order` | a SESSION_CONFIG replaces a session's conf whatever its seq | `NoStale` | C6 |
| `ConfigPush.mutant-no-latest` | a HANDOFF's conf is taken without comparing it with the broker's latest | `NoStale` | C6 |
| `ConfigPush.mutant-read-then-clear` | the session copies the conf, then clears the flag | `NoStale` | C6 |
| `ConfigPush.mutant-flag-before-write` | the handler sets the flag, then writes the conf | `NoStale` | C6 |
| `ConfigPush.mutant-no-dial-all` | a push goes only to the channels the broker has | `NoStale` | C7 |
| `ConfigPush.mutant-snap-unlocked` | the seq is taken after the shared memory was read, with no mutex around the two | `NoStale` | C6 |
| `ConfigPush.mutant-seq-restart` | a restarted broker starts its seq at 0 | `NoStale` | C7 |
| `AclTable.mutant-load-unserialized` | two loads run at once (no `cas_Acl_load_mutex`) | `Fresh` | C2 |
| `AclTable.mutant-check-unlocked` | a check reads the mark and the table in two steps | `OneTable` | C2 |
| `LogLease.mutant-no-lease` | an index excludes only the sessions of the same server | `Exclusive` | C5 |
| `LogLease.mutant-release-before-close` | the lock file is closed before the logs | `OpenUnderLease` | C5 |
| `LogLease.mutant-release-shares-file` | the same, read by the claim itself | `Exclusive` | C5 |
| `StatsKill.mutant-read-slot` | the reader reads the session's slot | `RowWhole` | C4 |
| `StatsKill.mutant-unpinned-unlocked` | the kill takes neither `registry_mutex` nor a pin | `KillRight` | C8 |
| `SslAck.mutant-ack-at-park` | an SSL client is acked when it is parked | `OneAnswer` | C1 |
| `SslAck.mutant-ack-at-park-unheld` | the same | `AckAfterHandoff` | C1 |
| `SslAck.mutant-ack-before-reply` | the ack is sent when the HANDOFF was sent | `AckAfterHandoff` | C1 |

## Witnesses

| cfg | Outcome reached |
|---|---|
| `ConfigPush.witness-applied` | a session works with the last conf and the change was answered as delivered |
| `ConfigPush.witness-late-older` | a SESSION_CONFIG older than a delivered one is still unhandled |
| `ConfigPush.witness-survivor-reached` | after a restart a session that outlived it works with the new conf |
| `ConfigPush.witness-partial` | a push ends with a server that did not answer |
| `AclTable.witness-fail-closed`, `witness-reloaded` | a check under a failed load; a check that used a later version than the first load |
| `LogLease.witness-second`, `witness-reused`, `witness-after-crash` | two indexes held at once; an index held again after its session left; after its server was killed |
| `StatsKill.witness-read`, `witness-killed`, `witness-kill-waited`, `witness-fd-reused` | a row read after a request; a shutdown; a session's drain waiting for a pin; a descriptor number given to a second session |
| `SslAck.witness-served`, `witness-refused-unacked`, `witness-silent`, `witness-cleartext-ack-then-err` | an SSL client served; refused with no ack before the error; left with no answer (the HANDOFF's reply did not come); a cleartext client acked, then refused |

## Counterexamples (correct variant) and their classification

| Counterexample | Classification |
|---|---|
| `ConfigPush`: the final state (every session ended) reported as a deadlock | model error: the environment could not end; `Finished` stutters there |
| `ConfigPush`: `CReply` taken for a server the push was not sent to | model error: the reply is of the request in flight (`cw`); `control_broadcast` asks one target at a time |
| `ConfigPush`: `NoStale` — a SESSION_CONFIG the broker timed out on is handled after a later one and replaces the later conf | **hole in the design as first written**, fixed before any build was gated (Findings 1) |
| `AclTable`: `Fresh` — a load that parsed the older file swaps after a load that parsed the newer one | **hole in the design as first written**, fixed (Findings 2) |
| `StatsKill`: `TypeOK` of `shuts` | model error: the ghost counter's bound; `KPin` is guarded by it |
| `ConfigPush`: `IndInv` on a reachable state — a session's conf older than `latest` | the invariant was too strong (a HANDOFF raises `latest` and pushes nothing); `Cover` now says what the handler guarantees |

## Findings

1. **A late SESSION_CONFIG could put an older conf back** (found by `ConfigPush`, no seq). The broker gives a channel
   up after a timeout and dials again; the old channel's thread on the server may still handle the message it had.
   Fix in the design: every snapshot carries a seq (`config_seq`, `broker_direct.cpp:964`); the server keeps the
   broker's latest and replaces a session's conf only by a larger seq (`adoption.cpp:778`, `:990`). Mutants
   `no_seq_order`, `no_latest`, `seq_restart`, `snap_unlocked`.
2. **Two ACL loads could finish in the wrong order** (found by `AclTable`): the parse runs outside the table's
   mutex, so the load that read the older file could swap last. Fix: `cas_Acl_load_mutex` around a whole load
   (`cas_server_support.cpp:446`). Mutant `load_unserialized`.
3. **A session answered a cursor close as "no transaction"** (found by the smoke, not by a model; present since
   B1a). `is_first_request` was set when the session began and never cleared, so every request that starts no
   transaction restored the status to out-of-transaction; a JDBC client with autocommit off then skipped its
   END_TRAN and the transaction kept its locks. Fix: `driver_session.cpp:490`. Before: the probe
   `fold-v2/b2/probe_lock.sh` shows the class lock held after the commit and one `end_tran` in the SQL log; after:
   no lock, two `end_tran`. The 51 cases that ran in the in-process tracer never took this path; cases 34–36 hung
   on it once they ran through the wire.
4. Smoke findings fixed in this stage: SHOW SESSION STATUS showed an empty `Db_user`; the SQL log lost the
   `con_close` line (the close discarded the open unit).

Open decision put to the user (not a defect): a KEEP_CONNECTION=ON session of the server has no out-of-transaction
SESSION_TIMEOUT (`cas_conn_helpers.c`, `net_read_header_keep_con_on`): the connection is the session, where a CAS
left an idle client after SESSION_TIMEOUT and the client took its session up again on another CAS.

## Dead expressions

Lines the main cfg of a module never evaluates; `tla-check` lists them per cfg. Each is a mutant's branch, or the
other value of `Ssl`.

| Line | Expression | Why it is dead |
|---|---|---|
| ConfigPush.tla:155 | `DSnap`: the seq left for a second step | mutant-only (`snap_unlocked`) |
| ConfigPush.tla:163 | `DSnapSeq` | mutant-only (`snap_unlocked`) |
| ConfigPush.tla:164 | `DSnapSeq`'s `UNCHANGED` | mutant-only (`snap_unlocked`) |
| ConfigPush.tla:295 | `SWrite`: the flag set before the conf | mutant-only (`flag_before_write`) |
| ConfigPush.tla:306 | `SFlag`: the conf written after the flag | mutant-only (`flag_before_write`) |
| ConfigPush.tla:307 | the same branch's `UNCHANGED` | mutant-only (`flag_before_write`) |
| ConfigPush.tla:326 | `TClear` after the read | mutant-only (`read_then_clear`) |
| ConfigPush.tla:337 | `TRead` before the clear | mutant-only (`read_then_clear`) |
| AclTable.tla:70 | `LStart` without the load mutex | mutant-only (`load_unserialized`): the `THEN` arm |
| AclTable.tla:96 | `CCheck`: the table left for a second step | mutant-only (`check_unlocked`) |
| AclTable.tla:103 | `CCheckTable` | mutant-only (`check_unlocked`) |
| AclTable.tla:104 | `CCheckTable` | mutant-only (`check_unlocked`) |
| AclTable.tla:105 | `CCheckTable`'s `UNCHANGED` | mutant-only (`check_unlocked`) |
| LogLease.tla:64 | `STry`: an index free among the sessions of the same server | mutant-only (`no_lease`) |
| LogLease.tla:65 | `STry`: the next index, the same mutant | mutant-only (`no_lease`) |
| StatsKill.tla:171 | `RRow` reading the slot | mutant-only (`read_slot`) |
| StatsKill.tla:178 | `RSlotB` | mutant-only (`read_slot`) |
| StatsKill.tla:179 | `RSlotB`'s `UNCHANGED` | mutant-only (`read_slot`) |
| StatsKill.tla:192 | `KBegin` without `registry_mutex` | mutant-only (`unpinned_unlocked`): the `ELSE` arm |
| StatsKill.tla:201 | `KPin` without a pin | mutant-only (`unpinned_unlocked`) |
| StatsKill.tla:211 | `KShut` with no pin to drop | mutant-only (`unpinned_unlocked`) |
| StatsKill.tla:217 | `KEnd` without `registry_mutex` | mutant-only (`unpinned_unlocked`) |
| ConfigPush.tla:135 | `BRestart` (lines 135–139) in `ConfigPush.live` | that cfg has `MaxRestart = 0`; the action fires in the main cfg |
| ConfigPush.tla:136 | as above | as above |
| ConfigPush.tla:137 | as above | as above |
| ConfigPush.tla:138 | as above | as above |
| ConfigPush.tla:139 | as above | as above |
| SslAck.tla:63 | `BPark`: an SSL client queued unacked, in `SslAck.scale-cleartext` | that cfg has `Ssl = FALSE`; the branch fires in the main cfg |
| SslAck.tla:54 | `SendAck` as used at the park | the main cfg has `Ssl = TRUE`: a cleartext client's ack fires in `SslAck.scale-cleartext` |
| SslAck.tla:55 | `SendAck`: `ackHeld` of a cleartext client | as above |
| SslAck.tla:64 | `BPark`: the ack at the park | cleartext (`scale-cleartext`) or the mutant `ack_at_park` |
| SslAck.tla:70 | `BPeeked` | cleartext only: an SSL client's db_info is encrypted and is not peeked |
| SslAck.tla:71 | `BPeeked`'s `UNCHANGED` | as above |
| SslAck.tla:75 | `BPeekTimeout` | cleartext only |
| SslAck.tla:76 | `BPeekTimeout`'s `UNCHANGED` | cleartext only |
| SslAck.tla:118 | `BAck`: no ack left to send | cleartext (acked at the park), fires in `scale-cleartext` |

## Bounds

| cfg | Constants | Why |
|---|---|---|
| `ConfigPush` | NS = 2, ND = 2, MaxV = 1, MaxRestart = 1 | two sessions (one live at a change, one handed over around it), two servers (a push reaches one and not the other), one change, one restart |
| `ConfigPush.scale-v2` | NS = 2, ND = 1, MaxV = 2, MaxRestart = 1 | two changes: a push overtaken by the next. With ND = 2 as well the check passed 30 million distinct states without ending in two hours; the two-server interleavings are the main cfg's |
| `ConfigPush.live` | NS = 1, ND = 1, MaxV = 1, MaxRestart = 0 | the smallest bound that reaches a delivered change (liveness alone) |
| `ConfigPush` mutants | NS = 1, ND = 1, the smallest MaxV and MaxRestart that reach the violation | a mutant needs one counterexample |
| `AclTable` | NL = 2, NC = 2, MaxF = 2; scale NL = 3, MaxF = 3 | two loaders (order), two checkers, two rewrites |
| `LogLease` | NS = 3, NP = 2, NI = 3; scale NS = 4, NI = 4 | sessions in two servers, more sessions than one server's |
| `StatsKill` | NS = 2, MaxReq = 2, NF = 1; scale NS = 3, NF = 2 | two sessions on one descriptor number (reuse), two requests |
| `SslAck` | Ssl = TRUE; scale Ssl = FALSE | the model is one connection; its two input classes |
| Apalache `CInit` | `ConfigPush` NS = 2, ND = 2, MaxV = 1, MaxRestart = 1; `AclTable` NL = 2, NC = 2, MaxF = 2; `LogLease` NS = 3, NP = 2, NI = 3; `StatsKill` NS = 2, MaxReq = 2, NF = 2; `SslAck` both values of `Ssl` | the constants bound the sets `IndInv` quantifies over; every state of `IndInv` at those sizes is checked, reachable or not |

## Trace validation

Instrumented build: scratch worktree of `b78af44d4` (`cas-fold-v2-tla2`), optdebug, libcubrid `c570e83dfaec…`;
instrumentation `fold-v2/b2/instrument.py` (93 added lines in 6 files, no line removed; `instrumented.diff`),
runner `fold-v2/b2/trace/run.sh`, converter `fold-v2/b2/events.py`, cfg and data generator `fold-v2/b2/trace/mk.py`.
The broker, broker_changer, the server and the run's script append to one file; the converter orders the lines by
CLOCK_MONOTONIC and renames a client port into a session, a binding's address into its session, snapshot seqs into
1, 2, … in the order they were taken, the values of LONG_QUERY_TIME into conf versions, descriptor numbers into
1..NF. Brokers `B2T` (cleartext, KEEP_CONNECTION=ON) and `B2TS` (SSL, DIRECT_HANDOFF_SSL_DB), one database.

Steps the converter derives, each bounded by what the model can take:

- `AChange` is logged by broker_changer after its write of the shared memory; a snapshot that shows the new value
  before that line has its `AChange` placed before it. `BRestart` is the start of a new process of the modeled
  broker. The snapshot of a RESET (sent to nobody) is dropped.
- `AclTable`: the script writes the access control file with as many rules as its version and logs each rewrite
  (`FEdit`); a load logs the rules it parsed, a check the rules of the table it read. `CAgain` follows every check.
- `LogLease`: a session is a session thread's pass through `cas_server_session_log_begin`; sessions are numbered
  so that `Proc (s)` is the server process that ran them. `Crash` is the script's `kill -9`.
- `StatsKill`: the slot's two counters are the requests the session thread started and finished; a row the reader
  copied is named by the publication it equals, -1 when it equals none.
- `SslAck`: one connection's events. `BRequest (TRUE)` is placed before the server's handling of the HANDOFF,
  `BRequest (FALSE)` at a request that returned unsent.

| cfg | Run | Events | Verdict |
|---|---|---|---|
| `ConfigPushTrace.witness-trace-config` | a session is live when broker_changer changes LONG_QUERY_TIME and takes the change at its next request; a second session is handed the new conf; a second change reaches both | 42 | accepted |
| `ConfigPushTrace.witness-trace-restart` | the broker restarts under a live session; the change after it is sent to the session's server, which the new broker had no channel to, and the session takes it | 20 | accepted |
| `AclTableTrace.witness-trace-acl` | checks from an address that is not the loopback; two `cubrid server acl reload` at once; a rewrite and a reload; an unreadable rewrite (the check is refused); a readable one again | 29 | accepted |
| `LogLeaseTrace.witness-trace-lease` | three sessions at once take indexes 1, 2, 3; the first leaves and the next takes 1; the server is killed with a session holding 3; sessions of the restarted servers take 1 | 37 | accepted |
| `StatsKillTrace.witness-trace-stats` | two sessions; SHOW SESSION STATUS reads both rows; `cubrid killtran` of one: the pin, the shutdown, that session's cleanup, drain, erase and close | 81 | accepted |
| `SslAckTrace.witness-trace-tls` | a TLS client through `B2TS`: parked unacked, handed over, acked after HANDOFF_ACK | 7 | accepted |
| `SslAckTrace.witness-trace-cleartext` | a cleartext client: acked at the park, its db_info peeked, handed over | 8 | accepted |
| `ConfigPushTrace.reject-write-skipped` | the config run with the first conf write logged as skipped | — | refused at event 12 |
| `AclTableTrace.reject-stale-check` | the acl run with the last good check logged with the table of the load before | — | refused at event 28 |
| `LogLeaseTrace.reject-index-twice` | the lease run with a held index logged as taken | — | refused at event 5 |
| `StatsKillTrace.reject-torn-row` | the stats run with a row's first counter one request ahead | — | refused at event 34 |
| `SslAckTrace.reject-ack-first` | the tls run with the ack before the server's handling of the HANDOFF | — | refused at event 6 |

Actions no accepted run takes: `DTimeout`, `CTimeout` (a server that does not answer within the channel's timeout;
the model reaches what follows them in `witness-late-older` and `witness-partial`), `SRefuse` and `BReject` (a
HANDOFF refused: a server shutting down or out of client seats), `BReplyTimeout` and `SLate` (the HANDOFF's reply
not coming after the descriptor left), `BPeekTimeout` (a client that sends no db_info for 60 seconds). Two servers
of one broker are not recorded (one database in the runs).

## Result

2026-11-17, `tools/tla/tla-check docs/tla/CBRD-27430-B2`: **`RESULT: OK`**, 62 cfgs PASS, run dir
`.git_ignored_dir/scratch/tla/CBRD-27430-B2-20261117-215438-3915919` (copy of the verdicts: tooling scratch
`fold-v2/b2/tla-check-record.out`). The Result section was written after the run; the spec and cfg files are the
run's.

| cfg | Verdict | States (generated / distinct) | Depth |
|---|---|---|---|
| `ConfigPush` (3 invariants + `IndInv`) | pass | 5,243,295 / 1,375,929 | 33 |
| `ConfigPush.scale-v2` | pass | 6,360,918 / 1,790,992 | 44 |
| `ConfigPush.live` (`Applied`, `LiveSpec`) | pass | 2,185 / 869 | 18 |
| `AclTable`, `AclTable.scale-3` | pass | 50,333 / 14,578 and 2,248,936 / 624,397 | 20, 27 |
| `LogLease`, `LogLease.scale-4` | pass | 7,398 / 1,681 and 195,167 / 35,229 | 16, 23 |
| `StatsKill`, `StatsKill.scale-3` | pass | 48,971 / 18,876 and 25,636,919 / 6,704,829 | 35, 49 |
| `SslAck`, `SslAck.scale-cleartext` | pass | 17 / 15 and 19 / 17 | 9, 10 |
| 17 mutant cfgs | each the expected violation | 2 … 47,035 generated | 2 … 31 |
| 16 witness cfgs | each reached | 4 … 9,675 generated | 4 … 18 |
| 5 `apalache-indinv` cfgs (`CInit`) | pass: `IndInv /\ Next => IndInv'` | Apalache, 4 s to 6 s; `ConfigPush` 312 s | — |
| 7 `witness-trace-*` cfgs | accepted (the whole run consumed) | 8 … 82 states | = events + 1 |
| 5 `reject-*` cfgs | refused | 5 … 34 states | — |

TLAPS: not requested. Engine: `cas-fold-v2` `b78af44d4`; trace build libcubrid `c570e83dfaec…` (optdebug, scratch
worktree of that commit, removed after the runs). Gate builds: optdebug libcubrid `d979d9c5cb9d…`, release
`54fdbec55102…`.

spec sha256:

```
ef1b517e33ee590198b56984ed2036204a6dd4d89a7fa9584c9c6ad4de0f08a1  AclTable.tla
8e2bb5ea614e650e3ab013a17847300c26e6ff39503001dd21526a51c0fa616a  AclTableTrace.tla
b74d9ddc82bd946e1459be1a72698920b73f96204fdd10a0b713eac397085d3c  AclTableTraceData.tla
abf7ecefc7d0bb94f4c4dd5d236d64da9d3102ce483d514c036503dc44604a86  ConfigPush.tla
733397494ed5c0d586754910aaa7bc0b78ef82a804ac65fc375869f0f75b3339  ConfigPushTrace.tla
d80a050cbbdc6b059d3a31e71ec69df5596f30743b82e8a3b323144f35d10bbd  ConfigPushTraceData.tla
5ef1de30e6ec5ad1253df8588eef417c56b93be112894f9990d02ce70948e785  LogLease.tla
585cc729fb450df6b0671fa5ab7e8291fea4f497ecc234463596e517ae018da5  LogLeaseTrace.tla
3d2f9c914e2b422085ef793561c2f33c980710853d50b56923188e1e363e2e35  LogLeaseTraceData.tla
a0c2177f14a2ca35f523a891e4ea53f77bb28d0932408ddef3fb32086abf88de  SslAck.tla
251b11408c9041133799940369418e1458e40b5379320623d8c3531db9e6357d  SslAckTrace.tla
75bcaaaface27f1aedca87672c6849d854876f26d644c00d7eaebe3423a607e4  SslAckTraceData.tla
1ad8552da008e732c89f84cecdc12f89b102ce732c7340976a0ab6d5e23d4a67  StatsKill.tla
c2e9247713df95a112f3429d9784e76e068f5ed651d21e408ccce9c4e1f038a2  StatsKillTrace.tla
048ca96e7f5df4bccabeba04c37ddb3b31357de568a5397b4022d710388897ea  StatsKillTraceData.tla
c125b833db849703bad4a87e5bc559c44349d966bfcf8a9439802e30d0bc967b  AclTable.apalache-indinv.cfg
cc3bc034bb406d5932097390a3b0fe38aaf9c940c3cb0ae5a1ea6517efff2b51  AclTable.cfg
7477b171952ed29282b49c2bbb1062de3b09a5abf6a4eac11bc86453e092629c  AclTable.mutant-check-unlocked.cfg
4e6534b970ac4affea71a21606bc249159ae2acc902a90e5de3ec13d97a05d6f  AclTable.mutant-load-unserialized.cfg
1c4acbc1946c1114162a5886a98201657cd4c1ae5d7fe215e0a27033508a9819  AclTable.scale-3.cfg
560515a99b8b7cb8a0e21fcbc29f40a3930af271b622eff0c5413363f5fef995  AclTable.witness-fail-closed.cfg
d177dd4ec0e50617ffd0ce5d4c137ee1fbc18a566fb05219169c1342389d6140  AclTable.witness-reloaded.cfg
62dfd49675a49922e56a0ee25858c2190aa12b9f2f5925e0e56fbf2e571bbfa6  AclTableTrace.reject-stale-check.cfg
c55b74b289216a8edf7257116ef2fa0a075b795fc47139a4607d2645262691d7  AclTableTrace.witness-trace-acl.cfg
c125b833db849703bad4a87e5bc559c44349d966bfcf8a9439802e30d0bc967b  ConfigPush.apalache-indinv.cfg
8215b6f4362a8408bd58d9cca4968ff9cf4161e466570fdce6232371e7029baf  ConfigPush.cfg
4ba1188e2f76796ca85c0a411eda56c1c004f236a9229aacb663218305aa58f4  ConfigPush.live.cfg
6853fea8841c24e11bd82d22459f025f785201eae0990672e3cbc96d8c30ecff  ConfigPush.mutant-flag-before-write.cfg
b3cdd1f79f21acf639af3c440cd41f22b559a124f155e675eb4e8c525c86f671  ConfigPush.mutant-no-dial-all.cfg
38d0dad9deb5bd9efda991cabd148bcaf01f5b4fbcc916550077a4c36a84fdb7  ConfigPush.mutant-no-latest.cfg
8470c0dc1639a7034aca6a005f3e5c51a0189f39dab0adf153e4f24cb9f33cdf  ConfigPush.mutant-no-seq-order.cfg
b17e99f5a3c240230cdf2cd3dbbe067d4dc7a52fb5f0b0eaf6f4aa689d599d2a  ConfigPush.mutant-read-then-clear.cfg
5fed7d4e36a6c6a46120d9055c9d28a9662d728b6f02c71f5cd7a04aa613856d  ConfigPush.mutant-seq-restart.cfg
7e605615299c69f6ebb4d2688066602603bceb7373356a0081df5a1e5aa0aee5  ConfigPush.mutant-snap-unlocked.cfg
64e776926012694391167b459f603f74b0d999ba986a5fe0662d6695b3bf770d  ConfigPush.scale-v2.cfg
13d1ac9582916e400bdb23181a6c69960dcd89a588d74157c66f2495b90dc910  ConfigPush.witness-applied.cfg
073951871def851f26459e6bda08c36779397ce3fb7257f77bc2e8646f089d6a  ConfigPush.witness-late-older.cfg
9879a60286d220459013b7de37321f4684c07205031eff78af190b5330399258  ConfigPush.witness-partial.cfg
6352b78c2e90054f5eb6b891423e7e109ca0c152d566da12b1400bbb17b1bdcb  ConfigPush.witness-survivor-reached.cfg
ebea4388e5b5fa19a0f5cc08f2564feb7123c57f7ae5bcdd5d63224ff4570ab2  ConfigPushTrace.reject-write-skipped.cfg
010d3f8184ba72735ff32e4ef8a6bfd7a1454143da403375c1c73757a5d65c13  ConfigPushTrace.witness-trace-config.cfg
0bba73b8f2fe6c19dec0ea43475a5df3c0b54c3e2eb386b3e3480960fc725ef7  ConfigPushTrace.witness-trace-restart.cfg
c125b833db849703bad4a87e5bc559c44349d966bfcf8a9439802e30d0bc967b  LogLease.apalache-indinv.cfg
bb3f8aba04a7d133a5cf14db23371a70b16757fbe96dc696eb960bca8738e8e3  LogLease.cfg
f369ad341b6195c9d52cab5ec6069fb31d9675691a777d69861926c1b2002676  LogLease.mutant-no-lease.cfg
b5cfb04e05252796219359e6a7d56f09510b923dfa120a2abb042d6267b92904  LogLease.mutant-release-before-close.cfg
70ee38087de08ffddddf87808da22b57374d35fc506a2aab4e1c16de216d9bcc  LogLease.mutant-release-shares-file.cfg
16d3c4c45031ff5d8424ad75f7304a1b3a984e23430672e6594f241a592332f0  LogLease.scale-4.cfg
427c9e1418dc2473b1c763489633a52a494a230710fe197860d78ff8a40ae12a  LogLease.witness-after-crash.cfg
0f60f6893e3158ec7c10577c876321605d3fa6f8b088a5a861c59cef181878c1  LogLease.witness-reused.cfg
685d0ee50fbfe92acbc87a2e18ad4a44c2e533e50ae3f13e0aafa86c57b7ad86  LogLease.witness-second.cfg
7bf52d11273ccaa1b48848121004be05db177f96c37b14c7580e5da87d0ea67b  LogLeaseTrace.reject-index-twice.cfg
d7cbdf8cbece8e37eaf90399c69050b648e3f0644690de5691773ef4ec7b2534  LogLeaseTrace.witness-trace-lease.cfg
c125b833db849703bad4a87e5bc559c44349d966bfcf8a9439802e30d0bc967b  SslAck.apalache-indinv.cfg
aacefbd95d912b3e4ec619ef8cbe078130949ffdc1925fff5a0d384a5ddd3f3f  SslAck.cfg
0b2e37b3d9de2f9cd0986ba747821b6e3252d732c0779f759ea12d51628592f6  SslAck.mutant-ack-at-park-unheld.cfg
0581b73728780831e35bbe694aef58af31d67b14c83e4be72afdde0f0b16f56b  SslAck.mutant-ack-at-park.cfg
90e7ede61276d9b29137cb1f7a3f04e5b9c7290167d4e8d2e827ed4ee13c5646  SslAck.mutant-ack-before-reply.cfg
c1b7f8e7b76501f7d9603caf70fad67d2de39cf2de7ca39b5a7794751fecf3cc  SslAck.scale-cleartext.cfg
cf3ecea6e1f3c9d15dc06b5563c0f307236b93a7dbaa942f892f336dfeac83fe  SslAck.witness-cleartext-ack-then-err.cfg
6b3bed75a872b7269d821404b3185111002f5cc0029e53c22a923c01f629487c  SslAck.witness-refused-unacked.cfg
37eed5c78175e6f894c301f5e5e02bf0028c2a045a920d47b445ee8360020eaa  SslAck.witness-served.cfg
c8bbd4e34a4e3fc740db3dba928e936d3833657428270ae1e260ea8c53021e4c  SslAck.witness-silent.cfg
b5970d6a63c32171ec9a4dcf2125d8db083c216f01863e8ce7d95cee3e9df8d0  SslAckTrace.reject-ack-first.cfg
242670f05784821f257ecf5f80a70be80240cdd16c1c28141c49e9dfd08be8f1  SslAckTrace.witness-trace-cleartext.cfg
140cf4a0f668d6c8248437f4c93aa3caba59ba9fc323915366d9c6a6ff6e4afb  SslAckTrace.witness-trace-tls.cfg
c125b833db849703bad4a87e5bc559c44349d966bfcf8a9439802e30d0bc967b  StatsKill.apalache-indinv.cfg
92b10095ff5aa57e31b40294a355f8267cc262757856a3cb9fa8b08eb4ce1f52  StatsKill.cfg
d6722b2df9980a277f313f0c1a7a18b0de247581a5165f7307aa7fbd70e93f11  StatsKill.mutant-read-slot.cfg
4910f176c7b7ae3f8ca9aadc4487774af4e7c218a320a5268d0b9fbc80ad75c8  StatsKill.mutant-unpinned-unlocked.cfg
103bc93a4151c312118b3232f9a1022139680b1ec506e581a2805eb6717c46ea  StatsKill.scale-3.cfg
e715ad2e6fae2bccf53d9de38884ab3b73f2c4a7ab7d75c466afb1572986a80e  StatsKill.witness-fd-reused.cfg
c33ba9373263743363d9fd9aa64660919d79e5a6885f98ef6e7ac246681a3d3c  StatsKill.witness-kill-waited.cfg
44a4902f732e79e516c8db81785adf324b795e1d1ab5380143c5d991929125c5  StatsKill.witness-killed.cfg
b3167f701096c5973d3f2d29de05d177e08603570f51479041dca4384a8a720c  StatsKill.witness-read.cfg
fc354b5345bd7422525c61a3e360e608beee856427935f4270708b847e9229a7  StatsKillTrace.reject-torn-row.cfg
d72c534991d9a6af3bc60d90e26127cd8d67dc4cc420fad3839815ec6cb46609  StatsKillTrace.witness-trace-stats.cfg
```
