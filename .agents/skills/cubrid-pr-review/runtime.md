# Runtime verification for a PR review

Reached from Step 3c of `SKILL.md`. Building CUBRID and running TCs for a review are permitted; this file is how. Use `curl --noproxy '*'` for the LAN hosts below.

## 1. Reuse CI evidence first

- `gh pr checks <N> -R CUBRID/cubrid` lists the gha-ci statuses (`build (debug|release)`, `test_sql`, `test_medium`, `test_shell`) and their run URLs. A `/run rerun <run id>` comment re-runs only the cases that failed in that run (its `plan/split.meta` shows `total=` the rerun count), so read the two runs together.
- The gha-ci artifact server keeps every run at `http://192.168.1.48:30080/runs/<run id>/`:
  - `<suite>/collect/verdict` and `<suite>/collect/failed.list` (one `shard<TAB>case` per line)
  - `<suite>/plan/split.meta`: `tc_branch` and `tc_sha` show whether the run used `tc/pr-<N>`
  - `<suite>/plan/shards/<NN>.list`: which shard ran a dir
  - `<suite>/shard/<NN>/build.read`: the engine `sha` and `mode` that shard tested
  - `<suite>/shard/<NN>/summary_info`: per-case `ok` / `nok` with ms
- A case that passed in a run with the PR head sha and `tc/pr-<N>` needs no local re-run. Before calling a shell NOK the PR's, check the same case in other PRs' `failed.list`; several shell cases fail on unrelated PRs.

## 2. Builds

- CI tarballs (with `build.meta`):
  - `http://192.168.1.48:30080/builds/pr/<head sha>/debug/CUBRID.tar.gz`
  - `http://192.168.1.48:30080/builds/develop/<merge-base sha>/debug/CUBRID.tar.gz`
- The "debug" slot is an optdebug build. The head and merge-base tarballs of one slot are the same build type, which an A/B needs; never compare across build types.
- Extract under `.git_ignored_dir/scratch/pr<N>/runtime/<label>/`. The install root holds `bin/cub_server`, `lib/libcubrid.so` and `jdbc/cubrid_jdbc.jar` (ctp-run refuses an install without the jar). Record `build.meta` and `sha256sum lib/libcubrid.so`; `cub_server` is a launcher and is no build fingerprint.
- No tarball for the sha, or another build type needed: build with `just` per the `cubrid-build` skill.

## 3. Runs

The lead runs these itself (source: .agents/AGENTS.md): a targeted subset in the foreground, a whole suite with `run_in_background`.

- Every CTP run, whole or subset, goes through `just ctp <sql|medium|shell|ha_shell> [DIRS...]` (containers) or `just ctp-rerun <CI URL>`. Never `ctp.sh` on the host, never resurrect a host-side recipe.
- The testcase ref is never implicit: pass `PR=<n>` or `TC_REF=<ref>`, or let it infer the PR from `WORKSPACE`. A run with none of the three refuses rather than validate a PR against develop testcases.

Keep the prompt to the commands and the facts to report. Add the host gotchas: `/usr/bin/grep` for `-E`, inline `VAR=x cmd` rather than bare `env`, and multi-command logic in a script run as `bash <script>`. Every CTP run is `just ctp` from the tooling repo root. Runs isolate containers and serialize testcase checkout with a lock, so an A/B pair runs at once.

- **TC fail-before / pass-after**: `BUILD=<install> PR=<N> CTP_HANG_SECS=<s> CTP_KEEP_COPIES=1 just ctp sql <dir>` for the merge-base and for the head.
  - Each run starts a fresh server, the condition that exposes temp-file and cache-dependent defects.
  - CTP has no per-case timeout. The hang watchdog stops a shard that printed nothing for `CTP_HANG_SECS`, so set it above the case's normal time. It saves the `cub_server` stacks and `tranlist`/`lockdb` in `shard_0/hang/` first.
