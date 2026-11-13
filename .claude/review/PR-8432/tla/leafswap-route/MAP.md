# PR 8432 (CBRD-27973) — leaf swap routed to the directory page of the deleted object

Code: PR head `cca5378df` (merge-base develop `953e83256`), `src/storage/btree.c`, line numbers of the
head. The model is a review copy of `docs/tla/CBRD-24094-ovf-dir` (the model behind CBRD-27972 and
CBRD-27973, develop `21c6e635d`; no commit between `21c6e635d` and `953e83256` touches `btree.c`,
`btree.h` or `vacuum.c`) with one new constant: `Swap = "routed"` is the PR head,
`Swap = "first"` the merge-base.

| Module | What it is |
|---|---|
| `OvfDirChain.tla` | one key: leaf record, OID-ordered overflow chain, separator directory, insert / removal / leaf swap / COMPACT, lookup `btree_ovf_dir_find_oid` |
| `OvfOrder.tla` | abstract order model; `OvfDirChain` refines it (`OrderSpec`, checked by TLC in `OvfDirChain.cfg`) |
| `OvfScanResume.tla` | a range scan whose OID buffer fills inside the key and resumes by OID while the writers run |
| `OvfScanResumeTrace.tla` | trace validation of a run of the instrumented PR head build |

## Claim and sources

| # | Claim | Source |
|---|---|---|
| C1 | After a crash between the two halves of the leaf swap, the restarted vacuum finds the deleted object D and removes it; no entry is left behind. | CBRD-27973 Expected Result; PR 8432 body ("재시작 뒤 directory 탐색이 D를 찾습니다") |
| C2 | The chain keeps its OID order at every point of the swap, in particular between the halves. | PR 8432 body ("체인은 어느 시점에도 OID 순서를 유지") |
| C3 | Every chain object stays routable; the directory stays consistent when the routed page is emptied and freed by the second half. | PR 8432 body (Implementation, routed page with one object); CBRD-24094 C1/C2 of the base model |
| C4 | The swap loses or duplicates no object. | base model C4 |
| C5 | A range scan interrupted inside the key returns every object visible to its snapshot exactly once (no COMPACT). | `btree_range_scan_select_visible_oids` interrupt comment points 2-4 ("Only one object from first overflow page is swapped ... It can be considered already processed"); CBRD-27401 (PR 7899); PR 8431 (CBRD-27972) comment in `btree_replace_first_oid_with_ovfl_oid` and `xbtree_compact_overflow` |
| C6 | The scan finishes. | liveness of any scan |

## Refinement map (model -> code)

Unchanged rows are the base model's (`docs/tla/CBRD-24094-ovf-dir/MAP.md`, refinement map); the rows
below are the ones the PR changes. Every writer holds the key's leaf WRITE latch for its whole operation,
the scan holds the leaf READ latch for one iteration and none between iterations.

| Model | Code (head) | One step because |
|---|---|---|
| `SwapPg` | `btree_replace_first_oid_with_ovfl_oid` (btree.c:11293): non-unique and `OID_GT (D, last object of the first page)`, then `btree_ovf_dir_route_oid` (btree.c:13593): no directory -> first page; `btree_ovf_dir_locate` -> target; target = first page -> first page | read of the first page and the directory under the leaf write latch |
| `Remove` (leaf, single object) | the swap page's last object goes to the leaf (`btree_leaf_change_first_object`), D replaces it in OID order (`btree_overflow_record_replace_object` -> `btree_record_replace_object` btree.c:38809, remove + `btree_insert_object_ordered_by_oid`; single-object page: in place), `log_sysop_commit` (btree.c:11389), then `btree_overflow_remove_object (..., &ovfl_page, prev_page, ...)` (btree.c:11398) | two durable halves under one leaf write latch: one step without the crash fault, `Remove` + `SwapDone` with it |
| `SwapDone` | the second half on the swap page at the offset the replace returned; a single-object routed page is freed, unlinked from `prev_page` (fixed by `btree_ovf_dir_route_oid` via `btree_ovf_dir_prev_data_vpid`) and its directory entry removed (`btree_ovf_dir_remove_entry`) | under the same leaf write latch |
| `CrashRecover` | crash after the swap commit; vacuum re-runs the removal by `btree_ovf_dir_find_oid` (btree.c:13739) | the crash ends the latch hold |
| `SStart`, `ChainIter` stop | `btree_range_scan_select_visible_oids` (btree.c:31000-31031 key-start soft check reserves leaf + first overflow page; btree.c:31196 hard check before each next page; anchor `O_last_oid` btree.c:31220) | leaf read latch over the iteration |
| `SResume` | `btree_ovf_scan_locate_resume` (btree.c:15703): chain only, the leaf record is not re-read for a partially processed key (btree.c:31073-31081) | leaf read latch |
| `Env` | any writer between iterations, including vacuum's leaf swap of a leaf object the snapshot does not see | — |

