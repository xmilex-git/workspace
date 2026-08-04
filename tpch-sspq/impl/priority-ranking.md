# Phase 1B priority ranking — campaign `tpch-sspq-impl-r1-20260803`

Generated 2026-08-04T16:39:50Z. Pinned norm `tpch-sspq/IMPL-SSOT.md` commit `eccdd1ae58cd733ed3121585146d68b9ae54a73f`, blob `15b42ddca521444fa54b34b0fa8477ed2df643f6` (AMEND-A..G).

**Phase gate.** This document is a Phase 1 deliverable. Phase 2 — writing any engine code — MUST NOT begin until the user has explicitly approved this ranking and the resulting candidate queue. There is no implicit promotion from Phase 1 to Phase 2.

---

## ⛔ STOP-AND-REPORT — the restart-variance combination rule is a user decision

**IMPL-SSOT section 6-d-1 escalation, section 11-a.** The six calibration points support **neither** a single pooled factor **nor** a defensible wall-magnitude-dependent one. Section 6-d-1 is explicit that in this case the worker reports the calibration data and asks, and **MUST NOT pick a factor to keep the sweep moving**.

Nothing here was picked for convenience. So that the rest of Phase 1 could still be produced and read, the corrected MDE below was computed under the **most conservative** of the six measured factors (**15.3158x**). That choice cannot under-correct, and under-correction is the single failure mode section 6-d-1 exists to prevent — an MDE smaller than real A/B noise causes **false accepts**.

**Consequence for reading this document:** **no `UNPROVABLE_ON_THIS_HOST` verdict is asserted for any query whose MDE depends on the undecided factor.** Every such determination is **WITHHELD** until the rule is chosen, and what each of the three candidate rules would give is published beside it. Rows whose outcome is the same under all three are marked `rule-invariant`, so the pending decision cannot move them; the remaining rows are marked as depending on the decision, and those are the ones the choice actually settles. Corrected MDE figures for those queries are provisional and illustrative only — they exist so the table can be read, not so a verdict can be drawn from them.

**Q01–Q06 are the exception, and their verdicts ARE asserted.** Section 6-d-1 step 6 uses their DIRECTLY MEASURED restart-regime paired CV, so no combination rule enters their MDE and the pending decision cannot change them. Their rows therefore carry real `resolvable` / `unprovable` verdicts rather than a withholding, and those are campaign determinations under section 6-d, not provisional ones.

### Why neither rule fits

- NEITHER a single pooled factor NOR a defensible wall-magnitude-dependent factor fits the six calibration points.
- (a) The wall-dependent fit is not robust. Full-sample pearson r = 0.7150 clears the declared 0.70 threshold by 0.015 and the residual reduction 30.1% clears the declared 30% threshold by 0.1 points, but leave-one-out shows the association is carried by individual points: dropping Q01 gives r=+0.3928, Q04 gives r=+0.6878 (all six: Q01:+0.3928, Q02:+0.7189, Q03:+0.7833, Q04:+0.6878, Q05:+0.8027, Q06:+0.7754).
- (b) A single pooled factor is out of range: the clamped factors span 1.4039..15.3158, a ratio of 10.91, beyond the declared stop ratio of 10.0.
- (c) The model is contradicted directly by near-equal walls: Q03 at 4.539s has factor 1.452 while Q06 at 3.846s has factor 6.424 — walls differ 1.18x, factors differ 4.43x.
- (d) Mechanism for the instability, so this is not left as an unexplained anomaly: the ratio's DENOMINATOR is at the resolution floor for the two queries carrying the extreme factors. Fast-regime paired CV is 0.000972 for Q01 and 0.001123 for Q06, each estimated from only 3 pairs. A ratio whose denominator is a 3-pair estimate of a ~0.1% dispersion is not a stable quantity, and that is exactly where the 15.3x and 6.4x factors come from.

Leave-one-out pearson r on ln(inflation) vs ln(wall) — the association is carried by individual points, which is what a genuine relationship at n=6 must not do:

| dropped query | r on the remaining five |
|---|---:|
| Q01 | +0.3928 **fails the 0.70 threshold** |
| Q02 | +0.7189 |
| Q03 | +0.7833 |
| Q04 | +0.6878 **fails the 0.70 threshold** |
| Q05 | +0.8027 |
| Q06 | +0.7754 |

### The three candidate rules, side by side

| Rule | Value / form | Status |
|---|---|---|
| `max_observed_factor` | 15.3158x | cannot under-correct; cannot cause a false accept |
| `single_pooled_geometric_mean` | 2.9598x (geometric mean) | factor spread ratio 10.91; within the declared stop ratio of 10: **False** |
| `wall_magnitude_dependent` | inflation(wall) = max(1, exp(0.4552 + 0.4637·ln wall)) | full-sample r=0.7150, residual cut 30.1%, robust under leave-one-out: **False** |

A fourth option exists and is not a rule choice: **collect more calibration blocks**. The instability's mechanism is that the ratio's denominator — the fast-regime paired CV — is a 3-pair estimate of a ~0.1% dispersion for the two queries carrying the extreme factors, so more blocks per query would shrink the denominator's uncertainty directly rather than model around it.

Per-query corrected MDE under each candidate rule is tabulated in the **Expected effect against the CORRECTED MDE** section below.

## Inputs (section 2-b-1 requires all three)

| # | Input | Role |
|---|---|---|
| 1 | `tpch-sspq/impl/feasibility-assessment.json` | frozen Phase 1B feasibility half; immutable |
| 2 | `tpch-sspq/impl/fresh-baseline.json` | the Phase 1A fresh baseline; the source of every `fresh_base_median_q` |
| 3 | `tpch-sspq/impl/triage-adjustments.json` | the user-led triage's corrections to benefit inputs, lanes and pre-implementation gates |

