#!/usr/bin/env python3.11
"""
TPCH-SSPQ FK campaign (tpch-sspq-fk-r1-20260730) — Q15 logical-session harness.

Q15 is the only query the generic section 12 harness cannot express. SSOT section 6:
"Q15 view creation, selection and drop are one logical query and must be handled in
one query session." So the unit that gets repeated is not a statement, it is the
THREE-statement session

    create view revenue0 ... ;   select ... from supplier, revenue0 ... ;   drop view revenue0;

and the section 12 block is 1 uncounted warmup SESSION + 3 measured SESSIONS, all
inside one direct campaign connection with no reconnect or prepare between them.
`headline_run.py` would repeat the file 4 times and then slice statement times
1..3, which on Q15 would mix one session's SELECT with the next session's DDL and
report the DROP as a headline value. This script keeps every other section 12
property byte-identical to `headline_run.py` (same client invocation, same taskset,
same sampler on the collector CPUs, same buffer-counter capture, same sink
accounting) and only changes the grouping: statement times are consumed in
consecutive triples, and a session's time is the sum of its three statements.

Both per-phase and per-session values are always recorded, so the report can state
the logical-session headline (SSOT section 6's unit) and the SELECT-only number
without a second measurement.

A controlled variant is selected with TPCH_SSPQ_Q15_VARIANT (artifact tag) plus
either TPCH_SSPQ_Q15_CREATE_FILE (alternate view definition) or PGOPTIONS
(PostgreSQL planner controls), exactly like measure_block.sh's variant path.

Modes:
  warm      N sessions, uncounted, convergence-gated exactly like warm_establish.py
            (the same non-monotone / half-split-level / spread gate, applied to the
            session totals) -> {QNN}-{label}-warm.json
  headline  1 uncounted + 3 measured sessions -> {QNN}-{label}-headline.json
  hltel     the SAME 4-session block under the per-TID sampler, so the section 16
            utilization U = CPU_block / sum(statement walls in block) is measured
            INSIDE the contract block rather than on a single-session run whose
            wall differs from the headline's (the reason harness/headline_telemetry.py
            exists for every other query) -> {QNN}-{label}-headline-telemetry.json

Usage: q15_session.py warm|headline ENGINE [N_WARM_SESSIONS]
"""
import json
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import headline_run as hr  # noqa: E402
import warm_establish as we  # noqa: E402
import telemetry_run as tr  # noqa: E402  (per-TID sampler, CPU/TWU/IO analysis)

os.environ["CUBRID_TMP"] = "/tmp"

QNN = "Q15"
PHASES = ("create_view", "select", "drop_view")
N_MEASURED = 3


def phase_files(engine, create_override=None):
    """The three canonical phase files. `create_override` replaces ONLY the
    create-view file, for a controlled A/B on the view definition (e.g. the
    dialect artifact where `date + interval '3' month` yields a timestamp and
    forces a date->timestamp comparison per row). Every artifact of such a run is
    tagged, so a variant can never overwrite the native block."""
    suffix = "cubrid" if engine == "cubrid" else "pg"
    files = [os.path.join(hr.QUERIES, f"q15_{p}-{suffix}.sql") for p in PHASES]
    if create_override and create_override != "-":
        files[0] = create_override
    return files


def session_text(engine, create_override=None):
    """One logical Q15 session: create view, select, drop view."""
    parts = []
    for f in phase_files(engine, create_override):
        with open(f) as fh:
            t = fh.read().rstrip()
        if not t.endswith(";"):
            t += ";"
        parts.append(t)
    return "\n".join(parts)


def build_block(engine, workdir, n_sessions, tag, create_override=None):
    path = os.path.join(workdir, f"q15-{tag}-block.sql")
    body = session_text(engine, create_override)
    with open(path, "w") as f:
        if engine == "postgresql":
            f.write("\\timing on\n")
        f.write("\n".join([body] * n_sessions) + "\n")
    return path


def view_exists(engine):
    if engine == "cubrid":
        env = dict(os.environ)
        env["CUBRID"] = hr.CUBRID_HOME
        env["CUBRID_DATABASES"] = hr.CUBRID_DATABASES
        cmd = [f"{hr.CUBRID_HOME}/bin/csql", "-u", "dba", hr.CUBRID_DB, "-q", "-N",
               "-c", "select count(*) from db_class where class_name = 'revenue0';"]
    else:
        env = dict(os.environ)
        cmd = [f"{hr.PG_HOME}/bin/psql", "-h", hr.PG_SOCKDIR, "-p", hr.PG_PORT,
               "-d", hr.PG_DB, "-Atc",
               "select count(*) from information_schema.views "
               "where table_name = 'revenue0';"]
    r = subprocess.run(cmd, capture_output=True, text=True, env=env, timeout=60)
    return int((r.stdout or "0").strip() or "0") > 0


