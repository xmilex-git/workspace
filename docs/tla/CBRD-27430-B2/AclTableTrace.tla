--------------------------- MODULE AclTableTrace ---------------------------
(* Trace validation of AclTable. The run's script writes the access control file with as many rules as its
   version and logs each rewrite; the server logs a load's steps and every check with the number of rules it
   read (MAP.md "Trace validation"). No hidden step. *)
EXTENDS AclTable, AclTableTraceData, Sequences

CONSTANTS TraceLog
VARIABLE i
TVars == <<vars, i>>

TInit == Init /\ i = 0
Ev == TraceLog[i + 1]

Logged ==
  /\ i < Len(TraceLog)
  /\ i' = i + 1
  /\ \/ Ev.a = "FEdit" /\ FEdit(Ev.bad = 1)
     \/ Ev.a = "LStart" /\ LStart(Ev.l)
     \/ Ev.a = "LParse" /\ LParse(Ev.l) /\ lbad'[Ev.l] = (Ev.ok = 0) /\ (Ev.ok = 1 => lver'[Ev.l] = Ev.n)
     \/ Ev.a = "LSwap" /\ LSwap(Ev.l)
     \/ Ev.a = "CCheck" /\ CCheck(Ev.c) /\ sfail'[Ev.c] = (Ev.failed = 1)
                                         /\ (Ev.failed = 0 => sver'[Ev.c] = Ev.n)
     \/ Ev.a = "CAgain" /\ CAgain(Ev.c)

TSpec == TInit /\ [][Logged]_TVars

TraceNotDone == i < Len(TraceLog)
=============================================================================
