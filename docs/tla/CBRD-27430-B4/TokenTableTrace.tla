--------------------------- MODULE TokenTableTrace ---------------------------
(* Trace validation of TokenTable. events_token.py merges the TLATRACE lines of cub_broker, the two servers and
   the run script (kill -9, SIGSTOP/SIGCONT) by CLOCK_MONOTONIC and renames them (MAP.md "Trace validation").
   No hidden step: a step the build takes without a line of its own is written by the converter from the lines
   around it. *)
EXTENDS TokenTable, TokenTableTraceData, Sequences

CONSTANTS TraceLog
VARIABLE i
TVars == <<vars, i>>

TInit == Init /\ i = 0
Ev == TraceLog[i + 1]
B(x) == IF x THEN 1 ELSE 0

\* what channel_get_or_dial logged of a database, against the model's state before the step
DialAs(e, res) ==
  \/ res = "live" /\ ch[e]
  \/ res = "ok" /\ ~ch[e] /\ up[e] /\ ans[e]
  \/ res = "refused" /\ ~ch[e] /\ ~up[e]
  \/ res = "none" /\ ~ch[e] /\ ~up[e]
  \/ res = "noans" /\ ~ch[e] /\ up[e] /\ ~ans[e]

Logged ==
  /\ i < Len(TraceLog)
  /\ i' = i + 1
  /\ \/ Ev.a = "DStart" /\ DStart(Ev.d, Ev.port) /\ B(dpc' = "scan") = Ev.scan
     \/ Ev.a = "DScan" /\ DialAs(Ev.e, Ev.res) /\ DScan(Ev.e)
     \/ Ev.a = "DScanEnd" /\ DScanEnd
     \/ Ev.a = "DDial" /\ DialAs(ddb, Ev.res) /\ DDial
     \/ Ev.a = "DWait" /\ DWait
     \/ Ev.a = "DGiveUp" /\ DGiveUp
     \/ Ev.a = "DSendOk" /\ DSendOk(Ev.t, Ev.sid)
     \/ Ev.a = "DSendNo" /\ DSendNo
     \/ Ev.a = "DSendDead" /\ DSendDead
     \/ Ev.a = "SEnd" /\ SEnd(Ev.e, Ev.t)
     \/ Ev.a = "SCrash" /\ SCrash(Ev.e)
     \/ Ev.a = "SRestart" /\ SRestart(Ev.e)
     \/ Ev.a = "Hang" /\ Hang(Ev.e)
     \/ Ev.a = "RDie" /\ RDie(Ev.e)
     \/ Ev.a = "Kill" /\ Kill(Ev.e)
     \/ Ev.a = "BRestart" /\ BRestart
     \/ Ev.a = "CnLook" /\ CnLook(Ev.t, Ev.q, Ev.s) /\ B(cpc' = "idle") = Ev.refused
     \/ Ev.a = "CnSend" /\ B(CnHits) = Ev.hit /\ CnSend

TSpec == TInit /\ [][Logged]_TVars

TraceNotDone == i < Len(TraceLog)
\* the run that restores the old dispatcher ends over the cap
TraceNotOverCap == ~(i = Len(TraceLog) /\ overCap)
\* the run that restores the server without the session id check ends with a cancel of a session the request did not name
TraceNotWrongCancel == ~(i = Len(TraceLog) /\ wrongCancel)
=============================================================================
