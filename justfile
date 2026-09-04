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
# CTP run artifacts stay in this tooling repo's .git_ignored_dir/scratch/ctp-run-out/.
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
#   just ctp <suite> [DIRS...]                             run a CTP suite (sql|medium|shell|ha_shell) in podman
#   just ctp-rerun <CI URL>                                re-run locally exactly what failed in CI
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
    # workspace#157: CMake's install step reinstalls conf/cubrid.conf from the
    # source template on EVERY build, silently reverting whatever was there. The
    # installed conf is a derived file (see `just conf`), so re-derive it here
    # instead of leaving the factory template in place.
    CUBRID="$dest" just conf || echo "WARNING: could not re-apply conf to $dest"
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

# Install a cubrid.conf into $CUBRID/conf/cubrid.conf.
#
# THE CONTRACT (workspace#157): the installed conf is a DERIVED file, never a
# place to hand-edit. Its source is either
#   - the campaign conf at this repo's root (the default), or
#   - a session conf, `CONF=<file>` — which `just port-claim` generates for you
#     with your claimed cubrid_port_id already substituted.
# Hand edits to $CUBRID/conf/cubrid.conf are wiped by the next install (CMake
# reinstalls the source template every build; `just build` re-applies this
# afterwards) — which once silently reverted a worker's port + stored_procedure
# edits and ran the gate on the factory port.
#
# So this warns, loudly but WITHOUT blocking (an unattended worker must not
# stall), whenever it is about to overwrite an installed conf whose contents
# differ from the source — and shows exactly which keys change.
[doc("Install the campaign (or CONF=<file>) cubrid.conf into $CUBRID/conf/")]
conf:
    #!/usr/bin/env bash
    set -eu
    [ -n "${CUBRID:-}" ] || { echo "ERROR: \$CUBRID not set." >&2; exit 1; }
    dest="$CUBRID/conf/cubrid.conf"
    src="${CONF:-{{justfile_directory()}}/cubrid.conf}"
    [ -f "$src" ] || { echo "ERROR: conf source not found: $src" >&2; exit 1; }
    [ -d "$CUBRID/conf" ] || { echo "ERROR: $CUBRID/conf/ not found (build/install first)." >&2; exit 1; }
    if [ -f "$dest" ] && ! cmp -s "$src" "$dest"; then
        echo "WARNING: about to overwrite $dest, whose contents differ from"
        echo "         $src"
        if [ -z "${CONF:-}" ]; then
            echo "         You are getting the CAMPAIGN conf. Is that what you intended?"
            echo "         If this session needs its own parameters, do NOT edit the installed"
            echo "         file: put them in a session conf and pass it, e.g."
            echo "           just port-claim <db> '<effort>'      # generates one with your port"
            echo "           CONF=.git_ignored_dir/conf/<db>.conf just conf"
        fi
        echo "         keys that change:"
        diff <(grep -E '^[[:space:]]*[a-z_]+[[:space:]]*=' "$dest" | tr -d ' ' | sort) \
             <(grep -E '^[[:space:]]*[a-z_]+[[:space:]]*=' "$src"  | tr -d ' ' | sort) \
          | grep -E '^[<>]' | sed 's/^/           /' || true
    fi
    cp -f "$src" "$dest"
    echo "conf: $src -> $dest"

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

# ---------------------------------------------------------------------------
# CTP — one entry point, every suite, always inside podman.
#
# WHY CONTAINERS, ALWAYS: CTP's own teardown runs `pkill cub` and kills every
# process of the running user (sql/bin/run.sh, util_common.sh cleanCUBRID,
# shell/init_path/init.sh). On the host that stops OTHER sessions' servers no
# matter which ports they claimed — the 2026-08-28 incident. Inside a container
# the same kill reaches only that container. There is therefore no host-side CTP
# recipe here, and none may be added.
#
# The runner is the ctp-run skill: the CI image (cubridci/cubridci:test_rl8.10,
# digest-pinned) with the skill's entrypoint fork bind-mounted in, the local
# install mounted in, and the testcases materialized from the ref this run is
# supposed to verify.
#
#   just ctp <suite>                     whole suite (sql/shell parallel, medium/ha_shell single)
#   just ctp <suite> <DIRS...>           subset: those scenario-relative dirs
#   just ctp-rerun <CI URL>              re-run exactly what failed in CI
#
# Suites: sql | medium | shell | ha_shell.
# Env knobs (all optional):
#   PR=<n>        testcases ref tc/pr-<n>            (else inferred from WORKSPACE)
#   TC_REF=<ref>  explicit testcases branch/tag/sha  (wins over PR)
#   SHARDS=<n>    override the shard count           (refused for medium/ha_shell)
#   BUILD=<dir>   install to test                    (else $CUBRID, else ~/CUBRID)
#   CONF=<file>   cubrid.conf whose [<suite>/cubrid.conf] section CTP applies
#   NO_ABORT_ON_CORE=1   keep running after a core dump (default: stop everything)
#   CTP_ARGS="…"  extra ctp_run.sh flags, verbatim
# ---------------------------------------------------------------------------

