#!/usr/bin/env bash
# Stop and remove the POC containers. Data under $HTAP_DATA is KEPT
# (use reset.sh to wipe).
set -euo pipefail
for c in htap-connect htap-clickhouse htap-kafka; do
    podman rm -f "$c" >/dev/null 2>&1 && echo "removed $c" || echo "$c not running"
done
