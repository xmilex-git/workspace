------------------------------- MODULE BvLastRow -------------------------------
(* One execution of a BUILDVALUE (aggregates without GROUP BY) whose output list
   may read a column of its own scan (PR 8364, CBRD-27870, head f65d0c0fa).

   XASL generation decides XASL_OUTPUT_READS_SCAN and the aggregates'
   agg_optimized (Gen); the stream writes the operand program image from
   agg_optimized.  The server picks how the rows are aggregated (Path): the
   statistics/index evaluation that skips the rows ("fast"), the count-only
   index scan ("count"), the page batch ("batch"), the parallel buildvalue
   gather ("gather"), or the serial row loop ("serial").  The source rows are
   enumerated one per Row step on every path (the ghost lp, the last row that
   passed the filters, is the answer the claims compare with); only the serial
   loop fetches a row into the value-list slot the output reads, and the slot
   is valid only while its row is the scan's current one.  The flagged block
   copies each aggregated row (qexec_keep_last_row) and puts the copy back into
   the slot before the output list reads it (qexec_restore_last_row).

   Row values are row ordinals 1..N; 0 is NULL. *)
EXTENDS Naturals

CONSTANTS N, Mutant
Mutants == {"none", "base", "server_clear", "gen_no_agg_clear", "keep_after_scan",
            "no_batch_guard", "no_par_guard", "no_count_guard", "no_restore_null",
            "clone_null", "restore_no_null", "no_clear_last_row", "flag_always", "error_no_clear", "fix"}
ASSUME Assm == N \in Nat /\ N >= 1 /\ Mutant \in Mutants

\* Types for Apalache (tools/tla/apalache-types writes them into the declarations).
\* apalache-type: N Int
\* apalache-type: Mutant Str
\* apalache-type: readsScan Bool
\* apalache-type: optimizable Bool
\* apalache-type: countStar Bool
\* apalache-type: batchable Bool
\* apalache-type: parallelable Bool
\* apalache-type: alwaysFalse Bool
\* apalache-type: flag Bool
\* apalache-type: aggOpt Bool
\* apalache-type: srvAggOpt Bool
\* apalache-type: path Str
\* apalache-type: phase Str
\* apalache-type: k Int
\* apalache-type: lp Int
\* apalache-type: slotRow Int
\* apalache-type: slotValid Bool
\* apalache-type: slotOwned Bool
\* apalache-type: keptHas Bool
\* apalache-type: keptRow Int
\* apalache-type: lrAlloc Bool
\* apalache-type: shared Bool
\* apalache-type: out Int
\* apalache-type: outSet Bool
\* apalache-type: uaf Bool
\* apalache-type: mismatch Bool
\* apalache-type: assertFail Bool
\* apalache-type: copyFailed Bool
\* apalache-type: doubleFree Bool

VARIABLES readsScan,     \* input: the output list reads a slot of its scans (pt_buildvalue_output_reads_scan)
          optimizable,   \* input: an aggregate the statistics/index evaluation can answer (pt_to_aggregate)
          countStar,     \* input: a lone COUNT(*) over an index scan with no data filter
          batchable,     \* input: the block passes qexec_batch_eligible's other questions
          parallelable,  \* input: the parallel scan checker allows the block's scan
          alwaysFalse,   \* input: the WHERE is always false (is_always_false)
          flag,          \* XASL_OUTPUT_READS_SCAN
          aggOpt,        \* agg_optimized as generated and streamed: the image leaves those aggregates out
          srvAggOpt,     \* agg_optimized as the server runs it
          path,          \* how the server aggregates the rows
          phase,
          k,             \* rows enumerated
          lp,            \* ghost: the last row that passed the filters (0 = none)
          slotRow,       \* the row whose value the value-list slot holds (0 = NULL)
          slotValid,     \* the slot's memory is still valid
          slotOwned,     \* the slot owns its value (a copy), not a peek into the scan
          keptHas,       \* last_row holds a copy marked by last_row_kept
          keptRow,       \* the row of that copy (0 = NULL)
          lrAlloc,       \* last_row is allocated
          shared,        \* ghost: last_row and the slot own the same buffer
          out,           \* the value the output list read
          outSet,
          uaf,           \* ghost: a read of the slot after its memory was released
          mismatch,      \* ghost: the server settled a program unlike the streamed image (expr_image_same_prog)
          assertFail,    \* ghost: qexec_intprt_fnc's debug assert on agg_optimized fired
          copyFailed,    \* ghost: a copy of a row failed
          doubleFree     \* ghost: one buffer freed twice

