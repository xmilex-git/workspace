#!/usr/bin/env bash
# (Re)apply the ClickHouse DDL (ddl.sql) inside the running htap-clickhouse
# container. Idempotent. Pass --truncate to also empty the *_local tables
# (ADR 0005: the only way to clean a partial snapshot load).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

podman exec -i htap-clickhouse clickhouse-client --multiquery < "$HERE/ddl.sql"
echo "ddl: applied"

if [ "${1:-}" = "--truncate" ]; then
    podman exec -i htap-clickhouse clickhouse-client --multiquery < "$HERE/truncate.sql"
    echo "ddl: truncated *_local tables"
fi
