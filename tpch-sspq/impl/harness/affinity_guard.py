#!/usr/bin/env python3.11
"""TPCH-SSPQ implementation campaign (tpch-sspq-impl-r1-20260803) — all-TID affinity guard.
Campaign-local adaptation of tpch-sspq/harness/affinity_guard.py (IMPL-SSOT section 8-b).

SSOT section 9: "verify every related TID and NUMA page distribution before and
after runs. If a pooled CUBRID thread or a PG worker/io worker inherits a different
affinity, mark the run invalid, reapply affinity and rerun." Section 24 lists the
same defect as a prior campaign failure: "new pooled threads escaped cpuset ->
all-TID pre/post validation and invalidation".

Why a continuous guard and not a pre/post pair. Q22 caught the defect for the first
time in the campaign, and it is not observable by a pre/post pair alone: cub_server
creates pooled `transaction` threads ON DEMAND during a block, and CUBRID rebinds
them itself in

    src/base/resources.cpp:174-188  clearaffinity()
        pthread_setaffinity_np (pthread_self (), ..., ctx.affinity.bitmap)
    src/base/resources.cpp:190-192  context &effective ()
        /* This function must be called first in the main thread's entry point */
        static context ctx = ...

`effective()` caches the affinity mask ONCE, in a function-local static, at server
start. Any `taskset` applied to the running server afterwards therefore does NOT
update that cached bitmap, and every pooled thread created later is bound back to
the STALE mask, landing outside the campaign cpuset. On this host that produced
`transaction` TIDs pinned to CPUs 24-31 while the contract requires 0-15. A thread
that is created and exits between a pre-check and a post-check is invisible to both;
only sampling for the whole run can prove a block was clean.

Modes
  --guard OUT_JSON [INTERVAL_S]   sample until SIGTERM, then write the verdict
  --check                         one-shot; exit 0 if clean, 3 if any TID is off
  --reapply                       taskset every engine TID back into the SUT set,
                                  then re-check (exit 0 only if clean afterwards)

Verdict is CLEAN only when NO engine TID was ever observed outside the SUT set.
The offending TID's own CPU delta while off-cpuset is recorded, so a violation can
be quantified instead of merely asserted.
"""
import json
import os
import signal
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import campaign_config as cfg  # noqa: E402

SUT = cfg.SUT_CPU_SET
CUBRID_HOME = cfg.CUBRID_HOME
PG_BIN = f"{cfg.PG_HOME}/bin/postgres"
PGDATA = cfg.PG_SOCKDIR
CUBRID_DB = cfg.CUBRID_DB
TCK = os.sysconf("SC_CLK_TCK")

_stop = False


def _on_term(signum, frame):
    global _stop
    _stop = True


def pgrep(pat):
    r = subprocess.run(["pgrep", "-f", pat], capture_output=True, text=True)
    return [int(p) for p in r.stdout.split()]


def engine_groups():
    g = {"cub_master": pgrep("cub_master"),
         "cub_server": pgrep(f"cub_server {CUBRID_DB}")}
    pm = pgrep(f"{PG_BIN} -D {PGDATA}")
    g["postmaster"] = pm
    kids = []
    for p in pm:
        kids += [int(c) for c in
                 subprocess.run(["pgrep", "-P", str(p)], capture_output=True,
                                text=True).stdout.split()]
    g["pg_children"] = kids
    return g


def tid_cpu_ticks(pid, tid):
    try:
        with open(f"/proc/{pid}/task/{tid}/stat") as f:
            p = f.read().rsplit(")", 1)[1].split()
        return int(p[11]) + int(p[12])          # utime + stime
    except (OSError, IndexError):
        return None


def comm(pid, tid):
    try:
        with open(f"/proc/{pid}/task/{tid}/comm") as f:
            return f.read().strip()
    except OSError:
        return "?"


def scan():
    """Return {(group,pid,tid): (off_cpuset, cpus, comm, cpu_ticks)} plus counts."""
    out = {}
    total = 0
    off = 0
    for label, pids in engine_groups().items():
        for pid in pids:
            try:
                tids = os.listdir(f"/proc/{pid}/task")
            except OSError:
                continue
            for tid in tids:
                total += 1
                try:
                    mask = os.sched_getaffinity(int(tid))
                except OSError:
                    continue
                is_off = not mask <= SUT
                if is_off:
                    off += 1
                out[(label, pid, int(tid))] = (
                    is_off, sorted(mask), comm(pid, int(tid)),
                    tid_cpu_ticks(pid, int(tid)))
    return out, total, off


