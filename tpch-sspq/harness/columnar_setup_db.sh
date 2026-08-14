#!/usr/bin/env bash
# Create and load TPC-H SF10 database for columnar verification.
# Runs in SA (standalone) mode — no server needed.
# Usage: columnar_setup_db.sh
set -euo pipefail

export CUBRID=/home/cubrid/release/CUBRID-columnar-rel
export CUBRID_TMP=/tmp
export LD_LIBRARY_PATH="$CUBRID/lib:$CUBRID/cci/lib"
export PATH="$CUBRID/bin:$PATH"

DB_NAME=tpch_col_verify
DB_DIR=/data/tpch-sspq/columnar-verify/db
DB_USER=dba
COMMIT_PERIOD=100000

DATA_DIR=/home/cubrid/dev/cubrid/.vscode/TPC-H/scale10/load_data
SCHEMA_SQL=/home/cubrid/dev/cubrid/.vscode/TPC-H/scale10/create_tpch_table.sql
INDEX_SQL=/home/cubrid/dev/cubrid/.vscode/TPC-H/scale10/create_tpch_index.sql
WORK=/data/tpch-sspq/columnar-verify
LOG="$WORK/setup.log"

TABLES=(region nation part supplier partsupp customer orders lineitem)

mkdir -p "$DB_DIR" "$WORK"
export CUBRID_DATABASES="$DB_DIR"

log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG"; }

# --- Step 1: createdb ---
if [ -f "$DB_DIR/databases.txt" ] && grep -q "$DB_NAME" "$DB_DIR/databases.txt" 2>/dev/null; then
    log "Database $DB_NAME already exists. Checking if tables are loaded..."
    LINEITEM_COUNT=$(echo "SELECT count(*) FROM lineitem;" | csql -S -u $DB_USER $DB_NAME 2>/dev/null | grep -oP '^\s+\K[0-9]+' || echo "0")
    if [ "$LINEITEM_COUNT" -gt 0 ] 2>/dev/null; then
        log "lineitem has $LINEITEM_COUNT rows. Skipping data load."
        # Jump to columnar table creation
        goto_columnar=true
    else
        log "Tables empty or missing. Will load data."
        goto_columnar=false
    fi
else
    log "=== Creating database $DB_NAME ==="
    # databases.txt needs to exist with at least a header
    echo "#db-name	vol-path		db-host		log-path		lob-base-path" > "$DB_DIR/databases.txt"
    cubrid createdb --db-volume-size=512M --log-volume-size=512M \
        -F "$DB_DIR" -L "$DB_DIR" "$DB_NAME" en_US.utf8 2>&1 | tee -a "$LOG"
    log "Database created."
    goto_columnar=false
fi

# --- Step 2: Load schema ---
if [ "$goto_columnar" != "true" ]; then
    log "=== Loading schema ==="
    csql -S -u $DB_USER -i "$SCHEMA_SQL" $DB_NAME 2>&1 | tee -a "$LOG"
    log "Schema loaded."

    # --- Step 3: Load data (SA mode) ---
    log "=== Loading data (SA mode, commit_period=$COMMIT_PERIOD) ==="
    for t in "${TABLES[@]}"; do
        log "  Loading $t..."
        t0=$(date +%s)
        cubrid loaddb -S -u $DB_USER -l -v -c $COMMIT_PERIOD --no-statistics \
            -d "$DATA_DIR/$t.load" -t "$t" $DB_NAME 2>&1 | tail -5 | tee -a "$LOG"
        t1=$(date +%s)
        log "  $t loaded in $((t1-t0))s"
    done
    log "All data loaded."

    # --- Step 4: Create indexes (CS mode) ---
    log "=== Starting server for index creation ==="
    # Need master running for CS mode
    pkill -x cub_master 2>/dev/null || true; sleep 1
    cubrid service start 2>/dev/null || true; sleep 2
    cubrid server start $DB_NAME 2>&1 | tee -a "$LOG"; sleep 3

    log "=== Creating indexes ==="
    csql -u $DB_USER -i "$INDEX_SQL" $DB_NAME 2>&1 | tee -a "$LOG"

    log "=== Updating statistics ==="
    csql -u $DB_USER $DB_NAME -c "UPDATE STATISTICS ON ALL CLASSES;" 2>&1 | tee -a "$LOG"

    # Stop server for SA verification
    cubrid server stop $DB_NAME 2>/dev/null || true; sleep 2
