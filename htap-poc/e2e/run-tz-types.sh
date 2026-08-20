#!/usr/bin/env bash
# TZ-family e2e (workspace#86 / #76-D3): TIMESTAMPTZ/TIMESTAMPLTZ/DATETIMETZ/DATETIMELTZ
# through snapshot + streaming + ClickHouse sink.
#   (1) snapshot rows carry wire-v2-shaped ISO instants (TO_CHAR projection),
#       offsets preserved (TZ) / UTC-rendered (LTZ), region zones resolved to
#       the effective numeric offset by the engine (DST included),
#   (2) streaming rows of the SAME source values are byte-identical to their
#       snapshot twins (snapshot/streaming parity),
#   (3) ClickHouse DateTime64(3,'UTC') + best_effort stores the true instant —
#       differing offsets of the same instant converge to one epoch.
#
# Prereqs: infra up (../infra/up.sh), connector plugin built (build-connector.sh),
# htapdb server (wire v2 engine) + broker running.
# Uses its own connector instances + topic prefix; does not disturb cubrid-source-poc.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONNECT="${CONNECT_URL:-http://localhost:8083}"
CUBRID="${HTAP_CUBRID:-$HOME/htap-cdc/CUBRID-11.5-htapcdc-prv}"
CUBRID_DATABASES="${CUBRID_DATABASES:-/home/cubrid/CUBRID/databases}"
DB="${DB:-htapdb}"
NAME=cubrid-source-tz86
SINK=clickhouse-sink-tz86
PREFIX=htaptz86
TABLE=t_tz86
TOPIC="$PREFIX.dba.$TABLE"

csql_c () { # $1 = sql text
    env CUBRID="$CUBRID" CUBRID_DATABASES="$CUBRID_DATABASES" PATH="$CUBRID/bin:$PATH" \
        csql -u dba "$DB" -c "$1"
}
task_state () {
    curl -fsS "$CONNECT/connectors/$NAME/status" \
        | python3 -c "import json,sys;t=json.load(sys.stdin)['tasks'];print(t[0]['state'] if t else 'PENDING')"
}
task_trace () {
    curl -fsS "$CONNECT/connectors/$NAME/status" \
        | python3 -c "import json,sys;print(json.load(sys.stdin)['tasks'][0].get('trace',''))"
}
KAFKA_BIN=/opt/kafka/bin
consume () { # full topic contents (value JSON, one per line)
    podman exec htap-kafka "$KAFKA_BIN/kafka-console-consumer.sh" --bootstrap-server localhost:19092 \
        --topic "$TOPIC" --from-beginning --timeout-ms 5000 2>/dev/null || true
}
ch () { podman exec htap-clickhouse clickhouse-client --query "$1"; }
wait_task () { # $1 = wanted state, $2 = tries (2s apart)
    for _ in $(seq 1 "$2"); do
        [ "$(task_state)" = "$1" ] && return 0
        sleep 2
    done
    return 1
}
wait_msg () { # $1 = grep pattern, $2 = tries
    for _ in $(seq 1 "$2"); do
        if consume | grep -q "$1"; then return 0; fi
        sleep 2
    done
    return 1
}

echo "== 0a. CDC session is single-consumer (cdc_Gl.conn) — stop other source connectors =="
MAIN=cubrid-source-poc
MAIN_WAS_RUNNING=""
if curl -fsS "$CONNECT/connectors/$MAIN/status" 2>/dev/null \
        | python3 -c 'import json,sys;s=json.load(sys.stdin);exit(0 if s["connector"]["state"]=="RUNNING" else 1)' 2>/dev/null; then
    MAIN_WAS_RUNNING=yes
    curl -fsS -X PUT "$CONNECT/connectors/$MAIN/stop" >/dev/null
    echo "stopped $MAIN for the duration of this test"
