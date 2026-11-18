------------------------------ MODULE DomainCache ------------------------------
(* CBRD-27430 B4: the domain cache of a server that runs the client half of many sessions.

   The cache (tp_Domains, tp_Midxkey_domains) is one set of lists for the process, searched without a lock
   and never freed. A domain of the client half may hold a class MOP: a pointer into the workspace of the
   session that cached it. A session ends when its driver connection ends, and its workspace is freed then.
   So a domain that holds a MOP goes to lists the session owns (client_session_context), searched and changed
   only by the thread that holds the session's bracket, and freed after the workspace.

   Roles: NS session slots (a slot runs one session after another; a session may be kept for its client's
   next connection and resumed), server threads without a bracket (workers, and the server half of any
   session) that look a class's domain up by OID.

   Constants:
     NS, NC, NA   session slots, classes, addresses a workspace gives its MOPs
     MaxInc       sessions one slot runs
     Mutant       "none" | "process_list" | "oom_fallback" | "shared_lists" | "no_match"
                  | "free_before_ws" | "gc_teardown" *)
EXTENDS Integers, FiniteSets

CONSTANTS NS, NC, NA, MaxInc, Mutant

\* apalache-type: NS Int
\* apalache-type: NC Int
\* apalache-type: NA Int
\* apalache-type: MaxInc Int
\* apalache-type: Mutant Str
\* apalache-type: st Int -> Str
\* apalache-type: ws Int -> Str
\* apalache-type: inc Int -> Int
\* apalache-type: tran Int -> Str
\* apalache-type: maddr Int -> (Int -> Int)
\* apalache-type: sl Int -> (Int -> Int)
\* apalache-type: srefs Int -> Set(Int)
\* apalache-type: sfreed Int -> Bool
\* apalache-type: pm Set({c: Int, s: Int, i: Int, a: Int})
\* apalache-type: po Set(Int)
\* apalache-type: uaf Bool
\* apalache-type: foreign Bool
\* apalache-type: wrongDom Bool
\* apalache-type: reused Bool

