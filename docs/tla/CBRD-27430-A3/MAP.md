# CBRD-27430 A3 — the folded server's in-process boundary refines the CS wire boundary

Map [CAS 폴드 재이식 지도](https://github.com/xmilex-git/workspace/issues/618), ticket
[A3 이식](https://github.com/xmilex-git/workspace/issues/624). A folded CAS session's client half runs on a
server thread and reaches the server half through `enter_server ()` / `exit_server ()`
(`network_interface_cl.c`) instead of a request. #620 judged A3 to need no model for shared state (none
is added); this model checks the other axis: that the boundary does around each call what the wire
boundary does around each request.

Code: fork branch `cas-fold-v2` at `4ef7922ea` (worktree `~/dev/cubrid-worktree/cas-fold-v2`), A3 commit
on `2d04848a3`. Line numbers below are at `4ef7922ea`.

Scope: **one in-process session** (the A stages have one: the compile tracer). Under SERVER_MODE
`CUB_THREAD_LOCAL` is empty (`db_multi_threads_connections.h:54-61`), so `tm_Tran_invalidate_snapshot`
and `tm_Tran_rep_read_lock`, which this boundary reads and writes per call, are process globals; with
two folded sessions one session's statement start would be consumed by the other's enter. A4 makes
them session-owned (handed over in A4's body); the model is per session and holds then.

## Claim and sources

| # | Claim | Source |
|---|---|---|
| C1 | Under READ COMMITTED every statement reads through a snapshot built after it started, and all reads of one statement read through one snapshot; under REPEATABLE READ all reads of a transaction share one snapshot. A statement run by a method inside a query starts a new one (existing behavior, kept). | manual `sql/transaction.rst` (READ COMMITTED: a new snapshot per statement); wire: `db_vdb.c:6534 db_invalidate_mvcc_snapshot_before_statement` sets `tm_Tran_invalidate_snapshot`, `client_support.cpp:276-284` sends it in the next request header and clears it, `network_sr.c:925-927 net_server_request` drops the snapshot; `db_method_static.cpp:725` (nested statement); `log_tran_table.c:4057` (RR keeps it) |
| C2 | A call that leaves its transaction to be aborted (deadlock victim, or a later error over the victim's) rolls it back on the server before the client half sees the error, which is then `ER_LK_UNILATERALLY_ABORTED`, and clears the abort reason; a victim never enters `lock_suspend` again. | wire: `network_interface_sr.cpp:332 need_to_abort_tran`, `415 return_error_to_client`; `lock_manager.c:2426` assert "I must not be a deadlock-victim thread"; old fold commit `788c32ff44` |
| C3 | KILL TRANSACTION / KILL QUERY returns no error to the killer when it succeeded (the victims' `ER_CSS_CONN_SHUTDOWN` and unknown-target errors stay off the killer's session), and `ER_KILL_TR_NOT_ALLOWED` when a target was refused. | wire: `network_interface_sr.cpp:7955 sthread_kill_or_interrupt_tran` (other errors ignored, the refusal returned); `log_tran_table.c:6091 logtb_slam_transaction` sets the error on the calling thread; old fold commits `6ba92b9f1f`, `dcb86d9876` |
| C4 | A REPEATABLE READ prefetch that returned `NO_ERROR` leaves the RR transaction lock held on the server, and the client's `tm_Tran_rep_read_lock` never claims a lock the server does not hold when the client reads it. | wire: `compile.c:462-485 pt_class_pre_fetch`, `network_interface_sr.cpp:7694` (`slocator_find_lockhint_class_oids` takes it), `transaction_sr.c:708 xtran_lock_rep_read`; client mirror `network_interface_cl.c` CS branches, `transaction_cl.c:400 tran_commit`, `607 tran_abort_only_client`; old fold commit `8eaa1feb6f` |

## Refinement map (model -> code)

| Model | Code | One step because |
|---|---|---|
| `StmtStart` | `db_vdb.c:6524 db_invalidate_mvcc_snapshot_before_statement` (RC: `tm_Tran_invalidate_snapshot = 1`), called at execution start by `db_execute_statement` & co. (`db_vdb.c:5487, 5559, 5687, 5714, 5728`); the compile's calls of a statement come before it | the flag is written only by the one in-process session's thread (scope above) |
| `Enter(k)` | `network_interface_cl.c:168 enter_server`: `db_on_server++`, `er_stack_push_if_exists`, then (fold) `logtb_invalidate_snapshot_data` when the flag is set and the flag cleared. `k`: `read` every call not below; `rr` `tran_lock_rep_read` (11055); `hint` `locator_find_lockhint_class_oids` (1501) under RR with a lock to take or a mirror to clear; `kill` `thread_kill_or_interrupt_tran` (8998); `commit` `tran_server_commit` (2995) | thread-local state plus the session's own tdes snapshot (`log_tran_table.c:4063-4066`); the tdes snapshot is only touched by the session's thread or its PX workers under `m_px_lock_mutex`, none of which run between calls |
| `NestedStmt` | a method or SP in an executing query runs SQL through the in-process client half (`db_method_static.cpp:725` sets the flag, `db_execute_statement` starts the statement, its first call enters at depth 2) | the nested statement start and its first enter are on the same thread with no shared access in between |
| `Read` | `log_tran_table.c:4378 logtb_get_mvcc_snapshot`: builds `tdes->mvccinfo.snapshot` when invalid (4397-4400), then the scan reads through it | the test and build of the thread's own tdes snapshot (no PX worker in the modeled calls) |
| `LockWait`, `Grant`, `Victim` | `lock_manager.c lock_suspend`: suspend at 2424-2430, resume `LOCK_RESUMED` / `LOCK_RESUMED_ABORTED_FIRST` (`lock_set_error_for_aborted`, `lock_set_tran_abort_reason (TRAN_ABORT_DUE_DEADLOCK)`) | the deadlock detector sets the waiter's state under the thread entry mutex; the waiter reads it after wakeup |
| `OtherErr` | any `er_set` of a call after its last logged step (including after a victim's error: `need_to_abort_tran`'s defence case) | a thread-local error |
| `RRLock` | `tran_lock_rep_read` fold branch (11055: `xtran_lock_rep_read`) and the RR part of `locator_find_lockhint_class_oids`' fold branch (1599-1610), skipped for a victim (`er_errid () == ER_LK_UNILATERALLY_ABORTED` or `tran_abort_reason != TRAN_NORMAL`); `lock_rep_read_tran` (`lock_manager.c:10732`, S on `oid_Rr`) | one lock request; its wait is the `waiting` branch |
| `KillStep(o)` | one `xlogtb_kill_or_interrupt_tran` of the fold loop (8998), then `er_clear ()` unless `ER_KILL_TR_NOT_ALLOWED` | one call on the killer's thread; the victim's side is not modeled (fault table) |
| `CommitStep` | `xtran_server_commit` in `tran_server_commit`'s fold branch (after `xsession_set_row_count`) | one server call; releases the RR lock and the snapshot |
| `Exit` | `network_interface_cl.c:208 exit_server`: when `er_errid () != NO_ERROR`, `network_interface_sr.cpp:378 abort_tran_on_error` (`need_to_abort_tran`, `tran_server_unilaterally_abort_tran`, abort reason cleared), then `er_restore_last_error`, `db_on_server--`; the client half's reaction on return: `tran_abort_only_client` on `ER_LK_UNILATERALLY_ABORTED` (mirror cleared), `tran_commit` (mirror cleared), the mirror set to the lock passed (`tran_lock_rep_read` on success, the lockhint call always) | the abort and the error-stack pop run on the session's thread with no other session touching its tdes abort state except the deadlock detector, which only marks waiters |
| `Done` | the session ends | — |
| `snap`, `snapCnt`, `snapTime` | `tdes->mvccinfo.snapshot` (valid, built at `clk`) | |
| `tmInv` | `tm_Tran_invalidate_snapshot` (`transaction_cl.c:72`; a process global under SERVER_MODE, see scope) | |
| `reason` | `tdes->tran_abort_reason` | |
| `rrHeld` / `rrMirror` | the S lock on `oid_Rr` held by the transaction / `tm_Tran_rep_read_lock != NULL_LOCK` (`transaction_cl.c:73`; a process global under SERVER_MODE) | |
| `er`, `saved` | the error manager's thread context: current level and the pushed stack (`error_manager.c:2282 er_stack_push_if_exists`, `2357 er_restore_last_error`) | |
| `epochSnap`, `tranSnap`, `lastKind`, `lastErr`, `rrOk`, `stale`, `unstable`, `victimWait`, `victimLeak` | ghosts | — |
| trace events | `TLATRACE` lines from the instrumented scratch build (below), only on the folded session's thread | each emitted inside the step it records, on one thread; the RR lock's wait outcome is emitted right after `xtran_lock_rep_read` returns (no other logged step in between) |

Callers of the protocol entry points: every `enter_server ()` caller is a fold branch in
`network_interface_cl.c` (one per x call) — each is `Enter(read)` unless listed under `Enter(k)`.
`enter_server_no_thread_entry` (boot before a thread entry) is not a session call. `exit_server` has the
same callers.

## Properties

| Name | Kind | Statement | Claim |
|---|---|---|---|
| `TypeOK` | invariant | variable types | — |
| `FreshSnapshot` | invariant | no READ COMMITTED read through a snapshot built before its statement started | C1 |
| `StableSnapshot` | invariant | the reads of one RC statement, and of one RR transaction, use one snapshot | C1 |
| `VictimRolledBack` | invariant | a call returning `ER_LK_UNILATERALLY_ABORTED`, or leaving a victim mark, rolled the transaction back and cleared the mark | C2 |
| `NoVictimWait` | invariant | no `LockWait` / RR lock wait with `reason = victim` | C2 |
| `KillErrorsStay` | invariant | a finished KILL returns no error when it succeeded and `notallowed` when refused | C3 |
| `RRLockHeld` | invariant | an RR prefetch that returned `NO_ERROR`, and the mirror at the client, imply the server holds the RR lock | C4 |
| `IndInv` | invariant | inductive strengthening (Apalache) | all |

## Fault model

| Fault | Modeled | Where / why not |
|---|---|---|
| error return of a call | yes | `OtherErr` (read and lockhint calls), `KillStep` outcomes |
| interrupt | no | an interrupt is an error return of the call (`OtherErr`); the boundary has no interrupt-specific branch |
| lock timeout | no | a timeout returns an error without an abort mark (`OtherErr` after `Grant`). The lockhint call sets the mirror whatever the result, as the CS branch does; a timed-out RR lock with a lookup that succeeded would leave the mirror set without the lock — the same on the wire (question Q1 below), not added by the fold |
| deadlock victim | yes | `Victim` on any wait, including the RR lock's |
| OOM | no | an error return (`OtherErr`); `sqmgr_unpack_db_values` OOM is on the CS handler side |
| crash / `kill -9` | no | the boundary keeps no durable state |
| spurious wakeup | no | `lock_suspend` loops until a resumed state |
| concurrent DML / vacuum | no | only the session's own snapshot validity matters here; the snapshot contents are out of scope |
| KILL of the session itself, or of a victim mid-call | no | the victim's side is another session; C3 is about the killer |
| HA standby (`ER_DB_NO_MODIFICATIONS`) | no | `need_to_abort_tran` aborts on it like the wire, but `conn->reset_on_commit` is HA (B3) |
| PX workers building the snapshot | no | under `m_px_lock_mutex` with the session's thread waiting; `docs/tla/CBRD-27967` models it |

## Mutants

| Mutant | cfg | Re-enables | Expected | Claim |
|---|---|---|---|---|
| `snap_every_enter` | `mutant-snap-every-enter` | the old fold `f9a2d3e67c`: invalidate the snapshot at every enter | `StableSnapshot` | C1 |
| `snap_never` | `mutant-snap-never` | the fold before `f9a2d3e67c`: never invalidate | `FreshSnapshot` | C1 |
| `no_abort_at_exit` | `mutant-no-abort-at-exit` (RC), `mutant-no-abort-victim-waits` (RR) | the fold before `788c32ff44`: no rollback at exit | `VictimRolledBack`, `NoVictimWait` | C2 |
| `hint_victim_locks` | `mutant-hint-victim-locks` | the lockhint fold taking the RR lock before the rollback (the first A3 port: `xtran_lock_rep_read` inside the bracket, the victim's abort only at `exit_server`) | `NoVictimWait` | C2, C4 |
| `kill_no_clear` | `mutant-kill-no-clear` | the fold before `dcb86d9876`: no `er_clear` after a killed or unknown target | `KillErrorsStay` | C3 |
| `rr_noop` | `mutant-rr-noop` | the SA branches: `tran_lock_rep_read` returns `NO_ERROR` without the lock, the lockhint fold takes none | `RRLockHeld` | C4 |

## Witnesses

| cfg | Outcome reached |
|---|---|
| `witness-victim-rolled-back` | a victim's call returned `ER_LK_UNILATERALLY_ABORTED` after the rollback |
| `witness-rr-victim` | a victim of the RR lock wait rolled back |
| `witness-hint-victim` | a lockhint victim took no RR lock and rolled back |
| `witness-hint-error-locked` | a lockhint lookup failed with another error and the RR lock was still taken (the wire order) |
| `witness-kill-refused` | KILL returned `ER_KILL_TR_NOT_ALLOWED` |
| `witness-nested-rebuilt` | a nested statement rebuilt the snapshot inside the outer statement's call |
| `witness-two-snapshots` | two RC statements read through two snapshots |

## Counterexamples (correct variant) and their classification

1. `RRLockHeld` in `FoldBoundary.rr` (first run): commit released the RR lock while the client mirror still
   said held. **Model error**: the property read the mirror inside the commit call, where no reader exists
   (`pt_class_pre_fetch` reads it only at depth 0); the client clears it in `tran_commit` after the call.
   Property scoped to depth 0.
2. `IndInv` in `FoldBoundary` (first run): a nested statement's victim abort, then the outer call set another
   error. **Real path, same on the wire** (the outer request reports its own error after the nested request
   rolled back); IndInv was too narrow. The client half of the nested statement (same thread) clears the
   mirror on its `ER_LK_UNILATERALLY_ABORTED`, which the model now does at any depth.
3. Apalache inductive-check counterexamples while IndInv was built (unreachable starting states: `rr` call
   under RC, kill errors at a read level, a commit window with a valid snapshot, `er = unilat` without a
   mark): IndInv strengthened each time, never the spec. One was a spec error: overlapping `CASE` guards in
   `Exit` (TLC takes the first, TLA+ any) — rewritten as an IF chain.

## Findings

- **H1 (fixed in A3)**: the first A3 port of `locator_find_lockhint_class_oids` took the RR lock inside the
  bracket for a call that had made the transaction a deadlock victim; the wire path rolls the victim back
  first (`return_error_to_client` before `xtran_lock_rep_read`, `network_interface_sr.cpp:7686-7700`). With an
  X holder on `oid_Rr` (ALTER ... ADD NOT NULL under RR) the victim waits and trips `lock_manager.c:2426`.
  `mutant-hint-victim-locks` is that code and fails `NoVictimWait`; the fix (skip the lock for a victim)
  passes. Not reproduced at runtime (needs a deadlock inside the lockhint lookup plus a concurrent ADD
  NOT NULL); the change is the fix, the mutant records the defect.
- **Q1 (develop, wire too, not A3)**: the lockhint request sets `tm_Tran_rep_read_lock` whatever the result;
  if the RR lock timed out while the lookup succeeded, the mirror says held and the next statement passes
  `NULL_LOCK`. Fault-table row "lock timeout"; not modeled, not reproduced.

## Dead expressions

| Line | Expression | Why TLC never evaluates it in the pass cfgs |
|---|---|---|
| FoldBoundary.tla:135 | `snap' = Invalidated /\ tmInv' = FALSE` in `EnterAt` | mutant-only branch (`snap_every_enter`); `mutant-snap-every-enter` fires it |
| FoldBoundary.tla:137 | `UNCHANGED <<snap, tmInv>>` in `EnterAt` | mutant-only branch (`snap_never`); `mutant-snap-never` fires it |
| FoldBoundary.tla:180 | `snap' = Invalidated /\ tmInv' = FALSE` in `NestedStmt` | mutant-only branch (`snap_every_enter`) |
| FoldBoundary.tla:182 | `snap' = snap /\ tmInv' = flag` in `NestedStmt` | mutant-only branch (`snap_never`) |
| FoldBoundary.tla:251 | line 251 of `RRLock`'s body | RC cfgs only (`FoldBoundary`, `FoldBoundary.scale-3`): READ COMMITTED never takes the RR lock (`compile.c:462-472`); the RR cfgs evaluate it |
| FoldBoundary.tla:252 | line 252 of `RRLock`'s body | RC cfgs only (`FoldBoundary`, `FoldBoundary.scale-3`): READ COMMITTED never takes the RR lock (`compile.c:462-472`); the RR cfgs evaluate it |
| FoldBoundary.tla:253 | line 253 of `RRLock`'s body | RC cfgs only (`FoldBoundary`, `FoldBoundary.scale-3`): READ COMMITTED never takes the RR lock (`compile.c:462-472`); the RR cfgs evaluate it |
| FoldBoundary.tla:254 | line 254 of `RRLock`'s body | RC cfgs only (`FoldBoundary`, `FoldBoundary.scale-3`): READ COMMITTED never takes the RR lock (`compile.c:462-472`); the RR cfgs evaluate it |
| FoldBoundary.tla:255 | line 255 of `RRLock`'s body | RC cfgs only (`FoldBoundary`, `FoldBoundary.scale-3`): READ COMMITTED never takes the RR lock (`compile.c:462-472`); the RR cfgs evaluate it |
| FoldBoundary.tla:256 | line 256 of `RRLock`'s body | RC cfgs only (`FoldBoundary`, `FoldBoundary.scale-3`): READ COMMITTED never takes the RR lock (`compile.c:462-472`); the RR cfgs evaluate it |
| FoldBoundary.tla:257 | line 257 of `RRLock`'s body | RC cfgs only (`FoldBoundary`, `FoldBoundary.scale-3`): READ COMMITTED never takes the RR lock (`compile.c:462-472`); the RR cfgs evaluate it |
| FoldBoundary.tla:258 | line 258 of `RRLock`'s body | RC cfgs only (`FoldBoundary`, `FoldBoundary.scale-3`): READ COMMITTED never takes the RR lock (`compile.c:462-472`); the RR cfgs evaluate it |

## Bounds

Main: `MaxStmts = 2`, `MaxCalls = 2`, `KillTargets = 2`, `Nested = TRUE`, `Iso` RC and RR; scale: 3 and 3.
IndInv: Apalache over every value of `MaxStmts`, `MaxCalls` and both `Iso`, `Nested` values.

## Trace validation

Instrumented scratch worktree `~/dev/cubrid-worktree/cas-fold-v2-tla` (detached at `4ef7922ea`, patch
`.git_ignored_dir/scratch/fold-v2/a3/instrument.py`), install `~/optdebug/CUBRID-cas-fold-v2-tla`.
Events go to `CUBRID_TLATRACE_OUT` from the tracer's thread only.

Events (`TLATRACE seq=<n> a=<action> p=S|E ...`): `StmtStart` (`db_invalidate_mvcc_snapshot_before_statement`),
`Enter k= inv= d=` (`enter_server`), `Read built=` (`logtb_get_mvcc_snapshot`), `LockWait` / `Grant` / `Victim`
(`lock_suspend`; for the RR lock emitted after `xtran_lock_rep_read` returns as `RRLock wait=` then `Grant` /
`Victim`), `KillStep o=`, `CommitStep`, `Exit e= abort=` (`exit_server` after `abort_tran_on_error`). Not
logged: `OtherErr` (hidden in the trace spec).

| Run | Scenario | Events | Result |
|---|---|---|---|
| `traces/rc-kill-bind.log` | RC; tracer PRE `KILL QUERY 9999`, case `SELECT ? + ?` bound 30,12, commit | 33 | accepted (`witness-trace-rc-kill-bind`) |
| `traces/rr-select.log` | RR (`db_set_isolation`); `SELECT COUNT(*) FROM a1p`: two lockhint calls (lock taken, then the mirror cleared by `NULL_LOCK`) | 46 | accepted (`witness-trace-rr-select`) |
| `traces/rc-deadlock.log` | RC; tracer PRE `UPDATE a3d … id = 1; SELECT SLEEP (3); UPDATE a3d … id = 2` against a CS csql session updating id 2 then id 1: the tracer is the victim (`LockWait`, `Victim`, `Exit e=unilat abort=1`) | 69 | accepted (`witness-trace-rc-deadlock`); the server then aborted in the client half's `tran_abort_only_client` (below) |
| `traces/rc-kill-bind-inv-dropped.log` | `rc-kill-bind` with the first `Enter` of the second statement claiming `inv=0` | 33 | refused at event 24 (`reject-inv-dropped`) |

Actions no run reaches: `NestedStmt` (no in-process nested statement before A7), `Grant` (the tracer
never waited and won), `RRLock` with a wait (needs an X holder on `oid_Rr`), `KillStep` `ok`/`notallowed`
(the tracer is DBA and has no other session to kill), `OtherErr` (hidden). Runs and the instrumentation
patch: `.git_ignored_dir/scratch/fold-v2/a3/trace/`, `instrument.py`.

Outside the model, the deadlock run and a plain `ROLLBACK` probe (PRE `UPDATE a3d …; ROLLBACK`, core pid
1717810) abort the server in the client half's rollback: `ws_abort_mops` → `ws_decache` →
`classobj_free_class_constraints` → `db_ws_free` → `mspace_free` (a workspace allocation freed into another
heap). The old implementation fixed this path in A4 (`c90ec1b5a`) and A5 (`cdea44b39`); handed over to A4.

## Result

- 2026-11-07, `tools/tla/tla-check docs/tla/CBRD-27430-A3`: `RESULT: OK` (23 cfgs), run dir
  `.git_ignored_dir/scratch/tla/CBRD-27430-A3-20261107-181424-1737918`.
- spec sha256: `93cecd14ff214afdf409436e69cf1bb51b9cade9d486ea28621c26b604f53512  FoldBoundary.tla`,
  `0f0fccefec465bf5c0f89fac4e2ab3a8449266754ce4bfe05e975f90d148ada9  FoldBoundaryTrace.tla` (cfgs and this
  file in the run's `summary.txt`; this section was written after the run).
- Correct variant: `FoldBoundary` 500,354 states / 247,240 distinct, depth 39; `.rr` 1,537,861 / 779,170,
  depth 40; `.scale-3` 4,527,323 / 2,153,492, depth 71; `.scale-3-rr` 22,422,196 / 11,025,392, depth 73.
- Mutants: 7 cfgs, each violates its property. Witnesses: 7 reached. IndInv: Apalache inductive check pass.
- Trace: 3 runs accepted, 1 corrupted run refused. Engine `4ef7922ea` + instrumentation, install
  `~/optdebug/CUBRID-cas-fold-v2-tla`.
- TLAPS: 요청 없음.
