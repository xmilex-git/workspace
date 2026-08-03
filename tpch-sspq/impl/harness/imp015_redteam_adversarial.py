#!/usr/bin/env python3.11
"""
IMP-015 ultragoal red-team lane — adversarial/boundary battery beyond the D6
TC. Does NOT modify product source or the campaign harness; imports
campaign_config read-only from the checked-in harness directory and owns its
own throwaway TC database (`imp015rt`, separate from the D6 harness's
`imp015tc`) and its own CUBRID_DATABASES directory under this redteam
workdir, per the assignment's self-provision constraint.

Covers (assignment item 2):
  RT-01 empty table GROUP BY
  RT-02 single-row table GROUP BY
  RT-03 all-NULL key GROUP BY (single NULL group)
  RT-04 single group, all rows share one non-NULL key (large row count)
  RT-05 mixed NULL/non-NULL keys, high selectivity (arms HS_REJECT_ALL)
  RT-06 composite (multi-column) GROUP BY key, high selectivity
  RT-07 HAVING + uncorrelated scalar subquery, armed GROUP BY
  RT-08 extreme LOW selectivity negative control (3 groups, many rows)
  RT-09 order-sensitive GROUP_CONCAT(v ORDER BY v) equality (D4)
  RT-10 same-session 10x repeat stability of an armed query
  RT-11 4-session concurrency stress of an armed query (latch/deadlock probe)

Usage:
  redteam_adversarial.py run --variant {base,IMP-015} --outdir DIR
  redteam_adversarial.py compare BASE_DIR PATCH_DIR
"""
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import time

HARNESS = "/home/cubrid/dev/workspace/tpch-sspq/impl/harness"
sys.path.insert(0, HARNESS)

RT_DB = "imp015rt"
SEQ_N = 200
N_ROWS = SEQ_N * SEQ_N

# Same overrides as the D6 harness (imp015_tc.py TC_OVERRIDES): lower the
# parallel-sort minimum input-size threshold (A5) so a ~40000-row TC table
# clears compute_parallel_degree()'s gate, plus a tiny hash budget to keep
# spill-arming reachable for cases that happen to hash first.
OVERRIDES = """
# --- IMP-015 redteam adversarial overrides (temporary; restored after run) --
parallel_sort_page_threshold=4
max_agg_hash_size=32K
agg_hash_respect_order=yes
"""

BATTERY = {
    "RT-01_empty": (
        "empty table GROUP BY",
        "SELECT k, COUNT(*), SUM(v), MIN(v), MAX(v) FROM t_empty "
        "GROUP BY k ORDER BY k"),
    "RT-02_onerow": (
        "single-row table GROUP BY",
        "SELECT k, COUNT(*), SUM(v), MIN(v), MAX(v) FROM t_one "
        "GROUP BY k ORDER BY k"),
    "RT-03_allnull": (
        "all-NULL key GROUP BY -> single NULL group",
        f"SELECT k, COUNT(*), SUM(v), MIN(v), MAX(v) FROM t_allnull "
        "GROUP BY k ORDER BY k"),
    "RT-04_singlegroup": (
        "single non-NULL group, large row count",
        "SELECT k, COUNT(*), SUM(v), MIN(v), MAX(v), AVG(v) FROM t_singlegroup "
        "GROUP BY k ORDER BY k"),
    "RT-05_mixednull": (
        "mixed NULL/non-NULL keys, high selectivity (arms HS_REJECT_ALL)",
        "SELECT k, COUNT(*), SUM(v), MIN(v), MAX(v) FROM t_mixednull "
        "GROUP BY k ORDER BY k"),
    "RT-06_composite": (
        "composite (k1,k2) GROUP BY key, high selectivity",
        "SELECT k1, k2, COUNT(*), SUM(v), MIN(v), MAX(v) FROM t_composite "
        "GROUP BY k1, k2 ORDER BY k1, k2"),
    "RT-07_having_subquery": (
        "HAVING + uncorrelated scalar subquery on an armed GROUP BY",
        "SELECT k1, COUNT(*), SUM(v) FROM t_composite GROUP BY k1 "
        "HAVING SUM(v) > (SELECT AVG(v) FROM t_mixednull) ORDER BY k1"),
    "RT-08_extreme_low_selectivity": (
        "negative control: 3 groups, many rows (must stay unaffected)",
        "SELECT k, COUNT(*), SUM(v), MIN(v), MAX(v) FROM t_extreme "
        "GROUP BY k ORDER BY k"),
    "RT-09_order_concat": (
        "order-sensitive GROUP_CONCAT(v ORDER BY v), D4",
        "SELECT g, GROUP_CONCAT(v ORDER BY v) FROM t_concat_hs "
        "GROUP BY g ORDER BY g"),
}

