#!/usr/bin/env python3.11
"""
TPCH-SSPQ implementation campaign (tpch-sspq-impl-r1-20260803) — headline timing harness.
Campaign-local adaptation of tpch-sspq/harness/headline_run.py (IMPL-SSOT section 8-b).
SSOT.md section 12: single-query-repeat WARM, metadata connection mode
`single-connection-four-statements` (1 uncounted warmup + 3 measured), one direct
campaign connection, no reconnect/prepare between measured statements, full row
consumption into a campaign-owned fixed sink under work/QNN, no terminal rendering.

SUT and client run on CPUs 0-15 (taskset); the sampler runs on CPUs 20-23
(SSOT section 9) and weights by ACTUAL timestamp deltas (SSOT section 15).

Usage: headline_run.py Q01 cubrid|postgresql
"""
import json
import os
import re
import subprocess
import sys
import threading
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import campaign_config as cfg  # noqa: E402

# Every campaign-specific constant comes from the pinned config module
# (IMPL-SSOT section 8-b): CAMPAIGN/RAW_ROOT, CUBRID_HOME and CUBRID_TMP are
# the four values the inherited copy hardcoded to the previous campaign.
CAMPAIGN = cfg.CAMPAIGN
RAW_ROOT = cfg.RAW_ROOT
REPO = cfg.REPO
QUERIES = cfg.QUERIES

CUBRID_HOME = cfg.CUBRID_HOME
CUBRID_DATABASES = cfg.CUBRID_DATABASES
CUBRID_DB = cfg.CUBRID_DB
PG_HOME = cfg.PG_HOME
PG_SOCKDIR = cfg.PG_SOCKDIR
PG_PORT = cfg.PG_PORT
PG_DB = cfg.PG_DB

SUT_CPUS = cfg.SUT_CPUS
COLLECTOR_CPUS = cfg.COLLECTOR_CPUS
SAMPLE_INTERVAL = 0.25
N_MEASURED = cfg.N_MEASURED
TIMEOUT = cfg.TIMEOUT


def read_proc_io(pid):
    out = {}
    try:
        with open(f"/proc/{pid}/io") as f:
            for line in f:
                k, _, v = line.partition(":")
                out[k.strip()] = int(v.strip())
    except OSError:
        return None
    return out


def read_proc_cpu(pid):
    """Return (utime+stime) in clock ticks for the whole process (all threads)."""
    try:
        with open(f"/proc/{pid}/stat") as f:
            parts = f.read().rsplit(")", 1)[1].split()
        # after ')' field 3 is state; utime=field 11, stime=field 12 (1-based from state)
        utime = int(parts[11])
        stime = int(parts[12])
        return utime + stime
    except (OSError, IndexError, ValueError):
        return None


def list_engine_pids(engine):
    if engine == "cubrid":
        pats = [("cub_server", f"cub_server {CUBRID_DB}"), ("cub_master", "cub_master")]
    else:
        pats = [("postmaster", f"{PG_HOME}/bin/postgres -D {PG_SOCKDIR}")]
    pids = {}
    for label, pat in pats:
        r = subprocess.run(["pgrep", "-f", pat], capture_output=True, text=True)
        for p in r.stdout.split():
            pids[int(p)] = label
    if engine == "postgresql":
        for parent in [p for p, l in list(pids.items()) if l == "postmaster"]:
            r = subprocess.run(["pgrep", "-P", str(parent)], capture_output=True, text=True)
            for p in r.stdout.split():
                pids[int(p)] = "pg_child"
    return pids


class Sampler(threading.Thread):
    """Samples engine CPU/IO with real timestamps; pinned to collector CPUs."""

    def __init__(self, engine):
        super().__init__(daemon=True)
        self.engine = engine
        self.samples = []
        self.stop_flag = threading.Event()

    def run(self):
        try:
            os.sched_setaffinity(0, {20, 21, 22, 23})
        except OSError:
            pass
        while not self.stop_flag.is_set():
            pids = list_engine_pids(self.engine)
            snap = {"t": time.monotonic(), "wall": time.time(), "procs": {}}
            for pid, label in pids.items():
                io = read_proc_io(pid)
                cpu = read_proc_cpu(pid)
                if io is None or cpu is None:
                    continue
                snap["procs"][str(pid)] = {
                    "label": label,
                    "cpu_ticks": cpu,
                    "read_bytes": io.get("read_bytes", 0),
                    "rchar": io.get("rchar", 0),
                    "write_bytes": io.get("write_bytes", 0),
                }
            self.samples.append(snap)
            self.stop_flag.wait(SAMPLE_INTERVAL)


