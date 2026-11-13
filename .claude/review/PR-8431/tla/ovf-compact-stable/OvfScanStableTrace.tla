------------------------ MODULE OvfScanStableTrace ------------------------
(* Trace validation: is a recorded run of the instrumented PR #8431 head a
   behavior of OvfScanStable?  The key is set up from its KeyDump; the leaf
   objects carry the run's MVCC state (TLeafSt), the chain objects are
   committed and undeleted.  Each logged event must be the step it names with
   the logged outcome: the scan's stop, each COMPACT leaf check with its
   answer (CompactCheck), each pull, the vacuum swap, the resume, the result.
   The repro's DELETE of the leaf row is not logged: the Swap step takes it
   as committed before the removal, and the removal must still be one the
   scan's snapshot allows.  Accepted iff TLC reaches i = Len(Log). *)
EXTENDS OvfScanStable, OvfScanStableTraceData

\* one run: its key setup and log, substituted in the cfg from OvfScanStableTraceData
CONSTANTS Log, TLeaf, TLeafSt, TChain, TPages, TDir
VARIABLE i
TVars == <<gall, i>>

TObj(r) == <<r, 1>>
TChainObjs == UNION {Range(TPages[k]) : k \in DOMAIN TPages}
TVis == TChainObjs \cup (IF TLeafSt = "stable" THEN TLeaf ELSE {})

TInit ==
  /\ chain = TChain
  /\ data = [p \in Pg |-> IF p <= Len(TPages) THEN TPages[p] ELSE <<>>]
  /\ hdr = [p \in Pg |-> IF p <= Len(TPages) THEN "H" ELSE "N"]
  /\ dir = TDir
  /\ leaf = TLeaf
  /\ live = TLeaf \cup TChainObjs
  /\ stale = {} /\ pend = <<>> /\ bad = {} /\ seen = {}
  /\ spc = "idle" /\ vis = {} /\ ret = {} /\ dup = FALSE /\ anchor = 0 /\ ovpid = NoPg
  /\ st = [o \in Obj |-> IF o \in TLeaf THEN TLeafSt ELSE IF o \in TChainObjs THEN "stable" ELSE "none"]
  /\ prot = {} /\ cok = FALSE /\ pulled = FALSE /\ lostg = FALSE
  /\ i = 0

Ev == Log[i + 1]

Logged ==
  /\ i < Len(Log)
  /\ i' = i + 1
  /\ \/ /\ Ev.a = "ScanStop"
        /\ spc = "idle" /\ Idle
        /\ VisNow = TVis
        /\ vis' = TVis
        /\ KeyIter(TVis)
        /\ spc' = "susp"
        /\ anchor' = Ev.anchor
        /\ ret' = (leaf \cap TVis) \cup (Range(Span(1, 1, Ev.before - 1)) \cap TVis)
        /\ prot' = {o \in live : st[o] = "stable"}
        /\ pulled' = FALSE
        /\ UNCHANGED <<vars, st, cok, lostg>>
     \/ /\ Ev.a = "CompactCheck"
        /\ Compact /\ Idle
        /\ (Ev.stable = 1) = Guard
        /\ IF Ev.stable = 0
           THEN /\ seen' = seen \cup {"skip"}
                /\ UNCHANGED <<chain, data, hdr, dir, leaf, live, stale, pend, bad, svars, gvars>>
           ELSE UNCHANGED gall
     \/ /\ Ev.a = "Pull"
        /\ Compact /\ Idle /\ hdr[chain[1]] = "H"
        /\ Guard
        /\ Ev.left \in Range(chain)
        /\ LET ci == IndexOf(chain, Ev.left) IN
           /\ ci < Len(chain)
           /\ chain[ci + 1] = Ev.right
           /\ data[Ev.right][1] = TObj(Ev.first)
           /\ data[Ev.right][Ev.n] = TObj(Ev.last)
           /\ (Ev.merge = 1) = (Ev.n = Len(data[Ev.right]))
           /\ PullAt(ci, Ev.n)
        /\ pulled' = (pulled \/ Susp)
        /\ UNCHANGED <<svars, st, prot, cok, lostg>>
     \/ /\ Ev.a = "Swap"
        /\ LET o == TObj(Ev.deleted) IN
           /\ o \in leaf
           /\ st[o] \in {"stable", "delu", "delc"}   \* the unlogged DELETE commits before vacuum runs
           /\ ~Protected(o)
           /\ Remove(o)
           /\ leaf' = {TObj(Ev.moved)}
           /\ st' = [st EXCEPT ![o] = "none"]
           /\ lostg' = (lostg \/ LostBySwap(o))
        /\ UNCHANGED <<svars, prot, cok, pulled>>
     \/ /\ Ev.a = "Resume"
        /\ spc = "susp"
        /\ anchor = Ev.anchor
        /\ Ev.page \in Range(chain)
        /\ ResumePoint = <<IndexOf(chain, Ev.page), Ev.k>>
        /\ SResumeS
     \/ /\ Ev.a = "Result"
        /\ spc = "done"
        /\ Cardinality(vis \ ret) = Ev.lost
        /\ dup = (Ev.dups > 0)
        /\ ~lostg
        /\ UNCHANGED gall

TSpec == TInit /\ [][Logged]_TVars

TraceNotDone == i < Len(Log)
=============================================================================
