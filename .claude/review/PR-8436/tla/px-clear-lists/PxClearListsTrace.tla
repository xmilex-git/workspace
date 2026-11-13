------------------------- MODULE PxClearListsTrace -------------------------
(* Trace validation: is a run of the instrumented head build (1e5fcd7ca + TLATRACE at qexec_clear_xasl_head's list
   destroy, qexec_intprt_fnc's per-row clear, MAP.md "Trace validation") a behavior of PxClearLists? traces/conv.py
   maps the raw log to arm-level events: TruncFree (the subquery's previous list destroyed before an execution),
   SubRow (a row of the subquery's own scan, while it builds its list), RowEnd / RowFree / RowDone (the arm's
   per-row clear and the frees inside it, with the arm whose clear did them), FinalFree (qexec_clear_xasl).
   Hidden: Start, Create, Use (not logged), and a truncation that finds no list. *)
EXTENDS PxClearLists, PxClearListsTraceData, Sequences, TLC

CONSTANTS TraceLog
VARIABLE t
TVars == <<vars, t>>

TInit == Init /\ t = 0

Ev == TraceLog[t + 1]

Logged ==
  /\ t < Len(TraceLog)
  /\ t' = t + 1
  /\ LET a == Ev.arm IN
     \/ Ev.a = "TruncFree" /\ pc[a] = "exec" /\ cur[a] # None /\ Trunc(a)
     \/ Ev.a = "SubRow" /\ pc[a] = "create" /\ UNCHANGED vars
     \/ Ev.a = "RowEnd" /\ EndRow(a)
     \/ Ev.a = "RowFree" /\ Ev.win = a /\ pc[a] = "rowdone" /\ UNCHANGED vars
     \/ Ev.a = "RowDone" /\ RowDone(a)
     \/ Ev.a = "FinalFree" /\ IF final THEN UNCHANGED vars ELSE Final

Hidden ==
  /\ UNCHANGED t
  /\ \E a \in Arms : Start(a) \/ Create(a) \/ Use(a) \/ (cur[a] = None /\ Trunc(a))

TSpec == TInit /\ [][Logged \/ Hidden]_TVars

TraceNotDone == t < Len(TraceLog)
=============================================================================
