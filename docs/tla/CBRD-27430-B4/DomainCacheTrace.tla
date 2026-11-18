--------------------------- MODULE DomainCacheTrace ---------------------------
(* Trace validation of DomainCache. events_domain.py orders a server's TLATRACE lines and renames them (MAP.md
   "Trace validation"): a client context is a slot from its login to the release of its lists, a class is its
   OID, a MOP's address a small number. Mop is written by the converter before a context's first resolve of a
   class (ws_mop itself has no line). *)
EXTENDS DomainCache, DomainCacheTraceData, Sequences

CONSTANTS TraceLog
VARIABLE i
TVars == <<vars, i>>

TInit == Init /\ i = 0
Ev == TraceLog[i + 1]
B(x) == IF x THEN 1 ELSE 0

Logged ==
  /\ i < Len(TraceLog)
  /\ i' = i + 1
  /\ \/ Ev.a = "Begin" /\ Begin(Ev.s)
     \/ Ev.a = "Mop" /\ Mop(Ev.s, Ev.c, Ev.addr)
     \/ Ev.a = "ResolveSess" /\ B(sl[L(Ev.s)][Ev.c] = 0) = Ev.ins /\ ResolveSess(Ev.s, Ev.c)
     \/ Ev.a = "ResolveProc" /\ B(~\E n \in pm : n.a = maddr[Ev.s][Ev.c]) = Ev.ins /\ ResolveProc(Ev.s, Ev.c)
     \/ Ev.a = "FindOid" /\ (Ev.mops > 0 => pm # {}) /\ FindOid(Ev.t, Ev.c)
     \/ Ev.a = "Tran" /\ Tran(Ev.s, Ev.x)
     \/ Ev.a = "Yield" /\ Yield(Ev.s)
     \/ Ev.a = "Resume" /\ Resume(Ev.s)
     \/ Ev.a = "Expire" /\ Expire(Ev.s)
     \/ Ev.a = "EndRollback" /\ EndRollback(Ev.s)
     \/ Ev.a = "WsFinal" /\ WsFinal(Ev.s)
     \/ Ev.a = "FreeLists" /\ FreeLists(Ev.s)

TSpec == TInit /\ [][Logged]_TVars

TraceNotDone == i < Len(TraceLog)
\* the run that restores the old routing ends with a freed MOP read
TraceNotUaf == ~(i = Len(TraceLog) /\ uaf)
=============================================================================
