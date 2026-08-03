#!/usr/bin/env python3.11
"""
TPCH-SSPQ implementation campaign `tpch-sspq-impl-r1-20260803` — per-query
reference capture on the immutable base binary.

Collects the parts of the IMPL-SSOT section 6 metric set that are NOT produced by
the timed contract block, plus the section 6-b correctness reference. All of it is
captured on the base binary, which is the cheapest correct moment to produce the
reference the later A/B work compares against.

  1. CANONICAL RESULT SET (section 6-b). ORDER BY queries keep the exact ordered
     sequence; non-ORDER BY queries are canonically sorted with duplicate
     multiplicity preserved (never converted to a set); decimals are kept as raw
     text so both value and scale survive. The canonical form is hashed, and the
     hash — not a re-run — is what a patched build is later compared against.
  2. PLAN ESTIMATED vs ACTUAL ROWS (sections 6-c, 7-d). `SET OPTIMIZATION LEVEL
     514` gives the estimated plan; `SET TRACE ON` + `SHOW TRACE` gives actual
     row counts from the same engine.
  3. HARDWARE COUNTERS (section 6-c): cycles, instructions, IPC, task-clock,
     context switches, sampled by `perf stat` attached to the running cub_server
     for exactly the query's execution window.
  4. EXECUTION TELEMETRY (section 6-c): executor / auxiliary / total CPU, TWU
     computed from actual sample timestamp deltas, the serial tail, /proc I/O and
     device I/O, and the NUMA page distribution — via telemetry_run.py.
  5. ENGINE COUNTERS (section 6-c): full `cubrid statdump -c` before and after,
     giving buffer, temp-file/temp-space and memory counters.

Nothing here is a headline timing value. The headline medians come only from the
gated contract blocks.

Usage: reference_capture.py QNN
"""
import json
import os
import re
import signal
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import campaign_config as cfg  # noqa: E402
import smoke_check as sc  # noqa: E402

DELIM = sc.DELIM


def raw_dir(qnn):
    d = os.path.join(cfg.RAW_ROOT, "raw", qnn)
    os.makedirs(d, exist_ok=True)
    return d


def query_files(qnn):
    n = int(qnn[1:])
    if qnn == "Q15":
        return [os.path.join(cfg.QUERIES, f"q15_{p}-cubrid.sql")
                for p in ("create_view", "select", "drop_view")]
    return [os.path.join(cfg.QUERIES, f"q{n}-cubrid.sql")]


def read_sql(path):
    with open(path) as f:
        t = f.read().rstrip()
    return t if t.endswith(";") else t + ";"


def csql(sql_text, out_path, extra_args=(), timeout=cfg.TIMEOUT):
    """One direct campaign connection; output to a campaign-owned file sink."""
    tmp_sql = out_path + ".sql"
    with open(tmp_sql, "w") as f:
        f.write(sql_text + "\n")
    cmd = ["taskset", "-c", cfg.SUT_CPUS,
           os.path.join(cfg.CUBRID_HOME, "bin", "csql"),
           "-u", "dba", cfg.CUBRID_DB, "--no-pager", *extra_args, "-i", tmp_sql]
    with open(out_path, "w") as sink:
        try:
            p = subprocess.run(cmd, stdout=sink, stderr=subprocess.PIPE, text=True,
                               env=cfg.campaign_env(), timeout=timeout)
            return p.returncode, p.stderr, False
        except subprocess.TimeoutExpired:
            return None, "", True


def statdump(tag, qnn):
    path = os.path.join(raw_dir(qnn), f"{qnn}-statdump-{tag}.txt")
    with open(path, "w") as f:
        subprocess.run([os.path.join(cfg.CUBRID_HOME, "bin", "cubrid"),
                        "statdump", "-c", cfg.CUBRID_DB],
                       stdout=f, stderr=subprocess.STDOUT,
                       env=cfg.campaign_env(), timeout=120)
    return path


