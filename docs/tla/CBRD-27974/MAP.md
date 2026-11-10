# CBRD-27974 — the partial-entry fold reads the group through a slot of a freed slot array

Model `MergePartials.tla`: one partition of the hash GROUP BY merge, the partial-entry loop
`qexec_gby_merge_partials` for a GROUP BY without the first-row copy (`XASL_G_FIRST_TUPLE_NONE`,
`rd->no_first_tuple`), one thread. Engine sha: develop `e30370dc0` (the code is unchanged since
`2ca10ed03`, CBRD-27802). Runtime repro: develop optdebug `37182deba`
(`~/optdebug/CUBRID-develop-37182deba`, hardlinked copy `.git_ignored_dir/scratch/cbrd27974/inst`),
SA, `use_system_malloc=yes` + `MALLOC_PERTURB_=165`: 2,000 keys OK, 2,001 keys SIGSEGV at
`qexec_gby_merge_partials` `query_executor.c:6692` (`s->value->accumulators`); default conf on the same
build returns the right answer (`.git_ignored_dir/scratch/cbrd27974/run.sh`, `gdb.out`).

trace-exempt: design spec before the fix is written; the fix is checked by the runtime repro (fail before, pass after, same method), and its implementation spec, if one is written, refines this one (cubrid-tla step 9).

## Claim and sources

| # | Claim | Source |
|---|---|---|
| C1 | The partial-entry fold never reads a group through a slot of a slot array the merge table has already freed. | CBRD-27974 Actual Result (`p *s` = 0xa5 fill, `s - t->slots` out of range); C (a read after `free` is undefined) |
| C2 | A finished fold of a partition holds one group per key of its rows and partial entries, each aggregating every row and every partial entry of that key once. | CBRD-27974 Expected Result (2,001 rows, `COUNT(*)` 1 each); `qexec_gby_merge_partials` comment ("an entry whose key has no group yet makes one"); CBRD-27802 / ADR 0034 |

## Refinement map (model -> code)

| Model | Code (develop e30370dc0, `src/query/query_executor.c`) | One step because |
|---|---|---|
| `ent`, `pre` | the partition's partial-entry list (`partials[i]`) and the keys its row lists made groups of (`qexec_gby_merge_fold` folds every piece's rows first, `qexec_gby_merge_rows`) | data |
| `has`, `grp`, `cnt` | `t->slots[]` key/value, `AGGREGATE_HASH_VALUE.tuple_count` (and the accumulators), `t->count` | single owner: the merge job's own table |
| `cap`, `gen` | `t->mask + 1`, the array `t->slots` points to; `qexec_gby_mtable_grow` allocates a new array, rehashes, `db_private_free`s the old one | single owner |
| `Load` | `qdata_load_agg_hentry_from_tuple` → `qexec_gby_mtable_hash` → `qexec_gby_mtable_find` (`s = &t->slots[i]`) | one thread, nothing between find and the branch |
| `Add` | `qexec_gby_mtable_add (..., s, h, NULL, NULL, &added)`: arena carve, `s->key/value` set, `t->count++`, grow when `t->count * 2 > t->mask` | one call; the grow is inside it |
| `Add` grow-OOM branch | `qexec_gby_mtable_grow` returns `ER_OUT_OF_VIRTUAL_MEMORY` → `rc != NO_ERROR`, `break` | part of the `Add` call: the insert is done, the grow fails, the loop ends with the error |
| `AfterAdd` over branch | `limit > 0 && t->bytes > limit` → `*over = true`, `break`; `qexec_gby_merge_partition` rewinds the table and splits the partition again (every entry read again) | the check right after the call returns, before the fold |
| `AfterAdd` `v` | `Mutant = "develop"`: the loop then reads `s->value` (s into the array `find` returned); `Fix = "added"`: the `added` value (`AGGREGATE_HASH_VALUE`, carved from `t->arena`, never moved by a grow); `Fix = "refind"`: `qexec_gby_mtable_find` again | the option under decision |
| `Fold` | the `agg_template` loop `qdata_aggregate_accumulator_to_accumulator (&s->value->accumulators[i], ...)` and `s->value->tuple_count += rd->temp_part_value->tuple_count` | one thread; both read the group through the same pointer |
| `Fold` stale branches | the freed array kept its bytes (release SA + valgrind: no report, JIRA) or was overwritten (0xa5 fill, SIGSEGV; garbage `value` pointer) | one read; which branch depends on whether the freed bytes were reused (allocator, build) |
| `Mutant = "skip_new"` | a wrong fix that `continue`s after the add, as `qexec_gby_merge_rows` does for `!rd->first_aggregated` | mutant |
| `Done` | the loop's end / `break` | stutter at a terminal state |
| `Caps` | slot counts from 2 instead of `QEXEC_GBY_MTABLE_SLOTS` = 256: the grow rule `count * 2 > mask` is the same at every size | scaled down |
| `uaf`, `grew`, `foldOld` | ghosts | not code |

Callers: `qexec_gby_mtable_add` has two callers, `qexec_gby_merge_rows` (reads the returned `value`, no stale read) and `qexec_gby_merge_partials`; `qexec_gby_mtable_grow` is called only from `qexec_gby_mtable_add`. The other loops over `t->slots` (`qexec_gby_merge_write`, `qexec_gby_merge_collapse`, `qexec_gby_px_emit`, `qexec_gby_mtable_rewind`) add no group.

