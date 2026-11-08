------------------------------ MODULE MethodFold ------------------------------
(* CBRD-27430 A7: the method/SP callback of a folded session terminates in-process.

   Extends the A4 model of one client context (csc) per session (CscSessions, linked from
   docs/tla/CBRD-27430-A4, constant ServerInit = TRUE as in A5) with what A7 changes. A statement of a
   folded session runs on its tracer thread, inside the session's activation bracket, in the server hat;
   when it evaluates a stored procedure or method, the PL executor raises callbacks (SQL semantics,
   INTERNAL_JDBC queries, end transaction, the builtin C method protocol) toward "the client"
   (xs_callback_send / xs_callback_receive). In CS they crossed the wire to the CAS, which ran them in its
   own process and thread. In the fold:

   - a callback raised on a thread that holds a bracket is dispatched on that very thread
     (method_dispatch): the hat switches to the client half, the session's libcas depth counts the
     nesting, an error-stack frame isolates the outer executor's error state, and the client half's
     clear-all stops at that frame (the floor); a thread without a bracket keeps the wire path;
   - the callback handler (the query handles a PL routine keeps, which refer to the session's MOPs) and
     the builtin methods' runtime arguments live in the session's csc, not in one process object; a
     transaction boundary defers the handles, the outermost dispatch exit frees the deferred ones, and
     csc_teardown retires the rest inside the bracket before ws_final;
   - cubpl::get_session admits a bracket thread (the tracer is not a TT_WORKER);
   - a nested query on the same thread (qmgr_process_query) restores the thread's XASL unpack info for
     the outer query, and the outer query's parallel-scan workers clone the stream kept in the query
     entry, not the main thread's current one;
   - a COMMIT inside a dispatch leaves the suspended outer executor's page fixes alone;
   - execute_info deletes call_info only when unpack () allocated it.

   Roles: the A4 tracers 1..N (each runs one statement that calls a stored procedure), the daemon N+2,
   and one parallel-scan worker per session (pw), which is not a Thr.

   Constants:
     MaxDepth  nesting levels of dispatch the model explores
     DeepAt    METHOD_MAX_RECURSION_DEPTH: a dispatch at a depth above it is refused
     MaxOps    client-half operations a session's statement runs in all its dispatches
   Mutant: "none" | see MAP.md, "Mutants" *)
EXTENDS CscSessions

CONSTANTS MaxDepth, DeepAt, MaxOps

\* apalache-type: MaxDepth Int
\* apalache-type: DeepAt Int
\* apalache-type: MaxOps Int
\* apalache-type: sp Int -> Str
\* apalache-type: dep Int -> Int
\* apalache-type: fr Int -> (Int -> { hat: Str, flr: Int, busy: Int, us: Str, st: Str })
\* apalache-type: hat Int -> Str
\* apalache-type: er Int -> (Int -> { tag: Str, sv: Str })
\* apalache-type: el Int -> Int
\* apalache-type: cur Int -> Str
\* apalache-type: flr Int -> Int
\* apalache-type: ops Int -> Int
\* apalache-type: hq Int -> Set(<<Int, Int>>)
\* apalache-type: hd Int -> Set(<<Int, Int>>)
\* apalache-type: hl Int -> Str
\* apalache-type: pls Int -> Str
\* apalache-type: uxi Int -> Str
\* apalache-type: pw Int -> Str
\* apalache-type: fix Int -> Int
\* apalache-type: base Int -> Str
\* apalache-type: xf Int -> Bool
\* apalache-type: wireFail Bool
\* apalache-type: gateRefused Bool
\* apalache-type: crossH Bool
\* apalache-type: hUaf Bool
\* apalache-type: erBad Bool
\* apalache-type: erLeak Bool
\* apalache-type: hatBad Bool
\* apalache-type: plUaf Bool
\* apalache-type: xaslBad Bool
\* apalache-type: pageUaf Bool
\* apalache-type: ciBad Bool
\* apalache-type: caught Bool
\* apalache-type: deepSeen Bool
\* apalache-type: drained Bool
\* apalache-type: retired Bool
\* apalache-type: cloneNested Bool
\* apalache-type: commitIn Bool
\* apalache-type: rightsOver Bool

VARIABLES sp, dep, fr, hat, er, el, cur, flr, ops, hq, hd, hl, pls, uxi, pw, fix, base, xf,
  wireFail, gateRefused, crossH, hUaf, erBad, erLeak, hatBad, plUaf, xaslBad, pageUaf, ciBad,
  caught, deepSeen, drained, retired, cloneNested, commitIn, rightsOver

v7 == <<sp, dep, fr, hat, er, el, cur, flr, ops, hq, hd, hl, pls, uxi, pw, fix, base, xf,
  wireFail, gateRefused, crossH, hUaf, erBad, erLeak, hatBad, plUaf, xaslBad, pageUaf, ciBad,
  caught, deepSeen, drained, retired, cloneNested, commitIn, rightsOver>>
all == <<vars, v7>>

Errs == {"none", "cb", "deep", "fail"}
Locs == 0..N
NoH == 0

\* where the callback handler of session s lives: its csc, or the one process object develop compiles
\* into cub_server (static CUB_THREAD_LOCAL, empty under SERVER_MODE)
Loc(s) == IF Mutant = "process_handler" THEN 0 ELSE s

\* a query handle: <<owner session, creation number>>; its execute_info and host variables refer to the
\* owner's workspace
\* @type: (<<Int, Int>>) => Int;
Owner(h) == h[1]
\* @type: (Int) => Set(<<Int, Int>>);
Alive(l) == hq[l] \cup hd[l]

\* error-stack clear-all (er_stack_clearall: pop_and_keep_error down to the floor): the error kept is the
\* current one, else the first saved one met popping down to the floor
\* @type: (Int -> { tag: Str, sv: Str }, Int, Str, Int) => Str;
Kept(e, l, c, f) ==
  IF c # "none" THEN c
  ELSE IF l > f /\ e[l].sv # "none" THEN e[l].sv
  ELSE IF l > f + 1 /\ e[l - 1].sv # "none" THEN e[l - 1].sv
  ELSE IF l > f + 2 /\ e[l - 2].sv # "none" THEN e[l - 2].sv
  ELSE "none"

\* the dispatch frames and the error stack are arrays with a length (dep, el); an unused slot holds a blank
ErMax == MaxDepth + 1
FrNone == [hat |-> "sv", flr |-> 0, busy |-> 0, us |-> "none", st |-> "ok"]
ErNone == [tag |-> "none", sv |-> "none"]
FrBlank == [k \in 1..MaxDepth |-> FrNone]
ErBlank == [i \in 1..ErMax |-> ErNone]

Init7 ==
  /\ Init
  /\ sp = [s \in Sess |-> "idle"]
  /\ dep = [s \in Sess |-> 0]
  /\ fr = [s \in Sess |-> FrBlank]
  /\ hat = [s \in Sess |-> "sv"]
  /\ er = [s \in Sess |-> ErBlank]
  /\ el = [s \in Sess |-> 0]
  /\ cur = [s \in Sess |-> "none"]
  /\ flr = [s \in Sess |-> 0]
  /\ ops = [s \in Sess |-> 0]
  /\ hq = [l \in Locs |-> {}]
  /\ hd = [l \in Locs |-> {}]
  /\ hl = [l \in Locs |-> "none"]
  /\ pls = [s \in Sess |-> "none"]
  /\ uxi = [s \in Sess |-> "none"]
  /\ pw = [s \in Sess |-> "none"]
  /\ fix = [s \in Sess |-> 0]
  /\ base = [s \in Sess |-> "none"]
  /\ xf = [s \in Sess |-> FALSE]
  /\ wireFail = FALSE /\ gateRefused = FALSE /\ crossH = FALSE /\ hUaf = FALSE /\ erBad = FALSE
  /\ erLeak = FALSE /\ hatBad = FALSE /\ plUaf = FALSE /\ xaslBad = FALSE /\ pageUaf = FALSE /\ ciBad = FALSE
  /\ caught = FALSE /\ deepSeen = FALSE /\ drained = FALSE /\ retired = FALSE /\ cloneNested = FALSE
  /\ commitIn = FALSE /\ rightsOver = FALSE

(* ---- hooks: what an A4 lifecycle step does to the A7 state ---- *)

Reg(s) == sst[s] = "none" /\ sst'[s] = "live"
Gone(s) == sst[s] = "live" /\ sst'[s] = "gone"
Torn == {c \in Sess : torn'[c] > torn[c]}
RetireAt(c) == IF Mutant = "handler_on_pl" THEN Gone(c) ELSE c \in Torn /\ Mutant # "no_retire"
InBracket(c) == \E t \in Thr : active[t] = c

\* deleting the handles of a handler: each one's destructor ends its client query result and walks its
\* host variables (workspace memory of its owner), and deletes its execute_info's call_info when the
\* compile-time rule says so (a handle's call_info is the alias of its own m_prepare_call_info)
\* @type: (Int, Set(<<Int, Int>>)) => Bool;
DelHandles(c, hs) ==
  \/ \E h \in hs : Owner(h) # c
  \/ hs # {} /\ (torn[c] > 0 \/ ~InBracket(c))

\* session_state_create (csession_find_or_create_session) creates the pl session; session_state_uninit deletes
\* it after csc_retire_and_delete (session.c:387), on the uninit thread, outside any bracket of the session's
\* context unless that thread ends its own session from inside it (A4 EndSess, orphan path).
\* csc_teardown (client_session_context.cpp) retires the session's handler and runtime arguments before
\* ws_final, inside the bracket of whichever thread tears it down.
Hook ==
  /\ pls' = [s \in Sess |-> IF Reg(s) THEN "live" ELSE IF Gone(s) THEN "freed" ELSE pls[s]]
  /\ LET rs == {c \in Sess : RetireAt(c)} IN
     /\ hUaf' = (hUaf \/ \E c \in rs : DelHandles(c, Alive(Loc(c))))
     /\ crossH' = (crossH \/ \E c \in rs : \E h \in Alive(Loc(c)) : Owner(h) # c)
     /\ ciBad' = (ciBad \/ (Mutant = "ci_compile" /\ \E c \in rs : Alive(Loc(c)) # {}))
     /\ retired' = (retired \/ \E c \in rs : Alive(Loc(c)) # {})
     /\ hq' = [l \in Locs |-> IF \E c \in rs : Loc(c) = l THEN {} ELSE hq[l]]
     /\ hd' = [l \in Locs |-> IF \E c \in rs : Loc(c) = l THEN {} ELSE hd[l]]
     /\ hl' = [l \in Locs |-> IF \E c \in rs : Loc(c) = l THEN "freed" ELSE hl[l]]
  /\ UNCHANGED <<sp, dep, fr, hat, er, el, cur, flr, ops, uxi, pw, fix, base, xf,
                 wireFail, gateRefused, erBad, erLeak, hatBad, plUaf, xaslBad, pageUaf,
                 caught, deepSeen, drained, cloneNested, commitIn, rightsOver>>

(* ---- the statement of tracer s: a query that calls a stored procedure ---- *)

\* every step below runs on the tracer thread inside its bracket (pc "work"); A4's Touch checks the context is
\* alive and owned
Sub(s) == pc[s] = "work" /\ Touch(s) /\ UNCHANGED <<WorkVars, clsH, pvH, badFree, TmVars, pc, work>>

\* a use of the handler: created on first use (get_callback_handler); a freed one is a use after free
UseH(s) ==
  /\ hUaf' = (hUaf \/ hl[Loc(s)] = "freed")
  /\ hl' = [hl EXCEPT ![Loc(s)] = IF @ = "none" THEN "live" ELSE @]

\* xqmgr_execute_query: the outer query starts, in the environment that exposes every claim at once (the
\* others only check less): a one-shot XASL with a parallel scan whose worker clones its own copy later, an
\* executor holding a page fix when it evaluates the procedure, a server error-stack frame below the callback
TStart(s) ==
  /\ CanWork(s) /\ sp[s] = "idle"
  /\ Touch(s) /\ Step(s, "work")
  /\ pw' = [pw EXCEPT ![s] = "ready"]
  /\ fix' = [fix EXCEPT ![s] = 1]
  /\ er' = [er EXCEPT ![s][1] = [tag |-> "x", sv |-> "none"]]
  /\ el' = [el EXCEPT ![s] = 1]
  /\ xf' = [xf EXCEPT ![s] = TRUE]
  /\ uxi' = [uxi EXCEPT ![s] = "outer"]
  /\ sp' = [sp EXCEPT ![s] = "call"]
  /\ UNCHANGED <<WorkVars, clsH, pvH, badFree, TmVars>>
  /\ UNCHANGED <<dep, fr, hat, cur, flr, ops, hq, hd, hl, pls, base, wireFail, gateRefused, crossH, hUaf,
                 erBad, erLeak, hatBad, plUaf, xaslBad, pageUaf, ciBad, caught, deepSeen, drained, retired,
                 cloneNested, commitIn, rightsOver>>

\* the PL executor (server hat) reaches the pl session and raises a callback: xs_callback_send. A thread with a
\* bracket dispatches it here (method_dispatch): the hat switches to the client half, the libcas depth goes up,
\* an error-stack frame isolates the caller's error state and becomes the floor of the client half's clear-all;
\* a depth above METHOD_MAX_RECURSION_DEPTH is refused with an error
TCall(s) ==
  /\ sp[s] = "call" /\ pc[s] = "work" /\ Touch(s)
  \* cubpl::get_session looks the pl session up through the thread's session (session_get_pl_session): a session
  \* this thread already ended from inside its bracket is not found, and the call fails
  /\ plUaf' = (plUaf \/ (sst[s] = "live" /\ pls[s] # "live"))
  /\ IF sst[s] # "live"
     THEN /\ sp' = [sp EXCEPT ![s] = IF dep[s] = 0 THEN "resume" ELSE "q2"]
          /\ UNCHANGED <<dep, fr, hat, er, el, cur, flr, wireFail, gateRefused, deepSeen, base, rightsOver>>
     ELSE IF Mutant = "gate_worker"
     THEN /\ gateRefused' = TRUE /\ sp' = [sp EXCEPT ![s] = IF dep[s] = 0 THEN "resume" ELSE "q2"]
          /\ UNCHANGED <<dep, fr, hat, er, el, cur, flr, wireFail, deepSeen, base, rightsOver>>
     ELSE IF Mutant = "wire"
     THEN /\ wireFail' = TRUE /\ sp' = [sp EXCEPT ![s] = IF dep[s] = 0 THEN "resume" ELSE "q2"]
          /\ UNCHANGED <<dep, fr, hat, er, el, cur, flr, gateRefused, deepSeen, base, rightsOver>>
     ELSE \E rights \in (IF dep[s] + 1 > DeepAt THEN BOOLEAN ELSE {FALSE}) :
          LET iso == Mutant # "no_isolation"
              l1 == IF iso THEN el[s] + 1 ELSE el[s]
              deep == dep[s] + 1 > DeepAt /\ ~rights
          IN /\ fr' = [fr EXCEPT ![s][dep[s] + 1] = [hat |-> hat[s], flr |-> flr[s], busy |-> NoH, us |-> "none",
                                                   st |-> IF deep THEN "deep" ELSE "ok"]]
             /\ base' = [base EXCEPT ![s] = IF dep[s] = 0 THEN cur[s] ELSE @]
             /\ hat' = [hat EXCEPT ![s] = "cl"]
             /\ dep' = [dep EXCEPT ![s] = @ + 1]
             /\ er' = IF iso THEN [er EXCEPT ![s][l1] = [tag |-> "d", sv |-> cur[s]]] ELSE er
             /\ el' = [el EXCEPT ![s] = l1]
             /\ flr' = [flr EXCEPT ![s] = l1]
             /\ cur' = [cur EXCEPT ![s] = IF deep THEN "deep" ELSE IF iso THEN "none" ELSE @]
             /\ deepSeen' = (deepSeen \/ deep)
             \* a change-rights notification above the limit is not refused; it carries no work
             /\ sp' = [sp EXCEPT ![s] = IF deep \/ rights THEN "dexit" ELSE "disp"]
             /\ rightsOver' = (rightsOver \/ rights)
             /\ UNCHANGED <<wireFail, gateRefused>>
  /\ nested' = (nested \/ Mutant = "reactivate")
  /\ UNCHANGED <<cst, orphan, owner, active, sst, ref, smx, cscp, connRef, adopted, orphL, tgt, aRef,
                 torn, bootMx, sawArea, areaCnt, areaLive, viaOrphan, daemonWaited, busyEnd,
                 clsH, pvH, badFree, TmVars, pc, work>>
  /\ UNCHANGED <<ops, hq, hd, hl, pls, uxi, pw, fix, xf, crossH, hUaf, erBad, erLeak, hatBad, xaslBad, pageUaf,
                 ciBad, caught, drained, retired, cloneNested, commitIn>>

Top(s) == dep[s]

CanOp(s) == sp[s] = "disp" /\ ops[s] < MaxOps /\ Sub(s)
Op(s) == ops' = [ops EXCEPT ![s] = @ + 1]

\* a callback that runs a query through a query handle (prepare/execute): qmgr_process_query unpacks a one-shot
\* XASL (or takes a cached clone, NULL unpack info) and installs it on the thread; the query may itself call
\* a procedure (a nested dispatch one level down, while this handle's execute is on the stack)
TQuery1(s) ==
  /\ CanOp(s) /\ Op(s) /\ UseH(s)
  /\ \E oneShot \in BOOLEAN, nest \in BOOLEAN :
       /\ uxi' = [uxi EXCEPT ![s] = IF oneShot THEN "nested" ELSE "nil"]
       /\ fr' = [fr EXCEPT ![s][Top(s)].us = uxi[s],
                           ![s][Top(s)].busy = IF nest /\ dep[s] < MaxDepth THEN ops[s] + 1 ELSE NoH]
       /\ hq' = [hq EXCEPT ![Loc(s)] = @ \cup {<<s, ops[s] + 1>>}]
       /\ sp' = [sp EXCEPT ![s] = IF nest /\ dep[s] < MaxDepth THEN "call" ELSE "q2"]
  /\ crossH' = (crossH \/ \E h \in Alive(Loc(s)) : Owner(h) # s)
  /\ UNCHANGED <<dep, hat, er, el, cur, flr, hd, pls, pw, fix, base, xf, wireFail, gateRefused, erBad, erLeak, hatBad,
                 plUaf, xaslBad, pageUaf, ciBad, caught, deepSeen, drained, retired, cloneNested, commitIn, rightsOver>>

\* the nested query ends: a one-shot XASL is freed; the thread's unpack info is put back to the caller's
\* (qmgr_process_query end); the handle, if it was busy, is used again (its execute returns through it)
TQuery2(s) ==
  /\ sp[s] = "q2" /\ Sub(s)
  /\ LET f == fr[s][Top(s)]
         restored == IF Mutant = "no_restore" THEN (IF uxi[s] = "nested" THEN "freed" ELSE uxi[s]) ELSE f.us
     IN /\ uxi' = [uxi EXCEPT ![s] = restored]
        /\ hUaf' = (hUaf \/ (f.busy # NoH /\ <<s, f.busy>> \notin Alive(Loc(s))) \/ hl[Loc(s)] = "freed")
        /\ fr' = [fr EXCEPT ![s][Top(s)].busy = NoH, ![s][Top(s)].us = "none"]
  /\ sp' = [sp EXCEPT ![s] = "disp"]
  /\ UNCHANGED <<dep, hat, er, el, cur, flr, ops, hq, hd, hl, pls, pw, fix, base, xf, wireFail, gateRefused, crossH,
                 erBad, erLeak, hatBad, plUaf, xaslBad, pageUaf, ciBad, caught, deepSeen, drained, retired,
                 cloneNested, commitIn, rightsOver>>

\* the callback's SQL fails: the error goes back to the PL routine in the response (the dispatch status stays
\* NO_ERROR), and the client half's er_set leaves it as this thread's current error
TErr(s) ==
  /\ CanOp(s) /\ Op(s)
  /\ cur' = [cur EXCEPT ![s] = "cb"]
  /\ caught' = TRUE
  /\ UNCHANGED <<sp, dep, fr, hat, er, el, flr, hq, hd, hl, pls, uxi, pw, fix, base, xf, wireFail, gateRefused, crossH,
                 hUaf, erBad, erLeak, hatBad, plUaf, xaslBad, pageUaf, ciBad, deepSeen, drained, retired,
                 cloneNested, commitIn, rightsOver>>