Functions of the diff: `btree_replace_first_oid_with_ovfl_oid` (`SwapPg`, `Remove`, `SwapDone`),
`btree_ovf_dir_route_oid` (`SwapPg`; its error paths: fault table), `btree_ovf_dir_prev_data_vpid`
(no state of its own: the predecessor page the unlink in `RemoveObjAt` uses), `btree_ovf_dir_find_oid`
(`Find`; refactor only, same predecessor computation).

## Fault model

| Fault | Modeled as |
|---|---|
| error return | not modeled: `btree_ovf_dir_route_oid` errors return before `log_sysop_start` (btree.c:11330), leaving the pre-state; the replace and the removal are under the base model's sysop rule |
| interrupt / query cancel | a scan's interrupt or LIMIT ends it before any resume |
| lock timeout, deadlock victim | not applicable: latches only |
| conditional latch failure | not applicable: every fix in the diff is `PGBUF_UNCONDITIONAL_LATCH` |
| OOM | not applicable: stack buffers only |
| crash / kill -9 | between the swap halves (`CrashSwap`); every other change is one system operation |
| spurious wakeup | not applicable |
| concurrent DML | `Insert`, `Remove` between scan iterations |
| vacuum | `Remove` of objects the snapshot does not see, including the leaf swap |
| checkpoint, page flush, page replacement | not applicable: pages fixed while read or written |
| HA log apply | not applicable: same code on the slave |
| capacity | the scan stops only after an accepted chain object (key start reserves leaf + one full page) |

## Mutants

| cfg | Change | Expected | Kills |
|---|---|---|---|
| `OvfDirChain.mutant-first-swap` | the merge-base swap page (always the first page) with the crash | `NoBad` violated (`crash_swap_lost`) | C1 |
| `OvfDirChain.mutant-first-swap-order` | the same, read on the chain order | `Sorted` violated | C2 |
| `OvfDirChain.mutant-grow-right-any` | grow right without checking that the OID exceeds the last | `Sorted` violated | C2 |
| `OvfDirChain.mutant-no-set-sep` | a partial COMPACT move leaves the separator | `Sorted` violated | C2 |
| `OvfDirChain.mutant-no-catch-all` | head entry 0 compared as a real separator | `Routable` violated | C3 |
| `OvfDirChain.mutant-no-step-back` | a lookup miss is final | `Routable` violated | C3 |
| `OvfDirChain.mutant-adv-strict` | directory pages advance only while the next entry 0 is below the OID | `Routable` violated | C3 |
| `OvfDirChain.mutant-swap-keep` | the swap leaves the moved object in the page too | `Content` violated | C4 |
| `OvfScanResume.mutant-anchor-processed` | anchor on the last processed object instead of the last visible one | `ExactlyOnce` violated | C5 |
| `OvfScanResume.mutant-page-resume` | resume from the page after the last page with a visible object | `NoResumeError` violated | C5 |
| `OvfScanResume.mutant-resume-blocked` | the resume never runs while the leaf holds an object | deadlock | C6 |

Surviving mutant (the guard is not needed for the properties; reported as a reading, not a defect):

| Change | Result | Reading |
|---|---|---|
| `route_always`: route every D through `btree_ovf_dir_route_oid`, dropping `OID_GT (D, first page's last)` (btree.c:11293) | crash cfg invariants hold, 1,311,663 / 284,643 states, the same space as `crash-swap` (probe cfg kept in `.git_ignored_dir/scratch/pr8432/tla/`) | `Locate` of a D not above the first page's last object returns the first page, so the guard saves the directory read only; the PR body says the same ("D가 첫 페이지의 마지막 OID 이하이면 ... 종전 경로") |

The routing itself is killed by `mutant-first-swap` (C1, C2).

## Witnesses

| cfg | Reached state |
|---|---|
| `OvfDirChain.witness-routed` | the swap moved an object from a page other than the first |
| `OvfDirChain.witness-routedfree` | the routed page held one object and was freed by the second half |
| `OvfDirChain.witness-swap`, `-stepback`, `-pullup`, `-dirsplit`, `-dirtail`, `-partial`, `-merge` | base model structural events |
| `OvfScanResume.witness-routed-while-suspended` | a routed swap ran while a scan was stopped in the key |
| `OvfScanResumeTrace.witness-trace-h3-head-run1` | the recorded PR-head run `traces/h3-head-run1.log` is a behavior of `OvfScanResume` with `Swap = "routed"` |
| `OvfScanResumeTrace.reject-first-page-swap` | the same run with the swap moving the first page's last object (the merge-base swap page) is refused at the swap |