# RT-10 / RT-11 armed probe query (composite key, high selectivity, bounded
# output via LIMIT so repeated/concurrent hashing stays cheap while the full
# GROUP BY + sort still executes over all N_ROWS rows).
ARMED_PROBE_SQL = (
    "SELECT k1, k2, COUNT(*), SUM(v), MIN(v), MAX(v) FROM t_composite "
    "GROUP BY k1, k2 ORDER BY k1, k2 LIMIT 500;")

TRACE_PROBES = {
    "RT-05_mixednull": "SELECT k, COUNT(*), SUM(v) FROM t_mixednull GROUP BY k;",
    "RT-06_composite": "SELECT k1, k2, COUNT(*) FROM t_composite GROUP BY k1, k2;",
    "RT-08_extreme_low_selectivity": (
        "SELECT k, COUNT(*), SUM(v) FROM t_extreme GROUP BY k;"),
    "RT-09_order_concat": (
        "SELECT g, GROUP_CONCAT(v ORDER BY v) FROM t_concat_hs GROUP BY g;"),
}


def sha256_file(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def sha256_text(text):
    return hashlib.sha256(text.encode("utf-8", "replace")).hexdigest()


def die(msg):
    print(f"IMP015-REDTEAM FATAL: {msg}", file=sys.stderr)
    sys.exit(1)


def load_cfg(variant):
    os.environ["TPCH_SSPQ_IMPL_VARIANT"] = variant
    os.environ.pop("TPCH_SSPQ_IMPL_PREFIX", None)
    import campaign_config as cfg
    return cfg


def rt_env(cfg, outdir):
    env = dict(os.environ)
    databases_dir = os.path.join(outdir, "..", "rt-databases")
    databases_dir = os.path.abspath(databases_dir)
    env.update({
        "CUBRID": cfg.CUBRID_HOME,
        "CUBRID_DATABASES": databases_dir,
        "CUBRID_TMP": cfg.CUBRID_TMP,
        "LD_LIBRARY_PATH": f"{cfg.CUBRID_HOME}/lib:{cfg.CUBRID_HOME}/cci/lib",
        "PATH": f"{cfg.CUBRID_HOME}/bin:/usr/local/bin:/usr/bin:/usr/sbin",
    })
    os.makedirs(env["CUBRID_DATABASES"], exist_ok=True)
    os.makedirs(env["CUBRID_TMP"], exist_ok=True)
    return env


def run_logged(cmd, env, log_path, cwd=None, timeout=600):
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
           RT_DB, "--no-pager", "-i", tmp_sql]
    with open(out_path, "w") as sink:
        p = subprocess.run(cmd, stdout=sink, stderr=subprocess.PIPE,
                           text=True, env=env, timeout=timeout)
    with open(out_path) as f:
        body = f.read()
    return p.returncode, p.stderr, body


