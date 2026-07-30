#!/usr/bin/env python3.11
"""
TPCH-SSPQ FK campaign (tpch-sspq-fk-r1-20260730) — stage 14.7 execution telemetry.
Non-headline diagnostic run.

SSOT section 15: records executor_cpu / auxiliary_query_cpu / total_query_cpu
separately, planned + launched workers, maximum simultaneous active units, and
time-weighted active units (TWU) computed from ACTUAL sample timestamp deltas
(never a nominal interval), plus the serial tail.

Per-TID sampling so pooled CUBRID threads and PG parallel workers are attributed
explicitly rather than inferred from settings. Sampler pinned to CPUs 20-23.

Usage: telemetry_run.py Q01 cubrid|postgresql
"""
import json
import os
import re
import subprocess
import sys
import threading
import time

os.environ["CUBRID_TMP"] = "/tmp"

CAMPAIGN = "tpch-sspq-fk-r1-20260730"
RAW_ROOT = f"/data/tpch-sspq/{CAMPAIGN}"
REPO = "/home/cubrid/dev/workspace/tpch-sspq"
QUERIES = os.path.join(REPO, "queries")

CUBRID_HOME = "/home/cubrid/release/CUBRID-tpch-sspq-fk-r1-607f1ee9"
CUBRID_DATABASES = "/home/cubrid/dev/workspace/.git_ignored_dir/tpch-sspq/cubrid-databases"
CUBRID_DB = "tpch_sf10_q1"
PG_HOME = "/home/cubrid/pg/pg20devel-5713b437"
PG_SOCKDIR = "/home/cubrid/pg/pgdata-tpch-sspq"
PG_PORT = "5442"
PG_DB = "tpch_sspq"

SUT_CPUS = "0-15"
# Nominal sampler period. Sub-second queries need a finer period so the TWU window
# has enough intervals; TWU itself is always weighted by ACTUAL timestamp deltas
# (SSOT section 15), never by this nominal value.
INTERVAL = float(os.environ.get("TPCH_SSPQ_TELEMETRY_INTERVAL_S", "0.1"))
TICKS = os.sysconf("SC_CLK_TCK")

# CUBRID cub_server maintenance/background threads -> auxiliary_query_cpu.
CUBRID_BG = re.compile(
    r"^(pgbuf-|dwb-|log-|vacuum-|deadlock-|session-|pl-monitor|cub_server$|"
    r"thread_|css_|fileio|checkpoint|deallocate|page-flush|flush-control)")


def tids(pid):
    try:
        return os.listdir(f"/proc/{pid}/task")
    except OSError:
        return []


def tid_cpu(pid, tid):
    try:
        with open(f"/proc/{pid}/task/{tid}/stat") as f:
            parts = f.read().rsplit(")", 1)[1].split()
        return int(parts[11]) + int(parts[12])
    except (OSError, IndexError, ValueError):
        return None


def tid_comm(pid, tid):
    try:
        with open(f"/proc/{pid}/task/{tid}/comm") as f:
            return f.read().strip()
    except OSError:
        return "?"


def proc_io(pid):
    out = {}
    try:
        with open(f"/proc/{pid}/io") as f:
            for line in f:
                k, _, v = line.partition(":")
                out[k.strip()] = int(v.strip())
    except OSError:
        pass
    return out


def diskstats():
    out = {}
    try:
        with open("/proc/diskstats") as f:
            for line in f:
                p = line.split()
                if len(p) >= 14:
                    out[p[2]] = {"reads": int(p[3]), "sectors_read": int(p[5]),
                                 "writes": int(p[7]), "sectors_written": int(p[9])}
    except OSError:
        pass
    return out


