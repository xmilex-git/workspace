---------------------------- MODULE PxSysopGate ----------------------------
(* The system operation gate of parallel execution (PR 8424, CBRD-27938).
   Every thread of one transaction shares the transaction descriptor: the
   system operation depth (topops.last + 1) and the re-entrant mutex
   rmutex_topop (owner, lock count). A thread opens a system operation in two
   steps (lock_topop, then topops.last++) and closes it in two steps
   (topops.last--, then unlock_topop). Before it starts px workers it asks
   is_under_system_operation (): a first read of the depth, then a read of the
   owner. Root is the request thread of the statement, Q the request thread
   that serves the server-side SQL of a stored procedure Root runs, and every
   other thread is a px task whose parent pushed it (Par). While Root runs a
   stored procedure it is registered in the PL session, and lock_topop () lets
   any thread re-enter rmutex_topop through it (Involved). Mutant selects the
   gate of develop, the gate with one clause removed, or the gate agreed in
   the JIRA comment. *)
EXTENDS Naturals, FiniteSets

CONSTANTS Thr, Par, MaxOps, Mutant, ParentLate
\* Types for Apalache (tools/tla/apalache-types writes them into the declarations).
\* apalache-type: Thr Set(Int)
\* apalache-type: Par Int -> Int
\* apalache-type: MaxOps Int
\* apalache-type: Mutant Str
\* apalache-type: ParentLate Bool
\* apalache-type: pc Int -> Str
\* apalache-type: owner Int
\* apalache-type: cnt Int
\* apalache-type: depth Int
\* apalache-type: h Int -> Int
\* apalache-type: late Int -> Int
\* apalache-type: ops Int -> Int
\* apalache-type: decn Int -> Str
\* apalache-type: reason Int -> Str
\* apalache-type: spawnOK Int -> Bool
\* apalache-type: decH Int -> Int
\* apalache-type: reent Bool

NoThr == 0 - 1
Root == 0
Q == 1
Mutants == {"none", "develop", "no_self", "no_pl", "empty_other", "jira"}
ASSUME Assm == /\ Thr \subseteq Nat /\ Root \in Thr /\ Q \in Thr
               /\ Par \in [Thr -> Thr \cup {NoThr}]
               /\ Par[Root] = NoThr /\ Par[Q] = NoThr
               /\ \A c \in Thr : Par[c] # c
               /\ MaxOps \in Nat
               /\ Mutant \in Mutants
               /\ ParentLate \in BOOLEAN

