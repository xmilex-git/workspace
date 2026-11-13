--------------------------- MODULE AnaStreamTrace ---------------------------
(* Trace validation: is a run of the instrumented head build (3501715f1 + TLATRACE lines in
   query_executor.c, MAP.md "Trace validation") a behavior of AnaStream? Every action of the spec is logged, so
   no action is hidden. The run's input (sorted rows, the evaluation group's functions, the SKIP_SORT flag with
   SELECT ROWNUM, the kind whose row value is row_vals[0]) is fixed by TraceIn; AreaMax is
   max_agg_hash_size div reclen of the run. inum = -1 and rv = -1 mean the build had none to log. *)
EXTENDS AnaStream, AnaStreamTraceData, TLC

CONSTANTS TraceLog, TraceIn
VARIABLE t
TVars == <<vars, t>>

TInit ==
  /\ rows = TraceIn.rows /\ F = TraceIn.F /\ skip = TraceIn.skip
  /\ streaming = TRUE /\ CanStream
  /\ pc = "key" /\ out = <<>> /\ ret = "add" /\ i = 1 /\ ended = FALSE /\ err = FALSE
  /\ grp = 0 /\ skc = 0 /\ rk = 0 /\ dr = 0 /\ cnt = 0 /\ sv = ZeroSv
  /\ area = <<>> /\ spill = <<>> /\ spillVals = <<>> /\ valsInMem = <<>> /\ files = 0 /\ fl = 0 /\ inum = 0
  /\ t = 0

Ev == TraceLog[t + 1]
Rv0 == TraceIn.rv0
InumOK == Ev.inum = -1 \/ inum' = Ev.inum
LastOf(s) == s[Len(s)]

AddOutcome ==
  \/ /\ Ev.mode = "put" /\ Ev.ok = 1 /\ Len(out') = Len(out) + 1 /\ InumOK
     /\ (Rv0 = "" \/ LastOf(out').v[Rv0] = <<"v", Ev.rv, 0>>)
  \/ /\ Ev.mode = "area" /\ Len(area') = Len(area) + 1
     /\ (Rv0 = "" \/ LastOf(area').rv[Rv0] = Ev.rv)
  \/ /\ Ev.mode = "spill" /\ Len(spill') = Len(spill) + 1
     /\ (Rv0 = "" \/ LastOf(spillVals')[Rv0] = Ev.rv)

PutOutcome ==
  /\ fl = Ev.row /\ Len(area) + Len(spill) = Ev.rows
  /\ (Rv0 = "" \/ FlushRec(fl).rv[Rv0] = Ev.rv)
  /\ IF Ev.ok = 1 THEN Len(out') = Len(out) + 1 /\ InumOK ELSE err' /\ out' = out

Logged ==
  /\ t < Len(TraceLog)
  /\ t' = t + 1
  /\ \/ /\ Ev.a = "Begin" /\ t = 0
        /\ Ev.waits = (IF Waits THEN 1 ELSE 0) /\ Ev.rvc = Cardinality(F \cap HasRowVal)
        /\ (Ev.skipflag = 1 /\ Ev.defer = 1) = skip
        /\ UNCHANGED vars
     \/ Ev.a = "Key" /\ Key /\ ended' = (Ev.ended = 1) /\ (Ev.first = 1) = (i = 1)
     \/ Ev.a = "Add" /\ Add /\ AddOutcome
     \/ Ev.a = "Put" /\ Put /\ PutOutcome
     \/ Ev.a = "FlushEnd" /\ FlushEnd /\ err = (Ev.err = 1)
     \/ Ev.a = "End" /\ End
     \/ Ev.a = "Clear" /\ Clear /\ (files > 0) = (Ev.spill = 1)
TSpec == TInit /\ [][Logged]_TVars

TraceNotDone == t < Len(TraceLog)

\* the runs' inputs: tw (p, k) sorted, 12 rows in p = 1 and 3 in p = 2; s1.b + 1 for the SKIP_SORT run
TwRows == << [p |-> 1, k |-> 1], [p |-> 1, k |-> 1], [p |-> 1, k |-> 2], [p |-> 1, k |-> 2], [p |-> 1, k |-> 2],
             [p |-> 1, k |-> 3], [p |-> 1, k |-> 3], [p |-> 1, k |-> 4], [p |-> 1, k |-> 4], [p |-> 1, k |-> 4],
             [p |-> 1, k |-> 5], [p |-> 1, k |-> 5], [p |-> 2, k |-> 1], [p |-> 2, k |-> 1], [p |-> 2, k |-> 2] >>
S1Rows == [j \in 1..12 |-> [p |-> 1, k |-> (j - 1) \div 4 + 1]]
\* row_number () + max (s) over (partition by p): MAX is an aggregate over the partition, as CP
SpillIn == [rows |-> TwRows, F |-> {"RN", "CP"}, skip |-> FALSE, rv0 |-> "RN"]
NtPrIn == [rows |-> TwRows, F |-> {"NT", "PR"}, skip |-> FALSE, rv0 |-> "PR"]
CoKeyIn == [rows |-> TwRows, F |-> {"CO", "RK"}, skip |-> FALSE, rv0 |-> "RK"]
\* the build orders the functions dense_rank first: row_vals[0] is DENSE_RANK's
ImmediateIn == [rows |-> TwRows, F |-> {"RN", "DR"}, skip |-> FALSE, rv0 |-> "DR"]
\* sum (c) over (order by b): a cumulative aggregate over the sort key, as CO with one partition
SkipIn == [rows |-> S1Rows, F |-> {"CO"}, skip |-> TRUE, rv0 |-> ""]
=============================================================================
