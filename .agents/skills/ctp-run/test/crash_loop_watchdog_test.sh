#!/usr/bin/env bash
# Drive the core watchdog over a fake run: podman, file and df are stubs, the
# shard layout is fixtures, and cores / [OK] lines appear while it polls.
# No container or CTP process is started.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(git -C "$HERE" rev-parse --show-toplevel)"
mkdir -p "$REPO/.git_ignored_dir/scratch/ctp-watchdog-tests"
SCRATCH="$(mktemp -d "$REPO/.git_ignored_dir/scratch/ctp-watchdog-tests/run.XXXXXX")"
export TMPDIR="$SCRATCH"
trap 'stop_core_watchdog 2>/dev/null || :; rm -rf "$SCRATCH"' EXIT
sed '/^main "\$@"$/,$d' "$HERE/../scripts/ctp_run.sh" > "$SCRATCH/functions.sh"

# Source definitions only.
# shellcheck disable=SC1090
. "$SCRATCH/functions.sh"
PASS=0
ok() { PASS=$((PASS+1)); printf '[PASS] %s\n' "$*"; }
fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }

mkdir -p "$SCRATCH/bin"
cat > "$SCRATCH/bin/podman" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$SCRATCH/podman.calls"
EOF
cat > "$SCRATCH/bin/file" <<'EOF'
#!/usr/bin/env bash
case "$(basename "${@: -1}")" in core.*) echo 'ELF 64-bit LSB core file, x86-64' ;; *) echo 'ASCII text' ;; esac
EOF
cat > "$SCRATCH/bin/df" <<'EOF'
#!/usr/bin/env bash
printf 'Avail\n%sG\n' "${FAKE_AVAIL_GB:-500}"
EOF
chmod +x "$SCRATCH/bin/podman" "$SCRATCH/bin/file" "$SCRATCH/bin/df"
export PATH="$SCRATCH/bin:$PATH"
CORE_POLL_SECS=1

# $1 = run name, $2 = shard count, $3 = ARG_ABORT_ON_CORE
setup_run() {
  local i
  OUT="$SCRATCH/$1"
  ARG_ABORT_ON_CORE="$3"
  : > "$SCRATCH/podman.calls"
  SHARD_NAMES=(); HA_SLAVE_NAMES=()
  for (( i=0; i<$2; i++ )); do
    mkdir -p "$OUT/shard_$i/cores" "$OUT/shard_$i/CTP/sql/log" "$OUT/shard_$i/CUBRID" "$OUT/shard_$i/CUBRID_DB"
    : > "$OUT/shard_$i/CTP/sql/log/sql_run.log"
    SHARD_NAMES[i]="fake_${1}_$i"
  done
}
CORE_SEQ=0
add_core() { CORE_SEQ=$((CORE_SEQ + 1)); : > "$OUT/shard_$1/cores/core.recovery-redo.$CORE_SEQ.host.$CORE_SEQ"; }
add_pass() { printf '[00:00:00] Testing /cases/%s.sql (1/9 1%%) [OK]\n' "$CORE_SEQ" >> "$OUT/shard_$1/CTP/sql/log/sql_run.log"; }
killed() { grep -qx "kill $1" "$SCRATCH/podman.calls"; }
# $1 = seconds; the rest is the condition
wait_for() {
  local t="$1" k; shift
  for (( k=0; k<t*10; k++ )); do "$@" && return 0; sleep 0.1; done
  return 1
}

# A database that crashes again on every restart: cores keep coming, no case passes.
setup_run loop 2 0
add_pass 0; add_pass 1
start_core_watchdog > /dev/null
for n in 1 2 3 4; do add_core 0; sleep 1.2; done
killed fake_loop_0 && fail 'crash loop: shard stopped before CTP_CRASH_LOOP_CORES cores'
add_core 0
wait_for 5 killed fake_loop_0 || fail 'crash loop: shard not stopped after 5 cores with no passing case'
killed fake_loop_1 && fail 'crash loop: a healthy shard was stopped too'
grep -q '^shard 0: crash loop: 5 core dumps' "$OUT/.dead_shards" || fail 'crash loop: .dead_shards lacks the reason'
[ ! -e "$OUT/.abort_reason" ] || fail 'crash loop: the whole run was aborted'
stop_core_watchdog
ok 'no-abort: a crash-looping shard is stopped alone after 5 cores with no passing case'

# A server that crashes on some cases but keeps running the others.
setup_run alive 1 0
start_core_watchdog > /dev/null
for n in 1 2 3 4 5 6 7 8; do add_pass 0; add_core 0; sleep 1.2; done
sleep 1.2
killed fake_alive_0 && fail 'alive: a shard that still passes cases was stopped'
stop_core_watchdog
ok 'no-abort: cores separated by passing cases keep the shard running'

# The per-shard cap bounds the disk even when cases keep passing.
setup_run cap 1 0
MAX_SHARD_CORES=3
start_core_watchdog > /dev/null
for n in 1 2 3; do add_pass 0; add_core 0; sleep 1.2; done
wait_for 5 killed fake_cap_0 || fail 'cap: shard not stopped at CTP_MAX_SHARD_CORES'
grep -q '^shard 0: core cap: 3 core dumps' "$OUT/.dead_shards" || fail 'cap: .dead_shards lacks the reason'
stop_core_watchdog
MAX_SHARD_CORES=20
ok 'no-abort: CTP_MAX_SHARD_CORES stops the shard'

# Default mode is unchanged: the first core stops every shard.
setup_run abort 2 1
start_core_watchdog > /dev/null
add_core 1
wait_for 5 killed fake_abort_0 || fail 'abort: shard 0 not stopped on the first core'
killed fake_abort_1 || fail 'abort: shard 1 not stopped on the first core'
grep -q '^core dump detected: ' "$OUT/.abort_reason" || fail 'abort: .abort_reason lacks the core'
stop_core_watchdog
ok 'abort-on-core: the first core stops every shard'

# The disk floor applies with --no-abort-on-core too.
setup_run disk 2 0
export FAKE_AVAIL_GB=10
start_core_watchdog > /dev/null
wait_for 5 killed fake_disk_1 || fail 'disk floor: shards not stopped with --no-abort-on-core'
grep -q '^disk floor breached' "$OUT/.abort_reason" || fail 'disk floor: .abort_reason lacks the reason'
stop_core_watchdog
unset FAKE_AVAIL_GB
ok 'no-abort: the disk floor still stops every shard'

echo "Core watchdog: $PASS checks passed"