def engine_procs(engine, client_pid=None):
    """Map pid -> role for the engine under test."""
    procs = {}
    if engine == "cubrid":
        r = subprocess.run(["pgrep", "-f", f"cub_server {CUBRID_DB}"],
                           capture_output=True, text=True)
        for p in r.stdout.split():
            procs[int(p)] = "cub_server"
        r = subprocess.run(["pgrep", "-x", "csql"], capture_output=True, text=True)
        for p in r.stdout.split():
            procs[int(p)] = "client_csql"
    else:
        r = subprocess.run(["pgrep", "-f", f"{PG_HOME}/bin/postgres -D {PG_SOCKDIR}"],
                           capture_output=True, text=True)
        for p in r.stdout.split():
            pm = int(p)
            procs[pm] = "postmaster"
            rc = subprocess.run(["pgrep", "-P", str(pm)], capture_output=True, text=True)
            for c in rc.stdout.split():
                cp = int(c)
                try:
                    cmd = open(f"/proc/{cp}/cmdline").read().replace("\x00", " ")
                except OSError:
                    continue
                if "parallel worker" in cmd:
                    procs[cp] = "pg_parallel_worker"
                elif "io worker" in cmd:
                    procs[cp] = "pg_io_worker"
                elif f"{PG_DB}" in cmd and "postgres:" in cmd:
                    procs[cp] = "pg_backend"
                else:
                    procs[cp] = "pg_background"
        r = subprocess.run(["pgrep", "-x", "psql"], capture_output=True, text=True)
        for p in r.stdout.split():
            procs[int(p)] = "client_psql"
    return procs


class Sampler(threading.Thread):
    """Per-TID CPU/IO sampler, pinned to the collector CPUs.

    Process-set discovery (`engine_procs`) spawns pgrep and walks /proc, which is
    far more expensive than the per-TID reads themselves. Re-running it on every
    sample perturbed sub-second queries measurably (observed +8..16% wall on a
    0.35 s query at a 20 ms period), so discovery is refreshed at most every
    PROC_REFRESH_S while CPU/IO is still sampled every period. PG parallel workers
    live for seconds, so a 0.1 s discovery lag still attributes them.
    """

    def __init__(self, engine, proc_refresh_s=0.1):
        super().__init__(daemon=True)
        self.engine = engine
        self.proc_refresh_s = proc_refresh_s
        self.samples = []
        self.stop_flag = threading.Event()

    def run(self):
        try:
            os.sched_setaffinity(0, {20, 21, 22, 23})
        except OSError:
            pass
        procs = {}
        last_refresh = -1.0
        while not self.stop_flag.is_set():
            now = time.monotonic()
            if now - last_refresh >= self.proc_refresh_s:
                procs = engine_procs(self.engine)
                last_refresh = now
            snap = {"t": time.monotonic(), "wall": time.time(), "tids": {}, "io": {}}
            for pid, role in procs.items():
                for tid in tids(pid):
                    c = tid_cpu(pid, tid)
                    if c is None:
                        continue
                    snap["tids"][f"{pid}/{tid}"] = {
                        "role": role, "comm": tid_comm(pid, tid), "cpu": c}
                snap["io"][str(pid)] = {"role": role, **proc_io(pid)}
            snap["disk"] = diskstats()
            self.samples.append(snap)
            self.stop_flag.wait(INTERVAL)


def classify(role, comm):
    if role in ("client_csql", "client_psql"):
        return "auxiliary"
    if role == "pg_io_worker":
        return "auxiliary"
    if role in ("postmaster", "pg_background"):
        return "auxiliary"
    if role in ("pg_backend", "pg_parallel_worker"):
        return "executor"
    if role == "cub_server":
        return "auxiliary" if CUBRID_BG.match(comm) else "executor"
    return "auxiliary"


def analyse(samples):
    """CPU decomposition + TWU using real timestamp deltas."""
    exec_ticks = aux_ticks = 0
    per_bucket = {}
    intervals = []
    for a, b in zip(samples, samples[1:]):
        dt = b["t"] - a["t"]
        if dt <= 0:
            continue
        d_exec = d_aux = 0
        for key, cur in b["tids"].items():
            prev = a["tids"].get(key)
            if prev is None:
                continue
            d = cur["cpu"] - prev["cpu"]
            if d <= 0:
                continue
            kind = classify(cur["role"], cur["comm"])
            bucket = f'{kind}:{cur["role"]}:{cur["comm"]}'
            per_bucket[bucket] = per_bucket.get(bucket, 0) + d
            if kind == "executor":
                d_exec += d
            else:
                d_aux += d
        exec_ticks += d_exec
        aux_ticks += d_aux
        total_units = (d_exec + d_aux) / TICKS / dt
        intervals.append({"t": b["t"], "dt": dt, "units": total_units,
                          "exec_units": d_exec / TICKS / dt})
    return exec_ticks, aux_ticks, per_bucket, intervals


