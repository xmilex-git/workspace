--------------------------- MODULE StatsKillTrace ---------------------------
(* Trace validation of StatsKill. The slot's two counters are the requests a session started and finished;
   a row the reader copied is named by the publication it equals (events.py), -1 when it equals none
   (MAP.md "Trace validation"). No hidden step. *)
EXTENDS StatsKill, StatsKillTraceData, Sequences

CONSTANTS TraceLog
VARIABLE i
TVars == <<vars, i>>

TInit == Init /\ i = 0
Ev == TraceLog[i + 1]

Logged ==
  /\ i < Len(TraceLog)
  /\ i' = i + 1
  /\ \/ Ev.a = "SNew" /\ SNew(Ev.s, Ev.f)
     \/ Ev.a = "SPublish" /\ SPublish(Ev.s)
     \/ Ev.a = "SReqA" /\ SReqA(Ev.s)
     \/ Ev.a = "SReqB" /\ SReqB(Ev.s)
     \/ Ev.a = "SCleanup" /\ SCleanup(Ev.s)
     \/ Ev.a = "SDrain" /\ SDrain(Ev.s)
     \/ Ev.a = "SErase" /\ SErase(Ev.s)
     \/ Ev.a = "SClose" /\ SClose(Ev.s)
     \/ Ev.a = "RBegin" /\ RBegin
     \/ Ev.a = "RRow" /\ RRow(Ev.s) /\ ga' = Ev.ga /\ gb' = Ev.gb
     \/ Ev.a = "REnd" /\ REnd
     \/ Ev.a = "KBegin" /\ KBegin
     \/ Ev.a = "KPin" /\ KPin(Ev.s)
     \/ Ev.a = "KShut" /\ KShut
     \/ Ev.a = "KEnd" /\ KEnd

TSpec == TInit /\ [][Logged]_TVars

TraceNotDone == i < Len(TraceLog)
=============================================================================