def canonical_result(qnn):
    """Section 6-b canonical result set from the base binary."""
    d = raw_dir(qnn)
    files = query_files(qnn)
    select_sql = files[1] if qnn == "Q15" else files[0]
    ordered = sc.query_has_order_by(select_sql)

    if qnn == "Q15":
        # Q15 is one logical unit: prove the view absent, create, select, drop,
        # prove absent again (sections 3-c and 6-b).
        pre = view_exists()
        if pre:
            csql("drop view revenue0;", os.path.join(d, "Q15-stale-drop.out"),
                 ("-q", "-N"))
            pre = view_exists()
        body = read_sql(files[0])
        rc0, err0, to0 = csql(body, os.path.join(d, "Q15-create_view.out"), ("-q", "-N"))
        created = view_exists()
    else:
        pre = created = None
        rc0 = err0 = to0 = None

    out_path = os.path.join(d, f"{qnn}-reference-raw.out")
    rc, err, to = csql(read_sql(select_sql), out_path,
                       ("-q", "-N", f"--delimiter={DELIM}", '--enclosure="'))

    if qnn == "Q15":
        csql(read_sql(files[2]), os.path.join(d, "Q15-drop_view.out"), ("-q", "-N"))
        post = view_exists()
    else:
        post = None

    result = {"ordered": ordered, "select_sql": select_sql,
              "client_exit": rc, "timed_out": to,
              "client_stderr": (err or "")[-1000:]}
    if qnn == "Q15":
        result["view_state"] = {"before_create": pre, "after_create": created,
                                "after_drop": post}
        result["create_view_exit"] = rc0

    if to or rc != 0:
        result["status"] = "censored" if to else "error"
        return result

    with open(out_path) as f:
        rows = sc.parse_output(f.read(), "cubrid")
    seq = rows if ordered else sorted(rows, key=sc.sort_key)
    canon_path = os.path.join(d, f"{qnn}-reference-canonical.txt")
    with open(canon_path, "w") as f:
        for r in seq:
            f.write("\x1f".join("\x00NULL\x00" if v is None else v for v in r))
            f.write("\n")
    result.update({
        "status": "captured",
        "row_count": len(rows),
        "canonicalization": ("exact ordered sequence (query has ORDER BY)" if ordered
                             else "canonically sorted, duplicate multiplicity "
                                  "preserved (never a set)"),
        "decimal_policy": "raw text preserved — value and scale both exact",
        "raw_path": out_path,
        "canonical_path": canon_path,
        "canonical_sha256": cfg.sha256_file(canon_path),
        "raw_sha256": cfg.sha256_file(out_path),
    })
    return result


def view_exists():
    r = subprocess.run(
        [os.path.join(cfg.CUBRID_HOME, "bin", "csql"), "-u", "dba", cfg.CUBRID_DB,
         "-q", "-N", "-c",
         "select count(*) from db_class where class_name = 'revenue0';"],
        capture_output=True, text=True, env=cfg.campaign_env(), timeout=60)
    return int((r.stdout or "0").strip() or "0") > 0


def plan_and_actual(qnn):
    """Section 6-c / 7-d: plan estimated rows versus actual rows."""
    d = raw_dir(qnn)
    select_sql = query_files(qnn)[1] if qnn == "Q15" else query_files(qnn)[0]
    body = read_sql(select_sql)
    if qnn == "Q15":
        csql(read_sql(query_files(qnn)[0]),
             os.path.join(d, "Q15-plan-create_view.out"), ("-q", "-N"))
    est = os.path.join(d, f"{qnn}-plan-estimated.out")
    csql("SET OPTIMIZATION LEVEL 514;\n" + body, est)
    act = os.path.join(d, f"{qnn}-plan-actual-trace.out")
    csql("SET TRACE ON;\n" + body + "\nSHOW TRACE;", act)
    if qnn == "Q15":
        csql(read_sql(query_files(qnn)[2]),
             os.path.join(d, "Q15-plan-drop_view.out"), ("-q", "-N"))
    return {"estimated_plan_path": est, "actual_trace_path": act,
            "estimated_sha256": cfg.sha256_file(est) if os.path.exists(est) else None,
            "actual_sha256": cfg.sha256_file(act) if os.path.exists(act) else None}


PERF_RE = re.compile(r"^\s*([\d,\.]+)\s+(\S+)")


