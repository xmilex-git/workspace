#!/usr/bin/env python3.11
"""
TPCH-SSPQ implementation campaign `tpch-sspq-impl-r1-20260803` — extract every
measurement ATTEMPT and its outcome from the Phase 1A driver log.

IMPL-SSOT section 3-a requires every invalidation to be recorded with its cause
and the measured external load. A block that is ultimately accepted can still have
discarded attempts — a failed WARM gate, or an external-load rejection — and those
are the ones that are easiest to lose: `measure_block.sh` writes its per-attempt
artifacts into `work/<QNN>/`, which the NEXT block of the same query overwrites.
Only the failed-block path copies them into `raw/`.

The driver log is therefore the authoritative, complete and durable record of
attempt-level outcomes, and this extractor parses it rather than globbing the work
directory, which would silently undercount.

Usage: extract_attempts.py DRIVER_LOG [OUT_JSON]
"""
import json
import re
import sys

RE_QUERY = re.compile(r"^\[(\S+)\] #{10} (Q\d\d) — (\d+) blocks")
RE_BLOCK = re.compile(r"^\[(\S+)\]   --- (Q\d\d) block (\d+)/(\d+)")
RE_ATTEMPT = re.compile(r"^=== (Q\d\d) cubrid attempt (\d+)/(\d+)")
RE_WARM = re.compile(r"^  warm_establish rc=(\d+) (CONVERGED|NOT_CONVERGED) (.*)$")
RE_HEAD = re.compile(
    r"^  headline_rc=(\d+) gate_field=(\S+) load_verdict=(\S+) strict_verdict=(\S+) "
    r"external_mean=(\S+) external_max=(\S+) external_max_1s=(\S+)")
RE_ACCEPT = re.compile(r"^(Q\d\d) cubrid: block ACCEPTED on attempt (\d+)")
RE_REJECT = re.compile(r"^(Q\d\d) cubrid: attempt (\d+) REJECTED \(headline_rc=(\d+), (\S+)\)")
RE_WARMFAIL = re.compile(r"^(Q\d\d) cubrid: attempt (\d+) WARM NOT ESTABLISHED \(rc=(\d+)\)")
RE_ALLREJ = re.compile(r"^(Q\d\d) cubrid: all (\d+) attempts rejected")
RE_BLOCKRES = re.compile(r"^\[(\S+)\]     block (\d+) (ACCEPTED|INVALID)(.*)$")


def main():
    log = sys.argv[1]
    out_path = sys.argv[2] if len(sys.argv) > 2 else None

    qnn = None
    block = None
    attempts = []
    cur = None

    with open(log, errors="replace") as f:
        for line in f:
            line = line.rstrip("\n")

            m = RE_QUERY.match(line)
            if m:
                qnn = m.group(2)
                continue

            m = RE_BLOCK.match(line)
            if m:
                qnn, block = m.group(2), int(m.group(3))
                continue

            m = RE_ATTEMPT.match(line)
            if m:
                if cur:
                    attempts.append(cur)
                cur = {"qnn": m.group(1), "block": block, "attempt": int(m.group(2)),
                       "max_attempts": int(m.group(3)), "outcome": None}
                continue

            if cur is None:
                continue

            m = RE_WARM.match(line)
            if m:
                cur["warm_rc"] = int(m.group(1))
                cur["warm_converged"] = m.group(2) == "CONVERGED"
                cur["warm_verdict"] = m.group(3).strip()
                continue

            m = RE_HEAD.match(line)
            if m:
                def num(x):
                    try:
                        return float(x)
                    except ValueError:
                        return None
                cur.update({
                    "headline_rc": int(m.group(1)),
                    "gate_field": m.group(2),
                    "load_verdict": m.group(3),
                    "strict_verdict": m.group(4),
                    "external_mean_core_s_per_s": num(m.group(5)),
                    "external_max_core_s_per_s": num(m.group(6)),
                    "external_max_1s_core_s_per_s": num(m.group(7)),
                })
                continue

            m = RE_ACCEPT.match(line)
            if m:
                cur["outcome"] = "ACCEPTED"
                attempts.append(cur)
                cur = None
                continue

            m = RE_REJECT.match(line)
            if m:
                cur["outcome"] = "REJECTED"
                cur["invalid_reason"] = m.group(4)
                attempts.append(cur)
                cur = None
                continue

            m = RE_WARMFAIL.match(line)
            if m:
                cur["outcome"] = "REJECTED"
                cur["invalid_reason"] = "WARM_NOT_CONVERGED"
                attempts.append(cur)
                cur = None
                continue

    if cur:
        attempts.append(cur)

    discarded = [a for a in attempts if a.get("outcome") == "REJECTED"]
    by_reason = {}
    for a in discarded:
        by_reason[a.get("invalid_reason", "?")] = by_reason.get(
            a.get("invalid_reason", "?"), 0) + 1
    per_query = {}
    for a in discarded:
        per_query.setdefault(a["qnn"], []).append(a)

    doc = {
        "source_log": log,
        "n_attempts_total": len(attempts),
        "n_attempts_accepted": sum(1 for a in attempts if a.get("outcome") == "ACCEPTED"),
        "n_attempts_discarded": len(discarded),
        "discarded_by_reason": by_reason,
        "discarded_attempts": discarded,
        "discarded_by_query": per_query,
        "note": ("Attempt-level outcomes parsed from the Phase 1A driver log, which "
                 "is the only complete durable record: work/<QNN>/ per-attempt "
                 "artifacts are overwritten by the next block of the same query."),
    }
    if out_path:
        with open(out_path, "w") as f:
            json.dump(doc, f, indent=2, sort_keys=True)
    print(json.dumps({k: v for k, v in doc.items()
                      if k not in ("discarded_attempts", "discarded_by_query")},
                     indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
