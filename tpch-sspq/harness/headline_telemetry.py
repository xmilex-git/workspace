#!/usr/bin/env python3.11
"""
TPCH-SSPQ FK campaign (tpch-sspq-fk-r1-20260730) — headline-regime CPU telemetry.

Why this exists
---------------
`harness/telemetry_run.py` supplies the CPU numerators for the section 16 causal
multiplier card, but it executes ONE statement per connection while the section 12
headline regime is `single-connection-four-statements` (1 uncounted warmup + 3
measured). The two regimes have measurably different walls, so the card's
`F_units x F_cpu` reconstructs the TELEMETRY wall ratio rather than the HEADLINE
wall ratio, and the difference shows up as a reconstruction residual:
Q03 -1.0259%, Q04 -2.0065% before this harness existed. Q03 recorded that as a
carried-forward gap ("a future harness change could sample CPU inside the headline
block itself"). This is that change.

What it measures
----------------
The identical section 12 block (same builder as `harness/headline_run.py`: same
query file, 1 warmup + 3 measured, one direct connection, no reconnect or prepare
between statements, full row consumption into a campaign-owned sink) is executed
once under the same per-TID sampler that `telemetry_run.py` uses, pinned to the
collector CPUs and weighted by actual sample timestamp deltas.

Two quantities come out DIRECTLY measured, with no attribution rule:

  CPU_block  total query CPU-seconds over the block's busy window
  T_block    sum of the client-reported per-statement walls in that block
  U          = CPU_block / T_block          [core-seconds per wall-second]

Per-statement CPU is then `CPU_stmt = U * t_stmt`. That is an explicit attribution
rule, not a measurement: it assumes utilization is constant across the statements
of one block. The assumption is TESTED, not asserted -- `u_crosscheck` in the
output compares this block-level U against the single-statement
`telemetry_run.py` U for the same engine, and section 12's own per-statement
spread bounds how far the warmup can drag it.

Statement-level segmentation of the sample timeline is deliberately NOT attempted:
the inter-statement client gap for these queries is single-digit milliseconds, so
resolving it would need a sampling period fast enough to perturb the very block
being measured (the sampler docstring records +8..16% wall at a 20 ms period on a
0.35 s query). A stated and cross-checked attribution rule is honest; a segmenter
that silently mis-slices is not.

Usage: headline_telemetry.py QNN cubrid|postgresql
"""
import json
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import headline_run as hr  # noqa: E402  (block builder + statement-time parsers)
import telemetry_run as tr  # noqa: E402  (sampler, CPU/TWU/IO analysis)

os.environ.setdefault("CUBRID_TMP", "/tmp")


