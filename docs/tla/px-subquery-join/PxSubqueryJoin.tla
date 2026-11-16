---------------------------- MODULE PxSubqueryJoin ----------------------------
(* The parallel subquery executor's job queue and join (src/query/parallel/px_query_execute/,
   px_thread_safe_queue.cpp) at CUBRID develop 41ca53ce7, and their redesign without a polling
   mutex (MAP.md "Decisions"). The statement's worker budget is out of scope (xmilex-git/workspace#644):
   the subquery workers start when the root's run_jobs starts, as develop's one worker does.

   One statement. The root executor "R" (attached to the first node with two or more parallel
   aptrs) and every nested executor own a set of jobs (JobsOf): one is its m_job, run by the thread
   that calls its run_jobs; the rest go to the one queue the statement shares. A job in Nested runs
   a nested executor during its execution. Tree picks the shape:
     "base"   R: 1, 2;  2 runs x2: 21, 22                    (the nested executor on a worker)
     "nestM"  R: 1, 2;  1 runs x1: 11, 12                    (the nested executor on the main thread)
     "wide"   R: 1, 2, 3;  2 runs x2: 21, 22, 23
     "bin2"   R: 1, 2;  x1: 11, 12;  x2: 21, 22
   Late adds the late executor "xL": L1, L2, attached to a node outside the root's jobs (a WHERE
   scalar subquery, CBRD-27823) and run by the main thread after the root's run_jobs returned.

   Mode picks the wait of run_jobs after its own job:
     "spin"         develop: poll the count under join_context::m_mutex and try_pop until the
                    count is 0 (px_query_executor.cpp:146-170), then join_jobs; the worker waits in
                    the queue's pop_slow.
     "exitOnEmpty"  oracle-gap#20 direction 2: try_pop until it fails, then join_jobs's cv wait.
     "event"        D2-D5: an atomic count per executor and one wake event per statement, owned
                    by the root executor; a waiter helps until the queue is empty, then sleeps on
                    the event; a push and the end of an executor's last job wake it. The worker's
                    idle wait is the same wait. *)
EXTENDS Naturals, Sequences, FiniteSets, TLC

CONSTANTS Mode,        \* "spin" | "exitOnEmpty" | "event"
          Mutant,      \* "none" | see MAP.md "Mutants"
          Workers,     \* the statement's subquery worker threads (develop: one)
          Tree,        \* "base" | "nestM" | "wide" | "bin2"
          WorkFail,    \* BOOLEAN: a leaf job may fail (raises the statement interrupt)
          InlineFail,  \* BOOLEAN: a nested job may fail after pushing, before its run_jobs
          MaxSpur,     \* failed try_pop on a non-empty queue + spurious condvar wakeups, in total
          WakeAlways,  \* BOOLEAN ("event"): a waker always locks and notifies (D5)
          Ghosts,      \* BOOLEAN: keep the ranBy ghost (witnesses)
          Late         \* BOOLEAN: the main thread runs the late executor xL after the root's run_jobs
CONSTANTS Depth        \* the stack bound for IndInv: 3 + 2 * Cardinality(Nested) (5 or 7)

\* apalache-type: Mode Str
\* apalache-type: Mutant Str
\* apalache-type: Workers Set(Str)
\* apalache-type: Tree Str
\* apalache-type: WorkFail Bool
\* apalache-type: InlineFail Bool
\* apalache-type: MaxSpur Int
\* apalache-type: WakeAlways Bool
\* apalache-type: Ghosts Bool
\* apalache-type: Late Bool
\* apalache-type: Depth Int
\* apalache-type: stack Str -> Seq({k: Str, id: Str, pc: Str, todo: Set(Str)})
\* apalache-type: queue Set(Str)
\* apalache-type: pending Str -> Int
\* apalache-type: freed Str -> Bool
\* apalache-type: qfreed Bool
\* apalache-type: interrupt Bool
\* apalache-type: completed Bool
\* apalache-type: alive Str -> Bool
\* apalache-type: asleep Str -> Str
\* apalache-type: qheld Str
\* apalache-type: epoch Int
\* apalache-type: sleepers Int
\* apalache-type: e0 Str -> Int
\* apalache-type: runs Str -> Int
\* apalache-type: ranBy Str -> Str
\* apalache-type: ended Set(Str)
\* apalache-type: refused Set(Str)
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
  IF e = "xL" THEN {"L1", "L2"}
  ELSE IF e = "R" THEN (IF Tree = "wide" THEN {"1", "2", "3"} ELSE {"1", "2"})
  ELSE IF e = "x2" /\ Tree = "wide" THEN {"21", "22", "23"}
  ELSE IF e = "x1" THEN {"11", "12"} ELSE {"21", "22"}
OwnJob(e) == IF e = "xL" THEN "L1" ELSE IF e = "R" THEN "1" ELSE IF e = "x1" THEN "11" ELSE "21"
Nested ==
  IF Tree = "base" THEN {"2"} ELSE IF Tree = "nestM" THEN {"1"} ELSE IF Tree = "wide" THEN {"2"}
  ELSE {"1", "2"}
