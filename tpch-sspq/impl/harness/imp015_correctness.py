#!/usr/bin/env python3.11
"""
IMP-015 section 6-b correctness gate — base-versus-patch on the SAME engine.

smoke_check.py compares CUBRID against the PostgreSQL reference (cross-engine,
tolerance-bearing). The 6-b A/B gate is stricter: base binary and patch binary
on the same data MUST be EXACTLY equal — ordered compare when the query has
ORDER BY, canonical sort with duplicate multiplicity preserved otherwise, raw
decimal text preserved (value and scale), no numeric tolerance at all.

Covers 6-b mandatory checks 2, 3 and 4 in one sweep:
  - target queries Q10 / Q15 / Q18,
  - every q_relations query (Q10, Q11, Q15, Q18),
  - the full Q01-Q22 result smoke,
  - the Q15 view protocol: proved absent before, dropped and re-proved after.

Usage:
  imp015_correctness.py run --variant {base,IMP-015} --outdir DIR
  imp015_correctness.py compare BASE_DIR PATCH_DIR
"""
import argparse
import json
import os
import re
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

DELIM = "\x1f"
REGULAR = [f"q{n}" for n in range(1, 23) if n != 15]


def die(msg):
    print(f"IMP015-CORRECTNESS FATAL: {msg}", file=sys.stderr)
    sys.exit(1)


def load_cfg(variant):
    os.environ["TPCH_SSPQ_IMPL_VARIANT"] = variant
    os.environ.pop("TPCH_SSPQ_IMPL_PREFIX", None)
    import campaign_config as cfg
    return cfg


def run_logged(cmd, env, log_path, timeout=600):
    with open(log_path, "a") as sink:
        sink.write(f"\n$ {' '.join(cmd)}\n")
        sink.flush()
        p = subprocess.run(cmd, stdout=sink, stderr=subprocess.STDOUT,
                           env=env, timeout=timeout)
    return p.returncode


def csql_file(cfg, env, sqlfile, out_path, timeout):
    cmd = [os.path.join(cfg.CUBRID_HOME, "bin", "csql"), "-u", "dba",
           cfg.CUBRID_DB, "-q", "-N", f"--delimiter={DELIM}",
           "--enclosure=\"", "-i", sqlfile]
    p = subprocess.run(cmd, env=env, capture_output=True, text=True,
                       timeout=timeout)
    with open(out_path, "w") as f:
        f.write(p.stdout)
    if p.returncode != 0:
        die(f"csql rc={p.returncode} for {sqlfile}: {p.stderr[:2000]}")
    if "ERROR" in p.stderr:
        die(f"csql stderr ERROR for {sqlfile}: {p.stderr[:2000]}")
    if not p.stdout.strip():
        die(f"csql produced EMPTY output (aborted statement?): {sqlfile}")
    if "ERROR" in p.stdout:
        die(f"csql output body contains ERROR: {sqlfile}")
    return p.stdout


def csql_stmt(cfg, env, stmt, timeout=30):
    cmd = [os.path.join(cfg.CUBRID_HOME, "bin", "csql"), "-u", "dba",
           cfg.CUBRID_DB, "-q", "-N", f"--delimiter={DELIM}", "-c", stmt]
    p = subprocess.run(cmd, env=env, capture_output=True, text=True,
                       timeout=timeout)
    return p.returncode, p.stdout.strip()


