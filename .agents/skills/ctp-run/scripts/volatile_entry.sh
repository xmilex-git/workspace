#!/bin/bash
# volatile_entry.sh — container entrypoint for shards whose database dir is
# volatile (sql/medium by default; CTP_VOLATILE=0 or --no-volatile turns it off).
#
# CTP creates its database under $CUBRID/databases (sql/bin/run.sh sets
# cubrid_root_dir=$CUBRID), and every autocommit statement then waits for the log
# fsync. The database is thrown away with the shard, so those syncs protect
# nothing. A killed server loses nothing either: its writes are already in the
# page cache. So this mounts an overlayfs with the kernel's `volatile` option
# over each target: lower = the target itself, upper/work under /ctprun-volatile
# (a host bind). Every fsync/fdatasync/syncfs there then returns at once. This is
# the mechanism cubrid-testkit uses for TESTKIT_SLOT_VOLATILE
# (internal/contain/slot.go).
#
# The mount needs CAP_SYS_ADMIN inside the container's user namespace, which
# ctp_run.sh grants with --cap-add SYS_ADMIN. The capability is dropped again
# before the image's entrypoint runs, so CTP keeps the capabilities it always had.
# Decision: docs/adr/0017-ctp-runner-on-cubridci-image.md D7.
set -euo pipefail

vol_root=/ctprun-volatile
for target in ${CTPRUN_VOLATILE_TARGETS:?CTPRUN_VOLATILE_TARGETS is unset}; do
  name="$(printf '%s' "$target" | tr / _)"
  upper="$vol_root/$name/upper" work="$vol_root/$name/work"
  mkdir -p "$target" "$upper" "$work"
  # A volatile workdir cannot be mounted twice: the kernel leaves
  # work/work/incompat/volatile behind. The runner makes a fresh one per run.
  if ! mount -t overlay overlay -o "volatile,lowerdir=$target,upperdir=$upper,workdir=$work" "$target"; then
    echo "[volatile] ERROR: cannot mount a volatile overlay on $target; rerun with CTP_VOLATILE=0" >&2
    exit 1
  fi
  if ! awk -v t="$target" '$5 == t && / - overlay / && /volatile/ { found = 1 } END { exit !found }' /proc/self/mountinfo; then
    echo "[volatile] ERROR: $target is mounted but the mount table does not show volatile" >&2
    exit 1
  fi
  echo "[volatile] $target: overlayfs volatile, writes in $upper"
done

if command -v setpriv >/dev/null 2>&1; then
  exec setpriv --inh-caps=-sys_admin --bounding-set=-sys_admin -- /entrypoint.sh "$@"
fi
echo "[volatile] WARN: setpriv not found; CAP_SYS_ADMIN stays in the container" >&2
exec /entrypoint.sh "$@"
