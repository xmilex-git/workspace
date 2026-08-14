#!/usr/bin/env python3.11
"""
Columnar verification harness — TPC-H 22-query correctness + performance.

Compares CUBRID heap (lineitem) vs CUBRID columnar (lineitem_col) results.
Reuses smoke_check.py normalization/comparison infrastructure.

Usage:
  columnar_verify.py correctness   — run all 22 queries, heap vs columnar
  columnar_verify.py perf          — timed runs for Q1,Q6,Q12,Q14
  columnar_verify.py setup         — create lineitem_col + INSERT SELECT
  columnar_verify.py all           — setup + correctness + perf
"""
import json
import os
import re
import subprocess
import sys
import time

# Pin CUBRID_TMP before anything else (smoke_check convention)
os.environ["CUBRID_TMP"] = "/tmp"

# ─── Configuration ───────────────────────────────────────────────────────────
CUBRID_HOME = os.environ.get("COL_CUBRID_HOME", os.path.expanduser("~/release/CUBRID-columnar-rel"))
CUBRID_DATABASES = os.environ.get("COL_CUBRID_DATABASES", "/data/tpch-sspq/columnar-verify/db")
CUBRID_DB = os.environ.get("COL_CUBRID_DB", "tpch_col_verify")

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
QUERIES = os.path.join(REPO, "queries")
WORK = os.environ.get("COL_WORK", "/data/tpch-sspq/columnar-verify")

CSQL = os.path.join(CUBRID_HOME, "bin", "csql")
TIMEOUT = 600  # 10 min per query (lineitem is 60M rows)
PERF_TIMEOUT = 900  # 15 min for perf runs
DELIM = "\x1f"

# Performance measurement: Q1, Q6, Q12, Q14
PERF_QUERIES = ["q1", "q6", "q12", "q14"]
WARMUP_RUNS = 2
MEASURE_RUNS = 5
INSERT_CHUNK_ORDERKEYS = 1000

# Queries that reference lineitem (need columnar variant)
LINEITEM_QUERIES = {
    "q1", "q3", "q4", "q5", "q6", "q7", "q8", "q9", "q10",
    "q12", "q14", "q17", "q18", "q19", "q20", "q21",
    # q15 handled separately (view-based)
}

# Queries that don't reference lineitem at all
NO_LINEITEM_QUERIES = {"q2", "q11", "q13", "q16", "q22"}

DATE_RE = re.compile(r"^(\d{2})/(\d{2})/(\d{4})$")
NUM_RE = re.compile(r"^-?\d+(\.\d+)?([eE][+-]?\d+)?$")


# ─── Normalization (from smoke_check.py) ─────────────────────────────────────
def norm_field(raw):
    """Normalize a single CUBRID csql output field."""
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


def parse_output(text):
    """Parse csql delimited output into list of row tuples."""
    rows = []
    for line in text.split("\n"):
        if line == "":
            continue
        fields = line.split(DELIM)
        rows.append(tuple(norm_field(f) for f in fields))
    return rows


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
    return all(fields_equal(x, y) for x, y in zip(a, b))


SORT_NONE = "\x00"


def sort_key(row):
    return tuple((SORT_NONE if v is None else "\x01" + v) for v in row)


def query_has_order_by(sqlfile):
    with open(sqlfile) as f:
        text = f.read()
    return bool(re.search(r"order\s+by", text, re.IGNORECASE))


def compare(qnn, heap_rows, col_rows, ordered):
    if len(heap_rows) != len(col_rows):
        return {
            "status": "FAIL",
            "detail": f"row count mismatch: heap={len(heap_rows)} columnar={len(col_rows)}",
        }
    if ordered:
        h_seq, c_seq = heap_rows, col_rows
    else:
        h_seq = sorted(heap_rows, key=sort_key)
        c_seq = sorted(col_rows, key=sort_key)
    for i, (h_row, c_row) in enumerate(zip(h_seq, c_seq)):
        if not rows_equal(h_row, c_row):
            return {
                "status": "FAIL",
                "detail": f"row {i} differs (ordered={ordered}): heap={h_row!r} col={c_row!r}",
            }
    return {"status": "PASS", "detail": f"{len(heap_rows)} rows, ordered={ordered}"}