## Properties

| Name | Kind | Statement | Claim |
|---|---|---|---|
| `NoStaleSlotRead` | invariant | `uaf` never set | C1 |
| `FoldCorrect` | invariant | at `done`, `has[k]` iff k has rows or entries, `grp[k]` = rows + entries of k | C2 |
| `IndInv` | inductive invariant | `TypeOK`, `MutantOnly`, `GenBound`, `NoStaleSlotRead`, `FoldCorrect`, `EntryIdx`, `HasGroups`, `GroupCounts`, `CountIsGroups`, `LoadFactor`, `SlotGen` | C1, C2 |

## Fault model and environment assumptions

| Fault | Modeled as |
|---|---|
| error return | grow OOM after the insert (`Add` err branch); the other error returns (`qdata_load_agg_hentry_from_tuple`, the accumulator fold, arena OOM before the insert) end the loop before any state the claims read changes and the query fails |
| interrupt / query cancel | not applicable: the loop checks none; the job's `stop` is read between partitions |
| lock timeout, deadlock victim | not applicable: no lock |
| conditional latch failure | not applicable: the list scan's page fix is not part of the table's state |
| OOM | grow OOM (above); arena OOM returns before `s` is set |
| crash / `kill -9` | not applicable: private memory of one query |
| spurious wakeup | not applicable: no wait |
| concurrent DML, vacuum | not applicable: the lists are the query's own temp files |
| checkpoint, flush, replacement | not applicable |
| HA log apply | not applicable |
| nested statement (SP SQL) | not applicable: no snapshot read |
| budget reached | `AfterAdd` over branch, at every add |
| parallel merge (px) | not modeled: each merge job folds its partition into its own table (`job->table`), so the loop is the same per thread |

## Mutants

| cfg | Change | Expected | Kills |
|---|---|---|---|
| `mutant-develop` | the fold reads `s->value` after the add (develop) | `NoStaleSlotRead` violated: the add that makes the table half full grows it, `s` points into the freed array | C1 |
| `mutant-develop-lost` | same | `FoldCorrect` violated: the stale read lands on overwritten memory, the entry is not in its group | C2 |
| `mutant-skip-new` | `continue` after the add | `FoldCorrect` violated: the group made by an entry lacks that entry's count | C2 |

## Witnesses

| cfg | Outcome reached |
|---|---|
| `witness-grew-in-partials` | a grow inside the partial-entry loop |
| `witness-fold-existing` | an entry folded into a group the rows made |
| `witness-done-after-grow` | a finished fold after a grow (the defect's case, correct under the fix) |

## Dead expressions

| Line | Expression | Why dead in the main cfg |
|---|---|---|
| MergePartials.tla:89, MergePartials.tla:90, MergePartials.tla:91, MergePartials.tla:92 | `AfterAdd` reached from the no-grow branch | at NK = 2 every add grows the table (2 slots → 4 → 8, the grow rule `count * 2 > mask`); the scale cfg (NK = 3: the third group goes into 8 slots) evaluates them |
| MergePartials.tla:114 | `Add`'s no-grow branch | same: alive in `scale-4` |
| MergePartials.tla:121, MergePartials.tla:122, MergePartials.tla:123 | `Skip` | mutant-only (`Mutant = "skip_new"`); `mutant-skip-new` fires it |
| MergePartials.tla:133, MergePartials.tla:134 | `Fold`'s stale branches | mutant-only (`Mutant = "develop"`): under both fix options the fold never reads through a stale slot (C1); `mutant-develop` and `mutant-develop-lost` fire them |

## Bounds

Main N = 3 entries, NK = 2 keys; scale N = 4, NK = 3. Apalache checks IndInv inductive at N = 3, NK = 2 (CInit).

## Result

- 2026-11-10, `tools/tla/tla-check docs/tla/CBRD-27974` → `RESULT: OK`, run dir `.git_ignored_dir/scratch/tla/CBRD-27974-20261110-193409-3998006`.
- `MergePartials` 340 distinct states, depth 10; `scale-4` 8,439, depth 13; `fix-refind` 340, depth 10 (comparison: the option not recommended, claims' invariants only).
- Mutants: `mutant-develop` violates `NoStaleSlotRead` at depth 4 (rows made group 2 in 4 slots; entry 1's key 1 has no group → add → count 2, `2 * 2 > 3` → grow to 8 slots → the fold reads `s` of the freed 4-slot array); `mutant-develop-lost` and `mutant-skip-new` violate `FoldCorrect`.
- Apalache: `apalache-indinv` passes (IndInv inductive at N = 3, NK = 2).
- TLAPS 요청 없음. Trace validation: trace-exempt (above).
- spec sha256 `38ff532d3cb6539c6da18450103ac65eccc6672a8d0110343bed7538ae12d4cb  MergePartials.tla`.
- Runtime: develop optdebug `37182deba` SA, sysmalloc + `MALLOC_PERTURB_=165`: 2,001 keys SIGSEGV at `query_executor.c:6692`, 2,000 keys OK; default conf OK on both.
