# Phase 1A — fresh Q01–Q22 CUBRID baseline

Campaign `tpch-sspq-impl-r1-20260803` · IMPL-SSOT pinned at commit `eccdd1ae58cd733ed3121585146d68b9ae54a73f`, blob `15b42ddca521444fa54b34b0fa8477ed2df643f6`.

This baseline is the **only** "before" this campaign's scoring (section 2-b) and A/B procedure (section 6-c) may use. No absolute wall time from the previous measurement campaign is reused as a denominator here (section 3).

## Campaign identity

| Item | Value |
|---|---|
| Campaign ID | `tpch-sspq-impl-r1-20260803` |
| Pinned IMPL-SSOT commit | `eccdd1ae58cd733ed3121585146d68b9ae54a73f` |
| Pinned IMPL-SSOT blob | `15b42ddca521444fa54b34b0fa8477ed2df643f6` |
| CUBRID base SHA (frozen) | `607f1ee9fb2394de129e083602c84a6525fc685c` |
| Install prefix (immutable base) | `/home/cubrid/dev/tpch-sspq-impl-r1/install/base` |
| `bin/csql` sha256 | `14b5b86865a5cafeb6b34ffa01a958b6d0e2da6e72d2e982e0527bac581a84b8` |
| `bin/csql` ELF Build ID | `64a48dfc4cc163847e9ecb528448694e0b47f7fd` |
| `bin/cub_master` sha256 | `003cae2331d0d0632bc450cc7520c40fcbd88190b548e828af13a7b1b9a890a5` |
| `bin/cub_master` ELF Build ID | `54bb9c7cec32b4c2e887540fa84c711abca8b439` |
| `bin/cub_server` sha256 | `16abc26afa1db16992b6213ecc02adc193d674eb8ba91f0963ae414abd953199` |
| `bin/cub_server` ELF Build ID | `af122f60daeddc3179fe31cd6b9b490f8ebb3f2a` |
| `conf/cubrid.conf` sha256 **as installed** | `ad19f5ac1e7e983e4a0b1c113d21e25e096d02d3160445f9d10a2e8b6d9cb9ff` |
| `CUBRID_TMP` | `/data/tpch-sspq/tpch-sspq-impl-r1-20260803/work/tmp` |
| Database | `tpch_sf10_q1` |
| Database files | `/home/cubrid/dev/workspace/.git_ignored_dir/tpch-sspq/cubrid-databases` |
| SUT CPUs / memory node | `0-15` / node `0` |
| Collector CPUs | `20-23` |
| Isolation mechanism | taskset + numactl applied at process start (IMPL-SSOT section 3-a); never cpuset cgroups, never post-hoc re-pinning |
| External-CPU invalidation gate | 6.0 core-s/s (IMPL-SSOT section 3-a, AMEND-D) |
| Blocks per query | 6 |
| Measured runs per block | 3 |
| Phase 1A driver tmux session | `tpch-sspq-impl-r1-20260803-phase1a-driver` |
| Phase 1A driver PID | `2848446` |
| Collection window start (UTC) | 2026-08-03T01:30:44Z |
| Aggregated (UTC) | 2026-08-04T10:51:09Z |

## Per-query baseline

`median wall` is the median over the converged WARM block medians (section 3-c). `within-block CV` is the largest dispersion seen inside any single block — a dispersion estimate, never a confidence interval (section 6-d). `block CV` is the dispersion across block medians.

