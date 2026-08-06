# IMP-005 report — merge the nl-join `scan_ptr` chain exactly once in the parallel trace merge

## 1. Identity, pins and diff

| Item | Value |
|---|---|
| IMP | `IMP-005` (**Enabler-Predecessor** lane — unblocks IMP-009 and IMP-012 measurement) |
| Campaign | `tpch-sspq-impl-r1-20260803` |
| Pinned IMPL-SSOT | commit `eccdd1ae58cd733ed3121585146d68b9ae54a73f`, blob `15b42ddca521444fa54b34b0fa8477ed2df643f6` |
| Phase 2 spec | `impl/PHASE2-SPEC.md` @ `13b2b13d6711af522ab3e0ac29aed1c8866b095c` (queue approved from IMP-005; §6-d-1 rule (c) max 15.3158) |
| CUBRID base SHA | `607f1ee9fb2394de129e083602c84a6525fc685c` (frozen base) |
| Branch | `impl/tpch-sspq-impl-r1-20260803/IMP-005-nl-trace-merge-dedup` (worktree `/home/cubrid/dev/tpch-sspq-impl-r1/worktrees/IMP-005`) |
| Plan commit | `a459e75cb` (committed before the first source edit, §5-c) |
| Patch commit | `e84baed11` |
| Diffstat | `src/query/parallel/px_scan/px_scan_trace_handler.cpp | 20 +++++++++-------` → **12 insertions, 8 deletions, 1 file** |
| Upstream scope gate (§5-e) | **Not applicable** — IMP-005 is absent from `triage-adjustments.json` `upstream_scope_gates` (the gated set is IMP-003/022/019/011/014) |
| B / P installs | `install/base` cub_server `16abc26afa1db169…` (matches the §6-a pin) / `install/IMP-005` cub_server `e970cffdf9026ad1…`; `conf/cubrid.conf` sha256 `ad19f5ac1e7e983e…` on **both** (§6-a-2) |

### The change

`trace_storage_for_sibling_xasl::merge_xasl_tree` walked the `scan_ptr` chain and
called `xasl_merge_stats` once per chain level, plus once per that level's
`dptr_list` sibling. `xasl_merge_stats` already recurses over the whole subtree
of its argument (`xasl_iteration.hpp:180` `dptr_list`, `:189` `scan_ptr`), so a
node at chain depth k was merged **k times per sibling tree**. The patch replaces
the loop with a single `xasl_merge_stats (xasl_tree->scan_ptr, m_main_xasl_tree)`
call on the chain head. `src/xasl/xasl_iteration.cpp` is untouched, as the plan
required (narrowing `xasl_merge_stats` instead would have under-counted
`aptr_list`/`bptr_list`/`fptr_list` and deep `dptr_list` subtrees that the old
caller loops never reached).

PostgreSQL reference (pinned `5713b437abed7085e7d59849c6e9e0f4f469633d`):
`ExecParallelRetrieveInstrumentation` (`execParallel.c:1094`) aggregates worker
instrumentation with `InstrAggNode` and descends with `planstate_tree_walker` —
**each plan node visited exactly once**. The patch restores that invariant.

## 2. Actual changed LOC and files

- Plan band: low 2 / likely 5 / high 15, §5-d 150% stop at 22.
  **Actual 12 insertions / 8 deletions in the one planned file** — inside the
  band, stop condition not approached. 9 of the 12 inserted lines are the
  rationale comment.
- No unanticipated subsystem. No XASL serialization, persistent format, lock
  protocol or write path surface. The edit sits inside the same `m_mutex`
  critical section it always did and strictly *removes* redundant calls.

## 3. Correctness (§6-b, all five mandatory checks)

| # | Check | Outcome |
|---|---|---|
| 1 | Candidate-specific regression probe (`imp005_trace_probe.py`, S/P two-leg trace capture on both binaries) | **PASS** — all five targets `OK`, `strict_improvement_seen: true`, 0 under-counts. Detail in §4 |
| 2 | Target queries Q05 Q07 Q08 Q09 Q21 | **PASS** — base vs patch results EXACTLY equal |
| 3 | `q_relations` Q03 Q04 Q05 Q06 Q07 Q08 Q09 Q10 Q11 Q12 Q13 Q15 Q17 Q19 Q21 | **PASS** — included in the sweep, EXACTLY equal |
| 4 | Q01–Q22 full result smoke | **PASS** — all 22 EXACTLY equal (ordered compare where `ORDER BY`, canonical multiset with duplicate multiplicity otherwise, raw decimal text preserved, zero tolerance), non-vacuous on both sides. Q15 view proved absent before create and absent after drop **in both variants** |
| 5 | Concurrency / memory stress + sanitizer lane | **Not applicable as a separate build** — the candidate is neither a concurrency nor a memory candidate under §6-b-5: it changes no locking, no allocation and no shared state, it only deletes repeated calls inside an already-held `m_mutex`. The parallel path it lives on is nevertheless exercised concurrently by every P leg of the probe (parallel scan workers merging into one main tree) and by all 12 gate blocks and 4 stream blocks of the A/B |

