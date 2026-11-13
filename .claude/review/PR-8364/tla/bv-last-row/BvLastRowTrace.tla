----------------------------- MODULE BvLastRowTrace -----------------------------
(* Trace validation: is a run of the instrumented PR head (f65d0c0fa, SA mode)
   a behavior of BvLastRow?  Each logged event must be the action it names with
   the logged outcome.  Hidden steps: a source row that is not copied (filtered,
   or a block that does not keep rows), the output of a block whose output reads
   no scan column, and the final clear when last_row was never allocated.
   Accepted iff TLC reaches i = Len(TraceLog). *)
EXTENDS BvLastRow, BvLastRowTraceData, Sequences

CONSTANT TraceLog
VARIABLE i
TVars == <<vars, i>>

TInit == Init /\ i = 0
Ev == TraceLog[i + 1]
Logged ==
  /\ i < Len(TraceLog)
  /\ i' = i + 1
  /\ \/ Ev.a = "Gen" /\ Gen /\ (flag' <=> Ev.f = 1) /\ (aggOpt' <=> Ev.ao = 1)
     \/ Ev.a = "Path" /\ Path
        /\ IF Ev.path = "fast" THEN path' \in {"fast", "none"} ELSE path' = Ev.path
     \/ Ev.a = "Keep" /\ Ev.ok = 1 /\ Row(TRUE) /\ Keeps(TRUE) /\ k' = Ev.row
     \/ Ev.a = "Keep" /\ Ev.ok = 0 /\ RowKeepFail /\ k' = Ev.row
     \/ Ev.a = "Close" /\ Close
     \/ Ev.a = "Restore" /\ Restore /\ ((flag /\ keptHas) <=> Ev.kept = 1)
     \/ Ev.a = "Output" /\ Output /\ readsScan /\ ((out' = 0) <=> Ev.null = 1)
     \/ Ev.a = "Free" /\ Clear /\ lrAlloc
Hidden ==
  /\ \/ \E p \in BOOLEAN : Row(p) /\ ~Keeps(p)
     \/ Output /\ ~readsScan
     \/ Clear /\ ~lrAlloc
  /\ UNCHANGED i
TSpec == TInit /\ [][Logged \/ Hidden]_TVars

TraceNotDone == i < Len(TraceLog)
=============================================================================
