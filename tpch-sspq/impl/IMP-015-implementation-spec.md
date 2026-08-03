# IMP-015 implementation spec — runtime-truth parallelism decision for the group-by fallback sort

Status: specification only, produced by a grilling session on 2026-08-03.
**This document does not authorize Phase 2.** The IMPL-SSOT phase gate stands: no engine
code is written until the user approves the Phase 1B ranking and queue. When Phase 2
starts for IMP-015, this spec is lifted into the candidate worktree's
`implementation-plan.md` (IMPL-SSOT §5-c) after the section-A assumptions are verified
against the pinned source.

Where this spec and the measurement-campaign registry's `implementation_direction`
disagree, **this spec supersedes it** (the registry is frozen input evidence per
IMPL-SSOT §1-b and is not edited). The specific divergence: the registry/card §4
proposed carrying runtime hash state inside `SORT_LISTFILE_PX_ARG` and editing the
condition in `external_sort.c`; this spec instead computes the truth at each caller and
leaves `external_sort.c` unmodified (decision D2).

Upstream scope-check gate (§5-e): **not applicable** — IMP-015 is not in
`triage-adjustments.json` `upstream_scope_gates`, and the card's §9 records that no CBRD
issue/PR in the pinned history touches the `SORT_GROUP_BY` branch of
`sort_check_parallelism()`.

---

## Decisions (D1–D5)

### D1 — Scope: (a) + (b) as one unit; (c) dropped
- **(a)** main group-by sort: stop refusing parallelism on the plan-time flag once the
  runtime has abandoned hashing (`HS_REJECT_ALL`).
- **(b)** partial-list sort of spilled hash entries (`query_executor.c:5571-5573`),
  currently serial by construction (`px == NULL`): pass a px and make it
  parallelism-eligible.
- **(c)** (skip post-`HS_REJECT_ALL` hash-path work, ~1.32% profile) is **dropped** —
  no measured effect of its own, pure scope growth.
- Why (a)+(b) together: in the `hash: partial` path both sorts execute; Q10's
  verification gate (parallel-workers sub-line + ioread ~0) plausibly needs both.
- Trade-off: (b) has no direct A/B of its own (the Q10 control had no spill; Q18
  explicitly has no isolating lever). (b)'s effect claim is therefore bounded by Q18's
  upper-bound framing, never stated as a measured factor.

### D2 — Mechanism: caller-side truth, per-call-site formulas; `external_sort.c` unchanged
The `hash_eligible` contract (`external_sort.h:172`: "if non-zero, parallelism must be
skipped") is kept intact; each caller becomes responsible for filling it with the truth
of its own call site — the same pattern the tree already uses for ANALYTIC
(`query_executor.c:21886`, `anl_px.hash_eligible = 0`).

- **(a) main sort (`query_executor.c:5657`)**:
  `gby_px.hash_eligible = gbstate.hash_eligible && (runtime hash state != HS_REJECT_ALL)`.
  The refusal rationale ("a live hash pass may make this sort small or unnecessary")
  stays valid while hashing is alive and dissolves exactly when the executor abandons it.
  Reading the state once at the caller is sound: `HS_REJECT_ALL` has a single assignment
  site (`:4845`, the selectivity test) and is latched (`:4648`); transitions are
  one-way ACCEPT→REJECT and the scan phase has ended before the sort is invoked.
- **(b) partial-list sort (`query_executor.c:5571-5573`)**: construct and pass a
  `SORT_LISTFILE_PX_ARG` with `hash_eligible = 0` — **unconditionally eligible,
  not state-gated**. Rationale: if this sort is running, the hash pass is over and
  spills exist; "hash may still cover it" is incoherent at this call site. Critically,
  in the parallel-scan path workers hash-aggregate unconditionally (no 0.5 selectivity
  test) and the leader merges their spilled partials — there the state is *not*
  `HS_REJECT_ALL`, so a state-gated (b) would stay serial exactly where Q18-class
  workloads hurt most.
- Why not the registry's callee-side variant: layering (storage layer learning executor
  hash-state concepts), a header-contract rewrite, and a 3-file blast radius vs 1 file.
- Escape hatch: `SORT_LISTFILE_PX_ARG` is an internal struct; if IC-5 later needs richer
  state in the callee, adding a field then is cheap.

