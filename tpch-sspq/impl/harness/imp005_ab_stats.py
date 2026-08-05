#!/usr/bin/env python3.11
"""
IMP-005 section 6-d statistics over the A/B block artifacts written by
imp005_ab.sh.

Gate (Q09): 12 gated blocks (3 balanced B->P->P->B cycles) give 6 block medians
per variant. Pairing rule: within each cycle the first B pairs with the first P
and the last P pairs with the last B (position-balanced), giving 6 (B, P) pairs.
Primary estimate: median of the 6 paired P/B block-median ratios. CI: paired
bootstrap 95% percentile interval over pair resampling (10^5 resamples, fixed
seed for reproducibility).

MDE: unlike IMP-015's A/B, the Phase 1A fresh baseline and the section 6-d-1
restart-variance calibration BOTH exist for this candidate, and the user fixed
the combination rule on 2026-08-05 as option (c): a single worst-case factor
15.3158 applied to every query, so

    corrected_MDE(q) = 15.3158 x paired_CV_fast(q)

with paired_CV_fast read from impl/fresh-baseline.json (the artifact, not a
summary document). For Q09 that is 15.3158 x 0.002788 = 4.27%.

Verdict frame (IMP-005 is the enabler lane, see
worktrees/IMP-005/implementation-plan.md "Verdict criteria for this enabler"):
the candidate is a statistics-only change with zero expected runtime effect, so
section 7-a criterion 2 (CI entirely below 1.0) CANNOT hold and is NOT the
accept test. The A/B is a NULL GUARD. It reports:

  * regression_proven      — CI entirely ABOVE 1.0 (a real slowdown; 7-c reject)
  * no_regression_proved   — CI upper bound below 1 + corrected_MDE, i.e. the
                             data exclude a regression at the pinned resolution
  * criterion2_CI_below_1  — recorded for completeness; expected False here

Stream (21 other queries): 2 block medians per variant; per-query median delta
against the 3% non-target regression bound of section 7-c, with each query's own
corrected MDE printed alongside so a delta below the query's noise floor is not
read as a movement.

Usage: imp005_ab_stats.py [AB_BASE]
"""
import glob
import json
import os
import random
import statistics
import sys

AB = sys.argv[1] if len(sys.argv) > 1 else \
    "/data/tpch-sspq/tpch-sspq-impl-r1-20260803/work/IMP-005/ab"
PATCH = "IMP-005"
GATE_QNN = "Q09"
# User decision 2026-08-05 (impl/PHASE2-SPEC.md section 1 item (1)): section
# 6-d-1 combination rule (c), the worst-case factor applied to every query.
MDE_FACTOR = 15.3158
BASELINE = "/home/cubrid/dev/workspace/tpch-sspq/impl/fresh-baseline.json"
NON_TARGET_REGRESSION_BOUND = 0.03


def load_baseline_cv():
    with open(BASELINE) as f:
        d = json.load(f)
    out = {}
    for q, v in d["queries"].items():
        cv = v.get("fast_regime_paired_cv", v.get("paired_cv"))
        out[q] = {"paired_cv_fast": cv,
                  "corrected_mde": MDE_FACTOR * cv if cv is not None else None,
                  "baseline_median_s": v.get("median_wall_seconds")}
    return out


def block_median(path):
    with open(path) as f:
        d = json.load(f)
    return d["median_s"], d.get("statement_times_all")


def collect_gate():
    blocks = []
    for d in sorted(glob.glob(os.path.join(AB, GATE_QNN, "block*-*"))):
        name = os.path.basename(d)
        idx = int(name[5:7])
        variant = name.split("-", 1)[1]
        hl = os.path.join(d, f"{GATE_QNN}-cubrid-headline.json")
        if not os.path.exists(hl):
            continue
        med, times = block_median(hl)
        blocks.append({"idx": idx, "variant": variant, "median_s": med,
                       "times": times})
    return sorted(blocks, key=lambda b: b["idx"])


def pair_cycles(blocks):
    """blocks arrive in driver order: [B P P B] x 3."""
    if len(blocks) != 12:
        raise ValueError(f"expected 12 gate blocks, got {len(blocks)}")
    pairs = []
    for c in range(3):
        b1, p1, p2, b2 = blocks[4 * c: 4 * c + 4]
        if (b1["variant"], p1["variant"], p2["variant"], b2["variant"]) != \
                ("base", PATCH, PATCH, "base"):
            raise ValueError("cycle order violated")
        pairs.append((b1["median_s"], p1["median_s"]))
        pairs.append((b2["median_s"], p2["median_s"]))
    return pairs


def bootstrap_ci(pairs, n=100000, seed=20260806):
    rng = random.Random(seed)
    ratios = [p / b for b, p in pairs]
    stats_ = []
    for _ in range(n):
        sample = [ratios[rng.randrange(len(ratios))] for _ in ratios]
        stats_.append(statistics.median(sample))
    stats_.sort()
    return stats_[int(0.025 * n)], stats_[int(0.975 * n) - 1]


def cv(values):
    m = statistics.mean(values)
    return (statistics.stdev(values) / m) if m else float("nan")