def reapply():
    """Bind every engine TID back into the SUT set (campaign-owned processes only)."""
    fixed = []
    st, _, _ = scan()
    for (label, pid, tid), (is_off, mask, cm, _) in sorted(st.items()):
        if not is_off:
            continue
        r = subprocess.run(["taskset", "-p", "-c", cfg.SUT_CPUS, str(tid)],
                           capture_output=True, text=True)
        fixed.append({"group": label, "pid": pid, "tid": tid, "comm": cm,
                      "was_cpus": mask, "rc": r.returncode,
                      "stderr": r.stderr.strip()[:200]})
    return fixed


def main():
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    mode = sys.argv[1]

    if mode == "--check":
        st, total, off = scan()
        for (label, pid, tid), (is_off, mask, cm, _) in sorted(st.items()):
            if is_off:
                print(f"  OFF-CPUSET {label} pid={pid} tid={tid} comm={cm!r} cpus={mask[:8]}")
        print(f"  all-TID affinity: tids={total} off_cpuset={off} -> "
              f"{'PASS' if off == 0 else 'FAIL'}")
        return 0 if off == 0 else 3

    if mode == "--reapply":
        fixed = reapply()
        for f in fixed:
            print(f"  reapplied {f['group']} tid={f['tid']} comm={f['comm']!r} "
                  f"was={f['was_cpus'][:8]} rc={f['rc']} {f['stderr']}")
        if not fixed:
            print("  nothing to reapply (no off-cpuset TID)")
        st, total, off = scan()
        print(f"  after reapply: tids={total} off_cpuset={off} -> "
              f"{'PASS' if off == 0 else 'FAIL'}")
        return 0 if off == 0 else 3

    if mode != "--guard":
        print(f"unknown mode {mode!r}", file=sys.stderr)
        return 2

    out_path = sys.argv[2]
    interval = float(sys.argv[3]) if len(sys.argv) > 3 else 0.1
    signal.signal(signal.SIGTERM, _on_term)
    signal.signal(signal.SIGINT, _on_term)

    t0 = time.time()
    samples = 0
    seen = {}          # tid -> record
    first_state, tot0, off0 = scan()
    for key, (is_off, mask, cm, ticks) in first_state.items():
        if is_off:
            seen[key] = {"group": key[0], "pid": key[1], "tid": key[2], "comm": cm,
                         "cpus": mask, "first_seen_s": 0.0,
                         "first_seen_iso": time.strftime("%Y-%m-%dT%H:%M:%S"),
                         "cpu_ticks_first": ticks, "cpu_ticks_last": ticks,
                         "present_at_start": True}
    while not _stop:
        time.sleep(interval)
        samples += 1
        st, tot, off = scan()
        for key, (is_off, mask, cm, ticks) in st.items():
            if not is_off:
                continue
            if key in seen:
                seen[key]["cpu_ticks_last"] = ticks
                seen[key]["cpus"] = mask
            else:
                seen[key] = {"group": key[0], "pid": key[1], "tid": key[2],
                             "comm": cm, "cpus": mask,
                             "first_seen_s": round(time.time() - t0, 3),
                             "first_seen_iso": time.strftime("%Y-%m-%dT%H:%M:%S"),
                             "cpu_ticks_first": ticks, "cpu_ticks_last": ticks,
                             "present_at_start": False}
    st, tot, off = scan()
    for key, (is_off, mask, cm, ticks) in st.items():
        if is_off and key in seen:
            seen[key]["cpu_ticks_last"] = ticks

    viol = list(seen.values())
    for v in viol:
        a, b = v.get("cpu_ticks_first"), v.get("cpu_ticks_last")
        v["cpu_core_s_while_off_cpuset"] = (
            round((b - a) / TCK, 4) if (a is not None and b is not None) else None)
    result = {
        "campaign_id": cfg.CAMPAIGN,
        "impl_ssot_commit": cfg.IMPL_SSOT_COMMIT,
        "stage": "all-TID affinity guard (IMPL-SSOT section 3-a)",
        "sut_cpus": sorted(SUT),
        "interval_s": interval,
        "samples": samples,
        "duration_s": round(time.time() - t0, 3),
        "engine_tids_first_scan": tot0,
        "engine_tids_last_scan": tot,
        "off_cpuset_tids_last_scan": off,
        "violations": sorted(viol, key=lambda v: v["first_seen_s"]),
        "verdict": "CLEAN" if not viol else "OFF_CPUSET",
    }
    with open(out_path, "w") as f:
        json.dump(result, f, indent=2, sort_keys=True)
    print(json.dumps({k: v for k, v in result.items() if k != "violations"},
                     indent=2, sort_keys=True))
    for v in result["violations"]:
        print(f"  VIOLATION {v['group']} tid={v['tid']} comm={v['comm']!r} "
              f"cpus={v['cpus'][:8]} first_seen={v['first_seen_s']}s "
              f"cpu_while_off={v['cpu_core_s_while_off_cpuset']}s")
    return 0 if not viol else 3


if __name__ == "__main__":
    sys.exit(main())
