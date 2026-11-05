# RtfLifecycle — the hash join runtime filter between its build, the parallel workers and its release

Code: develop `be0a9ab1f` (CBRD-27361 `309265e6d`, #8196). `query_hash_join.c` `hjoin_rtf_*`,
`query_executor.c` (`qexec_execute_mainblock_internal` around line 21946, `qexec_clear_xasl`,
`qexec_end_mainblock_iterations`), `px_scan_task.cpp` (`initialize` line 88, `finalize` line 565),
`px_scan.cpp` (`wait_for_workers` line 2003).

## Claim and sources

| # | Claim | Source |
|---|---|---|
| C1 | No worker and no leader reads the filter after `hjoin_rtf_release` freed it, on the normal path and on every error exit. | `query_hash_join.c:4995-4999` (release "once the target's scans are closed ... every worker ... has been drained ... and has dropped its alias"); `px_scan_task.cpp:652-660` (finalize unbinds before the clone is retired) |
| C2 | A probe row is dropped only when no row of the first input has its key: a filter is installed only from a list read to its end. | commit `309265e6d` ("drops the probe rows whose integer or DATE key it lacks"); `hjoin_rtf_build` ("a filter of the keys read so far would drop every probe row whose key was never read, so none is installed"; a key that does not key: no filter) |
| C3 | The counters the leader reads at the release hold every worker's rows. | `hjoin_rtf_unbind_clone` header ("the leader reads them after wait_for_workers ()"); `hjoin_rtf_release` comment |
| C4 | The leader reaches the release and finishes: the drain does not wait forever. | `manager::wait_for_workers` (JOB_ENDED, then `wait_workers`); every worker path ends in `finalize` |

## Refinement map (model -> code)

| Model | Code | One step because |
|---|---|---|
| `filt`, `fkeys` | `HASHJOIN_PROC_NODE.rtf` (`slots`, `has_empty_key`) and the target node's `rtf` | written by the leader only, before the workers start and after they are joined |
| `bkeys` | the first input's list file (its join-key column) | read-only after the first input ran |
| `alias[w]` | the worker clone's `xasl->rtf` (`hjoin_rtf_bind_clone`, `hjoin_rtf_sample`, `hjoin_rtf_unbind_clone`) | single owner (the worker) |
| `rows[w]`, `left[w]` | the clone's `rtf_rows` / the worker's share of pages | single owner |
| `merged[w]`, `Held` | the target node's `rtf_rows` after `__atomic_add_fetch` in `hjoin_rtf_unbind_clone` | one atomic add per counter; ordered before the leader's read by `wait_workers`' join |
| `stop` | the parallel scan's `interrupt` (worker error, leader interrupt, `JOB_ENDED`) | atomic |
| `LFirst` | `qexec_execute_mainblock (rtf_first)` | the leader's own block |
| `LBuild`, `LBuildFail` | `hjoin_rtf_build` (list scan to `S_END` installs; a decline installs none; an error frees and fails) | the leader alone, before any worker |
| `LInterrupt`, `LScanEnd` | the target block's row loop on the leader: its error/interrupt exit, or `S_END` | |
| `LSignalStop`, `LClose` | `wait_for_workers`: `JOB_ENDED`, then join every worker | join is the wait |
| `LRelease` | `hjoin_rtf_release` (from `qexec_end_mainblock_iterations` or the error exit's `qexec_clear_xasl`) | the leader alone, after the join |
| `WBind` | `task::initialize`: `clone_xasl`, `hjoin_rtf_bind_clone` | worker-local |
| `WRow` | the scan loop's interrupt check before a row / a chunk | the check and the lookup are separate steps (split once more after `release_before_drain` survived the coarser model) |
| `WProbe` | `hjoin_rtf_pass` (row loop, `row_body`) or `hjoin_rtf_contains_n` (the batch's leaf); the clone's `rtf_rows++` | one read of the filter |
| `WSample` | `hjoin_rtf_sample` on the clone | worker-local |
| `WEnd`, `WError` | the worker's share ends (`S_END`), or an error it raises sets the interrupt | |
| `WSkip` | a worker the interrupt stops before it bound | |
| `WFinalize` | `task::finalize`: `hjoin_rtf_unbind_clone`, `qexec_clear_xasl`, `xcache_retire_clone` | worker-local, then the atomic adds |

## Properties

| Name | Kind | Statement | Claim |
|---|---|---|---|
| `NoUseAfterFree` | invariant | no filter read after the free | C1 |
| `NoFalseNegative` | invariant | no row dropped whose key the first input has | C2 |
| `CountsComplete` | invariant | the counters the leader read equal every worker's rows | C3 |
| `LeaderFinishes` | liveness, WF on the leader's and the workers' progress steps | the leader reaches `done` | C4 |
| `IndInv` | inductive invariant | implies C1-C3; TLAPS-proved for any workers, keys, budget | C1-C3 |

## Fault model and environment assumptions

| Fault | Modeled as |
|---|---|
| error return | `LBuildFail` (list scan error), `WError` (a worker's row raises), `LInterrupt` (the leader's own error) |
| interrupt / query cancel | `LInterrupt`; workers see `stop` at `WRow` |
| lock timeout, deadlock victim | a worker or leader error (`WError`, `LInterrupt`) |
| conditional latch failure | not applicable (no latch in the filter's life) |
| OOM | `LBuild`'s decline branch (no filter, the join runs without it) |
| crash / `kill -9` | not applicable: the filter is private memory of one execution |
| spurious wakeup | not applicable here: `wait_workers` is the px join (`examples/condvar-handoff`, `px-error-handoff`) |
| concurrent DML, vacuum, checkpoint, HA apply | not applicable: they do not touch the filter |
| sample off | `WSample` on any bound worker, any time |
| fairness | WF on the leader's steps and on `WBind`, `WProbe`, `WEnd`, `WSkip`, `WFinalize`; a worker's share is finite (`left`) |

## Mutants

| cfg | Change | Expected | Kills |
|---|---|---|---|
| `mutant-release-before-drain` | the error exit frees the filter before `wait_for_workers` | `NoUseAfterFree` violated: a worker past its interrupt check reads the freed filter | C1 |
| `mutant-install-partial` | `hjoin_rtf_build` installs the keys read so far when the list scan stops early | `NoFalseNegative` violated | C2 |
| `mutant-read-counts-early` | the leader reads its node's counters before the drain | `CountsComplete` violated | C3 |
| `mutant-no-unbind` | `finalize` retires the clone without `hjoin_rtf_unbind_clone` | `CountsComplete` violated | C3 |
| `mutant-error-no-finalize` | a worker that raised an error never reaches `finalize` | deadlock: the leader waits in `LClose` forever | C4 |

## Witnesses

| cfg | Reached state |
|---|---|
| `witness-error-release` | the leader left on an error, drained, and freed a filter a worker had used |
| `witness-two-workers-counted` | two workers both checked rows against the filter before it was freed |

## Dead expressions (pass cfgs)

| Line | Why never evaluated |
|---|---|
| RtfLifecycle.tla:80 | `LBuild`'s partial install: mutant `install_partial` only |
| RtfLifecycle.tla:81 | the same branch |
| RtfLifecycle.tla:117 | `LReadEarly`: mutant `read_counts_early` only |
| RtfLifecycle.tla:118 | the same action |
| RtfLifecycle.tla:159 | `WFinalize`'s `no_unbind` branch: mutant `no_unbind` only |

## Bounds and limits

- TLC: 2 workers, 2 keys, 2 rows per worker; scale 3 workers. Inductive: 2 workers, 2 keys, 1 row.
- TLAPS: safety (C1-C3) for any workers, keys and budget. C4 is TLC-only, within the bounds.
- Not covered: the filter's hash table itself (`hjoin_rtf_insert`, `hjoin_rtf_grow`, `hjoin_rtf_contains*` are
  modeled as a key set); a filter reused across executions through a cached clone (`hjoin_rtf_build` and
  `hjoin_rtf_bind_clone` zero the fields first; read, not modeled); the leader's own row loop skips the filter on
  a parallel heap scan (`query_executor.c:14729`) and is not modeled as a reader.

## Counterexamples

| cfg | Classification |
|---|---|
| `mutant-release-before-drain` (first model) | surviving mutant: `WRow` checked the interrupt and read the filter in one step, coarser than the code; split into `WRow`/`WProbe` (step 5.3), after which the mutant is killed |
| main cfg, `LeaderFinishes` (first model) | model error: a sampled-off worker counted no rows, so its loop was unbounded; the worker's share is now finite (`left`) |
| inductive (first run) | unreachable initial states (`stop` before the scan): IndInv strengthened (P6) |

No counterexample from a correct-variant cfg remains.

## Result

2026-11-06, `tools/tla/tla-check docs/tla/CBRD-27361-runtime-filter`: `RESULT: OK`. Run dir
`.git_ignored_dir/scratch/tla/CBRD-27361-runtime-filter-20261106-011850-2322299`; TLC tla2tools 1.8.0, TLAPS tlapm 1.4.5.

| cfg | Result | States (distinct) | Depth |
|---|---|---|---|
| main | pass (incl. `LeaderFinishes`) | 39 276 (15 292) | 22 |
| scale-3workers | pass | 1 468 792 (391 684) | 30 |
| inductive-indinv | pass | 366 240 (94 752) | 1 |
| mutant-release-before-drain | violation `NoUseAfterFree` | 1 821 | 8 |
| mutant-install-partial | violation `NoFalseNegative` | 622 | 6 |
| mutant-read-counts-early | violation `CountsComplete` | 659 | 7 |
| mutant-no-unbind | violation `CountsComplete` | 12 007 | 12 |
| mutant-error-no-finalize | deadlock | 683 | 7 |
| witness-error-release | violation `NotErrorRelease` (reached) | 11 633 | 12 |
| witness-two-workers-counted | violation `NotSampledOff` (reached) | 30 700 | 16 |

TLAPS: `RtfLifecycle_proofs.tla` 379/379 obligations proved, none omitted.

```
1a609e3be122320d54c33c6a8dc1d6d8c4468968e9bd1d2d2c3a6d22bbdb8392  RtfLifecycle.tla
45db1c3e5639f1e0d51a708fc3563308bd348ad9171ac116e413a75386d8a0eb  RtfLifecycle_proofs.tla
```

Engine: develop `be0a9ab1f`, read only. Trace validation (step 8, PX worker coordination) not run: pending the
user's decision on an instrumented build.
