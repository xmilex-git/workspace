---------------------------- MODULE PartWalkTrace ----------------------------
(* Trace validation: is a run of the instrumented head build (60058202c + TLATRACE lines in
   query_executor.c) a behavior of PartWalk? Each logged event must be the action it names with the
   logged outcome; RowEnd and MemoDrop are not logged and may happen in between. The run's input
   (join kind, rows per partition, outer keys, per-row pruning) is fixed by TraceIn. *)
EXTENDS PartWalk, PartWalkTraceData, Sequences

CONSTANTS TraceLog, TraceIn
VARIABLE i
TVars == <<vars, i>>

TInit ==
  /\ Init
  /\ kind = TraceIn.kind /\ prune = TraceIn.prune /\ data = TraceIn.data /\ outer = TraceIn.outer
  /\ home = TraceIn.home /\ memoOn = TraceIn.memoOn
  /\ i = 0

Ev == TraceLog[i + 1]
Has(f) == f \in DOMAIN Ev
LoopOutcome ==
  \* a row (res = its partition) or the NULL row (res = 0); S_END lines carry end=1 instead
  /\ Has("res") => /\ Ev.res = 0 => (nf' /\ ~nf)
                   /\ Ev.res > 0 => (cur = Ev.res /\ pos' /\ ~pos)
  /\ Has("nxt") => cur' = Ev.nxt /\ pc' = "loop"
  /\ Has("last") => sf' /\ pc' = (IF kind = "anti" THEN "loop" ELSE "rowend")
  /\ Has("reent") => pc' = "rowend" /\ cur' = cur
Logged ==
  /\ i < Len(TraceLog)
  /\ i' = i + 1
  /\ \/ Ev.a = "Open" /\ i = 0 /\ cur = Ev.cur /\ UNCHANGED vars
     \/ Ev.a = "Open" /\ i > 0 /\ Reopen /\ cur' = Ev.cur
     \* the first outer row is rewound twice before it enters the inner; the second rewind changes nothing
     \/ Ev.a = "Reset" /\ (Reset \/ (pc = "enter" /\ UNCHANGED vars))
     \/ Ev.a = "Enter" /\ Enter /\ (hit' <=> Ev.hit = 1)
     \/ Ev.a = "OpenRow" /\ OpenRow /\ cur' = Ev.first
     \/ Ev.a = "Loop" /\ Loop /\ LoopOutcome
Hidden == (RowEnd \/ MemoDrop) /\ UNCHANGED i
TSpec == TInit /\ [][Logged \/ Hidden]_TVars

TraceNotDone == i < Len(TraceLog)

\* the runs' inputs (traces/README in MAP.md): keys 1 -> 1 and 10 -> 2 over pr3 (range p0 < 3, p1 < 6, p2 < 9;
\* rows k = 1 in p0 and k = 7 in p2), keys 5 -> 1 and 9 -> 2 over pn3.c (hash on k; c = 6 in p0, c = 5, 5, 7 in p2)
Pr3 == << {1}, {}, {} >>
\* home: key 1 lives in p0, key 10 in no partition; every run's third row is a memo hit (memoOn)
Pr3Home == << 1, 0 >>
LeftIn == [kind |-> "left", prune |-> TRUE, data |-> Pr3, outer |-> << 1, 2, 1 >>, home |-> Pr3Home, memoOn |-> TRUE]
AntiIn == [kind |-> "anti", prune |-> TRUE, data |-> Pr3, outer |-> << 1, 2, 1 >>, home |-> Pr3Home, memoOn |-> TRUE]
ReopenIn == [kind |-> "inner", prune |-> TRUE, data |-> Pr3, outer |-> << 1, 2, 1 >>, home |-> Pr3Home, memoOn |-> TRUE]
SemiIn == [kind |-> "semi", prune |-> FALSE, data |-> << {}, {}, {1} >>, outer |-> << 1, 2, 1 >>, home |-> << 3, 0 >>,
           memoOn |-> TRUE]
=============================================================================