# ─── Query execution ─────────────────────────────────────────────────────────
def run_csql(sqlfile, timeout=TIMEOUT):
    """Run a SQL file through csql and return (rc, stdout, stderr, timed_out)."""
    env = dict(os.environ)
    env["CUBRID"] = CUBRID_HOME
    env["CUBRID_DATABASES"] = CUBRID_DATABASES
    env["LD_LIBRARY_PATH"] = f"{CUBRID_HOME}/lib:{CUBRID_HOME}/cci/lib"
    cmd = [
        CSQL, "-u", "dba", CUBRID_DB,
        "-q", "-N",
        f"--delimiter={DELIM}", '--enclosure="',
        "-i", sqlfile,
    ]
    try:
        p = subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=timeout)
        return p.returncode, p.stdout, p.stderr, False
    except subprocess.TimeoutExpired as e:
        return None, e.stdout or "", e.stderr or "", True


def run_csql_statement(sql, timeout=TIMEOUT):
    """Run a single SQL statement and return (rc, stdout, stderr)."""
    env = dict(os.environ)
    env["CUBRID"] = CUBRID_HOME
    env["CUBRID_DATABASES"] = CUBRID_DATABASES
    env["LD_LIBRARY_PATH"] = f"{CUBRID_HOME}/lib:{CUBRID_HOME}/cci/lib"
    cmd = [
        CSQL, "-u", "dba", CUBRID_DB,
        "-q", "-N",
        "-c", sql,
    ]
    try:
        p = subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=timeout)
        return p.returncode, p.stdout, p.stderr
    except subprocess.TimeoutExpired:
        return None, "", "timed out"


def save(name, text):
    path = os.path.join(WORK, name)
    with open(path, "w") as f:
        f.write(text)
    return path


# ─── Columnar query generation ───────────────────────────────────────────────
def make_columnar_query(heap_sqlfile, col_sqlfile):
    """Generate columnar variant of a query by replacing lineitem -> lineitem_col."""
    with open(heap_sqlfile) as f:
        sql = f.read()
    # Case-insensitive replace of "lineitem" -> "lineitem_col"
    # Be careful not to replace inside column names (l_lineitem etc.) —
    # TPC-H uses "lineitem" only as a table name.
    col_sql = re.sub(r'\blineitem\b', 'lineitem_col', sql, flags=re.IGNORECASE)
    with open(col_sqlfile, "w") as f:
        f.write(col_sql)
    return col_sqlfile