\* the PL routine commits (METHOD_CALLBACK_END_TRANSACTION -> tran_commit): the handles move to the deferred list
\* (free_query_handle_all (true), db_admin.c), the client half's error-stack clear-all stops at the floor
\* (tran_er_stack_clearall), and pgbuf_unfix_all leaves the suspended outer executor's fixes alone
TCommit(s) ==
  /\ CanOp(s) /\ Op(s) /\ UseH(s)
  /\ LET fl == IF Mutant = "clearall" THEN 0 ELSE flr[s] IN
     /\ el' = [el EXCEPT ![s] = IF @ > fl THEN fl ELSE @]
     /\ er' = [er EXCEPT ![s] = [i \in 1..ErMax |-> IF i > fl THEN ErNone ELSE @[i]]]
     /\ cur' = [cur EXCEPT ![s] = Kept(er[s], el[s], cur[s], fl)]
  /\ hd' = [hd EXCEPT ![Loc(s)] = @ \cup hq[Loc(s)]]
  /\ hq' = [hq EXCEPT ![Loc(s)] = {}]
  /\ crossH' = (crossH \/ \E h \in hq[Loc(s)] : Owner(h) # s)
  /\ fix' = [fix EXCEPT ![s] = IF Mutant = "sweep" THEN 0 ELSE @]
  /\ commitIn' = (commitIn \/ fix[s] = 1)
  /\ UNCHANGED <<sp, dep, fr, hat, flr, pls, uxi, pw, base, xf, wireFail, gateRefused, erBad, erLeak, hatBad,
                 plUaf, xaslBad, pageUaf, ciBad, caught, deepSeen, drained, retired, cloneNested, rightsOver>>

