#!/usr/bin/env bash
#
# sweep_podman_scopes.sh — Reap leaked empty rootless-podman transient scopes on
# cgroup-v1 hosts.
#
# On legacy cgroup-v1 container hosts, systemd --user does not receive kernel
# release_agent notifications when a transient scope's cgroup empties. Each
# rootless podman invocation can leave an active empty podman-<pid>.scope until
# systemd --user hits MANAGER_MAX_NAMES (131,072) and future reloads or podman
# D-Bus calls stall.
#
# Usage:
#   sweep_podman_scopes.sh [--min-age <seconds>] [--dry-run]
#
# Env overrides (used by run_tests.sh fixtures):
#   CTP_SCOPE_MIN_AGE      Default min age in seconds (60)
#   SWEEP_FORCE            Set to 1 to run even on cgroup-v2 hosts
#   SWEEP_TRANSIENT_DIR    Override transient unit directory
#   SWEEP_CGRP_USER_SLICE  Override user.slice cgroup directory

set -euo pipefail

# cgroup-v2 hosts reap empty scopes via kernel cgroup.events natively.
if [ "${SWEEP_FORCE:-0}" != "1" ] && [ -f /sys/fs/cgroup/cgroup.controllers ]; then
  exit 0
fi

exec python3 - "$@" <<'PY'
import argparse
import errno
import os
import re
import subprocess
import sys
import time

PAT = re.compile(r"^(podman-\d+|rootless-netns-[0-9a-f]+)\.scope$")


def find_user_slice():
    override = os.environ.get("SWEEP_CGRP_USER_SLICE", "").strip()
    if override:
        return override
    uid = os.getuid()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/status", "r", encoding="utf-8", errors="replace") as f:
                uid_ok = False
                for line in f:
                    if line.startswith("Uid:"):
                        parts = line.split()
                        if len(parts) >= 2 and int(parts[1]) == uid:
                            uid_ok = True
                        break
                if not uid_ok:
                    continue
            with open(f"/proc/{entry}/cmdline", "rb") as f:
                args = [a.decode("utf-8", "replace") for a in f.read().split(b"\0") if a]
            if not args or not args[0].endswith("/systemd") or "--user" not in args[1:]:
                continue
            with open(f"/proc/{entry}/cgroup", "r", encoding="utf-8", errors="replace") as f:
                for line in f:
                    parts = line.strip().split(":", 2)
                    if len(parts) == 3 and parts[1] == "name=systemd":
                        cg = parts[2]
                        if cg.endswith("/init.scope"):
                            cg = cg[: -len("/init.scope")]
                        candidate = os.path.join("/sys/fs/cgroup/systemd", cg.lstrip("/"), "user.slice")
                        if os.path.isdir(candidate):
                            return candidate
        except (OSError, ValueError):
            continue
    return ""


def cgroup_is_nonempty(cgrp_dir):
    if not cgrp_dir or not os.path.isdir(cgrp_dir):
        return False
    for fn in ("cgroup.procs", "tasks"):
        fp = os.path.join(cgrp_dir, fn)
        try:
            with open(fp, "r", encoding="utf-8", errors="replace") as f:
                if f.read().strip():
                    return True
        except FileNotFoundError:
            continue
        except OSError:
            return True
    return False


def systemd_env():
    env = os.environ.copy()
    runtime_dir = env.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    env["XDG_RUNTIME_DIR"] = runtime_dir
    bus = env.get("DBUS_SESSION_BUS_ADDRESS", "")
    if not bus or bus == "disabled:" or bus == "/dev/null":
        sock = os.path.join(runtime_dir, "bus")
        if os.path.exists(sock):
            env["DBUS_SESSION_BUS_ADDRESS"] = f"unix:path={sock}"
    return env


def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--min-age", type=int, default=int(os.environ.get("CTP_SCOPE_MIN_AGE", "60")))
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    runtime_dir = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    transient_dir = os.environ.get("SWEEP_TRANSIENT_DIR") or os.path.join(runtime_dir, "systemd", "transient")
    if not os.path.isdir(transient_dir):
        return 0

    user_slice = find_user_slice()
    if not user_slice or not os.path.isdir(user_slice):
        return 0

    now = time.time()
    victims = []
    for name in sorted(os.listdir(transient_dir)):
        if not PAT.match(name):
            continue
        fpath = os.path.join(transient_dir, name)
        try:
            st = os.lstat(fpath)
        except FileNotFoundError:
            continue
        if (now - st.st_mtime) < args.min_age:
            continue
        cgrp_dir = os.path.join(user_slice, name)
        if cgroup_is_nonempty(cgrp_dir):
            continue
        victims.append(name)

    if not victims:
        return 0

    if args.dry_run:
        for name in victims:
            print(name)
        return 0

    env = systemd_env()
    swept = 0
    for i in range(0, len(victims), 100):
        batch = victims[i : i + 100]
        try:
            subprocess.run(
                ["systemctl", "--user", "stop", "--", *batch],
                env=env,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=30,
                check=False,
            )
        except (OSError, subprocess.SubprocessError):
            pass

        for name in batch:
            fpath = os.path.join(transient_dir, name)
            cgrp_dir = os.path.join(user_slice, name)
            still_there = os.path.exists(fpath) or os.path.isdir(cgrp_dir)
            if not still_there:
                swept += 1
                continue
            if cgroup_is_nonempty(cgrp_dir):
                continue
            removed_any = False
            try:
                os.unlink(fpath)
                removed_any = True
            except FileNotFoundError:
                pass
            except OSError:
                pass
            if os.path.isdir(cgrp_dir) and not cgroup_is_nonempty(cgrp_dir):
                try:
                    os.rmdir(cgrp_dir)
                    removed_any = True
                except OSError as e:
                    if e.errno not in (errno.ENOENT, errno.EBUSY):
                        pass
            if removed_any:
                swept += 1

    try:
        res = subprocess.run(
            ["systemctl", "--user", "--failed", "--type=scope", "--plain", "--no-legend"],
            env=env,
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )
        failed = [
            line.split()[0]
            for line in res.stdout.splitlines()
            if line.strip() and PAT.match(line.split()[0])
        ]
        if failed:
            subprocess.run(
                ["systemctl", "--user", "reset-failed", "--", *failed],
                env=env,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=10,
                check=False,
            )
    except (OSError, subprocess.SubprocessError):
        pass

    if swept > 0:
        print(f"[ctp-run] swept {swept} empty podman scope(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
PY
