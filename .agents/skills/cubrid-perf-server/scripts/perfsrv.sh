#!/usr/bin/env bash
# perfsrv.sh — reserve and use the shared perf servers (cubrid-perf-server skill).
# usage:
#   perfsrv.sh status
#   perfsrv.sh reserve <minutes> [node-ip]        -> prints RUN=<run-id> NODE=<ip>
#   perfsrv.sh push <run> <install-dir>           -> prints SHA=<sha12> (remote install-<sha12>, standard conf)
#   perfsrv.sh conf <run> <sha12> dwb-on|dwb-off  -> rewrites that install's conf (standard conf, DWB on/off)
#   perfsrv.sh exec <run> <sha12> '<command>'     -> runs the command on the node, streams its output
#   perfsrv.sh pull <run>                         -> copies the remote out/ into /home/cubrid/perf-run-out/<run>/out
#   perfsrv.sh release <run>                      -> pull, stop everything, delete the run dir, end the reservation now
set -euo pipefail

NODES=(192.168.1.248 192.168.1.249)
OWNER=송일한
SCHED=/home/devuser/schedule.txt
RROOT=/home/cubrid/perf-runs
LOUT=/home/cubrid/perf-run-out
SSHO=(-o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=30)

die() { echo "perfsrv: $*" >&2; exit 2; }

# ---------- functions that run on the node (shipped with declare -f) ----------

# "start end line" for every schedule entry except the exact line $1; an unparsable entry blocks everything
r_others() {
  local own=$1 l n s e
  while IFS= read -r l; do
    case $l in '' | '#'* | 담당자*) continue ;; esac
    [ "$l" = "$own" ] && continue
    IFS='|' read -r n s e <<< "$l"
    s=$(date -d "$(echo $s)" +%s 2>/dev/null) && e=$(date -d "$(echo $e)" +%s 2>/dev/null) || { s=0; e=4102444800; }
    echo "$s $e $l"
  done < "$SCHED"
}

# processes in this container that are neither system nor this ssh session (loadavg here is host-wide)
r_foreign() {
  local sid; sid=$(ps -o sid= -p $$ | tr -d ' ')
  ps -e -o user=,sid=,pid=,comm=,args= | awk -v sid="$sid" '$1!="root" && $1!="dbus" && $2!=sid && $4!~/^(sshd|bash|sh|sleep)$/'
}

