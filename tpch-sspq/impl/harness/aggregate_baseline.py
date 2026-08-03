#!/usr/bin/env python3.11
"""
TPCH-SSPQ implementation campaign `tpch-sspq-impl-r1-20260803` — Phase 1A
aggregation: raw block evidence -> fresh-baseline.json + fresh-baseline.md and the
raw manifest.

Statistics follow IMPL-SSOT sections 3-c and 6-d.

  per-block median        median of the 3 measured statements in that block (6-c)
  within-block dispersion SD and CV over those 3 values (3-c step 5). Three values
                          in a block are a dispersion estimate, NEVER a CI (6-d).
  block dispersion        SD and CV over the block medians (3-c step 5)
  noise floor             the base-vs-base PAIRED coefficient of variation of block
                          medians (3-c step 6) — the quantity 6-d's MDE consumes
  MDE                     max(1%, 2 x baseline_paired_CV) (6-d)

D2 (pairing). Section 3-c says "the paired coefficient of variation of base-vs-base
block medians" and fixes no pairing. In the section 6-c A/B the two B blocks of a
B-P-P-B cycle are separated by two P blocks, so a base-vs-base pair that mirrors
the real design must not be two temporally adjacent blocks — adjacent blocks share
whatever host state the interval carried and would understate the noise floor,
which would understate the MDE and overstate what this host can prove. Both
pairings are therefore computed:

    adjacent   (b1,b2) (b3,b4) (b5,b6)   pair members collected back to back
    spaced     (b1,b4) (b2,b5) (b3,b6)   pair members two blocks apart, mirroring
                                         the B-P-P-B slot spacing

and the LARGER paired CV is the one the MDE is computed from. Both are reported.

Usage: aggregate_baseline.py [OUT_DIR]
"""
import glob
import json
import os
import statistics
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import campaign_config as cfg  # noqa: E402

QNNS = [f"Q{n:02d}" for n in range(1, 23)]


def median(xs):
    return statistics.median(xs)


def sd(xs):
    return statistics.stdev(xs) if len(xs) > 1 else 0.0


def cv(xs):
    m = statistics.mean(xs)
    return (sd(xs) / m) if m else None


def paired_cv(medians, pairing):
    """Paired CV over base-vs-base block-median pairs.

    For each pair the relative difference is |a-b| / mean(a,b); the paired CV is
    the sample SD of the signed relative differences divided by sqrt(2), which is
    the per-block CV implied by the paired spread. Every pair is reported so the
    number can be audited rather than trusted.
    """
    pairs, rel = [], []
    for i, j in pairing:
        if i >= len(medians) or j >= len(medians):
            continue
        a, b = medians[i], medians[j]
        mean = (a + b) / 2.0
        d = (b - a) / mean if mean else 0.0
        pairs.append({"pair": [i + 1, j + 1], "a_s": a, "b_s": b,
                      "relative_diff": round(d, 6)})
        rel.append(d)
    if len(rel) < 2:
        return None, pairs
    # SD of paired differences -> per-observation CV
    return sd(rel) / (2 ** 0.5), pairs


ADJACENT = [(0, 1), (2, 3), (4, 5)]
SPACED = [(0, 3), (1, 4), (2, 5)]


_ATTEMPTS = None


def _load_attempts():
    """Attempt-level outcomes, parsed from the driver log by extract_attempts.py.

    The work directory is NOT used: `measure_block.sh` writes its per-attempt
    artifacts into `work/<QNN>/`, which the next block of the same query
    overwrites, so globbing there silently undercounts discarded attempts inside
    blocks that were ultimately accepted. The driver log is the only complete
    durable record (section 3-a requires every invalidation to be recorded with
    its cause and the measured load).
    """
    global _ATTEMPTS
    if _ATTEMPTS is not None:
        return _ATTEMPTS
    log = os.path.join(cfg.RAW_ROOT, "work", "BASELINE", "phase1a-driver.log")
    out = os.path.join(cfg.RAW_ROOT, "work", "BASELINE", "attempt-outcomes.json")
    subprocess.run(["python3.11", os.path.join(cfg.HARNESS, "extract_attempts.py"),
                    log, out], capture_output=True, text=True)
    try:
        with open(out) as f:
            _ATTEMPTS = json.load(f)
    except (OSError, ValueError):
        _ATTEMPTS = {"discarded_by_query": {}, "n_attempts_discarded": 0}
    return _ATTEMPTS