fi
restore_main () {
    if [ -n "$MAIN_WAS_RUNNING" ]; then
        curl -fsS -X PUT "$CONNECT/connectors/$MAIN/resume" >/dev/null 2>&1 || true
        echo "resumed $MAIN"
    fi
}
trap restore_main EXIT

echo "== 0. cleanup previous run (stop -> delete offsets -> delete, ADR 0004) =="
for C in "$NAME" "$SINK"; do
    if curl -fsS "$CONNECT/connectors/$C" >/dev/null 2>&1; then
        curl -fsS -X PUT "$CONNECT/connectors/$C/stop" >/dev/null || true
        for _ in $(seq 1 15); do
            st="$(curl -fsS "$CONNECT/connectors/$C/status" | python3 -c 'import json,sys;print(json.load(sys.stdin)["connector"]["state"])' 2>/dev/null || echo '')"
            [ "$st" = STOPPED ] && break
            sleep 2
        done
        curl -fsS -X DELETE "$CONNECT/connectors/$C/offsets" >/dev/null 2>&1 || true
        curl -fsS -X DELETE "$CONNECT/connectors/$C" >/dev/null 2>&1 || true
    fi
done
podman exec htap-kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:19092 \
    --delete --topic "$TOPIC" >/dev/null 2>&1 || true
ch "DROP TABLE IF EXISTS htap.${TABLE}_local"
csql_c "DROP TABLE IF EXISTS $TABLE" >/dev/null

echo "== 1. seed: snapshot rows — numeric offsets, region zones (DST summer), epoch floor, NULLs =="
csql_c "CREATE TABLE $TABLE (
          id INT PRIMARY KEY,
          v_tstz  TIMESTAMPTZ,
          v_tsltz TIMESTAMPLTZ,
          v_dttz  DATETIMETZ,
          v_dtltz DATETIMELTZ)" >/dev/null
csql_c "GRANT SELECT ON $TABLE TO cdc_e2e" >/dev/null
csql_c "INSERT INTO $TABLE VALUES
  (1, TIMESTAMPTZ'2026-01-02 03:04:05 +09:00', TIMESTAMPLTZ'2026-01-02 03:04:05 +09:00',
      DATETIMETZ'2026-01-02 03:04:05.670 +09:00', DATETIMELTZ'2026-01-02 03:04:05.670 +09:00'),
  (2, TIMESTAMPTZ'2026-06-15 12:00:00 Asia/Seoul', TIMESTAMPLTZ'2026-06-15 12:00:00 Asia/Seoul',
      DATETIMETZ'2026-06-15 12:00:00.123 America/New_York', DATETIMELTZ'2026-06-15 12:00:00.123 America/New_York'),
  (3, TIMESTAMPTZ'1970-01-01 00:00:01 +00:00', TIMESTAMPLTZ'1970-01-01 00:00:01 +00:00',
      DATETIMETZ'1970-01-01 00:00:00.001 -05:30', DATETIMELTZ'1970-01-01 00:00:00.001 -05:30'),
  (4, NULL, NULL, NULL, NULL)" >/dev/null
sleep 3   # keep the seed out of the second-resolution barrier replay window (ADR 0006)

echo "== 2. register dedicated source connector (include=dba.$TABLE, prod SMT chain) =="
python3 - "$HERE/cubrid-source.json" <<EOF | curl -fsS -X PUT -H 'Content-Type: application/json' -d @- "$CONNECT/connectors/$NAME/config" >/dev/null
import json, sys
cfg = json.load(open(sys.argv[1]))["config"]
cfg.update({
    "topic.prefix": "$PREFIX",
    "table.include.list": "dba.$TABLE",
})
print(json.dumps(cfg))
EOF

