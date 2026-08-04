#!/usr/bin/env python3.11
"""
TPCH-SSPQ implementation campaign `tpch-sspq-impl-r1-20260803` — render
fresh-baseline.md from fresh-baseline.json.

The Markdown deliverable is generated, never hand-typed, so every number in it is
traceable to the raw evidence the JSON indexes and cannot drift from it.

IMPL-SSOT section 6-d requires the per-query paired CV and MDE to be reported as
first-class campaign deliverables — "the only quantitative statement of what this
host can resolve" — so the MDE table is rendered prominently and the queries whose
MDE cannot resolve a few-percent effect are called out by name.

Usage: render_baseline_md.py fresh-baseline.json > fresh-baseline.md
"""
import json
import sys

# The previous measurement campaign's CUBRID medians. INPUT EVIDENCE ONLY
# (IMPL-SSOT section 1-b): shown for comparison so a material divergence is
# visible and must be explained. Section 3 forbids using these as this campaign's
# "before".
PREV = {
    "Q01": 31.193, "Q02": 0.353, "Q03": 4.808, "Q04": 1.756, "Q05": 9.591,
    "Q06": 3.797, "Q07": 24.044, "Q08": 1.136, "Q09": 10.981, "Q10": 7.128,
    "Q11": 1.342, "Q12": 4.045, "Q13": 11.483, "Q14": 3.210, "Q15": 10.455,
    "Q16": 2.869, "Q17": 0.147, "Q18": 37.472, "Q19": 45.856, "Q20": 1.949,
    "Q21": 49.274, "Q22": 1.101,
}


def pct(x):
    return "—" if x is None else f"{100 * x:.2f}%"


def s(x, n=3):
    return "—" if x is None else f"{x:.{n}f}"