def csql_ok(cfg, env, sql_text, out_path, timeout=600):
    rc, err, body = csql(cfg, env, sql_text, out_path, timeout)
    if rc != 0:
        die(f"csql rc={rc} for {out_path}: {err[-2000:]}")
    if err and "ERROR" in err:
        die(f"csql stderr contains ERROR for {out_path}: {err[-2000:]}")
    if not body.strip():
        die(f"csql produced EMPTY output: {out_path}")
    if "ERROR" in body:
        die(f"csql output contains ERROR: {out_path}")
    return body


def data_sql():
    stmts = ["CREATE TABLE seq (n INT PRIMARY KEY);"]
    for base in range(0, SEQ_N, 50):
        vals = ", ".join(f"({i})" for i in range(base, base + 50))
        stmts.append(f"INSERT INTO seq VALUES {vals};")
    stmts += [
        "CREATE TABLE t_empty (k INT, v INT);",
        "CREATE TABLE t_one (k INT, v INT);",
        "INSERT INTO t_one VALUES (5, 42);",
        "CREATE TABLE t_allnull (k INT, v INT);",
        "INSERT INTO t_allnull SELECT NULL, a.n * %(n)s + b.n"
        " FROM seq a, seq b;" % {"n": SEQ_N},
        "CREATE TABLE t_singlegroup (k INT, v INT);",
        "INSERT INTO t_singlegroup SELECT 1, a.n * %(n)s + b.n"
        " FROM seq a, seq b;" % {"n": SEQ_N},
        "CREATE TABLE t_mixednull (k INT, v INT);",
        "INSERT INTO t_mixednull SELECT"
        " CASE WHEN MOD(a.n * %(n)s + b.n, 7) = 0 THEN NULL"
        " ELSE a.n * %(n)s + b.n END,"
        " (a.n * %(n)s + b.n)" % {"n": SEQ_N} +
        " FROM seq a, seq b;",
        "CREATE TABLE t_composite (k1 INT, k2 VARCHAR(4), v INT, pad VARCHAR(80));",
        "INSERT INTO t_composite SELECT a.n * %(n)s + b.n,"
        " CAST(MOD(a.n * %(n)s + b.n, 3) AS VARCHAR(4)),"
        " (a.n * %(n)s + b.n) * 53," % {"n": SEQ_N} +
        " RPAD(CAST(MOD(a.n * 200 + b.n, 89) AS VARCHAR), 80, 'z')"
        " FROM seq a, seq b;",
        "CREATE TABLE t_extreme (k INT, v INT);",
        "INSERT INTO t_extreme SELECT MOD(a.n * %(n)s + b.n, 3),"
        " a.n * %(n)s + b.n FROM seq a, seq b;" % {"n": SEQ_N},
        "CREATE TABLE t_concat_hs (g INT, v INT);",
        "INSERT INTO t_concat_hs SELECT MOD(a.n * %(n)s + b.n, 4000),"
        " a.n * %(n)s + b.n FROM seq a, seq b;" % {"n": SEQ_N},
    ]
    return "\n".join(stmts)


def groupby_parallel_state(trace_text):
    lines = trace_text.splitlines()
    for i, ln in enumerate(lines):
        if "GROUPBY (" in ln:
            workers = 0
            if i + 1 < len(lines):
                m = re.search(r"\(parallel workers: (\d+)", lines[i + 1])
                if m:
                    workers = int(m.group(1))
            hash_mode = None
            for tok in ("hash: partial", "hash: true", "hash: false"):
                if tok in ln:
                    hash_mode = tok
                    break
            return ln.strip(), hash_mode, workers
    return None, None, 0


