------------------------- MODULE CscSessionsTrace -------------------------
(* Trace validation: is a run of the instrumented build (TLATRACE lines of the tracer session threads, p = the
   session, and of any other thread retiring a context, p = 0) a behavior of CscSessions? Each logged event is the
   action it names with the logged outcome; the client-half work inside a bracket (statements, enters, fetches,
   rollbacks, session calls) is not logged and may happen in between. Accepted iff TLC reaches i = Len(TraceLog). *)
EXTENDS CscSessions, CscSessionsTraceData, Sequences

CONSTANT TraceLog
VARIABLE i
TVars == <<vars, i>>

TInit == Init /\ i = 0
Ev == TraceLog[i + 1]
P == Ev.p
Logged ==
  /\ i < Len(TraceLog)
  /\ i' = i + 1
  /\ \/ Ev.a = "New" /\ TNew(P)
     \/ Ev.a = "Acquire" /\ P # 0 /\ (TAct(P) \/ TRAct(P))
     \/ Ev.a = "Acquire" /\ P = 0 /\ DAct /\ tgt[D] = Ev.c
     \/ Ev.a = "BootLock" /\ TBootLock(P)
     \/ Ev.a = "AreaCheck" /\ TAreaCheck(P) /\ (sawArea'[P] <=> Ev.saw = 1)
     \/ Ev.a = "AreaMake" /\ TAreaMake(P)
     \/ Ev.a = "Reg" /\ TReg(P)
     \/ Ev.a = "Adopt" /\ TAdopt(P)
     \/ Ev.a = "End1" /\ TEnd1(P)
     \/ Ev.a = "End2" /\ TEnd2(P) /\ (orphan'[P] <=> Ev.orph = 1)
     \/ Ev.a = "Unreg" /\ TUnreg(P)
     \/ Ev.a = "Deact" /\ TDeact(P) /\ (orphL'[P] <=> Ev.orph = 1)
     \/ Ev.a = "Unlock" /\ TUnlock(P)
     \/ Ev.a = "Del" /\ TDel(P) /\ (orphL[P] <=> Ev.del = 1)
     \/ Ev.a = "Scan" /\ DScan /\ tgt'[D] = Ev.c
     \/ Ev.a = "Uninit" /\ DUninit
     \/ Ev.a = "Tear" /\ P = 0 /\ DTear
     \/ Ev.a = "Tear" /\ P # 0 /\ TRTear(P)
     \/ Ev.a = "DDel" /\ DDel
     \/ Ev.a = "Erase" /\ DErase
Hidden ==
  /\ UNCHANGED i
  /\ \E s \in Sess : TStmt(s) \/ TEnter1(s) \/ TEnter2(s) \/ TRR(s) \/ TFetch(s) \/ TRollback(s) \/ TSessOp(s)
                     \/ TDoneWork(s) \/ TNotAdopted(s)
TSpec == TInit /\ [][Logged \/ Hidden]_TVars

TraceNotDone == i < Len(TraceLog)
=============================================================================