\* method_dispatch_internal returns: NO_ERROR, or an error status (a builtin method's ER_SM_INVALID_METHOD_ENV, a
\* response that failed to pack) with its error set
TDone(s) ==
  /\ sp[s] = "disp" /\ Sub(s)
  /\ sp' = [sp EXCEPT ![s] = "dexit"]
  /\ \E fail \in BOOLEAN :
       /\ fr' = [fr EXCEPT ![s][Top(s)].st = IF fail THEN "err" ELSE "ok"]
       /\ cur' = [cur EXCEPT ![s] = IF fail THEN "fail" ELSE @]
  /\ UNCHANGED <<dep, hat, er, el, flr, ops, hq, hd, hl, pls, uxi, pw, fix, base, xf, wireFail, gateRefused,
                 crossH, hUaf, erBad, erLeak, hatBad, plUaf, xaslBad, pageUaf, ciBad, caught, deepSeen, drained,
                 retired, cloneNested, commitIn, rightsOver>>

\* method_dispatch returns: libcas depth down; at the outermost exit the deferred handles are deleted (the mirror of
\* CS's deferred_flush_guard at its request boundary); the isolation frame is popped (an error status keeps the
\* error on top: er_stack_pop_and_keep_error); the hat is put back. Back in the caller: the server executor
\* (depth 0) or the nested query of the level above
TExit(s) ==
  /\ sp[s] = "dexit" /\ Sub(s)
  /\ LET f == fr[s][Top(s)]
         d1 == dep[s] - 1
         drain == IF Mutant = "drain_each_exit" THEN TRUE ELSE IF Mutant = "no_drain" THEN FALSE ELSE d1 = 0
         iso == Mutant # "no_isolation"
         e == er[s]
         l == el[s]
         ok == iso => (l >= 1 /\ e[l].tag = "d")
     IN /\ dep' = [dep EXCEPT ![s] = d1]
        /\ erBad' = (erBad \/ ~ok)
        /\ er' = [er EXCEPT ![s] = IF iso /\ ok THEN [@ EXCEPT ![l] = ErNone] ELSE e]
        /\ el' = [el EXCEPT ![s] = IF iso /\ ok THEN l - 1 ELSE l]
        /\ cur' = [cur EXCEPT ![s] = IF ~iso \/ ~ok THEN @
                                     ELSE IF f.st = "ok" THEN e[l].sv
                                     ELSE IF @ # "none" THEN @ ELSE e[l].sv]
        /\ hat' = [hat EXCEPT ![s] = IF Mutant = "err_keeps_hat" /\ f.st # "ok" THEN @ ELSE f.hat]
        /\ flr' = [flr EXCEPT ![s] = f.flr]
        /\ fr' = [fr EXCEPT ![s][Top(s)] = FrNone]
        /\ IF drain /\ hd[Loc(s)] # {}
           THEN /\ hUaf' = (hUaf \/ hl[Loc(s)] = "freed")
                /\ crossH' = (crossH \/ \E h \in hd[Loc(s)] : Owner(h) # s)
                /\ ciBad' = (ciBad \/ Mutant = "ci_compile")
                /\ hd' = [hd EXCEPT ![Loc(s)] = {}]
                /\ drained' = TRUE
           ELSE UNCHANGED <<hUaf, crossH, ciBad, hd, drained>>
        /\ sp' = [sp EXCEPT ![s] = IF d1 = 0 THEN "resume" ELSE "q2"]
  /\ UNCHANGED <<ops, hq, hl, pls, uxi, pw, fix, base, xf, wireFail, gateRefused, erLeak, hatBad, plUaf, xaslBad,
                 pageUaf, caught, deepSeen, retired, cloneNested, commitIn, rightsOver>>

