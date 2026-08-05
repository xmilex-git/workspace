#!/usr/bin/env python3.11
"""
IMP-005 raw-artifact manifest generator (section 1-e / section 8-e).

Every raw artifact this candidate produced under
/data/tpch-sspq/tpch-sspq-impl-r1-20260803/work/IMP-005 is hashed and recorded
with the command that produced it, the pins in force, and its validity. Blocks
rejected by the section 3-a load gate are recorded as `valid: false` with the
reason instead of being dropped, so discarded measurements stay auditable.

Usage: imp005_manifest.py [OUT_JSON]
  default OUT_JSON = tpch-sspq/impl/IMP-005/raw-manifest.json
"""
import datetime
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import campaign_config as c  # noqa: E402

WORK = os.path.join(c.RAW_ROOT, "work", "IMP-005")
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    c.REPO, "impl", "IMP-005", "raw-manifest.json")
SESSION = os.environ.get("GJC_SESSION_ID", "unknown")


def creation_command(rel):
    parts = rel.split(os.sep)
    if parts[0] == "build.log":
        return "section 6-a-1 pinned build recipe (INSTALL_PREFIX, taskset -c 24-31)"
    if parts[0] == "trace":
        return "imp005_trace_probe.py (section 6-b check 1 / section 5 metric signature)"
    if parts[0] == "correctness":
        return "imp005_correctness.py run/compare (section 6-b checks 2-4 + Q15 view protocol)"
    if parts[0] == "ab":
        if len(parts) > 1 and parts[1] == "Q09":
            return "imp005_ab.sh gate (server_ctl.sh restart + measure_block.sh Q09 cubrid)"
        if len(parts) > 1 and parts[1] == "stream":
            return "imp005_ab.sh stream (server_ctl.sh restart + measure_block.sh / q15_gated_block.sh)"
        if len(parts) > 1 and parts[1] == "ab-stats.json":
            return "imp005_ab_stats.py (section 6-d paired block-median ratio + bootstrap CI)"
        return "imp005_ab.sh (driver bookkeeping)"
    return "IMP-005 candidate tooling"


def validity(path, rel):
    name = os.path.basename(rel)
    if "INVALID" in name:
        return False, "section 3-a external load gate rejected this attempt"
    if name.endswith("-bgload.json"):
        try:
            with open(path) as f:
                v = json.load(f).get("verdict")
            if v != "CLEAN":
                return False, f"bgload verdict {v}"
        except Exception:
            pass
    return True, None


def main():
    artifacts = []
    for root, _dirs, files in os.walk(WORK):
        for fn in sorted(files):
            p = os.path.join(root, fn)
            if os.path.islink(p) or not os.path.isfile(p):
                continue
            rel = os.path.relpath(p, WORK)
            valid, reason = validity(p, rel)
            artifacts.append({
                "path": p,
                "relpath": rel,
                "bytes": os.path.getsize(p),
                "sha256": c.sha256_file(p),
                "creation_command": creation_command(rel),
                "campaign_id": c.CAMPAIGN,
                "imp_id": "IMP-005",
                "gjc_session_id": SESSION,
                "impl_ssot_commit": c.IMPL_SSOT_COMMIT,
                "impl_ssot_blob": c.IMPL_SSOT_BLOB,
                "cubrid_base_sha": c.CUBRID_BASE_SHA,
                "valid": valid,
                "invalid_reason": reason,
            })
    artifacts.sort(key=lambda a: a["relpath"])
    out = {
        "campaign_id": c.CAMPAIGN,
        "imp_id": "IMP-005",
        "generated_utc": datetime.datetime.now(
            datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "work_root": WORK,
        "artifact_count": len(artifacts),
        "invalid_count": sum(1 for a in artifacts if not a["valid"]),
        "artifacts": artifacts,
    }
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w") as f:
        json.dump(out, f, indent=2)
    print(f"{OUT}: {out['artifact_count']} artifacts "
          f"({out['invalid_count']} invalid)")


if __name__ == "__main__":
    main()
