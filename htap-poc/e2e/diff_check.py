#!/usr/bin/env python3
"""Keyed full-row differential comparison for diff-check.sh (#46 Gate C).

Usage:
    diff_check.py <scratch-dir> <quiet: yes|no>   # compare <table>.cub vs <table>.ch dumps
    diff_check.py --self-test                     # tamper self-test (no dumps needed)

Comparison unit: per PK-bucket, the sorted multiset of collision-free row
serializations (length-prefixed normalized columns, PK first). Per-column
checksums — the pre-#46 unit, blind to value-swap tampering — survive only as
a diagnostic printed for buckets that already mismatch.
"""
import sys
import hashlib
from decimal import Decimal

NBUCKETS = 8
TABLES = {
    "t_order": ["id:int", "customer:str", "amount:dec", "created_at:dt"],
    "t_item":  ["sku:str", "qty:int", "price:dec"],
    # #58 type corpus — dates dump as epoch days, times as ms-of-day (both int)
    "t_typecorpus": ["id:int", "v_short:int", "v_bigint:int", "v_num:dec",
                     "v_num2:dec", "v_float:f32", "v_double:f64", "v_char:str",
                     "v_varchar:str", "v_date:int", "v_time:int", "v_ts:dt",
                     "v_dtm:dt", "v_enum:str"],
}


def norm(v, t):
    if v == r"\N":
        return v
    if t == "dec":
        s = format(Decimal(v), "f")
        return s.rstrip("0").rstrip(".") if "." in s else s
    # float canonicalization (#58): CUBRID prints FLOAT with 7 significant
    # digits TRUNCATED and DOUBLE with 16 truncated, ClickHouse prints
    # shortest-round-trip — compare TWO digits below the lossier side
    # (truncation, unlike rounding, can push the reparsed value a full ulp
    # off: 1.797693134862315|7 truncated reparses to ...3149, which rounds
    # to ...31 at 15 significant digits while the true value rounds to ...32)
    if t == "f32":
        return f"{float(v):.5e}"
    if t == "f64":
        return f"{float(v):.13e}"
    return v


def serialize(vals):
    # length-prefixed concatenation: unambiguous no matter what the values
    # contain, so two different (PK, columns) pairings can never collide
    return "".join(f"{len(v)}:{v}" for v in vals)


def bucket_of(pk):
    return int(hashlib.md5(pk.encode()).hexdigest(), 16) % NBUCKETS


def load(path, types):
    buckets = {}
    with open(path) as f:
        for line in f:
            line = line.rstrip("\n")
            if not line:
                continue
            cols = line.split("|~|")
            assert len(cols) == len(types), f"{path}: bad row {line!r}"
            vals = [norm(c, t) for c, t in zip(cols, types)]
            buckets.setdefault(bucket_of(vals[0]), []).append(vals)
    return buckets


def row_digest(rows):
    return hashlib.md5("\n".join(sorted(serialize(r) for r in rows)).encode()).hexdigest()


def col_checksum(rows, i):
    return hashlib.md5("\n".join(sorted(r[i] for r in rows)).encode()).hexdigest()


def compare(cub, ch, table, names):
    """Returns (mismatches, diagnostics) for one table."""
    mismatches, diagnostics = [], []
    for b in range(NBUCKETS):
        crows, hrows = cub.get(b, []), ch.get(b, [])
        if len(crows) != len(hrows):
            mismatches.append(f"{table} bucket {b}: row count cubrid={len(crows)} clickhouse={len(hrows)}")
        cd, hd = row_digest(crows), row_digest(hrows)
        if cd != hd:
            mismatches.append(f"{table} bucket {b}: keyed row digest {cd[:8]} != {hd[:8]}")
            for i, col in enumerate(names):
                cs, hs = col_checksum(crows, i), col_checksum(hrows, i)
                mark = "differs" if cs != hs else "IDENTICAL (pairing-only divergence)"
                diagnostics.append(f"{table} bucket {b} column {col}: {mark} ({cs[:8]} vs {hs[:8]})")
    return mismatches, diagnostics


def run_diff(scratch, quiet):
    mismatches, diagnostics = [], []
    for table, spec in TABLES.items():
        names = [s.split(":")[0] for s in spec]
        types = [s.split(":")[1] for s in spec]
        cub = load(f"{scratch}/{table}.cub", types)
        ch = load(f"{scratch}/{table}.ch", types)
        m, d = compare(cub, ch, table, names)
        mismatches += m
        diagnostics += d
        if not quiet:
            nc = sum(len(v) for v in cub.values())
            nh = sum(len(v) for v in ch.values())
            print(f"{table}: cubrid={nc} rows, clickhouse={nh} rows, {NBUCKETS} buckets x keyed full-row digest")
    if mismatches:
        for m in mismatches:
            print(f"MISMATCH: {m}", file=sys.stderr)
        for d in diagnostics:
            print(f"  diag: {d}", file=sys.stderr)
        print(f"DIFF-CHECK: {len(mismatches)} mismatch(es)", file=sys.stderr)
        sys.exit(1)
    if not quiet:
        print("DIFF-CHECK: 0 mismatch")


def self_test():
    """Value-swap tamper: same per-bucket column multisets, different PK-value
    pairing. Must FAIL the keyed digest; the legacy per-column checksums must
    (provably) pass it — that false negative is why #46 replaced them."""
    names = ["sku", "qty", "price"]
    # two distinct PKs that land in the same bucket, so the swap is invisible
    # to any per-bucket column-multiset comparison
    base = "SELF"
    a = f"{base}-0"
    b = next(f"{base}-{i}" for i in range(1, 10000) if bucket_of(f"{base}-{i}") == bucket_of(a) and f"{base}-{i}" != a)
    truth = [[a, "1", "1.5"], [b, "2", "2.5"]]
    tampered = [[a, "2", "1.5"], [b, "1", "2.5"]]  # qty swapped between the rows

    def as_buckets(rows):
        out = {}
        for r in rows:
            out.setdefault(bucket_of(r[0]), []).append(r)
        return out

    # 1. identical sides pass
    m, _ = compare(as_buckets(truth), as_buckets(truth), "selftest", names)
    assert not m, f"identical sides must pass, got {m}"

    # 2. keyed digest catches the value swap
    m, d = compare(as_buckets(truth), as_buckets(tampered), "selftest", names)
    assert m, "value-swap tamper must FAIL the keyed row digest"
    print("tamper caught by keyed digest:")
    for x in m:
        print(f"  {x}")

    # 3. the legacy per-column checksums are blind to it (the pre-#46 hole)
    bkt = bucket_of(a)
    legacy_equal = all(
        col_checksum(as_buckets(truth)[bkt], i) == col_checksum(as_buckets(tampered)[bkt], i)
        for i in range(len(names)))
    assert legacy_equal, "expected the legacy column checksums to pass the tamper (false negative)"
    print("legacy per-column checksums pass the same tamper (false negative reproduced)")
    print("SELF-TEST PASS")


if __name__ == "__main__":
    if sys.argv[1:2] == ["--self-test"]:
        self_test()
    else:
        run_diff(sys.argv[1], sys.argv[2] == "yes")
