# PartWalk — the per-outer-row partition walk of a partitioned NL inner (PR #8356, CBRD-27866)

Engine head `60058202c` (worktree `~/dev/cubrid-worktree/pr8356-review`), merge-base `e98bdd885`.
One executor thread drives the inner scan of one scan chain; a PX worker runs its own XASL clone
with its own `ACCESS_SPEC_TYPE` (`parts`, `row_pruning`, kept caches are per clone), so the walk
has no shared state between threads. What the model explores is the input: the join kind, the
inner rows per partition, the outer keys, per-row pruning, the memo (absent, present, dropped
midway) and a re-execution of the scan.

## Claim and sources

| # | Claim | Source |
|---|---|---|
| C1 | Each outer row is read once per execution: a partitioned inner does not run the outer again per partition. | JIRA CBRD-27866 Acceptance Criteria 1단계; PR description Purpose |
| C2 | The join returns develop's rows for inner, LEFT, SEMI and ANTI inners, with or without memo, with the memo dropped midway, and with per-row pruning; a closed memo entry answers what the walk returns. | JIRA Specification Changes "없음(결과 행 동일)"; PR Remarks "결과 행 변화 없음"; code comments in `qexec_execute_scan` (CBRD-27465, CBRD-27493) |
| C3 | With a partition-key equality join term, an outer row whose key has a partition opens only that partition. (A key with no partition opens the first one when the pruning leaves none, or every partition when the pruning function finds no match: `partition_prune_range` turns MATCH_OK with nothing added into MATCH_NOT_FOUND, partition.c:1624; trace `left`/`anti` row 2.) | JIRA AC 3단계; PR Implementation "조인 키가 파티션 키이면 행마다 그 행의 파티션만 엽니다", `qexec_open_row_partition` comment |
| C4 | A row the memo answers switches no partition. | PR Implementation "지연 되감기 ... memo 가 답하면 pending 을 지웁니다"; `qexec_reset_sa_inner_scan_block` comment |
| C5 | A re-executed scan (a subquery run again) opens again: the last row's `row_pruned` marks do not leave every partition out. | PR reply to review 4476503330 (60058202c), `qexec_open_scan` comment |
| C6 | The walk stops on the last partition the row reads and leaves it open; it never goes back to the root class. | PR Implementation "순회는 마지막 파티션에서 멈춰 스캔을 열어 둡니다"; `qexec_execute_scan` comment "A deferred walk stops on its last partition" |

## Refinement map (model -> code)

