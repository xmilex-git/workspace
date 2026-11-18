# CBRD-27430 B4 — one broker in front of several databases; the domain cache of a server that runs many sessions

Map [CAS 폴드 재이식 지도](https://github.com/xmilex-git/workspace/issues/618), ticket
[B4 TLA+ 검증·이식 — 다중 DB 토큰·브로커 재시작 회계·도메인 캐시 세션 라우팅](https://github.com/xmilex-git/workspace/issues/635).

Two models, each standalone:

- `TokenTable` — the broker's token table and slot count (`broker_direct.cpp`) over the sessions of several
  servers (`adoption.cpp`): equal tokens of two databases, the count after a broker restart or a channel's
  death, the query cancel.
- `DomainCache` — the process's domain lists and a session's own (`object_domain.c`,
  `client_session_context`), and the end of a session with its connection (`driver_session.cpp`).

The ticket asked for a model that EXTENDS B1a (`Handoff.tla`). B1a's directory has no `RESULT: OK` (its IndInv's
inductiveness was stopped by a user decision) and its state space is 1.29e8 states for one database, so the B4
claims are checked in models of their own: the wire order of one channel, the channel generations of one database
and the descriptor lifetimes stay B1a's (`TokenTable.tla` header says what is abstracted).

Code: fork branch `cas-fold-v2` (worktree `~/dev/cubrid-worktree/cas-fold-v2`), the B4 commits `c0c4d9214` and
`294a73c1a` on `f9e3e6637`.
Old implementation: `cas-merge` @ `cdb9da11e`, B4 commits `7644733f84` … `f6374a89b9` and the fixes the attribution
table assigns (`de53931490`, `0f410d1328`, `d533969e4d`). What B1a, B1b, A4 and A5 had already taken of them
(token multimap, RESYNC survivors, the session's end with its connection, `db_Connect_status`, SHOW metadata) is
not ported again.

## Claim and sources

| # | Claim | Source |
|---|---|---|
| C1 | The sessions of two databases behind one broker may hold equal tokens; a database's SESSION_END and its channel's death change that database's entries only, `slots_used` is the size of the table, and a query cancel interrupts no session but one whose port (when the request carries one) and session id (when the request carries one, or the session's driver always sends one) are the request's — also when the token's thread id went to another session between the broker's lookup and the server's interrupt. A cancel whose request matches the entries of several sessions is sent to none. | ticket C1; old `516d7d6be7` (token multimap), `f6374a89b9` F3 (never an arbitrary session); develop CBRD-27389 (`bc1a91769`, `broker.c` receiver: session id of a QC/X1 cancel and of an ST probe); user decision 2026-11-18 (a session's token is its thread's kernel id, ADR 0064) |
| C2 | `MAX_NUM_APPL_SERVER` bounds the broker's sessions over all its databases: a HANDOFF goes out only while the sessions on every server the broker has not given up leave a slot — also after the broker restarted, or a channel died, and no client asked for that database since. | ticket C2; #117 D3 (slot = the broker's count), D7 (a re-sync restores the count after a broker restart); B1a C1/C4 for one database |
| C3 | A session ends with its driver connection: its open transaction is rolled back (a prepared one stays for its coordinator), its server session and its workspace are gone when its thread is. A kept session (KEEP_CONNECTION=AUTO) is the exception until it is resumed or expires. | ticket C3; old `dc0876dff7` (cas.c's end of a connection); B1b C1–C8 (kept sessions) |
| C4 | No node of the process's domain lists holds a workspace MOP: a domain that refers to a class MOP is cached in lists of the session whose workspace has the MOP, found there again by that session only, one node per domain, and freed after the workspace. | ticket C4; A1 handover (domain interning of bracket threads); old `bb690ac042`, `f6374a89b9` F1; develop's sub-client lists (`object_domain.c` `tp_Sub_client_domains`, CS mode with MULTI_CONN_TO_A_SERVER) |

C3 is by construction in the code that B1b ported (`driver_session_run`'s `retire`); the model keeps it as the
premise of C4 (a workspace is freed while the server runs) with the mutant that removes it.

## Refinement map (model -> code)

`bd` = `src/broker/broker_direct.cpp`, `ad` = `src/connection/adoption.cpp`, `ds` =
`src/connection/driver_session.cpp`, `od` = `src/object/object_domain.c`, `csc` =
`src/object/client_session_context.cpp`.

### TokenTable

| Model | Code | One step because |
|---|---|---|
| `DStart(d, p)` | `bd:brd_dispatch_job` takes the job; `resync_pending.exchange (false)` | the single dispatch thread; one atomic exchange |
| `DScan(e)` | `bd:dial_listening_servers` → `channel_get_or_dial` of one adoption socket: an existing channel, a dial with HELLO and RESYNC (the reader admits the snapshot, `tokens_admit`), a refused connect, or no answer | `dial_mutex`; the admissions under `tokens_mutex` (B1a `DGetCh` … `DResync` in one step: abstraction of this model) |
| `DScanEnd` | the directory is read to its end | dispatch thread |
| `DDial` | `brd_dispatch_job` → `channel_get_or_dial (job's database)`; NULL → `reject_client_no_server` | as `DScan` |
| `DWait`, `DGiveUp` | `bd:brd_wait_for_slot`: `slots_used < max_slots` under `slots_mutex`, or the admission budget ends | under `slots_mutex` |
| `DSendOk(t, sid)` | `channel_request (HANDOFF)`; `ad:handle_handoff` makes the session's thread (`session_thread_run`), registers the session under the thread's id `t` and writes HANDOFF_ACK, then lets the thread run; the reader's `tokens_admit` | B1a `DSend`, `SHReg`, `SHAck`, `RRecv` in one step (abstraction); `sid` is what `ad:registry_set_tran_index` records at the session's login |
| `DSendNo` | HANDOFF_REJECT, or the request on a channel that died since the dial | reply read by the dispatch thread |
| `DSendDead` | the request fails on a channel whose server is gone: `channel_kill`, the reader's `tokens_drop_for_channel` | B1a `DWait` timeout/dead and `RDrop` in one step |
| `SEnd(e, t)` | `ad:registry_session_finished` writes SESSION_END; `bd:tokens_end` erases the entry of this token **and this channel's generation** | under `tokens_mutex`; the END reaches the broker in the step that sends it (abstraction) |
| `SCrash(e)`, `SRestart(e)`, `Hang(e)` | the server process dies, starts, stops answering (SIGSTOP) | process boundary |
| `RDie(e)` | `bd:channel_reader_run`'s `recv` fails: `tokens_drop_for_channel`, `resync_pending.store (true)` when the channel was in the map (a dial that got no answer leaves the flag alone) | under `tokens_mutex`; the flag after the drop (a dispatch that reads it earlier finds the channel in the map or dials) |
| `Kill(e)` | `bd:channel_kill` after a reply timeout, or the server closes the channel; the same drop, the server's sessions go on | as `RDie` |
| `BRestart` | the broker process ends and starts: `bd:brd_init` (`resync_pending` starts true) | process boundary |
| `CnLook(t, q, s)` | `bd:brd_token_channel`: the entries of the token whose ip and port match; two matches → NULL | under `tokens_mutex` |
| `CnSend` | `bd:channel_of_token` (the admitting generation's live channel), `channel_send (CANCEL, session_ref_body)`; `ad:handle_cancel` → `binding_is_named_by` (port and session id against the binding the token has now), `logtb_set_tran_index_interrupt` | `channels_mutex`, `send_mutex`; the server's check under the binding's mutex with the pin (B1a `SCancel`) |

Callers of the entry points (code-index `callers`): `brd_dispatch_job` ← `broker.c:dispatch_thr_f`;
`dial_listening_servers` ← `brd_dispatch_job`, `control_broadcast` (the broker's control thread: the dials it adds
are `DScan` steps of a database before the dispatcher's own, which then finds the channel live);
`brd_cancel`/`brd_status` ← `brd_cancel_reply_async`/`brd_status_reply_async` ← `broker.c:receiver_thr_f`;
`registry_set_tran_index` ← `driver_session_run`; `handle_cancel`, `handle_status` ← `channel_thread_run`.

### DomainCache

| Model | Code | One step because |
|---|---|---|
| `Begin(s)` | `ds:driver_session_run`: `csc_activate`, `db_restart_ex` (the workspace) | the session's thread, inside its bracket (`bracket_mutex`) |
| `Tran(s, x)` | the session's statements | the session's thread |
| `Mop(s, c, a)` | `ws_mop` of a class in the session's workspace | the bracket |
| `ResolveSess(s, c)` | `od:tp_domain_cache` → `tp_domain_cache_for_sub_client` (search with the client's comparator, insert), and `od:tp_domain_find_object` with a MOP (search of the session's list) — both on `csc_current ()->tp_domains` | only the thread that holds the session's bracket reads or writes the session's lists (A4: one bracket holder) |
| `ResolveProc(s, c)` | mutants only: the same domain into `tp_Domains` | — |
| `ResolveOom(s, c)` | no allocation: the lists are arrays of the context | — (the old `f6374a89b9` F1 path does not exist) |
| `FindOid(t, c)` | `od:tp_domain_find_object` with a class OID and no MOP: the walk of `tp_Domains[type]`, lock-free | reads only; the process lists are append-only and never freed |
| `Yield(s)`, `Resume(s)`, `Expire(s)` | `ds`: `registry_auto_finish` (the context stays with its `session_state`), `boot_resume_client` on another thread, `csc_retire_and_delete` from the session-state daemon | B1b's steps; the bracket moves with the context |
| `EndRollback(s)` | `ds` `retire`: `ux_end_tran (ROLLBACK)` unless `is_xa_prepared ()`, `ux_end_session` | the session's thread |
| `WsFinal(s)` | `csc:csc_teardown`: `sm_final` … `ws_final (false)` | inside the bracket |
| `FreeLists(s)` | `csc_teardown`: `tp_free_sub_client_domains ()` after `ws_final` | inside the bracket |

Callers: `tp_domain_cache` and `tp_domain_find_object` are reached from every domain resolution of the parser,
the schema manager, `or_get_domain` (client and server half) and the executor; the routing is by the domain's
content (`tp_domain_list_has_class_mop`) and the thread's bracket, not by the caller. `tp_domain_find_set` takes
the same branch for a set or MIDXKEY domain whose elements hold a MOP (the model's class stands for any such
domain). `tp_free_sub_client_domains` ← `csc_teardown` ← `csc_deactivate` (orphaned context),
`csc_retire_and_delete`.

## Properties

| Property | Model | Kind | Claim |
|---|---|---|---|
| `SlotsMatch`, `TableExact`, `NoOrphan` | TokenTable | invariant | C1 |
| `CancelIsolation` (ghost `wrongCancel`), `NoAmbiguousPick` (ghost `ambPick`) | TokenTable | invariant | C1 |
| `NoOverCap` (ghost `overCap`) | TokenTable | invariant | C2 |
| `Prompt` | DomainCache | invariant | C3 |
| `NoMopInProcess`, `NoUaf`, `NoForeign`, `OwnDomain`, `Interned` | DomainCache | invariant | C4 |
| `TypeOK`, `IndInv` | both | invariants | — |

Every safety property is a conjunct of its model's `IndInv`.

## Fault model

| Fault | Modeled | How / why not |
|---|---|---|
| error return of a send | yes | `DSendDead`, `DSendNo`; a SESSION_END or CANCEL on a channel that is not in sync is lost |
| server crash / `kill -9`, restart | yes | `SCrash`, `SRestart` (tokens from 1) |
| broker crash / restart | yes | `BRestart` |
| reply timeout, a server that does not answer | yes | `Kill`, `Hang`; a database whose server listens and does not answer is given up (`lost`) and its sessions are outside `NoOverCap` until a dial reaches it (bound below) |
| capacity reject | yes | `DSendNo` |
| interrupt / query cancel | yes | `CnLook`, `CnSend` |
| STATUS probe | no | the lookup of a cancel without a port (`brd_status` → `brd_token_channel (NULL, 0)`), no interrupt; its session id check is the cancel's (`binding_is_named_by`) |
| thread creation failure | no | `handle_handoff` rejects (NO_RESOURCES) before anything is registered: `DSendNo` |
| OOM of the session's lists | not applicable | arrays of `client_session_context`; a node is the area allocation of every domain |
| lock timeout, latch, vacuum, checkpoint, HA apply, nested statement | not applicable | no lock, page or snapshot in the mapped code |
| session expiry | yes | `Expire` |
| spurious wakeup | not applicable | `brd_wait_for_slot` and `session_thread_run` wait with predicates |
| concurrent DDL (a class dropped) | no | a dropped class's MOP stays in its workspace until `ws_final`; the node is the session's |

Environment bounds: the broker's client ports of live sessions differ (one TCP peer per connection). A token is
reused only after its thread ended (the kernel); the model lets a server give any token none of its live sessions
has, at once.

## Mutants

| Mutant | cfg | Re-enables | Expected | Claim |
|---|---|---|---|---|
| `no_scan` | `TokenTable.mutant-no-scan` | the dispatcher dials only the job's database (the code before this change) | `NoOverCap` | C2 |
| `map_overwrite` | `TokenTable.mutant-map-overwrite` | a table keyed by the token alone (old code before `516d7d6be7`) | `SlotsMatch` | C1 |
| `end_any_db` | `TokenTable.mutant-end-any-db` | SESSION_END erases the first entry with the token | `TableExact` | C1 |
| `drop_all` | `TokenTable.mutant-drop-all` | a channel's death drops every entry | `TableExact` | C1 |
| `cancel_first` | `TokenTable.mutant-cancel-first` | the first of several matching entries (old code before F3; `brd_status`'s accepted F5) | `NoAmbiguousPick` | C1 |
| `no_sid_check` | `TokenTable.mutant-no-sid-check` | the server interrupts by the token alone (the code before this change) | `CancelIsolation` | C1 |
| `no_port_check` | `TokenTable.mutant-no-port-check` | the port compared by the broker's lookup only (`c0c4d9214`) | `CancelIsolation` | C1 |
| `process_list` | `DomainCache.mutant-process-list`, `-uaf`, `-foreign`, `-wrong` | a MOP domain in `tp_Domains` (the code before this change) | `NoMopInProcess`, `NoUaf`, `NoForeign`, `OwnDomain` | C4 |
| `oom_fallback` | `DomainCache.mutant-oom-fallback` | the process lists when the session's cannot be allocated (old `bb690ac042` before F1) | `NoMopInProcess` | C4 |
| `shared_lists` | `DomainCache.mutant-shared-lists` | develop's sub-client lists as they compile under SERVER_MODE (`CUB_THREAD_LOCAL` is empty there: one set of lists) | `OwnDomain` | C4 |
| `no_match` | `DomainCache.mutant-no-match` | the server's "no match for an object domain" in the session's lists | `Interned` | C4 |
| `free_before_ws` | `DomainCache.mutant-free-before-ws` | the lists freed before `ws_final` | `NoUaf` | C4 |
| `gc_teardown` | `DomainCache.mutant-gc-teardown` | the session left to `session_state_timeout` (old code before `dc0876dff7`) | `Prompt` | C3 |

`cancel_first` alone leaves `CancelIsolation` standing: the server's session id check (`ad:binding_is_named_by`)
restores it for a session whose driver sends its id, so the refusal of an ambiguous lookup has its own property
(`NoAmbiguousPick`); for a driver below PROTOCOL_V13 the refusal is the only protection.

## Witnesses

| cfg | Outcome reached |
|---|---|
| `TokenTable.witness-collide` | two databases' entries with one token |
| `TokenTable.witness-refused` | an ambiguous cancel refused |
| `TokenTable.witness-hit` | a cancel interrupts a session |
| `TokenTable.witness-scan-synced` | after a broker restart the scan re-admitted another database's survivors before the job's dial |
| `TokenTable.witness-held-by-other` | a job waits for a slot only other databases' sessions hold |
| `TokenTable.witness-given-up` | a server given up while it runs sessions |
| `DomainCache.witness-second-own` | a slot's second session has its own node |
| `DomainCache.witness-both` | two sessions each with a node of one class |
| `DomainCache.witness-kept-with-nodes` | a kept session keeps its nodes |
| `DomainCache.witness-xa-left` | a prepared transaction outlives its session |
| `DomainCache.witness-oid-node` | an OID-only node in the process lists |

## Bounds

- TokenTable main: ND = 2, NT = 2, NP = 2, NSid = 1, MaxSlots = 2, MaxConn = 2, one crash, broker restart, kill,
  hang and cancel; scale `scale-sid2`: NSid = 2. Apalache checks `IndInv` for every value of the
  integer constants at `CInit`'s role-set sizes.
- DomainCache main: NS = 2, NC = 2, NA = 2, MaxInc = 2; scale: NS = 3, NA = 3.
- Not in `NoOverCap`: the sessions of a server that listens and did not answer the broker's last dial, or whose
  channel the broker gave up, until a dial reaches it (`lost`). The scan runs once after a channel's death; a
  server that answers again later is dialed by the next client of its database or after the next death.
- A request without a port from a driver that sends no session id (below PROTOCOL_V13) names its session by
  the token and the client address alone, as it did a CAS by its pid.

## Counterexamples (correct variant) and their classification

1. *Surviving mutant: `cancel_first` under `CancelIsolation`.* 1.7e7 states without a violation: the server's
   session id check stops the wrong interrupt. Classified as a missing property, not a hole: `NoAmbiguousPick`
   was added and the mutant violates it (`## Mutants`).
2. *Unreachable witness: `held-by-other` at MaxSlots = 2, MaxConn = 2.* A job waiting for a slot that only other
   databases' sessions hold needs more connections than the slots; the witness cfg runs at MaxSlots = 1.

## Findings

| # | Hole | Model | Fix | Runtime |
|---|---|---|---|---|
| H1 | After a broker restart (or a channel's death) the dispatcher dials only the job's database: the sessions another database's server still runs for this broker are in no table, and a client is admitted over `MAX_NUM_APPL_SERVER` | `TokenTable.mutant-no-scan` (`NoOverCap`) | `resync_pending` + `dial_listening_servers` before the slot wait | pre-change build (`f9e3e6637`, release libcubrid `ad7557d6d3b5…`), MAX = 1, a session of `foldv2b` open over a broker restart: the connect to `foldv2s0` waited 0 s and two sessions ran; after the change it waited 11 s (smoke case 2). The instrumented build with `CUBRID_TLA_B4_NO_SCAN=1` gives the same run (`traces/token-noscan.log`), accepted only as `Mutant = "no_scan"` and ending with `overCap` |
| H2 | A domain that holds a class MOP is cached in the process lists: the node outlives the session's workspace, a later lookup of any thread reads the freed MOP (`WS_OID (dom->class_mop)`), and a session whose MOP gets the freed address is handed the dead node | `DomainCache.mutant-process-list*` | the session's lists (develop's sub-client lists under SERVER_MODE, owned by `client_session_context`) | no crash and no wrong answer in 6 sessions on the pre-change build (the freed MOP is read, not written); shown structurally: the instrumented build with `CUBRID_TLA_B4_OLD_DOMAIN=1` logs the process-list insert of a session's MOP node and, after that session's `ws_final`, `tp_domain_find_object` walks reading it (`traces/domain-olddomain.log`, `walked_dead` in `## Trace validation`) |
| H4 | A token is a thread id: between the broker's lookup (which compares the request's port) and the server's interrupt the session may end and another session of that server get the id; the server interrupted whatever session had the token | `TokenTable.mutant-no-port-check` (`CancelIsolation`), found when the model's tokens were made reusable to fit the recorded runs | the request's port goes to the server (`session_ref_body.client_port`) and `binding_is_named_by` compares it under the binding's mutex | not reproduced: it needs a thread id reused within the cancel's round trip. The same window exists on develop between `broker.c`'s port check and `kill (pid)` |
| H3 | The fold dropped the session id of a QC/X1 cancel and of an ST probe (develop CBRD-27389 checks it in `broker.c` for a CAS): any client of the same address interrupts a session by its token | `TokenTable.mutant-no-sid-check` (`CancelIsolation`) | `session_ref_body` carries the id to the server, `ad:binding_is_named_by` | instrumented build with `CUBRID_TLA_B4_NO_SID=1`: a hand-written cancel with another session id interrupts the statement (`traces/token-nosid.log`, accepted only as the mutant); without the knob the statement runs to its end (smoke case 5) |

Not model findings, found by the port's smoke: a broker's rejection after the header's ack was a bare code a
cleartext driver read as a length (JDBC -21112; now the connect reply's frame, -677 for a server that is down);
the 16 MiB request bound refused a 20 MiB bound string (-21003; now 1 GiB); and the B3 refusal code is not one a
JDBC driver goes to its next altHost on (ticket
[세션 수립 거절 응답](https://github.com/xmilex-git/workspace/issues/650)).