ExecOf(j) == IF j = "1" THEN "x1" ELSE "x2"
Execs == {"R"} \cup {ExecOf(j) : j \in Nested} \cup (IF Late THEN {"xL"} ELSE {})
Jobs == UNION {JobsOf(e) : e \in Execs}
Owner(j) ==
  IF j \in {"L1", "L2"} THEN "xL" ELSE IF j \in {"1", "2", "3"} THEN "R" ELSE IF j \in {"11", "12"} THEN "x1" ELSE "x2"
QJobs(e) == JobsOf(e) \ {OwnJob(e)}
Child(j) == IF j \in Nested THEN ExecOf(j) ELSE None
Leaf(j) == j \notin Nested

\* @type: (Str, Str, Str) => {k: Str, id: Str, pc: Str, todo: Set(Str)};
Frame(k, id, pc) == [k |-> k, id |-> id, pc |-> pc, todo |-> {}]

VARIABLES stack,     \* per thread: the call frames (root, task, job, wait)
          queue,     \* jobs pushed and not popped
          pending,   \* join_context::m_running_jobs per executor
          freed,     \* executor deleted (qexec_clear_xasl_for_parallel_aptr)
          qfreed,    \* the statement's queue and wake event deleted (root executor destroyed)
          interrupt, \* the statement's px interrupt (root executor's m_interrupt)
          completed, \* the workers are told to stop (develop: push_last, which also closes the queue to pushes)
          alive,     \* worker task started on the thread and not ended
          asleep,    \* "no" | "q" (queue m_not_empty) | "ev" (statement event) | e (join cv of e)
          qheld,     \* queue m_mutex held across pop_slow's check and its wait
          epoch,     \* statement event epoch
          sleepers,  \* threads registered to sleep on the event (WakeAlways = FALSE)
          e0,        \* epoch a thread read before its re-check
          runs,      \* ghost: times each job started
          ranBy,     \* ghost: thread that ran each job (Ghosts only)
          ended,     \* ghost: jobs that ended (decremented their owner's count, or were refused)
          refused,   \* ghost: jobs the queue refused (push_slow returns on the interrupt) and nobody runs
          returned,  \* ghost: executors whose run_jobs returned
          uaf,       \* ghost: a freed executor, queue or event was touched
          idle,      \* ghost: failed try_pop since the thread's last pop, job end, wake, queue change or epoch move it saw
          spur       \* ghost: spurious failures used

vars == <<stack, queue, pending, freed, qfreed, interrupt, completed, alive, asleep, qheld,
          epoch, sleepers, e0, runs, ranBy, ended, refused, returned, uaf, idle, spur>>

Init ==
  /\ stack = [t \in Threads |-> IF t = Main THEN <<Frame("root", "R", "own")>>
                                            ELSE <<Frame("task", None, "idle")>>]
  /\ queue = {}
  /\ pending = [e \in Execs |-> 0]
  /\ freed = [e \in Execs |-> FALSE]
  /\ qfreed = FALSE
  /\ interrupt = FALSE
  /\ completed = FALSE
  /\ alive = [w \in Workers |-> FALSE]
  /\ asleep = [t \in Threads |-> "no"]
  /\ qheld = None
  /\ epoch = 0
  /\ sleepers = 0
  /\ e0 = [t \in Threads |-> 0]
  /\ runs = [j \in Jobs |-> 0]
  /\ ranBy = [j \in Jobs |-> None]
  /\ ended = {}
  /\ refused = {}
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
AddTo(t) == IF Top(t).k = "root" THEN "R" ELSE IF Top(t).k = "lroot" THEN "xL" ELSE Child(Top(t).id)
Touch(e) == uaf' = (uaf \/ freed[e])
TouchQ == uaf' = (uaf \/ qfreed)
ZeroIdle == idle' = [s \in Threads |-> 0]

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

----------------------------------------------------------------------------
(* Adding jobs: query_executor::add_job from qexec_execute_mainblock_internal's aptr loop
   (query_executor.c:22423). The first job is m_job; the rest are pushed, then counted. *)
AddOwn(t) ==
  /\ \E k \in {"root", "job", "lroot"} : At(t, k, "own")
  /\ LET e == AddTo(t) IN
       /\ pending' = [pending EXCEPT ![e] = @ + 1]
       /\ Touch(e)
       /\ stack' = [stack EXCEPT ![t][Len(stack[t])].pc = "add",
                                 ![t][Len(stack[t])].todo = QJobs(e)]
  /\ UNCHANGED <<queue, freed, qfreed, interrupt, completed, alive, asleep, qheld,
                 epoch, sleepers, e0, runs, ranBy, ended, returned, idle, spur>>

