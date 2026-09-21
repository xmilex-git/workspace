#!/usr/bin/env bash
# Resolve CTP storage before staging copies or starting containers.
set -euo pipefail
mount="${CTP_ARTIFACT_MOUNT:-/bench/hdd}"
case "$mount" in /*) ;; *) echo "ERROR: CTP_ARTIFACT_MOUNT must be absolute" >&2; exit 1 ;; esac
mount="$(readlink -f "$mount")"
mountpoint -q "$mount" || { echo "ERROR: CTP artifact disk is not mounted: $mount (no local fallback)" >&2; exit 1; }
repo="$(cd "$(dirname "$0")/../../../.." && pwd -P)"
root="$mount/$(id -un)/$(basename "$repo")/ctp-run-out"
mkdir -p "$root"
root="$(cd "$root" && pwd -P)"
[ "$(findmnt -n -o TARGET -T "$root")" = "$mount" ] || { echo "ERROR: CTP output escaped artifact mount: $root" >&2; exit 1; }
[ -w "$root" ] || { echo "ERROR: CTP output is not writable: $root" >&2; exit 1; }
printf '%s\n' "$root"