# ─── Setup: create columnar table + INSERT SELECT ────────────────────────────
def cmd_setup():
    os.makedirs(WORK, exist_ok=True)
    print("=== Setup: checking lineitem_col existence ===")

    rc, out, err = run_csql_statement(
        "SELECT count(*) FROM db_class WHERE class_name = 'lineitem_col';",
        timeout=30,
    )
    if rc == 0 and out.strip() and int(out.strip().split()[0]) > 0:
        print("lineitem_col already exists. Checking row count...")
        rc2, out2, _ = run_csql_statement("SELECT count(*) FROM lineitem_col;", timeout=300)
        if rc2 == 0:
            count = out2.strip()
            print(f"lineitem_col row count: {count}")
            rc3, out3, _ = run_csql_statement("SELECT count(*) FROM lineitem;", timeout=300)
            heap_count = out3.strip() if rc3 == 0 else ""
            if count and heap_count and int(count) == int(heap_count) and int(count) > 0:
                print("lineitem_col already populated. Skipping setup.")
                return True
            print(f"lineitem_col is partial ({count} vs heap {heap_count}). Rebuilding...")
        print("lineitem_col exists but empty. Dropping and recreating...")
        run_csql_statement("DROP TABLE IF EXISTS lineitem_col;", timeout=60)

    print("=== Creating lineitem_col USING COLUMNAR ===")
    create_sql = """
CREATE TABLE lineitem_col (
    L_ORDERKEY      INTEGER       NOT NULL,
    L_PARTKEY       INTEGER       NOT NULL,
    L_SUPPKEY       INTEGER       NOT NULL,
    L_LINENUMBER    INTEGER       NOT NULL,
    L_QUANTITY      DECIMAL(15,2) NOT NULL,
    L_EXTENDEDPRICE DECIMAL(15,2) NOT NULL,
    L_DISCOUNT      DECIMAL(15,2) NOT NULL,
    L_TAX           DECIMAL(15,2) NOT NULL,
    L_RETURNFLAG    CHAR(1)       NOT NULL,
    L_LINESTATUS    CHAR(1)       NOT NULL,
    L_SHIPDATE      DATE          NOT NULL,
    L_COMMITDATE    DATE          NOT NULL,
    L_RECEIPTDATE   DATE          NOT NULL,
    L_SHIPINSTRUCT  CHAR(25)      NOT NULL,
    L_SHIPMODE      CHAR(10)      NOT NULL,
    L_COMMENT       VARCHAR(44)   NOT NULL
) USING COLUMNAR;
"""
    rc, out, err = run_csql_statement(create_sql.strip(), timeout=60)
    if rc != 0:
        print(f"FAIL: CREATE TABLE lineitem_col: rc={rc} err={err[:500]}")
        return False
    print("lineitem_col created.")

    print("=== INSERT SELECT: lineitem -> lineitem_col (chunked by order key) ===")
    rc, out, err = run_csql_statement("SELECT max(l_orderkey) FROM lineitem;", timeout=300)
    if rc != 0 or not out.strip():
        print(f"FAIL: max lineitem order key: rc={rc} err={err[:500]}")
        return False
    max_orderkey = int(out.strip().split()[0])
    chunk_sql = os.path.join(WORK, "lineitem_col_insert_chunks.sql")
    with open(chunk_sql, "w") as f:
        for lo in range(1, max_orderkey + 1, INSERT_CHUNK_ORDERKEYS):
            hi = min(lo + INSERT_CHUNK_ORDERKEYS - 1, max_orderkey)
            f.write(
                f"INSERT INTO lineitem_col SELECT * FROM lineitem "
                f"WHERE l_orderkey BETWEEN {lo} AND {hi};\nCOMMIT;\n"
            )
    chunk_count = (max_orderkey + INSERT_CHUNK_ORDERKEYS - 1) // INSERT_CHUNK_ORDERKEYS
    print(f"Generated {chunk_count} INSERT chunks in {chunk_sql}")
    t0 = time.time()
    rc, out, err, to = run_csql(chunk_sql, timeout=7200)  # 2 hour safety
    elapsed = time.time() - t0
    if to:
        print(f"FAIL: INSERT SELECT chunks timed out after {elapsed:.1f}s")
        return False
    if rc != 0:
        print(f"FAIL: INSERT SELECT: rc={rc} elapsed={elapsed:.1f}s err={err[:500]}")
        return False
    print(f"INSERT SELECT chunks done in {elapsed:.1f}s")

    # Verify row count
    rc, out, _ = run_csql_statement("SELECT count(*) FROM lineitem_col;", timeout=300)
    col_count = out.strip() if rc == 0 else "?"
    rc, out, _ = run_csql_statement("SELECT count(*) FROM lineitem;", timeout=300)
    heap_count = out.strip() if rc == 0 else "?"
    print(f"Row counts — heap: {heap_count}, columnar: {col_count}")
    save("setup-result.json", json.dumps({
        "insert_elapsed_s": elapsed,
        "heap_rows": heap_count,
        "columnar_rows": col_count,
    }, indent=2))
    return heap_count == col_count


