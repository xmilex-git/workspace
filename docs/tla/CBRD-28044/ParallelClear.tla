---------------------------- MODULE ParallelClear ----------------------------
(* The parallel subquery executor (px_query_task.cpp execute_job_internal) runs each job -- an
   aptr node, e.g. a UNION ALL branch -- on one thread, then clears that job's tree on the same
   thread (qexec_clear_xasl_for_parallel_aptr, is_final = true).  When every job has ended, the
   main thread clears the whole tree (qexec_clear_xasl), which frees what is still held, from its
   own private heap.  A node's execution state (heap attr values, scan caches, page batch copies)
   is allocated in the private heap of the thread that ran it.
   A job's tree is its block node plus the nodes of the lists the block owns (bptr, dptr, fptr,
   scan_ptr, eptr); the code is the same for each list, so one list of K nodes stands for them. *)
EXTENDS Naturals, FiniteSets

CONSTANTS NB, K, Fix, Mutant
\* apalache-type: NB Int
\* apalache-type: K Int
\* apalache-type: Fix Str
\* apalache-type: Mutant Str

\* Fix: "none" = develop (the job clear takes only the head of each list); "walk" = the job clear
\*   walks each list to its end.
\* Mutant: "none" | "follow_next" (the job clear also follows the job node's next, a sibling job)
\*   | "no_null" (a free leaves the pointer set, so a later clear frees it again)
\*   | "no_final" (the main thread's final clear is skipped)

Branches == 1..NB
Pos == 0..K                         \* 0 = the job's block node, 1..K = the list's nodes
Nodes == Branches \X Pos
Threads == {"main", "worker"}
Runner(b) == IF b = 1 THEN "main" ELSE "worker"   \* execute_job_internal: the main thread takes a job too

VARIABLES st, owner, jpc, fpc, crossFree, doubleFree
\* apalache-type: st <<Int, Int>> -> Str
\* apalache-type: owner <<Int, Int>> -> Str
\* apalache-type: jpc Int -> Str
\* apalache-type: fpc Str
\* apalache-type: crossFree Bool
\* apalache-type: doubleFree Bool

vars == <<st, owner, jpc, fpc, crossFree, doubleFree>>

\* st[n]: "none" (never run), "held" (state allocated, pointer set), "freed" (freed, pointer NULLed),
\*   "stale" (freed, pointer left set: Mutant "no_null").
\* owner[n]: the thread whose private heap holds n's state.
\* jpc[b]: "run", "clear", "end" of job b.  fpc: the main thread's final clear, "wait", "done".

Init ==
  /\ st = [n \in Nodes |-> "none"]
  /\ owner = [n \in Nodes |-> "main"]
  /\ jpc = [b \in Branches |-> "run"]
  /\ fpc = "wait"
  /\ crossFree = FALSE
  /\ doubleFree = FALSE

\* free of n by thread t (db_private_free_and_init through heap_attrinfo_end, scan cache end, ...)
FreeSt(n) == IF st[n] = "held" THEN (IF Mutant = "no_null" THEN "stale" ELSE "freed") ELSE st[n]
Frees(t, S) ==
  /\ st' = [n \in Nodes |-> IF n \in S THEN FreeSt(n) ELSE st[n]]
  /\ crossFree' = (crossFree \/ \E n \in S : st[n] \in {"held", "stale"} /\ owner[n] # t)
  /\ doubleFree' = (doubleFree \/ \E n \in S : st[n] = "stale")

\* job b runs its block: the block node and any subset of the list's nodes (a correlated
\* subquery runs only when a row reaches it; an error or an interrupt ends the job early)
Run(b) ==
  /\ jpc[b] = "run"
  /\ \E R \in SUBSET {p \in Pos : p > 0} :
       /\ st' = [n \in Nodes |-> IF n[1] = b /\ (n[2] = 0 \/ n[2] \in R) THEN "held" ELSE st[n]]
       /\ owner' = [n \in Nodes |-> IF n[1] = b THEN Runner(b) ELSE owner[n]]
  /\ jpc' = [jpc EXCEPT ![b] = "clear"]
  /\ UNCHANGED <<fpc, crossFree, doubleFree>>

\* the job's clear, on the thread that ran it
JobClear(b) ==
  /\ jpc[b] = "clear"
  /\ LET Mine == {n \in Nodes : n[1] = b /\ (n[2] = 0 \/ Fix = "walk" \/ n[2] = 1)}
         Sib  == IF Mutant = "follow_next" THEN {n \in Nodes : n[1] # b /\ n[2] = 0} ELSE {}
     IN Frees(Runner(b), Mine \cup Sib)
  /\ jpc' = [jpc EXCEPT ![b] = "end"]
  /\ UNCHANGED <<owner, fpc>>

\* the main thread's clear of the whole tree, after every job ended (run_jobs waits for them)
FinalClear ==
  /\ fpc = "wait"
  /\ \A b \in Branches : jpc[b] = "end"
  /\ IF Mutant = "no_final" THEN UNCHANGED <<st, crossFree, doubleFree>> ELSE Frees("main", Nodes)
  /\ fpc' = "done"
  /\ UNCHANGED <<owner, jpc>>

Done == fpc = "done" /\ UNCHANGED vars

Next == (\E b \in Branches : Run(b) \/ JobClear(b)) \/ FinalClear \/ Done

Spec == Init /\ [][Next]_vars

-----------------------------------------------------------------------------
TypeOK ==
  /\ st \in [Nodes -> {"none", "held", "freed", "stale"}]
  /\ owner \in [Nodes -> Threads]
  /\ jpc \in [Branches -> {"run", "clear", "end"}]
  /\ fpc \in {"wait", "done"}
  /\ crossFree \in BOOLEAN
  /\ doubleFree \in BOOLEAN

\* C4
OwnerFrees == ~crossFree
\* C5
FreedOnce == ~doubleFree /\ (fpc = "done" => \A n \in Nodes : st[n] # "held" /\ st[n] # "stale")

\* witnesses
NotWorkerListTail == ~(\E n \in Nodes : n[1] # 1 /\ n[2] = K /\ st[n] = "freed" /\ fpc = "done")
NotJobEndedEarly == ~(fpc = "done" /\ \E n \in Nodes : n[2] > 0 /\ st[n] = "none")

-----------------------------------------------------------------------------
\* inductive invariant (Fix = "walk", Mutant = "none")
OwnerIsRunner == \A n \in Nodes : st[n] # "none" => owner[n] = Runner(n[1])
NoStale == \A n \in Nodes : st[n] # "stale"
RunNothing == \A n \in Nodes : jpc[n[1]] = "run" => st[n] = "none"
ClearHeld == \A n \in Nodes : jpc[n[1]] = "clear" => (st[n] = "none" \/ st[n] = "held") /\ (n[2] = 0 => st[n] = "held")
EndFreed == \A n \in Nodes : jpc[n[1]] = "end" => st[n] # "held"
FinalAfterJobs == fpc = "done" => \A b \in Branches : jpc[b] = "end"

IndInv ==
  /\ TypeOK
  /\ OwnerIsRunner
  /\ NoStale
  /\ RunNothing
  /\ ClearHeld
  /\ EndFreed
  /\ FinalAfterJobs
  /\ OwnerFrees
  /\ FreedOnce

CInit == NB = 2 /\ K = 2 /\ Fix = "walk" /\ Mutant = "none"
=============================================================================
