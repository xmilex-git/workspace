# CUBRID build/deploy — self-contained & portable (parallel-test campaign).
#
# Drives a CUBRID checkout's TRACKED CMakePresets.json (presets: debug | release | profile).
# Replicates ~/bin/build_cubrid.sh + set_cubrid_ver.sh INSTALL-PATH behavior:
#   - installs to a per-mode versioned dir   ~/<mode>/CUBRID-<version>
#   - repoints the ~/CUBRID symlink to it     (so $CUBRID reflects the active build)
#   - debug and release live in SEPARATE dirs; switch the active one with `just use <mode>`
#     (or by building it) — no clobbering between modes.
#   NOTE: mode "debug" is remapped to the optdebug preset — plain debug builds are retired.
# The prebuilt locale files (this repo's .claude/locale/) are copied into EVERY build — the
# all-locales lib is needed for CTP execution and rebuilding it via make_locale is slow.
# No machine-local scripts (~/bin/*.sh) or CMakeUserPresets.json required.
# The cubrid-cci submodule auto-inits on first build (needs network for the initial clone).
#
# WORKSPACE (the CUBRID source dir) is REQUIRED — this justfile lives in the standalone
# tooling repo, NOT inside a CUBRID checkout, so there is NO cwd default. Pass it explicitly:
#   WORKSPACE=/path/to/cubrid just build           (env var)
#   just workspace=/path/to/cubrid build           (just variable)
# Source-touching recipes (build/configure/rebuild/ctest/deploy) operate on $WORKSPACE.
# Shell-debug scratch files stay in this tooling repo's .git_ignored_dir/scratch/.
# Run `just` from THIS repo's root (so it finds this justfile and the bundled locale files).
#
# Usage:
#   WORKSPACE=<src> just build [debug|release] [version]   build + install to ~/<mode>/CUBRID-<version>, repoint ~/CUBRID
#   INSTALL_PREFIX=<dir> WORKSPACE=<src> just build [mode] [ver]   install to <dir> instead; ~/CUBRID symlink is NOT repointed
#                                                          (for isolated builds while another session uses ~/CUBRID)
#   WORKSPACE=<src> just debug | just release              aliases (default version)
#   just use   [debug|release] [version]                   only repoint ~/CUBRID to an already-installed dir
#   WORKSPACE=<src> just rebuild [mode] [version]          fresh configure + build + install + repoint
#   just conf                                              copy repo-root cubrid.conf -> $CUBRID/conf/cubrid.conf
#   just install-locale [dest]                             copy prebuilt locale files (lib+bin); auto-run by build/rebuild
#   WORKSPACE=<src> just deploy [mode] [version]           stop server (if any) -> build -> conf
#   WORKSPACE=<src> just ctest [mode]                      ctest against the build tree
#   just shell-debug <TEST_DIR>                            run one CTP shell test (or subtree) via ~/cubrid-testtools/CTP
#   just ctp-parallel [ORCH_ARGS...]                       run the whole CTP SQL suite in parallel podman shards
#
# Campaign: debug install for D1/D2/D3, release install for D4 — switch via `just use <mode>`.

set shell := ["bash", "-cu"]

# REQUIRED CUBRID source checkout. No cwd default (see header). Override per-invocation
# with `WORKSPACE=/path just <recipe>` or `just workspace=/path <recipe>`.
workspace := env_var_or_default("WORKSPACE", "")

jobs := env_var_or_default("JOBS", num_cpus())
ver  := env_var_or_default("CUBRID_VERSION", "11.5.develop")

# Default: list recipes.
default:
    @just --list

# Ensure build-critical git submodules are present (cubrid-cci). Inits on first build.
_submodules:
    #!/usr/bin/env bash
    set -eu
    ws="{{workspace}}"
    [ -n "$ws" ] || { echo "ERROR: WORKSPACE not set — pass the CUBRID source dir (e.g. 'WORKSPACE=/path/to/cubrid just build' or 'just workspace=/path/to/cubrid build')." >&2; exit 1; }
    [ -f "$ws/CMakePresets.json" ] || { echo "ERROR: '$ws' is not a CUBRID source checkout (no CMakePresets.json)." >&2; exit 1; }
    [ -f "$ws/cubrid-cci/CMakeLists.txt" ] || git -C "$ws" submodule update --init cubrid-cci

# Configure a preset's build tree with install prefix = ~/<mode>/CUBRID-<version>.
configure mode="debug" version=ver: _submodules
    #!/usr/bin/env bash
    set -eu
    mode="{{mode}}"; if [ "$mode" = debug ]; then mode=optdebug; fi
    ws="{{workspace}}"
    [ -n "$ws" ] || { echo "ERROR: WORKSPACE not set — pass the CUBRID source dir." >&2; exit 1; }
    [ -f "$ws/CMakePresets.json" ] || { echo "ERROR: '$ws' is not a CUBRID source checkout (no CMakePresets.json)." >&2; exit 1; }
    ( cd "$ws" && cmake --preset $mode -DCMAKE_INSTALL_PREFIX="${INSTALL_PREFIX:-$HOME/$mode/CUBRID-{{version}}}" )

