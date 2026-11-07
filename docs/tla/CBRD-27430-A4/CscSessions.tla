----------------------------- MODULE CscSessions -----------------------------
(* CBRD-27430 A4: per-session client workspace in the folded server.

   The folded server runs a CAS session's client half on server threads. Every
   client-half module global (the workspace and its MOP table, the lea heap
   behind db_ws_alloc, tm_Tran_*, the schema and trigger managers ...) becomes
   a field of the session's client_session_context (csc). A thread reaches a
   csc only through an activation bracket, csc_activate () / csc_deactivate (),
   which installs it in a thread_local and holds the csc's bracket_mutex for
   the bracket's extent. session_state owns the csc (csc_p, adopted after
   registration); session_state_uninit retires it: a thread that is not inside
   the csc brackets it, tears it down and deletes it; a thread ending its own
   session from inside the bracket marks it orphaned instead, and its
   csc_deactivate tears it down and deletes it on bracket exit.

   Roles (thread ids):
     1..N      tracer s: the in-process client of session s (one csc each)
     N+1       attacher: another request reaching session s through the
               session (holds a session reference, reads csc_p, brackets it)
     N+2       daemon: session_remove_expired_sessions (server thread)

   Heaps: the lea workspace heap of csc s is heap s; the private heap of
   thread t is heap 100 + t. A chunk records the heap it came from; a free
   that lands on another heap is mspace_free's abort (A3's rollback core).

   Constants:
     N        number of sessions (and tracers)
     MaxWork  work steps a tracer runs inside its bracket
     Attach   the attacher runs
     Xfer     a tracer frees in the client half a chunk the server half of the
              same call allocated (the assumption census A-XFER says the fold
              boundary never does this)
     ServerInit  the server boot initialized the client modules the sessions share before it accepted one (A5,
              docs/tla/CBRD-27430-A5): the areas exist from the start and no session boot takes a boot lock
     Mutant   "none" | see MAP.md, "Mutants" *)
EXTENDS Naturals, FiniteSets

CONSTANTS N, MaxWork, Attach, Xfer, ServerInit, Mutant

\* apalache-type: N Int
\* apalache-type: MaxWork Int
\* apalache-type: Attach Bool
\* apalache-type: Xfer Bool
\* apalache-type: ServerInit Bool
\* apalache-type: Mutant Str
\* apalache-type: pc Int -> Str
\* apalache-type: cst Int -> Str
\* apalache-type: orphan Int -> Bool
\* apalache-type: owner Int -> Int
\* apalache-type: active Int -> Int
\* apalache-type: sst Int -> Str
\* apalache-type: ref Int -> Int
\* apalache-type: smx Int -> Int
\* apalache-type: cscp Int -> Int
\* apalache-type: connRef Int -> Bool
\* apalache-type: adopted Int -> Bool
\* apalache-type: orphL Int -> Bool
\* apalache-type: work Int -> Int
\* apalache-type: tgt Int -> Int
\* apalache-type: aRef Bool
\* apalache-type: clsH Int -> Int
\* apalache-type: pvH Int -> Int
\* apalache-type: torn Int -> Int
\* apalache-type: bootMx Int
\* apalache-type: sawArea Int -> Bool
\* apalache-type: areaCnt Int
\* apalache-type: areaLive Bool
\* apalache-type: inv Int -> Bool
\* apalache-type: sharedInv Bool
\* apalache-type: fresh Int -> Bool
\* apalache-type: rrHeld Int -> Bool
\* apalache-type: rrMir Int -> Bool
\* apalache-type: sharedMir Bool
\* apalache-type: uaf Bool
\* apalache-type: nested Bool
\* apalache-type: badFree Bool
\* apalache-type: areaUaf Bool
\* apalache-type: stale Bool
\* apalache-type: unstable Bool
\* apalache-type: rrBad Bool
\* apalache-type: viaOrphan Bool
\* apalache-type: daemonWaited Bool
\* apalache-type: busyEnd Bool

VARIABLES pc, cst, orphan, owner, active, sst, ref, smx, cscp, connRef, adopted, orphL, work, tgt, aRef,
  clsH, pvH, torn, bootMx, sawArea, areaCnt, areaLive, inv, sharedInv, fresh, rrHeld, rrMir, sharedMir,
  uaf, nested, badFree, areaUaf, stale, unstable, rrBad, viaOrphan, daemonWaited, busyEnd

vars == <<pc, cst, orphan, owner, active, sst, ref, smx, cscp, connRef, adopted, orphL, work, tgt, aRef,
  clsH, pvH, torn, bootMx, sawArea, areaCnt, areaLive, inv, sharedInv, fresh, rrHeld, rrMir, sharedMir,
  uaf, nested, badFree, areaUaf, stale, unstable, rrBad, viaOrphan, daemonWaited, busyEnd>>

Sess == 1..N
A == N + 1
D == N + 2
Thr == 1..(N + 2)
PrivHeap(t) == 100 + t

\* db_on_server of a thread's bracket work: tracers and the attacher run the client half (0); the daemon is a
\* server thread (1)
Hat(t) == IF t = D THEN "sv" ELSE "cl"

\* db_private_alloc / db_private_free routing (memory_alloc.c): inside a bracket and in the client half, the
\* session's workspace heap (the CS/SA discipline: client-half private memory is workspace memory); otherwise
\* the calling thread's private heap
RouteP(t, h) ==
  IF Mutant = "no_route" THEN PrivHeap(t)
  ELSE IF active[t] # 0 /\ h = "cl" THEN active[t] ELSE PrivHeap(t)

Terminal == {"done", "abort"}