\* st[s]       "free" | "run" | "kept" | "end1" | "end2": the slot's session thread (end1: rolled back, end2: the
\*             workspace is freed)
\* ws[s]       "none" | "live" | "final": the session's workspace (final: freed, the session lists not yet)
\* inc[s]      sessions the slot has run
\* tran[s]     "none" | "active" | "xa" (prepared)
\* maddr[s][c] the address of the session's MOP of class c, 0 when its workspace has none
\* sl[s][c]    nodes of class c in the session's lists
\* srefs[s]    classes whose session-list node the workspace's class structures point at
\* sfreed[s]   the session lists were freed while the workspace still points at their nodes
\* pm          process-list nodes that hold a MOP: class, owner slot and incarnation, the MOP's address
\* po          classes with an OID-only node in the process list
\* ghosts: uaf (a freed MOP or node was read), foreign (a thread read a MOP of another session's workspace),
\*         wrongDom (a session was given a domain whose MOP is not its own MOP of that class),
\*         reused (a workspace gave an address a freed MOP had)
VARIABLES st, ws, inc, tran, maddr, sl, srefs, sfreed, pm, po, uaf, foreign, wrongDom, reused

vars == <<st, ws, inc, tran, maddr, sl, srefs, sfreed, pm, po, uaf, foreign, wrongDom, reused>>

S == 1..NS
C == 1..NC
A == 1..NA
ZeroC == [c \in C |-> 0]

\* the slot whose lists a session's MOP domains go to.  mutant shared_lists: one set of lists for every session
\* (the sub-client lists as plain statics of the server)
L(s) == IF Mutant = "shared_lists" THEN 1 ELSE s

Init ==
  /\ st = [s \in S |-> "free"] /\ ws = [s \in S |-> "none"] /\ inc = [s \in S |-> 0]
  /\ tran = [s \in S |-> "none"] /\ maddr = [s \in S |-> ZeroC] /\ sl = [s \in S |-> ZeroC]
  /\ srefs = [s \in S |-> {}] /\ sfreed = [s \in S |-> FALSE]
  /\ pm = {} /\ po = {}
  /\ uaf = FALSE /\ foreign = FALSE /\ wrongDom = FALSE /\ reused = FALSE

\* driver_session_run: a connection is adopted, db_restart_ex makes the workspace
Begin(s) ==
  /\ st[s] = "free" /\ ws[s] = "none" /\ inc[s] < MaxInc
  /\ st' = [st EXCEPT ![s] = "run"] /\ ws' = [ws EXCEPT ![s] = "live"] /\ inc' = [inc EXCEPT ![s] = inc[s] + 1]
  /\ tran' = [tran EXCEPT ![s] = "none"]   \* a prepared transaction of the slot's last session is its coordinator's
  /\ UNCHANGED <<maddr, sl, srefs, sfreed, pm, po, uaf, foreign, wrongDom, reused>>

\* a statement leaves a transaction open, prepares it, or ends it
Tran(s, x) ==
  /\ st[s] = "run" /\ tran[s] # x
  /\ tran' = [tran EXCEPT ![s] = x]
  /\ UNCHANGED <<st, ws, inc, maddr, sl, srefs, sfreed, pm, po, uaf, foreign, wrongDom, reused>>

\* ws_mop: the workspace makes the MOP of a class at an address no live MOP has
Mop(s, c, a) ==
  /\ st[s] = "run" /\ ws[s] = "live" /\ maddr[s][c] = 0
  /\ \A t \in S, d \in C : maddr[t][d] # a
  /\ maddr' = [maddr EXCEPT ![s][c] = a]
  /\ reused' = (reused \/ \E n \in pm : n.a = a)
  /\ UNCHANGED <<st, ws, inc, tran, sl, srefs, sfreed, pm, po, uaf, foreign, wrongDom>>

\* the node a MOP-holding domain of (s, c) is in the process list
PNode(s, c) == [c |-> c, s |-> s, i |-> inc[s], a |-> maddr[s][c]]

\* tp_domain_cache / tp_domain_find_object of a domain that holds the session's MOP of class c, into the
\* session's lists: found there, or inserted.  mutant no_match: the server's "no match for an object domain"
ResolveSess(s, c) ==
  /\ st[s] = "run" /\ ws[s] = "live" /\ maddr[s][c] # 0
  /\ Mutant \notin {"process_list"}
  /\ IF sl[L(s)][c] > 0 /\ Mutant # "no_match"
       THEN UNCHANGED sl
       ELSE sl' = [sl EXCEPT ![L(s)][c] = IF sl[L(s)][c] < 2 THEN sl[L(s)][c] + 1 ELSE 2]
  \* under shared_lists the node found may be another session's: its MOP is compared by address and read
  /\ wrongDom' = (wrongDom \/ (Mutant = "shared_lists" /\ sl[L(s)][c] > 0 /\ L(s) # s))
  /\ srefs' = [srefs EXCEPT ![s] = srefs[s] \cup {c}]
  /\ UNCHANGED <<st, ws, inc, tran, maddr, sfreed, pm, po, uaf, foreign, reused>>

\* the same into the process lists (mutant process_list: the code before this change; mutant oom_fallback: taken
\* when the session's lists cannot be allocated).  The search compares MOP pointers: a node whose MOP has this
\* address is the answer, whoever made it
ResolveProc(s, c) ==
  /\ st[s] = "run" /\ ws[s] = "live" /\ maddr[s][c] # 0
  /\ Mutant \in {"process_list", "oom_fallback"}
  /\ IF \E n \in pm : n.a = maddr[s][c]
       THEN /\ wrongDom' = (wrongDom \/ \E n \in pm : n.a = maddr[s][c] /\ n # PNode(s, c))
            /\ UNCHANGED pm
       ELSE pm' = pm \cup {PNode(s, c)} /\ UNCHANGED wrongDom
  /\ UNCHANGED <<st, ws, inc, tran, maddr, sl, srefs, sfreed, po, uaf, foreign, reused>>

\* the allocation of the session's lists fails: the statement fails, nothing is cached
ResolveOom(s, c) ==
  /\ st[s] = "run" /\ ws[s] = "live" /\ maddr[s][c] # 0
  /\ UNCHANGED vars

\* tp_domain_find_object by class OID in the process list, by a thread t (0: a thread without a bracket; a
\* slot: the server half of its session). Every node on the way is compared: a node that holds a MOP has its
\* OID read through the MOP (WS_OID)
FindOid(t, c) ==
  /\ IF t = 0 THEN TRUE ELSE st[t] = "run"
  /\ uaf' = (uaf \/ \E n \in pm : ws[n.s] # "live" \/ inc[n.s] # n.i)
  /\ foreign' = (foreign \/ \E n \in pm : n.s # t)
  /\ po' = po \cup {c}
  /\ UNCHANGED <<st, ws, inc, tran, maddr, sl, srefs, sfreed, pm, wrongDom, reused>>

\* a session that is not in a transaction yields its connection (KEEP_CONNECTION=AUTO) and is kept
Yield(s) ==
  /\ st[s] = "run" /\ tran[s] = "none"
  /\ st' = [st EXCEPT ![s] = "kept"]
  /\ UNCHANGED <<ws, inc, tran, maddr, sl, srefs, sfreed, pm, po, uaf, foreign, wrongDom, reused>>

\* its client's next connection claims it, on another thread
Resume(s) ==
  /\ st[s] = "kept"
  /\ st' = [st EXCEPT ![s] = "run"]
  /\ UNCHANGED <<ws, inc, tran, maddr, sl, srefs, sfreed, pm, po, uaf, foreign, wrongDom, reused>>

\* a kept session nobody claims within session_state_timeout: a daemon thread ends it
Expire(s) ==
  /\ st[s] = "kept"
  /\ st' = [st EXCEPT ![s] = "end1"]
  /\ UNCHANGED <<ws, inc, tran, maddr, sl, srefs, sfreed, pm, po, uaf, foreign, wrongDom, reused>>

\* the connection ends: the open transaction is rolled back, a prepared one stays for its coordinator
EndRollback(s) ==
  /\ st[s] = "run" /\ Mutant # "gc_teardown"
  /\ tran' = [tran EXCEPT ![s] = IF tran[s] = "xa" THEN "xa" ELSE "none"]
  /\ st' = [st EXCEPT ![s] = "end1"]
  /\ UNCHANGED <<ws, inc, maddr, sl, srefs, sfreed, pm, po, uaf, foreign, wrongDom, reused>>

\* csc_teardown: ws_final frees the MOPs and the class structures; each of their domains is "freed" (a cached
\* node is left alone, which reads the node)
WsFinal(s) ==
  /\ st[s] = "end1" /\ ws[s] = "live"
  /\ uaf' = (uaf \/ (sfreed[s] /\ srefs[s] # {}))
  /\ ws' = [ws EXCEPT ![s] = "final"] /\ maddr' = [maddr EXCEPT ![s] = ZeroC]
  /\ srefs' = [srefs EXCEPT ![s] = {}] /\ sfreed' = [sfreed EXCEPT ![s] = FALSE]
  /\ st' = [st EXCEPT ![s] = "end2"]
  /\ UNCHANGED <<inc, tran, sl, pm, po, foreign, wrongDom, reused>>

\* the session's domain lists are freed after its workspace
FreeLists(s) ==
  /\ st[s] = "end2" /\ ws[s] = "final"
  /\ sl' = [sl EXCEPT ![s] = ZeroC]
  /\ ws' = [ws EXCEPT ![s] = "none"] /\ st' = [st EXCEPT ![s] = "free"]
  /\ UNCHANGED <<inc, tran, maddr, srefs, sfreed, pm, po, uaf, foreign, wrongDom, reused>>

\* mutant free_before_ws: the lists go first
FreeListsEarly(s) ==
  /\ Mutant = "free_before_ws" /\ st[s] = "end1" /\ ws[s] = "live" /\ ~sfreed[s]
  /\ sl' = [sl EXCEPT ![s] = ZeroC] /\ sfreed' = [sfreed EXCEPT ![s] = TRUE]
  /\ UNCHANGED <<st, ws, inc, tran, maddr, srefs, pm, po, uaf, foreign, wrongDom, reused>>

\* mutant gc_teardown: the thread leaves, the session waits for session_state_timeout
EndLeave(s) ==
  /\ Mutant = "gc_teardown" /\ st[s] = "run"
  /\ st' = [st EXCEPT ![s] = "free"]
  /\ UNCHANGED <<ws, inc, tran, maddr, sl, srefs, sfreed, pm, po, uaf, foreign, wrongDom, reused>>

Gc(s) ==
  /\ Mutant = "gc_teardown" /\ st[s] = "free" /\ ws[s] = "live"
  /\ ws' = [ws EXCEPT ![s] = "none"] /\ maddr' = [maddr EXCEPT ![s] = ZeroC] /\ sl' = [sl EXCEPT ![s] = ZeroC]
  /\ srefs' = [srefs EXCEPT ![s] = {}] /\ tran' = [tran EXCEPT ![s] = "none"]
  /\ UNCHANGED <<st, inc, sfreed, pm, po, uaf, foreign, wrongDom, reused>>

Next ==
  \/ \E s \in S : Begin(s) \/ Yield(s) \/ Resume(s) \/ Expire(s) \/ EndRollback(s) \/ WsFinal(s) \/ FreeLists(s)
                  \/ FreeListsEarly(s) \/ EndLeave(s) \/ Gc(s)
  \/ \E s \in S, x \in {"none", "active", "xa"} : Tran(s, x)
  \/ \E s \in S, c \in C, a \in A : Mop(s, c, a)
  \/ \E s \in S, c \in C : ResolveSess(s, c) \/ ResolveProc(s, c) \/ ResolveOom(s, c)
  \/ \E t \in 0..NS, c \in C : FindOid(t, c)

Spec == Init /\ [][Next]_vars

TypeOK ==
  /\ st \in [S -> {"free", "run", "kept", "end1", "end2"}]
  /\ ws \in [S -> {"none", "live", "final"}]
  /\ inc \in [S -> 0..MaxInc]
  /\ tran \in [S -> {"none", "active", "xa"}]
  /\ maddr \in [S -> [C -> 0..NA]]
  /\ sl \in [S -> [C -> 0..2]]
  /\ srefs \in [S -> SUBSET C]
  /\ sfreed \in [S -> BOOLEAN]
  /\ pm \in SUBSET [c : C, s : S, i : 1..MaxInc, a : A]
  /\ po \in SUBSET C
  /\ uaf \in BOOLEAN /\ foreign \in BOOLEAN /\ wrongDom \in BOOLEAN /\ reused \in BOOLEAN

\* C4: no node of the process lists holds a MOP
NoMopInProcess == pm = {}

\* C4: no thread reads a freed MOP or node, nor a MOP of another session's workspace
NoUaf == ~uaf
NoForeign == ~foreign

\* C4: a session gets its own domain of a class, and one node per class
OwnDomain == ~wrongDom
Interned == \A s \in S, c \in C : sl[s][c] <= 1

\* C3: a session whose connection ended is gone when its thread is: no workspace, no open transaction
Prompt == \A s \in S : st[s] = "free" => ws[s] = "none" /\ tran[s] # "active"

(* ---- the inductive invariant ---- *)

\* a slot's workspace follows its thread
StWs ==
  \A s \in S :
    /\ st[s] \in {"run", "kept", "end1"} => ws[s] = "live"
    /\ st[s] = "end2" => ws[s] = "final"
    /\ st[s] = "kept" => tran[s] = "none"
    /\ st[s] = "end1" => tran[s] # "active"
    /\ st[s] = "end2" => tran[s] # "active"
    /\ st[s] # "free" => inc[s] >= 1

\* only a live workspace has MOPs, pointers into the lists, or list nodes of its own
WsOwns ==
  \A s \in S :
    /\ ws[s] # "live" => maddr[s] = ZeroC /\ srefs[s] = {}
    /\ ws[s] = "none" => sl[s] = ZeroC
    /\ \A c \in srefs[s] : sl[s][c] > 0
    /\ ~sfreed[s]

\* the MOPs of live workspaces have different addresses
AddrDistinct ==
  \A s \in S, t \in S, c \in C, d \in C :
    maddr[s][c] # 0 /\ maddr[s][c] = maddr[t][d] => s = t /\ c = d

IndInv ==
  /\ TypeOK
  /\ StWs
  /\ WsOwns
  /\ AddrDistinct
  /\ NoMopInProcess
  /\ NoUaf
  /\ NoForeign
  /\ OwnDomain
  /\ Interned
  /\ Prompt

CInit == NS = 2 /\ NC = 2 /\ NA = 2 /\ MaxInc = 2 /\ Mutant = "none"

\* witnesses
NotSecondOwn == ~(\E s \in S, c \in C : sl[s][c] = 1 /\ c \in srefs[s] /\ inc[s] = 2)
NotBoth == ~(\E c \in C : sl[1][c] = 1 /\ sl[2][c] = 1)
NotKeptWithNodes == ~(\E s \in S, c \in C : st[s] = "kept" /\ sl[s][c] = 1)
NotXaLeft == ~(\E s \in S : st[s] = "free" /\ tran[s] = "xa")
NotOidNode == po = {}
=============================================================================