vars == <<readsScan, optimizable, countStar, batchable, parallelable, alwaysFalse, flag, aggOpt,
          srvAggOpt, path, phase, k, lp, slotRow, slotValid, slotOwned, keptHas, keptRow, lrAlloc,
          shared, out, outSet, uaf, mismatch, assertFail, copyFailed, doubleFree>>

Phases == {"gen", "path", "loop", "restore", "output", "done", "error", "cleared"}
Paths == {"undecided", "none", "fast", "count", "batch", "gather", "serial"}

\* develop's choice, the PR's for a block it does not flag
BasePath == IF alwaysFalse THEN "none"
            ELSE IF optimizable THEN "fast"
            ELSE IF countStar THEN "count"
            ELSE IF parallelable THEN "gather"
            ELSE IF batchable THEN "batch"
            ELSE "serial"

\* qexec_intprt_fnc, qexec_batch_eligible and the parallel scan checker for a block with flag f
ChoosePath(f, so) ==
  IF alwaysFalse THEN "none"
  ELSE IF optimizable /\ so THEN "fast"
  ELSE IF countStar /\ ~(f /\ Mutant \notin {"no_count_guard", "fix"}) THEN "count"
  ELSE IF parallelable /\ ~(f /\ Mutant \notin {"no_par_guard", "fix"}) THEN "gather"
  ELSE IF batchable /\ ~(f /\ Mutant # "no_batch_guard") THEN "batch"
  ELSE "serial"

Init ==
  /\ readsScan \in BOOLEAN /\ optimizable \in BOOLEAN /\ countStar \in BOOLEAN
  /\ batchable \in BOOLEAN /\ parallelable \in BOOLEAN /\ alwaysFalse \in BOOLEAN
  /\ flag = FALSE /\ aggOpt = FALSE /\ srvAggOpt = FALSE
  /\ path = "undecided" /\ phase = "gen"
  /\ k = 0 /\ lp = 0
  /\ slotRow = 0 /\ slotValid = TRUE /\ slotOwned = FALSE
  /\ keptHas = FALSE /\ keptRow = 0 /\ lrAlloc = FALSE /\ shared = FALSE
  /\ out = 0 /\ outSet = FALSE
  /\ uaf = FALSE /\ mismatch = FALSE /\ assertFail = FALSE /\ copyFailed = FALSE /\ doubleFree = FALSE

\* pt_to_buildvalue_proc: the flag, then agg_optimized cleared on the flagged block, before the stream
Gen ==
  /\ phase = "gen"
  /\ flag' = (IF Mutant = "base" THEN FALSE ELSE IF Mutant = "flag_always" THEN TRUE ELSE readsScan)
  /\ aggOpt' = (optimizable /\ (~flag' \/ Mutant \in {"server_clear", "gen_no_agg_clear", "fix"}))
  /\ phase' = "path"
  /\ UNCHANGED <<readsScan, optimizable, countStar, batchable, parallelable, alwaysFalse,
                 srvAggOpt, path, k, lp, slotRow, slotValid, slotOwned, keptHas, keptRow,
                 lrAlloc, shared, out, outSet, uaf, mismatch, assertFail, copyFailed, doubleFree>>

\* qexec_intprt_fnc before its loop (the debug assert, the statistics/index evaluation, the count-only
\* check), qexec_batch_eligible and the checker's CANNOT_PARALLEL_SCAN (decided at generation)
Path ==
  /\ phase = "path"
  /\ srvAggOpt' = (aggOpt /\ ~(Mutant = "server_clear" /\ flag))
  /\ assertFail' = (~alwaysFalse /\ flag /\ srvAggOpt' /\ Mutant \notin {"base", "server_clear", "fix"})
  /\ path' = ChoosePath(flag, srvAggOpt')
  /\ phase' = "loop"
  /\ UNCHANGED <<readsScan, optimizable, countStar, batchable, parallelable, alwaysFalse,
                 flag, aggOpt, k, lp, slotRow, slotValid, slotOwned, keptHas, keptRow,
                 lrAlloc, shared, out, outSet, uaf, mismatch, copyFailed, doubleFree>>

