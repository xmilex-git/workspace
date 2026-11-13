------------------------- MODULE OvfScanResumeTrace -------------------------
(* PR 8432 review copy.  Trace validation: is a recorded run of the instrumented build a behavior of
   OvfScanResume?  The run's key is set up from its KeyDump (leaf objects,
   chain pages, directory), then each logged event must be the step it names
   with the logged outcome: the scan's first iteration stopping before the
   logged page at the logged anchor, each COMPACT pull of the logged pair and
   count, the vacuum swap of the logged objects, the resume at the logged page
   and offset, and the measured result.  Accepted iff TLC reaches
   i = Len(Log).  No step is hidden: the run had no other writer on the key. *)
EXTENDS OvfScanResume, OvfScanResumeTraceData

CONSTANT Log
VARIABLE i
TVars == <<allvars, i>>

TObj(r) == <<r, 1>>
TVis == UNION {Range(TPages[k]) : k \in DOMAIN TPages}

TInit ==
  /\ chain = TChain
  /\ data = [p \in Pg |-> IF p <= Len(TPages) THEN TPages[p] ELSE <<>>]
  /\ hdr = [p \in Pg |-> IF p <= Len(TPages) THEN "H" ELSE "N"]
  /\ dir = TDir
  /\ leaf = TLeaf
  /\ live = TLeaf \cup TVis
  /\ stale = {} /\ pend = <<>> /\ bad = {} /\ seen = {}
  /\ spc = "idle" /\ vis = {} /\ ret = {} /\ dup = FALSE /\ anchor = 0 /\ ovpid = NoPg
  /\ i = 0

Ev == Log[i + 1]

Logged ==
  /\ i < Len(Log)
  /\ i' = i + 1
  /\ \/ /\ Ev.a = "ScanStop"
        /\ spc = "idle" /\ Idle
        /\ vis' = TVis
        /\ KeyIter(TVis)
        /\ spc' = "susp"
        /\ anchor' = Ev.anchor
        /\ ret' = (leaf \cap TVis) \cup (Range(Span(1, 1, Ev.before - 1)) \cap TVis)
        /\ UNCHANGED vars
     \/ /\ Ev.a = "Pull"
        /\ Compact /\ Idle /\ hdr[chain[1]] = "H"
        /\ Ev.left \in Range(chain)
        /\ LET ci == IndexOf(chain, Ev.left) IN
           /\ ci < Len(chain)
           /\ chain[ci + 1] = Ev.right
           /\ data[Ev.right][1] = TObj(Ev.first)
           /\ data[Ev.right][Ev.n] = TObj(Ev.last)
           /\ (Ev.merge = 1) = (Ev.n = Len(data[Ev.right]))
           /\ PullAt(ci, Ev.n)
        /\ UNCHANGED svars
     \/ /\ Ev.a = "Swap"
        /\ TObj(Ev.deleted) \in leaf
        /\ Remove(TObj(Ev.deleted))
        /\ leaf' = {TObj(Ev.moved)}
        /\ UNCHANGED svars
     \/ /\ Ev.a = "Resume"
        /\ spc = "susp"
        /\ anchor = Ev.anchor
        /\ Ev.page \in Range(chain)
        /\ ResumePoint = <<IndexOf(chain, Ev.page), Ev.k>>
        /\ SResume
     \/ /\ Ev.a = "Result"
        /\ spc = "done"
        /\ Cardinality(vis \ ret) = Ev.lost
        /\ dup = (Ev.dups > 0)
        /\ UNCHANGED allvars

TSpec == TInit /\ [][Logged]_TVars

TraceNotDone == i < Len(Log)
=============================================================================
