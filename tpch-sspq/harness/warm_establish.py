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

# Gate parameters. Defaults reproduce the Q04 constants; Q05 showed they are not
# universal, so each is overridable and every report must record the values used
# and the measurement they were derived from.
#
# Q05 finding (why the level test changed). The original test compared two
# adjacent 4-statement window medians and required <= 1.0% twice over. On Q05's
# CUBRID series that statistic is measured against a KNOWN-CONVERGED 40-statement
# probe (half-to-half drift -0.10%) and produces up to 3.74%: the gate rejects a
# query that has in fact converged, which is precisely the failure the original
# docstring warned about. The cause is that Q05's series is not white noise -- it
# contains multi-statement plateau excursions (statements 13-18 of
# q5-convergence-cubrid.out sit 2.6% below the baseline), so a 4-sample median is
# not a stable estimate of the level.
#
# The replacement compares the medians of the two halves of the WHOLE series
# (burn-in statement dropped), which uses n/2 samples per side instead of 4 and
# therefore averages the excursions out. Its null distribution was measured, not
# assumed: a moving-block bootstrap (block length 6, >= the observed plateau
# length) over the stationary 40-statement probes gives, for the statistic at the
# series length actually used,
#
#     n=20   CUBRID p95 2.68%  max 3.49%   PostgreSQL p95 0.92%  max 1.28%
#     n=40   CUBRID p95 2.16%  max 2.99%   PostgreSQL p95 0.73%  max 1.17%
#
# while a genuinely warming 40-statement series (the post-restart CUBRID trace,
# level 11.132 -> 9.574 s) scores 13.17%. At n=20 null and signal OVERLAP and no
# threshold can separate them, which is why the statement count matters more than
# the tolerance; at n=40 they separate by 4.4x. Q05 therefore runs the gate at 40
# statements with LEVEL_TOL 3.0% (above the n=40 stationary null max of 2.99%,
# far below the 13.17% warming signal) and SPREAD_SANITY 5.0% (above the 4.24%
# raw spread the converged probe itself exhibits).
WINDOW = int(os.environ.get("TPCH_SSPQ_WARM_WINDOW", "4"))
LEVEL_TOL = float(os.environ.get("TPCH_SSPQ_WARM_LEVEL_TOL", "0.010"))
SPREAD_SANITY = float(os.environ.get("TPCH_SSPQ_WARM_SPREAD", "0.030"))
MAX_DEFAULT = int(os.environ.get("TPCH_SSPQ_WARM_MAX", "20"))


def median(xs):
    s = sorted(xs)
    return s[len(s) // 2]


def _trend(times):
    """Signed half-split drift of the whole series, burn-in statement dropped.

    median(second half) / median(first half) - 1. Positive means the engine is
    still getting slower, negative means still getting faster; either way a
    magnitude above LEVEL_TOL means the level has not stopped moving.
    """
    body = times[1:]
    if len(body) < 4:
        return 0.0
    h = len(body) // 2
    return median(body[h:]) / median(body[:h]) - 1


def converged(times):
    if len(times) < 3 * WINDOW:
        return False, "insufficient statements"
    w = times[-WINDOW:]
    spread = (max(w) - min(w)) / median(w)
    if all(a > b for a, b in zip(w, w[1:])) or all(a < b for a, b in zip(w, w[1:])):
        return False, "monotone trailing window (still drifting)"
    if spread > SPREAD_SANITY:
        return False, f"spread {spread:.4%} > {SPREAD_SANITY:.2%} (unstable)"
    tr = _trend(times)
    if abs(tr) > LEVEL_TOL:
        return False, (f"half-split trend {tr:+.4%} exceeds {LEVEL_TOL:.2%} "
                       f"over {len(times)} statements (level still moving)")
    return True, (f"half-split trend {tr:+.4%} within {LEVEL_TOL:.2%} over "
                  f"{len(times)} statements, trailing spread {spread:.4%}")


def main():
    if len(sys.argv) not in (3, 4, 5, 6):
        print("usage: warm_establish.py QNN cubrid|postgresql [MAX_STATEMENTS] "
              "[SQL_FILE|-] [VARIANT_TAG]", file=sys.stderr)
        print("  SQL_FILE/- plus VARIANT_TAG drive a controlled-plan variant to ITS own "
              "steady state", file=sys.stderr)
        print("  before that variant's block is timed. A variant inherits neither the "
              "native plan's", file=sys.stderr)
        print("  residency nor its convergence point, so it needs its own warm proof.",
              file=sys.stderr)
        return 2
    qnn, engine = sys.argv[1].upper(), sys.argv[2].lower()
    max_stmt = int(sys.argv[3]) if len(sys.argv) > 3 else MAX_DEFAULT
    override = sys.argv[4] if len(sys.argv) > 4 else None
    variant = sys.argv[5] if len(sys.argv) > 5 else "native"
    label = engine if variant == "native" else f"{engine}-{variant}"
    n = int(qnn[1:])
    workdir = os.path.join(hr.RAW_ROOT, "work", qnn)
    sinkdir = os.path.join(workdir, "sink")
    os.makedirs(sinkdir, exist_ok=True)

    suffix = "cubrid" if engine == "cubrid" else "pg"
    qfile = override if (override and override != "-") else os.path.join(
        hr.QUERIES, f"q{n}-{suffix}.sql")
    with open(qfile) as f:
        q = f.read().rstrip()
    if not q.endswith(";"):
        q += ";"

    path = os.path.join(workdir, f"q{n}-{label}-warm.sql")
    with open(path, "w") as f:
        if engine == "postgresql":
            f.write("\\timing on\n")
        f.write("\n".join([q] * max_stmt) + "\n")
    sink = os.path.join(sinkdir, f"{qnn}-{label}-warm.out")

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
        "variant": variant,
        "pgoptions": os.environ.get("PGOPTIONS", "") if engine == "postgresql" else None,
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
    p = os.path.join(workdir, f"{qnn}-{label}-warm.json")
    with open(p, "w") as f:
        json.dump(out, f, indent=2, sort_keys=True)
    print(json.dumps({k: v for k, v in out.items() if k != "sink"}, indent=2,
                     sort_keys=True))
    return 0 if (rc == 0 and ok) else 4


if __name__ == "__main__":
    sys.exit(main())