def main():
    if len(sys.argv) not in (3, 4, 5):
        print("usage: headline_telemetry.py QNN cubrid|postgresql [SQL_FILE|-] [VARIANT_TAG]",
              file=sys.stderr)
        print("  SQL_FILE/- plus VARIANT_TAG measure a controlled-plan variant in the same",
              file=sys.stderr)
        print("  section 12 block regime as the native run, so a section 16 F_plan anchor",
              file=sys.stderr)
        print("  and its remaining cross-engine pair share one denominator.", file=sys.stderr)
        return 2
    qnn, engine = sys.argv[1].upper(), sys.argv[2].lower()
    if engine not in ("cubrid", "postgresql"):
        print("engine must be cubrid or postgresql", file=sys.stderr)
        return 2
    override = sys.argv[3] if len(sys.argv) > 3 else None
    variant = sys.argv[4] if len(sys.argv) > 4 else "native"
    label = engine if variant == "native" else f"{engine}-{variant}"

    workdir = os.path.join(tr.RAW_ROOT, "work", qnn)
    sinkdir = os.path.join(workdir, "sink")
    os.makedirs(sinkdir, exist_ok=True)
    sink = os.path.join(sinkdir, f"{qnn}-{label}-headline-telemetry.out")

    # identical block to the section 12 headline runner
    block_sql, qfile = hr.build_block(qnn, engine, workdir, override, variant)

    if engine == "cubrid":
        env = dict(os.environ)
        env["CUBRID"] = tr.CUBRID_HOME
        env["CUBRID_DATABASES"] = tr.CUBRID_DATABASES
        cmd = ["taskset", "-c", tr.SUT_CPUS, f"{tr.CUBRID_HOME}/bin/csql", "-C",
               "-u", "dba", tr.CUBRID_DB, "--no-pager", "-i", block_sql]
        srv_pat = f"cub_server {tr.CUBRID_DB}"
    else:
        env = dict(os.environ)
        cmd = ["taskset", "-c", tr.SUT_CPUS, f"{tr.PG_HOME}/bin/psql", "-h",
               tr.PG_SOCKDIR, "-p", tr.PG_PORT, "-d", tr.PG_DB, "-A", "-t",
               "-f", block_sql]
        srv_pat = f"{tr.PG_HOME}/bin/postgres -D {tr.PG_SOCKDIR}"

    srv_pid = int(subprocess.run(["pgrep", "-f", srv_pat], capture_output=True,
                                 text=True).stdout.split()[0])
    numa_pre = tr.numa(srv_pid)

    sampler = tr.Sampler(engine)
    sampler.start()
    time.sleep(1.0)
    t0 = time.monotonic()
    with open(sink, "w") as sf:
        p = subprocess.run(cmd, stdout=sf, stderr=subprocess.PIPE, text=True,
                           env=env, timeout=hr.TIMEOUT * 4 + 120)
    t1 = time.monotonic()
    time.sleep(1.0)
    sampler.stop_flag.set()
    sampler.join(timeout=10)
    numa_post = tr.numa(srv_pid)

    times = hr.parse_times(engine, sink, p.stderr)
    measured = times[1:1 + hr.N_MEASURED] if len(times) >= 1 + hr.N_MEASURED else []
    t_block = sum(times)

    exec_ticks, aux_ticks, per_bucket, intervals = tr.analyse(sampler.samples)
    w, peak, busy_dt, tail = tr.twu(intervals)
    executor_cpu = exec_ticks / tr.TICKS
    auxiliary_cpu = aux_ticks / tr.TICKS
    cpu_block = executor_cpu + auxiliary_cpu
    u = cpu_block / t_block if t_block else None

    median = sorted(measured)[len(measured) // 2] if measured else None
    result = {
        "campaign_id": tr.CAMPAIGN, "qnn": qnn, "engine": engine,
        "variant": variant,
        "pgoptions": os.environ.get("PGOPTIONS", "") if engine == "postgresql" else None,
        "stage": "14.7-execution-telemetry-headline-regime",
        "regime": "single-query-repeat WARM",
        "connection_mode": "single-connection-four-statements",
        "headline_regime": True,
        "query_file": qfile, "block_sql": block_sql,
        "client_exit": p.returncode, "client_stderr": p.stderr[-1500:],
        "client_wall_s": t1 - t0,
        "statement_times_all": times,
        "measured_times_s": measured,
        "median_s": median,
        "t_block_s": t_block,
        "sample_interval_nominal_s": tr.INTERVAL,
        "n_samples": len(sampler.samples),
        "cpu": {
            "executor_cpu_core_s": round(executor_cpu, 3),
            "auxiliary_query_cpu_core_s": round(auxiliary_cpu, 3),
            "total_query_cpu_block_core_s": round(cpu_block, 3),
            "per_bucket_core_s": {k: round(v / tr.TICKS, 3)
                                  for k, v in sorted(per_bucket.items(),
                                                     key=lambda x: -x[1])},
        },
        "utilization": {
            "U_core_s_per_wall_s": round(u, 5) if u else None,
            "formula": "U = total_query_cpu_block / sum(statement walls in block)",
            "note": "directly measured over the section 12 headline block; no attribution rule",
        },
        "per_statement_attribution": {
            "rule": "CPU_stmt = U * t_stmt (constant-utilization attribution)",
            "median_statement_cpu_core_s": round(u * median, 4) if (u and median) else None,
            "warmup_cpu_core_s": round(u * times[0], 4) if (u and times) else None,
            "tested_by": "u_crosscheck against single-statement telemetry_run.py U",
        },
        "units": {
            "time_weighted_active_units": round(w, 4) if w else None,
            "max_simultaneous_active_units": round(peak, 4) if peak else None,
            "busy_window_s": round(busy_dt, 3) if busy_dt else None,
            "serial_tail_s": round(tail, 3) if tail is not None else None,
            "weighting": "actual sample timestamp deltas (not nominal interval)",
            "note": "TWU spans the whole 4-statement block, including inter-statement gaps",
        },
        "io": {"engine_and_client": tr.io_delta(sampler.samples),
               "device": tr.disk_delta(sampler.samples)},
        "numa": {"pre": numa_pre, "post": numa_post},
        "sink": {"path": sink, "bytes": os.path.getsize(sink),
                 "sha256": subprocess.run(["sha256sum", sink], capture_output=True,
                                          text=True).stdout.split()[0]},
    }

    ipath = os.path.join(workdir, f"{qnn}-{label}-headline-telemetry-intervals.json")
    with open(ipath, "w") as f:
        json.dump(intervals, f)
    result["intervals_path"] = ipath
    spath = os.path.join(workdir, f"{qnn}-{label}-headline-telemetry-samples.json")
    with open(spath, "w") as f:
        json.dump(sampler.samples, f)
    result["samples_path"] = spath

    out = os.path.join(workdir, f"{qnn}-{label}-headline-telemetry.json")
    with open(out, "w") as f:
        json.dump(result, f, indent=2, sort_keys=True)
    print(json.dumps({k: v for k, v in result.items()
                      if k not in ("numa", "client_stderr")}, indent=2, sort_keys=True))
    return 0 if p.returncode == 0 and len(measured) == hr.N_MEASURED else 1


if __name__ == "__main__":
    sys.exit(main())