# Build + install to ~/<mode>/CUBRID-<version>, copy locale files, then repoint ~/CUBRID -> there
# (mirrors build_cubrid.sh + set_cubrid_ver.sh install-path + locale behavior).
build mode="debug" version=ver: _submodules
    #!/usr/bin/env bash
    set -eu
    mode="{{mode}}"; if [ "$mode" = debug ]; then mode=optdebug; fi
    [ -n "${HOME:-}" ] || { echo "ERROR: \$HOME not set." >&2; exit 1; }
    ws="{{workspace}}"
    [ -n "$ws" ] || { echo "ERROR: WORKSPACE not set — pass the CUBRID source dir." >&2; exit 1; }
    [ -f "$ws/CMakePresets.json" ] || { echo "ERROR: '$ws' is not a CUBRID source checkout (no CMakePresets.json)." >&2; exit 1; }
    dest="${INSTALL_PREFIX:-$HOME/$mode/CUBRID-{{version}}}"
    echo "install dest: $dest${INSTALL_PREFIX:+  (INSTALL_PREFIX override — ~/CUBRID untouched)}"
    mkdir -p "$dest"
    ( cd "$ws" && cmake --preset $mode -DCMAKE_INSTALL_PREFIX="$dest" \
                && cmake --build "build_preset_$mode" -j {{jobs}} --target install )
    [ -x "$dest/bin/cubrid" ] || { echo "ERROR: install did not land in $dest (bin/cubrid missing) — stale justfile copy or preset prefix override?" >&2; exit 1; }
    just install-locale "$dest"
    echo "installed $mode ($ws) -> $dest"
    if [ -n "${INSTALL_PREFIX:-}" ]; then
        echo "INSTALL_PREFIX set — ~/CUBRID symlink left untouched"
    else
        ln -sfn "$dest" "$HOME/CUBRID"
        echo "~/CUBRID -> $(readlink "$HOME/CUBRID")"
    fi

# Incremental build + install into an already-configured preset tree — no reconfigure,
# no locale copy, ~/CUBRID symlink untouched. The install prefix is whatever the tree
# was configured with (check: grep CMAKE_INSTALL_PREFIX build_preset_<mode>/CMakeCache.txt).
incr mode="release":
    #!/usr/bin/env bash
    set -eu
    mode="{{mode}}"; if [ "$mode" = debug ]; then mode=optdebug; fi
    ws="{{workspace}}"
    [ -n "$ws" ] || { echo "ERROR: WORKSPACE not set — pass the CUBRID source dir." >&2; exit 1; }
    [ -f "$ws/build_preset_$mode/CMakeCache.txt" ] || { echo "ERROR: '$ws/build_preset_$mode' is not configured — run 'just configure $mode' (or 'just build') first." >&2; exit 1; }
    dest=$(sed -n 's/^CMAKE_INSTALL_PREFIX:PATH=//p' "$ws/build_preset_$mode/CMakeCache.txt")
    echo "incremental install dest: $dest"
    ( cd "$ws" && cmake --build "build_preset_$mode" -j {{jobs}} --target install )
    [ -x "$dest/bin/cubrid" ] || { echo "ERROR: install did not land in $dest (bin/cubrid missing)." >&2; exit 1; }
    echo "installed (incremental) $mode ($ws) -> $dest"

# Convenience aliases (default version).
debug: (build "debug")
release: (build "release")
optdebug: (build "optdebug")

# Only repoint ~/CUBRID to an already-installed versioned dir (set_cubrid_ver.sh equivalent).
# Operates purely on the install tree under $HOME — no CUBRID source needed.
use mode="debug" version=ver:
    #!/usr/bin/env bash
    set -eu
    mode="{{mode}}"; if [ "$mode" = debug ]; then mode=optdebug; fi
    dest="$HOME/$mode/CUBRID-{{version}}"
    [ -d "$dest" ] || { echo "ERROR: not installed: $dest (build it first)" >&2; exit 1; }
    ln -sfn "$dest" "$HOME/CUBRID"
    echo "~/CUBRID -> $(readlink "$HOME/CUBRID")"

# Force a fresh configure + build + install (+ locale) + repoint.
rebuild mode="debug" version=ver: _submodules
    #!/usr/bin/env bash
    set -eu
    mode="{{mode}}"; if [ "$mode" = debug ]; then mode=optdebug; fi
    ws="{{workspace}}"
    [ -n "$ws" ] || { echo "ERROR: WORKSPACE not set — pass the CUBRID source dir." >&2; exit 1; }
    [ -f "$ws/CMakePresets.json" ] || { echo "ERROR: '$ws' is not a CUBRID source checkout (no CMakePresets.json)." >&2; exit 1; }
    dest="${INSTALL_PREFIX:-$HOME/$mode/CUBRID-{{version}}}"
    echo "install dest: $dest${INSTALL_PREFIX:+  (INSTALL_PREFIX override — ~/CUBRID untouched)}"
    ( cd "$ws" && rm -rf "build_preset_$mode" )
    mkdir -p "$dest"
    ( cd "$ws" && cmake --preset $mode -DCMAKE_INSTALL_PREFIX="$dest" \
                && cmake --build "build_preset_$mode" -j {{jobs}} --target install )
    [ -x "$dest/bin/cubrid" ] || { echo "ERROR: install did not land in $dest (bin/cubrid missing) — stale justfile copy or preset prefix override?" >&2; exit 1; }
    just install-locale "$dest"
    echo "installed $mode ($ws) -> $dest"
    if [ -n "${INSTALL_PREFIX:-}" ]; then
        echo "INSTALL_PREFIX set — ~/CUBRID symlink left untouched"
    else
        ln -sfn "$dest" "$HOME/CUBRID"
        echo "~/CUBRID -> $(readlink "$HOME/CUBRID")"
    fi