# Run a CTP suite (whole, or just the given scenario-relative dirs) in podman.
[doc("Run a CTP suite in isolated podman: just ctp <sql|medium|shell|ha_shell> [DIRS...]")]
ctp SUITE *DIRS:
    #!/usr/bin/env bash
    set -euo pipefail
    runner="{{justfile_directory()}}/.agents/skills/ctp-run/scripts/ctp_run.sh"
    [ -x "$runner" ] || { echo "ERROR: ctp-run runner missing: $runner" >&2; exit 1; }
    case "{{SUITE}}" in
        sql)      repo=cubrid-testcases ;;
        medium)   repo=cubrid-testcases ;;
        shell)    repo=cubrid-testcases-private-ex ;;
        ha_shell) repo=cubrid-testcases-private ;;
        *) echo "ERROR: suite must be sql | medium | shell | ha_shell (got '{{SUITE}}')" >&2; exit 1 ;;
    esac
    tc="${TESTCASES_ROOT:-$HOME}/$repo"
    [ -d "$tc" ] || { echo "ERROR: testcases checkout not found: $tc" >&2; exit 1; }
    args=( --suite "{{SUITE}}" --build "${BUILD:-${CUBRID:-$HOME/CUBRID}}" --testcases "$tc"
           --ctp "${CTP_HOME:-$HOME/cubrid-testtools/CTP}"
           --out "{{justfile_directory()}}/.git_ignored_dir/scratch/ctp-run-out/{{SUITE}}-$(date -u +%Y%m%dT%H%M%SZ)-$$" )
    # Which testcases ref: explicit wins, else the PR, else infer from the engine
    # checkout's branch. Never a silent develop — the runner refuses instead.
    if   [ -n "${TC_REF:-}" ]; then args+=( --tc-ref "$TC_REF" )
    elif [ -n "${PR:-}" ];     then args+=( --pr "$PR" )
    elif [ -n "{{workspace}}" ]; then args+=( --workspace "{{workspace}}" )
    fi
    [ -n "${SHARDS:-}" ] && args+=( --shards "$SHARDS" ) || :
    [ -n "${CONF:-}" ]   && args+=( --conf "$CONF" ) || :
    [ -n "${NO_ABORT_ON_CORE:-}" ] && args+=( --no-abort-on-core ) || :
    for d in {{DIRS}}; do args+=( --only "$d" ); done
    exec "$runner" "${args[@]}" ${CTP_ARGS:-}

# Re-run locally, in one shard, exactly the cases that failed in CI.
# Takes a CUBRID PR URL, a CircleCI job URL, or a gha-ci run URL.
[doc("Reproduce CI failures locally: just ctp-rerun <PR|CircleCI job|gha-ci run URL>")]
ctp-rerun URL *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    rerun="{{justfile_directory()}}/.agents/skills/ctp-run/scripts/ctp_rerun.sh"
    [ -x "$rerun" ] || { echo "ERROR: ctp-rerun script missing: $rerun" >&2; exit 1; }
    exec "$rerun" "{{URL}}" \
        --build "${BUILD:-${CUBRID:-$HOME/CUBRID}}" \
        --out "{{justfile_directory()}}/.git_ignored_dir/scratch/ctp-run-out" \
        --testcases-root "${TESTCASES_ROOT:-$HOME}" \
        {{ARGS}}


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
    # Generate this session's conf from the campaign conf with the claimed port
    # substituted, so nobody has to hand-edit an installed conf (workspace#157).
    confdir="{{justfile_directory()}}/.git_ignored_dir/conf"
    mkdir -p "$confdir"
    sconf="$confdir/{{db}}.conf"
    campaign="{{justfile_directory()}}/cubrid.conf"
    if [ -f "$campaign" ]; then
        if grep -qE '^[[:space:]]*cubrid_port_id[[:space:]]*=' "$campaign"; then
            sed -E "s#^[[:space:]]*cubrid_port_id[[:space:]]*=.*#cubrid_port_id=$port#" "$campaign" > "$sconf"
        else
            { cat "$campaign"; printf '\ncubrid_port_id=%s\n' "$port"; } > "$sconf"
        fi
        echo "session conf: $sconf  (cubrid_port_id=$port)"
        echo "apply it:     CONF=$sconf just conf"
        echo "              edit THAT file for session-specific parameters — never \$CUBRID/conf/cubrid.conf"
    else
        echo "WARNING: campaign conf $campaign missing; no session conf generated." >&2
    fi
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
