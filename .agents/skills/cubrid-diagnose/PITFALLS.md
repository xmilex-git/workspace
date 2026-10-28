# PITFALLS — the rules in SKILL.md and the probes that produced them

Each `P<n>` is one rule. The **Rule** line is the exact sentence SKILL.md carries at the step named in
**Applies at**; keep the two byte-identical. **Case** is the probe or incident that paid for the rule.
**Source** is where the lesson lived before it was folded in here (auto-memory slugs are deleted once
absorbed; kept for traceability only).

Adding a case: one `Case (YYYY-MM-DD):` line under the rule it confirms, in the session that hit it.
A new rule only when no rule fits — then add the sentence to SKILL.md in the same commit.

## Where to run the probe

### P1 — CS mode, not SA
- Rule: A probe runs in CS mode on an optdebug build unless the question is SA-only: `csql -S` shows `show trace` as NULL for every statement, tracks no resource leaks, does not pack values over the network and never runs SERVER_MODE-only paths, so a defect in re-execution, value transfer, tracing or parallel scans is invisible there — use a `fast-cs` job (or JDBC) and read the trace right after the query.
- Applies at: Where to run the probe
- Case (2026-09-29, PR 7991 review): 12 of 12 traces NULL under `csql -S` on three installs; the fast-cs job (fast-sa plus a private netns, `ip link set lo up`, `cubrid server start`, `csql -C`) ran 9 jobs in 5–11 s.
- Case (2026-10-15, PR 7658): `prepare st … execute st` returned the previous execution's value in csql -C and in a CTP shell case, correct values in csql -S and in the CTP sql (JDBC) case — the freed per-execution block was reused, so the stale pointer read the right value unless the network packed it.
- Case (SSOT §1.6): a selftest passed in SA mode while the same query crashed a live server; the resource tracker's leak checks run per request in CS mode only.
- Case (2026-10-20): a tran_info probe copied a shell TC's `grep '$USER'` inside `unshare -U` and marked all 4196 loaddb rows as mismatches — the login user shows as `root` there.
- Source: memory:sa-probe-gotchas, memory:stale-read-defects-need-cs-csql-path, CUBRID_SSOT.md §1.6

