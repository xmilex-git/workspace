-------------------------- MODULE MethodFoldTrace --------------------------
(* Trace validation: is a run of the instrumented A7 build a behavior of MethodFold? A tracer session's dispatch
   events are logged: Call (method_dispatch entered; deep = 1 when refused above METHOD_MAX_RECURSION_DEPTH), Query1
   and Query2 (a query nested in a dispatch starts and ends in qmgr_process_query), Commit (a transaction end inside
   a dispatch reaches pgbuf_unfix_all), Exit (method_dispatch returns; drain = 1 when it freed deferred handles).
   Not logged, so free to happen in between: the A4 lifecycle with its hook, the statement start and end, the
   last step of a dispatch's work, the resume of the outer executor, the routine's next callback and the workers'
   clone.
   Accepted iff TLC reaches i = Len(TraceLog). *)
EXTENDS MethodFold, MethodFoldTraceData, Sequences

CONSTANT TraceLog
VARIABLE i
TVars == <<all, i>>

TInit == Init7 /\ i = 0
Ev == TraceLog[i + 1]
P == Ev.p
Logged ==
  /\ i < Len(TraceLog)
  /\ i' = i + 1
  /\ \/ Ev.a = "Call" /\ TCall(P) /\ ((dep'[P] > dep[P] /\ fr'[P][dep'[P]].st = "deep") <=> (Ev.deep = 1))
     \/ Ev.a = "Query1" /\ TQuery1(P) /\ uxi'[P] = "nil"
     \/ Ev.a = "Query2" /\ TQuery2(P)
     \/ Ev.a = "Commit" /\ TCommit(P)
     \/ Ev.a = "Exit" /\ TExit(P) /\ ((hd[Loc(P)] # {} /\ hd'[Loc(P)] = {}) <=> (Ev.drain = 1))
\* the recorded runs' dispatches returned NO_ERROR (an error status shows in the tracer output, none did but the
\* refused depth, which is logged): the hidden end of a dispatch's work is the NO_ERROR one, and a callback error
\* (TErr, which changes only the current error) is left out. A run this narrower spec accepts, MethodFold accepts.
TDoneOk(s) == TDone(s) /\ fr'[s][Top(s)].st = "ok"
\* a callback's query runs a prepared statement, whose XASL comes from the cache (a clone: NULL unpack info), so
\* a logged Query1 is the cached case
Hidden ==
  /\ UNCHANGED i
  /\ \/ \E s \in Sess : (Life(s) /\ Hook) \/ TStart(s) \/ TDoneOk(s) \/ TResume(s) \/ TEnd(s) \/ TNext(s)
                         \/ PClone(s)
     \/ DStep /\ Hook
TSpec == TInit /\ [][Logged \/ Hidden]_TVars

TraceNotDone == i < Len(TraceLog)
=============================================================================
