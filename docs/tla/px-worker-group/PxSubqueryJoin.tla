---------------------------- MODULE PxSubqueryJoin ----------------------------
(* The parallel subquery executor's job queue, join and worker budget (src/query/parallel/
   px_query_execute/, px_thread_safe_queue.cpp, px_worker_manager*.cpp) at CUBRID develop
   41ca53ce7, and their redesign (MAP.md "Decisions").

   One statement. The root executor "R" (attached to the first node with two or more parallel
   aptrs) and every nested executor own an ordered list of jobs (TreeJobs): the first is its m_job,
   run by the thread that calls its run_jobs; the rest go to the one queue the statement shares.
   A job in Nested runs a nested executor "x<job>" during its execution. Tree picks the shape:
     "base"   R: 1, 2;  2 runs x2: 21, 22                    (the nested executor on a worker)
     "nestM"  R: 1, 2;  1 runs x1: 11, 12                    (the nested executor on the main thread)
     "wide"   R: 1, 2, 3;  2 runs x2: 21, 22, 23
     "bin2"   R: 1, 2;  x1: 11, 12;  x2: 21, 22
     "bin3"   bin2 one level deeper: x11 .. x22 own 111 .. 222 (14 jobs, 7 executors)

   Mode picks the wait of run_jobs after its own job:
     "spin"         develop: poll the count under join_context::m_mutex and try_pop until the
                    count is 0 (px_query_executor.cpp:146-170), then join_jobs.
     "exitOnEmpty"  oracle-gap#20 direction 2: try_pop until it fails, then join_jobs's cv wait.
     "event"        D2/D3: an atomic count per executor and one wake event per statement, owned
                    by the root executor; a waiter helps until the queue is empty, then sleeps on
                    the event; a push and the end of an executor's last job wake it.

   Workers are the statement's subquery worker threads. Budget picks where workers come from:
     "pool"   develop: the subquery workers and every parallel operator inside a job reserve from
              the server pool on their own (worker_manager::try_reserve_workers).
     "group"  D13: the root takes a group of B units once; subquery workers and operators take
              units only from the group.
   SqPolicy picks how subquery workers run:
     "fixed"    all Workers start when the root's run_jobs starts and keep their unit to the end.
     "elastic"  a push starts an idle worker when the group has a unit; a worker that finds the
                queue empty gives its unit back and ends (after a re-check). *)
EXTENDS Naturals, Sequences, FiniteSets, TLC

CONSTANTS Mode,        \* "spin" | "exitOnEmpty" | "event"
          Mutant,      \* "none" | see MAP.md "Mutants"
          Workers,     \* the statement's subquery worker threads
          Tree,        \* "base" | "nestM" | "wide" | "bin2" | "bin3"
          WorkFail,    \* BOOLEAN: a leaf job may fail (raises the statement interrupt)
          InlineFail,  \* BOOLEAN: a nested job may fail after pushing, before its run_jobs
          MaxSpur,     \* failed try_pop on a non-empty queue + spurious condvar wakeups, in total
          WakeAlways,  \* BOOLEAN ("event"): a waker always locks and notifies (D5)
          Budget,      \* "pool" | "group"
          B,           \* the statement's worker budget (group size; develop: the parallelism P)
          Want,        \* workers a leaf job's parallel operator asks for (0: no operator)
          SqPolicy,    \* "fixed" | "elastic"
          Ghosts       \* BOOLEAN: keep the ranBy ghost (witnesses); FALSE on big trees
CONSTANTS Depth        \* the stack bound for IndInv: 3 + 2 * Cardinality(Nested) (5, 7 or 15)

\* apalache-type: Mode Str
\* apalache-type: Mutant Str
\* apalache-type: Workers Set(Str)
\* apalache-type: Tree Str
\* apalache-type: WorkFail Bool
\* apalache-type: InlineFail Bool
\* apalache-type: MaxSpur Int
\* apalache-type: WakeAlways Bool
\* apalache-type: Budget Str
\* apalache-type: B Int
\* apalache-type: Want Int
\* apalache-type: SqPolicy Str
\* apalache-type: Ghosts Bool
\* apalache-type: Depth Int
\* apalache-type: stack Str -> Seq({k: Str, id: Str, pc: Str, todo: Set(Str)})
\* apalache-type: queue Set(Str)
\* apalache-type: pending Str -> Int
\* apalache-type: freed Str -> Bool
\* apalache-type: qfreed Bool
\* apalache-type: interrupt Bool
\* apalache-type: completed Bool
\* apalache-type: alive Str -> Bool
\* apalache-type: hold Str -> Bool
\* apalache-type: ptask Int
\* apalache-type: asleep Str -> Str
\* apalache-type: qheld Str
\* apalache-type: epoch Int
\* apalache-type: sleepers Int
\* apalache-type: e0 Str -> Int
\* apalache-type: grp Int
\* apalache-type: opHeld Str -> Int
\* apalache-type: opSum Int
\* apalache-type: poolTake Int
\* apalache-type: runs Str -> Int
\* apalache-type: ranBy Str -> Str
\* apalache-type: ended Set(Str)
\* apalache-type: returned Set(Str)
\* apalache-type: uaf Bool
\* apalache-type: idle Str -> Int
\* apalache-type: spur Int

Main == "M"
Threads == {Main} \cup Workers
None == "none"

\* the jobs an executor adds, its own job (m_job) and the executor a job runs (tables, no string
\* concatenation and no CHOOSE, so Apalache reads them)
JobsOf(e) ==
  IF e = "R" THEN (IF Tree = "wide" THEN {"1", "2", "3"} ELSE {"1", "2"})
  ELSE IF e = "x2" /\ Tree = "wide" THEN {"21", "22", "23"}
  ELSE IF e = "x1" THEN {"11", "12"}     ELSE IF e = "x2" THEN {"21", "22"}
  ELSE IF e = "x11" THEN {"111", "112"} ELSE IF e = "x12" THEN {"121", "122"}
  ELSE IF e = "x21" THEN {"211", "212"} ELSE {"221", "222"}
OwnJob(e) ==
  IF e = "R" THEN "1" ELSE IF e = "x1" THEN "11" ELSE IF e = "x2" THEN "21"
  ELSE IF e = "x11" THEN "111" ELSE IF e = "x12" THEN "121" ELSE IF e = "x21" THEN "211" ELSE "221"
Nested ==
  IF Tree = "base" THEN {"2"} ELSE IF Tree = "nestM" THEN {"1"} ELSE IF Tree = "wide" THEN {"2"}
  ELSE IF Tree = "bin2" THEN {"1", "2"} ELSE {"1", "2", "11", "12", "21", "22"}
ExecOf(j) ==
  IF j = "1" THEN "x1" ELSE IF j = "2" THEN "x2" ELSE IF j = "11" THEN "x11"
  ELSE IF j = "12" THEN "x12" ELSE IF j = "21" THEN "x21" ELSE "x22"
Execs == {"R"} \cup {ExecOf(j) : j \in Nested}
Jobs == UNION {JobsOf(e) : e \in Execs}
Owner(j) ==
  IF j \in {"1", "2", "3"} THEN "R" ELSE IF j \in {"11", "12"} THEN "x1"
  ELSE IF j \in {"21", "22", "23"} THEN "x2" ELSE IF j \in {"111", "112"} THEN "x11"
  ELSE IF j \in {"121", "122"} THEN "x12" ELSE IF j \in {"211", "212"} THEN "x21" ELSE "x22"
QJobs(e) == JobsOf(e) \ {OwnJob(e)}
Child(j) == IF j \in Nested THEN ExecOf(j) ELSE None
Leaf(j) == j \notin Nested
Units(r) == IF Budget = "group" THEN r ELSE 0

