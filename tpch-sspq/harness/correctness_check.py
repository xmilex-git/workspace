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


def main():
    if len(sys.argv) != 2:
        print("usage: correctness_check.py QNN   (e.g. Q01)", file=sys.stderr)
        return 2
    qnn = sys.argv[1].upper()
    n = int(qnn[1:])
    if n == 15:
        print("Q15 is one logical unit (create/select/drop); use smoke_check.py", file=sys.stderr)
        return 2

    q = f"q{n}"
    sc.WORK = f"/data/tpch-sspq/tpch-sspq-fk-r1-20260730/work/{qnn}"
    os.makedirs(sc.WORK, exist_ok=True)

    cubrid_sql = os.path.join(sc.QUERIES, f"{q}-cubrid.sql")
    pg_sql = os.path.join(sc.QUERIES, f"{q}-pg.sql")
    result = sc.run_query_pair(qnn, cubrid_sql, pg_sql, f"{q}-correctness")

    out = {
        "campaign_id": "tpch-sspq-fk-r1-20260730",
        "qnn": qnn,
        "stage": "14.2-correctness-gate",
        "ordered": sc.query_has_order_by(cubrid_sql),
        "cubrid_sql": cubrid_sql,
        "pg_sql": pg_sql,
        "result": result,
    }
    path = os.path.join(sc.WORK, f"{q}-correctness.json")
    with open(path, "w") as f:
        json.dump(out, f, indent=2, sort_keys=True)
    print(json.dumps(out, indent=2, sort_keys=True))
    return 0 if result["status"] == "result-equivalent-at-SF10" else 1


if __name__ == "__main__":
    sys.exit(main())