| Query | median wall (s) | block medians (s) | within-block CV (max) | block CV | paired CV | **MDE** | blocks ok | blocks invalid |
|---|---:|---|---:|---:|---:|---:|---:|---:|
| Q01 | 31.643 | 31.649, 31.616, 31.638, 31.671, 31.604, 31.653 | 0.47% | 0.08% | 0.10% | **1.00%** | 6 | 0 |
| Q02 | 0.364 | 0.364, 0.366, 0.365, 0.364, 0.367, 0.364 | 0.69% | 0.35% | 0.49% | **1.00%** | 6 | 0 |
| Q03 | 4.539 | 4.537, 4.547, 4.542, 4.533, 4.505, 4.560 | 0.66% | 0.41% | 0.51% | **1.03%** | 6 | 0 |
| Q04 | 1.666 | 1.666, 1.668, 1.664, 1.664, 1.666, 1.671 | 0.69% | 0.16% | 0.22% | **1.00%** | 6 | 0 |
| Q05 | 10.335 | 10.306, 10.148, 10.252, 10.373, 10.365, 10.396 | 0.70% | 0.91% | 0.98% | **1.96%** | 6 | 0 |
| Q06 | 3.846 | 3.845, 3.852, 3.846, 3.845, 3.848, 3.843 | 0.21% | 0.08% | 0.11% | **1.00%** | 6 | 0 |
| Q07 | 18.649 | 18.309, 18.480, 18.863, 18.699, 18.650, 18.649 | 1.26% | 1.03% | 1.16% | **2.32%** | 6 | 0 |
| Q08 | 1.007 | 0.991, 1.004, 1.011, 0.988, 1.060, 1.015 | 10.73% | 2.58% | 2.21% | **4.42%** | 6 | 0 |
| Q09 | 10.578 | 10.594, 10.578, 10.555, 10.598, 10.566 | 0.44% | 0.17% | 0.28% | **1.00%** | 5 | 1 |
| Q10 | 7.044 | 7.111, 7.022, 7.060, 7.028, 7.094, 7.020 | 1.34% | 0.56% | 0.80% | **1.60%** | 6 | 0 |
| Q11 | 3.228 | 3.529, 3.404, 3.298, 3.159, 3.040, 2.961 | 0.28% | 6.75% | 0.59% | **1.19%** | 6 | 0 |
| Q12 | 3.950 | 3.945, 3.953, 3.949, 3.953, 3.946, 3.952 | 0.32% | 0.09% | 0.14% | **1.00%** | 6 | 0 |
| Q13 | 11.334 | 11.328, 11.368, 11.354, 11.328, 11.341, 11.323 | 0.27% | 0.16% | 0.22% | **1.00%** | 6 | 0 |
| Q14 | 3.117 | 3.116, 3.116, 3.120, 3.127, 3.118, 3.115 | 0.23% | 0.14% | 0.18% | **1.00%** | 6 | 0 |
| Q15 | 10.024 | 10.041, 10.020, 10.029, 10.030, 10.006, 9.989 | 0.32% | 0.19% | 0.11% | **1.00%** | 6 | 0 |
| Q16 | 2.918 | 2.920, 2.904, 2.908, 2.916, 2.942, 2.924 | 0.93% | 0.46% | 0.51% | **1.02%** | 6 | 0 |
| Q17 | 0.146 | 0.146, 0.146, 0.146, 0.147, 0.147, 0.147 | 0.39% | 0.37% | 0.28% | **1.00%** | 6 | 0 |
| Q18 | 37.481 | 37.540, 37.370, 37.319, 37.423, 37.753, 37.603 | 0.99% | 0.43% | 0.50% | **1.00%** | 6 | 0 |
| Q19 | 43.964 | 44.008, 43.829, 44.034, 43.958, 43.970, 43.895 | 0.42% | 0.17% | 0.23% | **1.00%** | 6 | 0 |
| Q20 | 3.000 | 3.022, 3.008, 3.009, 2.973, 2.967, 2.992 | 0.85% | 0.73% | 0.73% | **1.46%** | 6 | 0 |
| Q21 | 52.586 | 52.479, 52.651, 52.446, 52.522, 52.820, 52.663 | 1.08% | 0.27% | 0.23% | **1.00%** | 6 | 0 |
| Q22 | 1.119 | 1.118, 1.119, 1.120, 1.115, 1.119, 1.123 | 0.22% | 0.23% | 0.29% | **1.00%** | 6 | 0 |

**Total Q01–Q22 median wall time: 262.544 s** (4.38 min), over 22 of 22 queries with a valid baseline.

### Queries that dominate `expected_saved_seconds`

Section 2-b multiplies `fresh_base_median_q` by the effect fraction, so absolute wall time — not relative effect — decides which candidates can contribute meaningful seconds.

| Rank | Query | median wall (s) | share of Q01–Q22 total |
|---:|---|---:|---:|
| 1 | Q21 | 52.586 | 20.03% |
| 2 | Q19 | 43.964 | 16.75% |
| 3 | Q18 | 37.481 | 14.28% |
| 4 | Q01 | 31.643 | 12.05% |
| 5 | Q07 | 18.649 | 7.10% |
| 6 | Q13 | 11.334 | 4.32% |
| 7 | Q09 | 10.578 | 4.03% |
| 8 | Q05 | 10.335 | 3.94% |

The top five queries alone are 184.325 s — 70.21% of the total. A candidate that does not touch them cannot move the campaign total materially, whatever its relative effect.

## Minimum detectable effect — what this host can actually prove

**This is a first-class deliverable, not a diagnostic.** Section 3-a's external-CPU gate stands at 6.0 core-s/s because measurement showed a lower gate is unattainable on this host (AMEND-D). A 6.0 core-s/s tolerance is large relative to the few-percent effects many candidates predict, so **the gate no longer guarantees the environment can resolve small effects**. Resolution is carried instead by the paired design and by the honest per-query MDE below.

`MDE = max(1%, 2 × baseline_paired_CV)` (section 6-d). The paired CV is the base-vs-base paired coefficient of variation of block medians (section 3-c step 6), computed under two pairings — adjacent blocks, and blocks spaced to mirror the B-P-P-B slot separation of section 6-c — with the **larger** of the two used, so the MDE is not flattered by pairing temporally adjacent blocks.

