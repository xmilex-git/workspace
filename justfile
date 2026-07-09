# CUBRID build/deploy — self-contained & portable (parallel-test campaign).
#
# Drives a CUBRID checkout's TRACKED CMakePresets.json (presets: debug | release | profile).
# Replicates ~/bin/build_cubrid.sh + set_cubrid_ver.sh INSTALL-PATH behavior:
#   - installs to a per-mode versioned dir   ~/<mode>/CUBRID-<version>
#   - repoints the ~/CUBRID symlink to it     (so $CUBRID reflects the active build)
#   - debug and release live in SEPARATE dirs; switch the active one with `just use <mode>`
#     (or by building it) — no clobbering between modes.
# The prebuilt locale files (this repo's .claude/locale/) are copied into EVERY build — the
# all-locales lib is needed for CTP execution and rebuilding it via make_locale is slow.
# No machine-local scripts (~/bin/*.sh) or CMakeUserPresets.json required.
# The cubrid-cci submodule auto-inits on first build (needs network for the initial clone).
#
# WORKSPACE (the CUBRID source dir) is REQUIRED — this justfile lives in the standalone
# tooling repo, NOT inside a CUBRID checkout, so there is NO cwd default. Pass it explicitly:
#   WORKSPACE=/path/to/cubrid just build           (env var)
#   just workspace=/path/to/cubrid build           (just variable)
# Source-touching recipes (build/configure/rebuild/ctest/deploy) operate on $WORKSPACE;
# shell-debug also needs it (its scratch conf lives in $WORKSPACE/.git_ignored_dir/scratch).
# Run `just` from THIS repo's root (so it finds this justfile and the bundled locale files).
#
# Usage:
#   WORKSPACE=<src> just build [debug|release] [version]   build + install to ~/<mode>/CUBRID-<version>, repoint ~/CUBRID
#   WORKSPACE=<src> just debug | just release              aliases (default version)
#   just use   [debug|release] [version]                   only repoint ~/CUBRID to an already-installed dir
#   WORKSPACE=<src> just rebuild [mode] [version]          fresh configure + build + install + repoint
#   just conf                                              copy repo-root cubrid.conf -> $CUBRID/conf/cubrid.conf
#   just install-locale [dest]                             copy prebuilt locale files (lib+bin); auto-run by build/rebuild
#   WORKSPACE=<src> just deploy [mode] [version]           stop server (if any) -> build -> conf
#   WORKSPACE=<src> just ctest [mode]                      ctest against the build tree
#   WORKSPACE=<src> just shell-debug <TEST_DIR>            run one CTP shell test (or subtree) via ~/cubrid-testtools/CTP
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
    ws="{{workspace}}"
    [ -n "$ws" ] || { echo "ERROR: WORKSPACE not set — pass the CUBRID source dir." >&2; exit 1; }
    [ -f "$ws/CMakePresets.json" ] || { echo "ERROR: '$ws' is not a CUBRID source checkout (no CMakePresets.json)." >&2; exit 1; }
    ( cd "$ws" && cmake --preset {{mode}} -DCMAKE_INSTALL_PREFIX="$HOME/{{mode}}/CUBRID-{{version}}" )

# Build + install to ~/<mode>/CUBRID-<version>, copy locale files, then repoint ~/CUBRID -> there
# (mirrors build_cubrid.sh + set_cubrid_ver.sh install-path + locale behavior).
build mode="debug" version=ver: _submodules
    #!/usr/bin/env bash
    set -eu
    [ -n "${HOME:-}" ] || { echo "ERROR: \$HOME not set." >&2; exit 1; }
    ws="{{workspace}}"
    [ -n "$ws" ] || { echo "ERROR: WORKSPACE not set — pass the CUBRID source dir." >&2; exit 1; }
    [ -f "$ws/CMakePresets.json" ] || { echo "ERROR: '$ws' is not a CUBRID source checkout (no CMakePresets.json)." >&2; exit 1; }
    dest="$HOME/{{mode}}/CUBRID-{{version}}"
    mkdir -p "$dest"
    ( cd "$ws" && cmake --preset {{mode}} -DCMAKE_INSTALL_PREFIX="$dest" \
                && cmake --build "build_preset_{{mode}}" -j {{jobs}} --target install )
    just install-locale "$dest"
    ln -sfn "$dest" "$HOME/CUBRID"
    echo "installed {{mode}} ($ws) -> $dest"
    echo "~/CUBRID -> $(readlink "$HOME/CUBRID")"

