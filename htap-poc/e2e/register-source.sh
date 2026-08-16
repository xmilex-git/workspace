#!/usr/bin/env bash
# Register (or update — PUT is idempotent) the CUBRID source connector on the
# local Connect worker from cubrid-source.json.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONNECT="${CONNECT_URL:-http://localhost:8083}"

NAME="$(python3 -c "import json;print(json.load(open('$HERE/cubrid-source.json'))['name'])")"
python3 -c "import json;print(json.dumps(json.load(open('$HERE/cubrid-source.json'))['config']))" \
  | curl -fsS -X PUT -H 'Content-Type: application/json' -d @- \
      "$CONNECT/connectors/$NAME/config" >/dev/null

sleep 2
curl -fsS "$CONNECT/connectors/$NAME/status"
echo