def attempt_invalidations(qnn):
    return _load_attempts().get("discarded_by_query", {}).get(qnn, [])


def load_query(qnn):
    d = os.path.join(cfg.RAW_ROOT, "raw", qnn)
    blocks, invalid = [], []
    for b in range(1, cfg.N_BLOCKS + 1):
        hp = os.path.join(d, f"block{b}-headline.json")
        ip = os.path.join(d, f"block{b}-INVALID.json")
        if os.path.exists(hp):
            with open(hp) as f:
                j = json.load(f)
            times = (j.get("measured_session_totals_s") if qnn == "Q15"
                     else j.get("measured_times_s")) or []
            if len(times) != cfg.N_MEASURED:
                invalid.append({"block": b, "reason": "INCOMPLETE_MEASURED_RUNS",
                                "n_measured": len(times), "path": hp})
                continue
            wp = os.path.join(d, f"block{b}-warm.json")
            warm = {}
            if os.path.exists(wp):
                with open(wp) as f:
                    wj = json.load(f)
                warm = {"converged": wj.get("converged"),
                        "verdict": wj.get("verdict"),
                        "converged_after": (wj.get("converged_after_statements")
                                            or wj.get("converged_after_sessions")),
                        "criteria": wj.get("criteria"),
                        "steady_state_median_s": wj.get("steady_state_median_s")}
            gp = os.path.join(d, f"block{b}-bgload.json")
            load = {}
            if os.path.exists(gp):
                with open(gp) as f:
                    gj = json.load(f)
                load = {k: gj.get(k) for k in
                        ("threshold_core_s_per_s", "external_mean", "external_max",
                         "external_p95", "external_max_contract_window",
                         "external_core_seconds", "verdict",
                         "verdict_contract_window", "n_samples", "duration_s")}
            ident = {}
            for phase in ("pre", "post"):
                p = os.path.join(d, f"block{b}-identity-{phase}.json")
                if os.path.exists(p):
                    with open(p) as f:
                        ij = json.load(f)
                    ident[phase] = {
                        "classification": ij.get("classification"),
                        "pid": (ij.get("cub_server") or {}).get("pid"),
                        "exe": (ij.get("cub_server") or {}).get("exe"),
                        "start_time_utc": (ij.get("cub_server") or {}).get("start_time_utc"),
                        "n_tids": (ij.get("all_tid_affinity") or {}).get("n_tids"),
                        "n_off_sut": (ij.get("all_tid_affinity") or {}).get("n_off_sut"),
                        "numa_totals": (ij.get("numa") or {}).get("totals"),
                        "cubrid_conf_sha256": ij.get("cubrid_conf_sha256"),
                    }
            blocks.append({
                "block": b,
                "measured_times_s": times,
                "median_s": median(times),
                "within_block_sd_s": sd(times),
                "within_block_cv": cv(times),
                "warmup_uncounted_s": (j.get("warmup_session_total_s") if qnn == "Q15"
                                       else j.get("warmup_time_s")),
                "warm": warm,
                "external_load": load,
                "server_identity": ident,
                "cubrid_conf_sha256": j.get("cubrid_conf_sha256"),
                "install_prefix": j.get("install_prefix"),
                "sink_sha256": (j.get("sink") or {}).get("sha256"),
                "headline_path": hp,
            })
        elif os.path.exists(ip):
            with open(ip) as f:
                invalid.append({**json.load(f), "path": ip})
        else:
            invalid.append({"block": b, "reason": "NOT_COLLECTED"})
    return blocks, invalid


