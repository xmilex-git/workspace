------------------------- MODULE PxSysopGateTrace -------------------------
(* Trace validation: is a run of the instrumented head build (316431fba + TLATRACE lines in
   log_manager.c, critical_section.c, px_parallel.cpp, px_worker_manager.cpp, pl_executor.cpp)
   a behavior of PxSysopGate? Each event must be the action it names with the logged outcome.
   Join is an observation of worker_manager::wait_workers returning: the thread holds no level
   it took while its workers ran (A1). Q's end is not logged (Hidden). The run's task tree is
   fixed by Par (Spawn events), Thr by the task ids. *)
EXTENDS PxSysopGate, PxSysopGateTraceData, Sequences

CONSTANT TraceLog
VARIABLE i
TVars == <<vars, i>>

\* A run is cut where no task runs and nothing is held; Root's decision before the cut may still
\* allow pushes (worker_manager reuses its reservation for a second round after wait_workers).
TInit ==
  /\ \E b \in BOOLEAN : spawnOK = [t \in Thr |-> IF t = Root THEN b ELSE FALSE]
  /\ pc = [t \in Thr |-> IF t = Root THEN "ready" ELSE "idle"]
  /\ owner = NoThr /\ cnt = 0 /\ depth = 0
  /\ h = [t \in Thr |-> 0] /\ late = [t \in Thr |-> 0] /\ ops = [t \in Thr |-> 0]
  /\ decn = [t \in Thr |-> "none"] /\ reason = [t \in Thr |-> "none"]
  /\ decH = [t \in Thr |-> 0] /\ reent = FALSE
  /\ i = 0

Ev == TraceLog[i + 1]
P == Ev.p

\* Want and Acq of one thread back to back: the log records the lock taken, not the wait
AcqNow(t) ==
  /\ pc[t] = "ready" /\ ops[t] < OpsMax(t) /\ Lockable(t)
  /\ AcqEffect(t)
  /\ pc' = [pc EXCEPT ![t] = "inc"]
  /\ ops' = [ops EXCEPT ![t] = @ + 1]

Logged ==
  /\ i < Len(TraceLog)
  /\ i' = i + 1
  /\ \/ Ev.a = "Acq" /\ AcqNow(P) /\ cnt' = Ev.cnt
        /\ (Ev.how = "first" => owner = NoThr)
        /\ (Ev.how = "self" => owner = P)
        /\ (Ev.how = "pl" => owner \in Involved /\ owner # P)
     \/ Ev.a = "Inc" /\ Inc(P) /\ depth' = Ev.depth
     \/ Ev.a = "Dec" /\ Dec(P) /\ depth' = Ev.depth
     \/ Ev.a = "Rel" /\ Rel(P) /\ cnt' = Ev.cnt
     \/ Ev.a = "D1" /\ D1(P) /\ ((depth > 0) <=> (Ev.under = 1))
     \/ Ev.a = "D2" /\ D2(P) /\ reason'[P] = Ev.reason /\ decn'[P] = Ev.dec
     \/ Ev.a = "Spawn" /\ Spawn(P, Ev.c)
     \/ Ev.a = "End" /\ Finish(P)
     \/ Ev.a = "Join" /\ pc[P] = "ready" /\ late[P] = 0 /\ UNCHANGED vars
     \/ Ev.a = "SpCall" /\ P = Root /\ SpCall
     \/ Ev.a = "SpRet" /\ P = Root /\ SpRet
Hidden == Finish(Q) /\ UNCHANGED i
TSpec == TInit /\ [][Logged \/ Hidden]_TVars

TraceNotDone == i < Len(TraceLog)
=============================================================================
