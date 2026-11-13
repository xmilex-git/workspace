# PxSysopGate: the system operation gate of parallel execution (PR 8424, CBRD-27938)

Spec of `parallel_query::is_under_system_operation ()` at PR head `316431fba` (merge-base `f846c3634`),
the transaction-level system operation it reads (`topops.last`, `rmutex_topop`), the px task tree that
shares the transaction, and the request thread that serves a stored procedure's server-side SQL.

## Claim and sources

| Claim | Statement | Kind | Source |
|---|---|---|---|
| C1 | A decision is serial only when the open system operation's owner is the deciding thread, a thread registered in the PL session, or empty; another thread's system operation never makes it serial | safety | JIRA CBRD-27938 Expected Result ("두 입력 스캔이 매번 병렬로 실행"); PR description "그 밖의 스레드(형제 워커 등)이면 false" |
| C2 | Every thread of the statement ends: no thread waits on `rmutex_topop` held by a thread that waits for it | liveness + deadlock freedom | CBRD-27492 (MERGE deadlock); PR description "교착한다(CBRD-27492 의 MERGE)"; code comment of `is_under_system_operation` |
| C3 | At most one executing thread is inside the transaction's system operation (the topops stack has one writer) | safety | PR description "PL 세션의 스레드는 `lock_topop ()` 이 소유자의 락을 다시 잡도록 허용하므로 소유자와 같게 취급한다"; `px_query_checker.cpp` CBRD-27561 comment ("loses mutual exclusion against every px job") |

Superseded: the JIRA comment of 2026-11-04 (agreed by the JIRA owner on 2026-11-05) proposed "the owner is
the current thread or the thread that started the current thread and waits for it". The PR implements "the
current thread or a thread registered in the PL session". The agreed condition is the mutant `jira`.

Environment assumptions (guards in the spec, each with the code fact behind it):

| Id | Assumption | Code fact |
|---|---|---|
| A1 | A thread does not call `worker_manager::wait_workers` inside a system operation it opened while those workers ran (`JoinStart` needs `late[t] = 0`) | every statement-level system operation (`qexec_execute_insert/update/delete/merge`, `qexec_execute_selupd_list`) opens after the statement's SELECT part and its workers end; the other `log_sysop_start` sites (file, disk, heap, btree) do not wait for px tasks. Develop needs it too: `witness-late-join-develop` deadlocks |
| A3 | Root holds a system operation across a stored procedure call only when no px task of the transaction runs (`SpCall` guard) | same fact: the statement's system operation opens after its workers end, and under it Root's own decisions are serial (C1 `self`) |
| A4 | Only client transactions call `compute_parallel_degree` | callers: `qexec_*`, `hjoin_try_parallel*`, `try_parallel_merge`, `scan_open_parallel_*`, `sort_check_parallelism` (`sort_listfile`), `heap_get_capacity_parallel`, `btree_index_capacity_parallel`, `reserve_and_split`: all reached from a request thread or its px task. A system transaction (`is_active_worker_transaction ()` false) takes no `rmutex_topop`, so its owner stays empty |

## Refinement map