### D3 — Sequencing: IMP-015 first, IC-5 (merge/finalize parallelization) strictly after
IC-5 (Notion candidate ⑤, `external_sort.c:5232, 5829, 5841`; difficulty high, risk
high) is **not** part of this diff. IMP-015 lands and is re-measured first; the
re-measured serial residue (Q18's leader-merge share) becomes IC-5's baseline. Combining
them would mix a low-risk measured fix with high-risk new machinery, destroy effect
attribution, and make regressions unbisectable.

### D4 — Order-sensitivity: expected nil new exposure, verified at source (A4)
The set newly reaching the parallel sort is exactly {plan-time hash-eligible ∧ runtime
abandonment or spill}. Order-sensitive aggregates (`GROUP_CONCAT`, order-dependent
MIN/MAX under `agg_hash_respect_order=y`) are believed **not hash-eligible** in the
first place, so they cannot enter that set; card verification criterion 3 then
downgrades from gate to sanity check. This is user recollection, so it stays an
assumption to verify (A4) and criterion 3 is treated as a **gate until A4 is confirmed**.

### D5 — `agg_hash_respect_order` untouched; parallel-time `n` deferred to IC-5
Flipping it to `n` under parallelism unlocks nothing for IMP-015 (the fallback sort
already emits key-sorted order) and would make user-visible GROUP BY order depend on a
runtime parallelism decision, contradicting the respect-order contract the registry
records under IMP-016. It becomes an explicit IC-5 design item, to be justified by
measurement there.

### D6 — Two-layer test cases, housed in the campaign harness only
A result-comparing SQL TC alone cannot detect this fix being silently reverted — the fix
changes a parallelism decision, not semantics, so results stay identical either way.
Therefore two layers, both living in the candidate branch's campaign harness (no
upstream TC-repo migration in this campaign — user decision):

1. **SQL correctness TCs** (CTP sql style): a group-by battery that deterministically
   arms the new path — (a) high-selectivity data (> 2000 tuples, > 50% distinct groups
   in the sample) to force `HS_REJECT_ALL`; (b) a tiny `max_agg_hash_size` conf override
   to force eviction/spill so the partial-list sort runs; an order-sensitive control
   (`GROUP_CONCAT`, order-dependent MIN/MAX) — all compared for identical results
   against the serial reference (`/*+ NO_HASH_AGGREGATE */` and/or parallelism off).
2. **Shell TC (arming proof)** (CTP shell style): same data, trace on, assert by grep
   that the trace shows `hash: partial` **and** a `parallel workers: N >= 2` sub-line
   (and, for the (b) case, that the spill-sort statement gains one). This is the
   regression detector for the mechanism itself; trace timing noise makes this
   unsuitable for byte-compared sql answers, hence the shell layer.

