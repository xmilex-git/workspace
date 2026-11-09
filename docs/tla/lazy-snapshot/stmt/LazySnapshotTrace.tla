--------------------------- MODULE LazySnapshotTrace ---------------------------
(* Trace validation of LazySnapshot against a run of the probe build (traces/:
   develop 2d928e34b + the TLATRACE lines of traces/probe.diff, optdebug) in which
   a READ COMMITTED statement's snapshot build was held between the status copy
   and the statistics load (CUBRID_TLA_BUILD_STATS_WAIT_MS) while another
   transaction committed. Logged: Invalidate (logtb_invalidate_snapshot_data),
   StatsPublish and Complete (complete_mvcc, under m_active_trans_mutex),
   StatsLoad (logtb_create_unique_stats_from_repr, where=build inside
   build_mvcc_info), Build (the end of build_mvcc_info). The writer's own snapshot
   builds and invalidations are left out of the projection: writers do not read
   in the model. Real MVCCIDs, history positions and versions are shifted by the
   run's base values; a count of loaded OIDs above OidsBase is the number of
   writers whose statistics the load included.
   Runs of the fix (PR #8438 head + the same probe) also log Confirm
   (logtb_confirm_global_statistics, where=build after the build loop or where=late
   in qexec_evaluate_aggregates_optimize, with ok = the version check's outcome);
   the build's own end is then a check of the reader's snapshot fields. *)
EXTENDS LazySnapshot, LazySnapshotTraceData, Sequences, FiniteSets

CONSTANTS TraceLog, IdBase, PosBase, OidsBase
VARIABLE i
TVars == <<vars, i>>

TInit == Init /\ i = 0
Ev == TraceLog[i + 1]
IdOf(m) == m - IdBase + 1
PosOf(x) == (x - PosBase) % H

Logged ==
  /\ i < Len(TraceLog)
  /\ i' = i + 1
  /\ \/ Ev.a = "Invalidate" /\ Exec /\ flag /\ (valid <=> Ev.valid = 1)
     \/ Ev.a = "StatsPublish" /\ \E w \in W : WStats(w) /\ wid[w] = IdOf(Ev.mvccid)
     \/ Ev.a = "Complete" /\ \E w \in W : /\ WPos(w) /\ wid[w] = IdOf(Ev.mvccid)
                                         /\ wnx[w] = PosOf(Ev.pos) /\ wver[w] = Ev.ver - PosBase
     \/ Ev.a = "StatsLoad" /\ Ev.where = "build" /\ BStats /\ cos \in {"to_load", "loading"}
        /\ Cardinality(cstats') = Ev.oids - OidsBase
     \/ Ev.a = "Build" /\ ~StatsFix /\ BCheck /\ valid' /\ rg = IdOf(Ev.lowest) /\ rpos = PosOf(Ev.pos)
        /\ rver = Ev.ver - PosBase
     \* the fix: logtb_confirm_global_statistics, then the end of build_mvcc_info
     \/ Ev.a = "Confirm" /\ Ev.where = "build" /\ BConf /\ snapVer = Ev.ver - PosBase
        /\ (cos = "loading" => ((cos' = "loaded") <=> Ev.ok = 1))
     \/ Ev.a = "Build" /\ StatsFix /\ UNCHANGED vars /\ rpc = "op" /\ valid /\ snapLow = IdOf(Ev.lowest)
        /\ rpos = PosOf(Ev.pos) /\ snapVer = Ev.ver - PosBase
     \/ Ev.a = "StatsLoad" /\ Ev.where = "late" /\ CountLate /\ Cardinality(cstats') = Ev.oids - OidsBase
     \/ Ev.a = "Confirm" /\ Ev.where = "late" /\ CountConf /\ snapVer = Ev.ver - PosBase
        /\ ((cos' = "loaded") <=> Ev.ok = 1)

Hidden ==
  /\ UNCHANGED i
  /\ \/ StmtBegin \/ NeedBuild \/ BSlot \/ BReadG \/ BSetSlot \/ BPos \/ BVer \/ BCopy
     \/ ScanRead \/ CountRead \/ StmtEnd \/ TEnd \/ VStep
     \/ (BStats /\ cos \notin {"to_load", "loading"}) \/ (BCheck /\ ~valid') \/ (BCheck /\ StatsFix)
     \/ \E w \in W : WBegin(w) \/ WOp(w) \/ WLock(w) \/ WStart(w) \/ WInactive(w) \/ WFill(w)
                     \/ WUnlock(w) \/ WAdvance(w) \/ WAck(w)
TSpec == TInit /\ [][Logged \/ Hidden]_TVars

TraceNotDone == i < Len(TraceLog)
=============================================================================