\* @type: (Str, Str, Str) => {k: Str, id: Str, pc: Str, todo: Set(Str)};
Frame(k, id, pc) == [k |-> k, id |-> id, pc |-> pc, todo |-> {}]

VARIABLES stack,     \* per thread: the call frames (root, task, job, wait)
          queue,     \* jobs pushed and not popped
          pending,   \* join_context::m_running_jobs per executor
          freed,     \* executor deleted (qexec_clear_xasl_for_parallel_aptr)
          qfreed,    \* the statement's queue, wake event and group deleted (root executor destroyed)
          interrupt, \* the statement's px interrupt (root executor's m_interrupt)
          completed, \* push_last done (m_push_completed)
          alive,     \* worker task running on the thread
          hold,      \* the worker holds a unit (group) / a reservation (pool)
          ptask,     \* elastic: subquery tasks pushed to the server's worker pool, not yet on a thread (each holds a unit)
          asleep,    \* "no" | "q" (queue m_not_empty) | "ev" (statement event) | e (join cv of e)
          qheld,     \* queue m_mutex held across pop_slow's check and its wait
          epoch,     \* statement event epoch
          sleepers,  \* threads registered to sleep on the event (WakeAlways = FALSE)
          e0,        \* epoch a thread read before its re-check
          grp,       \* free units of the statement's group
          opHeld,    \* units (group) or workers (pool) a leaf job's operator holds
          opSum,     \* the sum of opHeld
          poolTake,  \* ghost: reservations the statement made from the server pool after the root's start
          runs,      \* ghost: times each job started
          ranBy,     \* ghost: thread that ran each job (Ghosts only)
          ended,     \* ghost: jobs that ended (decremented their owner's count)
          returned,  \* ghost: executors whose run_jobs returned
          uaf,       \* ghost: a freed executor, queue, event or group was touched
          idle,      \* ghost: failed try_pop since the thread's last pop, job end, wake, queue change or epoch move it saw
          spur       \* ghost: spurious failures used

vars == <<stack, queue, pending, freed, qfreed, interrupt, completed, alive, hold, ptask, asleep, qheld,
          epoch, sleepers, e0, grp, opHeld, opSum, poolTake, runs, ranBy, ended, returned, uaf, idle, spur>>

Init ==
  /\ stack = [t \in Threads |-> IF t = Main THEN <<Frame("root", "R", "grp")>>
                                            ELSE <<Frame("task", None, "idle")>>]
  /\ queue = {}
  /\ pending = [e \in Execs |-> 0]
  /\ freed = [e \in Execs |-> FALSE]
  /\ qfreed = FALSE
  /\ interrupt = FALSE
  /\ completed = FALSE
  /\ alive = [w \in Workers |-> FALSE]
  /\ hold = [w \in Workers |-> FALSE]
  /\ ptask = 0
  /\ asleep = [t \in Threads |-> "no"]
  /\ qheld = None
  /\ epoch = 0
  /\ sleepers = 0
  /\ e0 = [t \in Threads |-> 0]
  /\ grp = 0
  /\ opHeld = [j \in Jobs |-> 0]
  /\ opSum = 0
  /\ poolTake = 0
  /\ runs = [j \in Jobs |-> 0]
  /\ ranBy = [j \in Jobs |-> None]
  /\ ended = {}
  /\ returned = {}
  /\ uaf = FALSE
  /\ idle = [t \in Threads |-> 0]
  /\ spur = 0

----------------------------------------------------------------------------
Top(t) == stack[t][Len(stack[t])]
At(t, k, pc) == Len(stack[t]) > 0 /\ asleep[t] = "no" /\ Top(t).k = k /\ Top(t).pc = pc
SetPc(t, pc) == stack' = [stack EXCEPT ![t][Len(stack[t])].pc = pc]
Call(t, pcAfter, f) == stack' = [stack EXCEPT ![t] = Append([@ EXCEPT ![Len(@)].pc = pcAfter], f)]
Ret(t) == stack' = [stack EXCEPT ![t] = SubSeq(@, 1, Len(@) - 1)]
AddTo(t) == IF Top(t).k = "root" THEN "R" ELSE Child(Top(t).id)
Touch(e) == uaf' = (uaf \/ freed[e])
TouchQ == uaf' = (uaf \/ qfreed)
ZeroIdle == idle' = [s \in Threads |-> 0]
IdleWorkers == {w \in Workers : ~alive[w]}

StartJob(t, j, pcAfter) ==
  /\ Call(t, pcAfter, Frame("job", j, "start"))
  /\ runs' = [runs EXCEPT ![j] = @ + 1]
  /\ ranBy' = IF Ghosts THEN [ranBy EXCEPT ![j] = t] ELSE ranBy

\* notify_all on the statement event (Mutant "wakeOne": one sleeper)
EvWakeAll ==
  IF Mutant = "wakeOne"
  THEN \/ /\ \A s \in Threads : asleep[s] # "ev"
          /\ UNCHANGED <<asleep, idle>>
       \/ \E s \in Threads :
            /\ asleep[s] = "ev"
            /\ asleep' = [asleep EXCEPT ![s] = "no"]
            /\ idle' = [idle EXCEPT ![s] = 0]
  ELSE /\ asleep' = [s \in Threads |-> IF asleep[s] = "ev" THEN "no" ELSE asleep[s]]
       /\ idle' = [s \in Threads |-> IF asleep[s] = "ev" THEN 0 ELSE idle[s]]

\* notify_one on the queue's m_not_empty from the fast push, without the queue mutex
QNotifyOne ==
  \/ /\ \A s \in Threads : asleep[s] # "q"
     /\ UNCHANGED asleep
  \/ \E s \in Threads :
       /\ asleep[s] = "q"
       /\ asleep' = [asleep EXCEPT ![s] = "no"]

(* Elastic start of one idle worker on a unit of the group (D14 option "elastic"): one CAS on the
   group count, then the task push. Nothing to start when the queue is empty, the group has no
   unit, or every worker runs. *)
\* a running worker about to pop takes a queued job next; one that gave its unit back or decided
\* to end is not free (code: a free-worker counter it decrements before the exit re-check)
FreeWorkers == {w \in Workers : alive[w] /\ Top(w).k = "task" /\ Top(w).pc \in {"loop", "pop"}}
CanSpawn == SqPolicy = "elastic" /\ grp > 0 /\ ~interrupt /\ ~completed
            /\ Cardinality(queue) > Cardinality(FreeWorkers) + ptask
Spawn ==
  IF CanSpawn
  THEN grp' = grp - 1 /\ ptask' = ptask + 1
  ELSE UNCHANGED <<grp, ptask>>

----------------------------------------------------------------------------
(* The root's start: develop reserves the subquery worker from the server pool
   (query_executor.c:22402); D13 takes the statement's group of B units there once. *)
RootGroup(t) ==
  /\ At(t, "root", "grp")
  /\ grp' = IF Budget = "group" THEN B ELSE 0
  /\ SetPc(t, "own")
  /\ UNCHANGED <<queue, pending, freed, qfreed, interrupt, completed, alive, hold, ptask, asleep, qheld,
                 epoch, sleepers, e0, opHeld, opSum, poolTake, runs, ranBy, ended, returned, uaf, idle, spur>>

(* Adding jobs: query_executor::add_job from qexec_execute_mainblock_internal's aptr loop
   (query_executor.c:22423). The first job is m_job; the rest are pushed, then counted. *)
AddOwn(t) ==
  /\ \E k \in {"root", "job"} : At(t, k, "own")
  /\ LET e == AddTo(t) IN
       /\ pending' = [pending EXCEPT ![e] = @ + 1]
       /\ Touch(e)
       /\ stack' = [stack EXCEPT ![t][Len(stack[t])].pc = "add",
                                 ![t][Len(stack[t])].todo = QJobs(e)]
  /\ UNCHANGED <<queue, freed, qfreed, interrupt, completed, alive, hold, ptask, asleep, qheld,
                 epoch, sleepers, e0, grp, opHeld, opSum, poolTake, runs, ranBy, ended, returned, idle, spur>>

AddPush(t) ==
  /\ \E k \in {"root", "job"} : At(t, k, "add")
  /\ Top(t).todo # {}
  /\ LET j == CHOOSE x \in Top(t).todo : TRUE IN
       /\ queue' = queue \cup {j}
       /\ TouchQ
       /\ ZeroIdle
       /\ stack' = [stack EXCEPT ![t][Len(stack[t])].pc = "cnt",
                                 ![t][Len(stack[t])].todo = @ \ {j}]
       /\ IF Mode = "event" THEN UNCHANGED asleep ELSE QNotifyOne
  /\ UNCHANGED <<pending, freed, qfreed, interrupt, completed, alive, hold, ptask, qheld,
                 epoch, sleepers, e0, grp, opHeld, opSum, poolTake, runs, ranBy, ended, returned, spur>>

