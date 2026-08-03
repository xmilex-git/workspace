#!/usr/bin/env python3.11
"""
TPCH-SSPQ implementation campaign (tpch-sspq-impl-r1-20260803) — Q01-Q22 result
canonicalization / comparison primitives. Campaign-local adaptation (section 8-b);
the comparison rules are IMPL-SSOT section 6-b. Legacy header: Q01-Q22 result-equivalence
smoke harness. SSOT.md section 11 correctness gate. Read-only against both
engines except for the Q15 create/drop view statements themselves.
"""
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import campaign_config as cfg  # noqa: E402

REPO = cfg.REPO
QUERIES = cfg.QUERIES
WORK = f"{cfg.RAW_ROOT}/work/smoke"

CUBRID_HOME = cfg.CUBRID_HOME
CUBRID_DATABASES = cfg.CUBRID_DATABASES
CUBRID_BIN = os.path.join(CUBRID_HOME, "bin", "csql")
CUBRID_DB = cfg.CUBRID_DB

PG_BIN = f"{cfg.PG_HOME}/bin/psql"
PG_SOCKDIR = cfg.PG_SOCKDIR
PG_PORT = cfg.PG_PORT
PG_DB = cfg.PG_DB
PG_USER = cfg.PG_USER

TIMEOUT = cfg.TIMEOUT
DELIM = "\x1f"
NULLMARK = "\x02NULL\x02"

DATE_RE = re.compile(r"^(\d{2})/(\d{2})/(\d{4})$")
NUM_RE = re.compile(r"^-?\d+(\.\d+)?([eE][+-]?\d+)?$")


def norm_field_cubrid(raw):
    if raw == "NULL":
        return None
    if len(raw) >= 2 and raw[0] == '"' and raw[-1] == '"':
        raw = raw[1:-1]
    raw = raw.rstrip(" ")
    m = DATE_RE.match(raw)
    if m:
        mm, dd, yyyy = m.groups()
        return f"{yyyy}-{mm}-{dd}"
    return raw


def norm_field_pg(raw):
    if raw == NULLMARK:
        return None
    raw = raw.rstrip(" ")
    return raw


def parse_output(text, engine):
    rows = []
    for line in text.split("\n"):
        if line == "":
            continue
        fields = line.split(DELIM)
        if engine == "cubrid":
            rows.append(tuple(norm_field_cubrid(f) for f in fields))
        else:
            rows.append(tuple(norm_field_pg(f) for f in fields))
    return rows


def run(cmd, env, timeout):
    try:
        p = subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=timeout)
        return p.returncode, p.stdout, p.stderr, False
    except subprocess.TimeoutExpired as e:
        return None, e.stdout or "", e.stderr or "", True


def run_cubrid(sqlfile):
    env = cfg.campaign_env()
    cmd = [
        CUBRID_BIN, "-u", "dba", CUBRID_DB,
        "-q", "-N",
        f"--delimiter={DELIM}", "--enclosure=\"",
        "-i", sqlfile,
    ]
    return run(cmd, env, TIMEOUT)


def run_pg(sqlfile):
    env = dict(os.environ)
    cmd = [
        PG_BIN, "-h", PG_SOCKDIR, "-p", PG_PORT, "-U", PG_USER, "-d", PG_DB,
        "-A", "-t", f"-F{DELIM}", f"-P", f"null={NULLMARK}",
        "-f", sqlfile,
    ]
    return run(cmd, env, TIMEOUT)


def is_numeric_field(a, b):
    return a is not None and b is not None and NUM_RE.match(a) and NUM_RE.match(b)


def fields_equal(a, b):
    if a is None or b is None:
        return a == b
    if a == b:
        return True
    if NUM_RE.match(a) and NUM_RE.match(b):
        try:
            fa, fb = float(a), float(b)
        except ValueError:
            return False
        return abs(fa - fb) <= 1e-12 * max(1.0, abs(fa), abs(fb))
    return False


def rows_equal(a, b):
    if len(a) != len(b):
        return False
    for x, y in zip(a, b):
        if not fields_equal(x, y):
            return False
    return True


SORT_NONE = "\x00"


def sort_key(row):
    return tuple((SORT_NONE if v is None else "\x01" + v) for v in row)


HAS_ORDER_BY_CACHE = {}


def query_has_order_by(sqlfile):
    if sqlfile in HAS_ORDER_BY_CACHE:
        return HAS_ORDER_BY_CACHE[sqlfile]
    with open(sqlfile) as f:
        text = f.read()
    result = bool(re.search(r"order\s+by", text, re.IGNORECASE))
    HAS_ORDER_BY_CACHE[sqlfile] = result
    return result


def compare(qnn, cubrid_rows, pg_rows, ordered):
    if len(cubrid_rows) != len(pg_rows):
        return {
            "status": "mismatch",
            "detail": f"row count mismatch: cubrid={len(cubrid_rows)} postgresql={len(pg_rows)}",
        }
    if ordered:
        c_seq, p_seq = cubrid_rows, pg_rows
    else:
        c_seq = sorted(cubrid_rows, key=sort_key)
        p_seq = sorted(pg_rows, key=sort_key)
    for i, (c_row, p_row) in enumerate(zip(c_seq, p_seq)):
        if not rows_equal(c_row, p_row):
            return {
                "status": "mismatch",
                "detail": f"first differing row at index {i} (ordered={ordered}): cubrid={c_row!r} postgresql={p_row!r}",
            }
    return {"status": "result-equivalent-at-SF10", "detail": f"{len(cubrid_rows)} rows, ordered={ordered}"}


