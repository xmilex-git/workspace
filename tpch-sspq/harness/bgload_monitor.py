#!/usr/bin/env python3.11
"""
TPCH-SSPQ FK campaign (tpch-sspq-fk-r1-20260730) — external SUT-set load monitor.

SSOT section 9 requires: "If external CPU on the SUT set is above 1.5 core-seconds
per second before a run, wait. If it crosses the threshold during a run, mark
INVALID_BACKGROUND_LOAD." The preflight harness only samples the *pre-run* value.
This monitor supplies the *during-run* half of that gate, which Q03 needs because the
measurement host is a podman container: /proc/stat is host-wide, so CPU burned by
processes outside the container is real contention on CPUs 0-15 that is invisible to
`ps`/`pgrep` inside it.

external = (host-wide busy on SUT CPUs) - (campaign-attributable process CPU)

Campaign processes (cub_master/cub_server/csql, postmaster tree/psql) are all pinned
to the SUT set by taskset or by inherited affinity, so subtracting their whole-process
CPU from the host-wide SUT-set busy time leaves exactly the non-campaign load. The
monitor itself is pinned to the collector CPUs 20-23 (section 9) so it never competes
with the measurement.

Usage:
  bgload_monitor.py OUT_JSON [INTERVAL_S] [THRESHOLD]     # runs until SIGTERM/SIGINT
"""
import json
import os
import signal
import subprocess
import sys
import time

SUT_CPUS = set(range(0, 16))
COLLECTOR_CPUS = {20, 21, 22, 23}
CUBRID_DB = "tpch_sf10_q1"
PG_HOME = "/home/cubrid/pg/pg20devel-5713b437"
PG_SOCKDIR = "/home/cubrid/pg/pgdata-tpch-sspq"
TICKS = os.sysconf("SC_CLK_TCK")

CAMPAIGN_PATTERNS = [
    f"cub_server {CUBRID_DB}",
    "cub_master",
    f"csql -C -u dba {CUBRID_DB}",
    f"{PG_HOME}/bin/postgres -D {PG_SOCKDIR}",
    f"{PG_HOME}/bin/psql",
]

_stop = False


def _handle(signum, frame):
    global _stop
    _stop = True


def cpu_snapshot():
    """Per-CPU (busy_excluded, total) ticks for the SUT set."""
    out = {}
    with open("/proc/stat") as f:
        for line in f:
            if line.startswith("cpu") and len(line) > 3 and line[3].isdigit():
                p = line.split()
                n = int(p[0][3:])
                if n in SUT_CPUS:
                    v = [int(x) for x in p[1:]]
                    # idle + iowait are "not busy"; everything else (user, nice,
                    # system, irq, softirq, steal, guest) counts as busy.
                    out[n] = (v[3] + v[4], sum(v))
    return out


def campaign_pids():
    """Return (roots, leaves).

    roots reap children (cub_master, postmaster), so their cutime/cstime carries the
    CPU of every already-exited backend or parallel worker. leaves are counted by
    their own utime/stime only.
    """
    roots, leaves = {}, {}
    for pat in CAMPAIGN_PATTERNS:
        r = subprocess.run(["pgrep", "-f", pat], capture_output=True, text=True)
        for p in r.stdout.split():
            pid = int(p)
            if pat == "cub_master" or pat.endswith(PG_SOCKDIR):
                roots[pid] = pat
            else:
                leaves[pid] = pat
    for parent in list(roots):
        r = subprocess.run(["pgrep", "-P", str(parent)], capture_output=True, text=True)
        for p in r.stdout.split():
            pid = int(p)
            if pid not in roots:
                leaves.setdefault(pid, "child")
    return roots, leaves


def proc_cpu(pid, with_children=False):
    """utime+stime, plus cutime+cstime of reaped children when with_children."""
    try:
        with open(f"/proc/{pid}/stat") as f:
            parts = f.read().rsplit(")", 1)[1].split()
        total = int(parts[11]) + int(parts[12])
        if with_children:
            total += int(parts[13]) + int(parts[14])
        return total
    except (OSError, IndexError, ValueError):
        return None


