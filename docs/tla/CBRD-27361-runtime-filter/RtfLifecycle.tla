--------------------------- MODULE RtfLifecycle ---------------------------
(* The hash join runtime filter's life across the leader and the parallel scan workers (CBRD-27361,
   develop be0a9ab1f, query_hash_join.c hjoin_rtf_*, px_scan_task.cpp, query_executor.c).

   The leader runs the join's first input, builds the filter from its list (hjoin_rtf_build), runs the target
   block whose heap scan is parallel, and frees the filter once the target's scans are closed
   (hjoin_rtf_release).  Each worker binds the leader's filter on its clone (hjoin_rtf_bind_clone), looks rows'
   keys up in it (hjoin_rtf_pass / the batch leaf), may take it off its clone after the sample
   (hjoin_rtf_sample), and in finalize () adds its counters to the leader's node and drops the alias
   (hjoin_rtf_unbind_clone) before the clone goes back to the pool.  A worker error or a leader interrupt
   stops the scan; the leader drains the workers (wait_for_workers) before the release. *)
EXTENDS Naturals, FiniteSets

CONSTANTS Workers, Keys, MaxRows, Mutant
ASSUME Assm == /\ IsFiniteSet(Workers) /\ Workers # {} /\ Keys # {} /\ IsFiniteSet(Keys)
               /\ MaxRows \in Nat /\ MaxRows >= 1
               /\ Mutant \in {"none", "release_before_drain", "install_partial", "read_counts_early",
                              "no_unbind",
                              "error_no_finalize"}

LPhases == {"first", "build", "scan", "close", "release", "done"}
WPhases == {"idle", "probe", "row", "fin", "done", "lost"}

VARIABLES
  lph,        \* the leader
  bkeys,      \* the first input's join keys (its list)
  filt,       \* "none" (no filter), "live", "freed"
  fkeys,      \* the keys the filter holds
  stop,       \* the parallel scan's interrupt (a worker error, the leader's interrupt, JOB_ENDED)
  lerr,       \* the leader leaves the target block on an error
  wph,        \* [Workers -> WPhases]
  alias,      \* [Workers -> BOOLEAN]: the worker's clone points at the leader's filter
  left,       \* [Workers -> 0..MaxRows]: rows still in the worker's share of the heap
  rows,       \* [Workers -> 0..MaxRows]: rows the worker checked against the filter, counted on its clone
  merged,     \* [Workers -> BOOLEAN]: the worker added its rows to the leader's node (hjoin_rtf_unbind_clone)
  read,       \* ghost: the leader read its node's counters
  snap,       \* ghost: the per-worker counts the leader's node held when the leader read them
  uaf,        \* ghost: the filter read after it was freed
  fneg        \* ghost: a probe row dropped whose key the first input has

vars == <<lph, bkeys, filt, fkeys, stop, lerr, wph, alias, left, rows, merged, read, snap, uaf, fneg>>

\* what the leader's node holds: each merged worker's rows (the sum of these is rtf_rows)
Held == [w \in Workers |-> IF merged[w] THEN rows[w] ELSE 0]

\* ---------------------------------------------------------------- properties
TypeOK == /\ lph \in LPhases /\ bkeys \in SUBSET Keys /\ filt \in {"none", "live", "freed"} /\ fkeys \in SUBSET Keys
          /\ stop \in BOOLEAN /\ lerr \in BOOLEAN
          /\ wph \in [Workers -> WPhases] /\ alias \in [Workers -> BOOLEAN] /\ left \in [Workers -> 0..MaxRows]
          /\ rows \in [Workers -> 0..MaxRows]
          /\ merged \in [Workers -> BOOLEAN] /\ read \in BOOLEAN /\ snap \in [Workers -> 0..MaxRows]
          /\ uaf \in BOOLEAN /\ fneg \in BOOLEAN

NoUseAfterFree == ~uaf                                                    \* C1
NoFalseNegative == ~fneg                                                  \* C2
CountsComplete == read => snap = rows                            \* C3
LeaderFinishes == <>(lph = "done")                                        \* C4

