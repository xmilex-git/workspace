------------------------------ MODULE LogLease ------------------------------
(* CBRD-27430 B2: the index N of a session's <broker>_<N>.sql.log, slow log and DDL log.

   A CAS wrote <broker>_<its number>. A session takes the lowest index no session of its broker holds: it
   opens var/cas_log_slots/<broker>_<N>.lock and asks for an exclusive flock without waiting, N = 1, 2, ...
   The lock belongs to the open file description, so it excludes the session threads of one server as well
   as the servers a broker hands sessions to, and the kernel drops it when its server dies. The session
   opens its logs under the index, and closes them before it closes the lock file.

   Roles: NS session threads in NP server processes (session s runs in process Proc(s)), the kernel.

   Constants:
     NS, NP, NI  sessions, server processes, indexes tried
     Mutant      "none" | "release_before_close" | "no_lease" *)
EXTENDS Naturals, FiniteSets

CONSTANTS NS, NP, NI, Mutant

\* apalache-type: NS Int
\* apalache-type: NP Int
\* apalache-type: NI Int
\* apalache-type: Mutant Str
\* apalache-type: lock Int -> Int
\* apalache-type: pc Int -> Str
\* apalache-type: idx Int -> Int
\* apalache-type: logopen Int -> Bool
\* apalache-type: alive Int -> Bool

\* lock: per index: the session whose open file description holds the flock, 0 when none
\* pc: per session: "idle" | "try" | "hold" | "released" | "done"
\* idx: per session: the index it tries or holds
\* logopen: per session: its log files of that index are open
\* alive: per server process
VARIABLES lock, pc, idx, logopen, alive

vars == <<lock, pc, idx, logopen, alive>>

S == 1..NS
P == 1..NP
I == 1..NI
Proc(s) == ((s - 1) % NP) + 1

Init ==
  /\ lock = [i \in I |-> 0]
  /\ pc = [s \in S |-> "idle"]
  /\ idx = [s \in S |-> 1]
  /\ logopen = [s \in S |-> FALSE]
  /\ alive = [p \in P |-> TRUE]

\* cas_server_session_log_begin
SBegin(s) ==
  /\ pc[s] = "idle" /\ alive[Proc(s)]
  /\ pc' = [pc EXCEPT ![s] = "try"] /\ idx' = [idx EXCEPT ![s] = 1]
  /\ UNCHANGED <<lock, logopen, alive>>

\* mutant: an index only the sessions of the same server exclude each other on
LocalFree(s) == \A t \in S : t # s /\ Proc(t) = Proc(s) /\ pc[t] = "hold" => idx[t] # idx[s]

\* flock (LOCK_EX | LOCK_NB) on the index's lock file
STry(s) ==
  /\ pc[s] = "try"
  /\ IF Mutant = "no_lease"
       THEN IF LocalFree(s)
              THEN pc' = [pc EXCEPT ![s] = "hold"] /\ UNCHANGED <<lock, idx>>
              ELSE idx[s] < NI /\ idx' = [idx EXCEPT ![s] = idx[s] + 1] /\ UNCHANGED <<lock, pc>>
       ELSE IF lock[idx[s]] = 0
              THEN /\ lock' = [lock EXCEPT ![idx[s]] = s]
                   /\ pc' = [pc EXCEPT ![s] = "hold"] /\ UNCHANGED idx
              ELSE idx[s] < NI /\ idx' = [idx EXCEPT ![s] = idx[s] + 1] /\ UNCHANGED <<lock, pc>>
  /\ UNCHANGED <<logopen, alive>>

\* cas_log_open, cas_slow_log_open, logddl: <broker>_<index> files
SOpen(s) ==
  /\ pc[s] = "hold" /\ ~logopen[s]
  /\ logopen' = [logopen EXCEPT ![s] = TRUE]
  /\ UNCHANGED <<lock, pc, idx, alive>>

