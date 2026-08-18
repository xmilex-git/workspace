#!/usr/bin/env bash
# Owner-collision E2E (workspace#69, ADR 0011 D8/D9): capture two SAME-NAMED
# tables under different owners (dba.t_order and app.t_order) in one connector
# and assert each flows to its own topic with its own column set.
#
# Before #69 the driver-metadata schema discovery silently merged the columns
# of same-named tables (getColumns by bare name — ADR 0006 D5's hidden bug);
# the catalog-view discovery (db_attribute owner filter) keeps them distinct.
#
# Prereqs: same as run-e2e.sh (infra up, connector plugin built, htapdb running).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONNECT="${CONNECT_URL:-http://localhost:8083}"
CUBRID="${CUBRID:-$HOME/htap-cdc/CUBRID-11.5-htapcdc}"
CUBRID_DATABASES="${CUBRID_DATABASES:-$HOME/htap-cdc/db}"
DB="${DB:-htapdb}"
APP_TOPIC=htapcdc.app.t_order
DBA_TOPIC=htapcdc.dba.t_order

csql_dba () { # $1 = sql string
    env CUBRID="$CUBRID" CUBRID_DATABASES="$CUBRID_DATABASES" PATH="$CUBRID/bin:$PATH" \
        csql -u dba "$DB" -c "$1"
}
kafka () { podman exec htap-kafka /opt/kafka/bin/"$@"; }

cleanup () {
    echo "== cleanup: back to the standard pipeline state =="
    "$HERE/reset-pipeline.sh" >/dev/null 2>&1 || true
    kafka kafka-topics.sh --bootstrap-server localhost:9092 --delete --topic "$APP_TOPIC" 2>/dev/null || true
    csql_dba "DROP TABLE IF EXISTS app.t_order; DROP USER app;" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "== 0. reset pipeline + create owner 'app' with a same-named t_order =="
"$HERE/reset-pipeline.sh"
kafka kafka-topics.sh --bootstrap-server localhost:9092 --delete --topic "$APP_TOPIC" 2>/dev/null || true
csql_dba "DROP TABLE IF EXISTS app.t_order; DROP USER app;" >/dev/null 2>&1 || true
csql_dba "CREATE USER app;"
# deliberately a DIFFERENT column set from dba.t_order (id, customer, amount, created_at)
csql_dba "CREATE TABLE app.t_order (id INT PRIMARY KEY, note VARCHAR(50), qty INT);"

echo "== 1. seed both owners' tables (snapshot phase input) =="
# pre-registration TRUNCATE: not yet captured (no connector), so no DDL halt
csql_dba "TRUNCATE t_order;"
csql_dba "INSERT INTO t_order VALUES (1, 'alice', 100, DATETIME'2026-08-16 10:00:00.000');"
csql_dba "INSERT INTO app.t_order VALUES (1, 'from-app-owner', 42);"

echo "== 2. register source capturing BOTH owner.table ids =="
CONFIG="$(python3 - "$HERE/cubrid-source.json" <<'PY'
import json, sys
cfg = json.load(open(sys.argv[1]))
cfg["config"]["table.include.list"] = "dba.t_order,dba.t_item,dba.t_typecorpus,app.t_order"
print(json.dumps(cfg))
PY
)"
curl -fsS -X POST -H 'Content-Type: application/json' --data "$CONFIG" "$CONNECT/connectors" >/dev/null
for _ in $(seq 1 60); do
    n="$(podman logs --since 5m htap-connect 2>&1 | grep -cE "CUBRID CDC stream" || true)"
    [ "${n:-0}" -gt 0 ] && break
    sleep 2
done

echo "== 3. stream one change into each owner's table =="
csql_dba "INSERT INTO t_order VALUES (2, 'bob', 20.5, DATETIME'2026-08-16 10:01:00.000');"
csql_dba "INSERT INTO app.t_order VALUES (2, 'app-streamed', 7);"
sleep 10

echo "== 4. assert: each topic carries its own owner's column set =="
dba_msgs="$(kafka kafka-console-consumer.sh --bootstrap-server localhost:9092 \
    --topic "$DBA_TOPIC" --from-beginning --timeout-ms 8000 2>/dev/null || true)"
app_msgs="$(kafka kafka-console-consumer.sh --bootstrap-server localhost:9092 \
    --topic "$APP_TOPIC" --from-beginning --timeout-ms 8000 2>/dev/null || true)"

python3 - <<PY
import json, sys
dba_raw = '''$dba_msgs'''
app_raw = '''$app_msgs'''

def rows(raw):
    out = []
    for line in raw.splitlines():
        line = line.strip()
        if not line or not line.startswith('{'):
            continue
        v = json.loads(line)
        if v is None:
            continue
        out.append(v)
    return out

dba, app = rows(dba_raw), rows(app_raw)
assert len(dba) >= 2, f"dba topic: expected snapshot+stream rows, got {len(dba)}"
assert len(app) >= 2, f"app topic: expected snapshot+stream rows, got {len(app)}"

DBA_COLS = {"id", "customer", "amount", "created_at"}
APP_COLS = {"id", "note", "qty"}
META = {"_op", "_version", "_is_deleted"}
for v in dba:
    cols = set(v) - META
    assert cols == DBA_COLS, f"dba.t_order row has wrong columns: {sorted(cols)}"
for v in app:
    cols = set(v) - META
    assert cols == APP_COLS, f"app.t_order row has wrong columns: {sorted(cols)}"

streamed = [v for v in app if v.get("note") == "app-streamed"]
assert streamed and streamed[0]["qty"] == 7, "app streamed row missing or wrong"
snap = [v for v in app if v.get("note") == "from-app-owner"]
assert snap and snap[0]["qty"] == 42, "app snapshot row missing or wrong"
print(f"OK: dba.t_order {len(dba)} msgs cols={sorted(DBA_COLS)} / app.t_order {len(app)} msgs cols={sorted(APP_COLS)} — no column merge, separate topics")
PY

echo "PASS"
