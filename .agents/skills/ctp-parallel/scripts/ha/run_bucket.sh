#!/bin/bash
# run_bucket.sh — run one HA/shell bucket through CTP inside the hamaster
# container (D143-4: ctp.sh shell, CTP-standard aggregation).
#   usage: run_bucket.sh <bucket>       e.g. run_bucket.sh _22_ha
# Writes conf into the mounted CTP copy, runs foreground (podman exec), and
# prints the CTP summary + result dir at the end.
set -euo pipefail
BUCKET="${1:?usage: run_bucket.sh <bucket> (e.g. _22_ha)}"

HA_ROOT="$(cd "$(dirname "$0")" && pwd)"
STATE="${HA_STATE:-$(cd "$HA_ROOT/../../../../.." && pwd)/.git_ignored_dir/scratch/ha-shell/state}"
CONF_HOST="$STATE/master/CTP/conf/ha_shell_${BUCKET}.conf"
cat > "$CONF_HOST" <<EOF
scenario=/root/tc/HA/shell/${BUCKET}
testcase_retry_num=0
testcase_timeout_in_secs=7200
test_continue_yn=false
testcase_update_yn=false
test_platform=linux
test_category=shell
testcase_exclude_by_macro=LINUX_NOT_SUPPORTED
delete_testcase_after_each_execution_yn=false
enable_check_disk_space_yn=false
feedback_type=file
EOF

echo "== ctp.sh shell scenario=${BUCKET} (foreground; timeout guard 12h) =="
timeout 43200 podman exec hamaster bash -lc \
  "cd /root/cubrid-testtools/CTP && bin/ctp.sh shell -c conf/ha_shell_${BUCKET}.conf"
rc=$?
echo "== ctp exit rc=$rc =="

echo "== summary =="
podman exec hamaster bash -lc \
  'ls -dt /root/cubrid-testtools/CTP/result/shell/current_runtime_logs 2>/dev/null;
   f=$(ls -t /root/cubrid-testtools/CTP/result/shell/*/main_snapshot.properties 2>/dev/null | head -1);
   for d in $(ls -dt /root/cubrid-testtools/CTP/result/shell/y* 2>/dev/null | head -1); do
     echo "result dir: $d"; grep -rE "total|fail|succ" $d/*.log 2>/dev/null | tail -20;
   done' || true
exit $rc
