------------------------- MODULE DescLeafDispatchTrace -------------------------
(* Trace validation: is a run of the instrumented build (CBRD-27968 fix + TLATRACE, scratch worktree) a behavior
   of DescLeafDispatch?  The build logs the dispatcher's protocol steps under m_leaf_mutex: the first leaf
   handed out (D_leaf), the left link's check (D_fix_prev: linked or not), the last leaf's LSA check
   (D_check_last: unchanged or changed) and every later hand-out (D_desc_take).  Each logged event must be that
   action with the logged outcome.  Steps the build does not log fire in between: the workers' reads and waits,
   the resume path (resume_after_last_key, btree_locate_key_from_saved_leaf), and other transactions' inserts,
   deletes, splits and merges.  The real index holds thousands of keys and the model one per leaf, so keys and
   page ids are not matched: the trace checks the protocol skeleton, which check led to which hand-out.
   Accepted iff TLC reaches i = Len(TraceLog). *)
EXTENDS DescLeafDispatch, DescLeafDispatchTraceData, Sequences

CONSTANT TraceLog
VARIABLE i
TVars == <<vars, i>>

TInit == Init /\ i = 0
Ev == TraceLog[i + 1]
Logged ==
  /\ i < Len(TraceLog)
  /\ i' = i + 1
  /\ \E w \in Workers :
       \/ Ev.a = "D_leaf" /\ D_leaf(w)
       \/ Ev.a = "D_fix_prev" /\ D_fix_prev(w)
          /\ ((Ev.o = "linked") <=> pc'[w] = "D_check_last")
       \/ Ev.a = "D_check_last" /\ D_check_last(w)
          /\ ((Ev.o = "unchanged") <=> pc'[w] = "D_desc_take")
       \/ Ev.a = "D_desc_take" /\ D_desc_take(w)
Hidden ==
  /\ UNCHANGED i
  /\ \/ \E w \in Workers :
          \/ W_start(w) \/ W_ask(w) \/ W_lock(w) \/ W_dispatch(w) \/ D_root(w) \/ D_resume(w) \/ D_saved(w)
          \/ D_reroot(w) \/ D_reroot_leaf(w) \/ W_retry(w) \/ D_publish(w) \/ W_read(w) \/ W_stop(w) \/ W_end(w)
     \/ writer
TSpec == TInit /\ [][Logged \/ Hidden]_TVars

TraceNotDone == i < Len(TraceLog)
=============================================================================
