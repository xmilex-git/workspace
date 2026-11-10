---------------------------- MODULE HandoffTrace ----------------------------
(* Trace validation: is a run of the instrumented build a behavior of Handoff? The broker and the server append
   TLATRACE lines to one file; events.py orders them by CLOCK_MONOTONIC (a sender's event carries the time taken
   before its send, so a receive never sorts first) and renames channels, tokens and transaction indices into the
   model's. Every action of the refinement map is logged, except Terminating and the second step of a cancel that
   found no transaction to interrupt. Accepted iff TLC reaches i = Len(TraceLog). *)
EXTENDS Handoff, HandoffTraceData

CONSTANTS TraceLog
VARIABLE i
TVars == <<vars, i>>

TInit == Init /\ i = 0
Ev == TraceLog[i + 1]
B(x) == IF x THEN 1 ELSE 0
HeadIs(q, c, op) == q[c] # <<>> /\ Head(q[c]).op = op

Logged ==
  /\ i < Len(TraceLog)
  /\ i' = i + 1
  /\ \/ Ev.a = "DStart" /\ DStart /\ dj' = Ev.j
     \/ Ev.a = "DGetCh" /\ DGetCh
        /\ CASE Ev.kind = "pub" -> published = Ev.c
             [] Ev.kind = "dial" -> published = 0 /\ dch' = Ev.c /\ dpc' = "hello"
             [] OTHER -> dpc' = "idle"
     \/ Ev.a = "DHello" /\ dch = Ev.c /\ DHello
     \/ Ev.a = "DResync" /\ dch = Ev.c /\ DResync
     \/ Ev.a = "DDialFail" /\ DDialFail /\ timeouts' - timeouts = Ev.to
     \/ Ev.a = "DAdmit" /\ DAdmit /\ ((dpc' # "idle") <=> Ev.ok = 1)
     \/ Ev.a = "DSend" /\ DSend /\ ((dpc' = "wait") <=> Ev.ok = 1)
     \/ Ev.a = "DWait" /\ DWait
        /\ CASE Ev.op = "ACK" -> mailbox[dch].op = "ACK"
             [] Ev.op = "REJECT" -> mailbox[dch].op = "REJECT"
             [] Ev.op = "timeout" -> timeouts' = timeouts + 1
             [] OTHER -> mailbox[dch].op = "none" /\ timeouts' = timeouts
     \/ Ev.a = "RRecv" /\ HeadIs(s2b, Ev.c, Ev.op) /\ RRecv(Ev.c)
        /\ (Ev.op \in {"ACK", "END"} => Head(s2b[Ev.c]).tok = Ev.tok)
        /\ (Ev.op = "RESYNC_REPLY" => Cardinality(Head(s2b[Ev.c]).toks) = Ev.tok)
     \/ Ev.a = "RDie" /\ RDie(Ev.c)
     \/ Ev.a = "RDrop" /\ RDrop(Ev.c)
     \/ Ev.a = "CnLook" /\ CnLook /\ cx'.gen = Ev.c /\ cx'.tok = Ev.tok
     \/ Ev.a = "CnSend" /\ CnSend /\ ((b2s' # b2s) <=> Ev.c # 0)
     \/ Ev.a = "BRestart" /\ BRestart
     \/ Ev.a = "SAccept" /\ SAccept(Ev.c)
     \/ Ev.a = "SRecv" /\ HeadIs(b2s, Ev.c, Ev.op) /\ SRecv(Ev.c)
     \/ Ev.a = "SHCheck" /\ SHCheck(Ev.c) /\ ((sCh'[Ev.c].hpc = "h_reg") <=> Ev.ok = 1)
     \/ Ev.a = "SHReg" /\ SHReg(Ev.c)
        /\ IF Ev.refused = 1 THEN sCh'[Ev.c].hpc = "idle" ELSE sess'[sCh[Ev.c].hs].tok = Ev.tok
     \/ Ev.a = "SHAck" /\ sCh[Ev.c].hs = Ev.s /\ SHAck(Ev.c) /\ (B(SrvSendOk(Ev.c)) = Ev.ok)
     \/ Ev.a = "SHSpawn" /\ sCh[Ev.c].hs = Ev.s /\ SHSpawn(Ev.c)
     \/ Ev.a = "SCancelLook" /\ sCh[Ev.c].cs = 0 /\ SCancel(Ev.c)
        /\ (Ev.tran >= 0 => sCh'[Ev.c].ctran # 0)
        /\ (Ev.found = 0 => sCh'[Ev.c].hpc = "idle")
     \/ Ev.a = "SCancelInt" /\ sCh[Ev.c].cs # 0 /\ sCh[Ev.c].ctran # 0 /\ SCancel(Ev.c)
     \/ Ev.a = "SResync" /\ SResync(Ev.c) /\ Cardinality(Snapshot) = Ev.n
     \/ Ev.a = "SEof" /\ SEof(Ev.c)
     \/ Ev.a = "SLogin" /\ SLogin(Ev.s) /\ sess'[Ev.s].tran = Ev.x
     \/ Ev.a = "SEnd" /\ SEnd(Ev.s)
     \/ Ev.a = "SClean" /\ SClean(Ev.s)
     \/ Ev.a = "SErase" /\ SErase(Ev.s)
     \/ Ev.a = "SPick" /\ SPick(Ev.s) /\ sess'[Ev.s].fch = Ev.c
     \/ Ev.a = "SSendEnd" /\ SSendEnd(Ev.s)
     \/ Ev.a = "SClose" /\ SClose(Ev.s)
     \/ Ev.a = "StopBegin" /\ StopBegin
     \/ Ev.a = "StopShutCh" /\ StopShutCh
     \/ Ev.a = "StopShutSess" /\ StopShutSess
     \/ Ev.a = "StopDrain" /\ StopDrain
     \/ Ev.a = "StopFinWait" /\ StopFinWait
     \/ Ev.a = "StopJoin" /\ StopJoin
     \/ Ev.a = "StopFree" /\ StopFree

\* a cancel whose pinned session had no transaction yet logs no interrupt
Hidden ==
  /\ \E c \in Conns : sCh[c].hpc = "c_int" /\ sCh[c].cs # 0 /\ sCh[c].ctran = 0 /\ SCancel(c)
  /\ UNCHANGED i

TSpec == TInit /\ [][Logged \/ Hidden]_TVars

TraceNotDone == i < Len(TraceLog)
=============================================================================