def build_block(qnn, engine, workdir, override=None, tag=None):
    """Build the section 12 block: 1 uncounted warmup + N_MEASURED statements.

    `override`/`tag` support a controlled-plan A/B (SSOT section 16: a numeric
    `F_plan` must be anchored on a same-engine native/controlled pair). The
    controlled variant must be measured in the SAME regime as the native block,
    otherwise the card mixes a block-regime denominator with a single-statement
    one. Defaults reproduce the native path byte for byte.

    A PostgreSQL variant is expressed through `PGOPTIONS` in the caller's
    environment, never as an extra `set` statement inside the block: an extra
    statement would emit its own `\\timing` line and corrupt statement-time
    parsing, and would also change the statement count the contract fixes at 4.
    """
    n = int(qnn[1:])
    suffix = "cubrid" if engine == "cubrid" else "pg"
    qfile = override if (override and override != "-") else os.path.join(
        QUERIES, f"q{n}-{suffix}.sql")
    with open(qfile) as f:
        qtext = f.read().rstrip()
    if not qtext.endswith(";"):
        qtext += ";"
    stmts = [qtext] * (1 + N_MEASURED)  # statement 1 = uncounted warmup
    label = engine if not tag or tag == "native" else f"{engine}-{tag}"
    path = os.path.join(workdir, f"q{n}-{label}-block.sql")
    with open(path, "w") as f:
        if engine == "postgresql":
            f.write("\\timing on\n")
        f.write("\n".join(stmts) + "\n")
    return path, qfile


CUBRID_TIME_RE = re.compile(r"\((\d+\.\d+) sec\) Committed")
PG_TIME_RE = re.compile(r"^Time: (\d+\.\d+) ms", re.MULTILINE)


def cubrid_buffer_gauges():
    env = cfg.campaign_env()
    r = subprocess.run([f"{CUBRID_HOME}/bin/cubrid", "statdump", "-c", CUBRID_DB],
                       capture_output=True, text=True, env=env)
    g = {}
    for line in r.stdout.split("\n"):
        m = re.match(r"\s*(Num_data_page_\w+)\s*=\s*(-?\d+)", line)
        if m:
            g[m.group(1)] = int(m.group(2))
    return g


def pg_buffer_counters():
    sql = ("select coalesce(sum(heap_blks_read),0)||' '||coalesce(sum(heap_blks_hit),0) "
           "from pg_statio_user_tables;")
    r = subprocess.run([f"{PG_HOME}/bin/psql", "-h", PG_SOCKDIR, "-p", PG_PORT,
                        "-d", PG_DB, "-Atc", sql], capture_output=True, text=True)
    try:
        rd, hit = r.stdout.strip().split()
        return {"heap_blks_read": int(rd), "heap_blks_hit": int(hit)}
    except ValueError:
        return {}


def run_block(qnn, engine, workdir, sink_path, block_sql):
    if engine == "cubrid":
        env = cfg.campaign_env()
        cmd = ["taskset", "-c", SUT_CPUS,
               f"{CUBRID_HOME}/bin/csql", "-C", "-u", "dba", CUBRID_DB,
               "--no-pager", "-i", block_sql]
    else:
        env = dict(os.environ)
        cmd = ["taskset", "-c", SUT_CPUS,
               f"{PG_HOME}/bin/psql", "-h", PG_SOCKDIR, "-p", PG_PORT, "-d", PG_DB,
               "-A", "-t", "-f", block_sql]
    t0 = time.monotonic()
    with open(sink_path, "w") as sink:
        p = subprocess.run(cmd, stdout=sink, stderr=subprocess.PIPE, text=True,
                           env=env, timeout=TIMEOUT * (1 + N_MEASURED) + 60)
    t1 = time.monotonic()
    return p.returncode, p.stderr, t1 - t0


def parse_times(engine, sink_path, stderr_text):
    with open(sink_path) as f:
        text = f.read()
    if engine == "cubrid":
        vals = [float(x) for x in CUBRID_TIME_RE.findall(text)]
    else:
        vals = [v / 1000.0 for v in (float(x) for x in PG_TIME_RE.findall(text))]
    return vals


def integrate(samples, key):
    """Sum positive deltas of a counter across all pids (cumulative counters)."""
    total = 0
    if len(samples) < 2:
        return 0
    for a, b in zip(samples, samples[1:]):
        for pid, cur in b["procs"].items():
            prev = a["procs"].get(pid)
            if prev is None:
                continue
            d = cur[key] - prev[key]
            if d > 0:
                total += d
    return total