\* the routine goes on and raises its next callback (a routine sends one per prepare, execute, fetch, ...; each is a
\* dispatch of its own): from the outer executor between two callbacks, or from inside a nested query whose routine
\* is still running
TNext(s) ==
  /\ Sub(s) /\ ops[s] < MaxOps /\ Op(s)
  /\ \/ sp[s] = "resume" /\ cur[s] = "none"
     \/ sp[s] = "q2" /\ fr[s][Top(s)].busy # NoH
  /\ sp' = [sp EXCEPT ![s] = "call"]
  /\ UNCHANGED <<dep, fr, hat, er, el, cur, flr, hq, hd, hl, pls, uxi, pw, fix, base, xf, wireFail, gateRefused,
                 crossH, hUaf, erBad, erLeak, hatBad, plUaf, xaslBad, pageUaf, ciBad, caught, deepSeen, drained,
                 retired, cloneNested, commitIn, rightsOver>>

\* the outer executor resumes after the procedure returned: in the server hat, with the error state it had
\* before the callback (a callback error the routine handled is not its error), reading the pages it fixed
TResume(s) ==
  /\ sp[s] = "resume" /\ Sub(s)
  /\ hatBad' = (hatBad \/ hat[s] # "sv")
  /\ erLeak' = (erLeak \/ (cur[s] # base[s] /\ cur[s] = "cb"))
  /\ pageUaf' = (pageUaf \/ (fix[s] = 0 /\ Mutant = "sweep" /\ commitIn))
  /\ sp' = [sp EXCEPT ![s] = "stend"]
  /\ UNCHANGED <<dep, fr, hat, er, el, cur, flr, ops, hq, hd, hl, pls, uxi, pw, fix, base, xf, wireFail, gateRefused,
                 crossH, hUaf, erBad, plUaf, xaslBad, ciBad, caught, deepSeen, drained, retired, cloneNested,
                 commitIn, rightsOver>>

