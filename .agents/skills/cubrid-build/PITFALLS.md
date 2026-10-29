# PITFALLS — the rules in SKILL.md and the builds that produced them

Each `P<n>` is one rule. The **Rule** line is the exact sentence SKILL.md carries at the step named in
**Applies at**; keep the two byte-identical (`rg -F "<rule>"` finds both). **Case** is the build or
gate that paid for the rule. **Source** is where the lesson lived before it was folded in here
(auto-memory slugs are deleted once absorbed; kept for traceability only).

Adding a case: one `Case (YYYY-MM-DD):` line under the rule it confirms, in the session that hit it.
A new rule only when no rule fits — then add the sentence to SKILL.md in the same commit.

### P1 — two build types, two jobs
- Rule: A gate needs both: optdebug (assert and fault-injection detection, small smoke) and release (large data and performance measurement — a large database never goes on optdebug).
- Applies at: Build modes
- Case (2026-07-22, SSOT): plain debug builds were retired and `debug` remapped to the optdebug preset; a gate run only on release reported `NEW:0 GONE:0` for a branch breaking invariants, because `assert()` compiles out of release (wf268 #286, 2026-09-19). Large verification and performance measurement on optdebug mis-measure; optdebug is for asserts, fault injection and small smoke.
- Source: CUBRID_SSOT.md §3.2, §3.8

### P2 — `~/CUBRID` is a directory here
- Rule: Every `just build|rebuild` passes `INSTALL_PREFIX=<dedicated dir>` (a per-ticket or per-candidate path, never the shared default install), and `just incr` is the only recipe that may run without it.
- Applies at: Build modes
- Case (2026-09-21): `~/CUBRID` on the Rocky 8 host is a real directory (`CUBRID-develop -> ~/optdebug/CUBRID-develop` plus live `databases/`, `tmp/`, `var/` used by other sessions' servers). `ln -sfn <dest> ~/CUBRID` then creates `~/CUBRID/<basename>` inside it: the repoint silently does nothing, `$CUBRID` keeps the old install, and stray symlinks accumulate in a live directory. Since 2026-10-28 the `build`, `rebuild` and `use` recipes refuse to repoint a directory and name `INSTALL_PREFIX` instead. Campaign and branch builds must never overwrite the shared default install (SSOT §3.2).
- Case (SSOT §2 실수 7): a `just build` during a measurement run repointed `~/CUBRID` and collided with the shared master's port.
- Source: memory:cubrid-home-symlink-is-a-directory, CUBRID_SSOT.md §3.2

### P3 — the fingerprint is libcubrid
- Rule: Two builds are told apart by `sha256sum lib/libcubrid.so.11.5` (and `libcubridsa.so` for SA runs), never by `bin/cub_server` (a launcher) or by the version string (`just incr` never regenerates `version.h`, so `cubrid_rel` keeps the last configure's hash); a build report carries the fingerprint and the build log's `installed … -> <prefix>` line.
- Applies at: Build modes
- Case (dpin #338/#340): the counter harness hashed `bin/cub_server`, which only links `lib/libcubrid.so.11.5` (243 MB, all engine code); the hash was identical for the pre-fix and post-fix builds, and a worker reported "the crashing and the passing binary are the same".
- Case (2026-10-13, PR 8145 gate): an incr build of 003104e still printed 8f6c805 in `cubrid_rel`; a build criterion of "cubrid_rel names the new commit" failed the gate on a good build.
- Source: memory:cub-server-hash-not-build-fingerprint, CUBRID_SSOT.md §3.1

### P4 — a copy runs the original's libraries
- Rule: A `cp -a` copy of an install runs the original prefix's libraries on the host, because CUBRID binaries carry `DT_RPATH=<original>/lib`, which wins over `LD_LIBRARY_PATH`; so a host-side baseline copy is probed before the original is rebuilt, or its `lib` is bind-mounted over the RPATH dir inside the job namespace, or it is made a real install with `patchelf --remove-rpath && patchelf --force-rpath --set-rpath <copy>/lib` on every ELF under `bin/` and `lib/` — and `readelf -d <copy>/bin/csql | grep RPATH` is read before any "base = …" comparison.
- Applies at: Copies of an install
- Case (2026-09-28, #372): `cp -a install-release install-release-c2` kept `DT_RPATH=<build prefix>/lib`; every "c1"/"c2" job loaded whatever the prefix held, and #372 concluded "commit 1 has no measurable gain" from a build compared with itself. Sign of the trap: two builds whose machine code differs on a per-row path give equal exact counts (±0.05 %).
- Case (2026-10-12, PRs 8130/8133/8136/8137): four reflink copies made as pre-fix baselines, originals rebuilt in place; `cubrid_rel` of the copies printed the new build, and one lane's "pre" trace numbers were fix numbers.
- Case (2026-10-20, CBRD-27583 lane B): a hand-written gdb job on an install copy ran the new build and produced a phantom defect (S3-43, withdrawn). `patchelf` (`nix-env -iA nixpkgs.patchelf`) fixed 34 files in a release install; plain `--set-rpath` turns DT_RPATH into DT_RUNPATH, `--force-rpath` keeps it; `ldd <copy>/bin/cub_server` must list `<copy>/lib`. The same week an in-place rebuild while another session's `just ctp` was copying the install produced a shard with mixed builds.
- Source: memory:install-copy-rpath-loads-original-libs, memory:bench-measurement-pitfalls

### P5 — `just build` has no SUPPORT_XA
- Rule: A DBLink DML check needs `cmake --preset optdebug -DCMAKE_INSTALL_PREFIX=<prefix> -DSUPPORT_XA=true` before `just build optdebug` (or a gha-ci archive build, which has XA), verified with `nm -D lib/libcascci.so | grep cci_xa_prepare`; a plain `just build` fails every remote-DML case with "N rows affected" and an unchanged remote; `just rebuild` wipes the build tree and with it the cached `-DSUPPORT_XA=true`, so configure again before it, for every build type the check runs on.
- Applies at: Commands
- Case (2026-10-07, CBRD-27365): the first candidate optdebug build had no `dblink_2pc_*` symbols and its libcascci lacked `cci_xa_prepare`; the remote CAS log showed `end_tran ROLLBACK` with no `xa_prepare`, so remote DML cases were NOK on the fixed engine. CI's build.sh passes `-DSUPPORT_XA=true`.
- Case (2026-10-20 and 2026-10-27, CBRD-27583 i1 / PR 8213 v36): a gha archive develop (XA on) was compared with a just-built branch (XA off), and later dblink shell cases were listed in a gate prompt on a reused `just incr` install — false NOKs both times (cbrd_27365, cbrd_26851 #16, cbrd_26921, cbrd_24501). In SA gdb: after the sink, `log_commit` never calls `dblink_2pc_get_participants`.
- Source: memory:just-build-lacks-support-xa

### P6 — a build resets the conf
- Rule: every build reinstalls `conf/cubrid.conf` from the source template; `build` then re-applies `just conf` (the campaign conf: `double_write_buffer_size=0`, `parallelism=24`, `log_buffer_size=256M`), `rebuild` and `incr` do **not** — after any build, read `parallelism`, `data_buffer_size`, `stored_procedure` and `max_plan_cache_entries` in the install's conf before using it, and restore a gate install's conf to the reference state.
- Applies at: Commands
- Case (workspace#157): CMake's install step reinstalls `conf/cubrid.conf` on every build, silently reverting whatever was there; `just build` now re-derives it, `just incr` does not.
- Case (2026-10-07, PR 8022 review #389): a develop install and its `-pc0` hardlink variant shared one `conf/cubrid.conf` (same inode), so the base ran with `max_plan_cache_entries=0` and a plan-reuse probe looked like a PR-only defect. Before an A/B: `rg -n '^(max_plan_cache_entries|plus_as_concat|return_null_on_function_errors)' <install>/conf/cubrid.conf` on both, `ls -i` the two conf files, and break a hardlink (`cp -p` to a temp name, `mv` back) before editing one.
- Source: CUBRID_SSOT.md §3.3, memory:ab-install-conf-check-plan-cache, memory:gate-install-conf-must-match-reference

### P7 — a comment-only change gets no build
- Rule: A comment-only change gets no build: verify that only PR-added lines changed, that the code is identical with comments stripped, and that the CI formatters (`indent -l120 -lc120 -st`, astyle with the codestyle.sh options) leave it unchanged.
- Applies at: Smoke before a delegated build
- Case (2026-09-29, PR 8022): after scrubbing workspace references from about 850 comments, a compile check was about to go to a worker; the user: "주석만 바뀌었는데 컴파일을 왜해. 그거 하지말고 마저 진행해." If a tiny non-comment change slips in (an unused table's id strings did), say so and let the PR's CI compile it; commit messages of a squash-merged PR need no cleanup.
- Source: memory:comment-only-change-no-build

### P8 — syntax-only with both compile commands
- Rule: For every changed TU, run the optdebug compile command from `build_preset_optdebug/compile_commands.json` with ` -fsyntax-only -fmax-errors=0` and the release command from `build_preset_release/compile_commands.json` with `-o /dev/null` (a real `-c` compile, not syntax-only), because `-Werror=maybe-uninitialized` needs the optimizer and only the release flags carry it; and when inserting a check into a long function, read the lines above it to confirm every variable it reads is assigned there.
- Applies at: Smoke before a delegated build
- Case (2026-10-23, PR 8213 gate v16): a check read `statement->xasl_id` about 30 lines before `statement = session->statements[stmt_ndx]`; the optdebug syntax-only pass was clean, the release build stopped with `-Werror=maybe-uninitialized`, and the optdebug install crashed every CAS at the first statement of every CTP case (16 shards stalled, one gate lost).
- Case (2026-10-28, dry run): GCC's `-fsyntax-only` does not run the optimizer, so the release command as syntax-only cannot raise `-Wmaybe-uninitialized`; the rule now compiles the release command for real into `/dev/null`.
- Source: memory:syntax-compile-with-release-command

### P9 — the compiler is the census
- Rule: To find every reader of a field, rename it in the header (`<field>_CENSUS_<tag>`), syntax-compile every TU of the tree (`xargs -P`, ~1200 TUs in about a minute, delegated), parse the `has no member named` errors with their struct name and `in expansion of macro` notes into a sites table, then undo the rename and check the tree hash — a grep census misses sites.
- Applies at: Smoke before a delegated build
- Case (dpin #355): a grep census missed `qdata_get_dbval_from_constant_regu_variable` and the diagnostic CTP died on it; the compiler census found 493 sites in 24 files (1214 TUs in 63 s with `xargs -P 48`). GCC's "did you mean" hint is not a matching signal (it suggested `domain_plan` for `arith_list_node::domain`); match on the struct name. Inline accessors that return the field (`REGU_VARIABLE_GET_TYPE`) need their callers checked too.
- Case (2026-09-30, PR 8022 C4, unused-member census): `private: … public:` wrapping reports nested accesses a rename stops at; GCC's message is `‘T X::m’ is private within this context`; skip C TUs, anonymous-union members and uses inside the class's own methods; GCC 8 reports unused-but-set for variables used only in a discarded `if constexpr` branch (false positives); removals cascade (wrapper → macro → next wrapper), so rerun until the reference count is empty.
- Source: memory:compiler-census-field-rename

### P10 — no source edits during a delegated build
- Rule: While a worker's build runs on a worktree, nobody edits, checks out or patches its sources: check `ps` or the workflow for a running build on that worktree first, and stage a mid-build decision as a patch file to apply after the `installed` line.
- Applies at: Delegated builds
- Case (2026-10-17, CBRD-27583): a peer reversed decision D-27 while build 26 was compiling; `system_parameter.c` was restored at 01:11:28 but its three objects had compiled at 01:11:08 from the reverted text. The install had `plus_as_concat` out of the plan key: 28 extra `_15_host_variable` failures and 4 `qdata_assert_arith_planned` cores the committed source would not produce, and the run was repeated. Also: keep the Bash tool's cwd out of smoke DB dirs (run scripts in a subshell), since removing the current directory is refused.
- Source: memory:no-source-edits-during-delegated-build

### P11 — one build per worktree at a time
- Rule: Two builds of one worktree (optdebug and release) run one after the other, never at once: both rebuild the JDBC jar inside the `cubrid-jdbc` submodule directory, and a build that copies it mid-rewrite into `build_preset_<mode>/pl_engine/lib` fails `pl_server:compileJava` with `package cubrid.sql does not exist`.
- Applies at: Delegated builds
- Case (2026-10-29, CBRD-27679): a worker ran `just incr optdebug` and `just incr release` on one worktree in parallel after a JDBC change; the optdebug tree copied a 1203-byte jar written while the release build was rebuilding it, and `pl_server:compileJava` failed on every `cubrid.sql`/`cubrid.jdbc` import. The release build passed, and the optdebug build alone passed afterwards. The first fresh builds of the same tree had run in parallel without failing, because the jar was only built once.