AfterCount == IF Mode = "event" /\ Mutant # "noPushWake" THEN "wk"
              ELSE IF SqPolicy = "elastic" THEN "spn" ELSE "add"
AfterWake == IF SqPolicy = "elastic" THEN "spn" ELSE "add"

AddCount(t) ==
  /\ \E k \in {"root", "job"} : At(t, k, "cnt")
  /\ LET e == AddTo(t) IN
       /\ pending' = [pending EXCEPT ![e] = @ + 1]
       /\ Touch(e)
  /\ SetPc(t, AfterCount)
  /\ UNCHANGED <<queue, freed, qfreed, interrupt, completed, alive, hold, ptask, asleep, qheld,
                 epoch, sleepers, e0, grp, opHeld, opSum, poolTake, runs, ranBy, ended, returned, idle, spur>>

(* The event wake: "wk" bumps the epoch (WakeAlways: and notifies under the event mutex in the
   same critical section); "wk2" notifies only when a sleeper registered. *)
AddWake(t) ==
  /\ \E k \in {"root", "job"} : At(t, k, "wk")
  /\ epoch' = epoch + 1
  /\ TouchQ
  /\ IF WakeAlways
     THEN EvWakeAll /\ SetPc(t, AfterWake)
     ELSE UNCHANGED <<asleep, idle>> /\ SetPc(t, "wk2")
  /\ UNCHANGED <<queue, pending, freed, qfreed, interrupt, completed, alive, hold, ptask, qheld,
                 sleepers, e0, grp, opHeld, opSum, poolTake, runs, ranBy, ended, returned, spur>>

AddWake2(t) ==
  /\ \E k \in {"root", "job"} : At(t, k, "wk2")
  /\ TouchQ
  /\ IF sleepers > 0 THEN EvWakeAll ELSE UNCHANGED <<asleep, idle>>
  /\ SetPc(t, AfterWake)
  /\ UNCHANGED <<queue, pending, freed, qfreed, interrupt, completed, alive, hold, ptask, qheld,
                 epoch, sleepers, e0, grp, opHeld, opSum, poolTake, runs, ranBy, ended, returned, spur>>

\* elastic: after a push, start a worker if the group has a unit (D14 option)
AddSpawn(t) ==
  /\ \E k \in {"root", "job"} : At(t, k, "spn")
  /\ TouchQ
  /\ Spawn
  /\ SetPc(t, "add")
  /\ UNCHANGED <<queue, pending, freed, qfreed, interrupt, completed, alive, hold, asleep, qheld,
                 epoch, sleepers, e0, opHeld, opSum, poolTake, runs, ranBy, ended, returned, idle, spur>>

(* All jobs added: run_jobs. The root starts the worker tasks first (px_query_executor.cpp:133):
   develop one task on the worker it reserved; "fixed" every worker on a unit of the group.
   InlineFail: a sibling aptr run inline (XASL_NO_PARALLEL_SUBQUERY) fails after the pushes;
   GOTO_EXIT_ON_ERROR skips run_jobs (query_executor.c:22427-22436, 23174). *)
FixedStart ==
  IF SqPolicy = "fixed"
  THEN /\ alive' = [w \in Workers |-> TRUE]
       /\ hold' = [w \in Workers |-> TRUE]
       /\ UNCHANGED ptask
       /\ grp' = grp - Units(Cardinality(Workers))
  ELSE UNCHANGED <<alive, hold, ptask, grp>>

AddDone(t) ==
  /\ \E k \in {"root", "job"} : At(t, k, "add")
  /\ Top(t).todo = {}
  /\ IF Top(t).k = "root"
     THEN /\ FixedStart
          /\ Call(t, "end", Frame("wait", "R", "own"))
          /\ UNCHANGED interrupt
     ELSE /\ UNCHANGED <<alive, hold, ptask, grp>>
          /\ \/ /\ Call(t, "clear", Frame("wait", AddTo(t), "own"))
                /\ UNCHANGED interrupt
             \/ /\ InlineFail
                /\ interrupt' = TRUE
                /\ SetPc(t, "clear")
  /\ UNCHANGED <<queue, pending, freed, qfreed, completed, asleep, qheld,
                 epoch, sleepers, e0, opHeld, opSum, poolTake, runs, ranBy, ended, returned, uaf, idle, spur>>

----------------------------------------------------------------------------
(* A job: execute_job_internal (px_query_task.cpp:73). A leaf's work may open a parallel
   operator (scan, hash join, sort: try_reserve_workers at e.g. px_scan.cpp:442) that holds
   workers until it ends. *)

JobStart(t) ==
  /\ At(t, "job", "start")
  /\ SetPc(t, IF interrupt THEN "fin"
              ELSE IF ~Leaf(Top(t).id) THEN "own"
              ELSE IF Want > 0 THEN "rsv" ELSE "work")
  /\ UNCHANGED <<queue, pending, freed, qfreed, interrupt, completed, alive, hold, ptask, asleep, qheld,
                 epoch, sleepers, e0, grp, opHeld, opSum, poolTake, runs, ranBy, ended, returned, uaf, idle, spur>>

(* The operator's reservation: "pool" takes Want from the server pool (assumed to have them: the
   worst case for the statement's total); "group" takes min(Want, free units) from the group by one
   CAS, or nothing when fewer than 2 are free (try_reserve_workers' min_degree, the operator then
   runs serially). *)
JobReserve(t) ==
  /\ At(t, "job", "rsv")
  /\ LET j == Top(t).id
         r == IF Budget = "pool" THEN Want
              ELSE IF (IF Want < grp THEN Want ELSE grp) >= 2 THEN (IF Want < grp THEN Want ELSE grp) ELSE 0 IN
       /\ opHeld' = [opHeld EXCEPT ![j] = r]
       /\ opSum' = opSum + r
       /\ grp' = grp - Units(r)
       /\ poolTake' = IF Budget = "pool" THEN poolTake + 1 ELSE poolTake
       /\ uaf' = (uaf \/ (Budget = "group" /\ qfreed))
  /\ SetPc(t, "work")
  /\ UNCHANGED <<queue, pending, freed, qfreed, interrupt, completed, alive, hold, ptask, asleep, qheld,
                 epoch, sleepers, e0, runs, ranBy, ended, returned, idle, spur>>

JobWork(t) ==
  /\ At(t, "job", "work")
  /\ \/ UNCHANGED interrupt
     \/ WorkFail /\ Leaf(Top(t).id) /\ interrupt' = TRUE
  /\ SetPc(t, IF opHeld[Top(t).id] > 0 THEN "orel" ELSE IF Leaf(Top(t).id) THEN "fin" ELSE "clear")
  /\ UNCHANGED <<queue, pending, freed, qfreed, completed, alive, hold, ptask, asleep, qheld,
                 epoch, sleepers, e0, grp, opHeld, opSum, poolTake, runs, ranBy, ended, returned, uaf, idle, spur>>

