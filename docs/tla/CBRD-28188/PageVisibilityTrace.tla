------------------------ MODULE PageVisibilityTrace ------------------------
(* Trace validation of PageVisibility's reader step against an instrumented build (TLATRACE in
   heap_page_collect_visible ()). A ScanCall event is one call: it sets the page's max_mvccid, the
   snapshot's lowest active MVCCID and the scanner's own MVCCID as the call read them, and the page
   judgment Passed () must agree with the logged one. A Decide event is one record of that call: its
   header fields set the record, its in-snapshot bits the snapshot's view of its ids; the model's
   FastDecide () and DevDecide () must give the logged answers and the logged path (word row, word
   delete, header decode), and on a data page every MVCCID of the record is at most the page's
   max_mvccid (IdBound, the claim's premise). Writer steps are not logged: they reach the trace only
   through the record contents (MAP.md). Accepted iff TLC reaches i = Len(TraceLog). *)
EXTENDS PageVisibility, PageVisibilityTraceData, Sequences

CONSTANT TraceLog
VARIABLES i, cur
TVars == <<vars, i, cur>>

TInit == Init /\ i = 0 /\ cur = HdrPage
Ev == TraceLog[i + 1]
TheData == CHOOSE d \in DataPages : TRUE
FirstId == 4  \* MVCCID_FIRST; MVCCID_ALL_VISIBLE (3) is no transaction's

(* the repid a record carries, in the model's terms: 1 = word_want (every repid when the scan checks none), *)
(* 3 = another one the scan decodes, 2 = one it does not                                                  *)
RepOf(e) == IF e.nrep = 0 \/ e.rep = e.want THEN 1 ELSE IF e.inrep = 1 THEN 3 ELSE 2

TCall(e) ==
  LET p == IF e.hdr = 1 THEN HdrPage ELSE TheData
      sn == [has |-> TRUE, low |-> e.low, done |-> {}]
      ps == PassedIn(p, e.max, sn)
  IN
  /\ ps = (e.pass = 1)
  /\ cur' = p
  /\ maxm' = [maxm EXCEPT ![p] = e.max]
  /\ snap' = sn
  /\ tid' = [tid EXCEPT ![R] = e.own]
  /\ rec' = [rec EXCEPT ![p][1] = Empty]
  /\ UNCHANGED <<owner, before, st, nextId, done, cmt, crashes>>

TDecide(e) ==
  LET r == [in |-> TRUE, rel |-> e.rel = 1, ins |-> e.ins, del |-> e.del, prev |-> e.prev = 1, rep |-> RepOf(e)]
      completed == {x \in {e.ins, e.del} : x > 0 /\ x >= snap.low /\ ((x = e.ins /\ e.insnap = 0) \/ (x = e.del /\ e.delsnap = 0))}
      sn == [snap EXCEPT !.done = @ \cup completed]
      own == tid[R]
      ps == PassedIn(cur, maxm[cur], sn)
  IN
  /\ (e.ins > 0 => (InSnapIn(sn, e.ins) = (e.insnap = 1)))
  /\ (e.del > 0 => (InSnapIn(sn, e.del) = (e.delsnap = 1)))
  /\ FastDecideIn(ps, sn, own, r, 1) = e.fast
  /\ DevDecideIn(sn, own, r) = e.dev
  /\ (e.path = "row") = (~r.rel /\ WordRowIn(ps, r, 1))
  /\ (e.path = "del") = (~r.rel /\ ~WordRowIn(ps, r, 1) /\ WordDelIn(ps, r))
  /\ (cur \in DataPages => \A x \in {e.ins, e.del} : x >= FirstId => x <= maxm[cur])
  /\ rec' = [rec EXCEPT ![cur][1] = r]
  /\ snap' = sn
  /\ UNCHANGED <<owner, before, maxm, st, tid, nextId, done, cmt, crashes, cur>>

Logged ==
  /\ i < Len(TraceLog)
  /\ i' = i + 1
  /\ IF Ev.a = "ScanCall" THEN TCall(Ev) ELSE Ev.a = "Decide" /\ TDecide(Ev)
TSpec == TInit /\ [][Logged]_TVars

TraceNotDone == i < Len(TraceLog)
=============================================================================
