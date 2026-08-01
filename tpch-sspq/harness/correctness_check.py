#!/usr/bin/env python3.11
"""
TPCH-SSPQ FK campaign (tpch-sspq-fk-r1-20260730) — per-query result-equivalence
gate for the section 14 mandatory pipeline, stage 2.

Reuses the verified comparator in smoke_check.py (section 11 rules: exact ordered
sequence for ORDER BY queries, canonical sort preserving duplicate multiplicity
otherwise, raw decimal text, relative 1e-12 tolerance for output-scale only).

Usage: correctness_check.py Q01
"""
import json
import os
import sys

# cub_master binds ${CUBRID_TMP:-/tmp}/CUBRID<port> (tcp.c css_get_master_domain_path).
# The interactive session environment points CUBRID_TMP at $CUBRID/var/CUBRID_SOCK,
# which makes every client connection fail with -353/-677. Pin it before import.
os.environ["CUBRID_TMP"] = "/tmp"

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import smoke_check as sc  # noqa: E402


def view_exists(engine):
    """SSOT section 11: 'For Q15, prove the view is absent before the query and
    dropped after the query.' Catalog probe, never a SELECT against the view."""
    if engine == "cubrid":
        cmd = [sc.CUBRID_BIN, "-u", "dba", sc.CUBRID_DB, "-q", "-N",
               f"--delimiter={sc.DELIM}",
               "-c", "select count(*) from db_class where class_name = 'revenue0';"]
        env = dict(os.environ)
        env["CUBRID"] = sc.CUBRID_HOME
        env["CUBRID_DATABASES"] = sc.CUBRID_DATABASES
    else:
        cmd = [sc.PG_BIN, "-h", sc.PG_SOCKDIR, "-p", sc.PG_PORT, "-U", sc.PG_USER,
               "-d", sc.PG_DB, "-A", "-t", "-c",
               "select count(*) from information_schema.views "
               "where table_name = 'revenue0';"]
        env = dict(os.environ)
    rc, out, err, to = sc.run(cmd, env, 30)
    if rc != 0 or to:
        raise RuntimeError(f"{engine} view-exists probe failed rc={rc} to={to} {err[:300]!r}")
    return int(out.strip() or "0") > 0


def q15_gate():
    """Q15 is ONE logical query (SSOT section 6): create view -> select -> drop
    view, in one session, on each engine. The comparison itself is the section 11
    comparator applied to the SELECT, bracketed by the mandatory view-absent
    proofs on both sides of the unit."""
    steps = []
    pre = {e: view_exists(e) for e in ("cubrid", "postgresql")}
    steps.append({"step": "pre-create-view-absent", "view_exists": pre})
    if pre["cubrid"] or pre["postgresql"]:
        return {"status": "mismatch",
                "detail": f"view revenue0 already exists before create: {pre}"}, steps

    cv_c = sc.run_cubrid(os.path.join(sc.QUERIES, "q15_create_view-cubrid.sql"))
    cv_p = sc.run_pg(os.path.join(sc.QUERIES, "q15_create_view-pg.sql"))
    sc.save("q15-correctness-create_view-cubrid.out", cv_c[1])
    sc.save("q15-correctness-create_view-postgresql.out", cv_p[1])
    created = {e: view_exists(e) for e in ("cubrid", "postgresql")}
    steps.append({"step": "create-view", "cubrid_rc": cv_c[0], "pg_rc": cv_p[0],
                  "cubrid_timeout": cv_c[3], "pg_timeout": cv_p[3],
                  "view_exists": created})
    if cv_c[3] or cv_p[3]:
        return {"status": "censored", "detail": "create view exceeded 300s"}, steps
    if cv_c[0] != 0 or cv_p[0] != 0 or not (created["cubrid"] and created["postgresql"]):
        return {"status": "mismatch",
                "detail": (f"create_view failed: cubrid rc={cv_c[0]} err={cv_c[2][:300]!r}; "
                           f"pg rc={cv_p[0]} err={cv_p[2][:300]!r}; exists={created}")}, steps

    result = sc.run_query_pair("Q15", os.path.join(sc.QUERIES, "q15_select-cubrid.sql"),
                               os.path.join(sc.QUERIES, "q15_select-pg.sql"),
                               "q15-correctness-select")
    steps.append({"step": "select", "result": dict(result)})

    dv_c = sc.run_cubrid(os.path.join(sc.QUERIES, "q15_drop_view-cubrid.sql"))
    dv_p = sc.run_pg(os.path.join(sc.QUERIES, "q15_drop_view-pg.sql"))
    sc.save("q15-correctness-drop_view-cubrid.out", dv_c[1])
    sc.save("q15-correctness-drop_view-postgresql.out", dv_p[1])
    post = {e: view_exists(e) for e in ("cubrid", "postgresql")}
    steps.append({"step": "post-drop-view-absent", "cubrid_rc": dv_c[0],
                  "pg_rc": dv_p[0], "view_exists": post})
    if post["cubrid"] or post["postgresql"]:
        return {"status": "mismatch",
                "detail": (result.get("detail", "") +
                           f" | DROP VIEW did not remove the view: {post}")}, steps
    return result, steps


def main():
    if len(sys.argv) != 2:
        print("usage: correctness_check.py QNN   (e.g. Q01)", file=sys.stderr)
        return 2
    qnn = sys.argv[1].upper()
    n = int(qnn[1:])
    q = f"q{n}"
    sc.WORK = f"/data/tpch-sspq/tpch-sspq-fk-r1-20260730/work/{qnn}"
    os.makedirs(sc.WORK, exist_ok=True)

    out = {
        "campaign_id": "tpch-sspq-fk-r1-20260730",
        "qnn": qnn,
        "stage": "14.2-correctness-gate",
    }
    if n == 15:
        result, steps = q15_gate()
        cubrid_sql = os.path.join(sc.QUERIES, "q15_select-cubrid.sql")
        out.update({
            "logical_unit": "create view -> select -> drop view (SSOT section 6, "
                            "one logical query in one session)",
            "ordered": sc.query_has_order_by(cubrid_sql),
            "cubrid_sql": [os.path.join(sc.QUERIES, f"q15_{p}-cubrid.sql")
                           for p in ("create_view", "select", "drop_view")],
            "pg_sql": [os.path.join(sc.QUERIES, f"q15_{p}-pg.sql")
                       for p in ("create_view", "select", "drop_view")],
            "view_absence_proof": "db_class (CUBRID) / information_schema.views "
                                  "(PostgreSQL) catalog probe before create and after drop",
            "steps": steps,
            "result": result,
        })
    else:
        cubrid_sql = os.path.join(sc.QUERIES, f"{q}-cubrid.sql")
        pg_sql = os.path.join(sc.QUERIES, f"{q}-pg.sql")
        result = sc.run_query_pair(qnn, cubrid_sql, pg_sql, f"{q}-correctness")
        out.update({
            "ordered": sc.query_has_order_by(cubrid_sql),
            "cubrid_sql": cubrid_sql,
            "pg_sql": pg_sql,
            "result": result,
        })

    path = os.path.join(sc.WORK, f"{q}-correctness.json")
    with open(path, "w") as f:
        json.dump(out, f, indent=2, sort_keys=True)
    print(json.dumps(out, indent=2, sort_keys=True))
    return 0 if result["status"] == "result-equivalent-at-SF10" else 1


if __name__ == "__main__":
    sys.exit(main())
