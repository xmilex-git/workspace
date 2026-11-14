--------------------------- MODULE CoveredVisitTrace ---------------------------
(* Trace validation of CoveredVisit: one covered index scan of an instrumented build, from its first batch request
   to its end (Open: the first batch request with the attached visit; Fix: a leaf is
   fixed after a start, a resume or a walk that gave its latch up; Sel: one selected object, visited or written
   to the covering list, with the key record it belongs to; Ret: btree_range_scan returns with the batch size;
   Restart: the walk gave its leaf latch up between two keys; Dlv: a row read back from the covering list; Again:
   the next batch request or the scan's end; End: scan_end_scan with the statement's error state).
   foreign = 1 marks an event before which another scan of the statement logged an event since this scan's
   previous one: something the block ran for a row read an index or a heap. Every action of the model is logged,
   so no step is hidden. *)
EXTENDS CoveredVisit, CoveredVisitTraceData, Sequences

CONSTANTS TraceLog
VARIABLE i
TVars == <<vars, i>>

TInit == Init /\ i = 0

Ev == TraceLog[i + 1]

Logged ==
  /\ i < Len(TraceLog)
  /\ i' = i + 1
  \* an event of another scan logged since this scan's previous event: the block ran a scan for the row
  /\ (Ev.foreign = 1) => Subquery
  /\ \/ /\ Ev.a = "Open"
        /\ Open
        /\ visit' = (Ev.visit = 1)
     \/ /\ Ev.a = "Fix"
        /\ Fix
     \/ /\ Ev.a = "Sel"
        /\ visit = (Ev.visit = 1)
        /\ (Ev.ks = 1) <=> ((nextObj - 1) % PerKey = 0)
        /\ Select
        /\ err' = (Ev.err = 1)
     \/ /\ Ev.a = "Ret"
        /\ batch = Ev.n
        /\ err = (Ev.err = 1)
        /\ (Ev.end = 1) <=> (nextObj > N)
        /\ Return
     \/ /\ Ev.a = "Restart"
        /\ Restart
     \/ /\ Ev.a = "Dlv"
        /\ Deliver
     \/ /\ Ev.a = "Again"
        /\ Again
        /\ (phase' = "end") <=> (Ev.end = 1)
     \/ /\ Ev.a = "End"
        \* the last event of a scan, once: the scan is over (after an error of a delivered row the row loop leaves
        \* without asking for another batch)
        /\ i + 1 = Len(TraceLog)
        /\ err = (Ev.err = 1)
        /\ IF phase = "deliver" THEN Again /\ phase' = "end" ELSE phase = "end" /\ UNCHANGED vars

TSpec == TInit /\ [][Logged]_TVars

TraceNotDone == i < Len(TraceLog)
=============================================================================