| Spec action / variable | Code (head 316431fba) | One step because |
|---|---|---|
| `owner`, `cnt` | `log_tdes::rmutex_topop.owner`, `.lock_cnt` | written only inside `rmutex_lock`/`rmutex_unlock` while the pthread mutex is held (or by the owner) |
| `depth` | `log_tdes::topops.last + 1` | written by the thread inside its system operation; read by others with no lock |
| `Want(t)` | `log_manager.c:log_sysop_start` calls `tdes->lock_topop ()` | the thread is committed: it returns only with the lock |
| `Acq(t)` / `AcqEffect` | `log_tran_table.c:log_tdes::lock_topop` -> `critical_section.c:rmutex_lock`: first lock (owner set), re-entry by the owner, or re-entry through `find_by_tid (owner)` when `cubpl::get_session ()->is_thread_involved (owner)` | owner and count change under the pthread mutex in one critical section |
| `Inc(t)` | `log_sysop_start`: `tdes->topops.last++` | a single store, read unsynchronized by `D1` of other threads |
| `Dec(t)` | `log_manager.c:log_sysop_end_unstack`: `tdes->topops.last--` | a single store, before `unlock_topop` |
| `Rel(t)` | `log_sysop_end_final` -> `unlock_topop` -> `rmutex_unlock` (owner cleared at count 0) | under the pthread mutex |
| `D1(t)` | `px_parallel.cpp:is_under_system_operation`: `tdes->is_under_sysop ()`; false -> no block | an unsynchronized load, its own step |
| `D2(t)` | the read of `tdes->rmutex_topop.owner`, the comparison with `thread_get_thread_entry_info ()->get_id ()`, `cubpl::get_session ()->is_thread_involved (owner)` | an unsynchronized load separate from the first (the PR's comment names the window between them); `is_thread_involved` takes `m_mutex_stack`, and the registration it reads changes only at `SpCall`/`SpRet`, which no `D2` overlaps |
| `Block(t)` (head) | `owner == thread_id_t ()` or `owner == self` -> true; otherwise `is_thread_involved (owner)` | the decision table of the diff |
| `Spawn(t, c)` | `px_worker_manager.cpp:worker_manager::push_task` after `compute_parallel_degree` (or `scan_try_promote_parallel_index_scan`) let workers start | the push is one call; `spawnOK`/`decH` tie it to the decision before it. A reservation is reused for a second round after `wait_workers` with no new decision (37 times in one TC body run), so `spawnOK` stays set until the thread's next decision |
| `JoinStart`/`JoinEnd` | `worker_manager::wait_workers` | the spin on `m_active_tasks` |
| `Finish(t)` | a px task's `retire ()` -> `worker_manager::pop_task`; the end of Q's request | `pop_task` is the last step of a task |
| `SpCall`/`SpRet`, `Involved` | `pl_executor.cpp:executor::executor` (`create_and_push_stack` registers Root's stack) / `executor::~executor`; `session::is_thread_involved` | registration is one `m_mutex_stack` section |
| `Q` | the request thread that runs the stored procedure's SQL: `executor::callback_execute` -> `send_data_to_client_recv`, the client sends the query as a new request (trace `pl`: events of p=1 while Root is registered) | |

Exit paths: a `log_sysop_start` OOM (`logtb_realloc_topops_stack` fails) unlocks and returns with `assert (false)`; not modeled (no decision changes). An interrupt makes px tasks stop early; it is a `Finish` at any point, which the spec allows. `get_session ()` failing (session expired) returns NULL -> `is_thread_involved` not called -> `false` (parallel): only on an expired session, where the statement fails anyway; not modeled.

## Fault model

| Fault | Treatment |
|---|---|
| error return | `log_sysop_start` OOM path: not modeled (above); `compute_parallel_degree` returns no error |
| interrupt / cancel | px tasks may `Finish` at any step |
| lock timeout, deadlock victim | not applicable: `rmutex_topop` has no timeout and is not in the lock manager's wait-for graph; a cycle is TLC's deadlock check (C2) |
| conditional latch failure | not applicable: no page latch in the mapped code |
| OOM | `logtb_realloc_topops_stack`: not modeled |
| crash / `kill -9` | not applicable: the gate is volatile state |
| spurious wakeup | not applicable: pthread mutex, no condition wait |
| concurrent DML, vacuum, checkpoint, HA apply | not applicable: they run on other transactions' descriptors (vacuum workers own a tdes that takes no `rmutex_topop`, A4) |
| torn read of `owner` | not modeled: `std::thread::id` is one aligned 8-byte word on x86-64; the PR's comment and `lock_topop` already read it unsynchronized |
| fairness | weak fairness per thread; the operation bound (`MaxOps`) makes every waiter's holder release |

## Properties

- `NoForeignSerial` (C1), `MutEx` (C3), `IndInv` in the main and scale cfgs; TLC's deadlock check and `RootEnds == <>(pc[Root] = "done")` (C2).
- `IndInv` (conjuncts `R_*`): every holder of a level is the owner, or Q re-entered through a registered Root; the count and the depth add up to the owner's levels; a thread that may push workers holds no level; while Root holds a level across a call no px task runs and Q may not push.

## Mutants

| Mutant | Kills | Result |
|---|---|---|
| `develop` (every open system operation blocks) | C1 | `mutant-develop`: violation NoForeignSerial (a worker decides while a sibling holds its temp file system operation) |
| `no_self` (the owner check removed) | C2 | `mutant-no-self`: deadlock (Root holds the statement-level system operation, pushes workers, waits; a worker waits on `rmutex_topop`) |
| `no_pl` (the PL clause removed) | C3 | `mutant-no-pl`: violation MutEx (Q decides parallel under Root's statement-level system operation; two of its workers re-enter through the registered Root at once) |
| `jira` (the condition agreed in the JIRA comment: self, empty, or the waiting starter) | C1 | `mutant-jira-design`: violation NoForeignSerial (a worker decides while its parent holds a temp file system operation) |

Surviving mutant: `empty_other` (an empty owner does not block). No claim breaks: for a client transaction the
owner is empty with the depth above zero only when the system operation ended between the two reads, and
then nothing is open. The `empty -> true` branch keeps develop's answer for a descriptor without the mutex
(A4) and costs a serial decision in the window (`witness-empty-race`). Reported as a question.

Atomicity: `D1` and `D2` are two steps, as the code reads them; `Want`/`Acq` and `Dec`/`Rel` are split at the
pthread mutex, and `Inc`/`Dec` are separate from `Acq`/`Rel` because other threads read the depth without the lock.

## Witnesses

| Witness | Outcome reached |
|---|---|
| `witness-par-under-foreign` | a thread decides parallel while a sibling holds a system operation (the CBRD-27938 fix) |
| `witness-self-serial` | Root decides serial inside its own statement-level system operation |
| `witness-pl-serial` | Q decides serial under Root's system operation through the PL clause |
| `witness-reentered` | Q re-enters `rmutex_topop` through the registered Root |
| `witness-empty-race` | a serial decision with an empty owner: the owner released between the two reads |
| `witness-late-join-head` / `-develop` / `-jira` | with A1 lifted, all three gates deadlock: A1 is a premise of develop's gate, not of this PR alone |

## Dead expressions

None: the main cfg (`PxSysopGate.cfg`) reported no dead-expr-lines.

## Bounds

- Main: `Thr = {0..6}` (Root 0, Q 1, Root's workers 2 and 3, worker 4 under 2, Q's workers 5 and 6), `MaxOps = 1` (Root 3).
- Scale: `Thr = {0..7}` with a third worker of Root (7): the safety invariants and the deadlock check; `RootEnds` is checked in the main cfg only (its temporal check at the scale size did not finish within 30 minutes at 5.8 M states).
- Apalache inductive check: `Thr` and `Par` of the main cfg fixed, `MaxOps` over every natural number.
- TLAPS: any thread set, any task tree, any `MaxOps` (`PxSysopGate_proofs.tla`), safety only (`Spec => []IndInv`, `IndInv => NoForeignSerial /\ MutEx`); C2 is TLC-only inside the bounds.

## Trace validation

- Build: scratch worktree `~/dev/cubrid-worktree/pr8424-tlatrace` = 316431fba + TLATRACE lines (global trace mutex around
  each recorded read or write) in `log_manager.c` (`Inc`, `Dec`, SP call), `critical_section.c` (`Acq` first/self/pl,
  `Rel`, for the `TDES_TOPOP` mutex), `px_parallel.cpp` (`D1`, `D2`), `px_worker_manager.cpp` (`Spawn`, `End`, `Join`),
  `pl_executor.cpp` (`SpCall`, `SpRet`); optdebug, `~/optdebug/CUBRID-pr8424-tlatrace`, libcubrid.so `42beb56b5f65...`.
- Runs (CS mode, `test_mode=yes`, the tc/td tables of `02_hash_join_mode.sql` before cubrid-testcases #4019):
  `sibling-a` (232 events, 11 threads) and `sibling-b` (164, 23): one statement of the TC body each, with a `D2 reason=other dec=par`;
  `self`: `INSERT ... VALUES ((SELECT /*+ PARALLEL(4) */ ...))`; `pl`: `INSERT ... VALUES (f_cnt ())`;
  `pl-reenter`: `INSERT ... VALUES (f_sort ())` (626 events, 152 re-entries `how=pl`, 6 decisions `pl -> serial`);
  `empty-race` (1657 events, 27 threads, head counter run 15): task 2 reads the depth while task 13 holds a temp file
  system operation, task 13 ends (`Dec`, `Rel`), task 2 reads an empty owner and decides serial: the outcome of
  `witness-empty-race`, observed on the build.
- Segmentation (`.git_ignored_dir/scratch/pr8424/tools/segment.py`): the run's transaction, cut where no task runs, the
  depth and the count are 0, no call is open, and no allowed push is pending; task ids renumbered.
- Join is an observation: `wait_workers` returned while the thread holds no level taken while its workers ran (A1).
- Rejected: `pl-decision-flipped` (the PL decision recorded as parallel), `sibling-lock-overlap` (a sibling's first lock
  moved before the holder's release).
- Batch: one full TC body run (`head-body-1`, 43228 events, 1182 tasks) cut into 375 segments, 151 distinct; all 151
  accepted by the trace spec in a scratch copy (`.git_ignored_dir/scratch/pr8424/tla-batch/`, `batch-trace.txt`, 151 PASS, 0 FAIL).

## Result

- 2026-11-06, `tools/tla/tla-check --prove --workers 12 --heap 24g` -> `RESULT: OK`,
  run dir `.git_ignored_dir/scratch/tla/px-sysop-gate-20261106-174428-885327/`.
- Main `PxSysopGate.cfg`: 7875930 states / 2326722 distinct, depth 47, no deadlock, `RootEnds` holds.
- Scale `scale-3-workers`: 171961879 / 42299810 distinct, depth 54, no deadlock.
- Apalache `apalache-indinv`: IndInv inductive, `MaxOps` open (13 s).
- Mutants 4 rejected (develop, no_self, no_pl, jira); witnesses 8 reached; traces 6 accepted, 2 corrupted runs refused;
  batch of 151 distinct segments of one full TC body run accepted (scratch copy).
- TLAPS `PxSysopGate_proofs.tla`: 641/641 obligations proved, tlapm `efe4f2d` (1.6.0-pre).
- Spec sha256: `PxSysopGate.tla` d78cb966d485f8ad..., `PxSysopGateTrace.tla` 404d05d0c3aedf1a...,
  `PxSysopGateTraceData.tla` 9f2fbe9b33b69f77..., `PxSysopGate_proofs.tla` fb24407924f430d4....
- Engine: PR head `316431fba`; trace build `~/optdebug/CUBRID-pr8424-tlatrace` (optdebug, libcubrid.so `42beb56b5f65...`);
  base-gate counter build `~/optdebug/CUBRID-pr8424-tlabase` (libcubrid.so `e614092a385e...`).
