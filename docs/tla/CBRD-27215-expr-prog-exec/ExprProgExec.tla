--------------------------- MODULE ExprProgExec ---------------------------
(* An expression program's per-execution state on a cached XASL clone (CBRD-27215, with CBRD-27361's
   generation-time images; develop be0a9ab1f).

   A clone sits in the plan cache's pool between executions; any thread of any transaction takes it.  A program's
   host-variable prologue fills slots from the execution's binds.  On a row, expr_prog_prepare skips the prologue
   when the program's exec_stamp equals the executing query's query_id; otherwise expr_prog_enter_execution runs it.
   query_id comes from a per-transaction counter that restarts and wraps (qmgr_allocate_query_entry), so two
   executions of one clone can carry the same query_id.  The final clear of the execution
   (qexec_clear_xasl is_final -> qdata_release_valptr_list_prog / qexec_clear_agg_list / qexec_clear_pred ->
   expr_prog_reset) releases the slots on the executing thread and invalidates the stamp. *)
EXTENDS Naturals

CONSTANTS Threads, QIDs, MaxExec, MaxRows, Mutant
ASSUME Assm == /\ Threads # {} /\ QIDs # {} /\ 0 \notin QIDs /\ "none" \notin Threads
               /\ MaxExec \in Nat /\ MaxRows \in Nat /\ MaxRows >= 1
               /\ Mutant \in {"none", "no_reset", "reset_keeps_stamp"}

VARIABLES
  cph,        \* the clone: "pool" (in the xcache pool), "run" (an execution has it)
  exec,       \* executions so far; execution e binds the host variable to e
  thr,        \* the thread executing the clone
  qid,        \* the executing query's query_id (xasl_state->query_id)
  left,       \* rows the execution still evaluates
  pdone,      \* EXPR_PROG.prologue_done
  svalid,     \* EXPR_PROG.exec_stamp_valid
  stamp,      \* EXPR_PROG.exec_stamp
  slot,       \* the host-variable slot's value: the execution that wrote it, 0 for none
  sowner,     \* the thread whose private heap holds the slot's value, "none"
  stale,      \* ghost: a row read a bind of another execution
  xfree,      \* ghost: a slot value released by a thread other than the one that allocated it
  sawCollide  \* ghost: an execution took the clone with the query_id of the one before it

vars == <<cph, exec, thr, qid, left, pdone, svalid, stamp, slot, sowner, stale, xfree, sawCollide>>

\* boolean and integer typing kept apart (P4: tlapm's SMT encoding cannot mix them)
TBool == /\ pdone \in BOOLEAN /\ svalid \in BOOLEAN /\ stale \in BOOLEAN /\ xfree \in BOOLEAN
         /\ sawCollide \in BOOLEAN
TRest == /\ cph \in {"pool", "run"} /\ exec \in 0..MaxExec /\ thr \in Threads \cup {"none"}
         /\ qid \in QIDs \cup {0} /\ left \in 0..MaxRows /\ stamp \in QIDs \cup {0}
         /\ slot \in 0..MaxExec /\ sowner \in Threads \cup {"none"}
TypeOK == TBool /\ TRest

NoStaleBind == ~stale                                       \* C1
NoCrossThreadFree == ~xfree                                 \* C2
\* witness: a query_id repeats across two executions of the clone and the second still reads its own bind
NotCollided == ~(sawCollide /\ cph = "pool" /\ ~stale)

Init == /\ cph = "pool" /\ exec = 0 /\ thr = "none" /\ qid = 0 /\ left = 0
        /\ pdone = FALSE /\ svalid = FALSE /\ stamp = 0 /\ slot = 0 /\ sowner = "none"
        /\ stale = FALSE /\ xfree = FALSE /\ sawCollide = FALSE

\* xcache_find_xasl_id_for_execute hands the clone to an execution on thread t with query_id q
Take(t, q) == /\ cph = "pool" /\ exec < MaxExec
              /\ cph' = "run" /\ exec' = exec + 1 /\ thr' = t /\ qid' = q /\ left' = MaxRows
              /\ sawCollide' = (sawCollide \/ (exec >= 1 /\ q = qid))
              /\ UNCHANGED <<pdone, svalid, stamp, slot, sowner, stale, xfree>>

\* a row: expr_prog_prepare, then the steps read the slot.  Running the prologue overwrites the slot
\* (the old value released by this thread)
Row == /\ cph = "run" /\ left > 0
       /\ left' = left - 1
       /\ IF svalid /\ stamp = qid
          THEN /\ UNCHANGED <<pdone, svalid, stamp, slot, sowner, xfree>>
               /\ stale' = (stale \/ slot # exec)
          ELSE /\ pdone' = TRUE /\ svalid' = TRUE /\ stamp' = qid
               /\ slot' = exec /\ sowner' = thr
               /\ xfree' = (xfree \/ (slot # 0 /\ sowner # thr))
               /\ UNCHANGED stale
       /\ UNCHANGED <<cph, exec, thr, qid, sawCollide>>

\* the execution ends -- its rows done, an error, an interrupt -- and its final clear runs on the executing
\* thread: expr_prog_reset releases the slots and re-arms the prologues; the clone goes back to the pool
EndExec == /\ cph = "run"
           /\ IF Mutant = "no_reset"
              THEN UNCHANGED <<pdone, svalid, slot, sowner, xfree>>
              ELSE /\ xfree' = (xfree \/ (slot # 0 /\ sowner # thr))
                   /\ slot' = 0 /\ sowner' = "none" /\ pdone' = FALSE
                   /\ svalid' = (Mutant = "reset_keeps_stamp" /\ svalid)
           /\ cph' = "pool" /\ thr' = "none" /\ left' = 0
           /\ UNCHANGED <<exec, qid, stamp, stale, sawCollide>>

Done == cph = "pool" /\ exec = MaxExec /\ UNCHANGED vars

Next == (\E t \in Threads, q \in QIDs : Take(t, q)) \/ Row \/ EndExec \/ Done
Spec == Init /\ [][Next]_vars

IState == /\ cph = "pool" => slot = 0 /\ sowner = "none" /\ ~svalid /\ ~pdone /\ thr = "none" /\ left = 0
          /\ cph = "run" => thr \in Threads /\ qid \in QIDs /\ exec >= 1
          /\ slot # 0 => cph = "run" /\ slot = exec /\ sowner = thr
          /\ slot = 0 => sowner = "none"
          /\ svalid => slot # 0 /\ stamp = qid
IndInv == TBool /\ TRest /\ stale = FALSE /\ xfree = FALSE /\ IState
=============================================================================
