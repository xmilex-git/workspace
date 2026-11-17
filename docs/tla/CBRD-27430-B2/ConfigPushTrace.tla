-------------------------- MODULE ConfigPushTrace --------------------------
(* Trace validation: is a run of the instrumented build a behavior of ConfigPush? The broker, broker_changer and
   the server append TLATRACE lines to one file; events.py orders them by CLOCK_MONOTONIC and renames jobs into
   sessions, snapshot seqs into 1, 2, ... in the order they were taken and conf values into versions (MAP.md
   "Trace validation"). Every action is logged; there is no hidden step. Accepted iff TLC reaches
   i = Len(TraceLog). *)
EXTENDS ConfigPush, ConfigPushTraceData, Sequences

CONSTANTS TraceLog
VARIABLE i
TVars == <<vars, i>>

TInit == Init /\ i = 0
Ev == TraceLog[i + 1]
B(x) == IF x THEN 1 ELSE 0

Logged ==
  /\ i < Len(TraceLog)
  /\ i' = i + 1
  /\ \/ Ev.a = "AChange" /\ AChange
     \/ Ev.a = "BRestart" /\ BRestart
     \/ Ev.a = "DStart" /\ DStart(Ev.s, Ev.d)
     \/ Ev.a = "DSnap" /\ DSnap /\ dq' = Ev.q /\ dv' = Ev.v
     \/ Ev.a = "DSend" /\ DSend
     \/ Ev.a = "DReply" /\ DReply
     \/ Ev.a = "DTimeout" /\ DTimeout
     \/ Ev.a = "CStart" /\ CStart
     \/ Ev.a = "CDial" /\ CDial
     \/ Ev.a = "CSnap" /\ CSnap /\ cq' = Ev.q /\ cv' = Ev.v
     \/ Ev.a = "CSend" /\ CSend(Ev.d)
     \/ Ev.a = "CReply" /\ CReply(Ev.d)
     \/ Ev.a = "CTimeout" /\ CTimeout(Ev.d)
     \/ Ev.a = "CDone" /\ CDone /\ B(cok) = Ev.ok
     \/ Ev.a = "SHandoff" /\ \E m \in net : m.t = "H" /\ m.s = Ev.s /\ SHandoff(m)
                                               /\ bq'[Ev.s] = Ev.q /\ bv'[Ev.s] = Ev.v
     \/ Ev.a = "SRefuse" /\ \E m \in net : m.t = "H" /\ m.s = Ev.s /\ SRefuse(m)
     \/ Ev.a = "SConfigBegin" /\ \E m \in net : m.t = "C" /\ m.d = Ev.d /\ m.q = Ev.q /\ SConfigBegin(m)
     \/ Ev.a = "SWrite" /\ SWrite(Ev.s) /\ B(wph'[Ev.s] = "flag") = Ev.take
     \/ Ev.a = "SFlag" /\ SFlag(Ev.s)
     \/ Ev.a = "SConfigEnd" /\ \E m \in net : m.t = "C" /\ m.d = Ev.d /\ SConfigEnd(m)
     \/ Ev.a = "TClear" /\ TClear(Ev.s)
     \/ Ev.a = "TRead" /\ TRead(Ev.s) /\ hq'[Ev.s] = Ev.q
     \/ Ev.a = "TFinish" /\ TFinish(Ev.s)

TSpec == TInit /\ [][Logged]_TVars

TraceNotDone == i < Len(TraceLog)
=============================================================================
