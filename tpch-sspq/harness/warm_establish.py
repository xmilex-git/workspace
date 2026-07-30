#!/usr/bin/env python3.11
"""
TPCH-SSPQ FK campaign (tpch-sspq-fk-r1-20260730) — SSOT section 12 WARM establishment.

Section 12 requires "WARM is proved, not assumed" and "A failed WARM gate
invalidates the run and restarts at warmup". It does NOT say one warmup statement
is always sufficient; it says the state must be proved. For most of this campaign
one warmup is enough -- Q01 and Q03 drift <= 0.28% across their three measured
statements -- but Q04 falsified that for the first time:

  PostgreSQL, 14 consecutive repeats in one connection (q4-convergence-pg.out):
    1026.9, 967.4, 960.1, 946.9, 944.8, 948.7, 945.8, 949.3, 946.3, 945.6, ...
  i.e. the contract block's three measured statements (positions 2-4) sit at
  967/960/947 ms while the steady state is ~947 ms -- still on the decay curve,
  a +2.1% bias on the headline.

  CUBRID, 14 consecutive repeats (q4-convergence-cubrid.out):
    1.778, 1.766, 1.772, 1.765, 1.766, 1.774, 1.777, 1.768, ... -- internally
  stable inside any block (sd ~0.4%), but the LEVEL depends on what the buffer
  pool already held: the first Q04 block measured 1.706 s and every later block
  reproduces 1.774-1.779 s. Q04's working set does not fit CUBRID's 8 GiB pool
  (277k page misses per statement, section 5), so a block inherits whichever
  residency the preceding workload left behind.

This stage removes both effects by driving the engine to its OWN steady state
before the contract block is timed. It is a warm-up, not a measurement: nothing
it produces is ever reported as a headline value. The contract block that follows
is unchanged -- one direct connection, one uncounted warmup, three measured
statements, no reconnect or prepare between them.

Convergence proof. The target is SYSTEMATIC drift -- PostgreSQL's per-connection
decay curve and CUBRID's inherited-residency level shift -- not run-to-run jitter,
so the gate is on the LEVEL and its direction, and raw spread is only recorded.
CUBRID's own statement-to-statement jitter reaches 1.2% over a 4-statement window
at a stable level (q4-convergence-cubrid.out: 1.752-1.788 s across 14 repeats with
no trend), so gating on spread would reject an engine that has in fact converged.
All of the following must hold:
  1. the trailing WINDOW is not monotone (a still-decaying series is not steady);
  2. the trailing window's median is within LEVEL_TOL of the preceding window's
     median, AND the same holds one window earlier -- the level has to have
     stopped moving and stayed stopped, not merely paused between two samples;
  3. spread stays under SPREAD_SANITY, which catches an engine that is genuinely
     unstable rather than one that is merely noisy.

Usage: warm_establish.py QNN cubrid|postgresql [MAX_STATEMENTS]
Exit 0 when converged, 4 when the cap is reached without convergence (the caller
decides whether to proceed and must record the failure).
"""
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import headline_run as hr  # noqa: E402

os.environ.setdefault("CUBRID_TMP", "/tmp")

WINDOW = 4
LEVEL_TOL = 0.010     # 1.0% between consecutive window medians, twice over
SPREAD_SANITY = 0.030 # 3.0% max-min over trailing window: instability, not noise
MAX_DEFAULT = 20      # replay traces converge at statement 12 (CUBRID) / 14 (PG)


def median(xs):
    s = sorted(xs)
    return s[len(s) // 2]


def _level_shift(times, end):
    """|median(times[end-W:end]) / median(times[end-2W:end-W]) - 1|."""
    return abs(median(times[end - WINDOW:end])
               / median(times[end - 2 * WINDOW:end - WINDOW]) - 1)


def converged(times):
    if len(times) < 3 * WINDOW:
        return False, "insufficient statements"
    w = times[-WINDOW:]
    spread = (max(w) - min(w)) / median(w)
    if all(a > b for a, b in zip(w, w[1:])) or all(a < b for a, b in zip(w, w[1:])):
        return False, "monotone trailing window (still drifting)"
    if spread > SPREAD_SANITY:
        return False, f"spread {spread:.4%} > {SPREAD_SANITY:.2%} (unstable)"
    l1 = _level_shift(times, len(times))
    l2 = _level_shift(times, len(times) - WINDOW)
    if max(l1, l2) > LEVEL_TOL:
        return False, f"level shift {max(l1, l2):.4%} > {LEVEL_TOL:.2%}"
    return True, f"spread {spread:.4%}, level shift {l1:.4%} then {l2:.4%}"


def main():
    if len(sys.argv) not in (3, 4):
        print("usage: warm_establish.py QNN cubrid|postgresql [MAX_STATEMENTS]",
              file=sys.stderr)
        return 2
    qnn, engine = sys.argv[1].upper(), sys.argv[2].lower()
    max_stmt = int(sys.argv[3]) if len(sys.argv) > 3 else MAX_DEFAULT
    n = int(qnn[1:])
    workdir = os.path.join(hr.RAW_ROOT, "work", qnn)
    sinkdir = os.path.join(workdir, "sink")
    os.makedirs(sinkdir, exist_ok=True)

    suffix = "cubrid" if engine == "cubrid" else "pg"
    qfile = os.path.join(hr.QUERIES, f"q{n}-{suffix}.sql")
    with open(qfile) as f:
        q = f.read().rstrip()
    if not q.endswith(";"):
        q += ";"

    path = os.path.join(workdir, f"q{n}-{engine}-warm.sql")
    with open(path, "w") as f:
        if engine == "postgresql":
            f.write("\\timing on\n")
        f.write("\n".join([q] * max_stmt) + "\n")
    sink = os.path.join(sinkdir, f"{qnn}-{engine}-warm.out")

    rc, err, wall = hr.run_block(qnn, engine, workdir, sink, path)
    times = hr.parse_times(engine, sink, err)
    ok, why = converged(times) if times else (False, "no statement times parsed")

    # first index at which the trailing-window test would already have passed
    first_ok = None
    for k in range(2 * WINDOW, len(times) + 1):
        c, _ = converged(times[:k])
        if c:
            first_ok = k
            break

    out = {
        "campaign_id": hr.CAMPAIGN, "qnn": qnn, "engine": engine,
        "stage": "14.4/14.5-warm-establishment (uncounted, never a headline value)",
        "query_file": qfile, "block_sql": path, "client_exit": rc,
        "statements_executed": len(times), "statement_times_s": times,
        "block_wall_s": wall,
        "criteria": {"window": WINDOW, "level_tol": LEVEL_TOL,
                     "spread_sanity": SPREAD_SANITY, "max_statements": max_stmt,
                     "gate": "non-monotone trailing window AND two consecutive "
                             "window-median shifts <= level_tol AND spread <= spread_sanity"},
        "converged": ok, "verdict": why,
        "converged_after_statements": first_ok,
        "steady_state_median_s": median(times[-WINDOW:]) if len(times) >= WINDOW else None,
        "sink": {"path": sink, "bytes": os.path.getsize(sink),
                 "sha256": subprocess.run(["sha256sum", sink], capture_output=True,
                                          text=True).stdout.split()[0]},
    }
    p = os.path.join(workdir, f"{qnn}-{engine}-warm.json")
    with open(p, "w") as f:
        json.dump(out, f, indent=2, sort_keys=True)
    print(json.dumps({k: v for k, v in out.items() if k != "sink"}, indent=2,
                     sort_keys=True))
    return 0 if (rc == 0 and ok) else 4


if __name__ == "__main__":
    sys.exit(main())
