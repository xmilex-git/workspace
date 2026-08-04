#!/usr/bin/env python3.11
"""Restart-variance calibration — IMPL-SSOT section 6-d-1 (`AMEND-G`).

WHY THIS EXISTS
---------------
Section 3-c-1 runs Phase 1A on ONE continuous server instance, so a query's six
blocks are not independent: they share buffer, page-table and thread-pool state.
Section 6-c's Phase 2 A/B blocks ARE independent, because `B -> P -> P -> B` swaps
binaries and must restart. The fast regime therefore measures a strictly smaller
dispersion than the regime the MDE is actually spent in, and feeding an uncorrected
fast-regime paired CV into `MDE = max(1%, 2 x paired_CV)` would make the campaign
OVER-ACCEPT — it would report restart noise as real improvement.

WHAT IT DOES (section 6-d-1 procedure, steps 1-7)
------------------------------------------------
  1/2. Q01-Q06 paired CV under BOTH regimes with the IDENTICAL estimator and the
       IDENTICAL pairing rule. Enforced by construction: the restart-regime and the
       fast-regime numbers both go through `aggregate_baseline.paired_cv` with the
       same `ADJACENT` / `SPACED` pairings and the same "take the larger" selection.
  3.   `inflation_q = paired_CV_restart_q / paired_CV_fast_q`.
  4.   State the six factors, their spread, and HOW THEY WERE COMBINED — pooled or
       wall-magnitude-dependent — with the choice made from what the six points show
       and the reason written down. The decision thresholds below are declared in
       advance so the rule cannot be retro-fitted to the data.
  5.   `corrected_MDE_q = max(1%, 2 x inflation x paired_CV_fast_q)` for Q07-Q22.
  6.   Q01-Q06 use their DIRECTLY MEASURED restart-regime paired CV — there is no
       reason to estimate a quantity that was measured.
  7.   Publish the derivation separately so the factor is auditable independently of
       the baseline file.

The restart regime's wall-clock medians are calibration evidence ONLY and are NEVER
used as `fresh_base_median_q` for any query (section 6-d-1 "The calibration set").
Q07 of the restart run is partial (one block) and is excluded — one block cannot
yield a paired CV.

DECLARED-IN-ADVANCE DECISION PROCEDURE
-------------------------------------
Guards (any trip => stop-and-report, section 11-a; the script never invents a factor):
  G1  a query's fast-regime paired CV is 0 or None       -> inflation undefined
  G2  >= 3 of 6 inflation factors are < 1.0              -> the amendment's premise
      ("the fast regime is strictly quieter") is contradicted by a majority
  G3  clamped factor spread max/min > 10 AND the log-linear fit is not accepted
      -> neither a single pooled factor nor a defensible wall-dependent one fits
Clamp: an individual factor < 1.0 is clamped UP to 1.0 and recorded. The correction
  may never DEFLATE an MDE below its measured fast-regime value.
Combination rule:
  accept the wall-magnitude-dependent form  inflation(wall) = exp(a + b*ln(wall))
  iff |pearson_r(ln inflation, ln wall)| >= 0.70  AND the fit reduces the SD of the
  log-inflation residuals by >= 30% versus the pooled model. Otherwise use a single
  pooled factor = GEOMETRIC mean of the clamped factors (geometric because the
  quantity is a ratio, so the mean must be multiplicative).
Sensitivity: the max-factor alternative is always computed, and every query whose
  `UNPROVABLE_ON_THIS_HOST` verdict would flip between the pooled and the max factor
  is named, so a fragile determination is visible rather than hidden.

Usage: calibrate_restart_variance.py [OUT_DIR]     (default: tpch-sspq/impl)
"""
import json
import math
import os
import statistics
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import campaign_config as cfg  # noqa: E402
import aggregate_baseline as ab  # noqa: E402

CALIB_ROOT = os.path.join(cfg.RAW_ROOT, "raw-restart-calibration")
CALIB_QUERIES = [f"Q{n:02d}" for n in range(1, 7)]     # Q07 partial -> excluded
ALL_QUERIES = [f"Q{n:02d}" for n in range(1, 23)]

