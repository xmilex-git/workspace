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
    records = {}
    for imp, c in cands.items():
        f = feas.get(imp, {})
        saved, terms = expected_saved(c, medians, WEIGHTS)
        evs = [t["evidence_level"] for t in terms if t["expected_saved_seconds"] > 0] \
            or [t["evidence_level"] for t in terms] or ["unmeasured"]
        best_ev = max(evs, key=lambda e: EVIDENCE_RANK.get(e, 0))

        # Section 6-d: the ranking MUST carry every candidate's expected effect against
        # the CORRECTED MDE of its target queries, flagging UNPROVABLE_ON_THIS_HOST at
        # ranking time. Evaluated per target query on the predicted effect FRACTION.
        mde_rows, unprovable_qs = [], []
        for t in c.get("terms", []):
            q, frac = t["q"], t.get("fraction")
            if q == "*":
                continue
            m = corrected.get(q)
            verdict = "no_predicted_effect" if not frac else (
                "unprovable" if (m is not None and frac < m) else
                "resolvable" if m is not None else "no_mde")
            if verdict == "unprovable":
                unprovable_qs.append(q)
            mde_rows.append({"q": q, "predicted_effect_fraction": frac,
                             "corrected_mde": m, "verdict": verdict})

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
    pop = [imp for imp, r in records.items()
           if r["scored"] and r["benefit_status"] not in BLOCKED_BENEFIT]
    vals = [math.log1p(records[imp]["expected_saved_seconds"]) for imp in pop]
    pr = percentile_rank(vals)
    for imp in pop:
        r = records[imp]
        r["in_percentile_population"] = True
        r["log1p_expected_saved_seconds"] = round(math.log1p(r["expected_saved_seconds"]), 6)
        r["benefit_score"] = round(pr[math.log1p(r["expected_saved_seconds"])], 4)
        if r["expected_saved_seconds"] == 0:
            r["no_numeric_basis"] = True
    for imp, r in records.items():
        if r.get("benefit_score") is None and r["benefit_status"] not in BLOCKED_BENEFIT:
            r["in_percentile_population"] = False
        fs, bs = r.get("feasibility_score"), r.get("benefit_score")
        r["total_score"] = round(0.5 * fs + 0.5 * bs, 4) if (fs is not None and bs is not None) else None

    # ---- section 2-c ordering with the exact tie-break chain ---------------
    def sort_key(imp):
        r = records[imp]
        is_pred = 1 if (r["lane"] == "enabler" or any(
            imp in (records[o].get("predecessors") or []) for o in records)) else 0
        return (-(r["total_score"] or 0.0),
                -EVIDENCE_RANK.get(r["best_evidence_level"], 0),
                RISK_RANK.get((r.get("correctness_concurrency_risk") or "high").lower(), 3),
                -is_pred,
                r.get("loc_high") or 10 ** 9,
                imp)

    ranked = sorted([i for i, r in records.items() if r["ranked_eligible"]], key=sort_key)
    for pos, imp in enumerate(ranked, 1):
        records[imp]["rank"] = pos
        records[imp].setdefault("eligibility", "eligible")

    # ---- section 4-a: enablers inherit the dependent's position ------------
    queue = []
    for imp in ranked:
        for pre in (records[imp].get("predecessors") or []):
            pid = pre.split()[0].strip("(),")
            if pid in records and records[pid]["lane"] in ("enabler", "diagnostic") \
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
            elif r["lane"] in ("deferred_research", "diagnostic", "enabler"):
                r["eligibility"] = f"listed with lane and rationale, no queue position ({r['lane']})"
            r.setdefault("rank", None)

    # ---- section 2-d sensitivity ------------------------------------------
    def top5(weights):
        recs = {}
        for imp, c in cands.items():
            if not (c.get("scored") and c["lane"] == "performance"
                    and c.get("benefit_status") not in BLOCKED_BENEFIT and c.get("ranked")):
                continue
            s, _ = expected_saved(c, medians, weights)
            recs[imp] = s
        p = percentile_rank([math.log1p(v) for v in recs.values()])
        scored = {}
        for imp, s in recs.items():
            b = p[math.log1p(s)]
            fs = feas.get(imp, {}).get("feasibility_score")
            scored[imp] = 0.5 * fs + 0.5 * b if fs is not None else None
        order = sorted(scored, key=lambda i: (-(scored[i] or 0), i))
        return order[:5], scored

    base_top5, _ = top5(WEIGHTS)
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
