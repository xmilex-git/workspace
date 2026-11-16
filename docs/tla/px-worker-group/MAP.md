# PxWorkerGroup (draft) — one worker budget per statement for the parallel subquery executor

**Status: draft, grilling paused (2026-11-16).** Split from `docs/tla/px-subquery-join/` at the user's
request: that directory now covers only the wait and wake without a polling mutex (oracle-gap#20);
this one keeps the budget design (D13-D18, claims C7-C9) for its own issue, xmilex-git/workspace#644. The spec here is the
combined v2 model as it stood at the split: TLC passes main, nest-main, wide, liveness and scale-3w
and every mutant fails as listed below; IndInv holds on every reachable state of those cfgs, but its
inductive check (Apalache) did not finish, so `tools/tla/tla-check` does not print `RESULT: OK` for
this directory. Resume with the grill (the decisions below are the starting point) before re-checking.

---

# PxSubqueryJoin — the parallel subquery executor's join without a polling mutex, and one worker budget per statement (oracle-gap #20)

Scope: `src/query/parallel/px_query_execute/` (`px_query_job.hpp`, `px_query_executor.cpp`,
`px_query_task.cpp`), `src/query/parallel/px_thread_safe_queue.cpp`, `px_worker_manager.cpp`,
`px_worker_manager_global.cpp`, the aptr dispatch of `qexec_execute_mainblock_internal`
(`query_executor.c:22386-22490`), and the parallel operators' reservations (`px_scan.cpp:442`,
`query_hash_join.c:2025-2052`, `external_sort.c:5070-5095`, `heap_file.c:10100-10127`) at CUBRID
develop `41ca53ce7` (identical to `origin/develop` 4bf2b2e32 in these files), read in
`~/dev/cubrid-worktree/develop-41ca53ce7`.

Motivation: xmilex-git/oracle-gap#20 (lane 2 diagnosis, 2026-11-14): on TPC-H Q21 with `parallelism=1`
31% of the server's `instructions:u` is `pthread_mutex_lock/unlock` of `join_context::m_mutex`, taken
twice per turn of `run_jobs`'s wait loop (`px_query_executor.cpp:146-170`) while the one worker scans
lineitem — about 35 million turns, proportional to the worker's time, not to rows or jobs. The user
added (2026-11-15): trees of uncorrelated subqueries three levels deep (2 → 4 → 8) with three or more
workers, and the workers each subquery job's parallel operators reserve on their own (today capped at 2).

Status: design verified (see `## Result`).

trace-exempt: a design with no implementation yet; the implementation must refine this spec (cubrid-tla step 9) and carry its own trace validation.


## Claim and sources

| # | Claim | Kind | Source |
|---|---|---|---|
| C1 | `run_jobs` of an executor returns only after every job it added has ended, so the caller reads finished list files. | safety | `run_jobs` step 5 `join_jobs` (px_query_executor.cpp:173); query_executor.c:22496 comment "only after run_jobs (): a parallel subquery executor may run the producer on a worker" |
| C2 | Every job runs at most once. | safety | one pop per pushed job (`try_pop_fast` / `pop_slow` CAS on the slot sequence); `m_job` run once by `run_jobs` step 3 |
| C3 | Nothing touches an executor's join state, the statement's queue, its wake event or its worker group after it is deleted. | safety | `qexec_clear_xasl_for_parallel_aptr` deletes the job's `px_executor` right after its `run_jobs` (query_executor.c:2615 via px_query_task.cpp:196); `~query_executor` deletes the queue (px_query_executor.cpp:87) |
| C4 | The statement ends: every `run_jobs` returns and every worker task ends, on the error and interrupt paths too. | liveness | any query must finish; `execute_job_internal`'s early exit (px_query_task.cpp:85-91) |
| C5 | A thread waiting in `run_jobs` does not poll: between two events (a push, a pop, a job end, a wake) it makes a bounded number of failed `try_pop` and takes no mutex per turn. | safety (ghost `idle`) | oracle-gap#20: 70 M lock/unlock pairs in one Q21 run, proportional to the worker's scan time; D2 |
| C6 | No thread sleeps in an idle wait while a job is queued, unless the pusher's wake is on its way to it. | safety | proposed by the model, adopted (D4): develop's fast push notifies `m_not_empty` without the queue mutex (px_thread_safe_queue.cpp:215), so the worker can sleep through a push (`mutant-develop-lost-wakeup`) |
| C7 | The statement holds at most B workers at once — its subquery workers and every parallel operator inside its jobs together — and takes none from the server pool after the root's start. | safety | the user (2026-11-15): "병렬부질의 안에서 병렬 스캔 worker를 각각 예약해서 worker를 과다사용하는 문제"; D13 |
| C8 | No job waits in the queue while the statement's group has a free unit and no worker is free to take it, unless a worker start is on its way. | safety | proposed by the model, adopted (D15): with fixed workers an operator never gets a unit (`option-fixed-op-starved`) |
| C9 | When the statement ends every unit is back in its group (and the group goes back to the server pool whole). | safety | D13: the group is reserved once at the root and released once at its end |