\* the operator ends: its workers go back to the group (or the pool); elastic then offers the unit to the queue
JobOpRelease(t) ==
  /\ At(t, "job", "orel")
  /\ grp' = grp + Units(opHeld[Top(t).id])
  /\ opHeld' = [opHeld EXCEPT ![Top(t).id] = 0]
  /\ opSum' = opSum - opHeld[Top(t).id]
  /\ uaf' = (uaf \/ (Budget = "group" /\ qfreed))
  /\ SetPc(t, IF SqPolicy = "elastic" /\ Mutant # "noReleaseSpawn" THEN "ospn" ELSE "fin")
  /\ UNCHANGED <<queue, pending, freed, qfreed, interrupt, completed, alive, hold, ptask, asleep, qheld,
                 epoch, sleepers, e0, poolTake, runs, ranBy, ended, returned, idle, spur>>

\* the released units start as many workers as the queue can use, one CAS each
JobOpSpawn(t) ==
  /\ At(t, "job", "ospn")
  /\ TouchQ
  /\ Spawn
  /\ SetPc(t, IF CanSpawn THEN "ospn" ELSE "fin")
  /\ UNCHANGED <<queue, pending, freed, qfreed, interrupt, completed, alive, hold, asleep, qheld,
                 epoch, sleepers, e0, opHeld, opSum, poolTake, runs, ranBy, ended, returned, idle, spur>>

\* qexec_clear_xasl_for_parallel_aptr (px_query_task.cpp:196) deletes the job's px_executor (query_executor.c:2615)
JobClear(t) ==
  /\ At(t, "job", "clear")
  /\ freed' = [freed EXCEPT ![Child(Top(t).id)] = TRUE]
  /\ SetPc(t, "fin")
  /\ UNCHANGED <<queue, pending, qfreed, interrupt, completed, alive, hold, ptask, asleep, qheld,
                 epoch, sleepers, e0, grp, opHeld, opSum, poolTake, runs, ranBy, ended, returned, uaf, idle, spur>>

(* sub_running_jobs: develop decrements and notifies the owner's join cv under its m_mutex (one
   step); "event" decrements the atomic count, and the job that took it to 0 wakes the statement
   event in a later step. *)
JobFin(t) ==
  /\ At(t, "job", "fin")
  /\ LET j == Top(t).id
         o == Owner(j)
         n == pending[o] - 1 IN
       /\ pending' = [pending EXCEPT ![o] = n]
       /\ ended' = ended \cup {j}
       /\ idle' = [idle EXCEPT ![t] = 0]
       /\ Touch(o)
       /\ IF Mode = "event"
          THEN /\ IF n = 0 THEN SetPc(t, "fwk") ELSE Ret(t)
               /\ UNCHANGED asleep
          ELSE /\ Ret(t)
               /\ asleep' = IF n = 0 THEN [s \in Threads |-> IF asleep[s] = o THEN "no" ELSE asleep[s]]
                            ELSE asleep
  /\ UNCHANGED <<queue, freed, qfreed, interrupt, completed, alive, hold, ptask, qheld,
                 epoch, sleepers, e0, grp, opHeld, opSum, poolTake, runs, ranBy, returned, spur>>

\* Mutant "wakeViaExec": the wake reaches the event through the owner executor (or the event lives in it)
JobWake(t) ==
  /\ At(t, "job", "fwk")
  /\ epoch' = epoch + 1
  /\ uaf' = (uaf \/ qfreed \/ (Mutant = "wakeViaExec" /\ freed[Owner(Top(t).id)]))
  /\ IF WakeAlways
     THEN EvWakeAll /\ Ret(t)
     ELSE UNCHANGED <<asleep, idle>> /\ SetPc(t, "fwk2")
  /\ UNCHANGED <<queue, pending, freed, qfreed, interrupt, completed, alive, hold, ptask, qheld,
                 sleepers, e0, grp, opHeld, opSum, poolTake, runs, ranBy, ended, returned, spur>>

JobWake2(t) ==
  /\ At(t, "job", "fwk2")
  /\ TouchQ
  /\ IF sleepers > 0 THEN EvWakeAll ELSE UNCHANGED <<asleep, idle>>
  /\ Ret(t)
  /\ UNCHANGED <<queue, pending, freed, qfreed, interrupt, completed, alive, hold, ptask, qheld,
                 epoch, sleepers, e0, grp, opHeld, opSum, poolTake, runs, ranBy, ended, returned, spur>>

----------------------------------------------------------------------------
(* try_pop (try_pop_fast, px_thread_safe_queue.cpp:221): fails on an empty queue, and may fail on
   a non-empty one (a lost CAS against another popper, compare_exchange_weak) within MaxSpur. *)
TryPop(t, pcOk, pcFail) ==
  /\ TouchQ
  /\ \/ \E j \in queue :
          /\ queue' = IF Mutant = "popKeeps" THEN queue ELSE queue \ {j}
          /\ StartJob(t, j, pcOk)
          /\ ZeroIdle
          /\ UNCHANGED spur
     \/ /\ queue = {}
        /\ SetPc(t, pcFail)
        /\ idle' = [idle EXCEPT ![t] = @ + 1]
        /\ UNCHANGED <<queue, runs, ranBy, spur>>
     \/ /\ queue # {} /\ spur < MaxSpur
        /\ spur' = spur + 1
        /\ SetPc(t, pcFail)
        /\ idle' = [idle EXCEPT ![t] = @ + 1]
        /\ UNCHANGED <<queue, runs, ranBy>>

----------------------------------------------------------------------------
(* run_jobs (px_query_executor.cpp:120): the own job, then the wait. *)

WaitOwn(t) ==
  /\ At(t, "wait", "own")
  /\ StartJob(t, OwnJob(Top(t).id), "loop")
  /\ UNCHANGED <<queue, pending, freed, qfreed, interrupt, completed, alive, hold, ptask, asleep, qheld,
                 epoch, sleepers, e0, grp, opHeld, opSum, poolTake, ended, returned, uaf, idle, spur>>

WaitReturn(t) ==
  /\ returned' = returned \cup {Top(t).id}
  /\ Ret(t)

SpinCheck(t) ==
  /\ Mode = "spin"
  /\ At(t, "wait", "loop")
  /\ Touch(Top(t).id)
  /\ SetPc(t, IF pending[Top(t).id] = 0 THEN "join" ELSE "pop")
  /\ UNCHANGED <<queue, pending, freed, qfreed, interrupt, completed, alive, hold, ptask, asleep, qheld,
                 epoch, sleepers, e0, grp, opHeld, opSum, poolTake, runs, ranBy, ended, returned, idle, spur>>

SpinPop(t) ==
  /\ Mode = "spin"
  /\ At(t, "wait", "pop")
  /\ TryPop(t, "loop", "loop")
  /\ UNCHANGED <<pending, freed, qfreed, interrupt, completed, alive, hold, ptask, asleep, qheld,
                 epoch, sleepers, e0, grp, opHeld, opSum, poolTake, ended, returned>>

ExitPop(t) ==
  /\ Mode = "exitOnEmpty"
  /\ At(t, "wait", "loop")
  /\ TryPop(t, "loop", "join")
  /\ UNCHANGED <<pending, freed, qfreed, interrupt, completed, alive, hold, ptask, asleep, qheld,
                 epoch, sleepers, e0, grp, opHeld, opSum, poolTake, ended, returned>>

