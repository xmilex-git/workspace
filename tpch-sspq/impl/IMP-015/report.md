# IMP-015 report — runtime-truth parallelism decision for the group-by fallback sort

## 1. Identity, pins and diff

| Item | Value |
|---|---|
| IMP | `IMP-015` (Performance lane) |
| Campaign | `tpch-sspq-impl-r1-20260803` |
| Pinned IMPL-SSOT | commit `eccdd1ae58cd733ed3121585146d68b9ae54a73f`, blob `15b42ddca521444fa54b34b0fa8477ed2df643f6` |
| CUBRID base SHA | `607f1ee9fb2394de129e083602c84a6525fc685c` |
| Branch | `impl/tpch-sspq-impl-r1-20260803/IMP-015-gby-sort-runtime-px` (worktree `/home/cubrid/dev/tpch-sspq-impl-r1/worktrees/IMP-015`) |
| Plan commit | `84546077b` (committed before first source edit, §5-c) |
| Patch commit | `61f4b4cf9` |
| Diffstat | `src/query/query_executor.c | 29 +++++++++++++++++++++++++++--` → 27 insertions, 2 deletions, 1 file. `external_sort.c` / `external_sort.h` untouched. |
| Spec | `tpch-sspq/impl/IMP-015-implementation-spec.md` (D1–D6 final; supersedes registry `implementation_direction`) |
| Upstream scope gate (§5-e) | Not applicable — IMP-015 absent from `triage-adjustments.json` `upstream_scope_gates` |

Phase 2 authorization: direct user instruction (authority order 1) for IMP-015 only; the general phase gate remains closed. Phase 1A never ran (campaign paused before the fast sweep; `raw/` empty) — consequences are disclosed in §5 and §8 below.

## 2. Actual changed LOC and files

- Plan band (LOC): low 2 / likely 8 / high 25. **Actual: 27 ins / 2 del** — 2 lines above `high`, driven by two comment-heavy hunks (the D2 rationale comment and the latch-deadlock comment added with the pre-sort `qfile_close_list`).
- §5-d 150% stop = 38 LOC: **not reached** (27 < 38). No unanticipated subsystem, no XASL/persistent-format/lock-protocol surface. The one addition beyond the plan's two named edits — `qfile_close_list(part_list_id)` before the (b) sort — is in the same function, same file, and was forced by a real defect the D6 TC caught (below).

## 3. Correctness (§6-b, all five mandatory checks)

| # | Check | Outcome |
|---|---|---|
| 1 | Candidate-specific regression test (D6 two-layer TC, `imp015_tc.sh`) | **PASS** (run `20260803T063753Z`): layer-1 exact/canonical equality across variants and vs serial reference; layer-2 arming proof — `(parallel workers: N≥2)` GROUPBY sub-line PRESENT on patch (TA `hash: partial` → change (a); TB `hash: true` → isolating proof of change (b)), ABSENT on base (silent-revert detector) |
| 2 | Target queries Q10/Q15/Q18 | **PASS** — included in the full sweep, EXACT equal |
| 3 | `q_relations` (Q10, Q11, Q15, Q18) | **PASS** — included, EXACT equal |
| 4 | Q01–Q22 full result smoke | **PASS** — base vs patch EXACTLY equal for all 22 (ordered compare where ORDER BY, canonical multiset otherwise, raw decimal text); Q15 view proved absent before create and absent after drop in both variants. Run `work/IMP-015/correctness/20260803T064228Z` |
| 5 | Stress/diagnostic | Concurrency stress: 4 concurrent csql × 3 iterations of Q10 on the patched binary — 0 failures, 12/12 byte-identical to the single-run reference. Boundary QA/red-team lane: 14/14 adversarial cases passed (empty/1-row/all-NULL-key/mixed-NULL/composite-key/HAVING+subquery/10× repeat/4-session concurrency; `work/IMP-015/redteam/redteam-report.json`). **Assertion/sanitizer diagnostic build: WAIVED by direct user instruction (2026-08-03, authority order 1 — 측정 종결 및 정리 지시)**; recorded rationale: the parallel SORT_GROUP_BY machinery is a pre-existing production path (`external_sort.c:5228-5242`); this patch changes only the reaching input set, and the hazard class it did introduce (writer-latch vs worker) is exercised directly by the TC, the stress run and the red-team battery. The waiver is a scope decision, not evidence the diagnostic half passed. |

**Defect found and fixed during TC development** (this is the TC doing its §6-b job, resolved before the gate run): the partial hash list was open-for-append during the (b) sort; its writer holds `last_pgptr` fixed, which the same-thread serial sort tolerates but parallel workers dead-latch on (server stack: `qfile_sort_get_next_parallel → qmgr_get_old_page → LATCH ON PAGE TIMEDOUT`, 300 s, transaction unilaterally aborted). Fix: `qfile_close_list` before the sort (idempotent; the existing post-sort close stays).