def collect_stream():
    out = {}
    for d in sorted(glob.glob(os.path.join(AB, "stream", "block*-*"))):
        name = os.path.basename(d)
        idx = int(name[5:7])
        variant = name.split("-", 1)[1]
        for qd in sorted(glob.glob(os.path.join(d, "Q*"))):
            qnn = os.path.basename(qd)
            hl = os.path.join(qd, f"{qnn}-cubrid-headline.json")
            if not os.path.exists(hl):
                continue
            med, _ = block_median(hl)
            out.setdefault(qnn, {}).setdefault(variant, []).append(
                {"idx": idx, "median_s": med})
    return out


def main():
    cvs = load_baseline_cv()
    report = {"campaign_id": "tpch-sspq-impl-r1-20260803", "imp_id": "IMP-005",
              "lane": "enabler (statistics-only; A/B is a null guard)",
              "mde_rule": {"decision": "(c) worst-case factor for every query",
                           "factor": MDE_FACTOR,
                           "formula": "corrected_MDE = factor x paired_CV_fast",
                           "source": "impl/PHASE2-SPEC.md section 1 item (1); "
                                     "impl/fresh-baseline.json"},
              "non_target_regression_bound": NON_TARGET_REGRESSION_BOUND}

    gate_blocks = collect_gate()
    gate = {"qnn": GATE_QNN, "blocks": gate_blocks,
            "n_blocks_present": len(gate_blocks)}
    if len(gate_blocks) == 12:
        pairs = pair_cycles(gate_blocks)
        ratios = sorted(p / b for b, p in pairs)
        point = statistics.median(ratios)
        lo, hi = bootstrap_ci(pairs)
        b_meds = [b["median_s"] for b in gate_blocks if b["variant"] == "base"]
        p_meds = [b["median_s"] for b in gate_blocks if b["variant"] == PATCH]
        mde = cvs[GATE_QNN]["corrected_mde"]
        gate.update({
            "pairs_BP": pairs,
            "paired_ratios_sorted": ratios,
            "point_estimate_median_ratio": point,
            "bootstrap_95CI": [lo, hi],
            "n_pairs": len(pairs),
            "base_block_medians": b_meds,
            "patch_block_medians": p_meds,
            "base_median_of_medians": statistics.median(b_meds),
            "patch_median_of_medians": statistics.median(p_meds),
            "restart_regime_CV_base_blocks": cv(b_meds),
            "restart_regime_CV_patch_blocks": cv(p_meds),
            "baseline_paired_cv_fast": cvs[GATE_QNN]["paired_cv_fast"],
            "corrected_MDE": mde,
            "delta_pct": (point - 1.0) * 100,
            "criterion2_CI_below_1": hi < 1.0,
            "regression_proven": lo > 1.0,
            "no_regression_proved": hi < 1.0 + mde,
            "point_within_MDE_of_null": abs(point - 1.0) <= mde,
        })
    report["gate"] = gate

    stream = collect_stream()
    sr = {}
    worst = None
    for qnn, per_var in sorted(stream.items()):
        entry = {}
        for v, blocks in per_var.items():
            entry[v] = {"block_medians": [b["median_s"] for b in blocks],
                        "block_idx": [b["idx"] for b in blocks]}
        info = cvs.get(qnn, {})
        entry["corrected_MDE"] = info.get("corrected_mde")
        entry["baseline_median_s"] = info.get("baseline_median_s")
        if "base" in entry and PATCH in entry:
            mb = statistics.median(entry["base"]["block_medians"])
            mp = statistics.median(entry[PATCH]["block_medians"])
            delta = (mp - mb) / mb if mb else None
            entry["median_base_s"] = mb
            entry["median_patch_s"] = mp
            entry["ratio_P_over_B"] = mp / mb if mb else None
            entry["delta_pct"] = delta * 100 if delta is not None else None
            entry["regression_gt_3pct"] = (
                delta > NON_TARGET_REGRESSION_BOUND
                if delta is not None else None)
            entry["delta_within_query_MDE"] = (
                abs(delta) <= entry["corrected_MDE"]
                if delta is not None and entry["corrected_MDE"] else None)
            if delta is not None and (worst is None or delta > worst[1]):
                worst = (qnn, delta)
        sr[qnn] = entry
    report["stream"] = sr
    report["stream_summary"] = {
        "queries_present": sorted(sr),
        "worst_regression_query": worst[0] if worst else None,
        "worst_regression_pct": worst[1] * 100 if worst else None,
        "any_regression_gt_3pct": any(
            v.get("regression_gt_3pct") for v in sr.values()),
    }

    out = os.path.join(AB, "ab-stats.json")
    with open(out, "w") as f:
        json.dump(report, f, indent=2)
    print(json.dumps({k: v for k, v in report.items() if k != "stream"},
                     indent=2))
    for q, v in sorted(sr.items()):
        if "delta_pct" in v:
            print(f"  {q}: base={v['median_base_s']:.4f}s "
                  f"patch={v['median_patch_s']:.4f}s "
                  f"delta={v['delta_pct']:+.2f}% "
                  f"(query MDE {v['corrected_MDE'] * 100:.2f}%)"
                  f"{'  <<< 3% REGRESSION' if v['regression_gt_3pct'] else ''}")
    print(f"\nwritten {out}")


if __name__ == "__main__":
    main()