fi

# --- Step 5: Verify row counts (SA mode) ---
log "=== Verifying row counts ==="
for t in "${TABLES[@]}"; do
    COUNT=$(echo "SELECT count(*) FROM $t;" | csql -S -u $DB_USER $DB_NAME 2>/dev/null | grep -oP '^\s+\K[0-9]+' || echo "FAIL")
    log "  $t: $COUNT rows"
done

# --- Step 6: Create columnar lineitem_col ---
log "=== Creating lineitem_col USING COLUMNAR ==="

# Check if it already exists
COL_EXISTS=$(echo "SELECT count(*) FROM db_class WHERE class_name = 'lineitem_col';" | csql -S -u $DB_USER $DB_NAME 2>/dev/null | grep -oP '^\s+\K[0-9]+' || echo "0")
if [ "$COL_EXISTS" -gt 0 ] 2>/dev/null; then
    COL_COUNT=$(echo "SELECT count(*) FROM lineitem_col;" | csql -S -u $DB_USER $DB_NAME 2>/dev/null | grep -oP '^\s+\K[0-9]+' || echo "0")
    if [ "$COL_COUNT" -gt 0 ] 2>/dev/null; then
        log "lineitem_col already exists with $COL_COUNT rows. Skipping."
    else
        log "lineitem_col exists but empty. Dropping..."
        echo "DROP TABLE IF EXISTS lineitem_col;" | csql -S -u $DB_USER $DB_NAME 2>&1 | tee -a "$LOG"
        COL_EXISTS=0
    fi
fi

if [ "$COL_EXISTS" -eq 0 ] 2>/dev/null; then
    cat << 'SQL' | csql -S -u $DB_USER $DB_NAME 2>&1 | tee -a "$LOG"
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
SQL
    log "lineitem_col table created."

    # INSERT SELECT needs CS mode for large datasets
    log "=== Starting server for INSERT SELECT ==="
    pkill -x cub_master 2>/dev/null || true; sleep 1
    cubrid service start 2>/dev/null || true; sleep 2
    cubrid server start $DB_NAME 2>&1 | tee -a "$LOG"; sleep 3

    log "=== INSERT SELECT: lineitem -> lineitem_col (60M rows) ==="
    t0=$(date +%s)
    csql -u $DB_USER $DB_NAME -c "INSERT INTO lineitem_col SELECT * FROM lineitem;" 2>&1 | tee -a "$LOG"
    t1=$(date +%s)
    log "INSERT SELECT completed in $((t1-t0))s"

    # Verify
    COL_COUNT=$(csql -u $DB_USER $DB_NAME -c "SELECT count(*) FROM lineitem_col;" 2>/dev/null | grep -oP '^\s+\K[0-9]+' || echo "FAIL")
    HEAP_COUNT=$(csql -u $DB_USER $DB_NAME -c "SELECT count(*) FROM lineitem;" 2>/dev/null | grep -oP '^\s+\K[0-9]+' || echo "FAIL")
    log "Row counts — heap lineitem: $HEAP_COUNT, columnar lineitem_col: $COL_COUNT"

    if [ "$HEAP_COUNT" = "$COL_COUNT" ]; then
        log "=== Row count match: PASS ==="
    else
        log "=== Row count MISMATCH: FAIL ==="
    fi
fi

log "=== Setup complete ==="
log "Database: $DB_NAME at $DB_DIR"
log "CUBRID: $CUBRID"
log "cubrid_rel: $(cubrid_rel 2>&1)"