def cmd_run(args):
    cfg = load_cfg(args.variant)
    outdir = os.path.abspath(args.outdir)
    os.makedirs(outdir, exist_ok=True)
    log = os.path.join(outdir, "rt-driver.log")
    env = rt_env(cfg, outdir)

    conf = os.path.join(cfg.CUBRID_HOME, "conf", "cubrid.conf")
    got = sha256_file(conf)
    if got != cfg.CONF_SHA256:
        die(f"pre-run conf sha mismatch: {got} != pinned {cfg.CONF_SHA256}")
    with open(conf, "rb") as f:
        pinned_bytes = f.read()

    if subprocess.run(["pgrep", "-x", "cub_server"],
                      stdout=subprocess.DEVNULL).returncode == 0:
        die("a cub_server is already running — ownership gate refuses")

    summary = {"variant": args.variant, "cubrid_home": cfg.CUBRID_HOME,
               "battery": {}, "trace": {}, "stability": {}, "concurrency": {},
               "pass": False}
    started = False
    try:
        with open(conf, "wb") as f:
            f.write(pinned_bytes + OVERRIDES.encode())

        dbdir = os.path.join(env["CUBRID_DATABASES"], RT_DB)
        os.makedirs(dbdir, exist_ok=True)
        rc = run_logged(["cubrid", "createdb", "--db-volume-size=128M",
                         "--log-volume-size=128M", RT_DB, "en_US.utf8"],
                        env, log, cwd=dbdir)
        if rc != 0:
            die(f"createdb rc={rc} (see {log})")
        rc = run_logged(["cubrid", "server", "start", RT_DB], env, log)
        if rc != 0:
            die(f"server start rc={rc} (see {log})")
        started = True
        time.sleep(2)

        csql_ok(cfg, env, data_sql(), os.path.join(outdir, "load.out"),
                timeout=1200)

        # --- RT-01..RT-09: battery ------------------------------------------
        for name, (comment, body) in BATTERY.items():
            out = csql_ok(cfg, env, body + ";",
                          os.path.join(outdir, f"{name}.out"))
            rows = re.search(r"(\d+) rows? selected", out)
            summary["battery"][name] = {
                "comment": comment,
                "rows": rows.group(1) if rows else None,
                "sha256": sha256_text(out),
            }

        # --- trace probes (informational: records hash mode + worker count)
        for name, sql in TRACE_PROBES.items():
            out = csql_ok(cfg, env, f"SET TRACE ON;\n{sql}\nSHOW TRACE;",
                          os.path.join(outdir, f"{name}-trace.out"))
            line, hash_mode, workers = groupby_parallel_state(out)
            summary["trace"][name] = {
                "groupby_line": line, "hash_mode": hash_mode,
                "parallel_workers": workers,
            }

        # --- RT-10: same-session 10x repeat stability -----------------------
        stab_sql = "\n".join([ARMED_PROBE_SQL] * 10)
        out = csql_ok(cfg, env, stab_sql, os.path.join(outdir, "RT-10.out"),
                      timeout=600)
        blocks = re.split(r"=== <Result of SELECT Command", out)[1:]
        hashes = [sha256_text(canon_block(b)) for b in blocks]
        summary["stability"] = {
            "runs": len(hashes),
            "all_identical": len(set(hashes)) == 1 if hashes else False,
            "distinct_hashes": len(set(hashes)),
        }
        if len(hashes) != 10 or len(set(hashes)) != 1:
            die(f"RT-10 stability FAILED: {len(hashes)} runs, "
                f"{len(set(hashes))} distinct results")

        # --- RT-11: 4-session concurrency stress ----------------------------
        n_sessions = 4
        n_iters = 3
        conc_sql = "\n".join([ARMED_PROBE_SQL] * n_iters)
        conc_sql_path = os.path.join(outdir, "RT-11.sql")
        with open(conc_sql_path, "w") as f:
            f.write(conc_sql + "\n")
        procs = []
        for i in range(n_sessions):
            out_path = os.path.join(outdir, f"RT-11-session{i}.out")
            err_path = os.path.join(outdir, f"RT-11-session{i}.err")
            cmd = [os.path.join(cfg.CUBRID_HOME, "bin", "csql"), "-u", "dba",
                   RT_DB, "--no-pager", "-i", conc_sql_path]
            fout = open(out_path, "w")
            ferr = open(err_path, "w")
            procs.append((subprocess.Popen(cmd, stdout=fout, stderr=ferr,
                                           env=env), fout, ferr, out_path,
                         err_path))
        session_hashes = []
        session_errors = []
        for proc, fout, ferr, out_path, err_path in procs:
            rc = proc.wait(timeout=600)
            fout.close()
            ferr.close()
            with open(err_path) as f:
                errtext = f.read()
            with open(out_path) as f:
                body = f.read()
            if rc != 0 or "ERROR" in errtext or "ERROR" in body:
                session_errors.append({"out": out_path, "rc": rc,
                                       "stderr": errtext[-1000:]})
            blocks = [canon_block(b) for b in
                     re.split(r"=== <Result of SELECT Command", body)[1:]]
            for b in blocks:
                session_hashes.append(sha256_text(b))
        summary["concurrency"] = {
            "sessions": n_sessions, "iters_per_session": n_iters,
            "total_results": len(session_hashes),
            "all_identical": (len(set(session_hashes)) == 1
                              if session_hashes else False),
            "distinct_hashes": len(set(session_hashes)),
            "errors": session_errors,
        }
        if session_errors:
            die(f"RT-11 concurrency FAILED: errors={session_errors}")
        if len(session_hashes) != n_sessions * n_iters or \
                len(set(session_hashes)) != 1:
            die(f"RT-11 concurrency FAILED: "
                f"{len(session_hashes)} results, "
                f"{len(set(session_hashes))} distinct")

        summary["pass"] = True
    finally:
        if started:
            run_logged(["cubrid", "server", "stop", RT_DB], env, log)
        run_logged(["cubrid", "deletedb", RT_DB], env, log)
        with open(conf, "wb") as f:
            f.write(pinned_bytes)
        restored = sha256_file(conf)
        summary["conf_restored_sha256"] = restored
        with open(os.path.join(outdir, "summary.json"), "w") as f:
            json.dump(summary, f, indent=2)
        if restored != cfg.CONF_SHA256:
            die(f"conf restore FAILED: {restored}")
    print(f"IMP015-REDTEAM run {args.variant}: "
          f"{'PASS' if summary['pass'] else 'FAIL'} ({outdir})")
    if not summary["pass"]:
        sys.exit(1)


