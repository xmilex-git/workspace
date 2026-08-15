#!/usr/bin/env bash
# Download the ClickHouse Kafka Connect Sink release (pinned in
# ../infra/versions.env) and unpack it into the Connect plugin dir.
# Scratch goes to the repo's .git_ignored_dir/scratch — never /tmp.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../infra/versions.env"

HTAP_DATA="${HTAP_DATA:-$HOME/htap-data}"
PLUGIN_DIR="$HTAP_DATA/connect-plugins/clickhouse-kafka-connect"
SCRATCH="$HERE/../../.git_ignored_dir/scratch/clickhouse-sink"
V="$CLICKHOUSE_SINK_VERSION"
ZIP="clickhouse-kafka-connect-$V.zip"

if ls "$PLUGIN_DIR"/*"$V"*/*.jar >/dev/null 2>&1 || ls "$PLUGIN_DIR"/*"$V"*.jar >/dev/null 2>&1; then
    echo "plugin: $V already installed in $PLUGIN_DIR"
    exit 0
fi

mkdir -p "$SCRATCH" "$PLUGIN_DIR"
[ -f "$SCRATCH/$ZIP" ] || curl -fSL -o "$SCRATCH/$ZIP" \
    "https://github.com/ClickHouse/clickhouse-kafka-connect/releases/download/$V/$ZIP"

unzip -oq "$SCRATCH/$ZIP" -d "$PLUGIN_DIR"
echo "plugin: installed $V -> $PLUGIN_DIR"
echo "NOTE: restart the worker to load it: podman restart htap-connect"