| Query | fast-regime paired CV | pairing used | raw MDE | inflation applied | **CORRECTED MDE** | median wall (s) | smallest provable saving (s) |
|---|---:|---|---:|---:|---:|---:|---:|
| Q01 | 0.10% | adjacent | 1.00% | measured directly | **2.98%** | 31.643 | 0.942 |
| Q02 | 0.49% | adjacent | 1.00% | measured directly | **1.37%** | 0.364 | 0.005 |
| Q03 | 0.51% | adjacent | 1.03% | measured directly | **1.49%** | 4.539 | 0.068 |
| Q04 | 0.22% | spaced | 1.00% | measured directly | **1.00%** | 1.666 | 0.017 |
| Q05 | 0.98% | adjacent | 1.96% | measured directly | **4.46%** | 10.335 | 0.461 |
| Q06 | 0.11% | adjacent | 1.00% | measured directly | **1.44%** | 3.846 | 0.055 |
| Q07 | 1.16% | spaced | 2.32% | 15.3158x | **35.60%** | 18.649 | 6.638 |
| Q08 | 2.21% | spaced | 4.42% | 15.3158x | **67.71%** | 1.007 | 0.682 |
| Q09 | 0.28% | adjacent | 1.00% | 15.3158x | **8.54%** | 10.578 | 0.904 |
| Q10 | 0.80% | spaced | 1.60% | 15.3158x | **24.54%** | 7.044 | 1.729 |
| Q11 | 0.59% | adjacent | 1.19% | 15.3158x | **18.19%** | 3.228 | 0.587 |
| Q12 | 0.14% | spaced | 1.00% | 15.3158x | **4.19%** | 3.950 | 0.165 |
| Q13 | 0.22% | adjacent | 1.00% | 15.3158x | **6.88%** | 11.334 | 0.779 |
| Q14 | 0.18% | spaced | 1.00% | 15.3158x | **5.57%** | 3.117 | 0.174 |
| Q15 | 0.11% | spaced | 1.00% | 15.3158x | **3.45%** | 10.024 | 0.346 |
| Q16 | 0.51% | spaced | 1.02% | 15.3158x | **15.57%** | 2.918 | 0.454 |
| Q17 | 0.28% | adjacent | 1.00% | 15.3158x | **8.54%** | 0.146 | 0.013 |
| Q18 | 0.50% | spaced | 1.00% | 15.3158x | **15.28%** | 37.481 | 5.729 |
| Q19 | 0.23% | spaced | 1.00% | 15.3158x | **7.05%** | 43.964 | 3.101 |
| Q20 | 0.73% | adjacent | 1.46% | 15.3158x | **22.40%** | 3.000 | 0.672 |
| Q21 | 0.23% | adjacent | 1.00% | 15.3158x | **6.96%** | 52.586 | 3.660 |
| Q22 | 0.29% | adjacent | 1.00% | 15.3158x | **8.87%** | 1.119 | 0.099 |

### The correction is mandatory, and why (section 6-d-1)

The fast Phase 1A regime runs all six blocks of a query on **one continuous server instance**, so those blocks share buffer, page-table and thread-pool state and are **not independent**. Phase 2's `B → P → P → B` A/B blocks **are** independent, because swapping binaries forces a restart. The fast regime therefore measures a strictly smaller dispersion than the regime the MDE is actually spent in, and feeding an uncorrected fast-regime paired CV into `MDE = max(1%, 2 × paired_CV)` would produce an MDE smaller than the noise present in a real A/B block — **the campaign would over-accept, reporting restart noise as real improvement**.

`corrected_MDE_q = max(1%, 2 × inflation × paired_CV_fast_q)` for Q07–Q22. Q01–Q06 use their **directly measured** restart-regime paired CV instead: there is no reason to estimate a quantity that was measured. The inflation factor, its six per-query points, their spread and the written reason for how they were combined are published separately in `tpch-sspq/impl/restart-variance-calibration.json` so the factor is auditable independently of this file.

### ⛔ STOP-AND-REPORT — the combination rule is escalated to the user

**IMPL-SSOT section 6-d-1 escalation, section 11-a.** The six calibration points support neither a single pooled factor nor a defensible wall-magnitude-dependent one, and section 6-d-1 forbids picking a factor to keep the sweep moving. **The combination rule is NOT decided; it is the user's decision.**

Every corrected MDE printed in this file is a **PROVISIONAL, ILLUSTRATIVE** figure, not a campaign value. It is computed under the most conservative of the six measured factors (**15.3158x**, the maximum observed) purely so the shape of the table can be read while the decision is open. The maximum is used because it is the one option that cannot under-correct, and under-correction is the single failure mode section 6-d-1 exists to prevent — an MDE smaller than real A/B noise causes false accepts. Section 6-d-1 forbids picking a factor to keep the sweep moving. This value is not picked for convenience: it is the most conservative of the six measured factors, so it cannot under-correct and therefore cannot cause a false accept. Every downstream artifact produced under it is labelled provisional, and the consequences of all three candidate rules are published side by side so the decision is the user's.

