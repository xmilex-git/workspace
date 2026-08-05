#!/usr/bin/env python3.11
"""
IMP-005 gate-1 probe: nl-join parallel trace merge duplication.

Hypothesis (implementation-plan.md section 1): on the BASE binary, a scan_ptr
chain node at depth k has its integer trace counters merged k times per
sibling tree by trace_storage_for_sibling_xasl::merge_xasl_tree; on the PATCH
binary each node is merged exactly once, so parallel-leg counters equal the
serial-leg counters.

Per query, two legs on one server instance:
  S: every SELECT gets /*+ NO_PARALLEL_SCAN */  (serial truth)
  P: natural statement                          (parallel, exercises the merge)

compare asserts, on deterministic integer counters only
(readrows, readkeys, filteredkeys, rows):
  A. serial legs are identical base-vs-patch (the patch cannot touch serial);
  B. patch parallel == patch serial on every matched SCAN node;
  C. base parallel >= patch parallel everywhere, strictly > somewhere
     (the section 5 metric signature: duplication removed, direction down).
Queries whose serial/parallel plan shapes differ are reported SHAPE_MISMATCH
and excluded; at least one usable query MUST show a strict improvement.

Usage:
  imp005_trace_probe.py run --variant {base,IMP-005} --outdir DIR
  imp005_trace_probe.py compare BASE_DIR PATCH_DIR
"""
import argparse
import json
import os
import re
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

TARGETS = ["q05", "q07", "q08", "q09", "q21"]
COUNTERS = ("readrows", "readkeys", "filteredkeys", "rows")


def die(msg):
    print(f"IMP005-TRACE FATAL: {msg}", file=sys.stderr)
    sys.exit(1)


def load_cfg(variant):
    os.environ["TPCH_SSPQ_IMPL_VARIANT"] = variant
    os.environ.pop("TPCH_SSPQ_IMPL_PREFIX", None)
    import campaign_config as cfg
    return cfg


def run_logged(cmd, env, log_path, timeout=900):
    with open(log_path, "a") as sink:
        sink.write(f"\n$ {' '.join(cmd)}\n")
        sink.flush()
        p = subprocess.run(cmd, stdout=sink, stderr=subprocess.STDOUT,
                           env=env, timeout=timeout)
    return p.returncode


def leg_sql(query_text, serial):
    if serial:
        query_text = re.sub(r"(?i)\bselect\b",
                            "select /*+ NO_PARALLEL_SCAN */", query_text)
    return f"SET TRACE ON;\n{query_text}\nSHOW TRACE;\n"


def cmd_run(args):
    cfg = load_cfg(args.variant)
    outdir = os.path.abspath(args.outdir)
    os.makedirs(outdir, exist_ok=True)
    log = os.path.join(outdir, "driver.log")
    env = cfg.campaign_env()
    env["PATH"] = f"{cfg.CUBRID_HOME}/bin:/usr/local/bin:/usr/bin:/usr/sbin"

    import hashlib
    with open(os.path.join(cfg.CUBRID_HOME, "conf", "cubrid.conf"), "rb") as f:
        conf_sha = hashlib.sha256(f.read()).hexdigest()
    if conf_sha != cfg.CONF_SHA256:
        die(f"conf sha {conf_sha} != pinned {cfg.CONF_SHA256}")
    if subprocess.run(["pgrep", "-x", "cub_server"],
                      stdout=subprocess.DEVNULL).returncode == 0:
        die("a cub_server is already running — ownership gate (3-b) refuses")

    started = False
    try:
        if run_logged(["cubrid", "server", "start", cfg.CUBRID_DB],
                      env, log, timeout=900) != 0:
            die(f"server start failed (see {log})")
        started = True
        time.sleep(2)
        for q in TARGETS:
            with open(os.path.join(cfg.QUERIES, f"{q}-cubrid.sql")) as f:
                text = f.read()
            for leg, serial in (("S", True), ("P", False)):
                sqlfile = os.path.join(outdir, f"{q}-{leg}.sql")
                outfile = os.path.join(outdir, f"{q}-{leg}.out")
                with open(sqlfile, "w") as f:
                    f.write(leg_sql(text, serial))
                cmd = [os.path.join(cfg.CUBRID_HOME, "bin", "csql"),
                       "-u", "dba", cfg.CUBRID_DB, "-i", sqlfile,
                       "-o", outfile]
                p = subprocess.run(cmd, env=env, capture_output=True,
                                   text=True, timeout=cfg.TIMEOUT + 600)
                if p.returncode != 0:
                    die(f"csql rc={p.returncode} {q}-{leg}: {p.stderr[:1500]}")
                body = open(outfile).read()
                if "Trace Statistics" not in body:
                    die(f"no trace in {q}-{leg} output")
    finally:
        if started:
            run_logged(["cubrid", "server", "stop", cfg.CUBRID_DB], env, log)
    print(f"IMP005-TRACE run {args.variant}: captured ({outdir})")


