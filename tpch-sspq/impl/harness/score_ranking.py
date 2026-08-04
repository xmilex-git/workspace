#!/usr/bin/env python3.11
"""Phase 1B ranking — mechanical application of IMPL-SSOT sections 2-b, 2-c, 2-d, 2-e.

This script contains NO judgment. Every per-term effect fraction, evidence level and
citation comes from `tpch-sspq/impl/benefit-inputs.json`; every feasibility score comes
from the immutable `tpch-sspq/impl/feasibility-assessment.json`; every
`fresh_base_median_q` and every corrected MDE comes from the Phase 1A deliverables
`fresh-baseline.json` and `restart-variance-calibration.json`. The split is deliberate:
the judgment is auditable in one file and the arithmetic is reproducible in another.

Section 2-b-1: a ranking produced without reading `triage-adjustments.json` is invalid.
It is read here, and the blocked benefit statuses it defines are enforced.

Usage: score_ranking.py [IMPL_DIR]        (default: tpch-sspq/impl)
"""
import json
import math
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import campaign_config as cfg  # noqa: E402

WEIGHTS = {"direct_ab": 1.00, "lower_bound": 0.90, "attribution": 0.70,
           "projection": 0.50, "upper_bound": 0.35, "unmeasured": 0.00}
# Section 2-c tie-break 1: higher evidence level wins, in this exact order.
EVIDENCE_RANK = {"direct_ab": 6, "lower_bound": 5, "attribution": 4,
                 "projection": 3, "upper_bound": 2, "unmeasured": 1}
RISK_RANK = {"low": 1, "medium": 2, "high": 3, "very high": 4, "very_high": 4}
PERTURBATION = 0.15          # section 2-d
BLOCKED_BENEFIT = ("BENEFIT_PENDING_DENOMINATOR", "BENEFIT_CONFOUNDED")


def percentile_rank(values):
    """Section 2-b normalization: 100 x percentile_rank(log1p(expected_saved_seconds)).

    Ties share a value, and the minimum of the population maps to 0, so every
    candidate with expected_saved_seconds = 0 receives the same bottom rank exactly as
    section 2-b requires.
    """
    n = len(values)
    if n == 0:
        return {}
    if n == 1:
        return {values[0]: 100.0}
    out = {}
    for v in set(values):
        below = sum(1 for y in values if y < v)
        out[v] = 100.0 * below / (n - 1)
    return out


def expected_saved(cand, medians, weights):
    total, terms = 0.0, []
    for t in cand.get("terms", []):
        q, frac, ev = t["q"], t.get("fraction"), t.get("evidence", "unmeasured")
        w = weights.get(ev, 0.0)
        base = medians.get(q) if q != "*" else None
        if frac in (None, 0) or base is None or w == 0.0:
            contrib = 0.0
        else:
            contrib = base * frac * w
        total += contrib
        terms.append({
            "q": q, "fresh_base_median_seconds": base, "conservative_effect_fraction": frac,
            "evidence_level": ev, "evidence_weight": w,
            "expected_saved_seconds": round(contrib, 6),
            "basis": t.get("basis"), "citation": t.get("citation"),
            "wall_basis": t.get("wall_basis"),
        })
    return total, terms


def _static(imp, feas, cands):
    """Weight-independent inputs to the section 2-c tie-break chain."""
    f = feas.get(imp, {})
    c = cands.get(imp, {})
    return {
        "feasibility_score": f.get("feasibility_score"),
        "risk": (f.get("correctness_concurrency_risk") or "high").lower(),
        "loc_high": f.get("loc_high"),
        "lane": c.get("lane"),
        "predecessors": c.get("predecessors") or f.get("predecessors") or [],
        "ranked_eligible": bool(c.get("ranked")) and c.get("lane") == "performance",
        "blocked": c.get("benefit_status") in BLOCKED_BENEFIT,
        "scored": bool(c.get("scored")),
    }


