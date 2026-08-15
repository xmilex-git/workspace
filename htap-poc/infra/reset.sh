#!/usr/bin/env bash
# Full reset: down + wipe all stack data ($HTAP_DATA kafka/clickhouse dirs).
# The connector-plugin dir is kept (jars are expensive to rebuild).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HTAP_DATA="${HTAP_DATA:-$HOME/htap-data}"

"$HERE/down.sh"
# the :U mount flag in up.sh chowns data to the container's mapped UID
# (e.g. subuid-shifted, not the host user), so a plain rm -rf here would
# fail with Permission denied — remove inside the user namespace instead.
podman unshare rm -rf "$HTAP_DATA/kafka" "$HTAP_DATA/clickhouse"
echo "wiped $HTAP_DATA/{kafka,clickhouse} (connect-plugins kept)"
