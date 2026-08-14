#!/usr/bin/env bash
# Server control for columnar verification campaign.
# Usage: columnar_server.sh start|stop|status
set -euo pipefail

export CUBRID=/home/cubrid/release/CUBRID-columnar-rel
export CUBRID_DATABASES=/data/tpch-sspq/columnar-verify/db
export CUBRID_TMP=/tmp
export LD_LIBRARY_PATH="$CUBRID/lib:$CUBRID/cci/lib"
export PATH="$CUBRID/bin:$PATH"

DB=tpch_col_verify
CONF="$CUBRID/conf/cubrid.conf"

configure() {
    echo "=== Configuring cubrid.conf ==="
    cat > "$CONF" << 'CONF_EOF'
[service]
service=server,broker,manager

[common]
# 4GB buffer for TPC-H SF10 (47GB on-disk)
data_buffer_size=4G
log_buffer_size=256M
sort_buffer_size=16M
max_clients=10
cubrid_port_id=1523
db_volume_size=16G
log_volume_size=512M
log_max_archives=0
# Columnar verification: no need for HA
ha_mode=off
CONF_EOF
    echo "Configuration written to $CONF"
}

start_server() {
    configure

    # Clean stale master
    if pgrep -x cub_master > /dev/null 2>&1; then
        echo "Killing stale cub_master..."
        pkill -x cub_master || true
        sleep 2
    fi

    echo "=== Starting CUBRID master ==="
    cubrid service start 2>/dev/null || true
    sleep 2

    echo "=== Starting server for $DB ==="
    cubrid server start "$DB"
    sleep 2

    echo "=== Server status ==="
    cubrid server status
    echo ""
    cubrid_rel
}

stop_server() {
    echo "=== Stopping server ==="
    cubrid server stop "$DB" 2>/dev/null || true
    sleep 2
    cubrid service stop 2>/dev/null || true
    # Kill any remaining processes
    pkill -x cub_master 2>/dev/null || true
    echo "Server stopped."
}

status_server() {
    cubrid server status 2>/dev/null || echo "No server running"
    echo ""
    cubrid_rel 2>/dev/null || echo "cubrid_rel not available"
}

case "${1:-}" in
    start)     start_server ;;
    stop)      stop_server ;;
    status)    status_server ;;
    configure) configure ;;
    *)         echo "Usage: $0 start|stop|status|configure"; exit 1 ;;
esac
