------------------------------- MODULE FoldOom -------------------------------
(* CBRD-27430 A8: an AREA allocation failure inside the folded server.

   The client half's AREAs (domains, sets, DB_VALUE containers, object and schema templates, object lists) are
   shared by every thread of cub_server. A client process aborts its transaction when one of them cannot grow
   (area->failure_function = ws_abort_transaction); the server never did (NULL). In the folded server one
   thread runs both halves: a session's bracket thread is in the client half (db_on_server = 0), in the server
   half it reached through enter_server (db_on_server > 0: the executor holds page fixes and its query is in
   progress), or back in the client half inside a method/SP dispatch (db_on_server = 0 again, the outer executor
   suspended below it). Threads without a bracket (CS requests, daemons, parallel-query workers) and a bracket
   with no registered client (the server boot's shared context, a session retired after its logout) run the
   same allocator.

   One AREA: entries are taken lock-free while a block has room; growing it takes area_mutex, mallocs a block
   and releases the mutex. A malloc failure (the fault) runs the failure callback, which on a gated thread
   aborts the session's transaction; the abort path may itself allocate from this AREA (and fail again).

   Constants:
     NB        registered sessions' bracket threads (thread t's session is t)
     HasBoot   one bracket thread with no registered client
     NW        threads with no bracket (each serves a CS request of its own transaction)
     Block     entries a new block holds
     MaxAllocs allocations each thread makes
     MaxFaults malloc failures in the whole run
     MaxMoves  half changes of a bracket thread (enter/exit server, dispatch in/out)
     Mutant    "none" | "old_a8" (gate = a bracket) | "no_registered" | "no_bracket" | "null" (no callback, as
               the server before A8) | "no_guard" | "cb_under_mutex" *)
EXTENDS Naturals, FiniteSets

CONSTANTS NB, HasBoot, NW, Block, MaxAllocs, MaxFaults, MaxMoves, Mutant

\* apalache-type: NB Int
\* apalache-type: HasBoot Bool
\* apalache-type: NW Int
\* apalache-type: Block Int
\* apalache-type: MaxAllocs Int
\* apalache-type: MaxFaults Int
\* apalache-type: MaxMoves Int
\* apalache-type: Mutant Str
\* apalache-type: hat Int -> Str
\* apalache-type: qry Int -> Str
\* apalache-type: lost Int -> Bool
\* apalache-type: ap Int -> Str
\* apalache-type: ip Int -> Str
\* apalache-type: inAbort Int -> Bool
\* apalache-type: allocs Int -> Int
\* apalache-type: moves Int -> Int
\* apalache-type: err Int -> Str
\* apalache-type: free Int
\* apalache-type: mutex Int
\* apalache-type: faults Int
\* apalache-type: aborted Set(Int)
\* apalache-type: outcome Int -> Str
\* apalache-type: outHat Int -> Str
\* apalache-type: serverAbort Bool
\* apalache-type: uaf Bool
\* apalache-type: missed Bool
\* apalache-type: wrongAbort Bool
\* apalache-type: noCtx Bool
\* apalache-type: selfDeadlock Bool
\* apalache-type: recAbort Bool
\* apalache-type: guardHit Bool

ASSUME Assm ==
  /\ NB \in Nat /\ NW \in Nat /\ HasBoot \in BOOLEAN
  /\ Block \in Nat \ {0} /\ MaxAllocs \in Nat /\ MaxFaults \in Nat /\ MaxMoves \in Nat
  /\ Mutant \in {"none", "old_a8", "no_registered", "no_bracket", "null", "no_guard", "cb_under_mutex"}

NoThread == 0
Brackets == 1..NB
BootT == IF HasBoot THEN {NB + 1} ELSE {}
Workers == (NB + 1 + (IF HasBoot THEN 1 ELSE 0)) .. (NB + NW + (IF HasBoot THEN 1 ELSE 0))
Threads == Brackets \cup BootT \cup Workers
\* the transaction an abort on t would end: its session's, the system transaction (the boot thread's index), or the
\* CS client's the worker serves
SysTran == NB + NW + 2
TranOf(t) == IF t \in BootT THEN SysTran ELSE t