Evidence: `evidence/correctness-report.json` (per-query ordered/rows/equal/
non-vacuous), `evidence/correctness-base-summary.json`,
`evidence/correctness-patch-summary.json`.

## 4. §5 metric signature — the duplication is gone, nothing is lost

`imp005_trace_probe.py` captures, on one server instance per binary, a serial leg
(`/*+ NO_PARALLEL_SCAN */`) and a natural parallel leg with `SET TRACE ON`, then
asserts on the deterministic integer counters (`readrows`, `readkeys`,
`filteredkeys`, `rows`) that

- **A** the serial legs are identical base-vs-patch (the patch cannot touch the
  serial path) — held for all five targets;
- **B** on every matched SCAN node, `base_par == m × patch_par` for a whole
  number `m ≥ 1`, with `m > 1` somewhere (an under-count would break the exact
  integer relation, because `m × (p + lost)` is not a multiple of `p`);
- **C** `patch_par ≤ base_par` on every counter.

Observed merge multiplicities on the base binary, collapsed to 1 by the patch:

| Query | multiplicities by trace depth | interpretation |
|---|---|---|
| Q09 | depth 6: ×1, 8: ×2, 10: ×3, 12: ×4, 14: ×5 | textbook k-fold over-count down a 5-level `scan_ptr` chain |
| Q08 | depth 30: ×1, 32: ×2, 34: ×3 | 3-level chain |
| Q21 | depth 22: ×1, 26: ×2 | 2-level chain |
| Q05, Q07 | all ×1 | those plans' chains are one level deep, so nothing was duplicated and nothing changed — the negative control inside the probe |

Concrete Q09 numbers (`dba.orders.pk_orders_o_orderkey`, depth 10):
`readkeys` 9 784 839 → 3 261 613, `rows` 19 569 678 → 6 523 226, exactly ÷3.
Serial reference for the same node: `readkeys` 3 261 613 — the patched parallel
leg lands on the serial truth. Q21 depth 26 shows the residual genuine
parallel/serial variation the plan predicted for time-like and worker-split
values (39 907 302 → 19 953 651 vs serial 39 907 300 summed across the two
worker lines): the integer-multiple relation holds, the serial comparison is
recorded as reference only.

Evidence: `evidence/trace-probe-report.json`.

## 5. Performance A/B (§6-c/§6-d) — the null guard

