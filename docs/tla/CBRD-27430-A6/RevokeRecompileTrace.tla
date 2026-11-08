------------------------- MODULE RevokeRecompileTrace -------------------------
(* Trace validation: is a run of the instrumented A6 build a behavior of RevokeRecompile? The revoker's events
   (p = 0) are its actions on the traced class; a grantee's events (p = its session) are its steps on that class,
   with the outcome the spec must reproduce: SAu ok (passed the check), SIns new (inserted, not found), SELook
   found, SECheck run. Not logged, so free to happen in between: a transaction or statement start, the next
   statement of a transaction (SBegin, SStmt, SNext) and the checks of other classes (SAuOther, SSkipOther); the
   grantee's statements on other classes are not modeled. Accepted iff TLC reaches i = Len(TraceLog). *)
EXTENDS RevokeRecompile, RevokeRecompileTraceData, Sequences

CONSTANT TraceLog
VARIABLE i
TVars == <<vars, i>>

TInit == Init /\ i = 0
Ev == TraceLog[i + 1]
P == Ev.p
Logged ==
  /\ i < Len(TraceLog)
  /\ i' = i + 1
  /\ \/ Ev.a = "RUpdate" /\ RUpdate
     \/ Ev.a = "RTouch" /\ RTouch
     \/ Ev.a = "RCommit" /\ RCommit
     \/ Ev.a = "RCleanup" /\ RCleanup
     \/ Ev.a = "RUnlock" /\ RUnlock
     \/ Ev.a = "SPLock" /\ SPLock(P)
     \/ Ev.a = "SAu" /\ SAu(P) /\ ((pc'[P] = "ins") <=> (Ev.ok = 1))
     \/ Ev.a = "SIns" /\ SIns(P) /\ ((live = 0) <=> (Ev.new = 1))
     \/ Ev.a = "SELook" /\ SELook(P) /\ ((pc'[P] = "elock") <=> (Ev.found = 1))
     \/ Ev.a = "SELock" /\ SELock(P)
     \/ Ev.a = "SECheck" /\ SECheck(P) /\ ((pc'[P] = "end") <=> (Ev.run = 1))
     \/ Ev.a = "SCommit" /\ SCommit(P)
     \/ Ev.a = "DRevoke" /\ DRevoke
     \/ Ev.a = "DFree" /\ DFree
Hidden ==
  /\ UNCHANGED i
  /\ \E s \in Sess : SBegin(s) \/ SStmt(s) \/ SAuOther(s) \/ SSkipOther(s) \/ SNext(s)
TSpec == TInit /\ [][Logged \/ Hidden]_TVars

TraceNotDone == i < Len(TraceLog)
=============================================================================