# Copy the prebuilt locale files into an install's lib/ & bin/ (build_cubrid.sh behavior).
# Sourced from THIS repo's .claude/locale/ (resolved absolutely, so cwd does not matter).
# The all-locales lib is needed for CTP execution; shipping it avoids the slow make_locale rebuild.
# Auto-run at the end of `just build` / `just rebuild`. dest defaults to $CUBRID.
install-locale dest=env_var_or_default("CUBRID", ""):
    #!/usr/bin/env bash
    set -eu
    dest="{{dest}}"
    [ -n "$dest" ] || { echo "ERROR: no dest given and \$CUBRID not set." >&2; exit 1; }
    so="{{justfile_directory()}}/.claude/locale/libcubrid_all_locales.so"
    sh="{{justfile_directory()}}/.claude/locale/make_locale.sh"
    if [ -f "$so" ]; then cp -f "$so" "$dest/lib/" && echo "locale: libcubrid_all_locales.so -> $dest/lib/"; else echo "locale: $so missing (skipped)"; fi
    if [ -f "$sh" ]; then cp -f "$sh" "$dest/bin/" && echo "locale: make_locale.sh -> $dest/bin/";          else echo "locale: $sh missing (skipped)"; fi

# Apply campaign test conf to $CUBRID/conf/cubrid.conf.
# Copies the canonical cubrid.conf from this repo (single source of truth for campaign
# parameters) into the active CUBRID install.  Edit cubrid.conf at the repo root to
# change parameters — no more sed/grep patching.
conf:
    #!/usr/bin/env bash
    set -eu
    [ -n "${CUBRID:-}" ] || { echo "ERROR: \$CUBRID not set." >&2; exit 1; }
    dest="$CUBRID/conf/cubrid.conf"
    src="{{justfile_directory()}}/cubrid.conf"
    [ -f "$src" ] || { echo "ERROR: $src not found." >&2; exit 1; }
    [ -d "$CUBRID/conf" ] || { echo "ERROR: $CUBRID/conf/ not found (build/install first)." >&2; exit 1; }
    cp -f "$src" "$dest"
    echo "copied $src -> $dest"

# Ensure ALL conf files that CTP/shell expects exist in $CUBRID/conf/.
# CTP shell backup/restore + ini.sh cycle can delete cubrid_ha.conf, cm.conf,
# cubrid_gateway.conf, etc.  When missing, ini.sh crashes and subsequent
# cubrid commands emit "Can't access system configuration file" to stderr,
# causing false diff failures in shell TCs.
# Uses the CUBRID source checkout (WORKSPACE) to get canonical defaults;
# falls back to minimal stubs when WORKSPACE is unavailable.
_ensure-conf-full:
    #!/usr/bin/env bash
    set -eu
    [ -n "${CUBRID:-}" ] || { echo "ERROR: \$CUBRID not set." >&2; exit 1; }
    confdir="$CUBRID/conf"
    [ -d "$confdir" ] || { echo "ERROR: $confdir not found." >&2; exit 1; }
    ws="{{workspace}}"
    srcconf=""
    if [ -n "$ws" ] && [ -d "$ws/conf" ]; then
        srcconf="$ws/conf"
    elif [ -d "${CUBRID_SRC:-}/conf" ]; then
        srcconf="${CUBRID_SRC}/conf"
    fi
    restored=0
    for f in cubrid_ha.conf cubrid_broker.conf cubrid_gateway.conf cubrid_hosts.conf; do
        if [ ! -f "$confdir/$f" ]; then
            if [ -n "$srcconf" ] && [ -f "$srcconf/$f" ]; then
                cp -f "$srcconf/$f" "$confdir/$f"
                echo "conf: restored $f from source"
            else
                # Create minimal stub so ini.sh / CTP backup/restore won't crash
                case "$f" in
                    cubrid_ha.conf)
                        printf '[common]\nha_mode=yes\n' > "$confdir/$f" ;;
                    cubrid_gateway.conf)
                        printf '[gateway]\nMASTER_SHM_ID=40001\n' > "$confdir/$f" ;;
                    cubrid_hosts.conf)
                        printf '# hosts\n' > "$confdir/$f" ;;
                    *)
                        touch "$confdir/$f" ;;
                esac
                echo "conf: created stub $f"
            fi
            restored=$((restored+1))
        fi
    done
    # cm.conf is expected by CTP but not shipped by cmake install
    if [ ! -f "$confdir/cm.conf" ]; then
        printf '[cm]\ncm_port=8001\n' > "$confdir/cm.conf"
        echo "conf: created stub cm.conf"
        restored=$((restored+1))
    fi
    if [ $restored -eq 0 ]; then
        echo "conf: all CTP-required conf files present"
    fi
    # CTP shell's resetCUBRID() does `rm -rf $CUBRID/conf/*` then
    # `cp -rf ~/.CUBRID_SHELL_FM/conf/* $CUBRID/conf/`.  When $CUBRID
    # (~/CUBRID) is a symlink, CTP's DeployOneNode does
    #   `cp -r ${CUBRID} ~/.CUBRID_SHELL_FM`
    # which creates ANOTHER symlink (cp -r preserves symlinks on Linux).
    # Then the rm wipes the only real copy → "Can't access" errors.
    #
    # Fix: materialize the ~/CUBRID symlink into a real directory.
    # `just use`/`just build` will recreate the symlink on next build,
    # and _ensure-conf-full will re-materialize it on next CTP run.
    cubrid_path="$CUBRID"
    if [ -L "$cubrid_path" ]; then
        real_target="$(readlink -f "$cubrid_path")"
        rm "$cubrid_path"                       # remove the symlink itself
        cp -rL "$real_target" "$cubrid_path"     # copy the real dir in its place
        echo "conf: materialized $cubrid_path symlink → real dir (was → $real_target)"
    fi
    # Now rebuild .CUBRID_SHELL_FM as a real copy (CTP will recreate it with
    # `cp -r $CUBRID`, which now copies a real directory → real backup).
    fm="$HOME/.CUBRID_SHELL_FM"
    if [ -L "$fm" ] || [ ! -d "$fm/conf" ] || [ ! -f "$fm/conf/cubrid.conf" ]; then
        rm -rf "$fm"
        cp -r "$CUBRID" "$fm"
        echo "conf: rebuilt .CUBRID_SHELL_FM (real copy)"
    fi

