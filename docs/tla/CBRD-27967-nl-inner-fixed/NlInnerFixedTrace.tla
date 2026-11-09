------------------------------ MODULE NlInnerFixedTrace ------------------------------
(* Trace validation: is one execution of a statement on the instrumented build (traces/run1.raw, turned
   into R's actions by traces/post.py) a behavior of NlInnerFixed? Each logged event is the R action it
   names, with the logged outcome (the middle page a row came from and whether that row fixed it, whether
   the innermost scan holds its page). The build does not log the outer leaf (RLeaf) nor the move to the
   next outer row before the last (RONext); they fire as hidden steps. The run has no concurrent writer or
   vacuum, so W and V never step. Accepted iff TLC reaches i = Len(TraceLog). *)
EXTENDS NlInnerFixed, NlInnerFixedTraceData, Sequences

CONSTANT TraceLog
VARIABLE i
TVars == <<vars, i>>

TInit == Init /\ i = 0
Ev == TraceLog[i + 1]
Logged ==
  /\ i < Len(TraceLog)
  /\ i' = i + 1
  /\ \/ Ev.a = "OuterRow"  /\ RLookup
     \/ Ev.a = "OuterEnd"  /\ RONext /\ rpc' = "done"
     \/ Ev.a = "MStart"    /\ RMStart
     \/ Ev.a = "MRow"      /\ RMRow /\ MPage(mp) = Ev.pg /\ ((mfix' = mfix + 1) <=> Ev.fix = 1)
     \/ Ev.a = "MNextPage" /\ RMNextPage /\ ((cvp' = 2) <=> Ev.copy = 1)
     \/ Ev.a = "MEnd"      /\ RMEnd
     \/ Ev.a = "IReset"    /\ (held = {} <=> Ev.held = 0) /\ UNCHANGED vars
     \/ Ev.a = "IStart"    /\ RIStart /\ ifix' = 1
     \/ Ev.a = "IRow"      /\ RIRow /\ (held # {} <=> Ev.held = 1)
     \/ Ev.a = "IEarly"    /\ RIEarly
     \/ Ev.a = "INextPage" /\ RINextPage
     \/ Ev.a = "IEnd"      /\ RIEnd
     \/ Ev.a = "IBack"     /\ RIBack /\ (held' = {} <=> Ev.held = 0)
Hidden == (RLeaf \/ (RONext /\ rpc' # "done")) /\ UNCHANGED i
TSpec == TInit /\ [][Logged \/ Hidden]_TVars

TraceNotDone == i < Len(TraceLog)
=============================================================================
