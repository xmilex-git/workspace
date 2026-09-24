---
name: ctp-run
description: >-
  Run any CUBRID CTP suite — sql, medium, shell, HA/shell — inside isolated
  rootless-podman containers: the whole suite in parallel shards, an arbitrary
  subset in one shard, or exactly the cases that failed in CI. Use when asked to
  run CTP / a regression suite / shell tests / medium / HA tests, to "run ctp in
  parallel", "shard the sql suite", "reproduce the CI failures locally",
  "ctp 병렬 실행", "shell TC 돌려", "CI 실패분 재현", or "딸깍 ctp". Host-side CTP is
  forbidden (its teardown pkills every cub_* of this user), so this is the only
  way CTP may run. Requires podman; without it use --dry-run to validate a split.
---

# ctp-run — the CTP runner

One entry point for every CTP suite. Two commands cover everything:

```bash
just ctp <sql|medium|shell|ha_shell>              # whole suite (whole sql also runs whole medium beside it)
just ctp sql+medium                               # the same sql + medium pair, explicitly
just ctp <suite> <DIR> [<DIR> ...]                # subset (scenario-relative dirs)
just ctp-rerun <PR | CircleCI job | gha-ci run URL>   # exactly what failed in CI
```

Env knobs: `PR=<n>` / `TC_REF=<ref>` (testcase ref), `SHARDS=<n>`, `BUILD=<install>`,
`CONF=<file>`, `EXCLUDE=<file>`, `NO_ABORT_ON_CORE=1` (+ `CTP_CRASH_LOOP_CORES`, `CTP_MAX_SHARD_CORES`),
`CTP_VOLATILE=0` (see "Volatile databases"), `CTP_PIN_PARAMS=0` (see below),
`CTP_HANG_SECS=<s>` (see "Diagnosing a bad run"), `CTP_ARGS="…"`, `TESTCASES_ROOT=<dir>`.

**Every CTP server runs the engine's own defaults for `data_buffer_size=512M`, `parallelism=4`
and `max_parallel_workers=100`** (ADR 0017 D8). `data_buffer_size=512M` is 32768 pages of 16K.
Without the pin, the campaign cubrid.conf that `just conf` puts into installs would apply,
with `parallelism=24`. sql/medium servers also get `max_clients=20`:
- CQT holds one connection, and no sql/medium case mentions `max_clients`.
- 16+ shards share this host's pids cgroup, whose `pids.max` is 8192.
- shell/HA keep the install's `max_clients`: their cases open connections themselves, and
  124 of them set it.

Where the values go:
- sql/medium: `[sql/cubrid.conf]` of the shard's CTP conf. CTP reads that section for
  medium too.
- shell/HA: `[common]` of the shard install's `conf/cubrid.conf`.

The pin is applied before `CONF=`, so an explicit `CONF=` value wins, e.g. `parallelism=24`
for a PX stress run. `CTP_PIN_PARAMS=0` keeps the install's values. Provenance records
`pinned=`.
`CONF=` for medium now reaches the server too: it used to merge into a
`[medium/cubrid.conf]` section that CTP never reads.

## Non-negotiables

**CTP only ever runs in a container.** CTP's teardown runs `pkill cub` and
`kill -9` over `ps -u $USER`, so a host-side run kills every `cub_master` /
`cub_server` / `cub_broker` of this user regardless of ports — the port registry
cannot protect against it (2026-08-28 incident). Never invoke `ctp.sh` on the
host, and never add a host-side recipe back.

**The testcase ref is never implicit.** Pass `PR=`, `TC_REF=`, or let the runner
infer the PR from `WORKSPACE`'s branch. With none of the three it refuses rather
than run develop testcases against a PR build. Refs are materialized as git
worktrees, so host checkouts (and their uncommitted edits) are never touched.

**medium and ha_shell are never sharded.** medium loads one mdb from a single
`data_file` tarball and its cases mutate it in place; an ha_shell shard is a
master+slave container pair. `SHARDS>1` is refused with the reason.

## Layout

