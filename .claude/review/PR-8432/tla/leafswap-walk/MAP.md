# PR 8432 (CBRD-27973) r2 — leaf swap kept, removal lookup walks the pages before the routed one

Code: PR head `945478c64cd46e0523e95f204dfc62c865bd2f69` (merge-base develop `1b2645925`), `src/storage/btree.c`,
line numbers of the head. Review copy of `docs/tla/CBRD-24094-ovf-dir` (via the r1 dir `leafswap-route`). Constants:
`Swap = "first"` (the head keeps the merge-base swap; `"routed"` is r1's head `cca5378df`), `DFix = "walk"` (the
head; `"none"` the merge-base, `"first_page_fallback"` CBRD-27973's F2).

| Module | What it is |
|---|---|
| `OvfDirChain.tla` | one key: leaf record, OID-ordered overflow chain, separator directory, insert / removal / leaf swap / COMPACT, lookup `btree_ovf_dir_find_oid` with the head's walk (`FindRemove`), a crash between the swap halves and a retry at any later point (`CrashRecover`, `Retry`) |
| `OvfOrder.tla` | abstract order model; `OvfDirChain` refines it (`OrderSpec` in `OvfDirChain.cfg`, no crash) |
| `OvfScanResume.tla` | a range scan whose OID buffer fills inside the key and resumes by OID while the writers run |
| `OvfDirChainTrace.tla` | trace validation of the crash-retry run of the instrumented head build |

## Claim and sources

| # | Claim | Source |
|---|---|---|
| C1 | After a crash between the two halves of the leaf swap, a retried removal (vacuum re-running the block, recovery undoing the insert), whenever it comes, finds the deleted object D and removes it; no entry is left behind | CBRD-27973 Expected Result; PR 8432 body (Implementation: directory 탐색 실패 시 첫 페이지부터 라우팅된 페이지 직전까지 순회; 그 페이지가 분할돼도 D는 라우팅 페이지보다 앞에 남음) |
| C2 | The chain stays OID-ordered except the crash-left objects a retry has not removed yet (OrderedButPending) | PR 8432 body TLA+ table |
| C3 | Every chain object other than a crash-left one stays routable through the directory | CBRD-24094 base model C1/C2; PR body (Routable) |
| C4 | No object is lost or duplicated | base model C4 |
| C5 | A range scan interrupted inside the key returns every object visible to its snapshot exactly once (no COMPACT) | `btree_range_scan_select_visible_oids` interrupt comment; PR 8432 comment in `btree_replace_first_oid_with_ovfl_oid` (the object moved to the leaf stays the first page's last); r1 finding R1 |
| C6 | The scan finishes | liveness |

## Refinement map (model -> code, head)

Unchanged rows are the base model's (`docs/tla/CBRD-24094-ovf-dir/MAP.md`). Every writer holds the key's leaf WRITE
latch for its whole operation; the scan holds the leaf READ latch for one iteration and none between iterations.

| Model | Code (head) | One step because |
|---|---|---|
| `LeafDel` (swap) | `btree_replace_first_oid_with_ovfl_oid` (btree.c:11474): the first page's last object to the leaf, D in its place at D's in-page OID position, `log_sysop_commit`, then the removal from that page (unchanged from the merge-base; comment only) | two durable halves under one leaf write latch: one step without the crash fault, `LeafDel` + `SwapDone` with it |
| `CrashRecover` | the server stops after the first half's sysop commit (`CUBRID_TLA_CRASH_AFTER_SWAP` in the trace run) | the crash ends the latch hold |
| `Retry` | vacuum re-runs the block / recovery undoes the insert -> `btree_key_delete_remove_object` (btree.c:36684): the leaf record first (`LeafDel` when D sits in the leaf again), else `btree_ovf_dir_find_oid` | under the leaf write latch |
| `FindRemove` | `btree_ovf_dir_find_oid` (btree.c:13758): directory route + step-back (`Find`); on a miss (btree.c:14001), for `DELETE_VACUUM_OBJECT`, `DELETE_UNDO_INSERT(_UNQ_MULTIUPD)`, `DELETE_OBJECT_PHYSICAL(_POSTPONED)`, the walk from `first_ovf_vpid` while `!VPID_EQ (walk_vpid, routed_vpid)` (btree.c:14028), each page searched by `btree_find_oid_from_ovfl` | leaf write latch held by the caller; data pages fixed in chain order |
| `Remove` (chain object) | the same lookup for a regular removal; a miss there would be `unknown_key` | |

Functions of the diff: `btree_replace_first_oid_with_ovfl_oid` (comment only), `btree_ovf_dir_find_oid` (`FindRemove`;
the walk's `prev_page` bookkeeping is the predecessor `RemoveObjAt` unlinks a freed page from; the broken-chain
`assert_release` and `walk_error` paths: fault table).

## Fault model

| Fault | Modeled as |
|---|---|
| error return | not modeled: a `pgbuf_fix` / `btree_find_oid_from_ovfl` / `btree_get_next_overflow_vpid` error in the walk unfixes and returns the error (`walk_error`), the removal fails as on any lookup error |
| interrupt / query cancel | a scan's interrupt or LIMIT ends it before any resume |
| lock timeout, deadlock victim | not applicable: latches only |
| conditional latch failure | not applicable: every fix in the walk is `PGBUF_UNCONDITIONAL_LATCH` |
| OOM | not applicable |
| crash / kill -9 | between the swap halves (`CrashRecover`); the retry at any later point, with inserts, removals and other swaps in between (`Retry` needs only `Idle`) |
| spurious wakeup | not applicable |
| concurrent DML | `Insert`, `Remove` between scan iterations and between the crash and the retry |
| vacuum | `Remove` of objects the snapshot does not see, including the leaf swap; the retry |
| COMPACT while a crash-left D waits | `witness-preexisting-compact` (merge-base): a pull into the page that ends with D breaks its in-page order and a live object becomes unroutable. The merge-base leaves D for good, so the exposure is the merge-base's; the head shortens it to the retry and adds no way in. The head crash cfgs run with `Compact = FALSE` |
| broken chain (walk reaches NULL before the routed page) | not modeled: `assert_release (false)`, returns not found |
| checkpoint, page flush, HA | not applicable |

## Mutants

| cfg | Change | Expected | Kills |
|---|---|---|---|
| `OvfDirChain.mutant-merge-base` | merge-base 1b2645925: a removal's directory miss is final | `RetryFindable` | C1 |
| `OvfDirChain.mutant-first-page-only` | the miss searches the first page only (CBRD-27973 F2): an insert that splits the first page before the retry moves D to the new page | `RetryFindable` | C1 |
| `OvfDirChain.mutant-grow-right-any` | grow right without checking that the OID exceeds the last | `Sorted` | C2 |
| `OvfDirChain.mutant-no-set-sep` | a partial COMPACT move leaves the separator | `Sorted` | C2 |
| `OvfDirChain.mutant-no-catch-all` | head entry 0 compared as a real separator | `Routable` | C3 |
| `OvfDirChain.mutant-no-step-back` | a lookup miss after routing is final | `Routable` | C3 |
| `OvfDirChain.mutant-adv-strict` | directory pages advance only while the next entry 0 is below the OID | `Routable` | C3 |
| `OvfDirChain.mutant-swap-keep` | the swap leaves the moved object in the page too | `Content` | C4 |
| `OvfScanResume.mutant-routed-swap` | r1 head cca5378df: the swap moves the routed page's last object into the leaf | `ExactlyOnce` | C5 |
| `OvfScanResume.mutant-anchor-processed` | anchor on the last processed object | `ExactlyOnce` | C5 |
| `OvfScanResume.mutant-page-resume` | resume from the page after the last page with a visible object | `NoResumeError` | C5 |
| `OvfScanResume.mutant-resume-blocked` | the resume never runs while the leaf holds an object | deadlock | C6 |

Not modeled as a mutant: the purpose filter of the walk (`DELETE_VACUUM_INSID` and the insert purposes skip it). It
only bounds cost: a miss for those purposes is a regular outcome (an object whose removal later in the same block was
vacuumed first), and walking would not change what is found. Measured by the author and jihyekim-0 (OVFP reads per
removal 3-4 pages, develop 4; before the filter 448).

## Witnesses

| cfg | Reached state |
|---|---|
| `OvfDirChain.witness-walk` | a retry found D by the walk |
| `OvfDirChain.witness-walk-split` | the walk found D past a split first page (PageCap 3) |
| `OvfDirChain.witness-preexisting-compact` | the merge-base exposure above |
| `OvfDirChain.witness-swap`, `-stepback`, `-pullup`, `-dirsplit`, `-dirtail`, `-partial`, `-merge` | base model structural events |

## Dead expressions (pass cfgs)

TLC reports coverage per call site, so an operator body line is listed when one of its call sites never runs under
the cfg's constants.

| Line | Cfgs | Why never evaluated |
|---|---|---|
| `OvfDirChain.tla:198` | all OvfDirChain pass cfgs | `RemoveObjAt`'s body at a call site the cfg's `CrashSwap` excludes (the non-crash swap with CrashSwap TRUE; `SwapDone`/`Retry` with CrashSwap FALSE); the same lines run at the lookup call site |
| `OvfDirChain.tla:199` | all OvfDirChain pass cfgs | the same |
| `OvfDirChain.tla:200` | all OvfDirChain pass cfgs | the same |
| `OvfDirChain.tla:203` | all OvfDirChain pass cfgs | the same |
| `OvfDirChain.tla:204` | all OvfDirChain pass cfgs | the same |
| `OvfDirChain.tla:205` | all OvfDirChain pass cfgs | the same |
| `OvfDirChain.tla:206` | all OvfDirChain pass cfgs | the same |
| `OvfDirChain.tla:207` | all OvfDirChain pass cfgs | the same |
| `OvfDirChain.tla:208` | all OvfDirChain pass cfgs | the same |
| `OvfDirChain.tla:209` | all OvfDirChain pass cfgs | the same |
| `OvfDirChain.tla:210` | all OvfDirChain pass cfgs | the same |
| `OvfDirChain.tla:266` | main, scale-page-cap-3 | `LeafDel` with no chain at the `Retry` call site: `Retry` needs `CrashSwap` |
| `OvfDirChain.tla:271` | main, scale-page-cap-3 | the same call site (the swap) |
| `OvfDirChain.tla:275` | main, scale-page-cap-3 | the crash branch of the swap: `CrashSwap = FALSE` |
| `OvfDirChain.tla:276` | main, scale-page-cap-3 | the same |
| `OvfDirChain.tla:277` | main, scale-page-cap-3 | the same |
| `OvfDirChain.tla:278` | main, scale-page-cap-3 | the same |
| `OvfDirChain.tla:280` | all pass cfgs | the `swap_keep` mutant branch (`mutant-swap-keep` reaches it) |
| `OvfDirChain.tla:281` | all pass cfgs | the same |
| `OvfDirChain.tla:283` | all pass cfgs | the non-crash swap at the call site the cfg excludes (`Retry` with CrashSwap FALSE; `Remove` with CrashSwap TRUE) |
| `OvfDirChain.tla:293` | all pass cfgs | violation ghost `unknown_key`: a regular removal never misses (`Routable`, C3) |
| `OvfDirChain.tla:294` | all pass cfgs | the same |
| `OvfDirChain.tla:305` | main, scale-page-cap-3 | `SwapDone`: `CrashSwap = TRUE` only |
| `OvfDirChain.tla:306` | main, scale-page-cap-3 | the same |
| `OvfDirChain.tla:312` | main, scale-page-cap-3 | `CrashRecover`: `CrashSwap = TRUE` only |
| `OvfDirChain.tla:313` | main, scale-page-cap-3 | the same |
| `OvfDirChain.tla:314` | main, scale-page-cap-3 | the same |
| `OvfDirChain.tla:315` | main, scale-page-cap-3 | the same |
| `OvfDirChain.tla:321` | main, scale-page-cap-3 | `Retry`: `CrashSwap = TRUE` only |
| `OvfDirChain.tla:323` | main, scale-page-cap-3 | the same |
| `OvfDirChain.tla:326` | all pass cfgs | violation ghost `crash_swap_lost` (C1): with the walk a retry never misses; it fires in `mutant-merge-base` and `mutant-first-page-only` |
| `OvfDirChain.tla:327` | all pass cfgs | the same |
| `OvfDirChain.tla:329` | main, scale-page-cap-3 | `Retry`'s removal: `CrashSwap = TRUE` only |
| `OvfDirChain.tla:341` | crash cfgs | `PullAt`: `Compact = FALSE` in the crash cfgs (fault table) |
| `OvfDirChain.tla:342` | crash cfgs | the same |
| `OvfDirChain.tla:343` | crash cfgs | the same |
| `OvfDirChain.tla:344` | crash cfgs | the same |
| `OvfDirChain.tla:345` | crash cfgs | the same |
| `OvfDirChain.tla:346` | crash cfgs | the same |
| `OvfDirChain.tla:347` | crash cfgs | the same |
| `OvfDirChain.tla:348` | crash cfgs | the same |
| `OvfDirChain.tla:349` | crash cfgs | the same |
| `OvfDirChain.tla:350` | crash cfgs | the same |
| `OvfDirChain.tla:351` | crash cfgs | the same |
| `OvfDirChain.tla:352` | crash cfgs | the same |
| `OvfScanResume.tla:115` | OvfScanResume, its scale | `resume_freed_page`: only the `page_resume` mutant resumes from a saved page |
| `OvfScanResume.tla:116` | OvfScanResume, its scale | the same |
| `OvfScanResume.tla:117` | OvfScanResume, its scale | the same |
| `OvfScanResume.tla:129` | OvfScanResume, its scale | `RemoveSwapFirst` (base model's CBRD-27972 candidate F1), enabled only with `Fix = "swap_first"` (`mutant-page-resume`) |
| `OvfScanResume.tla:130` | OvfScanResume, its scale | the same |
| `OvfScanResume.tla:132` | OvfScanResume, its scale | the same |

## Bounds and limits

- `OvfDirChain` main: 3 OIDs x 2 versions, page capacity 2, directory capacity 2, leaf 1, no crash, COMPACT on.
  Crash cfgs: 6 OIDs x 1 version, page capacity 3 (capacity 2 makes a full page `[x, D]` split at D itself, which a
  real page of hundreds of OIDs never does: D is the largest object of its page), COMPACT off; scale 7 OIDs.
  `OvfScanResume`: 4 OIDs x 1 version; scale 3 x 2.
- Inductive invariant: `OvfOrder.inductive-indinv` by TLC (the abstract order model; Apalache cannot type its
  sequence-of-records state, cubrid-tla P42); `OvfDirChain` reaches it through `OrderSpec` in the main cfg only.
  TLAPS 요청 없음.
- Not modeled: unique indexes (the walk runs for non-unique only: `assert (!BTREE_IS_UNIQUE ...)`).

## Trace validation

Instrumented scratch worktree `~/dev/cubrid-worktree/pr8432-instr` = 945478c64 + CBRD-27973 attachment
`tla-evidence-21c6e635d.patch` (Swap, CrashAfterSwap, KeyDump, resume delay, vacuum gate) + TLATRACE at the
directory miss (`FindMiss`, with the purpose and the routed page) and at the walk's result (`FindWalk`), optdebug,
prefix `~/optdebug/CUBRID-pr8432-tla`, libcubrid.so sha256 `93ef37f70f8222e5...`, CS server port 1700, `parallelism=1`.
`traces/crash2tla.py` keeps the file order (the restart resets `seq`).

| Run | What | cfg | Result |
|---|---|---|---|
| crash-retry | JIRA `h2_repro.sh` + key dumps: key 8 of `t5`, 1,916 objects (leaf 1 + three pages of 678 / 678 / 559, one directory page); the swap on the first page moved rank 678 into the leaf and put D (rank 1,916) there; crash; after the restart vacuum's retry missed in the directory (routed to page 3, purpose 10 = `DELETE_VACUUM_OBJECT`) and the walk found D on page 1; the key then equals its dump after the retry | `OvfDirChainTrace.witness-trace-crash-retry` | accepted (depth 5) |
| corrupted: the walk reports page 2 | | `OvfDirChainTrace.reject-walk-page` | refused |
| corrupted: the crash event dropped | | `OvfDirChainTrace.reject-no-crash` | refused |

## Counterexamples

| cfg | Classification |
|---|---|
| `crash-swap` (first version: `Retry` looked only in the chain) | model error: after the crash another removal's swap can move the crash-left D into the leaf; `btree_key_delete_remove_object` searches the leaf record first. `Retry` now takes the leaf branch |
| `crash-swap` at page capacity 2 (`DirSorted`) | model artifact: a full two-object page `[x, D]` splits at D; with capacity 3 the upper half never starts with D (bounds) |
| `crash-swap` with COMPACT on (`Routable`) | the merge-base exposure (fault table, `witness-preexisting-compact`); not introduced by the PR |

## Findings

None for the head. r1's R1 (scan loss with the routed swap) is gone: `OvfScanResume.mutant-routed-swap` keeps it as
a mutant.

## Result

(filled after the record run)
