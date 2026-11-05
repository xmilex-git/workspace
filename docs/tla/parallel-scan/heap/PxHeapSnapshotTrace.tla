------------------------ MODULE PxHeapSnapshotTrace ------------------------
(* Trace validation of PxHeapSnapshot against a run of the instrumented probe
   build (develop e98bdd885 + TLATRACE lines, optdebug): the leader's open
   (scan_open_parallel_heap_scan, with the transaction's snapshot validity at
   that moment) and the build of the snapshot by a parallel-scan worker
   (logtb_get_mvcc_snapshot). Every other step is hidden. *)
EXTENDS PxHeapSnapshot, PxHeapSnapshotTraceData, Sequences

CONSTANT TraceLog
VARIABLE i
TVars == <<vars, i>>

TInit == Init /\ i = 0
Ev == TraceLog[i + 1]
Logged ==
  /\ i < Len(TraceLog)
  /\ i' = i + 1
  /\ \/ Ev.a = "L_open" /\ Open /\ ((snap = 0) <=> (Ev.snapshot_valid = 0))
     \/ Ev.a = "snapshot_built" /\ Ev.p = "px_worker" /\ snap = 0 /\ \E w \in Workers : Start(w)
Hidden ==
  /\ UNCHANGED i
  /\ \/ TakeEarlySnapshot \/ Finish \/ VacuumIdle
     \/ \E w \in Workers : snap > 0 /\ Start(w)          \* later workers find the snapshot built
     \/ \E w \in Workers, p \in Pages : ReadPage(w, p)
     \/ \E r \in Rows, p \in Pages : Insert(r, p)
     \/ \E r \in Rows : Delete(r)
     \/ \E p \in Pages : VacuumRows(p) \/ VacuumPage(p)
TSpec == TInit /\ [][Logged \/ Hidden]_TVars

TraceNotDone == i < Len(TraceLog)
=============================================================================
