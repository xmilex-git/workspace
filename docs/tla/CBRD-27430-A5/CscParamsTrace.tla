-------------------------- MODULE CscParamsTrace --------------------------
(* Trace validation: is a run of the instrumented A5 build a behavior of CscParams? The lifecycle events are A4's
   (CscSessionsTrace) with A5's hooks; a Set event is TSet of the logged parameter class with the logged outcome
   (ok = 0: refused). Not logged, so free to happen in between: the client half's reads, compiles, SHOWs and the
   client state it leaves (TRead, TCompile, TShow, TAlloc), and the lifecycle steps with no code point of their own
   (TDoneWork, TNotAdopted) or no code left under ServerInit (TBootLock, TAreaCheck, TAreaMake). Accepted iff TLC
   reaches i = Len(TraceLog). *)
EXTENDS CscParams, CscParamsTraceData, Sequences

CONSTANT TraceLog
VARIABLE i
TVars == <<all, i>>

TInit == Init5 /\ i = 0
Ev == TraceLog[i + 1]
P == Ev.p
Life5(Act) == Act /\ Hook
Logged ==
  /\ i < Len(TraceLog)
  /\ i' = i + 1
  /\ \/ Ev.a = "New" /\ Life5(TNew(P))
     \/ Ev.a = "Acquire" /\ P # 0 /\ Life5(TAct(P) \/ TRAct(P))
     \/ Ev.a = "Acquire" /\ P = 0 /\ Life5(DAct) /\ tgt[D] = Ev.c
     \/ Ev.a = "Reg" /\ Life5(TReg(P))
     \/ Ev.a = "Adopt" /\ Life5(TAdopt(P))
     \/ Ev.a = "End1" /\ Life5(TEnd1(P))
     \/ Ev.a = "End2" /\ Life5(TEnd2(P)) /\ (orphan'[P] <=> Ev.orph = 1)
     \/ Ev.a = "Unreg" /\ Life5(TUnreg(P))
     \/ Ev.a = "Deact" /\ Life5(TDeact(P)) /\ (orphL'[P] <=> Ev.orph = 1)
     \/ Ev.a = "Unlock" /\ Life5(TUnlock(P))
     \/ Ev.a = "Del" /\ Life5(TDel(P)) /\ (orphL[P] <=> Ev.del = 1)
     \/ Ev.a = "Scan" /\ Life5(DScan) /\ tgt'[D] = Ev.c
     \/ Ev.a = "Uninit" /\ Life5(DUninit)
     \/ Ev.a = "Tear" /\ P = 0 /\ Life5(DTear)
     \/ Ev.a = "Tear" /\ P # 0 /\ Life5(TRTear(P))
     \/ Ev.a = "DDel" /\ Life5(DDel)
     \/ Ev.a = "Erase" /\ Life5(DErase)
     \/ Ev.a = "Set" /\ TSet(P, Ev.cls) /\ ((Ev.ok = 0) <=> (Ev.cls = "sv" /\ ~IsDba(P)))
Hidden ==
  /\ UNCHANGED i
  /\ \E s \in Sess :
       \/ TRead(s)
       \/ TCompile(s) \/ TShow(s) \/ TAlloc(s)
       \/ Life5(TDoneWork(s) \/ TNotAdopted(s) \/ TBootLock(s) \/ TAreaCheck(s) \/ TAreaMake(s))
TSpec == TInit /\ [][Logged \/ Hidden]_TVars

TraceNotDone == i < Len(TraceLog)
=============================================================================
