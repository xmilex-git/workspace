#!/usr/bin/env python3.11
"""
IMP-015 D6 two-layer test battery — campaign harness TC (no upstream TC-repo
migration; user decision recorded in the spec).

Layer 1 (SQL correctness): a group-by battery that deterministically arms the
new code paths, compared for EXACT equality (IMPL-SSOT section 6-b: ordered
compare — every battery query carries ORDER BY over the group key) in two
directions:
  - cross-variant: base output vs patch output, byte-identical;
  - in-variant: natural output vs serial reference
    (`/*+ NO_HASH_AGGREGATE PARALLEL(1) */`), value-identical.

Layer 2 (shell arming proof): `SET TRACE ON` + `SHOW TRACE`, asserting by
pattern that
  - TA (high-selectivity, > 2000 tuples with > 50% distinct groups in the
    sample; constants verified at source: HASH_AGGREGATE_VH_SELECTIVITY_
    TUPLE_THRESHOLD=2000 / _THRESHOLD=0.5, query_executor.c:131,134) shows
    `hash: partial` — and, on the PATCHED binary only, that the GROUPBY line
    is followed by a `(parallel workers: N)` sub-line with N >= 2. This is
    change (a): runtime HS_REJECT_ALL unlocks the main fallback sort.
  - TB (tiny max_agg_hash_size forces LRU eviction/spill while the hash state
    stays HS_ACCEPT_ALL; eviction path verified at query_executor.c:4798-4836)
    shows `hash: true` — and, on the PATCHED binary only, a
    `(parallel workers: N >= 2)` sub-line. Because change (a) still refuses
    parallelism while the state is HS_ACCEPT_ALL, a parallel sub-line under
    `hash: true` can only come from the partial-list spill sort: this is the
    isolating arming proof for change (b).
  On the BASE binary both sub-lines must be ABSENT (regression detector: this
  TC fails if the fix is silently reverted).

TC-only conf overrides (A5: `parallel_sort_page_threshold` is conf-tunable but
latched via std::call_once, so it is set before server start):
  parallel_sort_page_threshold=4, max_agg_hash_size=32K (PRM minimum),
  agg_hash_respect_order=yes (spec D6 order-sensitive control regime).
The pinned install cubrid.conf (sha256 ad19f5ac..., section 6-a-2) is asserted
before modification and byte-restored + re-asserted afterwards; the override
exists only for the TC server's lifetime and never during a measurement block.

Usage:
  imp015_tc.py run --variant {base,IMP-015} --outdir DIR
  imp015_tc.py compare BASE_DIR PATCH_DIR
"""
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

TC_DB = "imp015tc"
SEQ_N = 200          # seq 0..199; cross join -> 40000 rows
N_ROWS = SEQ_N * SEQ_N

TC_OVERRIDES = """
# --- IMP-015 D6 TC overrides (temporary; restored after the TC run) ---------
parallel_sort_page_threshold=4
max_agg_hash_size=32K
agg_hash_respect_order=yes
"""

# Layer 1 battery: name -> (arming comment, SQL body without hints).
# Every query carries ORDER BY over the group key => section 6-b ordered compare.
BATTERY = {
    "QA1": ("HS_REJECT_ALL arming: 40000 rows, 100% distinct groups",
            "SELECT {h}k, COUNT(*), SUM(v), MIN(v), MAX(v), AVG(v) "
            "FROM t_hs GROUP BY k ORDER BY k"),
    "QB1": ("spill arming under HS_ACCEPT_ALL: 8000 clustered groups of 5, "
            "32K budget (adjacent duplicates keep group_count/tuple_count at "
            "0.2 < 0.5 so the state never flips to HS_REJECT_ALL while LRU "
            "eviction continuously spills finished groups)",
            "SELECT {h}g2, COUNT(*), SUM(v), AVG(v), MIN(pad), MAX(pad) "
            "FROM t_spill GROUP BY g2 ORDER BY g2"),
    "QC1": ("order-sensitive control: GROUP_CONCAT (never hash-eligible, A4)",
            "SELECT {h}g, GROUP_CONCAT(v) FROM t_hs GROUP BY g ORDER BY g"),
    "QC2": ("order-sensitive control: ordered GROUP_CONCAT + MIN/MAX",
            "SELECT {h}g, GROUP_CONCAT(v ORDER BY v DESC), MIN(pad), MAX(pad) "
            "FROM t_hs GROUP BY g ORDER BY g"),
}
SERIAL_HINT = "/*+ NO_HASH_AGGREGATE PARALLEL(1) */ "