def twu(intervals, threshold=0.5):
    """Time-weighted active units over the busy window; actual dt weighting."""
    busy = [i for i in intervals if i["units"] >= threshold]
    if not busy:
        return None, None, None, None
    tot_dt = sum(i["dt"] for i in busy)
    weighted = sum(i["units"] * i["dt"] for i in busy) / tot_dt
    peak = max(i["units"] for i in busy)
    # serial tail: trailing contiguous portion of the busy window with < 1.5 units
    tail = 0.0
    for i in reversed(busy):
        if i["units"] < 1.5:
            tail += i["dt"]
        else:
            break
    return weighted, peak, tot_dt, tail


def io_delta(samples, role_filter=None):
    tot = {}
    for a, b in zip(samples, samples[1:]):
        for pid, cur in b["io"].items():
            prev = a["io"].get(pid)
            if prev is None:
                continue
            if role_filter and cur.get("role") != role_filter:
                continue
            for k in ("read_bytes", "write_bytes", "rchar", "wchar", "syscr"):
                d = cur.get(k, 0) - prev.get(k, 0)
                if d > 0:
                    tot[k] = tot.get(k, 0) + d
    return tot


def disk_delta(samples):
    if len(samples) < 2:
        return {}
    first, last = samples[0]["disk"], samples[-1]["disk"]
    out = {}
    for dev, v in last.items():
        p = first.get(dev)
        if not p:
            continue
        dr = v["sectors_read"] - p["sectors_read"]
        dw = v["sectors_written"] - p["sectors_written"]
        if dr or dw:
            out[dev] = {"sectors_read": dr, "read_MiB": round(dr * 512 / 1048576, 2),
                        "sectors_written": dw, "write_MiB": round(dw * 512 / 1048576, 2)}
    return out


def numa(pid):
    r = subprocess.run(["numastat", "-p", str(pid)], capture_output=True, text=True)
    return r.stdout