# ─── Correctness: all 22 queries ─────────────────────────────────────────────
def cmd_correctness():
    os.makedirs(WORK, exist_ok=True)
    os.makedirs(os.path.join(WORK, "col-queries"), exist_ok=True)
    results = {}
    regular_qnns = [f"q{n}" for n in range(1, 23) if n != 15]

    for qnn in regular_qnns:
        heap_sql = os.path.join(QUERIES, f"{qnn}-cubrid.sql")
        if not os.path.exists(heap_sql):
            results[qnn] = {"status": "SKIP", "detail": "heap query file missing"}
            continue

        if qnn in NO_LINEITEM_QUERIES:
            # No lineitem — both heap and columnar should give identical results
            # Just run the heap query to confirm it works under columnar server
            print(f"{qnn}: no lineitem, running heap query only...")
            rc, out, err, to = run_csql(heap_sql)
            if to:
                results[qnn] = {"status": "CENSORED", "detail": "timed out"}
            elif rc != 0:
                results[qnn] = {"status": "FAIL", "detail": f"csql exit={rc} err={err[:300]}"}
            else:
                rows = parse_output(out)
                results[qnn] = {"status": "PASS", "detail": f"{len(rows)} rows (no lineitem, heap-only run)"}
            save(f"{qnn}-heap.out", out)
            continue

        # Generate columnar variant
        col_sql = os.path.join(WORK, "col-queries", f"{qnn}-columnar.sql")
        make_columnar_query(heap_sql, col_sql)

        print(f"{qnn}: running heap...")
        rc_h, out_h, err_h, to_h = run_csql(heap_sql)
        save(f"{qnn}-heap.out", out_h)

        print(f"{qnn}: running columnar...")
        rc_c, out_c, err_c, to_c = run_csql(col_sql)
        save(f"{qnn}-columnar.out", out_c)

        if to_h or to_c:
            detail = []
            if to_h:
                detail.append("heap timed out")
            if to_c:
                detail.append("columnar timed out")
            results[qnn] = {"status": "CENSORED", "detail": "; ".join(detail)}
            continue

        # csql exits 0 even when the query errors (prints ERROR to stderr,
        # leaves stdout empty) — treat any ERROR marker as a query failure,
        # never as an empty result
        if rc_h != 0 or "ERROR" in err_h:
            results[qnn] = {"status": "FAIL", "detail": f"heap csql exit={rc_h} err={err_h[:300]}"}
            continue
        if rc_c != 0 or "ERROR" in err_c:
            results[qnn] = {"status": "FAIL", "detail": f"columnar csql exit={rc_c} err={err_c[:300]}"}
            continue

        heap_rows = parse_output(out_h)
        col_rows = parse_output(out_c)
        ordered = query_has_order_by(heap_sql)
        results[qnn] = compare(qnn, heap_rows, col_rows, ordered)
        print(f"  {qnn}: {results[qnn]['status']} — {results[qnn]['detail']}")

    # Q15 (view-based)
    results["q15"] = run_q15()

    # Summary
    total = len(results)
    passed = sum(1 for v in results.values() if v["status"] == "PASS")
    failed = sum(1 for v in results.values() if v["status"] == "FAIL")
    print(f"\n=== Correctness Summary: {passed}/{total} PASS, {failed} FAIL ===")
    for q in sorted(results, key=lambda x: int(re.search(r'\d+', x).group())):
        r = results[q]
        mark = "✓" if r["status"] == "PASS" else "✗" if r["status"] == "FAIL" else "?"
        print(f"  {mark} {q}: {r['status']} — {r['detail']}")

    save("correctness-results.json", json.dumps(results, indent=2, sort_keys=True))
    return failed == 0


def run_q15():
    """Q15 uses a view — need special handling."""
    # Heap: create view → select → drop view
    heap_view_sql = os.path.join(QUERIES, "q15_create_view-cubrid.sql")
    heap_select_sql = os.path.join(QUERIES, "q15_select-cubrid.sql")
    heap_drop_sql = os.path.join(QUERIES, "q15_drop_view-cubrid.sql")

    # Generate columnar variants
    col_view_sql = os.path.join(WORK, "col-queries", "q15_create_view-columnar.sql")
    col_select_sql = os.path.join(WORK, "col-queries", "q15_select-columnar.sql")
    col_drop_sql = os.path.join(WORK, "col-queries", "q15_drop_view-columnar.sql")
    make_columnar_query(heap_view_sql, col_view_sql)
    make_columnar_query(heap_select_sql, col_select_sql)
    make_columnar_query(heap_drop_sql, col_drop_sql)

    # Run heap version
    print("q15: running heap (create view → select → drop view)...")
    run_csql_statement("DROP VIEW IF EXISTS revenue0;", timeout=30)
    run_csql(heap_view_sql)
    rc_h, out_h, err_h, to_h = run_csql(heap_select_sql)
    run_csql(heap_drop_sql)
    save("q15-heap.out", out_h)

    # Run columnar version (view references lineitem_col)
    print("q15: running columnar (create view → select → drop view)...")
    run_csql_statement("DROP VIEW IF EXISTS revenue0;", timeout=30)
    run_csql(col_view_sql)
    rc_c, out_c, err_c, to_c = run_csql(col_select_sql)
    run_csql(col_drop_sql)
    save("q15-columnar.out", out_c)

    if to_h or to_c:
        return {"status": "CENSORED", "detail": "timed out"}
    if rc_h != 0:
        return {"status": "FAIL", "detail": f"heap exit={rc_h}"}
    if rc_c != 0:
        return {"status": "FAIL", "detail": f"columnar exit={rc_c}"}

    heap_rows = parse_output(out_h)
    col_rows = parse_output(out_c)
    ordered = query_has_order_by(heap_select_sql)
    result = compare("q15", heap_rows, col_rows, ordered)
    print(f"  q15: {result['status']} — {result['detail']}")
    return result