(* push (px_thread_safe_queue.cpp:54): try_push_fast, else push_slow, which returns without pushing
   when the interrupt is set (:285, :297, :307). The redesign's add_job counts and wakes only a job the
   queue took; a refused job ends without running, as one popped after the interrupt would
   (execute_job_internal's early exit). Mutant "countRefused" (develop) counts it anyway. *)
AddPush(t) ==
  /\ \E k \in {"root", "job", "lroot"} : At(t, k, "add")
  /\ Top(t).todo # {}
  /\ \E j \in Top(t).todo :
       \/ /\ queue' = IF Mutant = "closedQueue" /\ completed THEN queue ELSE queue \cup {j}
          /\ TouchQ
          /\ ZeroIdle
          /\ stack' = [stack EXCEPT ![t][Len(stack[t])].pc = "cnt",
                                    ![t][Len(stack[t])].todo = @ \ {j}]
          /\ IF Mode = "event" THEN UNCHANGED asleep ELSE QNotifyOne
          /\ UNCHANGED <<ended, refused>>
       \/ /\ interrupt
          /\ Mode = "event"
          /\ UNCHANGED <<queue, asleep, idle>>
          /\ TouchQ
          /\ IF Mutant = "countRefused"
             THEN /\ stack' = [stack EXCEPT ![t][Len(stack[t])].pc = "cnt",
                                            ![t][Len(stack[t])].todo = @ \ {j}]
                  /\ UNCHANGED <<ended, refused>>
             ELSE /\ stack' = [stack EXCEPT ![t][Len(stack[t])].todo = @ \ {j}]
                  /\ ended' = ended \cup {j}
                  /\ refused' = refused \cup {j}
  /\ UNCHANGED <<pending, freed, qfreed, interrupt, completed, alive, qheld,
                 epoch, sleepers, e0, runs, ranBy, returned, spur>>

