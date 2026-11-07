---------------------------- MODULE FoldBoundary ----------------------------
(* CBRD-27430 A3: the in-process boundary of the folded server.

   A CAS session's client half runs on a server thread and reaches the server
   half through enter_server () / exit_server () (network_interface_cl.c)
   instead of a request on the wire. The wire boundary does four things around
   every request that the folded boundary must do too:

     - net_server_request drops a READ COMMITTED snapshot when the request
       header carries NET_HEADER_FLAG_INVALIDATE_SNAPSHOT, which the client
       sets from tm_Tran_invalidate_snapshot and clears after sending;
     - return_error_to_client rolls back a transaction a failed request left
       to be aborted (deadlock victim) and clears its abort reason before the
       client sees the error;
     - a request's errors stay on the server worker: KILL's per-victim errors
       (logtb_slam_transaction's ER_CSS_CONN_SHUTDOWN) never reach the killer;
     - the REPEATABLE READ transaction lock is taken on the server and mirrored
       in the client's tm_Tran_rep_read_lock.

   One session S, its client and server halves on one thread; the deadlock
   detector is the environment. The thread-local error is the error manager's
   stack: enter pushes when an error exists, exit keeps the inner error if any
   (er_stack_push_if_exists / er_restore_last_error).

   Constants:
     Iso        "RC" | "RR"
     MaxStmts   statements the session runs (a statement after a rollback
                starts a new transaction)
     MaxCalls   server calls per statement
     Nested     a call of a statement runs one nested statement (a method or
                stored procedure running SQL from the in-process client half)
     Mutant     "none" | "snap_every_enter" | "snap_never" | "no_abort_at_exit"
                | "kill_no_clear" | "rr_noop" | "hint_victim_locks" *)
EXTENDS Naturals

CONSTANTS Iso, MaxStmts, MaxCalls, Nested, Mutant

\* apalache-type: Iso Str
\* apalache-type: MaxStmts Int
\* apalache-type: MaxCalls Int
\* apalache-type: Nested Bool
\* apalache-type: Mutant Str
\* apalache-type: depth Int
\* apalache-type: kind Int -> Str
\* apalache-type: saved Int -> Str
\* apalache-type: er Str
\* apalache-type: waiting Bool
\* apalache-type: stepDone Bool
\* apalache-type: stmts Int
\* apalache-type: calls Int
\* apalache-type: nestedDone Bool
\* apalache-type: tmInv Bool
\* apalache-type: clk Int
\* apalache-type: stmtTime Int
\* apalache-type: snap Int
\* apalache-type: snapCnt Int
\* apalache-type: snapTime Int
\* apalache-type: epochSnap Int
\* apalache-type: tranSnap Int
\* apalache-type: tran Str
\* apalache-type: reason Str
\* apalache-type: rrHeld Bool
\* apalache-type: rrMirror Bool
\* apalache-type: rrOk Bool
\* apalache-type: killRes Str
\* apalache-type: killLeft Int
\* apalache-type: lastKind Str
\* apalache-type: lastErr Str
\* apalache-type: stale Bool
\* apalache-type: unstable Bool
\* apalache-type: victimWait Bool
\* apalache-type: victimLeak Bool
\* apalache-type: rrWait Bool

ASSUME Assm ==
  /\ Iso \in {"RC", "RR"}
  /\ MaxStmts \in Nat \ {0} /\ MaxCalls \in Nat \ {0}
  /\ Nested \in BOOLEAN
  /\ Mutant \in {"none", "snap_every_enter", "snap_never", "no_abort_at_exit", "kill_no_clear", "rr_noop",
                "hint_victim_locks"}

\* read: any call (query execution, fetches); rr: tran_lock_rep_read; hint: locator_find_lockhint_class_oids
\* under REPEATABLE READ (the RR lock rides it); kill: KILL; commit: tran_server_commit
Kinds == {"read", "rr", "hint", "kill", "commit"}
\* "unilat" ER_LK_UNILATERALLY_ABORTED, "other" any other server error, "shutdown" ER_CSS_CONN_SHUTDOWN
\* (a killed victim), "unknown" a kill target that is gone, "notallowed" ER_KILL_TR_NOT_ALLOWED
Errs == {"none", "unilat", "other", "shutdown", "unknown", "notallowed"}
KillTargets == 2
KillOutcomes == {"ok", "unknown", "notallowed"}
Levels == 1..2

(* depth      db_on_server: 0 client, 1 a call, 2 a nested statement's call
   kind       kind of the call at each level
   saved      the error below each level when it was entered (the pushed error stack)
   er         the thread's current error
   waiting    in lock_suspend
   stepDone   the one-shot server step of an rr or commit call ran
   tmInv      tm_Tran_invalidate_snapshot
   snap, snapCnt, snapTime   tdes->mvccinfo.snapshot: id (0 invalid) and build time
   epochSnap  snapshot the current statement read through (0 none yet)
   tranSnap   snapshot the current transaction read through (RR)
   tran, reason  tdes state; tran_abort_reason
   rrHeld     the server holds the RR transaction lock
   rrMirror   tm_Tran_rep_read_lock # NULL_LOCK
   rrOk       an RR prefetch of this transaction returned NO_ERROR
   lastKind, lastErr  the last call that returned to the client and the error it returned
   stale, unstable, victimWait, victimLeak  violation ghosts
   rrWait     the wait in lock_suspend is for the RR transaction lock *)
VARIABLES depth, kind, saved, er, waiting, stepDone, stmts, calls, nestedDone, tmInv, clk, stmtTime,
          snap, snapCnt, snapTime, epochSnap, tranSnap, tran, reason, rrHeld, rrMirror, rrOk,
          killRes, killLeft, lastKind, lastErr, stale, unstable, victimWait, victimLeak, rrWait

vars == <<depth, kind, saved, er, waiting, stepDone, stmts, calls, nestedDone, tmInv, clk, stmtTime,
          snap, snapCnt, snapTime, epochSnap, tranSnap, tran, reason, rrHeld, rrMirror, rrOk,
          killRes, killLeft, lastKind, lastErr, stale, unstable, victimWait, victimLeak, rrWait>>

Init ==
  /\ depth = 0 /\ kind = [l \in Levels |-> "none"] /\ saved = [l \in Levels |-> "none"]
  /\ er = "none" /\ waiting = FALSE /\ stepDone = FALSE
  /\ stmts = 0 /\ calls = 0 /\ nestedDone = FALSE
  /\ tmInv \in BOOLEAN /\ clk = 0 /\ stmtTime = 0     \* the session's first requests may have consumed the flag
  /\ snap = 0 /\ snapCnt = 0 /\ snapTime = 0 /\ epochSnap = 0 /\ tranSnap = 0
  /\ tran = "active" /\ reason = "normal"
  /\ rrHeld = FALSE /\ rrMirror = FALSE /\ rrOk = FALSE
  /\ killRes = "none" /\ killLeft = 0
  /\ lastKind = "none" /\ lastErr = "none"
  /\ stale = FALSE /\ unstable = FALSE /\ victimWait = FALSE /\ victimLeak = FALSE /\ rrWait = FALSE

\* logtb_invalidate_snapshot_data: READ COMMITTED only
Invalidated == IF Iso = "RC" THEN 0 ELSE snap

\* enter_server at level depth + 1 for a call of kind k
EnterAt(k) ==
  /\ \/ /\ Mutant = "snap_every_enter"
        /\ snap' = Invalidated /\ tmInv' = FALSE
     \/ /\ Mutant = "snap_never"
        /\ UNCHANGED <<snap, tmInv>>
     \/ /\ Mutant \notin {"snap_every_enter", "snap_never"}
        /\ snap' = IF tmInv THEN Invalidated ELSE snap
        /\ tmInv' = FALSE
  /\ depth' = depth + 1
  /\ kind' = [kind EXCEPT ![depth + 1] = k]
  /\ saved' = [saved EXCEPT ![depth + 1] = er]
  /\ er' = "none"
  /\ stepDone' = FALSE

\* db_execute_statement: db_invalidate_mvcc_snapshot_before_statement (RC sets the flag); a statement
\* after a rollback runs in a new transaction
StmtStart ==
  /\ depth = 0 /\ stmts < MaxStmts
  /\ stmts' = stmts + 1 /\ calls' = 0 /\ nestedDone' = FALSE
  /\ clk' = clk + 1 /\ stmtTime' = clk + 1 /\ epochSnap' = 0
  /\ tmInv' = (tmInv \/ Iso = "RC")
  /\ tran' = "active"
  /\ IF tran = "aborted" THEN tranSnap' = 0 /\ rrOk' = FALSE ELSE UNCHANGED <<tranSnap, rrOk>>
  /\ UNCHANGED <<depth, kind, saved, er, waiting, stepDone, snap, snapCnt, snapTime, reason, rrHeld,
                 rrMirror, killRes, killLeft, lastKind, lastErr, stale, unstable, victimWait, victimLeak, rrWait>>

\* a server call of the client half: compiling the next statement (before its StmtStart) or executing the
\* current one; after a rollback the server half already runs a new transaction
Enter(k) ==
  /\ depth = 0 /\ calls < MaxCalls
  /\ k \in {"rr", "hint"} => Iso = "RR"
  /\ EnterAt(k)
  /\ calls' = calls + 1
  /\ tran' = "active"
  /\ killRes' = IF k = "kill" THEN "running" ELSE killRes
  /\ IF k = "kill" THEN killLeft' \in 1..KillTargets ELSE killLeft' = killLeft   \* KILL names one or more transactions
  /\ UNCHANGED <<waiting, stmts, nestedDone, clk, stmtTime, snapCnt, snapTime, epochSnap, tranSnap, reason,
                 rrHeld, rrMirror, rrOk, lastKind, lastErr, stale, unstable, victimWait, victimLeak, rrWait>>

\* a method in the executing query runs a statement through the in-process client half
NestedStmt ==
  /\ Nested /\ ~nestedDone
  /\ depth = 1 /\ kind[1] = "read" /\ ~waiting /\ er = "none"
  /\ nestedDone' = TRUE
  /\ clk' = clk + 1 /\ stmtTime' = clk + 1 /\ epochSnap' = 0
  /\ LET flag == tmInv \/ Iso = "RC" IN
       \/ /\ Mutant = "snap_every_enter"
          /\ snap' = Invalidated /\ tmInv' = FALSE
       \/ /\ Mutant = "snap_never"
          /\ snap' = snap /\ tmInv' = flag
       \/ /\ Mutant \notin {"snap_every_enter", "snap_never"}
          /\ snap' = IF flag THEN Invalidated ELSE snap
          /\ tmInv' = FALSE
  /\ depth' = 2
  /\ kind' = [kind EXCEPT ![2] = "read"]
  /\ saved' = [saved EXCEPT ![2] = er]
  /\ er' = "none"
  /\ UNCHANGED <<waiting, stepDone, stmts, calls, snapCnt, snapTime, tranSnap, tran, reason, rrHeld, rrMirror, rrOk,
                 killRes, killLeft, lastKind, lastErr, stale, unstable, victimWait, victimLeak, rrWait>>

\* logtb_get_mvcc_snapshot at a heap read: build when invalid, then read through it
Read ==
  /\ depth > 0 /\ kind[depth] = "read" /\ ~waiting /\ er = "none" /\ tran = "active"
  /\ LET s == IF snap = 0 THEN snapCnt + 1 ELSE snap
         t == IF snap = 0 THEN clk ELSE snapTime
     IN /\ snap' = s /\ snapCnt' = (IF snap = 0 THEN snapCnt + 1 ELSE snapCnt) /\ snapTime' = t
        /\ stale' = (stale \/ (Iso = "RC" /\ t < stmtTime))
        /\ unstable' = (unstable \/ (Iso = "RC" /\ epochSnap # 0 /\ epochSnap # s)
                                 \/ (Iso = "RR" /\ tranSnap # 0 /\ tranSnap # s))
        /\ epochSnap' = s
        /\ tranSnap' = IF tranSnap = 0 THEN s ELSE tranSnap
  /\ UNCHANGED <<depth, kind, saved, er, waiting, stepDone, stmts, calls, nestedDone, tmInv, clk, stmtTime, tran,
                 reason, rrHeld, rrMirror, rrOk, killRes, killLeft, lastKind, lastErr, victimWait, victimLeak, rrWait>>

\* lock_suspend (lock_manager.c:2426 asserts the waiter is no victim)
LockWait ==
  /\ depth > 0 /\ kind[depth] \in {"read", "hint"} /\ ~waiting /\ er = "none" /\ tran = "active" /\ ~stepDone
  /\ waiting' = TRUE
  /\ victimWait' = (victimWait \/ reason # "normal")
  /\ UNCHANGED <<depth, kind, saved, er, stepDone, stmts, calls, nestedDone, tmInv, clk, stmtTime, snap, snapCnt,
                 snapTime, epochSnap, tranSnap, tran, reason, rrHeld, rrMirror, rrOk, killRes, killLeft, lastKind,
                 lastErr, stale, unstable, victimLeak, rrWait>>

\* the deadlock detector picks the waiter: LOCK_RESUMED_ABORTED_FIRST, lock_set_error_for_aborted
Victim ==
  /\ waiting
  /\ waiting' = FALSE /\ reason' = "victim" /\ er' = "unilat"
  /\ stepDone' = (stepDone \/ rrWait) /\ rrWait' = FALSE
  /\ UNCHANGED <<depth, kind, saved, stmts, calls, nestedDone, tmInv, clk, stmtTime, snap, snapCnt,
                 snapTime, epochSnap, tranSnap, tran, rrHeld, rrMirror, rrOk, killRes, killLeft, lastKind, lastErr,
                 stale, unstable, victimWait, victimLeak>>

Grant ==
  /\ waiting
  /\ waiting' = FALSE
  /\ stepDone' = (stepDone \/ rrWait) /\ rrHeld' = (rrHeld \/ rrWait) /\ rrWait' = FALSE
  /\ UNCHANGED <<depth, kind, saved, er, stmts, calls, nestedDone, tmInv, clk, stmtTime, snap, snapCnt,
                 snapTime, epochSnap, tranSnap, tran, reason, rrMirror, rrOk, killRes, killLeft, lastKind,
                 lastErr, stale, unstable, victimWait, victimLeak>>

\* a later error of the call overwrites the current one (need_to_abort_tran's defence case)
OtherErr ==
  /\ depth > 0 /\ kind[depth] \in {"read", "hint"} /\ ~waiting /\ er \in {"none", "unilat"}
  /\ er' = "other"
  /\ UNCHANGED <<depth, kind, saved, waiting, stepDone, stmts, calls, nestedDone, tmInv, clk, stmtTime, snap, snapCnt,
                 snapTime, epochSnap, tranSnap, tran, reason, rrHeld, rrMirror, rrOk, killRes, killLeft, lastKind,
                 lastErr, stale, unstable, victimWait, victimLeak, rrWait>>

\* the RR lock of tran_lock_rep_read (the whole call) or after the lockhint lookup (whatever it left in er):
\* lock_rep_read_tran (S on oid_Rr) unless the mirror says it is held (the client then passes NULL_LOCK).
\* A transaction the call left to be aborted takes no RR lock: the wire path rolls it back before the lock
\* (slocator_find_lockhint_class_oids calls return_error_to_client first), the folded call only at exit.
RRLock ==
  /\ depth = 1 /\ kind[1] \in {"rr", "hint"} /\ ~waiting /\ ~stepDone
  /\ kind[1] = "rr" => er = "none"
  /\ LET victim == er = "unilat" \/ reason # "normal"
         noLock == rrMirror \/ Mutant = "rr_noop" \/ (victim /\ Mutant # "hint_victim_locks")
     IN IF noLock
        THEN /\ stepDone' = TRUE
             /\ UNCHANGED <<waiting, rrHeld, rrWait, victimWait>>
        ELSE \/ /\ stepDone' = TRUE /\ rrHeld' = TRUE
                /\ UNCHANGED <<waiting, rrWait, victimWait>>
             \/ /\ waiting' = TRUE /\ rrWait' = TRUE
                /\ victimWait' = (victimWait \/ reason # "normal")
                /\ UNCHANGED <<stepDone, rrHeld>>
  /\ UNCHANGED <<depth, kind, saved, er, stmts, calls, nestedDone, tmInv, clk, stmtTime, snap, snapCnt,
                 snapTime, epochSnap, tranSnap, tran, reason, rrMirror, rrOk, killRes, killLeft, lastKind, lastErr,
                 stale, unstable, victimLeak>>

\* one xlogtb_kill_or_interrupt_tran of the KILL loop; the victim's error lands on this thread
KillStep(o) ==
  /\ depth = 1 /\ kind[1] = "kill" /\ killRes = "running" /\ killLeft > 0
  /\ IF o = "notallowed"
     THEN er' = "notallowed" /\ killRes' = "notallowed" /\ killLeft' = killLeft
     ELSE /\ er' = IF Mutant = "kill_no_clear" THEN (IF o = "ok" THEN "shutdown" ELSE "unknown") ELSE "none"
          /\ killLeft' = killLeft - 1
          /\ killRes' = IF killLeft = 1 THEN "ok" ELSE "running"
  /\ UNCHANGED <<depth, kind, saved, waiting, stepDone, stmts, calls, nestedDone, tmInv, clk, stmtTime, snap, snapCnt,
                 snapTime, epochSnap, tranSnap, tran, reason, rrHeld, rrMirror, rrOk, lastKind, lastErr, stale,
                 unstable, victimWait, victimLeak, rrWait>>

\* xtran_server_commit: locks released, the snapshot of the transaction dropped
CommitStep ==
  /\ depth = 1 /\ kind[1] = "commit" /\ ~waiting /\ er = "none" /\ ~stepDone
  /\ stepDone' = TRUE /\ rrHeld' = FALSE /\ snap' = 0
  /\ UNCHANGED <<depth, kind, saved, er, waiting, stmts, calls, nestedDone, tmInv, clk, stmtTime, snapCnt, snapTime,
                 epochSnap, tranSnap, tran, reason, rrMirror, rrOk, killRes, killLeft, lastKind, lastErr, stale,
                 unstable, victimWait, victimLeak, rrWait>>

CallFinished ==
  CASE kind[depth] = "kill" -> killRes # "running"
    [] kind[depth] \in {"rr", "hint", "commit"} -> stepDone
    [] OTHER -> TRUE

\* exit_server: abort_tran_on_error when the call failed, then the error stack pop; the client half's
\* reaction to the returned error and to a finished rr or commit call
Exit ==
  /\ depth > 0 /\ ~waiting /\ CallFinished
  /\ LET check == er # "none" /\ Mutant # "no_abort_at_exit"
         e == IF check /\ er # "unilat" /\ reason # "normal" THEN "unilat" ELSE er
         abort == check /\ e = "unilat"
         k == kind[depth]
         ok == e = "none"
     IN /\ tran' = IF abort THEN "aborted" ELSE tran
        /\ reason' = IF check THEN "normal" ELSE reason
        /\ rrHeld' = IF abort THEN FALSE ELSE rrHeld
        /\ snap' = IF abort THEN 0 ELSE snap
        /\ er' = IF e # "none" THEN e ELSE saved[depth]
        /\ depth' = depth - 1
        /\ kind' = [kind EXCEPT ![depth] = "none"]
        /\ victimLeak' = (victimLeak \/ (e = "unilat" /\ tran' # "aborted") \/ (reason = "victim" /\ tran' # "aborted")
                                     \/ (e # "none" /\ reason' # "normal"))
        /\ epochSnap' = IF abort \/ (k = "commit" /\ ok) THEN 0 ELSE epochSnap
        /\ tranSnap' = IF abort \/ (k = "commit" /\ ok) THEN 0 ELSE tranSnap
        /\ stepDone' = FALSE
        \* the client half (the nested statement's too: same thread) drops the mirror on a rollback
        \* (tran_abort_only_client) and after a commit (tran_commit), and sets it to the lock it passed:
        \* tran_lock_rep_read on success, locator_find_lockhint_class_oids whatever the result
        /\ rrMirror' = IF e = "unilat" \/ (k = "commit" /\ ok) THEN FALSE
                       ELSE IF Mutant = "rr_noop" THEN rrMirror
                       ELSE IF (k = "rr" /\ ok) \/ k = "hint" THEN ~rrMirror
                       ELSE rrMirror
        /\ rrOk' = IF e = "unilat" \/ (k = "commit" /\ ok) THEN FALSE
                   ELSE IF k \in {"rr", "hint"} /\ ok THEN TRUE
                   ELSE rrOk
        /\ IF depth = 1 THEN lastKind' = k /\ lastErr' = e ELSE UNCHANGED <<lastKind, lastErr>>
  /\ UNCHANGED <<saved, waiting, stmts, calls, nestedDone, tmInv, clk, stmtTime, snapCnt, snapTime,
                 killRes, killLeft, stale, unstable, victimWait, rrWait>>

Done ==
  /\ depth = 0 /\ stmts = MaxStmts
  /\ UNCHANGED vars

Next ==
  \/ StmtStart
  \/ \E k \in Kinds : Enter(k)
  \/ NestedStmt
  \/ Read \/ LockWait \/ Victim \/ Grant \/ OtherErr
  \/ RRLock \/ (\E o \in KillOutcomes : KillStep(o)) \/ CommitStep
  \/ Exit
  \/ Done

Spec == Init /\ [][Next]_vars

\* ---- properties ----
TypeOK ==
  /\ depth \in 0..2 /\ kind \in [Levels -> Kinds \cup {"none"}] /\ saved \in [Levels -> Errs] /\ er \in Errs
  /\ waiting \in BOOLEAN /\ stepDone \in BOOLEAN /\ nestedDone \in BOOLEAN /\ tmInv \in BOOLEAN
  /\ stmts \in 0..MaxStmts /\ calls \in 0..MaxCalls /\ clk \in Nat /\ stmtTime \in Nat
  /\ snap \in Nat /\ snapCnt \in Nat /\ snapTime \in Nat /\ epochSnap \in Nat /\ tranSnap \in Nat
  /\ tran \in {"active", "aborted"} /\ reason \in {"normal", "victim"}
  /\ rrHeld \in BOOLEAN /\ rrMirror \in BOOLEAN /\ rrOk \in BOOLEAN
  /\ killRes \in {"none", "running", "ok", "notallowed"} /\ killLeft \in 0..KillTargets
  /\ lastKind \in Kinds \cup {"none"} /\ lastErr \in Errs
  /\ stale \in BOOLEAN /\ unstable \in BOOLEAN /\ victimWait \in BOOLEAN /\ victimLeak \in BOOLEAN
  /\ rrWait \in BOOLEAN

\* C1: a READ COMMITTED read sees a snapshot built after its statement started
FreshSnapshot == ~stale
\* C1: the reads of one statement (READ COMMITTED) or one transaction (REPEATABLE READ) share one snapshot
StableSnapshot == ~unstable
\* C2: the client sees ER_LK_UNILATERALLY_ABORTED only after the server rolled the transaction back, and a
\* failed call leaves no abort reason behind
VictimRolledBack == ~victimLeak
\* C2: lock_suspend's assert: a deadlock victim never waits again
NoVictimWait == ~victimWait
\* C3: a KILL that succeeded returns no error to the killer; a refused one returns ER_KILL_TR_NOT_ALLOWED
KillErrorsStay ==
  /\ (depth = 0 /\ lastKind = "kill" /\ killRes = "ok") => lastErr = "none"
  /\ (depth = 0 /\ lastKind = "kill" /\ killRes = "notallowed") => lastErr = "notallowed"
\* C4: an RR prefetch that returned NO_ERROR leaves the RR lock held on the server, and the client's mirror
\* never claims a lock the server does not hold
RRLockHeld ==
  /\ (tran = "active" /\ rrOk /\ depth = 0) => rrHeld
  /\ (tran = "active" /\ rrMirror /\ depth = 0) => rrHeld

\* ---- inductive invariant ----
CommitWindow == depth = 1 /\ kind[1] = "commit" /\ stepDone
R_depth == /\ \A l \in Levels : (l > depth) => kind[l] = "none"
           /\ \A l \in Levels : (l <= depth) => kind[l] # "none"
           /\ kind[2] \in {"none", "read"}
           /\ depth = 2 => (kind[1] = "read" /\ nestedDone /\ saved[2] = "none")
           /\ stepDone => (depth = 1 /\ kind[1] \in {"rr", "hint", "commit"})
           /\ Iso = "RC" => kind[1] \notin {"rr", "hint"}
           /\ depth > 0 => calls > 0
           /\ (depth > 0 /\ kind[depth] = "commit") => er = "none"
           /\ CommitWindow => (snap = 0 /\ ~rrHeld)
R_wait == /\ waiting => (depth > 0 /\ reason = "normal" /\ ~stepDone /\ tran = "active")
          /\ (waiting /\ ~rrWait) => (kind[depth] \in {"read", "hint"} /\ er = "none")
          /\ rrWait => (waiting /\ depth = 1 /\ kind[1] \in {"rr", "hint"} /\ er \in {"none", "other"} /\ ~rrMirror)
          /\ (rrWait /\ kind[1] = "rr") => er = "none"
R_er == /\ (depth > 0 /\ kind[depth] \in {"read", "rr", "hint"}) => er \in {"none", "unilat", "other"}
        /\ (depth > 0 /\ kind[depth] = "kill") => er \in {"none", "notallowed"}
R_unilat == (depth > 0 /\ er = "unilat") => (reason = "victim" \/ tran = "aborted")
R_reason == reason = "victim" => (depth > 0 /\ kind[depth] \in {"read", "rr", "hint"} /\ er \in {"unilat", "other"}
                                  /\ ~waiting /\ tran = "active")
R_snap == /\ snap <= snapCnt /\ epochSnap <= snapCnt /\ tranSnap <= snapCnt
          /\ snapTime <= clk /\ stmtTime = clk
          /\ (Iso = "RC" /\ tmInv) => (depth = 0 /\ epochSnap = 0)
          /\ (Iso = "RC" /\ snap # 0 /\ snapTime < stmtTime) => (tmInv /\ depth = 0 /\ epochSnap = 0)
          /\ (Iso = "RC" /\ epochSnap # 0) => (epochSnap = snap \/ (CommitWindow /\ snap = 0))
          /\ (Iso = "RR") => (tranSnap = snap \/ (CommitWindow /\ snap = 0))
R_tran == tran = "aborted" =>
            /\ snap = 0 /\ ~rrHeld /\ reason = "normal" /\ tranSnap = 0 /\ epochSnap = 0 /\ ~waiting
            /\ ~rrMirror /\ ~rrOk /\ depth < 2
            /\ (depth = 1 => (kind[1] = "read" /\ er \in {"unilat", "other"} /\ nestedDone))
R_rr == /\ rrMirror => (rrHeld \/ CommitWindow)
        /\ rrOk => (rrHeld \/ CommitWindow)
        /\ (depth = 1 /\ kind[1] \in {"rr", "hint"} /\ stepDone) => (rrHeld \/ reason = "victim")
        /\ (depth = 1 /\ kind[1] = "rr" /\ ~stepDone) => er = "none"
        /\ Iso = "RC" => (~rrHeld /\ ~rrMirror /\ ~rrOk)
R_kill == /\ killRes = "running" => (depth = 1 /\ kind[1] = "kill" /\ er = "none" /\ killLeft > 0)
          /\ (depth = 1 /\ kind[1] = "kill" /\ killRes = "ok") => er = "none"
          /\ (depth = 1 /\ kind[1] = "kill" /\ killRes = "notallowed") => er = "notallowed"
          /\ (depth = 1 /\ kind[1] = "kill") => killRes # "none"
          /\ (depth = 0 /\ lastKind = "kill") => killRes \in {"ok", "notallowed"}
          /\ (depth = 0 /\ lastKind = "kill" /\ killRes = "ok") => lastErr = "none"
          /\ (depth = 0 /\ lastKind = "kill" /\ killRes = "notallowed") => lastErr = "notallowed"
R_ghost == ~stale /\ ~unstable /\ ~victimWait /\ ~victimLeak

IndInv == TypeOK /\ R_depth /\ R_wait /\ R_er /\ R_unilat /\ R_reason /\ R_snap /\ R_tran /\ R_rr /\ R_kill /\ R_ghost

\* ---- witnesses ----
\* a deadlock victim's call returned ER_LK_UNILATERALLY_ABORTED to the client after the rollback
NotVictimRolledBack == ~(lastErr = "unilat" /\ tran = "aborted")
\* a victim's RR prefetch lock wait rolled the transaction back
NotRRVictim == ~(lastErr = "unilat" /\ tran = "aborted" /\ lastKind = "rr")
\* a lockhint request whose lookup failed with another error still took the RR lock
NotHintErrorLocked == ~(lastKind = "hint" /\ lastErr = "other" /\ rrMirror /\ rrHeld)
\* a victim of the lockhint lookup took no RR lock and was rolled back
NotHintVictim == ~(lastKind = "hint" /\ lastErr = "unilat" /\ tran = "aborted")
\* a KILL was refused for one target
NotKillRefused == ~(lastKind = "kill" /\ lastErr = "notallowed")
\* a nested statement rebuilt the snapshot inside the outer statement's call
NotNestedRebuilt == ~(nestedDone /\ depth = 1 /\ epochSnap > 1)
\* two READ COMMITTED statements read through different snapshots
NotTwoSnapshots == ~(stmts = 2 /\ snapCnt = 2 /\ depth = 0 /\ ~nestedDone)

\* Apalache: the bounds open, the mutant off
CInit ==
  /\ Iso \in {"RC", "RR"} /\ MaxStmts \in Nat /\ MaxStmts > 0 /\ MaxCalls \in Nat /\ MaxCalls > 0
  /\ Nested \in BOOLEAN /\ Mutant = "none"
=============================================================================