This candidate has **zero expected runtime effect**: the merge it fixes runs only
while a trace is being collected, and no measured block runs with `SET TRACE ON`.
The A/B therefore exists to prove *absence of regression*, and §7-a criterion 2
(CI entirely below 1.0) cannot hold — as the plan recorded in advance
(`worktrees/IMP-005/implementation-plan.md`, "Verdict criteria for this
enabler"). MDE rule: user decision (c), `corrected_MDE = 15.3158 ×
paired_CV_fast` from `impl/fresh-baseline.json`.

### 5.1 Gate — Q09, 3 balanced cycles B→P→P→B, 12 accepted blocks

Q09 is the gate query: it is a plan target, it carries the largest observed
duplication factors (up to ×5), and its pinned `paired_CV_fast` 0.002788 gives
the tightest corrected MDE per unit of measurement time among the targets.
Every block restarted the server on that block's binary under `taskset -c 0-15`
+ `numactl --membind=0`, passed the ownership / all-TID affinity gate before and
after the block (131 TIDs, 0 off-SUT throughout), proved WARM for that block,
ran 1 uncounted warmup + 3 measured statements on one connection, and was
accepted with a `CLEAN` bgload verdict on the first attempt — **0 rejected
attempts across all 12 blocks**.

| | value |
|---|---|
| base block medians (s) | 11.044999, 11.035999, 11.086999, 11.069, 11.000999, 11.036 |
| patch block medians (s) | 11.127, 11.131, 11.086999, 11.064, 11.03, 11.156999 |
| paired P/B ratios (6 pairs, sorted) | 0.99955, 1.00000, 1.00264, 1.00742, 1.00861, 1.01096 |
| point estimate (median paired ratio) | **1.00503 (+0.50%)** |
| paired bootstrap 95% CI (10⁵ resamples, seed 20260806) | **[0.99977, 1.00979]** |
| corrected MDE (Q09) | 4.271% |
| restart-regime CV, base blocks / patch blocks | 0.270% / 0.428% |
| §7-a criterion 2 (CI entirely below 1.0) | **false** — expected and not the accept test for this lane |
| regression proven (CI entirely above 1.0) | **false** |
| no-regression proved (CI upper bound < 1 + MDE) | **true** (1.0098 < 1.0427) |

Honest reading of the +0.50%: it is **six times smaller than the pinned
resolution** for Q09 and its CI straddles 1.0, so the measurement does not
establish a real difference — but the point estimate is positive in 5 of 6 pairs,
which is worth stating rather than rounding to "no effect". It cannot be the
patched code doing work: the changed function is only reachable while a trace is
collected, and none of these blocks traced. The residue is code-layout/binary
noise of the same order as the patch-side block CV (0.43%). §5.2 is the check on
whether that residue is systematic.

### 5.2 Stream — 21 other queries, negative controls (§7-c)

One balanced B→P→P→B cycle was planned; **3 of the 4 blocks completed**
(block1 base, block2 patch, block3 patch). Block3's Q19 failed its per-block
WARM gate 4 times ("monotone trailing window (still drifting)", rc=4 each
attempt — the Q11-style drift caveat the baseline already recorded), the driver
correctly refused to time an unconverged block and aborted, so **block4 (base)
never ran**. Disclosure: every stream base median therefore rests on **one**
block (block1), patch medians on two (block2/3), except Q19 where block3 is
absent and the comparison is 1-vs-1. No attempt was rejected for background
load anywhere in the stream; all timed blocks carried CLEAN bgload verdicts.

Result on what exists (`evidence/ab-stats.json` `stream`): all 21 queries have
both variants; the worst delta is **Q01 +2.28%**, inside its own corrected MDE
band region and **below the §7-c 3% bound**; `any_regression_gt_3pct: false`.
Q21, the largest trace target (52.6 s), moved −1.52%. The negative-control
contract of the plan (Q01 Q02 Q14 Q16 Q18 Q20 Q22 must not move) holds within
noise on every control.

The incomplete cycle weakens the stream's per-query resolution but does not
touch the primary estimate: the gate (§5.1) is a complete, balanced,
12-block/0-rejection measurement. To restore the balanced stream cycle later:
`STREAM_START=4 imp005_ab.sh stream` (the driver's per-block resume guard skips
blocks 1–3), with Q19's warm window widened or its `max_statements` raised
before retrying.

## 6. Verdict

**accepted (enabler)** under the plan's pre-stated criteria
(`implementation-plan.md` "Verdict criteria for this enabler"):

1. §6-b — all five checks pass (§3).
2. §5 metric signature — moved exactly as predicted: base-side merge
   multiplicities ×2…×5 collapse to ×1 on every deep chain node, serial legs
   byte-identical across binaries, zero under-counts (§4).
3. A/B no-regression — gate CI [0.9998, 1.0098] contains 1.0 (the EXPECTED
   outcome for a zero-effect-by-construction change) with upper bound far
   below 1 + corrected MDE (1.0427); no stream query regresses ≥ 3% (§5.2).
4. §7-a criterion 2 is recorded as false and is not the accept test for this
   lane, per the plan and §4-a.

Caveats attached to the verdict: (a) the stream corroboration cycle is 3/4
blocks (§5.2 disclosure) — the missing block is a base block, so if anything
the stream is biased *against* the patch (patch medians average a later,
warmer machine state); (b) the +0.50% gate point estimate is attributed to
code-layout/binary noise, six times below Q09's pinned resolution.

IMP-009 (the only §5.2-rule survivor of the 2026-08-06 scope decision) is
unblocked and starts next.

## 7. Rollback

`git revert e84baed11` on branch
`impl/tpch-sspq-impl-r1-20260803/IMP-005-nl-trace-merge-dedup`. The branch is
merged nowhere without user approval, so rollback is branch-local.

## 8. Consequences for the queue

- **IMP-009 and IMP-012 are unblocked**: their degree/trace readings were being
  taken from a merge that multiplied deep `scan_ptr` counters by their chain
  depth. Any earlier IMP-009/IMP-012 trace figure taken on the base binary must
  be re-read on this branch before it is used as evidence.
- Both candidates share `src/xasl/xasl_iteration.cpp`; this patch leaves that
  file untouched, so no textual conflict is introduced for them.

## 9. Raw evidence

`impl/IMP-005/raw-manifest.json` lists every raw artifact under
`/data/tpch-sspq/tpch-sspq-impl-r1-20260803/work/IMP-005` with sha256, the
command that produced it, the pins in force, and its validity flag.