# Full local refresh: stop server (if any) -> build -> conf.
# `cubrid service stop` output is detached to avoid the known pipe-hang under captured shells.
# Forwards WORKSPACE to the nested build (so `just workspace=... deploy` works too).
deploy mode="debug" version=ver:
    -cubrid service stop </dev/null >/dev/null 2>&1
    just workspace="{{workspace}}" build {{mode}} {{version}}
    just conf

# ctest (unit + sql-level) against a build tree inside the CUBRID source dir.
ctest mode="debug":
    #!/usr/bin/env bash
    set -eu
    mode="{{mode}}"; if [ "$mode" = debug ]; then mode=optdebug; fi
    ws="{{workspace}}"
    [ -n "$ws" ] || { echo "ERROR: WORKSPACE not set — pass the CUBRID source dir." >&2; exit 1; }
    cd "$ws"
    ctest --test-dir "build_preset_$mode" --output-on-failure

# Run one or a limited range of CTP shell tests against the local build.
# Powers the `cubrid-shell-run` skill. CTP's stock shell_ci.conf runs *everything*
# under scenario=; this copies it, repoints scenario= at one directory, and disables
# the testcase git auto-update so a debug run never mutates ~/cubrid-testcases-private-ex.
# CTP runs against the install on PATH (not the build tree) — rebuild/reinstall first
# if you changed src/.
#
# Throwaway CTP files always live in this tooling workspace's
# .git_ignored_dir/scratch/ (NOT /tmp and not the target engine checkout).
#
# ARG SHAPE
#   TEST_DIR must be the directory that *contains* `cases/<name>.sh`, NOT the .sh itself.
#   Pass any ancestor directory to run a wider subtree (CTP recurses).
#
# Usage:
#   just shell-debug ~/cubrid-testcases-private-ex/shell/_06_issues/_10_1h/bug_1638
shell-debug TEST_DIR: conf _ensure-conf-full
    #!/usr/bin/env bash
    set -euo pipefail
    # CTP requires these in the environment (vimkim's .envrc exports the same two).
    # `just` recipes run in a non-login shell that does not source the profile, so
    # set them here to keep the recipe self-contained.
    export CTP_HOME="${CTP_HOME:-$HOME/cubrid-testtools/CTP}"
    export init_path="${init_path:-$CTP_HOME/shell/init_path}"
    SRC="$CTP_HOME/conf/shell_ci.conf"
    [ -f "$SRC" ] || { echo "ERROR: CTP conf not found: $SRC (is CTP installed?)" >&2; exit 1; }
    SCRATCH="{{justfile_directory()}}/.git_ignored_dir/scratch"
    mkdir -p "$SCRATCH"
    CONF=$(mktemp "$SCRATCH/shell_single.XXXXXX.conf")
    cp "$SRC" "$CONF"
    sed -i "s|^scenario=.*|scenario={{TEST_DIR}}|"              "$CONF"
    sed -i "s|^testcase_update_yn=.*|testcase_update_yn=false|" "$CONF"
    sed -i "s|^testcase_exclude_from_file=.*|#&|"               "$CONF"
    echo "[shell-debug] scenario={{TEST_DIR}}"
    echo "[shell-debug] conf=$CONF"
    # Wrap in script(1) for a pseudo-TTY: avoids the known pipe-hang when `cubrid
    # server start/stop` output is captured by a non-TTY (CI, agent shells).
    # -q quiet, -e return the child's exit code, -f flush, -c run the command.
    script -qefc "$CTP_HOME/bin/ctp.sh shell -c $CONF" /dev/null