**Nothing downstream asserts a verdict from these numbers.** In `tpch-sspq/impl/priority-ranking.md` every `UNPROVABLE_ON_THIS_HOST` determination that would depend on the factor is **WITHHELD**, with what each candidate rule would give published alongside it, so no candidate is judged provable or unprovable on the strength of a factor this campaign picked.

The three candidate rules and their per-query consequences are tabulated in `tpch-sspq/impl/priority-ranking.md`, together with the additive-versus-multiplicative diagnostic that explains the direction of the failure and the fourth option — collecting more calibration blocks, which answers the question by measurement instead of by model choice.

**Why neither rule fits:**

- NEITHER a single pooled factor NOR a defensible wall-magnitude-dependent factor fits the six calibration points.
- (a) The wall-dependent fit is not robust. Full-sample pearson r = 0.7150 clears the declared 0.70 threshold by 0.015 and the residual reduction 30.1% clears the declared 30% threshold by 0.1 points, but leave-one-out shows the association is carried by individual points: dropping Q01 gives r=+0.3928, Q04 gives r=+0.6878 (all six: Q01:+0.3928, Q02:+0.7189, Q03:+0.7833, Q04:+0.6878, Q05:+0.8027, Q06:+0.7754).
- (b) A single pooled factor is out of range: the clamped factors span 1.4039..15.3158, a ratio of 10.91, beyond the declared stop ratio of 10.0.
- (c) The model is contradicted directly by near-equal walls: Q03 at 4.539s has factor 1.452 while Q06 at 3.846s has factor 6.424 — walls differ 1.18x, factors differ 4.43x.
- (d) Mechanism for the instability, so this is not left as an unexplained anomaly: the ratio's DENOMINATOR is at the resolution floor for the two queries carrying the extreme factors. Fast-regime paired CV is 0.000972 for Q01 and 0.001123 for Q06, each estimated from only 3 pairs. A ratio whose denominator is a 3-pair estimate of a ~0.1% dispersion is not a stable quantity, and that is exactly where the 15.3x and 6.4x factors come from.

Per-query clamped factors: Q01 15.3158, Q02 1.4039, Q03 1.4516, Q04 1.4760, Q05 2.2719, Q06 6.4235. Spread 1.4039..15.3158 (ratio 10.91), geometric mean 2.9598, pearson r of ln(inflation) vs ln(wall) = 0.7150.

Sensitivity: the most conservative single factor available is 15.3158x. Queries whose corrected MDE would change under it: none. Reported so a factor-sensitive determination is visible. NO combination rule has been chosen — see combination.rule. While the rule is USER_DECISION_REQUIRED the ranking asserts no UNPROVABLE_ON_THIS_HOST verdict at all: every factor-dependent determination is WITHHELD and each row publishes what all three candidate rules would give. This column states what the most conservative single factor would give, as one of those possibilities — not because that factor is in force.

### Queries a few-percent effect could not be proven on — ILLUSTRATIVE ONLY

**For Q07–Q22 nothing in this section is a determination.** The section 6-d-1 combination rule is undecided (see the stop-and-report block above), so for those queries the corrected MDE is not a campaign value and none of them can yet be declared unable to resolve a given effect. Their rows below show which queries WOULD exceed a 3% corrected MDE **under the most conservative of the three candidate rules** — one possibility among three, listed so the shape of the decision is visible.

**Q01–Q06 are different and their rows ARE determinations.** Section 6-d-1 step 6 uses their DIRECTLY MEASURED restart-regime paired CV, so no combination rule enters their MDE and the pending decision cannot move them. Where a calibration query appears below it is a real section 6-d statement about this host, and the `basis` column says which kind of row you are looking at.

`tpch-sspq/impl/priority-ranking.md` withholds every factor-dependent `UNPROVABLE_ON_THIS_HOST` determination while the rule is open and publishes all three rules' outcomes per row; the calibration queries' verdicts there are asserted normally, for the same reason.