# Declared in advance — see the module docstring.
R_ACCEPT = 0.70
RESIDUAL_REDUCTION_ACCEPT = 0.30
SPREAD_STOP_RATIO = 10.0
MINORITY_CLAMP_STOP_COUNT = 3


class StopAndReport(Exception):
    """Section 11-a: report the calibration data and wait; never pick a factor."""


def load_restart_blocks(qnn):
    """Accepted restart-regime block medians, in block order.

    Mirrors `aggregate_baseline.load_query` exactly — same headline field, same
    Q15 session-total special case, same INCOMPLETE_MEASURED_RUNS rejection — but
    rooted at the preserved calibration evidence rather than at `raw/`. An
    invalidated block simply has no `blockN-headline.json` (Q06 block 5 is the
    known case), so the accepted blocks are compacted in order and the positional
    pairings apply to that compacted list, which is what produced the restart-side
    numbers already published in `restart-variance-calibration.json`.
    """
    d = os.path.join(CALIB_ROOT, qnn)
    meds, invalid = [], []
    for b in range(1, cfg.N_BLOCKS + 1):
        hp = os.path.join(d, f"block{b}-headline.json")
        if not os.path.exists(hp):
            ip = os.path.join(d, f"block{b}-INVALID.json")
            reason = "INVALID_MARKER" if os.path.exists(ip) else "NOT_COLLECTED"
            invalid.append({"block": b, "reason": reason})
            continue
        with open(hp) as f:
            j = json.load(f)
        times = (j.get("measured_session_totals_s") if qnn == "Q15"
                 else j.get("measured_times_s")) or []
        if len(times) != cfg.N_MEASURED:
            invalid.append({"block": b, "reason": "INCOMPLETE_MEASURED_RUNS",
                            "n_measured": len(times)})
            continue
        meds.append({"block": b, "median_s": ab.median(times)})
    return meds, invalid


def regime_paired_cv(medians):
    """The section 3-c step 6 estimator, both pairings, larger wins."""
    adj, adj_pairs = ab.paired_cv(medians, ab.ADJACENT)
    spc, spc_pairs = ab.paired_cv(medians, ab.SPACED)
    cands = [x for x in (adj, spc) if x is not None]
    pcv = max(cands) if cands else None
    return {
        "paired_cv": pcv,
        "paired_cv_source": ("spaced" if (pcv is not None and spc is not None
                                          and pcv == spc) else "adjacent"),
        "adjacent": {"paired_cv": adj, "pairs": adj_pairs},
        "spaced": {"paired_cv": spc, "pairs": spc_pairs,
                   "rationale": "mirrors the B-P-P-B slot spacing of section 6-c"},
    }


def pearson(xs, ys):
    n = len(xs)
    if n < 3:
        return None
    mx, my = statistics.mean(xs), statistics.mean(ys)
    num = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
    dx = math.sqrt(sum((x - mx) ** 2 for x in xs))
    dy = math.sqrt(sum((y - my) ** 2 for y in ys))
    return (num / (dx * dy)) if dx and dy else None


def ols(xs, ys):
    mx, my = statistics.mean(xs), statistics.mean(ys)
    den = sum((x - mx) ** 2 for x in xs)
    if not den:
        return None, None
    b = sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / den
    return my - b * mx, b


