# PxSubqueryJoin — the parallel subquery executor waits for its jobs without polling a mutex (CBRD-28126)

Scope: `src/query/parallel/px_query_execute/` (`px_query_job.hpp`, `px_query_executor.cpp`,
`px_query_task.cpp`), `src/query/parallel/px_thread_safe_queue.cpp`, and the aptr dispatch of
`qexec_execute_mainblock_internal` (`query_executor.c:22386-22490`) at CUBRID develop `41ca53ce7`
(identical to `origin/develop` `4bf2b2e32` in these files), and the implementation on branch
`CBRD-28126` (worktree `~/dev/cubrid-worktree/CBRD-28126`).

Motivation: oracle-gap#20 (lane 2 diagnosis, 2026-11-14): on TPC-H Q21 with `parallelism=1` 31% of
the server's `instructions:u` is `pthread_mutex_lock/unlock` of `join_context::m_mutex`, taken twice
per turn of `run_jobs`'s wait loop (`px_query_executor.cpp:146-170`) while the one worker scans
lineitem. CBRD-27823: an executor that runs after the root's `run_jobs` loses its pushes to the closed
queue and waits forever in the same loop.

Split (2026-11-16, the user): the statement's worker budget (how many workers, operators' own
reservations) is xmilex-git/workspace#644, draft model `docs/tla/px-worker-group/`. This directory is
the wait and the wake only; the subquery workers start when the root's `run_jobs` starts, as today.

Status: design verified (see `## Result`); implementation on branch `CBRD-28126`.

trace-exempt: the spec is the design model; the CBRD-28126 implementation is tied to it by the refinement map below, and its trace validation (instrumented build, recorded runs) is not done.

## Claim and sources

| # | Claim | Kind | Source |
|---|---|---|---|
| C1 | `run_jobs` of an executor returns only after every job it added has ended (run, skipped on the interrupt, or refused by the queue on the interrupt), so the caller reads finished list files. | safety | `run_jobs` step 5 `join_jobs` (px_query_executor.cpp:173 at 41ca53ce7); query_executor.c:22496 comment "only after run_jobs (): a parallel subquery executor may run the producer on a worker" |
| C2 | Every job runs at most once. | safety | one pop per pushed job (`try_pop_fast` / `pop_slow` CAS on the slot sequence); `m_job` run once by `run_jobs` step 3 |
| C3 | Nothing touches an executor's join state, the statement's queue or its wake event after it is deleted. | safety | `qexec_clear_xasl_for_parallel_aptr` deletes the job's `px_executor` right after its `run_jobs` (query_executor.c:2615 via px_query_task.cpp:196); `~query_executor` deletes the queue (px_query_executor.cpp:87) |
| C4 | The statement ends: every `run_jobs` returns and every worker task ends, on the error and interrupt paths too, and also for an executor that runs after the root's `run_jobs` (CBRD-27823). | liveness | any query must finish; `execute_job_internal`'s early exit (px_query_task.cpp:85-91); CBRD-27823 (q1, q4, q6, q7 never return) |
| C5 | A thread waiting in `run_jobs` does not poll: between two events (a push, a pop, a job end, a wake) it makes a bounded number of failed `try_pop` and takes no mutex per turn. | safety (ghost `idle`) | oracle-gap#20: 70 M lock/unlock pairs in one Q21 run, proportional to the worker's scan time; D2 |
| C6 | No thread sleeps in an idle wait while a job is queued, unless the pusher's wake is on its way to it. | safety | proposed by the model, adopted (D4): develop's fast push notifies `m_not_empty` without the queue mutex (px_thread_safe_queue.cpp:215), so the worker can sleep through a push (`mutant-develop-lost-wakeup`) |
| C7 | No aptr of a block opens a list file before the aptr that writes it ended; in particular every reader of a CTE, a subquery a joined scan evaluates per row included, reads the CTE's finished list. | safety | user, 2026-11-18 (review of PR #8556): CTE readers ran before the CTE as parallel subquery jobs (q5 repro, wrong result 20/20 on develop `4bf2b2e32` and on `f6961b036`); SQL: a CTE reference reads the CTE's whole result |
| C8 | A block whose sibling aptrs read nothing but CTEs keeps its parallel subquery executor: a reference to a CTE no longer makes the statement serial. | safety (static) | user, 2026-11-18, decision 3 ("CTE는 무조건 먼저 실행되었으니 참조가 있더라도 병렬부질의가 가능하게") |
| C9 | A block gets a parallel subquery executor only for two jobs or more; a CTE is not a job. | safety (static) | `aptr_cnts > 1` (px_query_executor.cpp `make_parallel_query_executor_recursively`), `m_aptr_set.size() < 2` (px_query_checker.cpp `is_parallel_executable`); user decision 2 makes a CTE inline |

## Decisions

