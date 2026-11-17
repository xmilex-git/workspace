---------------------------- MODULE SslAckTrace ----------------------------
(* Trace validation of SslAck: the events of one client connection, from brd_park_client to the reply of its
   HANDOFF. The HANDOFF's sending is known from what followed it (the server handled it, or the request
   returned unsent); events.py places BRequest there (MAP.md "Trace validation"). No hidden step. *)
EXTENDS SslAck, SslAckTraceData, Sequences

CONSTANTS TraceLog
VARIABLE i
TVars == <<vars, i>>

TInit == Init /\ i = 0
Ev == TraceLog[i + 1]

Logged ==
  /\ i < Len(TraceLog)
  /\ i' = i + 1
  /\ \/ Ev.a = "BPark" /\ BPark
     \/ Ev.a = "BPeeked" /\ BPeeked
     \/ Ev.a = "BPeekTimeout" /\ BPeekTimeout
     \/ Ev.a = "BDequeue" /\ BDequeue
     \/ Ev.a = "BDial" /\ BDial(Ev.up = 1)
     \/ Ev.a = "BSlot" /\ BSlot(Ev.got = 1)
     \/ Ev.a = "BRequest" /\ BRequest(Ev.sent = 1)
     \/ Ev.a = "SHandle" /\ SHandle(Ev.ok = 1)
     \/ Ev.a = "BAck" /\ BAck
     \/ Ev.a = "BReject" /\ BReject
     \/ Ev.a = "BReplyTimeout" /\ BReplyTimeout
     \/ Ev.a = "SLate" /\ SLate

TSpec == TInit /\ [][Logged]_TVars

TraceNotDone == i < Len(TraceLog)
=============================================================================
