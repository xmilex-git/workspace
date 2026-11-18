----------------------------- MODULE HaGateTrace -----------------------------
(* Trace validation: is a run of the instrumented build a behavior of HaGate? The server appends TLATRACE lines;
   events.py orders them, renames the session threads into the model's sessions and the numbers of the code
   into the model's names (MAP.md "Trace validation"). Every action is logged or synthesized from a logged
   evaluation; there is no hidden step. Accepted iff TLC reaches i = Len(TraceLog). *)
EXTENDS HaGate, HaGateTraceData, Sequences

CONSTANTS TraceLog
VARIABLE i
TVars == <<vars, i>>

TInit == Init /\ i = 0
Ev == TraceLog[i + 1]
B(x) == IF x THEN 1 ELSE 0
(* the write kinds a check site stands for: an entry point of the client half, the fold boundary, the executor,
   the serial code *)
KindsOf(c) == IF c = "cl" THEN {"dml", "ddl"}
              ELSE IF c = "bnd" THEN {"ddl", "wire"}
              ELSE IF c = "exe" THEN {"dml"} ELSE {"srv"}

Logged ==
  /\ i < Len(TraceLog)
  /\ i' = i + 1
  /\ \/ Ev.a = "Connect" /\ Connect(Ev.s, Ev.t)
     \/ Ev.a = "Admit" /\ ha = Ev.h /\ Admit(Ev.s, Ev.d = 1) /\ B(ph'[Ev.s] = "off") = Ev.rej
     \/ Ev.a = "Register" /\ Register(Ev.s) /\ B(ph'[Ev.s] = "idle") = Ev.ok
          /\ (Ev.ok = 1 => cnt'[Ev.s] = Ev.cnt /\ base'[Ev.s] = Ev.base /\ B(kept[Ev.s]) = Ev.resumed)
          /\ (Ev.ok = 0 => B(ref'[Ev.s] = "retry") = Ev.retry)
     \/ Ev.a = "Begin" /\ Begin(Ev.s)
     \/ Ev.a = "MBegin" /\ MBegin(Ev.s) /\ cnt'[Ev.s] = Ev.cnt
     \/ Ev.a = "MEnd" /\ MEnd(Ev.s) /\ cnt'[Ev.s] = Ev.cnt
     \/ Ev.a = "Write" /\ \E k \in KindsOf(Ev.c) : WOut(Ev.s, k) = Ev.out /\ Write(Ev.s, k)
     \/ Ev.a = "End1" /\ End1(Ev.s) /\ B(hu'[Ev.s]) = Ev.hu /\ base'[Ev.s] = Ev.base
     \/ Ev.a = "End2" /\ ha = Ev.h /\ End2(Ev.s, Ev.d = 1) /\ B(rst'[Ev.s]) = Ev.r /\ B(roc'[Ev.s]) = Ev.roc
     \/ Ev.a = "Leave" /\ Leave(Ev.s, Ev.y = 1) /\ B(ha' # ha) = Ev.tr
     \/ Ev.a = "Demote1" /\ Demote1
     \/ Ev.a = "Demote2" /\ Demote2 /\ B(ha' = "standby") = Ev.moved
     \/ Ev.a = "Promote1" /\ Promote1
     \/ Ev.a = "Promote2" /\ Promote2
     \/ Ev.a = "Maint" /\ Maint
     \/ Ev.a = "GateDis" /\ GateDis
     \/ Ev.a = "GateEn" /\ GateEn

TSpec == TInit /\ [][Logged]_TVars
TraceNotDone == i < Len(TraceLog)
=============================================================================
