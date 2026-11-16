--------------------------- MODULE BucketLatchWord ---------------------------
(***************************************************************************)
(* The bucket latch itself (design, docs/tla/bcb-mutex-removal, D20).      *)
(* BucketLatch.tla takes a bucket latch as one atomic critical section;    *)
(* this module checks the latch that provides it.                          *)
(*                                                                         *)
(* The latch word holds an exclusive bit (X), an exclusive-request bit     *)
(* (XREQ: new shared requests wait), a wait bit (WAIT: somebody sleeps)    *)
(* and the shared count; every change of it is one atomic step (CAS or     *)
(* fetch-and-op). A request that cannot get the latch takes the latch's   *)
(* wait-list lock, checks the word again and sets WAIT in one CAS, appends *)
(* itself, releases the list lock and sleeps on its own doorbell (a       *)
(* per-thread futex word; it loops while the doorbell is armed, so a      *)
(* spurious futex return is invisible). The release that leaves the latch *)
(* free and saw WAIT takes the list lock and wakes only the waiters the    *)
(* latch admits next: the head waiter if it asks for X, otherwise the      *)
(* shared waiters before the first X waiter (then XREQ is cleared, since  *)
(* the X waiter behind them sleeps). Woken waiters retry from the start   *)
(* (a new request may barge in first).                                    *)
(***************************************************************************)
EXTENDS Integers, FiniteSets

\* Mutant: "none" or one known-wrong variant
CONSTANTS NT,      \* threads 1..NT
          MaxOps,  \* latch requests per thread
          Ops,     \* modes a thread may request ("S", "X")
          Mutant

\* apalache-type: NT Int
\* apalache-type: MaxOps Int
\* apalache-type: Ops Set(Str)
\* apalache-type: Mutant Str
\* apalache-type: pc Int -> Str
\* apalache-type: req Int -> Str
\* apalache-type: ops Int -> Int
\* apalache-type: inq Int -> Bool
\* apalache-type: tk Int -> Int
\* apalache-type: door Int -> Bool
\* apalache-type: tick Int
\* apalache-type: xo Int
\* apalache-type: sc Int
\* apalache-type: xreq Bool
\* apalache-type: wbit Bool
\* apalache-type: lk Int
\* apalache-type: over Bool

Thr == 1..NT

VARIABLES pc,    \* Thr -> program counter
          req,   \* Thr -> mode requested ("S", "X")
          ops,   \* Thr -> requests left
          inq,   \* Thr -> in the wait list
          tk,    \* Thr -> list position (ticket)
          door,  \* Thr -> its doorbell is armed (it must sleep until a waker disarms it)
          tick,  \* next ticket
          xo,    \* word: the X holder (0: none)
          sc,    \* word: shared count
          xreq,  \* word: XREQ
          wbit,  \* word: WAIT
          lk,    \* wait-list lock holder (0: none)
          over   \* ghost: a waker woke more than the head rule allows

vars == <<pc, req, ops, inq, tk, door, tick, xo, sc, xreq, wbit, lk, over>>

Free == xo = 0 /\ sc = 0
CanS == xo = 0 /\ ~xreq
CanX == Free
Can(t) == IF req[t] = "S" THEN CanS ELSE CanX
List == {t \in Thr : inq[t]}

\* the waiters the latch admits next: the head if it asks for X, else the S waiters before the first X
HeadRun ==
  LET heads == {h \in List : \A v \in List : tk[h] <= tk[v]}
      xs == {w \in List : req[w] = "X"}
  IN IF \E h \in heads : req[h] = "X" THEN heads
     ELSE {w \in List : req[w] = "S" /\ \A v \in xs : tk[w] < tk[v]}

Init ==
  /\ pc = [t \in Thr |-> "idle"]
  /\ req = [t \in Thr |-> "S"]
  /\ ops = [t \in Thr |-> MaxOps]
  /\ inq = [t \in Thr |-> FALSE]
  /\ tk = [t \in Thr |-> 0]
  /\ door = [t \in Thr |-> FALSE]
  /\ tick = 1
  /\ xo = 0 /\ sc = 0 /\ xreq = FALSE /\ wbit = FALSE /\ lk = 0
  /\ over = FALSE

Begin(t) ==
  /\ pc[t] = "idle" /\ ops[t] > 0
  /\ \E m \in Ops : req' = [req EXCEPT ![t] = m]
  /\ ops' = [ops EXCEPT ![t] = @ - 1]
  /\ pc' = [pc EXCEPT ![t] = "try"]
  /\ UNCHANGED <<inq, tk, door, tick, xo, sc, xreq, wbit, lk, over>>

\* the fast path: one CAS; X takes the word with the request bit gone, WAIT kept. Failing, an X request
\* sets XREQ (new S requests wait) and both go to the slow path (the spin is a repeated try: stuttering)
Try(t) ==
  /\ pc[t] = "try"
  /\ IF Can(t)
     THEN /\ IF req[t] = "S" THEN sc' = sc + 1 /\ UNCHANGED <<xo, xreq>>
             ELSE xo' = t /\ xreq' = FALSE /\ UNCHANGED sc
          /\ pc' = [pc EXCEPT ![t] = "held"]
     ELSE /\ xreq' = (xreq \/ req[t] = "X")
          /\ pc' = [pc EXCEPT ![t] = "lockl"]
          /\ UNCHANGED <<xo, sc>>
  /\ UNCHANGED <<req, ops, inq, tk, door, tick, wbit, lk, over>>

LockL(t) ==
  /\ pc[t] = "lockl" /\ lk = 0
  /\ lk' = t
  /\ pc' = [pc EXCEPT ![t] = "chk"]
  /\ UNCHANGED <<req, ops, inq, tk, door, tick, xo, sc, xreq, wbit, over>>

\* under the list lock, one CAS: the latch admits it now (release the list lock, retry), or set WAIT
\* while the word still refuses it (mutant no_recheck: set WAIT without looking)
Check(t) ==
  /\ pc[t] = "chk"
  /\ IF Can(t) /\ Mutant # "no_recheck"
     THEN /\ lk' = 0
          /\ pc' = [pc EXCEPT ![t] = "try"]
          /\ UNCHANGED <<wbit, xreq>>
     ELSE /\ wbit' = TRUE
          /\ xreq' = (xreq \/ req[t] = "X")
          /\ pc' = [pc EXCEPT ![t] = "enq"]
          /\ UNCHANGED lk
  /\ UNCHANGED <<req, ops, inq, tk, door, tick, xo, sc, over>>

\* append to the list, arm the doorbell, release the list lock
Enq(t) ==
  /\ pc[t] = "enq"
  /\ inq' = [inq EXCEPT ![t] = TRUE]
  /\ tk' = [tk EXCEPT ![t] = tick]
  /\ tick' = tick + 1
  /\ door' = [door EXCEPT ![t] = TRUE]
  /\ lk' = 0
  /\ pc' = [pc EXCEPT ![t] = "sleep"]
  /\ UNCHANGED <<req, ops, xo, sc, xreq, wbit, over>>

\* the doorbell was disarmed: retry from the start
Wake(t) ==
  /\ pc[t] = "sleep" /\ ~door[t]
  /\ pc' = [pc EXCEPT ![t] = "try"]
  /\ UNCHANGED <<req, ops, inq, tk, door, tick, xo, sc, xreq, wbit, lk, over>>

\* release: one fetch-and-op; the release that leaves the latch free and saw WAIT goes on to wake
\* (mutant release_no_wake: never)
Release(t) ==
  /\ pc[t] = "held"
  /\ LET nsc == IF req[t] = "S" THEN sc - 1 ELSE sc
         nxo == IF req[t] = "X" THEN 0 ELSE xo
     IN /\ sc' = nsc /\ xo' = nxo
        /\ pc' = [pc EXCEPT ![t] =
                    IF wbit /\ nxo = 0 /\ nsc = 0 /\ Mutant # "release_no_wake" THEN "lockw" ELSE "idle"]
  /\ UNCHANGED <<req, ops, inq, tk, door, tick, xreq, wbit, lk, over>>

LockW(t) ==
  /\ pc[t] = "lockw" /\ lk = 0
  /\ lk' = t
  /\ pc' = [pc EXCEPT ![t] = "wake"]
  /\ UNCHANGED <<req, ops, inq, tk, door, tick, xo, sc, xreq, wbit, over>>

\* under the list lock: take the head run off the list, disarm their doorbells, clear WAIT when the list
\* empties (mutant clear_wait_early: always), clear XREQ when shared waiters are woken (mutant
\* keep_xreq: not), release the list lock (mutant wake_all: every waiter)
WakeUp(t) ==
  /\ pc[t] = "wake"
  /\ LET W == IF Mutant = "wake_all" THEN List ELSE HeadRun
         left == List \ W
     IN /\ inq' = [w \in Thr |-> inq[w] /\ w \notin W]
        /\ door' = [w \in Thr |-> door[w] /\ w \notin W]
        /\ wbit' = (left # {} /\ Mutant # "clear_wait_early")
        /\ xreq' = IF (\E w \in W : req[w] = "S") /\ Mutant # "keep_xreq" THEN FALSE ELSE xreq
        /\ over' = (over \/ W # HeadRun)
  /\ lk' = 0
  /\ pc' = [pc EXCEPT ![t] = "idle"]
  /\ UNCHANGED <<req, ops, tk, tick, xo, sc>>

Finish(t) ==
  /\ pc[t] = "idle" /\ ops[t] = 0
  /\ pc' = [pc EXCEPT ![t] = "done"]
  /\ UNCHANGED <<req, ops, inq, tk, door, tick, xo, sc, xreq, wbit, lk, over>>

AllDone == \A t \in Thr : pc[t] = "done"
Terminating == AllDone /\ UNCHANGED vars

Step(t) ==
  \/ Begin(t) \/ Try(t) \/ LockL(t) \/ Check(t) \/ Enq(t) \/ Wake(t) \/ Release(t) \/ LockW(t)
  \/ WakeUp(t) \/ Finish(t)

Next == (\E t \in Thr : Step(t)) \/ Terminating

Spec == Init /\ [][Next]_vars
FairSpec == Spec /\ \A t \in Thr : WF_vars(Step(t))

------------------------------------------------------------------------------
\* Properties

TypeOK ==
  /\ \A t \in Thr :
       /\ pc[t] \in {"idle", "try", "lockl", "chk", "enq", "sleep", "held", "lockw", "wake", "done"}
       /\ req[t] \in {"S", "X"} /\ ops[t] \in 0..MaxOps /\ tk[t] >= 0
       /\ inq[t] \in BOOLEAN /\ door[t] \in BOOLEAN
  /\ tick >= 1 /\ xo \in 0..NT /\ sc \in 0..NT /\ lk \in 0..NT
  /\ xreq \in BOOLEAN /\ wbit \in BOOLEAN /\ over \in BOOLEAN

\* L1 X is held alone; S only without X; the word counts exactly the holders
Exclusion ==
  /\ sc = Cardinality({t \in Thr : pc[t] = "held" /\ req[t] = "S"})
  /\ \A t \in Thr : (pc[t] = "held" /\ req[t] = "X") <=> xo = t
  /\ xo # 0 => sc = 0

\* L2 no sleeper is forgotten: while somebody is in the list, WAIT is set; a free latch with only
\* sleepers in the list has a waker on its way, a woken waiter about to retry, or a thread that will
\* take and release it
NoLostWake ==
  /\ List # {} => wbit
  /\ ~(/\ List # {} /\ Free
       /\ \A w \in List : door[w]
       /\ ~\E t \in Thr : pc[t] \in {"try", "lockl", "chk", "enq", "lockw", "wake"}
       /\ ~\E t \in Thr : pc[t] = "sleep" /\ ~door[t])

\* L3 a waker wakes only the waiters the latch admits next
OnlyNeeded == ~over

\* L4 (liveness) every request ends
Termination == <>AllDone

\* the list lock and the doorbells in the shape the program counters allow
Shape ==
  /\ \A t \in Thr :
       /\ inq[t] => pc[t] = "sleep" /\ door[t] /\ tk[t] >= 1 /\ tk[t] < tick
       /\ pc[t] = "sleep" /\ door[t] => inq[t]
       /\ (pc[t] \in {"chk", "enq", "wake"}) <=> lk = t
       /\ pc[t] = "enq" => wbit
       /\ ~(pc[t] \in {"sleep"}) => ~door[t]
  /\ \A t, u \in Thr : (t # u /\ inq[t] /\ inq[u]) => tk[t] # tk[u]

IndInv ==
  /\ TypeOK
  /\ Shape
  /\ Exclusion
  /\ NoLostWake
  /\ OnlyNeeded

\* witnesses
NotSlept == ~\E t \in Thr : pc[t] = "sleep" /\ door[t]
NotSharedRunWoken == ~\E t, u \in Thr : pc[t] = "sleep" /\ ~door[t] /\ req[t] = "S" /\ inq[u] /\ req[u] = "X"
NotBargedAfterWake == ~\E t, u \in Thr : t # u /\ pc[t] = "sleep" /\ ~door[t] /\ pc[u] = "held"
=============================================================================
