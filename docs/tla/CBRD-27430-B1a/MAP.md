# CBRD-27430 B1a — the broker hands a driver connection to the server that runs its session

Map [CAS 폴드 재이식 지도](https://github.com/xmilex-git/workspace/issues/618), ticket
[B1a TLA+ 검증·이식 — 브로커→서버 세션 핸드오프](https://github.com/xmilex-git/workspace/issues/631). The broker
(`broker_direct.cpp`) keeps one control channel per database on the server's adoption socket (`adoption.cpp`); its
dispatch thread hands each driver connection over with SCM_RIGHTS, its channel reader applies the slot accounting
in wire order, and a query cancel travels as a token. The server registers each adopted session under a token, runs
it on its own thread (`driver_session.cpp`, the folded CAS loop) and announces its end with SESSION_END. The model
checks the handoff protocol and the lifetimes around it; the folded CAS request loop itself is the A-stages' model.

Code: fork branch `cas-fold-v2` (worktree `~/dev/cubrid-worktree/cas-fold-v2`), B1a commit on `c9cbc3519`.
Old implementation: `cas-merge` @ `cdb9da11e`, the B1 PR series `dc6ec348da`…`2184adc76a` and the later B1 fixes the
attribution table assigns, in particular `c49af22e82` (wire-order admission, generation-scoped drop, RESYNC under
`send_mutex`) and the B4 `516d7d6be7` token multimap. The old behaviors are the model's mutants (`## Mutants`).
AUTO detach/resume and its executor pool (`8eff88291c`…) are B1b; the binding pin/drain came with them and is taken
here only as the cancel's pin.

## Claim and sources

| # | Claim | Source |
|---|---|---|
| C1 | The broker's handoff slots are the live sessions it handed over: at rest every slot (token) belongs to a live session of this server, every live session of the broker holds one once the database's channel is re-synced, and `slots_used` is the size of the token table — across server restarts, broker restarts (re-sync survivors) and channels killed by a reply timeout. One SESSION_END releases exactly one slot. | #117 D3 (slot = broker count, SESSION_END +1), D7 (channel death resets, RESYNC restores); #138 B1-D8, codex F1/F2/F7; ticket C1 ("SESSION_END 1회에 정확히 1 반환, 재시작 생존자 포함"); workspace#265 axis 3 (`c49af22e82` message) |
| C2 | No descriptor is shut down or written after its owner closed it (the number may be reused): the broker's control fd after its reader closed it, a driver fd stop() reaches through the registry. | ticket C2; codex F4/F6 (`2184adc76a`); B1 review `5aeb5c377c` (registry entry dropped before the fd closes) |
| C3 | A query cancel interrupts only the session whose token the broker looked up: not another session that took the same transaction index after the target released it, nor a session of a restarted server that reuses the token value. | #117 D4 (anti-spoof token table, interrupt by token); ticket C3; B4 `516d7d6be7` (equal tokens of different server processes behind one broker) |
| C4 | A database whose server is not listening is a retryable rejection at once; a driver waits only while every slot is taken, and a HANDOFF goes out only while a slot is free counted after the channel's re-sync. | #121 D5 (no server: immediate retryable reject, queue only when full); #117 D3 (`MAX_NUM_APPL_SERVER` = handoff slots); ticket C4 |
| C5 | `stop()` frees the manager only when no session, sign-off or channel handler of this server can touch it afterwards. | codex F2/F3 (`2184adc76a`); ticket C5 |

Claims C1–C5 are the ticket's candidates; none needed a user decision (the sources fix each). The protocol changes
the model forced (`## Findings`) keep every sourced behavior.

## Refinement map (model -> code)

Code at the B1a commit; `bd` = `src/broker/broker_direct.cpp`, `ad` = `src/connection/adoption.cpp`, `ds` =
`src/connection/driver_session.cpp`.

| Model | Code | One step because |
|---|---|---|
| `DStart` | `bd:brd_dispatch_job` takes the job's peeked db_info (`db_info_mutex`) | the single dispatch thread (`broker.c:dispatch_thr_f`) |
| `DGetCh` (published) | `bd:channel_get_or_dial` finds the map's live channel (`dial_mutex`, `channels_mutex`) | under `channels_mutex` |
| `DGetCh` (dial) | `channel_get_or_dial`: `connect`, `generation = next_channel_gen++`, reader thread started, HELLO written by `channel_request` (`send_mutex`) | the dial is `dial_mutex`-single-flight; HELLO is the first byte on the new socket |
| `DGetCh` (no server) | `connect` fails (no listener, or the listen socket closed by `stop`) → `send_error_code_to_driver (CAS_ER_FREE_SERVER)` | one syscall |
| `DHello` | `channel_request (HELLO)` returns HELLO_ACK; `channel_request (RESYNC)` writes RESYNC under `send_mutex` | the mailbox read and the next write are on the requesting thread |
| `DResync` | RESYNC_REPLY returned; `if (ch->dead) return NULL; m.channels[db] = ch` under `channels_mutex` | under `channels_mutex` |
| `DDialFail` | HELLO/RESYNC request failed or timed out → `channel_kill` (dead, `shutdown (ch.fd)` under `send_mutex` only while `fd >= 0`) | under `send_mutex` |
| `DAdmit` | `slots_cv.wait_for (slots_used < max_slots || stopping)` under `slots_mutex`; timeout → `CAS_ER_FREE_SERVER` | under `slots_mutex` |
| `DSend` | `channel_request (HANDOFF, fd)`: one `sendmsg` with SCM_RIGHTS under `send_mutex` (`fd_transferred`) | under `send_mutex` |
| `DWait` | the reply wait: HANDOFF_ACK / REJECT in the mailbox, the channel dead, or the 5 s timeout → `channel_kill` | `reply_mutex`; the kill under `send_mutex` |
| `RRecv(c)` ACK, RESYNC_REPLY | `bd:channel_reader_run` → `tokens_admit` (`tokens_mutex`, `slots_add` under `slots_mutex`), then the mailbox | admission happens before the reply is visible (wire order) |
| `RRecv(c)` END | `channel_reader_run` → `tokens_end`: erase the entry with this token **and this channel's generation** | under `tokens_mutex` |
| `RDie(c)` | reader `recv` fails: `dead.store`, close under `send_mutex`, erase from `channels` | the dead flag first; the map erase is the publication `DGetCh` reads |
| `RDrop(c)` | `tokens_drop_for_channel`: erase every token of this generation, release its slot | under `tokens_mutex` |
| `CnLook` | `bd:brd_token_channel`: token table lookup with the ip/port anti-spoof check | under `tokens_mutex` |
| `CnSend` | `channel_of_token` (the admitting generation's channel, never a dial) → `channel_send (CANCEL)` | `channels_mutex`, then `send_mutex` |
| `SAccept(c)` | `ad:accept_thread_run`: reap dead channels, `id = next_channel_id++`, insert, start the channel thread | under `channels_mutex`; `accept` takes the backlog in connect order |
| `SRecv(c)` | `ad:channel_thread_run` reads one message; HELLO: name, `latest_channel[name] = max (…, id)` under `channels_mutex`, HELLO_ACK | one thread per channel handles its messages in order |
| `SEof(c)` | channel thread `recv` fails: close and `fd = -1` under `send_mutex`, `dead` | under `send_mutex` |
| `SResync(c)` | `ad:handle_resync`: holding `send_mutex`, snapshot this broker's registry entries (`registry_mutex`) and write RESYNC_REPLY | both mutexes held (`send_mutex` → `registry_mutex`) |
| `SHCheck(c)` | `ad:handle_handoff`: `stopping`, db name, binding allocation, `css_increment_num_conn` | thread-local until the registry |
| `SHReg(c)` | registry insert under `registry_mutex`, re-reading `stopping` there | under `registry_mutex` |
| `SHAck(c)` | HANDOFF_ACK (`resync_token_body`) under `send_mutex`; on failure the adoption is undone like a session end (cleanup, refund, `registry_session_finished`, close) | under `send_mutex` |
| `SHSpawn(c)` | `std::thread (driver_session_run)` | the thread start |
| `SCancel(c)` lookup | `ad:handle_cancel`: registry lookup (`registry_mutex`), `binding_pin` (`users++` unless `closing`, copy `tran_index`) | under the binding mutex |
| `SCancel(c)` interrupt | `logtb_set_tran_index_interrupt (pin.tran_index)`, pin destructor | the pin holds the index |
| `SLogin(s)` | `ds:driver_session_run` → `registry_set_tran_index` (binding mutex) after `db_restart_ex` registered the transaction | under the binding mutex |
| `SEnd(s)` | `ad:registry_begin_session_cleanup`: `closing = true` (the driver closed, or `stop` shut the fd) | under the binding mutex |
| `SClean(s)` | the same call waits `users == 0`, clears `tran_index`/`client_fd`; `boot_unregister_client` releases the index after | the wait returns under the binding mutex; no pin can reach the index afterwards |
| `SErase(s)` | `ad:registry_session_finished`: `active_finishers++`, erase under `registry_mutex` | under `registry_mutex` |
| `SPick(s)` | the broker's newest channel `latest_channel[name]` looked up in `channels` | under `channels_mutex` |
| `SSendEnd(s)` | SESSION_END under that channel's `send_mutex` (fd checked), `active_finishers--` | under `send_mutex` |
| `SClose(s)` | `ds`: `close (params.client_fd)` after the sign-off | one syscall |
| `StopBegin` … `StopFree` | `ad:stop`: `stopping`, listen close + accept join; channel `shutdown`s; registry walk with pins (fd shutdown, interrupt); drain wait (`shutdown_wait_time_in_secs`); `active_finishers == 0`; map swapped out and joined; `delete` | one step per lock region |
| `SCrash`, `SRestart` | server process death and restart (tokens restart at 1) | process boundary |
| `BRestart` | broker process death (`broker.c:cleanup` → `exit`) and restart; adopted sessions survive | process boundary |

Callers of the protocol entry points (code-index `callers` at the B1a commit): `brd_dispatch_job` ←
`dispatch_thr_f`; `brd_cancel`/`brd_status` ← `brd_cancel_reply_async`/`brd_status_reply_async` ←
`receiver_thr_f` (QC/ST, on detached threads); `registry_session_finished` ← `driver_session_run` (both exits) and
`handle_handoff` (undo); `registry_begin_session_cleanup` ← the same three sites; `adoption::stop` ← `css_init`'s
shutdown path (`server_support.c`).

## Properties

| Property | Kind | Claim |
|---|---|---|
| `NoLeak` | invariant (at rest: `Quiescent`) | C1 |
| `NoUndercount` | invariant (at rest, a published channel) | C1 |
| `SlotsMatch` | invariant | C1 |
| `NoBadFd` | invariant (ghost `badFd`) | C2 |
| `CancelIsolation` | invariant (ghost `wrongCancel`) | C3 |
| `NoOverCap` | invariant (ghost `overCap`: a HANDOFF sent while the live channels' tokens fill every slot) | C4 |
| `NoUseAfterFree` | invariant (ghost `uaf`) | C5 |
| `TypeOK`, `IndInv` | invariants | — |

C4's "retryable at once" is by construction (`DGetCh` no-server branch, witness `noserver`), "waits only while
full" likewise (`DAdmit`, witness `full`).

## Fault model

| Fault | Modeled | How / why not |
|---|---|---|
| error return of a send | yes | `SrvSendOk`/`BrkSendOk` decide every send from the peer's state (EPIPE once the reader is gone or shut) |
| server crash / `kill -9` | yes | `SCrash` at any point outside `stop`; `SRestart` (tokens from 1) |
| broker crash / restart | yes | `BRestart` at any point |
| reply timeout | yes | `DWait`, `DDialFail` timeout branches kill the channel |
| capacity reject (`css_increment_num_conn`) | yes | `SHCheck` reject branch (also the db-name and allocation rejects) |
| server stop | yes | `StopBegin`…`StopFree` |
| interrupt / cancel | yes | `CnLook`/`CnSend`/`SCancel` |
| protocol violation (bad magic, oversize) | as a channel death | the reader breaks its loop: `RDie`/`SEof` |
| thread creation failure | no | `SHSpawn` failure takes the undo path of `SHAck`'s failure branch (same code) |
| OOM in the broker's dial | no | the dial returns NULL before anything is shared (`DGetCh` no-server outcome) |
| STATUS probe | no | a request/reply on the channel whose only effect on the claims is its timeout kill (modeled) |
| a second broker of the same name | no | broker names are unique (`broker_shm`) |
| crash during `stop` | no | the process exits either way; `stop` frees nothing a later step reads |
| spurious wakeup | no | every wait re-checks its predicate (`std::condition_variable::wait_for` with predicate) |

## Mutants

| Mutant | cfg | Re-enables (old code) | Expected | Claim |
|---|---|---|---|---|
| `end_by_entry` | `mutant-end-by-entry` | SESSION_END to the entry's own channel, any live channel only when it left the map (`cdb9da11e` `registry_session_finished`) | `NoLeak` | C1 |
| `end_any_gen` | `mutant-end-any-gen` | `tokens_end` matching the database, not the generation (`cdb9da11e`) | `NoLeak` | C1 |
| `resync_unlocked` | `mutant-resync-unlocked` | snapshot and reply apart (`2184adc76a`, before `c49af22e82` D3) | `NoLeak` | C1 |
| `ack_after_spawn` | `mutant-ack-after-spawn` | the session started before its ACK (before codex F1) | `NoLeak` | C1 |
| `ack_ignored` | `mutant-ack-ignored` | the ACK's send result ignored (`(void) send_message`, every old version) | `NoUndercount` | C1 |
| `hello_fail_shutdown` | `mutant-hello-fail-shutdown` | `shutdown (fd)` on the dialed number after a failed HELLO/RESYNC (`cdb9da11e`) | `NoBadFd` | C2 |
| `close_before_erase` | `mutant-close-before-erase` | the driver fd closed before the registry erase (before `5aeb5c377c`) | `NoBadFd` | C2 |
| `cancel_by_db` | `mutant-cancel-by-db` | CANCEL on the database's current channel (`cdb9da11e` `brd_cancel` → `channel_get_or_dial`) | `CancelIsolation` | C3 |
| `no_pin` | `mutant-no-pin` | the registry's tran index copied without a pin, cleared never (`2184adc76a`) | `CancelIsolation` | C3 |
| `admit_before_dial` | `mutant-admit-before-dial` | the slot wait before the dial and its RESYNC (every old version) | `NoOverCap` | C4 |
| `no_stop_recheck` | `mutant-no-stop-recheck` | registration without re-reading `stopping` under `registry_mutex` (every old version) | `NoUseAfterFree` | C5 |
| `no_finisher_wait` | `mutant-no-finisher-wait` | `stop` not waiting for `active_finishers` (before codex F2) | `NoUseAfterFree` | C5 |

## Witnesses

| cfg | Outcome reached |
|---|---|
| `witness-acked` | a driver handed over and acknowledged |
| `witness-cancelled` | a cancel interrupts its target |
| `witness-timedout` | a reply timeout kills a channel |
| `witness-noserver` | no listening server: immediate retryable rejection |
| `witness-full` | a driver turned away after waiting for a slot |
| `witness-readmitted` | a RESYNC re-admits surviving sessions |
| `witness-stoppedclean` | `stop` frees the manager after draining a session |
| `witness-undone` | an adoption whose ACK the broker no longer reads is undone |

## Counterexamples (correct variant) and their classification

1. *Candidate design: undo without SESSION_END.* The first fix for `ack_ignored` undid the adoption silently. TLC:
   broker restart while the HANDOFF is in flight; the new channel's RESYNC snapshots the registered session; the
   ACK on the dead channel fails and the undo erases the session without an END — the new broker's slot leaks
   (`NoLeak`). Classified as a hole of the candidate; the undo now goes through `registry_session_finished`.
2. *Candidate design: re-homing the snapshot's entries to the re-syncing channel.* TLC: the old broker's RESYNC,
   still unread on its channel when the broker restarts, is answered after the new channel's; it re-homes the
   session to the dead channel and its END is lost (`NoLeak`). Classified as a hole of the candidate; SESSION_ENDs
   now go to the broker's newest channel (`latest_channel`), so no per-session channel is kept.
3. *Model error: `SCrash` narrowed by an UNCHANGED.* A bulk edit put `latest` in `SCrash`'s UNCHANGED next to
   `latest' = 0`, so a crash could only happen before the first HELLO; `mutant-cancel-by-db` survived 60 levels.
   Found by a reachability probe (cubrid-tla P58); the main cfg was rerun after the fix.

## Findings

Old-implementation holes, each a mutant that the properties reject; the B1a port carries the fix.

| # | Hole (old code) | Counterexample | Fix in B1a | Runtime |
|---|---|---|---|---|
| H1 | SESSION_END to the entry's channel while it is still in the server's map (dead but not reaped) — a broker that re-synced the session on its next channel never gets the END: the slot leaks | `mutant-end-by-entry` | END to the broker's newest channel (`latest_channel`) | not reproduced (needs the old channel unreaped at the new accept) |
| H2 | `tokens_end` by database: after a server restart an END for token value 1 removes the dead incarnation's entry and leaves the live one | `mutant-end-any-gen` | match the generation | not reproduced |
| H3 | `brd_cancel` sends on the database's current channel (dialing if needed): a stale token of a crashed server interrupts the restarted server's session with the same value | `mutant-cancel-by-db` | the admitting generation's live channel, no dial | not reproduced |
| H4 | the cancel copies the registry's tran index and interrupts after unlocking (B1 PR state): the index may belong to another session by then | `mutant-no-pin` | binding pin/drain (from the old AUTO commit `8eff88291c`) | not reproduced |
| H5 | failed HELLO/RESYNC: `shutdown (fd)` on the dialed number after the reader may have closed it | `mutant-hello-fail-shutdown` | `channel_kill` (under `send_mutex`, `fd >= 0`) | not reproduced |
| H6 | a HANDOFF whose `stopping` check passed before `stop` registers after the drain: its session runs on a freed manager | `mutant-no-stop-recheck` | re-read `stopping` under `registry_mutex` | not reproduced |
| H7 | the ACK's failure is ignored: a session the broker gave up (reply timeout) runs unaccounted until the next re-sync | `mutant-ack-ignored` | undo the adoption through the sign-off path | not reproduced |
| H8 | admission before the dial: after a broker restart the first driver is admitted before the RESYNC counts the survivors — more sessions than `MAX_NUM_APPL_SERVER` | `mutant-admit-before-dial` | dial first, then wait for a slot | reproduced on the instrumented build (`CUBRID_TLA_B1A_OLD_ADMIT=1` restores the old order): MAX=1, one session survives a broker restart, the next driver was admitted after 0 s and two sessions ran; the fixed order kept it waiting 19 s until the survivor ended. The old-order run is `traces/oldadmit.log`, accepted only with `Mutant = "admit_before_dial"` (`HandoffTrace.witness-trace-oldadmit-mutant`) |

## Dead expressions

Lines of `Handoff.tla` the main and scale cfgs (`Mutant = "none"`) never evaluate:

- `Handoff.tla:390` — the `OTHER` arm of `SRecv`'s CASE. A broker writes only HELLO, HANDOFF, CANCEL and RESYNC on a
  channel (`DGetCh`, `DHello`, `DSend`, `CnSend`), so no other message reaches the server's reader; the arm is the
  code's `default:` that drops an unknown message.
- `Handoff.tla:413`, `Handoff.tla:414` — `SResync`'s snapshot-first step, taken only under `Mutant = "resync_unlocked"`
  (evaluated 43,860 times in `mutant-resync-unlocked`).
- `Handoff.tla:459`, `Handoff.tla:461` — `SHAck`'s "send failed, carry on" branch, taken only under
  `Mutant \in {"ack_ignored", "ack_after_spawn"}` (23,938 and 5,837 times in those cfgs).
- `Handoff.tla:523`, `Handoff.tla:524` — `SEnd` without the cleanup step, taken only under `Mutant = "no_pin"`
  (1,044,298 times in `mutant-no-pin`).
- `Handoff.tla:554`, `Handoff.tla:556`, `Handoff.tla:557` — `SPick` choosing the entry's own channel or any live one,
  taken only under `Mutant = "end_by_entry"` (142,246 / 7,803 / 3,443 times in `mutant-end-by-entry`).

## Bounds

Main: `J = 2` drivers, `MaxSlots = 1`, `NT = 1` transaction index, `MaxConn = 3` channel connections, one each of
server crash, broker restart, reply timeout and cancel, and a server stop. Scale (`scale-slots2`): `MaxSlots = 2`, `NT = 2`, the
rest as the main cfg.

IndInv has 64 conjuncts (`Inv01`–`Inv64`) and is in the INVARIANTS of the main and scale cfgs, so TLC checks every
conjunct on every reachable state at those bounds. Its inductiveness (`HandoffInd.apalache-indinv`: Apalache, `J = 2`,
`MaxConn = 3`, `NT = 1`, every `MaxSlots` and fault budget) is **not established**: the check was stopped on
2026-11-09 by the user's decision to close B1a on TLC and trace validation. At the stop, checked per conjunct group
with `tools/tla/apalache-split` (each `IndInv => Group'`):

- passed: `Inv01 02 05 07 08 09 10 11 12 15 17 18 19 21 25 26 27 28 29 31 32 33 35 36 37 38 39 40 41 42 44 45 46 47 48 49
  51 53 55 56 57 58 59 60 61` (45);
- `Inv22`, `Inv23` passed on 3 of 8 transition classes (index ≡ 0, 4, 6 mod 8 of Next's 76 transitions);
- not settled: `Inv03 04 06 13 14 16 20 24 30 34 43 50 52 54 62 63 64` and the rest of `Inv22`, `Inv23` — runs out of
  their 3–4 h budgets with no counterexample, or a counterexample from a state no behavior reaches that the next
  strengthening was not yet run against: a RESYNC queued ahead of a CANCEL and a HANDOFF on one channel (the code sends
  HANDOFF and CANCEL only after the RESYNC was answered), and for `Inv22` a signing-off session of incarnation 0 (excluded
  by `Inv64`, not rerun).

Every counterexample the Apalache runs produced came from such an unreachable state (stale handler fields, a message
shape no sender builds, a request queued behind an unanswered HELLO, a session of a crashed incarnation); none was a
step the code can take from a reachable state, and each added conjunct passed TLC's reachable-state check before it
was kept.

## Trace validation

Instrumented build: worktree `cas-fold-v2-tla1a` = engine `b8696c5bb` (tree identical to the squashed B1a commit
`99c251107`) plus `TLATRACE` lines at every mapped site (`.git_ignored_dir/scratch/fold-v2/b1a/instrument.py`),
optdebug install `CUBRID-cas-fold-v2-tla1a`, `libcubrid.so.11.5` sha256 `edd04ea717fd8447…`. Both processes append to
one file; `events.py` sorts by `CLOCK_MONOTONIC` (a sender's event carries the time taken before its send) and renames
channel generations, tokens and transaction indices to the model's; `trace2tla` writes `HandoffTraceData.tla`.

| Run | Scenario | Lines | Cfg | Verdict |
|---|---|---|---|---|
| `basic.log` | three drivers, two JDBC cancels of a running query, a broker restart, server stop at the end | 86 | `witness-trace-basic` | accepted |
| `survivor.log` | a session survives two broker restarts (each RESYNC re-admits it), server stop | 67 | `witness-trace-survivor` | accepted |
| `stopopen.log` | server stop with an open session (drain, finisher wait, join, free); drivers after the stop find no server | 41 | `witness-trace-stopopen` | accepted |
| `oldadmit.log` | H8 on the old admission order | 67 | `witness-trace-oldadmit-mutant` (Mutant `admit_before_dial`) | accepted |
| `reject-spawn-before-ack.log` | `basic.log` with a session thread started before its HANDOFF_ACK | 86 | `reject-spawn-before-ack` | refused |
| `reject-admit-before-dial.log` | `basic.log` with the admission moved before the dial | 86 | `reject-admit-before-dial` | refused |
| `reject-end-old-channel.log` | `survivor.log` with a SESSION_END sent on the channel the broker had replaced | 67 | `reject-end-old-channel` | refused |

The accepted runs log 37 of the model's actions. Not in any run: `DDialFail` (HELLO or RESYNC failure), `SCrash`,
`SRestart` (a `kill -9` of the server and its restart) and `Terminating`; these are checked by TLC only. The second
step of a cancel that found no transaction is hidden (`HandoffTrace!Hidden`): the code logs no interrupt there.

## Result

- Date: 2026-11-09 (TLC, trace), closed 2026-11-10. **No directory-level `RESULT: OK`**: IndInv's inductiveness
  (`HandoffInd.apalache-indinv`) is not established (`## Bounds`), by the user's decision of 2026-11-09 to close B1a on
  TLC and trace validation ("tlaps 하지말고 tlc - trace 쪽만 하고 완료해"). The Apalache cfg stays in the directory
  expecting pass, so `tools/tla/tla-check docs/tla/CBRD-27430-B1a` does not print `RESULT: OK`.
- TLC and trace cfgs: 29 of 29 got the expected verdict, in two `--only` runs on the spec below —
  `--only Handoff` (run dir `.git_ignored_dir/scratch/tla/CBRD-27430-B1a-20261109-130721-899875`) and
  `--only 'Handoff[!I]*'` (`…-20261109-130723-900074`). Both ended `RESULT: PARTIAL (… 1 failed)`; the one failure
  in each was the main / scale cfg's dead expressions not yet explained in this file (`## Dead expressions`, written
  2026-11-10; the check is the presence of each `Handoff.tla:<line>` here, confirmed by grep, the cfgs were not rerun).
- Per cfg (states generated / distinct, depth):

```
Handoff expect=[pass] got=[pass] states=352787419/69893809 depth=75 8290s dead-expr-lines=390,413,414,459,461,523,524,554,556,557
Handoff.mutant-ack-after-spawn expect=[violation NoLeak] got=[violation NoLeak] states=2146987/539083 depth=28 21s
Handoff.mutant-ack-ignored expect=[violation NoUndercount] got=[violation NoUndercount] states=14065669/3469864 depth=37 99s
Handoff.mutant-admit-before-dial expect=[violation NoOverCap] got=[violation NoOverCap] states=2223186/569300 depth=29 30s
Handoff.mutant-cancel-by-db expect=[violation CancelIsolation] got=[violation CancelIsolation] states=77002898/16756330 depth=47 353s
Handoff.mutant-close-before-erase expect=[violation NoBadFd] got=[violation NoBadFd] states=927132/239653 depth=23 10s
Handoff.mutant-end-any-gen expect=[violation NoLeak] got=[violation NoLeak] states=35330180/8080128 depth=42 429s
Handoff.mutant-end-by-entry expect=[violation NoLeak] got=[violation NoLeak] states=12037567/2974312 depth=36 125s
Handoff.mutant-hello-fail-shutdown expect=[violation NoBadFd] got=[violation NoBadFd] states=828/501 depth=7 4s
Handoff.mutant-no-finisher-wait expect=[violation NoUseAfterFree] got=[violation NoUseAfterFree] states=2099916/509241 depth=28 36s
Handoff.mutant-no-pin expect=[violation CancelIsolation] got=[violation CancelIsolation] states=88385293/18933938 depth=48 649s
Handoff.mutant-no-stop-recheck expect=[violation NoUseAfterFree] got=[violation NoUseAfterFree] states=1664431/415524 depth=25 28s
Handoff.mutant-resync-unlocked expect=[violation NoLeak] got=[violation NoLeak] states=17740714/4290980 depth=39 110s
Handoff.scale-slots2 expect=[pass] got=[pass] states=685487753/128957407 depth=75 12714s dead-expr-lines=390,413,414,459,461,523,524,554,556,557
Handoff.witness-acked expect=[violation NotAcked] got=[violation NotAcked] states=415726/117768 depth=20 5s
Handoff.witness-cancelled expect=[violation NotCancelled] got=[violation NotCancelled] states=1548538/387694 depth=26 10s
Handoff.witness-full expect=[violation NotFull] got=[violation NotFull] states=825947/215444 depth=23 6s
Handoff.witness-noserver expect=[violation NotNoServer] got=[violation NotNoServer] states=81/53 depth=5 2s
Handoff.witness-readmitted expect=[violation NotReadmitted] got=[violation NotReadmitted] states=1786259/446667 depth=26 12s
Handoff.witness-stoppedclean expect=[violation NotStoppedClean] got=[violation NotStoppedClean] states=4041864/1029634 depth=31 20s
Handoff.witness-timedout expect=[violation NotTimedOut] got=[violation NotTimedOut] states=50247/18149 depth=15 2s
Handoff.witness-undone expect=[violation NotUndone] got=[violation NotUndone] states=304010/89428 depth=20 4s
HandoffTrace.reject-admit-before-dial expect=[pass] got=[pass] states=4/2 depth=2 1s
HandoffTrace.reject-end-old-channel expect=[pass] got=[pass] states=57/56 depth=56 2s
HandoffTrace.reject-spawn-before-ack expect=[pass] got=[pass] states=18/16 depth=16 1s
HandoffTrace.witness-trace-basic expect=[violation TraceNotDone] got=[violation TraceNotDone] states=91/87 depth=87 2s
HandoffTrace.witness-trace-oldadmit-mutant expect=[violation TraceNotDone] got=[violation TraceNotDone] states=70/68 depth=68 2s
HandoffTrace.witness-trace-stopopen expect=[violation TraceNotDone] got=[violation TraceNotDone] states=46/42 depth=42 2s
HandoffTrace.witness-trace-survivor expect=[violation TraceNotDone] got=[violation TraceNotDone] states=70/68 depth=68 2s
```

- TLAPS: 요청 없음.
- Spec sha256 (from the runs' summary; MAP.md changed afterwards):

```
744aef9b94f45274f2342300264e25e2a18de557525807bcc5fe3b5f255b5fb1  Handoff.tla
72517f6e46c7a1dc180cf56cc885044906f7dd6fc585e3b184bc131d024c7743  HandoffInd.tla
1ff694d381f7e6b7a2309b672714f73aeefe5cf8d7be9f7ee946df634c211b41  HandoffTrace.tla
76d9ede7205b896ae698ae509259158928be9b711193102bbded71a3cf0ff4f8  HandoffTraceData.tla
e3d21d8853139db012e3016acdfee9e62fbe723e61a438428115f8b0f7693751  Handoff.cfg
e9c2c36c1f0303998a5bc94515f192c25d2121f22dad2abe21c1e3ba83bad647  Handoff.mutant-ack-after-spawn.cfg
484486f0bc5e401956067a4eef964c005e3b31ecfca9663feca11c1eca10ca55  Handoff.mutant-ack-ignored.cfg
f472ddc8435655d1970df8d7c945644eb8374120e5889f0a9c327eb8a2bd9499  Handoff.mutant-admit-before-dial.cfg
963ac9fc52e4eeb077edc3bb96a08b7c8f63c2d2fc777e5ec2d46420a5a89788  Handoff.mutant-cancel-by-db.cfg
da333535e1df1cc437981945586c3cd468b356263b6065e897accabbc4e5d68b  Handoff.mutant-close-before-erase.cfg
17c1b492f94a5ebb16202ada3c3393cf90d569f4e1759abe880c4f14eaf8f8a2  Handoff.mutant-end-any-gen.cfg
f201780eb084c030f7b9516b00c53cd95d3a7b0cd0e8b65b3b6c20eec7f5768f  Handoff.mutant-end-by-entry.cfg
09d20e8101b7148f6dc2eeee25d0baf1140df20db261afbd375c6b1c37932fbe  Handoff.mutant-hello-fail-shutdown.cfg
70003838f89e1b8c89932566ba09784abcc7cfefae6d3913467c291784e126c5  Handoff.mutant-no-finisher-wait.cfg
ec7b1690104b7479e569888bcb671941a19fa9462aacda47928e0afa9822a831  Handoff.mutant-no-pin.cfg
c4ab818975067faf5916ec1d5993c8287b04899fd20becf71b6dff8c836a21da  Handoff.mutant-no-stop-recheck.cfg
f6465470a53578a25c877d49677a1ad0a7b4071da65b1dce5193288d3ea01a9c  Handoff.mutant-resync-unlocked.cfg
83670b5d4ee15edc1bb15005e86a5cbeab84ae8e8aadab0c3880943192cc90a2  Handoff.scale-slots2.cfg
c0790c4622dbd3eb365929c7ddca9460a6a3e28b04a392d91ace66b4fddb9b52  Handoff.witness-acked.cfg
7a817abcd0ba9d92bd4c8a03fe3617a866ac110eac5d9af1aa75d02c7cacb83e  Handoff.witness-cancelled.cfg
82cca716be23303c2ea88e5047c0ec0b1e1490c6bd29afd788b48af6a3f6c253  Handoff.witness-full.cfg
ff45f96c2dc13146e6798f6d0ba38ff75b1d3b9a92e4bc952c80519f86a473ea  Handoff.witness-noserver.cfg
60bead0d6814601a573badd5b02134bcc1f8e9f6f687818784edfede206ea376  Handoff.witness-readmitted.cfg
087e18f67f146718c3f6f25959572d90b18a00b186fa104c2933697ee4e25ec5  Handoff.witness-stoppedclean.cfg
ebae1c1b8bc6cf46d21bfbec3c2437b833c45051520c014b3ca7fb91f5ca8604  Handoff.witness-timedout.cfg
df044843ed1293e0982f012e6efbf3d6fe5c799b62733f4f89b0af398467a7a2  Handoff.witness-undone.cfg
976d579c79b2c365c5b4b12a7ebcbbd93cf0c96d96f48aad00e953ec06edf1ff  HandoffInd.apalache-indinv.cfg
40532da16357719a2dc27492af35aa33840095fbd27f5ff0775203319da87187  HandoffTrace.reject-admit-before-dial.cfg
ff5e2d77a6d96e94ad37a979043253662404fc870baff2cede6a061268612807  HandoffTrace.reject-end-old-channel.cfg
d22aa4209a5618aeb5e9d27c6aacd6d836bf8b8bdfd8955d0d2b4ebcfd0e5d1f  HandoffTrace.reject-spawn-before-ack.cfg
f9c952f0db389fe897619912f121fcc0bdd21470ebf9cb9af47d27d1f10ffe64  HandoffTrace.witness-trace-basic.cfg
682d831c0fab81f2fe41e10863eaf18dc21c8ec87bee9d1ed98dbe5d896f14b7  HandoffTrace.witness-trace-oldadmit-mutant.cfg
b541cccf143ccb816932de8f8b1c5f8c88939c185c4c0148b35d2b5b99f56003  HandoffTrace.witness-trace-stopopen.cfg
089e55a34a37426da4761703673e0ffcedfde76afc04604165e9ab248fa539f9  HandoffTrace.witness-trace-survivor.cfg
```

- Engine: B1a commit `99c251107` on `cas-fold-v2`; trace runs on the instrumented optdebug build of the same tree
  (`b8696c5bb`, libcubrid `edd04ea717fd8447…`). Gate on the head merged with develop `633bf1988`
  (`7327db817`): optdebug libcubrid `fd8d988b7bdcf4af…`, release `6f336cfece3dc2cb…`; tracer smoke 51/51 and the
  broker smoke (`smoke_b1a.sh`: raw-wire probe, JDBC cancel, survivor across a broker restart, server restart,
  stop with an open session) 5/5 on both builds, no core.