def perf_counters(qnn):
    """Section 6-c: cycles, instructions, IPC over exactly the query window."""
    d = raw_dir(qnn)
    srv = subprocess.run(["pgrep", "-f", f"cub_server {cfg.CUBRID_DB}"],
                         capture_output=True, text=True).stdout.split()
    if not srv:
        return {"status": "no_server"}
    pid = srv[0]
    out = os.path.join(d, f"{qnn}-perf-stat.txt")
    perf = subprocess.Popen(
        ["taskset", "-c", cfg.COLLECTOR_CPUS, "perf", "stat", "-p", pid,
         "-e", "cycles,instructions,task-clock,context-switches", "-o", out],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.5)
    select_sql = query_files(qnn)[1] if qnn == "Q15" else query_files(qnn)[0]
    if qnn == "Q15":
        csql(read_sql(query_files(qnn)[0]),
             os.path.join(d, "Q15-perf-create_view.out"), ("-q", "-N"))
    rc, err, to = csql(read_sql(select_sql),
                       os.path.join(d, f"{qnn}-perf-query.out"), ("-q", "-N"))
    if qnn == "Q15":
        csql(read_sql(query_files(qnn)[2]),
             os.path.join(d, "Q15-perf-drop_view.out"), ("-q", "-N"))
    perf.send_signal(signal.SIGINT)
    try:
        perf.wait(timeout=30)
    except subprocess.TimeoutExpired:
        perf.kill()
    vals = {}
    try:
        with open(out) as f:
            for line in f:
                m = PERF_RE.match(line)
                if m and m.group(2) in ("cycles", "instructions", "task-clock",
                                        "context-switches"):
                    vals[m.group(2)] = float(m.group(1).replace(",", ""))
    except OSError:
        pass
    if vals.get("cycles"):
        vals["ipc"] = round(vals.get("instructions", 0) / vals["cycles"], 4)
    return {"status": "captured" if vals else "unparsed", "path": out,
            "client_exit": rc, "timed_out": to, "counters": vals}


def main():
    if len(sys.argv) != 2:
        print("usage: reference_capture.py QNN", file=sys.stderr)
        return 2
    qnn = sys.argv[1].upper()
    cfg.assert_cubrid_tmp()
    conf = cfg.assert_conf_sha()
    cfg.assert_prefix_allowed()
    d = raw_dir(qnn)

    out = {
        "campaign_id": cfg.CAMPAIGN,
        "impl_ssot_commit": cfg.IMPL_SSOT_COMMIT,
        "impl_ssot_blob": cfg.IMPL_SSOT_BLOB,
        "qnn": qnn,
        "stage": "phase1a-reference-capture",
        "headline": False,
        "install_prefix": cfg.CUBRID_HOME,
        "cubrid_conf_sha256": conf,
        "cubrid_tmp": cfg.CUBRID_TMP,
        "binaries": cfg.binary_fingerprint(),
        "started_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }
    out["statdump_pre"] = statdump("pre", qnn)
    out["canonical_result"] = canonical_result(qnn)
    out["plan"] = plan_and_actual(qnn)
    out["perf"] = perf_counters(qnn)

    # Execution telemetry: executor/aux CPU, TWU, serial tail, /proc + device I/O,
    # NUMA distribution. Runs the adapted telemetry_run.py in-process-tree.
    tel = subprocess.run(
        ["python3.11", os.path.join(cfg.HARNESS, "telemetry_run.py"), qnn, "cubrid"],
        capture_output=True, text=True, env=cfg.campaign_env())
    tel_path = os.path.join(cfg.RAW_ROOT, "work", qnn, f"{qnn}-cubrid-telemetry.json")
    out["telemetry"] = {"rc": tel.returncode, "path": tel_path,
                        "exists": os.path.exists(tel_path)}
    if os.path.exists(tel_path):
        dst = os.path.join(d, f"{qnn}-telemetry.json")
        with open(tel_path) as f:
            tj = json.load(f)
        with open(dst, "w") as f:
            json.dump(tj, f, indent=2, sort_keys=True)
        out["telemetry"]["raw_path"] = dst
        out["telemetry"]["cpu"] = tj.get("cpu")
        out["telemetry"]["units"] = tj.get("units")
        out["telemetry"]["io"] = tj.get("io")

    out["statdump_post"] = statdump("post", qnn)
    out["finished_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

    path = os.path.join(d, f"{qnn}-reference.json")
    with open(path, "w") as f:
        json.dump(out, f, indent=2, sort_keys=True)
    printable = {k: v for k, v in out.items() if k != "binaries"}
    print(json.dumps(printable, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