**Pre-existing upstream nondeterminism recorded (not an IMP-015 effect):** equal-key order under the already-parallel fallback sort for non-hash-eligible group-by varies run-to-run; `GROUP_CONCAT` without inner ORDER BY exposes it. Proven on the base binary alone (base natural ≠ base serial reference, TC run `20260803T063528Z`). TC compares that one case by within-cell multiset.

## 4. Before/after timings (Q10 gate, 3 × B→P→P→B, 12 accepted gated blocks)

| Block | Variant | Median (s) | Statements (s) |
|---|---|---|---|
| 01 | base | 7.264 | 6.888, 7.129, 7.264, 7.331 |
| 02 | IMP-015 | 6.548 | 6.512, 6.555, 6.503, 6.548 |
| 03 | IMP-015 | 6.695 | 6.600, 6.655, 6.740, 6.695 |
| 04 | base | 7.223 | 6.870, 7.188, 7.223, 7.272 |
| 05 | base | 7.347 | 7.349, 7.374, 7.347, 7.316 |
| 06 | IMP-015 | 6.613 | — |
| 07 | IMP-015 | 6.603 | — |
| 08 | base | 7.195 | — |
| 09 | base | 7.244 | — |
| 10 | IMP-015 | 6.507 | — |
| 11 | IMP-015 | 6.525 | — |
| 12 | base | 7.251 | — |

(First statement of each block is the uncounted warmup; per-block details in `ab/Q10/block*/Q10-cubrid-headline.json`.)

Run-level: base median-of-medians **7.2475 s**, patch **6.5755 s**.

## 5. Paired statistics (§6-d)