def view_exists(cfg, env):
    rc, out = csql_stmt(
        cfg, env,
        "select count(*) from db_class where class_name = 'revenue0';")
    return rc == 0 and out not in ("0", "")


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

    summary = {"variant": args.variant, "cubrid_home": cfg.CUBRID_HOME,
               "conf_sha256": conf_sha, "queries": {}, "pass": False}
    started = False
    try:
        if run_logged(["cubrid", "server", "start", cfg.CUBRID_DB],
                      env, log, timeout=900) != 0:
            die(f"server start failed (see {log})")
        started = True
        time.sleep(2)

        for q in REGULAR:
            sql = os.path.join(cfg.QUERIES, f"{q}-cubrid.sql")
            out = os.path.join(outdir, f"{q}.out")
            csql_file(cfg, env, sql, out, cfg.TIMEOUT + 300)
            summary["queries"][q] = {"rows": sum(
                1 for ln in open(out) if ln.strip())}

        # Q15 protocol: view proved absent -> create -> select -> drop -> absent
        if view_exists(cfg, env):
            die("Q15 view revenue0 already exists before create")
        summary["q15_pre_absent"] = True
        csql_file(cfg, env, os.path.join(cfg.QUERIES, "q15_create_view-cubrid.sql"),
                  os.path.join(outdir, "q15_create.out"), 300)
        csql_file(cfg, env, os.path.join(cfg.QUERIES, "q15_select-cubrid.sql"),
                  os.path.join(outdir, "q15.out"), cfg.TIMEOUT + 300)
        csql_file(cfg, env, os.path.join(cfg.QUERIES, "q15_drop_view-cubrid.sql"),
                  os.path.join(outdir, "q15_drop.out"), 300)
        if view_exists(cfg, env):
            die("Q15 view revenue0 still exists after drop")
        summary["q15_post_absent"] = True
        summary["queries"]["q15"] = {"rows": sum(
            1 for ln in open(os.path.join(outdir, "q15.out")) if ln.strip())}
        summary["pass"] = True
    finally:
        if started:
            run_logged(["cubrid", "server", "stop", cfg.CUBRID_DB], env, log)
        with open(os.path.join(outdir, "summary.json"), "w") as f:
            json.dump(summary, f, indent=2)
    print(f"IMP015-CORRECTNESS run {args.variant}: PASS ({outdir})")


def query_has_order_by(cfg_queries, q):
    name = "q15_select" if q == "q15" else q
    with open(os.path.join(cfg_queries, f"{name}-cubrid.sql")) as f:
        return bool(re.search(r"order\s+by", f.read(), re.IGNORECASE))


def cmd_compare(args):
    cfg = load_cfg("base")
    report = {"queries": {}, "pass": True}
    for q in REGULAR + ["q15"]:
        pa = os.path.join(args.base_dir, f"{q}.out")
        pb = os.path.join(args.patch_dir, f"{q}.out")
        with open(pa) as f:
            rows_a = [ln for ln in f.read().split("\n") if ln != ""]
        with open(pb) as f:
            rows_b = [ln for ln in f.read().split("\n") if ln != ""]
        ordered = query_has_order_by(cfg.QUERIES, q)
        if not ordered:
            # canonical sort, duplicate multiplicity preserved (never a set)
            rows_a, rows_b = sorted(rows_a), sorted(rows_b)
        equal = rows_a == rows_b
        # vacuous-pass guard: a query producing zero rows on both sides would
        # otherwise "pass"; every TPC-H answer here is non-empty by contract.
        nonvacuous = len(rows_a) > 0 and len(rows_b) > 0
        report["queries"][q] = {"ordered": ordered, "rows": len(rows_a),
                                "rows_patch": len(rows_b), "equal": equal,
                                "nonvacuous": nonvacuous}
        if not equal or not nonvacuous:
            for i, (x, y) in enumerate(zip(rows_a, rows_b)):
                if x != y:
                    report["queries"][q]["first_diff_index"] = i
                    break
            report["pass"] = False
    out = os.path.join(args.patch_dir, "correctness-report.json")
    with open(out, "w") as f:
        json.dump(report, f, indent=2)
    print(json.dumps(report, indent=2))
    if not report["pass"]:
        die("6-b correctness gate FAILED — stop-and-report")
    print("IMP015-CORRECTNESS compare: PASS (all queries EXACTLY equal)")


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("run")
    r.add_argument("--variant", required=True, choices=["base", "IMP-015"])
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