SCAN_RE = re.compile(r"^(\s*)SCAN \((table|index): ([^)]+)\)")
KV_RE = re.compile(r"(\w+): (\d+)")


def parse_scans(path):
    """ordered list of (depth, kind, name, {counter: summed_value})"""
    nodes = []
    for ln in open(path):
        m = SCAN_RE.match(ln)
        if not m:
            continue
        vals = {}
        for k, v in KV_RE.findall(ln):
            if k in COUNTERS:
                vals[k] = vals.get(k, 0) + int(v)
        nodes.append((len(m.group(1)), m.group(2), m.group(3).strip(),
                      vals))
    return nodes


def shapes_equal(a, b):
    return [(d, k, n) for d, k, n, _ in a] == [(d, k, n) for d, k, n, _ in b]


def cmd_compare(args):
    report = {"queries": {}, "pass": True, "strict_improvement_seen": False}
    for q in TARGETS:
        entry = {"status": "OK", "nodes": []}
        report["queries"][q] = entry
        legs = {}
        for tag, d in (("base", args.base_dir), ("patch", args.patch_dir)):
            for leg in ("S", "P"):
                legs[(tag, leg)] = parse_scans(os.path.join(d, f"{q}-{leg}.out"))
        # A: serial identical across variants
        if legs[("base", "S")] != legs[("patch", "S")]:
            entry["status"] = "SERIAL_DIVERGED"
            report["pass"] = False
            continue
        # shape match S vs P (within patch)
        if not (shapes_equal(legs[("patch", "S")], legs[("patch", "P")])
                and shapes_equal(legs[("base", "P")], legs[("patch", "P")])):
            entry["status"] = "SHAPE_MISMATCH"  # excluded, not a failure
            continue
        for i, (d_, k_, n_, s_vals) in enumerate(legs[("patch", "S")]):
            bp = legs[("base", "P")][i][3]
            pp = legs[("patch", "P")][i][3]
            node = {"depth": d_, "kind": k_, "name": n_,
                    "serial": s_vals, "base_par": bp, "patch_par": pp}
            entry["nodes"].append(node)
            for c in COUNTERS:
                if c not in s_vals:
                    continue
                # B: patch parallel == serial truth
                if pp.get(c) != s_vals[c]:
                    node[f"B_fail_{c}"] = True
                    entry["status"] = "PATCH_NE_SERIAL"
                    report["pass"] = False
                # C: base >= patch, strictly > somewhere
                if bp.get(c, 0) < pp.get(c, 0):
                    node[f"C_regress_{c}"] = True
                    entry["status"] = "PATCH_ABOVE_BASE"
                    report["pass"] = False
                elif bp.get(c, 0) > pp.get(c, 0):
                    node[f"dup_factor_{c}"] = round(bp[c] / pp[c], 3) if pp.get(c) else None
                    report["strict_improvement_seen"] = True
    if not report["strict_improvement_seen"]:
        report["pass"] = False
        report["note"] = ("no strict counter reduction found on any target — "
                          "section 7-e surprise, root-cause re-exam required")
    out = os.path.join(args.patch_dir, "trace-probe-report.json")
    with open(out, "w") as f:
        json.dump(report, f, indent=2)
    print(json.dumps({q: v["status"] for q, v in report["queries"].items()},
                     indent=1))
    print(f"strict_improvement_seen={report['strict_improvement_seen']}")
    if not report["pass"]:
        die("gate-1 trace probe FAILED (see trace-probe-report.json)")
    print("IMP005-TRACE compare: PASS")


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("run")
    r.add_argument("--variant", required=True, choices=["base", "IMP-005"])
    r.add_argument("--outdir", required=True)
    r.set_defaults(fn=cmd_run)
    c = sub.add_parser("compare")
    c.add_argument("base_dir")
    c.add_argument("patch_dir")
    c.set_defaults(fn=cmd_compare)
    args = ap.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