\* the statement ends after its parallel-scan workers joined: the outer XASL is freed, the server pops its own
\* error-stack frames, the executor releases its fix
TEnd(s) ==
  /\ sp[s] = "stend" /\ Sub(s)
  /\ pw[s] # "ready"
  /\ erBad' = (erBad \/ (IF xf[s] THEN el[s] # 1 \/ er[s][1].tag # "x" ELSE el[s] # 0))
  /\ er' = [er EXCEPT ![s] = ErBlank]
  /\ el' = [el EXCEPT ![s] = 0]
  /\ cur' = [cur EXCEPT ![s] = "none"]
  /\ uxi' = [uxi EXCEPT ![s] = "none"]
  /\ fix' = [fix EXCEPT ![s] = 0]
  /\ pw' = [pw EXCEPT ![s] = "none"]
  /\ base' = [base EXCEPT ![s] = "none"]
  /\ xf' = [xf EXCEPT ![s] = FALSE]
  /\ sp' = [sp EXCEPT ![s] = "idle"]
  /\ UNCHANGED <<dep, fr, hat, flr, ops, hq, hd, hl, pls, wireFail, gateRefused, crossH, hUaf, erLeak, hatBad,
                 plUaf, xaslBad, pageUaf, ciBad, caught, deepSeen, drained, retired, cloneNested, commitIn, rightsOver>>

