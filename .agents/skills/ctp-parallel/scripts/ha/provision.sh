#!/bin/bash
# provision.sh — stand up the 2-container HA topology for the wf143 final gate.
#   usage: provision.sh <CUBRID_INSTALL_DIR>
# Creates podman network ctp-ha-net (static IPs), per-node writable copies of
# the CUBRID install + CTP + testcases, and starts hamaster/haslave (sshd).
# Idempotent-ish: tears down existing containers/network first.
set -euo pipefail

INSTALL="${1:?usage: provision.sh <CUBRID_INSTALL_DIR>}"
[ -x "$INSTALL/bin/cub_server" ] || { echo "ERROR: $INSTALL has no bin/cub_server" >&2; exit 1; }

HA_ROOT="$(cd "$(dirname "$0")" && pwd)"
# state lives in the tooling repo scratch (never /tmp); override with HA_STATE
STATE="${HA_STATE:-$(cd "$HA_ROOT/../../../../.." && pwd)/.git_ignored_dir/scratch/ha-shell/state}"
NET=ctp-ha-net
MASTER_IP=10.89.7.10
SLAVE_IP=10.89.7.11
PW='haq-wf143'

echo "== teardown previous =="
podman rm -f hamaster haslave 2>/dev/null || true
podman network rm -f $NET 2>/dev/null || true
rm -rf "$STATE"
mkdir -p "$STATE"/{master,slave}/CUBRID "$STATE"/master/CTP "$STATE"/tc

echo "== per-node copies =="
rsync -a "$INSTALL"/ "$STATE/master/CUBRID/"
rsync -a "$INSTALL"/ "$STATE/slave/CUBRID/"
rsync -a --exclude result --exclude '*.log' "$HOME/cubrid-testtools/CTP/" "$STATE/master/CTP/"
# Fold accommodation (recorded in workspace#176): B5 turned csql into a wire
# driver, so `csql db@slave` now needs a broker ON THE SLAVE (legacy fat-client
# csql connected to cub_master directly). QA's setup_ha_environment only starts
# the master broker; start the slave one too, as production HA does.
sed -i 's|^\( *\)run_on_slave -c "cubrid hb start;cubrid hb status"|\1run_on_slave -c "cubrid broker start"\n\1run_on_slave -c "cubrid hb start;cubrid hb status"|' \
  "$STATE/master/CTP/shell/init_path/make_ha_upper.sh"
grep -q 'run_on_slave -c "cubrid broker start"' "$STATE/master/CTP/shell/init_path/make_ha_upper.sh" \
  || { echo "ERROR: slave-broker-start patch did not land" >&2; exit 1; }
rsync -a "$HOME/cubrid-testcases-private/HA" "$STATE/tc/"

echo "== HA.properties (make_ha.sh contract; ports = install defaults) =="
cat > "$STATE/master/CTP/shell/init_path/HA.properties" <<EOF
MASTER_SERVER_IP=$MASTER_IP
MASTER_SERVER_USER=root
MASTER_SERVER_PW=$PW
MASTER_SERVER_SSH_PORT=22

SLAVE_SERVER_IP=$SLAVE_IP
SLAVE_SERVER_USER=root
SLAVE_SERVER_PW=$PW
SLAVE_SERVER_SSH_PORT=22

CUBRID_PORT_ID=1523
HA_PORT_ID=59901
MASTER_SHM_ID=30001
BROKER_PORT1=30000
APPL_SERVER_SHM_ID1=30000
BROKER_PORT2=33000
APPL_SERVER_SHM_ID2=33000
CM_PORT=8001
BROKER_PORT3=36000
APPL_SERVER_SHM_ID3=36000
SHARD_PROXY_SHM_ID=36090
EOF

echo "== network + containers =="
podman network create --subnet 10.89.7.0/24 $NET
common=(--cgroupns=private --ipc=private --shm-size=2g --ulimit core=-1 --ulimit nofile=65536
        --network $NET --add-host hamaster:$MASTER_IP --add-host haslave:$SLAVE_IP)
podman run -d --name hamaster --hostname hamaster --ip $MASTER_IP "${common[@]}" \
  -v "$STATE/master/CUBRID":/root/CUBRID:z \
  -v "$STATE/master/CTP":/root/cubrid-testtools/CTP:z \
  -v "$STATE/tc":/root/tc:z \
  ctp-ha:local
podman run -d --name haslave --hostname haslave --ip $SLAVE_IP "${common[@]}" \
  -v "$STATE/slave/CUBRID":/root/CUBRID:z \
  ctp-ha:local

echo "== smoke the topology =="
sleep 2
podman exec hamaster bash -lc 'which cubrid && cubrid_rel | grep CUBRID' || { echo NOK: master env; exit 1; }
podman exec hamaster bash -lc "ping -c1 -W2 haslave >/dev/null && echo ping-ok"
# password ssh master->slave exactly as run_remote_script will do it
podman exec hamaster bash -lc '/root/cubrid-testtools/CTP/common/script/run_remote_script -host haslave -port 22 -user root -password "haq-wf143" -c "hostname && cubrid_rel | grep -c CUBRID"' \
  || { echo "NOK: CTP run_remote_script to slave failed"; exit 1; }
echo "PROVISION OK"