### P2 — archive builds on the host
- Rule: A repro on a develop commit uses the archive build for that sha when the archive still has it, else a local `INSTALL_PREFIX=… just build` (release ≈ 3 min; it then overwrites the conf with the campaign conf — copy the worktree's `conf/cubrid.conf` back and set the port); an archive's binaries carry `RPATH=/home/CUBRID/lib`, so run them with `LD_LIBRARY_PATH=<inst>/lib` and confirm with `ldd`; `CUBRID_TMP` stays short (the socket path must fit 107 bytes); the install's master is stopped by the pid whose `/proc/<pid>/exe` is under it (no `cubrid master stop` in archives, never `cubrid service stop` or `pkill`); after a crash run, wait ~10 s before starting the next version so the respawned orphan does not register with the new master.
- Applies at: Where to run the probe
- Case (2026-10-07, #386): an 83-character `CUBRID_TMP` failed with `-359 Datagram bind error … Invalid argument`; 69 worked. `cubrid master stop` printed "utility-name is invalid". Core names used the thread's comm (`core.vacuum.<pid>`). Release logs `vacuum_er_log_error` lines with the stock conf; `er_log_vacuum=147` gives per-page timelines but GBs of log (`error_log_size` in bytes). An incompressible one-row-per-page payload: `varchar(10000)` of ~70 concatenated `sha2(…,512)` values (CHAR(9000) is rejected).
- Case (2026-10-13): the 2026-09-09 fix commit 3339858ec was gone from the archive (404) although it had been mirrored on 10-08; the window had moved from 09-07 to later. `tc-install.sh <sha>` falls back to a local optdebug build (~10 min).
- Case (2026-10-20, PR 8196 / develop c966fabc6 release tarballs): RPATH `/home/CUBRID/lib` does not exist on this host.
- Source: memory:host-repro-on-gha-archive-builds

### P3 — release-line installs
- Rule: "Since which version" is answered on release-line installs: `~/release/CUBRID-11.4.6.1963`, `-11.3.6.1321`, `-11.2.9.0866`, `-11.0.16.0419`, `-10.2.18.9024` (no public 11.1); 11.2/11.0/10.2 need `libncurses.so.5` from `nix-build tools/legacy-libs/ncurses5-el8.nix -o .git_ignored_dir/legacy-libs/ncurses5` on `LD_LIBRARY_PATH`; each install's conf is stock except `cubrid_port_id` — claim a port first, and when the port is taken make a shadow install (symlinks except `conf`, `log`, `var`, `tmp`) with the claimed port.
- Applies at: Where to run the probe
- Case (2026-10-18, CBRD-27668): the user asked for every release line, not only 11.5; installs were fetched from `https://ftp.cubrid.org/CUBRID_Engine/<line>/CUBRID-<stamp>-Linux.x86_64.tar.gz` (md5sum file beside). Rocky 8 lacks ncurses 5; nixpkgs `ncurses5` needs GLIBC_2.33+, so the Rocky 8.10 `ncurses-compat-libs` RPM is unpacked by the nix expression (user, 2026-10-27: "nix 이용해서 실행되게 만들어").
- Case (2026-10-19, #455): port 1708 was claimed by another session; shadow installs under `.git_ignored_dir/scratch/issue455/inst-<tag>` kept the shared installs' confs untouched; the runner stops the master by matching `CUBRID=` in `/proc/<pid>/environ` because `exe` resolves to the real install.
- Case (2026-10-25): zsh `$b:src/...` applies the `:s` modifier — write `${b}:src`.
- Source: memory:release-line-installs-for-version-checks

### P4 — A/B confs
- Rule: A/B over two installs starts with their confs: hardlinked variants (`cp -l`, `-pc0`) share one `conf/cubrid.conf` (`ls -i`), so `rg -n '^(max_plan_cache_entries|plus_as_concat|return_null_on_function_errors)' <install>/conf/cubrid.conf` on both before reading any result, and break the link (`cp -p` to a temp name, `mv` back) before editing one.
- Applies at: Where to run the probe
- Case (2026-10-07, PR 8022 review, #389): a develop "latest" install and its `-pc0` hardlink variant shared one conf (same inode), so the base ran with `max_plan_cache_entries=0`; a PREPARE → ALTER → EXECUTE probe then looked like a PR-only plan-reuse defect; with the cache on, develop reused the folded plan like the PR.
- Source: memory:ab-install-conf-check-plan-cache

### P5 — probe datasets
- Rule: A database loaded for a probe is generated by seed table × cross join × `ROWNUM <= N` (`CREATE TABLE t1 (n INT PRIMARY KEY)` with 10 rows, then `INSERT INTO t SELECT ROWNUM, … FROM t1 a, t1 b, t1 c … WHERE ROWNUM <= N`), never `CONNECT BY LEVEL <= N` beyond a few thousand rows; a recursive CTE stops at `cte_max_recursions` (2000).
- Applies at: Where to run the probe
- Case (2026-09-16, PR 7866 boundary check): `INSERT … SELECT level FROM db_root CONNECT BY LEVEL <= 300000` ran 30+ minutes at 100 % CPU with 8 GB+ RSS on the base build too — the hierarchical query's own cost, not the patch.
- Source: CUBRID_SSOT.md §3.19, memory:ctp-new-tc-needs-answer-and-as-is

## Designing the probe

### P6 — discriminate, and probe the no-key cases
- Rule: A claim about develop is made only after running it on a develop build with a discriminating row; a statement that fails on develop is run three ways on the candidate — with keys reached, on an empty table, and with a bound that skips every key — and the server log's error count is read beside the client message, because a check that moved from scan-open into the key compare fails only when a key is met.
- Applies at: Designing the probe
- Case (2026-10-20, CBRD-27583 an2/24905): develop fails an unindexable key value in `qexec_resolve_key_constant` (`tp_valid_indextype`) before any scan opens; the fork's -181 came from `btree_compare_bound_key` only when the range scan met a key, so a SEQUENCE bind failed on a table with rows but returned 0 rows on an empty table. The TC had rows everywhere. The clue was an extra -181 line in the server log: `scan_key_compare` clears the failed conversion with `er_clear()` after `er_set` wrote the line.
- Case (2026-10-25, PR 8213 Q19): "develop cuts 35203 to '3'" was stated without a run; the user: "develop이 숫자를 저렇게 잘라서 비교한다고??" — false, as was its rationale.
- Source: memory:error-probe-needs-no-key-reached-case, memory:verify-develop-claims-before-stating

### P7 — driver row
- Rule: A "subquery result reused across inner rows" or stale-dptr question is probed behind a driver row: `qexec_clear_all_lists` runs once per root row, so a 2-table join hides a missing per-row dptr reset; `xasl_debug_dump=yes` (optdebug, client parameter) prints which node owns the dptr list.
- Applies at: Designing the probe
- Case (2026-10-06, PR 8114 greptile review): the 2-table ANTI probe was 52/52 correct on develop; the same query behind a 1-row driver was 26/52 stale (CBRD-26872 anti-survive defect). The CBRD-27567 TC's `cz` table does the same.
- Source: memory:dptr-staleness-probe-needs-middle-scan

### P8 — grammar and client-side folding
- Rule: csql and CQT grammar that wastes a probe: `select @v := s a` is ambiguous — write `(@v := s) a`; no quoted values inside probe labels; `… group by g using index a, b order by 1` (not `using index … group by`); ROWNUM / ORDERBY_NUM() cannot share an expression with a column or correlated subquery (only CASE/IF/DECODE conditions escape); `count(*)` over a CONNECT BY subquery returns 1 per start row (CBRD-27461) — use `count(col)` or `max(level)`; CQT answers print only `Error:<code>`, so message-text changes are invisible to CTP; JDBC cannot prepare a CTE whose select list holds an untyped `?` (-494); `cast(? as int)` is coerced on the client, so the server's path never runs — hand it a string with `concat(?, '')`; literal-only expressions fold at compile; an indexed column's comparison fails at scan open on develop too (probe an unindexed column); a PL/CSQL function declared PARALLEL_ENABLE that uses SQL is refused at CREATE, so the runtime refusal text is reachable only by a Java SP or an undeclared SP in a worker, and PL/CSQL in a worker shows the client only -889 (the text is in `log/pl/*_pl.log`).
- Applies at: Designing the probe
- Case (#367 round 3): most bind statements tested nothing — `execute q using 'abc'` into `cast(? as int)` answered -494 on develop and dpin alike before the server's gate ran. Pair each statement with its result block before trusting a TC's coverage.
- Case (2026-10-13, PR 8136 Case 13): the CONNECT BY `count(*)` trap recurred after it had been recorded — the index count-only path in `qexec_intprt_fnc` does not exclude `connect_by_ptr`.
- Case (#364): proving a PX scan over JDBC — CasProbe's `run()` checks the connection with `select 1 from db_root` after every case, so the next `show trace` traces that; read the trace right after the query. CasProbe compiles once per out-dir (`classes-<jar hash>`): a new out-dir after editing it.
- Source: memory:sa-probe-gotchas

### P9 — develop's answer needs a reason to break
- Rule: A statement that runs on develop keeps running unless the break is justified at spec level: SERIAL (`s.next_value`, `s.current_value` in comparisons, arithmetic, aggregates), host variables, PL/CSQL and JDBC binds are written by real applications, so turning their develop result into an error means the engine is wrong, not the test; session variables as typed operands are the only accepted exception, and the exception list is recorded in the ticket.
- Applies at: Designing the probe
- Case (2026-10-07, PR 8022 first-value experiment): the user: "develop에서 되던데 안되려면 그만한 근거가 있어야한다? 하위호환성 깨지면 큰일날만한 질의여야해. 물론 세션변수같은건 아무데서도 안쓰니까 상관없는데, serial 같은건 되어야해."
- Source: memory:develop-worked-needs-reason-to-break

### P10 — widen the view on repetition
- Rule: When the same item fails twice, or a fix for symptom A surfaces symptom B of the same kind, stop patching consumers: write the shared-cause hypothesis in one line (a producer decision vs its consumers), measure develop per consumer kind in separate statements (output, aggregate, comparison, arithmetic, CAST, WHERE/IN/BETWEEN, ORDER BY, CASE) across releases, fix at the decision site, delete the consumer patches, add a generation-time assert comparing the decision with the declaration, and only then rerun the gate; a type the compiler can know from the schema, spec or plan is a generation defect, never an exception.
- Applies at: Designing the probe
- Case (2026-10-19, CBRD-27583 S3-33): b144 and b145 patched consumers (output column, then aggregates) of one untouched producer decision (an ENFORCE cast over ENUM decided as element-less ENUM while type checking declared VARCHAR); per-consumer measurement showed develop decides every consumer as VARCHAR. The user: "교훈좀 써놔. 뭔가 몇번 헤매는 상황에서 더 넓은 시각으로 봐서 고치는. … 자꾸 포기하더라고 몇번 실패하면." "Two failures → stop" is a brake on stacking blind fixes, not a reason to drop the item.
- Source: memory:widen-view-on-repeated-failure

## Instrumenting

### P11 — the server's own stack dump
- Rule: For "where does the server raise error -NNN", add `call_stack_dump_activation_list=-NNN` to the smoke conf: `er_set` writes the symbolized stack into `$CUBRID/log/server/<db>_<date>.err` with no debugger; client-side parser errors do not pass `er_set` — run SA `csql -S` under `timeout N gdb -batch -x <script> --args …` (gdb owns the process and ends with it); SERVER_MODE-only paths show in `xasl_debug_dump=yes` (access-spec flags such as `no_parallel_scan`); never `pgrep -f` with a string that appears in your own command line, never an unbounded `wait`, every csql/gdb under `timeout`, and a smoke that rewrote the install conf copies the claimed-port conf back at the end.
- Applies at: Instrumenting
- Case (2026-10-17): a smoke did `P=$(pgrep -u $USER -f "cub_server svdb")` then `gdb -batch -p $P … &` and `wait`; the pattern was in the calling zsh's own command line, so gdb attached to the tool's parent shell, which waited on the script while the script waited on gdb — the user had to interrupt ("gdb 스크립트에 hang문제가 있는거같아").
- Source: memory:server-stack-at-error-without-gdb

### P12 — the gdb boundary
- Rule: gdb is a diagnosis tool, not verification evidence, and it never attaches to a live `cub_server` (a 2026-08-06 attach produced a server core during QA): it reads cores offline and runs SA `csql -S` inside a namespace job (`gdb -batch -x cmds.gdb --args csql -S … -i <sql>` with a pending breakpoint whose `commands` print `bt` and `continue`; `info breakpoints` at the end gives the hit count; a runner waits for a `printf "=== GDB READY\n"` the commands file emits before its first `continue`, since `-p` attach does not echo "Continuing."); break on a source line, not an extern function (the `@plt` stub stops first with no arguments and aborts the `commands` block), read `info breakpoints` sub-locations before comparing hit counts, and expect an optdebug frame line to sit at a loop head near the real call.
- Applies at: Instrumenting
- Case (2026-08-06, CBRD-27181 QA): a gdb attach session produced `core.cub_server`; live attach has been banned since, and code-path proof moved to `perf record -p` symbol bands, counters and A/B outputs.
- Case (2026-09-27, #368 C11): the namespace gdb job (`gdbjob.sh <job dir> <install> <sql> <gdb cmds> <out prefix>` under `unshare -Urmipf --mount-proc --kill-child`, job dir removed with `podman unshare rm -rf`) hit `domain_key_pairs_make` 0 times on constant collections and once on a row's multiset column — pick SQL that reaches the function. fast-sa jobs share pid 15, so same-second cores overwrite.
- Case (2026-10-06, nodatafilter repro): `break pgbuf_ordered_fix_debug` bound libcubrid.so's PLT stub, a condition on an argument failed ("No symbol caller_func") and hit counters doubled. In b179, a breakpoint with 3 locations showed 15 hits for 5 calls.
- Source: memory:sa-gdb-breakpoint-in-namespace, memory:sa-probe-gotchas, CUBRID_SSOT.md §1.6

### P13 — cores by pid; container cores with a sysroot
- Rule: A core is matched by the pid you own, never by time and name: start csql with `&` and keep `$!`, take a `cub_server` pid from `/proc/<pid>/exe` before the probe, then `find /data/core/ -name "core.*.<pid>.*"` — `%e` is the crashing thread's comm, so a server assert is `core.transaction.<pid>…` or `core.vacuum.<pid>…`, never `core.cub_server.*` — and run gdb with that process's binary; a core from a `just ctp` container unwinds to `?? ()` without the image's glibc: extract the cubridci image rootfs once (`podman create --name x docker.io/cubridci/cubridci@sha256:<digest>`, `podman export x -o rootfs.tar`, `tar -xf … -C <scratch>/rootfs`, `podman rm x`) and read it with `gdb -batch -ex "set sysroot <rootfs>" -ex "set solib-search-path <run>/shard_0/CUBRID/lib" -ex "file <run>/shard_0/CUBRID/bin/cub_server" -ex "core-file <core>" -ex "bt 40"` (the crashing thread is current; an assert shows as `abort_handler → __assert_fail → <CUBRID frame>` with file:line; the assertion text is not in the core); cores are sparse — `du`, not `stat`.
- Applies at: Instrumenting
- Case (2026-10-07, #388): two parallel lanes used `find /data/core -name "core.csql.*" -newer .mark`; the release lane caught the optdebug lane's csql cores, ran gdb with the wrong binary (all `??`) and deleted them; `core.cub_server.*` never matched the server crashes. `timeout`'s child pid is not `$!` — use a watchdog.
- Case (2026-09-28, #345): four container cores gave full backtraces with file:line once the image rootfs (717 MB) was the sysroot; a copy for digest 79a344fc… sat at `.git_ignored_dir/scratch/cbrd25717-repro/rootfs` as of 2026-10-06.
- Source: memory:match-host-cores-by-pid, memory:container-core-gdb-sysroot, CUBRID_SSOT.md §7.3

### P14 — cross-thread heap frees
- Rule: An `mspace_free` / `db_private_free` abort on a `parallel-query` thread is a cross-thread free until proven otherwise: `cub_server` private heaps are per-thread dlmalloc mspaces (`FOOTERS=0`), so a buffer freed by a thread that did not allocate it aborts only when the address check catches it and silently corrupts both heaps otherwise, which makes a bisect non-monotonic; in gdb, `thrd->private_heap_id` is the `HL_MSPACE*` — print `((mstate) msp)->seg` base/size for the crashing thread and for the connection thread with the same tran_index (the one in `qexec_execute_query` / `run_jobs`) and see which range holds the freed pointer, then look for a main-thread producer (gate, pin, recipe) of the freed value.
- Applies at: Instrumenting
- Case (2026-09-21, #307): the pre-execution gate evaluated a value-invariant expression on the connection thread; the PX worker that ran and cleared the same-tree aptr freed it. The bisect had pointed at four different commits. develop guards `TYPE_SP`/`TYPE_DBVAL` the consumer way in `qexec_clear_regu_var` (`for_parallel_aptr`); the fix rule: whoever settles a slot before execution leaves no allocation in it.
- Source: memory:cross-mspace-free-nonmonotonic-bisect, CUBRID_SSOT.md §4.2

### P15 — checkdb is not a test
- Rule: `cubrid checkdb` is not a test: "정합성 체크" in this workspace means comparing query results (variants against a serial no-hash reference), checkdb runs only for work that changes index structure (page split/merge, overflow keys, prefix separators) on a small DB and is named in the report, and worker prompts carry "no checkdb".
- Applies at: Instrumenting
- Case (2026-10-19, CBRD-27583 S3-37): `FAST_CS_CHECKDB=1` had been set on every smoke job when only the overflow-key B-tree smoke needed it; the user: "checkdb는 개 느려서 테스트로 쓰면 안되긴할텐데." 2026-10-22 (CBRD-27727), after "좀 크게해서 정합성좀 맞는지 체크해봐": "checkdb 는 ㅈㄴ 느리니까 쓰지말라고" — name the method in the first status line ("결과 비교, checkdb 아님").
- Source: memory:checkdb-not-a-default-smoke, memory:checkdb-not-a-test-method

## Reporting a triage

### P16 — the triage report
- Rule: A defect-triage report says, per issue, whether it occurs on a develop **release** build with the engine-default conf (only the port set) in CS mode, a 0–10 severity (integrity breaks high, shapes nobody writes low; an optdebug-only assert scores 0) and the reason, with repro steps that read "start the server, run this SQL"; no release outcome is stated from source reading (a release PREPARE once failed with "Internal error- reporting semantic error" where the source read as "passes silently"), issue-body claims are re-probed before they are repeated, fix directions and internal tool names stay out (stack frames as evidence are fine), and it is delivered as a Korean `.md` via SendUserFile plus a short summary table.
- Applies at: Reporting a triage
- Case (2026-09-28, #326~#370 triage): the user: "실제로 발생 가능한지, 얼마나 심각한지 이런것만 따져서 보고하면돼. 어떻게 해결할지는 해결하는 사람 마음이라.." and "격리 실행 도구도 넘길 필요없이, 그냥 엔진 켜서 테스트 하는 기준으로 넘겨줘". #347 ("stored as NULL") and #359 ("hidden in develop") were wrong as written; #349 item 3 did not reproduce.
- Case (2026-10-06, #380 item 6 → CBRD-27573): "release passes silently" predicted from an `ER_FAILED` without a parser message; the release PREPARE actually failed — "don't file" became "file".
- Source: memory:defect-triage-report-style

## Cleanup

### P17 — delete what is analyzed
- Rule: A core whose cause is recorded (assert text + case, or a backtrace in `cores-analyzed.txt` under the effort's scratch) is deleted at once by literal path, as are the smoke DB dirs of each batch after their logs are read and every CTP run dir whose evidence has been copied out (keep only the latest passing baseline); other sessions' cores are listed for the user, never touched; a "how much disk" question is answered with a per-location `du` table (scratch, run dirs, cores, worktree).
- Applies at: Cleanup
- Case (2026-09-23 → 2026-10-17, four reminders): "코어 분석된건 지우면서 진행좀" (170 cores, 393 G from one crash-looping shard; 539 G of diagnosed cores in the dpin store); "코어 정리 잘해가면서 작업해 … CTP 결과도 분석끝났으면 좀 지우고!!"; "core 랑 CTP 결과 분석바로바로 해서 정리/제거"; "코어 지워가면서 작업중이지? 디스크 얼마나 사용중이야" (432 smoke DB dirs, 89 G; 65 G of cores from builds whose binaries were gone). After a rebuild of the install the old cores cannot be symbolized anyway. `rm -rf` takes only literal absolute paths written out in full.
- Source: memory:delete-analyzed-cores