def main():
    if len(sys.argv) not in (3, 4, 5):
        print("usage: telemetry_run.py QNN cubrid|postgresql [SQL_FILE] [VARIANT_TAG]",
              file=sys.stderr)
        print("  SQL_FILE overrides the canonical query file for a controlled-plan A/B",
              file=sys.stderr)
        return 2
    qnn, engine = sys.argv[1].upper(), sys.argv[2].lower()
    override = sys.argv[3] if len(sys.argv) > 3 else None
    variant = sys.argv[4] if len(sys.argv) > 4 else ("native" if not override else "variant")
    n = int(qnn[1:])
    workdir = os.path.join(RAW_ROOT, "work", qnn)
    os.makedirs(workdir, exist_ok=True)

    suffix = "cubrid" if engine == "cubrid" else "pg"
    qfile = override or os.path.join(QUERIES, f"q{n}-{suffix}.sql")
    tag = engine if variant == "native" else f"{engine}-{variant}"
    sql_path = os.path.join(workdir, f"q{n}-{tag}-telemetry.sql")
    with open(qfile) as f:
        q = f.read().rstrip()
    if not q.endswith(";"):
        q += ";"
    with open(sql_path, "w") as f:
        f.write(q + "\n")
    sink = os.path.join(workdir, "sink", f"{qnn}-{tag}-telemetry.out")
    os.makedirs(os.path.dirname(sink), exist_ok=True)

    srv_pid = None
    if engine == "cubrid":
        r = subprocess.run(["pgrep", "-f", f"cub_server {CUBRID_DB}"],
                           capture_output=True, text=True)
        srv_pid = int(r.stdout.split()[0])
    else:
        r = subprocess.run(["pgrep", "-f", f"{PG_HOME}/bin/postgres -D {PG_SOCKDIR}"],
                           capture_output=True, text=True)
        srv_pid = int(r.stdout.split()[0])
    numa_pre = numa(srv_pid)

    if engine == "cubrid":
        env = dict(os.environ)
        env["CUBRID"] = CUBRID_HOME
        env["CUBRID_DATABASES"] = CUBRID_DATABASES
        cmd = ["taskset", "-c", SUT_CPUS, f"{CUBRID_HOME}/bin/csql", "-C", "-u", "dba",
               CUBRID_DB, "--no-pager", "-i", sql_path]
    else:
        env = dict(os.environ)
        cmd = ["taskset", "-c", SUT_CPUS, f"{PG_HOME}/bin/psql", "-h", PG_SOCKDIR,
               "-p", PG_PORT, "-d", PG_DB, "-A", "-t", "-f", sql_path]

    sampler = Sampler(engine)
    sampler.start()
    time.sleep(1.0)
    t0 = time.monotonic()
    with open(sink, "w") as sf:
        p = subprocess.run(cmd, stdout=sf, stderr=subprocess.PIPE, text=True, env=env,
                           timeout=900)
    t1 = time.monotonic()
    time.sleep(1.0)
    sampler.stop_flag.set()
    sampler.join(timeout=10)
    numa_post = numa(srv_pid)

    exec_ticks, aux_ticks, per_bucket, intervals = analyse(sampler.samples)
    w, peak, busy_dt, tail = twu(intervals)
    executor_cpu = exec_ticks / TICKS
    auxiliary_cpu = aux_ticks / TICKS

    result = {
        "campaign_id": CAMPAIGN, "qnn": qnn, "engine": engine,
        "variant": variant, "query_file": qfile,
        "stage": "14.7-execution-telemetry", "headline": False,
        "client_exit": p.returncode, "client_stderr": p.stderr[-1500:],
        "client_wall_s": t1 - t0,
        "sample_interval_nominal_s": INTERVAL,
        "n_samples": len(sampler.samples),
        "cpu": {
            "executor_cpu_core_s": round(executor_cpu, 3),
            "auxiliary_query_cpu_core_s": round(auxiliary_cpu, 3),
            "total_query_cpu_core_s": round(executor_cpu + auxiliary_cpu, 3),
            "per_bucket_core_s": {k: round(v / TICKS, 3)
                                  for k, v in sorted(per_bucket.items(),
                                                     key=lambda x: -x[1])},
        },
        "units": {
            "time_weighted_active_units": round(w, 4) if w else None,
            "max_simultaneous_active_units": round(peak, 4) if peak else None,
            "busy_window_s": round(busy_dt, 3) if busy_dt else None,
            "serial_tail_s": round(tail, 3) if tail is not None else None,
            "weighting": "actual sample timestamp deltas (not nominal interval)",
        },
        "io": {"engine_and_client": io_delta(sampler.samples),
               "device": disk_delta(sampler.samples)},
        "numa": {"pre": numa_pre, "post": numa_post},
    }
    ipath = os.path.join(workdir, f"{qnn}-{tag}-telemetry-intervals.json")
    with open(ipath, "w") as f:
        json.dump(intervals, f)
    result["intervals_path"] = ipath
    spath = os.path.join(workdir, f"{qnn}-{tag}-telemetry-samples.json")
    with open(spath, "w") as f:
        json.dump(sampler.samples, f)
    result["samples_path"] = spath

    out = os.path.join(workdir, f"{qnn}-{tag}-telemetry.json")
    with open(out, "w") as f:
        json.dump(result, f, indent=2, sort_keys=True)
    printable = {k: v for k, v in result.items() if k not in ("numa", "client_stderr")}
    print(json.dumps(printable, indent=2, sort_keys=True))
    return 0 if p.returncode == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