Hats == {"client", "server", "dispatch"}
APs == {"none", "lock", "malloc", "cb", "abort", "ret"}
IPs == {"none", "start", "malloc", "cb", "effect"}
Errs == {"none", "oom", "unilat"}
Outcomes == {"none", "null", "abort"}

(* hat      what runs below the thread: nothing ("client"), an executor with its page fixes and its query in progress
            ("server"), an executor suspended under a method dispatch ("dispatch", libcas depth > 0); a bracket
            thread's db_on_server is > 0 exactly in "server"
   qry      the executor's query below the thread: "running" (QUERY_IN_PROGRESS) or "freed" by an abort
   lost     the executor's page fixes were released under it
   ap, ip   the allocation in progress, and the allocation the abort path makes
   inAbort  ws_abort_transaction's thread-local in-progress flag
   err      the thread's current error
   free     entries left in the AREA's newest block; mutex the area_mutex holder
   aborted  transactions an allocation failure aborted
   outcome, outHat  the last failed allocation's end and the half it failed in (witnesses)
   serverAbort, uaf, missed, wrongAbort, noCtx, selfDeadlock, recAbort  violation ghosts (noCtx: a session
            context read on a thread with no bracket, where csc_current () asserts); guardHit a witness ghost *)
VARIABLES hat, qry, lost, ap, ip, inAbort, allocs, moves, err, free, mutex, faults, aborted,
          outcome, outHat, serverAbort, uaf, missed, wrongAbort, noCtx, selfDeadlock, recAbort, guardHit

vars == <<hat, qry, lost, ap, ip, inAbort, allocs, moves, err, free, mutex, faults, aborted,
          outcome, outHat, serverAbort, uaf, missed, wrongAbort, noCtx, selfDeadlock, recAbort, guardHit>>

TypeOK ==
  /\ hat \in [Threads -> Hats] /\ qry \in [Threads -> {"none", "running", "freed"}] /\ lost \in [Threads -> BOOLEAN]
  /\ ap \in [Threads -> APs] /\ ip \in [Threads -> IPs] /\ inAbort \in [Threads -> BOOLEAN]
  /\ allocs \in [Threads -> 0..MaxAllocs] /\ moves \in [Threads -> 0..MaxMoves] /\ err \in [Threads -> Errs]
  /\ free \in 0..Block /\ mutex \in Threads \cup {NoThread} /\ faults \in 0..MaxFaults
  /\ aborted \in SUBSET (Threads \cup {SysTran})
  /\ outcome \in [Threads -> Outcomes] /\ outHat \in [Threads -> Hats]
  /\ serverAbort \in BOOLEAN /\ uaf \in BOOLEAN /\ missed \in BOOLEAN /\ wrongAbort \in BOOLEAN /\ noCtx \in BOOLEAN
  /\ selfDeadlock \in BOOLEAN /\ recAbort \in BOOLEAN /\ guardHit \in BOOLEAN

Init ==
  /\ hat = [t \in Threads |-> IF t \in Workers THEN "server" ELSE "client"]
  /\ qry = [t \in Threads |-> IF t \in Workers THEN "running" ELSE "none"]
  /\ lost = [t \in Threads |-> FALSE]
  /\ ap = [t \in Threads |-> "none"] /\ ip = [t \in Threads |-> "none"] /\ inAbort = [t \in Threads |-> FALSE]
  /\ allocs = [t \in Threads |-> 0] /\ moves = [t \in Threads |-> 0] /\ err = [t \in Threads |-> "none"]
  /\ free = 0 /\ mutex = NoThread /\ faults = 0 /\ aborted = {}
  /\ outcome = [t \in Threads |-> "none"] /\ outHat = [t \in Threads |-> "client"]
  /\ serverAbort = FALSE /\ uaf = FALSE /\ missed = FALSE /\ wrongAbort = FALSE /\ noCtx = FALSE
  /\ selfDeadlock = FALSE /\ recAbort = FALSE /\ guardHit = FALSE