\* the source's next row; p: it passes the filters.  The serial loop fetches it into the slot
\* (fetch_val_list clears an owned value first); a passing row is aggregated (qdata_evaluate_aggregate_list
\* settles the operand program) and, on a flagged serial block, copied (qexec_keep_last_row)
Keeps(p) == p /\ flag /\ path = "serial" /\ Mutant # "keep_after_scan"
Row(p) ==
  /\ phase = "loop" /\ k < N
  /\ (alwaysFalse => ~p)
  /\ k' = k + 1
  /\ lp' = (IF p THEN k + 1 ELSE lp)
  /\ IF path = "serial"
       THEN slotRow' = k + 1 /\ slotValid' = TRUE /\ slotOwned' = FALSE
       ELSE UNCHANGED <<slotRow, slotValid, slotOwned>>
  /\ mismatch' = (mismatch \/ (p /\ path # "fast" /\ optimizable /\ aggOpt # srvAggOpt))
  /\ IF Keeps(p)
       THEN keptHas' = TRUE /\ keptRow' = k + 1 /\ lrAlloc' = TRUE
       ELSE UNCHANGED <<keptHas, keptRow, lrAlloc>>
  /\ UNCHANGED <<readsScan, optimizable, countStar, batchable, parallelable, alwaysFalse,
                 flag, aggOpt, srvAggOpt, path, phase, shared, out, outSet, uaf, assertFail,
                 copyFailed, doubleFree>>

\* qexec_keep_last_row fails (the allocation, or the type's setval): the query ends with the error.
\* The clone_null mutant is pr_clone_value, which stores NULL and returns NO_ERROR
RowKeepFail ==
  /\ phase = "loop" /\ k < N
  /\ Keeps(TRUE) /\ ~alwaysFalse
  /\ k' = k + 1
  /\ lp' = k + 1
  /\ slotRow' = k + 1 /\ slotValid' = TRUE /\ slotOwned' = FALSE
  /\ mismatch' = (mismatch \/ (optimizable /\ aggOpt # srvAggOpt))
  /\ copyFailed' = TRUE
  /\ \E a \in BOOLEAN : lrAlloc' = (lrAlloc \/ a)
  /\ IF Mutant = "clone_null"
       THEN keptHas' = TRUE /\ keptRow' = 0 /\ phase' = "loop"
       ELSE UNCHANGED <<keptHas, keptRow>> /\ phase' = "error"
  /\ UNCHANGED <<readsScan, optimizable, countStar, batchable, parallelable, alwaysFalse,
                 flag, aggOpt, srvAggOpt, path, shared, out, outSet, uaf, assertFail, doubleFree>>

\* the scan ends: its page is unfixed and the attribute cache's buffers freed; a peeked value dangles.
\* keep_after_scan is the PR's first head, which copied the slots only here
Close ==
  /\ phase = "loop" /\ k = N
  /\ slotValid' = (slotOwned \/ slotRow = 0)
  /\ IF Mutant = "keep_after_scan" /\ flag /\ path = "serial"
       THEN /\ uaf' = (uaf \/ (slotRow # 0 /\ ~slotValid'))
            /\ keptHas' = TRUE /\ keptRow' = slotRow /\ lrAlloc' = TRUE
       ELSE UNCHANGED <<uaf, keptHas, keptRow, lrAlloc>>
  /\ phase' = "restore"
  /\ UNCHANGED <<readsScan, optimizable, countStar, batchable, parallelable, alwaysFalse,
                 flag, aggOpt, srvAggOpt, path, k, lp, slotRow, slotOwned, shared, out, outSet,
                 mismatch, assertFail, copyFailed, doubleFree>>