# Layer 2 trace probes: name -> (SQL, expected hash mode on the GROUPBY line).
TRACE_PROBES = {
    "TA": ("SELECT k, COUNT(*), SUM(v), MIN(v), MAX(v), AVG(v) "
           "FROM t_hs GROUP BY k", "hash: partial"),
    "TB": ("SELECT g2, COUNT(*), SUM(v), AVG(v), MIN(pad), MAX(pad) "
           "FROM t_spill GROUP BY g2", "hash: true"),
}


def sha256_file(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def die(msg):
    print(f"IMP015-TC FATAL: {msg}", file=sys.stderr)
    sys.exit(1)


def load_cfg(variant):
    os.environ["TPCH_SSPQ_IMPL_VARIANT"] = variant
    os.environ.pop("TPCH_SSPQ_IMPL_PREFIX", None)
    import campaign_config as cfg
    return cfg


def tc_env(cfg):
    env = dict(os.environ)
    env.update({
        "CUBRID": cfg.CUBRID_HOME,
        "CUBRID_DATABASES": os.path.join(cfg.RAW_ROOT, "work", "IMP-015",
                                         "tc-databases"),
        "CUBRID_TMP": cfg.CUBRID_TMP,
        "LD_LIBRARY_PATH": f"{cfg.CUBRID_HOME}/lib:{cfg.CUBRID_HOME}/cci/lib",
        "PATH": f"{cfg.CUBRID_HOME}/bin:/usr/local/bin:/usr/bin:/usr/sbin",
    })
    os.makedirs(env["CUBRID_DATABASES"], exist_ok=True)
    os.makedirs(env["CUBRID_TMP"], exist_ok=True)
    return env


def run_logged(cmd, env, log_path, cwd=None, timeout=600):
    """cubrid utilities hang when stdout is a pipe — always sink to a file."""
    with open(log_path, "a") as sink:
        sink.write(f"\n$ {' '.join(cmd)}\n")
        sink.flush()
        p = subprocess.run(cmd, stdout=sink, stderr=subprocess.STDOUT,
                           env=env, cwd=cwd, timeout=timeout)
    return p.returncode


def csql(cfg, env, sql_text, out_path, timeout=600):
    tmp_sql = out_path + ".sql"
    with open(tmp_sql, "w") as f:
        f.write(sql_text + "\n")
    cmd = [os.path.join(cfg.CUBRID_HOME, "bin", "csql"), "-u", "dba",
           TC_DB, "--no-pager", "-i", tmp_sql]
    with open(out_path, "w") as sink:
        p = subprocess.run(cmd, stdout=sink, stderr=subprocess.PIPE,
                           text=True, env=env, timeout=timeout)
    if p.returncode != 0:
        die(f"csql rc={p.returncode} for {out_path}: {p.stderr[-2000:]}")
    if p.stderr and "ERROR" in p.stderr:
        die(f"csql stderr contains ERROR for {out_path}: {p.stderr[-2000:]}")
    with open(out_path) as f:
        body = f.read()
    if not body.strip():
        die(f"csql produced EMPTY output (aborted statement?): {out_path}")
    if "ERROR" in body:
        die(f"csql output contains ERROR: {out_path}")
    return body


def data_sql():
    stmts = ["CREATE TABLE seq (n INT PRIMARY KEY);"]
    for base in range(0, SEQ_N, 50):
        vals = ", ".join(f"({i})" for i in range(base, base + 50))
        stmts.append(f"INSERT INTO seq VALUES {vals};")
    stmts += [
        "CREATE TABLE t_hs (k INT, g INT, v INT, pad VARCHAR(120));",
        f"INSERT INTO t_hs SELECT a.n * {SEQ_N} + b.n,"
        f" (a.n * {SEQ_N} + b.n) % 500, ((a.n * {SEQ_N} + b.n) * 37) % 10007,"
        " RPAD(CAST((a.n * 200 + b.n) % 97 AS VARCHAR), 100, 'x')"
        " FROM seq a, seq b;",
        "CREATE TABLE t_spill (g2 INT, v INT, pad VARCHAR(120));",
        f"INSERT INTO t_spill SELECT (a.n * {SEQ_N} + b.n) / 5,"
        f" ((a.n * {SEQ_N} + b.n) * 53) % 20011,"
        " RPAD(CAST((a.n * 200 + b.n) % 89 AS VARCHAR), 100, 'y')"
        " FROM seq a, seq b;",
    ]
    return "\n".join(stmts)


def groupby_parallel_state(trace_text, want_hash):
    """Return (hash_mode_ok, parallel_workers or 0) for the GROUPBY trace line."""
    lines = trace_text.splitlines()
    for i, ln in enumerate(lines):
        if "GROUPBY (" in ln:
            hash_ok = want_hash in ln
            workers = 0
            if i + 1 < len(lines):
                m = re.search(r"\(parallel workers: (\d+)", lines[i + 1])
                if m:
                    workers = int(m.group(1))
            return hash_ok, workers
    return False, 0


def cmd_run(args):
    cfg = load_cfg(args.variant)
    outdir = os.path.abspath(args.outdir)
    os.makedirs(outdir, exist_ok=True)
    log = os.path.join(outdir, "tc-driver.log")
    env = tc_env(cfg)
    expect_parallel = args.variant != "base"

    conf = os.path.join(cfg.CUBRID_HOME, "conf", "cubrid.conf")
    got = sha256_file(conf)
    if got != cfg.CONF_SHA256:
        die(f"pre-TC conf sha mismatch: {got} != pinned {cfg.CONF_SHA256}")
    with open(conf, "rb") as f:
        pinned_bytes = f.read()

    if subprocess.run(["pgrep", "-x", "cub_server"],
                      stdout=subprocess.DEVNULL).returncode == 0:
        die("a cub_server is already running — ownership gate (3-b) refuses")

    summary = {"variant": args.variant, "cubrid_home": cfg.CUBRID_HOME,
               "expect_parallel": expect_parallel,
               "cub_server_sha256": sha256_file(
                   os.path.join(cfg.CUBRID_HOME, "bin", "cub_server")),
               "overrides": TC_OVERRIDES.strip().splitlines()[1:],
               "layer1": {}, "layer2": {}, "pass": False}
    started = False
    try:
        with open(conf, "wb") as f:
            f.write(pinned_bytes + TC_OVERRIDES.encode())

        dbdir = os.path.join(env["CUBRID_DATABASES"], TC_DB)
        os.makedirs(dbdir, exist_ok=True)
        rc = run_logged(["cubrid", "createdb", "--db-volume-size=128M",
                         "--log-volume-size=128M", TC_DB, "en_US.utf8"],
                        env, log, cwd=dbdir)
        if rc != 0:
            die(f"createdb rc={rc} (see {log})")
        rc = run_logged(["cubrid", "server", "start", TC_DB], env, log)
        if rc != 0:
            die(f"server start rc={rc} (see {log})")
        started = True
        time.sleep(2)

        csql(cfg, env, data_sql(), os.path.join(outdir, "load.out"),
             timeout=1200)

        for name, (comment, body) in BATTERY.items():
            nat = csql(cfg, env, body.format(h="") + ";",
                       os.path.join(outdir, f"{name}-natural.out"))
            ref = csql(cfg, env, body.format(h=SERIAL_HINT) + ";",
                       os.path.join(outdir, f"{name}-serialref.out"))
            rows_nat = re.search(r"(\d+) rows? selected", nat)
            rows_ref = re.search(r"(\d+) rows? selected", ref)
            summary["layer1"][name] = {
                "comment": comment,
                "rows_natural": rows_nat.group(1) if rows_nat else None,
                "rows_serialref": rows_ref.group(1) if rows_ref else None,
            }

        for name, (body, want_hash) in TRACE_PROBES.items():
            out = csql(cfg, env,
                       f"SET TRACE ON;\n{body};\nSHOW TRACE;",
                       os.path.join(outdir, f"{name}-trace.out"))
            hash_ok, workers = groupby_parallel_state(out, want_hash)
            ok = hash_ok and ((workers >= 2) == expect_parallel)
            summary["layer2"][name] = {
                "want_hash": want_hash, "hash_ok": hash_ok,
                "parallel_workers": workers,
                "expected_parallel": expect_parallel, "ok": ok}
            if not ok:
                die(f"layer2 {name} failed: hash_ok={hash_ok} "
                    f"workers={workers} expect_parallel={expect_parallel}")

        summary["pass"] = True
    finally:
        if started:
            run_logged(["cubrid", "server", "stop", TC_DB], env, log)
        run_logged(["cubrid", "deletedb", TC_DB], env, log)
        with open(conf, "wb") as f:
            f.write(pinned_bytes)
        restored = sha256_file(conf)
        summary["conf_restored_sha256"] = restored
        with open(os.path.join(outdir, "summary.json"), "w") as f:
            json.dump(summary, f, indent=2)
        if restored != cfg.CONF_SHA256:
            die(f"conf restore FAILED: {restored}")
    print(f"IMP015-TC run {args.variant}: PASS ({outdir})")


def cmd_compare(args):
    report = {"pairs": {}, "pass": True}
    for name in BATTERY:
        # QC1 (GROUP_CONCAT with NO inner ORDER BY): within-group member order
        # is not a stable invariant once the fallback group-by sort runs in
        # parallel — a PRE-EXISTING upstream property of non-hash-eligible
        # parallel group-by (base natural differs from base serial reference
        # too; verified 2026-08-03, run 20260803T063528Z). The comparison for
        # QC1 therefore sorts the members inside each concat cell (multiset
        # identity); QA1/QB1/QC2 remain exact ordered compares per 6-b.
        concat_canon = (name == "QC1")
        entry = {"concat_canonicalized": concat_canon}
        blobs = {}
        for v, d in (("base", args.base_dir), ("patch", args.patch_dir)):
            with open(os.path.join(d, f"{name}-natural.out"), "rb") as f:
                blobs[v] = canonicalize(f.read(), concat_canon)
        entry["cross_variant_identical"] = blobs["base"] == blobs["patch"]
        for v, d in (("base", args.base_dir), ("patch", args.patch_dir)):
            with open(os.path.join(d, f"{name}-serialref.out"), "rb") as f:
                ref = canonicalize(f.read(), concat_canon)
            entry[f"{v}_natural_eq_serialref"] = (blobs[v] == ref)
        entry["ok"] = (entry["cross_variant_identical"]
                       and entry["base_natural_eq_serialref"]
                       and entry["patch_natural_eq_serialref"])
        report["pairs"][name] = entry
        report["pass"] = report["pass"] and entry["ok"]
    out = os.path.join(args.patch_dir, "compare-report.json")
    with open(out, "w") as f:
        json.dump(report, f, indent=2)
    print(json.dumps(report, indent=2))
    if not report["pass"]:
        die("layer1 comparison FAILED — stop-and-report (section 6-b)")
    print("IMP015-TC compare: PASS")


def canonicalize(blob, concat_canon):
    """Comparison canon: drop csql statement headers (line numbers differ when
    the hint changes the SQL text) and wall-clock decorations; row data is
    otherwise compared verbatim."""
    txt = blob.decode("utf-8", "replace")
    txt = re.sub(r"\(\d+\.\d+ sec\)", "", txt)
    if concat_canon:
        txt = re.sub(
            r"'(\d+(?:,\d+)+)'",
            lambda m: "'" + ",".join(
                sorted(m.group(1).split(","), key=int)) + "'",
            txt)
    keep = [ln.rstrip() for ln in txt.splitlines()
            if not ln.startswith("=== <Result of SELECT Command")]
    return "\n".join(keep)


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