def build(qnn):
    blocks, invalid = load_query(qnn)
    d = os.path.join(cfg.RAW_ROOT, "raw", qnn)
    attempts = attempt_invalidations(qnn)
    rec = {
        "qnn": qnn,
        "blocks_collected": len(blocks),
        "blocks_invalidated": len(invalid),
        "invalidations": invalid,
        "attempt_invalidations": attempts,
        "attempts_invalidated": len(attempts),
        "raw_evidence_path": d,
        "blocks": blocks,
    }
    if not blocks:
        rec.update({"status": "NO_VALID_BLOCK", "median_wall_seconds": None,
                    "paired_cv": None, "mde": None})
        return rec

    meds = [b["median_s"] for b in blocks]
    rec["block_medians_s"] = meds
    rec["median_wall_seconds"] = median(meds)
    rec["block_dispersion_sd_s"] = sd(meds)
    rec["block_dispersion_cv"] = cv(meds)
    rec["within_block_cv_max"] = max(b["within_block_cv"] or 0 for b in blocks)
    rec["all_measured_values_s"] = [v for b in blocks for v in b["measured_times_s"]]

    adj, adj_pairs = paired_cv(meds, ADJACENT)
    spc, spc_pairs = paired_cv(meds, SPACED)
    rec["noise_floor"] = {
        "definition": ("base-vs-base paired CV of block medians "
                       "(IMPL-SSOT section 3-c step 6)"),
        "adjacent_pairing": {"pairs": adj_pairs, "paired_cv": adj},
        "spaced_pairing": {"pairs": spc_pairs, "paired_cv": spc,
                           "rationale": "mirrors the B-P-P-B slot spacing of "
                                        "section 6-c"},
    }
    cands = [x for x in (adj, spc) if x is not None]
    pcv = max(cands) if cands else None
    rec["paired_cv"] = pcv
    rec["paired_cv_source"] = (
        "spaced" if (pcv is not None and spc is not None and pcv == spc) else "adjacent")
    # section 6-d: MDE = max(1%, 2 x baseline_paired_CV)
    rec["mde"] = max(0.01, 2 * pcv) if pcv is not None else None
    rec["mde_formula"] = "max(1%, 2 x baseline_paired_CV)  (IMPL-SSOT section 6-d)"

    ref = os.path.join(d, f"{qnn}-reference.json")
    if os.path.exists(ref):
        with open(ref) as f:
            rj = json.load(f)
        rec["reference"] = {
            "canonical_result": rj.get("canonical_result"),
            "plan": rj.get("plan"),
            "perf": rj.get("perf"),
            "telemetry_cpu": (rj.get("telemetry") or {}).get("cpu"),
            "telemetry_units": (rj.get("telemetry") or {}).get("units"),
            "telemetry_io": (rj.get("telemetry") or {}).get("io"),
            "statdump_pre": rj.get("statdump_pre"),
            "statdump_post": rj.get("statdump_post"),
            "path": ref,
        }
    rec["status"] = "OK" if len(blocks) == cfg.N_BLOCKS else "PARTIAL"
    return rec


