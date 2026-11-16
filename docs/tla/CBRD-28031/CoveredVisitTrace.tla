--------------------------- MODULE CoveredVisitTrace ---------------------------
(* Trace validation of CoveredVisit: one covered index scan of an instrumented build, from its first batch request
   to its end (Open: the first batch request with the attached visit; Fix: a leaf is
   fixed after a start, a resume or a walk that gave its latch up; Sel: one selected object, visited or written
   to the covering list, with the key record it belongs to; Ret: btree_range_scan returns with the batch size;
   Restart: the walk gave its leaf latch up between two keys; Dlv: a row read back from the covering list; Again:
   the next batch request or the scan's end; End: scan_end_scan with the statement's error state; Put: memoize_put
   returned for a row of this scan, with whether the scan node still has its storage. The visit's Put is logged
   inside the visit, before the Sel of its object; a delivered row's Put after its Dlv).
   foreign = 1 marks an event before which another scan of the statement logged an event since this scan's
   previous one: something the block ran for a row read an index or a heap. Every action of the model is logged,
   so no step is hidden. *)
EXTENDS CoveredVisit, CoveredVisitTraceData, Sequences

CONSTANTS TraceLog
VARIABLES i,
          bal,   \* 1: a Put is logged, its object's Sel not yet; -1: a delivered row was stored, its Put not logged yet
          pon    \* the pending Put's storage state
TVars == <<vars, i, bal, pon>>

TInit == Init /\ i = 0 /\ bal = 0 /\ pon = 0

Ev == TraceLog[i + 1]

There(m) == m \in {"on", "stopped"}

Logged ==
  /\ i < Len(TraceLog)
  /\ i' = i + 1
  \* an event of another scan logged since this scan's previous event: the block ran a scan for the row
  /\ (Ev.foreign = 1) => Subquery
  /\ \/ /\ Ev.a = "Open"
        /\ bal = 0
        /\ Open
        /\ visit' = (Ev.visit = 1)
        /\ UNCHANGED <<bal, pon>>
     \/ /\ Ev.a = "Fix"
        /\ bal = 0
        /\ Fix
        /\ UNCHANGED <<bal, pon>>
     \/ /\ Ev.a = "Put"
        /\ UNCHANGED vars
        /\ IF bal = -1
             THEN (Ev.on = 1) = There(memo) /\ bal' = 0 /\ pon' = 0
             ELSE bal = 0 /\ visit /\ phase = "walk" /\ latched /\ bal' = 1 /\ pon' = Ev.on
     \/ /\ Ev.a = "Sel"
        /\ visit = (Ev.visit = 1)
        /\ (Ev.ks = 1) <=> ((nextObj - 1) % PerKey = 0)
        /\ Select
        /\ err' = (Ev.err = 1)
        \* a visited object's row was stored exactly when its Put was logged; a listed key is stored when delivered
        /\ IF visit THEN puts' - puts = bal /\ (bal = 1 => (pon = 1) = There(memo')) ELSE bal = 0
        /\ bal' = 0
        /\ pon' = 0
     \/ /\ Ev.a = "Ret"
        /\ batch = Ev.n
        /\ err = (Ev.err = 1)
        /\ (Ev.end = 1) <=> (nextObj > N)
        /\ bal = 0
        /\ Return
        /\ UNCHANGED <<bal, pon>>
     \/ /\ Ev.a = "Restart"
        /\ bal = 0
        /\ Restart
        /\ UNCHANGED <<bal, pon>>
     \/ /\ Ev.a = "Dlv"
        /\ bal = 0
        /\ Deliver
        /\ bal' = puts - puts'
        /\ pon' = 0
     \/ /\ Ev.a = "Again"
        /\ bal = 0
        /\ Again
        /\ (phase' = "end") <=> (Ev.end = 1)
        /\ UNCHANGED <<bal, pon>>
     \/ /\ Ev.a = "End"
        \* the last event of a scan, once: the scan is over (after an error of a delivered row the row loop leaves
        \* without asking for another batch)
        /\ i + 1 = Len(TraceLog)
        /\ err = (Ev.err = 1)
        /\ bal = 0
        /\ IF phase = "deliver" THEN Again /\ phase' = "end" ELSE phase = "end" /\ UNCHANGED vars
        /\ UNCHANGED <<bal, pon>>

TSpec == TInit /\ [][Logged]_TVars

TraceNotDone == i < Len(TraceLog)
=============================================================================
