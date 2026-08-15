#!/usr/bin/env bash
# One-shot test-DB provisioning for the CDC harness (ticket #33).
# Requires $CUBRID to point at the ISOLATED htap install (never the shared
# ~/CUBRID campaign install) and its bin on PATH.
#
#   CUBRID=$HOME/htap-cdc/CUBRID-11.5-htapcdc PATH=$CUBRID/bin:$PATH ./db_setup.sh [dbname]
set -euo pipefail

DB="${1:-htapdb}"
: "${CUBRID:?CUBRID env var required (isolated htap install)}"
DBDIR="$HOME/htap-cdc/db/$DB"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SERVER_CTL="$REPO_ROOT/.claude/skills/cubrid-server-control/scripts/cubrid-server-ctl.sh"
[ -x "$SERVER_CTL" ] || { echo "ERROR: server-control wrapper not found: $SERVER_CTL" >&2; exit 1; }

# supplemental_log=1 is the whole point of this DB (htap-cubrid.md §21-1)
CONF="$CUBRID/conf/cubrid.conf"
if ! grep -q '^supplemental_log=1' "$CONF"; then
    printf '\n# htap-poc ticket #33: CDC log extraction needs supplemental logging\nsupplemental_log=1\n' >> "$CONF"
    echo "conf: appended supplemental_log=1 -> $CONF"
else
    echo "conf: supplemental_log=1 already set"
fi

if [ -d "$DBDIR" ]; then
    echo "db: $DBDIR already exists — skipping createdb (use 'cubrid deletedb $DB' to recreate)"
else
    mkdir -p "$DBDIR"
    ( cd "$DBDIR" && cubrid createdb --db-volume-size=512M --log-volume-size=256M "$DB" en_US.utf8 )
    echo "db: created $DB in $DBDIR"
fi

"$SERVER_CTL" restart "$DB"
