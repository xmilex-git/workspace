#!/usr/bin/env bash
# Hermetic pilot-gate suite runner (workspace#81, 재리뷰 3.3 대응).
#
# 단일 orchestration으로 전 스위트를 clean state에서 순차 실행하고, 각 스위트 사이에
# 잔여 scenario 커넥터를 정리하며(CDC 단일 consumer 계약), 실측 pair의 SHA·image
# digest를 헤더에 자동 기록한다. 재리뷰가 지적한 "재시도로 합성한 10/10"이 아니라
# "초기화된 단일 연속 실행"의 증거를 만든다. 어느 스위트든 실패하면 즉시 non-zero.
#
# 전제: infra up, 커넥터 플러그인 빌드, htapdb(파일럿 pair 엔진)+broker 기동.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONNECT="${CONNECT_URL:-http://localhost:8083}"
CONN_REPO="${CONN_REPO:-$HOME/htap-cdc/debezium-connector-cubrid}"
BUNDLE="${BUNDLE:-$HERE/evidence/pilot-gate-clean}"
mkdir -p "$BUNDLE"
SUMMARY="$BUNDLE/SUMMARY.txt"
MAIN=cubrid-source-poc
SINK=clickhouse-sink-poc
# scenario 커넥터(스위트가 자체 생성) — 스위트 간 잔여 제거 대상
SCENARIO_CONNECTORS=(cubrid-source-part83 cubrid-source-tz86 cubrid-source-relfault clickhouse-sink-tz86)

log () { echo "$@" | tee -a "$SUMMARY"; }

del_conn () { # $1 = name
    curl -fsS "$CONNECT/connectors/$1" >/dev/null 2>&1 || return 0
    curl -fsS -X PUT "$CONNECT/connectors/$1/stop" >/dev/null 2>&1 || true
    for _ in $(seq 1 10); do
        [ "$(curl -fsS "$CONNECT/connectors/$1/status" | python3 -c 'import json,sys;print(json.load(sys.stdin)["connector"]["state"])' 2>/dev/null || echo x)" = STOPPED ] && break; sleep 1
    done
    curl -fsS -X DELETE "$CONNECT/connectors/$1/offsets" >/dev/null 2>&1 || true
    curl -fsS -X DELETE "$CONNECT/connectors/$1" >/dev/null 2>&1 || true
}
scrub_scenarios () { for c in "${SCENARIO_CONNECTORS[@]}"; do del_conn "$c"; done; }

# --- provenance header ---------------------------------------------------------
: > "$SUMMARY"
log "# Pilot-gate hermetic run — $(TZ=UTC date -u +%FT%TZ 2>/dev/null || echo '(date unavailable)')"
CONN_SHA="$(git -C "$CONN_REPO" rev-parse HEAD 2>/dev/null || echo unknown)"
CONN_TAG="$(git -C "$CONN_REPO" describe --tags --always 2>/dev/null || echo unknown)"
SERVER_EXE="$(readlink -f /proc/"$(pgrep -f 'cub_server htapdb' | head -1)"/exe 2>/dev/null || echo unknown)"
log "connector: repo HEAD=$CONN_SHA  describe=$CONN_TAG"
log "engine:    running cub_server exe=$SERVER_EXE"
for img in htap-kafka htap-clickhouse htap-connect; do
    d="$(podman inspect --format '{{.ImageName}}@{{.ImageDigest}}' "$img" 2>/dev/null || echo unavailable)"
    log "image:     $img = $d"
done
log ""

# --- clean baseline ------------------------------------------------------------
log "== reset pipeline to clean baseline (reset-pipeline + run-e2e) =="
scrub_scenarios
if timeout 400 "$HERE/run-e2e.sh" > "$BUNDLE/00-baseline-e2e.log" 2>&1; then
    log "  baseline: PASS -> 00-baseline-e2e.log"
else
    log "  baseline: FAIL -> 00-baseline-e2e.log"; tail -5 "$BUNDLE/00-baseline-e2e.log" | sed 's/^/    /' | tee -a "$SUMMARY"
    exit 1
fi

FAILED=0
run () { # $1 = label; rest = command. Scrubs scenario connectors + ensures MAIN running before each.
    local label="$1"; shift
    local logf="$BUNDLE/${label//[^A-Za-z0-9_-]/_}.log"
    scrub_scenarios
    curl -fsS -X PUT "$CONNECT/connectors/$MAIN/resume" >/dev/null 2>&1 || true
    log "== $label =="
    if timeout 900 "$@" > "$logf" 2>&1; then
        log "  PASS ($label) -> $(basename "$logf")"
    else
        log "  FAIL rc=$? ($label) -> $(basename "$logf")"; tail -6 "$logf" | sed 's/^/    /' | tee -a "$SUMMARY"; FAILED=1
    fi
}

run "01-diff-check"        "$HERE/diff-check.sh"
run "02-faults-S1-S4"      "$HERE/run-faults.sh"
run "03-snapshot-faults"   "$HERE/run-snapshot-faults.sh"
run "04-blocking-snapshot" "$HERE/run-blocking-snapshot.sh"
run "05-owner-collision"   "$HERE/run-owner-collision.sh"
run "06-partition-ddl"     "$HERE/run-partition-ddl.sh"
run "07-tz-types"          "$HERE/run-tz-types.sh"
run "08-relation-fault"    "$HERE/run-relation-fault.sh"
run "09-port-isolation"    "$HERE/run-port-isolation-denial.sh"

scrub_scenarios
curl -fsS -X PUT "$CONNECT/connectors/$MAIN/resume" >/dev/null 2>&1 || true
log ""
if [ "$FAILED" -ne 0 ]; then log "=== RESULT: FAIL (see [FAIL] above) ==="; exit 1; fi
log "=== RESULT: ALL PASS (single hermetic run, connector $CONN_TAG) ==="