| path | what |
|---|---|
| `scripts/ctp_run.sh` | the runner: split, mount, launch, aggregate, merge |
| `scripts/ctp_rerun.sh` | CI failure extraction → subset run |
| `scripts/entrypoint.sh` | current upstream entrypoint plus two local HA hooks, bind-mounted into the container |
| `scripts/volatile_entry.sh` | sql/medium container entrypoint: mounts the volatile database overlay, then runs `/entrypoint.sh` |
| `scripts/harvest_weights.sh` | turn a finished run into a timing table |
| `baseline_weights.tsv` | measured per-case seconds (sql), for time-balanced splits |
| `colocate.tsv` | order-sensitive dirs that must stay on one shard |
| `split.tsv` | sql cases dirs too slow for one shard, cut into contiguous weight chunks |
| `dirsplit_exclusions.txt` | sql cases left out of dir-split runs only (answers need CI's whole order) |
| `test/run_tests.sh` | split, image-contract and HA regression checks; no CTP execution |
| `test/image_contract_test.sh` | runtime conf isolation, scope migration and exclusion planning fixtures |
| `test/locale_staging_test.sh` | real shard staging followed by CTP-style locale deletion |
| `test/crash_loop_watchdog_test.sh` | core watchdog over stubbed podman: abort-on-core, crash-loop shard stop, core cap, disk floor |

The image is `cubridci/cubridci:test_rl8.10`, digest-pinned in `ctp_run.sh`. It is
never built locally; the CUBRID install is mounted in from the host (`just build`
output). The image includes gcc for locale and testcase helper compilation. Our entrypoint fork is bind-mounted over
`/entrypoint.sh`, so changing the runner never means rebuilding an image.
The default pull/run reference includes the full digest; `--image` explicitly
overrides it. Since the 2026-09-11 update, scope, testcase source pinning, DB
permissions and start/end provenance come from upstream (PRs #120, #121, #123).
Only the HA thin-csql port and slave broker startup remain local. See
`docs/adr/0017-ctp-runner-on-cubridci-image.md` for the migration decision.

## Suites

| suite | testcases repo | scenario | whole-suite shards | result style |
|---|---|---|---|---|
| `sql` | cubrid-testcases | `sql/` | 16 (cases dir + measured time + `split.tsv`) | schedule `summary.xml` |
| `medium` | cubrid-testcases | `medium/` | always 1 | schedule `summary.xml` |
| `shell` | cubrid-testcases-private-ex | `shell/` | 7 (per test dir) | `test_status.data` + JUnit |
| `ha_shell` | cubrid-testcases-private | `HA/shell/` | always 1 (2 containers) | `test_status.data` + JUnit |

A **subset defaults to 1 shard** whatever the suite: each shard costs a full copy
of the install and a container, which pays for itself over 17k cases and not over
a handful of dirs. `SHARDS=N` splits a big subset anyway.

**sql splits by cases dir** (ADR 0017 D9). The user confirmed that no case fails from
order effects at dir granularity. `CTP_ARGS='--by-category'` restores the old bulk split.
- The 16-shard default comes from the measured weights: 2,668s of cases / 16 ≈ 167s per
  shard.
- `split.tsv` cuts a dir longer than that into contiguous chunks of equal weight. Today
  that is only `_005_reorganization` (203s). `--no-split` keeps it whole.
- A dir enters `split.tsv` only after its chunks passed on their own.
- Some cases depend on what the cases before them in the shard left behind. Two kinds
  have turned up:
  - **Session state.** `last_insert_id()` reads the last AUTO_INCREMENT insert on CQT's
    one connection. `colocate.tsv` pins the dir together with its CI predecessor, so the
    predecessor runs just before it.
  - **Catalog order without ORDER BY.** For example `_001_db_class/1003.sql` needs 481s
    of CI's `_01_object` order to pass, which no colocation can buy.
  - **An engine hang the placement triggers.** `_06_merge_statement/_20_adhoc_merge_1.sql`
    deadlocks (xmilex-git/workspace#350) whenever it runs on a fresh server.
  - `dirsplit_exclusions.txt` leaves both kinds out of dir-split runs only; `--by-category`
    and CI keep them. It holds 8 cases today, each with its reason.
    `EXCLUDE=<file>` replaces that list with yours, and `EXCLUDE=''` drops it.
- **The plan ignores dir-split exclusions.** Units and weights are computed over the pool
  before `dirsplit_exclusions.txt` is applied, and those cases are dropped from the shards
  only afterwards.
  - So adding an entry never moves another dir to another shard.
  - Why this matters: LPT is sensitive, and a 4s weight change once reassigned almost every
    dir.
  - A verified plan keeps its order when an exclusion is added, and the fix converges in one
    more run.
- **Any change to the plan's inputs needs two verification runs.** The inputs are
  `baseline_weights.tsv`, `split.tsv`, colocate groups, the shard count and the set of
  cases.
  - Each plan puts different dirs in front of each dir, and has exposed order-dependent
    cases of its own.
  - Such a case fails the same way on every run of that plan, and then goes into
    `colocate.tsv` or `dirsplit_exclusions.txt`.
- **Expected balance.** Against another run's measured case times, the current plan puts
  every shard at 171–196s of cases (mean 181s). The last shard to finish ends ~10–25s
  after the first.
- **pids cgroup short of room.** The runner waits up to `CTP_PIDS_WAIT_SECS` (900) for
  other runs to finish instead of running fewer shards. Only after that does it cap the
  count.
- The default shard count is also capped by free RAM (~3GB a shard) and bounded by the
  pids cgroup (~400 processes+threads a shard).

**A whole `just ctp sql` also runs the whole medium suite** (its single shard) beside the
16 sql shards. `just ctp sql+medium` is the same thing, spelled out.
- Measured: medium takes 151–193s (38–39s setup, 102–143s of cases), sql ~5 min. So the
  pair costs the sql run's time.
- Both use the same testcase ref.
- `CTP_WITH_MEDIUM=0` runs sql alone.
- Medium is not attached to a subset (DIRS), to `ctp-rerun`, or when `EXCLUDE` is set,
  because an exclusion list is per suite.
Worktree creation takes a per-repo lock, because two runs creating worktrees at once died
on git's `index.lock`. medium's runner output goes to
`<artifact root>/medium-beside-sql-*.log`, and the recipe prints both results at the end.
`just ctp sql+medium` refuses DIRS and EXCLUDE, since they are per suite.

`sql`/`medium` split by case FILE (two-pass materialization); `shell`/`ha_shell`
split by test DIRECTORY, because a shell case's directory also carries the
`.answer` files and the `.c`/`.java`/helper `.sh` it compiles at run time.

An `ha_shell` shard is two containers: the master runs CTP, the slave runs the
image's `node` mode (sshd + a `qa` account CTP logs into). Each gets its OWN copy
of the install and of `CUBRID_DATABASES` — they run separate servers and rewrite
their own conf, so sharing those would make the pair clobber each other.
Inside each HA node, mount `CUBRID_DATABASES` at `$CUBRID/databases`: CTP cleans
that path between cases, including replication logs tied to the previous DB.

## Scope and exclusions

Use `just ctp <suite> <DIR>...` / `--only` to select scenario-relative directories.
The host partitions those cases before launch and sets upstream `TEST_SCENARIO`
to each shard's materialized scenario root. This keeps SQL exclusion paths relative
to the suite root even when only one directory is selected.

`EXCLUDE=<host-file> just ctp ...` (`--exclude <host-file>` in the runner) replaces
the default list **before planning** and stages the same list for upstream
`TEST_EXCLUDE`. Unset uses the suite default; `EXCLUDE=''` / `--exclude ''` disables
exclusions. Missing files fail before launch. SQL/medium entries are relative to
`sql/` or `medium/` without that prefix; shell entries include `shell/`, and HA
entries include `HA/shell/`. Entries use the target runner's substring semantics.

Use these host options instead of `--env TEST_SCENARIO=...` / `--env TEST_EXCLUDE=...`:
a container-only override would disagree with the host's planned case count.
Those `--env` names are rejected with guidance. The retired `CTP_SCENARIO`,
`CTP_EXCLUDE`, `SHELL_SCENARIO`, `HA_SCENARIO`, `MEMORY_SCENARIO` names also fail,
even when empty; do not use them in `CTP_ARGS`.

Upstream writes SQL, medium and shell overrides to `conf/<suite>_runtime.conf`.
HA derives `conf/ha_shell_ci.conf` from `shell_ci.conf`. Inspect these generated
files, not just the stock conf, when diagnosing scope. `CONF=` engine parameters
are still merged into the shard's stock conf before upstream copies it.

## Volatile databases (sql/medium, default on)

CTP creates sql's `basic` and medium's `mdb` under `$CUBRID/databases`. Every autocommit
statement then waits for the log fsync. By default that directory is an overlayfs mounted
with the kernel's `volatile` option inside the shard container, so every fsync there
returns at once. The database is thrown away with the shard, and a killed server loses
nothing because its writes are in the page cache. Only a host crash mid-run could matter.
This is the mechanism cubrid-testkit uses for `TESTKIT_SLOT_VOLATILE`
([ADR 0017](../../../docs/adr/0017-ctp-runner-on-cubridci-image.md) D7).

- The shard container gets `--cap-add SYS_ADMIN` for the mount only.
  `scripts/volatile_entry.sh` mounts the overlay, checks `/proc/self/mountinfo` for
  `volatile`, drops the capability with `setpriv`, then runs `/entrypoint.sh`. A failed
  mount stops the shard. It never falls back silently.
- Evidence: a `[volatile] /home/CUBRID/databases: overlayfs volatile` line at the top of
  `shard_N/console.log`, and `volatile=` in `provenance.txt`/`.tsv`.
- `CTP_VOLATILE=0` (or `--no-volatile` in `CTP_ARGS`) restores the plain bind. It is
  read by the runner, so it applies to `just ctp` and `just ctp-rerun` alike.
- Not applied to shell/ha_shell, whose cases create databases in their own case dirs,
  or with `--overlay`.
- Writes land in `shard_N/volatile/_home_CUBRID_databases/upper/`. That is where a
  `--keep-copies` run's database files are.
- A used volatile workdir keeps a mode-000 `work/` that plain `rm` cannot remove. The
  runner's prune and `just ctp-prune` fall back to `podman unshare rm -rf`. It also
  refuses a second mount, so every run makes fresh dirs.

## Shell/HA locale baseline

CTP deletes generated locale libraries before every shell/HA case. If the build's
`cubrid_locales.txt` exactly matches its full sample `cubrid_locales.all.txt`, the
runner clears the active entries **in the private install copy only**, before CTP
snapshots it. Built-in locales then work after the deletion; cases that need extra
locales still call `do_make_locale` themselves. SQL/medium and independently
customized locale configs are unchanged. With that inherited preset, omit
`--overlay`: normalization requires a writable install copy and refuses to edit
the shared lower directory.

## Output

### Storage: NVMe runs, pruned working copies, explicit cleanup

CTP runs live on the NVMe home disk: `/home/<user>/ctp-run-out/<tooling-repo>/`
(`scripts/artifact_root.sh`, shared by `just ctp`, `just ctp-rerun` and the
scripts' default output; `CTP_ARTIFACT_MOUNT` points it at another mounted disk).
Runs were moved to the mounted HDD for a while; a run there spent most of its
wall clock in I/O (install copies, DB volumes, cores), so they are back on NVMe
with two rules that keep the disk from filling:

1. **A run prunes its own working copies when it ends.** After the results are
   merged the runner deletes each `shard_N/{CUBRID,CTP,testcases,CUBRID_DB}` copy
   and keeps the evidence: `console.log`, `out/` (CTP result + log, the composed
   `ctp-conf/`, the install's `cubrid-log/`), `reports/`, `cores/` (a symlink to the HDD store). The copies are
   reproducible from `--build` / `--testcases`. `--keep-copies` (or
   `CTP_KEEP_COPIES=1`) keeps them for a run whose shard you need to debug in place.
2. **Analyze, then delete.** `just ctp-runs` lists runs with size; `just ctp-prune
   [KEEP]` deletes all but the newest KEEP (default 3), never a run whose container
   is still up. Read `console.log` / `cores/` first — a deleted run is gone. Remove
   generated `tc-worktrees` with `git worktree remove` before deleting their parent.

Merged SQL/medium reports stay in `<run>/webconsole/`; the runner does not copy
them into the source `CTP_HOME/sql/result`.

Cores stay on the HDD: each `shard_N/cores/` is a symlink into
`/bench/hdd/core/ctp/<run>/shard_N/` (`CTP_CORE_STORE` overrides the store), so
`just ctp-prune` removes a run's NVMe evidence but not its cores; delete those
in the store once analyzed. Keep the default stop-on-core behavior: a
crash-looping server once wrote 1.1T of cores.

Every run writes, under its `--out` dir:

- `provenance.txt` / `provenance.tsv` — install, image digest, CTP revision,
  testcases repo@ref(sha), how the ref was chosen. Read this first when a result
  surprises you.
- `plan.tsv`, `assignment.tsv`, `units.tsv` — the split.
- `shard_N/` — `console.log` (the container's own log; primary evidence),
  `assigned_cases.txt`, `exclusions.txt`, `reports/` (JUnit), `cores/`, and the
  per-shard `CUBRID` / `CTP` / `testcases` / `CUBRID_DB` copies.
- `failed.list` — failing cases in the exact shape `--only` accepts.
- `timing.txt` / `timing.tsv` — where the wall clock went.
  - Host marks, in seconds from start: `planned`, `workdirs_built`, `launched`,
    `shards_done`, `pruned`.
  - Per shard, from `shard_N/console.ts.log` (`podman logs --timestamps`): when each CTP
    stage started (CTP start, locale, createdb, SP load, server start), `setup` (container
    up → first case) and `tc` (first → last case).
  - The runner prints one `timing:` summary line.

## Reproducing CI failures

`ctp-rerun` takes a PR URL and finds the failed suites itself, or a single job URL.

- **CircleCI** (sql, medium): the public API needs no token; failing case paths
  come straight from `/api/v2/project/gh/CUBRID/cubrid/<job>/tests`.
- **GitHub Actions** (shell): the run uploads no artifacts — the complete
  `failed.list` exists only on the self-hosted runner's storage. What is readable
  is the `collect` job's log summary, which upstream caps at 50 rows. Past that
  cap only the first 50 are reproducible here; the rest need CI's `/run rerun <id>`.

It always uses 1 shard and re-runs whole test DIRECTORIES, not single cases: sql
cases in one directory share state, so a case run without its directory-mates
fails for reasons that have nothing to do with the change.

## Diagnosing a bad run

1. `provenance.txt` — right install? right testcase ref?
2. `shard_N/console.log` — the container's stdout, including the entrypoint's
   `[conf]`/`[scope]`/`[pin]`/`[provenance]` lines. Check the final `[scope]`
   line and runtime conf. Upstream may report `unknown` git metadata because
   shard copies omit `.git`; the host `provenance.tsv` records the source refs.
3. `shard_N/CTP/conf/<suite>*.conf` — the conf the entrypoint actually composed,
   preserved on the host.
4. `shard_N/hang/` — present when the **hang watchdog** fired.
   - The watchdog treats a sql/medium shard that printed nothing for `CTP_HANG_SECS`
     (default 300; the longest sql case is 69s) as hung.
   - Before stopping only that shard, it saves the full `cub_server` stacks
     (`gdb thread apply all bt`), the CQT JVM's jstack, `tranlist` and `lockdb`.
   - CTP's sql/medium have no per-case timeout: without the watchdog, one engine hang held a
     whole run for 35 minutes (2026-09-24, a PX sort worker ↔ leader mutex deadlock).
   - shell/HA cases may legitimately run silent for long, so the watchdog is off there
     unless `CTP_HANG_SECS` is set.
   - The stopped shard is named in the aggregate (`STOPPED by a watchdog`).
5. `timing.txt` — whether the wall clock went to setup or to cases, shard by shard.
6. `shard_N/cores/` — real core dumps. By default the first one stops every
   shard; a crash-looping server once wrote 1.1T of cores. `NO_ABORT_ON_CORE=1`
   (`--no-abort-on-core`) keeps collecting cores but still stops a shard after
   `CTP_CRASH_LOOP_CORES` (5) cores with no passing case in between or
   `CTP_MAX_SHARD_CORES` (20) cores in total, and the disk floor still stops
   every shard. A stopped shard is named in the aggregate
   (`STOPPED by the crash-loop watchdog`) and in `<out>/.dead_shards`. Without
   this, a database that crashed again in recovery on every restart kept its
   shard running for hours: each remaining case waited out a 3-minute connect
   timeout (2026-09-23).

Run `bash .agents/skills/ctp-run/test/run_tests.sh` from the tooling repo after
touching the runner. The fixtures cover split invariants, runtime conf isolation,
unset/empty/custom exclusions and retained HA hooks. For an image update, also
run small real SQL/shell/HA subsets through `just ctp` and compare executed
counts with the plan; fixtures alone do not validate the image.