# Semantic alias for shell-debug — signals "run a whole bucket" at the call site.
shell-debug-many SUBTREE: (shell-debug SUBTREE)

# Run explicit, non-contiguous test directories in one CTP session.
# Every argument must be a leaf test directory containing cases/<dirname>.sh,
# and all directories must belong to the same shell testcase checkout.
shell-debug-selected +TEST_DIRS: conf _ensure-conf-full
    #!/usr/bin/env bash
    set -euo pipefail
    export CTP_HOME="${CTP_HOME:-$HOME/cubrid-testtools/CTP}"
    export init_path="${init_path:-$CTP_HOME/shell/init_path}"
    SRC="$CTP_HOME/conf/shell_ci.conf"
    [ -f "$SRC" ] || { echo "ERROR: CTP conf not found: $SRC (is CTP installed?)" >&2; exit 1; }
    dirs=( {{TEST_DIRS}} )
    first="${dirs[0]}"
    first="$(realpath "$first")"
    tc_root="$(git -C "$first" rev-parse --show-toplevel)"
    shell_root="$tc_root/shell"
    selected=()
    for dir in "${dirs[@]}"; do
        dir="$(realpath "$dir")"
        [ "$(git -C "$dir" rev-parse --show-toplevel)" = "$tc_root" ] || {
            echo "ERROR: all test directories must belong to the same testcase checkout." >&2
            exit 1
        }
        name="$(basename "$dir")"
        [ -f "$dir/cases/$name.sh" ] || {
            echo "ERROR: expected test script: $dir/cases/$name.sh" >&2
            exit 1
        }
        selected+=("$dir")
    done
    SCRATCH="{{justfile_directory()}}/.git_ignored_dir/scratch"
    mkdir -p "$SCRATCH"
    EXCLUDES=$(mktemp "$SCRATCH/shell_selected_excludes.XXXXXX.conf")
    python3 - "$shell_root" "$EXCLUDES" "${selected[@]}" <<'PY'
    import os
    import sys

    shell_root, output, *selected = sys.argv[1:]
    selected = {os.path.realpath(path) for path in selected}
    home = os.path.realpath(os.environ.get("CTP_EXEC_HOME", os.path.expanduser("~")))
    excluded = []
    for root, dirs, files in os.walk(shell_root):
        if os.path.basename(root) != "cases":
            continue
        test_dir = os.path.realpath(os.path.dirname(root))
        test_name = os.path.basename(test_dir) + ".sh"
        if test_name in files and test_dir not in selected:
            excluded.append(os.path.relpath(test_dir, home))
    with open(output, "w", encoding="utf-8") as stream:
        for path in sorted(excluded):
            stream.write(path + "\n")
    PY
    CONF=$(mktemp "$SCRATCH/shell_selected.XXXXXX.conf")
    cp "$SRC" "$CONF"
    sed -i "s|^scenario=.*|scenario=$shell_root|" "$CONF"
    sed -i "s|^testcase_update_yn=.*|testcase_update_yn=false|" "$CONF"
    sed -i "s|^testcase_exclude_from_file=.*|testcase_exclude_from_file=$EXCLUDES|" "$CONF"
    echo "[shell-debug-selected] scenario=$shell_root"
    echo "[shell-debug-selected] selected=${#selected[@]}"
    printf '[shell-debug-selected] test=%s\n' "${selected[@]}"
    echo "[shell-debug-selected] conf=$CONF"
    script -qefc "$CTP_HOME/bin/ctp.sh shell -c $CONF" /dev/null