| Query | basis | corrected MDE | median wall (s) | an effect below this would be undecidable |
|---|---|---:|---:|---|
| Q08 | illustrative, under the most conservative candidate rule | **67.71%** | 1.007 | < 0.682 s |
| Q07 | illustrative, under the most conservative candidate rule | **35.60%** | 18.649 | < 6.638 s |
| Q10 | illustrative, under the most conservative candidate rule | **24.54%** | 7.044 | < 1.729 s |
| Q20 | illustrative, under the most conservative candidate rule | **22.40%** | 3.000 | < 0.672 s |
| Q11 | illustrative, under the most conservative candidate rule | **18.19%** | 3.228 | < 0.587 s |
| Q16 | illustrative, under the most conservative candidate rule | **15.57%** | 2.918 | < 0.454 s |
| Q18 | illustrative, under the most conservative candidate rule | **15.28%** | 37.481 | < 5.729 s |
| Q22 | illustrative, under the most conservative candidate rule | **8.87%** | 1.119 | < 0.099 s |
| Q09 | illustrative, under the most conservative candidate rule | **8.54%** | 10.578 | < 0.904 s |
| Q17 | illustrative, under the most conservative candidate rule | **8.54%** | 0.146 | < 0.013 s |
| Q19 | illustrative, under the most conservative candidate rule | **7.05%** | 43.964 | < 3.101 s |
| Q21 | illustrative, under the most conservative candidate rule | **6.96%** | 52.586 | < 3.660 s |
| Q13 | illustrative, under the most conservative candidate rule | **6.88%** | 11.334 | < 0.779 s |
| Q14 | illustrative, under the most conservative candidate rule | **5.57%** | 3.117 | < 0.174 s |
| Q05 | measured directly (section 6-d-1 step 6) — a real determination | **4.46%** | 10.335 | < 0.461 s |
| Q12 | illustrative, under the most conservative candidate rule | **4.19%** | 3.950 | < 0.165 s |
| Q15 | illustrative, under the most conservative candidate rule | **3.45%** | 10.024 | < 0.346 s |

At the other end, Q04 (measured restart-regime CV, no inflation applied) sit at the 1% floor — their paired CV is below 0.5%, so the formula's 1% floor, not the noise, is what limits them, and that holds under every candidate rule, so the pending decision cannot move them.

## Divergence from the previous measurement campaign

The previous campaign `tpch-sspq-fk-r1-20260730` is **input evidence only** (section 1-b) and its absolute times are **not** this campaign's before (section 3). The comparison exists only so an unexplained divergence is visible. A large divergence would mean the two campaigns are not in the same operating regime, which would invalidate reusing that campaign's evidence to score candidates (section 6-a-2).

| Query | fresh median (s) | previous campaign (s) | delta | delta % |
|---|---:|---:|---:|---:|
| Q01 | 31.643 | 31.193 | +0.450 | +1.44% |
| Q02 | 0.364 | 0.353 | +0.012 | +3.26% |
| Q03 | 4.539 | 4.808 | -0.269 | -5.58% |
| Q04 | 1.666 | 1.756 | -0.090 | -5.13% |
| Q05 | 10.335 | 9.591 | +0.745 | +7.76% |
| Q06 | 3.846 | 3.797 | +0.049 | +1.28% |
| Q07 | 18.649 | 24.044 | -5.395 | -22.44% |
| Q08 | 1.007 | 1.136 | -0.129 | -11.31% |
| Q09 | 10.578 | 10.981 | -0.403 | -3.67% |
| Q10 | 7.044 | 7.128 | -0.084 | -1.18% |
| Q11 | 3.228 | 1.342 | +1.886 | +140.57% |
| Q12 | 3.950 | 4.045 | -0.095 | -2.34% |
| Q13 | 11.334 | 11.483 | -0.149 | -1.29% |
| Q14 | 3.117 | 3.210 | -0.093 | -2.90% |
| Q15 | 10.024 | 10.455 | -0.431 | -4.12% |
| Q16 | 2.918 | 2.869 | +0.049 | +1.71% |
| Q17 | 0.146 | 0.147 | -0.001 | -0.34% |
| Q18 | 37.481 | 37.472 | +0.009 | +0.03% |
| Q19 | 43.964 | 45.856 | -1.892 | -4.13% |
| Q20 | 3.000 | 1.949 | +1.051 | +53.93% |
| Q21 | 52.586 | 49.274 | +3.312 | +6.72% |
| Q22 | 1.119 | 1.101 | +0.018 | +1.63% |

**Queries differing by 10% or more:** Q07 (-22.4%), Q08 (-11.3%), Q11 (+140.6%), Q20 (+53.9%).

## Invalidations

Section 3-a requires every invalidation to be recorded with its cause and the measured external load. Two levels exist: a **block** invalidation (the block yielded no baseline value) and an **attempt** invalidation (a discarded attempt inside a block that later succeeded). Both are listed; both remain on disk as evidence (section 8-e).

### Block-level invalidations

| Query | block | reason | detail |
|---|---:|---|---|
| Q09 | 3 | `MEASURE_BLOCK_REJECTED` | measure_block_rc=1; post_identity_rc=0 |

### Attempt-level invalidations (block later succeeded)

| Query | reason | measured external load (core-s/s) | gate | detail |
|---|---|---:|---:|---|
| Q01 | `WARM_NOT_CONVERGED` | — | — | — |
| Q01 | `INVALID_BACKGROUND_LOAD` | max 15.5419 | — | — |
| Q01 | `WARM_NOT_CONVERGED` | — | — | — |
| Q01 | `WARM_NOT_CONVERGED` | — | — | — |
| Q01 | `WARM_NOT_CONVERGED` | — | — | — |
| Q04 | `WARM_NOT_CONVERGED` | — | — | — |
| Q04 | `WARM_NOT_CONVERGED` | — | — | — |
| Q04 | `WARM_NOT_CONVERGED` | — | — | — |
| Q05 | `WARM_NOT_CONVERGED` | — | — | — |
| Q05 | `WARM_NOT_CONVERGED` | — | — | — |
| Q06 | `WARM_NOT_CONVERGED` | — | — | — |
| Q06 | `WARM_NOT_CONVERGED` | — | — | — |
| Q06 | `INVALID_BACKGROUND_LOAD` | max 6.9442 | — | — |
| Q06 | `WARM_NOT_CONVERGED` | — | — | — |
| Q07 | `WARM_NOT_CONVERGED` | — | — | — |
| Q07 | `WARM_NOT_CONVERGED` | — | — | — |