## Dead expressions (pass cfgs)

TLC reports coverage per call site, so an operator body line is listed when one of its call sites never
runs under the cfg's constants.

| Lines | Cfgs | Why never evaluated |
|---|---|---|
| `OvfDirChain.tla:184`, `OvfDirChain.tla:185`, `OvfDirChain.tla:186`, `OvfDirChain.tla:189`, `OvfDirChain.tla:190`, `OvfDirChain.tla:191`, `OvfDirChain.tla:192`, `OvfDirChain.tla:193`, `OvfDirChain.tla:194`, `OvfDirChain.tla:195`, `OvfDirChain.tla:196` | all OvfDirChain pass cfgs | `RemoveObjAt`'s body at the call site the cfg's `CrashSwap` excludes: `SwapDone`/`CrashRecover` (CrashSwap FALSE) or the plain swap at line 271 (CrashSwap TRUE). The same lines run at the lookup call site (line 277) in every cfg |
| `OvfDirChain.tla:264`, `OvfDirChain.tla:265`, `OvfDirChain.tla:266`, `OvfDirChain.tla:267` | main, scale-page-cap-3 | the crash branch of the swap: `CrashSwap = FALSE` (runs in the crash cfgs) |
| `OvfDirChain.tla:269`, `OvfDirChain.tla:270` | all pass cfgs | the `swap_keep` mutant branch (`mutant-swap-keep` reaches it) |
| `OvfDirChain.tla:272` | crash cfgs, fix-first-page-fallback | the non-crash swap: these cfgs run with `CrashSwap = TRUE` |
| `OvfDirChain.tla:275`, `OvfDirChain.tla:276` | all pass cfgs | violation ghost `unknown_key`: a lookup miss would break `NoBad`; `Routable` (C3) holds |
| `OvfDirChain.tla:287`, `OvfDirChain.tla:288`, `OvfDirChain.tla:293`, `OvfDirChain.tla:302` | main, scale-page-cap-3 | `SwapDone`, `CrashRecover`: enabled only with `CrashSwap = TRUE` |
| `OvfDirChain.tla:297`, `OvfDirChain.tla:298`, `OvfDirChain.tla:299`, `OvfDirChain.tla:300` | crash cfgs, fix-first-page-fallback | violation ghost `crash_swap_lost` (C1); it fires in `mutant-first-swap` |
| `OvfScanResume.tla:115`, `OvfScanResume.tla:116`, `OvfScanResume.tla:117` | first-swap-no-compact, its scale | `resume_freed_page`: only the `page_resume` mutant resumes from a saved page (`mutant-page-resume` reaches it) |
| `OvfScanResume.tla:129`, `OvfScanResume.tla:130`, `OvfScanResume.tla:132` | first-swap-no-compact, its scale | `RemoveSwapFirst` (base model's CBRD-27972 candidate F1), enabled only with `Fix = "swap_first"` (used by `mutant-page-resume`) |

## Counterexamples and findings

| Id | Cfg | Classification | Runtime |
|---|---|---|---|
| R1 | `OvfScanResume.cfg` (head, `Swap = "routed"`, no COMPACT; `ExactlyOnce`) | **hole, confirmed** — introduced by this PR | reproduced 3/3 on the PR head; merge-base build 3/3 clean (below) |
| — | first `OvfDirChain.crash-swap.cfg` carried `PROPERTY OrderSpec` | model error: the state between the swap halves (D inside the swap page, M in the leaf) has no `OvfOrder` counterpart; the base model checks `OrderSpec` only without the crash fault | — |

**R1 — a range scan stopped inside a key loses a visible row when vacuum's leaf swap is routed past the
first overflow page.** TLC trace (`OvfScanResume.cfg`, depth 8-9): leaf `{4}` (deleted before the snapshot),
page 1 `[1,2]`, page 2 `[3]`, snapshot sees `{1,3}`; the scan returns 1 and stops before page 2 (anchor 1)
[btree.c:31196, 31220]; vacuum removes 4, `4 > 2` so `btree_ovf_dir_route_oid` routes to page 2 and the swap
moves 3 into the leaf, freeing page 2 [btree.c:11293-11326, 11398]; the resume reads the chain after anchor 1
and never the leaf [btree.c:15703, 31141]: 3 is not returned. With `Swap = "first"` the swap moves page 1's
last object, which a stopped scan has always processed (a key stops only after its first page: key-start soft
check btree.c:31000-31031), and `OvfScanResume.first-swap-no-compact` (with `ScanFinishes`) and its
3x2 scale pass.

Runtime (scratch instrumentation = CBRD-27973 attachment `tla-evidence-21c6e635d.patch`, Swap trace printing
the routed page; `parallelism=1`, `max_parallel_workers=1`, OID buffer default): key 0 7,400 rows, key 1 3,000
rows (pages of 678), key 1's leaf reduced to one deleted row D with an OID above every chain object, vacuum held
by a gate, `SELECT id FROM t WHERE k <= 1 USING INDEX idx(+)` stops at n=7,737 before key 1's page 2 and pauses
8 s, the gate opens in the pause.
- PR head `cca5378df` optdebug + instrumentation, libcubrid `4df88321aa9b…`: 3/3 `expected=9974 returned=9973`,
  lost ids 2845, 2096, 2140; each `Swap ... page=0|4756` (the last data page) moved the lost row into the leaf.
- develop `21c6e635d` optdebug + instrumentation (= merge-base for this path), libcubrid `025329474e72…`: 3/3
  `returned=9974`; the swap took page `0|4751` (the first) and moved the scan's anchor itself.

C1 at runtime: CBRD-27973 `h2_repro.sh` on the PR head build: `Swap ... page=0|4870`, `CrashAfterSwap`; after
the restart and vacuum D `0|4818|1` is gone, the chain's three pages are in OID order, index = heap = 1,915,
`checkdb -C --check-btree-entries -i dba.t5` rc 0.

## Bounds and limits

- `OvfDirChain`: 3 OIDs x 2 versions, page capacity 2, directory capacity 2, leaf capacity 1; scale: page
  capacity 3 (main and crash). `OvfScanResume`: 4 OIDs x 1 version; scale 3 x 2 (merge-base swap).
- Inductive invariant: `OvfOrder.inductive-indinv` by TLC (the abstract order model's IndInv; Apalache cannot
  type its sequence-of-records state, cubrid-tla P42); `OvfDirChain` reaches it through `OrderSpec` in the main cfg
  only (not under the crash fault). TLAPS 요청 없음.
- C5 and C6 are TLC only. The model trusts the in-page search and that every writer holds the leaf write latch.
- Not modeled: unique indexes (the PR leaves them unchanged), `btree_ovf_dir_route_oid` error paths (they return
  before the system operation starts).

## Result

- 2026-11-09, `tools/tla/tla-check --workers 12 .claude/review/PR-8432/tla/leafswap-route`: **`RESULT: FAILED (1)`**,
  exactly the code cfg of the confirmed hole R1 (`OvfScanResume`, `ExactlyOnce`, depth 8). 33 cfgs PASS.
  Run dir `.git_ignored_dir/scratch/tla/leafswap-route-20261109-154914-1359002`.
- Pass cfgs (generated / distinct, depth): `OvfDirChain` (with `OrderSpec`) 1,027,027 / 142,325, 31;
  `OvfDirChain.crash-swap` 1,311,663 / 284,643, 35; `crash-swap.scale-page-cap-3` 264,979 / 57,895, 29;
  `scale-page-cap-3` 207,091 / 28,951; `fix-first-page-fallback` 1,359,763 / 295,683;
  `OvfScanResume.first-swap-no-compact` (with `ScanFinishes`) 11,102 / 4,274, 23; its scale-versions
  25,337,733 / 6,482,575, 47; `OvfOrder`, `OvfOrder.scale-4-pages`, `OvfOrder.inductive-indinv`.
- 11 mutants and 10 witnesses PASS; trace witness `h3-head-run1` accepted (8 states, depth 5),
  `reject-first-page-swap` refused (2 states).
- TLAPS 요청 없음.
- Spec sha256: `OvfDirChain.tla` c7e7b5c9…, `OvfOrder.tla` ac08f81b…, `OvfScanResume.tla` a6fabb5d…, `OvfScanResumeTrace.tla` a3c25cf1…, `OvfScanResumeTraceData.tla` d2443e0e….
- Engine: PR head `cca5378df` optdebug + scratch instrumentation (worktree `pr8432-instr`, uncommitted),
  libcubrid `4df88321aa9b…`; merge-base side develop `21c6e635d` optdebug + the same instrumentation,
  libcubrid `025329474e72…`.