def manifest():
    """Section 10-b: per artifact absolute path, bytes, SHA-256, campaign identity."""
    items = []
    for p in sorted(glob.glob(os.path.join(cfg.RAW_ROOT, "raw", "*", "*"))):
        if not os.path.isfile(p):
            continue
        items.append({
            "path": p,
            "bytes": os.path.getsize(p),
            "sha256": cfg.sha256_file(p),
            "campaign_id": cfg.CAMPAIGN,
            "imp_id": "BASELINE",
            "impl_ssot_commit": cfg.IMPL_SSOT_COMMIT,
            "impl_ssot_blob": cfg.IMPL_SSOT_BLOB,
            "cubrid_base_sha": cfg.CUBRID_BASE_SHA,
            "valid": "INVALID" not in os.path.basename(p),
            "artifact_type": os.path.basename(p).split(".")[-1],
            "producing_stage": "phase1a-fresh-baseline",
        })
    return items


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(out_dir, exist_ok=True)

    queries = {q: build(q) for q in QNNS}
    ok = [r for r in queries.values() if r.get("median_wall_seconds") is not None]

    idjson = os.path.join(cfg.RAW_ROOT, "work", "BASELINE", "campaign-identity.json")
    identity = {}
    if os.path.exists(idjson):
        with open(idjson) as f:
            identity = json.load(f)

    repin = {}
    rp = os.path.join(cfg.RAW_ROOT, "work", "BASELINE", "repin-record.json")
    if os.path.exists(rp):
        with open(rp) as f:
            repin = json.load(f)

    doc = {
        "campaign_id": cfg.CAMPAIGN,
        "phase": "1A fresh baseline",
        "impl_ssot_commit": cfg.IMPL_SSOT_COMMIT,
        "impl_ssot_blob": cfg.IMPL_SSOT_BLOB,
        "impl_ssot_commit_at_driver_start": cfg.IMPL_SSOT_COMMIT_AT_START,
        "impl_ssot_blob_at_driver_start": cfg.IMPL_SSOT_BLOB_AT_START,
        "impl_ssot_repin": repin,
        "cubrid_base_sha": cfg.CUBRID_BASE_SHA,
        "install_prefix": cfg.CUBRID_HOME,
        "binaries": cfg.binary_fingerprint(),
        "cubrid_conf_sha256_as_installed": cfg.assert_conf_sha(),
        "cubrid_tmp": cfg.CUBRID_TMP,
        "database": cfg.CUBRID_DB,
        "database_files": cfg.CUBRID_DATABASES,
        "cpu_contract": {
            "sut_cpus": cfg.SUT_CPUS, "collector_cpus": cfg.COLLECTOR_CPUS,
            "membind_node": cfg.MEMBIND_NODE,
            "mechanism": "taskset + numactl applied at process start "
                         "(IMPL-SSOT section 3-a); never cpuset cgroups, never "
                         "post-hoc re-pinning",
        },
        "external_load_gate_core_s_per_s": cfg.EXTERNAL_LOAD_THRESHOLD,
        "external_load_gate_source": "IMPL-SSOT section 3-a, AMEND-D",
        "blocks_per_query": cfg.N_BLOCKS,
        "measured_runs_per_block": cfg.N_MEASURED,
        "mde_formula": "max(1%, 2 x baseline_paired_CV)  (section 6-d)",
        "generated_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "campaign_identity": identity,
        "attempt_outcomes_summary": {
            k: v for k, v in _load_attempts().items()
            if k not in ("discarded_attempts", "discarded_by_query")},
        "total_q01_q22_median_wall_seconds": round(
            sum(r["median_wall_seconds"] for r in ok), 4) if ok else None,
        "queries_with_baseline": len(ok),
        "queries": queries,
    }

    jpath = os.path.join(out_dir, "fresh-baseline.json")
    with open(jpath, "w") as f:
        json.dump(doc, f, indent=2, sort_keys=True)
    print("wrote", jpath)

    mpath = os.path.join(out_dir, "raw-manifest.json")
    with open(mpath, "w") as f:
        json.dump({"campaign_id": cfg.CAMPAIGN, "imp_id": "BASELINE",
                   "impl_ssot_commit": cfg.IMPL_SSOT_COMMIT,
                   "impl_ssot_blob": cfg.IMPL_SSOT_BLOB,
                   "generated_utc": doc["generated_utc"],
                   "artifacts": manifest()}, f, indent=2, sort_keys=True)
    print("wrote", mpath)
    return 0


if __name__ == "__main__":
    sys.exit(main())