| Model | Code (60058202c) | One step because |
|---|---|---|
| `Reset` | `query_executor.c:qexec_reset_sa_inner_scan_block` deferred branch: `curr_spec = spec_list`, `row_rewind_pending = true`, `single_fetched = false`; merge-base: the block reset | single thread; no other reader of the spec |
| `Enter` hit | `qexec_execute_scan` `qexec_execute_nljoin_with_memoize` success -> `row_rewind_pending = false`, return | the replay of an entry is one result in the model (replay internals are memoize.cpp, not changed) |
| `Enter` miss | `qexec_execute_scan` memo miss: the entry for the key starts over | |
| `OpenRow` | `qexec_open_row_partition` (`none`: for a key with no partition, whether the pruning keeps none or, MATCH_NOT_FOUND, all): `partition_prune_spec_for_row` (`row_pruned`), first live partition, forced first partition for `QPROC_NO_SINGLE_OUTER` / `XASL_NL_ANTIJOIN`, `scan_reset_scan_block` when it is `curent` and `S_STARTED`, else `qexec_init_next_partition` (`scan_switch_index_partition` or close/open), all pruned -> `curr_spec = NULL`, `memoize_put_nullptr`, `S_END` | one call, no shared state |
| `Loop` mode | `qexec_execute_scan` do-loop head: `s_id.single_fetch = qexec_row_partition_has_next ? QPROC_NO_SINGLE_INNER : QPROC_NO_SINGLE_OUTER` for an outer join | |
| `Loop` res | `scan_manager.c:scan_next_scan` per `single_fetch` (`QPROC_NO_SINGLE_INNER`, `QPROC_NO_SINGLE_OUTER` with `null_fetched`, `QPROC_SINGLE_INNER`), then the outer-join latch `single_fetched = true` on `S_SUCCESS` | one call |
| `Loop` S_SUCCESS | `memoize_put`; SEMI: the outer row goes through (the entry is complete at the first match); ANTI: `memoize_put`, drain, `S_END` | |
| `Loop` S_END, next partition | `XASL_NL_FOLLOWING_JOIN` / SEMI-ANTI branches: `qexec_next_scan_block` -> `qexec_init_next_partition` past `row_pruned`, outer join `single_fetched = row_fetched` | |
| `Loop` S_END, last partition | `memoize_put_nullptr`; ANTI: `single_fetched = qualified_block = true`, `qexec_execute_sa_anti_survive`, which returns the row and is entered again (`pc' = "loop"`, then the re-entry) | |
| `Loop` re-entry | SEMI / ANTI with `single_fetched` -> `S_END` | |
| `RowEnd` | the parent's next outer row (`qexec_execute_scan` of the outer level calls `qexec_reset_sa_inner_scan_block` again) | |
| `Reopen` | `qexec_close_scan` (`curent = NULL`), `qexec_open_scan` S_SELECT branch: every `row_pruned = false`, `qexec_init_next_partition`; the execution builds its memo storage again (trace `reopen`: the second execution's first row misses) | |
| `MemoDrop` | `memoize::storage` freed by its budget / hit-ratio check | environment, no fairness |
| `Mutant = "block"` | merge-base `qexec_next_scan_block_iterations`: every outer row again per partition block | |
| ghosts `em`, `reads`, `opened`, `hit`, `err` | rows returned, outer reads, partitions opened or reset, memo answer, open failure | |

## Properties

| Name | Kind | Statement | Claim |
|---|---|---|---|
| `TypeOK` | invariant | variable types | — |
| `ReadOnce` | invariant | `reads[x] <= 1` | C1 |
| `ResultOK` | invariant | at the end of an execution every outer row returned `Exp` | C2 |
| `MemoSound` | invariant | a closed entry replays `Exp` | C2 |
| `PruneOK` | invariant | with pruning and a key that has a partition, the row opens only that partition | C3 |
| `HitOpensNone` | invariant | a memo answer opens nothing | C4 |
| `NoReopenError` | invariant | the re-execution opens | C5 |
| `NoRootBlock` | invariant | the loop never runs on the root class | C6 |
| `Terminates` | liveness, WF on the executor actions | every execution ends | — |
| `IndInv` | inductive invariant | implies all of the above invariants; inductive by Apalache (NP = NR = NK = 2, NExec = 1), checked on every reachable state by the main and scale cfgs | C1-C6 |

## Fault model and environment assumptions

| Item | Modeled as / why not |
|---|---|
| error return (`partition_prune_spec_for_row`, `scan_switch_index_partition`, `heap_scancache_switch_class`, `heap_attrinfo_*`, `qexec_init_next_partition`) | not modeled: every one returns `S_ERROR` straight to the caller and ends the query (`qexec_open_row_partition`, `qexec_init_next_partition` return paths); no later step reads the walk state, `qexec_clear_access_spec_list` frees `row_pruning` and the kept caches |
| interrupt / query cancel | not modeled: no loop in the changed code checks it; it surfaces as an error of `scan_next_scan` (row above) |
| lock timeout, deadlock victim (`lock_scan` IS_LOCK in `heap_scancache_switch_class`) | not modeled: the partition already holds IS/IX from `qexec_prune_spec` (`lock_subclass` over every partition at open), so the request is a re-grant; a failure is an error return (row above) |
| OOM (`malloc` of `PRUNING_CONTEXT`, `PARTITION_SCAN_CACHE`) | the first returns `ER_OUT_OF_VIRTUAL_MEMORY`; the second falls back to `heap_attrinfo_start` (`*kept == NULL`), state of the walk unchanged |
| crash, checkpoint, page replacement, vacuum, concurrent DML, HA | not applicable: the walk keeps no durable state; row visibility is the snapshot's and is the same for every partition order |
| memo budget kill | modeled: `MemoDrop` at any step |
| memo replay internals | not modeled: the replay of an entry is one `Enter` result; memoize.cpp is unchanged by the PR |
| SEMI / ANTI memo entry | assumption: an entry is complete at the first match (`memoize_put` then the outer row decides) |
| pruning soundness | assumption: `partition_prune_spec_for_row` leaves out only partitions without the key (`data` respects `home` when `prune`); the planner restricts the flag to integer and date/time keys of the same type (`qo_nl_inner_prunes_per_row`) |
| root heap rows (ALTER ... PARTITION BY) | not modeled: the per-row walk starts at the first partition for every scan op type; a join DML never runs while the root still holds rows (the redistribution UPDATE is single-table) |
| fast switch vs close/open | one action: both leave the scan started on the partition with `single_fetched`, `null_fetched` false (`scan_init_scan_id` in `scan_switch_index_partition`, `scan_reset_scan_block` after it) |
| attribute-cache parking, `heap_attrinfo_start_private`, 4 MB cap, `xasl_merge_stats` | not a state of the walk: checked by the review's reading and runtime (report), outside this model |
| PX worker clone | per-clone copy of the spec (XASL clone), no shared walk state; `partition_prune_spec` in `px_scan_task.cpp` gives the clone its `parts` |

## Mutants

| cfg | Change | Expected | Kills |
|---|---|---|---|
| `mutant-block` | merge-base: the block iterator reads every outer row once per partition | `ReadOnce` violated | C1 |
| `mutant-no-fetched-restore` | an outer join forgets a row of an earlier partition at the switch | `ResultOK` (extra NULL row) | C2 |
| `mutant-no-success-latch` | no `single_fetched = true` on an outer join row in `QPROC_NO_SINGLE_INNER` mode | `ResultOK` (extra NULL row) | C2 |
| `mutant-all-partitions-outer` | every partition in `QPROC_NO_SINGLE_OUTER` | `ResultOK` (NULL row per partition) | C2 |
| `mutant-no-force-partition` | all pruned returns `S_END` for LEFT / ANTI too | `ResultOK` (missing NULL row / survivor) | C2, C3 |
| `mutant-memo-done-each-partition` | `memoize_put_nullptr` at every partition end | `MemoSound` | C2, C4 |
| `mutant-no-reopen-reset` | `qexec_open_scan` keeps the last row's `row_pruned` | `NoReopenError` | C5 |
| `mutant-has-next-ignores-pruned` | `qexec_row_partition_has_next` ignores `row_pruned` | `NoRootBlock` | C6 |

## Witnesses

| cfg | Reached state |
|---|---|
| `witness-left-null-row` | an outer join row returns its NULL row after the walk |
| `witness-forced-partition` | a pruned-out LEFT / ANTI row opens the first partition |
| `witness-memo-hit` | the memo answers a row |
| `witness-reused-partition` | a later row reuses the last partition left open |
| `witness-reopened` | a re-execution reads a row |
| `witness-memo-dropped` | the memo is dropped after it closed an entry |
| `witness-unpruned-walk` | a pruned row whose key has no partition walks to the last partition |

## Dead expressions (pass cfg)

| Line | Why never evaluated |
|---|---|
| PartWalk.tla:162 | `Reset` branch of `mutant-block` only |
| PartWalk.tla:246 | `Loop` block-iterator branch of `mutant-block` only |
| PartWalk.tla:275 | `RowEnd` next-block branch of `mutant-block` only |
| PartWalk.tla:288 | `Reopen` failure: `mutant-no-reopen-reset` only (C5 holds) |
| PartWalk.tla:289 | same branch |

## Bounds and limits

- TLC main: NP = 2 partitions, NR = 2 outer rows, NK = 2 keys, NExec = 1 re-execution, every kind, data, home, prune and memo setting in Init. Scale: NP = 3.
- Apalache inductive: `IndInv /\ Next => IndInv'` over every IndInv state at NP = NR = NK = 2, NExec = 1.
- TLAPS: 요청 없음 (ADR 0046, cubrid-tla P48; the user chose to stop it on 2026-11-06). A partial proof (InitInv, InvSafe and every action but Loop, 735 obligations on tlapm efe4f2d) is kept outside the spec directory in the review scratch and counts for nothing here.
- `Terminates` is a TLC result inside the bounds.
- IndInv strengthenings the Apalache counterexamples asked for (each an unreachable state): `R_rp` only for a row the memo did not answer, `R_open` holds `pending` from `enter` on, `R_left` adds `nf => ~HasNext`.

## Trace validation

The change takes an IS_LOCK in `heap_scancache_switch_class` and changes PX trace merging, so the walk's map
is tied to the code by recorded runs (cubrid-tla step 8).

- Build: scratch worktree `~/dev/cubrid-worktree/pr8356-tlatrace` = 60058202c + `qexec_tla_trace` lines in
  `query_executor.c` (Open, Reset, Enter hit, OpenRow first, Loop res / end nxt / end last / end reent),
  optdebug, `~/optdebug/CUBRID-pr8356-tlatrace`, libcubrid.so `4df0508b...`; runs in SA mode (`csql -S`).
- Data: `pr3` range (p0 < 3, p1 < 6, p2 < 9; rows k = 1, 7) with index on k; `pn3` hash 3 on k with index on c
  (c = 6 in p0, c = 5, 5, 7 in p2); outer `o3` keys 1, 10, 1 and `on3` keys 5, 9, 5; `x2` two rows.
- Hidden actions: `RowEnd`, `MemoDrop`; the first outer row is rewound twice before it enters the inner, the
  second rewind a stutter step (`Reset` at `enter`).

| cfg | run | verdict |
|---|---|---|
| `witness-trace-left` | `o3 LEFT JOIN pr3 ON p.k = o3.k` (16 events) | accepted |
| `witness-trace-anti` | `NOT EXISTS (pr3 p.k = o3.k)` (15) | accepted |
| `witness-trace-reopen` | correlated subquery `o3, pr3` run for two `x2` rows (30) | accepted |
| `witness-trace-semi` | `EXISTS (pn3 p.c = on3.k)` (17) | accepted |
| `reject-left-no-null-row` | `left` with the NULL row event dropped | refused |

Divergences the first runs showed, each a model error fixed in the model: the second execution's memo is new
(Reopen), ANTI is entered again after its row goes through, and a key with no range partition is not pruned.
Not covered by a run: `MemoDrop` (no budget kill at this size), the forced first partition (needs join terms
whose partition sets do not meet), `no_reopen_reset` (the code fix).

## Result

- 2026-11-06, `tools/tla/tla-check --workers 8`, toolchain `mcnrlar201f0kiwhaz2d8pfxhbl6h3zb-tla-tools`: `RESULT: OK`,
  run dir `.git_ignored_dir/scratch/tla/per-row-partition-walk-20261106-093844-3079880`.
- TLC: main 340 716 / 233 696 states (depth 35), scale (NP = 3) 2 449 022 / 1 724 836 (depth 43); 8 mutants rejected;
  7 witnesses reached; `Terminates` holds in both.
- Apalache 0.62.4: IndInv inductive at NP = NR = NK = 2, NExec = 1 (17 s).
- TLAPS: 요청 없음 (ADR 0046).
- Trace: 4 runs accepted, 1 corrupted run refused, on the instrumented 60058202c optdebug build (libcubrid.so `4df0508b...`).
- spec sha256: `PartWalk.tla` b11c2e8c..., `PartWalkTrace.tla` 3434e2d2..., `PartWalkTraceData.tla` 5a983db7...