\* operations a thread may start; Root two more (open the statement's system operation, decide, call)
OpsMax(t) == IF t = Root THEN MaxOps + 2 ELSE MaxOps
Labels == {"idle", "ready", "acq", "inc", "rel", "d2", "join", "spwait", "done"}
Reasons == {"none", "free", "empty", "self", "pl", "other"}

VARIABLES pc, owner, cnt, depth, h, late, ops, decn, reason, spawnOK, decH, reent

vars == <<pc, owner, cnt, depth, h, late, ops, decn, reason, spawnOK, decH, reent>>

\* threads registered in the PL session: Root while it runs a stored procedure
Involved == IF pc[Root] = "spwait" THEN {Root} ELSE {}
Running(t) == pc[t] \notin {"idle", "done"}
RunKids(t) == {c \in Thr : Par[c] = t /\ Running(c)}
\* a thread that is executing, not waiting for its workers or for the stored procedure
Active(t) == pc[t] \notin {"idle", "done", "join", "spwait"}
\* inside a system operation: between lock_topop and unlock_topop
InSys(t) == h[t] > 0 \/ pc[t] \in {"inc", "rel"}
\* the thread that started t and waits for it (the JIRA comment's condition)
Waiter(t) == IF t = Q THEN Root ELSE Par[t]

\* is_under_system_operation () after its first read found the depth above zero
Reason(t) == IF owner = NoThr THEN "empty"
             ELSE IF owner = t THEN "self"
             ELSE IF owner \in Involved THEN "pl"
             ELSE "other"
Block(t) ==
  CASE Mutant = "develop" -> TRUE
    [] Mutant = "no_self" -> owner = NoThr \/ owner \in Involved
    [] Mutant = "no_pl" -> owner = NoThr \/ owner = t
    [] Mutant = "empty_other" -> owner = t \/ owner \in Involved
    [] Mutant = "jira" -> owner = NoThr \/ owner = t \/ owner = Waiter(t)
    [] OTHER -> owner = NoThr \/ owner = t \/ owner \in Involved

TypeOK ==
  /\ reent \in BOOLEAN
  /\ pc \in [Thr -> Labels]
  /\ owner \in Thr \cup {NoThr}
  /\ cnt \in Nat /\ depth \in Nat
  /\ h \in [Thr -> Nat] /\ late \in [Thr -> Nat] /\ ops \in [Thr -> Nat] /\ decH \in [Thr -> Nat]
  /\ decn \in [Thr -> {"none", "par", "serial"}]
  /\ reason \in [Thr -> Reasons]
  /\ spawnOK \in [Thr -> BOOLEAN]

Init ==
  /\ pc = [t \in Thr |-> IF t = Root THEN "ready" ELSE "idle"]
  /\ owner = NoThr /\ cnt = 0 /\ depth = 0
  /\ h = [t \in Thr |-> 0] /\ late = [t \in Thr |-> 0] /\ ops = [t \in Thr |-> 0]
  /\ decn = [t \in Thr |-> "none"] /\ reason = [t \in Thr |-> "none"]
  /\ spawnOK = [t \in Thr |-> FALSE] /\ decH = [t \in Thr |-> 0]
  /\ reent = FALSE

(* log_sysop_start is called: the thread needs a system operation and waits for rmutex_topop *)
Want(t) ==
  /\ pc[t] = "ready" /\ ops[t] < OpsMax(t)
  /\ pc' = [pc EXCEPT ![t] = "acq"]
  /\ ops' = [ops EXCEPT ![t] = @ + 1]
  /\ UNCHANGED <<owner, cnt, depth, h, late, decn, reason, spawnOK, decH, reent>>

(* lock_topop -> rmutex_lock: owner and count, re-entrant for the owner and through a thread
   registered in the PL session *)
Lockable(t) == owner = NoThr \/ owner = t \/ owner \in Involved
AcqEffect(t) ==
  /\ owner' = (IF owner = NoThr THEN t ELSE owner)
  /\ cnt' = cnt + 1
  /\ reent' = (reent \/ (owner # NoThr /\ owner # t))
  /\ UNCHANGED <<depth, h, late, decn, reason, spawnOK, decH>>
Acq(t) ==
  /\ pc[t] = "acq" /\ Lockable(t)
  /\ AcqEffect(t)
  /\ pc' = [pc EXCEPT ![t] = "inc"]
  /\ UNCHANGED ops

(* log_sysop_start: topops.last++. A level taken while workers of t run is "late". *)
Inc(t) ==
  /\ pc[t] = "inc"
  /\ depth' = depth + 1
  /\ h' = [h EXCEPT ![t] = @ + 1]
  /\ late' = (IF RunKids(t) # {} THEN [late EXCEPT ![t] = @ + 1] ELSE late)
  /\ pc' = [pc EXCEPT ![t] = "ready"]
  /\ UNCHANGED <<owner, cnt, ops, decn, reason, spawnOK, decH, reent>>

(* log_sysop_end_unstack: topops.last-- *)
Dec(t) ==
  /\ pc[t] = "ready" /\ h[t] > 0
  /\ depth' = depth - 1
  /\ h' = [h EXCEPT ![t] = @ - 1]
  /\ late' = (IF late[t] > 0 THEN [late EXCEPT ![t] = @ - 1] ELSE late)
  /\ pc' = [pc EXCEPT ![t] = "rel"]
  /\ UNCHANGED <<owner, cnt, ops, decn, reason, spawnOK, decH, reent>>

(* log_sysop_end_final -> unlock_topop -> rmutex_unlock *)
Rel(t) ==
  /\ pc[t] = "rel"
  /\ cnt' = cnt - 1
  /\ owner' = (IF cnt = 1 THEN NoThr ELSE owner)
  /\ pc' = [pc EXCEPT ![t] = "ready"]
  /\ UNCHANGED <<depth, h, late, ops, decn, reason, spawnOK, decH, reent>>

(* is_under_system_operation: the read of tdes->is_under_sysop () *)
D1(t) ==
  /\ pc[t] = "ready" /\ ops[t] < OpsMax(t)
  /\ ops' = [ops EXCEPT ![t] = @ + 1]
  /\ IF depth = 0
       THEN /\ decn' = [decn EXCEPT ![t] = "par"]
            /\ reason' = [reason EXCEPT ![t] = "free"]
            /\ spawnOK' = [spawnOK EXCEPT ![t] = TRUE]
            /\ decH' = [decH EXCEPT ![t] = h[t]]
            /\ pc' = pc
       ELSE /\ pc' = [pc EXCEPT ![t] = "d2"]
            /\ spawnOK' = [spawnOK EXCEPT ![t] = FALSE]
            /\ UNCHANGED <<decn, reason, decH>>
  /\ UNCHANGED <<owner, cnt, depth, h, late, reent>>

(* is_under_system_operation: the read of rmutex_topop.owner and the decision *)
D2(t) ==
  /\ pc[t] = "d2"
  /\ reason' = [reason EXCEPT ![t] = Reason(t)]
  /\ decn' = [decn EXCEPT ![t] = IF Block(t) THEN "serial" ELSE "par"]
  /\ spawnOK' = [spawnOK EXCEPT ![t] = ~Block(t)]
  /\ decH' = [decH EXCEPT ![t] = IF Block(t) THEN 0 ELSE h[t]]
  /\ pc' = [pc EXCEPT ![t] = "ready"]
  /\ UNCHANGED <<owner, cnt, depth, h, late, ops, reent>>

(* worker_manager::push_task after a decision that did not block *)
Spawn(t, c) ==
  /\ pc[t] = "ready" /\ spawnOK[t] /\ h[t] = decH[t]
  /\ Par[c] = t /\ pc[c] = "idle"
  /\ pc' = [pc EXCEPT ![c] = "ready"]
  /\ UNCHANGED <<owner, cnt, depth, h, late, ops, decn, reason, spawnOK, decH, reent>>

(* worker_manager::wait_workers. Environment A1: a thread does not wait for
   its workers inside a system operation it opened while they ran. *)
JoinStart(t) ==
  /\ pc[t] = "ready" /\ RunKids(t) # {}
  /\ late[t] = 0 \/ ParentLate
  /\ pc' = [pc EXCEPT ![t] = "join"]
  /\ UNCHANGED <<owner, cnt, depth, h, late, ops, decn, reason, spawnOK, decH, reent>>

JoinEnd(t) ==
  /\ pc[t] = "join" /\ RunKids(t) = {}
  /\ pc' = [pc EXCEPT ![t] = "ready"]
  /\ UNCHANGED <<owner, cnt, depth, h, late, ops, decn, reason, spawnOK, decH, reent>>

(* Root calls a stored procedure; Q runs its server-side SQL while Root waits.
   Environment A3: Root holds a system operation across the call only when no px task of
   the transaction runs (a statement-level system operation opens after its SELECT's workers end). *)
SpCall ==
  /\ pc[Root] = "ready" /\ ops[Root] < OpsMax(Root)
  /\ h[Root] > 0 => \A c \in Thr \ {Root, Q} : ~Running(c)
  /\ pc[Q] \in {"idle", "done"}
  /\ pc' = [pc EXCEPT ![Root] = "spwait", ![Q] = "ready"]
  /\ ops' = [ops EXCEPT ![Root] = @ + 1, ![Q] = 0]
  \* each call is a new request: Q starts with no decision
  /\ spawnOK' = [spawnOK EXCEPT ![Q] = FALSE]
  /\ decn' = [decn EXCEPT ![Q] = "none"]
  /\ reason' = [reason EXCEPT ![Q] = "none"]
  /\ decH' = [decH EXCEPT ![Q] = 0]
  /\ UNCHANGED <<owner, cnt, depth, h, late, reent>>

SpRet ==
  /\ pc[Root] = "spwait" /\ pc[Q] = "done"
  /\ pc' = [pc EXCEPT ![Root] = "ready"]
  /\ UNCHANGED <<owner, cnt, depth, h, late, ops, decn, reason, spawnOK, decH, reent>>

Finish(t) ==
  /\ pc[t] = "ready" /\ h[t] = 0 /\ RunKids(t) = {}
  /\ pc' = [pc EXCEPT ![t] = "done"]
  /\ UNCHANGED <<owner, cnt, depth, h, late, ops, decn, reason, spawnOK, decH, reent>>

Step(t) ==
  \/ Want(t) \/ Acq(t) \/ Inc(t) \/ Dec(t) \/ Rel(t) \/ D1(t) \/ D2(t)
  \/ (\E c \in Thr : Spawn(t, c))
  \/ JoinStart(t) \/ JoinEnd(t) \/ Finish(t)
  \/ (t = Root /\ (SpCall \/ SpRet))

AllEnded == pc[Root] = "done" /\ \A t \in Thr : pc[t] \in {"idle", "done"}
Terminating == AllEnded /\ UNCHANGED vars

Next == (\E t \in Thr : Step(t)) \/ Terminating

Spec == Init /\ [][Next]_vars /\ \A t \in Thr : WF_vars(Step(t))


\* Topologies for the cfgs: Root's workers 2, 3 (worker 2 has worker 4); Q's workers 5, 6.
ParMain == [t \in 0 .. 6 |-> IF t \in {2, 3} THEN 0 ELSE IF t = 4 THEN 2 ELSE IF t \in {5, 6} THEN 1 ELSE 0 - 1]
\* one size up: a third worker of Root (7)
ParScale == [t \in 0 .. 7 |-> IF t \in {2, 3, 7} THEN 0 ELSE IF t = 4 THEN 2 ELSE IF t \in {5, 6} THEN 1 ELSE 0 - 1]

----------------------------------------------------------------------------
(* Claims *)
\* C1 (CBRD-27938 Expected Result): a decision is serial only for its own,
\* an empty or a PL owner, never for another thread's system operation.
NoForeignSerial == \A t \in Thr : decn[t] = "serial" => reason[t] # "other"
\* C3: at most one executing thread is inside the system operation.
MutEx == \A t, u \in Thr : (t # u /\ InSys(t) /\ Active(t) /\ InSys(u)) => ~Active(u)
\* C2: the statement ends (deadlock freedom is TLC's deadlock check).
RootEnds == <>(pc[Root] = "done")

\* Witnesses: each must be reachable; its cfg expects the predicate violated.
NotParUnderForeign == ~\E t \in Thr : decn[t] = "par" /\ reason[t] = "other"
NotPlSerial == ~\E t \in Thr : decn[t] = "serial" /\ reason[t] = "pl"
NotSelfSerial == ~\E t \in Thr : decn[t] = "serial" /\ reason[t] = "self"
NotEmptySerialRace == ~\E t \in Thr : decn[t] = "serial" /\ reason[t] = "empty"
NotReentered == ~reent

----------------------------------------------------------------------------
(* Inductive invariant of the head (Mutant = "none", ParentLate = FALSE). *)
\* levels a thread holds toward the lock count: taken (inc) or not yet released (rel)
Lv(t) == h[t] + (IF pc[t] \in {"inc", "rel"} THEN 1 ELSE 0)
\* what the lock count and the depth add up to under an owner (Q re-enters through Root)
LvBy(o) == IF o = NoThr THEN 0 ELSE Lv(o) + (IF o = Root THEN Lv(Q) ELSE 0)
HBy(o) == IF o = NoThr THEN 0 ELSE h[o] + (IF o = Root THEN h[Q] ELSE 0)

R_ended == \A t \in Thr : pc[t] \in {"idle", "done"} => h[t] = 0
R_late == \A t \in Thr : late[t] <= h[t]
R_holder == \A t \in Thr : Lv(t) > 0 => (t = owner \/ (t = Q /\ owner = Root /\ pc[Root] = "spwait"))
R_cnt == cnt = LvBy(owner)
R_depth == depth = HBy(owner)
R_owner == owner # NoThr => Lv(owner) > 0
R_q == Running(Q) => pc[Root] = "spwait"
R_spwait == (pc[Root] = "spwait" /\ h[Root] > 0) =>
              (~spawnOK[Q] /\ \A c \in Thr \ {Root, Q} : ~Running(c))
R_spawn == \A t \in Thr : spawnOK[t] => decH[t] = 0
R_dec == \A t \in Thr : /\ (decn[t] = "serial" => reason[t] \in {"empty", "self", "pl"})
                        /\ (decn[t] = "par" => reason[t] \in {"free", "other"})

IndInv ==
  /\ TypeOK
  /\ pc[Root] # "idle"
  /\ R_ended /\ R_late /\ R_holder /\ R_cnt /\ R_depth /\ R_owner /\ R_q /\ R_spwait /\ R_spawn /\ R_dec

\* Apalache: the role set fixed, the bounds open
CInit == /\ Thr = {0, 1, 2, 3, 4, 5, 6} /\ Par = ParMain /\ MaxOps \in Nat /\ Mutant = "none" /\ ParentLate = FALSE
=============================================================================