def campaign_total():
    """Absolute campaign CPU in ticks — monotone and complete.

    A live child's CPU sits in its own utime/stime; the instant it is reaped that CPU
    moves into its parent's cutime/cstime. Summing roots *with* children plus live
    leaves *without* children therefore never double counts and never loses the CPU of
    a short-lived per-statement backend or parallel worker. Because the sum is
    absolute rather than incremental, CPU burned between a process's fork and its
    first appearance in process discovery is also captured instead of leaking into the
    external residual and faking a neighbour-load spike.
    """
    roots, leaves = campaign_pids()
    total = 0
    for pid in roots:
        v = proc_cpu(pid, with_children=True)
        if v is not None:
            total += v
    for pid in leaves:
        v = proc_cpu(pid)
        if v is not None:
            total += v
    return total, len(roots) + len(leaves)


def main():
    if len(sys.argv) < 2:
        print("usage: bgload_monitor.py OUT_JSON [INTERVAL_S] [THRESHOLD]",
              file=sys.stderr)
        return 2
    out_path = sys.argv[1]
    interval = float(sys.argv[2]) if len(sys.argv) > 2 else 0.25
    threshold = float(sys.argv[3]) if len(sys.argv) > 3 else 1.5

    try:
        os.sched_setaffinity(0, COLLECTOR_CPUS)
    except OSError:
        pass
    signal.signal(signal.SIGTERM, _handle)
    signal.signal(signal.SIGINT, _handle)

    samples = []
    prev_cpu = cpu_snapshot()
    prev_camp, _ = campaign_total()
    prev_t = time.monotonic()

    while not _stop:
        time.sleep(interval)
        now = time.monotonic()
        dt = now - prev_t
        cur_cpu = cpu_snapshot()
        cur_camp, n_procs = campaign_total()

        host = sum((cur_cpu[c][1] - prev_cpu[c][1]) - (cur_cpu[c][0] - prev_cpu[c][0])
                   for c in cur_cpu if c in prev_cpu) / TICKS / dt
        camp = max(0.0, (cur_camp - prev_camp) / TICKS / dt)
        samples.append({
            "t": round(now, 6),
            "wall": time.time(),
            "dt_s": round(dt, 6),
            "host_busy_sut": round(host, 4),
            "campaign_cpu": round(camp, 4),
            "campaign_procs": n_procs,
            "external": round(max(0.0, host - camp), 4),
        })
        prev_cpu, prev_camp, prev_t = cur_cpu, cur_camp, now

    ext = [s["external"] for s in samples]
    n = len(ext)
    over = [s for s in samples if s["external"] > threshold]
    # contiguous runs of over-threshold samples, with their durations
    windows = []
    run = None
    for s in samples:
        if s["external"] > threshold:
            if run is None:
                run = {"start_wall": s["wall"], "dur_s": 0.0, "max": s["external"], "n": 0}
            run["dur_s"] += s["dt_s"]
            run["n"] += 1
            run["max"] = max(run["max"], s["external"])
        elif run is not None:
            windows.append({k: (round(v, 4) if isinstance(v, float) else v)
                            for k, v in run.items()})
            run = None
    if run is not None:
        windows.append({k: (round(v, 4) if isinstance(v, float) else v)
                        for k, v in run.items()})

    summary = {
        "campaign_id": "tpch-sspq-fk-r1-20260730",
        "artifact": "external SUT-set background load during a measurement block",
        "sut_cpus": "0-15",
        "collector_cpus": "20-23",
        "threshold_core_s_per_s": threshold,
        "definition": ("external = host-wide busy on cpu0-15 minus absolute campaign "
                       "CPU, where campaign CPU = roots (cub_master, postmaster) "
                       "utime+stime+cutime+cstime plus live leaves (cub_server, csql, "
                       "psql, postmaster children) utime+stime; reaped per-statement "
                       "backends and parallel workers are therefore fully attributed"),
        "interval_nominal_s": interval,
        "n_samples": n,
        "duration_s": round(sum(s["dt_s"] for s in samples), 4),
        "external_mean": round(sum(ext) / n, 4) if n else None,
        "external_max": round(max(ext), 4) if n else None,
        "external_p95": round(sorted(ext)[int(0.95 * (n - 1))], 4) if n else None,
        "n_over_threshold": len(over),
        "over_threshold_windows": windows,
        "verdict": ("CLEAN" if not over else "INVALID_BACKGROUND_LOAD"),
        "samples": samples,
    }
    with open(out_path, "w") as f:
        json.dump(summary, f, indent=2, sort_keys=True)
    print(json.dumps({k: v for k, v in summary.items() if k != "samples"},
                     indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
