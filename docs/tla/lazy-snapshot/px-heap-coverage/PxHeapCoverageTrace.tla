------------------------- MODULE PxHeapCoverageTrace -------------------------
(* Trace validation of PxHeapCoverage against a run of the probe build
   (traces/: develop 2d928e34b + traces/probe.diff, release) of the H2 scenario:
   a REPEATABLE READ parallel heap scan collects its bitmap, its workers wait
   (CUBRID_TLA_PX_WORKER_DELAY_MS) while vacuum deallocates pages emptied by a
   delete committed before the snapshot and the heap file reuses one of them as
   a file table page. The run is projected onto three bitmap pages (PageIds):
   the page reused as a table page, a page deallocated and skipped, a page
   whose row stays. Logged: Collect (init_on_main after
   file_get_all_data_sectors), Dealloc (file_perm_dealloc of a heap page), Alloc
   (file_perm_alloc, kind user or table), Fix (the worker's pgbuf_ordered_fix,
   with the fixed page's type: 2 heap, 1 file table, -1 not fixed). *)
EXTENDS PxHeapCoverage, PxHeapCoverageTraceData, Integers, Sequences

CONSTANTS TraceLog, PageIds
VARIABLE i
TVars == <<vars, i>>

\* the projection of release-run8: the reused page, the skipped page, the page that keeps its row
PageIdsR8 == <<4867, 7747, 16768>>
PageIdsF1 == <<16451, 16515, 18861>>   \* the fix build's run 1: reused, deallocated, heap

TInit == Init /\ i = 0
Ev == TraceLog[i + 1]
PageOf(x) == CHOOSE k \in 1..Len(PageIds) : PageIds[k] = x
PType(s) == IF s = "heap" THEN 2 ELSE IF s = "ftab" THEN 1 ELSE -1
\* the type the worker logs: with the fix a reused page comes back unfixed, as a deallocated one
FixType(s) == IF PtypeCheck /\ s = "ftab" THEN -1 ELSE PType(s)

Logged ==
  /\ i < Len(TraceLog)
  /\ i' = i + 1
  /\ \/ Ev.a = "Collect" /\ Collect /\ ((snap > 0) <=> Ev.snap = 1)
     \/ Ev.a = "Dealloc" /\ Ev.kind = "user" /\ VacuumPage(PageOf(Ev.page))
     \/ Ev.a = "Alloc" /\ Ev.kind = "table" /\ FtabAlloc(PageOf(Ev.page))
     \/ Ev.a = "Alloc" /\ Ev.kind = "user" /\ \E r \in Rows : Insert(r, PageOf(Ev.page)) /\ state[PageOf(Ev.page)] = "free"
     \/ Ev.a = "Fix" /\ \E w \in Workers : ReadPage(w, PageOf(Ev.page)) /\ FixType(state[PageOf(Ev.page)]) = Ev.ptype
     \* the fix: pgbuf_ordered_fix found the bitmap page reused (logged before the worker's Fix of it)
     \/ Ev.a = "Reused" /\ PtypeCheck /\ UNCHANGED vars /\ state[PageOf(Ev.vpid)] = "ftab"

Hidden ==
  /\ UNCHANGED i
  /\ \/ QueryStart \/ LeaderSnap \/ Finish
     \/ \E w \in Workers : Start(w)
     \/ \E r \in Rows : Delete(r)
     \/ \E p \in Pg : VacuumRows(p)
TSpec == TInit /\ [][Logged \/ Hidden]_TVars

TraceNotDone == i < Len(TraceLog)
=============================================================================
