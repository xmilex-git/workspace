#!/usr/bin/env python3.11
"""Render `tpch-sspq/impl/priority-ranking.md` from `priority-ranking.json`.

Section 2 opens with "the methodology below is normative and MUST be reproduced
verbatim in `tpch-sspq/impl/priority-ranking.md`". This renderer therefore does not
paraphrase it: it extracts section 2 of the pinned `tpch-sspq/IMPL-SSOT.md` byte for
byte at render time and embeds it, so the reproduction cannot drift from the pin and
the drift check is mechanical rather than editorial.

Section 2-e fixes the ranking table's columns exactly; they are emitted in that order
and no others.

Usage: render_ranking_md.py priority-ranking.json [IMPL_SSOT_PATH] > priority-ranking.md
"""
import json
import os
import sys

OUT = []


def w(s=""):
    OUT.append(s)


def extract_section_2(ssot_path):
    """Section 2 of the pinned norm, verbatim, from its heading to section 3's."""
    with open(ssot_path) as f:
        lines = f.read().split("\n")
    start = end = None
    for i, ln in enumerate(lines):
        if ln.startswith("## 2. Candidate scoring methodology"):
            start = i
        elif start is not None and ln.startswith("## 3. "):
            end = i
            break
    if start is None or end is None:
        raise SystemExit("could not locate section 2 in " + ssot_path)
    body = lines[start:end]
    while body and body[-1].strip() in ("", "---"):
        body.pop()
    return "\n".join(body)


def cell(x):
    """One markdown table cell, with the pipe escaped on EVERY path.

    The escaping has to be uniform or it is not a guarantee. An earlier revision
    escaped only the string path and let the list path join elements raw, so a list
    field whose element happened to contain a pipe would have silently split the row
    into an extra column. Column 10 (predecessor / alternative / containment) does
    pass raw lists, so that hazard was reachable and merely latent — no element
    currently contains a pipe. Escaping is now applied once, at the end, to whatever
    the value was reduced to.
    """
    if x is None:
        return "—"
    if isinstance(x, float):
        return _esc(f"{x:g}")
    if isinstance(x, list):
        return _esc("; ".join(str(i) for i in x)) if x else "—"
    return _esc(str(x))


def _esc(s):
    return s.replace("|", "\\|").replace("\n", " ")


def fmt_pct(x):
    return "—" if x is None else f"{100 * x:.3f}%"