def force_drop(engine):
    """Leave no view behind from an aborted earlier block. Uncounted, separate
    connection, never inside a timed block."""
    if not view_exists(engine):
        return "absent"
    if engine == "cubrid":
        env = dict(os.environ)
        env["CUBRID"] = hr.CUBRID_HOME
        env["CUBRID_DATABASES"] = hr.CUBRID_DATABASES
        cmd = [f"{hr.CUBRID_HOME}/bin/csql", "-u", "dba", hr.CUBRID_DB, "-q", "-N",
               "-c", "drop view revenue0;"]
    else:
        env = dict(os.environ)
        cmd = [f"{hr.PG_HOME}/bin/psql", "-h", hr.PG_SOCKDIR, "-p", hr.PG_PORT,
               "-d", hr.PG_DB, "-Atc", "drop view revenue0;"]
    subprocess.run(cmd, capture_output=True, text=True, env=env, timeout=60)
    return "dropped_stale" if not view_exists(engine) else "STALE_VIEW_REMAINS"


def group_sessions(times):
    """Consume the flat statement-time list in consecutive create/select/drop
    triples. A trailing partial group means the block did not complete."""
    n = len(times) // len(PHASES)
    sessions = []
    for i in range(n):
        tri = times[i * 3:i * 3 + 3]
        sessions.append({
            "create_view_s": tri[0],
            "select_s": tri[1],
            "drop_view_s": tri[2],
            "session_total_s": sum(tri),
        })
    return sessions, len(times) % len(PHASES)