\* join_jobs (px_query_job.hpp:70): wait on the executor's cv under its m_mutex while the count > 0
Join(t) ==
  /\ Mode \in {"spin", "exitOnEmpty"}
  /\ At(t, "wait", "join")
  /\ Touch(Top(t).id)
  /\ IF pending[Top(t).id] = 0
     THEN WaitReturn(t) /\ UNCHANGED asleep
     ELSE asleep' = [asleep EXCEPT ![t] = Top(t).id] /\ UNCHANGED <<stack, returned>>
  /\ UNCHANGED <<queue, pending, freed, qfreed, interrupt, completed, alive, hold, ptask, qheld,
                 epoch, sleepers, e0, grp, opHeld, opSum, poolTake, runs, ranBy, ended, idle, spur>>

(* "event" waiter (D2-D5), also the worker's idle wait under "fixed" (D4). Done(t) ends the wait:
   the executor's count at 0 for a waiter; push_last or the interrupt for the worker task. *)
EvDone(t) ==
  IF Top(t).k = "wait"
  THEN pending[Top(t).id] = 0 \/ (Mutant = "returnOnEmpty" /\ queue = {})
  ELSE (completed \/ interrupt)
EvTouch(t) == IF Top(t).k = "wait" THEN Touch(Top(t).id) ELSE TouchQ
EvLeave(t) == IF Top(t).k = "wait" THEN WaitReturn(t) ELSE (SetPc(t, "exit") /\ UNCHANGED returned)
NoHelp(t) == Mutant = "noHelp" /\ Top(t).k = "wait"
\* an elastic worker ends instead of sleeping (D14 option "elastic")
ElasticTask(t) == SqPolicy = "elastic" /\ Top(t).k = "task"

EvLoop(t) ==
  /\ Mode = "event"
  /\ \E k \in {"wait", "task"} : At(t, k, "loop")
  /\ EvTouch(t)
  /\ IF EvDone(t) THEN EvLeave(t) ELSE (SetPc(t, "pop") /\ UNCHANGED returned)
  /\ UNCHANGED <<queue, pending, freed, qfreed, interrupt, completed, alive, hold, ptask, asleep, qheld,
                 epoch, sleepers, e0, grp, opHeld, opSum, poolTake, runs, ranBy, ended, idle, spur>>

EvPop(t) ==
  /\ Mode = "event"
  /\ \E k \in {"wait", "task"} : At(t, k, "pop")
  /\ IF NoHelp(t)
     THEN SetPc(t, "reg") /\ UNCHANGED <<queue, runs, ranBy, spur, uaf, idle>>
     ELSE TryPop(t, "loop", IF ElasticTask(t) THEN "xrel" ELSE "reg")
  /\ UNCHANGED <<pending, freed, qfreed, interrupt, completed, alive, hold, ptask, asleep, qheld,
                 epoch, sleepers, e0, grp, opHeld, opSum, poolTake, ended, returned>>

EvReg(t) ==
  /\ Mode = "event"
  /\ \E k \in {"wait", "task"} : At(t, k, "reg")
  /\ TouchQ
  /\ IF WakeAlways
     THEN /\ e0' = [e0 EXCEPT ![t] = epoch] /\ SetPc(t, "chk") /\ UNCHANGED sleepers
     ELSE /\ sleepers' = sleepers + 1 /\ SetPc(t, "reg2") /\ UNCHANGED e0
  /\ UNCHANGED <<queue, pending, freed, qfreed, interrupt, completed, alive, hold, ptask, asleep, qheld,
                 epoch, grp, opHeld, opSum, poolTake, runs, ranBy, ended, returned, idle, spur>>

EvReg2(t) ==
  /\ Mode = "event"
  /\ \E k \in {"wait", "task"} : At(t, k, "reg2")
  /\ TouchQ
  /\ e0' = [e0 EXCEPT ![t] = epoch]
  /\ SetPc(t, "chk")
  /\ UNCHANGED <<queue, pending, freed, qfreed, interrupt, completed, alive, hold, ptask, asleep, qheld,
                 epoch, sleepers, grp, opHeld, opSum, poolTake, runs, ranBy, ended, returned, idle, spur>>

Unreg == IF WakeAlways THEN UNCHANGED sleepers ELSE sleepers' = sleepers - 1

EvCheck(t) ==
  /\ Mode = "event"
  /\ \E k \in {"wait", "task"} : At(t, k, "chk")
  /\ EvTouch(t)
  /\ IF EvDone(t)
     THEN EvLeave(t) /\ Unreg
     ELSE IF queue # {} /\ Mutant # "noQueueRecheck" /\ ~NoHelp(t)
          THEN SetPc(t, "pop") /\ Unreg /\ UNCHANGED returned
          ELSE SetPc(t, "slp") /\ UNCHANGED <<sleepers, returned>>
  /\ UNCHANGED <<queue, pending, freed, qfreed, interrupt, completed, alive, hold, ptask, asleep, qheld,
                 epoch, e0, grp, opHeld, opSum, poolTake, runs, ranBy, ended, idle, spur>>

EvSleep(t) ==
  /\ Mode = "event"
  /\ \E k \in {"wait", "task"} : At(t, k, "slp")
  /\ TouchQ
  /\ IF epoch = e0[t]
     THEN asleep' = [asleep EXCEPT ![t] = "ev"] /\ UNCHANGED <<stack, sleepers, idle>>
     ELSE SetPc(t, "loop") /\ Unreg /\ UNCHANGED asleep /\ idle' = [idle EXCEPT ![t] = 0]
  /\ UNCHANGED <<queue, pending, freed, qfreed, interrupt, completed, alive, hold, ptask, qheld,
                 epoch, e0, grp, opHeld, opSum, poolTake, runs, ranBy, ended, returned, spur>>

(* Elastic worker end: give the unit back, then re-check the queue; a job pushed while this worker
   still held the unit (so its pusher could not start anyone) is taken here (Mutant
   "noExitRecheck" skips the re-check). *)
TaskUnitRelease(t) ==
  /\ At(t, "task", "xrel")
  /\ grp' = grp + 1
  /\ hold' = [hold EXCEPT ![t] = FALSE]
  /\ TouchQ
  /\ SetPc(t, IF Mutant = "noExitRecheck" THEN "exit" ELSE "xchk")
  /\ UNCHANGED <<queue, pending, freed, qfreed, interrupt, completed, alive, asleep, qheld, ptask,
                 epoch, sleepers, e0, opHeld, opSum, poolTake, runs, ranBy, ended, returned, idle, spur>>

TaskUnitRecheck(t) ==
  /\ At(t, "task", "xchk")
  /\ TouchQ
  /\ IF queue # {} /\ grp > 0 /\ ~completed /\ ~interrupt
     THEN grp' = grp - 1 /\ hold' = [hold EXCEPT ![t] = TRUE] /\ SetPc(t, "loop")
     ELSE UNCHANGED <<grp, hold>> /\ SetPc(t, "exit")
  /\ UNCHANGED <<queue, pending, freed, qfreed, interrupt, completed, alive, asleep, qheld, ptask,
                 epoch, sleepers, e0, opHeld, opSum, poolTake, runs, ranBy, ended, returned, idle, spur>>

----------------------------------------------------------------------------
(* The worker task: task::execute (px_query_task.cpp:30), pop (px_thread_safe_queue.cpp:64). *)

TaskStart(t) ==
  /\ At(t, "task", "idle")
  /\ alive[t]
  /\ SqPolicy = "fixed"
  /\ SetPc(t, IF Mode = "event" THEN "loop" ELSE "get")
  /\ UNCHANGED <<queue, pending, freed, qfreed, interrupt, completed, alive, hold, ptask, asleep, qheld,
                 epoch, sleepers, e0, grp, opHeld, opSum, poolTake, runs, ranBy, ended, returned, uaf, idle, spur>>

\* elastic: an idle pool thread picks up a pushed subquery task and its unit
TaskPickup(t) ==
  /\ At(t, "task", "idle")
  /\ ~alive[t]
  /\ ptask > 0
  /\ ptask' = ptask - 1
  /\ alive' = [alive EXCEPT ![t] = TRUE]
  /\ hold' = [hold EXCEPT ![t] = TRUE]
  /\ TouchQ
  /\ idle' = [idle EXCEPT ![t] = 0]
  /\ SetPc(t, "loop")
  /\ UNCHANGED <<queue, pending, freed, qfreed, interrupt, completed, asleep, qheld,
                 epoch, sleepers, e0, grp, opHeld, opSum, poolTake, runs, ranBy, ended, returned, spur>>

TaskFast(t) ==
  /\ Mode # "event"
  /\ At(t, "task", "get")
  /\ TouchQ
  /\ IF queue # {}
     THEN \E j \in queue : queue' = queue \ {j} /\ StartJob(t, j, "get") /\ ZeroIdle
     ELSE SetPc(t, "qchk") /\ UNCHANGED <<queue, runs, ranBy, idle>>
  /\ UNCHANGED <<pending, freed, qfreed, interrupt, completed, alive, hold, ptask, asleep, qheld,
                 epoch, sleepers, e0, grp, opHeld, opSum, poolTake, ended, returned, spur>>

TaskSlowCheck(t) ==
  /\ Mode # "event"
  /\ At(t, "task", "qchk")
  /\ qheld = None
  /\ TouchQ
  /\ IF queue # {}
     THEN IF interrupt
          THEN SetPc(t, "exit") /\ UNCHANGED <<queue, runs, ranBy, idle, qheld>>
          ELSE \E j \in queue : queue' = queue \ {j} /\ StartJob(t, j, "get") /\ ZeroIdle
                                /\ UNCHANGED qheld
     ELSE IF completed \/ interrupt
          THEN SetPc(t, "exit") /\ UNCHANGED <<queue, runs, ranBy, idle, qheld>>
          ELSE SetPc(t, "qslp") /\ qheld' = t /\ UNCHANGED <<queue, runs, ranBy, idle>>
  /\ UNCHANGED <<pending, freed, qfreed, interrupt, completed, alive, hold, ptask, asleep,
                 epoch, sleepers, e0, grp, opHeld, opSum, poolTake, ended, returned, spur>>

TaskSlowWait(t) ==
  /\ Mode # "event"
  /\ At(t, "task", "qslp")
  /\ asleep' = [asleep EXCEPT ![t] = "q"]
  /\ qheld' = None
  /\ SetPc(t, "qchk")
  /\ UNCHANGED <<queue, pending, freed, qfreed, interrupt, completed, alive, hold, ptask,
                 epoch, sleepers, e0, grp, opHeld, opSum, poolTake, runs, ranBy, ended, returned, uaf, idle, spur>>

\* the task ends (~task -> worker_manager::pop_task); a unit still held goes back to the group
TaskExit(t) ==
  /\ At(t, "task", "exit")
  /\ alive' = [alive EXCEPT ![t] = FALSE]
  /\ hold' = [hold EXCEPT ![t] = FALSE]
  /\ grp' = grp + (IF hold[t] /\ Mutant # "exitKeepsUnit" THEN Units(1) ELSE 0)
  /\ uaf' = (uaf \/ (hold[t] /\ Budget = "group" /\ qfreed))
  /\ SetPc(t, "idle")
  /\ UNCHANGED <<queue, pending, freed, qfreed, interrupt, completed, asleep, qheld, ptask,
                 epoch, sleepers, e0, opHeld, opSum, poolTake, runs, ranBy, ended, returned, idle, spur>>

----------------------------------------------------------------------------
(* The root after R's run_jobs joined: push_last, release_workers (waits for every task to end),
   then the executors, the queue and the group are deleted (px_query_executor.cpp:175-180). *)

RootEnd(t) ==
  /\ At(t, "root", "end")
  /\ completed' = TRUE
  /\ IF Mode = "event"
     THEN epoch' = epoch + 1 /\ EvWakeAll /\ UNCHANGED qheld
     ELSE /\ qheld = None
          /\ asleep' = [s \in Threads |-> IF asleep[s] = "q" THEN "no" ELSE asleep[s]]
          /\ UNCHANGED <<qheld, epoch, idle>>
  /\ SetPc(t, "rel")
  /\ UNCHANGED <<queue, pending, freed, qfreed, interrupt, alive, hold, ptask, sleepers, e0,
                 grp, opHeld, opSum, poolTake, runs, ranBy, ended, returned, uaf, spur>>

RootRelease(t) ==
  /\ At(t, "root", "rel")
  /\ \A w \in Workers : ~alive[w]
  /\ ptask = 0
  /\ freed' = [e \in Execs |-> TRUE]
  /\ qfreed' = TRUE
  /\ SetPc(t, "done")
  /\ UNCHANGED <<queue, pending, interrupt, completed, alive, hold, ptask, asleep, qheld,
                 epoch, sleepers, e0, grp, opHeld, opSum, poolTake, runs, ranBy, ended, returned, uaf, idle, spur>>

----------------------------------------------------------------------------
SpuriousWake ==
  \E t \in Threads :
    /\ asleep[t] # "no"
    /\ spur < MaxSpur
    /\ spur' = spur + 1
    /\ asleep' = [asleep EXCEPT ![t] = "no"]
    /\ UNCHANGED <<stack, queue, pending, freed, qfreed, interrupt, completed, alive, hold, ptask, qheld,
                   epoch, sleepers, e0, grp, opHeld, opSum, poolTake, runs, ranBy, ended, returned, uaf, idle>>

Step(t) ==
  \/ RootGroup(t) \/ AddOwn(t) \/ AddPush(t) \/ AddCount(t) \/ AddWake(t) \/ AddWake2(t)
  \/ AddSpawn(t) \/ AddDone(t)
  \/ JobStart(t) \/ JobReserve(t) \/ JobWork(t) \/ JobOpRelease(t) \/ JobOpSpawn(t)
  \/ JobClear(t) \/ JobFin(t) \/ JobWake(t) \/ JobWake2(t)
  \/ WaitOwn(t) \/ SpinCheck(t) \/ SpinPop(t) \/ ExitPop(t) \/ Join(t)
  \/ EvLoop(t) \/ EvPop(t) \/ EvReg(t) \/ EvReg2(t) \/ EvCheck(t) \/ EvSleep(t)
  \/ TaskUnitRelease(t) \/ TaskUnitRecheck(t)
  \/ TaskStart(t) \/ TaskPickup(t) \/ TaskFast(t) \/ TaskSlowCheck(t) \/ TaskSlowWait(t) \/ TaskExit(t)
  \/ RootEnd(t) \/ RootRelease(t)

Finished == Len(stack[Main]) = 1 /\ Top(Main).pc = "done"

Next ==
  \/ \E t \in Threads : Step(t)
  \/ SpuriousWake
  \/ (Finished /\ UNCHANGED vars)

Spec == Init /\ [][Next]_vars /\ \A t \in Threads : WF_vars(Step(t))

----------------------------------------------------------------------------
(* Claims (MAP.md). *)

TypeOK ==
  /\ queue \subseteq Jobs
  /\ pending \in [Execs -> 0..Cardinality(Jobs)]
  /\ asleep \in [Threads -> {"no", "q", "ev"} \cup Execs]
  /\ sleepers \in 0..Cardinality(Threads)
  /\ grp \in 0..B

\* C1: run_jobs of an executor returns only after every job it added has ended
JoinAfterAllEnded == \A e \in returned : JobsOf(e) \subseteq ended
\* C2: no job runs twice
RunsOnce == \A j \in Jobs : runs[j] <= 1
\* C3: nothing touches a deleted executor, queue, event or group
NoUseAfterFree == ~uaf
\* C5: a waiting thread does not poll
NoPolling == \A t \in Threads : idle[t] <= MaxSpur + 1
\* C6: no thread sleeps in an idle wait while a job is queued, unless a pusher's wake is on its way
WakeOnTheWay == \E t \in Threads : Len(stack[t]) > 0 /\ Top(t).pc \in {"cnt", "wk", "wk2"} /\ Top(t).k \in {"root", "job"}
NoSleepWithWork ==
  (queue # {} /\ \E t \in Threads : asleep[t] \in {"q", "ev"}) => WakeOnTheWay
\* C7: the statement holds at most B workers, and takes none from the server pool after the root's start
SqHeld == Cardinality({w \in Workers : hold[w]}) + ptask
WithinBudget == SqHeld + opSum <= B /\ poolTake = 0
\* C8 (elastic): no job waits in the queue while the group has a unit and a worker is idle, unless a start is on its way
SpawnOnTheWay == \E t \in Threads : Len(stack[t]) > 0 /\ Top(t).pc \in {"cnt", "wk", "wk2", "spn", "orel", "ospn", "xrel", "xchk"}
NoIdleUnitWithWork == CanSpawn => SpawnOnTheWay
\* C9: at the end every unit is back in the group
NoLeak == Finished => (Budget = "pool" \/ grp = B)
\* C4: the statement ends
Terminates == <>Finished

----------------------------------------------------------------------------
(* IndInv: the inductive invariant of the chosen design (Mode "event", WakeAlways, Budget "group",
   SqPolicy "elastic", no InlineFail, Mutant "none"). Its conjuncts carry every safety claim
   (C1-C3, C5-C9); the rest describe the call stacks, where each job is, each executor's phase, and
   the counts the claims rest on. *)

\* the deepest stack: the root and its wait (or the task), a job and a wait frame per nested job (each
\* on one stack at most), and a leaf job
ASSUME Depth = 3 + 2 * Cardinality(Nested)
KMax == Depth
Idx == 2..Depth
IsJobAt(t, i, j) == i <= Len(stack[t]) /\ stack[t][i].k = "job" /\ stack[t][i].id = j
OnStack(j) == \E t \in Threads : \E i \in Idx : IsJobAt(t, i, j)

\* the sum of opHeld, written out per tree (nested jobs hold nothing)
OpTotal ==
  IF Tree = "base" THEN opHeld["1"] + opHeld["2"] + opHeld["21"] + opHeld["22"]
  ELSE IF Tree = "nestM" THEN opHeld["1"] + opHeld["2"] + opHeld["11"] + opHeld["12"]
  ELSE IF Tree = "wide" THEN opHeld["1"] + opHeld["2"] + opHeld["3"] + opHeld["21"] + opHeld["22"] + opHeld["23"]
  ELSE IF Tree = "bin2" THEN opHeld["1"] + opHeld["2"] + opHeld["11"] + opHeld["12"] + opHeld["21"] + opHeld["22"]
  ELSE opHeld["1"] + opHeld["2"] + opHeld["11"] + opHeld["12"] + opHeld["21"] + opHeld["22"]
       + opHeld["111"] + opHeld["112"] + opHeld["121"] + opHeld["122"]
       + opHeld["211"] + opHeld["212"] + opHeld["221"] + opHeld["222"]

\* the jobs of an executor as a list of three (None pads the two-job executors): counts are sums, not
\* Cardinality, which Apalache encodes per element pair
J2(e) == IF e = "R" THEN "2" ELSE IF e = "x1" THEN "12" ELSE IF e = "x2" THEN "22"
         ELSE IF e = "x11" THEN "112" ELSE IF e = "x12" THEN "122" ELSE IF e = "x21" THEN "212" ELSE "222"
J3(e) == IF Tree = "wide" /\ e = "R" THEN "3" ELSE IF Tree = "wide" /\ e = "x2" THEN "23" ELSE None
In(x, S) == IF x \in S THEN 1 ELSE 0
\* jobs of e in S, and queued jobs of e (the second and third) not in S
CntIn(e, S) == In(OwnJob(e), S) + In(J2(e), S) + In(J3(e), S)
NQ(e) == IF J3(e) = None THEN 1 ELSE 2
CntQOut(e, S) == NQ(e) - In(J2(e), S) - In(J3(e), S)

\* executor phases
Fresh(c) ==
  /\ pending[c] = 0 /\ c \notin returned /\ (~freed[c] \/ qfreed)
  /\ \A x \in JobsOf(c) : runs[x] = 0 /\ x \notin queue /\ x \notin ended
Done(c) == c \in returned /\ JobsOf(c) \subseteq ended /\ pending[c] = 0
Live(c) == c \notin returned /\ ~freed[c]
\* @type: (Str, {k: Str, id: Str, pc: Str, todo: Set(Str)}) => Bool;
Adding(c, f) ==
  /\ Live(c)
  /\ f.todo \subseteq QJobs(c)
  /\ runs[OwnJob(c)] = 0 /\ OwnJob(c) \notin queue
  /\ \A x \in f.todo : runs[x] = 0 /\ x \notin queue
  /\ \A x \in JobsOf(c) : x \in ended => x \in QJobs(c) \ f.todo
  /\ pending[c] + CntIn(c, ended)
       = 1 + CntQOut(c, f.todo) - (IF f.pc = "cnt" THEN 1 ELSE 0)
AllPushed(c) ==
  /\ Live(c)
  /\ pending[c] + CntIn(c, ended) = 1 + NQ(c)
\* the executor c whose jobs the frame f adds (f a root frame, or a nested job's frame); lower: c's wait is above f
\* @type: (Str, {k: Str, id: Str, pc: Str, todo: Set(Str)}, Bool) => Bool;
ExecInv(c, f, lower) ==
  IF lower THEN AllPushed(c)
  ELSE IF f.pc \in {"grp", "own", "start"} THEN Fresh(c)
  ELSE IF f.pc \in {"add", "cnt", "wk", "spn"} THEN Adding(c, f)
  ELSE IF f.pc \in {"end", "clear"} THEN Done(c) /\ ~freed[c]
  ELSE IF f.pc = "rel" THEN Done(c) /\ ~freed[c] /\ completed
  ELSE IF f.pc = "done" THEN Done(c)
  ELSE (Done(c) /\ freed[c]) \/ (Fresh(c) /\ interrupt)   \* "fin", "fwk": cleared, or skipped on the interrupt

\* @type: ({k: Str, id: Str, pc: Str, todo: Set(Str)}) => Set(Str);
TopPcs(f) ==
  IF f.k = "root" THEN {"grp", "own", "add", "cnt", "wk", "spn", "end", "rel", "done"}
  ELSE IF f.k = "wait" THEN {"own", "loop", "pop", "reg", "chk", "slp"}
  ELSE IF f.k = "task" THEN {"idle", "loop", "pop", "xrel", "xchk", "exit"}
  ELSE IF f.id \in Nested THEN {"start", "own", "add", "cnt", "wk", "spn", "clear", "fin", "fwk"}
  ELSE {"start", "rsv", "work", "orel", "ospn", "fin", "fwk"}
LowerPc(k) == IF k = "root" THEN "end" ELSE IF k = "job" THEN "clear" ELSE "loop"

\* elastic workers that run no job and will take a queued one (FreeWorkers, and those giving back or re-checking)
FreeOrRecheck == {w \in Workers : alive[w] /\ Len(stack[w]) = 1 /\ stack[w][1].pc \in {"loop", "pop", "xrel", "xchk"}}
Rechecking == {w \in Workers : Len(stack[w]) = 1 /\ stack[w][1].pc = "xchk"}
Pushing == {t \in Threads : Top(t).pc \in {"cnt", "wk", "spn"}}
Releasing == \E t \in Threads : Top(t).pc \in {"orel", "ospn"}

IStackShape ==
  \A t \in Threads :
    /\ 1 <= Len(stack[t]) /\ Len(stack[t]) <= KMax
    /\ stack[t][1].k = (IF t = Main THEN "root" ELSE "task")
    /\ stack[t][1].id = (IF t = Main THEN "R" ELSE None)
    /\ \A i \in Idx : i <= Len(stack[t]) =>
         /\ stack[t][i].k = (IF (t = Main) = (i % 2 = 0) THEN "wait" ELSE "job")
         /\ stack[t][i].k = "job" => stack[t][i].id \in Jobs
         /\ stack[t][i].k = "wait" =>
              /\ stack[t][i - 1].k = "root" \/ stack[t][i - 1].id \in Nested
              /\ stack[t][i].id = (IF stack[t][i - 1].k = "root" THEN "R" ELSE ExecOf(stack[t][i - 1].id))
    /\ \A i \in {1} \cup Idx : i <= Len(stack[t]) =>
         /\ i < Len(stack[t]) => stack[t][i].pc = LowerPc(stack[t][i].k)
         /\ i = Len(stack[t]) => stack[t][i].pc \in TopPcs(stack[t][i])
         /\ stack[t][i].pc \notin {"add", "cnt", "wk", "spn"} => stack[t][i].todo = {}
         /\ stack[t][i].k \in {"wait", "task"} => stack[t][i].todo = {}
         /\ stack[t][i].k = "job" /\ stack[t][i].id \notin Nested => stack[t][i].todo = {}

IThreads ==
  /\ \A t \in Threads : asleep[t] \in {"no", "ev"} /\ e0[t] <= epoch /\ idle[t] >= 0
  /\ \A t \in Threads : asleep[t] = "ev" => Top(t).k = "wait" /\ Top(t).pc = "slp" /\ e0[t] = epoch
  /\ sleepers = 0 /\ qheld = None /\ epoch >= 0 /\ spur >= 0 /\ spur <= MaxSpur
  /\ \A w \in Workers :
       /\ ~alive[w] <=> (Len(stack[w]) = 1 /\ stack[w][1].pc = "idle")
       /\ ~alive[w] => ~hold[w]
       /\ alive[w] /\ stack[w][1].pc \in {"loop", "pop", "xrel"} => hold[w]
       /\ stack[w][1].pc = "xchk" => ~hold[w]

IJobs ==
  /\ queue \subseteq Jobs /\ ended \subseteq Jobs /\ returned \subseteq Execs
  /\ \A e \in Execs : OwnJob(e) \notin queue
  /\ \A j \in Jobs :
       /\ runs[j] \in {0, 1}
       /\ j \in queue => runs[j] = 0
       /\ j \in ended => runs[j] = 1
       /\ runs[j] = 1 /\ j \notin ended => OnStack(j)
       /\ opHeld[j] >= 0
       /\ opHeld[j] > 0 => j \notin Nested /\ runs[j] = 1 /\ j \notin ended
  /\ \A t1, t2 \in Threads : \A i1, i2 \in Idx :
       /\ i1 <= Len(stack[t1]) /\ i2 <= Len(stack[t2])
       /\ stack[t1][i1].k = "job" /\ stack[t2][i2].k = "job" /\ stack[t1][i1].id = stack[t2][i2].id
       => t1 = t2 /\ i1 = i2
  /\ \A t \in Threads : \A i \in Idx : i <= Len(stack[t]) /\ stack[t][i].k = "job" =>
       /\ runs[stack[t][i].id] = 1
       /\ (stack[t][i].id \in ended <=> stack[t][i].pc = "fwk")
       /\ stack[t][i].pc \notin {"work", "orel"} => opHeld[stack[t][i].id] = 0
       /\ stack[t][i].pc = "orel" => opHeld[stack[t][i].id] > 0

IExecs ==
  /\ \A e \in Execs : pending[e] >= 0
  /\ ExecInv("R", stack[Main][1], Len(stack[Main]) > 1)
  /\ \A j \in Nested : \A t \in Threads : \A i \in Idx :
       IsJobAt(t, i, j) => ExecInv(ExecOf(j), stack[t][i], i < Len(stack[t]))
  /\ \A j \in Nested :
       /\ runs[j] = 0 => Fresh(ExecOf(j))
       /\ j \in ended => (Done(ExecOf(j)) /\ freed[ExecOf(j)]) \/ (Fresh(ExecOf(j)) /\ interrupt)
  /\ \A e \in Execs : \A t \in Threads : \A i \in Idx :
       i <= Len(stack[t]) /\ stack[t][i].k = "wait" /\ stack[t][i].id = e =>
         runs[OwnJob(e)] = (IF stack[t][i].pc = "own" /\ i = Len(stack[t]) THEN 0 ELSE 1)
  /\ completed <=> stack[Main][1].pc \in {"rel", "done"}
  /\ qfreed <=> stack[Main][1].pc = "done"
  /\ qfreed => /\ \A e \in Execs : freed[e]
               /\ \A w \in Workers : ~alive[w]
               /\ ptask = 0
  /\ ~uaf /\ poolTake = 0

IBudget ==
  /\ grp >= 0 /\ ptask >= 0 /\ opSum = OpTotal
  /\ IF stack[Main][1].pc = "grp"
     THEN grp = 0 /\ ptask = 0 /\ opSum = 0 /\ \A w \in Workers : ~alive[w]
     ELSE grp + Cardinality({w \in Workers : hold[w]}) + ptask + opSum = B
  \* C8's inductive form: a job queued beyond the workers that will take it has a pusher on its way
  /\ (~interrupt /\ ~completed /\ grp > Cardinality(Rechecking) /\ ~Releasing)
       => Cardinality(queue) <= Cardinality(FreeOrRecheck) + ptask + Cardinality(Pushing)

IWake ==
  \A t \in Threads :
    Top(t).k = "wait" /\ Top(t).pc = "slp" /\ e0[t] = epoch /\ queue # {} => WakeOnTheWay

IIdle ==
  \A t \in Threads :
    /\ idle[t] <= spur + 1
    /\ Top(t).k \in {"wait", "task"} /\ Top(t).pc \in {"loop", "pop"} => idle[t] <= spur
    /\ Top(t).pc \in {"reg", "chk", "slp", "xrel", "xchk"} /\ queue # {} => idle[t] <= spur
    /\ Top(t).k = "job" /\ Top(t).pc = "fwk" => idle[t] = 0

IndInv ==
  /\ IStackShape
  /\ IThreads
  /\ IJobs
  /\ IExecs
  /\ IBudget
  /\ IWake
  /\ IIdle
  /\ JoinAfterAllEnded
  /\ RunsOnce
  /\ NoUseAfterFree
  /\ NoPolling
  /\ NoSleepWithWork
  /\ WithinBudget
  /\ NoIdleUnitWithWork
  /\ NoLeak

Sym == Permutations(Workers)

\* develop's spin loop's ghost cap, so its other claims can be checked
IdleCap == \A t \in Threads : idle[t] <= MaxSpur + 2

\* witnesses (expected violated)
NotHelped == \A j \in Jobs : ranBy[j] # Main \/ Owner(j) = "R" \/ j = OwnJob(Owner(j))
NotNestedWaiterSlept == ~(\E t \in Threads : asleep[t] = "ev" /\ Len(stack[t]) > 0 /\ Top(t).k = "wait" /\ Top(t).id # "R")
NotInterruptedEnd == ~(Finished /\ interrupt)
NotAllLeavesDeepRun == ~(\A j \in Jobs : Leaf(j) => j \in ended) \/ Cardinality(Jobs) < 14
NotOpGotUnits == \A j \in Jobs : opHeld[j] = 0
NotThreeWorkersBusy == Cardinality({w \in Workers : alive[w] /\ Len(stack[w]) >= 2}) < 3
=============================================================================
