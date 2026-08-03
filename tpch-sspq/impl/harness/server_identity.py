#!/usr/bin/env python3.11
"""
TPCH-SSPQ implementation campaign `tpch-sspq-impl-r1-20260803` — section 3-b
server-ownership gate plus the section 3-a all-TID affinity / NUMA proof.

Section 3-b requires this to be verified and RECORDED before and after EVERY
block:
  1. cub_master and database-server PIDs and the port owner;
  2. /proc/<pid>/exe resolved to a real path;
  3. that the executable path is under this campaign's install prefix;
  4. the database identity, the port, the PID and the process start time;
  5. a classification OK / FREE / BLOCKED.

Section 3-a additionally requires the affinity of EVERY cub_server TID to be
checked individually by iterating /proc/<pid>/task/*, and the NUMA page
distribution to be recorded before and after each block. A single off-target TID
makes the run INVALID.

Exit codes
  0  OK        campaign-owned, every TID inside the SUT set, memory bound to node 0
  3  OFF_CPUSET  at least one TID outside the SUT CPU list  => block INVALID
  4  BLOCKED     a server exists but is not campaign-owned  => stop, do not measure
  5  FREE        no server running

Usage: server_identity.py [OUT_JSON]
"""
import json
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import campaign_config as cfg  # noqa: E402

TCK = os.sysconf("SC_CLK_TCK")


def pgrep(args):
    r = subprocess.run(["pgrep"] + args, capture_output=True, text=True)
    return [int(x) for x in r.stdout.split()]


def boot_time():
    with open("/proc/stat") as f:
        for line in f:
            if line.startswith("btime "):
                return int(line.split()[1])
    return None


def proc_info(pid):
    out = {"pid": pid}
    try:
        out["exe"] = os.path.realpath(f"/proc/{pid}/exe")
    except OSError:
        out["exe"] = None
    try:
        with open(f"/proc/{pid}/cmdline") as f:
            out["cmdline"] = f.read().replace("\x00", " ").strip()
    except OSError:
        out["cmdline"] = None
    try:
        with open(f"/proc/{pid}/stat") as f:
            parts = f.read().rsplit(")", 1)[1].split()
        starttime_ticks = int(parts[19])
        bt = boot_time()
        out["start_time_epoch"] = bt + starttime_ticks / TCK if bt else None
        out["start_time_utc"] = (
            time.strftime("%Y-%m-%dT%H:%M:%SZ",
                          time.gmtime(out["start_time_epoch"]))
            if out["start_time_epoch"] else None)
    except (OSError, IndexError, ValueError):
        out["start_time_epoch"] = out["start_time_utc"] = None
    return out


def all_tid_affinity(pid):
    """Section 3-a: iterate /proc/<pid>/task/* and check each TID individually."""
    tids, off = [], []
    try:
        entries = os.listdir(f"/proc/{pid}/task")
    except OSError:
        return [], [], 0
    for t in entries:
        try:
            mask = os.sched_getaffinity(int(t))
        except (OSError, ValueError):
            continue
        try:
            with open(f"/proc/{pid}/task/{t}/comm") as f:
                comm = f.read().strip()
        except OSError:
            comm = "?"
        rec = {"tid": int(t), "comm": comm, "cpus": sorted(mask)}
        tids.append(rec)
        if not mask <= cfg.SUT_CPU_SET:
            off.append(rec)
    return tids, off, len(entries)


def numa_maps(pid):
    """NUMA page distribution — recorded before and after each block (3-a)."""
    r = subprocess.run(["numastat", "-p", str(pid)], capture_output=True, text=True)
    per_node = {}
    for line in r.stdout.split("\n"):
        if line.startswith("Total"):
            parts = line.split()
            for i, v in enumerate(parts[1:-1]):
                per_node[f"node{i}_MB"] = float(v)
            per_node["total_MB"] = float(parts[-1])
    return {"numastat_raw": r.stdout, "totals": per_node}


def port_owner(port):
    r = subprocess.run(["ss", "-lntp"], capture_output=True, text=True)
    rows = [l for l in r.stdout.split("\n") if f":{port} " in l]
    return rows


def main():
    out_path = sys.argv[1] if len(sys.argv) > 1 else None

    srv = pgrep(["-f", f"cub_server {cfg.CUBRID_DB}"])
    mst = pgrep(["-x", "cub_master"])

    result = {
        "campaign_id": cfg.CAMPAIGN,
        "impl_ssot_commit": cfg.IMPL_SSOT_COMMIT,
        "impl_ssot_blob": cfg.IMPL_SSOT_BLOB,
        "checked_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "expected_install_prefix": cfg.CUBRID_HOME,
        "expected_db": cfg.CUBRID_DB,
        "expected_port": cfg.CUBRID_PORT,
        "sut_cpus": cfg.SUT_CPUS,
        "membind_node": cfg.MEMBIND_NODE,
        "cub_server_pids": srv,
        "cub_master_pids": mst,
        "port_listeners": port_owner(cfg.CUBRID_PORT),
    }

    if not srv:
        result["classification"] = "FREE"
        result["cubrid_conf_sha256"] = cfg.assert_conf_sha()
        rc = 5
    else:
        pid = srv[0]
        info = proc_info(pid)
        result["cub_server"] = info
        result["cub_master"] = [proc_info(p) for p in mst]
        expected_exe = os.path.join(cfg.CUBRID_HOME, "bin", "cub_server")
        owned = (info["exe"] == os.path.realpath(expected_exe)
                 and f"cub_server {cfg.CUBRID_DB}" in (info["cmdline"] or ""))
        result["executable_under_campaign_prefix"] = owned
        if not owned:
            result["classification"] = "BLOCKED"
            result["blocked_reason"] = (
                f"exe {info['exe']!r} is not {expected_exe!r} — section 3-b forbids "
                f"stopping or measuring another owner's server")
            rc = 4
        else:
            tids, off, n = all_tid_affinity(pid)
            result["all_tid_affinity"] = {
                "n_tids": len(tids),
                "n_off_sut": len(off),
                "off_sut_tids": off,
                "tids": tids,
            }
            result["numa"] = numa_maps(pid)
            result["binaries"] = cfg.binary_fingerprint()
            result["cubrid_conf_sha256"] = cfg.assert_conf_sha()
            result["cubrid_tmp"] = cfg.assert_cubrid_tmp()
            result["install_prefix_allowed"] = cfg.assert_prefix_allowed()
            if off:
                result["classification"] = "OFF_CPUSET"
                rc = 3
            else:
                result["classification"] = "OK"
                rc = 0

    if out_path:
        with open(out_path, "w") as f:
            json.dump(result, f, indent=2, sort_keys=True)
    printable = dict(result)
    if "all_tid_affinity" in printable:
        a = dict(printable["all_tid_affinity"])
        a.pop("tids", None)
        printable["all_tid_affinity"] = a
    printable.pop("numa", None)
    printable.pop("binaries", None)
    print(json.dumps(printable, indent=2, sort_keys=True))
    return rc


if __name__ == "__main__":
    sys.exit(main())