def stats(xs):
    if not xs:
        return {}
    s = sorted(xs)
    mean = sum(xs) / len(xs)
    var = sum((x - mean) ** 2 for x in xs) / (len(xs) - 1) if len(xs) > 1 else 0.0
    return {"median_s": s[len(s) // 2], "mean_s": mean, "stddev_s": var ** 0.5,
            "min_s": s[0], "max_s": s[-1]}


def run(engine, mode, n_sessions, variant="native", create_override=None):
    label = engine if variant == "native" else f"{engine}-{variant}"
    tag = f"{label}-{mode}"
    workdir = os.path.join(hr.RAW_ROOT, "work", QNN)
    sinkdir = os.path.join(workdir, "sink")
    os.makedirs(sinkdir, exist_ok=True)
    sink = os.path.join(sinkdir, f"{QNN}-{label}-{mode}.out")
    block = build_block(engine, workdir, n_sessions, tag, create_override)

    pre_view = force_drop(engine)
    pre_buf = hr.cubrid_buffer_gauges() if engine == "cubrid" else hr.pg_buffer_counters()
    sampler = hr.Sampler(engine)
    sampler.start()
    time.sleep(1.0)
    rc, err, wall = hr.run_block(QNN, engine, workdir, sink, block)
    time.sleep(1.0)
    sampler.stop_flag.set()
    sampler.join(timeout=10)
    post_buf = hr.cubrid_buffer_gauges() if engine == "cubrid" else hr.pg_buffer_counters()
    post_view = "absent" if not view_exists(engine) else "PRESENT_AFTER_BLOCK"

    times = hr.parse_times(engine, sink, err)
    sessions, ragged = group_sessions(times)
    samples_path = os.path.join(workdir, f"{QNN}-{label}-{mode}-samples.json")
    with open(samples_path, "w") as f:
        json.dump(sampler.samples, f)

    out = {
        "campaign_id": hr.CAMPAIGN,
        "qnn": QNN,
        "engine": engine,
        "variant": variant,
        "create_view_override": create_override,
        "pgoptions": os.environ.get("PGOPTIONS", "") if engine == "postgresql" else None,
        "mode": mode,
        "logical_unit": "create view -> select -> drop view (SSOT section 6)",
        "connection_mode": "single-connection-four-sessions" if mode == "headline"
                           else "single-connection-N-sessions (uncounted)",
        "regime": "single-query-repeat WARM",
        "phase_files": phase_files(engine, create_override),
        "block_sql": block,
        "sessions_requested": n_sessions,
        "sessions_parsed": len(sessions),
        "ragged_trailing_statements": ragged,
        "client_exit": rc,
        "client_stderr": err[-2000:],
        "statement_times_all_s": times,
        "sessions": sessions,
        "session_totals_s": [s["session_total_s"] for s in sessions],
        "phase_series_s": {p: [s[f"{p}_s"] for s in sessions] for p in PHASES},
        "block_wall_s": wall,
        "view_state": {"before_block": pre_view, "after_block": post_view},
        "sink": {"path": sink, "bytes": os.path.getsize(sink),
                 "sha256": subprocess.run(["sha256sum", sink], capture_output=True,
                                          text=True).stdout.split()[0]},
        "buffer_counters": {"pre": pre_buf, "post": post_buf},
        "sampler": {
            "path": samples_path,
            "interval_s": hr.SAMPLE_INTERVAL,
            "n_samples": len(sampler.samples),
            "cpus": hr.COLLECTOR_CPUS,
            "engine_cpu_ticks_delta": hr.integrate(sampler.samples, "cpu_ticks"),
            "engine_read_bytes_delta": hr.integrate(sampler.samples, "read_bytes"),
            "engine_rchar_delta": hr.integrate(sampler.samples, "rchar"),
        },
    }

    totals = out["session_totals_s"]
    ok = (rc == 0 and ragged == 0 and post_view == "absent")

    if mode == "warm":
        conv, why = we.converged(totals) if totals else (False, "no session times parsed")
        first_ok = None
        for k in range(2 * we.WINDOW, len(totals) + 1):
            c, _ = we.converged(totals[:k])
            if c:
                first_ok = k
                break
        out.update({
            "stage": "14.4/14.5-warm-establishment (uncounted, never a headline value)",
            "criteria": {"window": we.WINDOW, "level_tol": we.LEVEL_TOL,
                         "spread_sanity": we.SPREAD_SANITY,
                         "gated_on": "session_total_s",
                         "gate": "non-monotone trailing window AND |half-split level "
                                 "drift| <= level_tol AND trailing spread <= spread_sanity"},
            "converged": conv,
            "verdict": why,
            "converged_after_sessions": first_ok,
            "steady_state_median_s": we.median(totals[-we.WINDOW:])
                                     if len(totals) >= we.WINDOW else None,
            "session_total_stats": stats(totals),
            "phase_stats": {p: stats(out["phase_series_s"][p]) for p in PHASES},
        })
        path = os.path.join(workdir, f"{QNN}-{label}-warm.json")
        rc_out = 0 if (ok and conv) else 4
    else:
        measured = totals[1:1 + N_MEASURED]
        out.update({
            "stage": "14.4-cubrid-headline" if engine == "cubrid"
                     else "14.5-postgresql-headline",
            "warmup_session_total_s": totals[0] if totals else None,
            "measured_session_totals_s": measured,
            "measured_sessions": sessions[1:1 + N_MEASURED],
            "headline": {
                "unit": "logical Q15 session (create view + select + drop view)",
                **stats(measured),
            },
            "select_only": stats([s["select_s"] for s in sessions[1:1 + N_MEASURED]]),
            "create_view_only": stats([s["create_view_s"] for s in sessions[1:1 + N_MEASURED]]),
            "drop_view_only": stats([s["drop_view_s"] for s in sessions[1:1 + N_MEASURED]]),
        })
        if measured:
            out["median_s"] = out["headline"]["median_s"]
            out["mean_s"] = out["headline"]["mean_s"]
            out["stddev_s"] = out["headline"]["stddev_s"]
        path = os.path.join(workdir, f"{QNN}-{label}-headline.json")
        rc_out = 0 if (ok and len(measured) == N_MEASURED) else 1

    with open(path, "w") as f:
        json.dump(out, f, indent=2, sort_keys=True)
    print(json.dumps({k: v for k, v in out.items()
                      if k not in ("client_stderr", "statement_times_all_s", "sessions")},
                     indent=2, sort_keys=True))
    return rc_out


def run_hltel(engine, variant="native", create_override=None):
    """Section 14.7 in the section 12 block regime: the identical 4-session block,
    sampled per TID, giving CPU_block and U directly with no attribution rule."""
    label = engine if variant == "native" else f"{engine}-{variant}"
    workdir = os.path.join(hr.RAW_ROOT, "work", QNN)
    sinkdir = os.path.join(workdir, "sink")
    os.makedirs(sinkdir, exist_ok=True)
    sink = os.path.join(sinkdir, f"{QNN}-{label}-headline-telemetry.out")
    block = build_block(engine, workdir, 1 + N_MEASURED, f"{label}-hltel", create_override)

    pre_view = force_drop(engine)
    srv_pat = (f"cub_server {hr.CUBRID_DB}" if engine == "cubrid"
               else f"{hr.PG_HOME}/bin/postgres -D {hr.PG_SOCKDIR}")
    srv_pid = int(subprocess.run(["pgrep", "-f", srv_pat], capture_output=True,
                                 text=True).stdout.split()[0])
    numa_pre = tr.numa(srv_pid)

    sampler = tr.Sampler(engine)
    sampler.start()
    time.sleep(1.0)
    rc, err, wall = hr.run_block(QNN, engine, workdir, sink, block)
    time.sleep(1.0)
    sampler.stop_flag.set()
    sampler.join(timeout=10)
    numa_post = tr.numa(srv_pid)
    post_view = "absent" if not view_exists(engine) else "PRESENT_AFTER_BLOCK"

    times = hr.parse_times(engine, sink, err)
    sessions, ragged = group_sessions(times)
    totals = [x["session_total_s"] for x in sessions]
    measured = totals[1:1 + N_MEASURED]
    t_block = sum(times)

    exec_ticks, aux_ticks, per_bucket, intervals = tr.analyse(sampler.samples)
    w, peak, busy_dt, tail = tr.twu(intervals)
    executor_cpu = exec_ticks / tr.TICKS
    auxiliary_cpu = aux_ticks / tr.TICKS
    cpu_block = executor_cpu + auxiliary_cpu
    u = cpu_block / t_block if t_block else None
    med = sorted(measured)[len(measured) // 2] if measured else None

    out = {
        "campaign_id": hr.CAMPAIGN, "qnn": QNN, "engine": engine, "variant": variant,
        "create_view_override": create_override,
        "pgoptions": os.environ.get("PGOPTIONS", "") if engine == "postgresql" else None,
        "stage": "14.7-execution-telemetry-headline-regime",
        "regime": "single-query-repeat WARM",
        "connection_mode": "single-connection-four-sessions",
        "logical_unit": "create view -> select -> drop view (SSOT section 6)",
        "headline_regime": True,
        "phase_files": phase_files(engine, create_override), "block_sql": block,
        "client_exit": rc, "client_stderr": err[-1500:], "client_wall_s": wall,
        "statement_times_all_s": times,
        "sessions": sessions,
        "session_totals_s": totals,
        "phase_series_s": {ph: [x[f"{ph}_s"] for x in sessions] for ph in PHASES},
        "measured_session_totals_s": measured,
        "median_s": med,
        "t_block_s": t_block,
        "ragged_trailing_statements": ragged,
        "view_state": {"before_block": pre_view, "after_block": post_view},
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
        "per_session_attribution": {
            "rule": "CPU_session = U * session_total_s (constant-utilization attribution)",
            "median_session_cpu_core_s": round(u * med, 4) if (u and med) else None,
            "tested_by": "u_crosscheck against single-session telemetry_run.py U",
        },
        "units": {
            "time_weighted_active_units": round(w, 4) if w else None,
            "max_simultaneous_active_units": round(peak, 4) if peak else None,
            "busy_window_s": round(busy_dt, 3) if busy_dt else None,
            "serial_tail_s": round(tail, 3) if tail is not None else None,
            "weighting": "actual sample timestamp deltas (not nominal interval)",
            "note": "TWU spans the whole 4-session block, including inter-statement gaps",
        },
        "io": {"engine_and_client": tr.io_delta(sampler.samples),
               "device": tr.disk_delta(sampler.samples)},
        "numa": {"pre": numa_pre, "post": numa_post},
        "sink": {"path": sink, "bytes": os.path.getsize(sink),
                 "sha256": subprocess.run(["sha256sum", sink], capture_output=True,
                                          text=True).stdout.split()[0]},
    }
    ipath = os.path.join(workdir, f"{QNN}-{label}-headline-telemetry-intervals.json")
    with open(ipath, "w") as f:
        json.dump(intervals, f)
    out["intervals_path"] = ipath
    path = os.path.join(workdir, f"{QNN}-{label}-headline-telemetry.json")
    with open(path, "w") as f:
        json.dump(out, f, indent=2, sort_keys=True)
    print(json.dumps({k: v for k, v in out.items()
                      if k not in ("numa", "client_stderr", "statement_times_all_s",
                                   "sessions")}, indent=2, sort_keys=True))
    return 0 if (rc == 0 and ragged == 0 and post_view == "absent"
                 and len(measured) == N_MEASURED) else 1


def main():
    if len(sys.argv) not in (3, 4):
        print("usage: q15_session.py warm|headline|hltel cubrid|postgresql [N_WARM_SESSIONS]",
              file=sys.stderr)
        return 2
    mode, engine = sys.argv[1].lower(), sys.argv[2].lower()
    if mode not in ("warm", "headline", "hltel") or engine not in ("cubrid", "postgresql"):
        print("bad mode/engine", file=sys.stderr)
        return 2
    if mode == "hltel":
        return run_hltel(engine, os.environ.get("TPCH_SSPQ_Q15_VARIANT", "native"),
                         os.environ.get("TPCH_SSPQ_Q15_CREATE_FILE") or None)
    if mode == "headline":
        n = 1 + N_MEASURED
    else:
        n = int(sys.argv[3]) if len(sys.argv) > 3 and sys.argv[3] != "-" else int(
            os.environ.get("TPCH_SSPQ_WARM_MAX", "20"))
    variant = os.environ.get("TPCH_SSPQ_Q15_VARIANT", "native")
    create_override = os.environ.get("TPCH_SSPQ_Q15_CREATE_FILE") or None
    return run(engine, mode, n, variant, create_override)


if __name__ == "__main__":
    sys.exit(main())