def build():
    generated = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

    # ---- fast regime, all 22 queries (section 3-c-1) -----------------------
    fast = {q: ab.build(q) for q in ALL_QUERIES}

    # ---- the six calibration queries, both regimes -------------------------
    per_query, factors, walls, notes = {}, {}, {}, []
    for q in CALIB_QUERIES:
        rmeds, rinvalid = load_restart_blocks(q)
        rvals = [m["median_s"] for m in rmeds]
        restart = regime_paired_cv(rvals)
        f = fast[q]
        fast_cv = f.get("paired_cv")
        rec = {
            "restart_regime": {
                **restart,
                "blocks_accepted": len(rvals),
                "block_medians_s": rvals,
                "invalidations": rinvalid,
                "median_wall_seconds": ab.median(rvals) if rvals else None,
                "wall_is_calibration_evidence_only": True,
                "never_used_as_fresh_base_median": True,
            },
            "fast_regime": {
                "paired_cv": fast_cv,
                "paired_cv_source": f.get("paired_cv_source"),
                "blocks_accepted": f.get("blocks_collected"),
                "block_medians_s": f.get("block_medians_s"),
                "median_wall_seconds": f.get("median_wall_seconds"),
                "raw_mde": f.get("mde"),
            },
        }
        rcv = restart["paired_cv"]
        if fast_cv in (None, 0) or rcv is None:
            raise StopAndReport(
                f"{q}: paired CV unavailable or zero (restart={rcv}, fast={fast_cv}); "
                "inflation_q is undefined — section 6-d-1 escalation")
        raw_factor = rcv / fast_cv
        clamped = max(1.0, raw_factor)
        rec["inflation_raw"] = raw_factor
        rec["inflation_clamped"] = clamped
        rec["clamped_up_to_1"] = clamped != raw_factor
        if rec["clamped_up_to_1"]:
            notes.append(
                f"{q}: raw inflation {raw_factor:.4f} < 1 — the fast regime measured MORE "
                "dispersion than the restart regime for this query, contradicting the "
                "AMEND-G premise for it. Clamped up to 1.0 so the correction can never "
                "deflate an MDE below its measured fast-regime value.")
        factors[q] = clamped
        walls[q] = f.get("median_wall_seconds")
        per_query[q] = rec

    n_below_1 = sum(1 for q in CALIB_QUERIES if per_query[q]["clamped_up_to_1"])
    if n_below_1 >= MINORITY_CLAMP_STOP_COUNT:
        raise StopAndReport(
            f"{n_below_1} of {len(CALIB_QUERIES)} calibration queries have inflation < 1. "
            "A majority contradiction of the AMEND-G premise means no defensible "
            "inflation factor exists — section 6-d-1 escalation / section 11-a")

    # ---- step 4: choose the combination rule from what the six points show --
    fv = [factors[q] for q in CALIB_QUERIES]
    ln_f = [math.log(factors[q]) for q in CALIB_QUERIES]
    ln_w = [math.log(walls[q]) for q in CALIB_QUERIES]
    pooled = math.exp(statistics.mean(ln_f))               # geometric mean
    pooled_resid_sd = statistics.stdev(ln_f) if len(ln_f) > 1 else 0.0
    r = pearson(ln_w, ln_f)
    a, b = ols(ln_w, ln_f)
    fit_resid_sd = None
    reduction = None
    if a is not None:
        resid = [y - (a + b * x) for x, y in zip(ln_w, ln_f)]
        fit_resid_sd = statistics.stdev(resid) if len(resid) > 1 else 0.0
        if pooled_resid_sd:
            reduction = (pooled_resid_sd - fit_resid_sd) / pooled_resid_sd

    accept_fit = bool(
        r is not None and abs(r) >= R_ACCEPT
        and reduction is not None and reduction >= RESIDUAL_REDUCTION_ACCEPT)
    spread_ratio = (max(fv) / min(fv)) if min(fv) else float("inf")
    if not accept_fit and spread_ratio > SPREAD_STOP_RATIO:
        raise StopAndReport(
            f"clamped inflation factors span {min(fv):.4f}..{max(fv):.4f} "
            f"(ratio {spread_ratio:.2f} > {SPREAD_STOP_RATIO}) and the wall-magnitude fit "
            f"was not accepted (|r|={None if r is None else abs(r):.4f}, "
            f"residual reduction={reduction}). No single pooled factor and no defensible "
            "wall-dependent factor fits — section 6-d-1 escalation / section 11-a")

    if accept_fit:
        combination = {
            "rule": "wall_magnitude_dependent",
            "form": "inflation(wall_s) = max(1.0, exp(a + b * ln(wall_s)))",
            "a": a, "b": b,
            "reason": (
                f"The six points show a strong log-log association between the restart "
                f"penalty and the query's wall magnitude (pearson r = {r:.4f} on "
                f"ln(inflation) vs ln(wall), |r| >= {R_ACCEPT}), and the log-linear fit "
                f"cuts the residual spread of ln(inflation) by {reduction:.1%} "
                f"(>= {RESIDUAL_REDUCTION_ACCEPT:.0%}) versus a single pooled factor "
                f"({pooled_resid_sd:.4f} -> {fit_resid_sd:.4f}). A pooled factor would "
                f"therefore systematically over-correct one end of the 0.35 s..31 s wall "
                f"span and under-correct the other, and under-correction is the direction "
                f"that causes false accepts."),
        }
    else:
        combination = {
            "rule": "single_pooled_factor",
            "value": pooled,
            "statistic": "geometric mean of the six clamped per-query factors",
            "reason": (
                f"The six points do NOT support a wall-magnitude-dependent factor: "
                f"pearson r = {r if r is None else round(r, 4)} on ln(inflation) vs "
                f"ln(wall) (acceptance needs |r| >= {R_ACCEPT}) and the log-linear fit "
                f"changes the residual spread of ln(inflation) by "
                f"{'n/a' if reduction is None else format(reduction, '.1%')} "
                f"(acceptance needs >= {RESIDUAL_REDUCTION_ACCEPT:.0%}). With no wall "
                f"dependence to model, a single pooled factor is the honest reduction. "
                f"The geometric mean is used because an inflation factor is a ratio, so "
                f"the pooled value must be multiplicative; the arithmetic mean would bias "
                f"the factor upward for no measured reason. Factor spread "
                f"{min(fv):.4f}..{max(fv):.4f} (ratio {spread_ratio:.2f}, within the "
                f"declared stop threshold {SPREAD_STOP_RATIO})."),
        }

    def factor_for(wall_s):
        if combination["rule"] == "wall_magnitude_dependent":
            return max(1.0, math.exp(combination["a"] + combination["b"] * math.log(wall_s)))
        return combination["value"]

    max_factor = max(fv)

    # ---- steps 5/6: corrected MDE per query --------------------------------
    corrected = {}
    flip = []
    for q in ALL_QUERIES:
        f = fast[q]
        rec = {
            "fast_regime_paired_cv": f.get("paired_cv"),
            "fast_regime_raw_mde": f.get("mde"),
            "fresh_base_median_seconds": f.get("median_wall_seconds"),
            "blocks_accepted": f.get("blocks_collected"),
            "status": f.get("status"),
        }
        if q in CALIB_QUERIES:
            rcv = per_query[q]["restart_regime"]["paired_cv"]
            rec.update({
                "basis": "measured_restart_regime_paired_cv",
                "basis_reason": ("section 6-d-1 step 6: this query's restart-regime paired "
                                 "CV was measured directly, so it is used as-is rather "
                                 "than estimated from an inflation factor"),
                "inflation_factor_applied": None,
                "paired_cv_used": rcv,
                "corrected_mde": max(0.01, 2 * rcv),
            })
        elif f.get("paired_cv") is None:
            rec.update({"basis": "NO_VALID_BLOCK", "inflation_factor_applied": None,
                        "paired_cv_used": None, "corrected_mde": None})
        else:
            wall = f.get("median_wall_seconds")
            inf = factor_for(wall) if wall else factor_for(1.0)
            rec.update({
                "basis": "inflated_fast_regime_paired_cv",
                "basis_reason": ("section 6-d-1 step 5: corrected_MDE = max(1%, 2 x "
                                 "inflation x paired_CV_fast)"),
                "inflation_factor_applied": inf,
                "paired_cv_used": inf * f["paired_cv"],
                "corrected_mde": max(0.01, 2 * inf * f["paired_cv"]),
                "corrected_mde_at_max_factor": max(0.01, 2 * max_factor * f["paired_cv"]),
            })
            if (rec["corrected_mde"] != rec["corrected_mde_at_max_factor"]):
                flip.append(q)
        corrected[q] = rec

    out = {
        "PARTIAL": False,
        "phase": "Phase 1A complete — fast regime measured, restart-variance correction applied",
        "campaign_id": cfg.CAMPAIGN,
        "impl_ssot_commit": cfg.IMPL_SSOT_COMMIT,
        "impl_ssot_blob": cfg.IMPL_SSOT_BLOB,
        "impl_ssot_amendment": "AMEND-G section 6-d-1",
        "install_prefix": cfg.CUBRID_HOME,
        "generated_utc": generated,
        "estimator": {
            "paired_cv": ("sample SD of the signed relative differences (b-a)/mean(a,b) "
                          "over base-vs-base block-median pairs, divided by sqrt(2) — the "
                          "per-block CV implied by the paired spread (IMPL-SSOT section "
                          "3-c step 6)"),
            "pairings": {"adjacent": "(b1,b2)(b3,b4)(b5,b6)",
                         "spaced": "(b1,b4)(b2,b5)(b3,b6) — mirrors the B-P-P-B slot spacing"},
            "selection": "the LARGER of the two pairings is used, so the noise floor is never understated",
            "identity_guarantee": ("both regimes are reduced by the same "
                                   "aggregate_baseline.paired_cv function with the same "
                                   "ADJACENT/SPACED pairings and the same selection rule, "
                                   "so CV_restart/CV_fast is a measurement of the "
                                   "restart's contribution by construction, not by assertion"),
        },
        "decision_thresholds_declared_in_advance": {
            "pearson_r_accept": R_ACCEPT,
            "residual_reduction_accept": RESIDUAL_REDUCTION_ACCEPT,
            "factor_spread_stop_ratio": SPREAD_STOP_RATIO,
            "minority_clamp_stop_count": MINORITY_CLAMP_STOP_COUNT,
        },
        "calibration_queries": CALIB_QUERIES,
        "q07_restart_regime_excluded": ("partial at one block; one block cannot yield a "
                                        "paired CV (section 6-d-1)"),
        "per_query_calibration": per_query,
        "inflation_factors_clamped": factors,
        "inflation_factor_spread": {
            "min": min(fv), "max": max(fv), "ratio": spread_ratio,
            "geometric_mean": pooled,
            "median": statistics.median(fv),
            "ln_inflation_sd_pooled_model": pooled_resid_sd,
            "ln_inflation_sd_loglinear_fit": fit_resid_sd,
            "pearson_r_ln_inflation_vs_ln_wall": r,
            "loglinear_residual_reduction": reduction,
        },
        "combination": combination,
        "clamp_notes": notes,
        "corrected_mde": corrected,
        "sensitivity_max_factor": {
            "max_clamped_factor": max_factor,
            "queries_whose_corrected_mde_changes_under_the_max_factor": flip,
            "note": ("Reported so a fragile UNPROVABLE_ON_THIS_HOST determination is "
                     "visible. The ranking uses the chosen combination rule; this column "
                     "states what the most conservative single factor would have given."),
        },
        "rule_established": ("Phase 2 A/B accept decisions (section 7-a criterion 3) and the "
                             "Phase 1B UNPROVABLE_ON_THIS_HOST flag both use the CORRECTED "
                             "MDE, never the raw fast-regime MDE"),
        "raw_evidence_paths": {"fast_regime": os.path.join(cfg.RAW_ROOT, "raw"),
                               "restart_regime": CALIB_ROOT},
    }
    return out, fast


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(cfg.REPO, "impl")
    os.makedirs(out_dir, exist_ok=True)
    try:
        out, _fast = build()
    except StopAndReport as e:
        blocker = {
            "PARTIAL": True,
            "STOP_AND_REPORT": True,
            "section": "IMPL-SSOT 6-d-1 escalation / 11-a",
            "blocker": str(e),
            "generated_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        }
        p = os.path.join(out_dir, "restart-variance-calibration-STOP.json")
        with open(p, "w") as f:
            json.dump(blocker, f, indent=2, sort_keys=True)
        print(f"STOP_AND_REPORT: {e}", file=sys.stderr)
        print(f"wrote {p}", file=sys.stderr)
        return 3
    p = os.path.join(out_dir, "restart-variance-calibration.json")
    with open(p, "w") as f:
        json.dump(out, f, indent=2, sort_keys=True)
    print(f"wrote {p}")
    print(f"rule={out['combination']['rule']}")
    print(f"factors={json.dumps(out['inflation_factors_clamped'])}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
