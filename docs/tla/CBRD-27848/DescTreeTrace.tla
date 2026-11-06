---------------------------- MODULE DescTreeTrace ----------------------------
(* Trace validation: is a run of the instrumented build (CBRD-27848 df7cc0a37 + TLATRACE, scratch worktree) a
   behavior of DescTree?  The build logs the scan's protocol steps; each logged event must be the action it
   names with the logged outcome.  Steps the build does not log fire in between: reading records (ScanRecord),
   the end of the scan, and other transactions' operations (the injected latch conflict and page free are their
   effects).  The real index holds thousands of keys and the model a handful, so record reads are not logged and
   the trace checks the protocol skeleton: which re-positioning each latch failure took, and in what order.
   Accepted iff TLC reaches i = Len(TraceLog). *)
EXTENDS DescTree, DescTreeTraceData, Sequences

CONSTANT TraceLog
VARIABLE i
TVars == <<vars, i>>

TInit == Init /\ i = 0
Ev == TraceLog[i + 1]
Logged ==
  /\ i < Len(TraceLog)
  /\ i' = i + 1
  /\ \/ Ev.a = "Start" /\ Start /\ pc' = "scan"
     \/ Ev.a = "Resume" /\ Resume
     \/ Ev.a = "PrevLatched" /\ PrevLatched
     \/ Ev.a = "PrevLatchFails" /\ PrevLatchFails
        /\ (started <=> Ev.started = 1) /\ ((curKey = NoKey) <=> Ev.curnull = 1)
     \/ Ev.a = "GapRequestP" /\ GapRequestP
     \/ Ev.a = "GapFixP" /\ GapFixP
        /\ CASE Ev.o = "unlinked" -> ~Linked
             [] Ev.o = "special" -> Linked /\ pc' \in {"start", "resume"}
             [] OTHER -> pc' = "gapc"
     \/ Ev.a = "GapLinked" /\ GapLinked
        /\ ((Ev.o = "restart") <=> pc' \in {"start", "resume"})
Hidden == (ScanRecord \/ ScanEnd \/ WriterLatch \/ WriterApply) /\ UNCHANGED i
TSpec == TInit /\ [][Logged \/ Hidden]_TVars

TraceNotDone == i < Len(TraceLog)
=============================================================================