\* witnesses
NotErrorRelease == ~(lph = "done" /\ lerr /\ filt = "freed" /\ \E w \in Workers : rows[w] > 0)
NotSampledOff == ~(lph = "done" /\ filt = "freed" /\ \E w, v \in Workers : w # v /\ rows[w] > 0 /\ rows[v] > 0)

\* ---------------------------------------------------------------- the leader
Init == /\ lph = "first" /\ bkeys \in SUBSET Keys /\ filt = "none" /\ fkeys = {}
        /\ stop = FALSE /\ lerr = FALSE
        /\ wph = [w \in Workers |-> "idle"] /\ alias = [w \in Workers |-> FALSE] /\ left = [w \in Workers |-> MaxRows] /\ rows = [w \in Workers |-> 0]
        /\ merged = [w \in Workers |-> FALSE] /\ read = FALSE /\ snap = [w \in Workers |-> 0] /\ uaf = FALSE /\ fneg = FALSE

\* qexec_execute_mainblock (rtf_first): the first input's list
LFirst == /\ lph = "first"
          /\ lph' = "build"
          /\ UNCHANGED <<bkeys, filt, fkeys, stop, lerr, wph, alias, left, rows, merged, read, snap, uaf, fneg>>

\* hjoin_rtf_build: every key of the list read (S_END) installs the filter; a decline (too many keys, a type,
\* no memory) installs none and the join goes on; a list that ends in an error installs none and fails.
LBuild == /\ lph = "build"
          /\ \/ filt' = "live" /\ fkeys' = bkeys /\ lph' = "scan" /\ UNCHANGED lerr
             \/ UNCHANGED <<filt, fkeys>> /\ lph' = "scan" /\ UNCHANGED lerr
             \/ /\ Mutant = "install_partial"
                /\ \E part \in SUBSET bkeys : filt' = "live" /\ fkeys' = part
                /\ lph' = "scan" /\ UNCHANGED lerr
          /\ UNCHANGED <<bkeys, stop, wph, alias, left, rows, merged, read, snap, uaf, fneg>>
\* the list scan fails: the filter memory is freed in hjoin_rtf_build (fail:), none installed; the block exits
LBuildFail == /\ lph = "build"
              /\ lph' = "release" /\ lerr' = TRUE
              /\ UNCHANGED <<bkeys, filt, fkeys, stop, wph, alias, left, rows, merged, read, snap, uaf, fneg>>

\* the target block's scan: the leader takes the workers' rows; an interrupt or its own error stops the scan
LInterrupt == /\ lph = "scan" /\ ~stop
              /\ stop' = TRUE /\ lerr' = TRUE
              /\ lph' = IF Mutant = "release_before_drain" THEN "release" ELSE "close"
              /\ UNCHANGED <<bkeys, filt, fkeys, wph, alias, left, rows, merged, read, snap, uaf, fneg>>
LScanEnd == /\ lph = "scan" /\ \A w \in Workers : wph[w] \in {"fin", "done"}
            /\ lph' = "close"
            /\ UNCHANGED <<bkeys, filt, fkeys, stop, lerr, wph, alias, left, rows, merged, read, snap, uaf, fneg>>
\* scan_end_scan / scan_close_scan: wait_for_workers () sets JOB_ENDED and joins every worker
LClose == /\ lph = "close"
          /\ stop' = TRUE
          /\ \A w \in Workers : wph[w] = "done"
          /\ lph' = "release"
          /\ UNCHANGED <<bkeys, filt, fkeys, lerr, wph, alias, left, rows, merged, read, snap, uaf, fneg>>
LSignalStop == /\ lph = "close" /\ ~stop
               /\ stop' = TRUE
               /\ UNCHANGED <<lph, bkeys, filt, fkeys, lerr, wph, alias, left, rows, merged, read, snap, uaf, fneg>>
\* hjoin_rtf_release (qexec_end_mainblock_iterations, or qexec_clear_xasl on the error exit): the target's
\* counters read, the filter freed
LRelease == /\ lph = "release"
            /\ IF filt = "live"
               THEN /\ filt' = "freed"
                    /\ snap' = Held /\ read' = TRUE
               ELSE UNCHANGED <<filt, read, snap>>
            /\ lph' = IF Mutant = "release_before_drain" /\ ~\A w \in Workers : wph[w] = "done"
                      THEN "close" ELSE "done"
            /\ UNCHANGED <<bkeys, fkeys, stop, lerr, wph, alias, left, rows, merged, uaf, fneg>>
\* mutant: the counters read before the workers are drained
LReadEarly == /\ lph = "scan" /\ Mutant = "read_counts_early" /\ filt = "live" /\ ~read
              /\ snap' = Held /\ read' = TRUE
              /\ UNCHANGED <<lph, bkeys, filt, fkeys, stop, lerr, wph, alias, left, rows, merged, uaf, fneg>>

\* ---------------------------------------------------------------- a worker
\* initialize (): clone_xasl, then hjoin_rtf_bind_clone (the leader's filter on the clone, counters zeroed)
WBind(w) == /\ wph[w] = "idle" /\ lph = "scan"
            /\ wph' = [wph EXCEPT ![w] = "probe"]
            /\ alias' = [alias EXCEPT ![w] = (filt = "live")]
            /\ uaf' = (uaf \/ filt = "freed")
            /\ UNCHANGED <<lph, bkeys, filt, fkeys, stop, lerr, left, rows, merged, read, snap, fneg>>
\* the scan loop checks the interrupt before a row (a chunk: its runtime filter leaf runs over all its rows)
WRow(w) == /\ wph[w] = "probe" /\ ~stop /\ left[w] > 0
           /\ wph' = [wph EXCEPT ![w] = "row"] /\ left' = [left EXCEPT ![w] = left[w] - 1]
           /\ UNCHANGED <<lph, bkeys, filt, fkeys, stop, lerr, alias, rows, merged, read, snap, uaf, fneg>>
\* the key looked up in the filter the clone points at (hjoin_rtf_pass, hjoin_rtf_contains_n), counted on the clone
WProbe(w) == /\ wph[w] = "row"
             /\ \E k \in Keys :
                  /\ rows' = [rows EXCEPT ![w] = IF alias[w] THEN rows[w] + 1 ELSE rows[w]]
                  /\ uaf' = (uaf \/ (alias[w] /\ filt = "freed"))
                  /\ fneg' = (fneg \/ (alias[w] /\ k \notin fkeys /\ k \in bkeys))
             /\ wph' = [wph EXCEPT ![w] = "probe"]
             /\ UNCHANGED <<lph, bkeys, filt, fkeys, stop, lerr, alias, left, merged, read, snap>>
\* hjoin_rtf_sample: the clone's sample done and the filter drops too few: off this clone only
WSample(w) == /\ wph[w] = "probe" /\ alias[w]
              /\ alias' = [alias EXCEPT ![w] = FALSE]
              /\ UNCHANGED <<lph, bkeys, filt, fkeys, stop, lerr, wph, left, rows, merged, read, snap, uaf, fneg>>
\* the worker's part ends (S_END), or it stops: an error it raises sets the interrupt for every worker
WEnd(w) == /\ wph[w] = "probe"
           /\ wph' = [wph EXCEPT ![w] = "fin"]
           /\ UNCHANGED <<lph, bkeys, filt, fkeys, stop, lerr, alias, left, rows, merged, read, snap, uaf, fneg>>
WError(w) == /\ wph[w] = "probe" /\ ~stop
             /\ wph' = [wph EXCEPT ![w] = IF Mutant = "error_no_finalize" THEN "lost" ELSE "fin"] /\ stop' = TRUE
             /\ UNCHANGED <<lph, bkeys, filt, fkeys, lerr, alias, left, rows, merged, read, snap, uaf, fneg>>
\* a worker the scan never started (an interrupt before it bound) ends too
WSkip(w) == /\ wph[w] = "idle" /\ stop
            /\ wph' = [wph EXCEPT ![w] = "done"]
            /\ UNCHANGED <<lph, bkeys, filt, fkeys, stop, lerr, alias, left, rows, merged, read, snap, uaf, fneg>>
\* finalize (): hjoin_rtf_unbind_clone adds the clone's counters to the leader's node and drops the alias
\* (rtf_val marks a bound clone; a sampled-off clone's rows count all the same), then the clone is retired
WFinalize(w) == /\ wph[w] = "fin"
                /\ wph' = [wph EXCEPT ![w] = "done"]
                /\ IF Mutant = "no_unbind"
                   THEN UNCHANGED <<alias, merged>>
                   ELSE /\ merged' = [merged EXCEPT ![w] = TRUE]
                        /\ alias' = [alias EXCEPT ![w] = FALSE]
                /\ UNCHANGED <<lph, bkeys, filt, fkeys, stop, lerr, left, rows, read, snap, uaf, fneg>>

Terminating == lph = "done" /\ UNCHANGED vars

Next == \/ LFirst \/ LBuild \/ LBuildFail \/ LInterrupt \/ LScanEnd \/ LClose \/ LSignalStop \/ LRelease
        \/ LReadEarly
        \/ \E w \in Workers : WBind(w) \/ WRow(w) \/ WProbe(w) \/ WSample(w) \/ WEnd(w) \/ WError(w) \/ WSkip(w)
                              \/ WFinalize(w)
        \/ Terminating

Fairness == /\ WF_vars(LFirst) /\ WF_vars(LBuild) /\ WF_vars(LScanEnd) /\ WF_vars(LClose)
            /\ WF_vars(LSignalStop) /\ WF_vars(LRelease)
            /\ \A w \in Workers : WF_vars(WBind(w)) /\ WF_vars(WProbe(w)) /\ WF_vars(WEnd(w)) /\ WF_vars(WSkip(w))
                                  /\ WF_vars(WFinalize(w))
Spec == Init /\ [][Next]_vars /\ Fairness

\* ---------------------------------------------------------------- inductive invariant
\* in parts (the proof takes them one at a time), in the order TLC enumerates them (INIT IndInv)
IGhost == uaf = FALSE /\ fneg = FALSE
ILeader == /\ lph \in LPhases /\ stop \in BOOLEAN /\ lerr \in BOOLEAN
           /\ lph \in {"first", "build"} => ~stop /\ ~lerr
IFilter == /\ bkeys \in SUBSET Keys /\ filt \in {"none", "live", "freed"}
           /\ lph \in {"first", "build"} => filt = "none"
           /\ filt = "freed" => lph = "done"
           /\ fkeys \in SUBSET Keys
           /\ filt = "live" => fkeys = bkeys
           /\ filt = "none" => fkeys = {}
IWorkers == /\ wph \in [Workers -> WPhases]
            /\ \A w \in Workers : wph[w] # "lost"
            /\ \A w \in Workers : wph[w] # "idle" => lph \in {"scan", "close", "release", "done"}
            /\ lph \in {"release", "done"} => \A w \in Workers : wph[w] \in {"idle", "done"}
            /\ alias \in [Workers -> BOOLEAN]
            /\ \A w \in Workers : alias[w] => filt = "live" /\ wph[w] \in {"probe", "row", "fin"}
            /\ left \in [Workers -> 0..MaxRows] /\ rows \in [Workers -> 0..MaxRows]
            /\ \A w \in Workers : rows[w] + left[w] <= MaxRows
            /\ \A w \in Workers : wph[w] = "row" => rows[w] + left[w] < MaxRows
            /\ \A w \in Workers : wph[w] = "idle" => left[w] = MaxRows /\ rows[w] = 0
IMerge == /\ merged \in [Workers -> BOOLEAN]
          /\ \A w \in Workers : merged[w] => wph[w] = "done"
          /\ \A w \in Workers : wph[w] = "done" => merged[w] \/ rows[w] = 0
          /\ read \in BOOLEAN
          /\ read => lph = "done"
          /\ snap \in [Workers -> 0..MaxRows]
          /\ read => snap = rows
IndInv == IGhost /\ ILeader /\ IFilter /\ IWorkers /\ IMerge
=============================================================================