# Convenience aliases (default version).
debug: (build "debug")
release: (build "release")

# Only repoint ~/CUBRID to an already-installed versioned dir (set_cubrid_ver.sh equivalent).
# Operates purely on the install tree under $HOME — no CUBRID source needed.
use mode="debug" version=ver:
    #!/usr/bin/env bash
    set -eu
    dest="$HOME/{{mode}}/CUBRID-{{version}}"
    [ -d "$dest" ] || { echo "ERROR: not installed: $dest (build it first)" >&2; exit 1; }
    ln -sfn "$dest" "$HOME/CUBRID"
    echo "~/CUBRID -> $(readlink "$HOME/CUBRID")"

# Force a fresh configure + build + install (+ locale) + repoint.
rebuild mode="debug" version=ver: _submodules
    #!/usr/bin/env bash
    set -eu
    ws="{{workspace}}"
    [ -n "$ws" ] || { echo "ERROR: WORKSPACE not set — pass the CUBRID source dir." >&2; exit 1; }
    [ -f "$ws/CMakePresets.json" ] || { echo "ERROR: '$ws' is not a CUBRID source checkout (no CMakePresets.json)." >&2; exit 1; }
    dest="$HOME/{{mode}}/CUBRID-{{version}}"
    ( cd "$ws" && rm -rf "build_preset_{{mode}}" )
    mkdir -p "$dest"
    ( cd "$ws" && cmake --preset {{mode}} -DCMAKE_INSTALL_PREFIX="$dest" \
                && cmake --build "build_preset_{{mode}}" -j {{jobs}} --target install )
    just install-locale "$dest"
    ln -sfn "$dest" "$HOME/CUBRID"
    echo "~/CUBRID -> $(readlink "$HOME/CUBRID")"

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
    ws="{{workspace}}"
    [ -n "$ws" ] || { echo "ERROR: WORKSPACE not set — pass the CUBRID source dir." >&2; exit 1; }
    cd "$ws"
    ctest --test-dir "build_preset_{{mode}}" --output-on-failure

# Run one or a limited range of CTP shell tests against the local build.
# Powers the `cubrid-shell-run` skill. CTP's stock shell_ci.conf runs *everything*
# under scenario=; this copies it, repoints scenario= at one directory, and disables
# the testcase git auto-update so a debug run never mutates ~/cubrid-testcases-private-ex.
# CTP runs against the install on PATH (not the build tree) — rebuild/reinstall first
# if you changed src/.
#
# The rewritten conf goes under $WORKSPACE/.git_ignored_dir/scratch (NOT /tmp — host /tmp is tmpfs);
# shell-debug therefore also requires WORKSPACE (the CUBRID checkout).
#
# ARG SHAPE
#   TEST_DIR must be the directory that *contains* `cases/<name>.sh`, NOT the .sh itself.
#   Pass any ancestor directory to run a wider subtree (CTP recurses).
#
# Usage:
#   just shell-debug ~/cubrid-testcases-private-ex/shell/_06_issues/_10_1h/bug_1638
shell-debug TEST_DIR:
    #!/usr/bin/env bash
    set -euo pipefail
    ws="{{workspace}}"
    [ -n "$ws" ] || { echo "ERROR: WORKSPACE not set — pass the CUBRID checkout whose .git_ignored_dir/scratch/ holds the temp conf (e.g. 'WORKSPACE=/path/to/cubrid just shell-debug <TEST_DIR>')." >&2; exit 1; }
    # CTP requires these in the environment (vimkim's .envrc exports the same two).
    # `just` recipes run in a non-login shell that does not source the profile, so
    # set them here to keep the recipe self-contained.
    export CTP_HOME=~/cubrid-testtools/CTP
    export init_path="$CTP_HOME/shell/init_path"
    SRC="$CTP_HOME/conf/shell_ci.conf"
    [ -f "$SRC" ] || { echo "ERROR: CTP conf not found: $SRC (is CTP installed?)" >&2; exit 1; }
    SCRATCH="$ws/.git_ignored_dir/scratch"
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

# Interactive picker against the UNMODIFIED conf (testcase_update_yn=true still git-pulls).
shell-debug-interactive:
    #!/usr/bin/env bash
    set -euo pipefail
    export CTP_HOME=~/cubrid-testtools/CTP
    export init_path="$CTP_HOME/shell/init_path"
    "$CTP_HOME/bin/ctp.sh" shell --interactive -c "$CTP_HOME/conf/shell_ci.conf"