**Totals: 1 invalidated blocks, 16 discarded attempts.**

## How WARM convergence was determined

Section 3-c requires WARM to be **proved, not assumed**, and the method recorded. Every block ran the gate in `warm_establish.py` on an uncounted warm-up series executed on its own connection before the contract block was timed. Convergence requires all three of:

1. the trailing window is **not monotone** — a still-decaying series is not steady;
2. the **half-split level drift** over the whole series (burn-in statement dropped) is within `level_tol`; the two halves are compared rather than two adjacent 4-sample windows, because a 4-sample median is not a stable estimate of the level when the series contains multi-statement plateau excursions;
3. the trailing **spread** is within `spread_sanity`, which catches a genuinely unstable engine rather than a merely noisy one.

Per-query gate parameters are pinned in `harness/warm_params.json` with the measurement each was derived from. Per-block outcomes:

| Query | window | level_tol | spread | max stmts | blocks converged | typical statements to converge |
|---|---:|---:|---:|---:|---:|---:|
| Q01 | 4 | 0.02 | 0.05 | 12 | 6/6 | 12–12 |
| Q02 | 4 | 0.02 | 0.05 | 40 | 6/6 | 12–12 |
| Q03 | 4 | 0.02 | 0.05 | 20 | 6/6 | 12–12 |
| Q04 | 4 | 0.01 | 0.03 | 20 | 6/6 | 12–12 |
| Q05 | 4 | 0.04 | 0.07 | 24 | 6/6 | 12–12 |
| Q06 | 4 | 0.04 | 0.07 | 40 | 6/6 | 12–12 |
| Q07 | 4 | 0.04 | 0.07 | 16 | 6/6 | 12–12 |
| Q08 | 4 | 0.03 | 0.05 | 40 | 6/6 | 12–12 |
| Q09 | 4 | 0.03 | 0.05 | 20 | 5/5 | 12–12 |
| Q10 | 4 | 0.03 | 0.05 | 20 | 6/6 | 12–12 |
| Q11 | 6 | 0.03 | 0.05 | 20 | 6/6 | 19–19 |
| Q12 | 6 | 0.02 | 0.05 | 20 | 6/6 | 18–18 |
| Q13 | 6 | 0.01 | 0.05 | 20 | 6/6 | 18–18 |
| Q14 | 6 | 0.02 | 0.05 | 22 | 6/6 | 18–18 |
| Q15 | 4 | 0.01 | 0.03 | — | 6/6 | 12–12 |
| Q16 | 6 | 0.015 | 0.05 | 30 | 6/6 | 18–18 |
| Q17 | 6 | 0.03 | 0.07 | 40 | 6/6 | 18–18 |
| Q18 | 4 | 0.02 | 0.045 | 12 | 6/6 | 12–12 |
| Q19 | 4 | 0.02 | 0.045 | 12 | 6/6 | 12–12 |
| Q20 | 4 | 0.02 | 0.06 | 20 | 6/6 | 12–12 |
| Q21 | 4 | 0.01 | 0.03 | 12 | 6/6 | 12–12 |
| Q22 | 4 | 0.01 | 0.03 | 20 | 6/6 | 12–12 |

## Section 6 metric set

Per query the raw evidence under the campaign raw root carries:

| Query | executor CPU (core-s) | auxiliary CPU | total CPU | TWU | serial tail (s) | cycles | instructions | IPC | rows |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Q01 | 188.940 | 0.180 | 189.120 | 5.943 | 0.115 | 513136165077 | 1283190527273 | 2.5007 | 4 |
| Q02 | 1.830 | 0.030 | 1.860 | 3.972 | 0.000 | 4908167921 | 11332256614 | 2.3089 | 100 |
| Q03 | 20.550 | 0.100 | 20.650 | 4.482 | 0.459 | 56341306404 | 56689196453 | 1.0062 | 10 |
| Q04 | 9.840 | 0.040 | 9.880 | 5.365 | 0.114 | 27037605313 | 39047521990 | 1.4442 | 5 |
| Q05 | 10.140 | 0.080 | 10.220 | 1.020 | 0.000 | 28958889853 | 36773708168 | 1.2699 | 5 |
| Q06 | 22.960 | 0.060 | 23.020 | 5.722 | 0.114 | 62377648396 | 148553686918 | 2.3815 | 1 |
| Q07 | 18.390 | 0.140 | 18.530 | 1.002 | 18.480 | 52500941762 | 65063268388 | 1.2393 | 4 |
| Q08 | 4.010 | 0.040 | 4.050 | 3.527 | 0.229 | 10930030677 | 15131003489 | 1.3844 | 2 |
| Q09 | 52.410 | 0.080 | 52.490 | 4.914 | 0.000 | 142705214075 | 170009977116 | 1.1913 | 175 |
| Q10 | 22.620 | 1.210 | 23.830 | 3.355 | 0.115 | 64990439956 | 108233362377 | 1.6654 | 20 |
| Q11 | 2.560 | 0.020 | 2.580 | 1.004 | 2.509 | 7307442561 | 8214520265 | 1.1241 | 8685 |
| Q12 | 23.340 | 0.030 | 23.370 | 5.675 | 0.113 | 63483955858 | 147502461030 | 2.3235 | 2 |
| Q13 | 47.850 | 0.070 | 47.920 | 4.191 | 0.114 | 130547261999 | 237219263989 | 1.8171 | 46 |
| Q14 | 18.360 | 0.030 | 18.390 | 5.742 | 0.000 | 49910739904 | 95061986964 | 1.9046 | 1 |
| Q15 | 37.070 | 0.650 | 37.720 | 3.753 | 1.356 | 104236864921 | 218054140134 | 2.0919 | 1 |
| Q16 | 9.620 | 0.040 | 9.660 | 3.246 | 1.141 | 26243544841 | 64861463216 | 2.4715 | 27840 |
| Q17 | 0.730 | 0.010 | 0.740 | 2.134 | 0.114 | 1949398148 | 4526305189 | 2.3219 | 1 |
| Q18 | 92.140 | 6.450 | 98.590 | 2.644 | 11.846 | 270659024005 | 474783410844 | 1.7542 | 100 |
| Q19 | 217.130 | 0.330 | 217.460 | 4.963 | 0.113 | 591279958464 | 511572598168 | 0.8652 | 1 |
| Q20 | 3.320 | 0.010 | 3.330 | 1.119 | 2.722 | 9784369736 | 11219166294 | 1.1466 | 1804 |
| Q21 | 302.080 | 0.310 | 302.390 | 5.786 | 0.113 | 826978597941 | 1204793878971 | 1.4569 | 100 |
| Q22 | 5.540 | 0.010 | 5.550 | 4.885 | 0.000 | 15066017663 | 31826358498 | 2.1125 | 7 |

`/proc` and device I/O counters, buffer/temp/memory counters (`cubrid statdump -c` before and after), NUMA page distribution before and after every block, plan estimated rows (`SET OPTIMIZATION LEVEL 514`) and actual rows (`SET TRACE ON` / `SHOW TRACE`) are in the per-query raw directory and indexed by `raw-manifest.json`.

## Correctness reference captured from the base binary

Section 6-b's canonical result set was captured from the base binary for every query, at the cheapest correct moment. ORDER BY queries keep the exact ordered sequence; the rest are canonically sorted with duplicate multiplicity preserved (never converted to a set); decimals keep their raw text so value and scale are both exact. A later patched build is compared against these hashes.