Init ==
  /\ pc = [t \in Thr |-> IF t = A THEN (IF Attach THEN "a_ref" ELSE "done")
                          ELSE IF t = D THEN "d_scan" ELSE "new"]
  /\ cst = [s \in Sess |-> "none"]
  /\ orphan = [s \in Sess |-> FALSE]
  /\ owner = [s \in Sess |-> 0]
  /\ active = [t \in Thr |-> 0]
  /\ sst = [s \in Sess |-> "none"]
  /\ ref = [s \in Sess |-> 0]
  /\ smx = [s \in Sess |-> 0]
  /\ cscp = [s \in Sess |-> 0]
  /\ connRef = [s \in Sess |-> FALSE]
  /\ adopted = [s \in Sess |-> FALSE]
  /\ orphL = [t \in Thr |-> FALSE]
  /\ work = [t \in Thr |-> 0]
  /\ tgt = [t \in Thr |-> 0]
  /\ aRef = FALSE
  /\ clsH = [s \in Sess |-> 0]
  /\ pvH = [s \in Sess |-> 0]
  /\ torn = [s \in Sess |-> 0]
  /\ bootMx = 0
  /\ sawArea = [t \in Thr |-> FALSE]
  /\ areaCnt = IF ServerInit /\ Mutant # "lazy_init" THEN 1 ELSE 0
  /\ areaLive = (ServerInit /\ Mutant # "lazy_init")
  /\ inv = [s \in Sess |-> FALSE]
  /\ sharedInv = FALSE
  /\ fresh = [s \in Sess |-> FALSE]
  /\ rrHeld = [s \in Sess |-> FALSE]
  /\ rrMir = [s \in Sess |-> FALSE]
  /\ sharedMir = FALSE
  /\ uaf = FALSE /\ nested = FALSE /\ badFree = FALSE /\ areaUaf = FALSE
  /\ stale = FALSE /\ unstable = FALSE /\ rrBad = FALSE
  /\ viaOrphan = FALSE /\ daemonWaited = FALSE /\ busyEnd = FALSE

Goto(t, l) == pc' = [pc EXCEPT ![t] = l]

(* ---- the activation bracket (client_session_context.cpp) ---- *)

\* csc_activate: nesting is a hard abort; otherwise lock bracket_mutex (wait while another thread holds it),
\* then install the thread_local
Acquire(t, c, next) ==
  IF active[t] # 0
  THEN /\ nested' = TRUE /\ Goto(t, "abort")
       /\ UNCHANGED <<owner, active, uaf, daemonWaited>>
  ELSE /\ IF Mutant = "no_mutex" THEN UNCHANGED owner ELSE /\ owner[c] = 0 /\ owner' = [owner EXCEPT ![c] = t]
       /\ active' = [active EXCEPT ![t] = c]
       /\ uaf' = (uaf \/ cst[c] # "live")
       /\ Goto(t, next)
       /\ UNCHANGED <<nested, daemonWaited>>

\* a thread blocked in csc_activate: its pc is at an acquire label and the mutex is held
AcqTarget(t) ==
  CASE pc[t] \in {"act", "r_act"} -> t
    [] pc[t] = "a_act" -> tgt[t]
    [] pc[t] = "d_act" -> tgt[t]
    [] OTHER -> 0

\* csc_teardown on thread t inside the bracket of c: the client half's teardown with the allocation routing forced
\* to the client side (db_on_server = 0 for its extent, whatever thread drives it); frees the session's chunks
\* (classobj_free_class_constraints frees through db_ws_free, value containers through db_private_free), then
\* ws_final destroys the session's lea heap. Shared areas stay (#123 D5).
Teardown(t, c) ==
  LET h == IF Mutant = "tear_sv_hat" THEN Hat(t) ELSE "cl"
  IN /\ badFree' = (badFree \/ (clsH[c] # 0 /\ clsH[c] # c) \/ (pvH[c] # 0 /\ pvH[c] # RouteP(t, h)))
     /\ clsH' = [clsH EXCEPT ![c] = 0]
     /\ pvH' = [pvH EXCEPT ![c] = 0]
     /\ torn' = [torn EXCEPT ![c] = @ + 1]
     /\ areaLive' = (areaLive /\ Mutant # "tear_frees_areas")

TearVars == <<badFree, clsH, pvH, torn, areaLive>>

\* csc_deactivate, first step: the orphan flag is read once (before the unlock), the orphaned context is torn down,
\* the thread_local cleared
Deact(t, next) ==
  LET c == active[t] IN
  /\ pc[t] \in {"deact", "a_deact"}
  /\ uaf' = (uaf \/ cst[c] # "live")
  /\ orphL' = [orphL EXCEPT ![t] = orphan[c]]
  /\ IF orphan[c] THEN Teardown(t, c) ELSE UNCHANGED TearVars
  /\ active' = [active EXCEPT ![t] = 0]
  /\ tgt' = [tgt EXCEPT ![t] = c]
  /\ Goto(t, next)

\* csc_deactivate, second step: unlock bracket_mutex
Unlock(t, next, reread) ==
  /\ IF Mutant = "no_mutex" THEN UNCHANGED owner ELSE owner' = [owner EXCEPT ![tgt[t]] = 0]
  /\ Goto(t, IF Mutant = "reread" THEN reread ELSE next)

\* csc_deactivate as it was in the old implementation: ctx->orphaned is read again after the unlock
Reread(t, next) ==
  /\ uaf' = (uaf \/ cst[tgt[t]] # "live")
  /\ orphL' = [orphL EXCEPT ![t] = orphan[tgt[t]]]
  /\ Goto(t, next)

\* csc_deactivate, third step: delete the orphaned context
Del(t, next) ==
  /\ IF orphL[t]
     THEN /\ uaf' = (uaf \/ cst[tgt[t]] # "live")
          /\ cst' = [cst EXCEPT ![tgt[t]] = "freed"]
          /\ viaOrphan' = TRUE
     ELSE UNCHANGED <<uaf, cst, viaOrphan>>
  /\ Goto(t, next)

(* ---- session_state (session.c) ---- *)

\* session_state_destroy by a thread holding a session reference (xsession_end_session), second step under the
\* session mutex: drop its reference; the last one runs session_state_uninit, whose csc_retire_and_delete marks
\* the context orphaned when the caller is inside it
EndSess(t, s, next) ==
  /\ cscp[s] # 0 /\ active[t] = cscp[s]
  /\ ref' = [ref EXCEPT ![s] = @ - 1]
  /\ IF ref[s] - 1 > 0
     THEN /\ busyEnd' = TRUE /\ smx' = [smx EXCEPT ![s] = 0] /\ Goto(t, next)
          /\ UNCHANGED <<sst, cscp, orphan, nested>>
     ELSE /\ UNCHANGED busyEnd
          \* the last reference's holder is inside the adopted context: in A4 only a bracket holder ends a folded
          \* session (a wire client's session has no context, csc_p = NULL)
          /\ IF Mutant = "retire_reactivate"
             THEN /\ nested' = TRUE /\ Goto(t, "abort")
                  /\ UNCHANGED <<sst, cscp, orphan, smx>>
             ELSE /\ orphan' = [orphan EXCEPT ![cscp[s]] = TRUE]
                  /\ sst' = [sst EXCEPT ![s] = "gone"]
                  /\ cscp' = [cscp EXCEPT ![s] = 0]
                  /\ smx' = [smx EXCEPT ![s] = 0]
                  /\ Goto(t, next) /\ UNCHANGED nested

(* ---- per-session client transaction state (transaction_cl.c, A3 boundary) ---- *)

InvOf(s) == IF Mutant = "shared_tm" THEN sharedInv ELSE inv[s]
MirOf(s) == IF Mutant = "shared_tm" THEN sharedMir ELSE rrMir[s]

SetInv(s, v) ==
  IF Mutant = "shared_tm" THEN sharedInv' = v /\ UNCHANGED inv ELSE inv' = [inv EXCEPT ![s] = v] /\ UNCHANGED sharedInv
SetMir(s, v) ==
  IF Mutant = "shared_tm" THEN sharedMir' = v /\ UNCHANGED rrMir ELSE rrMir' = [rrMir EXCEPT ![s] = v] /\ UNCHANGED sharedMir

TmVars == <<inv, sharedInv, fresh, rrHeld, rrMir, sharedMir, stale, unstable, rrBad>>

\* every touch of the context's state checks it is alive and owned (WS_ASSERT_OWNED; csc_current)
Touch(t) == uaf' = (uaf \/ active[t] = 0 \/ cst[active[t]] # "live" \/ areaLive = FALSE)
           /\ areaUaf' = (areaUaf \/ ~areaLive)

(* ---- tracer s (server_compile_tracer.cpp tracer_session) ---- *)

TNew(s) ==
  /\ pc[s] = "new"
  /\ cst' = [cst EXCEPT ![s] = "live"]
  /\ Goto(s, "act")
  /\ UNCHANGED <<orphan, owner, active, sst, ref, smx, cscp, connRef, adopted, orphL, work, tgt, aRef,
                 clsH, pvH, torn, bootMx, sawArea, areaCnt, areaLive, TmVars, uaf, nested, badFree, areaUaf,
                 viaOrphan, daemonWaited, busyEnd>>

TAct(s) ==
  /\ pc[s] = "act"
  /\ Acquire(s, s, "bootlk")
  /\ UNCHANGED <<cst, orphan, sst, ref, smx, cscp, connRef, adopted, orphL, work, tgt, aRef,
                 clsH, pvH, torn, bootMx, sawArea, areaCnt, areaLive, TmVars, badFree, areaUaf, viaOrphan, busyEnd>>

\* client boot is serialized until A5 makes it reentrant (tracer_Boot_mutex); from A5 no boot lock exists
NoBootLock == Mutant = "no_boot_lock" \/ ServerInit

TBootLock(s) ==
  /\ pc[s] = "bootlk"
  /\ IF NoBootLock THEN UNCHANGED bootMx ELSE bootMx = 0 /\ bootMx' = s
  /\ Goto(s, "area")
  /\ UNCHANGED <<cst, orphan, owner, active, sst, ref, smx, cscp, connRef, adopted, orphL, work, tgt, aRef,
                 clsH, pvH, torn, sawArea, areaCnt, areaLive, TmVars, uaf, nested, badFree, areaUaf,
                 viaOrphan, daemonWaited, busyEnd>>

\* ws_init's *_area_init: the process-shared area is created once (the init returns when it exists)
TAreaCheck(s) ==
  /\ pc[s] = "area"
  /\ sawArea' = [sawArea EXCEPT ![s] = (Mutant # "no_area_guard" /\ areaCnt > 0)]
  /\ Goto(s, "area2")
  /\ UNCHANGED <<cst, orphan, owner, active, sst, ref, smx, cscp, connRef, adopted, orphL, work, tgt, aRef,
                 clsH, pvH, torn, bootMx, areaCnt, areaLive, TmVars, uaf, nested, badFree, areaUaf,
                 viaOrphan, daemonWaited, busyEnd>>

TAreaMake(s) ==
  /\ pc[s] = "area2"
  /\ IF sawArea[s] THEN UNCHANGED <<areaCnt, areaLive>> ELSE areaCnt' = areaCnt + 1 /\ areaLive' = TRUE
  /\ Goto(s, "reg")
  /\ UNCHANGED <<cst, orphan, owner, active, sst, ref, smx, cscp, connRef, adopted, orphL, work, tgt, aRef,
                 clsH, pvH, torn, bootMx, sawArea, TmVars, uaf, nested, badFree, areaUaf,
                 viaOrphan, daemonWaited, busyEnd>>

ReleaseBoot(s) == IF NoBootLock THEN UNCHANGED bootMx ELSE bootMx' = 0

\* db_restart_ex succeeds: boot_register_client creates the session with one reference (the conn's), the boot
\* loads classes through the client half (set_get_element allocates with db_private_alloc in the client hat)
TReg(s) ==
  /\ pc[s] = "reg"
  /\ sst' = [sst EXCEPT ![s] = "live"]
  /\ ref' = [ref EXCEPT ![s] = 1]
  /\ connRef' = [connRef EXCEPT ![s] = TRUE]
  /\ clsH' = [clsH EXCEPT ![s] = RouteP(s, "cl")]
  /\ ReleaseBoot(s)
  /\ Goto(s, "adopt")
  /\ UNCHANGED <<cst, orphan, owner, active, smx, cscp, adopted, orphL, work, tgt, aRef,
                 pvH, torn, sawArea, areaCnt, areaLive, TmVars, uaf, nested, badFree, areaUaf,
                 viaOrphan, daemonWaited, busyEnd>>

\* db_restart_ex fails after ws_init built the areas: no session; ws_init's error path (or the boot failure
\* cleanup) must not finalize the process-shared areas other sessions use
TBootFail(s) ==
  /\ pc[s] = "reg"
  /\ areaLive' = (areaLive /\ Mutant # "err_frees_areas")
  /\ ReleaseBoot(s)
  /\ Goto(s, "deact")
  /\ UNCHANGED <<cst, orphan, owner, active, sst, ref, smx, cscp, connRef, adopted, orphL, work, tgt, aRef,
                 clsH, pvH, torn, sawArea, areaCnt, TmVars, uaf, nested, badFree, areaUaf,
                 viaOrphan, daemonWaited, busyEnd>>

\* session_adopt_client_context: the session becomes the durable owner
TAdopt(s) ==
  /\ pc[s] = "adopt"
  /\ cscp' = [cscp EXCEPT ![s] = s]
  /\ adopted' = [adopted EXCEPT ![s] = TRUE]
  /\ Goto(s, "work")
  /\ UNCHANGED <<cst, orphan, owner, active, sst, ref, smx, connRef, orphL, work, tgt, aRef,
                 clsH, pvH, torn, bootMx, sawArea, areaCnt, areaLive, TmVars, uaf, nested, badFree, areaUaf,
                 viaOrphan, daemonWaited, busyEnd>>

WorkVars == <<cst, orphan, owner, active, sst, ref, smx, cscp, connRef, adopted, orphL, tgt, aRef,
              torn, bootMx, sawArea, areaCnt, areaLive, nested, viaOrphan, daemonWaited, busyEnd>>

CanWork(s) == pc[s] = "work" /\ work[s] < MaxWork
Step(s, l) == Goto(s, l) /\ work' = [work EXCEPT ![s] = @ + 1]

\* db_execute_statement: db_invalidate_mvcc_snapshot_before_statement (RC) sets the session's flag
TStmt(s) ==
  /\ CanWork(s)
  /\ SetInv(s, TRUE)
  /\ fresh' = [fresh EXCEPT ![s] = FALSE]
  /\ Touch(s)
  /\ Step(s, "enter1")
  /\ UNCHANGED <<WorkVars, clsH, pvH, badFree, rrHeld, rrMir, sharedMir, stale, unstable, rrBad>>

\* enter_server: drop the snapshot when the session's flag is set, and clear the flag
Enter(s) ==
  /\ IF InvOf(s)
     THEN /\ unstable' = (unstable \/ fresh[s])
          /\ fresh' = [fresh EXCEPT ![s] = TRUE]
          /\ SetInv(s, FALSE)
          /\ UNCHANGED stale
     ELSE /\ stale' = (stale \/ ~fresh[s])
          /\ UNCHANGED <<unstable, fresh, inv, sharedInv>>
  /\ UNCHANGED <<rrHeld, rrMir, sharedMir, rrBad>>

TEnter1(s) ==
  /\ pc[s] = "enter1"
  /\ Enter(s) /\ Touch(s)
  /\ Goto(s, "enter2")
  /\ UNCHANGED <<WorkVars, work, clsH, pvH, badFree>>

TEnter2(s) ==
  /\ pc[s] = "enter2"
  /\ Enter(s) /\ Touch(s)
  /\ Goto(s, "work")
  /\ UNCHANGED <<WorkVars, work, clsH, pvH, badFree>>

\* tran_lock_rep_read: skip when the session's mirror says the RR lock is held, else take it and set the mirror
TRR(s) ==
  /\ CanWork(s)
  /\ IF MirOf(s)
     THEN rrBad' = (rrBad \/ ~rrHeld[s]) /\ UNCHANGED <<rrHeld, rrMir, sharedMir>>
     ELSE rrHeld' = [rrHeld EXCEPT ![s] = TRUE] /\ SetMir(s, TRUE) /\ UNCHANGED rrBad
  /\ Touch(s)
  /\ Step(s, "work")
  /\ UNCHANGED <<WorkVars, clsH, pvH, badFree, inv, sharedInv, fresh, stale, unstable>>

\* a class is fetched (again) and a value container allocated: db_private_alloc in the client hat
TFetch(s) ==
  /\ CanWork(s)
  /\ clsH' = [clsH EXCEPT ![s] = IF @ = 0 THEN RouteP(s, "cl") ELSE @]
  /\ pvH' = [pvH EXCEPT ![s] = IF @ = 0 THEN RouteP(s, "cl") ELSE @]
  /\ Touch(s)
  /\ Step(s, "work")
  /\ UNCHANGED <<WorkVars, badFree, TmVars>>

\* tran_abort (ROLLBACK, or the client's reaction to a deadlock victim): ws_abort_mops decaches the classes,
\* classobj_free_class_constraints frees through db_ws_free; the transaction's RR lock and mirror go
TRollback(s) ==
  /\ CanWork(s)
  /\ badFree' = (badFree \/ (clsH[s] # 0 /\ clsH[s] # active[s]))
  /\ clsH' = [clsH EXCEPT ![s] = 0]
  /\ rrHeld' = [rrHeld EXCEPT ![s] = FALSE]
  /\ SetMir(s, FALSE)
  /\ Touch(s)
  /\ Step(s, "work")
  /\ UNCHANGED <<WorkVars, pvH, inv, sharedInv, fresh, stale, unstable, rrBad>>

\* a server-half allocation of a call freed by the client half after the call returns
TXfer(s) ==
  /\ Xfer /\ CanWork(s)
  /\ badFree' = (badFree \/ RouteP(s, "sv") # RouteP(s, "cl"))
  /\ Touch(s)
  /\ Step(s, "work")
  /\ UNCHANGED <<WorkVars, clsH, pvH, TmVars>>

\* a session call that takes the session mutex (session_check_session / session_state_destroy shape); only a
\* thread whose connection holds the session reaches the session
TSessOp(s) ==
  /\ CanWork(s) /\ connRef[s]
  /\ smx[s] = 0
  /\ Touch(s)
  /\ Step(s, "work")
  /\ UNCHANGED <<WorkVars, clsH, pvH, badFree, TmVars>>

\* db_end_session from inside the bracket: xsession_end_session -> session_state_destroy, first step: the
\* session mutex
TEnd1(s) ==
  /\ CanWork(s) /\ connRef[s]
  /\ smx[s] = 0
  /\ smx' = [smx EXCEPT ![s] = s]
  /\ Touch(s)
  /\ Step(s, "end2")
  /\ UNCHANGED <<cst, orphan, owner, active, sst, ref, cscp, connRef, adopted, orphL, tgt, aRef,
                 clsH, pvH, torn, bootMx, sawArea, areaCnt, areaLive, TmVars, nested, badFree,
                 viaOrphan, daemonWaited, busyEnd>>

TEnd2(s) ==
  /\ pc[s] = "end2"
  /\ EndSess(s, s, "work")
  /\ connRef' = [connRef EXCEPT ![s] = FALSE]
  /\ UNCHANGED <<cst, owner, active, adopted, orphL, work, tgt, aRef, clsH, pvH, torn, bootMx, sawArea,
                 areaCnt, areaLive, TmVars, uaf, badFree, areaUaf, viaOrphan, daemonWaited>>

TDoneWork(s) ==
  /\ pc[s] = "work"
  /\ Goto(s, "unreg")
  /\ UNCHANGED <<cst, orphan, owner, active, sst, ref, smx, cscp, connRef, adopted, orphL, work, tgt, aRef,
                 clsH, pvH, torn, bootMx, sawArea, areaCnt, areaLive, TmVars, uaf, nested, badFree, areaUaf,
                 viaOrphan, daemonWaited, busyEnd>>

\* boot_unregister_client (the transaction logs out: its RR lock goes) and css_free_conn (the conn's session
\* reference goes), both still inside the bracket
TUnreg(s) ==
  /\ pc[s] = "unreg"
  /\ ref' = [ref EXCEPT ![s] = IF connRef[s] THEN @ - 1 ELSE @]
  /\ connRef' = [connRef EXCEPT ![s] = FALSE]
  /\ rrHeld' = [rrHeld EXCEPT ![s] = FALSE]
  /\ SetMir(s, FALSE)
  /\ Goto(s, IF Mutant = "sessop_unref" THEN "late_op" ELSE "deact")
  /\ UNCHANGED <<cst, orphan, owner, active, sst, smx, cscp, adopted, orphL, work, tgt, aRef,
                 clsH, pvH, torn, bootMx, sawArea, areaCnt, areaLive, inv, sharedInv, fresh, stale, unstable, rrBad,
                 uaf, nested, badFree, areaUaf, viaOrphan, daemonWaited, busyEnd>>

\* mutant: a session call after the conn released the session, still inside the bracket
TLateOp(s) ==
  /\ pc[s] = "late_op"
  /\ smx[s] = 0
  /\ Goto(s, "deact")
  /\ UNCHANGED <<cst, orphan, owner, active, sst, ref, smx, cscp, connRef, adopted, orphL, work, tgt, aRef,
                 clsH, pvH, torn, bootMx, sawArea, areaCnt, areaLive, TmVars, uaf, nested, badFree, areaUaf,
                 viaOrphan, daemonWaited, busyEnd>>

TDeact(s) ==
  /\ pc[s] = "deact"
  /\ Deact(s, "unlock")
  /\ UNCHANGED <<cst, orphan, owner, sst, ref, smx, cscp, connRef, adopted, work, aRef,
                 bootMx, sawArea, areaCnt, TmVars, nested, areaUaf, viaOrphan, daemonWaited, busyEnd>>

TUnlock(s) ==
  /\ pc[s] = "unlock"
  /\ Unlock(s, "del", "reread")
  /\ UNCHANGED <<cst, orphan, active, sst, ref, smx, cscp, connRef, adopted, orphL, work, tgt, aRef,
                 clsH, pvH, torn, bootMx, sawArea, areaCnt, areaLive, TmVars, uaf, nested, badFree, areaUaf,
                 viaOrphan, daemonWaited, busyEnd>>

TReread(s) ==
  /\ pc[s] = "reread"
  /\ Reread(s, "del")
  /\ UNCHANGED <<cst, orphan, owner, active, sst, ref, smx, cscp, connRef, adopted, work, tgt, aRef,
                 clsH, pvH, torn, bootMx, sawArea, areaCnt, areaLive, TmVars, nested, badFree, areaUaf,
                 viaOrphan, daemonWaited, busyEnd>>

TDel(s) ==
  /\ pc[s] = "del"
  /\ Del(s, "na")
  /\ UNCHANGED <<orphan, owner, active, sst, ref, smx, cscp, connRef, adopted, orphL, work, tgt, aRef,
                 clsH, pvH, torn, bootMx, sawArea, areaCnt, areaLive, TmVars, nested, badFree, areaUaf,
                 daemonWaited, busyEnd>>

\* a context no session adopted (boot failed) is retired by its creator
TNotAdopted(s) ==
  /\ pc[s] = "na"
  /\ Goto(s, IF ~adopted[s] /\ cst[s] = "live" THEN "r_act" ELSE "done")
  /\ UNCHANGED <<cst, orphan, owner, active, sst, ref, smx, cscp, connRef, adopted, orphL, work, tgt, aRef,
                 clsH, pvH, torn, bootMx, sawArea, areaCnt, areaLive, TmVars, uaf, nested, badFree, areaUaf,
                 viaOrphan, daemonWaited, busyEnd>>

TRAct(s) ==
  /\ pc[s] = "r_act"
  /\ Acquire(s, s, "r_tear")
  /\ UNCHANGED <<cst, orphan, sst, ref, smx, cscp, connRef, adopted, orphL, work, tgt, aRef,
                 clsH, pvH, torn, bootMx, sawArea, areaCnt, areaLive, TmVars, badFree, areaUaf, viaOrphan, busyEnd>>

TRTear(s) ==
  /\ pc[s] = "r_tear"
  /\ Teardown(s, s)
  /\ active' = [active EXCEPT ![s] = 0]
  /\ owner' = [owner EXCEPT ![s] = 0]
  /\ cst' = [cst EXCEPT ![s] = "freed"]
  /\ Goto(s, "done")
  /\ UNCHANGED <<orphan, sst, ref, smx, cscp, connRef, adopted, orphL, work, tgt, aRef,
                 bootMx, sawArea, areaCnt, TmVars, uaf, nested, areaUaf, viaOrphan, daemonWaited, busyEnd>>

(* ---- attacher ---- *)

\* session_check_session: find the session under its mutex and take a reference
ARef ==
  /\ pc[A] = "a_ref"
  /\ \/ \E s \in Sess :
          /\ sst[s] = "live" /\ smx[s] = 0
          /\ ref' = [ref EXCEPT ![s] = @ + 1]
          /\ tgt' = [tgt EXCEPT ![A] = s]
          /\ aRef' = TRUE
          /\ Goto(A, "a_read")
     \/ /\ \A t \in Sess : pc[t] \in Terminal
        /\ Goto(A, "done") /\ UNCHANGED <<ref, tgt, aRef>>
  /\ UNCHANGED <<cst, orphan, owner, active, sst, smx, cscp, connRef, adopted, orphL, work,
                 clsH, pvH, torn, bootMx, sawArea, areaCnt, areaLive, TmVars, uaf, nested, badFree, areaUaf,
                 viaOrphan, daemonWaited, busyEnd>>

\* read csc_p under the reference
ARead ==
  /\ pc[A] = "a_read"
  /\ IF cscp[tgt[A]] = 0
     THEN Goto(A, "a_unref")
     ELSE Goto(A, IF Mutant = "a_unref_early" THEN "a_unref0" ELSE "a_act")
  /\ UNCHANGED <<cst, orphan, owner, active, sst, ref, smx, cscp, connRef, adopted, orphL, work, tgt, aRef,
                 clsH, pvH, torn, bootMx, sawArea, areaCnt, areaLive, TmVars, uaf, nested, badFree, areaUaf,
                 viaOrphan, daemonWaited, busyEnd>>

\* mutant: the reference goes before the bracket is taken
AUnrefEarly ==
  /\ pc[A] = "a_unref0"
  /\ ref' = [ref EXCEPT ![tgt[A]] = @ - 1]
  /\ aRef' = FALSE
  /\ Goto(A, "a_act")
  /\ UNCHANGED <<cst, orphan, owner, active, sst, smx, cscp, connRef, adopted, orphL, work, tgt,
                 clsH, pvH, torn, bootMx, sawArea, areaCnt, areaLive, TmVars, uaf, nested, badFree, areaUaf,
                 viaOrphan, daemonWaited, busyEnd>>

AAct ==
  /\ pc[A] = "a_act"
  /\ Acquire(A, tgt[A], "a_work")
  /\ UNCHANGED <<cst, orphan, sst, ref, smx, cscp, connRef, adopted, orphL, work, tgt, aRef,
                 clsH, pvH, torn, bootMx, sawArea, areaCnt, areaLive, TmVars, badFree, areaUaf, viaOrphan, busyEnd>>

\* client-half work in the bracket (allocates a value container), then leave or end the session
AWork ==
  /\ pc[A] = "a_work"
  /\ Touch(A)
  /\ pvH' = [pvH EXCEPT ![tgt[A]] = IF @ = 0 THEN RouteP(A, "cl") ELSE @]
  /\ \/ Goto(A, "a_deact") /\ UNCHANGED smx
     \/ aRef /\ smx[tgt[A]] = 0 /\ smx' = [smx EXCEPT ![tgt[A]] = A] /\ Goto(A, "a_end2")
  /\ UNCHANGED <<cst, orphan, owner, active, sst, ref, cscp, connRef, adopted, orphL, work, tgt, aRef,
                 clsH, torn, bootMx, sawArea, areaCnt, areaLive, TmVars, nested, badFree,
                 viaOrphan, daemonWaited, busyEnd>>

AEnd2 ==
  /\ pc[A] = "a_end2"
  /\ EndSess(A, tgt[A], "a_deact")
  /\ aRef' = FALSE
  /\ UNCHANGED <<cst, owner, active, connRef, adopted, orphL, work, tgt, clsH, pvH, torn, bootMx, sawArea,
                 areaCnt, areaLive, TmVars, uaf, badFree, areaUaf, viaOrphan, daemonWaited>>

ADeact ==
  /\ pc[A] = "a_deact"
  /\ Deact(A, "a_unlock")
  /\ UNCHANGED <<cst, orphan, owner, sst, ref, smx, cscp, connRef, adopted, work, aRef,
                 bootMx, sawArea, areaCnt, TmVars, nested, areaUaf, viaOrphan, daemonWaited, busyEnd>>

AUnlock ==
  /\ pc[A] = "a_unlock"
  /\ Unlock(A, "a_del", "a_reread")
  /\ UNCHANGED <<cst, orphan, active, sst, ref, smx, cscp, connRef, adopted, orphL, work, tgt, aRef,
                 clsH, pvH, torn, bootMx, sawArea, areaCnt, areaLive, TmVars, uaf, nested, badFree, areaUaf,
                 viaOrphan, daemonWaited, busyEnd>>

AReread ==
  /\ pc[A] = "a_reread"
  /\ Reread(A, "a_del")
  /\ UNCHANGED <<cst, orphan, owner, active, sst, ref, smx, cscp, connRef, adopted, work, tgt, aRef,
                 clsH, pvH, torn, bootMx, sawArea, areaCnt, areaLive, TmVars, nested, badFree, areaUaf,
                 viaOrphan, daemonWaited, busyEnd>>

ADel ==
  /\ pc[A] = "a_del"
  /\ Del(A, "a_unref")
  /\ UNCHANGED <<orphan, owner, active, sst, ref, smx, cscp, connRef, adopted, orphL, work, tgt, aRef,
                 clsH, pvH, torn, bootMx, sawArea, areaCnt, areaLive, TmVars, nested, badFree, areaUaf,
                 daemonWaited, busyEnd>>

\* the request ends: its reference goes (css_shutdown_conn / the request's own decrement)
AUnref ==
  /\ pc[A] = "a_unref"
  /\ ref' = [ref EXCEPT ![tgt[A]] = IF aRef THEN @ - 1 ELSE @]
  /\ aRef' = FALSE
  /\ Goto(A, "done")
  /\ UNCHANGED <<cst, orphan, owner, active, sst, smx, cscp, connRef, adopted, orphL, work, tgt,
                 clsH, pvH, torn, bootMx, sawArea, areaCnt, areaLive, TmVars, uaf, nested, badFree, areaUaf,
                 viaOrphan, daemonWaited, busyEnd>>

(* ---- daemon: session_remove_expired_sessions ---- *)

\* an expired session (no reference, timed out) is found and locked; the timeout is a nondeterministic choice
DScan ==
  /\ pc[D] = "d_scan"
  /\ \/ \E s \in Sess :
          /\ sst[s] = "live" /\ ref[s] = 0 /\ smx[s] = 0
          /\ smx' = [smx EXCEPT ![s] = D]
          /\ tgt' = [tgt EXCEPT ![D] = s]
          /\ Goto(D, "d_uninit")
     \/ /\ \A t \in Thr \ {D} : pc[t] \in Terminal
        /\ \A s \in Sess : sst[s] # "live"
        /\ Goto(D, "done") /\ UNCHANGED <<smx, tgt>>
  /\ UNCHANGED <<cst, orphan, owner, active, sst, ref, cscp, connRef, adopted, orphL, work, aRef,
                 clsH, pvH, torn, bootMx, sawArea, areaCnt, areaLive, TmVars, uaf, nested, badFree, areaUaf,
                 viaOrphan, daemonWaited, busyEnd>>

\* session_state_uninit: retire the adopted context (the daemon is never inside one)
DUninit ==
  /\ pc[D] = "d_uninit"
  /\ Goto(D, IF cscp[tgt[D]] # 0 THEN "d_act" ELSE "d_erase")
  /\ daemonWaited' = (daemonWaited \/ (cscp[tgt[D]] # 0 /\ owner[tgt[D]] # 0))
  /\ UNCHANGED <<cst, orphan, owner, active, sst, ref, smx, cscp, connRef, adopted, orphL, work, tgt, aRef,
                 clsH, pvH, torn, bootMx, sawArea, areaCnt, areaLive, TmVars, uaf, nested, badFree, areaUaf,
                 viaOrphan, busyEnd>>

\* csc_retire_and_delete: csc_activate (waits for a bracket the session's last client still holds)
DAct ==
  /\ pc[D] = "d_act"
  /\ Acquire(D, tgt[D], "d_tear")
  /\ UNCHANGED <<cst, orphan, sst, ref, smx, cscp, connRef, adopted, orphL, work, tgt, aRef,
                 clsH, pvH, torn, bootMx, sawArea, areaCnt, areaLive, TmVars, badFree, areaUaf, viaOrphan, busyEnd>>

\* csc_teardown, csc_deactivate, delete
DTear ==
  /\ pc[D] = "d_tear"
  /\ Teardown(D, tgt[D])
  /\ active' = [active EXCEPT ![D] = 0]
  /\ owner' = [owner EXCEPT ![tgt[D]] = IF Mutant = "no_mutex" THEN @ ELSE 0]
  /\ Goto(D, "d_del")
  /\ UNCHANGED <<cst, orphan, sst, ref, smx, cscp, connRef, adopted, orphL, work, tgt, aRef,
                 bootMx, sawArea, areaCnt, TmVars, uaf, nested, areaUaf, viaOrphan, daemonWaited, busyEnd>>

DDel ==
  /\ pc[D] = "d_del"
  /\ uaf' = (uaf \/ cst[tgt[D]] # "live")
  /\ cst' = [cst EXCEPT ![tgt[D]] = IF Mutant = "no_delete" THEN @ ELSE "freed"]
  /\ Goto(D, "d_erase")
  /\ UNCHANGED <<orphan, owner, active, sst, ref, smx, cscp, connRef, adopted, orphL, work, tgt, aRef,
                 clsH, pvH, torn, bootMx, sawArea, areaCnt, areaLive, TmVars, nested, badFree, areaUaf,
                 viaOrphan, daemonWaited, busyEnd>>

\* erase_locked: the session leaves the hash and its mutex is released
DErase ==
  /\ pc[D] = "d_erase"
  /\ sst' = [sst EXCEPT ![tgt[D]] = "gone"]
  /\ cscp' = [cscp EXCEPT ![tgt[D]] = 0]
  /\ smx' = [smx EXCEPT ![tgt[D]] = 0]
  /\ Goto(D, "d_scan")
  /\ UNCHANGED <<cst, orphan, owner, active, ref, connRef, adopted, orphL, work, tgt, aRef,
                 clsH, pvH, torn, bootMx, sawArea, areaCnt, areaLive, TmVars, uaf, nested, badFree, areaUaf,
                 viaOrphan, daemonWaited, busyEnd>>

Finished == /\ \A t \in Thr : pc[t] \in Terminal
            /\ UNCHANGED vars

TStep(s) ==
  \/ TNew(s) \/ TAct(s) \/ TBootLock(s) \/ TAreaCheck(s) \/ TAreaMake(s) \/ TReg(s) \/ TBootFail(s)
  \/ TAdopt(s) \/ TStmt(s) \/ TEnter1(s) \/ TEnter2(s) \/ TRR(s) \/ TFetch(s) \/ TRollback(s) \/ TXfer(s)
  \/ TSessOp(s) \/ TEnd1(s) \/ TEnd2(s) \/ TDoneWork(s) \/ TUnreg(s) \/ TLateOp(s) \/ TDeact(s)
  \/ TUnlock(s) \/ TReread(s) \/ TDel(s) \/ TNotAdopted(s) \/ TRAct(s) \/ TRTear(s)

AStep == ARef \/ ARead \/ AUnrefEarly \/ AAct \/ AWork \/ AEnd2 \/ ADeact \/ AUnlock \/ AReread \/ ADel \/ AUnref

DStep == DScan \/ DUninit \/ DAct \/ DTear \/ DDel \/ DErase

Next ==
  \/ \E s \in Sess : TNew(s) \/ TAct(s) \/ TBootLock(s) \/ TAreaCheck(s) \/ TAreaMake(s) \/ TReg(s)
  \/ \E s \in Sess : TBootFail(s) \/ TAdopt(s) \/ TStmt(s) \/ TEnter1(s) \/ TEnter2(s) \/ TRR(s)
  \/ \E s \in Sess : TFetch(s) \/ TRollback(s) \/ TXfer(s) \/ TSessOp(s) \/ TEnd1(s) \/ TEnd2(s)
  \/ \E s \in Sess : TDoneWork(s) \/ TUnreg(s) \/ TLateOp(s) \/ TDeact(s) \/ TUnlock(s) \/ TReread(s)
  \/ \E s \in Sess : TDel(s) \/ TNotAdopted(s) \/ TRAct(s) \/ TRTear(s)
  \/ ARef \/ ARead \/ AUnrefEarly \/ AAct \/ AWork \/ AEnd2 \/ ADeact \/ AUnlock \/ AReread \/ ADel \/ AUnref
  \/ DScan \/ DUninit \/ DAct \/ DTear \/ DDel \/ DErase
  \/ Finished

\* weak fairness per thread; a boot failure is a fault, not a step a fair scheduler must take
Fairness ==
  /\ \A s \in Sess : WF_vars(TStep(s) /\ ~TBootFail(s))
  /\ WF_vars(AStep)
  /\ WF_vars(DStep)

Spec == Init /\ [][Next]_vars /\ Fairness

(* ---- properties ---- *)

TLab == {"new", "act", "bootlk", "area", "area2", "reg", "adopt", "work", "enter1", "enter2", "end2", "unreg",
         "late_op", "deact", "unlock", "reread", "del", "na", "r_act", "r_tear", "done", "abort"}
ALab == {"a_ref", "a_read", "a_unref0", "a_act", "a_work", "a_end2", "a_deact", "a_unlock", "a_reread", "a_del",
         "a_unref", "done", "abort"}
DLab == {"d_scan", "d_uninit", "d_act", "d_tear", "d_del", "d_erase", "done", "abort"}

TypeOK ==
  /\ pc \in [Thr -> TLab \cup ALab \cup DLab]
  /\ cst \in [Sess -> {"none", "live", "freed"}]
  /\ orphan \in [Sess -> BOOLEAN]
  /\ owner \in [Sess -> 0..(N + 2)]
  /\ active \in [Thr -> 0..N]
  /\ sst \in [Sess -> {"none", "live", "gone"}]
  /\ ref \in [Sess -> 0..3]
  /\ smx \in [Sess -> 0..(N + 2)]
  /\ cscp \in [Sess -> 0..N]
  /\ tgt \in [Thr -> 0..N]
  /\ torn \in [Sess -> 0..3]

\* C1: a context's state is touched only by the thread whose bracket holds it, one thread at a time
Excl == \A t1, t2 \in Thr : (t1 # t2 /\ active[t1] # 0) => active[t1] # active[t2]

\* C2: no thread is inside, waits for, or deletes a context that was deleted
NoUAF == ~uaf /\ \A t \in Thr : active[t] # 0 => cst[active[t]] = "live"
NoWaitFreed == \A t \in Thr : AcqTarget(t) # 0 => cst[AcqTarget(t)] # "freed"

\* C3: brackets never nest (the retiring thread inside its own context never re-activates it)
NoNest == ~nested

\* C4: every free lands on the heap its chunk came from, and the process-shared areas are created once and
\* outlive every session's use
NoForeignFree == ~badFree
AreaOnce == areaCnt <= 1 /\ ~areaUaf

\* C2/C5: a deleted context was torn down exactly once
TornOnce == \A s \in Sess : torn[s] <= 1 /\ (cst[s] = "freed" => torn[s] = 1)

\* C6 (A3 per session): RC snapshots stay per statement, the RR mirror never claims a lock the session lacks
FreshSnapshot == ~stale
StableSnapshot == ~unstable
RRMirror == ~rrBad

\* C5: every context is eventually torn down and deleted
AllFreed == <>(\A s \in Sess : cst[s] = "freed")

(* ---- inductive invariant ---- *)

TPre == {"new", "act", "bootlk", "area", "area2", "reg"}
TIn == {"bootlk", "area", "area2", "reg", "adopt", "work", "enter1", "enter2", "end2", "unreg", "deact", "r_tear"}
TOwn == TIn \cup {"unlock"}
TWork == {"work", "enter1", "enter2", "end2", "unreg"}
AOwn == {"a_work", "a_end2", "a_deact", "a_unlock"}
AIn == {"a_work", "a_end2", "a_deact"}
DHold == {"d_uninit", "d_act", "d_tear", "d_del", "d_erase"}
B(b) == IF b THEN 1 ELSE 0
ARefOn(s) == aRef /\ tgt[A] = s

R_type ==
  /\ pc \in [Thr -> TLab \cup ALab \cup DLab]
  /\ cst \in [Sess -> {"none", "live", "freed"}]
  /\ orphan \in [Sess -> BOOLEAN]
  /\ owner \in [Sess -> 0..(N + 2)]
  /\ active \in [Thr -> 0..N]
  /\ sst \in [Sess -> {"none", "live", "gone"}]
  /\ ref \in [Sess -> 0..2]
  /\ smx \in [Sess -> 0..(N + 2)]
  /\ cscp \in [Sess -> 0..N]
  /\ connRef \in [Sess -> BOOLEAN]
  /\ adopted \in [Sess -> BOOLEAN]
  /\ orphL \in [Thr -> BOOLEAN]
  /\ work \in [Thr -> Nat] /\ \A t \in Thr : work[t] <= MaxWork
  /\ tgt \in [Thr -> 0..N]
  /\ aRef \in BOOLEAN
  /\ clsH \in [Sess -> 0..N]
  /\ pvH \in [Sess -> 0..N]
  /\ torn \in [Sess -> 0..1]
  /\ bootMx \in 0..N
  /\ sawArea \in [Thr -> BOOLEAN]
  /\ areaCnt \in 0..1
  /\ areaLive \in BOOLEAN
  /\ inv \in [Sess -> BOOLEAN]
  /\ sharedInv = FALSE
  /\ fresh \in [Sess -> BOOLEAN]
  /\ rrHeld \in [Sess -> BOOLEAN]
  /\ rrMir \in [Sess -> BOOLEAN]
  /\ sharedMir = FALSE
  /\ uaf = FALSE /\ nested = FALSE /\ badFree = FALSE /\ areaUaf = FALSE
  /\ stale = FALSE /\ unstable = FALSE /\ rrBad = FALSE
  /\ viaOrphan \in BOOLEAN /\ daemonWaited \in BOOLEAN /\ busyEnd \in BOOLEAN

\* roles stay on their own labels; no mutant label is reached
R_pc ==
  /\ \A s \in Sess : pc[s] \in TLab \ {"late_op", "reread", "abort"}
  /\ pc[A] \in ALab \ {"a_unref0", "a_reread", "abort"}
  /\ pc[D] \in DLab \ {"abort"}
  /\ ~Attach => pc[A] = "done"

\* the bracket: the thread_local and the mutex
R_bracket ==
  /\ \A s \in Sess : active[s] = (IF pc[s] \in TIn THEN s ELSE 0)
  /\ active[A] = (IF pc[A] \in AIn THEN tgt[A] ELSE 0)
  /\ active[D] = (IF pc[D] = "d_tear" THEN tgt[D] ELSE 0)
  /\ \A s \in Sess : pc[s] \in TOwn => owner[s] = s
  /\ pc[A] \in AOwn => owner[tgt[A]] = A
  /\ pc[D] = "d_tear" => owner[tgt[D]] = D
  /\ \A c \in Sess : owner[c] # 0 =>
       \/ owner[c] = c /\ pc[c] \in TOwn
       \/ owner[c] = A /\ tgt[A] = c /\ pc[A] \in AOwn
       \/ owner[c] = D /\ tgt[D] = c /\ pc[D] = "d_tear"
  /\ \A s \in Sess : pc[s] = "act" => owner[s] = 0
  /\ orphL[D] = FALSE

\* targets
R_tgt ==
  /\ \A s \in Sess : tgt[s] \in {0, s} /\ (pc[s] \in {"unlock", "del"} => tgt[s] = s)
  /\ (pc[A] \notin {"a_ref", "done"} \/ aRef \/ orphL[A]) => tgt[A] \in Sess
  /\ pc[D] \in DHold => tgt[D] \in Sess
  /\ work[A] = 0 /\ work[D] = 0

\* the session, its references and its mutex
R_sess ==
  /\ \A s \in Sess : ref[s] = B(connRef[s]) + B(ARefOn(s))
  /\ \A s \in Sess : connRef[s] => pc[s] \in {"adopt"} \cup TWork /\ sst[s] = "live"
  /\ \A s \in Sess : pc[s] = "end2" => connRef[s]
  /\ \A s \in Sess : pc[s] = "adopt" => sst[s] = "live" /\ connRef[s] /\ cscp[s] = 0 /\ ~adopted[s]
  /\ \A s \in Sess : pc[s] \in TPre => sst[s] = "none" /\ ~adopted[s] /\ cst[s] = (IF pc[s] = "new" THEN "none" ELSE "live")
  /\ \A s \in Sess : pc[s] # "new" => cst[s] # "none"
  /\ \A s \in Sess : adopted[s] => pc[s] \in TWork \cup {"deact", "unlock", "del", "na", "done"}
  /\ \A s \in Sess : sst[s] = "none" => ~adopted[s] /\ ~connRef[s] /\ cscp[s] = 0 /\ pc[s] \notin TWork \cup {"adopt"}
  /\ \A s \in Sess : sst[s] = "live" => (adopted[s] \/ pc[s] = "adopt")
  /\ \A s \in Sess : sst[s] = "live" /\ adopted[s] => cscp[s] = s
  /\ \A s \in Sess : cscp[s] # 0 => cscp[s] = s /\ sst[s] = "live" /\ adopted[s]
  /\ \A s \in Sess : sst[s] = "gone" => adopted[s] /\ cscp[s] = 0 /\ ~connRef[s] /\ ~ARefOn(s)
  /\ \A s \in Sess : sst[s] = "gone" /\ ~orphan[s] => cst[s] = "freed"
  /\ \A s \in Sess : sst[s] = "live" /\ ~(pc[D] \in {"d_del", "d_erase"} /\ tgt[D] = s) => cst[s] = "live" /\ torn[s] = 0
  /\ \A s \in Sess : ~adopted[s] /\ pc[s] \in {"deact", "unlock", "del", "na", "r_act", "r_tear"} => cst[s] = "live" /\ torn[s] = 0
  /\ \A s \in Sess : ~adopted[s] /\ pc[s] = "done" => cst[s] = "freed"
  /\ \A c \in Sess : smx[c] # 0 =>
       \/ smx[c] = D /\ pc[D] \in DHold /\ tgt[D] = c
       \/ smx[c] = c /\ pc[c] = "end2"
       \/ smx[c] = A /\ pc[A] = "a_end2" /\ tgt[A] = c
  /\ \A s \in Sess : pc[s] = "end2" => smx[s] = s
  /\ pc[A] = "a_end2" => smx[tgt[A]] = A
  /\ pc[D] \in DHold => smx[tgt[D]] = D

\* the attacher holds its reference from the lookup through the bracket
R_attach ==
  /\ aRef => pc[A] \in {"a_read", "a_act", "a_work", "a_end2", "a_deact", "a_unlock", "a_del", "a_unref"}
  /\ pc[A] \in {"a_read", "a_act", "a_work", "a_end2"} => aRef
  /\ aRef => sst[tgt[A]] = "live" /\ ~orphan[tgt[A]] /\ cst[tgt[A]] = "live"
  /\ pc[A] \in {"a_act", "a_work", "a_end2", "a_deact", "a_unlock", "a_del"} /\ aRef => cscp[tgt[A]] = tgt[A]
  /\ pc[A] \in {"a_deact", "a_unlock", "a_del"} /\ ~aRef => orphan[tgt[A]]
  /\ pc[A] \in {"a_unlock", "a_del"} => (orphL[A] <=> ~aRef)
  /\ pc[A] \in {"a_act", "a_work", "a_end2", "a_deact", "a_unlock", "a_del"} => cst[tgt[A]] = "live"
  /\ orphL[A] => pc[A] \in {"a_unlock", "a_del", "a_unref", "done"} /\ orphan[tgt[A]]
  /\ orphL[A] /\ pc[A] \in {"a_unref", "done"} => cst[tgt[A]] = "freed"
  /\ pc[A] \in {"a_ref", "done"} => ~aRef
  /\ pc[A] \in {"a_work", "a_end2", "a_deact", "a_unlock", "a_del"} => pc[tgt[A]] \in {"del", "na", "done"}

\* the daemon holds the session mutex of an unreferenced, adopted session from the scan to the erase
R_daemon ==
  /\ pc[D] \in DHold => sst[tgt[D]] = "live" /\ ref[tgt[D]] = 0 /\ ~orphan[tgt[D]]
  /\ pc[D] \in {"d_uninit", "d_act", "d_tear", "d_del"} => cscp[tgt[D]] = tgt[D]
  /\ pc[D] \in {"d_uninit", "d_act", "d_tear"} => cst[tgt[D]] = "live" /\ torn[tgt[D]] = 0
  /\ pc[D] = "d_del" => cst[tgt[D]] = "live" /\ torn[tgt[D]] = 1 /\ owner[tgt[D]] = 0
  /\ pc[D] = "d_erase" => cst[tgt[D]] = "freed"
  /\ pc[D] \in {"d_tear", "d_del", "d_erase"} => pc[tgt[D]] \in {"del", "na", "done"}
  /\ pc[D] = "done" => (\A t \in Thr \ {D} : pc[t] \in Terminal) /\ \A s \in Sess : sst[s] # "live"

\* orphaned contexts: the ender is inside it until the bracket exit deletes it
R_orphan ==
  /\ \A c \in Sess : orphan[c] => adopted[c] /\ sst[c] = "gone"
  /\ \A c \in Sess : orphan[c] /\ torn[c] = 0 =>
       \/ pc[c] \in {"work", "enter1", "enter2", "unreg", "deact"}
       \/ pc[A] = "a_deact" /\ tgt[A] = c
  /\ \A c \in Sess : torn[c] = 1 /\ cst[c] = "live" =>
       \/ orphan[c] /\ pc[c] \in {"unlock", "del"} /\ orphL[c]
       \/ orphan[c] /\ pc[A] \in {"a_unlock", "a_del"} /\ tgt[A] = c /\ orphL[A]
       \/ ~orphan[c] /\ pc[D] = "d_del" /\ tgt[D] = c
  /\ \A c \in Sess : cst[c] # "live" => torn[c] = (IF cst[c] = "freed" THEN 1 ELSE 0)
  /\ \A s \in Sess : cst[s] = "freed" => pc[s] \in {"del", "na", "done"}
  /\ \A s \in Sess : orphL[s] => orphan[s] /\ pc[s] \in {"unlock", "del", "na", "done"}
  /\ \A s \in Sess : orphL[s] /\ pc[s] \in {"na", "done"} => cst[s] = "freed"
  /\ \A s \in Sess : orphL[s] /\ pc[s] \in {"unlock", "del"} => cst[s] = "live" /\ torn[s] = 1
  /\ orphL[A] /\ pc[A] \in {"a_unlock", "a_del"} => torn[tgt[A]] = 1
  /\ \A s \in Sess : pc[s] \in {"r_act", "r_tear"} => ~orphan[s]
  /\ \A s \in Sess : ~(orphL[s] /\ orphL[A] /\ tgt[A] = s)
  /\ \A s \in Sess : orphL[s] => ~(tgt[A] = s /\ pc[A] \in {"a_act", "a_work", "a_end2", "a_deact", "a_unlock", "a_del"})

\* heaps: client-half chunks live in the session's own workspace heap
R_heap == \A s \in Sess : clsH[s] \in {0, s} /\ pvH[s] \in {0, s}

\* areas: created once under the boot lock, alive once a tracer booted
R_area ==
  /\ areaLive = (areaCnt = 1)
  /\ ServerInit => areaCnt = 1
  /\ \A s \in Sess : (bootMx = s) = (~ServerInit /\ pc[s] \in {"area", "area2", "reg"})
  /\ \A s \in Sess : pc[s] = "area2" => areaCnt = (IF sawArea[s] THEN 1 ELSE 0)
  /\ \A s \in Sess : pc[s] \notin {"new", "act", "bootlk", "area", "area2"} => areaCnt = 1

\* client transaction state: the flag lives between the statement start and its first enter
R_tm ==
  /\ \A s \in Sess : inv[s] = (pc[s] = "enter1")
  /\ \A s \in Sess : pc[s] = "enter1" => ~fresh[s]
  /\ \A s \in Sess : pc[s] = "enter2" => fresh[s]
  /\ \A s \in Sess : rrMir[s] => rrHeld[s]

IndInv == R_type /\ R_pc /\ R_bracket /\ R_tgt /\ R_sess /\ R_attach /\ R_daemon /\ R_orphan /\ R_heap /\ R_area /\ R_tm

\* Apalache: the role sets fixed, the work bound open
CInit ==
  /\ N = 2 /\ MaxWork \in Nat /\ MaxWork >= 1
  /\ Attach \in BOOLEAN /\ Xfer = FALSE /\ ServerInit \in BOOLEAN /\ Mutant = "none"

\* witnesses
NotViaOrphan == ~viaOrphan
NotDaemonWaited == ~daemonWaited
NotBusyEnd == ~busyEnd
NotBootFailRetired == ~(\E s \in Sess : ~adopted[s] /\ cst[s] = "freed")

=============================================================================