- **Review-only SQL** (for example a linked ticket's repro):
  1. Export a testcases tree: `git -C <tc checkout> archive origin/develop sql | tar -x -C <scratch>/tc-adhoc`.
  2. Add `sql/_99_review_adhoc/<id>/cases/<id>.sql`, with an answer that contains `PLACEHOLDER`. A missing answer makes CTP skip the case and still report PASSED.
  3. Run `TC_REF=develop CTP_ARGS="--testcases-as-is --testcases <scratch>/tc-adhoc" CTP_KEEP_COPIES=1 just ctp sql _99_review_adhoc/<id>`. Its NOK is the placeholder; the `.result` is the evidence.
- **A case the dir-split runs exclude** (`.agents/skills/ctp-run/dirsplit_exclusions.txt`): add `EXCLUDE=''`.

## 3a. Differential probing & path-activation coverage

When verifying an engine PR with BASE-vs-HEAD differential queries (representative plus randomized shapes against two CS optdebug servers on separate claimed ports and install copies):

- **Prove target path activation first.** A 0-diff run proves nothing unless `SHOW TRACE` (or counters / `perf record -p <pid>` symbol bands per P16) confirms the PR's target execution path actually fired (for example `SCAN (bitmap heap lookup)`, `parallel workers: N>1`, or the target spill path) rather than silently falling back to `TABLE SCAN`, tiny compressed pages, or serial scan.
- **Cross-check `EXPLAIN` against `SHOW TRACE`.** Equal result rows do not rule out an execution regression where `EXPLAIN` shows one scan plan (for example key-order `iscan`) while `SHOW TRACE` executes another (for example iterative `SCAN (bitmap heap lookup)`). Compare both plan and trace scan lines whenever a PR touches scan flags or plan selection.
- **Compare full results and memory safety.** Judge output by full client rows plus robust aggregates (P13) and count all differing lines (P10). For C/C++ heap/buffer changes, re-run the differential smoke once on an optdebug install copy with `use_system_malloc=yes` in `cubrid.conf` and `MALLOC_CHECK_=3 MALLOC_PERTURB_=165` in the server and `csql` environment.

## 3b. CUBRID test-data & CLI pitfalls

- **LZ4 & B-tree prefix compression**: `REPEAT('x', N)` and sequential/low-entropy strings compress into far fewer pages than expected, silently preventing multi-page scans or spills. Concatenate distinct `MD5(...)` values to produce incompressible pages and index keys.
- **`PARALLEL(N)` silent serial fallback**: parallel scan falls back to serial when B-tree user pages are below `parallel_scan_page_threshold` (default `100`, server-conf-only). Size incompressible index keys above the threshold and confirm `parallel workers: N>1` in `SHOW TRACE` (P14).
- **High slot IDs (`slotid >= 640`)**: normal MVCC record headers cap live slots per page below 640. Reaching `slotid >= 640` (such as overflow slot lists) requires `DONT_REUSE_OID` plus multiple insert/delete churn cycles on the table.
- **`SHOW TRACE` returning `NULL`**: `SHOW TRACE` returns `NULL` in multi-statement `csql -c "..."` and in SA mode (`csql -S`). Run `SET TRACE ON; <query>; SHOW TRACE;` via `csql -i <file>` against a CS server.
- **`USING INDEX` with `GROUP BY`**: CUBRID requires `WHERE ... GROUP BY ... USING INDEX idx(...) ORDER BY ...`; placing `USING INDEX` before `GROUP BY` is a syntax error.
- **Server-only / non-dynamic parameters**: parameters such as `index_scan_key_buffer_pages` and `parallel_scan_page_threshold` fail `SET SYSTEM PARAMETERS`. Set them in `cubrid.conf` of an install copy and restart via `cubrid-server-ctl.sh`.
- **MVCC `REPEATABLE READ` in `csql`**: `SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;` has no cross-statement effect under default auto-commit (each `SELECT` runs in a new transaction). Pass `--no-auto-commit` to `csql`.

## 4. Record and clean up

- The report's Runtime Verification names, for each run: the build (sha, build type), the testcase ref and sha, the verdict, and for a hang the stuck frames.
- After reading, copy the small evidence (stacks, provenance, `.result`) to `.git_ignored_dir/scratch/pr<N>/evidence/`. Then delete the run dirs and downloads by literal path (`rm -rf <dir> || podman unshare rm -rf <dir>` for kept copies).
