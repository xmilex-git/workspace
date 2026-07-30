#!/usr/bin/env python3.11
"""
TPCH-SSPQ FK campaign (tpch-sspq-fk-r1-20260730) — SSOT section 9 pre-run load gate.

"If external CPU on the SUT set is above 1.5 core-seconds per second before a run,
wait." This blocks until the external (non-campaign) load on CPUs 0-15 has stayed at or
below the threshold for a required number of consecutive samples, then exits 0. It
exits 3 if the set never quiesces within the deadline, so a caller never starts a
measurement on a contended host.

External load is computed with the same accounting as harness/bgload_monitor.py:
absolute campaign CPU (roots with cutime/cstime so reaped per-statement backends and
parallel workers are attributed) subtracted from host-wide busy time on the SUT set.
The measurement host is a podman container whose /proc/stat is host-wide, so this
residual is exactly the neighbour load that is invisible to ps/pgrep inside it.

Usage: wait_quiet.py [THRESHOLD] [NEED_CONSECUTIVE] [INTERVAL_S] [MAX_WAIT_S]
"""
import os
import subprocess
import sys
import time

SUT_CPUS = set(range(0, 16))
COLLECTOR_CPUS = {20, 21, 22, 23}
TICKS = os.sysconf("SC_CLK_TCK")
CUBRID_DB = "tpch_sf10_q1"
PG_HOME = "/home/cubrid/pg/pg20devel-5713b437"
PG_SOCKDIR = "/home/cubrid/pg/pgdata-tpch-sspq"
PATTERNS = [
    f"cub_server {CUBRID_DB}",
    "cub_master",
    f"csql -C -u dba {CUBRID_DB}",
    f"{PG_HOME}/bin/postgres -D {PG_SOCKDIR}",
    f"{PG_HOME}/bin/psql",
]


def cpu_snapshot():
    out = {}
    with open("/proc/stat") as f:
        for line in f:
            if line.startswith("cpu") and len(line) > 3 and line[3].isdigit():
                p = line.split()
                n = int(p[0][3:])
                if n in SUT_CPUS:
                    v = [int(x) for x in p[1:]]
                    out[n] = (v[3] + v[4], sum(v))
    return out


def proc_cpu(pid, with_children=False):
    try:
        with open(f"/proc/{pid}/stat") as f:
            parts = f.read().rsplit(")", 1)[1].split()
        total = int(parts[11]) + int(parts[12])
        if with_children:
            total += int(parts[13]) + int(parts[14])
        return total
    except (OSError, IndexError, ValueError):
        return 0


def campaign_total():
    roots, leaves = set(), set()
    for pat in PATTERNS:
        r = subprocess.run(["pgrep", "-f", pat], capture_output=True, text=True)
        for x in r.stdout.split():
            (roots if (pat == "cub_master" or pat.endswith(PG_SOCKDIR)) else leaves).add(int(x))
    for parent in list(roots):
        r = subprocess.run(["pgrep", "-P", str(parent)], capture_output=True, text=True)
        leaves |= {int(x) for x in r.stdout.split()} - roots
    return (sum(proc_cpu(p, True) for p in roots) + sum(proc_cpu(p) for p in leaves))


def main():
    threshold = float(sys.argv[1]) if len(sys.argv) > 1 else 1.5
    need = int(sys.argv[2]) if len(sys.argv) > 2 else 6
    interval = float(sys.argv[3]) if len(sys.argv) > 3 else 2.0
    max_wait = float(sys.argv[4]) if len(sys.argv) > 4 else 1800.0

    try:
        os.sched_setaffinity(0, COLLECTOR_CPUS)
    except OSError:
        pass

    started = time.time()
    quiet = 0
    prev_cpu, prev_camp, prev_t = cpu_snapshot(), campaign_total(), time.monotonic()
    while True:
        time.sleep(interval)
        now = time.monotonic()
        dt = now - prev_t
        cur_cpu, cur_camp = cpu_snapshot(), campaign_total()
        host = sum((cur_cpu[c][1] - prev_cpu[c][1]) - (cur_cpu[c][0] - prev_cpu[c][0])
                   for c in cur_cpu if c in prev_cpu) / TICKS / dt
        camp = max(0.0, (cur_camp - prev_camp) / TICKS / dt)
        ext = max(0.0, host - camp)
        prev_cpu, prev_camp, prev_t = cur_cpu, cur_camp, now
        quiet = quiet + 1 if ext <= threshold else 0
        print(f"  gate external={ext:.3f} quiet_streak={quiet}/{need}", flush=True)
        if quiet >= need:
            print("  gate PASS — starting block", flush=True)
            return 0
        if time.time() - started > max_wait:
            print(f"  gate TIMEOUT after {max_wait}s — SUT set never quiesced", flush=True)
            return 3


if __name__ == "__main__":
    sys.exit(main())