\* db_on_server > 0: every server thread starts at 1 (network_interface_sr.cpp), a bracket thread drops it to 0 for
\* its client half and enter_server raises it again
DbOnServer(t) == t \in Workers \/ hat[t] = "server"
\* the decision ws_abort_transaction makes: a bracket (csc_bracket_is_active), a registered client
\* (tm_Tran_index != NULL_TRAN_INDEX), the client half (db_on_server == 0)
RightGate(t) == t \in Brackets /\ ~DbOnServer(t)
Gate(t) ==
  IF Mutant = "old_a8" THEN t \in Brackets \cup BootT
  ELSE IF Mutant = "no_registered" THEN t \in Brackets \cup BootT /\ ~DbOnServer(t)
  ELSE IF Mutant = "null" THEN FALSE
  ELSE RightGate(t)
ReleaseOnFail(t) == IF Mutant = "cb_under_mutex" THEN mutex ELSE NoThread

Unchanged1 == UNCHANGED <<serverAbort, uaf, missed, wrongAbort, noCtx, selfDeadlock, recAbort, guardHit>>

(* area_alloc steps 1-2: an entry of a block with room, lock-free (LF bitmap) *)
FastAlloc(t) ==
  /\ ap[t] = "none" /\ allocs[t] < MaxAllocs /\ free > 0
  /\ free' = free - 1 /\ allocs' = [allocs EXCEPT ![t] = @ + 1]
  /\ UNCHANGED <<hat, qry, lost, ap, ip, inAbort, moves, err, mutex, faults, aborted, outcome, outHat>> /\ Unchanged1

(* area_alloc step 3: every block full, take area_mutex to add one *)
Lock(t) ==
  /\ ap[t] = "none" /\ allocs[t] < MaxAllocs /\ free = 0 /\ mutex = NoThread
  /\ mutex' = t /\ ap' = [ap EXCEPT ![t] = "malloc"]
  /\ UNCHANGED <<hat, qry, lost, ip, inAbort, allocs, moves, err, free, faults, aborted, outcome, outHat>>
  /\ Unchanged1

(* area_alloc_block succeeds: the new block is the hint block, one entry taken, area_mutex released *)
MallocOk(t) ==
  /\ ap[t] = "malloc"
  /\ free' = Block - 1 /\ mutex' = NoThread /\ ap' = [ap EXCEPT ![t] = "none"] /\ allocs' = [allocs EXCEPT ![t] = @ + 1]
  /\ UNCHANGED <<hat, qry, lost, ip, inAbort, moves, err, faults, aborted, outcome, outHat>> /\ Unchanged1

