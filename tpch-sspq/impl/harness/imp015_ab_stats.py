#!/usr/bin/env python3.11
"""
IMP-015 section 6-d statistics over the A/B block artifacts written by
imp015_ab.sh.

Gate (Q10): 12 gated blocks (3 balanced B->P->P->B cycles) give 6 block
medians per variant. Pairing rule: within each cycle the first B pairs with
the first P and the last P pairs with the last B (position-balanced), giving
6 (B, P) pairs. Primary estimate: median of the 6 paired P/B block-median
ratios. CI: paired bootstrap 95% percentile interval over pair resampling
(10^5 resamples, fixed seed for reproducibility).

MDE disclosure: the Phase 1A fresh baseline and the 6-d-1 corrected MDE do
NOT exist (the campaign was paused before the fast sweep; raw/ is empty).
This report therefore states, instead of the corrected MDE, the strictest
available noise statement: the restart-regime paired CV computed from this
A/B's OWN six base block medians (same-regime, same-query), with
MDE_proxy = max(1%, 2 x CV_B). The 7-a criterion-3 decision is evaluated
against MDE_proxy and labelled as such; it is not the pinned corrected MDE.

Stream (Q15 + controls): 2 block medians per variant; per-query median delta
reported against the 3% non-target regression bound (7-c).

Usage: imp015_ab_stats.py [AB_BASE]
"""
import json
import glob
import os
import random
import statistics
import sys

AB = sys.argv[1] if len(sys.argv) > 1 else \
    "/data/tpch-sspq/tpch-sspq-impl-r1-20260803/work/IMP-015/ab"


def block_median(path):
    with open(path) as f:
        d = json.load(f)
    return d["median_s"], d.get("statement_times_all")


def collect_gate():
    blocks = []
    for d in sorted(glob.glob(os.path.join(AB, "Q10", "block*-*"))):
        name = os.path.basename(d)
        idx = int(name[5:7])
        variant = name.split("-", 1)[1]
        med, times = block_median(os.path.join(d, "Q10-cubrid-headline.json"))
        blocks.append({"idx": idx, "variant": variant, "median_s": med,
                       "times": times})
    return sorted(blocks, key=lambda b: b["idx"])


def pair_cycles(blocks):
    """blocks arrive in driver order: [B P P B] x 3."""
    assert len(blocks) == 12, f"expected 12 gate blocks, got {len(blocks)}"
    pairs = []
    for c in range(3):
        b1, p1, p2, b2 = blocks[4 * c: 4 * c + 4]
        assert (b1["variant"], p1["variant"], p2["variant"], b2["variant"]) == \
            ("base", "IMP-015", "IMP-015", "base"), "cycle order violated"
        pairs.append((b1["median_s"], p1["median_s"]))
        pairs.append((b2["median_s"], p2["median_s"]))
    return pairs


def bootstrap_ci(pairs, n=100000, seed=20260803):
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
    report = {}
    gate_blocks = collect_gate()
    if len(gate_blocks) == 12:
        pairs = pair_cycles(gate_blocks)
        ratios = sorted(p / b for b, p in pairs)
        point = statistics.median(ratios)
        lo, hi = bootstrap_ci(pairs)
        b_meds = [b["median_s"] for b in gate_blocks if b["variant"] == "base"]
        p_meds = [b["median_s"] for b in gate_blocks
                  if b["variant"] == "IMP-015"]
        cv_b = cv(b_meds)
        mde_proxy = max(0.01, 2 * cv_b)
        report["Q10_gate"] = {
            "blocks": gate_blocks,
            "pairs_BP": pairs,
            "paired_ratios_sorted": ratios,
            "point_estimate_median_ratio": point,
            "bootstrap_95CI": [lo, hi],
            "n_pairs": len(pairs),
            "base_block_medians": b_meds,
            "patch_block_medians": p_meds,
            "base_median_of_medians": statistics.median(b_meds),
            "patch_median_of_medians": statistics.median(p_meds),
            "restart_regime_CV_base_blocks": cv_b,
            "MDE_proxy_note": ("Phase 1A corrected MDE unavailable (campaign "
                               "paused before fast sweep; raw/ empty). Proxy: "
                               "max(1%, 2 x CV over this A/B's own 6 base "
                               "block medians), same-regime same-query."),
            "MDE_proxy": mde_proxy,
            "criterion2_CI_below_1": hi < 1.0,
            "criterion3_point_improvement_ge_MDE_proxy":
                (1.0 - point) >= mde_proxy,
            "q10_gate_median_le_5p70s":
                statistics.median(p_meds) <= 5.70,
        }
    else:
        report["Q10_gate"] = {"error": f"{len(gate_blocks)} blocks present"}

    stream = collect_stream()
    sr = {}
    for qnn, per_var in sorted(stream.items()):
        entry = {}
        for v, blocks in per_var.items():
            entry[v] = {"block_medians": [b["median_s"] for b in blocks]}
        if "base" in entry and "IMP-015" in entry:
            mb = statistics.median(entry["base"]["block_medians"])
            mp = statistics.median(entry["IMP-015"]["block_medians"])
            entry["median_base_s"] = mb
            entry["median_patch_s"] = mp
            entry["ratio_P_over_B"] = mp / mb if mb else None
            entry["delta_pct"] = (mp - mb) / mb * 100 if mb else None
            entry["regression_gt_3pct"] = (mp - mb) / mb > 0.03 if mb else None
        sr[qnn] = entry
    report["stream"] = sr

    out = os.path.join(AB, "ab-stats.json")
    with open(out, "w") as f:
        json.dump(report, f, indent=2)
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