| # | Decision | Status | Evidence |
|---|---|---|---|
| D1 | Directions 1 (`parallelism < 2` gives no subquery worker) and 3 (the runtime filter an executor disables, query_executor.c:22289) of oracle-gap#20 are out of scope; the worker budget is xmilex-git/workspace#644. | locked (Q1, split 2026-11-16) | — |
| D2 | C5 means: a waiter takes a mutex only on the sleep/wake path; the per-executor count is an atomic. | locked (Q2) | `mutant-develop-spin` violates NoPolling |
| D3 | One wake event per statement (epoch + mutex + cv), owned by the root executor and deleted with it; every executor's waiters and the workers sleep on it. The job that takes its executor's count to 0 reads the event pointer before its `fetch_sub`, then wakes the event. | locked (Q3) | `mutant-wake-via-exec` violates NoUseAfterFree; issue direction 2 (`mutant-exit-on-empty`) deadlocks |
| D4 | Adopt C6; the worker's idle wait is the same event wait (no `pop_slow` wait on `m_not_empty`). | locked (Q4) | `mutant-develop-lost-wakeup` violates NoSleepWithWork; `witness-worker-slept` |
| D5 | Every waker locks the event mutex, moves the epoch and calls `notify_all` (no sleeper count). | locked (Q5) | `mutant-wake-one` deadlocks; `mutant-no-push-wake`, `mutant-no-queue-recheck` violate NoSleepWithWork |
| D6 | One, two and three workers are checked (`one-worker`, main, `scale-3w`). | locked (Q6, Q1 of the split) | — |
| D7 | The inline-aptr error that skips `run_jobs` after pushes (xmilex-git/workspace#643) cannot reach a nested executor: the checker flags every non-root node whose subtree calls an SP (`mark_sp_blocks_recursive`, px_query_checker.cpp:677-693), so such a node gets no executor and a job containing it runs inline; at the root the error exits before `run_jobs` starts the worker task, so no thread runs the pushed jobs. The model keeps InlineFail as a mutant only. Runtime check 2026-11-16 (develop `4bf2b2e32` optdebug, system malloc, `MALLOC_CHECK_=3`): the SP sibling failing after two parallel siblings at the root, 20 runs, no crash or abort. | locked (Q7, Q21: fix only if reproduced) | `mutant-develop-inline-fail`, `mutant-inline-fail` violate NoUseAfterFree |
| D8 | C4 assumes weak fairness per thread and finitely many spurious failures (`MaxSpur`). | locked (Q8) | `liveness` |
| D9 | A waiter helps: it pops any queued job, of any executor, until the queue is empty, re-checks, then sleeps (as develop helps). | locked (Q9) | `mutant-no-help` deadlocks; `witness-helped` |
| D10 | On the interrupt a worker ends (as develop's `pop_slow`). | locked (Q10) | `witness-interrupted-end` |
| D11 | `release_workers`' `wait_workers` yield loop stays: it starts after the workers were told to stop. | locked (Q11) | `RootRelease` |
| D12 | An ADR; JIRA CBRD-28126 filed 2026-11-16. The directory closes without `RESULT: OK`: IndInv holds on every reachable state TLC visits, its inductive check did not finish (see `## Result`). | locked (Q12, Q6 of the split, Q22) | docs/adr/0059 |
| D13 | The 3-level tree (2 → 4 → 8) is not modeled (the user: scope reduced with the implementation); the scale cfg is the base tree with three workers and the late executor, because the two-level tree with three workers did not finish in 1 h 40 min. | locked (Q2 of the split, Q22) | — |
| D14 | An executor that runs after the root's `run_jobs` (CBRD-27823) is fixed here: the root's end stops the workers without closing the queue; the late executor pushes its jobs and its waiter runs them (D9); the queue closes when the root executor is deleted. | locked (Q5 of the split: "코드일관성을 위해") | `mutant-closed-queue` deadlocks; `witness-late-helped` |
| D15 | `add_job` counts and wakes only a job the queue took; a job `push_slow` refuses on the interrupt ends without running, as one popped after the interrupt would. Follows from D14 (no job is lost while its count stays). | locked (consequence of D14) | `mutant-count-refused` deadlocks; `witness-refused` |
| D16 | Review of PR #8556 (2026-11-18): D14 removed the hang that hid an input class, the branches of a correlated subquery that a joined scan evaluates per row. The checker (`add_xasl_recursive`, px_query_checker.cpp) refused a correlated subquery on the block itself but not on a joined scan's `dptr_list`, while `make_parallel_query_executor_recursively` gives an executor to every node `iterate_xasl_tree` reaches, that list included; each job's `qexec_clear_xasl_for_parallel_aptr (..., true)` then cleared the outer row's values its predicates point to. The checker now flags every node under a joined scan's `dptr_list` and `fptr_list` `XASL_NO_PARALLEL_SUBQUERY`, so no executor is made inside such a subquery and the rest of the statement keeps its executors. Q1 (a), refusing the whole statement as for a correlated subquery on the block itself, was dropped after its build took the parallel arms away from cbrd_28044 (correlated subqueries without a UNION under a joined scan, correct on develop: 24 answer lines differ). Outside the join protocol: a job is an opaque step of the model. | locked (review Q1 (b) after (a) failed cbrd_28044, Q2: in this ticket) | runtime, `.git_ignored_dir/scratch/cbrd28126-review/`: review query s1 on `b22001002` release `0 8589934600`/`0 0`, optdebug abort in `qfile_tuple_fill_from_values`, develop `4bf2b2e32` optdebug hang; a nested executor (n1) wrong on develop `4bf2b2e32` release and on `b22001002`; `f6961b036` optdebug and release (libcubridcs `8abe88d15b652dfe`, `b04f45b31124589d`) s1 and n1 equal the NO_PARALLEL_SUBQUERY results with the FROM UNION still parallel, also with system malloc and `MALLOC_CHECK_=3`; cbrd_28044 PASSED in CTP; CBRD-28155 (two derived tables, each with a correlated UNION IN subquery under its join, hang in `push_slow`) returns `2 2` on `f6961b036` optdebug 3 of 3 and hangs on develop `4bf2b2e32` optdebug |
| D17 | The late executor's trace prints no worker count (text and JSON): it records at the start of `run_jobs` that the workers had stopped, and the dump prints workers only above one (`get_executed_parallelism`), as hash and merge join do. | locked (review Q3 (a)) | `f6961b036` optdebug: review query h1 prints `(time: …)` under the WHERE subquery's UNION and `parallel workers: 2` under the FROM's |
| D18 | Review of PR #8556 (2026-11-18, the user): a CTE read from a subquery that a joined scan evaluates per row ran after its reader (the checker did not visit `scan_ptr->dptr_list`/`fptr_list`, so the CTE and its reader became sibling jobs). Fixed here, not in a new issue (Q1). (1) the checker visits those subqueries and counts their list scans as the block's reads; (2) the CTEs of a block with an executor run first, inline in list order on the dispatching thread, before its first job (`qexec_execute_ctes_first`), after the executor exists so a CTE's own subqueries stay parallel; (3) a read of a CTE does not make the statement serial, and a CTE does not count as a job. (4) a joined scan's aptr (`gen_inner`'s inner temp list, `add_subqueries` on an inner scan) is checked by `add_xasl_recursive` as the head's own aptrs are; before, only the node and its scan_ptr chain were checked while the dispatch ran it as a job (the user, 2026-11-18: "scanptr aptr도 순회"). Model `PxCteFirst.tla`. | locked (user, Q1-Q3 and 1-3, 2026-11-18) | C7-C9; `PxCteFirst` cfgs; smoke q0-q11 (`.git_ignored_dir/scratch/cbrd28126-review/cte-fix2-od`, `cte-fix3-od`) |

## Refinement map (model -> code; "28126" = branch CBRD-28126)

| Model | Code | One step because |
|---|---|---|
| `stack` frames `root`/`job`/`wait`/`task`/`lroot` | `qexec_execute_mainblock_internal` of the root executor's node / `execute_job_internal` / `query_executor::run_jobs` / `task::execute` / the late executor's node | call structure; a thread's frames nest as its C stack does |
| `AddOwn` | `add_job` first call: `m_job = job (..)`, `add_running_jobs` (28126 px_query_executor.cpp:116-118) | `m_job` is executor-local; one atomic RMW |
| `AddPush` | `add_job`: `m_job_execution_queue->push` (28126 :124) → `try_push_fast` / `push_slow` (px_thread_safe_queue.cpp:54, 274); the refused branch is `push_slow`'s interrupt returns (:285, :293, :306); develop's `m_not_empty.notify_one ()` without the queue mutex (:215) in the develop modes | the slot is published by `ready.store` + `fetch_add` |
| `AddCount` | `add_running_jobs` after a push the queue took (28126 :127) | one atomic RMW |
| `AddWake` | `m_wake_event_p->wake_all ()` (28126 :128; px_query_job.hpp `wake_event::wake_all`) | one event-mutex section (epoch++ and `notify_all` under it) |
| `AddWake2`, `JobWake2`, `EvReg2` | the rejected "wake only a registered sleeper" variant (WakeAlways = FALSE) | — (option) |
| `AddDone` root | `run_jobs` step 2: `new task` + `push_task` (28126 :144-149) when `*m_is_task_running_p` is false | worker start is the task push |
| `AddDone` lroot | the late executor's node calls `run_jobs`; `*m_is_task_running_p` is true, so no task starts | — |
| `AddDone` InlineFail | a sibling aptr flagged `XASL_NO_PARALLEL_SUBQUERY` fails inline (query_executor.c:22427-22436) → `GOTO_EXIT_ON_ERROR`, skipping `run_jobs` | mutant only: unreachable for a nested executor (D7) |
| `JobStart` | interrupt check at the top of `execute_job_internal` (28126 px_query_task.cpp:112-118) | one atomic load of `interrupt::m_code` |
| `JobWork` | `qexec_execute_mainblock` of the job and its error branch setting the px interrupt | the job's own work touches no join state |
| `JobClear` | `qexec_clear_xasl_for_parallel_aptr (cur_thread_p, xasl, true)` (28126 px_query_task.cpp:224) → `delete xasl->px_executor` (query_executor.c:2615) | thread-local until the delete |
| `JobFin` (event) | `sub_running_jobs` (28126 px_query_job.hpp): read `m_wake_event_p`, then `fetch_sub` (acq_rel) | one atomic RMW; the pointer read before it is thread-local |
| `JobWake` | `wake_event_p->wake_all ()` when the `fetch_sub` returned 1 | one event-mutex section |
| `JobFin` (spin/exitOnEmpty) | develop `sub_running_jobs` (px_query_job.hpp:56-64): decrement and `notify_one` under `m_mutex` | one `m_mutex` section |
| `TryPop` | `try_pop_fast` (px_thread_safe_queue.cpp:221-271): fails on empty, on a not-ready head slot, on a lost CAS | the CAS is the linearization point; failure on a non-empty queue is the `spur` budget |
| `EvLoop` (wait) | 28126 `run_jobs` loop head `while (get_running_jobs () > 0)` (:162) | one acquire load |
| `EvLoop` (task) | 28126 `task::execute` `while (!is_ended ())` (px_query_task.cpp:53): `is_workers_stopped ()` or the interrupt | two acquire loads; each alone ends the wait |
| `EvPop` | `try_pop (j)` and `execute_job_internal` (28126 :164-168; px_query_task.cpp:56-59) | the pop is `TryPop` |
| `EvReg` | `get_epoch ()` (28126 :170; px_query_task.cpp:61) | one event-mutex section |
| `EvCheck` | re-read of the count / `is_ended ()`, then `is_empty ()` (28126 :171-178; px_query_task.cpp:62-69) | each an acquire load; `is_empty` reads two positions, a stale answer is `TryPop`'s spurious failure or one more loop |
| `EvSleep` | `wake_event::wait (seen_epoch)`: `m_cv.wait (lock, epoch != seen)` | the epoch check and the sleep are one event-mutex section |
| `SpuriousWake` | a condvar wakeup without a notify; the predicate wait sleeps again | — |
| `SpinCheck`, `SpinPop` | develop `run_jobs` loop (px_query_executor.cpp:146-170): `get_running_jobs` (lock/unlock `m_mutex`) and `try_pop` | each `get_running_jobs` is one `m_mutex` section |
| `ExitPop` | issue direction 2: leave the loop on the first failed `try_pop` | — (option) |
| `Join` | develop `join_jobs` (px_query_job.hpp:70-74): `m_cv.wait (lock, pred)` | predicate check and wait are atomic under `m_mutex` |
| `TaskStart` | the pool thread runs `task::execute` | — |
| `TaskFast`, `TaskSlowCheck`, `TaskSlowWait` | develop `get_job` → `pop` / `pop_slow` (px_thread_safe_queue.cpp:64-71, 334-356) | two steps: a notify without the mutex can fall between them |
| `TaskExit` | `task::execute` returns → `~task` → `worker_manager::pop_task` | — |
| `RootEnd` | 28126 `run_jobs` step 5: `stop_workers ()` (:186) — develop: `push_last ()` (closes the queue) | one event-mutex section |
| `RootRelease` | `release_workers` → `wait_workers` (yield loop until every task ended, px_worker_manager.cpp:97); `run_jobs` returns | the yield loop is short: the workers were told to stop |
| `LateEnd` | the late executor's `run_jobs` returns | — |
| `RootFree` | `~query_executor` of the root (28126 :86-101): `stop_workers`, `release_workers` if still held, `push_last`, delete queue, event, flag | the main thread alone; every task ended |
| `interrupt` | the root executor's `m_interrupt` (the task's `m_interrupt_p`) | simplification: one statement interrupt; per-executor interrupts of nested `run_jobs` are not modeled |
| `PxCteFirst` `Parallel` (Checker `visit_cte_ok`) | `xasl_checker`: `per_row_iter` registers the list scans of a joined scan's `dptr`/`fptr` subtrees under the block (28126 px_query_checker.cpp:596-618); `check_xasl_recursive` skips a CTE sibling as a target (`aptr_is_cte`, :98-119); `m_aptr_set` holds no CTE (:553, :624, :769) | decided once before execution, on the XASL tree |
| `PxCteFirst` `MainPre` | `qexec_execute_ctes_first` (28126 query_executor.c:21905), called at the block start when the block has an executor (:22286) and right after the top block creates the executors (:22449) | one CTE per call of `qexec_execute_mainblock` on the dispatching thread; no job of the block exists yet |
| `PxCteFirst` `MainDisp` / `Add` | the aptr loop: a CTE that ran is skipped as executed; `add_job` (:22477), the first job kept as `m_job` | as `AddOwn` / `AddPush` above |
| `PxCteFirst` `MainRun` / `WorkerPop` / `WorkerEnd` / `MainEnd` | `run_jobs` (:22535): `m_job`, then `try_pop`, then the wait on the running count; a worker's `task::execute`; job end | coarse: the wait and the wake are `PxSubqueryJoin`'s; here only the order of opens matters |
| `PxCteFirst` `Open` (bad) | a reader's scan opens the producer's `list_id` (`TARGET_LIST` spec, `s.list_node.xasl_node`) | the earliest read; an open before the producer ended reads an empty or growing list (q5: `readrows: 0`) |
| `PxCteFirst` executors (C9) | `make_parallel_query_executor_recursively` counts no CTE (28126 px_query_executor.cpp:338, :365) | static |

Code facts the model relies on:
- One root executor per statement: `make_parallel_query_executor_recursively` makes the first executor of its XASL walk the root and every later one `new query_executor (executor_p)`, sharing its queue, event and task flag (px_query_executor.cpp:357-366 at 41ca53ce7) — including executors on nodes outside the root's jobs (the late executor).
- All `add_job` calls of an executor precede its `run_jobs` on the same thread (query_executor.c:22423, 22481).
- The queue's capacity is `estimated_jobs`, the jobs of every executor of the statement together (px_query_executor.cpp:316-339), and each executor's `run_jobs` drains its jobs before it returns; so a push never waits on a full queue, also after the workers stopped.
- The late executor's `run_jobs` finds `*m_is_task_running_p` true and starts no task; its jobs run on the main thread.
- WakeAlways needs no seq_cst: the epoch is read and moved only under the event mutex, and every push and count change happens before the waker takes it.

## Properties

`JoinAfterAllEnded` (C1), `RunsOnce` (C2), `NoUseAfterFree` (C3), `Terminates` (C4, liveness cfg),
`NoPolling` (C5), `NoSleepWithWork` (C6); `TypeOK`; `IndInv` (named conjuncts IStackShape, IThreads,
IJobs, IExecs, IWake, IIdle and the five safety properties).

`PxCteFirst`: `NoEarlyRead` (C7), `ParallelKept` (C8), `JobsAtLeastTwo` (C9), `AllEndedAtFin`; `TypeOK`;
`IndInv` (named conjuncts ShapeOrder, OnlyCteRead, Absent, StartedReadDone, Running, WorkersDistinct,
WorkerJobs, JobBook, MjobFirst, PreOnlyParallel, Pre, PostPre, ParDisp, ParRun, Serial and the properties).

## Fault model

| Fault | Modeled | Where |
|---|---|---|
| error return | yes | `JobWork` (WorkFail) sets the interrupt; `AddDone` InlineFail (D7) |
| interrupt / cancel | yes | the interrupt flag: `JobStart` early exit, a worker ends (D10), `push_slow` refuses (D15) |
| lock timeout, deadlock victim | as an error return | inside a job's work |
| conditional latch failure | n/a | no page latch in the join protocol |
| OOM | as an error return | `qexec_deep_copy_xasl_state` failure fails the job like a work error |
| crash / kill -9 | n/a | no durable state |
| spurious wakeup | yes | `SpuriousWake` within `MaxSpur` |
| failed try_pop on a non-empty queue | yes | `TryPop` within `MaxSpur` (lost CAS, weak CAS, a head slot not yet ready) |
| push refused | yes | `AddPush`'s refused branch: `push_slow` returns on the interrupt (D15) |
| full queue | n/a | capacity covers every executor's jobs (code facts) |
| an executor after the root's `run_jobs` | yes | `Late` (CBRD-27823, D14) |
| a job whose branch reads the outer row (correlated subquery of a joined scan) | n/a | no executor inside such a subquery (D16); the model's jobs read no shared row |
| concurrent DML, vacuum, checkpoint, HA | n/a | inside a job's work, not in the join protocol |
| nested statement (SP SQL) | n/a | a separate statement with its own executors; its wait does not share this statement's event |
| error in a CTE run first (`PxCteFirst`) | no | `qexec_execute_ctes_first` returns the error before any job of the block exists; the block exits as on any aptr error and the executor is deleted with the XASL clear (smoke q9: the same error as `NO_PARALLEL_SUBQUERY`, server alive) |
| a non-CTE sibling read by a sibling (`PxCteFirst` shape `hid`) | yes | the checker keeps such a read blocking; the generator makes none in SQL (a derived table has no name another one can read) |
| an aptr list where a CTE follows its reader (`PxCteFirst` shape `late`) | yes | `pt_uncorr_post` prepends a CTE to the aptr list (xasl_generation.c "append the CTE xasl at the beginning of the list"); `qexec_execute_ctes_first` does not rely on it |
| a recursive CTE | no | `add_xasl_recursive` keeps the statement serial (`proc.cte.recursive_part`); smoke q10 |
| a joined scan's aptr subtree (`PxCteFirst` shape `hid`: a read the checker does not see) | yes | `add_xasl_recursive (aptr)` in the scan_ptr aptr loop (28126 px_query_checker.cpp:624); producers of such an aptr: plan_generation.c `gen_inner` SORT/JOIN inner (`add_uncorrelated`, :3651) and `add_subqueries` on an inner scan (:3603); no SQL found that makes one in 7 probes (`.git_ignored_dir/scratch/cbrd28126-review/sptr-*`) |

Environment assumptions (C4): weak fairness of every thread's step, and finitely many spurious failures
and wakeups (`MaxSpur`).

## Mutants

| cfg | Mutant | Claim it breaks | Result |
|---|---|---|---|
| `mutant-return-on-empty` | a waiter returns when the queue is empty, not when its count is 0 | C1 | violation JoinAfterAllEnded |
| `mutant-pop-keeps` | a pop leaves the job in the queue | C2 | violation RunsOnce |
| `mutant-develop-inline-fail` | develop (wait as exitOnEmpty), InlineFail | C3 | violation NoUseAfterFree |
| `mutant-inline-fail` | the redesign with InlineFail (workspace#643 unfixed) | C3 | violation NoUseAfterFree |
| `mutant-wake-via-exec` | the last job's wake goes through (or lives in) the owner executor | C3 | violation NoUseAfterFree |
| `mutant-exit-on-empty` | issue direction 2: leave on the first failed try_pop, cv wait on the executor | C4 | deadlock |
| `mutant-no-help` | a waiter never pops (one worker) | C4 | deadlock |
| `mutant-wake-one` | notify_one on the event (two-level tree) | C4 | deadlock |
| `mutant-closed-queue` | develop's `push_last` at the root's end: the late executor's pushes are dropped (CBRD-27823) | C4 | deadlock |
| `mutant-count-refused` | develop's `add_job`: a refused push is counted anyway | C4 | deadlock |
| `mutant-develop-spin` | develop's wait loop | C5 | violation NoPolling |
| `mutant-develop-lost-wakeup` | develop's queue wait (spin loop capped by `IdleCap`) | C6 | violation NoSleepWithWork |
| `mutant-no-queue-recheck` | the waiter re-checks only its count before sleeping | C6 | violation NoSleepWithWork |
| `mutant-no-push-wake` | a push does not wake the event | C6 | violation NoSleepWithWork |
| `PxCteFirst.mutant-develop` | develop: CTE dispatched as a job, checker does not visit the joined scan's subqueries (shape q5o, the repro) | C7 | violation NoEarlyRead |
| `PxCteFirst.mutant-in-place` | a CTE runs inline where the list order meets it, not before the first job (shape late) | C7 | violation NoEarlyRead |
| `PxCteFirst.mutant-no-visit` | CTEs first, but the checker does not visit a joined scan's subqueries (shape hid) | C7 | violation NoEarlyRead |
| `PxCteFirst.mutant-checker-only` | the checker lets a CTE read through, the dispatch still makes the CTE a job (shape q0) | C7 | violation NoEarlyRead |
| `PxCteFirst.mutant-cte-blocks` | the checker visits but a read of a CTE still blocks (shape q0) | C8 | violation ParallelKept |
| `PxCteFirst.mutant-count-cte` | a CTE counts as a job (shape c1q: one reader beside the CTE) | C9 | violation JobsAtLeastTwo |

## Witnesses

| cfg | Outcome reached |
|---|---|
| `witness-helped` | the main thread runs a job of a nested executor (helping, D9) |
| `witness-nested-waiter-slept` | a nested executor's waiter sleeps on the statement event |
| `witness-worker-slept` | a worker sleeps on the statement event (D4) |
| `witness-interrupted-end` | the statement ends after an interrupt |
| `witness-late-helped` | the late executor returns after the main thread ran its queued job (D14) |
| `witness-refused` | the queue refuses a push on the interrupt (D15) |
| `witness-three-busy` | three workers run jobs at once (two-level tree) |
| `PxCteFirst.witness-overlap` | after the CTE ran first, its two readers run as parallel jobs at once (shape q0) |

## Bounds

| cfg | Tree | Workers | Late | Faults |
|---|---|---|---|---|
| main | base (R: 1, 2; x2: 21, 22) | 2 | yes | WorkFail, MaxSpur 1 |
| `one-worker` | base | 1 | yes | WorkFail, MaxSpur 1 |
| `nest-main` | nestM (the nested executor on the main thread) | 2 | no | WorkFail, MaxSpur 1 |
| `wide` | wide (three jobs per executor) | 2 | no | MaxSpur 1 |
| `liveness` | base | 2 | yes | WorkFail, MaxSpur 1 |
| `scale-3w` | base | 3 | yes | WorkFail |
| `PxSubqueryJoinInd.apalache-base` | base | 2 | yes | WorkFail, every MaxSpur |

`PxCteFirst`: shapes q5o, q0, cte2, late, hid, c1q (two to four aptrs, every reader class: direct, from a
joined scan's subquery, CTE from CTE, non-CTE producer, a lone reader); 1 worker (parallelism 2) in the main
cfg, 3 workers in `scale-2w`; the inductive check covers every shape with 2 workers.

## Dead expressions

Union over the pass cfgs (main, `one-worker`, `nest-main`, `wide`, `liveness`, `scale-3w`). Each is a mode, option or mutant branch, a branch a cfg's constants switch off (WorkFail, Late, MaxSpur), or a helper body counted at such a call site; none is a path of the chosen design that every cfg misses.

| Lines | Why TLC never evaluates them |
|---|---|
| `PxSubqueryJoin.tla:153` `PxSubqueryJoin.tla:154` `PxSubqueryJoin.tla:155` `PxSubqueryJoin.tla:157` `PxSubqueryJoin.tla:158` `PxSubqueryJoin.tla:159` `PxSubqueryJoin.tla:163` `PxSubqueryJoin.tla:164` `PxSubqueryJoin.tla:375` | helper operator bodies (SetPc, Call, Ret, Touch, TouchQ, ZeroIdle, StartJob, WaitReturn): TLC counts an operator body once per call site, and these are its call sites inside the branches below |
| `PxSubqueryJoin.tla:170` `PxSubqueryJoin.tla:173` `PxSubqueryJoin.tla:174` | EvWakeAll's Mutant "wakeOne" branch (`mutant-wake-one` only) |
| `PxSubqueryJoin.tla:175` `PxSubqueryJoin.tla:176` | EvWakeAll counted at its WakeAlways = FALSE call sites (AddWake2, JobWake2; D5) |
| `PxSubqueryJoin.tla:181` `PxSubqueryJoin.tla:184` `PxSubqueryJoin.tla:321` `PxSubqueryJoin.tla:544` `PxSubqueryJoin.tla:545` | Mode "spin" / "exitOnEmpty" branches: develop's queue notify, `sub_running_jobs` and `push_last` (the develop mutants only) |
| `PxSubqueryJoin.tla:219` `PxSubqueryJoin.tla:221` | AddPush's Mutant "countRefused" arm (`mutant-count-refused` only) |
| `PxSubqueryJoin.tla:216` `PxSubqueryJoin.tla:222` `PxSubqueryJoin.tla:223` `PxSubqueryJoin.tla:224` `PxSubqueryJoin.tla:292` | the refused push and the job failure: WorkFail = FALSE in `wide`, so nothing sets the interrupt there; the other pass cfgs fire both |
| `PxSubqueryJoin.tla:245` `PxSubqueryJoin.tla:252` `PxSubqueryJoin.tla:254` `PxSubqueryJoin.tla:333` `PxSubqueryJoin.tla:340` `PxSubqueryJoin.tla:342` `PxSubqueryJoin.tla:444` `PxSubqueryJoin.tla:452` `PxSubqueryJoin.tla:454` `PxSubqueryJoin.tla:457` | WakeAlways = FALSE branches: the rejected registered-sleeper wake (D5) |
| `PxSubqueryJoin.tla:269` `PxSubqueryJoin.tla:562` | AddDone's late-executor branch and LateEnd: Late = FALSE in `nest-main` and `wide`; main, `one-worker`, `liveness` and `scale-3w` fire them |
| `PxSubqueryJoin.tla:275` | AddDone's InlineFail branch: unreachable in the code (D7), mutants only |
| `PxSubqueryJoin.tla:351` | TryPop's Mutant "popKeeps" arm (`mutant-pop-keeps` only) |
| `PxSubqueryJoin.tla:354` `PxSubqueryJoin.tla:357` `PxSubqueryJoin.tla:358` `PxSubqueryJoin.tla:360` `PxSubqueryJoin.tla:362` `PxSubqueryJoin.tla:363` | TryPop counted at its develop call sites (SpinPop, ExitPop) |
| `PxSubqueryJoin.tla:383` `PxSubqueryJoin.tla:390` `PxSubqueryJoin.tla:397` `PxSubqueryJoin.tla:406` `PxSubqueryJoin.tla:407` `PxSubqueryJoin.tla:408` | SpinCheck, SpinPop, ExitPop, Join: Mode "spin" / "exitOnEmpty" only |
| `PxSubqueryJoin.tla:433` | EvPop's Mutant "noHelp" arm (`mutant-no-help` only) |
| `PxSubqueryJoin.tla:496` `PxSubqueryJoin.tla:497` `PxSubqueryJoin.tla:498` `PxSubqueryJoin.tla:508` `PxSubqueryJoin.tla:509` `PxSubqueryJoin.tla:510` `PxSubqueryJoin.tla:512` `PxSubqueryJoin.tla:513` `PxSubqueryJoin.tla:514` `PxSubqueryJoin.tla:520` `PxSubqueryJoin.tla:521` `PxSubqueryJoin.tla:523` | TaskFast, TaskSlowCheck, TaskSlowWait: develop's `pop` / `pop_slow`, replaced by the event wait in Mode "event" (D4) |
| `PxSubqueryJoin.tla:580` `PxSubqueryJoin.tla:581` `PxSubqueryJoin.tla:582` `PxSubqueryJoin.tla:601` | SpuriousWake and its disjunct in Next: MaxSpur = 0 in `scale-3w`; the other pass cfgs fire it |

## Result

Not `RESULT: OK` — closed without the inductive check (the user, Q22, 2026-11-16, as CBRD-27430-B1a).

TLC, spec `PxSubqueryJoin.tla` sha256 `673e19f21522b093…`, evidence under `.git_ignored_dir/scratch/tla/`:

| cfg | verdict | states (generated / distinct) | run dir |
|---|---|---|---|
| main (with `IndInv`) | no error | 4,925,271 / 2,083,758, depth 69 | `px-subquery-join-20261116-150623-1478455` |
| `one-worker` (with `IndInv`) | PASS | 38,162 / 23,083 | `px-subquery-join-20261116-151044-1480485` |
| `nest-main` (with `IndInv`) | no error | 3,456,457 / 1,394,724 | `px-subquery-join-20261116-123951-952569` |
| `wide` (with `IndInv`) | no error | 9,617,829 / 3,392,602 | `px-subquery-join-20261116-144242-1462497` |
| `scale-3w` (with `IndInv`) | no error | 11,479,528 / 3,520,797 | `px-subquery-join-20261116-145305-1467557` |
| `liveness` (Terminates) | no error | 2,866,193 / 1,118,432 | `px-subquery-join-20261116-123951-952569` |
| 14 mutants | each fails as expected | — | `px-subquery-join-20261116-123951-952569` |
| 7 witnesses | each reached | — | `px-subquery-join-20261116-150512-1476144` |

"no error" cfgs failed only on dead expressions not yet explained in MAP.md at their run; the table above
explains every one (`one-worker` reran after it: PASS). The whole-directory record run was not repeated after
that MAP edit (host load); the spec and the cfgs did not change since these runs.

Inductive check (Apalache, `PxSubqueryJoinInd.apalache-base`, `apalache-split` 6 groups, State 1 only, no
deadlock check): every group timed out at 7200 s without a verdict (IStackShape+JoinAfterAllEnded,
IThreads+RunsOnce, IJobs+NoUseAfterFree, IExecs+NoPolling, IWake+NoSleepWithWork, IIdle). IndInv holds on
every reachable state of the five pass cfgs that list it; its inductiveness is not established.

2026-11-18 rerun after the PR #8556 review (no spec step changed; D16 and D17 are outside the join protocol): `tla-check --only 'PxSubqueryJoin*'` 26 TLC cfgs PASS and `PxSubqueryJoinInd.apalache-base` timed out at 7200 s as on 11-16 (`px-subquery-join-20261118-122445-359514`); `scale-3w` failed only on the vacuity check (the SpuriousWake disjunct of Next never fires with MaxSpur = 0) and passed after its `uncovered-ok` line (`px-subquery-join-20261118-132326-500963`, 11,479,528 / 3,520,797 states). Apalache not rerun (D12).

2026-11-18 `PxCteFirst` (D18): `tla-check --only 'PxCteFirst*'` — main and `scale-2w` PASS (166/124 and
278/164 states, no dead expression), 6 mutants fail as expected, `witness-overlap` reached
(`px-subquery-join-20261118-202349-2618473`); `PxCteFirst.apalache-ind` PASS in 12 s after `WorkersDistinct` got
the main thread's job (`px-subquery-join-20261118-202409-2619468`). IndInv is inductive for the design over every
shape.

TLAPS 요청 없음. Trace validation not done (trace-exempt above).