| Query | ordered | rows | canonical sha256 |
|---|---|---:|---|
| Q01 | yes (exact sequence) | 4 | `8864b84184ab4921c1835277449969c67bea635b9ce6a77068791d80004f67e1` |
| Q02 | yes (exact sequence) | 100 | `bfc2cec706b7b4cb91ed450a188cb5b8e951f3d6839bcd4593e63bacb10b1c25` |
| Q03 | yes (exact sequence) | 10 | `791d565ca8a37442c9c113fcfbc5c371b501d4a8e296cba9f9d78d5f5e1a42ad` |
| Q04 | yes (exact sequence) | 5 | `7cace54b1bdf59caad749fc0b31bd1e345a859dc851c36cfebc96f2e46eb8d24` |
| Q05 | yes (exact sequence) | 5 | `550277556015f5ebf3aa23c17d707fb2e85e21b4136b55f5b73d9c5b5f2c2814` |
| Q06 | no (canonical sort) | 1 | `085140a4231b076ae984bfc445b85a8b4b0deb0c4315eb893f354cf768752734` |
| Q07 | yes (exact sequence) | 4 | `9b3738a8e298e698d21bc224be5e4f9bb7d3047113e2141b77eda2c502c37fd8` |
| Q08 | yes (exact sequence) | 2 | `9c0eaa701ea56b6cc8dfaa600a4e857ab1cfad690b931e94d21a80b0545ad346` |
| Q09 | yes (exact sequence) | 175 | `4ad1c6b5af998892b5fa5228c3c1353f5bc83945b1c0c226f3730ba75a3de5df` |
| Q10 | yes (exact sequence) | 20 | `32cf85a4ecd039347163966debb182d6fcbecc0d7782b8547eea16c1dec4a57d` |
| Q11 | yes (exact sequence) | 8685 | `ef8eaa6f1acc567ff5108c6e5c0b3db08bb29b8d3e7e36f494579dd273861ef2` |
| Q12 | yes (exact sequence) | 2 | `dad168ef75b7ed2f24b6adcdab4f6d31ee0451e36ac4d156aad08b036ee8070e` |
| Q13 | yes (exact sequence) | 46 | `1d04d0a9582739940c58c185d5aedf05bb70f7446ce2db95173ad186af09d4a3` |
| Q14 | no (canonical sort) | 1 | `a31ef3fe6b1b24182f7eb9a87ae9f05da121180aa555e65bf9f49be49ace0708` |
| Q15 | yes (exact sequence) | 1 | `1da7b5661cefc57f59b96efbc6cfba895fe84f15a559f6dd6d9fc05fb96c82e5` |
| Q16 | yes (exact sequence) | 27840 | `be1e33efe60d42611b431af33a9a2b98c0cd17866068c58f2138eb0750500a7a` |
| Q17 | no (canonical sort) | 1 | `ca3fe8d0e6f459a2e15466ab0d799eb5a30efff17456a77a42d39e8749c1fdf5` |
| Q18 | yes (exact sequence) | 100 | `5e85531cb587d4fc0e02522f64105b63733ae206ba3ec03c177aef7b734ff0dc` |
| Q19 | no (canonical sort) | 1 | `9f58bd0331b4048c0c8830ae415e993916c8097e662b4eb3adde5680fdc82c62` |
| Q20 | yes (exact sequence) | 1804 | `d0e2d0f7b87c3038e9ed2859817c44fac28b05b26cfd88380197245d6140538f` |
| Q21 | yes (exact sequence) | 100 | `640c836179d657570c6ba0a7e1901ba38a1cc534a011c11bafafc0ee91d7cf1c` |
| Q22 | yes (exact sequence) | 7 | `6a92ffce66c3dbfddf7b1c2351f89fe0a95774178a1dd220fa7af466579413b9` |

## Raw evidence

| Query | path | blocks |
|---|---|---:|
| Q01 | `/data/tpch-sspq/tpch-sspq-impl-r1-20260803/raw/Q01` | 6 |
| Q02 | `/data/tpch-sspq/tpch-sspq-impl-r1-20260803/raw/Q02` | 6 |
| Q03 | `/data/tpch-sspq/tpch-sspq-impl-r1-20260803/raw/Q03` | 6 |
| Q04 | `/data/tpch-sspq/tpch-sspq-impl-r1-20260803/raw/Q04` | 6 |
| Q05 | `/data/tpch-sspq/tpch-sspq-impl-r1-20260803/raw/Q05` | 6 |
| Q06 | `/data/tpch-sspq/tpch-sspq-impl-r1-20260803/raw/Q06` | 6 |
| Q07 | `/data/tpch-sspq/tpch-sspq-impl-r1-20260803/raw/Q07` | 6 |
| Q08 | `/data/tpch-sspq/tpch-sspq-impl-r1-20260803/raw/Q08` | 6 |
| Q09 | `/data/tpch-sspq/tpch-sspq-impl-r1-20260803/raw/Q09` | 5 |
| Q10 | `/data/tpch-sspq/tpch-sspq-impl-r1-20260803/raw/Q10` | 6 |
| Q11 | `/data/tpch-sspq/tpch-sspq-impl-r1-20260803/raw/Q11` | 6 |
| Q12 | `/data/tpch-sspq/tpch-sspq-impl-r1-20260803/raw/Q12` | 6 |
| Q13 | `/data/tpch-sspq/tpch-sspq-impl-r1-20260803/raw/Q13` | 6 |
| Q14 | `/data/tpch-sspq/tpch-sspq-impl-r1-20260803/raw/Q14` | 6 |
| Q15 | `/data/tpch-sspq/tpch-sspq-impl-r1-20260803/raw/Q15` | 6 |
| Q16 | `/data/tpch-sspq/tpch-sspq-impl-r1-20260803/raw/Q16` | 6 |
| Q17 | `/data/tpch-sspq/tpch-sspq-impl-r1-20260803/raw/Q17` | 6 |
| Q18 | `/data/tpch-sspq/tpch-sspq-impl-r1-20260803/raw/Q18` | 6 |
| Q19 | `/data/tpch-sspq/tpch-sspq-impl-r1-20260803/raw/Q19` | 6 |
| Q20 | `/data/tpch-sspq/tpch-sspq-impl-r1-20260803/raw/Q20` | 6 |
| Q21 | `/data/tpch-sspq/tpch-sspq-impl-r1-20260803/raw/Q21` | 6 |
| Q22 | `/data/tpch-sspq/tpch-sspq-impl-r1-20260803/raw/Q22` | 6 |

Hashes, byte sizes and producing stage for every artifact are in `tpch-sspq/impl/raw-manifest.json`.