AddCount(t) ==
  /\ \E k \in {"root", "job", "lroot"} : At(t, k, "cnt")
  /\ LET e == AddTo(t) IN
       /\ pending' = [pending EXCEPT ![e] = @ + 1]
       /\ Touch(e)
  /\ SetPc(t, IF Mode = "event" /\ Mutant # "noPushWake" THEN "wk" ELSE "add")
  /\ UNCHANGED <<queue, freed, qfreed, interrupt, completed, alive, asleep, qheld,
                 epoch, sleepers, e0, runs, ranBy, ended, returned, idle, spur>>

(* The event wake: "wk" bumps the epoch (WakeAlways: and notifies under the event mutex in the
   same critical section); "wk2" notifies only when a sleeper registered. *)
AddWake(t) ==
  /\ \E k \in {"root", "job", "lroot"} : At(t, k, "wk")
  /\ epoch' = epoch + 1
  /\ TouchQ
  /\ IF WakeAlways
     THEN EvWakeAll /\ SetPc(t, "add")
     ELSE UNCHANGED <<asleep, idle>> /\ SetPc(t, "wk2")
  /\ UNCHANGED <<queue, pending, freed, qfreed, interrupt, completed, alive, qheld,
                 sleepers, e0, runs, ranBy, ended, returned, spur>>

AddWake2(t) ==
  /\ \E k \in {"root", "job", "lroot"} : At(t, k, "wk2")
  /\ TouchQ
  /\ IF sleepers > 0 THEN EvWakeAll ELSE UNCHANGED <<asleep, idle>>
  /\ SetPc(t, "add")
  /\ UNCHANGED <<queue, pending, freed, qfreed, interrupt, completed, alive, qheld,
                 epoch, sleepers, e0, runs, ranBy, ended, returned, spur>>

(* All jobs added: run_jobs. The root starts the worker tasks first (px_query_executor.cpp:133):
   develop one task on the worker it reserved, here one per thread of Workers.
   InlineFail: a sibling aptr run inline (XASL_NO_PARALLEL_SUBQUERY) fails after the pushes;
   GOTO_EXIT_ON_ERROR skips run_jobs (query_executor.c:22427-22436, 23174). *)
AddDone(t) ==
  /\ \E k \in {"root", "job", "lroot"} : At(t, k, "add")
  /\ Top(t).todo = {}
  /\ IF Top(t).k = "root"
     THEN /\ alive' = [w \in Workers |-> TRUE]
          /\ Call(t, "end", Frame("wait", "R", "own"))
          /\ UNCHANGED interrupt
     ELSE IF Top(t).k = "lroot"
     THEN /\ UNCHANGED <<alive, interrupt>>
          /\ Call(t, "lend", Frame("wait", "xL", "own"))
     ELSE /\ UNCHANGED alive
          /\ \/ /\ Call(t, "clear", Frame("wait", AddTo(t), "own"))
                /\ UNCHANGED interrupt
             \/ /\ InlineFail
                /\ interrupt' = TRUE
                /\ SetPc(t, "clear")
  /\ UNCHANGED <<queue, pending, freed, qfreed, completed, asleep, qheld,
                 epoch, sleepers, e0, runs, ranBy, ended, returned, uaf, idle, spur>>

----------------------------------------------------------------------------
(* A job: execute_job_internal (px_query_task.cpp:73). *)

JobStart(t) ==
  /\ At(t, "job", "start")
  /\ SetPc(t, IF interrupt THEN "fin" ELSE IF ~Leaf(Top(t).id) THEN "own" ELSE "work")
  /\ UNCHANGED <<queue, pending, freed, qfreed, interrupt, completed, alive, asleep, qheld,
                 epoch, sleepers, e0, runs, ranBy, ended, returned, uaf, idle, spur>>

JobWork(t) ==
  /\ At(t, "job", "work")
  /\ \/ UNCHANGED interrupt
     \/ WorkFail /\ interrupt' = TRUE
  /\ SetPc(t, "fin")
  /\ UNCHANGED <<queue, pending, freed, qfreed, completed, alive, asleep, qheld,
                 epoch, sleepers, e0, runs, ranBy, ended, returned, uaf, idle, spur>>

\* qexec_clear_xasl_for_parallel_aptr (px_query_task.cpp:196) deletes the job's px_executor (query_executor.c:2615)
JobClear(t) ==
  /\ At(t, "job", "clear")
  /\ freed' = [freed EXCEPT ![Child(Top(t).id)] = TRUE]
  /\ SetPc(t, "fin")
  /\ UNCHANGED <<queue, pending, qfreed, interrupt, completed, alive, asleep, qheld,
                 epoch, sleepers, e0, runs, ranBy, ended, returned, uaf, idle, spur>>

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
  /\ UNCHANGED <<queue, freed, qfreed, interrupt, completed, alive, qheld,
                 epoch, sleepers, e0, runs, ranBy, returned, spur>>

\* Mutant "wakeViaExec": the wake reaches the event through the owner executor (or the event lives in it)
JobWake(t) ==
  /\ At(t, "job", "fwk")
  /\ epoch' = epoch + 1
  /\ uaf' = (uaf \/ qfreed \/ (Mutant = "wakeViaExec" /\ freed[Owner(Top(t).id)]))
  /\ IF WakeAlways
     THEN EvWakeAll /\ Ret(t)
     ELSE UNCHANGED <<asleep, idle>> /\ SetPc(t, "fwk2")
  /\ UNCHANGED <<queue, pending, freed, qfreed, interrupt, completed, alive, qheld,
                 sleepers, e0, runs, ranBy, ended, returned, spur>>

JobWake2(t) ==
  /\ At(t, "job", "fwk2")
  /\ TouchQ
  /\ IF sleepers > 0 THEN EvWakeAll ELSE UNCHANGED <<asleep, idle>>
  /\ Ret(t)
  /\ UNCHANGED <<queue, pending, freed, qfreed, interrupt, completed, alive, qheld,
                 epoch, sleepers, e0, runs, ranBy, ended, returned, spur>>

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
  /\ UNCHANGED <<queue, pending, freed, qfreed, interrupt, completed, alive, asleep, qheld,
                 epoch, sleepers, e0, ended, returned, uaf, idle, spur>>

WaitReturn(t) ==
  /\ returned' = returned \cup {Top(t).id}
  /\ Ret(t)

SpinCheck(t) ==
  /\ Mode = "spin"
  /\ At(t, "wait", "loop")
  /\ Touch(Top(t).id)
  /\ SetPc(t, IF pending[Top(t).id] = 0 THEN "join" ELSE "pop")
  /\ UNCHANGED <<queue, pending, freed, qfreed, interrupt, completed, alive, asleep, qheld,
                 epoch, sleepers, e0, runs, ranBy, ended, returned, idle, spur>>

SpinPop(t) ==
  /\ Mode = "spin"
  /\ At(t, "wait", "pop")
  /\ TryPop(t, "loop", "loop")
  /\ UNCHANGED <<pending, freed, qfreed, interrupt, completed, alive, asleep, qheld,
                 epoch, sleepers, e0, ended, returned>>

ExitPop(t) ==
  /\ Mode = "exitOnEmpty"
  /\ At(t, "wait", "loop")
  /\ TryPop(t, "loop", "join")
  /\ UNCHANGED <<pending, freed, qfreed, interrupt, completed, alive, asleep, qheld,
                 epoch, sleepers, e0, ended, returned>>

\* join_jobs (px_query_job.hpp:70): wait on the executor's cv under its m_mutex while the count > 0
Join(t) ==
  /\ Mode \in {"spin", "exitOnEmpty"}
  /\ At(t, "wait", "join")
  /\ Touch(Top(t).id)
  /\ IF pending[Top(t).id] = 0
     THEN WaitReturn(t) /\ UNCHANGED asleep
     ELSE asleep' = [asleep EXCEPT ![t] = Top(t).id] /\ UNCHANGED <<stack, returned>>
  /\ UNCHANGED <<queue, pending, freed, qfreed, interrupt, completed, alive, qheld,
                 epoch, sleepers, e0, runs, ranBy, ended, idle, spur>>

(* "event" waiter (D2-D5), also the worker's idle wait (D4). EvDone(t) ends the wait: the
   executor's count at 0 for a waiter; push_last or the interrupt for the worker task. *)
EvDone(t) ==
  IF Top(t).k = "wait"
  THEN pending[Top(t).id] = 0 \/ (Mutant = "returnOnEmpty" /\ queue = {})
  ELSE (completed \/ interrupt)
EvTouch(t) == IF Top(t).k = "wait" THEN Touch(Top(t).id) ELSE TouchQ
EvLeave(t) == IF Top(t).k = "wait" THEN WaitReturn(t) ELSE (SetPc(t, "exit") /\ UNCHANGED returned)
NoHelp(t) == Mutant = "noHelp" /\ Top(t).k = "wait"

EvLoop(t) ==
  /\ Mode = "event"
  /\ \E k \in {"wait", "task"} : At(t, k, "loop")
  /\ EvTouch(t)
  /\ IF EvDone(t) THEN EvLeave(t) ELSE (SetPc(t, "pop") /\ UNCHANGED returned)
  /\ UNCHANGED <<queue, pending, freed, qfreed, interrupt, completed, alive, asleep, qheld,
                 epoch, sleepers, e0, runs, ranBy, ended, idle, spur>>

EvPop(t) ==
  /\ Mode = "event"
  /\ \E k \in {"wait", "task"} : At(t, k, "pop")
  /\ IF NoHelp(t)
     THEN SetPc(t, "reg") /\ UNCHANGED <<queue, runs, ranBy, spur, uaf, idle>>
     ELSE TryPop(t, "loop", "reg")
  /\ UNCHANGED <<pending, freed, qfreed, interrupt, completed, alive, asleep, qheld,
                 epoch, sleepers, e0, ended, returned>>

EvReg(t) ==
  /\ Mode = "event"
  /\ \E k \in {"wait", "task"} : At(t, k, "reg")
  /\ TouchQ
  /\ IF WakeAlways
     THEN /\ e0' = [e0 EXCEPT ![t] = epoch] /\ SetPc(t, "chk") /\ UNCHANGED sleepers
     ELSE /\ sleepers' = sleepers + 1 /\ SetPc(t, "reg2") /\ UNCHANGED e0
  /\ UNCHANGED <<queue, pending, freed, qfreed, interrupt, completed, alive, asleep, qheld,
                 epoch, runs, ranBy, ended, returned, idle, spur>>

EvReg2(t) ==
  /\ Mode = "event"
  /\ \E k \in {"wait", "task"} : At(t, k, "reg2")
  /\ TouchQ
  /\ e0' = [e0 EXCEPT ![t] = epoch]
  /\ SetPc(t, "chk")
  /\ UNCHANGED <<queue, pending, freed, qfreed, interrupt, completed, alive, asleep, qheld,
                 epoch, sleepers, runs, ranBy, ended, returned, idle, spur>>

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
  /\ UNCHANGED <<queue, pending, freed, qfreed, interrupt, completed, alive, asleep, qheld,
                 epoch, e0, runs, ranBy, ended, idle, spur>>

EvSleep(t) ==
  /\ Mode = "event"
  /\ \E k \in {"wait", "task"} : At(t, k, "slp")
  /\ TouchQ
  /\ IF epoch = e0[t]
     THEN asleep' = [asleep EXCEPT ![t] = "ev"] /\ UNCHANGED <<stack, sleepers, idle>>
     ELSE SetPc(t, "loop") /\ Unreg /\ UNCHANGED asleep /\ idle' = [idle EXCEPT ![t] = 0]
  /\ UNCHANGED <<queue, pending, freed, qfreed, interrupt, completed, alive, qheld,
                 epoch, e0, runs, ranBy, ended, returned, spur>>

----------------------------------------------------------------------------
(* The worker task: task::execute (px_query_task.cpp:30), pop (px_thread_safe_queue.cpp:64). *)

TaskStart(t) ==
  /\ At(t, "task", "idle")
  /\ alive[t]
  /\ SetPc(t, IF Mode = "event" THEN "loop" ELSE "get")
  /\ UNCHANGED <<queue, pending, freed, qfreed, interrupt, completed, alive, asleep, qheld,
                 epoch, sleepers, e0, runs, ranBy, ended, returned, uaf, idle, spur>>

TaskFast(t) ==
  /\ Mode # "event"
  /\ At(t, "task", "get")
  /\ TouchQ
  /\ IF queue # {}
     THEN \E j \in queue : queue' = queue \ {j} /\ StartJob(t, j, "get") /\ ZeroIdle
     ELSE SetPc(t, "qchk") /\ UNCHANGED <<queue, runs, ranBy, idle>>
  /\ UNCHANGED <<pending, freed, qfreed, interrupt, completed, alive, asleep, qheld,
                 epoch, sleepers, e0, ended, returned, spur>>

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
  /\ UNCHANGED <<pending, freed, qfreed, interrupt, completed, alive, asleep,
                 epoch, sleepers, e0, ended, returned, spur>>

TaskSlowWait(t) ==
  /\ Mode # "event"
  /\ At(t, "task", "qslp")
  /\ asleep' = [asleep EXCEPT ![t] = "q"]
  /\ qheld' = None
  /\ SetPc(t, "qchk")
  /\ UNCHANGED <<queue, pending, freed, qfreed, interrupt, completed, alive,
                 epoch, sleepers, e0, runs, ranBy, ended, returned, uaf, idle, spur>>

\* the task ends (~task -> worker_manager::pop_task)
TaskExit(t) ==
  /\ At(t, "task", "exit")
  /\ alive' = [alive EXCEPT ![t] = FALSE]
  /\ SetPc(t, "idle")
  /\ UNCHANGED <<queue, pending, freed, qfreed, interrupt, completed, asleep, qheld,
                 epoch, sleepers, e0, runs, ranBy, ended, returned, uaf, idle, spur>>

----------------------------------------------------------------------------
(* The root after R's run_jobs joined: push_last, release_workers (waits for every task to end),
   then the executors, the queue and the event are deleted (px_query_executor.cpp:175-180). *)

RootEnd(t) ==
  /\ At(t, "root", "end")
  /\ completed' = TRUE
  /\ IF Mode = "event"
     THEN epoch' = epoch + 1 /\ EvWakeAll /\ UNCHANGED qheld
     ELSE /\ qheld = None
          /\ asleep' = [s \in Threads |-> IF asleep[s] = "q" THEN "no" ELSE asleep[s]]
          /\ UNCHANGED <<qheld, epoch, idle>>
  /\ SetPc(t, "rel")
  /\ UNCHANGED <<queue, pending, freed, qfreed, interrupt, alive, sleepers, e0,
                 runs, ranBy, ended, returned, uaf, spur>>

\* release_workers returns once every task ended; the root's run_jobs returns; the late executor runs
RootRelease(t) ==
  /\ At(t, "root", "rel")
  /\ \A w \in Workers : ~alive[w]
  /\ IF Late THEN Call(t, "free", Frame("lroot", "xL", "own")) ELSE SetPc(t, "free")
  /\ UNCHANGED <<queue, pending, freed, qfreed, interrupt, completed, alive, asleep, qheld,
                 epoch, sleepers, e0, runs, ranBy, ended, returned, uaf, idle, spur>>

\* the late executor's run_jobs returned (its node's scan goes on)
LateEnd(t) ==
  /\ At(t, "lroot", "lend")
  /\ Ret(t)
  /\ UNCHANGED <<queue, pending, freed, qfreed, interrupt, completed, alive, asleep, qheld,
                 epoch, sleepers, e0, runs, ranBy, ended, returned, uaf, idle, spur>>

\* the query ends: ~query_executor of the root closes and deletes the queue and the event, and the
\* executors go with their XASL (query_executor.c:2615)
RootFree(t) ==
  /\ At(t, "root", "free")
  /\ freed' = [e \in Execs |-> TRUE]
  /\ qfreed' = TRUE
  /\ SetPc(t, "done")
  /\ UNCHANGED <<queue, pending, interrupt, completed, alive, asleep, qheld,
                 epoch, sleepers, e0, runs, ranBy, ended, returned, uaf, idle, spur>>

----------------------------------------------------------------------------
SpuriousWake ==
  \E t \in Threads :
    /\ asleep[t] # "no"
    /\ spur < MaxSpur
    /\ spur' = spur + 1
    /\ asleep' = [asleep EXCEPT ![t] = "no"]
    /\ UNCHANGED <<stack, queue, pending, freed, qfreed, interrupt, completed, alive, qheld,
                   epoch, sleepers, e0, runs, ranBy, ended, returned, uaf, idle>>

Step0(t) ==
  \/ AddOwn(t) \/ AddCount(t) \/ AddWake(t) \/ AddWake2(t) \/ AddDone(t)
  \/ JobStart(t) \/ JobWork(t) \/ JobClear(t) \/ JobFin(t) \/ JobWake(t) \/ JobWake2(t)
  \/ WaitOwn(t) \/ SpinCheck(t) \/ SpinPop(t) \/ ExitPop(t) \/ Join(t)
  \/ EvLoop(t) \/ EvPop(t) \/ EvReg(t) \/ EvReg2(t) \/ EvCheck(t) \/ EvSleep(t)
  \/ TaskStart(t) \/ TaskFast(t) \/ TaskSlowCheck(t) \/ TaskSlowWait(t) \/ TaskExit(t)
  \/ RootEnd(t) \/ RootRelease(t) \/ LateEnd(t) \/ RootFree(t)

Step(t) ==
  \/ AddPush(t)
  \/ Step0(t) /\ UNCHANGED refused

Finished == Len(stack[Main]) = 1 /\ Top(Main).pc = "done"

Next ==
  \/ \E t \in Threads : Step(t)
  \/ SpuriousWake /\ UNCHANGED refused
  \/ (Finished /\ UNCHANGED vars)

Spec == Init /\ [][Next]_vars /\ \A t \in Threads : WF_vars(Step(t))

----------------------------------------------------------------------------
(* Claims (MAP.md). *)

TypeOK ==
  /\ queue \subseteq Jobs
  /\ pending \in [Execs -> 0..Cardinality(Jobs)]
  /\ asleep \in [Threads -> {"no", "q", "ev"} \cup Execs]
  /\ sleepers \in 0..Cardinality(Threads)

\* C1: run_jobs of an executor returns only after every job it added has ended
JoinAfterAllEnded == \A e \in returned : JobsOf(e) \subseteq ended
\* C2: no job runs twice
RunsOnce == \A j \in Jobs : runs[j] <= 1
\* C3: nothing touches a deleted executor, queue or event
NoUseAfterFree == ~uaf
\* C5: a waiting thread does not poll
NoPolling == \A t \in Threads : idle[t] <= MaxSpur + 1
\* C6: no thread sleeps in an idle wait while a job is queued, unless a pusher's wake is on its way
WakeOnTheWay == \E t \in Threads : Len(stack[t]) > 0 /\ Top(t).pc \in {"cnt", "wk", "wk2"} /\ Top(t).k \in {"root", "job", "lroot"}
NoSleepWithWork ==
  (queue # {} /\ \E t \in Threads : asleep[t] \in {"q", "ev"}) => WakeOnTheWay
\* C4: the statement ends
Terminates == <>Finished

----------------------------------------------------------------------------
(* IndInv: the inductive invariant of the chosen design (Mode "event", WakeAlways, no InlineFail,
   Mutant "none"). Its conjuncts carry every safety claim (C1-C3, C5, C6); the rest describe the
   call stacks, where each job is, each executor's phase, and the counts the claims rest on. *)

\* the deepest stack: the root and its wait (or the task), a job and a wait frame per nested job (each
\* on one stack at most), and a leaf job
ASSUME Depth = 3 + 2 * Cardinality(Nested)
Idx == 2..Depth
IsJobAt(t, i, j) == i <= Len(stack[t]) /\ stack[t][i].k = "job" /\ stack[t][i].id = j
OnStack(j) == \E t \in Threads : \E i \in Idx : IsJobAt(t, i, j)

\* the jobs of an executor as a list of three (None pads the two-job executors): counts are sums, not
\* Cardinality, which Apalache encodes per element pair
J2(e) == IF e = "xL" THEN "L2" ELSE IF e = "R" THEN "2" ELSE IF e = "x1" THEN "12" ELSE "22"
J3(e) == IF Tree = "wide" /\ e = "R" THEN "3" ELSE IF Tree = "wide" /\ e = "x2" THEN "23" ELSE None
In(x, S) == IF x \in S THEN 1 ELSE 0
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
  ELSE IF f.pc \in {"own", "start"} THEN Fresh(c)
  ELSE IF f.pc \in {"add", "cnt", "wk"} THEN Adding(c, f)
  ELSE IF f.pc \in {"end", "clear"} THEN Done(c) /\ ~freed[c]
  ELSE IF f.pc \in {"rel", "free"} THEN Done(c) /\ ~freed[c] /\ completed
  ELSE IF f.pc = "lend" THEN Done(c) /\ ~freed[c]
  ELSE IF f.pc = "done" THEN Done(c)
  ELSE (Done(c) /\ freed[c]) \/ (Fresh(c) /\ interrupt)   \* "fin", "fwk": cleared, or skipped on the interrupt

\* @type: ({k: Str, id: Str, pc: Str, todo: Set(Str)}) => Set(Str);
TopPcs(f) ==
  IF f.k = "root" THEN {"own", "add", "cnt", "wk", "end", "rel", "free", "done"}
  ELSE IF f.k = "lroot" THEN {"own", "add", "cnt", "wk", "lend"}
  ELSE IF f.k = "wait" THEN {"own", "loop", "pop", "reg", "chk", "slp"}
  ELSE IF f.k = "task" THEN {"idle", "loop", "pop", "reg", "chk", "slp", "exit"}
  ELSE IF f.id \in Nested THEN {"start", "own", "add", "cnt", "wk", "clear", "fin", "fwk"}
  ELSE {"start", "work", "fin", "fwk"}
LowerPc(k) == IF k = "job" THEN "clear" ELSE IF k = "lroot" THEN "lend" ELSE "loop"
\* the main thread runs the late executor
InLate == stack[Main][1].pc = "free" /\ Len(stack[Main]) > 1
\* the root has started the worker tasks
Started == Len(stack[Main]) > 1 \/ stack[Main][1].pc \in {"end", "rel", "free", "done"}

IStackShape ==
  \A t \in Threads :
    /\ 1 <= Len(stack[t]) /\ Len(stack[t]) <= Depth
    /\ stack[t][1].k = (IF t = Main THEN "root" ELSE "task")
    /\ stack[t][1].id = (IF t = Main THEN "R" ELSE None)
    /\ t = Main /\ InLate =>
         /\ Late /\ Len(stack[t]) <= 4
         /\ stack[t][2].k = "lroot" /\ stack[t][2].id = "xL"
         /\ Len(stack[t]) >= 3 => stack[t][3].k = "wait" /\ stack[t][3].id = "xL"
         /\ Len(stack[t]) = 4 => stack[t][4].k = "job" /\ stack[t][4].id \in {"L1", "L2"}
    /\ ~(t = Main /\ InLate) =>
       \A i \in Idx : i <= Len(stack[t]) =>
         /\ stack[t][i].k = (IF (t = Main) = (i % 2 = 0) THEN "wait" ELSE "job")
         /\ stack[t][i].k = "job" => stack[t][i].id \in Jobs /\ stack[t][i].id \notin {"L1", "L2"}
         /\ stack[t][i].k = "wait" =>
              /\ stack[t][i - 1].k = "root" \/ stack[t][i - 1].id \in Nested
              /\ stack[t][i].id = (IF stack[t][i - 1].k = "root" THEN "R" ELSE ExecOf(stack[t][i - 1].id))
    /\ Len(stack[t]) > 1 /\ t = Main => stack[t][1].pc \in {"end", "free"}
    /\ Len(stack[t]) > 1 /\ t = Main /\ stack[t][1].pc = "end" => ~InLate
    /\ \A i \in {1} \cup Idx : i <= Len(stack[t]) =>
         /\ i < Len(stack[t]) /\ i > 1 => stack[t][i].pc = LowerPc(stack[t][i].k)
         /\ i < Len(stack[t]) /\ i = 1 /\ t # Main => stack[t][i].pc = "loop"
         /\ i = Len(stack[t]) => stack[t][i].pc \in TopPcs(stack[t][i])
         /\ stack[t][i].pc \notin {"add", "cnt", "wk"} => stack[t][i].todo = {}
         /\ stack[t][i].k \in {"wait", "task"} => stack[t][i].todo = {}
         /\ stack[t][i].k = "job" /\ stack[t][i].id \notin Nested => stack[t][i].todo = {}

IThreads ==
  /\ \A t \in Threads : asleep[t] \in {"no", "ev"} /\ e0[t] <= epoch /\ idle[t] >= 0
  /\ \A t \in Threads : asleep[t] = "ev" => Top(t).k \in {"wait", "task"} /\ Top(t).pc = "slp" /\ e0[t] = epoch
  /\ sleepers = 0 /\ qheld = None /\ epoch >= 0 /\ spur >= 0 /\ spur <= MaxSpur
  /\ \A w \in Workers :
       /\ Len(stack[w]) > 1 \/ stack[w][1].pc # "idle" => alive[w]
       /\ ~Started => ~alive[w] /\ Len(stack[w]) = 1 /\ stack[w][1].pc = "idle"
       /\ Started /\ ~alive[w] => completed \/ interrupt

IJobs ==
  /\ queue \subseteq Jobs /\ ended \subseteq Jobs /\ refused \subseteq Jobs /\ returned \subseteq Execs
  /\ \A e \in Execs : OwnJob(e) \notin queue
  /\ \A j \in Jobs :
       /\ runs[j] \in {0, 1}
       /\ j \in queue => runs[j] = 0
       /\ j \in ended => runs[j] = 1 \/ j \in refused
       /\ j \in refused => runs[j] = 0 /\ j \notin queue /\ j \in ended /\ interrupt
       /\ runs[j] = 1 /\ j \notin ended => OnStack(j)
  /\ \A t1, t2 \in Threads : \A i1, i2 \in Idx :
       /\ i1 <= Len(stack[t1]) /\ i2 <= Len(stack[t2])
       /\ stack[t1][i1].k = "job" /\ stack[t2][i2].k = "job" /\ stack[t1][i1].id = stack[t2][i2].id
       => t1 = t2 /\ i1 = i2
  /\ \A t \in Threads : \A i \in Idx : i <= Len(stack[t]) /\ stack[t][i].k = "job" =>
       /\ runs[stack[t][i].id] = 1
       /\ (stack[t][i].id \in ended <=> stack[t][i].pc = "fwk")

IExecs ==
  /\ \A e \in Execs : pending[e] >= 0
  /\ ExecInv("R", stack[Main][1], Len(stack[Main]) > 1 /\ stack[Main][1].pc = "end")
  /\ Late =>
       IF InLate THEN ExecInv("xL", stack[Main][2], Len(stack[Main]) > 2)
       ELSE IF stack[Main][1].pc \in {"free", "done"} THEN Done("xL") /\ (~freed["xL"] \/ qfreed)
       ELSE Fresh("xL") /\ ~freed["xL"]
  /\ \A j \in Nested : \A t \in Threads : \A i \in Idx :
       IsJobAt(t, i, j) => ExecInv(ExecOf(j), stack[t][i], i < Len(stack[t]))
  /\ \A j \in Nested :
       /\ runs[j] = 0 => Fresh(ExecOf(j))
       /\ j \in ended => (Done(ExecOf(j)) /\ freed[ExecOf(j)]) \/ (Fresh(ExecOf(j)) /\ interrupt)
  /\ \A e \in Execs : \A t \in Threads : \A i \in Idx :
       i <= Len(stack[t]) /\ stack[t][i].k = "wait" /\ stack[t][i].id = e =>
         runs[OwnJob(e)] = (IF stack[t][i].pc = "own" /\ i = Len(stack[t]) THEN 0 ELSE 1)
  /\ completed <=> stack[Main][1].pc \in {"rel", "free", "done"}
  /\ stack[Main][1].pc \in {"free", "done"} => \A w \in Workers : ~alive[w] /\ Len(stack[w]) = 1
  /\ qfreed <=> stack[Main][1].pc = "done"
  /\ qfreed => /\ \A e \in Execs : freed[e]
               /\ \A w \in Workers : ~alive[w]
  /\ ~uaf

IWake ==
  \A t \in Threads :
    Top(t).k \in {"wait", "task"} /\ Top(t).pc = "slp" /\ e0[t] = epoch /\ queue # {} => WakeOnTheWay

IIdle ==
  \A t \in Threads :
    /\ idle[t] <= spur + 1
    /\ Top(t).k \in {"wait", "task"} /\ Top(t).pc \in {"loop", "pop"} => idle[t] <= spur
    /\ Top(t).pc \in {"reg", "chk", "slp"} /\ queue # {} => idle[t] <= spur
    /\ Top(t).k = "job" /\ Top(t).pc = "fwk" => idle[t] = 0

IndInv ==
  /\ IStackShape
  /\ IThreads
  /\ IJobs
  /\ IExecs
  /\ IWake
  /\ IIdle
  /\ JoinAfterAllEnded
  /\ RunsOnce
  /\ NoUseAfterFree
  /\ NoPolling
  /\ NoSleepWithWork

Sym == Permutations(Workers)

\* develop's spin loop's ghost cap, so its other claims can be checked
IdleCap == \A t \in Threads : idle[t] <= MaxSpur + 2

\* witnesses (expected violated)
NotHelped == \A j \in Jobs : ranBy[j] # Main \/ Owner(j) = "R" \/ j = OwnJob(Owner(j))
NotNestedWaiterSlept == ~(\E t \in Threads : asleep[t] = "ev" /\ Len(stack[t]) > 0 /\ Top(t).k = "wait" /\ Top(t).id # "R")
NotInterruptedEnd == ~(Finished /\ interrupt)
NotThreeWorkersBusy == Cardinality({w \in Workers : alive[w] /\ Len(stack[w]) >= 2}) < 3
NotWorkerSlept == ~(\E w \in Workers : asleep[w] = "ev")
NotLateHelped == ~("xL" \in returned /\ ranBy["L2"] = Main)
NotRefused == refused = {}
=============================================================================
