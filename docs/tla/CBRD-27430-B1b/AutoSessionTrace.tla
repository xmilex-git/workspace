-------------------------- MODULE AutoSessionTrace --------------------------
(* Trace validation: is a run of the instrumented build a behavior of AutoSession? The broker and the server append
   TLATRACE lines to one file; events.py orders them by CLOCK_MONOTONIC and renames jobs, tokens and session ids
   into the model's threads and sessions (MAP.md "Trace validation"). Every action is logged or synthesized from a
   logged evaluation; there is no hidden step. Accepted iff TLC reaches i = Len(TraceLog). *)
EXTENDS AutoSession, AutoSessionTraceData, Sequences

CONSTANTS TraceLog
VARIABLE i
TVars == <<vars, i>>

TInit == Init /\ i = 0
Ev == TraceLog[i + 1]
B(x) == IF x THEN 1 ELSE 0
OpOf(m) == IF m = "try" THEN "try" ELSE IF m = "w1" THEN "w1" ELSE IF m = "w0" THEN "w0" ELSE "reset"

Logged ==
  /\ i < Len(TraceLog)
  /\ i' = i + 1
  /\ \/ Ev.a = "BStart" /\ BStart(Ev.t, 1, Ev.s, Ev.c)
     \/ Ev.a = "BTop" /\ BTop /\ B(bpc' = "try") = Ev.full
     \/ Ev.a = "BTry" /\ BTry(1)
     \/ Ev.a = "BTryRep" /\ BTryRep /\ B(tryRep = "yes") = Ev.rep
     \/ Ev.a = "BWatch" /\ BWatch
     \/ Ev.a = "BSlot" /\ BSlot
     \/ Ev.a = "BHint" /\ BHint
     \/ Ev.a = "BTimeout" /\ BTimeout
     \/ Ev.a = "EReset" /\ EReset(1)
     \/ Ev.a = "CStart" /\ qn[1] > 0 /\ q[1][1] = Ev.op /\ CStart(1)
     \/ Ev.a = "CTCas" /\ CTCas(1, Ev.t) /\ B(st'[Ev.t] = "yielded") = Ev.ok
     \/ Ev.a = "CTWake" /\ CTWake(1)
     \/ Ev.a = "CW1" /\ CW1(1)
     \/ Ev.a = "CWScan" /\ CWScan(1) /\ B(cpc'[1] = "wx") = Ev.idle
     \/ Ev.a = "CWX" /\ CWX(1)
     \/ Ev.a = "CRMark" /\ CRMark(1, Ev.t)
     \/ Ev.a = "CRCas" /\ ccand[1] = Ev.t /\ CRCas(1)
     \/ Ev.a = "Create" /\ Create(Ev.t) /\ att'[Ev.t] = Ev.s
     \/ Ev.a = "Claim" /\ Claim(Ev.t) /\ B(pc'[Ev.t] = "swap") = Ev.ok
     \/ Ev.a = "Swap" /\ Swap(Ev.t)
     \/ Ev.a = "Auth" /\ Auth(Ev.t) /\ B(pc'[Ev.t] = "top") = Ev.ok
     \/ Ev.a = "Top" /\ Top(Ev.t, Ev.clean = 1)
     \/ Ev.a = "Rst" /\ B(rreq[Ev.t]) = Ev.rreq /\ Rst(Ev.t)
     \/ Ev.a = "Wch" /\ Wch(Ev.t) /\ B(pc'[Ev.t] = "wx") = Ev.go
     \/ Ev.a = "Wx" /\ Wx(Ev.t)
     \/ Ev.a = "WakeSeen" /\ WakeSeen(Ev.t) /\ pc'[Ev.t] = "exit"
     \/ Ev.a = "Request" /\ Request(Ev.t) /\ B(pc'[Ev.t] = "exec") = Ev.ok
     \/ Ev.a = "Exec" /\ Exec(Ev.t)
     \/ Ev.a = "ClientClose" /\ ClientClose(Ev.t)
     \/ Ev.a = "Finish" /\ Finish(Ev.t) /\ B(yld'[Ev.t]) = Ev.yld
     \/ Ev.a = "EndSession" /\ EndSession(Ev.t)
     \/ Ev.a = "FreeConn" /\ FreeConn(Ev.t)
     \/ Ev.a = "Deact" /\ Deact(Ev.t)
     \/ Ev.a = "Send" /\ Send(Ev.t)
     \/ Ev.a = "Timeout" /\ Timeout(Ev.s)
     \/ Ev.a = "XScan" /\ XScan(Ev.s)
     \/ Ev.a = "XRecheck" /\ xcand = Ev.s /\ XRecheck /\ B(xpc' = "tear") = Ev.exp
     \/ Ev.a = "XTear" /\ xcand = Ev.s /\ XTear
     \/ Ev.a = "XEndPass" /\ XEndPass

TSpec == TInit /\ [][Logged]_TVars

TraceNotDone == i < Len(TraceLog)
=============================================================================