# true while a command group or a process of this run's installs is alive
r_busy() {
  local R=$1 g p
  for g in $(cat "$R/pgids" 2>/dev/null); do kill -0 -- "-$g" 2>/dev/null && return 0; done
  for p in /proc/[0-9]*; do case $(readlink "$p/exe" 2>/dev/null) in "$R"/*) return 0 ;; esac; done
  return 1
}

r_replace_line() {  # old new rundir: replace (empty new: drop) one exact schedule line in place, keeping the inode others edit
  awk -v old="$1" -v new="$2" '$0==old{if(new=="")next; $0=new}1' "$SCHED" > "$3/sched.tmp" && cat "$3/sched.tmp" > "$SCHED"
}

r_active() {
  local R=$RROOT/$1
  [ -f "$R/reservation" ] || { echo "no reservation for run $1 on this node" >&2; return 2; }
  grep -qxF "$(cat "$R/reservation")" "$SCHED" || { echo "reservation line is gone from $SCHED" >&2; return 2; }
  [ "$(date +%s)" -lt "$(cat "$R/end")" ] || { echo "reservation has ended" >&2; return 2; }
}

r_conf() {  # install dwb-on|dwb-off — the perf server standard conf (QAHome values, 16 GiB cgroup)
  cat > "$1/conf/cubrid.conf" <<'CONF'
[service]
service=server
[common]
data_buffer_size=12G
log_buffer_size=256M
sort_buffer_size=8M
parallelism=32
max_parallel_workers=100
error_log_size=2000000000
max_clients=100
cubrid_port_id=1523
log_max_archives=0
stored_procedure=no
CONF
  [ "$2" = dwb-off ] && echo 'double_write_buffer_size=0' >> "$1/conf/cubrid.conf"
  echo "CONF $2 $1/conf/cubrid.conf"
}

r_reserve() {
  local mins=$1 run=$2 R=$RROOT/$2 now end cap line s e l busy= procs base
  now=$(date +%s); cap=$(date -d 'today 21:55' +%s)
  [ "$(date +%H%M)" -ge 1200 ] || { echo "perf servers run 12:00-22:00 KST" >&2; return 2; }
  end=$((now + mins * 60)); [ "$end" -gt "$cap" ] && end=$cap
  end=$(date -d "$(date -d @"$end" '+%F %H:%M')" +%s)
  [ "$end" -gt $((now + 300)) ] || { echo "less than 5 minutes before 21:55" >&2; return 2; }
  while read -r s e l; do
    if [ "$s" -lt "$end" ] && [ "$e" -gt "$now" ]; then echo "BUSY reservation: $l"; busy=1; fi
  done < <(r_others "")
  procs=$(r_foreign); [ -z "$procs" ] || { echo "BUSY processes:"; echo "$procs"; busy=1; }
  [ -z "$busy" ] || return 3
  line="$OWNER | $(date -d @"$now" '+%F %H:%M') | $(date -d @"$end" '+%F %H:%M')"
  [ -z "$(tail -c1 "$SCHED")" ] || echo >> "$SCHED"
  echo "$line" >> "$SCHED"
  base=$(ls -1A ~)
  mkdir -p "$R/out" "$R/databases" "$R/tmp"
  printf '%s\n' "$base" > "$R/home-baseline.txt"
  echo "$line" > "$R/reservation"; echo "$end" > "$R/end"; : > "$R/pgids"
  r_write_scripts "$R"
  while read -r s e l; do
    if [ "$s" -lt "$end" ] && [ "$e" -gt "$now" ]; then
      echo "RACE: $l was written at the same time; backing out" >&2
      r_replace_line "$line" "" "$R"; bash "$R/cleanup.sh"; return 3
    fi
  done < <(r_others "$line")
  grep -E '^tpch_sf10[[:space:]]' /home/cubrid/databases/databases.txt > "$R/databases/databases.txt" || :
  setsid bash "$R/watchdog.sh" > /dev/null 2>&1 < /dev/null &
  echo $! > "$R/watchdog.pid"
  echo "RESERVED $line"
}

r_write_scripts() { r_write_cleanup "$1"; r_write_watchdog "$1"; }

r_write_cleanup() {  # cleanup.sh carries the run dir as a literal path
  local R=$1
  cat > "$R/cleanup.sh" <<EOF
#!/bin/bash
# stops every process of run $R and deletes the run dir; prints a CLEANUP verdict
base=\$(cat $R/home-baseline.txt)
# servers first, while their cub_master (a member of an exec's process group) still runs
for p in /proc/[0-9]*; do
  exe=\$(readlink \$p/exe 2>/dev/null) || continue
  case \$exe in $R/install-*/bin/cub_server) ;; *) continue ;; esac
  i=\${exe%/bin/cub_server}; db=\$(tr '\0' ' ' < \$p/cmdline | awk '{print \$2}')
  CUBRID=\$i CUBRID_DATABASES=$R/databases CUBRID_TMP=$R/tmp LD_LIBRARY_PATH=\$i/lib timeout 120 \$i/bin/cubrid server stop \$db > /dev/null 2>&1 || kill -TERM \${p#/proc/}
done
for g in \$(cat $R/pgids); do kill -TERM -- -\$g 2>/dev/null; done
sleep 5
for g in \$(cat $R/pgids); do kill -KILL -- -\$g 2>/dev/null; done
for p in /proc/[0-9]*; do case \$(readlink \$p/exe 2>/dev/null) in $R/*) kill -KILL \${p#/proc/} 2>/dev/null ;; esac; done
sleep 1
rm -rf $R
rmdir $RROOT 2>/dev/null
left=\$(for p in /proc/[0-9]*; do readlink \$p/exe 2>/dev/null; done | grep -c '^$R/')
if [ "\$(ls -1A ~)" = "\$base" ] && [ "\$left" = 0 ]; then echo "CLEANUP OK"; else echo "CLEANUP DIFF leftovers=\$left"; diff <(echo "\$base") <(ls -1A ~); fi
EOF
}

r_write_watchdog() {  # watchdog.sh enforces the end time
  local R=$1
  {
    echo '#!/bin/bash'
    echo "# enforces the reservation end of $R: extends by 1h while busy and free, else cleans up at the end"
    declare -p SCHED OWNER RROOT
    declare -f r_others r_busy r_replace_line
    cat <<EOF
R=$R
while line=\$(cat \$R/reservation 2>/dev/null); do
  end=\$(cat \$R/end); now=\$(date +%s)
  if [ \$now -ge \$end ]; then bash \$R/cleanup.sh > /dev/null 2>&1; exit 0; fi
  if [ \$now -ge \$((end - 600)) ] && [ "\$(cat \$R/ext-checked 2>/dev/null)" != \$end ] && r_busy \$R; then
    echo \$end > \$R/ext-checked
    new=\$((end + 3600)); cap=\$(date -d 'today 21:55' +%s); [ \$new -gt \$cap ] && new=\$cap
    while read -r s e l; do [ \$e -gt \$end ] && [ \$s -lt \$new ] && new=\$s; done < <(r_others "\$line")
    if [ \$new -gt \$end ]; then
      newline="\${line% | *} | \$(date -d @\$new '+%F %H:%M')"
      r_replace_line "\$line" "\$newline" \$R && echo "\$newline" > \$R/reservation && echo \$new > \$R/end
    fi
  fi
  sleep 20
done
EOF
  } > "$R/watchdog.sh"
}

r_push() {  # run sha: unpack the tar on stdin into install-<sha>, verify, write the standard conf
  local R=$RROOT/$1 I=$RROOT/$1/install-$2
  r_active "$1"
  mkdir -p "$I" && tar -C "$I" -xf -
  [ "$(sha256sum "$I/lib/libcubrid.so.11.5" | cut -c1-12)" = "$2" ] || { echo "fingerprint mismatch in $I" >&2; return 2; }
  r_conf "$I" dwb-on
  echo "PUSHED $I"
}

r_exec() {  # run sha command
  local R=$RROOT/$1 I=$RROOT/$1/install-$2 log pid rc
  r_active "$1"
  [ -x "$I/bin/cubrid" ] || { echo "no install $I (push it first)" >&2; return 2; }
  log=$R/out/exec-$(date +%H%M%S)-$$.log
  export CUBRID=$I CUBRID_DATABASES=$R/databases CUBRID_TMP=$R/tmp RUN=$R OUT=$R/out
  export PATH=$I/bin:$PATH LD_LIBRARY_PATH=$I/lib:$I/cci/lib
  cd "$R/out"
  setsid bash -c "$3" > "$log" 2>&1 < /dev/null &
  pid=$!; echo "$pid" >> "$R/pgids"
  tail -n +1 --pid="$pid" -f "$log"
  wait "$pid" && rc=0 || rc=$?
  echo "PERFSRV exec rc=$rc log=$log"
  return "$rc"
}

r_conf_cmd() { r_active "$1" && r_conf "$RROOT/$1/install-$2" "$3"; }

r_release() {
  local R=$RROOT/$1 line now
  line=$(cat "$R/reservation") || { echo "no run $1 on this node" >&2; return 2; }
  kill "$(cat "$R/watchdog.pid")" 2>/dev/null || :
  now=$(date '+%F %H:%M')
  r_replace_line "$line" "${line% | *} | $now" "$R"
  bash "$R/cleanup.sh"
  echo "RELEASED ${line% | *} | $now"
}

r_status() {
  echo "== $(hostname) $(date '+%F %H:%M')"
  grep -v -E '^(담당자|#|[[:space:]]*$)' "$SCHED" | tail -5 || echo "(no reservations)"
  echo "-- foreign processes:"; r_foreign || :
  ls -1 "$RROOT" 2>/dev/null | sed 's/^/-- my run: /' || :
}

# ---------- local side ----------

remote() {  # node function args... — runs a node function over ssh; stdin passes through
  local h=$1; shift
  local script
  script="$(declare -p SCHED OWNER RROOT); $(declare -f r_others r_foreign r_busy r_replace_line r_active r_conf r_reserve r_write_scripts r_write_cleanup r_write_watchdog r_push r_exec r_conf_cmd r_release r_status); $(printf '%q ' "$@")"
  ssh "${SSHO[@]}" "cubrid@$h" "bash -c $(printf '%q' "$script")"
}

node_of() { cat "$LOUT/$1/node" 2>/dev/null || die "unknown run $1 (no $LOUT/$1/node)"; }

cmd=${1:-}; shift || :
case $cmd in
  status)
    for h in "${NODES[@]}"; do remote "$h" r_status < /dev/null || echo "== $h unreachable (off outside 12:00-22:00?)"; done ;;
  reserve)
    mins=${1:?minutes}; nodes=("${NODES[@]}"); [ -n "${2:-}" ] && nodes=("$2")
    for h in "${nodes[@]}"; do
      run=$(date +%Y%m%d-%H%M%S)-${h##*.}
      if remote "$h" r_reserve "$mins" "$run" < /dev/null; then
        mkdir -p "$LOUT/$run"; echo "$h" > "$LOUT/$run/node"
        echo "RUN=$run NODE=$h"; exit 0
      fi
    done
    die "no free perf server; run 'perfsrv.sh status' for the earliest free time" ;;
  push)
    run=${1:?run}; inst=${2:?install-dir}; h=$(node_of "$run")
    sha=$(sha256sum "$inst/lib/libcubrid.so.11.5" | cut -c1-12)
    tar -C "$inst" -cf - . | remote "$h" r_push "$run" "$sha"
    echo "SHA=$sha" ;;
  conf)
    run=${1:?run}; remote "$(node_of "$run")" r_conf_cmd "$run" "${2:?sha12}" "${3:?dwb-on|dwb-off}" < /dev/null ;;
  exec)
    run=${1:?run}; h=$(node_of "$run")
    remote "$h" r_exec "$run" "${2:?sha12}" "${3:?command}" < /dev/null | tee -a "$LOUT/$run/exec.log"
    exit "${PIPESTATUS[0]}" ;;
  pull)
    run=${1:?run}; mkdir -p "$LOUT/$run/out"
    ssh -n "${SSHO[@]}" "cubrid@$(node_of "$run")" "tar -C $RROOT/$run/out -cf - ." | tar -m -C "$LOUT/$run/out" -xf -
    echo "PULLED $LOUT/$run/out" ;;
  release)
    run=${1:?run}; "$0" pull "$run"
    remote "$(node_of "$run")" r_release "$run" < /dev/null | tee -a "$LOUT/$run/release.log" ;;
  *) sed -n '2,11p' "$0"; exit 2 ;;
esac