\* the session's end: logddl_destroy, cas_log_close, cas_slow_log_close
SClose(s) ==
  /\ pc[s] \in {"hold", "released"} /\ logopen[s]
  /\ logopen' = [logopen EXCEPT ![s] = FALSE]
  /\ UNCHANGED <<lock, pc, idx, alive>>

\* cas_server_session_slot_end closes the lock file
SRelease(s) ==
  /\ pc[s] = "hold"
  /\ Mutant = "release_before_close" \/ ~logopen[s]
  /\ lock' = [i \in I |-> IF lock[i] = s THEN 0 ELSE lock[i]]
  /\ pc' = [pc EXCEPT ![s] = "released"]
  /\ UNCHANGED <<idx, logopen, alive>>

SDone(s) ==
  /\ pc[s] = "released" /\ ~logopen[s]
  /\ pc' = [pc EXCEPT ![s] = "done"]
  /\ UNCHANGED <<lock, idx, logopen, alive>>

\* kill -9 of a server: the kernel closes its descriptors
Crash(p) ==
  /\ alive[p]
  /\ alive' = [alive EXCEPT ![p] = FALSE]
  /\ lock' = [i \in I |-> IF lock[i] # 0 /\ Proc(lock[i]) = p THEN 0 ELSE lock[i]]
  /\ logopen' = [s \in S |-> IF Proc(s) = p THEN FALSE ELSE logopen[s]]
  /\ pc' = [s \in S |-> IF Proc(s) = p THEN "done" ELSE pc[s]]
  /\ UNCHANGED idx

Next ==
  \/ \E s \in S : SBegin(s) \/ STry(s) \/ SOpen(s) \/ SClose(s) \/ SRelease(s) \/ SDone(s)
  \/ \E p \in P : Crash(p)

Spec == Init /\ [][Next]_vars

TypeOK ==
  /\ lock \in [I -> 0..NS]
  /\ pc \in [S -> {"idle", "try", "hold", "released", "done"}]
  /\ idx \in [S -> I]
  /\ logopen \in [S -> BOOLEAN]
  /\ alive \in [P -> BOOLEAN]

\* C5: no two sessions on the host have the log files of one index open
Exclusive == \A s \in S, t \in S : s # t /\ logopen[s] /\ logopen[t] => idx[s] # idx[t]

\* C5: a session's logs are open only under an index it holds
OpenUnderLease == \A s \in S : logopen[s] => lock[idx[s]] = s

\* the lease table is consistent with the sessions
LockIsHolder == \A i \in I : lock[i] # 0 => pc[lock[i]] = "hold" /\ idx[lock[i]] = i /\ alive[Proc(lock[i])]

(* ---- the inductive invariant ---- *)

\* a session that holds an index is the holder of its lock file
HoldIsLock == \A s \in S : pc[s] = "hold" => lock[idx[s]] = s

\* the logs are open only between the lease and its release
OpenOnlyHeld == \A s \in S : logopen[s] => pc[s] = "hold"

\* a dead server's sessions are gone
DeadIsDone == \A s \in S : ~alive[Proc(s)] => pc[s] = "done" /\ ~logopen[s]

IndInv ==
  /\ TypeOK
  /\ HoldIsLock
  /\ OpenOnlyHeld
  /\ DeadIsDone
  /\ LockIsHolder
  /\ OpenUnderLease
  /\ Exclusive

CInit == NS = 3 /\ NP = 2 /\ NI = 3 /\ Mutant = "none"

\* witnesses
NotReused == ~(\E s \in S, t \in S : s # t /\ pc[s] = "done" /\ pc[t] = "hold" /\ idx[s] = idx[t] /\ logopen[t])
NotSecond == ~(\E s \in S : pc[s] = "hold" /\ idx[s] = 2)
NotAfterCrash == ~(\E p \in P : ~alive[p] /\ \E t \in S : alive[Proc(t)] /\ pc[t] = "hold" /\ idx[t] = 1)

=============================================================================