def score_with(weights, cands, feas, medians):
    """The ONE scoring implementation, parameterized only by the evidence weights.

    Section 2-d perturbs the evidence weights and asks whether the top 5 moves. That
    question is only meaningful if the perturbed run is the SAME computation with
    different weights. An earlier revision had a second, simplified scorer for the
    sensitivity pass: it normalized over a narrower population (scored + ranked +
    performance) than the main pass (every scored, non-blocked candidate) and ordered
    by (total, id) instead of the full section 2-c chain. The two therefore disagreed
    on the base case itself, so `RANKING_UNSTABLE` was not measuring perturbation
    sensitivity at all. Both passes now go through this function, so identity is
    structural rather than asserted.

    Returns (per_imp, order) where order is the ranked-eligible set in section 2-c
    order and per_imp carries saved/terms/best_evidence_level/benefit/total.
    """
    per = {}
    for imp, c in cands.items():
        saved, terms = expected_saved(c, medians, weights)
        evs = [t["evidence_level"] for t in terms if t["expected_saved_seconds"] > 0] \
            or [t["evidence_level"] for t in terms] or ["unmeasured"]
        per[imp] = {"saved": saved, "terms": terms,
                    "best_evidence_level": max(evs, key=lambda e: EVIDENCE_RANK.get(e, 0)),
                    "static": _static(imp, feas, cands)}

    # Population rule, identical for every pass: every SCORED candidate whose benefit
    # status is not blocked, regardless of lane or ranked eligibility (section 2-b-1
    # excludes only the blocked statuses from the percentile population).
    pop = [imp for imp, d in per.items() if d["static"]["scored"] and not d["static"]["blocked"]]
    pr = percentile_rank([math.log1p(per[imp]["saved"]) for imp in pop])
    for imp, d in per.items():
        if imp in pop:
            d["benefit"] = round(pr[math.log1p(d["saved"])], 4)
        else:
            d["benefit"] = None
        fs = d["static"]["feasibility_score"]
        d["total"] = (round(0.5 * fs + 0.5 * d["benefit"], 4)
                      if (fs is not None and d["benefit"] is not None) else None)

    is_pred_of = set()
    for imp, d in per.items():
        for pre in d["static"]["predecessors"]:
            is_pred_of.add(str(pre).split()[0].strip("(),"))

    def sort_key(imp):
        d = per[imp]
        st = d["static"]
        is_pred = 1 if (st["lane"] == "enabler" or imp in is_pred_of) else 0
        return (-(d["total"] or 0.0),
                -EVIDENCE_RANK.get(d["best_evidence_level"], 0),
                RISK_RANK.get(st["risk"], 3),
                -is_pred,
                st["loc_high"] or 10 ** 9,
                imp)

    order = sorted([imp for imp, d in per.items() if d["static"]["ranked_eligible"]],
                   key=sort_key)
    return per, order