def main():
    if len(sys.argv) not in (3, 4, 5):
        print("usage: headline_run.py QNN cubrid|postgresql [SQL_FILE|-] [VARIANT_TAG]",
              file=sys.stderr)
        print("  SQL_FILE/- plus VARIANT_TAG run a controlled-plan A/B in the section 12",
              file=sys.stderr)
        print("  block regime; '-' keeps the canonical query (PostgreSQL variants come",
              file=sys.stderr)
        print("  from PGOPTIONS). Artifacts are tagged so a variant never overwrites the",
              file=sys.stderr)
        print("  native block.", file=sys.stderr)
        return 2
    qnn, engine = sys.argv[1].upper(), sys.argv[2].lower()
    if engine not in ("cubrid", "postgresql"):
        print("engine must be cubrid or postgresql", file=sys.stderr)
        return 2
    override = sys.argv[3] if len(sys.argv) > 3 else None
    variant = sys.argv[4] if len(sys.argv) > 4 else "native"
    label = engine if variant == "native" else f"{engine}-{variant}"

    workdir = os.path.join(RAW_ROOT, "work", qnn)
    sinkdir = os.path.join(workdir, "sink")
    os.makedirs(sinkdir, exist_ok=True)
    sink_path = os.path.join(sinkdir, f"{qnn}-{label}-headline.out")
    block_sql, qfile = build_block(qnn, engine, workdir, override, variant)

    pre_buf = cubrid_buffer_gauges() if engine == "cubrid" else pg_buffer_counters()
    sampler = Sampler(engine)
    sampler.start()
    time.sleep(1.0)
    rc, err, wall_total = run_block(qnn, engine, workdir, sink_path, block_sql)
    time.sleep(1.0)
    sampler.stop_flag.set()
    sampler.join(timeout=10)
    post_buf = cubrid_buffer_gauges() if engine == "cubrid" else pg_buffer_counters()

    times = parse_times(engine, sink_path, err)
    sink_bytes = os.path.getsize(sink_path)
    sha = subprocess.run(["sha256sum", sink_path], capture_output=True,
                         text=True).stdout.split()[0]

    samples_path = os.path.join(workdir, f"{qnn}-{label}-samples.json")
    with open(samples_path, "w") as f:
        json.dump(sampler.samples, f)

    measured = times[1:1 + N_MEASURED] if len(times) >= 1 + N_MEASURED else []
    result = {
        "campaign_id": CAMPAIGN,
        "impl_ssot_commit": cfg.IMPL_SSOT_COMMIT,
        "impl_ssot_blob": cfg.IMPL_SSOT_BLOB,
        "install_prefix": CUBRID_HOME,
        "cubrid_tmp": cfg.assert_cubrid_tmp(),
        "cubrid_conf_sha256": cfg.assert_conf_sha(),
        "qnn": qnn,
        "engine": engine,
        "variant": variant,
        "pgoptions": os.environ.get("PGOPTIONS", "") if engine == "postgresql" else None,
        "stage": "14.4-cubrid-headline" if engine == "cubrid" else "14.5-postgresql-headline",
        "connection_mode": "single-connection-four-statements",
        "regime": "single-query-repeat WARM",
        "query_file": qfile,
        "block_sql": block_sql,
        "client_exit": rc,
        "client_stderr": err[-2000:],
        "statement_times_all": times,
        "warmup_time_s": times[0] if times else None,
        "measured_times_s": measured,
        "block_wall_s": wall_total,
        "sink": {"path": sink_path, "bytes": sink_bytes, "sha256": sha},
        "buffer_counters": {"pre": pre_buf, "post": post_buf},
        "sampler": {
            "path": samples_path,
            "interval_s": SAMPLE_INTERVAL,
            "n_samples": len(sampler.samples),
            "cpus": COLLECTOR_CPUS,
            "engine_cpu_ticks_delta": integrate(sampler.samples, "cpu_ticks"),
            "engine_read_bytes_delta": integrate(sampler.samples, "read_bytes"),
            "engine_rchar_delta": integrate(sampler.samples, "rchar"),
        },
    }
    if measured:
        s = sorted(measured)
        result["median_s"] = s[len(s) // 2]
        result["mean_s"] = sum(measured) / len(measured)
        var = sum((x - result["mean_s"]) ** 2 for x in measured) / (len(measured) - 1) if len(measured) > 1 else 0.0
        result["stddev_s"] = var ** 0.5

    out_path = os.path.join(workdir, f"{qnn}-{label}-headline.json")
    with open(out_path, "w") as f:
        json.dump(result, f, indent=2, sort_keys=True)
    print(json.dumps({k: v for k, v in result.items() if k != "client_stderr"},
                     indent=2, sort_keys=True))
    return 0 if rc == 0 and len(measured) == N_MEASURED else 1


if __name__ == "__main__":
    sys.exit(main())