## Decisions

| # | Decision | Status | Evidence |
|---|---|---|---|
| D1 | Directions 1 (`parallelism < 2` gives no subquery worker) and 3 (the runtime filter an executor disables, query_executor.c:22289) of oracle-gap#20 are out of this model; it covers direction 2's question (the wait) and the worker budget. | locked (Q1) | — |
| D2 | C5 means: a waiter takes a mutex only on the sleep/wake path; the per-executor count is an atomic. | locked (Q2) | `mutant-develop-spin` violates NoPolling |
| D3 | One wake event per statement (epoch + mutex + cv), owned by the root executor and deleted with it; every executor's waiters sleep on it. The job that takes its executor's count to 0 reads the event pointer before its `fetch_sub`, then wakes the event. | locked (Q3) | `mutant-wake-via-exec` (the wake through the owner executor) violates NoUseAfterFree; issue direction 2 (`mutant-exit-on-empty`) deadlocks |
| D4 | Adopt C6; the worker's idle wait is the same event wait (no separate `m_not_empty` wait). | locked (Q4) | `mutant-develop-lost-wakeup` violates NoSleepWithWork |
| D5 | Every waker locks the event mutex and calls `notify_all` (no sleeper count). | locked (Q5) | `mutant-wake-one` deadlocks; `mutant-no-push-wake`, `mutant-no-queue-recheck` violate NoSleepWithWork |
| D6 | Two or more workers are checked by the scale cfg (3 workers, the two-level tree); the three-level tree by the inductive check. | locked (Q6) | `scale-3w`, `PxSubqueryJoinInd.apalache-bin3` |
| D7 | The inline-aptr error that skips `run_jobs` after pushes is a develop defect, filed separately (xmilex-git/workspace#643); the design assumes it fixed. | locked (Q7) | `mutant-develop-inline-fail`, `mutant-inline-fail` violate NoUseAfterFree |
| D8 | C4 assumes weak fairness per thread and finitely many spurious failures (`MaxSpur`). | locked (Q8) | `liveness` |
| D9 | A waiter helps: it pops any queued job, of any executor, until the queue is empty, re-checks, then sleeps (as develop helps). | locked (Q9) | `mutant-no-help` deadlocks; `witness-helped` |
| D10 | On the interrupt a worker ends (as develop's `pop_slow`). | locked (Q10) | `witness-interrupted-end` |
| D11 | `release_workers`' `wait_workers` yield loop stays: it starts after every job ended and lasts until the tasks return. | locked (Q11) | `RootRelease` |
| D12 | An ADR after `RESULT: OK`; the JIRA issue at implementation time. | locked (Q12) | the budget ADR when #644 ends (0059 holds the wait design only) |
| D13 | The statement's worker group: B = min(parallelism, the need found by one traversal of the root XASL), reserved once at the root by one `try_reserve_workers`; subquery workers and every parallel operator inside a job take units only from the group (min degree 2, else serial), and give them back to it. | locked (Q13) | `mutant-develop-budget`, `mutant-pool-budget` violate WithinBudget |
| D14 | Elastic subquery workers: a push starts a worker when the group has a unit and the queue holds more jobs than free and starting workers; a worker that finds the queue empty gives its unit back, re-checks the queue, and ends. An operator that gives units back starts as many workers as the queue can use. | locked (Q14) | `option-fixed-op-starved` (fixed workers: no operator ever gets a unit); `mutant-no-exit-recheck`, `mutant-no-release-spawn` violate NoIdleUnitWithWork |
| D15 | Adopt C8. | locked (Q15) | — |
| D16 | Inside the group, units go first-come (operators and subquery workers alike). | locked (Q16) | `witness-op-got-units` |
| D17 | Fairness between sessions (one statement's group against another's) is out of scope; the server pool's `try_reserve_workers` stays the arbiter. | locked (Q17) | — |
| D18 | A nested statement (SQL from a stored procedure) gets its own group from its own root; the thread's armed group is saved when the nested statement starts and restored when it ends. Today such SQL arrives through CAS on another thread (a separate statement); after the CAS fold it runs on the same thread, where clearing the link would send the outer statement's later operators to the server pool and break C7. Not modeled (fault table). | locked (Q18) | — |

## Refinement map (model -> code at 41ca53ce7; "redesign" rows name what the implementation adds)

| Model | Code | One step because |
|---|---|---|
| `stack` frames `root`/`job`/`wait`/`task` | `qexec_execute_mainblock_internal` of the root executor's node / `execute_job_internal` / `query_executor::run_jobs` / `task::execute` | call structure; a thread's frames nest as its C stack does |
| `RootGroup` | develop: `try_reserve_workers` of the subquery worker (query_executor.c:22402); redesign: one `worker_manager_global::try_reserve_workers` (px_worker_manager_global.cpp:95, one CAS) of B units | one CAS |
| `AddOwn` | `add_job` first call: `m_job = job(..)`, `add_running_jobs` (px_query_executor.cpp:108-113) | `m_job` is executor-local; the increment is one atomic RMW (redesign) / one `m_mutex` section (develop) |
| `AddPush` | `add_job`: `m_job_execution_queue->push` (:115) → `try_push_fast` (px_thread_safe_queue.cpp:172-218); develop's `m_not_empty.notify_one ()` without the queue mutex (:215) | the slot is published by `ready.store` + `fetch_add`; develop's notify is folded into the step (generous to develop) |
| `AddCount` | `add_running_jobs` after the push (:117) | one atomic RMW / one `m_mutex` section |
| `AddWake` | redesign: epoch increment and `notify_all` under the statement event's mutex after each push | one event-mutex section |
| `AddWake2`, `JobWake2`, `EvReg2` | the rejected "wake only a registered sleeper" variant (WakeAlways = FALSE) | — (option) |
| `AddSpawn` | redesign: after the push, one CAS on the group's free count, then `worker_manager::push_task` of a subquery task | the CAS is the decision; the task push hands the unit to the pool thread |
| `AddDone` root | `run_jobs` steps 2-3: `new task` + `push_task` (:133-138) — develop one task on the reserved worker; "fixed" every worker | worker start is the task push |
| `AddDone` InlineFail | a sibling aptr flagged `XASL_NO_PARALLEL_SUBQUERY` fails inline (query_executor.c:22427-22436) → `GOTO_EXIT_ON_ERROR`, skipping `run_jobs` (:22481) | the error exit (`exit_on_error:` 23174) does not join the executor |
| `JobStart` | interrupt check at the top of `execute_job_internal` (px_query_task.cpp:85-91) | one atomic load of `interrupt::m_code` |
| `JobReserve` | the operator's `try_reserve_workers` (px_scan.cpp:442, 909, 1453; query_hash_join.c:2025-2052; external_sort.c:5070-5095; heap_file.c:10100-10127) — develop from the server pool; redesign from the group armed on the thread (a subquery worker finds the statement through `m_px_orig_thread_entry`, px_query_task.cpp:116-124) | one CAS on the pool / group count |
| `JobWork` | `qexec_execute_mainblock` of the job (:128) and its error branch setting the px interrupt (:141-190) | the job's own work touches no join state |
| `JobOpRelease` | the operator's `worker_manager::release_workers` (px_worker_manager.cpp:78-87; px_scan.cpp:588 ...) → the group | one atomic RMW on the group count |
| `JobOpSpawn` | redesign: the releaser starts subquery workers on the freed units while the queue can use them | one CAS + task push per worker |
| `JobClear` | `qexec_clear_xasl_for_parallel_aptr (cur_thread_p, xasl, true)` (:196) → `delete xasl->px_executor` (query_executor.c:2615) | thread-local until the delete |
| `JobFin` (spin/exitOnEmpty) | `sub_running_jobs` (px_query_job.hpp:56-64): decrement and `notify_one` under `m_mutex` | one `m_mutex` section |
| `JobFin`, `JobWake` (event) | redesign: read the statement event pointer, `fetch_sub` on the executor's atomic count; the job that took it to 0 then bumps the epoch and `notify_all` under the event mutex | an atomic RMW, then the event's mutex section |
| `TryPop` | `try_pop_fast` (px_thread_safe_queue.cpp:221-271): fails on empty, on a not-ready head slot, on a lost CAS | the CAS is the linearization point; failure on a non-empty queue is the `spur` budget |
| `SpinCheck`, `SpinPop` | develop `run_jobs` loop (px_query_executor.cpp:146-170): `get_running_jobs` (lock/unlock `m_mutex`) and `try_pop` | each `get_running_jobs` is one `m_mutex` section |
| `ExitPop` | issue direction 2: leave the loop on the first failed `try_pop` | — (option) |
| `Join` | `join_jobs` (px_query_job.hpp:70-74): `m_cv.wait (lock, pred)` | predicate check and wait are atomic under `m_mutex` |
| `EvLoop`, `EvPop` | redesign wait: read the atomic count (0: return), else `try_pop` and run the job | one atomic load / one pop |
| `EvReg`, `EvCheck`, `EvSleep` | redesign: read the epoch, re-check the count and the queue, then under the event mutex sleep while the epoch is unchanged | `EvSleep`'s epoch check and wait are one event-mutex section |
| `TaskStart`, `TaskFast` | `task::execute` → `get_job` → `pop` fast path (px_thread_safe_queue.cpp:64-71) | fast path ignores the interrupt |
| `TaskSlowCheck`, `TaskSlowWait` | `pop_slow` (:334-356): `is_empty`/`m_push_completed`/interrupt checked under the queue mutex, then `m_not_empty.wait` | two steps: a notify without the mutex can fall between them |
| `TaskPickup` | a pool thread runs the pushed subquery `task::execute` (worker_manager pool) | the unit was taken by the starter |
| `TaskUnitRelease`, `TaskUnitRecheck` | redesign: the worker decrements the free-worker counter and gives its unit back (one atomic RMW), then re-checks the queue and takes a unit back by CAS if a job is there | two atomics: a push between them sees the unit free and starts a worker itself |
| `TaskExit` | `pop` returns false → `task::execute` ends → `~task` → `worker_manager::pop_task`; a unit still held goes back to the group | — |
| `RootEnd` | `run_jobs` after the join: `push_last` (:177; px_thread_safe_queue.cpp:164-169) — redesign: set completed, bump the epoch and `notify_all` | one queue-mutex / event-mutex section |
| `RootRelease` | `release_workers` → `wait_workers` (yield loop until every task ended, px_worker_manager.cpp:97), then `~query_executor` deletes queue, event and executors and returns the group to the server pool | the yield loop is short: it starts after every job ended (D11) |
| `interrupt` | the root executor's `m_interrupt` (the task's `m_interrupt_p`) | simplification: one statement interrupt; per-executor interrupts of nested `run_jobs` are not modeled |
| `FreeWorkers` | redesign: a free-worker counter a worker increments when it comes back to its loop and decrements before it pops or gives its unit back | the starter's decision reads one atomic |

Code facts the model relies on:
- develop runs one worker task per statement: `compute_parallel_degree (SUBQUERY)` returns `MIN (1, parallelism)` (px_parallel.cpp:142-155), `assert (n_workers_to_reserve == 1)` (query_executor.c:22397), and `*m_is_task_running_p` is shared by every executor of the statement (px_query_executor.cpp:66).
- Every executor of the statement pushes to the one queue the root created (px_query_executor.cpp:65).
- All `add_job` calls of an executor precede its `run_jobs` on the same thread (query_executor.c:22423, 22481).
- Every parallel operator reserves through `worker_manager::try_reserve_workers` → `worker_manager_global::try_reserve_workers` (px_worker_manager_global.cpp:95): that is the one place D13's group is consulted.
- WakeAlways needs no seq_cst ordering: every wake and every sleep decision is under the event mutex, and the count and queue reads before it are acquire loads of release writes.

## Properties

`JoinAfterAllEnded` (C1), `RunsOnce` (C2), `NoUseAfterFree` (C3), `Terminates` (C4, liveness cfg),
`NoPolling` (C5), `NoSleepWithWork` (C6), `WithinBudget` (C7), `NoIdleUnitWithWork` (C8), `NoLeak`
(C9); `TypeOK`; `IndInv` (named conjuncts IStackShape, IThreads, IJobs, IExecs, IBudget, IWake, IIdle
and the nine safety properties).

## Fault model

| Fault | Modeled | Where |
|---|---|---|
| error return | yes | `JobWork` (WorkFail) sets the interrupt; `AddDone` InlineFail (D7) |
| interrupt / cancel | yes | the interrupt flag: `JobStart` early exit, a worker ends (D10) |
| lock timeout, deadlock victim | as an error return | inside a job's work |
| conditional latch failure | n/a | no page latch in the join protocol |
| OOM | as an error return | `qexec_deep_copy_xasl_state` failure (px_query_task.cpp:108) fails the job like a work error |
| crash / kill -9 | n/a | no durable state |
| spurious wakeup | yes | `SpuriousWake` within `MaxSpur` |
| failed try_pop on a non-empty queue | yes | `TryPop` within `MaxSpur` (lost CAS, weak CAS) |
| the server pool has no worker for the group | as a smaller B | `B` ranges over every natural in the inductive check (B = 0: everything serial on the main thread) |
| concurrent DML, vacuum, checkpoint, HA | n/a | inside a job's work, not in the join protocol |
| nested statement (SP SQL) | n/a by D18 | a separate statement with its own group; the thread's armed group is saved and restored around it |

Environment assumptions (C4): weak fairness of every thread's step (each thread is scheduled), and
finitely many spurious failures and wakeups (`MaxSpur`). The server pool always has a thread for a
pushed task once a unit was taken for it (`TaskPickup`): the unit came from the statement's group,
which the pool already counted.

## Mutants

| cfg | Mutant | Claim it breaks | Result |
|---|---|---|---|
| `mutant-return-on-empty` | a waiter returns when the queue is empty, not when its count is 0 | C1 | violation JoinAfterAllEnded |
| `mutant-pop-keeps` | a pop leaves the job in the queue | C2 | violation RunsOnce |
| `mutant-develop-inline-fail` | develop (wait as exitOnEmpty, MaxSpur 0), InlineFail | C3 | violation NoUseAfterFree |
| `mutant-inline-fail` | the redesign with InlineFail (workspace#643 unfixed) | C3 | violation NoUseAfterFree |
| `mutant-wake-via-exec` | the last job's wake goes through (or lives in) the owner executor | C3 | violation NoUseAfterFree |
| `mutant-exit-on-empty` | issue direction 2: leave on the first failed try_pop, cv wait on the executor | C4 | deadlock |
| `mutant-no-help` | a waiter never pops (B = 1: one elastic worker) | C4 | deadlock |
| `mutant-wake-one` | notify_one on the event (two-level tree, B = 2) | C4 | deadlock |
| `mutant-develop-spin` | develop's wait loop | C5 | violation NoPolling |
| `mutant-develop-lost-wakeup` | develop's queue wait (spin loop capped by `IdleCap`) | C6 | violation NoSleepWithWork |
| `mutant-no-queue-recheck` | the waiter re-checks only its count before sleeping | C6 | violation NoSleepWithWork |
| `mutant-no-push-wake` | a push does not wake the event | C6 | violation NoSleepWithWork |
| `mutant-develop-budget` | develop: subquery worker and operators reserve from the server pool | C7 | violation WithinBudget |
| `mutant-pool-budget` | the redesign's wait, operators still reserve from the pool | C7 | violation WithinBudget |
| `mutant-no-exit-recheck` | an elastic worker ends without re-checking the queue (B = 1, Want 0) | C8 | violation NoIdleUnitWithWork |
| `mutant-no-release-spawn` | an operator's released units start no worker | C8 | violation NoIdleUnitWithWork |
| `mutant-exit-keeps-unit` | a worker that ends on the interrupt or push_last keeps its unit | C9 | violation NoLeak |

## Witnesses

| cfg | Outcome reached |
|---|---|
| `witness-helped` | the main thread runs a job of a nested executor (helping, D9) |
| `witness-nested-waiter-slept` | a nested executor's waiter sleeps on the statement event |
| `witness-interrupted-end` | the statement ends after an interrupt |
| `witness-op-got-units` | a leaf's operator gets units from the group (D14, D16) |
| `witness-three-busy` | three workers run jobs at once (two-level tree) |

## Options compared (not chosen)

| cfg | Option | Result |
|---|---|---|
| `option-fixed` | fixed subquery workers (all start at the root, hold their unit to the end) | passes C1-C7, C9 |
| `option-fixed-op-starved` | the same, with `NotOpGotUnits` | no operator ever gets a unit (B = 3, two workers): the reason for D14 |

## Bounds

| cfg | Tree | Workers | B / Want | Faults |
|---|---|---|---|---|
| main | base (R: 1, 2; x2: 21, 22) | 2 | 3 / 2 | WorkFail, MaxSpur 1 |
| `nest-main` | nestM (the nested executor on the main thread) | 2 | 3 / 2 | WorkFail, MaxSpur 1 |
| `wide` | wide (three jobs per executor) | 2 | 3 / 2 | MaxSpur 1 |
| `liveness` | base | 2 | 3 / 2 | WorkFail, MaxSpur 1 |
| `scale-3w` | bin2 (2 → 4, 6 jobs) | 3 | 4 / 2 | — |
| `PxSubqueryJoinInd.apalache-base` | base | 2 | every B, Want | WorkFail, every MaxSpur |
| `PxSubqueryJoinInd.apalache-bin3` | bin3 (2 → 4 → 8, 14 jobs, 7 executors) | 3 | every B, Want | WorkFail, every MaxSpur |

The three-level tree is not explored by TLC: with 3 workers the run passed 440 million distinct
states at depth 101 without a violation and its queue still grew (2026-11-16, stopped at 9 h); the
inductive check covers it for every reachable state instead.

## Dead expressions

Union over the pass cfgs (main, nest-main, wide, liveness, scale-3w, option-fixed, option-fixed-op-starved). Every one is a mode, option or mutant branch, or a helper body counted at such a call site; none maps to a path of the chosen design that the cfgs fail to reach.

| Lines | Why TLC never evaluates them |
|---|---|
| `PxSubqueryJoin.tla:188` `PxSubqueryJoin.tla:189` `PxSubqueryJoin.tla:190` `PxSubqueryJoin.tla:192` `PxSubqueryJoin.tla:193` `PxSubqueryJoin.tla:194` `PxSubqueryJoin.tla:199` `PxSubqueryJoin.tla:200` `PxSubqueryJoin.tla:477` | helper operator bodies (SetPc, Call, Ret, Touch, TouchQ, ZeroIdle, StartJob, WaitReturn): TLC counts an operator body once per call site, and these are its call sites inside the actions the rows below explain |
| `PxSubqueryJoin.tla:206` `PxSubqueryJoin.tla:209` `PxSubqueryJoin.tla:210` | EvWakeAll's Mutant "wakeOne" branch (`mutant-wake-one` only) |
| `PxSubqueryJoin.tla:211` `PxSubqueryJoin.tla:212` | EvWakeAll counted at its WakeAlways = FALSE call sites (AddWake2, JobWake2; D5) |
| `PxSubqueryJoin.tla:217` `PxSubqueryJoin.tla:220` `PxSubqueryJoin.tla:423` `PxSubqueryJoin.tla:687` `PxSubqueryJoin.tla:688` | Mode "spin" / "exitOnEmpty" branches: develop's queue notify, `sub_running_jobs` and `push_last` (the develop mutants only) |
| `PxSubqueryJoin.tla:291` `PxSubqueryJoin.tla:298` `PxSubqueryJoin.tla:300` `PxSubqueryJoin.tla:435` `PxSubqueryJoin.tla:442` `PxSubqueryJoin.tla:444` `PxSubqueryJoin.tla:548` `PxSubqueryJoin.tla:556` `PxSubqueryJoin.tla:558` `PxSubqueryJoin.tla:561` | WakeAlways = FALSE branches: the rejected registered-sleeper wake (D5) |
| `PxSubqueryJoin.tla:318` `PxSubqueryJoin.tla:319` `PxSubqueryJoin.tla:320` `PxSubqueryJoin.tla:321` | FixedStart's "fixed" branch: dead in the elastic cfgs (main, nest-main, wide, liveness, scale-3w); fires in `option-fixed*` |
| `PxSubqueryJoin.tla:232` `PxSubqueryJoin.tla:233` `PxSubqueryJoin.tla:309` `PxSubqueryJoin.tla:322` `PxSubqueryJoin.tla:396` | Spawn, AddSpawn, FixedStart's elastic branch and JobOpSpawn: dead in the SqPolicy "fixed" cfgs (`option-fixed`, `option-fixed-op-starved`); fire in the elastic cfgs |
| `PxSubqueryJoin.tla:590` `PxSubqueryJoin.tla:591` `PxSubqueryJoin.tla:594` `PxSubqueryJoin.tla:601` `PxSubqueryJoin.tla:602` `PxSubqueryJoin.tla:603` `PxSubqueryJoin.tla:622` `PxSubqueryJoin.tla:623` `PxSubqueryJoin.tla:624` `PxSubqueryJoin.tla:626` `PxSubqueryJoin.tla:628` | TaskUnitRelease, TaskUnitRecheck, TaskPickup: elastic only, dead in `option-fixed*` |
| `PxSubqueryJoin.tla:614` | TaskStart: SqPolicy "fixed" only, dead in the elastic cfgs |
| `PxSubqueryJoin.tla:335` | AddDone's InlineFail branch: workspace#643, D7 (`mutant-inline-fail`, `mutant-develop-inline-fail` only) |
| `PxSubqueryJoin.tla:374` | JobWork's failure: WorkFail = FALSE in `wide`, `scale-3w`, `option-fixed-op-starved` (the main, nest-main and liveness cfgs fire it) |
| `PxSubqueryJoin.tla:382` `PxSubqueryJoin.tla:383` `PxSubqueryJoin.tla:384` `PxSubqueryJoin.tla:385` `PxSubqueryJoin.tla:387` | JobOpRelease in `option-fixed-op-starved`: no operator ever gets a unit there, which is what that cfg shows |
| `PxSubqueryJoin.tla:453` | TryPop's Mutant "popKeeps" arm (`mutant-pop-keeps` only) |
| `PxSubqueryJoin.tla:456` `PxSubqueryJoin.tla:459` `PxSubqueryJoin.tla:460` `PxSubqueryJoin.tla:462` `PxSubqueryJoin.tla:464` `PxSubqueryJoin.tla:465` | TryPop counted at its develop call sites (SpinPop, ExitPop) |
| `PxSubqueryJoin.tla:485` `PxSubqueryJoin.tla:492` `PxSubqueryJoin.tla:499` `PxSubqueryJoin.tla:508` `PxSubqueryJoin.tla:509` `PxSubqueryJoin.tla:510` | SpinCheck, SpinPop, ExitPop, Join: Mode "spin" / "exitOnEmpty" only |
| `PxSubqueryJoin.tla:520` | EvLeave's task branch at its EvCheck call site: an elastic worker never reaches "chk" (its failed pop goes to "xrel"); fires in `option-fixed*` |
| `PxSubqueryJoin.tla:537` | EvPop's Mutant "noHelp" arm (`mutant-no-help` only) |
| `PxSubqueryJoin.tla:636` `PxSubqueryJoin.tla:637` `PxSubqueryJoin.tla:638` `PxSubqueryJoin.tla:648` `PxSubqueryJoin.tla:649` `PxSubqueryJoin.tla:650` `PxSubqueryJoin.tla:652` `PxSubqueryJoin.tla:653` `PxSubqueryJoin.tla:654` `PxSubqueryJoin.tla:660` `PxSubqueryJoin.tla:661` `PxSubqueryJoin.tla:663` | TaskFast, TaskSlowCheck, TaskSlowWait: develop's `pop` / `pop_slow`, Mode "event" replaces them (D4) |
| `PxSubqueryJoin.tla:708` `PxSubqueryJoin.tla:709` `PxSubqueryJoin.tla:710` | SpuriousWake: MaxSpur = 0 in `scale-3w` and `option-fixed-op-starved`; the main, nest-main, wide and liveness cfgs fire it |

## Result

Not run to `RESULT: OK` yet.
