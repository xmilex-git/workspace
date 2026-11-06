---------------------- MODULE PxHeapRcSnapshotTrace ----------------------
(* Trace validation of PxHeapRcSnapshot against runs of the probe builds
   (traces/): develop 953e83256 and the fix 63a00a185, each with the same
   TLATRACE lines and the env-gated delay after open (CUBRID_TLA_PX_OPEN_DELAY_MS),
   optdebug. Two events are logged: snapshot_built (logtb_get_mvcc_snapshot
   built the transaction's snapshot, by any thread of the statement) and L_open
   (scan_open_parallel_heap_scan returned with the bitmap collected, carrying
   whether the snapshot existed then). Every other step is hidden. *)
EXTENDS PxHeapRcSnapshot, PxHeapRcSnapshotTraceData, Sequences

CONSTANT TraceLog
VARIABLE i
TVars == <<vars, i>>

TInit == Init /\ i = 0
Ev == TraceLog[i + 1]
\* a step that builds the snapshot (it logs snapshot_built) and one that finds it built (silent)
Builds(A) == A /\ snap = 0 /\ snap' # 0
Silent(A) == A /\ snap' = snap

Logged ==
  /\ i < Len(TraceLog)
  /\ i' = i + 1
  /\ \/ Ev.a = "snapshot_built"
        /\ \/ Builds(QueryStart) \/ Builds(OtherBuild)
           \/ \E s \in Scans : Builds(LeaderSnap(s)) \/ \E w \in Workers : Builds(Start(s, w))
     \/ Ev.a = "L_open" /\ \E s \in Scans : Collect(s) /\ ((snap > 0) <=> (Ev.snapshot_valid = 1))
Hidden ==
  /\ UNCHANGED i
  /\ \/ Silent(QueryStart) \/ Silent(OtherBuild)
     \/ \E s \in Scans : \/ Silent(LeaderSnap(s)) \/ Finish(s)
                         \/ \E w \in Workers : Silent(Start(s, w)) \/ \E p \in PIdx : ReadPage(s, w, p)
     \/ \E r \in Rows, p \in PIdx : Insert(r, p)
     \/ \E r \in Rows : Delete(r)
     \/ \E pg \in Pages : VacuumRows(pg) \/ VacuumPage(pg)
TSpec == TInit /\ [][Logged \/ Hidden]_TVars

TraceNotDone == i < Len(TraceLog)
=============================================================================
