---
name: cubrid-build
description: CUBRID build and install workflow using the portable justfile (optdebug and release presets, incremental builds, dedicated install prefixes, build fingerprints, gate checklist). The CUBRID source directory is passed explicitly via WORKSPACE (the justfile lives in this standalone tooling repo, not inside the checkout). Use when building, compiling, installing, or syntax-checking CUBRID source code in any CUBRID worktree or source directory, or when a build must be delegated to a worker.
---

# CUBRID Build & Install

Build and install CUBRID via this repo's portable `justfile`, which drives the target checkout's
tracked `CMakePresets.json` and installs to a versioned, per-mode directory.

## Terms

- **optdebug**: the `optdebug` preset — optimized with asserts on. `just build debug` is remapped to it; plain debug builds are retired. CI's "debug" slot is this build.
- **release**: `RelWithDebInfo`, asserts compiled out; `er_log_debug` is a no-op.
- **install**: the directory a build lands in (`bin/`, `lib/`, `conf/`, `jdbc/`); every CTP run and server runs on one.
- **incremental build** (`just incr`): ninja over an already-configured tree, installing to the prefix the tree was configured with; no locale copy, no conf re-apply, no `~/CUBRID` change.
- **fingerprint**: `sha256sum <install>/lib/libcubrid.so.11.5` (and `libcubridsa.so` for SA work) — the only thing that tells two builds apart.
- **gate**: the verification a change must pass before push or merge; its builds are optdebug and release, both green.
- **delegated build**: a build run by a worker (Sonnet Workflow or Luna) under the execution contract below; the lead does not run builds that produce an install.

The lessons behind every `(P<n>)` are in `PITFALLS.md`; a new lesson goes there as a case under its rule, or as a new rule added to both files in one commit.

## Workspace (required)

This tooling repo is **not** a CUBRID checkout, so the build recipes cannot use the current
directory. Pass the CUBRID source directory explicitly via `WORKSPACE` (no cwd default):

```bash
WORKSPACE=/path/to/cubrid just build          # env var
just workspace=/path/to/cubrid build          # just variable
```

Run `just` from **this tooling repo's root** (where the `justfile` and `.claude/locale/` live).
Source-touching recipes — `build`, `configure`, `rebuild`, `incr`, `deploy` — operate on
`$WORKSPACE` and fail fast if it is unset or is not a CUBRID checkout (no `CMakePresets.json`).
`use`, `conf`, and `install-locale` act on an install tree and need no `WORKSPACE`.

## Preconditions (checkable)

