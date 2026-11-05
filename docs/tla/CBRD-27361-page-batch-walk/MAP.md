# PageBatchWalk — the page batch's heap walk hands every visible row out once, in heap order, from a held page

Code: develop `be0a9ab1f` (CBRD-27361 page batch `309265e6d`, #8196). Worktree
`~/dev/cubrid-worktree/tla-develop-be0a9ab1f`. Two modes share the walk: `chain` (the consumers of
`qexec_batch_scan_chain` and the px worker's batch loop: aggregate, hash GROUP BY, projection) and `iter`
(the filter iterator `scan_batch_iter_next`, whose rows go out one by one to joins and subqueries).

## Claim and sources

| # | Claim | Source |
|---|---|---|
| C1 | Every row the scan's snapshot sees goes to the consumer exactly once, in heap order, and no row the snapshot does not see goes out — whatever mix of chunks, declined chunks, records whose version is off the page, unlearned representations, page releases and concurrent DML/vacuum. | commit `309265e6d` ("Rows leave in heap order, as on develop"); `heap_file.c` `heap_page_collect_visible` header ("the rows therefore come in the heap's order"); `expr_batch.h:234-236` ("a FALLBACK from any node leaves nothing of the chunk anywhere"); `scan_batch_page_rowmode` header |
| C2 | No peeked row of a chunk is read after its page was let go, or let go and fixed again, since the chunk was collected. | `expr_batch.c:5515` `expr_batch_run` (page_was_unfixed hands the chunk back); `scan_manager.c` `scan_batch_copy_kept` header; `scan_batch_open_internal` comment above `assert (xasl == NULL \|\| scan_id->fixed)` |
| C3 | The walk never fixes a page vacuum may have removed: a page is fixed again only when a row the snapshot sees is on it, and the next page is fixed before the held one is released. | `scan_manager.c` `scan_batch_next_page` ("A row this snapshot sees was on it, so vacuum cannot have deallocated it"; "the next page fixed before the held one is released"); `scan_next_heap_scan_rows` row-mode comment ("instead of fixing again a page none of whose rows this snapshot saw") |

## Refinement map (model -> code)

| Model | Code | One step because |
|---|---|---|
| `rec`, `alive` | heap records and the heap page chain | written only by `Env*` under the page's write latch |
| `fixed`, `cur` | `HEAP_SCAN_ID.scan_cache.page_watcher.pgptr`, `batch_vpid` | single owner (the scanning thread) |
| `unfixedFlag` | `PGBUF_WATCHER.page_was_unfixed` (`page_buffer.c:12897`, cleared by a fresh `pgbuf_ordered_fix`) | single owner |
| `ptrValid` | ghost: the page held continuously since `heap_page_collect_visible` peeked the chunk's records | |
| `NextFirst` | `scan_batch_next_page` first branch: `pgbuf_ordered_fix (header page, OLD_PAGE_PREVENT_DEALLOC)` | one fix |
| `NextRefix` | `scan_batch_next_page`, `page_watcher.pgptr == NULL` branch | one fix |
| `NextHop` | `scan_batch_next_page`: `heap_vpid_next`, `pgbuf_replace_watcher`, fix next, unfix old | both pages latched across the step (the next is fixed before the old is released) |
| `CollectRefix` | `heap_page_collect_visible` (`heap_file.c:8297`) fixing the page when the watcher was let go; `scan_batch_iter_next` re-fix | one fix |
| `Collect` | `scan_batch_collect_chunk` -> `heap_page_collect_visible` (one call: S_SUCCESS / S_END / S_DOESNT_FIT) | the walk runs under the page's read latch from first to last slot it looks at |
| `Learn`, `LearnDrop`, `LearnRefix` | `scan_batch_collect_chunk` -> `expr_batch_plan_learn_repr` (`expr_batch.c:6117`); its `heap_classrepr_get` ordered fix may release and re-fix the page | release and re-fix are two steps; the environment runs between them |
| `RunOk`, `RunDecline`, `RunError` | `expr_batch_run` (`expr_batch.c:5511`) through `expr_chunk_eval_consume` / `scan_batch_iter_next` | under the held page |
| `RunDrop`, `RunRefix` | an ordered fix on this thread under `eb_run_chunk` (page_was_unfixed set) | release and re-fix are two steps |
| `ConsumeRow`, `ConsumeEnd` | the blocking node: `qdata_agg_chunk_consume`, `qexec_batch_gby_consume`, `scan_batch_project_consume` | one row per step (the code takes the whole chunk under the latch: finer is sound) |
| `Copy` | `scan_batch_iter_next`: `scan_batch_copy_kept`, then `pgbuf_ordered_unfix`; `scan_batch_rows_consume` for a cached px scan | copy under the latch, then the release |
| `EmitRow`, `EmitEnd` | `scan_batch_iter_next` returning a kept row from its copy (`scan_batch_row_values`) | no page access |
| `RowRefix`, `RowNext`, `RowEnd` | row mode: `scan_next_heap_scan_rows` -> `heap_next_1page (batch_vpid, curr_oid)`; `release_after_row` (iter), a previous-version walk / forward-page fetch (`off`) | one record under the latch; the release ends the step |
| `Interrupt` | `logtb_is_interrupted` checks / an error on the row path | |
| `EnvUpdate` | `heap_update_logical` / `heap_delete_logical` by another transaction: the home record changes in place, the old version is in the log (`vis`/`rep` -> `off`) | write latch on the page |
| `EnvVacuum`, `EnvInsert` | `vacuum_heap_page` removing an invisible record; `heap_insert_logical` of a record the snapshot cannot see | write latch |
| `EnvRemove` | `heap_remove_page_on_vacuum` (`heap_file.c:3332`): an empty page leaves the chain, its neighbours write-latched | write latches on the page and both neighbours |

## Properties

| Name | Kind | Statement | Claim |
|---|---|---|---|
| `NoDuplicate`, `NoInvisibleRow`, `Complete` | invariants | no row twice; only visible rows; at the end every visible row went out | C1 |
| `IEm` (part of `IndInv`) | inductive | the rows out are exactly the visible rows up to `<<cur, front>>` (heap-order prefix) | C1 |
| `NoUseAfterUnfix` | invariant | no peeked chunk row read without the page held since collection | C2 |
| `NoFixOfRemovedPage` | invariant | no fix of a page that left the chain | C3 |
| `AnsStable` | action property | the environment never changes which records the snapshot sees (the MVCC assumption the equivalence rests on) | C1 |
| `IndInv` | inductive invariant | implies all of the above; TLAPS-proved for any NP, NS and both modes | C1-C3 |

## Fault model and environment assumptions

| Fault | Modeled as |
|---|---|
| error return | `RunError`, `Interrupt` (scan stops; the properties hold for what went out); OOM in `scan_batch_copy_kept` is the same error exit |
| interrupt / query cancel | `Interrupt` in collect and row phases |
| lock timeout, deadlock victim | not applicable: the batch refuses locking reads (`scan_batch_open_internal`: `mvcc_select_lock_needed`) |
| conditional latch failure | not applicable: every fix in the walk is unconditional (`pgbuf_ordered_fix` read latch) |
| ordered-fix release and re-fix on this thread | `LearnDrop`, `RunDrop`, row-path release (`off`); under the blocking node it is excluded by eligibility (`qexec_batch_eligible`: no fptr/dptr/scan_ptr/selected_upd; `XASL_NO_FIXED_SCAN` for serial and catalog operators makes the scan cached, refused by `scan_batch_open_internal`; a stored function's callback queries run on another server thread, `pl_executor.cpp` callback_execute) — mutant `tail_drop` shows C2 depends on it |
| OOM | the plan build declines (row path); copy failure = error exit |
| crash / `kill -9` | not applicable: a read-only scan holds no durable state |
| spurious wakeup | not applicable: no condition wait in the walk |
| concurrent DML | `EnvUpdate`, `EnvInsert` on every page the scan does not hold |
| vacuum | `EnvVacuum`, `EnvRemove` (page removal from the chain) |
| checkpoint, page flush, page replacement | covered by C2's ghost: any release of the page invalidates the chunk's pointers (`ptrValid`), whether or not the frame was replaced |
| HA log apply | not applicable: applied changes are concurrent DML from the scan's view |
| MVCC snapshot | assumed (`AnsStable`): a record visible to the snapshot stays visible (vacuum's threshold is at or below the snapshot's lowest active MVCCID); new and vacuumable records stay invisible |
| chunk size | abstracted: the cap may end a chunk at any visible row (`EXPR_BATCH_CHUNK_BYTES`) |
| filter selectivity | not modeled: every row qualifies (a filter only shrinks `n_sel`, which `Copy`'s unfix condition reads as non-empty) |
| heap growth | not modeled: pages appended after the walk passed hold only records the snapshot cannot see |

## Mutants

| cfg | Change | Expected | Kills |
|---|---|---|---|
| `mutant-exc-resume-at-slot` | `heap_page_collect_visible` returns `*slot = oid.slotid` instead of `oid.slotid - 1` after a chunk that ends before an off-page record | `Complete` violated: that record never goes out | C1 |
| `mutant-fallback-from-pos` | a declined chunk goes to the row path from the chunk's end, not `chunk_start` | `Complete` violated: the chunk's rows are lost | C1 |
| `mutant-fallback-after-consume` | the blocking node accumulates part of a chunk, then hands it back | `NoDuplicate` violated | C1 |
| `mutant-no-unfixed-check` | `expr_batch_run` ignores `page_was_unfixed` | `NoUseAfterUnfix` violated | C2 |
| `mutant-tail-drop` | (environment assumption) an ordered fix on this thread under the blocking node | `NoUseAfterUnfix` violated | C2 |
| `mutant-unfix-before-next` | `scan_batch_next_page` releases the held page before it finds and fixes the next | `NoFixOfRemovedPage` violated: the released page was removed and its next link read | C3 |
| `mutant-iter-release-empty` | the filter iterator lets the page go after a chunk with no rows too | `NoFixOfRemovedPage` violated: a page with no visible row is removed, then fixed again | C3 |

## Witnesses

| cfg | Reached state |
|---|---|
| `witness-mixed-page` | the scan finished after chunks, a row-path page and an ordered-fix release |
| `witness-page-removed` | (iter) the scan finished after vacuum removed a page from the chain mid-scan |

## Dead expressions (pass cfgs)

| Line | Why never evaluated |
|---|---|
| PageBatchWalk.tla:106, PageBatchWalk.tla:107, PageBatchWalk.tla:108 | `Emit`'s body under `EmitRow` (chain cfgs) and `ConsumeRow` (iter cfgs): TLC counts an operator's body per call site, and the calling action is the other mode's only; it is evaluated under `RowNext` and the mode's own action |
| PageBatchWalk.tla:134 | `ClearChunk` under `ConsumeFallback` (mutant `fallback_after_consume` only) and under the other mode's `ChunkDone` caller |
| PageBatchWalk.tla:140, PageBatchWalk.tla:141, PageBatchWalk.tla:142, PageBatchWalk.tla:143 | `Hop`'s body under `NextHopLate` (mutant `unfix_before_next` only); evaluated under `NextHop` |
| PageBatchWalk.tla:152, PageBatchWalk.tla:153 | `NextUnfixFirst`: mutant `unfix_before_next` only |
| PageBatchWalk.tla:157, PageBatchWalk.tla:159 | `NextHopLate`: mutant `unfix_before_next` only |
| PageBatchWalk.tla:241 | `ChunkDone` under the other mode's end action (`EmitEnd` in chain cfgs, `ConsumeEnd` in iter cfgs) |
| PageBatchWalk.tla:244, PageBatchWalk.tla:245, PageBatchWalk.tla:246, PageBatchWalk.tla:247, PageBatchWalk.tla:252 | `ConsumeRow`, `ConsumeEnd`: chain mode only (iter cfgs) |
| PageBatchWalk.tla:256, PageBatchWalk.tla:257 | `ConsumeFallback`: mutant `fallback_after_consume` only |
| PageBatchWalk.tla:263, PageBatchWalk.tla:264 | `ConsumeDrop`: mutant `tail_drop` only (the environment assumption) |
| PageBatchWalk.tla:269, PageBatchWalk.tla:270, PageBatchWalk.tla:271, PageBatchWalk.tla:275, PageBatchWalk.tla:276, PageBatchWalk.tla:277, PageBatchWalk.tla:282 | `Copy`, `EmitRow`, `EmitEnd`: iter mode only (chain cfgs) |
| PageBatchWalk.tla:297 | `RowNext`'s keep-the-page branch `fixed' = TRUE /\ Mode = "chain"`: chain mode only (iter cfgs) |
| PageBatchWalk.tla:129, PageBatchWalk.tla:130, PageBatchWalk.tla:164, PageBatchWalk.tla:165 | `NextRefix`, `CollectRefix`: iter mode only (chain cfgs, `uncovered-ok`): in chain mode the row path fixes the page again before `S_END` and only `Copy` lets it go between chunks |

## Bounds and limits

- TLC: NP = 2, NS = 3 (chain and iter; every record kind on every slot initially, 15 625 initial heaps); scale
  NP = 3, NS = 2 (both modes). Inductive cfgs: NP = 1, NS = 2 and NP = 2, NS = 1, both modes.
- TLAPS: `IndInv` inductive and the safety claims, for any NP, NS and both modes (`PageBatchWalk_proofs.tla`).
- Not covered: the px workers' page dispatch (`docs/tla/parallel-scan/heap`) and their shared result handler;
  the vector kernels' arithmetic (the equivalence of a chunk's filter and steps to the row path's is a decision
  table, not modeled); filter selectivity; hash GROUP BY's key cache and eviction.

## Counterexamples

| cfg | Classification |
|---|---|
| inductive (first run) | model error: `ChunkDone`'s `IF ... ELSE "next" /\ ClearChunk` parsed the clear into the ELSE; fixed with parentheses |
| inductive (first run) | unreachable state `ph = "nexthop"` under the correct variant: IndInv strengthened (P6) |

No counterexample from a correct-variant cfg remains.

## Result

2026-11-06, `tools/tla/tla-check --workers 20 --stretch 3 docs/tla/CBRD-27361-page-batch-walk`: `RESULT: OK`. Run dir
`.git_ignored_dir/scratch/tla/CBRD-27361-page-batch-walk-20261106-040553-2437200`; TLC tla2tools 1.8.0, TLAPS tlapm
1.6.0-pre (toolchain `/nix/store/pkpvq91yw7b91465jplq1nvhkrv4z34c-tla-tools`).

| cfg | Result | States (distinct) | Depth |
|---|---|---|---|
| main (chain) | pass | 19 485 669 (4 239 504) | 27 |
| iter | pass | 29 660 900 (5 882 616) | 33 |
| scale-3pages | pass | 26 481 826 (5 226 379) | 31 |
| scale-3pages-iter | pass | 36 913 296 (6 900 342) | 39 |
| inductive-1page-chain / -iter | pass | 202 432 (64 000) each | 1 |
| inductive-2pages-chain / -iter | pass | 191 488 (55 360) each | 1 |
| mutant-exc-resume-at-slot | violation `Complete` | 2 597 759 | 9 |
| mutant-fallback-from-pos | violation `Complete` | 1 108 495 | 7 |
| mutant-fallback-after-consume | violation `NoDuplicate` | 1 012 619 | 7 |
| mutant-no-unfixed-check | violation `NoUseAfterUnfix` | 1 033 205 | 7 |
| mutant-tail-drop | violation `NoUseAfterUnfix` | 606 132 | 6 |
| mutant-unfix-before-next | violation `NoFixOfRemovedPage` | 2 385 783 | 9 |
| mutant-iter-release-empty | violation `NoFixOfRemovedPage` | 1 805 872 | 8 |
| witness-mixed-page | violation `NotDoneMixed` (reached) | 8 260 271 | 14 |
| witness-page-removed | violation `NotDoneAfterRemoval` (reached) | 3 634 560 | 10 |

TLAPS: `PageBatchWalk_proofs.tla` 3679/3679 obligations proved, none omitted (2564 s at load average 40-60; the
same file at `--stretch 1` and load average 55-93 left 57 obligations to timeouts, none refuted). The proof file is
generated (`StepInv` per action and per `IndInv` part, with hand-split steps for `RunDrop`/`RunRefix` `IChunk'` and
`Copy` `IFix'`).

```
a6e9e0cf213f509c20973f43710947bc425750b1697639b912af394d6583b87a  PageBatchWalk.tla
9828905917d9c48f329adc0f99b72d3366900f0aea51e2637ca9014db9f5bf86  PageBatchWalk_proofs.tla
```

Engine: develop `be0a9ab1f`, read only. Trace validation (step 8: page latch protocol) not run: pending the user's
decision on an instrumented build.