def canon_block(block_text):
    """Canonicalize one csql result block split on the '=== <Result of
    SELECT Command' marker: the remainder still starts with ' in Line N> ===
    ...' whose line number varies with the statement's position in a
    multi-statement script, plus per-run wall-clock timing — neither is a
    real result difference."""
    txt = re.sub(r"^\s*in Line \d+>\s*===\s*", "", block_text)
    txt = re.sub(r"\(\d+\.\d+ sec\)", "", txt)
    return txt.rstrip()

def canonicalize(blob):
    txt = blob.decode("utf-8", "replace") if isinstance(blob, bytes) else blob
    txt = re.sub(r"\(\d+\.\d+ sec\)", "", txt)
    keep = [ln.rstrip() for ln in txt.splitlines()
            if not ln.startswith("=== <Result of SELECT Command")]
    return "\n".join(keep)


def cmd_compare(args):
    report = {"pairs": {}, "pass": True}
    for name in BATTERY:
        entry = {}
        blobs = {}
        for v, d in (("base", args.base_dir), ("patch", args.patch_dir)):
            with open(os.path.join(d, f"{name}.out"), "rb") as f:
                blobs[v] = canonicalize(f.read())
        entry["cross_variant_identical"] = blobs["base"] == blobs["patch"]
        entry["ok"] = entry["cross_variant_identical"]
        report["pairs"][name] = entry
        report["pass"] = report["pass"] and entry["ok"]
    out = os.path.join(args.patch_dir, "compare-report.json")
    with open(out, "w") as f:
        json.dump(report, f, indent=2)
    print(json.dumps(report, indent=2))
    if not report["pass"]:
        die("adversarial cross-variant comparison FAILED")
    print("IMP015-REDTEAM compare: PASS")


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