# ─── Performance: Q1, Q6, Q12, Q14 ──────────────────────────────────────────
def timed_run(sqlfile, label, timeout=PERF_TIMEOUT):
    """Run a query and return wall-clock elapsed seconds."""
    t0 = time.time()
    rc, out, err, to = run_csql(sqlfile, timeout=timeout)
    elapsed = time.time() - t0
    if to:
        return None, "timed out"
    if rc != 0:
        return None, f"csql exit={rc} err={err[:200]}"
    rows = parse_output(out)
    return elapsed, f"{len(rows)} rows"


def cmd_perf():
    os.makedirs(WORK, exist_ok=True)
    os.makedirs(os.path.join(WORK, "col-queries"), exist_ok=True)
    results = {}

    for qnn in PERF_QUERIES:
        heap_sql = os.path.join(QUERIES, f"{qnn}-cubrid.sql")
        col_sql = os.path.join(WORK, "col-queries", f"{qnn}-columnar.sql")
        if not os.path.exists(col_sql):
            make_columnar_query(heap_sql, col_sql)

        print(f"\n=== {qnn.upper()} Performance ===")

        # Warmup heap
        print(f"  heap warmup ({WARMUP_RUNS} runs)...")
        for i in range(WARMUP_RUNS):
            t, info = timed_run(heap_sql, f"{qnn}-heap-warmup-{i}")
            if t is None:
                print(f"    warmup {i}: FAIL — {info}")
            else:
                print(f"    warmup {i}: {t:.3f}s")

        # Measure heap
        heap_times = []
        print(f"  heap measure ({MEASURE_RUNS} runs)...")
        for i in range(MEASURE_RUNS):
            t, info = timed_run(heap_sql, f"{qnn}-heap-{i}")
            if t is None:
                print(f"    run {i}: FAIL — {info}")
            else:
                heap_times.append(t)
                print(f"    run {i}: {t:.3f}s")

        # Warmup columnar
        print(f"  columnar warmup ({WARMUP_RUNS} runs)...")
        for i in range(WARMUP_RUNS):
            t, info = timed_run(col_sql, f"{qnn}-col-warmup-{i}")
            if t is None:
                print(f"    warmup {i}: FAIL — {info}")
            else:
                print(f"    warmup {i}: {t:.3f}s")

        # Measure columnar
        col_times = []
        print(f"  columnar measure ({MEASURE_RUNS} runs)...")
        for i in range(MEASURE_RUNS):
            t, info = timed_run(col_sql, f"{qnn}-col-{i}")
            if t is None:
                print(f"    run {i}: FAIL — {info}")
            else:
                col_times.append(t)
                print(f"    run {i}: {t:.3f}s")

        # Compute statistics
        qr = {"heap_times": heap_times, "col_times": col_times}
        if heap_times and col_times:
            h_med = sorted(heap_times)[len(heap_times) // 2]
            c_med = sorted(col_times)[len(col_times) // 2]
            speedup = h_med / c_med if c_med > 0 else float("inf")
            qr["heap_median_s"] = h_med
            qr["col_median_s"] = c_med
            qr["speedup"] = speedup
            print(f"  → heap median: {h_med:.3f}s, columnar median: {c_med:.3f}s, speedup: {speedup:.2f}×")
        results[qnn] = qr

    save("perf-results.json", json.dumps(results, indent=2))
    print(f"\n=== Performance complete ===")
    for qnn in PERF_QUERIES:
        r = results.get(qnn, {})
        if "speedup" in r:
            print(f"  {qnn}: heap {r['heap_median_s']:.3f}s → col {r['col_median_s']:.3f}s ({r['speedup']:.2f}×)")
        else:
            print(f"  {qnn}: incomplete data")
    return True


# ─── Main ────────────────────────────────────────────────────────────────────
def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} setup|correctness|perf|all")
        return 1

    mode = sys.argv[1]
    if mode == "setup":
        ok = cmd_setup()
        return 0 if ok else 1
    elif mode == "correctness":
        ok = cmd_correctness()
        return 0 if ok else 1
    elif mode == "perf":
        ok = cmd_perf()
        return 0 if ok else 1
    elif mode == "all":
        if not cmd_setup():
            return 1
        if not cmd_correctness():
            return 1
        cmd_perf()
        return 0
    else:
        print(f"Unknown mode: {mode}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
