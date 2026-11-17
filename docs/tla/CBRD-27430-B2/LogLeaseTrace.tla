--------------------------- MODULE LogLeaseTrace ---------------------------
(* Trace validation of LogLease. A session is a session thread's pass through cas_server_session_log_begin;
   events.py numbers the sessions so that Proc (s) is the server process that ran them, and the script logs the
   kill -9 of a server (MAP.md "Trace validation"). No hidden step. *)
EXTENDS LogLease, LogLeaseTraceData, Sequences

CONSTANTS TraceLog
VARIABLE i
TVars == <<vars, i>>

TInit == Init /\ i = 0
Ev == TraceLog[i + 1]
B(x) == IF x THEN 1 ELSE 0

Logged ==
  /\ i < Len(TraceLog)
  /\ i' = i + 1
  /\ \/ Ev.a = "SBegin" /\ SBegin(Ev.s)
     \/ Ev.a = "STry" /\ idx[Ev.s] = Ev.idx /\ STry(Ev.s) /\ B(pc'[Ev.s] = "hold") = Ev.got
     \/ Ev.a = "SOpen" /\ SOpen(Ev.s)
     \/ Ev.a = "SClose" /\ SClose(Ev.s)
     \/ Ev.a = "SRelease" /\ SRelease(Ev.s)
     \/ Ev.a = "SDone" /\ SDone(Ev.s)
     \/ Ev.a = "Crash" /\ Crash(Ev.p)

TSpec == TInit /\ [][Logged]_TVars

TraceNotDone == i < Len(TraceLog)
=============================================================================