def main():
    with open(sys.argv[1]) as f:
        d = json.load(f)
    qs = d["queries"]
    out = []
    w = out.append

    w("# Phase 1A — fresh Q01–Q22 CUBRID baseline")
    w("")
    w(f"Campaign `{d['campaign_id']}` · IMPL-SSOT pinned at commit "
      f"`{d['impl_ssot_commit']}`, blob `{d['impl_ssot_blob']}`.")
    w("")
    w("This baseline is the **only** \"before\" this campaign's scoring (section "
      "2-b) and A/B procedure (section 6-c) may use. No absolute wall time from "
      "the previous measurement campaign is reused as a denominator here "
      "(section 3).")
    w("")

    # ---- identity ----
    w("## Campaign identity")
    w("")
    w("| Item | Value |")
    w("|---|---|")
    w(f"| Campaign ID | `{d['campaign_id']}` |")
    w(f"| Pinned IMPL-SSOT commit | `{d['impl_ssot_commit']}` |")
    w(f"| Pinned IMPL-SSOT blob | `{d['impl_ssot_blob']}` |")
    w(f"| CUBRID base SHA (frozen) | `{d['cubrid_base_sha']}` |")
    w(f"| Install prefix (immutable base) | `{d['install_prefix']}` |")
    for name, b in sorted(d.get("binaries", {}).items()):
        w(f"| `bin/{name}` sha256 | `{b['sha256']}` |")
        w(f"| `bin/{name}` ELF Build ID | `{b['build_id']}` |")
    w(f"| `conf/cubrid.conf` sha256 **as installed** | `{d['cubrid_conf_sha256_as_installed']}` |")
    w(f"| `CUBRID_TMP` | `{d['cubrid_tmp']}` |")
    w(f"| Database | `{d['database']}` |")
    w(f"| Database files | `{d['database_files']}` |")
    c = d["cpu_contract"]
    w(f"| SUT CPUs / memory node | `{c['sut_cpus']}` / node `{c['membind_node']}` |")
    w(f"| Collector CPUs | `{c['collector_cpus']}` |")
    w(f"| Isolation mechanism | {c['mechanism']} |")
    w(f"| External-CPU invalidation gate | {d['external_load_gate_core_s_per_s']} core-s/s ({d['external_load_gate_source']}) |")
    w(f"| Blocks per query | {d['blocks_per_query']} |")
    w(f"| Measured runs per block | {d['measured_runs_per_block']} |")
    ident = d.get("campaign_identity", {})
    drv = ident.get("driver", {})
    if drv:
        w(f"| Phase 1A driver tmux session | `{drv.get('tmux_session')}` |")
        w(f"| Phase 1A driver PID | `{drv.get('driver_pid')}` |")
    w(f"| Collection window start (UTC) | {ident.get('collection_window_utc_start', '—')} |")
    w(f"| Aggregated (UTC) | {d['generated_utc']} |")
    w("")

    # ---- headline table ----
    w("## Per-query baseline")
    w("")
    w("`median wall` is the median over the converged WARM block medians "
      "(section 3-c). `within-block CV` is the largest dispersion seen inside any "
      "single block — a dispersion estimate, never a confidence interval "
      "(section 6-d). `block CV` is the dispersion across block medians.")
    w("")
    w("| Query | median wall (s) | block medians (s) | within-block CV (max) | block CV | paired CV | **MDE** | blocks ok | blocks invalid |")
    w("|---|---:|---|---:|---:|---:|---:|---:|---:|")
    for q in sorted(qs):
        r = qs[q]
        meds = r.get("block_medians_s") or []
        w(f"| {q} | {s(r.get('median_wall_seconds'))} | "
          f"{', '.join(s(x) for x in meds) or '—'} | "
          f"{pct(r.get('within_block_cv_max'))} | {pct(r.get('block_dispersion_cv'))} | "
          f"{pct(r.get('paired_cv'))} | **{pct(r.get('mde'))}** | "
          f"{r['blocks_collected']} | {r['blocks_invalidated']} |")
    w("")
    tot = d.get("total_q01_q22_median_wall_seconds")
    w(f"**Total Q01–Q22 median wall time: {s(tot, 3)} s** "
      f"({s(tot / 60.0, 2) if tot else '—'} min), over "
      f"{d['queries_with_baseline']} of 22 queries with a valid baseline.")
    w("")

    # ---- dominant queries ----
    ranked = sorted((r for r in qs.values() if r.get("median_wall_seconds")),
                    key=lambda r: -r["median_wall_seconds"])
    w("### Queries that dominate `expected_saved_seconds`")
    w("")
    w("Section 2-b multiplies `fresh_base_median_q` by the effect fraction, so "
      "absolute wall time — not relative effect — decides which candidates can "
      "contribute meaningful seconds.")
    w("")
    w("| Rank | Query | median wall (s) | share of Q01–Q22 total |")
    w("|---:|---|---:|---:|")
    for i, r in enumerate(ranked[:8], 1):
        share = r["median_wall_seconds"] / tot if tot else None
        w(f"| {i} | {r['qnn']} | {s(r['median_wall_seconds'])} | {pct(share)} |")
    top5 = sum(r["median_wall_seconds"] for r in ranked[:5])
    w("")
    w(f"The top five queries alone are {s(top5)} s — {pct(top5 / tot) if tot else '—'} "
      "of the total. A candidate that does not touch them cannot move the campaign "
      "total materially, whatever its relative effect.")
    w("")

    # ---- MDE, called out ----
    w("## Minimum detectable effect — what this host can actually prove")
    w("")
    w("**This is a first-class deliverable, not a diagnostic.** Section 3-a's "
      "external-CPU gate stands at 6.0 core-s/s because measurement showed a "
      "lower gate is unattainable on this host (AMEND-D). A 6.0 core-s/s "
      "tolerance is large relative to the few-percent effects many candidates "
      "predict, so **the gate no longer guarantees the environment can resolve "
      "small effects**. Resolution is carried instead by the paired design and by "
      "the honest per-query MDE below.")
    w("")
    w("`MDE = max(1%, 2 × baseline_paired_CV)` (section 6-d). The paired CV is "
      "the base-vs-base paired coefficient of variation of block medians "
      "(section 3-c step 6), computed under two pairings — adjacent blocks, and "
      "blocks spaced to mirror the B-P-P-B slot separation of section 6-c — with "
      "the **larger** of the two used, so the MDE is not flattered by pairing "
      "temporally adjacent blocks.")
    w("")
    w("| Query | fast-regime paired CV | pairing used | raw MDE | inflation applied | **CORRECTED MDE** | median wall (s) | smallest provable saving (s) |")
    w("|---|---:|---|---:|---:|---:|---:|---:|")
    for q in sorted(qs):
        r = qs[q]
        raw, med = r.get("mde"), r.get("median_wall_seconds")
        cm = r.get("corrected_mde")
        inf = r.get("inflation_factor_applied")
        w(f"| {q} | {pct(r.get('paired_cv'))} | {r.get('paired_cv_source', '—')} | "
          f"{pct(raw)} | {('measured directly' if inf is None else f'{inf:.4f}x')} | "
          f"**{pct(cm)}** | {s(med)} | {s(cm * med) if (cm and med) else '—'} |")
    w("")
    w("### The correction is mandatory, and why (section 6-d-1)")
    w("")
    w("The fast Phase 1A regime runs all six blocks of a query on **one continuous server "
      "instance**, so those blocks share buffer, page-table and thread-pool state and are "
      "**not independent**. Phase 2's `B → P → P → B` A/B blocks **are** independent, because "
      "swapping binaries forces a restart. The fast regime therefore measures a strictly "
      "smaller dispersion than the regime the MDE is actually spent in, and feeding an "
      "uncorrected fast-regime paired CV into `MDE = max(1%, 2 × paired_CV)` would produce an "
      "MDE smaller than the noise present in a real A/B block — **the campaign would "
      "over-accept, reporting restart noise as real improvement**.")
    w("")
    w("`corrected_MDE_q = max(1%, 2 × inflation × paired_CV_fast_q)` for Q07–Q22. Q01–Q06 use "
      "their **directly measured** restart-regime paired CV instead: there is no reason to "
      "estimate a quantity that was measured. The inflation factor, its six per-query points, "
      "their spread and the written reason for how they were combined are published "
      "separately in `tpch-sspq/impl/restart-variance-calibration.json` so the factor is "
      "auditable independently of this file.")
    w("")
    corr = d.get("restart_variance_correction") or {}
    comb = corr.get("combination_rule") or {}
    if comb:
        if comb.get("rule") == "USER_DECISION_REQUIRED":
            w("### ⛔ STOP-AND-REPORT — the combination rule is escalated to the user")
            w("")
            w("**IMPL-SSOT section 6-d-1 escalation, section 11-a.** The six calibration points "
              "support neither a single pooled factor nor a defensible wall-magnitude-dependent "
              "one, and section 6-d-1 forbids picking a factor to keep the sweep moving. **No "
              "factor was chosen here.**")
            w("")
            w(f"Every corrected MDE in this file is therefore **PROVISIONAL**, computed under the "
              f"most conservative of the six measured factors "
              f"(**{comb.get('provisional_value'):.4f}x**, the maximum observed). That choice "
              f"cannot under-correct, and under-correction is the single failure mode section "
              f"6-d-1 exists to prevent — an MDE smaller than real A/B noise causes false "
              f"accepts. {comb.get('provisional_is_not_a_decision', '')}")
            w("")
            w("The three candidate rules and their per-query consequences are tabulated in "
              "`tpch-sspq/impl/priority-ranking.md`, together with the "
              "additive-versus-multiplicative diagnostic that explains the direction of the "
              "failure and the fourth option — collecting more calibration blocks, which answers "
              "the question by measurement instead of by model choice.")
            w("")
            w("**Why neither rule fits:**")
            w("")
            for para in (comb.get("reason") or "").split("\n"):
                if para.strip():
                    w(f"- {para.strip()}")
            w("")
        else:
            w(f"**Combination rule chosen: `{comb.get('rule')}`.** "
              + (f"Value {comb.get('value'):.4f}. " if comb.get("value") is not None else "")
              + (f"Form `{comb.get('form')}` with a={comb.get('a')}, b={comb.get('b')}. "
                 if comb.get("form") else ""))
            w("")
            w(comb.get("reason", ""))
            w("")
        sp = corr.get("inflation_factor_spread") or {}
        if sp:
            w(f"Per-query clamped factors: "
              + ", ".join(f"{k} {v:.4f}" for k, v in
                          (corr.get("inflation_factors_clamped") or {}).items())
              + f". Spread {sp.get('min'):.4f}..{sp.get('max'):.4f} "
                f"(ratio {sp.get('ratio'):.2f}), geometric mean {sp.get('geometric_mean'):.4f}, "
                f"pearson r of ln(inflation) vs ln(wall) = "
                f"{'n/a' if sp.get('pearson_r_ln_inflation_vs_ln_wall') is None else format(sp['pearson_r_ln_inflation_vs_ln_wall'], '.4f')}.")
            w("")
        for n in (corr.get("clamp_notes") or []):
            w(f"- {n}")
        if corr.get("clamp_notes"):
            w("")
        sm = corr.get("sensitivity_max_factor") or {}
        if sm:
            flips = sm.get("queries_whose_corrected_mde_changes_under_the_max_factor") or []
            w(f"Sensitivity: the most conservative single factor available is "
              f"{sm.get('max_clamped_factor'):.4f}x. Queries whose corrected MDE would change "
              f"under it: {', '.join(flips) if flips else 'none'}. "
              + sm.get("note", ""))
            w("")

    def _cm(r):
        return r.get("corrected_mde")

    coarse = sorted((r for r in qs.values() if (_cm(r) or 0) > 0.03),
                    key=lambda r: -(_cm(r) or 0))
    fine = sorted((r for r in qs.values() if _cm(r) is not None
                   and _cm(r) <= 0.01 + 1e-12), key=lambda r: r["qnn"])
    w("### Queries where a few-percent effect CANNOT be proven on this host")
    w("")
    if coarse:
        w("These queries' **corrected** MDE exceeds 3%. A candidate predicting a smaller "
          "effect on them must be flagged `UNPROVABLE_ON_THIS_HOST` **at Phase 1B ranking "
          "time** (section 6-d) — before it is queued, not after twelve pairs of "
          "measurement have come back inconclusive.")
        w("")
        w("| Query | corrected MDE | median wall (s) | an effect below this is undecidable here |")
        w("|---|---:|---:|---|")
        for r in coarse:
            w(f"| {r['qnn']} | **{pct(_cm(r))}** | {s(r['median_wall_seconds'])} | "
              f"< {s(_cm(r) * r['median_wall_seconds'])} s |")
    else:
        w("No query's corrected MDE exceeds 3%.")
    w("")
    if fine:
        w(f"At the other end, {', '.join(r['qnn'] for r in fine)} sit at the 1% "
          "floor — even after inflation their paired CV is below 0.5%, so the formula's 1% "
          "floor, not the noise, is what limits them.")
        w("")

    # ---- comparison to previous campaign ----
    w("## Divergence from the previous measurement campaign")
    w("")
    w("The previous campaign `tpch-sspq-fk-r1-20260730` is **input evidence only** "
      "(section 1-b) and its absolute times are **not** this campaign's before "
      "(section 3). The comparison exists only so an unexplained divergence is "
      "visible. A large divergence would mean the two campaigns are not in the "
      "same operating regime, which would invalidate reusing that campaign's "
      "evidence to score candidates (section 6-a-2).")
    w("")
    w("| Query | fresh median (s) | previous campaign (s) | delta | delta % |")
    w("|---|---:|---:|---:|---:|")
    big = []
    for q in sorted(qs):
        r = qs[q]
        cur, prev = r.get("median_wall_seconds"), PREV.get(q)
        if cur is None or prev is None:
            w(f"| {q} | {s(cur)} | {s(prev) if prev else '—'} | — | — |")
            continue
        dd = cur - prev
        dp = dd / prev
        if abs(dp) >= 0.10:
            big.append((q, cur, prev, dp))
        w(f"| {q} | {s(cur)} | {s(prev)} | {dd:+.3f} | {100 * dp:+.2f}% |")
    w("")
    if big:
        w("**Queries differing by 10% or more:** "
          + ", ".join(f"{q} ({100 * dp:+.1f}%)" for q, _, _, dp in big) + ".")
    else:
        w("**No query differs from the previous campaign by 10% or more.**")
    w("")

    # ---- invalidations ----
    w("## Invalidations")
    w("")
    any_inv = False
    w("Section 3-a requires every invalidation to be recorded with its cause and "
      "the measured external load. Two levels exist: a **block** invalidation "
      "(the block yielded no baseline value) and an **attempt** invalidation (a "
      "discarded attempt inside a block that later succeeded). Both are listed; "
      "both remain on disk as evidence (section 8-e).")
    w("")
    w("### Block-level invalidations")
    w("")
    w("| Query | block | reason | detail |")
    w("|---|---:|---|---|")
    for q in sorted(qs):
        for iv in qs[q].get("invalidations", []):
            any_inv = True
            det = []
            for k in ("measure_block_rc", "post_identity_rc", "n_measured",
                      "external_max_core_s_per_s", "note"):
                if iv.get(k) is not None:
                    det.append(f"{k}={iv[k]}")
            w(f"| {q} | {iv.get('block', '?')} | `{iv.get('invalid_reason') or iv.get('reason')}` | "
              f"{'; '.join(det) or '—'} |")
    if not any_inv:
        w("| — | — | none | every block produced a valid baseline value |")
    w("")
    w("### Attempt-level invalidations (block later succeeded)")
    w("")
    w("| Query | reason | measured external load (core-s/s) | gate | detail |")
    w("|---|---|---:|---:|---|")
    any_att = False
    for q in sorted(qs):
        for iv in qs[q].get("attempt_invalidations", []):
            any_att = True
            em = iv.get("external_max_core_s_per_s")
            emc = iv.get("external_max_contract_window_core_s_per_s")
            load = "—"
            if em is not None:
                load = f"max {em}" + (f" / 1s-window {emc}" if emc is not None else "")
            w(f"| {q} | `{iv.get('invalid_reason')}` | {load} | "
              f"{iv.get('threshold_core_s_per_s', '—')} | "
              f"{(iv.get('verdict') or iv.get('note') or '—')} |")
    if not any_att:
        w("| — | none | — | — | no attempt was discarded |")
    w("")
    n_att = sum(qs[q].get("attempts_invalidated", 0) for q in qs)
    n_blk = sum(qs[q].get("blocks_invalidated", 0) for q in qs)
    w(f"**Totals: {n_blk} invalidated blocks, {n_att} discarded attempts.**")
    w("")

    # ---- warm convergence ----
    w("## How WARM convergence was determined")
    w("")
    w("Section 3-c requires WARM to be **proved, not assumed**, and the method "
      "recorded. Every block ran the gate in `warm_establish.py` on an uncounted "
      "warm-up series executed on its own connection before the contract block "
      "was timed. Convergence requires all three of:")
    w("")
    w("1. the trailing window is **not monotone** — a still-decaying series is not steady;")
    w("2. the **half-split level drift** over the whole series (burn-in statement "
      "dropped) is within `level_tol`; the two halves are compared rather than two "
      "adjacent 4-sample windows, because a 4-sample median is not a stable "
      "estimate of the level when the series contains multi-statement plateau "
      "excursions;")
    w("3. the trailing **spread** is within `spread_sanity`, which catches a "
      "genuinely unstable engine rather than a merely noisy one.")
    w("")
    w("Per-query gate parameters are pinned in `harness/warm_params.json` with the "
      "measurement each was derived from. Per-block outcomes:")
    w("")
    w("| Query | window | level_tol | spread | max stmts | blocks converged | typical statements to converge |")
    w("|---|---:|---:|---:|---:|---:|---:|")
    for q in sorted(qs):
        r = qs[q]
        blocks = r.get("blocks", [])
        crit = next((b["warm"].get("criteria") for b in blocks if b.get("warm")), None)
        nconv = sum(1 for b in blocks if (b.get("warm") or {}).get("converged"))
        afters = [b["warm"]["converged_after"] for b in blocks
                  if (b.get("warm") or {}).get("converged_after")]
        typ = f"{min(afters)}–{max(afters)}" if afters else "—"
        if crit:
            w(f"| {q} | {crit.get('window')} | {crit.get('level_tol')} | "
              f"{crit.get('spread_sanity')} | {crit.get('max_statements', '—')} | "
              f"{nconv}/{len(blocks)} | {typ} |")
        else:
            w(f"| {q} | — | — | — | — | {nconv}/{len(blocks)} | {typ} |")
    w("")

    # ---- metric set ----
    w("## Section 6 metric set")
    w("")
    w("Per query the raw evidence under the campaign raw root carries:")
    w("")
    w("| Query | executor CPU (core-s) | auxiliary CPU | total CPU | TWU | serial tail (s) | cycles | instructions | IPC | rows |")
    w("|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
    for q in sorted(qs):
        ref = qs[q].get("reference") or {}
        cpu = ref.get("telemetry_cpu") or {}
        un = ref.get("telemetry_units") or {}
        pf = (ref.get("perf") or {}).get("counters") or {}
        cr = ref.get("canonical_result") or {}
        w(f"| {q} | {s(cpu.get('executor_cpu_core_s'))} | "
          f"{s(cpu.get('auxiliary_query_cpu_core_s'))} | "
          f"{s(cpu.get('total_query_cpu_core_s'))} | "
          f"{s(un.get('time_weighted_active_units'))} | "
          f"{s(un.get('serial_tail_s'))} | "
          f"{int(pf['cycles']) if pf.get('cycles') else '—'} | "
          f"{int(pf['instructions']) if pf.get('instructions') else '—'} | "
          f"{s(pf.get('ipc'), 4)} | {cr.get('row_count', '—')} |")
    w("")
    w("`/proc` and device I/O counters, buffer/temp/memory counters "
      "(`cubrid statdump -c` before and after), NUMA page distribution before and "
      "after every block, plan estimated rows (`SET OPTIMIZATION LEVEL 514`) and "
      "actual rows (`SET TRACE ON` / `SHOW TRACE`) are in the per-query raw "
      "directory and indexed by `raw-manifest.json`.")
    w("")

    # ---- correctness reference ----
    w("## Correctness reference captured from the base binary")
    w("")
    w("Section 6-b's canonical result set was captured from the base binary for "
      "every query, at the cheapest correct moment. ORDER BY queries keep the "
      "exact ordered sequence; the rest are canonically sorted with duplicate "
      "multiplicity preserved (never converted to a set); decimals keep their raw "
      "text so value and scale are both exact. A later patched build is compared "
      "against these hashes.")
    w("")
    w("| Query | ordered | rows | canonical sha256 |")
    w("|---|---|---:|---|")
    for q in sorted(qs):
        cr = ((qs[q].get("reference") or {}).get("canonical_result")) or {}
        w(f"| {q} | {'yes (exact sequence)' if cr.get('ordered') else 'no (canonical sort)'} | "
          f"{cr.get('row_count', '—')} | `{(cr.get('canonical_sha256') or '—')}` |")
    w("")

    w("## Raw evidence")
    w("")
    w("| Query | path | blocks |")
    w("|---|---|---:|")
    for q in sorted(qs):
        r = qs[q]
        w(f"| {q} | `{r['raw_evidence_path']}` | {r['blocks_collected']} |")
    w("")
    w("Hashes, byte sizes and producing stage for every artifact are in "
      "`tpch-sspq/impl/raw-manifest.json`.")
    w("")
    print("\n".join(out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