\* the outer query's parallel-scan worker clones its copy of the one-shot XASL (px_scan_task.cpp), under the main
\* thread's m_px_lock_mutex, which the main thread's own nested queries do not take
PClone(s) ==
  /\ pw[s] = "ready"
  /\ LET src == IF Mutant = "thread_ptr" THEN uxi[s] ELSE "outer" IN
     /\ xaslBad' = (xaslBad \/ src # "outer")
     /\ cloneNested' = (cloneNested \/ uxi[s] # "outer")
  /\ pw' = [pw EXCEPT ![s] = "done"]
  /\ UNCHANGED vars
  /\ UNCHANGED <<sp, dep, fr, hat, er, el, cur, flr, ops, hq, hd, hl, pls, uxi, fix, base, xf, wireFail, gateRefused,
                 crossH, hUaf, erBad, erLeak, hatBad, plUaf, pageUaf, ciBad, caught, deepSeen, drained, retired,
                 commitIn, rightsOver>>

Work7(s) ==
  \/ TStart(s) \/ TCall(s) \/ TQuery1(s) \/ TQuery2(s) \/ TErr(s) \/ TCommit(s) \/ TDone(s) \/ TExit(s)
  \/ TResume(s) \/ TEnd(s) \/ TNext(s)

(* ---- the A4 lifecycle without the attacher and A4's own work steps (checked by docs/tla/CBRD-27430-A4) ---- *)

Life(s) ==
  /\ sp[s] = "idle"
  /\ \/ TNew(s) \/ TAct(s) \/ TBootLock(s) \/ TAreaCheck(s) \/ TAreaMake(s) \/ TReg(s) \/ TBootFail(s) \/ TAdopt(s)
     \/ TEnd1(s) \/ TEnd2(s) \/ TDoneWork(s) \/ TUnreg(s) \/ TLateOp(s) \/ TDeact(s) \/ TUnlock(s) \/ TReread(s)
     \/ TDel(s) \/ TNotAdopted(s) \/ TRAct(s) \/ TRTear(s)

TStep7(s) == (Life(s) /\ Hook) \/ Work7(s) \/ PClone(s)
DStep7 == DStep /\ Hook

Next7 ==
  \/ \E s \in Sess : TStep7(s)
  \/ DStep7
  \/ Finished /\ UNCHANGED v7

Fairness7 ==
  /\ \A s \in Sess : WF_all(TStep7(s) /\ ~TBootFail(s))
  /\ WF_all(DStep7)

Spec7 == Init7 /\ [][Next7]_all /\ Fairness7

(* ---- properties ---- *)

\* C1: a callback raised in a bracket is dispatched on that thread under that bracket: served, never through a
\* second activation (A4 NoNest), and the session's pl session admits the bracket thread
InProcess == ~wireFail /\ ~gateRefused

\* C2: the handles are the session's own: no thread uses or frees another session's handle, none is used after
\* it was freed or after the workspace it refers to was freed, none is freed outside its session's bracket
OwnHandles == ~crossH /\ ~hUaf

\* C2: a deleted context left no handle behind; a statement leaves no deferred handle of its own past its end
NoHandleLeak ==
  /\ \A s \in Sess : cst[s] = "freed" /\ Mutant # "process_handler" => Alive(s) = {}
  /\ \A s \in Sess : sp[s] = "idle" => \A h \in hd[Loc(s)] : Owner(h) # s

\* C3: every error-stack pop finds its own frame; the outer executor resumes in the server hat with the error
\* state it had (a callback error the routine handled does not reach it)
ErBalanced == ~erBad /\ ~erLeak /\ ~hatBad

\* C4: execute_info deletes only the call_info unpack () allocated
CallInfoOwned == ~ciBad

\* C5: the outer query's workers clone the outer XASL, and the thread's unpack info is the outer query's again
\* after a nested query (never a freed one)
OuterXasl == ~xaslBad /\ \A s \in Sess : sp[s] \in {"resume", "stend", "disp"} /\ dep[s] <= 1 => uxi[s] = "outer"

\* C6: a COMMIT inside a dispatch leaves the outer executor's page fixes in place
OuterFixes == ~pageUaf

NoPlUaf == ~plUaf

TypeOK7 ==
  /\ sp \in [Sess -> {"idle", "call", "disp", "q2", "dexit", "resume", "stend"}]
  /\ dep \in [Sess -> 0..MaxDepth]
  /\ hat \in [Sess -> {"sv", "cl"}]
  /\ cur \in [Sess -> Errs]
  /\ ops \in [Sess -> 0..MaxOps]
  /\ hl \in [Locs -> {"none", "live", "freed"}]
  /\ pls \in [Sess -> {"none", "live", "freed"}]
  /\ uxi \in [Sess -> {"none", "outer", "nested", "nil", "freed"}]
  /\ pw \in [Sess -> {"none", "ready", "done"}]
  /\ fix \in [Sess -> 0..1]

(* ---- inductive invariant (A4's, with the A7 state) ---- *)

R7 ==
  /\ TypeOK7
  /\ wireFail = FALSE /\ gateRefused = FALSE /\ crossH = FALSE /\ hUaf = FALSE /\ erBad = FALSE
  /\ erLeak = FALSE /\ hatBad = FALSE /\ plUaf = FALSE /\ xaslBad = FALSE /\ pageUaf = FALSE /\ ciBad = FALSE
  /\ caught \in BOOLEAN /\ deepSeen \in BOOLEAN /\ drained \in BOOLEAN /\ retired \in BOOLEAN
  /\ cloneNested \in BOOLEAN /\ commitIn \in BOOLEAN /\ rightsOver \in BOOLEAN
  /\ base \in [Sess -> Errs]
  /\ xf \in [Sess -> BOOLEAN]
  /\ flr \in [Sess -> 0..ErMax]
  /\ fr \in [Sess -> [1..MaxDepth -> [hat : {"sv", "cl"}, flr : 0..ErMax, busy : 0..MaxOps,
                                        us : {"none", "outer", "nested", "nil"}, st : {"ok", "deep", "err"}]]]
  /\ er \in [Sess -> [1..ErMax -> [tag : {"none", "x", "d"}, sv : Errs]]]
  /\ el \in [Sess -> 0..ErMax]
  /\ hq \in [Locs -> SUBSET (Sess \X (1..MaxOps))]
  /\ hd \in [Locs -> SUBSET (Sess \X (1..MaxOps))]
  \* a statement is running only on the tracer's work label, inside its own live context, whose pl session lives
  /\ \A s \in Sess : sp[s] # "idle" => pc[s] = "work" /\ active[s] = s /\ cst[s] = "live"
                                     /\ torn[s] = 0 /\ uxi[s] # "none"
  /\ \A s \in Sess : sp[s] = "idle" => dep[s] = 0 /\ hat[s] = "sv" /\ el[s] = 0
                                      /\ cur[s] = "none" /\ flr[s] = 0 /\ uxi[s] = "none" /\ pw[s] = "none"
                                      /\ fix[s] = 0 /\ base[s] = "none"
  \* the pl session lives exactly while the session is registered
  /\ \A s \in Sess : pls[s] = (IF sst[s] = "none" THEN "none" ELSE IF sst[s] = "live" THEN "live" ELSE "freed")
  \* the dispatch frames: one per depth, the outermost saved the server hat and floor 0
  /\ \A s \in Sess : \A k \in 1..MaxDepth : k > dep[s] => fr[s][k] = FrNone
  /\ \A s \in Sess : \A i \in 1..ErMax : i > el[s] => er[s][i] = ErNone
  /\ \A s \in Sess : dep[s] = 0 => hat[s] = "sv" /\ flr[s] = 0
  /\ \A s \in Sess : dep[s] > 0 => hat[s] = "cl"
  /\ \A s \in Sess : \A k \in 1..MaxDepth : k <= dep[s] => fr[s][k].hat = (IF k = 1 THEN "sv" ELSE "cl")
                                       /\ fr[s][k].st \in {"ok", "deep", "err"}
                                       /\ (fr[s][k].st = "deep" => k > DeepAt)
                                       /\ (k > DeepAt => k = dep[s] /\ sp[s] = "dexit")
                                       /\ fr[s][k].busy \in 0..MaxOps
                                       /\ fr[s][k].us \in {"none", "outer", "nested", "nil"}
  \* the error stack: the server's frame below, then one isolation frame per depth; the floor is the top one
  /\ \A s \in Sess : sp[s] # "idle" =>
       /\ el[s] = dep[s] + (IF xf[s] THEN 1 ELSE 0)
       /\ \A i \in 1..ErMax : i <= el[s] => er[s][i].tag = (IF xf[s] /\ i = 1 THEN "x" ELSE "d")
       /\ flr[s] = (IF dep[s] = 0 THEN 0 ELSE el[s])
  /\ \A s \in Sess : sp[s] = "idle" => xf[s] = FALSE
  \* the handles: session s's handles are in its own handler, which lives while the context is not torn down
  /\ \A l \in Locs : \A h \in Alive(l) : Owner(h) = l /\ h[2] \in 1..MaxOps
  /\ \A l \in Locs : hq[l] \cap hd[l] = {}
  /\ hq[0] = {} /\ hd[0] = {} /\ hl[0] = "none"
  /\ \A s \in Sess : Alive(s) # {} => hl[s] = "live" /\ torn[s] = 0 /\ cst[s] = "live"
  /\ \A s \in Sess : hl[s] = "live" => torn[s] = 0
  /\ \A s \in Sess : sp[s] # "idle" => hl[s] # "freed"
  /\ \A s \in Sess : sp[s] = "idle" => hd[s] = {}
  /\ \A s \in Sess : \A k \in 1..MaxDepth : k <= dep[s] /\ fr[s][k].busy # NoH => <<s, fr[s][k].busy>> \in Alive(s)
  /\ \A s \in Sess : hl[s] = "freed" => torn[s] > 0
  /\ \A s \in Sess : dep[s] = 0 => hd[s] = {}
  /\ \A s \in Sess : \A h \in Alive(s) : h[2] <= ops[s]
  \* where each step of the statement is: the depth, the frames below the top (each inside a query that called a
  \* routine), the top frame, the thread's unpack info, and the error state the server executor sees at depth 0
  /\ \A s \in Sess : sp[s] # "idle" => xf[s] /\ fix[s] = 1 /\ pw[s] \in {"ready", "done"} /\ base[s] = "none"
  /\ \A s \in Sess : sp[s] \in {"disp", "q2", "dexit"} => dep[s] >= 1
  /\ \A s \in Sess : sp[s] \in {"resume", "stend"} => dep[s] = 0 /\ uxi[s] = "outer" /\ cur[s] # "cb"
  /\ \A s \in Sess : sp[s] = "call" /\ dep[s] = 0 => uxi[s] = "outer" /\ cur[s] = "none"
  /\ \A s \in Sess : sp[s] = "call" => dep[s] < MaxDepth
  \* a dispatch runs only in a registered session (a statement after the session ended fails before the dispatch)
  /\ \A s \in Sess : dep[s] >= 1 => sst[s] = "live"
  \* an error exit carries its error as the current one; only an exiting top frame has an error status
  /\ \A s \in Sess : sp[s] = "dexit" /\ dep[s] >= 1 =>
       /\ (fr[s][dep[s]].st = "err" => cur[s] = "fail")
       /\ (fr[s][dep[s]].st = "deep" => cur[s] = "deep")
  /\ \A s \in Sess : \A k \in 1..MaxDepth : k <= dep[s] /\ fr[s][k].st = "err" => k = dep[s] /\ sp[s] = "dexit"
  \* the server frame and the outermost isolation frame saved the statement's error state: none
  /\ \A s \in Sess : (el[s] >= 1 => er[s][1].sv = "none") /\ (el[s] >= 2 => er[s][2].sv = "none")
  /\ \A s \in Sess : \A k \in 1..MaxDepth : fr[s][k].busy # NoH => k < MaxDepth
  /\ \A s \in Sess : \A k \in 1..MaxDepth : k <= dep[s] =>
       /\ fr[s][k].flr = (IF k = 1 THEN 0 ELSE k)
       /\ (k < dep[s] \/ sp[s] = "call") =>
            /\ fr[s][k].busy # NoH
            /\ fr[s][k].us = (IF k = 1 THEN "outer" ELSE fr[s][k].us) /\ (k > 1 => fr[s][k].us \in {"nested", "nil"})
       /\ k = dep[s] /\ sp[s] \in {"disp", "dexit"} => fr[s][k].busy = NoH /\ fr[s][k].us = "none"
       /\ k = dep[s] /\ sp[s] = "q2" => fr[s][k].us = (IF k = 1 THEN "outer" ELSE fr[s][k].us)
                                       /\ (k > 1 => fr[s][k].us \in {"nested", "nil"})
       /\ fr[s][k].st = "deep" => k = dep[s] /\ sp[s] = "dexit"
  /\ \A s \in Sess : sp[s] \in {"disp", "dexit"} => uxi[s] = (IF dep[s] = 1 THEN "outer" ELSE uxi[s])
                                                    /\ (dep[s] > 1 => uxi[s] \in {"nested", "nil"})
  /\ \A s \in Sess : sp[s] = "q2" \/ (sp[s] = "call" /\ dep[s] > 0) => uxi[s] \in {"nested", "nil"}

IndInv7 == IndInv /\ R7

CInit7 ==
  /\ N = 2 /\ MaxWork \in Nat /\ MaxWork >= 1
  /\ Attach = FALSE /\ Xfer = FALSE /\ ServerInit = TRUE /\ Mutant = "none"
  /\ MaxDepth = 2 /\ DeepAt \in 1..2 /\ MaxOps = 2

\* witnesses
NotCaught == ~caught
NotDeep == ~deepSeen
NotDrained == ~drained
NotRetired == ~retired
NotCloneNested == ~cloneNested
NotCommitIn == ~commitIn
NotRightsOver == ~rightsOver

=============================================================================
