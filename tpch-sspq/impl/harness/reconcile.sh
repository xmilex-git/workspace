#!/usr/bin/env bash
# Phase 1A reconciler (IMPL-SSOT section 9). Idempotent, read-only.
# Emits CHANGED/BLOCKER lines only; silence means an unchanged healthy poll.
set -uo pipefail
S=tpch-sspq-impl-r1-20260803-phase1a-driver
R=/data/tpch-sspq/tpch-sspq-impl-r1-20260803
L=$R/work/BASELINE/phase1a-driver.log
PIN_C=2de2404ba3e39016c423a85900e5b04a39dfda14
PIN_B=111c281081785cd25f2b59d74b2a38dfaa75d7da

# 1. pin
cd /home/cubrid/dev/workspace
git fetch -q origin 2>/dev/null
ob=$(git rev-parse origin/main:tpch-sspq/IMPL-SSOT.md 2>/dev/null)
[ "$ob" = "$PIN_B" ] || echo "BLOCKER IMPL_SSOT_DRIFT origin/main blob=$ob expected=$PIN_B"

# 2. driver alive + two capture-pane samples
if ! tmux has-session -t "$S" 2>/dev/null; then
  echo "BLOCKER driver tmux session $S ABSENT"
else
  a=$(tmux capture-pane -t "$S" -p | tail -25 | md5sum)
  sleep 20
  b=$(tmux capture-pane -t "$S" -p | tail -25 | md5sum)
  [ "$a" = "$b" ] && PANE=SAME || PANE=MOVING
fi
DRV=$(pgrep -f "bash /home/cubrid/dev/tpch-sspq-impl-r1/harness/phase1a_driver.sh" | head -1)
[ -n "$DRV" ] || echo "BLOCKER phase1a_driver.sh process ABSENT"

# 3. server identity
P=$(pgrep -f "cub_server tpch_sf10_q1" | head -1)
if [ -n "$P" ]; then
  EXE=$(readlink -f /proc/$P/exe)
  case "$EXE" in
    /home/cubrid/dev/tpch-sspq-impl-r1/install/base/bin/cub_server) ;;
    *) echo "BLOCKER cub_server exe NOT campaign-owned: $EXE" ;;
  esac
  OFF=0; N=0
  for t in /proc/$P/task/*; do
    N=$((N+1))
    m=$(taskset -pc ${t##*/} 2>/dev/null | sed "s/.*list: //")
    case "$m" in 0-15|0-15,*) ;; "") ;; *) OFF=$((OFF+1)); echo "BLOCKER OFF_CPUSET tid=${t##*/} cpus=$m" ;; esac
  done
  NB=$(grep -c "bind:0" /proc/$P/numa_maps 2>/dev/null || echo 0)
  NOTB=$(grep -v "bind:0" /proc/$P/numa_maps 2>/dev/null | grep -c "N1=" || true)
  SRV="pid=$P tids=$N off=$OFF bind0_regions=$NB"
else
  SRV="pid=none (between blocks)"
fi
LP=$(ss -lntp 2>/dev/null | grep ":1523 " | grep -c cub_master || true)

# 4. durable artifact advance
NF=$(find $R/raw -type f 2>/dev/null | wc -l)
NB_ACC=$(grep -cE "block [0-9]+ ACCEPTED" $L 2>/dev/null || echo 0)
NB_INV=$(grep -cE "block [0-9]+ INVALID" $L 2>/dev/null || echo 0)
CUR=$(grep -E "##########" $L 2>/dev/null | tail -1 | sed "s/.*##########//;s/##########//")
LAST=$(tail -1 $L 2>/dev/null | cut -c1-120)
MT=$(stat -c %Y $L 2>/dev/null); AGE=$(( $(date +%s) - MT ))

# 5. neighbours
NEI=$(tmux ls 2>/dev/null | grep -cE "^(1gjc|claude):")

echo "CYCLE $(date -u +%FT%TZ) pane=${PANE:-?} drv=${DRV:-none} $SRV port1523_master=$LP rawfiles=$NF accepted=$NB_ACC invalid=$NB_INV neighbours=$NEI log_age_s=$AGE"
echo "  at:$CUR"
echo "  last:$LAST"
[ -f $R/work/BASELINE/PHASE1A-DRIVER-DONE ] && echo "DONE PHASE1A-DRIVER-DONE present"
exit 0
