------------------------- MODULE FkParentUnlockedTrace -------------------------
(* Trace validation: is a run the instrumented fbaae2592 build recorded a behavior of
   FkParentUnlocked?  Each logged event is the action it names, by that process, with the logged
   slot and outcome; the steps the build does not log (statement start and end, the UPDATE's lock,
   the parent row lock, empty-phase transitions, the locked read's wait, victims) are Hidden.
   Accepted iff TLC reaches i = Len(TraceLog).  Events are normalized by traces/normalize.py. *)
EXTENDS FkParentUnlocked, FkParentUnlockedTraceData, Sequences

CONSTANT TraceLog
VARIABLE i
TVars == <<vars, i>>

TInit == Init /\ i = 0
Ev == TraceLog[i + 1]
MaskSet(m) == {s \in Slots : (m \div (2 ^ (s - 1))) % 2 = 1}
P == Ev.p
Logged ==
  /\ i < Len(TraceLog)
  /\ i' = i + 1
  /\ \/ Ev.a = "WInsHeap"  /\ cur[P] = Ev.s /\ WInsHeap(P)
     \/ Ev.a = "WInsEntry" /\ cur[P] = Ev.s /\ WInsEntry(P)
     \/ Ev.a = "WChkPass"  /\ cur[P] = Ev.s /\ WChkPass(P)
     \/ Ev.a = "WChkFail"  /\ cur[P] = Ev.s /\ WChkFail(P)
     \/ Ev.a = "WUpdStamp" /\ cur[P] = Ev.s /\ WUpdStamp(P)
     \/ Ev.a = "WCommit"   /\ WCommit(P)
     \/ Ev.a = "WAbort"    /\ WAbort(P)
     \/ Ev.a = "DMark"     /\ DMark
     \/ Ev.a = "DCollect"  /\ DCollect /\ coll' = MaskSet(Ev.coll) /\ (cc' <=> Ev.cc = 1)
                           /\ {s \in Slots : insr'[s] # NT} = MaskSet(Ev.insr)
     \/ Ev.a = "DP2"       /\ p2 # {} /\ Min(p2) = Ev.s /\ DP2 /\ (OtherRow(Ev.s) <=> Ev.o = 1)
                           /\ IF Ev.w = "none" THEN pcD' = "d_p2" ELSE pcD' = "d_p2wait" /\ waitOn' = Ev.w
     \/ Ev.a = "DP2Wait"   /\ DP2Wait
     \/ Ev.a = "DRCheck"   /\ DRCheck
                           /\ IF Ev.found # "none" THEN pcD' = "d_fail"
                              ELSE IF Ev.w # "none" THEN pcD' = "d_rwait" /\ waitOn' = Ev.w
                              ELSE pcD' = "d_commit"
     \/ Ev.a = "DRWait"    /\ DRWait
     \/ Ev.a = "DP3"       /\ p3 # {} /\ Min(p3) = Ev.s /\ DP3
                           /\ IF Ev.skip = 1 THEN pcD' = "d_p3" ELSE pcD' = "d_p3read"
     \/ Ev.a = "DP3Read"   /\ curS = Ev.s /\ DP3Read /\ pcD' = "d_p3" /\ (Ev.s \in kept' <=> Ev.kept = 1)
     \/ Ev.a = "DAct"      /\ DAct
     \/ Ev.a = "DCommit"   /\ DCommit
     \/ Ev.a = "DFail"     /\ DFail
Hidden ==
  /\ i' = i
  /\ \/ \E w \in Writers : WStart(w) \/ WEnd(w) \/ WUpdAcq(w) \/ WStmtEnd(w) \/ WStmtFault(w) \/ WInsHeapLost(w)
     \/ DLock
     \/ (DP2 /\ p2 = {})
     \/ (DP3 /\ p3 = {})
     \/ (DP3Read /\ pcD' = "d_p3wait")
     \/ DP3Wait
\* the ghosts of FkParentUnlocked's Next ride along
TNext == (Logged \/ Hidden)
  /\ gen' = [s \in Slots |-> IF row'[s] = row[s] THEN gen[s] ELSE gen[s] + 1]
  /\ p1gen' = IF pcD = "d_collect" /\ pcD' # "d_collect" THEN gen ELSE p1gen
TSpec == TInit /\ [][TNext]_TVars

TraceNotDone == i < Len(TraceLog)
=============================================================================