def save(name, text):
    path = os.path.join(WORK, name)
    with open(path, "w") as f:
        f.write(text)
    return path


def run_query_pair(qnn, cubrid_sql, pg_sql, out_prefix):
    ordered = query_has_order_by(cubrid_sql)
    rc_c, out_c, err_c, to_c = run_cubrid(cubrid_sql)
    rc_p, out_p, err_p, to_p = run_pg(pg_sql)
    save(f"{out_prefix}-cubrid.out", out_c)
    save(f"{out_prefix}-postgresql.out", out_p)
    if to_c or to_p:
        detail = []
        if to_c:
            detail.append("cubrid timed out >300s")
        if to_p:
            detail.append("postgresql timed out >300s")
        return {"status": "censored", "detail": "; ".join(detail)}
    if rc_c != 0:
        return {"status": "mismatch", "detail": f"cubrid csql exit={rc_c} stderr={err_c[:500]!r}"}
    if rc_p != 0:
        return {"status": "mismatch", "detail": f"postgresql psql exit={rc_p} stderr={err_p[:500]!r}"}
    cubrid_rows = parse_output(out_c, "cubrid")
    pg_rows = parse_output(out_p, "pg")
    return compare(qnn, cubrid_rows, pg_rows, ordered)


REGULAR_QNNS = [f"q{n}" for n in range(1, 23) if n != 15]


def main():
    os.makedirs(WORK, exist_ok=True)
    summary = {}

    for q in REGULAR_QNNS:
        qnn = f"Q{int(q[1:]):02d}"
        cubrid_sql = os.path.join(QUERIES, f"{q}-cubrid.sql")
        pg_sql = os.path.join(QUERIES, f"{q}-pg.sql")
        print(f"=== {qnn} ===", file=sys.stderr)
        result = run_query_pair(qnn, cubrid_sql, pg_sql, q)
        print(f"{qnn}: {result['status']} — {result['detail']}", file=sys.stderr)
        summary[qnn] = result

    # Q15: create_view -> select -> drop_view, one logical unit per engine
    qnn = "Q15"
    print(f"=== {qnn} ===", file=sys.stderr)

    def cubrid_view_exists():
        cmd_check = [
            CUBRID_BIN, "-u", "dba", CUBRID_DB, "-q", "-N",
            f"--delimiter={DELIM}",
            "-c", "select count(*) from db_class where class_name = 'revenue0';",
        ]
        env = dict(os.environ)
        env["CUBRID"] = CUBRID_HOME
        env["CUBRID_DATABASES"] = CUBRID_DATABASES
        rc, out, err, to = run(cmd_check, env, 30)
        return rc == 0 and out.strip() not in ("0", "")

    def pg_view_exists():
        cmd_check = [
            PG_BIN, "-h", PG_SOCKDIR, "-p", PG_PORT, "-U", PG_USER, "-d", PG_DB,
            "-A", "-t", "-c",
            "select count(*) from information_schema.views where table_name = 'revenue0';",
        ]
        env = dict(os.environ)
        rc, out, err, to = run(cmd_check, env, 30)
        return rc == 0 and out.strip() not in ("0", "")

    pre_c = cubrid_view_exists()
    pre_p = pg_view_exists()
    q15_pre_note = f"pre-create view-exists check: cubrid={pre_c} postgresql={pre_p}"
    print(q15_pre_note, file=sys.stderr)

    if pre_c or pre_p:
        summary[qnn] = {"status": "mismatch", "detail": f"view revenue0 already exists before create: {q15_pre_note}"}
    else:
        cv_rc, cv_out, cv_err, cv_to = run_cubrid(os.path.join(QUERIES, "q15_create_view-cubrid.sql"))
        cv_rc_p, cv_out_p, cv_err_p, cv_to_p = run_pg(os.path.join(QUERIES, "q15_create_view-pg.sql"))
        save("q15_create_view-cubrid.out", cv_out)
        save("q15_create_view-postgresql.out", cv_out_p)
        if cv_to or cv_to_p or cv_rc != 0 or cv_rc_p != 0:
            summary[qnn] = {
                "status": "censored" if (cv_to or cv_to_p) else "mismatch",
                "detail": f"create_view failed: cubrid rc={cv_rc} to={cv_to} err={cv_err[:300]!r}; pg rc={cv_rc_p} to={cv_to_p} err={cv_err_p[:300]!r}",
            }
        else:
            sel_result = run_query_pair(qnn, os.path.join(QUERIES, "q15_select-cubrid.sql"),
                                         os.path.join(QUERIES, "q15_select-pg.sql"), "q15_select")
            dv_rc, dv_out, dv_err, dv_to = run_cubrid(os.path.join(QUERIES, "q15_drop_view-cubrid.sql"))
            dv_rc_p, dv_out_p, dv_err_p, dv_to_p = run_pg(os.path.join(QUERIES, "q15_drop_view-pg.sql"))
            save("q15_drop_view-cubrid.out", dv_out)
            save("q15_drop_view-postgresql.out", dv_out_p)
            post_c = cubrid_view_exists()
            post_p = pg_view_exists()
            drop_note = f"post-drop view-exists check: cubrid={post_c} postgresql={post_p}"
            print(drop_note, file=sys.stderr)
            if post_c or post_p:
                sel_result = {"status": "mismatch", "detail": sel_result.get("detail", "") + f" | DROP VIEW FAILED TO REMOVE VIEW: {drop_note}"}
            summary[qnn] = sel_result

    with open(os.path.join(WORK, "smoke-summary.json"), "w") as f:
        json.dump(summary, f, indent=2, sort_keys=True)

    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
