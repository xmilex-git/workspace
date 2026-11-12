# CBRD-28044 — the parallel query paths free what they do not own: an uninitialized collector after a failed sector read, and a job's subquery state from the main thread's heap

Two models, one per defect; they share no state.

Model `SectorCollector.tla`: the ownership of a `FILE_FTAB_COLLECTOR`'s `partsect_ftab` at one call
site — the six callers of `file_get_all_data_sectors ()` and `file_destroy ()`'s own collector. One
thread per call site and nothing shared between call sites, so a behavior runs one site, chosen in
`Init`. Engine sha: develop `a3988b832` when modeled; the change is commit `4359cf3a7` on develop `98b892cf4` (worktree `~/dev/cubrid-worktree/CBRD-28044`, local branch `CBRD-28044`); the mapped code is unchanged between the two.

Model `ParallelClear.tla`: the parallel subquery executor's two clears of a job's XASL tree — the
job's own clear on the thread that ran it (`qexec_clear_xasl_for_parallel_aptr`, called from
`execute_job_internal`) and the main thread's clear of the whole tree at the end
(`qexec_clear_xasl`). Same engine sha.

trace-exempt: each call site's collector is a stack variable of one thread, and a job's tree is cleared by the thread that ran it after that job ended (the main thread's clear waits for every job), so a recorded run has no interleaving for the trace to tell apart; the code is checked instead by runtime reproductions of the same method before and after the fix (CS mode, optdebug; the Result section) (decision D3, 2026-11-12).

## Claim and sources

| # | Claim | Source |
|---|---|---|
| C1 | No call site frees a `partsect_ftab` value the allocator did not hand it or already took back (an uninitialized stack value, a freed array not set to NULL). | CBRD-28044 Actual Result (`mspace_free` abort from `init_on_main`, the freed pointer pointed at code); CBRD-27285 comment at `histogram_sampler_sr.cpp:1024` |
| C2 | Every array `file_get_all_data_sectors ()` or `file_destroy ()` allocates into the collector is freed exactly once by the time the call site returns, on every exit. | CBRD-28044 body ("실패 때 자기가 할당한 것을 해제하고 NULL 로 둔다"); `file_destroy` exit label |
| C3 | `file_get_all_data_sectors ()` leaves `collector_out` empty (`partsect_ftab` NULL, counts 0) on every failure return, so no caller depends on how it declared the collector. | decision D1 (user, 2026-11-12); CBRD-27285 and CBRD-28044 are the same defect at two callers |
| C4 | A job's execution state (heap attr values, scan caches, page batch copies) is freed by the thread that ran the job, never by another thread's private heap. | screenshot analysis handed over 2026-11-12 (`mspace_free` abort in the main thread's `qexec_clear_xasl` → `heap_attrinfo_end`); runtime: develop optdebug `956e1c19f` 3 of 5 runs (Result); cpp-perf-rules ALLOC-08 |
| C5 | Every node's execution state is freed exactly once by the end of the statement, whether the job ran every subquery or ended early. | `qexec_clear_xasl` frees what is still held; `db_private_free_and_init` NULLs what it frees |

## Decisions (grill-with-tla, 2026-11-12)

| # | Decision | Settled in the spec | Struck options |
|---|---|---|---|
| D1 | `file_get_all_data_sectors ()` empties `collector_out` before its first exit (C3); `init_on_main ()` drops its free on failure, which would only see NULL; its declaration stays without an initializer; the two histogram comments that described the old contract say the new one. | `Fix = "callee"` in `SectorCollector.cfg` (PASS, with `FailLeavesEmpty`) | caller only (CBRD-27285's shape, the ticket's proposal): passes C1 and C2 (`option-caller`), struck by C3 (`mutant-callee-no-reset`: `btsort` keeps the garbage after a header fix failure); callee + caller initializer (`option-both`): same verdict as D1, more lines |
| D2 | `file_destroy ()`'s collector is set NULL beside `vsid_collector.vsids`, before the first `goto exit` (the tracker unregister); a latent defect of the same kind since `cc368329d` (2016), fixed here. | `DestroyFix = TRUE`; `mutant-destroy-develop` violates `NoBadFree` | leave it to its own ticket |
| D3 | No trace validation: the trace-exempt line above; the runtime reproductions stand for it. | trace-exempt line | an instrumented build with recorded runs |
| D4 | No regression TC for the parallel heap scan's interrupt: the window is a race that needs a hidden parameter and a 4K-page DB; the manual repro goes into test.md. The parallel clear (D5) gets a sql TC: it crashes deterministically enough on the first runs. | no claim row | a fault-injection point to make the race deterministic (not asked) |
| D6 | The crash the same UNION ALL query also showed during execution (a job's correlated subquery list destroyed while its thread wrote it: tuple layout asserts, a temp file freed twice) is CBRD-27959, fixed in develop by `bb3ccce3f` (#8436, merged 2026-11-12 14:39) while this ticket was open: `qexec_clear_all_lists ()` no longer walks the block's `next` (a sibling job). This change is rebased on it and does not touch it. Found by an instrumented build (an XASL node records its executing thread; a clear by another thread aborts): the main thread's per-row `qexec_intprt_fnc → qexec_clear_all_lists` of job 1 reached job 2's dptr node. | no claim row; not modeled here | the same edit in this ticket (written, then dropped at the rebase as identical to `bb3ccce3f`) |
| D5 | The parallel clear walks each of the five lists a job's block owns (`bptr_list`, `dptr_list`, `fptr_list`, `scan_ptr`, `buildlist->eptr_list`) to its end, as `qexec_clear_xasl ()` does; only a job node's own `next` (a sibling job, run by another thread) is left alone. Folded into CBRD-28044 on the user's go (both: the parallel query path frees what it does not own). | `Fix = "walk"` in `ParallelClear.cfg` (PASS); `mutant-develop` violates `OwnerFrees`; `mutant-follow-next` (following the job's `next`) violates it too | a separate ticket |

## Refinement map (model -> code)

### SectorCollector

| Model | Code (develop a3988b832) | One step because |
|---|---|---|
| `site` | the call sites: `pxheap` = `parallel_scan::input_handler_heap::init_on_main` (`px_scan_input_handler_heap.cpp:58-89`); `list` = `qfile_collect_list_sector_info` (`list_file.c:7724`, loop over `dependent_list_id`); `btsort` = `btsort_start_parallelism` (`btree_sort.c:1841`, loop over `n_classes`); `capacity` = `heap_get_capacity_parallel` (`heap_file.c:10039-10255`); `histo_split` = `reserve_and_split` (`histogram_sampler_sr.cpp:1030`); `histo_full` = `xhistogram_build_multi_by_fullscan_reservoir` (`histogram_sampler_sr.cpp:2318`); `destroy` = `file_destroy` (`file_manager.c:4049-4301`) | data; code-index `callers file_get_all_data_sectors` lists exactly the six |
| `ptr` | the collector's `partsect_ftab` | single owner: a stack variable of the call site's thread |
| `Init` `ptr` | `DeclInit`: `FILE_FTAB_COLLECTOR_INITIALIZER` at the declaration (`list`, `capacity`, both `histo`); `pxheap` and `btsort` declare it uninitialized; `destroy` sets it NULL at `file_manager.c:4086`, after the tracker unregister (`DestroyFix`: before it) | declaration |
| `Call` `fix_fail` | `file_get_all_data_sectors` `file_manager.c:12608-12613`: `pgbuf_fix` of the file header fails (interrupt, latch timeout) and returns before touching `collector_out`; `Fix` `callee`/`both`: `collector_out` emptied before this exit | one call, one exit; no other thread sees the collector |
| `Call` `oom_first` | `file_manager.c:12618-12627`: the first `db_private_alloc` returns NULL into `collector_out->partsect_ftab` | same |
| `Call` `fail_after_alloc` | `file_manager.c:12634-12641` (second alloc OOM), `12655-12662` (part ftab walk error), `12670-12677` (full ftab walk error): each `db_private_free_and_init (collector_out->partsect_ftab)` | same |
| `Call` `ok` | `file_manager.c:12704`: the array is the caller's | same |
| `AfterFail` | `FreeOnFail`: `init_on_main` `px_scan_input_handler_heap.cpp:73-79` (develop; `Fix` != `none` drops it), `list_file.c:7802-7806` (`error_exit`), `heap_file.c:10251-10254` (`exit`); `btsort` and both `histo` return without a free | the caller's code between the return and its own return |
| `AfterOk` | `px_scan_input_handler_heap.cpp:85-88`, `list_file.c:7792-7795`, `btree_sort.c:1893`, `heap_file.c:10251`, `histogram_sampler_sr.cpp:1040-1043`, `2329-2332`: free and NULL; a loop site calls again | same |
| `DUnreg` | `file_manager.c:4075-4084`: `file_tracker_unregister` for a permanent file; failure `goto exit` | one call |
| `DReset` | `file_manager.c:4086` `ftab_collector.partsect_ftab = NULL` | one statement |
| `DCollect` | `file_manager.c:4088-4270`: header fix, `file_table_collect_all_vsids`, the ftab array alloc (`4135` temp, `4214` permanent), its walks; every failure `goto exit` | the body between the reset and the exit; the array is allocated at most once |
| `DExit` | `file_manager.c:4293-4296`: `db_private_free` if not NULL | one statement |
| `allocs`, `frees`, `badFree`, `lastExit` | ghosts | not code |

## Properties

| Name | Kind | Statement | Claim |
|---|---|---|---|
| `NoBadFree` | invariant | `badFree` never set | C1 |
| `NoLeak` | invariant | at `done`, `allocs = frees` | C2 |
| `FailLeavesEmpty` | invariant | after a failure return of `file_get_all_data_sectors`, `ptr = "null"` | C3 |
| `IndInv` (SectorCollector) | inductive invariant | `TypeOK`, `GadsPc`, `DestroyPc`, `OwnedCount`, `NotOwnedCount`, `NoDangling`, `OwnedOnlyAfter`, `GarbageSafe`, `DestroyShape`, `GadsShape`, `IterRange`, `AllocBound`, `ResCall`, `NoBadFree`, `NoLeak` | C1, C2 |
| `OwnerFrees` | invariant | `crossFree` never set | C4 |
| `FreedOnce` | invariant | `doubleFree` never set, and at the end no node's state is still held | C5 |
| `IndInv` (ParallelClear) | inductive invariant | `TypeOK`, `OwnerIsRunner`, `NoStale`, `RunNothing`, `ClearHeld`, `EndFreed`, `FinalAfterJobs`, `OwnerFrees`, `FreedOnce` | C4, C5 |

### ParallelClear

| Model | Code (develop a3988b832) | One step because |
|---|---|---|
| `Branches`, `Runner(b)` | the jobs of one parallel executor (`px_query_executor.cpp:343-372` gives `px_executor` to a node with two or more parallel aptrs; each such aptr is a job); `execute_job_internal` runs a job on a worker or, when it takes one, on the main thread (`parent_thread_p`, core of run 1: main `0x...3cc8` ran one branch, a worker the other) | data |
| `Pos`, `Nodes` | the job's block node (0) and the nodes of a list the block owns; the five lists (`bptr_list`, `dptr_list`, `fptr_list`, `scan_ptr`, `buildlist->eptr_list`) are cleared by the same code, so one list of `K` nodes stands for each | data |
| `st`, `owner` | a node's execution state: `heap_attrinfo` value arrays (`qexec_clear_access_spec_list` → `heap_attrinfo_end`), scan caches, page batch copies, allocated by `db_private_alloc` in the running thread's private heap (per-thread lea mspace) | single owner while the job runs: only the job's thread touches its tree |
| `Run(b)` | `qexec_execute_mainblock` of the job (`execute_job_internal`); a dptr node runs when a row reaches it (`qexec_execute_dptr_list`), so any subset of the list may have run when the job ends (an error or interrupt ends it early) | the job's thread alone; the state other threads read (`jpc`) changes only when the job ends |
| `JobClear(b)` | `qexec_clear_xasl_for_parallel_aptr (cur_thread_p, xasl, true)` (`px_query_task.cpp:214`): the block's own state, each list (`query_executor.c:3208-3227`, `3373-3377`), never the job node's `next` (`:3618`) | same thread, after the job's execution, before it reports the end |
| `JobClear` `Fix = "none"` | develop: `if (xasl->dptr_list) … (xasl->dptr_list)`: only the head of each list | the option under decision |
| `FinalClear` | the main thread's `qexec_clear_xasl (…, is_final = true, false)` over the whole tree at the end of the query (`query_executor.c:2645-2663` walks each list to its end) | after `run_jobs` has waited for every job |
| `Frees` | `db_private_free_and_init` in the clearing thread's heap: a NULL pointer is skipped | one free per node |
| `Mutant = "follow_next"` | a clear that also follows the job node's `next` (the sibling job, run on another thread) | mutant |
| `Mutant = "no_null"` | a free that leaves the pointer set (`db_private_free` without `_and_init`) | mutant |
| `Mutant = "no_final"` | the main thread's clear skipped | mutant |
| `crossFree`, `doubleFree` | ghosts | not code |

Callers: `qexec_clear_xasl_for_parallel_aptr` is called from `execute_job_internal` (`px_query_task.cpp:214`), from `qexec_clear_xasl` when `for_parallel_aptr` is true, and from itself (aptr, the five lists, `connect_by_ptr`, the CTE parts).

## Fault model and environment assumptions

| Fault | SectorCollector | ParallelClear |
|---|---|---|
| error return | every exit of `file_get_all_data_sectors` (`Call`'s four exits) and `file_destroy`'s (`DUnreg`, `DCollect`) | a job ended by an error runs any prefix of its subqueries (`Run`'s subset), then its clear runs as usual (`execute_job_internal` clears on every path) |
| interrupt / query cancel | the header fix fails by an interrupt: `fix_fail` | same as an error: the job ends early (`Run` subset) |
| lock timeout, deadlock victim | not applicable: no lock request in the mapped code | not applicable |
| conditional latch failure | not applicable: every fix is unconditional; its failure is `fix_fail` / `DCollect`'s failure branch | not applicable |
| OOM | `oom_first`, `fail_after_alloc` (second alloc); `file_destroy`'s alloc OOM is `DCollect`'s branch without an array | an allocation failure in a job ends it early (`Run` subset) |
| crash / `kill -9` | not applicable: the collector is private memory; `file_destroy`'s durable steps are not touched | not applicable: private memory of one query |
| spurious wakeup | not applicable: no wait | not applicable: `run_jobs`'s wait is outside the model; `FinalClear` needs every job ended |
| concurrent DML, vacuum, checkpoint, flush | not applicable: the file header is read under its latch, the array is private | not applicable |
| HA log apply | not applicable | not applicable |
| nested statement (SP SQL) | not applicable: no snapshot read | not applicable |
| a sibling job running at once | not applicable | `JobClear(b)` of one job interleaves with `Run`/`JobClear` of the other; `mutant-follow-next` shows why a job's `next` stays untouched |
| a nested parallel executor inside a job (an aptr with `px_executor`) | not applicable | not modeled: the aptr loop (`query_executor.c:3194-3206`) is unchanged and leaves such an aptr to its own jobs |

## Mutants

| cfg | Change | Expected | Kills |
|---|---|---|---|
| `SectorCollector.mutant-develop` | develop: `init_on_main` declares the collector uninitialized and frees it on failure; the callee does not empty it | `NoBadFree`: `pxheap`, header fix fails, the garbage is freed | C1 |
| `SectorCollector.mutant-destroy-develop` | develop `file_destroy`: NULL set after the tracker unregister | `NoBadFree`: permanent file, unregister fails, exit frees the garbage | C1 |
| `SectorCollector.mutant-callee-free-no-null` | the callee frees on failure without NULLing | `NoBadFree`: `list` frees the freed array again at `error_exit` | C1 |
| `SectorCollector.mutant-callee-leak` | the callee does not free on a failure after its alloc | `NoLeak` | C2 |
| `SectorCollector.mutant-px-no-free-ok` | `init_on_main` drops its free on success | `NoLeak` | C2 |
| `SectorCollector.mutant-callee-no-reset` | the caller-only option (callee not emptying the collector) | `FailLeavesEmpty`: `btsort`, header fix fails, the collector keeps its garbage | C3 |
| `ParallelClear.mutant-develop` | develop: the job clear takes only each list's head | `OwnerFrees`: the main thread frees the worker's second dptr's state | C4 |
| `ParallelClear.mutant-follow-next` | the job clear follows the job's `next` | `OwnerFrees`: a job frees its sibling's state | C4 |
| `ParallelClear.mutant-no-null` | a free leaves the pointer set | `FreedOnce`: the final clear frees it again | C5 |
| `ParallelClear.mutant-no-final` | the main thread's final clear skipped (develop job clear) | `FreedOnce`: list tails still held at the end | C5 |

## Witnesses

| cfg | Outcome reached |
|---|---|
| `SectorCollector.witness-px-fix-fail-done` | the parallel heap scan's call site ends after the header fix failure (the defect's path) |
| `SectorCollector.witness-destroy-unreg-fail` | `file_destroy` ends after a failed tracker unregister |
| `SectorCollector.witness-loop-fail-after-ok` | a loop site (`list`, `btsort`) fails on its second call after a successful first |
| `ParallelClear.witness-worker-list-tail` | the worker job's last list node is freed by the end (the defect's case, by its own thread under the fix) |
| `ParallelClear.witness-job-ended-early` | a job ends with subqueries that never ran (error, interrupt, no row reached them) |

## Dead expressions

| Line | Expression | Why dead in the main cfg |
|---|---|---|
| SectorCollector.tla:87 | `Call`'s `fail_after_alloc` branch keeping the array | mutant-only (`Mutant = "callee_leak"`); `mutant-callee-leak` fires it |
| SectorCollector.tla:100 | `AfterFail`'s free | under the fix every failure leaves NULL (C3), so the sites that free on failure (`list` `error_exit`, `capacity` `exit`) find nothing; `mutant-develop` and `mutant-callee-free-no-null` fire it |
| SectorCollector.tla:108 | `AfterOk` without the free | mutant-only (`Mutant = "px_no_free_ok"`); `mutant-px-no-free-ok` fires it |
| ParallelClear.tla:83 | `FinalClear` skipped | mutant-only (`Mutant = "no_final"`); `mutant-no-final` fires it |

## Bounds

SectorCollector: every call site, `MaxIter` = 2 (loop sites call twice); scale `MaxIter` = 3. ParallelClear: `NB` = 2 jobs (one on the main thread, one on a worker), `K` = 2 list nodes (the defect needs two); scale `NB` = 3, `K` = 3. Apalache checks each IndInv inductive at the `CInit` constants (SectorCollector `Fix = "callee"`, `MaxIter` = 2; ParallelClear `NB` = 2, `K` = 2).

## Result

- 2026-11-12, `tools/tla/tla-check docs/tla/CBRD-28044` → `RESULT: OK`, run dir `.git_ignored_dir/scratch/tla/CBRD-28044-20261112-170623-2828761`.
- `SectorCollector` 221 distinct states, depth 5; `scale-3` 265, depth 7; `option-caller` and `option-both` 221, depth 5 (comparison cfgs: the options not chosen, claims' invariants only).
- `ParallelClear` 177 distinct states, depth 6; `scale-3` 14,897, depth 8.
- Mutants: all ten violate their property (Mutants table). Witnesses: all five reached.
- Apalache: `SectorCollector.apalache-indinv` and `ParallelClear.apalache-indinv` pass (each IndInv inductive at its `CInit` constants).
- TLAPS 요청 없음. Trace validation: trace-exempt (D3).
- spec sha256 `4cd4ea7170743d17005f8aff54f473ad463f34cc8d93e4209ec762bc34e4d208  ParallelClear.tla`, `d3d14eb0ee4cbd79cc6330563d93553462a03ffeb9799cffa3d399f2f0843656  SectorCollector.tla`.

Runtime (CS, optdebug, `parallelism=24`; scripts in `.git_ignored_dir/scratch/cbrd28044/`: `run.sh`, `q5loop.sh`, `gdbinj.sh`):

| Check | Before | After (`4359cf3a7`, optdebug `39570b2d…`, release `9ddf97a3…`) |
|---|---|---|
| C4/C5: the UNION ALL with two correlated subqueries per arm, one run per fresh server | develop `98b892cf4` (optdebug `83b9deed…`, includes CBRD-27959): 9 of 11 runs abort, all 14 cores (single + 50-statement) at the main thread's `qexec_clear_access_spec_list → heap_attrinfo_end → mspace_free`; develop `956e1c19f`: 3 of 6 the same, 1 CBRD-27959 | 0 of 11 |
| same, 50 statements per script | `98b892cf4`: 5 of 5 abort | 0 of 5 (50 of 50 results each) |
| a row-returning variant (`t2.sql`) | — | 9 rows, CS (parallel) identical to SA (serial) |
| C1/C3: the parallel heap scan's interrupted open (ticket repro, 4K pages, `parallel_scan_page_threshold=2`, 30 runs) | not reproduced on `956e1c19f` nor `98b892cf4` (30 of 30 alive): the race did not occur here; the evidence is the model and the reporter's core | 30 of 30 alive, each "Attempt to divide by zero." |
| C1 (D2): `file_destroy` with `file_tracker_unregister` failing (SA `csql -S` DROP TABLE under gdb, release; the tracker page fix forced to return NULL) | release `956e1c19f`: the exit frees `0x55555579fa38`, the transaction's `LOG_TDES` that `logtb_clear_tdes` reads later | release fix: no free from `file_destroy` |
| memory check: the smoke above with `use_system_malloc=yes`, `MALLOC_CHECK_=3`, `MALLOC_PERTURB_=165` | — | no crash, abort or result change (q5 1 + 5×50, px 30) |
| CTP sql (16 shards) + medium, TC develop `89f591ac7` | — | sql 17,794 / 17,794, medium 975 / 975 |

The third crash of the same SQL (D6) was found with an instrumented build of `a3988b832` (an XASL node records the thread executing it; a clear by another thread aborts): every 50-statement run aborted at the main thread's `qexec_intprt_fnc → qexec_clear_all_lists → qexec_clear_scan_all_lists → qexec_clear_head_lists` on the worker's dptr node; with `qexec_clear_all_lists` not walking `next` (= `bb3ccce3f`, CBRD-27959) 5 of 5 runs passed with no abort.