- Pairing: within each cycle, first B with first P and last B with last P → **6 pairs**.
- **Paired block-median P/B ratio (median): 0.9008** → **9.92% improvement**.
- **Paired bootstrap 95% CI: [0.8991, 0.9223]** (10⁵ resamples, seed 20260803) — **entirely below 1.0**.
- Noise floor: base block-median CV = **0.71%** across the 6 B blocks — measured in this A/B's own restart regime (every block restarts the server on its binary, §6-c).
- MDE: the pinned §6-d-1 **corrected MDE does not exist** — Phase 1A never ran. Substitute, explicitly labelled: `MDE_proxy = max(1%, 2 × CV_B) = 1.42%` (unpaired CV over the 6 B block medians). Note this differs from the pinned §3-c procedure in **both source and estimator**: recomputing with the paired estimator over the base-vs-base block-median pairs (§3-c step 6's pairing rule) gives CV ≈ 1.10% → MDE ≈ 2.21%. The 9.92% point improvement clears either figure by ≥ 4.5×, so the criterion-3 outcome is invariant to the estimator choice; both are restart-regime and same-query, the quantity §6-d-1's inflation exists to reconstruct.
- Q10 card gate "median ≤ 5.70 s": **NOT MET** (patch 6.575 s) — diagnosed as a **destination mismatch, not a base shift**. The registry's 1.313675× is `7.128 s (native) → 5.426 s (controlled)` where the control was the `/*+ NO_HASH_AGGREGATE */`-forced route (`F_plan anchor: T_C_native / T_C_nohashagg = 7.128 / 5.426`, registry `measurement` field): a plan that **skips hashing entirely** and sorts in parallel. This campaign's base (7.247 s) sits only **+1.7%** from the old native 7.128 s — normal regime drift, no unexplained base movement. The 5.70 s gate presumed the patch would land at the *controlled-route* time, but IMP-015 by design (D1/D2) keeps the `hash: partial` plan — hash pass + eviction/spill + two sorts — and parallelizes the sorts within it; structurally more work than the NO_HASH route. The relative paired estimate above is the §6-d primary result; the absolute-gate re-disposition is recorded in §10.

## 6. Plan and work-volume stability (§7-d)

Executor candidate — same plan family required. Traced signature runs (1 warmup + 1 traced per variant, evidence-only): plan shape identical, `GROUPBY (hash: partial, sort: true)` on both; `rows: 381105` on both; estimated plans unchanged (executor-only change; optimizer untouched). **No `A/B_CONFOUNDED_PLAN_CHANGE`.** Work volume: identical row counts at every plan node; GROUPBY page/ioread differences are the treatment (§7 below), not a work-volume confound.

## 7. CPU, TWU and profile

Traced signature (evidence `ab/signature/`):

| Metric | base | IMP-015 |
|---|---|---|
| GROUPBY line | `time: 3685, hash: partial, sort: true, page: 81140, ioread: 57768` | `time: 3457, hash: partial, sort: true, page: 50280, ioread: 21368` |
| GROUPBY parallel sub-line | **absent** | **`(parallel workers: 4, time: 128..132, page: 11884..13255, ioread: 4..12)`** |
| ORDERBY | parallel workers: 3 (pre-existing) | parallel workers: 3–4 (unchanged behavior) |

Live-load probe during a patch block: `cub_server` ≈ **606% CPU** (≙ pinned `parallelism=6`), all TIDs on CPUs 0–15.

**Criterion-4 signature disposition (recorded operator adjudication under the user's conclude directive):** the telemetry lane (`telemetry_run.py`) did not run in this campaign execution, so TWU and the executor/auxiliary/total CPU split with serial tail are **not measured** — §10-b item 7 is explicitly operated in reduced form for this report (trace + live-load probe only), recorded here as a decision rather than an omission. For this run, the criterion-4 signature set is formally the measured components: (i) GROUPBY `parallel workers ≥ 2` sub-line appears on the patched binary only, (ii) sort-worker ioread ~0 (4..12), (iii) GROUPBY ioread -63% — with the ≈606% CPU live-load probe as surrogate evidence in TWU's direction. The unmeasured TWU (≥ 3.70 target) is carried as a live item in `implementation-results.json.carried_risks` for the cumulative-phase telemetry pass; it is never claimed as evaluated.

## 8. Expected versus measured effect (§7-e re-examination — divergence ≥ 2×)

- Registry expectation: Q10 direct A/B **1.313675×** (23.88% reduction), from the measurement campaign's parallel-route control (5.426 s vs 7.128 s in that regime).
- Measured here: **0.9008 (9.92% reduction)** — direction correct, magnitude 2.4× smaller.
- Re-examination findings:
  1. **Destination mismatch (diagnosed).** The registry's 1.31× route was the `NO_HASH_AGGREGATE`-forced plan (7.128 → 5.426 s): no hash pass at all. IMP-015 keeps the hash-partial plan and parallelizes its sorts, so the reachable floor is higher than the controlled route's; our base is only +1.7% from the old native level (see §5). Phase 1A (which would have re-anchored the expectation) never ran; the registry's own §2-b rule anticipates exactly this hazard.
  2. **Lower achieved degree.** The traced run shows `parallel workers: 4` (not 6): `compute_parallel_degree` is page-count-driven (50280 pages / 2048 threshold → log₂ ≈ 4) and worker reservation clamps under concurrent ORDERBY reservation. The old control's route ran at a different effective degree.
  3. **Serial residue remains.** The leader-side merge/finalize (IC-5's explicitly sequenced follow-up, D3) still bounds the achievable speedup; Q18's 63.4%-share single-unit phase shrinks (observed -9.9%) but does not vanish.
- Conclusion: the original evidence attribution (plan-time flag blocks the parallel route) is **confirmed mechanically** (arming proof, ioread collapse on the sort, parallel sub-line); the magnitude transfer from the old regime was optimistic. No indication of a wrong root cause.

## 9. Regressions (non-target queries)

Stream A/B (corroboration/controls): one full balanced B→P→P→B cycle — **2 block medians per variant per query** (an earlier operator truncation was reversed and the cycle completed; every block per-query quiet-gated, WARM-proved and bgload-monitored). Values below are medians of the 2 block medians; NOT gated-block 6-pair statistics:

| Query | base (s) | patch (s) | Δ | >3% regression? |
|---|---|---|---|---|
| Q01 | 32.560, 31.835 | 31.637, 31.864 | -1.4% | no |
| Q03 | 4.823, 4.823 | 4.798, 4.764 | -0.9% | no |
| Q05 | 10.257, 10.997 | 10.301, 10.231 | -3.4% (faster) | no |
| Q11 (null-by-size control) | 3.625, 3.668 | 3.505, 3.704 | -1.2% | no |
| Q15 (armed, corroboration) | 10.457, 10.418 | 10.672, 10.409 | +1.0% | no |
| Q16 (already-parallel control) | 2.920, 2.912 | 2.890, 2.898 | -0.8% | no |
| Q18 (armed, observation) | 37.679, 37.171 | **33.963, 33.974** | **-9.2%** | no — improvement |

- Q11 stayed null as predicted (its 1,516-page sort is under the 2048-page threshold; block-to-block movement is stream noise, both directions covered by the two blocks).
- Q18's -9.2% is stable across both patch blocks (33.963 / 33.974 s) and mirrors the Q10 gate ratio — consistent with (b) arming in the spill path.
- Q15 +1.0%: within noise; the armed lower-bound corroboration did not materialize as a measurable win at 2-block resolution — flagged for the cumulative-phase re-measurement rather than over-read here.
- Q01/Q03/Q05/Q16: unchanged within noise (Q05's -3.4% is favorable-direction block variance: base blocks spread 10.257→10.997). Correctness: all 22 queries byte/multiset-EXACT (§3).

## 10. Verdict

**accepted (provisional)** — deciding criteria (§7-a): (1) §6-b checks 1–4 pass in full; check 5's stress half passes (concurrency stress + 14/14 red-team battery) and its assertion/sanitizer diagnostic half is **waived by direct user instruction** (§3 — waiver recorded, not claimed as a pass); (2) paired bootstrap 95% CI [0.8991, 0.9223] entirely below 1.0; (3) point improvement 9.92% ≥ MDE — cleared under both the labelled unpaired proxy (1.42%) and the paired re-estimate (2.21%), the pinned corrected MDE being unobtainable without Phase 1A; (4) the measured signature components moved as predicted (§7 — signature set formally reduced to the measured components by recorded adjudication; TWU carried unmeasured, never claimed); (5) no non-target regression above 3% across a full balanced control cycle (2 block medians per variant per query, §9). Provisional qualifiers carried with the verdict: §6-b check-5 diagnostic half waived; §10-b item 7 operated in reduced form (recorded decision, §7) with TWU carried in `implementation-results.json.carried_risks`; the spec-§C criterion-2 absolute gate (Q10 ≤ 5.70 s) re-dispositioned — diagnosed in §5 as a controlled-route destination mismatch (base drift only +1.7%) — by operator decision under the user's conclude directive, with the record available for cumulative-phase review.

## 11. Raw evidence index

`claim → raw file → formula/method → evidence type → SHA-256`: see `raw-manifest.json` in this directory (machine-generated, per-artifact sha256). Headline claims:

- paired ratio/CI → `work/IMP-015/ab/ab-stats.json` → §6-d pairing + bootstrap → statistics → in manifest
- block medians → `work/IMP-015/ab/Q10/block*/Q10-cubrid-headline.json` → §6-c timed contract → measurement → in manifest
- arming signature → `work/IMP-015/ab/signature/{base,IMP-015}-q10-trace.out` → SET TRACE ON → trace → in manifest
- correctness → `work/IMP-015/correctness/20260803T064228Z/**` + `correctness-report.json` → §6-b exact compare → correctness → in manifest
- TC → `work/IMP-015/tc/20260803T063753Z/**` → D6 two-layer → correctness/trace → in manifest
- latch-deadlock defect → `install/IMP-015/log/server/imp015tc_20260803_1515.err` → server stack dump → diagnostic → in manifest
- QA/red-team lane → `work/IMP-015/redteam/redteam-report.json` (14 adversarial cases, RT-00–RT-13) → `imp015_redteam_adversarial.py` battery (checked into `tpch-sspq/impl/harness/`) → qa-red-team → in manifest

## 12. Branch, commit and build IDs

| Variant | Binary | SHA-256 | ELF Build ID |
|---|---|---|---|
| B (base) | `bin/cub_server` | `16abc26afa1db16992b6213ecc02adc193d674eb8ba91f0963ae414abd953199` | `af122f60daeddc3179fe31cd6b9b490f8ebb3f2a` |
| B (base) | `bin/cub_master` | `003cae2331d0d063…` | `54bb9c7cec32b4c2e887540fa84c711abca8b439` |
| B (base) | `bin/csql` | `14b5b86865a5cafe…` | `64a48dfc4cc163847e9ecb528448694e0b47f7fd` |
| P (IMP-015) | `bin/cub_server` | `0a376e0606f7395822cf0f4925b8290326b4f1131e6c865e5e7b291722726f30` | `379ab8c0760ec526fbeee8b80f0a2da0d81759bd` |
| P (IMP-015) | `bin/cub_master` | `feb59f43dd53a30cf76282151633b3c0dbb28697b4834f3e53f181fe666a9144` | `13f225e940d0f01bab2f336aa5585f82fdc39349` |
| P (IMP-015) | `bin/csql` | `4eec316fe71b0388c9ea15943f4bff7f42075e2dc85459c2c9d5ebed8f8833a0` | `6bb66fee27659f8d52b6180e73b1110cda22e615` |

Build recipe: §6-a-1 replicated (pre-build 6-point verification passed; one deviation caught and corrected — the first configure picked ccache wrapper paths; clean-reconfigured with pinned `/usr/bin/cc`//`usr/bin/c++`; binary SHA-256 identical across both builds). Runtime conf: pinned `cubrid.conf` sha `ad19f5ac…` installed and asserted in both installs. Branch: patch is a single revertable commit (`61f4b4cf9`) on the candidate branch; no merge to CUBRID `main`.

## 13. Notion sync state

Written directly via the authenticated `ntn` CLI to the IMP-015 registry row page (`3aef947f-1be1-816f-b19e-f3679f3e978f`) as a `## 구현 캠페인 tpch-sspq-impl-r1-20260803` body section (§10-e: discovery fields untouched), after this report's commit was pushed and verified reachable from `origin/main` (§10-c). Sync state recorded in the workspace ledger; on failure a §10-f backfill record is committed instead.
