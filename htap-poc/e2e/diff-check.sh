#!/usr/bin/env bash
# Differential check (#41): compare live CUBRID tables against the ClickHouse
# canonical FINAL views — per-range row counts + per-column checksums.
#
# Both sides are dumped as one canonical string per row ('|~|' separated,
# '\N' for NULL) and compared host-side in a single normalizer:
#   - decimals: trailing-zero-stripped fixed notation (CUBRID '100.0000' vs
#     ClickHouse '100' must hash equal)
#   - datetimes: both sides already render 'YYYY-MM-DD HH:MM:SS.mmm'
#   - ranges: md5(pk) % 8 buckets (uniform for INT and VARCHAR PKs)
# D1: checksums are computed host-side, not in-engine — the engines' hash
# functions differ, a single normalizer guarantees identical canonicalization,
# and POC tables are tiny. At scale, swap the dump for engine-side hashing.
#
# Exit 0 = 0 mismatch. --quiet suppresses the report (for convergence polling).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CUBRID="${CUBRID:-$HOME/htap-cdc/CUBRID-11.5-htapcdc}"
CUBRID_DATABASES="${CUBRID_DATABASES:-$HOME/htap-cdc/db}"
DB="${DB:-htapdb}"
QUIET=""
[ "${1:-}" = "--quiet" ] && QUIET=yes

SCRATCH="$HERE/../../.git_ignored_dir/scratch/diffcheck.$$"
mkdir -p "$SCRATCH"
trap 'rm -rf "$SCRATCH"' EXIT

cub_dump () { # $1 = concat select
    env CUBRID="$CUBRID" CUBRID_DATABASES="$CUBRID_DATABASES" PATH="$CUBRID/bin:$PATH" \
        csql -u dba "$DB" -c "$1" | sed -n "s/^  '\\(.*\\)'[[:space:]]*\$/\\1/p"
}
ch_dump () { podman exec htap-clickhouse clickhouse-client --query "$1"; }

# ---- table specs: name | col:type list | CUBRID dump SQL | CH dump SQL ----
# (NVL on every column: string concat with NULL is NULL in CUBRID)
CUB_ORDER="SELECT NVL(CAST(id AS VARCHAR),'\\N') || '|~|' || NVL(customer,'\\N') || '|~|' || NVL(CAST(amount AS VARCHAR),'\\N') || '|~|' || NVL(TO_CHAR(created_at,'YYYY-MM-DD HH24:MI:SS.FF'),'\\N') FROM t_order"
CH_ORDER="SELECT concat(toString(id),'|~|',ifNull(customer,'\\\\N'),'|~|',ifNull(toString(amount),'\\\\N'),'|~|',ifNull(toString(created_at),'\\\\N')) FROM htap.t_order FORMAT TSVRaw"
CUB_ITEM="SELECT NVL(sku,'\\N') || '|~|' || NVL(CAST(qty AS VARCHAR),'\\N') || '|~|' || NVL(CAST(price AS VARCHAR),'\\N') FROM t_item"
CH_ITEM="SELECT concat(sku,'|~|',ifNull(toString(qty),'\\\\N'),'|~|',ifNull(toString(price),'\\\\N')) FROM htap.t_item FORMAT TSVRaw"

cub_dump "$CUB_ORDER" > "$SCRATCH/t_order.cub"
ch_dump  "$CH_ORDER"  > "$SCRATCH/t_order.ch"
cub_dump "$CUB_ITEM"  > "$SCRATCH/t_item.cub"
ch_dump  "$CH_ITEM"   > "$SCRATCH/t_item.ch"

python3 - "$SCRATCH" "${QUIET:-no}" <<'PYEOF'
import sys, hashlib
from decimal import Decimal

scratch, quiet = sys.argv[1], sys.argv[2] == "yes"
NBUCKETS = 8
TABLES = {
    "t_order": ["id:int", "customer:str", "amount:dec", "created_at:dt"],
    "t_item":  ["sku:str", "qty:int", "price:dec"],
}

def norm(v, t):
    if v == r"\N":
        return v
    if t == "dec":
        s = format(Decimal(v), "f")
        return s.rstrip("0").rstrip(".") if "." in s else s
    return v

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
            b = int(hashlib.md5(vals[0].encode()).hexdigest(), 16) % NBUCKETS
            buckets.setdefault(b, []).append(vals)
    return buckets

mismatches = []
for table, spec in TABLES.items():
    names = [s.split(":")[0] for s in spec]
    types = [s.split(":")[1] for s in spec]
    cub = load(f"{scratch}/{table}.cub", types)
    ch = load(f"{scratch}/{table}.ch", types)
    for b in range(NBUCKETS):
        crows, hrows = cub.get(b, []), ch.get(b, [])
        if len(crows) != len(hrows):
            mismatches.append(f"{table} bucket {b}: row count cubrid={len(crows)} clickhouse={len(hrows)}")
        for i, col in enumerate(names):
            cs = hashlib.md5("\n".join(sorted(r[i] for r in crows)).encode()).hexdigest()
            hs = hashlib.md5("\n".join(sorted(r[i] for r in hrows)).encode()).hexdigest()
            if cs != hs:
                mismatches.append(f"{table} bucket {b} column {col}: checksum {cs[:8]} != {hs[:8]}")
    if not quiet:
        nc = sum(len(v) for v in cub.values())
        nh = sum(len(v) for v in ch.values())
        print(f"{table}: cubrid={nc} rows, clickhouse={nh} rows, {NBUCKETS} buckets x {len(names)} column checksums")

if mismatches:
    for m in mismatches:
        print(f"MISMATCH: {m}", file=sys.stderr)
    print(f"DIFF-CHECK: {len(mismatches)} mismatch(es)", file=sys.stderr)
    sys.exit(1)
if not quiet:
    print("DIFF-CHECK: 0 mismatch")
PYEOF