- `[ -L ~/CUBRID ] && echo symlink || echo directory` — on this host it prints `directory`: `~/CUBRID` is a real directory holding live `databases/`, `tmp/`, `var/` that other sessions' servers use, so a repoint is impossible and the recipes refuse it (P2).
- `cmake --version` ≥ 3.21, `ninja`, `gcc` 8+ (the host's `gcc (GCC) 8.5.0` is the CI release compiler, so local single-TU compiles reproduce CI code generation).
- `ls <WORKSPACE>/cubrid-jdbc/src` exists, or the first build initializes the submodule (needs network once); an install without `jdbc/cubrid_jdbc.jar` is refused by the build and by CTP.
- `nm -D <install>/lib/libcascci.so | grep -c cci_xa_prepare` prints 0 for a plain `just build` — it has no `SUPPORT_XA` (P5).

## Build modes and where they install

- A gate needs both: optdebug (assert and fault-injection detection, small smoke) and release (large data and performance measurement — a large database never goes on optdebug). (P1)
- Each mode installs to its own dir, `~/<mode>/CUBRID-<version>` by default (`CUBRID_VERSION`, default `11.5.develop`), so optdebug and release never clobber each other.
- Every `just build|rebuild` passes `INSTALL_PREFIX=<dedicated dir>` (a per-ticket or per-candidate path, never the shared default install), and `just incr` is the only recipe that may run without it. (P2)
- Two builds are told apart by `sha256sum lib/libcubrid.so.11.5` (and `libcubridsa.so` for SA runs), never by `bin/cub_server` (a launcher) or by the version string (`just incr` never regenerates `version.h`, so `cubrid_rel` keeps the last configure's hash); a build report carries the fingerprint and the build log's `installed … -> <prefix>` line. (P3)

## Commands

```bash
INSTALL_PREFIX=~/optdebug/CUBRID-<ticket> WORKSPACE=~/dev/cubrid just build optdebug   # configure + build + install + locale + conf
INSTALL_PREFIX=~/release/CUBRID-<ticket>  WORKSPACE=~/dev/cubrid just build release
INSTALL_PREFIX=<dir> WORKSPACE=<src> just build <mode> <version-label>                  # explicit version label
WORKSPACE=~/dev/cubrid just incr optdebug      # incremental: ninja + install into the tree's configured prefix
WORKSPACE=~/dev/cubrid just incr release
INSTALL_PREFIX=<dir> WORKSPACE=<src> just rebuild <mode>   # wipe build_preset_<mode> first
WORKSPACE=<src> just configure <mode>          # configure only (sets the tree's prefix)
CUBRID=<install> just conf                     # copy the repo-root campaign cubrid.conf into the install
just install-locale <install>                  # copy the prebuilt locale files (build/rebuild do it)
```

- `build` and `rebuild` reinstall `conf/cubrid.conf` from the source template and then re-apply `just conf` (the campaign conf: `double_write_buffer_size=0`, `parallelism=24`, `log_buffer_size=256M`); `incr` reinstalls the factory template and does **not** re-apply it — after any build, read `parallelism`, `data_buffer_size`, `stored_procedure` and `max_plan_cache_entries` in the install's conf before using it, and restore a gate install's conf to the reference state. (P6)
- `just incr` reconfigures once when the tree lacks JDBC targets (a tree configured while `cubrid-jdbc/src` was missing).
- A DBLink DML check needs `cmake --preset optdebug -DCMAKE_INSTALL_PREFIX=<prefix> -DSUPPORT_XA=true` before `just build optdebug` (or a gha-ci archive build, which has XA), verified with `nm -D lib/libcascci.so | grep cci_xa_prepare`; a plain `just build` fails every remote-DML case with "N rows affected" and an unchanged remote. (P5)
- Never `cmake --build` or `ctest` by hand; unit tests are not run or enabled in this repo (policy, 2026-09-22).

## Copies of an install

A `cp -a` copy of an install runs the original prefix's libraries on the host, because CUBRID binaries carry `DT_RPATH=<original>/lib`, which wins over `LD_LIBRARY_PATH`; so a host-side baseline copy is probed before the original is rebuilt, or its `lib` is bind-mounted over the RPATH dir inside the job namespace, or it is made a real install with `patchelf --remove-rpath && patchelf --force-rpath --set-rpath <copy>/lib` on every ELF under `bin/` and `lib/` — and `readelf -d <copy>/bin/csql | grep RPATH` is read before any "base = …" comparison. (P4) Inside CTP containers a copy is fine (the original path does not exist there). CI tarballs carry `RPATH=/home/CUBRID/lib`: run them with `LD_LIBRARY_PATH=<inst>/lib` and confirm with `ldd`. With several sessions sharing one install, each new candidate is built into its own directory and the old one is left until their runs end.

## Smoke before a delegated build (lead)

- A comment-only change gets no build: verify that only PR-added lines changed, that the code is identical with comments stripped, and that the CI formatters (`indent -l120 -lc120 -st`, astyle with the codestyle.sh options) leave it unchanged. (P7)
- For every changed TU, run `-fsyntax-only` with the compile command from **both** `build_preset_optdebug/compile_commands.json` and `build_preset_release/compile_commands.json` (`-o` removed, ` -fsyntax-only -fmax-errors=0` appended), because `-Werror=maybe-uninitialized` needs optimization and only the release command carries it; and when inserting a check into a long function, read the lines above it to confirm every variable it reads is assigned there. (P8)
- To find every reader of a field, rename it in the header (`<field>_CENSUS_<tag>`), syntax-compile every TU of the tree (`xargs -P`, ~1200 TUs in about a minute, delegated), parse the `has no member named` errors with their struct name and `in expansion of macro` notes into a sites table, then undo the rename and check the tree hash — a grep census misses sites. (P9) For an unused-member census wrap declarations as `private: … public:` instead (the access error keeps the expression's type, so nested accesses still report); `-fsyntax-only` reports no unused static functions in C++ — compile with `-O0 -c -o /dev/null` and diff the `-Wunused` warnings against develop's same TUs.

## Delegated builds

Every build that produces an install (`just build|rebuild|incr`, optdebug and release) goes to the designated worker (Claude Code: Sonnet at effort `xhigh` through the `Workflow` tool, `agent(prompt, { model: 'sonnet', effort: 'xhigh' })`; Codex: Luna). The prompt carries these lines verbatim (source: .agents/AGENTS.md):

- Finite gate work (incremental build, smoke rerun, targeted CTP — steps that each finish within ~10 min) runs as FOREGROUND blocking commands, chained in one continuous turn. run_in_background/nohup/monitors are FORBIDDEN for such steps. Only a full fresh build may go background, and then the SAME turn must bounded-poll its completion marker (`timeout ... until grep ...`) — never end a turn "waiting for a notification".
- The worker must deliver its final report in the same turn the work finishes, BEFORE going idle.

The completion marker of a build is the log's last line `installed <mode> (<ws>) -> <prefix>` (incremental: `installed (incremental) …`); a bounded poll is `timeout 540 bash -c 'until grep -q "^installed " <build.log>; do sleep 15; done'`. The worker reports the prefix, the marker line, the rebuilt targets and the fingerprint (P3); the lead checks the install's `lib/libcubrid.so.11.5` mtime against the commit time instead of trusting an idle worker.

- While a worker's build runs on a worktree, nobody edits, checks out or patches its sources: check `ps` or the workflow for a running build on that worktree first, and stage a mid-build decision as a patch file to apply after the `installed` line. (P10)

## Gate checklist (what a change must pass)

- [ ] optdebug and release builds green, each in its own `INSTALL_PREFIX` (P1, P2)
- [ ] fail-before-fix captured on the pre-fix build, then PASS by the same method on the fix build
- [ ] live run on a CS-mode optdebug server: no assert, no crash, no resource-tracker leak (SA `csql -S` cannot see leaks)
- [ ] orphan-zero: no temp files left after normal exit, abnormal exit and `kill -9`
- [ ] containerized CTP per the `ctp-run` skill (sql + medium locally on optdebug; shell on upstream CI)
- [ ] tree restored (submodules and untracked result dirs untouched), daemons stopped, fingerprint recorded in the proof (P3)

## Important

- `just --list` shows all recipes; read a failed build's error output before changing anything.
- Builds never run while a measurement or parity run uses the same install — a rebuild in place swaps the libraries under a running comparison (P4) and resets its conf (P6).
