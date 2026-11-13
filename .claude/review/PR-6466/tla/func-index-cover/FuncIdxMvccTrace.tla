---------------------------- MODULE FuncIdxMvccTrace ----------------------------
(* Trace validation: is a CS-mode run of the instrumented head build (f1f4f21ea + TLATRACE in btree_update,
   btree_range_scan, btree_select_visible_object_for_range_scan, btree_vacuum_object, xtran_server_commit,
   xtran_server_abort) a behavior of FuncIdxMvcc? Events of the test index only (root filter at extraction).
   A Vis event is one Scan step at the entry its key value names; the scan steps over a position that has
   no entry without logging. Begin records the updater's MVCCID, so a Vacuum event names the entry whose
   delete it cleans. TraceIn fixes the scan type and maps key values (F x 100) to versions. *)
EXTENDS FuncIdxMvcc, FuncIdxMvccTraceData, Sequences, TLC

CONSTANTS TraceLog, TraceIn
VARIABLES i, mids
TVars == <<vars, i, mids>>

TInit ==
  /\ Init
  /\ fv = [e \in Ver |-> TRUE] /\ covered = TraceIn.covered /\ kfOn = TRUE
  /\ i = 0 /\ mids = [k \in Upd |-> 0]

Ev == TraceLog[i + 1]
VerOf(key) == TraceIn.ver[key]
Logged ==
  /\ i < Len(TraceLog)
  /\ i' = i + 1
  /\ \/ Ev.a = "Start" /\ Start /\ UNCHANGED mids
     \/ /\ Ev.a = "Vis" /\ Scan /\ pos = VerOf(Ev.key) /\ (Visible(pos) <=> Ev.vis = 1)
        /\ UNCHANGED mids
     \/ /\ Ev.a = "Begin" /\ Begin /\ VerOf(Ev.new) = next + 1
        /\ mids' = [mids EXCEPT ![next] = Ev.mid]
     \/ Ev.a = "Commit" /\ Commit /\ UNCHANGED mids
     \/ Ev.a = "Abort" /\ Abort /\ UNCHANGED mids
     \/ /\ Ev.a = "Vacuum"
        /\ \E e \in Ver : delBy[e] # 0 /\ mids[delBy[e]] = Ev.del /\ Vacuum(e)
        /\ UNCHANGED mids
Hidden ==
  /\ \/ Scan /\ ~ent[pos]
     \/ Finish
  /\ UNCHANGED <<i, mids>>
TSpec == TInit /\ [][Logged \/ Hidden]_TVars

TraceNotDone == i < Len(TraceLog)

\* run "commit": rows d = 4 -> 9 (F x 100 = 200 -> 300); run "abort": d = 9 -> 16 rolled back (300 -> 400)
CommitIn == [covered |-> FALSE, ver |-> (200 :> 1) @@ (300 :> 2) @@ (400 :> 3)]
AbortIn == [covered |-> TRUE, ver |-> (300 :> 1) @@ (400 :> 2) @@ (500 :> 3)]
=============================================================================