echo "== 3. snapshot values are wire-v2-shaped ISO instants =="
wait_task RUNNING 30 || { echo "FAIL: task never RUNNING"; task_trace; exit 1; }
wait_msg '"id":4' 30 || { echo "FAIL: snapshot rows missing on $TOPIC"; task_trace; exit 1; }
SNAP="$(consume)"
expect_snap () { # $1 = id, $2 = exact fragment
    echo "$SNAP" | grep "\"id\":$1," | grep -qF "$2" \
        || { echo "FAIL: snapshot id=$1 missing fragment $2"; echo "$SNAP" | grep "\"id\":$1,"; exit 1; }
}
expect_snap 1 '"v_tstz":"2026-01-02T03:04:05+09:00"'
expect_snap 1 '"v_tsltz":"2026-01-01T18:04:05Z"'
expect_snap 1 '"v_dttz":"2026-01-02T03:04:05.670+09:00"'
expect_snap 1 '"v_dtltz":"2026-01-01T18:04:05.670Z"'
expect_snap 2 '"v_tstz":"2026-06-15T12:00:00+09:00"'
expect_snap 2 '"v_tsltz":"2026-06-15T03:00:00Z"'
expect_snap 2 '"v_dttz":"2026-06-15T12:00:00.123-04:00"'   # America/New_York in June = EDT, engine-resolved
expect_snap 2 '"v_dtltz":"2026-06-15T16:00:00.123Z"'
expect_snap 3 '"v_tstz":"1970-01-01T00:00:01Z"'
expect_snap 3 '"v_dttz":"1970-01-01T00:00:00.001-05:30"'
expect_snap 4 '"v_tstz":null'
echo "OK: snapshot offsets preserved (TZ), UTC-rendered (LTZ), DST resolved, NULLs null"

echo "== 4. streaming twins (ids +10, same source values) are byte-identical to snapshot =="
csql_c "INSERT INTO $TABLE VALUES
  (11, TIMESTAMPTZ'2026-01-02 03:04:05 +09:00', TIMESTAMPLTZ'2026-01-02 03:04:05 +09:00',
       DATETIMETZ'2026-01-02 03:04:05.670 +09:00', DATETIMELTZ'2026-01-02 03:04:05.670 +09:00'),
  (12, TIMESTAMPTZ'2026-06-15 12:00:00 Asia/Seoul', TIMESTAMPLTZ'2026-06-15 12:00:00 Asia/Seoul',
       DATETIMETZ'2026-06-15 12:00:00.123 America/New_York', DATETIMELTZ'2026-06-15 12:00:00.123 America/New_York'),
  (13, TIMESTAMPTZ'1970-01-01 00:00:01 +00:00', TIMESTAMPLTZ'1970-01-01 00:00:01 +00:00',
       DATETIMETZ'1970-01-01 00:00:00.001 -05:30', DATETIMELTZ'1970-01-01 00:00:00.001 -05:30'),
  (14, NULL, NULL, NULL, NULL)" >/dev/null
wait_msg '"id":14' 30 || { echo "FAIL: streaming rows missing"; task_trace; exit 1; }
PARITY_PY=$(cat <<'EOF'
import json, sys
rows = {}
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    r = json.loads(line)
    if isinstance(r, dict) and "id" in r:
        rows[r["id"]] = r
cols = ["v_tstz", "v_tsltz", "v_dttz", "v_dtltz"]
bad = 0
for snap_id in (1, 2, 3, 4):
    s, t = rows.get(snap_id), rows.get(snap_id + 10)
    if s is None or t is None:
        print(f"FAIL: missing row pair {snap_id}/{snap_id+10}"); bad += 1; continue
    for c in cols:
        if s[c] != t[c]:
            print(f"FAIL: parity {c} id={snap_id} snapshot={s[c]!r} vs streaming={t[c]!r}"); bad += 1
sys.exit(1 if bad else 0)
EOF
)
consume | python3 -c "$PARITY_PY" || exit 1
echo "OK: snapshot/streaming parity — identical JSON per column for all 4 value rows"

