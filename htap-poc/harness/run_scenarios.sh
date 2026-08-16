#!/usr/bin/env bash
# Runs every CDC scenario against a running server and captures one dump per
# scenario into htap-poc/dumps/ (the committed P0 evidence).
#
# Prereqs: db_setup.sh done (server running, supplemental_log=1),
#          cdclogdump built (make CUBRID=...).
#
#   CUBRID=$HOME/htap-cdc/CUBRID-11.5-htapcdc PATH=$CUBRID/bin:$PATH ./run_scenarios.sh [dbname]
set -euo pipefail

DB="${1:-htapdb}"
: "${CUBRID:?CUBRID env var required}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
DUMPDIR="$HERE/../dumps"
SCRATCH="$REPO_ROOT/.git_ignored_dir/scratch/htap-dumps"
DUMP="$HERE/cdclogdump"

[ -x "$DUMP" ] || { echo "ERROR: $DUMP not built — run: make -C $HERE CUBRID=\$CUBRID" >&2; exit 1; }
mkdir -p "$DUMPDIR" "$SCRATCH"

run_sql () { # file
    echo "== csql: $(basename "$1")"
    csql -u dba --no-pager -i "$1" "$DB"
}

dump_since () { # t0 outfile [extra cdclogdump args...]
    local t0="$1" out="$2"; shift 2
    sleep 2
    "$DUMP" -d "$DB" -t "$t0" -i 5 "$@" > "$out"
    echo "== dump: $out ($(grep -c '^ITEM' "$out" || true) items)"
}

now () { echo $(( $(date +%s) - 2 )); }

# s00 (DDL/setup) .. s07 — small scenarios, full dumps committed
for s in s00_setup s01_insert_commit s02_insert_rollback s03_update_rollback \
         s05_insert_delete_commit s06_savepoint_partial_rollback s07_trigger_dml; do
    t0=$(now)
    run_sql "$HERE/scenarios/$s.sql"
    dump_since "$t0" "$DUMPDIR/$s.dump"
done

# s04 twice: identical DML, dumped once with all_in_cond=0 and once with =1
# (the second run re-applies the same prices; the changed-image comparison
#  between -a0 and -a1 is what matters, not the values)
t0=$(now)
run_sql "$HERE/scenarios/s04_multi_update_commit.sql"
dump_since "$t0" "$DUMPDIR/s04_multi_update_commit.allincond0.dump" -a 0

t0=$(now)
run_sql "$HERE/scenarios/s04_multi_update_commit.sql"
dump_since "$t0" "$DUMPDIR/s04_multi_update_commit.allincond1.dump" -a 1

# s10 statement failure — needs all_in_cond=1 like the connector; rerun requires
# a fresh db (fixed SKUs collide with a previous run, like the other scenarios)
t0=$(now)
run_sql "$HERE/scenarios/s10_statement_failure.sql"
dump_since "$t0" "$DUMPDIR/s10_statement_failure.dump" -a 1

# s08 large txn — full dump stays in scratch, committed evidence is a
# head+tail excerpt plus event counts
t0=$(now)
run_sql "$HERE/scenarios/s08_large_txn.sql"
dump_since "$t0" "$SCRATCH/s08_large_txn.full.dump" -T 120
{
    echo "# s08_large_txn — excerpt; full dump: .git_ignored_dir/scratch/htap-dumps/s08_large_txn.full.dump"
    echo "# event counts:"
    grep '^ITEM' "$SCRATCH/s08_large_txn.full.dump" | awk '{print $4}' | sort | uniq -c
    echo "# extract rounds:"
    grep -c '^EXTRACT' "$SCRATCH/s08_large_txn.full.dump"
    echo "# ---- head -300 ----"
    head -300 "$SCRATCH/s08_large_txn.full.dump"
    echo "# ---- tail -100 ----"
    tail -100 "$SCRATCH/s08_large_txn.full.dump"
} > "$DUMPDIR/s08_large_txn.excerpt.dump"
echo "== dump: $DUMPDIR/s08_large_txn.excerpt.dump"

echo "ALL SCENARIOS DONE — dumps in $DUMPDIR"