def main():
    with open(sys.argv[1]) as f:
        d = json.load(f)
    ssot = sys.argv[2] if len(sys.argv) > 2 else os.path.join(
        os.path.dirname(os.path.abspath(sys.argv[1])), "..", "IMPL-SSOT.md")
    C = d["candidates"]
    medians = d["fresh_base_medians_seconds"]
    mde = d["corrected_mde"]

    w("# Phase 1B priority ranking — campaign `tpch-sspq-impl-r1-20260803`")
    w()
    w(f"Generated {d['generated_utc']}. Pinned norm `tpch-sspq/IMPL-SSOT.md` commit "
      f"`{d['impl_ssot_commit']}`, blob `{d['impl_ssot_blob']}` (AMEND-A..G).")
    w()
    w("**Phase gate.** This document is a Phase 1 deliverable. Phase 2 — writing any engine "
      "code — MUST NOT begin until the user has explicitly approved this ranking and the "
      "resulting candidate queue. There is no implicit promotion from Phase 1 to Phase 2.")
    w()
    cs = d.get("calibration_status") or {}
    if cs.get("STOP_AND_REPORT"):
        w("---")
        w()
        w("## ⛔ STOP-AND-REPORT — the restart-variance combination rule is a user decision")
        w()
        w("**IMPL-SSOT section 6-d-1 escalation, section 11-a.** The six calibration points "
          "support **neither** a single pooled factor **nor** a defensible "
          "wall-magnitude-dependent one. Section 6-d-1 is explicit that in this case the "
          "worker reports the calibration data and asks, and **MUST NOT pick a factor to "
          "keep the sweep moving**.")
        w()
        w("Nothing here was picked for convenience. So that the rest of Phase 1 could still "
          "be produced and read, the corrected MDE below was computed under the "
          f"**most conservative** of the six measured factors "
          f"(**{cs.get('provisional_value'):.4f}x**). That choice cannot under-correct, and "
          "under-correction is the single failure mode section 6-d-1 exists to prevent — an "
          "MDE smaller than real A/B noise causes **false accepts**.")
        w()
        w("**Consequence for reading this document:** every `UNPROVABLE_ON_THIS_HOST` verdict "
          "is provisional and errs toward flagging. A candidate marked provable here is "
          "provable under *every* candidate rule; a candidate marked `UNPROVABLE_ON_THIS_HOST` "
          "may become provable if a smaller factor is chosen.")
        w()
        w("### Why neither rule fits")
        w()
        for para in (cs.get("reason") or "").split("\n"):
            if para.strip():
                w(f"- {para.strip()}")
        w()
        loo = cs.get("leave_one_out_pearson_r") or {}
        if loo:
            w("Leave-one-out pearson r on ln(inflation) vs ln(wall) — the association is "
              "carried by individual points, which is what a genuine relationship at n=6 "
              "must not do:")
            w()
            w("| dropped query | r on the remaining five |")
            w("|---|---:|")
            for q in sorted(loo):
                v = loo[q]
                mark = " **fails the 0.70 threshold**" if (v is None or abs(v) < 0.70) else ""
                w(f"| {q} | {'—' if v is None else f'{v:+.4f}'}{mark} |")
            w()
        w("### The three candidate rules, side by side")
        w()
        w("| Rule | Value / form | Status |")
        w("|---|---|---|")
        for name, r in (cs.get("candidate_rules_for_user_decision") or {}).items():
            if name == "wall_magnitude_dependent":
                val = f"inflation(wall) = max(1, exp({r.get('a'):.4f} + {r.get('b'):.4f}·ln wall))"
                st = (f"full-sample r={r.get('full_sample_pearson_r'):.4f}, residual cut "
                      f"{r.get('residual_reduction'):.1%}, robust under leave-one-out: "
                      f"**{r.get('robust_under_leave_one_out')}**")
            elif name == "single_pooled_geometric_mean":
                val = f"{r.get('value'):.4f}x (geometric mean)"
                st = (f"factor spread ratio {r.get('spread_ratio'):.2f}; within the declared "
                      f"stop ratio of 10: **{r.get('within_declared_stop_ratio')}**")
            else:
                val = f"{r.get('value'):.4f}x"
                st = r.get("property", "")
            w(f"| `{name}` | {val} | {st} |")
        w()
        w("A fourth option exists and is not a rule choice: **collect more calibration "
          "blocks**. The instability's mechanism is that the ratio's denominator — the "
          "fast-regime paired CV — is a 3-pair estimate of a ~0.1% dispersion for the two "
          "queries carrying the extreme factors, so more blocks per query would shrink the "
          "denominator's uncertainty directly rather than model around it.")
        w()
        w("Per-query corrected MDE under each candidate rule is tabulated in the "
          "**Expected effect against the CORRECTED MDE** section below.")
        w()
    w("## Inputs (section 2-b-1 requires all three)")
    w()
    w("| # | Input | Role |")
    w("|---|---|---|")
    w("| 1 | `tpch-sspq/impl/feasibility-assessment.json` | frozen Phase 1B feasibility half; immutable |")
    w("| 2 | `tpch-sspq/impl/fresh-baseline.json` | the Phase 1A fresh baseline; the source of every `fresh_base_median_q` |")
    w("| 3 | `tpch-sspq/impl/triage-adjustments.json` | the user-led triage's corrections to benefit inputs, lanes and pre-implementation gates |")
    w()
    w("Supporting: `tpch-sspq/impl/restart-variance-calibration.json` (the section 6-d-1 "
      "corrected MDE this ranking flags against), `tpch-sspq/impl/benefit-inputs.json` (the "
      "per-term judgment, separated from the arithmetic), "
      "`tpch-sspq/impl/implementation-results.json` (this campaign's own recorded verdicts), "
      "`tpch-sspq/impl/diagnosis/Q15-parallel-non-arming.md` (this run's diagnosis, which "
      "changes two of IMP-015's target-query terms).")
    w()
    w("A ranking produced without reading input 3 is invalid (section 2-b-1). The three "
      "inputs are independent: `triage-adjustments.json` does not modify "
      "`feasibility-assessment.json`, which remains immutable.")
    w()
    w("---")
    w()
    w("## Methodology, reproduced verbatim from the pinned IMPL-SSOT section 2")
    w()
    w("> Reproduced byte for byte by `render_ranking_md.py`, which extracts section 2 from "
      "the pinned file at render time. It is not paraphrased and cannot drift from the pin.")
    w()
    w(extract_section_2(ssot))
    w()
    w("---")
    w()
    w("## Methodology decisions this ranking had to make")
    w()
    w("Section 2-b tells the ranking to argue a removable fraction rather than assume one, "
      "and AMEND-F makes that operational by naming IMP-001 and IMP-013. Applying it "
      "consistently across all 31 candidates forced five decisions. They are recorded here "
      "because each one changes numbers.")
    w()
    for m in d["methodology_decisions"]:
        w(f"### {m['id']} — {m['decision']}")
        w()
        w(m["reason"])
        for k in ("consequence", "q22_equivalence"):
            if m.get(k):
                w()
                w(f"*{k.replace('_', ' ').capitalize()}:* {m[k]}")
        w()
    w("---")
    w()
    w("## The ranking (section 2-e columns, exactly)")
    w()
    w("Rows appear in rank order. Section 2-e fixes twelve columns and says \"exactly these columns\", so the ordinal is not a thirteenth column here — explicit queue positions are in the **Candidate queue** table below.")
    w()
    ranked = sorted([i for i in C if C[i].get("rank")], key=lambda i: C[i]["rank"])
    # Section 2-e fixes the columns as "exactly these columns" and lists twelve. An
    # earlier revision prepended a 13th "Rank" column; the ordinal is instead carried
    # by row order here and by explicit positions in the Candidate queue table below,
    # so this table now matches the twelve literally.
    hdr = ["IMP ID", "Lane", "Fresh affected-query baseline (s)",
           "Expected effect + evidence level", "Expected saved seconds",
           "LOC low/likely/high", "Files and subsystems touched",
           "Difficulty and risk rationale", "Feasibility / Benefit / Total",
           "Predecessor / alternative / containment", "Eligibility and blocker",
           "Ranking rationale"]
    w("| " + " | ".join(hdr) + " |")
    w("|" + "---|" * len(hdr))
    for imp in ranked:
        r = C[imp]
        base = "; ".join(f"{t['q']} {t['fresh_base_median_seconds']:.4f}"
                         for t in r["per_query_terms"]
                         if t.get("fresh_base_median_seconds") is not None) or "—"
        eff = "; ".join(f"{t['q']} {fmt_pct(t['conservative_effect_fraction'])} "
                        f"({t['evidence_level']} w={t['evidence_weight']:g})"
                        for t in r["per_query_terms"]
                        if t.get("conservative_effect_fraction")) or "no non-zero term"
        rel = " / ".join([cell(r.get("predecessors")), cell(r.get("alternatives")),
                          cell(r.get("containment"))])
        elig = cell(r.get("eligibility"))
        extra = []
        if r.get("blocker"):
            extra.append("BLOCKER: " + r["blocker"])
        if r.get("hard_stop_flag"):
            extra.append("section 5-d hard stop: " + r["hard_stop_flag"])
        if r.get("write_path_flag"):
            extra.append("write path — section 11-a stop-and-report BEFORE implementing")
        if r.get("upstream_scope_gate"):
            extra.append("section 5-e upstream scope-check gate")
        if r.get("unprovable_on_this_host_queries"):
            extra.append("UNPROVABLE_ON_THIS_HOST on " + ", ".join(r["unprovable_on_this_host_queries"]))
        if r.get("campaign_status"):
            extra.append(r["campaign_status"])
        if r.get("triage_note"):
            extra.append("triage: " + r["triage_note"])
        if r.get("baseline_caveat"):
            extra.append("BASELINE CAVEAT: " + r["baseline_caveat"])
        if r.get("acceptance_criterion_caveat"):
            extra.append("acceptance-criterion caveat: " + r["acceptance_criterion_caveat"])
        if r.get("no_numeric_basis"):
            extra.append("NO_NUMERIC_BASIS")
        if extra:
            elig += " — " + " | ".join(extra)
        w("| " + " | ".join([
            f"`{imp}`", r["lane"], cell(base), cell(eff),
            f"{r['expected_saved_seconds']:.4f}",
            f"{r.get('loc_low')}/{r.get('loc_likely')}/{r.get('loc_high')}",
            # Section 2-e column 7 is ONE column ("files and subsystems touched").
            # An earlier revision spliced a literal " | " between two cell() calls, which
            # bypassed cell()'s pipe escaping and emitted a 13th cell on every data row
            # against a 12-column header — a malformed table that failed the very contract
            # this section claims to satisfy. Both halves are now joined INSIDE one value
            # and passed through cell(), so any pipe in the data is escaped.
            cell("files: " + (", ".join((r.get("files_affected") or [])[:4]) or "—")
                 + "; subsystems: " + (", ".join(r.get("subsystems_affected") or []) or "—")),
            cell(r.get("difficulty_and_risk_rationale")),
            f"{cell(r.get('feasibility_score'))} / {cell(r.get('benefit_score'))} / {cell(r.get('total_score'))}",
            cell(rel), cell(elig), cell(r.get("ranking_rationale")),
        ]) + " |")
    w()
    w("### Not ranked, with lane and rationale")
    w()
    w("Section 4-a: the overall implementation ranking covers the **Performance lane only**. "
      "Enabler, Diagnostic and Deferred-research candidates are listed with their lane and "
      "rationale but carry no queue position, and `external_tracking` candidates are "
      "excluded from the queue without that being a benefit judgment.")
    w()
    w("| IMP ID | Lane | External ref | Expected saved seconds | Eligibility | Rationale |")
    w("|---|---|---|---|---|---|")
    for imp in sorted(i for i in C if not C[i].get("rank")):
        r = C[imp]
        w(f"| `{imp}` | {r['lane']} | {cell(r.get('external_reference'))} | "
          f"{cell(r.get('expected_saved_seconds'))} | {cell(r.get('eligibility'))}"
          + (f" — BLOCKER: {r['blocker']}" if r.get("blocker") else "")
          + f" | {cell(r.get('ranking_rationale'))} |")
    w()
    w("---")
    w()
    w("## Candidate queue (section 4-a ordering)")
    w()
    w("A required enabler is inserted **immediately ahead of** the dependent candidate it "
      "unblocks; it inherits its position from the dependent, never from its own benefit "
      "score (which is typically zero).")
    w()
    w("| Position | IMP ID | Lane | Note |")
    w("|---|---|---|---|")
    for i, q in enumerate(d["queue"], 1):
        w(f"| {i} | `{q['imp_id']}` | {q['lane']} | {cell(q.get('reason') or ('rank ' + str(q.get('rank'))))} |")
    w()
    w("---")
    w()
    w("## Expected effect against the CORRECTED MDE (section 6-d)")
    w()
    w("The Phase 1B ranking MUST carry every candidate's expected effect against the MDE of "
      "its target queries, and the flag is raised **at ranking time** so it is known before "
      "a candidate is queued rather than discovered inconclusive after twelve pairs. The MDE "
      "used is the section 6-d-1 **corrected** MDE, never the raw fast-regime MDE. "
      "`UNPROVABLE_ON_THIS_HOST` does not delete a candidate; it states that this host "
      "cannot decide it.")
    w()
    w("| IMP ID | Query | Predicted effect | Corrected MDE | Verdict |")
    w("|---|---|---|---|---|")
    any_row = False
    for imp in sorted(C):
        for row in C[imp].get("mde_comparison", []):
            if row["verdict"] in ("no_predicted_effect",):
                continue
            any_row = True
            w(f"| `{imp}` | {row['q']} | {fmt_pct(row['predicted_effect_fraction'])} | "
              f"{fmt_pct(row['corrected_mde'])} | "
              f"{'**UNPROVABLE_ON_THIS_HOST**' if row['verdict'] == 'unprovable' else row['verdict']} |")
    if not any_row:
        w("| — | — | — | — | no candidate carries a non-zero predicted effect |")
    w()
    w("### Per-query corrected MDE")
    w()
    alt = d.get("corrected_mde_under_each_candidate_rule") or {}
    rules = sorted({r for v in alt.values() for r in (v or {})})
    if rules:
        w("| Query | Fresh base median (s) | Corrected MDE (applied) | "
          + " | ".join(f"under `{r}`" for r in rules) + " |")
        w("|---|---|---|" + "---|" * len(rules))
        for q in sorted(medians):
            m = medians[q]
            cells = [fmt_pct((alt.get(q) or {}).get(r)) if alt.get(q) else "measured directly"
                     for r in rules]
            w(f"| {q} | {'—' if m is None else f'{m:.4f}'} | {fmt_pct(mde.get(q))} | "
              + " | ".join(cells) + " |")
        w()
        w("`measured directly` marks Q01–Q06, which use their **measured** restart-regime "
          "paired CV rather than an inflated fast-regime one (section 6-d-1 step 6), so no "
          "combination rule applies to them and the pending decision cannot move them.")
    else:
        w("| Query | Fresh base median (s) | Corrected MDE |")
        w("|---|---|---|")
        for q in sorted(medians):
            m = medians[q]
            w(f"| {q} | {'—' if m is None else f'{m:.4f}'} | {fmt_pct(mde.get(q))} |")
    w()
    w("**The 6.0 core-s/s external-CPU gate does not guarantee that this host can resolve "
      "small effects.** It bounds only gross contention. Resolution is carried by the paired "
      "design and by these honest per-query MDE figures. This limitation must be restated in "
      "every report that cites a sub-MDE effect.")
    w()
    w("---")
    w()
    w("## Overlap and containment clusters (section 4-c)")
    w()
    w("Within a cluster the `expected_saved_seconds` of the **highest-scoring member only** "
      "is counted toward any campaign-level total; other members are marked "
      "`SUPPRESSED_OVERLAP` and excluded from every sum. Cluster totals are never produced "
      "by addition across members.")
    w()
    w("| Type | Members | Scope | Queued | Why |")
    w("|---|---|---|---|---|")
    for c in d["clusters"]:
        w(f"| {c['type']} | {', '.join('`' + m + '`' for m in c['members'])} | "
          f"{cell(c.get('query_scope'))} | {cell(c.get('queued') or c.get('container') or c.get('order'))} | "
          f"{cell(c['why'])} |")
    w()
    w("---")
    w()
    w("## Sensitivity and ranking stability (section 2-d)")
    w()
    s = d["sensitivity"]
    w(f"Every evidence weight was perturbed by ±{s['perturbation']} (clamped to `[0, 1]`) in "
      f"both the pessimistic and the optimistic direction and the ranking recomputed.")
    w()
    w(f"- Base top 5: {', '.join('`' + i + '`' for i in s['base_top5'])}")
    for k, v in s["perturbed"].items():
        w(f"- {k}: {', '.join('`' + i + '`' for i in v['top5'])} — "
          f"identity changed: {v['identity_changed']}, order changed: {v['order_changed']}")
    w()
    if s["RANKING_UNSTABLE"]:
        w("**`RANKING_UNSTABLE`.** The identity or the order of the top 5 changes materially "
          "under perturbation. Candidates that moved in or out: "
          + ", ".join('`' + i + '`' for i in s["candidates_that_swapped"])
          + ". The queue order in that region is **not evidence-supported**. "
          "`RANKING_UNSTABLE` does not block Phase 1 completion; it blocks silent reliance "
          "on a fragile order.")
    else:
        w("The top 5 is stable in identity and order under both perturbations, so "
          "`RANKING_UNSTABLE` is **not** raised.")
    w()
    w("---")
    w()
    w("## ID-unassigned new candidates — user decision required")
    w()
    w("Section 1-b: this campaign allocates no new IMP IDs unless the user directs it to. "
      "`next_id` is `IMP-032` and is consumed. Findings that would otherwise become "
      "candidates are raised here instead.")
    w()
    for n in d["id_unassigned_new_candidates"]:
        w(f"### {n['label']} — {n['title']}")
        w()
        w(f"- **ID**: {n['id']}")
        w(f"- **Source**: `{n['source']}`")
        w(f"- **Problem**: {n['problem']}")
        for k, v in (n.get("two_arms") or {}).items():
            w(f"- **{k} arm**: {v}")
        w(f"- **Relations**: {json.dumps(n['relations'], ensure_ascii=False)}")
        w(f"- **Target queries**: {', '.join(n['target_queries'])}")
        w(f"- **Expected effect**: {n['expected_effect']}")
        w(f"- **Decision requested**: {n['decision_requested']}")
        w()
    w("---")
    w()
    w("## Per-candidate benefit derivation (every non-zero term cites its raw evidence)")
    w()
    w("Section 2-b: every non-zero term MUST cite the raw evidence pointer that produced it. "
      "Zero terms are listed too, so the reader can see them, but they add nothing.")
    w()
    for imp in sorted(C):
        r = C[imp]
        if not r.get("per_query_terms"):
            continue
        w(f"### `{imp}` — {cell(r.get('root_cause_title'))}")
        w()
        w(f"lane `{r['lane']}` · feasibility {cell(r.get('feasibility_score'))} · "
          f"benefit {cell(r.get('benefit_score'))} · total {cell(r.get('total_score'))} · "
          f"expected saved {r['expected_saved_seconds']:.4f} s")
        w()
        w("| Query | Fresh base median (s) | Effect fraction | Evidence | Weight | Saved (s) | Basis | Citation |")
        w("|---|---|---|---|---|---|---|---|")
        for t in r["per_query_terms"]:
            w(f"| {t['q']} | {cell(t['fresh_base_median_seconds'])} | "
              f"{fmt_pct(t['conservative_effect_fraction'])} | {t['evidence_level']} | "
              f"{t['evidence_weight']:g} | {t['expected_saved_seconds']:.4f} | "
              f"{cell(t.get('basis'))} | {cell(t.get('citation'))} |")
        w()
    print("\n".join(OUT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