def build(impl_dir):
    with open(os.path.join(impl_dir, "benefit-inputs.json")) as f:
        bi = json.load(f)
    with open(os.path.join(impl_dir, "feasibility-assessment.json")) as f:
        feas = {c["id"]: c for c in json.load(f)["candidates"]}
    with open(os.path.join(impl_dir, "triage-adjustments.json")) as f:
        triage = json.load(f)
    with open(os.path.join(impl_dir, "fresh-baseline.json")) as f:
        fresh = json.load(f)
    with open(os.path.join(impl_dir, "restart-variance-calibration.json")) as f:
        calib = json.load(f)
    if calib.get("PARTIAL"):
        raise SystemExit("restart-variance-calibration.json is still PARTIAL — "
                         "section 3-c-1: a Phase 1A baseline is INVALID as an MDE source "
                         "until the 6-d-1 correction has been applied")

    medians = {q: r.get("median_wall_seconds") for q, r in fresh["queries"].items()}
    corrected = {q: r.get("corrected_mde") for q, r in calib["corrected_mde"].items()}

    cands = bi["candidates"]
    base_per, base_order = score_with(WEIGHTS, cands, feas, medians)
    records = {}
    for imp, c in cands.items():
        f = feas.get(imp, {})
        saved, terms = base_per[imp]["saved"], base_per[imp]["terms"]
        best_ev = base_per[imp]["best_evidence_level"]

        # Section 6-d: the ranking MUST carry every candidate's expected effect against
        # the CORRECTED MDE of its target queries, flagging UNPROVABLE_ON_THIS_HOST at
        # ranking time. Evaluated per target query on the predicted effect FRACTION.
        #
        # BUT section 6-d-1 also forbids this campaign from choosing the combination
        # rule when the calibration does not support one: "the worker reports the
        # calibration data and asks; it MUST NOT pick a factor to keep the sweep
        # moving." When the calibration is escalated, the corrected MDE is not a
        # campaign fact, so a verdict computed from it would be this campaign silently
        # making the user's decision. The verdict is therefore WITHHELD and, instead,
        # what each candidate rule WOULD give is published so the decision is informed.
        # A candidate is only reported UNPROVABLE_ON_THIS_HOST when the rule is settled.
        mde_rows, unprovable_qs = [], []
        escalated = bool(calib.get("STOP_AND_REPORT"))
        for t in c.get("terms", []):
            q, frac = t["q"], t.get("fraction")
            if q == "*":
                continue
            m = corrected.get(q)
            per_rule = ((calib["corrected_mde"].get(q) or {})
                        .get("corrected_mde_under_each_candidate_rule") or {})
            if not frac:
                verdict = "no_predicted_effect"
            elif m is None:
                verdict = "no_mde"
            elif escalated and per_rule:
                verdict = "withheld_pending_user_factor_decision"
            elif escalated:
                # Q01-Q06 use their MEASURED restart-regime CV, so no combination rule
                # applies to them and the pending decision cannot move their verdict.
                verdict = "unprovable" if frac < m else "resolvable"
            else:
                verdict = "unprovable" if frac < m else "resolvable"
            if verdict == "unprovable":
                unprovable_qs.append(q)
            row = {"q": q, "predicted_effect_fraction": frac,
                   "corrected_mde": m, "verdict": verdict}
            if verdict == "withheld_pending_user_factor_decision":
                row["would_be_under_each_candidate_rule"] = {
                    rule: ("unprovable" if frac < mm else "resolvable")
                    for rule, mm in per_rule.items()}
                row["verdict_is_rule_invariant"] = len(
                    set(row["would_be_under_each_candidate_rule"].values())) == 1
                row["note"] = ("section 6-d-1 escalation: the combination rule is the "
                               "user's decision, so no UNPROVABLE_ON_THIS_HOST verdict is "
                               "asserted for this query. Where every candidate rule agrees "
                               "(verdict_is_rule_invariant true) the outcome does not depend "
                               "on the pending decision.")
            mde_rows.append(row)

        records[imp] = {
            "imp_id": imp,
            "lane": c["lane"],
            "registry_lane_before_triage": f.get("lane"),
            "root_cause_title": f.get("root_cause_title"),
            "feasibility_score": f.get("feasibility_score"),
            "loc_low": f.get("loc_low"), "loc_likely": f.get("loc_likely"),
            "loc_high": f.get("loc_high"),
            "files_affected": f.get("files_affected"),
            "subsystems_affected": f.get("subsystems_affected"),
            "correctness_concurrency_risk": f.get("correctness_concurrency_risk"),
            "difficulty_and_risk_rationale": f.get("feasibility_rationale"),
            "registry_difficulty_agreement": f.get("registry_difficulty_agreement"),
            "predecessors": c.get("predecessors") or f.get("predecessors"),
            "alternatives": f.get("alternatives"),
            "containment": f.get("containment"),
            "cluster_note": c.get("cluster_note"),
            "hard_stop_flag": c.get("hard_stop_flag"),
            "write_path_flag": c.get("write_path_flag", False),
            "upstream_scope_gate": c.get("upstream_scope_gate", False),
            "external_reference": c.get("external_reference"),
            "external_state": c.get("external_state"),
            "benefit_status": c.get("benefit_status"),
            "triage_note": c.get("triage_note"),
            "campaign_status": c.get("campaign_status"),
            "acceptance_criterion_caveat": c.get("acceptance_criterion_caveat"),
            "baseline_caveat": c.get("baseline_caveat"),
            "ranking_rationale": c.get("ranking_rationale"),
            "scored": c.get("scored", False),
            "ranked_eligible": c.get("ranked", False) and c["lane"] == "performance",
            "queue_position_rule": c.get("queue_position_rule"),
            "best_evidence_level": best_ev,
            "per_query_terms": terms,
            "expected_saved_seconds": round(saved, 6),
            "mde_comparison": mde_rows,
            "unprovable_on_this_host_queries": unprovable_qs,
        }

    # ---- section 2-b-1: blocked benefit statuses ----------------------------
    for imp, r in records.items():
        if r["benefit_status"] in BLOCKED_BENEFIT:
            r.update({"benefit_score": None, "total_score": None, "rank": None,
                      "in_percentile_population": False,
                      "eligibility": "blocked",
                      "blocker": cands[imp].get("blocker")})

    # ---- section 2-b normalization over the scored candidate set ------------
    for imp, r in records.items():
        d = base_per[imp]
        if r["benefit_status"] in BLOCKED_BENEFIT:
            continue
        r["in_percentile_population"] = d["benefit"] is not None
        if d["benefit"] is not None:
            r["log1p_expected_saved_seconds"] = round(math.log1p(d["saved"]), 6)
            r["benefit_score"] = d["benefit"]
            r["total_score"] = d["total"]
            if d["saved"] == 0:
                r["no_numeric_basis"] = True

    # ---- section 2-c ordering: taken from score_with, the single implementation ----
    ranked = list(base_order)
    for pos, imp in enumerate(ranked, 1):
        records[imp]["rank"] = pos
        records[imp].setdefault("eligibility", "eligible")

    # ---- section 4-a: ONLY enablers inherit the dependent's position --------
    # Section 4-a (IMPL-SSOT 583-587) is precise about which lanes enter the queue:
    # "A required enabler is inserted into the queue immediately ahead of the
    # dependent candidate it unblocks; it inherits its position from the dependent...
    # Diagnostic and Deferred-research candidates are listed with their lane and
    # rationale but carry no queue position."
    # So `enabler` is the ONLY non-performance lane that gets a queue position, and
    # `diagnostic` gets one only in the sense that it does not. An earlier revision
    # tested `("enabler", "diagnostic")` here and `("deferred_research", "diagnostic",
    # "enabler")` below, which put the diagnostic IMP-017 into the queue while ALSO
    # labelling it "no queue position", and labelled the enabler IMP-005 "no queue
    # position" while it correctly carried queue_position_inherited_from. Both halves
    # of that contradiction are fixed here.
    queue = []
    for imp in ranked:
        for pre in (records[imp].get("predecessors") or []):
            pid = pre.split()[0].strip("(),")
            if pid in records and records[pid]["lane"] == "enabler" \
                    and pid not in [q["imp_id"] for q in queue]:
                records[pid]["queue_position_inherited_from"] = imp
                queue.append({"imp_id": pid, "lane": records[pid]["lane"],
                              "reason": f"required predecessor of {imp}; inherits its position "
                                        f"(section 4-a), never its own benefit score"})
        queue.append({"imp_id": imp, "lane": "performance", "rank": records[imp]["rank"]})

    for imp, r in records.items():
        if not r["ranked_eligible"] and r.get("eligibility") is None:
            if r["lane"] == "external_tracking":
                r["eligibility"] = "excluded from the implementation queue (external_tracking); still tracked to a resolution"
            elif r["lane"] in ("deferred_research", "diagnostic"):
                r["eligibility"] = f"listed with lane and rationale, no queue position ({r['lane']})"
            elif r["lane"] == "enabler":
                inh = r.get("queue_position_inherited_from")
                r["eligibility"] = (
                    f"no benefit-ranked position; inserted into the queue immediately ahead of "
                    f"{inh} as its required predecessor, inheriting that position (section 4-a)"
                    if inh else
                    "enabler with no dependent in the ranked set, so no queue position (section 4-a)")
            r.setdefault("rank", None)

    # ---- section 2-d sensitivity ------------------------------------------
    def top5(weights):
        _per, order = score_with(weights, cands, feas, medians)
        return order[:5], _per

    base_top5, _ = top5(WEIGHTS)
    # The base case of the perturbation MUST reproduce the published order, or the
    # perturbation is not measuring what section 2-d asks. Asserted, not assumed.
    if base_top5 != ranked[:5]:
        raise SystemExit(
            "sensitivity base case disagrees with the published ranking "
            f"({base_top5} vs {ranked[:5]}) — the two passes are not the same "
            "computation, so RANKING_UNSTABLE would be meaningless")
    perturbed = {}
    for direction, sign in (("pessimistic", -1), ("optimistic", +1)):
        w = {k: min(1.0, max(0.0, v + sign * PERTURBATION)) for k, v in WEIGHTS.items()}
        w["unmeasured"] = 0.0 if sign < 0 else w["unmeasured"]
        t5, _ = top5(w)
        perturbed[direction] = {"weights": w, "top5": t5,
                                "identity_changed": set(t5) != set(base_top5),
                                "order_changed": t5 != base_top5}
    unstable = any(v["identity_changed"] or v["order_changed"] for v in perturbed.values())
    swapped = sorted(set().union(*[set(v["top5"]) ^ set(base_top5) for v in perturbed.values()]))

    out = {
        "campaign_id": cfg.CAMPAIGN,
        "phase": "Phase 1B ranking",
        "impl_ssot_commit": cfg.IMPL_SSOT_COMMIT,
        "impl_ssot_blob": cfg.IMPL_SSOT_BLOB,
        "generated_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "inputs": {
            "feasibility_assessment": "tpch-sspq/impl/feasibility-assessment.json (immutable)",
            "triage_adjustments": "tpch-sspq/impl/triage-adjustments.json (section 2-b-1 required input 3)",
            "fresh_baseline": "tpch-sspq/impl/fresh-baseline.json",
            "restart_variance_calibration": "tpch-sspq/impl/restart-variance-calibration.json",
            "benefit_inputs": "tpch-sspq/impl/benefit-inputs.json",
            "triage_generated_utc": triage.get("generated_utc"),
        },
        "methodology": {
            "feasibility": "section 2-a, reproduced verbatim in priority-ranking.md",
            "benefit": "expected_saved_seconds = sum_q (fresh_base_median_q x conservative_effect_fraction_q x evidence_weight_q); benefit_score = 100 x percentile_rank(log1p(expected_saved_seconds))",
            "total": "Total = 0.50 x Feasibility + 0.50 x Benefit",
            "tie_breaks": ["higher evidence level", "lower correctness risk",
                           "is a predecessor/enabler of another candidate", "smaller high-LOC estimate"],
            "evidence_weights": WEIGHTS,
            "mde_source": "CORRECTED MDE from section 6-d-1, never the raw fast-regime MDE",
        },
        "fresh_base_medians_seconds": medians,
        "corrected_mde": corrected,
        "calibration_status": {
            "STOP_AND_REPORT": calib.get("STOP_AND_REPORT", False),
            "combination_rule": (calib.get("combination") or {}).get("rule"),
            "provisional_rule_applied": (calib.get("combination") or {}).get("provisional_rule_applied"),
            "provisional_value": (calib.get("combination") or {}).get("provisional_value"),
            "user_decision_required": calib.get("user_decision_required"),
            "reason": (calib.get("combination") or {}).get("reason"),
            "candidate_rules_for_user_decision": (calib.get("combination") or {}).get(
                "candidate_rules_for_user_decision"),
            "leave_one_out_pearson_r": (calib.get("combination") or {}).get("leave_one_out_pearson_r"),
            "near_equal_wall_contradictions": (calib.get("combination") or {}).get(
                "near_equal_wall_contradictions"),
            "effect_on_this_ranking": (
                "Every UNPROVABLE_ON_THIS_HOST verdict below is computed against the "
                "PROVISIONAL corrected MDE. Because the provisional factor is the most "
                "conservative of the six measured factors, the flag can only be raised too "
                "OFTEN here, never too rarely: a candidate marked provable is provable under "
                "every candidate rule, while a candidate marked UNPROVABLE may become "
                "provable if the user selects a smaller factor."
                if calib.get("STOP_AND_REPORT") else
                "The combination rule was accepted, so the corrected MDE is final."),
        },
        "corrected_mde_under_each_candidate_rule": {
            q: (r or {}).get("corrected_mde_under_each_candidate_rule")
            for q, r in calib["corrected_mde"].items()
            if (r or {}).get("corrected_mde_under_each_candidate_rule")
        },
        "candidates": records,
        "queue": queue,
        "sensitivity": {
            "perturbation": PERTURBATION,
            "base_top5": base_top5,
            "perturbed": {k: {kk: (sorted(vv) if isinstance(vv, set) else vv)
                              for kk, vv in v.items()} for k, v in perturbed.items()},
            "RANKING_UNSTABLE": unstable,
            "candidates_that_swapped": swapped,
            "note": ("RANKING_UNSTABLE does not block Phase 1 completion; it blocks silent "
                     "reliance on a fragile order (section 2-d)."),
        },
        "id_unassigned_new_candidates": bi["id_unassigned_new_candidates"],
        "clusters": bi["clusters"],
        "methodology_decisions": bi["methodology_decisions"],
    }
    return out


def main():
    impl_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(cfg.REPO, "impl")
    out = build(impl_dir)
    p = os.path.join(impl_dir, "priority-ranking.json")
    with open(p, "w") as f:
        json.dump(out, f, indent=2, sort_keys=True)
    print(f"wrote {p}")
    print(f"RANKING_UNSTABLE={out['sensitivity']['RANKING_UNSTABLE']}")
    for imp in out["sensitivity"]["base_top5"]:
        r = out["candidates"][imp]
        print(f"  {r['rank']}. {imp} total={r['total_score']} feas={r['feasibility_score']} "
              f"benefit={r['benefit_score']} saved={r['expected_saved_seconds']}s")
    return 0


if __name__ == "__main__":
    sys.exit(main())