# Run selected tests against the local OptDebug install used by CircleCI shell jobs.
# Build it first with: WORKSPACE=<src> just optdebug
shell-debug-optdebug +TEST_DIRS:
    #!/usr/bin/env bash
    set -euo pipefail
    source_workspace="{{workspace}}"
    install="${OPTDEBUG_CUBRID:-$HOME/optdebug/CUBRID-{{ver}}}"
    [ -x "$install/bin/cubrid_rel" ] || {
        echo "ERROR: OptDebug install not found: $install" >&2
        echo "Build it with: WORKSPACE=${source_workspace:-<cubrid-src>} just optdebug" >&2
        exit 1
    }
    install="$(realpath "$install")"
    real_home="$HOME"
    export CUBRID="$install"
    export PATH="$CUBRID/bin:$PATH"
    export LD_LIBRARY_PATH="$CUBRID/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    export SHLIB_PATH="$CUBRID/lib${SHLIB_PATH:+:$SHLIB_PATH}"
    export LIBPATH="$CUBRID/lib${LIBPATH:+:$LIBPATH}"
    export CTP_HOME="${CTP_HOME:-$real_home/cubrid-testtools/CTP}"
    export init_path="${init_path:-$CTP_HOME/shell/init_path}"
    version="$("$CUBRID/bin/cubrid_rel")"
    printf '%s\n' "$version"
    [[ "${version,,}" == *"optdebug build"* ]] || {
        echo "ERROR: $install is not an OptDebug install." >&2
        exit 1
    }
    scratch="{{justfile_directory()}}/.git_ignored_dir/scratch"
    mkdir -p "$scratch"
    runtime_home=$(mktemp -d "$scratch/ctp_optdebug_home.XXXXXX")
    trap 'rm -rf "$runtime_home"' EXIT
    profile="$runtime_home/.bash_profile"
    {
        printf 'export HOME=%q\n' "$real_home"
        printf 'export CUBRID=%q\n' "$CUBRID"
        printf 'export PATH=%q\n' "$PATH"
        printf 'export LD_LIBRARY_PATH=%q\n' "$LD_LIBRARY_PATH"
        printf 'export SHLIB_PATH=%q\n' "$SHLIB_PATH"
        printf 'export LIBPATH=%q\n' "$LIBPATH"
        printf 'export CTP_HOME=%q\n' "$CTP_HOME"
        printf 'export init_path=%q\n' "$init_path"
    } > "$profile"
    export CTP_EXEC_HOME="$real_home"
    export HOME="$runtime_home"
    just shell-debug-selected {{TEST_DIRS}}

# REMOVED (2026-08-28): the host-side CTP SQL recipes. `ctp.sh sql` runs
# `pkill cub` in its do_clean()/teardown — it kills EVERY cub_master/cub_server/
# cub_broker of this user on any port, and the port registry cannot protect
# against it (incident: it killed another session's claimed server). CTP SQL
# therefore runs ONLY via podman isolation:
#   just ctp-sql-isolated <TEST_DIRS...>    subset, one container
#   just ctp-parallel                       full suite, N shards
# Custom server params (e.g. lowered parallel thresholds): CTP applies the
# [sql/cubrid.conf] section of $CTP_HOME/conf/sql.conf inside the container
# too — point CTP_HOME at a modified CTP copy for such runs.
# The stubs below stay so a stale habit gets the WHY instead of "unknown
# recipe". Do NOT resurrect the host-side bodies from git history.
[doc("REMOVED — use ctp-sql-isolated (host CTP SQL pkills every cub_* of this user)")]
sql-debug TEST_DIR:
    @echo "REFUSED: 'just sql-debug' was removed — host-side CTP SQL pkills every cub_* of this user (any port)." >&2
    @echo "Use instead:  just ctp-sql-isolated {{TEST_DIR}}" >&2
    @exit 1

[doc("REMOVED — use ctp-sql-isolated (host CTP SQL pkills every cub_* of this user)")]
sql-debug-selected +TEST_DIRS:
    @echo "REFUSED: 'just sql-debug-selected' was removed — host-side CTP SQL pkills every cub_* of this user (any port)." >&2
    @echo "Use instead:  just ctp-sql-isolated {{TEST_DIRS}}" >&2
    @exit 1

# Interactive picker against the UNMODIFIED conf (testcase_update_yn=true still git-pulls).
shell-debug-interactive:
    #!/usr/bin/env bash
    set -euo pipefail
    export CTP_HOME=~/cubrid-testtools/CTP
    export init_path="$CTP_HOME/shell/init_path"
    "$CTP_HOME/bin/ctp.sh" shell --interactive -c "$CTP_HOME/conf/shell_ci.conf"

# Run the full CTP SQL suite in N parallel rootless-podman shards (the `ctp-parallel` skill).
# Thin wrapper: it execs the CANONICAL orchestrator in .agents/skills/ctp-parallel/ (no copy
# of the split/merge logic lives here). A bare `just ctp-parallel` is the one-click form and
# uses the skill's optimal defaults (7 shards, per-bulk split, time-balanced) with:
#   build      ${CUBRID}   or $HOME/CUBRID
#   testcases  ${TESTCASES} or $HOME/cubrid-testcases
#   CTP_HOME   ${CTP_HOME}  or $HOME/cubrid-testtools/CTP
#   out        this repo's .git_ignored_dir/scratch/ctp-parallel-out   (never /tmp)
# Any extra arguments are forwarded to the orchestrator verbatim (quoting/space safe), and
# since its parser takes the LAST occurrence of an option, an explicit --out/--build/
# --testcases/--ctp overrides the default above. Run `just ctp-parallel --help` for all flags.
#
# Usage:
#   just ctp-parallel                                   full parallel run, defaults
#   just ctp-parallel --dry-run                          plan + validate the split only (no podman)
#   just ctp-parallel --shards 10 --no-webconsole        CircleCI-parity shard count, skip the merge
#   just ctp-parallel --env CUBRID_WM_SORT_NEW=1         extra env vars into every shard container
#   just ctp-parallel --out /some/other/out-dir          explicit output dir (wins over the default)
[doc("Run the whole CTP SQL suite in parallel podman shards (ctp-parallel skill)")]
[positional-arguments]
ctp-parallel *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    orch="{{justfile_directory()}}/.agents/skills/ctp-parallel/scripts/ctp_parallel.sh"
    [ -x "$orch" ] || { echo "ERROR: ctp-parallel orchestrator not found/executable: $orch" >&2; exit 1; }
    out="{{justfile_directory()}}/.git_ignored_dir/scratch/ctp-parallel-out"
    mkdir -p "$(dirname "$out")"
    exec "$orch" \
        --build      "${CUBRID:-$HOME/CUBRID}" \
        --testcases  "${TESTCASES:-$HOME/cubrid-testcases}" \
        --ctp        "${CTP_HOME:-$HOME/cubrid-testtools/CTP}" \
        --out        "$out" \
        "$@"

