-------------------------- MODULE OvfDirChainTrace --------------------------
(* PR 8432 review, r2 (head 945478c64).  Trace validation of the crash-retry path: is a recorded run of the
   instrumented head build (h2 repro: the server stops right after the swap's first half; after the restart vacuum
   retries the removal) a behavior of OvfDirChain?  The key is set up from its KeyDump before the swap; each logged
   event must be the step it names with the logged outcome: the swap of the logged objects on the first page, the
   crash, the retry's directory miss at the logged routed page, the walk finding the object on the logged page; the
   key must then equal its KeyDump after the retry.  No step is hidden: no other writer touched the key in between
   (the repro's load goes to another table). *)
EXTENDS OvfDirChain, OvfDirChainTraceData

CONSTANT Log
VARIABLE i
TVars == <<vars, i>>

TObj(r) == <<r, 1>>
TVis == UNION {Range(TPages[k]) : k \in DOMAIN TPages}

TInit ==
  /\ chain = TChain
  /\ data = [p \in Pg |-> IF p <= Len(TPages) THEN TPages[p] ELSE <<>>]
  /\ hdr = [p \in Pg |-> IF p <= Len(TPages) /\ Len(TPages) > 1 THEN "H" ELSE "N"]
  /\ dir = TDir
  /\ leaf = TLeaf
  /\ live = TLeaf \cup TVis
  /\ stale = {} /\ pend = <<>> /\ bad = {} /\ seen = {}
  /\ i = 0

Ev == Log[i + 1]

Logged ==
  /\ i < Len(Log)
  /\ i' = i + 1
  /\ \/ /\ Ev.a = "Swap"
        /\ TObj(Ev.deleted) \in leaf
        /\ chain[Ev.page] = chain[1]
        /\ Last(data[chain[1]]) = TObj(Ev.moved)
        /\ Remove(TObj(Ev.deleted))
     \/ /\ Ev.a = "CrashAfterSwap" /\ CrashRecover
     \/ /\ Ev.a = "FindMiss"
        /\ Idle /\ TObj(Ev.o) \in stale
        /\ Find(TObj(Ev.o))[1] = NoPg
        /\ Routed(TObj(Ev.o)) = chain[Ev.routed]
        /\ UNCHANGED vars
     \/ /\ Ev.a = "FindWalk" /\ Ev.found = 1
        /\ FindRemove(TObj(Ev.o))[1] = chain[Ev.page]
        /\ Retry(TObj(Ev.o))
        /\ (i' = Len(Log) => (leaf' = TLeafAfter /\ Flat' = TFlatAfter))

TSpec == TInit /\ [][Logged]_TVars
TraceNotDone == i < Len(Log)
=============================================================================
