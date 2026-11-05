------------------------- MODULE PxErrorHandoffTrace -------------------------
(* Trace validation: is a run an instrumented build recorded a behavior of
   PxErrorHandoff? Each logged event must be the action it names, by that
   process, with the logged outcome; steps the build does not log (W_wait)
   may happen in between. Accepted iff TLC reaches i = Len(TraceLog). *)
EXTENDS PxErrorHandoff, PxErrorHandoffTraceData, Sequences

CONSTANT TraceLog
VARIABLE i
TVars == <<vars, i>>

TInit == Init /\ i = 0
Ev == TraceLog[i + 1]
Logged ==
  /\ i < Len(TraceLog)
  /\ i' = i + 1
  /\ \/ Ev.a = "L_spawn" /\ L_spawn
     \/ Ev.a = "L_work"  /\ L_work /\ (leaderFailed' <=> Ev.err = 1)
     \/ Ev.a = "L_join"  /\ L_join
     \/ Ev.a = "L_adopt" /\ L_adopt /\ (leaderErr' = "err" <=> Ev.err = 1)
     \/ Ev.a = "L_free"  /\ L_free
     \/ Ev.a = "W_run"   /\ W_run(Ev.p) /\ (failed'[Ev.p] <=> Ev.err = 1)
     \/ Ev.a = "W_done"  /\ W_done(Ev.p)
Hidden == (\E w \in Workers : W_wait(w)) /\ UNCHANGED i
TSpec == TInit /\ [][Logged \/ Hidden]_TVars

TraceNotDone == i < Len(TraceLog)
=============================================================================