\* qexec_end_buildvalueblock_iterations -> qexec_restore_last_row: the slot takes the copy over and
\* last_row[i] is reset to NULL; no copy -> NULL
Restore ==
  /\ phase = "restore"
  /\ IF flag /\ keptHas
       THEN /\ slotRow' = keptRow /\ slotValid' = TRUE /\ slotOwned' = TRUE
            /\ keptHas' = (Mutant = "restore_no_null")
            /\ shared' = (Mutant = "restore_no_null")
       ELSE IF flag /\ Mutant # "no_restore_null"
       THEN /\ slotRow' = 0 /\ slotValid' = TRUE /\ slotOwned' = FALSE
            /\ UNCHANGED <<keptHas, shared>>
       ELSE UNCHANGED <<slotRow, slotValid, slotOwned, keptHas, shared>>
  /\ phase' = "output"
  /\ UNCHANGED <<readsScan, optimizable, countStar, batchable, parallelable, alwaysFalse,
                 flag, aggOpt, srvAggOpt, path, k, lp, keptRow, lrAlloc, out, outSet, uaf,
                 mismatch, assertFail, copyFailed, doubleFree>>

\* the output list reads the slot (a hidden ODKU column, or the derived table's carried column)
Output ==
  /\ phase = "output"
  /\ IF readsScan
       THEN /\ out' = slotRow /\ outSet' = TRUE
            /\ uaf' = (uaf \/ (slotRow # 0 /\ ~slotValid))
       ELSE UNCHANGED <<out, outSet, uaf>>
  /\ phase' = "done"
  /\ UNCHANGED <<readsScan, optimizable, countStar, batchable, parallelable, alwaysFalse,
                 flag, aggOpt, srvAggOpt, path, k, lp, slotRow, slotValid, slotOwned, keptHas,
                 keptRow, lrAlloc, shared, mismatch, assertFail, copyFailed, doubleFree>>

\* qexec_clear_xasl (is_final) at the end of the query, on success and on error: qexec_clear_last_row
\* frees last_row[i] and last_row, then the value list's values are cleared
Clear ==
  /\ phase \in (IF Mutant = "error_no_clear" THEN {"done"} ELSE {"done", "error"})
  /\ doubleFree' = (doubleFree \/ shared)
  /\ lrAlloc' = (Mutant = "no_clear_last_row" /\ lrAlloc)
  /\ keptHas' = FALSE /\ keptRow' = 0 /\ shared' = FALSE
  /\ slotOwned' = FALSE
  /\ phase' = "cleared"
  /\ UNCHANGED <<readsScan, optimizable, countStar, batchable, parallelable, alwaysFalse,
                 flag, aggOpt, srvAggOpt, path, k, lp, slotRow, slotValid, out, outSet, uaf,
                 mismatch, assertFail, copyFailed>>

Terminating == phase = "cleared" /\ UNCHANGED vars

Next == Gen \/ Path \/ (\E p \in BOOLEAN : Row(p)) \/ RowKeepFail \/ Close \/ Restore \/ Output \/ Clear
        \/ Terminating
Spec == Init /\ [][Next]_vars /\ WF_vars(Next)

-----------------------------------------------------------------------------
\* Claims (MAP.md)
BoolOK == /\ readsScan \in BOOLEAN /\ optimizable \in BOOLEAN /\ countStar \in BOOLEAN
          /\ batchable \in BOOLEAN /\ parallelable \in BOOLEAN /\ alwaysFalse \in BOOLEAN
          /\ flag \in BOOLEAN /\ aggOpt \in BOOLEAN /\ srvAggOpt \in BOOLEAN
          /\ slotValid \in BOOLEAN /\ slotOwned \in BOOLEAN /\ keptHas \in BOOLEAN
          /\ lrAlloc \in BOOLEAN /\ shared \in BOOLEAN /\ outSet \in BOOLEAN /\ uaf \in BOOLEAN
          /\ mismatch \in BOOLEAN /\ assertFail \in BOOLEAN /\ copyFailed \in BOOLEAN
          /\ doubleFree \in BOOLEAN
IntOK == /\ k \in 0..N /\ lp \in 0..N /\ slotRow \in 0..N /\ keptRow \in 0..N /\ out \in 0..N
StrOK == path \in Paths /\ phase \in Phases
TypeOK == BoolOK /\ IntOK /\ StrOK

\* the paths that never fetch a row into the slot read NULL, as on develop
DevelopNullPath == {"fast", "gather", "count"}
OutputIsLastPassed == outSet => out = (IF path \in DevelopNullPath THEN 0 ELSE lp)  \* C1
DoneHasOutput == (phase = "done" /\ readsScan) => outSet              \* C1
NoDanglingRead == ~uaf                                                \* C2
ImageMatchesServer == ~mismatch /\ ~assertFail                        \* C3
CopyErrorNotLost == copyFailed => ~outSet                             \* C4
NoLeakNoDoubleFree == (phase = "cleared" => ~lrAlloc) /\ ~doubleFree  \* C5
OtherQueriesUnchanged == (~readsScan /\ phase \notin {"gen", "path"}) => path = BasePath  \* C6
Terminates == <>(phase = "cleared")                                   \* C7
\* the flagged block keeps develop's aggregate evaluation and parallel scan; only the page batch declines it
OptimizationsKept == phase \notin {"gen", "path"} =>
                       path = (IF flag /\ BasePath = "batch" THEN "serial" ELSE BasePath)  \* C8

\* inductive invariant of the correct variant
R_pre == phase \in {"gen", "path"} =>
           /\ k = 0 /\ lp = 0 /\ ~keptHas /\ ~lrAlloc /\ ~outSet /\ ~copyFailed
           /\ slotRow = 0 /\ slotValid /\ ~slotOwned
R_gen == phase # "gen" => (flag = readsScan /\ aggOpt = (optimizable /\ ~(flag /\ Mutant = "none")))
R_path == phase \notin {"gen", "path"} =>
            /\ srvAggOpt = aggOpt
            /\ path = (IF flag /\ Mutant = "none" THEN (IF alwaysFalse THEN "none" ELSE "serial")
                       ELSE IF flag /\ BasePath = "batch" THEN "serial" ELSE BasePath)
R_ghost == ~uaf /\ ~mismatch /\ ~assertFail /\ ~doubleFree /\ ~shared
R_lp == lp <= k /\ (alwaysFalse => lp = 0)
R_kept == (phase \in {"loop", "restore"} /\ flag /\ path = "serial") =>
            ((keptHas <=> lp # 0) /\ (keptHas => keptRow = lp))
R_unflagged == (~flag \/ path # "serial") => (~keptHas /\ ~lrAlloc)
R_alloc == keptHas => lrAlloc
R_loop == phase = "loop" =>
            /\ (path = "serial" /\ k > 0) => (slotRow = k /\ slotValid /\ ~slotOwned)
            /\ (path # "serial" \/ k = 0) => (slotRow = 0 /\ slotValid /\ ~slotOwned)
R_restore == phase = "restore" => (k = N /\ ~slotOwned /\ (slotValid <=> slotRow = 0))
R_output == phase = "output" =>
              /\ k = N
              /\ (flag /\ path = "serial") => (slotRow = lp /\ slotValid)
              /\ (flag /\ path # "serial") => (slotRow = 0 /\ slotValid)
R_out == outSet => (out = (IF path = "serial" THEN lp ELSE 0) /\ readsScan /\ phase \in {"done", "cleared"}
                    /\ (path \notin DevelopNullPath => path \in {"serial", "none"}))
R_done == (phase = "done" /\ readsScan) => outSet
R_copy == copyFailed => (phase \in {"error", "cleared"} /\ ~outSet)
R_err == phase = "error" => copyFailed
R_cleared == phase = "cleared" => (~lrAlloc /\ ~keptHas)
R_none == path = "none" => alwaysFalse
IndInv == /\ TypeOK /\ R_pre /\ R_gen /\ R_path /\ R_ghost /\ R_lp /\ R_kept /\ R_unflagged
          /\ R_alloc /\ R_loop /\ R_restore /\ R_output /\ R_out /\ R_done /\ R_copy /\ R_err
          /\ R_cleared /\ R_none

\* witnesses: outcomes that must be reachable
NotValueOut == ~(outSet /\ out # 0)
NotNullOut == ~(outSet /\ out = 0 /\ ~copyFailed)
NotError == phase # "error"
NotFast == path # "fast"
NotBatch == path # "batch"
NotGather == path # "gather"
NotCount == path # "count"
NotFlaggedFast == ~(flag /\ path = "fast" /\ outSet)

\* Apalache inductive check: the integer bound N open
CInit == N \in Nat /\ N >= 1 /\ Mutant = "none"
CInitFix == N \in Nat /\ N >= 1 /\ Mutant = "fix"
=============================================================================
