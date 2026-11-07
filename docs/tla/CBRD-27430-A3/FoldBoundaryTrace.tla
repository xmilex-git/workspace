------------------------- MODULE FoldBoundaryTrace -------------------------
(* Trace validation: is a run of the instrumented build (TLATRACE lines of the folded session's thread) a
   behavior of FoldBoundary? Each logged event is the action it names with the logged outcome; an error a
   call sets without logging it (OtherErr) may happen in between. Accepted iff TLC reaches i = Len(TraceLog). *)
EXTENDS FoldBoundary, FoldBoundaryTraceData, Sequences

CONSTANT TraceLog
VARIABLE i
TVars == <<vars, i>>

TInit == Init /\ i = 0
Ev == TraceLog[i + 1]
Logged ==
  /\ i < Len(TraceLog)
  /\ i' = i + 1
  /\ \/ Ev.a = "StmtStart" /\ StmtStart
     \/ Ev.a = "Enter" /\ Ev.d = depth + 1 /\ (Ev.inv = 1 <=> tmInv) /\ Enter(Ev.k)
     \/ Ev.a = "Read" /\ (Ev.built = 1 <=> snap = 0) /\ Read
     \/ Ev.a = "LockWait" /\ LockWait
     \/ Ev.a = "Grant" /\ Grant
     \/ Ev.a = "Victim" /\ Victim
     \/ Ev.a = "RRLock" /\ RRLock /\ (waiting' <=> Ev.wait = 1)
     \/ Ev.a = "KillStep" /\ KillStep(Ev.o)
     \/ Ev.a = "CommitStep" /\ CommitStep
     \/ Ev.a = "Exit" /\ Exit /\ (depth = 1 => lastErr' = Ev.e)
                     /\ ((tran = "active" /\ tran' = "aborted") <=> Ev.abort = 1)
Hidden == OtherErr /\ UNCHANGED i
TSpec == TInit /\ [][Logged \/ Hidden]_TVars

TraceNotDone == i < Len(TraceLog)
=============================================================================