# Run a SUBSET of the CTP SQL suite inside ONE isolated podman container.
#
# WHY THIS EXISTS: host-side CTP SQL (`ctp.sh sql`; the old `just sql-debug*` recipes
# are removed and stubbed to refuse)
# runs `pkill cub` in its do_clean()/teardown — it kills EVERY cub_master/cub_server/
# cub_broker of this user, on any port, defeating the port registry (incident
# 2026-08-28: a gate run killed another session's claimed server). Inside podman the
# pkill only sees the container's own processes, so concurrent agents can each run
# their own TC subsets without stopping each other's servers.
#
# HOW: thin wrapper over the canonical ctp-parallel orchestrator (1 shard,
# no webconsole merge). It synthesizes a private testcases root holding ONLY the
# requested subtrees (host testcases checkout untouched), gives every invocation
# its own run dir (UTC timestamp + PID) so concurrent runs never share paths, and
# copies the build into the container workdir (host $CUBRID conf/processes untouched).
#
# ARG SHAPE: each TEST_DIR is a directory under a testcases checkout's sql/ tree
# (leaf with cases/*.sql, or any ancestor bucket). A .sql file resolves to its test
# dir. All arguments must live under the SAME sql/ root.
# Build source: $BUILD, else $CUBRID, else ~/CUBRID (copied, never mutated).
#
# Usage:
#   just ctp-sql-isolated ~/cubrid-testcases/sql/_08_javasp
#   just ctp-sql-isolated ~/cubrid-testcases/sql/_13_issues/_23_1h ~/cubrid-testcases/sql/_35_fig_cake/cbrd_25382
#   BUILD=~/optdebug/CUBRID-x just ctp-sql-isolated ~/cubrid-testcases/sql/_08_javasp
[doc("Run selected CTP SQL dirs in one isolated podman container (no host cub_* touched)")]
ctp-sql-isolated +TEST_DIRS:
    #!/usr/bin/env bash
    set -euo pipefail
    orch="{{justfile_directory()}}/.agents/skills/ctp-parallel/scripts/ctp_parallel.sh"
    [ -x "$orch" ] || { echo "ERROR: ctp-parallel orchestrator not found/executable: $orch" >&2; exit 1; }
    command -v podman >/dev/null 2>&1 || { echo "ERROR: podman not found — the isolated runner requires it. (Never fall back to host ctp.sh: its teardown pkills every cub_* of this user.)" >&2; exit 1; }
    build="${BUILD:-${CUBRID:-$HOME/CUBRID}}"
    build="$(realpath "$build")"
    [ -x "$build/bin/cubrid" ] || { echo "ERROR: '$build' is not a CUBRID install (bin/cubrid missing). Set BUILD= or CUBRID=." >&2; exit 1; }
    # Resolve every TEST_DIR to (sql_root, relpath-under-sql_root); require one shared root.
    sql_root=""
    rels=()
    for arg in {{TEST_DIRS}}; do
        t="$arg"
        [[ "$t" == *.sql ]] && t="$(dirname "$(dirname "$t")")"
        t="$(realpath "$t")"
        [ -d "$t" ] || { echo "ERROR: directory not found: $t" >&2; exit 1; }
        r="$t"
        while [ "$r" != "/" ] && [ "$(basename "$r")" != "sql" ]; do r="$(dirname "$r")"; done
        [ "$r" != "/" ] || { echo "ERROR: '$t' is not under a testcases sql/ tree." >&2; exit 1; }
        if [ -z "$sql_root" ]; then sql_root="$r"; fi
        [ "$r" = "$sql_root" ] || { echo "ERROR: all TEST_DIRS must share one sql/ root ($sql_root vs $r)." >&2; exit 1; }
        rels+=("${t#"$(dirname "$sql_root")"/}")   # e.g. sql/_08_javasp/foo
    done
    # Private per-invocation run dir: concurrent agents never share paths.
    run="{{justfile_directory()}}/.git_ignored_dir/scratch/ctp-iso/$(date -u +%Y%m%dT%H%M%SZ)-$$"
    tcroot="$run/testcases"
    mkdir -p "$tcroot"
    src_parent="$(dirname "$sql_root")"
    if command -v rsync >/dev/null 2>&1; then
        ( cd "$src_parent" && rsync -aR --exclude='*.result' --exclude='*.log' "${rels[@]}" "$tcroot/" )
    else
        ( cd "$src_parent" && for r in "${rels[@]}"; do
              find "$r" -type f ! -name '*.result' ! -name '*.log' -exec cp --parents -a {} "$tcroot/" \; ; done )
    fi
    echo "[ctp-sql-isolated] build=$build"
    echo "[ctp-sql-isolated] subset=${rels[*]}"
    echo "[ctp-sql-isolated] run dir=$run  (results: $run/out)"
    exec "$orch" \
        --build      "$build" \
        --testcases  "$tcroot" \
        --ctp        "${CTP_HOME:-$HOME/cubrid-testtools/CTP}" \
        --out        "$run/out" \
        --shards 1 --no-webconsole