TC data volume depends on A5: whether `compute_parallel_degree()`'s minimum input-size
threshold can be lowered by conf. If yes, the battery stays small; if not, size the TC
table so the sort input clears the threshold (Q11's 1,516 pages measurably did not).

---

## A. Assumptions to verify against pinned source (before first edit)

| # | Assumption | Expected answer | If refuted |
|---|---|---|---|
| A1 | The aggregate hash state enum has exactly two values, `HS_ACCEPT_ALL` / `HS_REJECT_ALL` (`query_dump.c:3944-3951` maps only these; `hash: false` = not eligible, not a state) | holds | re-derive the (a) formula per extra state; update this spec |
| A2 | The sort of worker-spilled partial hashes in the parallel-scan unconditional-hash path is the `:5571-5573` call (no third sort call site) | holds | extend (b) to the real call site(s); re-estimate LOC band |
| A3 | The parallel sort machinery supports the partial-record type (`qfile_compare_partial_sort_record` inputs) | holds | **stop-and-report**: (b) needs new machinery, which is out of this candidate's scope; user decides whether (a) ships alone |
| A4 | Hash eligibility (`pt_to_buildlist_proc()`, `xasl_generation.c:16556-16568`) excludes order-sensitive aggregates; `agg_hash_respect_order` does not admit them | excluded | criterion 3 stays a hard gate; add order-preservation proof for the parallel fallback sort before proceeding |
| A5 | `compute_parallel_degree()`'s minimum sort-input-size threshold can be lowered by conf, so the D6 TC battery can stay small | tunable | size the TC table up until the sort input clears the built-in threshold |

---

## B. Mapping to `implementation-plan.md` (IMPL-SSOT §5-c items 1–10)

1. **Hypothesis (falsifiable).** The serial group-by fallback sort under `hash: partial`
   is caused solely by the plan-time `hash_eligible` flag reaching
   `sort_check_parallelism()`; substituting per-call-site runtime truth parallelizes it,
   moving Q10 native median wall to ≤ 5.70 s (measured control 5.426 s + 1.22% block
   spread margin) with byte-identical results.
2. **CUBRID `file:line` to change.** `src/query/query_executor.c:5657` (px flag formula)
   and `:5571-5573` (construct + pass px). **Unchanged but load-bearing:**
   `external_sort.c:5228-5234`, `external_sort.h:172`, `query_executor.c:4845/:4648/:4862`,
   `query_dump.c:3944-3951`, ANALYTIC precedent `query_executor.c:21886`.
3. **PostgreSQL reference (pinned `5713b437`).** `planner.c:8019/8083/7793/7588`
   (gather_grouping_paths: sort parallelism independent of hashing);
   `nodeAgg.c:1866/1907` (budget breach ⇒ spill mode, never a strategy flip or a
   parallelism veto).
4. **Changed files / LOC band.** 1 file (`query_executor.c`). LOC low 2 / likely 8 /
   high 25 (px construction for (b) dominates). §5-d hard stop at 150% of high = 38 LOC
   or any unanticipated subsystem.
5. **Expected metric signature.** Q10 native trace: `GROUPBY (... hash: partial,
   sort: true ...)` gains `(parallel workers: N ≥ 2)` sub-line; group-by sort ioread → ~0;
   TWU 3.42875 → ≥ 3.70. Q18: `qfile_compare_partial_sort_record` profile share (3.27%)
   drops; 1-unit phase share (63.4%) shrinks — observation, not a gate. Direction of all
   counters per §6-c capture list.
6. **Correctness risk & testing.** One real hazard: input-order sensitivity (D4/A4).
   Tests: the five mandatory §6-b checks, where check 1 (candidate-specific regression
   test) is the D6 two-layer battery — SQL correctness TCs plus the shell arming-proof
   TC (trace must show `hash: partial` with `parallel workers: N >= 2`), housed in the
   campaign harness only; order-sensitive aggregate suite (`GROUP_CONCAT`,
   order-dependent MIN/MAX under `agg_hash_respect_order=y`) vs serial output; Q10
   20-row byte-identity under the section-11 comparator.
7. **Target queries.** Q10 (primary gate, measured 1.313675x route); Q15 (armed,
   lower-bound corroboration); Q18 (armed, upper-bound observation only — no gate, no
   isolating A/B exists).
8. **Negative controls (must not change).** Q11 (null by size: 1,516-page sort,
   `compute_parallel_degree` returns 1 regardless — must stay null); Q16 (GROUPBY
   already parallel; its 1.041 s post-sort serial loop belongs to IMP-023 and must not
   move); Q01/Q03/Q05 group-by wall and plan shape; plan shapes campaign-wide
   (estimated costs unchanged — this is an executor-only change).
9. **Overlap / dependency.** IMP-016: genuine ALTERNATIVE for Q10's 1.313675x — at most
   one is counted; IMP-015 is the measured route. IMP-017: predecessor of IMP-016's
   memory arm, orthogonal here. IMP-021: anti-additive (removes the sort this
   parallelizes). IMP-023: separate post-sort consumer loop. IC-5: strictly sequenced
   after (D3); consumes IMP-015's re-measured baseline. `agg_hash_respect_order`
   parallel-time policy: deferred to IC-5 (D5).
10. **Rollback.** Single revert of the candidate-branch commit; no XASL serialization,
    persistent format, or lock-protocol surface (any such contact triggers §5-d
    stop-and-report).

---

## C. Verification-criteria disposition (card §5 criteria 1–5)

| Criterion | Disposition |
|---|---|
| 1. Q10 trace parallel sub-line + ioread ~0 + byte-identical 20 rows | gate, unchanged |
| 2. Q10 median ≤ 5.70 s, U ≥ 3.70 | gate, unchanged (paired B→P→P→B per §6-c/6-d) |
| 3. order-sensitive aggregate suite | gate until A4 confirmed; sanity check after |
| 4. Q01/Q03/Q05 no regression, plan shapes unchanged | gate, unchanged |
| 5. worker-pool pressure | **no design item** — admission is the existing `try_reserve_workers()` path already exercised by the Q10 control block (parallel scan + 5-worker sort coexisted at 5.426 s); gate is the standard Q01–Q22 stream wall no-regression under §12 WARM discipline. (b) may raise peak worker demand vs the control (spill sort did not exist there); the stream measurement is the detector, degradation to degree 1 the built-in relief. |