Supporting: `tpch-sspq/impl/restart-variance-calibration.json` (the section 6-d-1 corrected MDE this ranking flags against), `tpch-sspq/impl/benefit-inputs.json` (the per-term judgment, separated from the arithmetic), `tpch-sspq/impl/implementation-results.json` (this campaign's own recorded verdicts), `tpch-sspq/impl/diagnosis/Q15-parallel-non-arming.md` (this run's diagnosis, which changes two of IMP-015's target-query terms).

A ranking produced without reading input 3 is invalid (section 2-b-1). The three inputs are independent: `triage-adjustments.json` does not modify `feasibility-assessment.json`, which remains immutable.

---

## Methodology, reproduced verbatim from the pinned IMPL-SSOT section 2

> Reproduced byte for byte by `render_ranking_md.py`, which extracts section 2 from the pinned file at render time. It is not paraphrased and cannot drift from the pin.

## 2. Candidate scoring methodology

Phase 1 scores every registry candidate and produces one ranking. The methodology below
is normative and MUST be reproduced verbatim in `tpch-sspq/impl/priority-ranking.md`.

### 2-a. Implementation Feasibility Score (0–100, higher = easier)

Weighted sum of four components, each scored 0–100 on the "easier is higher" scale:

| Component | Weight |
|---|---|
| LOC / diff scope | 40% |
| Files, subsystems and serialization blast radius | 20% |
| Correctness and concurrency risk | 25% |
| Test and dependency burden | 15% |

Rules:

- LOC scoring MUST use the **HIGH** estimate of the LOC band, never the optimistic or
  the likely one. Optimism in the estimate is not a feasibility advantage.
- **KLOC alone never decides difficulty.** A 30-line change to XASL serialization or to
  a lock protocol is harder than a 400-line change confined to one executor file. The
  blast-radius and correctness-risk components exist precisely to override raw size, and
  the written rationale MUST say which component dominated.
- The blast-radius component MUST explicitly consider: number of files, number of
  subsystems, whether XASL / wire format / persistent format / catalog format is
  touched, and whether client-server compatibility is affected.
- The correctness/concurrency component MUST consider MVCC, latching, locking, worker
  lifecycle and memory ownership.
- The test/dependency component MUST consider whether an existing regression test covers
  the path, whether a new test must be authored, and whether a predecessor candidate is
  required first.

### 2-b. Evidence-adjusted Benefit Score (0–100)

Evidence weights, applied per affected query:

| Evidence level | Weight |
|---|---|
| Direct A/B | 1.00 |
| Lower bound | 0.90 |
| Attribution | 0.70 |
| Projection | 0.50 |
| Upper bound | 0.35 |
| Unmeasured | 0.00 |

Expected saving:

```text
expected_saved_seconds = Σ_q ( fresh_base_median_q
                             × conservative_effect_fraction_q
                             × evidence_weight_q )
```

Rules, all mandatory:

- `fresh_base_median_q` is this campaign's **fresh** Phase 1A CUBRID baseline median for
  query `q` (section 3). A previous campaign's absolute time MUST NOT be substituted.
- For a **direct A/B** candidate, `conservative_effect_fraction_q` is the observed effect
  rate from that A/B — not a rounded-up or extrapolated one.
- For a candidate whose effect is stated as a **range**, the conservative **lower bound**
  of the range MUST be used.
- A whole profile band MUST NOT be automatically treated as removable. If the evidence is
  "this band costs X", the removable fraction MUST be argued and stated; absent an
  argument, the band contributes its measured *reduction*, not its total.
- A `q_relation` with no numeric basis contributes **0 seconds**. It is still listed, so
  the reader can see it, but it adds nothing.
- Overlapping candidates' effects MUST NOT be summed. See section 4 for clusters.
- Every non-zero term MUST cite the raw evidence pointer that produced it.

Normalization:

```text
benefit_score = 100 × percentile_rank( log1p(expected_saved_seconds) )
```

over the scored candidate set. The `log1p` compression plus percentile ranking is chosen
so a single outlier candidate cannot dominate the ranking by arithmetic alone. Candidates
with `expected_saved_seconds = 0` all receive the bottom rank and MUST be marked
`NO_NUMERIC_BASIS`.

#### 2-b-1. Triage adjustments are a required input (`AMEND-F`)

Phase 1B benefit scoring has **three** required inputs, not two:

1. `tpch-sspq/impl/feasibility-assessment.json` — the frozen Phase 1B feasibility input;
2. the Phase 1A fresh baseline (section 3) — the source of every `fresh_base_median_q`;
3. `tpch-sspq/impl/triage-adjustments.json` — the user-led triage's corrections to the
   benefit inputs, lanes and pre-implementation gates.

A ranking produced without reading input 3 is invalid. The three inputs are independent:
`triage-adjustments.json` does **not** modify `feasibility-assessment.json`, which remains
immutable, and where the two disagree the disagreement is recorded in
`triage-adjustments.json` and escalated (section 11-a) — it is never resolved silently by
the ranking tool.

**Blocked benefit statuses.** A candidate marked `BENEFIT_PENDING_DENOMINATOR` or
`BENEFIT_CONFOUNDED` in `triage-adjustments.json` MUST NOT receive a numeric benefit
score and MUST NOT receive a rank position. It is listed with its status and its blocker
in the ranking table's eligibility column, and it is excluded from the percentile-rank
population so it cannot shift other candidates' scores. This is distinct from
`NO_NUMERIC_BASIS`, which means *no evidence*; these two statuses mean *evidence exists
but is not yet usable*, and neither is a rejection.

**Profile bands, made operational.** The rule above — a whole profile band MUST NOT be
automatically treated as removable — has two concrete instances, and the ranking MUST
apply it in exactly these terms:

- `IMP-001`: the profile band is **62.35%**, but an internal prototype measured an actual
  effect of **≈13%**. The 62.35% band is therefore refuted as a removable effect. The
  13% figure is nevertheless unusable until its denominator (wall time vs CPU time) is
  confirmed, which is why the candidate is `BENEFIT_PENDING_DENOMINATOR` rather than
  simply re-scored at 13%.
- `IMP-013`: the profile band is **32.7%**, but the realistic target is **0.47 core-s**.
  The benefit MUST be computed from the 0.47 core-s target, never from the band's upper
  bound — which is also the section 2-b range rule (conservative lower bound).

Citing these two cases is what makes the band rule operational rather than abstract: a
band figure that appears in the registry is a *cost observation*, and it becomes an
*effect* only when a measurement or a stated, argued removable fraction says so.

### 2-c. Total score and tie-breaks

```text
Total = 0.50 × Feasibility + 0.50 × Benefit
```

Ties in `Total` are broken in this exact order:

1. higher evidence level (Direct A/B > Lower bound > Attribution > Projection > Upper
   bound > Unmeasured);
2. lower correctness risk;
3. is a predecessor / enabler of another candidate;
4. smaller high-LOC estimate.

### 2-d. Sensitivity and ranking stability

The ranking MUST be recomputed with every evidence weight perturbed by ±0.15 (clamped to
`[0, 1]`), in both the pessimistic and the optimistic direction. If the identity or the
order of the top 5 changes materially under either perturbation, the ranking document
MUST carry the marker `RANKING_UNSTABLE`, name which candidates swapped, and state that
the queue order in that region is not evidence-supported. `RANKING_UNSTABLE` does not
block Phase 1 completion; it blocks silent reliance on a fragile order.

### 2-e. Required ranking table columns

`tpch-sspq/impl/priority-ranking.md` MUST carry a table with exactly these columns, and
`priority-ranking.json` MUST carry the same fields machine-readably:

1. canonical IMP ID (`IMP-NNN`, from the frozen registry);
2. lane (section 4);
3. fresh affected-query baseline (per-query medians used, from Phase 1A);
4. expected effect + evidence level;
5. expected saved seconds;
6. LOC estimate low / likely / high;
7. files and subsystems touched;
8. difficulty and risk rationale (prose, one to three sentences);
9. feasibility score / benefit score / total score;
10. predecessor / alternative / containment relations;
11. eligibility and blocker (eligible, or blocked with the exact blocker);
12. one-line ranking rationale.

---

## Methodology decisions this ranking had to make

Section 2-b tells the ranking to argue a removable fraction rather than assume one, and AMEND-F makes that operational by naming IMP-001 and IMP-013. Applying it consistently across all 31 candidates forced five decisions. They are recorded here because each one changes numbers.

### MD-1 — A CPU-side figure is never substituted into a wall denominator.

Section 2-b multiplies fresh_base_median_q, which is a WALL median (section 3-c). AMEND-F's operational reading of the band rule blocks IMP-001 for exactly this reason — 'applying a CPU-side figure would overstate the benefit, possibly by a large factor'. Consistency requires the same treatment everywhere, not only for IMP-001. A term whose only quantified evidence is a core-second band, with no measured active-unit count U and no stated wall conversion, therefore has NO WALL BASIS and contributes 0 seconds. It is still listed (section 2-b: 'A q_relation with no numeric basis contributes 0 seconds. It is still listed, so the reader can see it, but it adds nothing'). This introduces no new status vocabulary — it applies the SSOT's own NO_NUMERIC_BASIS category at term granularity.

*Consequence:* Several profile-attribution candidates score 0. That is the honest outcome of a wall-denominated formula meeting CPU-denominated evidence, and it is visible rather than hidden.

### MD-2 — Where the registry itself supplies the CPU->wall conversion, the conversion is used and cited.

Section 2-b requires the removable fraction to be argued and stated. The registry argues it for some candidates (IMP-012 'projects 0.998 s', IMP-013 'about 0.12 s of wall', IMP-019 'about 0.220 s of the 4.039 s median at the measured U=5.89315', IMP-031 '2.02% of CUBRID's CPU and 2.05% of its wall'). Those are stated wall conversions, not inferences of ours.

*Q22 equivalence:* For Q22 specifically, IMP-031 measured the same mechanism at 2.02% of CPU and 2.05% of wall on the same statement, i.e. a CPU share and a wall share coincide within 1.5% relative on this query. IMP-029 and IMP-030 are Q22 core-second shares of the SAME 5.453622 core-s statement, so that measured equivalence is the stated argument that licenses their conversion. It is cited per term and is not generalized to any other query.

### MD-3 — An effect measured only outside the WARM-converged regime is not removable from a WARM baseline — but whether a given cost is outside that regime is a question for THIS campaign's baseline, not for the previous campaign's.

Phase 1A proves WARM convergence before measuring (section 3-c step 3), so it is tempting to assume any first-touch cost is absent from fresh_base_median_q. That reasoning was applied to IMP-018 in the first draft of this file and it was WRONG. The WARM gate proves STATEMENT-level convergence within one connection; it cannot converge a PER-CONNECTION structure, and Phase 1A opens one direct `csql -C` connection per block (headline_run.py:189, connection_mode `single-connection-four-statements`). A per-connection cost is therefore re-paid by every block and IS in the baseline.

*Consequence:* The correction is not theoretical — this campaign's own baseline settled it. See the IMP-018 Q11 term, where three independent observations show the cost present, and the Q11 baseline caveat it forces.

### MD-4 — A PostgreSQL figure may be used as an achievable FLOOR in a bound argument, never as a denominator of an effect.

Section 3-d forbids expressing a patch's effect as a ratio against PostgreSQL, and makes PostgreSQL a source contrast that motivates a change direction. IMP-009 and IMP-023 both argue their removable fraction by naming PostgreSQL's own measured value on the same plan shape as the floor. That is a stated removable-fraction argument (which section 2-b demands) and the resulting term is CUBRID-over-CUBRID. Every such term is marked postgresql_floor_argument=true and carries the Upper bound weight.

### MD-5 — A defect measured on a synthetic probe is not transferred to a named query without a stated transfer argument.

IMP-021's 1.5617x is measured on an isolated 1,500,000-group aggregate constructed to expose the defect, not on Q13. The registry supplies no quantified transfer to Q13's wall. Section 2-b's 'no numeric basis contributes 0 seconds' therefore applies to the Q13 term.

---

## The ranking (section 2-e columns, exactly)

Rows appear in rank order. Section 2-e fixes twelve columns and says "exactly these columns", so the ordinal is not a thirteenth column here — explicit queue positions are in the **Candidate queue** table below.

| IMP ID | Lane | Fresh affected-query baseline (s) | Expected effect + evidence level | Expected saved seconds | LOC low/likely/high | Files and subsystems touched | Difficulty and risk rationale | Feasibility / Benefit / Total | Predecessor / alternative / containment | Eligibility and blocker | Ranking rationale |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `IMP-015` | performance | Q10 7.0440; Q11 3.2285; Q15 10.0245; Q18 37.4815 | Q10 23.877% (direct_ab w=1) | 1.6819 | 5/20/60 | files: src/storage/external_sort.c, src/storage/external_sort.h, src/query/query_executor.c; subsystems: sort, executor / group by | I read sort_check_parallelism()'s SORT_GROUP_BY branch at external_sort.c:5228-5246: 'if (px == NULL \|\| px->hash_eligible) return 1;' is an unconditional early return that skips a fully-implemented parallel path used by the sibling branches. The smallest genuinely-performance-bearing change in the set. | 73 / 80 / 76.5 | — / stop marking the query hash-eligible when the optimizer's group estimate cannot fit max_agg_hash_size (recorded as the cheaper mitigation IF IMP-016 lands first); IMP-016 (fixing either recovers Q10's measured 1.313675x; IMP-015 is the measured route) / IMP-016; IMP-021 (removes the sort IMP-015 parallelizes; not additive) | eligible — ALREADY IMPLEMENTED AND MEASURED IN THIS CAMPAIGN — implementation-results.json records verdict 'accepted (provisional)' on branch impl/tpch-sspq-impl-r1-20260803/IMP-015-gby-sort-runtime-px, Notion synced. It is therefore not a queue candidate; it is listed with its recorded verdict. | Already implemented and measured in this campaign — verdict 'accepted (provisional)'. Its scored Q10 benefit stands, but this run's diagnosis removes Q15 from its target set and the IMP-032 probe removes Q18, so its proven applicability narrows to group-by whose leader actually runs the hash pass. |
| `IMP-009` | performance | Q05 10.3355; Q11 3.2285; Q16 2.9180; Q20 3.0000; Q21 52.5865 | Q05 81.070% (upper_bound w=0.35) | 2.9326 | 20/60/150 | files: src/query/parallel/px_parallel.cpp, src/query/parallel/px_parallel.hpp, src/optimizer/plan_generation.c; subsystems: parallel query, query optimizer (degree annotation) | I read compute_parallel_degree() in full at the pin: the SUBQUERY case is a literal 'auto_degree = 1' with a TODO and an explicit 'hint ignored' return. The code change is small and obvious; the risk is entirely in what turning it on exercises. | 57.8 / 88 / 72.9 | IMP-005 / — / IMP-012 (the sibling SCAN branch of the same function compute_parallel_degree) | eligible | Largest scored benefit after the two headline A/Bs: an argued 81% of Q05's wall, discounted to the Upper bound weight because that is exactly what the registry calls it, with PostgreSQL's 5.43 units on the same plan as the achievable floor. Needs IMP-005 first. |
| `IMP-018` | performance | Q11 3.2285; Q14 3.1170 | Q11 58.430% (direct_ab w=1) | 1.8864 | 10/40/120 | files: src/storage/page_buffer.c, src/base/system_parameter.c; subsystems: buffer manager, system parameter | Both ceilings are exactly where the registry says and I read both at the pin. The diff can be two constants — but the pinned document's rule that KLOC never decides difficulty applies: this is a global default governing multi-session fairness, and the evidence base is one serial query. | 60.2 / 84 / 72.1 | — / make num_private_chains dynamically settable so an operator can set it to 0 (rejected: workaround for a wrong default); demote rather than victimize an over-quota private page (structurally cleanest; changes the victim path rather than one expression) / IMP-002 (different premise: IMP-002 is a working set that EXCEEDS the pool, this is one that FITS); IMP-007 (this removes the reads, IMP-007 makes them cheaper); IMP-010 (bypassed vs too small) | eligible — write path — section 11-a stop-and-report BEFORE implementing · BASELINE CAVEAT: Q11's own baseline is regime-ambiguous and this must be carried into any Phase 2 A/B on it. Its six block medians are a monotone TREND, not exchangeable draws, so (a) its paired CV 0.005940 measures the trend rather than a noise floor and understates the true dispersion, and (b) its median depends on how many connections the block sequence made. Section 6-c's B->P->P->B restarts per block, which resets the per-connection state every block, so a Phase 2 A/B on Q11 will not reproduce this trend and its noise floor must be re-derived under that regime rather than taken from here. | Corrected upward after this campaign's own baseline refuted the first-draft reasoning: Q11's fresh median (3.2285 s, +140.57% vs the previous campaign) sits in the amplified per-connection regime, and its block medians decay monotonically -16.10% across the six connections — the only query in the sweep that does. The 2.64x direct A/B therefore applies to a cost this baseline really carries, making it one of the larger honestly wall-measured savings in the set. Write-path candidate, so section 11-a stop-and-report before implementing. |
| `IMP-014` | performance | Q09 10.5780 | Q09 35.171% (direct_ab w=1) | 3.7204 | 80/200/450 | files: src/optimizer/query_planner.c, src/optimizer/query_graph.c, src/optimizer/query_graph.h; subsystems: query optimizer / cardinality estimation, schema constraint lookup (read-only) | planner_visit_node() at query_planner.c:7927-7936 really does multiply per-term selectivities with only a 1/cardinality floor, and the FK-coverage predicate already exists at query_graph.c:9955 but is called from exactly one place (:9927, sort/limit node exclusion). The change is to reuse an existing predicate on a new path. | 52 / 92 / 72 | — / IMP-011 (the other candidate that changes Q09's join-method selection; the registry rejects IMP-011 as Q09's deciding term); IMP-003 (rejected as Q09's deciding term by measurement) / IMP-011 (IMP-014 supplies what IMP-011 costs; Q09 effects overlap completely) | eligible — section 5-e upstream scope-check gate | Clean direct A/B on Q09's wall (1.5425x, 35.2% saved) that also subsumes IMP-011's Q09 claim; deliberately not generalized, since Q08 is a measured positive control where the same forcing makes CUBRID 1.5123x slower. Upstream scope gate applies. |
| `IMP-027` | performance | Q19 43.9640 | Q19 99.177% (direct_ab w=1) | 43.6022 | 150/350/800 | files: src/optimizer/query_graph.c, src/optimizer/query_graph.h, src/optimizer/query_planner.c, src/parser/cnf.c; subsystems: query optimizer / term analysis, parser / CNF transformation | I confirmed the two anchors at the pin: cnf.c:988 switches to OR-compact mode above a score of 100, and query_graph.c:2536-2544 classifies a term purely by bitset_cardinality, so a 2-relation OR term can only ever be a join term. The fix is a new optimizer pass with a soundness proof obligation, not a parameter change. | 41 / 100 / 70.5 | — / widen the count_and_or limit at cnf.c:988 (rejected: full distribution is exponential, 8^3 = 512 for Q19) / IMP-007 (amplified by, not overlapping); IMP-013 (amplified by) | eligible | The single largest measured effect in the whole registry — 121.4x on Q19's wall, 99.2% of it removable, by same-engine controlled A/B with three gated blocks per configuration and independent COUNT(*) ground truth. Ranks on benefit despite mid-band feasibility. |
| `IMP-003` | performance | Q02 0.3645; Q09 10.5780; Q16 2.9180 | Q02 53.100% (direct_ab w=1) | 0.1935 | 30/80/180 | files: src/optimizer/histogram/histogram_cl.cpp, src/optimizer/query_planner.c; subsystems: query optimizer / statistics | I read histogram_cl.cpp:1474-1560 at the pin: the non-MCV arm really is matched_bucket_hi/bucket_count, i.e. the estimate is the fraction of bucket UPPER BOUNDARIES matching, and the fix is local to that block plus the blend gate. One file, one subsystem, no runtime path. | 67 / 72 / 69.5 | — / promote rank above selectivity in make_pred_from_bitset() (plan_generation.c:1615-1640) / IMP-004 (for Q02) | eligible — section 5-e upstream scope-check gate | Highest-confidence wall-measured optimizer fix in the set: -53.1% of Q02's own wall by direct A/B, one predicate-ordering decision, and it contains IMP-004 for Q02. Gated on the upstream scope check and conflicts with IMP-022 under the one-branch rule. |
| `IMP-029` | performance | Q22 1.1190 | Q22 20.903% (attribution w=0.7) | 0.1637 | 30/90/220 | files: src/query/query_evaluator.c, src/object/set_object.c, src/object/set_object.h; subsystems: executor / predicate evaluation, collection (DB_SET) API | The smallest genuine per-row waste in the set that is not already claimed by a harder candidate: 'for (i = 0; i < set_size (set); i++)' re-calls set_size every iteration and set_get_element materializes and frees a DB_VALUE copy of a compile-time-constant element per row. The hoist alone is a handful of lines. | 63.7 / 68 / 65.85 | — / IMP-008 (complementary, not a substitute: IMP-008 lowers the per-element compare, this removes the per-element materialization) / IMP-020 (shares the per-row DB_VALUE alloc/copy/clear band on Q22; must not be double counted); IMP-025 (sibling membership test on a different path) | eligible | Scored on the conservative lower bound of its recoverable range (20.9% of Q22) at the Attribution weight, converted to wall only on IMP-031's same-statement CPU/wall equivalence. Must not be double counted with IMP-020's shared DB_VALUE band. |
| `IMP-019` | performance | Q12 3.9505; Q17 0.1465 | Q12 5.447% (projection w=0.5) | 0.1076 | 40/100/250 | files: src/optimizer/query_planner.c, src/optimizer/histogram/histogram_cl.cpp, src/optimizer/query_graph.c; subsystems: query optimizer / selectivity estimation | I read qo_comp_selectivity() at query_planner.c:10498-10530: the PC_ATTR/PC_ATTR arm is literally '/* TODO: add histogram selectivity */ break;', so 'success' is never set and DEFAULT_COMP_SELECTIVITY 0.1 is returned. Finding it is trivial; implementing a defensible two-column estimator is not. | 62.5 / 64 / 63.25 | — / IMP-020 (reduce the cost per materialized row rather than the number of predicate evaluations; disjoint bands) / — | eligible — section 5-e upstream scope-check gate | Small but properly wall-converted projection (5.4% of Q12) from measured counts times a measured per-term cost; good feasibility, and the upstream scope gate applies. |
| `IMP-023` | performance | Q16 2.9180 | Q16 25.990% (upper_bound w=0.35) | 0.2654 | 150/400/900 | files: src/query/query_aggregate.cpp, src/query/query_aggregate.hpp, src/xasl/xasl_aggregate.hpp, src/query/list_file.c; subsystems: executor / aggregation, list file, sort, XASL runtime state | I read qdata_process_distinct_or_sort() (query_aggregate.cpp:70-118) and the per-row body at :830-870 at the pin: per group it db_private_allocs a type list and opens a QFILE list, and per row it calls pr_data_writeval_disk_size + db_private_alloc + data_writeval + qfile_add_item_to_list + free. Replacing that means writing a new per-group dedup with its own budget and spill — a substantial new component, not a tweak. | 41.4 / 76 / 58.7 | — / — / IMP-006 (shares qfile_* profile symbols; bands must not be summed); IMP-021 (removes the input this loop consumes; not additive); IMP-015 | eligible — section 5-d hard stop: XASL serialization (section 5-d independent hard stop) | Scored on a genuine wall-seconds serial-phase differential (0.750 s of Q16's 2.886 s) at the Upper bound weight, with PostgreSQL's own 0.291 s as the argued floor. Touches XASL serialization — section 5-d hard stop. |
| `IMP-030` | performance | Q22 1.1190 | Q22 2.310% (direct_ab w=1) | 0.0258 | 20/50/130 | files: src/query/numeric_opfunc.c; subsystems: expression/type (NUMERIC coercion) | The function is exactly as described — stack char buffer, numeric_coerce_num_to_dec_str, atof, pow — with an in-code precision warning and a CUBRIDSUS-2637 TODO. Tiny diff, but it is the engine-wide NUMERIC->double path. | 63.8 / 52 / 57.9 | — / IMP-008 (a domain-specialized NUMERIC/DOUBLE comparator would subsume this band) / — | eligible — acceptance-criterion caveat: feasibility-assessment.json records that the replacement is MORE accurate than the current string round-trip, so 'results unchanged' cannot be this candidate's acceptance criterion. That is an acceptance-design item for its implementation plan, not a benefit adjustment. | Small, clean, cheap: 2.3% of Q22 by paired direct A/B at the range's lower bound, high feasibility. Its acceptance criterion cannot be 'results unchanged' — the replacement is more accurate than the current string round-trip. |
| `IMP-013` | performance | Q08 1.0075; Q09 10.5780; Q10 7.0440; Q11 3.2285; Q13 11.3345; Q15 10.0245; Q19 43.9640; Q20 3.0000; Q21 52.5865; Q22 1.1190 | Q08 10.560% (attribution w=0.7) | 0.0745 | 30/80/200 | files: src/storage/page_buffer.c; subsystems: buffer manager | I read pgbuf_lru_boost_bcb() at :10073-10125: the existing age-based suppression is documented in-file and is implemented in the caller (pgbuf_unlatch_bcb_upon_unfix), so the extension point exists. The diff is small; it sits inside the hottest mutex in the server. | 48.9 / 60 / 54.45 | — / IMP-010 (same subsystem: where new pages land, vs whether the list is touched on a hit) / IMP-002; IMP-007 | eligible — write path — section 11-a stop-and-report BEFORE implementing · triage: BENEFIT_BASIS_CORRECTED — the benefit MUST be computed from the realistic 0.47 core-s target, never from the 32.7% band upper bound (AMEND-F section 2-b-1, cited by name). | Scored strictly on the triage-mandated 0.47 core-s target with the registry's own wall conversion (0.12 s of Q08), never on the 32.7% band. Write-path candidate, so stop-and-report before implementing. |
| `IMP-012` | performance | Q08 1.0075; Q17 0.1465; Q19 43.9640 | Q08 12.150% (projection w=0.5) | 0.0612 | 80/200/450 | files: src/query/parallel/px_parallel.cpp, src/query/parallel/px_scan/px_scan.cpp, src/optimizer/plan_generation.c, src/base/system_parameter.c; subsystems: parallel query, query optimizer (degree annotation) | compute_parallel_degree()'s SCAN ladder (auto_degree = 63 - clzll(num_pages/threshold) + 2, then MIN with parallelism) is exactly as described and is ~10 lines; the coordinator change in px_scan.cpp is the larger and riskier half. | 48 / 56 / 52 | IMP-005 / raise parallel_scan_page_threshold from its hidden 2048 default — rejected by the registry as too coarse / IMP-009 (the SUBQUERY branch of the same function) | eligible — triage: PRIORITY_DISAGREEMENT — the 0.138 s projection does not support the registry's P0. That is a priority note, not a benefit block; the discovery Priority field is left untouched. | Modest but honestly wall-converted projection (0.1215 of Q08) at good feasibility; the triage's PRIORITY_DISAGREEMENT stands — a 0.138 s projection does not support the registry's P0. Needs IMP-005 first and shares a 176-line file with it. |
| `IMP-031` | performance | Q22 1.1190 | Q22 2.050% (direct_ab w=1) | 0.0229 | 40/120/300 | files: src/parser/xasl_generation.c, src/optimizer/rewriter/query_rewrite.c, src/optimizer/query_graph.c; subsystems: XASL generation, query rewriter, query optimizer / index selection | I read xasl_generation.c:1683-1699 at the pin: PT_EXISTS is compiled with UNBOX_AS_TABLE and then flagged XASL_NEED_SINGLE_TUPLE_SCAN, so a whole tuple of the subquery select list must be produced. The covering-index machinery already exists (qo_is_coverage_index, query_graph.c:6933); only the projection makes the query ineligible for it. | 54.4 / 48 / 51.2 | — / — / IMP-028 (contains this: IMP-028's Q22 anti-join band contains this candidate's 0.11004 core-s; if IMP-028 ever landed this becomes moot — do not implement both, and do not sum them) | eligible | Smallest scored benefit but the tightest evidence: 2.05% of Q22's wall stated directly by the registry, measured, and explicitly a lower bound. Contained by IMP-028, which is not queued, so it stands for now. |
| `IMP-022` | performance | Q16 2.9180 | no non-zero term | 0.0000 | 20/60/150 | files: src/optimizer/histogram/histogram_cl.cpp, src/optimizer/query_planner.c; subsystems: query optimizer / statistics | I read pattern_heuristic_selectivity() at histogram_cl.cpp:1300-1345 at the pin. The prefix-skip loop and the 'if (pos >= pattern.size()) return 1.0;' early return are exactly as reported, and the fix is to score the prefix when the caller is the negated form. Small, local, and the correctness obligation is an estimate, not a row. | 68.8 / 0 / 34.4 | — / raise the [0.0001,0.9999] clamp (rejected: changes the number, not the cause); rewrite NOT LIKE into NOT(range) (rejected: larger blast radius for the same outcome) / IMP-003 (sibling arm of the same estimator; effects never additive on a single term); IMP-004 (plan-time estimate vs runtime matcher cost; not additive) | eligible — section 5-e upstream scope-check gate · NO_NUMERIC_BASIS | Measured zero seconds on Q16 and the registry says so plainly; it is a latent, provably pattern-independent plan-space defect whose value is future-proofing, not this workload. Conflicts with IMP-003 under the one-branch rule. |
| `IMP-016` | performance | Q10 7.0440; Q11 3.2285; Q18 37.4815 | no non-zero term | 0.0000 | 10/40/100 | files: src/query/query_executor.c; subsystems: executor / hash aggregation | Confirmed at the pin: context->group_count++ at :4740 on every insert, and the eviction loop at :4800-4836 adjusts hash_size but never group_count, so an evicted-and-remet group is counted twice in the selectivity ratio computed at :4839-4842. | 67 / 0 / 33.5 | IMP-017 / raise max_agg_hash_size so eviction never happens (rejected: blocked by IMP-017); delete the very-high-selectivity abort entirely (rejected: the guard protects a real case); IMP-015 (fixing either recovers Q10's 1.313675x) / IMP-015 (IMP-016 puts the executor into HS_REJECT_ALL; IMP-015 turns that into a lost parallel sort) | eligible — NO_NUMERIC_BASIS | Ranked but unscored: it is the alternative arm of IMP-015 on Q10 and IMP-015 already landed, so its Q10 saving is SUPPRESSED_OVERLAP. Its remaining independent figure is a 1.32% CPU profile share. Needs IMP-017 to become testable. |
| `IMP-004` | performance | Q02 0.3645; Q13 11.3345; Q16 2.9180 | no non-zero term | 0.0000 | 60/120/260 | files: src/base/language_support.c, src/query/string_opfunc.c; subsystems: collation / i18n, expression/type (string) | The defect is real and localized (per-character intl_utf8_to_cp on BOTH operands plus two weight-table lookups per position), but the fast path needs a collation-eligibility gate that must be proven, and the risk component dominates the small LOC. | 58 / 0 / 29 | — / IMP-003 / — | eligible — NO_NUMERIC_BASIS | Real per-row LIKE cost (8.64x-9.75x) but zero scored benefit here: its Q02 figure is a CPU band with no wall conversion, and IMP-003 already takes Q02's measured wall as the alternative-cluster winner. |
| `IMP-021` | performance | Q13 11.3345 | no non-zero term | 0.0000 | 30/90/220 | files: src/optimizer/query_planner.c, src/query/query_executor.c, src/parser/xasl_generation.c; subsystems: query optimizer / plan selection, executor / group by | I read query_planner.c:6006-6019 at the pin and the asymmetry is exactly as described: the ORDER BY arm has a pre-top-rooted candidate predicate ('plan->top_rooted ? ... : qo_plan_is_orderby_skip_candidate (plan)') and the GROUP BY arm immediately below it has none, so it tests a flag that qo_top_plan_new() has not written yet. | 54.8 / 0 / 27.4 | — / — / IMP-015 (removes the sort IMP-015 parallelizes; not additive); IMP-023 (removes the input IMP-023's per-group loop consumes; not additive) | eligible — NO_NUMERIC_BASIS | Ranked but unscored: its 1.5617x is measured on a synthetic 1.5M-group aggregate, not on Q13, and no transfer is quantified. Its real significance is as a sequencing hazard — it removes the very sort IMP-015 was measured parallelizing. |
| `IMP-010` | performance | Q06 3.8455; Q12 3.9505; Q13 11.3345 | no non-zero term | 0.0000 | 20/60/150 | files: src/query/parallel/px_scan/px_scan_task.cpp, src/thread/thread_entry_task.cpp, src/storage/page_buffer.c, src/thread/thread_entry.hpp; subsystems: parallel query / worker lifecycle, buffer manager, thread pool | I verified the loss point: thread_entry_task.cpp retire/recycle set private_lru_index = -1, px_scan_task.cpp propagates only the parent thread entry, and page_buffer.c:6902 branches on thread_private_lru_index != -1. The diff is tiny; the concurrency consequence of undoing that clearing is not. | 49.5 / 0 / 24.75 | — / a generic scan-resistance ring handed to pgbuf_fix per scan (the PostgreSQL freelist.c:426 design) — recorded, explicitly not costed / IMP-002 (this re-scopes IMP-002's claim to the parallel path); IMP-007 (composes multiplicatively) | eligible — write path — section 11-a stop-and-report BEFORE implementing · NO_NUMERIC_BASIS | Ranked but unscored: the measured quantity is physical page reads (458,209 -> 158,930) and the core-second consequence is explicitly conditional on the kernel band scaling with bytes. Also a write-path candidate, so section 11-a stop-and-report applies before implementing. |
| `IMP-008` | performance | Q04 1.6660; Q06 3.8455; Q10 7.0440; Q12 3.9505; Q15 10.0245; Q16 2.9180; Q17 0.1465; Q19 43.9640; Q20 3.0000; Q21 52.5865; Q22 1.1190 | no non-zero term | 0.0000 | 120/300/700 | files: src/query/query_evaluator.c, src/query/scan_manager.c, src/object/object_domain.c, src/object/object_primitive.c; subsystems: executor / predicate evaluation, object domain / type system, scan manager | The dispatch really is per row and generic, and there is visible evidence (the #if 0 block) that a prior attempt was abandoned. Risk dominates: the fast path must be provably equivalent for every domain pair it intercepts. | 45 / 0 / 22.5 | — / — / IMP-029 (complementary, shares the tp_value_compare_with_error callee — not additive); IMP-030 (a specialized NUMERIC/DOUBLE comparator would subsume it); IMP-025 (lowers cost per compare where IMP-025 lowers the number of compares) | eligible — NO_NUMERIC_BASIS | Ranked but unscored: an 18.1% CPU-excess attribution whose own registry entry states no wall claim and leaves the realistic target — the coercion and domain-resolution prologue — unquantified. |
| `IMP-024` | performance | Q10 7.0440 | no non-zero term | 0.0000 | 150/350/800 | files: src/parser/semantic_check.c, src/parser/xasl_generation.c, src/optimizer/query_graph.c, src/parser/parse_tree.h; subsystems: parser / semantic analysis, query optimizer, XASL generation (SORT_LIST), schema constraint lookup | I confirmed both halves at the pin: pt_check_group_by() (semantic_check.c:14569) never compares GROUP BY columns against each other or looks up a constraint, and pt_to_groupby() (xasl_generation.c:6024) is a one-line pass through to pt_to_sort_list with no elimination step. The absence is structural, so the whole pass must be written. | 38.2 / 0 / 19.1 | — / leave the key at 7 columns and rely on IMP-015 + IMP-016 (rejected as a full fix); rewrite the query text (rejected: forbidden by SSOT section 6) / IMP-015 (orthogonal, compounds rather than overlaps); IMP-016 (orthogonal); IMP-026 (additive) | eligible — section 5-d hard stop: XASL serialization (section 5-d independent hard stop) · NO_NUMERIC_BASIS | Ranked but unscored: the registry states outright that the wall-time effect is unquantified in this campaign and only the key-byte-width comparison is measured. Also an XASL-serialization hard stop. |
| `IMP-006` | performance | Q03 4.5395; Q10 7.0440; Q11 3.2285; Q21 52.5865 | no non-zero term | 0.0000 | 200/500/1200 | files: src/query/query_executor.c, src/query/list_file.c, src/query/query_opfunc.c, src/query/fetch.c; subsystems: executor / XASL, list file (temporary result), heap, expression/type | Seven files across executor, list file and heap; the change alters where per-tuple DB_VALUEs are copied, which is exactly the ownership boundary qdata_generate_tuple_desc_for_valptr_list relies on. LOC is large and the risk component, not the size, dominates. | 32.7 / 0 / 16.35 | — / cache the tuple descriptor per node instead of rebuilding per tuple (query_opfunc.c:625) — a strict subset / the tuple-descriptor rebuild sub-case (query_opfunc.c:625) | eligible — section 5-d hard stop: XASL serialization (section 5-d independent hard stop) · NO_NUMERIC_BASIS | Ranked but unscored: the registry declines any wall claim for CUBRID's native plan and offers only a controlled-plan core-second band. It also touches XASL serialization, a section 5-d independent hard stop. |

### Not ranked, with lane and rationale

Section 4-a: the overall implementation ranking covers the **Performance lane only**. Enabler, Diagnostic and Deferred-research candidates are listed with their lane and rationale but carry no queue position, and `external_tracking` candidates are excluded from the queue without that being a benefit judgment.

| IMP ID | Lane | External ref | Expected saved seconds | Eligibility | Rationale |
|---|---|---|---|---|---|
| `IMP-001` | performance | — | 0 | blocked — BLOCKER: Is the internal prototype's ~13% a WALL or a CPU reduction? expected_saved_seconds multiplies a wall median, so a CPU-side figure would overstate the benefit, possibly by a large factor. | No rank position: BENEFIT_PENDING_DENOMINATOR under AMEND-F. The 62.35% band is refuted by the prototype's ~13%, and that 13% cannot be used until one datum — wall or CPU — is supplied. Not a rejection. |
| `IMP-002` | deferred_research | — | 0 | blocked — BLOCKER: The Q04 1.160 core-s attribution is confounded with the IMP-018 mechanism; effective evidence weight 0.00 until IMP-018 and IMP-010 are fixed. Independent of its deferred_research lane, which alone already removes it from the ranked set. | Not ranked: deferred_research lane plus BENEFIT_CONFOUNDED. Its Q04 attribution is entangled with the IMP-018 mechanism, and CUBRID has no BufferAccessStrategy equivalent (0 grep hits), so it is research, not a bounded patch. |
| `IMP-005` | enabler | — | 0 | no benefit-ranked position; inserted into the queue immediately ahead of IMP-009 as its required predecessor, inheriting that position (section 4-a) | Enabler with zero runtime effect by construction; it earns its place only as the measurement prerequisite for IMP-009 and IMP-012, whose degree changes cannot be honestly read while the nested-chain trace merge is corrupt. |
| `IMP-007` | external_tracking | CBRD-26788 | 0 | excluded from the implementation queue (external_tracking); still tracked to a resolution | Excluded from the queue by the triage's external_tracking lane change (CBRD-26788, state watch); CUBRID additionally has no async I/O infrastructure to build on. Tracked to resolution, not closed. |
| `IMP-011` | deferred_research | — | 13.5675 | listed with lane and rationale, no queue position (deferred_research) | Not ranked: deferred_research lane. Its 3.67x on Q07's wall is real and recorded for information, but its Q09 effect is wholly contained by IMP-014 and it also carries the upstream scope gate. |
| `IMP-017` | diagnostic | — | 0 | listed with lane and rationale, no queue position (diagnostic) | Diagnostic lane, no queue position, zero measured effect by design; its value is restoring the max_agg_hash_size control that makes IMP-016's memory-limit hypothesis testable at all. |
| `IMP-020` | deferred_research | — | 0 | listed with lane and rationale, no queue position (deferred_research) | Not ranked: deferred_research lane, and its 69.5% figure is a pair of core-second bands with no wall conversion. Lowest feasibility band in the set. |
| `IMP-025` | external_tracking | #7533 | 0 | excluded from the implementation queue (external_tracking); still tracked to a resolution | Excluded from the queue by the triage's external_tracking lane change (PR #7533). OQ-F4 requires confirming whether that PR merged before campaign closeout. |
| `IMP-026` | deferred_research | — | 0 | listed with lane and rationale, no queue position (deferred_research) | Not ranked: deferred_research lane, and the band cannot be separated from the surrounding sort in this campaign's setup, so only an 8.91% cycle share exists. |
| `IMP-028` | external_tracking | #7533 | 0 | excluded from the implementation queue (external_tracking); still tracked to a resolution | Excluded from the queue by the triage's external_tracking lane change (PR #7533), and structurally impossible in-campaign anyway: semi/anti join is absent from CUBRID (0 grep hits tree-wide). Contains IMP-031, recorded for a later lane decision. |

---

## Candidate queue (section 4-a ordering)

A required enabler is inserted **immediately ahead of** the dependent candidate it unblocks; it inherits its position from the dependent, never from its own benefit score (which is typically zero).

| Position | IMP ID | Lane | Note |
|---|---|---|---|
| 1 | `IMP-015` | performance | rank 1 |
| 2 | `IMP-005` | enabler | required predecessor of IMP-009; inherits its position (section 4-a), never its own benefit score |
| 3 | `IMP-009` | performance | rank 2 |
| 4 | `IMP-018` | performance | rank 3 |
| 5 | `IMP-014` | performance | rank 4 |
| 6 | `IMP-027` | performance | rank 5 |
| 7 | `IMP-003` | performance | rank 6 |
| 8 | `IMP-029` | performance | rank 7 |
| 9 | `IMP-019` | performance | rank 8 |
| 10 | `IMP-023` | performance | rank 9 |
| 11 | `IMP-030` | performance | rank 10 |
| 12 | `IMP-013` | performance | rank 11 |
| 13 | `IMP-012` | performance | rank 12 |
| 14 | `IMP-031` | performance | rank 13 |
| 15 | `IMP-022` | performance | rank 14 |
| 16 | `IMP-016` | performance | rank 15 |
| 17 | `IMP-004` | performance | rank 16 |
| 18 | `IMP-021` | performance | rank 17 |
| 19 | `IMP-010` | performance | rank 18 |
| 20 | `IMP-008` | performance | rank 19 |
| 21 | `IMP-024` | performance | rank 20 |
| 22 | `IMP-006` | performance | rank 21 |

---

## Expected effect against the CORRECTED MDE (section 6-d)

The Phase 1B ranking MUST carry every candidate's expected effect against the MDE of its target queries, and the flag is raised **at ranking time** so it is known before a candidate is queued rather than discovered inconclusive after twelve pairs. The MDE used is the section 6-d-1 **corrected** MDE, never the raw fast-regime MDE. `UNPROVABLE_ON_THIS_HOST` does not delete a candidate; it states that this host cannot decide it.

**For every query whose MDE depends on the undecided factor, no `UNPROVABLE_ON_THIS_HOST` verdict is asserted here.** Section 6-d-1 says that when the calibration supports no combination rule the worker reports and asks, and MUST NOT pick a factor. For those queries the corrected MDE is therefore not a campaign fact yet, and a verdict computed from one would be this campaign quietly making the user's decision. Each affected row is **WITHHELD**, and what each candidate rule *would* give is published instead so the decision is informed. Rows marked `rule-invariant` come out the same under all three candidate rules, so the pending decision cannot move them.

**Q01–Q06 rows in this table are real determinations.** Their MDE comes from a DIRECTLY MEASURED restart-regime paired CV (section 6-d-1 step 6), no combination rule enters it, and the pending decision cannot move them — so their verdicts are stated normally rather than withheld.

| IMP ID | Query | Predicted effect | Corrected MDE (provisional for factor-dependent queries) | Verdict | Under each candidate rule |
|---|---|---|---|---|---|
| `IMP-003` | Q02 | 53.100% | 1.368% | resolvable | — |
| `IMP-009` | Q05 | 81.070% | 4.458% | resolvable | — |
| `IMP-011` | Q07 | 72.750% | 35.595% | **WITHHELD** — pending the section 6-d-1 rule decision (rule-invariant) | max_observed_factor → resolvable; single_pooled_geometric_mean → resolvable; wall_magnitude_dependent → resolvable |
| `IMP-012` | Q08 | 12.150% | 67.708% | **WITHHELD** — pending the section 6-d-1 rule decision · **outcome DEPENDS on the decision** | max_observed_factor → unprovable; single_pooled_geometric_mean → unprovable; wall_magnitude_dependent → resolvable |
| `IMP-013` | Q08 | 10.560% | 67.708% | **WITHHELD** — pending the section 6-d-1 rule decision · **outcome DEPENDS on the decision** | max_observed_factor → unprovable; single_pooled_geometric_mean → unprovable; wall_magnitude_dependent → resolvable |
| `IMP-014` | Q09 | 35.171% | 8.541% | **WITHHELD** — pending the section 6-d-1 rule decision (rule-invariant) | max_observed_factor → resolvable; single_pooled_geometric_mean → resolvable; wall_magnitude_dependent → resolvable |
| `IMP-015` | Q10 | 23.877% | 24.544% | **WITHHELD** — pending the section 6-d-1 rule decision · **outcome DEPENDS on the decision** | max_observed_factor → unprovable; single_pooled_geometric_mean → resolvable; wall_magnitude_dependent → resolvable |
| `IMP-018` | Q11 | 58.430% | 18.194% | **WITHHELD** — pending the section 6-d-1 rule decision (rule-invariant) | max_observed_factor → resolvable; single_pooled_geometric_mean → resolvable; wall_magnitude_dependent → resolvable |
| `IMP-019` | Q12 | 5.447% | 4.189% | **WITHHELD** — pending the section 6-d-1 rule decision (rule-invariant) | max_observed_factor → resolvable; single_pooled_geometric_mean → resolvable; wall_magnitude_dependent → resolvable |
| `IMP-023` | Q16 | 25.990% | 15.569% | **WITHHELD** — pending the section 6-d-1 rule decision (rule-invariant) | max_observed_factor → resolvable; single_pooled_geometric_mean → resolvable; wall_magnitude_dependent → resolvable |
| `IMP-027` | Q19 | 99.177% | 7.054% | **WITHHELD** — pending the section 6-d-1 rule decision (rule-invariant) | max_observed_factor → resolvable; single_pooled_geometric_mean → resolvable; wall_magnitude_dependent → resolvable |
| `IMP-029` | Q22 | 20.903% | 8.871% | **WITHHELD** — pending the section 6-d-1 rule decision (rule-invariant) | max_observed_factor → resolvable; single_pooled_geometric_mean → resolvable; wall_magnitude_dependent → resolvable |
| `IMP-030` | Q22 | 2.310% | 8.871% | **WITHHELD** — pending the section 6-d-1 rule decision · **outcome DEPENDS on the decision** | max_observed_factor → unprovable; single_pooled_geometric_mean → resolvable; wall_magnitude_dependent → resolvable |
| `IMP-031` | Q22 | 2.050% | 8.871% | **WITHHELD** — pending the section 6-d-1 rule decision · **outcome DEPENDS on the decision** | max_observed_factor → unprovable; single_pooled_geometric_mean → resolvable; wall_magnitude_dependent → resolvable |

### Per-query corrected MDE

| Query | Fresh base median (s) | Corrected MDE (illustrative, no rule applied) | under `max_observed_factor` | under `single_pooled_geometric_mean` | under `wall_magnitude_dependent` |
|---|---|---|---|---|---|
| Q01 | 31.6435 | 2.976% | measured directly | measured directly | measured directly |
| Q02 | 0.3645 | 1.368% | measured directly | measured directly | measured directly |
| Q03 | 4.5395 | 1.489% | measured directly | measured directly | measured directly |
| Q04 | 1.6660 | 1.000% | measured directly | measured directly | measured directly |
| Q05 | 10.3355 | 4.458% | measured directly | measured directly | measured directly |
| Q06 | 3.8455 | 1.443% | measured directly | measured directly | measured directly |
| Q07 | 18.6495 | 35.595% | 35.595% | 6.879% | 14.228% |
| Q08 | 1.0075 | 67.708% | 67.708% | 13.085% | 6.993% |
| Q09 | 10.5780 | 8.541% | 8.541% | 1.651% | 2.625% |
| Q10 | 7.0440 | 24.544% | 24.544% | 4.743% | 6.246% |
| Q11 | 3.2285 | 18.194% | 18.194% | 3.516% | 3.225% |
| Q12 | 3.9505 | 4.189% | 4.189% | 1.000% | 1.000% |
| Q13 | 11.3345 | 6.877% | 6.877% | 1.329% | 2.182% |
| Q14 | 3.1170 | 5.568% | 5.568% | 1.076% | 1.000% |
| Q15 | 10.0245 | 3.453% | 3.453% | 1.000% | 1.035% |
| Q16 | 2.9180 | 15.569% | 15.569% | 3.009% | 2.633% |
| Q17 | 0.1465 | 8.536% | 8.536% | 1.650% | 1.000% |
| Q18 | 37.4815 | 15.284% | 15.284% | 2.954% | 8.444% |
| Q19 | 43.9640 | 7.054% | 7.054% | 1.363% | 4.196% |
| Q20 | 3.0000 | 22.401% | 22.401% | 4.329% | 3.838% |
| Q21 | 52.5865 | 6.960% | 6.960% | 1.345% | 4.499% |
| Q22 | 1.1190 | 8.871% | 8.871% | 1.714% | 1.000% |

`measured directly` marks Q01–Q06, which use their **measured** restart-regime paired CV rather than an inflated fast-regime one (section 6-d-1 step 6), so no combination rule applies to them and the pending decision cannot move them.

**The 6.0 core-s/s external-CPU gate does not guarantee that this host can resolve small effects.** It bounds only gross contention. Resolution is carried by the paired design and by these honest per-query MDE figures. This limitation must be restated in every report that cites a sub-MDE effect.

---

## Overlap and containment clusters (section 4-c)

Within a cluster the `expected_saved_seconds` of the **highest-scoring member only** is counted toward any campaign-level total; other members are marked `SUPPRESSED_OVERLAP` and excluded from every sum. Cluster totals are never produced by addition across members.

| Type | Members | Scope | Queued | Why |
|---|---|---|---|---|
| alternative | `IMP-003`, `IMP-004` | Q02 | IMP-003 | IMP-003's effect is measured on Q02's WALL (-53.1%); IMP-004's Q02 figure is a CPU band with no wall conversion. The registry states the two are NOT additive. |
| containment | `IMP-003`, `IMP-004` | Q02 | IMP-003 | registry records 'IMP-004 (for Q02)' as contained by IMP-003. |
| alternative | `IMP-002`, `IMP-007` | — | — | Both are excluded from the ranked set — IMP-002 by lane and BENEFIT_CONFOUNDED, IMP-007 by the external_tracking lane change. |
| alternative | `IMP-015`, `IMP-016` | Q10 | IMP-015 | 'fixing either recovers Q10's measured 1.313675x'; IMP-015 is the measured route and is already implemented with verdict 'accepted (provisional)'. IMP-016's Q10 saving is SUPPRESSED_OVERLAP. |
| predecessor | `IMP-017`, `IMP-016` | — | IMP-017; IMP-016 | IMP-017 restores the max_agg_hash_size control that makes IMP-016's memory-limit hypothesis testable. |
| predecessor | `IMP-005`, `IMP-009`, `IMP-012` | — | IMP-005; IMP-009; IMP-012 | The nested-chain trace merge is corrupt, so degree changes cannot be honestly read until IMP-005 lands. IMP-005 also shares a 176-line file with IMP-009/IMP-012 and must be sequenced. |
| containment | `IMP-014`, `IMP-011` | Q09 | IMP-014 | IMP-014 supplies the cardinality IMP-011 costs; Q09 effects overlap completely and must never be summed. |
| containment | `IMP-021`, `IMP-015`, `IMP-023` | — | IMP-021 | IMP-021 removes the sort IMP-015 parallelizes and the input IMP-023's per-group loop consumes. Ordering hazard: IMP-015 is already measured, so landing IMP-021 later would render that measured gain moot. |
| containment | `IMP-028`, `IMP-031` | Q22 | IMP-028 | IMP-028's Q22 anti-join band contains IMP-031's 0.11004 core-s. IMP-028 is external_tracking and unscored, so the suppression is recorded but not applied. |
| containment | `IMP-020`, `IMP-029` | Q22 | — | Shared per-row DB_VALUE alloc/copy/clear band; IMP-020 is deferred_research and unscored, so no suppression fires. |
| conflict_one_branch_rule | `IMP-003`, `IMP-022` | — | — | They edit the same function region; the one-branch rule (section 5-b) forbids one branch carrying both. |

---

## Sensitivity and ranking stability (section 2-d)

Every evidence weight was perturbed by ±0.15 (clamped to `[0, 1]`) in both the pessimistic and the optimistic direction and the ranking recomputed.

- Base top 5: `IMP-015`, `IMP-009`, `IMP-018`, `IMP-014`, `IMP-027`
- optimistic: `IMP-015`, `IMP-009`, `IMP-018`, `IMP-027`, `IMP-014` — identity changed: False, order changed: True
- pessimistic: `IMP-015`, `IMP-009`, `IMP-018`, `IMP-014`, `IMP-003` — identity changed: True, order changed: True

**`RANKING_UNSTABLE`.** The identity or the order of the top 5 changes materially under perturbation. Candidates that moved in or out: `IMP-003`, `IMP-027`. The queue order in that region is **not evidence-supported**. `RANKING_UNSTABLE` does not block Phase 1 completion; it blocks silent reliance on a fragile order.

---

## ID-unassigned new candidates — user decision required

Section 1-b: this campaign allocates no new IMP IDs unless the user directs it to. `next_id` is `IMP-032` and is consumed. Findings that would otherwise become candidates are raised here instead.

### NEW-CAND-A — Group-by fallback sort parallel eligibility on the parallel-scan mergeable-list gather path

- **ID**: UNASSIGNED — section 1-b forbids this campaign allocating a new IMP ID without user direction (next_id is IMP-032, consumed)
- **Source**: `tpch-sspq/impl/diagnosis/Q15-parallel-non-arming.md (handoff task 2, this run)`
- **Problem**: px_scan_result_handler.cpp:635 force-assigns groupby_stats.groupby_hash = HS_REJECT_ALL for the trace label only, while the leader's agg_hash_context->state stays HS_ACCEPT_ALL because the leader never runs its own hash pass (:628-641). query_executor.c:5682 (IMP-015) / :5657 (base) therefore yields hash_eligible = 1 and sort_check_parallelism returns 1 at external_sort.c:5232 before any size, degree or worker logic.
- **measurement_correctness arm**: Separate the forced trace label from the runtime state. The current trace cannot distinguish whether the leader ran a hash pass, and that ambiguity already caused a real candidate-selection error (IMP-015 plan section 5-c item 7 listed Q15 as 'armed').
- **performance arm**: Make the eligibility decision reflect call-site truth on the gather path, as IMP-015 change (b) already does unconditionally for the partial hash-list sort.
- **Relations**: {"anti_additive_with": ["IMP-021"], "complementary_to": ["IMP-015"], "lane_character": "performance + Diagnostic-Measurement-correctness", "predecessor_of": ["IMP-032"]}
- **Target queries**: Q15 (2 group-by nodes), Q18
- **Expected effect**: NOT DETERMINED. Task 2 was read-only; no section 6-c A/B was run. The leg A<->B and C<->D wall differences also change scan parallelism and therefore cannot be converted into an effect for the sort parallelization alone.
- **Decision requested**: Whether to allocate an IMP ID and, if so, whether the performance and measurement-correctness arms are one candidate or two.

---

## Per-candidate benefit derivation (every non-zero term cites its raw evidence)

Section 2-b: every non-zero term MUST cite the raw evidence pointer that produced it. Zero terms are listed too, so the reader can see them, but they add nothing.

### `IMP-001` — Aggregate accumulation performs a fully generalized per-row NUMERIC add/mul (buffer zeroing, byte<->word conversion, precision recomputation, overflow check, round-and-pack, DB_VALUE construction) instead of a deferred-carry fast sum accumulator

lane `performance` · feasibility 41.8 · benefit — · total — · expected saved 0.0000 s

| Query | Fresh base median (s) | Effect fraction | Evidence | Weight | Saved (s) | Basis | Citation |
|---|---|---|---|---|---|---|---|
| Q01 | 31.6435 | — | unmeasured | 0 | 0.0000 | no numeric benefit permitted while BENEFIT_PENDING_DENOMINATOR | triage-adjustments.json IMP-001 |
| Q11 | 3.2285 | — | unmeasured | 0 | 0.0000 | no numeric benefit permitted while BENEFIT_PENDING_DENOMINATOR | triage-adjustments.json IMP-001 |

### `IMP-003` — Leading-wildcard LIKE selectivity is estimated from histogram bucket *upper-boundary* values only, producing a 21.7x under-estimate that then decides conjunctive predicate evaluation order, so an expensive UTF-8 LIKE is evaluated on all rows instead of the few surviving a cheap integer equality

lane `performance` · feasibility 67 · benefit 72 · total 69.5 · expected saved 0.1935 s

| Query | Fresh base median (s) | Effect fraction | Evidence | Weight | Saved (s) | Basis | Citation |
|---|---|---|---|---|---|---|---|
| Q02 | 0.3645 | 53.100% | direct_ab | 1 | 0.1935 | -53.1% of Q02 median wall (353 ms -> ~166 ms) from reordering alone. Used as the observed effect rate, not rounded up. | improvement-registry.json IMP-003.effect_range |
| Q09 | 10.578 | 0.000% | unmeasured | 0 | 0.0000 | NO_NUMERIC_BASIS — 'Generalizes to any query whose cheap predicate is estimated less selective than an expensive string predicate' is a mechanism statement with no per-query number. Registry also records IMP-003 rejected by measurement as Q09's deciding term. | improvement-registry.json IMP-003.effect_range, IMP-014.alternatives |
| Q16 | 2.918 | 0.000% | unmeasured | 0 | 0.0000 | NO_NUMERIC_BASIS — no per-query figure. | improvement-registry.json IMP-003.effect_range |

### `IMP-004` — UTF-8 LIKE matcher decodes both operands to codepoints per character through non-inlined PLT calls and maps each codepoint through a collation weight table, with no byte-lockstep comparison and no ASCII fast path

lane `performance` · feasibility 58 · benefit 0 · total 29 · expected saved 0.0000 s

| Query | Fresh base median (s) | Effect fraction | Evidence | Weight | Saved (s) | Basis | Citation |
|---|---|---|---|---|---|---|---|
| Q02 | 0.3645 | 0.000% | upper_bound | 0.35 | 0.0000 | MD-1. The quantified figure is a CPU band: 'Upper bound on Q02 is the 46.72% band (0.836 of 1.79 core-s)'. The 8.64x-9.75x figure is a reduction of the per-row LIKE cost, not of Q02's wall, and no active-unit count is given for Q02, so no wall conversion is available. Contributes 0 s and is listed. | improvement-registry.json IMP-004.effect_range |
| Q13 | 11.3345 | 0.000% | unmeasured | 0 | 0.0000 | NO_NUMERIC_BASIS — no per-query figure. | improvement-registry.json IMP-004.q_relations |
| Q16 | 2.918 | 0.000% | unmeasured | 0 | 0.0000 | NO_NUMERIC_BASIS — no per-query figure. | improvement-registry.json IMP-004.q_relations |

### `IMP-005` — Parallel-scan trace statistics for a nested-loop subtree are merged once per scan_ptr level and again by the whole-subtree walk inside xasl_merge_stats, so a level-k scan's counters are reported (k-1) times: depth 3 is exactly 2x and depth 4 exactly 3x

lane `enabler` · feasibility 86.3 · benefit 0 · total 43.15 · expected saved 0.0000 s

| Query | Fresh base median (s) | Effect fraction | Evidence | Weight | Saved (s) | Basis | Citation |
|---|---|---|---|---|---|---|---|
| * | — | 0.000% | unmeasured | 0 | 0.0000 | 'Diagnosability only; zero measured runtime effect (query results and headline timings are unaffected).' A zero benefit score is correct and expected for this lane. | improvement-registry.json IMP-005.effect_range |

### `IMP-006` — Every intermediate join result tuple is materialized into a list-file page through a per-value DB_VALUE -> tuple copy (tuple descriptor build, per-value size computation, memcpy, clear), where PostgreSQL passes a TupleTableSlot by reference and only materializes when a node genuinely must store the tuple

lane `performance` · feasibility 32.7 · benefit 0 · total 16.35 · expected saved 0.0000 s

| Query | Fresh base median (s) | Effect fraction | Evidence | Weight | Saved (s) | Basis | Citation |
|---|---|---|---|---|---|---|---|
| Q03 | 4.5395 | 0.000% | upper_bound | 0.35 | 0.0000 | MD-1. 'Upper bound on Q03's controlled plan is the 6.26 core-second band ... No wall-clock claim is made for CUBRID's native plan.' The registry itself declines the wall claim. | improvement-registry.json IMP-006.effect_range |
| Q10 | 7.044 | 0.000% | unmeasured | 0 | 0.0000 | NO_NUMERIC_BASIS. | improvement-registry.json IMP-006.q_relations |
| Q11 | 3.2285 | 0.000% | unmeasured | 0 | 0.0000 | NO_NUMERIC_BASIS. | improvement-registry.json IMP-006.q_relations |
| Q21 | 52.5865 | 0.000% | unmeasured | 0 | 0.0000 | NO_NUMERIC_BASIS. | improvement-registry.json IMP-006.q_relations |

### `IMP-008` — Scan-level sarg evaluation routes every row through the generic DB_VALUE comparator tp_value_compare_with_error(), with per-call domain resolution and coercion, where PostgreSQL compiles the qual once into type-specialized ExprEvalSteps and calls the resolved datum comparison directly

lane `performance` · feasibility 45 · benefit 0 · total 22.5 · expected saved 0.0000 s

| Query | Fresh base median (s) | Effect fraction | Evidence | Weight | Saved (s) | Basis | Citation |
|---|---|---|---|---|---|---|---|
| Q04 | 1.666 | 0.000% | attribution | 0.7 | 0.0000 | MD-1. '0.825 core-s of the 4.558 core-s Q04 CPU excess (18.1%) ... No wall-clock claim is made: at 5.4 active units a CPU saving converts to wall only in proportion.' The registry gives U=5.4 but also states the realistic target is only 'the coercion and domain-resolution prologue, since the comparison itself is irreducible', without quantifying that prologue. With no quantified removable portion there is nothing to convert. | improvement-registry.json IMP-008.effect_range |
| Q06 | 3.8455 | 0.000% | unmeasured | 0 | 0.0000 | NO_NUMERIC_BASIS. | improvement-registry.json IMP-008.q_relations |
| Q10 | 7.044 | 0.000% | unmeasured | 0 | 0.0000 | NO_NUMERIC_BASIS. | improvement-registry.json IMP-008.q_relations |
| Q12 | 3.9505 | 0.000% | unmeasured | 0 | 0.0000 | NO_NUMERIC_BASIS. | improvement-registry.json IMP-008.q_relations |
| Q15 | 10.0245 | 0.000% | unmeasured | 0 | 0.0000 | NO_NUMERIC_BASIS. | improvement-registry.json IMP-008.q_relations |
| Q16 | 2.918 | 0.000% | unmeasured | 0 | 0.0000 | NO_NUMERIC_BASIS. | improvement-registry.json IMP-008.q_relations |
| Q17 | 0.1465 | 0.000% | unmeasured | 0 | 0.0000 | NO_NUMERIC_BASIS. | improvement-registry.json IMP-008.q_relations |
| Q19 | 43.964 | 0.000% | unmeasured | 0 | 0.0000 | NO_NUMERIC_BASIS. | improvement-registry.json IMP-008.q_relations |
| Q20 | 3 | 0.000% | unmeasured | 0 | 0.0000 | NO_NUMERIC_BASIS. | improvement-registry.json IMP-008.q_relations |
| Q21 | 52.5865 | 0.000% | unmeasured | 0 | 0.0000 | NO_NUMERIC_BASIS. | improvement-registry.json IMP-008.q_relations |
| Q22 | 1.119 | 0.000% | unmeasured | 0 | 0.0000 | NO_NUMERIC_BASIS. | improvement-registry.json IMP-008.q_relations |

### `IMP-009` — The parallel degree of an uncorrelated subquery is hardcoded to 1 and explicitly ignores both the parallelism parameter and an explicit PARALLEL hint, so when the optimizer folds an entire multi-table join chain into an uncorrelated subquery that whole chain executes single-threaded

lane `performance` · feasibility 57.8 · benefit 88 · total 72.9 · expected saved 2.9326 s

| Query | Fresh base median (s) | Effect fraction | Evidence | Weight | Saved (s) | Basis | Citation |
|---|---|---|---|---|---|---|---|
| Q05 | 10.3355 | 81.070% | upper_bound | 0.35 | 2.9326 | MD-4. 'Upper bound on what perfect parallelization of this node recovers; the realistic bound is PostgreSQL's own 5.43 units on the same plan, i.e. CUBRID's 9.615 s would approach 9.8863 core-s / 5.43 units = 1.82 s.' The removable fraction is argued (PostgreSQL's own unit count on the SAME plan shape is the achievable floor), so the band rule is satisfied: 1 - 1.82/9.615 = 0.8107. Carried at the Upper bound weight 0.35 because the registry labels it an upper bound. The fraction transfers; the 9.615 s does NOT — the scorer multiplies this campaign's fresh_base_median_Q05. | improvement-registry.json IMP-009.effect_range |
| Q11 | 3.2285 | 0.000% | unmeasured | 0 | 0.0000 | NO_NUMERIC_BASIS. | improvement-registry.json IMP-009.q_relations |
| Q16 | 2.918 | 0.000% | unmeasured | 0 | 0.0000 | NO_NUMERIC_BASIS — the registry attributes Q16's side effect to how many times the RHS is built, not a quantified wall term. | improvement-registry.json IMP-025.containment |
| Q20 | 3 | 0.000% | unmeasured | 0 | 0.0000 | NO_NUMERIC_BASIS. | improvement-registry.json IMP-009.q_relations |
| Q21 | 52.5865 | 0.000% | unmeasured | 0 | 0.0000 | NO_NUMERIC_BASIS. | improvement-registry.json IMP-009.q_relations |

### `IMP-010` — A heap scan's newly read pages are inserted at the TOP of the session's private LRU list when the scan runs on the client transaction thread, but only into the MIDDLE of a round-robin SHARED LRU list when the same scan runs on pooled parallel-query workers, because a worker's thread entry is recycled with private_lru_index = -1 and the parallel-scan task never propagates its parent's LRU identity - so going parallel silently discards the buffer pool's scan-resistance and re-reads 2.88x the pages

lane `performance` · feasibility 49.5 · benefit 0 · total 24.75 · expected saved 0.0000 s

| Query | Fresh base median (s) | Effect fraction | Evidence | Weight | Saved (s) | Basis | Citation |
|---|---|---|---|---|---|---|---|
| Q06 | 3.8455 | 0.000% | direct_ab | 1 | 0.0000 | MD-1. The directly measured quantity is physical page reads per statement (458,209 -> 158,930, -4.57 GiB of page-cache traffic). The core-second consequence is explicitly conditional — 'IF the kernel read band scales with bytes, the 2.543 core-s band falls to about 0.882 core-s, releasing roughly 1.66 core-s of the 14.023 core-s Q06 CPU excess (11.8%)' — and no wall conversion is given. A conditional CPU band is not a wall fraction. | improvement-registry.json IMP-010.effect_range |
| Q12 | 3.9505 | 0.000% | unmeasured | 0 | 0.0000 | NO_NUMERIC_BASIS. | improvement-registry.json IMP-010.q_relations |
| Q13 | 11.3345 | 0.000% | unmeasured | 0 | 0.0000 | NO_NUMERIC_BASIS. | improvement-registry.json IMP-010.q_relations |

### `IMP-011` — Join plan selection is parallel-degree blind: qo_nljoin_cost() and qo_hjoin_cost() compare candidate plans on a single-threaded cost scale while scan_check_parallel_scan_possible() force-blocks parallel scan on every inner join level, so a serial index-nested-loop chain is preferred over a hash-join plan the same executor runs at 7.20 active units - 3.6694x measured wall loss on Q07, plus a hard-coded HJ_MEM_ALLOC_CONSTANT 'heuristic offset to prefer NL join over hash join' and a per-row hash spill penalty that together make the winning plan look 872x more expensive

lane `deferred_research` · feasibility 35.2 · benefit 96 · total 65.6 · expected saved 13.5675 s

| Query | Fresh base median (s) | Effect fraction | Evidence | Weight | Saved (s) | Basis | Citation |
|---|---|---|---|---|---|---|---|
| Q07 | 18.6495 | 72.750% | direct_ab | 1 | 13.5675 | '3.6694x on Q07's CUBRID wall (23.719 s -> 6.464 s)'. Observed effect rate: 1 - 6.464/23.719 = 0.7275. Recorded for information only; the deferred_research lane carries no queue position, so this term never enters a campaign-level total. | improvement-registry.json IMP-011.effect_range |
| Q09 | 10.578 | 0.000% | unmeasured | 0 | 0.0000 | SUPPRESSED_OVERLAP — contained by IMP-014 on Q09; effects overlap completely and must never be summed. | improvement-registry.json IMP-011.containment |
| Q10 | 7.044 | 0.000% | unmeasured | 0 | 0.0000 | NO_NUMERIC_BASIS. | improvement-registry.json IMP-011.q_relations |
| Q11 | 3.2285 | 0.000% | unmeasured | 0 | 0.0000 | NO_NUMERIC_BASIS. | improvement-registry.json IMP-011.q_relations |
| Q14 | 3.117 | 0.000% | unmeasured | 0 | 0.0000 | NO_NUMERIC_BASIS. | improvement-registry.json IMP-011.q_relations |

### `IMP-012` — The parallel-scan coordinator is a pure consumer and the SCAN auto-degree formula saturates below the configured parallelism cap, so a plan CUBRID does parallelise runs at 5 active units where PostgreSQL runs the identical shape at 6 (5 workers plus a participating leader) - the sole factor above 1.0 in Q08's causal card, F_units 1.373763x of a 1.111086x gap

lane `performance` · feasibility 48 · benefit 56 · total 52 · expected saved 0.0612 s

| Query | Fresh base median (s) | Effect fraction | Evidence | Weight | Saved (s) | Basis | Citation |
|---|---|---|---|---|---|---|---|
| Q08 | 1.0075 | 12.150% | projection | 0.5 | 0.0612 | MD-2. 'Amdahl on the measured split ... reconstructs the measured 1.136 s exactly at 5 units and projects 0.998 s at 6 units.' Stated wall conversion: 1 - 0.998/1.136 = 0.1215. Evidence level Projection because the registry labels the 0.998 s figure a projection (the F_units decomposition itself is attribution). | improvement-registry.json IMP-012.effect_range and IMP-012.evidence_type |
| Q17 | 0.1465 | 0.000% | unmeasured | 0 | 0.0000 | NO_NUMERIC_BASIS. | improvement-registry.json IMP-012.q_relations |
| Q19 | 43.964 | 0.000% | unmeasured | 0 | 0.0000 | NO_NUMERIC_BASIS. | improvement-registry.json IMP-012.q_relations |

### `IMP-013` — Every page unfix on a HIT path performs mutex-protected LRU doubly-linked-list surgery plus zone rebalancing (pgbuf_lru_boost_bcb), so a plan that touches 6.6x fewer tuples than PostgreSQL's nets only a 16% total-CPU advantage: 27.41% of CUBRID's profile sits in pgbuf fix/unfix/LRU and 5.32% in libpthread, against PostgreSQL's 3.70% clock-sweep pin/unpin with no list and no mutex

lane `performance` · feasibility 48.9 · benefit 60 · total 54.45 · expected saved 0.0745 s

| Query | Fresh base median (s) | Effect fraction | Evidence | Weight | Saved (s) | Basis | Citation |
|---|---|---|---|---|---|---|---|
| Q08 | 1.0075 | 10.560% | attribution | 0.7 | 0.0745 | MD-2 + triage. 'A realistic target is the pgbuf_lru_boost_bcb plus mutex portion, 10.73% of profiled self cost, i.e. about 0.47 core-s of the 4.34 core-s statement, which at the measured U is about 0.12 s of wall.' The 4.34 core-s statement is Q08 (IMP-012 records total_query_cpu 4.3442 core-s per Q08 statement). Stated wall conversion 0.12 s against the 1.136 s Q08 median: 0.12/1.136 = 0.1056. This is the triage-mandated 0.47 core-s basis, not the 27.41%+5.32% band. | improvement-registry.json IMP-013.effect_range; triage-adjustments.json IMP-013; IMP-012.effect_range for the Q08 core-s identification |
| Q09 | 10.578 | 0.000% | unmeasured | 0 | 0.0000 | NO_NUMERIC_BASIS. | improvement-registry.json IMP-013.q_relations |
| Q10 | 7.044 | 0.000% | unmeasured | 0 | 0.0000 | NO_NUMERIC_BASIS. | improvement-registry.json IMP-013.q_relations |
| Q11 | 3.2285 | 0.000% | unmeasured | 0 | 0.0000 | NO_NUMERIC_BASIS. | improvement-registry.json IMP-013.q_relations |
| Q13 | 11.3345 | 0.000% | unmeasured | 0 | 0.0000 | NO_NUMERIC_BASIS. | improvement-registry.json IMP-013.q_relations |
| Q15 | 10.0245 | 0.000% | unmeasured | 0 | 0.0000 | NO_NUMERIC_BASIS. | improvement-registry.json IMP-013.q_relations |
| Q19 | 43.964 | 0.000% | unmeasured | 0 | 0.0000 | NO_NUMERIC_BASIS. | improvement-registry.json IMP-013.q_relations |
| Q20 | 3 | 0.000% | unmeasured | 0 | 0.0000 | NO_NUMERIC_BASIS. | improvement-registry.json IMP-013.q_relations |
| Q21 | 52.5865 | 0.000% | unmeasured | 0 | 0.0000 | NO_NUMERIC_BASIS. | improvement-registry.json IMP-013.q_relations |
| Q22 | 1.119 | 0.000% | unmeasured | 0 | 0.0000 | NO_NUMERIC_BASIS. | improvement-registry.json IMP-013.q_relations |

### `IMP-014` — Join selectivity for a multi-column foreign-key match is formed as the product of the per-column selectivities, so a two-column FK join is under-estimated by the ratio between the parent's row count and the product of the column NDVs (24,920x on Q09, collapsing a 3,261,613-row join to an estimated 2 rows) and the cost model then prefers an index-nested-loop chain that measurement shows is 1.5425x slower than the hash plan the same executor already implements

lane `performance` · feasibility 52 · benefit 92 · total 72 · expected saved 3.7204 s

| Query | Fresh base median (s) | Effect fraction | Evidence | Weight | Saved (s) | Basis | Citation |
|---|---|---|---|---|---|---|---|
| Q09 | 10.578 | 35.171% | direct_ab | 1 | 3.7204 | 'Lower bound 1.5425x on Q09's wall by direct A/B (10.980999 s -> 7.118999 s)'. Observed effect rate 1 - 7.118999/10.980999 = 0.35171. The registry calls the FACTOR a lower bound while the measurement is a direct A/B on the wall, so the Direct A/B weight applies to the observed rate (section 2-b: 'for a direct A/B candidate, conservative_effect_fraction_q is the observed effect rate from that A/B'). Explicitly not generalized: the registry records Q08 as a measured positive control where forcing the hash shape makes CUBRID 1.5123x SLOWER. | improvement-registry.json IMP-014.effect_range |

### `IMP-015` — sort_check_parallelism() unconditionally refuses parallelism for a SORT_GROUP_BY whenever the query was marked hash-aggregate-eligible, even after the executor has already ABANDONED hash aggregation at runtime (HS_REJECT_ALL), so the entire sort-based fallback group-by runs single-threaded while every other node of the same plan runs at 5-6 workers - 3834 ms of Q10's 8048 ms traced execution at one active unit, and a 1.313675x direct same-engine A/B

lane `performance` · feasibility 73 · benefit 80 · total 76.5 · expected saved 1.6819 s

| Query | Fresh base median (s) | Effect fraction | Evidence | Weight | Saved (s) | Basis | Citation |
|---|---|---|---|---|---|---|---|
| Q10 | 7.044 | 23.877% | direct_ab | 1 | 1.6819 | 'Direct A/B on the query as written: 7.128 s -> 5.426 s, i.e. 1.313675x'. Observed effect rate 1 - 5.426/7.128 = 0.23877. This campaign's own re-measurement recorded a smaller realized effect and a lower achieved degree (parallel workers: 4, not 6) — see IMP-015/report.md; the registry rate is retained here because section 2-b prescribes the A/B's observed rate, and the divergence is reported in the ranking rationale rather than silently re-based. | improvement-registry.json IMP-015.effect_range; tpch-sspq/impl/IMP-015/report.md |
| Q11 | 3.2285 | 0.000% | direct_ab | 1 | 0.0000 | MEASURED NEGATIVE CONTROL, contributing 0: 'the controlled block measures /*+ NO_HASH_AGGREGATE */ at 1.340000 s against native 1.342000 s - F_plan 1.001493x, inside the 1.28% CUBRID block band'. Q11's group-by sorts 1,516 pages against the 2048-page threshold, so compute_parallel_degree returns < 2 regardless. | improvement-registry.json IMP-015.q_evidence.Q11 |
| Q15 | 10.0245 | 0.000% | unmeasured | 0 | 0.0000 | REFUTED THIS RUN. The registry listed Q15 as 'armed, lower-bound corroboration', but the handoff task 2 diagnosis proves the mechanism cannot arm on Q15: Q15's group-by input arrives through the parallel-heap-scan mergeable-list gather, where the leader never runs its own hash pass, so its agg_hash_context->state stays HS_ACCEPT_ALL and sort_check_parallelism returns 1 at external_sort.c:5232 before any size/degree/worker logic. The trace's 'hash: partial' on Q15 is a label force-assigned at px_scan_result_handler.cpp:635, not the runtime state the gate reads. Reproduced by a 4-leg hint contrast pair on the preserved IMP-015 binary. | tpch-sspq/impl/diagnosis/Q15-parallel-non-arming.md sections 2-3; IMP-032/report.md D1 probe |
| Q18 | 37.4815 | 0.000% | upper_bound | 0.35 | 0.0000 | MD-1 plus a refuted target. The registry offers 'upper bound ~1.98x (63.4% of a 140.50 s block at ~1 active unit); no direct A/B available' — a previous-campaign block figure, not a wall fraction of this campaign's Q18. The IMP-032 D1 perf attribution further showed that the sort which actually parallelizes on Q18 is the partial hash-list sort (688 of 716 samples co-occur with qexec_hash_gby_put_next; ZERO with qexec_gby_put_next), i.e. IMP-015 change (b), not the main group-by sort this term was meant to price. | improvement-registry.json IMP-015.effect_range; IMP-032/report.md section 2; diagnosis/Q15-parallel-non-arming.md section 5 |

### `IMP-016` — Hash aggregation is abandoned for the whole statement by a hardcoded 0.5f very-high-selectivity heuristic that is evaluated on a group counter which the LRU eviction path never decrements, so the 2 MB max_agg_hash_size budget makes the estimate drift upward until it crosses 0.5 on a query whose true group/tuple selectivity is 0.332243 and whose every measured input prefix is at most 0.424788

lane `performance` · feasibility 67 · benefit 0 · total 33.5 · expected saved 0.0000 s

| Query | Fresh base median (s) | Effect fraction | Evidence | Weight | Saved (s) | Basis | Citation |
|---|---|---|---|---|---|---|---|
| Q10 | 7.044 | 0.000% | direct_ab | 1 | 0.0000 | SUPPRESSED_OVERLAP. 'On Q10 the whole observable effect is the fallback IMP-015 prices at 1.313675x'; the alternative-cluster rule queues at most one member and counts only the highest-scoring member's saving. IMP-015 already landed. The registry also declines to claim how much better IMP-016 alone would be, because the server-parameter experiment is blocked by IMP-017. | improvement-registry.json IMP-016.effect_range |
| Q11 | 3.2285 | 0.000% | unmeasured | 0 | 0.0000 | NO_NUMERIC_BASIS. | improvement-registry.json IMP-016.q_relations |
| Q18 | 37.4815 | 0.000% | attribution | 0.7 | 0.0000 | MD-1. The only independently recoverable figure is '1.32% of profile spent on the discarded hash' — a CPU profile share with no wall conversion. | improvement-registry.json IMP-016.effect_range |

### `IMP-017` — max_agg_hash_size is read into a FUNCTION-LOCAL STATIC in the per-row hash-aggregate path, so the parameter is frozen at the first hash-aggregate tuple of the server process and can never be changed for the life of that process - a session-level SET SYSTEM PARAMETERS to 512M provably changed nothing

lane `diagnostic` · feasibility 86.7 · benefit 0 · total 43.35 · expected saved 0.0000 s

| Query | Fresh base median (s) | Effect fraction | Evidence | Weight | Saved (s) | Basis | Citation |
|---|---|---|---|---|---|---|---|
| Q10 | 7.044 | 0.000% | unmeasured | 0 | 0.0000 | 'Zero measured effect on Q10's wall by itself, because HS_REJECT_ALL on Q10 is set by the selectivity test and not by the memory limit (query_executor.c:4845 is the only assignment site).' Independently re-confirmed this run: :4845 is still the only assignment site at the pinned base SHA. | improvement-registry.json IMP-017.effect_range; diagnosis/Q15-parallel-non-arming.md section 2-b #9 |
| Q18 | 37.4815 | 0.000% | unmeasured | 0 | 0.0000 | Diagnostic lane; not ranked for performance benefit. | improvement-registry.json IMP-017.q_relations |

### `IMP-018` — A single session's retainable buffer working set is capped at PGBUF_PRIVATE_LRU_MAX_HARD_QUOTA = 5000 BCBs regardless of data_buffer_size, because every page a query reads is placed on that session's PRIVATE LRU list and escapes into the shared pool only when a DIFFERENT session touches it or it reaches 64 fixes while still resident; so an 8192 MB pool retains 78 MiB for one connection, and the SAME query gets 2.6408x faster as later connections migrate its pages out

lane `performance` · feasibility 60.2 · benefit 84 · total 72.1 · expected saved 1.8864 s

| Query | Fresh base median (s) | Effect fraction | Evidence | Weight | Saved (s) | Basis | Citation |
|---|---|---|---|---|---|---|---|
| Q11 | 3.2285 | 58.430% | direct_ab | 1 | 1.8864 | CORRECTED (see MD-3). The cost IMP-018 removes IS present in this campaign's Q11 baseline. Three independent observations: (i) the fresh Phase 1A median is 3.2285 s, +140.57% against the previous campaign's 1.342 s — the largest divergence in the sweep — and within 9% of IMP-018's own measured `connection_1_of_the_query` value of 3.544 s, i.e. this baseline sits in the amplified regime, not the saturated one; (ii) Q11's six block medians decline MONOTONICALLY 3.529 / 3.404 / 3.298 / 3.159 / 3.040 / 2.961, which is the across-CONNECTION decay signature the registry records as `connection_sweep_median_s` [1.581, 1.54, 1.436, 1.353, 1.352, 1.349, 1.344, 1.346] with `connection_sweep_reads_per_statement` [49292, 34538, 18306, 3519, 135, 119, 127, 124]; Phase 1A opens one connection per block, so each block re-pays it; (iii) Q11 is the ONLY query of 22 with a monotone across-block drift above 3% (-16.10%; every other query is within +/-2.42% and non-monotone), so the drift is specific to this mechanism rather than an artefact of the fast regime. The fraction is the CONSERVATIVE of the two readings the A/B supports: the raw observed rate 1 - 1.342/3.544 = 0.62133, versus taking the A/B's measured saturated endpoint 1.342 s against THIS campaign's median, (3.2285 - 1.342)/3.2285 = 0.58430. The smaller is used, so the term cannot over-claim, and the previous campaign's absolute time is never used as the 'before' (section 3) — the before is this campaign's own fresh median. | improvement-registry.json IMP-018.measurement.{cubrid_block_median_s,connection_sweep_median_s,connection_sweep_reads_per_statement}; tpch-sspq/impl/fresh-baseline.json Q11 (blocks + divergence); raw/Q11/block[1-6]-headline.json; harness/headline_run.py:189 |
| Q14 | 3.117 | 0.000% | unmeasured | 0 | 0.0000 | NO_NUMERIC_BASIS. | improvement-registry.json IMP-018.q_relations |

### `IMP-019` — The selectivity of a comparison between two ATTRIBUTES of the same table is an unconditional hardcoded DEFAULT_COMP_SELECTIVITY = 0.1 -- the attribute-vs-attribute arm of qo_comp_selectivity() is an explicit empty '/* TODO: add histogram selectivity */' -- and because qo_discover_edges() then orders sarg terms by ASCENDING estimated selectivity, every column-vs-column comparison is evaluated BEFORE genuinely selective constant predicates, inverting the evaluation order exactly where the estimate is a placeholder

lane `performance` · feasibility 62.5 · benefit 64 · total 63.25 · expected saved 0.1076 s

| Query | Fresh base median (s) | Effect fraction | Evidence | Weight | Saved (s) | Basis | Citation |
|---|---|---|---|---|---|---|---|
| Q12 | 3.9505 | 5.447% | projection | 0.5 | 0.1076 | MD-2. 'about 0.220 s of the 4.039 s median at the measured U=5.89315' — a stated wall conversion from measured counts times a measured unit cost: 0.220/4.039 = 0.05447. Evidence level Projection, exactly as the registry labels it. | improvement-registry.json IMP-019.effect_range and IMP-019.evidence_type |
| Q17 | 0.1465 | 0.000% | unmeasured | 0 | 0.0000 | NO_NUMERIC_BASIS. | improvement-registry.json IMP-019.q_relations |

### `IMP-020` — Per-row scan output is materialised into fully-typed DB_VALUEs: for every row the heap scan re-reads the MVCC/representation header, re-resolves each attribute's domain and disk size, calls a type-specific mr_data_readval_* to build a DB_VALUE, and afterwards tears each one down with pr_clear_value -- where PostgreSQL deforms the same tuple into a flat Datum/isnull array using cached attribute offsets, with no per-value type object, no per-value domain init and no per-value teardown at all

lane `deferred_research` · feasibility 20.1 · benefit 0 · total 10.05 · expected saved 0.0000 s

| Query | Fresh base median (s) | Effect fraction | Evidence | Weight | Saved (s) | Basis | Citation |
|---|---|---|---|---|---|---|---|
| Q12 | 3.9505 | 0.000% | attribution | 0.7 | 0.0000 | MD-1 and lane. 'band A +3.2854 core-s and band B +1.4219 core-s, together +4.7073 core-s of Q12's +6.7771 core-s total query CPU excess (69.5%)' — core-second bands with no wall conversion. Deferred research carries no queue position regardless. | improvement-registry.json IMP-020.effect_range |

### `IMP-021` — A group-by-skip index scan plan is released at birth whenever the query contains a join, because qo_check_plan_on_info() tests index->head->groupby_skip -- a flag that is only ever written later, in qo_top_plan_new(), and only when the final top plan is itself a scan -- where the ORDER BY twin six lines above it tests a candidate predicate instead; so the sort-free streaming GROUP BY is unreachable behind any join and an unconditional SORT_GROUPBY is inserted

lane `performance` · feasibility 54.8 · benefit 0 · total 27.4 · expected saved 0.0000 s

| Query | Fresh base median (s) | Effect fraction | Evidence | Weight | Saved (s) | Basis | Citation |
|---|---|---|---|---|---|---|---|
| Q13 | 11.3345 | 0.000% | direct_ab | 1 | 0.0000 | MD-5. The 1.5617x (0.883 s -> 1.379 s, medians of 5) is measured on an ISOLATED 1,500,000-group aggregate constructed so that the only change is adding a 1-row cross join. It is a clean demonstration of the defect but not a measurement of Q13, and the registry supplies no quantified transfer to Q13's wall. | improvement-registry.json IMP-021.effect_range |

### `IMP-022` — NOT LIKE selectivity silently drops the anchored literal prefix: pattern_heuristic_selectivity() deliberately skips the fixed prefix on the documented assumption that 'it is already handled by a range predicate', which holds for PT_LIKE (rewritten into a range) but NOT for PT_NOT_LIKE (never rewritten), so every anchored NOT LIKE receives the same pattern-independent selectivity -- 0.0263974 on Q16's part.p_type, a 36.6x under-estimate that is identical for a pattern matching 3.3% of rows and for one matching 0%

lane `performance` · feasibility 68.8 · benefit 0 · total 34.4 · expected saved 0.0000 s

| Query | Fresh base median (s) | Effect fraction | Evidence | Weight | Saved (s) | Basis | Citation |
|---|---|---|---|---|---|---|---|
| Q16 | 2.918 | 0.000% | direct_ab | 1 | 0.0000 | MEASURED ZERO, stated by the registry: '36.61x selectivity error on one sarg, 39.24x on the part-side conjunct, 0.0000x measured wall effect ... upper bound on Q16 is zero seconds.' A LATENT plan-space defect: real, provably pattern-independent, and worth zero seconds on this workload. | improvement-registry.json IMP-022.effect_range |

### `IMP-023` — count(DISTINCT x) under a sort-based GROUP BY is executed as one temporary LIST FILE PER GROUP: every operand row is converted to its disk representation and appended to that group's file, and at each group boundary the file is sorted with duplicate elimination just to read back its tuple count -- and the whole per-row/per-group loop runs SINGLE-THREADED after the parallel sort phase, where PostgreSQL either dedups adjacent rows with one equality call or runs an in-memory per-group tuplesort inside the pipelined GroupAggregate

lane `performance` · feasibility 41.4 · benefit 76 · total 58.7 · expected saved 0.2654 s

| Query | Fresh base median (s) | Effect fraction | Evidence | Weight | Saved (s) | Basis | Citation |
|---|---|---|---|---|---|---|---|
| Q16 | 2.918 | 25.990% | upper_bound | 0.35 | 0.2654 | MD-4. 'Addressable band on Q16 = the serial-phase differential, 1.041 - 0.291 = 0.750 s of 2.886 s (25.99%) against the plan-controlled PostgreSQL leg.' This is a wall-seconds differential of the serial phase, and PostgreSQL's own 0.291 s on the plan-controlled leg is the argued achievable floor, satisfying the band rule. Carried at Upper bound weight 0.35 because it is an addressable band, and because sub-item (a) is bounded above by PostgreSQL's own measurement of the same optimization. | improvement-registry.json IMP-023.effect_range |

### `IMP-024` — CUBRID's GROUP BY planning path (pt_check_group_by in semantic_check.c, pt_to_groupby in xasl_generation.c) has no functional-dependency elimination pass, so Q10's GROUP BY key is carried at its full unreduced 7-column width even though 5 of the 7 columns (c_name, c_acctbal, c_phone, c_address, c_comment) are functionally dependent on the PK column (c_custkey) already present in the key, unlike PostgreSQL's remove_useless_groupby_columns() which reduces the same key to 2 columns (c_custkey, n_name)

lane `performance` · feasibility 38.2 · benefit 0 · total 19.1 · expected saved 0.0000 s

| Query | Fresh base median (s) | Effect fraction | Evidence | Weight | Saved (s) | Basis | Citation |
|---|---|---|---|---|---|---|---|
| Q10 | 7.044 | 0.000% | projection | 0.5 | 0.0000 | 'Unquantified-in-this-campaign for wall-time' — the registry states plainly that no controlled reduced-key A/B was run and only the key-byte-width comparison is measured. NO_NUMERIC_BASIS. | improvement-registry.json IMP-024.effect_range and IMP-024.evidence_type |

### `IMP-026` — Q10's GROUP BY sort-key string comparison re-runs a full byte-by-byte collation-weighted comparison (lang_fastcmp_byte, language_support.c:5453) from scratch on every compare call, with no cached/abbreviated prefix representation, unlike PostgreSQL's varstr_sortsupport()/varstr_abbrev_convert() (varlena.c) which packs the leading 8 bytes of a strxfrm() blob into a single Datum once per tuple and resolves most comparisons with one integer compare, falling back to a full byte compare only on a tie

lane `deferred_research` · feasibility 29.1 · benefit 0 · total 14.55 · expected saved 0.0000 s

| Query | Fresh base median (s) | Effect fraction | Evidence | Weight | Saved (s) | Basis | Citation |
|---|---|---|---|---|---|---|---|
| Q10 | 7.044 | 0.000% | attribution | 0.7 | 0.0000 | 'Unquantified as an isolated wall-time delta - report.md itself states this band cannot be separated from the surrounding sort in this campaign's measurement setup.' The 8.91% CPU-cycle share is the only quantified figure. NO_NUMERIC_BASIS. | improvement-registry.json IMP-026.effect_range |

### `IMP-027` — A join predicate that is an OR of per-relation AND groups yields no single-relation restriction, so every base scan under it runs unfiltered and the join drives the entire inner relation: CUBRID's only routes from an OR to a sarg are full CNF distribution (switched OFF by count_and_or() > 100 exactly when the predicate is large) and factoring of TEXTUALLY IDENTICAL conjuncts, neither of which fires on a TPC-H Q19-shaped disjunction, where PostgreSQL derives a redundant per-relation OR in extract_restriction_or_clauses() and cuts the driving scan 420.7x

lane `performance` · feasibility 41 · benefit 100 · total 70.5 · expected saved 43.6022 s

| Query | Fresh base median (s) | Effect fraction | Evidence | Weight | Saved (s) | Basis | Citation |
|---|---|---|---|---|---|---|---|
| Q19 | 43.964 | 99.177% | direct_ab | 1 | 43.6022 | '121.4491x wall on Q19 (46.514998 s -> 0.383000 s)', same-engine controlled, three gated blocks per configuration, corroborated by engine trace, /proc and independent COUNT(*) ground truth. Observed effect rate 1 - 0.383/46.514998 = 0.99177. The further 1.31x available from the FORM of the emitted clause is deliberately NOT added — section 2-b forbids rounding up a direct A/B. | improvement-registry.json IMP-027.effect_range and IMP-027.evidence_type |

### `IMP-029` — A constant IN-list predicate is evaluated per row by walking a generic DB_SET collection object element by element, materialising and freeing a fresh DB_VALUE copy of every element on every row, instead of being compiled once into a typed array (or hash) of the target domain

lane `performance` · feasibility 63.7 · benefit 68 · total 65.85 · expected saved 0.1637 s

| Query | Fresh base median (s) | Effect fraction | Evidence | Weight | Saved (s) | Basis | Citation |
|---|---|---|---|---|---|---|---|
| Q22 | 1.119 | 20.903% | attribution | 0.7 | 0.1637 | MD-2 (Q22 CPU/wall equivalence). 'the recoverable range is 1.14-2.41 core-s of 5.453622 core-s per statement', with PostgreSQL's 0.22160 core-s named as the achievable floor for the same work. Section 2-b requires the conservative LOWER bound of a range: 1.14/5.453622 = 0.20903. Converted to a wall share on the strength of IMP-031's measurement on the SAME Q22 statement, where the same kind of band was 2.02% of CPU and 2.05% of wall. Carried at Attribution weight 0.70 because the isolating measurement is a band probe rather than a whole-query A/B. | improvement-registry.json IMP-029.effect_range and IMP-029.evidence_type; IMP-031.effect_range for the Q22 CPU/wall equivalence |

### `IMP-030` — Comparing a NUMERIC column against a DOUBLE value coerces the NUMERIC to double per row by FORMATTING IT TO A DECIMAL STRING and calling atof() on it, then dividing by pow(10, scale); and avg(NUMERIC) returning DOUBLE is what forces that coercion into the row loop in the first place

lane `performance` · feasibility 63.8 · benefit 52 · total 57.9 · expected saved 0.0258 s

| Query | Fresh base median (s) | Effect fraction | Evidence | Weight | Saved (s) | Basis | Citation |
|---|---|---|---|---|---|---|---|
| Q22 | 1.119 | 2.310% | direct_ab | 1 | 0.0258 | MD-2 (Q22 CPU/wall equivalence). '0.126-0.190 core-s per statement (the observed replicate range), i.e. 2.3-3.5% of CUBRID's 5.453622 core-s', paired B6/B7, 4 replicates per engine, row set held identical at 190,691. Conservative lower bound of the range: 0.126/5.453622 = 0.02310, converted to a wall share on IMP-031's same-statement CPU/wall equivalence. | improvement-registry.json IMP-030.effect_range and IMP-030.evidence_type; IMP-031.effect_range for the Q22 CPU/wall equivalence |

### `IMP-031` — An EXISTS / NOT EXISTS subquery is compiled as a table-producing XASL that must fetch one whole TUPLE of the subquery's select list, so the membership probe projects a data column, the index scan fails the covering-index test and performs a data-row lookup per matching key -- even though existence needs no column value at all

lane `performance` · feasibility 54.4 · benefit 48 · total 51.2 · expected saved 0.0229 s

| Query | Fresh base median (s) | Effect fraction | Evidence | Weight | Saved (s) | Basis | Citation |
|---|---|---|---|---|---|---|---|
| Q22 | 1.119 | 2.050% | direct_ab | 1 | 0.0229 | '0.11004 core-s per statement on Q22, measured, i.e. 2.02% of CUBRID's CPU and 2.05% of its wall.' The wall share is stated directly by the registry, so no conversion is needed: 0.0205. Explicitly a LOWER bound on the general effect (on Q22 the orders heap pages are buffer-resident, trace ioread 0, so the eliminated lookups cost only CPU); the lower bound is what is used. | improvement-registry.json IMP-031.effect_range and IMP-031.evidence_type |

