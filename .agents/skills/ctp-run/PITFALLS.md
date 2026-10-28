# PITFALLS — the rules in SKILL.md and the runs that produced them

Each `P<n>` is one rule. The **Rule** line is the exact sentence SKILL.md carries at the step named in
**Applies at**; keep the two byte-identical (`rg -F "<rule>"` finds both). **Case** is the run that
paid for the rule. **Source** is where the lesson lived before it was folded in here (auto-memory
slugs are deleted once absorbed; the slug is kept for traceability only).

Adding a case: one `Case (YYYY-MM-DD):` line under the rule it confirms, in the session that hit it.
A new rule only when no rule fits — then add the sentence to SKILL.md in the same commit.

## Gates and baselines

### P1 — gate build type
- Rule: A gate runs on the **optdebug** install and is compared only against a baseline of the same build type; every failure count is reported with its build type.
- Applies at: Gates
- Case (2026-09-19/20, wf268 #286): three release-only gates reported `NEW:0 GONE:0` while the branch broke invariants — `assert()` compiles out of release and the answers stayed correct; the first optdebug run showed 365 failures and 74 cores against a baseline of 50 and 1. The same week a "crash regression" was bisected to a commit and then to a fix: every 1-core measurement had used an optdebug install and every 0-core measurement a release one. The defect (a tuple read past the end from `mq_rewrite_order_dependent_query`) was pre-existing on develop — a silent NULL in release, a clean abort in optdebug.
- Source: memory:ctp-gate-optdebug-only, memory:ctp-list-comparison-pitfalls

### P2 — shell is CI's
- Rule: The whole shell suite never runs locally; a local shell subset runs once, right after a crash fix, with the exact dirs that crashed — every other shell verdict comes from upstream CI (`/run all`).
- Applies at: Gates
- Case (2026-09-23, map #312): the user, on seeing a full local shell run: "shell suite 를 전부 로컬에서 돌리고있어..? 그거 하지마 엄청오래걸림.. 나중에 upstream pr 생기면 거기서 CI/CD로 돌릴거야." A full local shell run ties up the host for hours.
- Case (2026-10-20, CBRD-27583 b186/b187): a 2,022 s shell subset ("union 124") sat on the critical path of every push although CI's `/run all` runs the whole suite after the push anyway; the user: "shell을 왜 자꾸 쳐 돌릴까?". The subset earned its time once, confirming the b185 crash fix (CI-1 kinds A1–A4).
- Source: memory:no-local-full-shell-suite, memory:shell-ctp-local-only-for-crash-confirmation

### P3 — engine ↔ testcases skew
- Rule: Before a gate, fetch upstream develop for both the engine and cubrid-testcases and build from an engine tip paired with the TC ref; a NOK, hang or off-by-one catalog count shared by the branch and the develop baseline is skew, not "develop common", until `git log <engine-base>..origin/develop` shows no engine PR paired with that case's TC commit.
- Applies at: Gates
- Case (2026-09-21, CBRD-27465): full sql 17465/17466; the one failure (`19_user_cursor_system_view.sql`, DBA counts 550→549) was an engine base that predated #7976 (db_histogram). An A/B run was spent proving it "environmental" before the user named the skew; rebasing was the fix.
- Case (2026-09-29, PR 8034 / #8051): gha-ci cuts `tc/pr-N` from the current TC develop while the engine branch sat on an older develop; `_13_shard_command` (`CACHE_USER_INFO` removed by #7941) and cbrd_27485 (debug assert partition.c:903, whose abort failed the next 4 cases) failed for that reason alone. Fix = `/cubrid-pr-sync` then `/run all`.
- Case (2026-10-17, CBRD-27583): `cbrd_27379/02_hash_join_mode.sql` "hung" (300 % CPU, parallel heap scan workers in `mr_cmpval_char`) on branch and baseline alike — the TC and its engine PR #8001 (SEMI/ANTI hash join) both landed after the base commit. First called "develop common"; the user: "저 엔진 수정을 넣고 돌려야지, 다 최신화하고 진행해".
- Case (2026-10-15, PR #8145): a PR merged green and still broke develop — gha-ci builds the PR head as-is against a `tc/pr-N` tip nobody re-syncs; TCs #3747/#3696 landed after the last sync and went NOK on develop after the squash merge. Before merging a PR that changes shared output (trace, plan text, catalogs), re-sync and `/run all` on the synced head.
- Source: memory:ctp-engine-tc-develop-skew, memory:ctp-shell-false-nok-sources (develop-install skew)

### P4 — install confs are gate inputs
- Rule: Before delegating a gate, `cmp` the install's `conf/cubrid.conf` and `conf/cubrid_broker.conf` against the reference state (`just incr` reinstalls the factory templates and does not re-apply `just conf`; a smoke that writes install confs restores them), and read `parallelism` in the install conf before suspecting a patch for a PX trace failure.
- Applies at: Gates
- Case (2026-10-18, CBRD-27583 b110): a JDBC smoke runner copied a session cubrid.conf and a `%smoke27583` broker conf into the install two minutes before the gate; the whole CQT workload ran through that broker. Byte-equal results, but not a like-for-like comparison — discarded and rerun after restoring the templates. Shard CAS logs named `smoke27583_*.err` instead of `broker1_*.err` were the tell.
- Case (dpin #334): a counter bench's cleanup trap left `parallelism=0` in the install conf; the next CTP run failed every PX trace TC (18/156) — only the `(parallel workers: …)` lines were missing. One round-trip lost on a "PX regression" that was a conf line.
- Source: memory:gate-install-conf-must-match-reference, memory:counter-harness-leaves-parallelism-0, SSOT §3.3

### P5 — the campaign conf has the DWB off
- Rule: Treat a crash-recovery anomaly seen under a `just conf` / `port-claim` install as "double write buffer off" until it reproduces with a conf holding only `cubrid_port_id`.
- Applies at: Gates
- Case (2026-09-28, #348 triage): the repo's `cubrid.conf` has carried `double_write_buffer_size=0` since 2026-09-16 (with `parallelism=24`, `log_buffer_size=256M`), so every campaign CTP server ran with the DWB off; all the redo-assert observations came from such servers, while 13 kill -9 cycles on a default-conf release server recovered cleanly.
- Source: memory:campaign-conf-disables-dwb

### P6 — fingerprint the install the shards copied
- Rule: When runs share an install another session may rebuild, run with `CTP_KEEP_COPIES=1` and report `sha256sum shard_*/CUBRID/lib/libcubrid.so shard_*/CUBRID/lib/libcubridsa.so` for every shard of every run (a swap can hit any shard); warn the sessions running CTP on an install before rebuilding it.
- Applies at: Gates
- Case (2026-10-20, CBRD-27583 dev14-a): seven runs launched in the same second from one install; one shard copy carried b187's libraries and six carried b188's — another session had overwritten the install during the copy window. The install's mtime, ctime and `cubrid_rel` still named the old build; provenance.txt records only the install path.
- Case (2026-10-28, dry run): the rule named `shard_0` only, while its own case had one mixed shard among seven — hashing every shard closes that.
- Source: memory:ctp-install-swapped-mid-copy, SSOT §3.1

## Reading a run

### P7 — verdicts come from CTP's own log lines
- Rule: Take verdicts from CTP's `[OK]`/`[NOK]` lines (sql/medium: `shard_N/out/log/sql_*.log` after the prune, `shard_N/CTP/sql/log/sql_*.log` with kept copies, pairing each `Testing <path>` with the next verdict token; shell: `shard_N/out/result/shell/current_runtime_logs/feedback.log`), never from a raw `.answer` vs `.result` diff, and strip the `sql/` prefix before comparing two case lists.
- Applies at: Diagnosing a bad run
- Case (2026-09-21, #285/#295): a "29 new regressions" claim came from a release list used as the baseline of an optdebug run, lists that disagreed on the `sql/` prefix (so every case looked new), and a raw answer/result diff that over-reported 16 whitespace-only differences in 17,466. An hour of bisect and two runtime tasks before the premise was checked.
- Case (2026-10-20, CBRD-27583 i1): a shard stopped by the crash-loop watchdog (rc=137) was missing from `failed.list` and the console — `bug_bts_14651` NOK was in neither; feedback.log had it. Its `HH:MM:SS----<case>/cases--- time=N` lines map a core's epoch to its case; CTP reruns a NOK case at the end, so a late core can belong to an early case.
- Source: memory:ctp-list-comparison-pitfalls, memory:ctp-shell-false-nok-sources

### P8 — shell NOKs a `just build` install cannot pass
- Rule: Compare a branch shell run only against a develop install built the same way (`just build`), and read these before calling a shell NOK the change's: DBLink 2PC cases (no `SUPPORT_XA`), cases reading `cm.conf` or counting `cubrid service` lines (no CUBRID Manager), cases editing `$CUBRID/databases/databases.txt` (the runner sets `CUBRID_DATABASES=/home/CUBRID_DB`), `grep -wc 100` on the container IP, `wait_until` (absent from the image's CTP db90747), and answer files named `*.result` (the runner's rsync excludes them).
- Applies at: Diagnosing a bad run
- Case (2026-10-19/20, CBRD-27583 i1, 239 dirs): `cbrd_27365` 1/2/4 and `cbrd_26851` #16 (XA-less build, proof: remote CAS sql_log `execute … tuple 1` then `end_tran ROLLBACK`, 0 `xa_prepare`); `cbrd_25446`, `cbrd_26349`, `cbrd_24911`, `cbrd_24404/_03_setting` #12/#15 (runner environment, same NOK on develop and branch, OK on CI); `bug_bts_9337` #2 (`wait_until: command not found`); `itrack_1003147` ("Cannot find the proper file for I1003147.result"). Four i18n cases that force-rebuild the locale failed "make_locale failed" until dbc5324 stopped injecting `libcubrid_all_locales.so` into shell shards.
- Source: memory:ctp-shell-false-nok-sources, memory:ctp-engine-tc-develop-skew (wait_until)

### P9 — one abort poisons the rest of the shard
- Rule: A server that stops on a debug assert is respawned, and every later case in that shard fails -581 then -669/-677 — run with `NO_ABORT_ON_CORE=1`, find the `Assertion` lines in `console.log`, and rerun the poisoned cases alone; a core is charged to the case running when it finished writing, so confirm a charged case by running it alone on the same build.
- Applies at: Diagnosing a bad run
- Case (2026-09-29, A/B of cubrid-testcases#3588): constant_errors, plcsql_slot_gate and parts of analytic_interpolation_keys looked NOK only because of an earlier crash; the rerun reached a second assert the first crash had masked.
- Case (2026-10-12, CBRD-27365, QA's cbrd_27510 report): a 4 GB optdebug core finished writing during the next case, so case 18's crash was charged to 19.
- Source: memory:develop-assert-poisons-later-cases, memory:ctp-engine-tc-develop-skew

### P10 — wall-clock cases
- Rule: A timezone case that flips between runs minutes apart is checked against the DST transitions of the zones it names at the run's UTC time, and develop is rerun in the same window before a commit is suspected.
- Applies at: Diagnosing a bad run
- Case (2026-09-27, #368): `_08_current_date_function/_02_functions/cases/_10_new_time.sql` fails 13:00–14:00 UTC on the day Pacific/Chatham enters DST (`Sep lastSun 2:45s`; next 2027-09-26): Error -495 twice, root ER_TZ_DURING_DS_LEAP -1166. The develop install fails it byte-identically in the same window; a host SA probe does not.
- Case (2026-10-01, PR 8034 gate 07:52 UTC): `_02_addmonths.sql` verdicts #10–#15 NOK — +1 month from Oct 1 02:52 CDT lands on the US DST end (Nov 1), shown as 01:52 CST, so `expect_value=1` while the month diff is 0. The rerun at 08:00 UTC was 26/26 OK. Window: Chicago 02:00–03:00 on the 1st of a month before a US DST change.
- Source: memory:ctp-chatham-dst-day-new-time, memory:ctp-addmonths-us-dst-window

### P11 — shard server logs carry the install's history
- Rule: A census over `shard_N/out/cubrid-log/server/*.err` selects files with `-newermt '<run start, from the run dir name>'` and skips the `*_latest.err` symlinks, because the install's existing server logs are copied into every shard.
- Applies at: Diagnosing a bad run
- Case (2026-10-18, CBRD-27583 4.6a): one old smoke statement was counted 48 times (16 shards × 3 files) as if CTP had run it.
- Source: memory:ctp-shard-logs-include-install-logs

### P12 — CTP's databases are utf8
- Rule: CTP sql/medium databases are utf8 (`utf8_bin` in error messages, although the conf line reads `db_charset=en_US`), so a smoke that stands in for CTP on string, collation, name or client/server value-transfer paths runs on an `en_US.utf8` database through a CS client (csql -C or JDBC), never only on an `en_US` (iso88591) SA database.
- Applies at: Gates
- Case (2026-10-17, CBRD-27583 4.8): every SA smoke passed on an iso88591 DB, then 5 CTP cases with non-ASCII session-variable names failed -1386: a CHAR name built with precision = byte length is space-padded when packed for the network in utf8, so the server's byte compare missed it; on iso88591 bytes = characters, and SA mode does not pack at all.
- Source: memory:ctp-sql-db-is-utf8

### P13 — a gha-ci shard "hang"
- Rule: For a gha-ci shard that stops printing, read the last `Testing … (n/N) [OK]` line of the job log, take case n+1 from the `tc/pr-N` tree, and check that case's engine pair against the PR head before blaming the last visible case.
- Applies at: Reproducing CI failures
- Case (2026-10-22, PR #8214, run 39696274206 shard sql 09): the user saw `cbrd_27299_java.sql` "never ends" because its 131,075 PARALLEL_ENABLE refusal lines were the last visible output; it had passed in 15 s. Case 415, `cbrd_27655` (REGEXP empty match), looped forever on an engine without 800d85f48. A hanging case's `Testing` line has no newline yet, so GitHub never shows it.
- Source: memory:ctp-engine-tc-develop-skew

## Storage and cleanup

### P14 — provenance before rm
- Rule: Before `rm -rf` of a run dir or its `/bench/hdd/core/ctp/<run>` store, `head -1 <run>/provenance.txt` and match `install=` to your own install and `testcases=` to your ref; delete only the runs you started — identified by the `plan written to <OUT>` line of your own launch output (medium's from its `medium-beside-sql-*.log`), never "the ones near my timestamp" — by literal path; `just ctp-prune` keeps the newest N regardless of owner, so it is not used while other sessions' runs share the root.
- Applies at: Output → Storage
- Case (2026-10-08): `sql-20261008T063936Z-975762` / `medium-…-975761`, deleted as "my gate worker's leftover reruns", were another session's PR 7834 gate evidence (`install=…/pr7834/install/head-optdebug testcases=cubrid-testcases@tc/pr-7834`). Its console.log, verdicts and reports were lost; the user was told. `/home/cubrid/ctp-run-out/workspace/` is shared by every session on this host and gate timestamps overlap.
- Source: memory:ctp-run-dir-check-provenance-before-rm

### P15 — recipe parameters are positional
- Rule: Recipe parameters go after the recipe name, positionally (`just ctp-prune 3`); env knobs (`BUILD=`, `TC_REF=`, `SHARDS=`) go before `just` — `just ctp-prune KEEP=3` does not bind KEEP.
- Applies at: Output → Storage
- Case (2026-09-27): `just ctp-prune KEEP=3` made `[ "$i" -le "KEEP=3" ] && continue` fail inside an `&&` list, so every run under `~/ctp-run-out/workspace` was deleted, including the #366 gate runs meant to be the next baseline. Commit 942c904 made ctp-prune refuse a non-numeric KEEP.
- Source: memory:just-recipe-params-positional

### P16 — analyze, then delete
- Rule: Right after a run's evidence is read (verdicts, diffs, census extracts copied to scratch), delete the run and its analyzed cores — record a core's backtrace or assert text first — keep only the latest passing baseline, `podman rm` the run's exited `ctprun_*` containers first, and list other sessions' cores for the user instead of touching them.
- Applies at: Output → Storage
- Case (2026-09-23 → 2026-10-17, four user reminders): "코어 분석된건 지우면서 진행좀" (one crash-looping shard: 170 cores, 393 G; the dpin store: 539 G of diagnosed cores); "CTP 결과도 분석끝났으면 좀 지우고!!" (≈100 analyzed run dirs, 400 G of NVMe); "core 랑 CTP 결과 분석바로바로 해서 정리/제거"; "코어 지워가면서 작업중이지? 디스크 얼마나 사용중이야" (432 smoke DB dirs, 89 G; two run dirs unpruned because 32 exited `ctprun_*` containers were still there; 65 G of cores from builds whose binaries were gone). Cores are sparse: `du`, not `stat`, gives the real size. A volatile workdir needs `podman unshare rm -rf`. Answer a "how much disk" question with a per-location `du` table.
- Source: memory:delete-analyzed-cores

## Small runs

### P17 — the single-case fast path
- Rule: A small CTP check runs candidate and control at the same time, puts `CTP_KEEP_COPIES=1` in the first command whenever the `.result` is needed, passes `EXCLUDE=''` when the case is in `dirsplit_exclusions.txt`, and the worker prompt carries only the commands and the facts to report.
- Applies at: Suites (subsets)
- Case (2026-09-29, PR 7866 cbrd_26473): each single-case run took ≈45 s (the case: 1.3 s), yet the check took 13 minutes — the first attempt died on a jar-less install, the prompt omitted `CTP_KEEP_COPIES=1` so run A was repeated, and the runs went one after another. The user: "그 1건 돌려보는데 시간이 이렇게 많이걸려?".
- Case (2026-10-07, CBRD-27365): `_36_guava/cbrd_27485` is in `dirsplit_exclusions.txt`; the A/B on gha-ci develop archives needed `EXCLUDE=''` to run it alone.
- Source: memory:single-case-ctp-fast-path, memory:ctp-engine-tc-develop-skew

### P18 — `CONF=` is not for stored_procedure
- Rule: The image's stock `CTP/conf/sql.conf` already sets `java_stored_procedure=yes` and `stored_procedure=yes`, so runs with and without a `CONF=` that only adds them are comparable.
- Applies at: Env knobs
- Case (2026-09-21, wf268 #285): a campaign `ctp-conf.conf` delta of `stored_procedure=yes` passed via `CONF=` was a no-op, which made candidate-only runs comparable with the cited upstream CI baseline.
- Source: memory:ctp-stored-procedure-default-and-ci-baseline