(* area_alloc_block (or area_insert_block's blockset) returns NULL: er_set ER_OUT_OF_VIRTUAL_MEMORY, area_mutex
   released, then area_call_failure_function *)
MallocFail(t) ==
  /\ ap[t] = "malloc" /\ faults < MaxFaults
  /\ faults' = faults + 1 /\ err' = [err EXCEPT ![t] = "oom"] /\ mutex' = ReleaseOnFail(t)
  /\ ap' = [ap EXCEPT ![t] = "cb"]
  /\ UNCHANGED <<hat, qry, lost, ip, inAbort, allocs, moves, free, aborted, outcome, outHat>> /\ Unchanged1

(* ws_abort_transaction entered from the outer allocation: the gate, then the in-progress flag *)
Callback(t) ==
  /\ ap[t] = "cb"
  /\ IF Gate(t) /\ ~inAbort[t]
       THEN /\ ap' = [ap EXCEPT ![t] = "abort"] /\ ip' = [ip EXCEPT ![t] = "start"]
            /\ inAbort' = [inAbort EXCEPT ![t] = TRUE]
            /\ missed' = missed
       ELSE /\ ap' = [ap EXCEPT ![t] = "ret"] /\ UNCHANGED <<ip, inAbort>>
            /\ missed' = (missed \/ RightGate(t))
  \* without the bracket test first, the gate reads tm_Tran_index through csc_current () on any thread
  /\ noCtx' = (noCtx \/ (Mutant = "no_bracket" /\ t \notin Brackets \cup BootT))
  /\ UNCHANGED <<hat, qry, lost, allocs, moves, err, free, mutex, faults, aborted, outcome, outHat>>
  /\ UNCHANGED <<serverAbort, uaf, wrongAbort, selfDeadlock, recAbort, guardHit>>

(* tran_unilaterally_abort -> tran_abort allocates (an entry with room, or a new block under area_mutex) *)
AbortAlloc(t) ==
  /\ ap[t] = "abort" /\ ip[t] = "start"
  /\ \/ /\ free > 0 /\ free' = free - 1 /\ ip' = [ip EXCEPT ![t] = "effect"]
        /\ UNCHANGED <<mutex, selfDeadlock>>
     \/ /\ free = 0 /\ mutex = NoThread /\ mutex' = t /\ ip' = [ip EXCEPT ![t] = "malloc"]
        /\ UNCHANGED <<free, selfDeadlock>>
     \/ /\ free = 0 /\ mutex = t
        \* pthread_mutex_lock on a default mutex its own thread holds never returns
        /\ selfDeadlock' = TRUE /\ ip' = [ip EXCEPT ![t] = "effect"] /\ UNCHANGED <<free, mutex>>
  /\ UNCHANGED <<hat, qry, lost, ap, inAbort, allocs, moves, err, faults, aborted, outcome, outHat>>
  /\ UNCHANGED <<noCtx, serverAbort, uaf, missed, wrongAbort, recAbort, guardHit>>

AbortMallocOk(t) ==
  /\ ap[t] = "abort" /\ ip[t] = "malloc"
  /\ free' = Block - 1 /\ mutex' = NoThread /\ ip' = [ip EXCEPT ![t] = "effect"]
  /\ UNCHANGED <<hat, qry, lost, ap, inAbort, allocs, moves, err, faults, aborted, outcome, outHat>> /\ Unchanged1

AbortMallocFail(t) ==
  /\ ap[t] = "abort" /\ ip[t] = "malloc" /\ faults < MaxFaults
  /\ faults' = faults + 1 /\ mutex' = ReleaseOnFail(t) /\ ip' = [ip EXCEPT ![t] = "cb"]
  /\ UNCHANGED <<hat, qry, lost, ap, inAbort, allocs, moves, err, free, aborted, outcome, outHat>> /\ Unchanged1

(* the callback re-entered from the abort's own allocation: the in-progress flag returns at once *)
AbortCallback(t) ==
  /\ ap[t] = "abort" /\ ip[t] = "cb"
  /\ ip' = [ip EXCEPT ![t] = "effect"]
  /\ IF Mutant = "no_guard" /\ Gate(t) THEN recAbort' = TRUE ELSE recAbort' = recAbort
  /\ guardHit' = TRUE
  /\ UNCHANGED <<hat, qry, lost, ap, inAbort, allocs, moves, err, free, mutex, faults, aborted, outcome, outHat>>
  /\ UNCHANGED <<noCtx, serverAbort, uaf, missed, wrongAbort, selfDeadlock>>

(* the abort ends the transaction: tran_abort -> ws_abort_mops, the folded xtran_server_abort -> lock_unlock_all ->
   pgbuf_unfix_all (returns at once inside a dispatch) and qmgr_clear_trans_wakeup (skips a query in progress
   while a pl session runs, asserts QUERY_COMPLETED otherwise); ER_LK_UNILATERALLY_ABORTED is the thread's error *)
AbortEffect(t) ==
  /\ ap[t] = "abort" /\ ip[t] = "effect"
  /\ aborted' = aborted \cup {TranOf(t)}
  /\ wrongAbort' = (wrongAbort \/ t \notin Brackets)
  /\ serverAbort' = (serverAbort \/ hat[t] = "server")
  /\ lost' = [lost EXCEPT ![t] = @ \/ hat[t] = "server"]
  /\ qry' = [qry EXCEPT ![t] = IF hat[t] = "server" /\ @ = "running" THEN "freed" ELSE @]
  /\ err' = [err EXCEPT ![t] = "unilat"]
  /\ inAbort' = [inAbort EXCEPT ![t] = FALSE]
  /\ ap' = [ap EXCEPT ![t] = "ret"] /\ ip' = [ip EXCEPT ![t] = "none"]
  /\ UNCHANGED <<hat, allocs, moves, free, mutex, faults, outcome, outHat>>
  /\ UNCHANGED <<noCtx, uaf, missed, selfDeadlock, recAbort, guardHit>>

(* area_alloc returns NULL; the caller unwinds on the error: a server-half caller's error path (scan close,
   qexec_clear) reads its page fixes and its query entry *)
Return(t) ==
  /\ ap[t] = "ret"
  /\ ap' = [ap EXCEPT ![t] = "none"] /\ allocs' = [allocs EXCEPT ![t] = @ + 1]
  /\ outcome' = [outcome EXCEPT ![t] = IF err[t] = "unilat" THEN "abort" ELSE "null"]
  /\ outHat' = [outHat EXCEPT ![t] = hat[t]]
  /\ uaf' = (uaf \/ (hat[t] = "server" /\ (lost[t] \/ qry[t] = "freed")))
  /\ err' = [err EXCEPT ![t] = "none"]
  /\ UNCHANGED <<hat, qry, lost, ip, inAbort, moves, free, mutex, faults, aborted>>
  /\ UNCHANGED <<noCtx, serverAbort, missed, wrongAbort, selfDeadlock, recAbort, guardHit>>

(* half changes of a session's bracket thread, between allocations: enter_server (the executor starts a query and
   fixes pages), exit_server (it ends them), method_dispatch in and out *)
Move(t, from, to) ==
  /\ t \in Brackets /\ ap[t] = "none" /\ moves[t] < MaxMoves /\ hat[t] = from
  /\ hat' = [hat EXCEPT ![t] = to] /\ moves' = [moves EXCEPT ![t] = @ + 1]
EnterServer(t) ==
  /\ Move(t, "client", "server") /\ qry' = [qry EXCEPT ![t] = "running"] /\ lost' = [lost EXCEPT ![t] = FALSE]
  /\ UNCHANGED <<ap, ip, inAbort, allocs, err, free, mutex, faults, aborted, outcome, outHat>> /\ Unchanged1
ExitServer(t) ==
  /\ Move(t, "server", "client") /\ qry' = [qry EXCEPT ![t] = "none"] /\ lost' = [lost EXCEPT ![t] = FALSE]
  /\ uaf' = (uaf \/ lost[t] \/ qry[t] = "freed")
  /\ UNCHANGED <<ap, ip, inAbort, allocs, err, free, mutex, faults, aborted, outcome, outHat>>
  /\ UNCHANGED <<noCtx, serverAbort, missed, wrongAbort, selfDeadlock, recAbort, guardHit>>
DispatchIn(t) ==
  /\ Move(t, "server", "dispatch")
  /\ UNCHANGED <<qry, lost, ap, ip, inAbort, allocs, err, free, mutex, faults, aborted, outcome, outHat>> /\ Unchanged1
DispatchOut(t) ==
  /\ Move(t, "dispatch", "server")
  /\ UNCHANGED <<qry, lost, ap, ip, inAbort, allocs, err, free, mutex, faults, aborted, outcome, outHat>> /\ Unchanged1

Done == \A t \in Threads : ap[t] = "none" /\ allocs[t] = MaxAllocs
Terminating == Done /\ UNCHANGED vars

Next ==
  \/ \E t \in Threads :
       \/ FastAlloc(t) \/ Lock(t) \/ MallocOk(t) \/ MallocFail(t) \/ Callback(t)
       \/ AbortAlloc(t) \/ AbortMallocOk(t) \/ AbortMallocFail(t) \/ AbortCallback(t) \/ AbortEffect(t)
       \/ Return(t) \/ EnterServer(t) \/ ExitServer(t) \/ DispatchIn(t) \/ DispatchOut(t)
  \/ Terminating

Spec == Init /\ [][Next]_vars

(* ---- properties ---- *)

\* C1: no allocation failure ends a transaction under a server-half executor, which keeps its fixes and its query
NoServerHalfAbort == ~serverAbort
NoUseAfterRelease == ~uaf
\* C2: a registered session's client-half failure aborts that session's transaction
ClientOomAborts == ~missed
\* C3: only a registered session's own transaction is ever aborted, and the gate reads a session context only under a bracket
Isolation == ~wrongAbort /\ ~noCtx /\ aborted \subseteq Brackets
\* C4: the callback never waits on an area_mutex its thread holds
NoSelfDeadlock == ~selfDeadlock
\* C5: a failure inside the abort does not start a second abort
NoRecursiveAbort == ~recAbort

IndInv ==
  /\ TypeOK
  /\ NoServerHalfAbort /\ NoUseAfterRelease /\ ClientOomAborts /\ Isolation /\ NoSelfDeadlock /\ NoRecursiveAbort
  /\ mutex # NoThread => (ap[mutex] = "malloc" \/ ip[mutex] = "malloc")
  /\ \A t \in Threads :
       /\ (ap[t] = "malloc" \/ ip[t] = "malloc") => mutex = t
       /\ (ap[t] = "abort") <=> (ip[t] # "none")
       /\ (ap[t] = "abort") <=> inAbort[t]
       /\ ap[t] = "abort" => RightGate(t)
       /\ ap[t] = "ret" => (err[t] = "unilat" <=> RightGate(t))
       /\ ap[t] \in {"cb", "abort"} => err[t] = "oom" \/ err[t] = "unilat"
       /\ ap[t] = "cb" => err[t] = "oom"
       /\ ip[t] = "effect" => err[t] = "oom"
       /\ ap[t] = "abort" => err[t] = "oom"
       /\ ap[t] \in {"none", "lock", "malloc"} => err[t] = "none"
       /\ err[t] = "unilat" => ap[t] = "ret" /\ RightGate(t)
       /\ ~lost[t] /\ qry[t] # "freed"
       /\ t \in Workers => hat[t] = "server" /\ qry[t] = "running" /\ moves[t] = 0
       /\ t \in BootT => hat[t] = "client" /\ qry[t] = "none" /\ moves[t] = 0
       /\ (t \in Brackets /\ hat[t] = "client") => qry[t] = "none"
       /\ (t \in Brackets /\ hat[t] # "client") => qry[t] = "running"
       /\ (ap[t] = "none" /\ allocs[t] = MaxAllocs) \/ allocs[t] < MaxAllocs
       /\ ap[t] # "none" => allocs[t] < MaxAllocs

\* Apalache's inductive check: Block and MaxFaults range over Nat; the role set sizes and the bounds that are
\* codomains of per-thread functions (Apalache needs constant ranges there) are the main cfg's
CInit ==
  /\ NB = 2 /\ NW = 1 /\ HasBoot = TRUE /\ MaxAllocs = 2 /\ MaxMoves = 3
  /\ Block \in Nat /\ Block > 0 /\ MaxFaults \in Nat
  /\ Mutant = "none"

(* ---- witnesses: outcomes that must be reachable ---- *)
NotClientAbort == ~\E t \in Brackets : outcome[t] = "abort" /\ outHat[t] = "client"
NotDispatchAbort == ~\E t \in Brackets : outcome[t] = "abort" /\ outHat[t] = "dispatch"
NotServerError == ~\E t \in Brackets : outcome[t] = "null" /\ outHat[t] = "server"
NotGuarded == ~(guardHit /\ \E t \in Brackets : outcome[t] = "abort")
NotUnregisteredError == ~\E t \in BootT \cup Workers : outcome[t] = "null"
=============================================================================