echo "== 5. streaming UPDATE (NULL -> value) decodes =="
csql_c "UPDATE $TABLE SET v_dtltz = DATETIMELTZ'2299-12-31 23:59:59.999 +00:00' WHERE id = 14" >/dev/null
wait_msg '"v_dtltz":"2299-12-31T23:59:59.999Z"' 30 || { echo "FAIL: TZ update missing"; task_trace; exit 1; }
[ "$(task_state)" = RUNNING ] || { echo "FAIL: task not RUNNING after TZ traffic"; task_trace; exit 1; }
echo "OK: streaming UPDATE on TZ column"

echo "== 6. ClickHouse sink: DateTime64(3,'UTC') + best_effort stores the true instant =="
ch "CREATE TABLE htap.${TABLE}_local (
      id          Int32,
      v_tstz      Nullable(DateTime64(3, 'UTC')),
      v_tsltz     Nullable(DateTime64(3, 'UTC')),
      v_dttz      Nullable(DateTime64(3, 'UTC')),
      v_dtltz     Nullable(DateTime64(3, 'UTC')),
      _op         LowCardinality(String),
      _version    UInt64,
      _is_deleted Bool
   ) ENGINE = ReplacingMergeTree(_version, _is_deleted) ORDER BY id"
python3 - "$HERE/../sink/clickhouse-sink.json" <<EOF | curl -fsS -X PUT -H 'Content-Type: application/json' -d @- "$CONNECT/connectors/$SINK/config" >/dev/null
import json, sys
cfg = json.load(open(sys.argv[1]))["config"]
cfg.update({
    "topics": "$TOPIC",
    "topic2TableMap": "$TOPIC=${TABLE}_local",
})
print(json.dumps(cfg))
EOF
for _ in $(seq 1 30); do
    n="$(ch "SELECT count() FROM htap.${TABLE}_local FINAL" 2>/dev/null || echo 0)"
    [ "${n:-0}" -ge 8 ] && break
    sleep 2
done
[ "${n:-0}" -ge 8 ] || { echo "FAIL: ClickHouse rows never arrived (count=$n)"; exit 1; }
# same instant, different offsets: TZ column (+09:00 / -04:00 / -05:30 text) and its LTZ
# twin (Z text) must land on the same epoch; expected epochs are the engine-side truths
CH_PY=$(cat <<'EOF'
import sys
expect = {
    1: (1767290645000, 1767290645000, 1767290645670, 1767290645670),
    2: (1781492400000, 1781492400000, 1781539200123, 1781539200123),
    3: (1000, 1000, 19800001, 19800001),
}
bad = 0
seen = set()
for line in sys.stdin:
    f = line.split()
    if not f:
        continue
    rid = int(f[0]); seen.add(rid)
    got = tuple(int(x) for x in f[1:5])
    if got != expect[rid]:
        print(f"FAIL: CH instants id={rid} got={got} want={expect[rid]}"); bad += 1
missing = set(expect) - seen
if missing:
    print(f"FAIL: CH rows missing: {sorted(missing)}"); bad += 1
sys.exit(1 if bad else 0)
EOF
)
ch "SELECT id,
           toUnixTimestamp64Milli(v_tstz)  AS tstz,
           toUnixTimestamp64Milli(v_tsltz) AS tsltz,
           toUnixTimestamp64Milli(v_dttz)  AS dttz,
           toUnixTimestamp64Milli(v_dtltz) AS dtltz
    FROM htap.${TABLE}_local FINAL WHERE id IN (1,2,3) ORDER BY id FORMAT TSV" \
    | python3 -c "$CH_PY" || exit 1
ch "SELECT count() FROM htap.${TABLE}_local FINAL WHERE id=4 AND v_tstz IS NULL AND v_dtltz IS NULL" | grep -q '^1$' \
    || { echo "FAIL: CH NULL row wrong"; exit 1; }
echo "OK: ClickHouse instants exact — TZ/LTZ twins converge to one epoch, NULLs preserved"

echo "== 7. cleanup =="
curl -fsS -X DELETE "$CONNECT/connectors/$SINK" >/dev/null || true
curl -fsS -X DELETE "$CONNECT/connectors/$NAME" >/dev/null || true

echo "PASS"
