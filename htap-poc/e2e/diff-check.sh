#!/usr/bin/env bash
# Differential check (#41, keyed full-row digest since #46): compare live
# CUBRID tables against the ClickHouse canonical FINAL views.
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
# D2 (#46 Gate C): the comparison unit is a KEYED FULL-ROW digest — every row
# is serialized collision-free (length-prefixed PK + all columns) and each
# bucket compares the sorted multiset of row serializations. The former
# per-column independent checksums pass value-swap tampering (same column
# multisets, different PK-value pairing) and are demoted to a diagnostic
# printed only when a bucket already mismatches. `--self-test` proves the
# tamper case: keyed digest FAILs it, legacy column checksums pass it.
#
# Exit 0 = 0 mismatch. --quiet suppresses the report (for convergence polling).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CUBRID="${CUBRID:-$HOME/htap-cdc/CUBRID-11.5-htapcdc}"
CUBRID_DATABASES="${CUBRID_DATABASES:-$HOME/htap-cdc/db}"
DB="${DB:-htapdb}"
QUIET=""
[ "${1:-}" = "--quiet" ] && QUIET=yes

if [ "${1:-}" = "--self-test" ]; then
    exec python3 "$HERE/diff_check.py" --self-test
fi

SCRATCH="$HERE/../../.git_ignored_dir/scratch/diffcheck.$$"
mkdir -p "$SCRATCH"
trap 'rm -rf "$SCRATCH"' EXIT

cub_dump () { # $1 = concat select
    # SET TIME ZONE 'UTC': wire v2 (#76/#85) makes TIMESTAMP a true instant, so the
    # ClickHouse side displays UTC digits — TO_CHAR must render in UTC too, not in the
    # server default (Asia/Seoul). DATETIME is zone-less and unaffected.
    env CUBRID="$CUBRID" CUBRID_DATABASES="$CUBRID_DATABASES" PATH="$CUBRID/bin:$PATH" \
        csql -u dba "$DB" -c "SET TIME ZONE 'UTC'; $1" | sed -n "s/^  '\\(.*\\)'[[:space:]]*\$/\\1/p"
}
ch_dump () { podman exec htap-clickhouse clickhouse-client --query "$1"; }

# ---- table specs: name | col:type list | CUBRID dump SQL | CH dump SQL ----
# (NVL on every column: string concat with NULL is NULL in CUBRID)
CUB_ORDER="SELECT NVL(CAST(id AS VARCHAR),'\\N') || '|~|' || NVL(customer,'\\N') || '|~|' || NVL(CAST(amount AS VARCHAR),'\\N') || '|~|' || NVL(TO_CHAR(created_at,'YYYY-MM-DD HH24:MI:SS.FF'),'\\N') FROM t_order"
CH_ORDER="SELECT concat(toString(id),'|~|',ifNull(customer,'\\\\N'),'|~|',ifNull(toString(amount),'\\\\N'),'|~|',ifNull(toString(created_at),'\\\\N')) FROM htap.t_order FORMAT TSVRaw"
CUB_ITEM="SELECT NVL(sku,'\\N') || '|~|' || NVL(CAST(qty AS VARCHAR),'\\N') || '|~|' || NVL(CAST(price AS VARCHAR),'\\N') FROM t_item"
CH_ITEM="SELECT concat(sku,'|~|',ifNull(toString(qty),'\\\\N'),'|~|',ifNull(toString(price),'\\\\N')) FROM htap.t_item FORMAT TSVRaw"

# #58 type corpus: DATE -> epoch days, TIME -> ns of day (int both sides);
# TIMESTAMP has no fraction in CUBRID so '.000' is appended to match
# DateTime64(3); floats are canonicalized host-side (f32/f64 in diff_check.py)
CUB_CORPUS="SELECT NVL(CAST(id AS VARCHAR),'\\N') || '|~|' || NVL(CAST(v_short AS VARCHAR),'\\N') || '|~|' || NVL(CAST(v_bigint AS VARCHAR),'\\N') || '|~|' || NVL(CAST(v_num AS VARCHAR),'\\N') || '|~|' || NVL(CAST(v_num2 AS VARCHAR),'\\N') || '|~|' || NVL(CAST(v_float AS VARCHAR),'\\N') || '|~|' || NVL(CAST(v_double AS VARCHAR),'\\N') || '|~|' || NVL(v_char,'\\N') || '|~|' || NVL(v_varchar,'\\N') || '|~|' || NVL(CAST(v_date - DATE'1970-01-01' AS VARCHAR),'\\N') || '|~|' || NVL(CAST(CAST((HOUR(v_time)*3600+MINUTE(v_time)*60+SECOND(v_time)) AS BIGINT)*1000000000 AS VARCHAR),'\\N') || '|~|' || NVL(TO_CHAR(v_ts,'YYYY-MM-DD HH24:MI:SS') || '.000','\\N') || '|~|' || NVL(TO_CHAR(v_dtm,'YYYY-MM-DD HH24:MI:SS.FF'),'\\N') || '|~|' || NVL(v_enum,'\\N') FROM t_typecorpus"
CH_CORPUS="SELECT concat(toString(id),'|~|',ifNull(toString(v_short),'\\\\N'),'|~|',ifNull(toString(v_bigint),'\\\\N'),'|~|',ifNull(toString(v_num),'\\\\N'),'|~|',ifNull(toString(v_num2),'\\\\N'),'|~|',ifNull(toString(v_float),'\\\\N'),'|~|',ifNull(toString(v_double),'\\\\N'),'|~|',ifNull(v_char,'\\\\N'),'|~|',ifNull(v_varchar,'\\\\N'),'|~|',ifNull(toString(v_date),'\\\\N'),'|~|',ifNull(toString(v_time),'\\\\N'),'|~|',ifNull(toString(v_ts),'\\\\N'),'|~|',ifNull(toString(v_dtm),'\\\\N'),'|~|',ifNull(v_enum,'\\\\N')) FROM htap.t_typecorpus FORMAT TSVRaw"

cub_dump "$CUB_ORDER" > "$SCRATCH/t_order.cub"
ch_dump  "$CH_ORDER"  > "$SCRATCH/t_order.ch"
cub_dump "$CUB_ITEM"  > "$SCRATCH/t_item.cub"
ch_dump  "$CH_ITEM"   > "$SCRATCH/t_item.ch"
cub_dump "$CUB_CORPUS" > "$SCRATCH/t_typecorpus.cub"
ch_dump  "$CH_CORPUS"  > "$SCRATCH/t_typecorpus.ch"

python3 "$HERE/diff_check.py" "$SCRATCH" "${QUIET:-no}"