# ---------------------------------------------------------------------------
# CUBRID port registry — machine-local claims so concurrent Claude sessions
# never start servers on colliding ports. Protocol: docs/agents/port-registry.md
# Claims live in .git_ignored_dir/port-registry/claims.md (git-ignored).
#   just ports                         show claims + live CUBRID listeners
#   just port-claim <db> <effort>      auto-pick a free cubrid_port_id in 1700-1799,
#                                      reserve a 100-block of broker ports, append the claim
#   just port-release <db-or-port>     drop the matching claim line(s)
# ---------------------------------------------------------------------------

_ports_file := justfile_directory() / ".git_ignored_dir/port-registry/claims.md"

# Show active port claims and live listeners.
[doc("Show CUBRID port claims (port registry) + live listeners")]
ports:
    #!/usr/bin/env bash
    set -eu
    f="{{_ports_file}}"
    if [ -f "$f" ]; then cat "$f"; else echo "(no claims file yet: $f)"; fi
    echo
    echo "-- live listeners (cub_*, 1500-1799, 30000+) --"
    ss -ltnp 2>/dev/null | awk 'NR==1 || /cub_/ || /:1[5-7][0-9][0-9] / || /:3[0-9]{4} /' || true

# Claim a free cubrid_port_id (1700-1799) + broker 100-block for <db>/<effort>.
[doc("Claim a free cubrid_port_id + broker block in the port registry")]
port-claim db effort:
    #!/usr/bin/env bash
    set -eu
    f="{{_ports_file}}"
    mkdir -p "$(dirname "$f")"
    if [ ! -f "$f" ]; then
        {
            echo "# Active port claims — see docs/agents/port-registry.md for the protocol"
            echo
            echo "| cubrid_port_id | broker ports | db name | session/effort | date |"
            echo "|---|---|---|---|---|"
        } > "$f"
    fi
    if awk -F'|' 'NR>2 && $4 ~ /[^ ]/ {gsub(/ /,"",$4); print $4}' "$f" | grep -qx "{{db}}"; then
        echo "ERROR: db '{{db}}' already has a claim — release it first (just port-release {{db}})." >&2
        exit 1
    fi
    claimed=$(awk -F'|' 'NR>2 {gsub(/ /,"",$2); if ($2 ~ /^[0-9]+$/) print $2}' "$f")
    listening=$(ss -ltn 2>/dev/null | awk 'NR>1 {n=split($4,a,":"); print a[n]}')
    port=""
    for p in $(seq 1700 1799); do
        echo "$claimed"   | grep -qx "$p" && continue
        echo "$listening" | grep -qx "$p" && continue
        port=$p; break
    done
    [ -n "$port" ] || { echo "ERROR: no free port in 1700-1799." >&2; exit 1; }
    idx=$((port - 1700))
    blo=$((36000 + idx * 100)); bhi=$((blo + 99))
    printf '| %s | %s-%s | %s | %s | %s |\n' "$port" "$blo" "$bhi" "{{db}}" "{{effort}}" "$(date +%F)" >> "$f"
    echo "claimed: cubrid_port_id=$port broker=$blo-$bhi db={{db}} effort='{{effort}}'"
    echo "server conf:  cubrid_port_id=$port   (set in \$CUBRID/conf/cubrid.conf or CUBRID_PORT_ID env)"
    echo "registry: $f"

# Release claim line(s) matching a db name or a cubrid_port_id.
[doc("Release a port claim by db name or port number")]
port-release key:
    #!/usr/bin/env bash
    set -eu
    f="{{_ports_file}}"
    [ -f "$f" ] || { echo "ERROR: no claims file: $f" >&2; exit 1; }
    before=$(wc -l < "$f")
    awk -F'|' -v key="{{key}}" '
        NR<=4 {print; next}
        { p=$2; d=$4; gsub(/ /,"",p); gsub(/ /,"",d);
          if (p==key || d==key) next; print }
    ' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
    after=$(wc -l < "$f")
    removed=$((before - after))
    [ "$removed" -gt 0 ] || { echo "WARNING: no claim matched '{{key}}'." >&2; exit 1; }
    echo "released $removed claim(s) matching '{{key}}'"
