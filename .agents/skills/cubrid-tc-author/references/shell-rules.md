# Shell testcase rules (CTP `shell` suite, cubrid-testcases-private-ex)

Work in the TC worktree from [pr-and-jira.md](pr-and-jira.md) §1 (`~/dev/cubrid-tc-ex-worktree/cbrd_<N>`
in merged mode, the private-ex `tc/pr-<PR>` worktree in open mode).

**The shell rulebook is the source.** Before you write, change or review a shell TC, read from that
worktree `AGENTS.md`, `shell/AGENTS.md`, `shell/rules/test-perspectives.md` and
`shell/rules/writing-rules.md` (QA's deployed copy, merged by CUBRIDQA-1686; the worktree carries the
develop or bot-branch copy, so it is the current one). This file holds only what the rulebook lacks: the
points where we decided to differ, the CTP facts behind our checks, and the CUBRID-internal judging
methods (trace counters, parallel thresholds, margins, crash detectors). Anything else that disagrees
with the rulebook is a defect of this file: follow the rulebook and tell the user.

Model files: the rulebook's three ("Model TCs" in `test-perspectives.md`) for form, with their "Differs"
lines. For trace and concurrency judging only: `shell/_06_issues/_26_2h/cbrd_27484/cases/cbrd_27484.sh`
(concurrent sessions, pid/core/assert detectors) and `shell/_06_issues/_26_2h/cbrd_27486/cases/cbrd_27486.sh`
(parameter + per-session observation). Differs: both end abort paths with `exit 0` and wait with counter
loops around `sleep 1` (rulebook: `exit 1`, `wait_until`); cbrd_27484 finds cores with `-name "core"` and
no `-type f` (rule 12). CTP's own guide: `~/cubrid-testtools/doc/shell_guide.md` §5.

## Where we differ from the rulebook (user, 2026-10-30)

- **Builds**: pre, fix and dev on optdebug only; no release run, and the PR table names optdebug
  (rulebook: release and debug). Release hides asserts (verify.md).
- **Half-year directory**: a Correct Error TC goes under the half-year in which the TC is written
  (`_06_issues/_26_2h/` from 2026-07 to 2026-12), as QA's mail announcing the rulebook says and
  cubrid-agent PR #35 sets for sql. The rulebook text still says "the half-year in which the issue was
  created"; the question went to CUBRIDQA-1505.
- **Empty draft TC PR**: kept open (pr-and-jira.md §1); the rulebook closes it and reruns `Check TC PRs`.
- **`kill -INT`**: allowed only on a pid the TC saved with `$!` from its own `timeout -s INT … &`, with a
  comment saying why (rule 10); `xkill_pid` is `kill -9`, which loses the output `cubrid statdump -i`
  prints when it stops.
- **Timing**: a time or footprint check never goes under `shell/`; a performance-only change with a
  switch to the old path gets a `shell_perf` TC (rule 25, judge.md R4).

## How CTP runs the script — facts the rules follow from

- `. $init_path/init.sh; init test` sets globals **`result_file`, `case_name`, `case_no`, `cur_path`,
  `run_mode`, `answer_no`, `pids`** and puts CTP's `cubrid` wrapper first in `PATH`. `write_ok [msg]` /
  `write_nok [msg|file]` append one line to `${cur_path}/$result_file` and increment `case_no`.
  **CTP reads only that `.result`.** A helper that assigned `result_file` redirected every later verdict
  into a log the case then deleted — 7 checks, 1 line, reported OK (2026-09-30).
- CTP runs the script with **xtrace on**. A result line written in two commands gets a `+ echo`
  trace line between them (`19200+ echo`, 2026-09-23). Background work writes its stderr to its own
  file so the trace never lands in a result file.
- `finish` stops services, frees broker shared memory, restores every conf changed through
  `change_*_parameter`. It must be the **last** call on **every** exit path.
- `cubrid deletedb` (the wrapper) checks for cores and fatal errors and backs up volumes/logs.
- The server is **auto-restarted** after a crash: only the pid, a new core, or an `assertion` line in
  `$CUBRID/log/server/<db>_*.err` tells.
- `show trace` prints `(parallel workers: N, ...)` on the line **after** `SCAN (table: ...)`: grep with `-A1`.
- Digits are **not** masked here, so a shell TC is where worker counts, readkeys, page counts and
  statistics are asserted (judge.md R2).

## File skeleton (copy, then fill)

```bash
#!/bin/bash
:<<'DESCRIPTION'
Issue:
  CBRD-<N>: <symptom in one sentence>.
  <2-6 lines: cause and what the fix changes, in user-visible terms.>

Setup:
  <tables, sizes, parameters, why the sizes clear the thresholds; the oracle values and why they
  are fixed by the data>

Test:
  1. Positive control: <the trace or statistic that proves the tested path is reached>.
  2. <check>
  3. <check>
  N. No new core and no assertion line in the server error log; cub_server pid unchanged.
DESCRIPTION

. $init_path/init.sh
init test

dbname=db<N>
csql_timeout=300

# --- Cleanup helpers (used by every exit path) ----------------------------
do_cleanup()
{
    cubrid server stop ${dbname} > /dev/null 2>&1
    cubrid deletedb ${dbname} > /dev/null 2>&1
    rm -rf ${dbname}
    rm -f *.sql *.log *.out *_session_*.err csql.err
}

abort_test()
{
    write_nok "$1"
    do_cleanup
    finish
    exit 1
}

# --- Setup phase ----------------------------------------------------------
change_db_parameter "<param>=<value>"
cubrid server stop ${dbname} > /dev/null 2>&1
cubrid deletedb ${dbname} > /dev/null 2>&1
rm -rf ${dbname}
mkdir -p ${dbname}
cd ${dbname}
# 20M is the rulebook default; a larger size only when the data needs it, with the reason in Setup:
cubrid_createdb ${dbname} --db-volume-size=20M --log-volume-size=20M > ../createdb.log 2>&1
createdb_rc=$?
cd ..
[ "${createdb_rc}" -eq 0 ] || abort_test "createdb.log"
cubrid server start ${dbname} > server_start.log 2>&1 || abort_test "server_start.log"

csql -u dba ${dbname} > load.log 2>&1 <<'EOF'
create table n1 (i int);
insert into n1 values (0),(1),(2),(3),(4),(5),(6),(7),(8),(9);
...
update statistics on all classes with fullscan;
commit;
select count(*) from t;
EOF
grep -q "ERROR" load.log && abort_test "load.log"
loaded=$(grep -cE "^[[:space:]]*<expected rows>[[:space:]]*$" load.log)
[ "${loaded:-0}" -eq 1 ] || abort_test "dataset not loaded"

# --- Case 1: positive control ----------------------------------------------
...
if [ -n "${workers}" ] && [ "${workers}" -ge 2 ]; then
    write_ok "<label>"
else
    cat trace.log
    abort_test "<label> : expected ..., got workers='${workers}' (cores=$(nproc))"
fi

# --- Crash detectors ---------------------------------------------------------
server_pid_before=$(cubrid server status 2>&1 | grep "Server ${dbname} " | sed -e 's/.*pid //' -e 's/[^0-9]//g')
core_before=$(find $init_path $CUBRID ${cur_path} -name "core*" -type f 2>/dev/null | wc -l)
cat $CUBRID/log/server/${dbname}_2*.err > err_before.log 2>/dev/null

# --- Cases 2..N-1 ------------------------------------------------------------
...

# --- Case N: no restart, no core, no assertion --------------------------------
...

# --- Cleanup phase ---------------------------------------------------------
do_cleanup
finish
```

## Rules

1. **Header**: the `:<<'DESCRIPTION'` block on line 2, right under `#!/bin/bash`, with `Issue:` /
   `Setup:` / `Test:` (numbered, one line per `write_ok`/`write_nok` check), at most 40 lines,
   user-visible terms. No workspace numbers.
2. **Placement**: judge.md §2 table; the directory name equals the script name. One TC per issue;
   split into `cbrd_<N>_<keyword>` only under the rulebook's three conditions (other settings or a
   restart, the TC timeout, or a NOK that cannot name its scenario).
3. **Own database** (`db<N>`), created inside its own directory at `--db-volume-size=20M
   --log-volume-size=20M` unless the data needs more (say why in `Setup:`);
   `cubrid server stop/deletedb` **before** createdb too (a crashed earlier run leaves it registered).
4. **Parameters** only through `change_db_parameter "k=v"` (restored by `finish`); never edit
   `cubrid.conf` by hand. Add `change_db_parameter "call_stack_dump_on_error=no"` when the case
   provokes errors on purpose. Pin every parameter the tested path depends on: installs from
   `just build` carry the campaign conf (`double_write_buffer_size=0`, `log_max_archives=0`,
   `log_buffer_size=256M`), archive installs and CI carry the stock one. A case that depends on page
   flushing sets `double_write_buffer_size=2097152` (bytes only; `2M` makes createdb fail with
   "Value type does not match parameter type").
5. **First check is a positive control**: prove the tested path is reached (`parallel workers: N`
   with N ≥ 2, the new statistic name, the trace token). If it fails, take the abort path
   (`abort_test` with the measured values plus `nproc` and the relevant parameter: `write_nok`,
   cleanup, `finish`, `exit 1`) — the remaining checks would pass vacuously otherwise (cbrd_27484
   case 1, cbrd_27486 case 1).
6. **Oracle values are fixed by the data** (`4 x 600 x 8 = 19200`) and written in `Setup:`; never
   measured once and pasted.
7. **Helpers**: every variable in a function is `local`; never name anything `result_file`,
   `case_name`, `case_no`, `cur_path`, `pids`, `run_mode`, `answer_no`. Reuse of `pids` is only
   safe if the case never calls `xkill` between setting and reading it.
8. **One write per result line**: `echo "${count:-NO_RESULT}"`, `awk '... {print $1; exit}'`; never
   `printf` + `echo` pairs. Background sessions: `run_session ... > out_N.log 2> session_N.err &`.
   `write_ok`/`write_nok` echo their message unquoted (`echo ... $1 >> $result_file`), so the message
   carries no glob character (`*`, `?`, `[`): write the SQL in words ("(bind + 1) times n").
   CBRD-27215 (2026-10-15, caught by the first CTP run): wrote `write_ok "(? + 1) * n on every
   execution"` → the `*` expanded into the case directory listing in every `.result` line → words only.
9. **Grep anchors**: counts with `^[[:space:]]*19200[[:space:]]*$`; literal dots escaped
   (`grep -o "0\.00"` — an unescaped `0.00` matched pid 40000, cbrd_26123 2026-10-07); pids compared
   as whole strings, never substrings of `ps` lines.
10. **Bounded waiting**: `timeout ${csql_timeout} csql ...` on every csql in a loop; wait for a state
    with the rulebook's `wait_until <whole seconds> eval '<condition>'` (CTP init.sh since testtools
    af69c00, 2026-10-19), never a counter loop around `sleep 1` and never a fixed `sleep 60` as the only
    synchronization.
    A utility that must run beside a statement (`cubrid statdump -i`) runs as
    `timeout -s INT <bound> cubrid ... &`, its pid saved with `$!`, and stops with `kill -INT` on that
    pid, with a comment saying why (our one exception to the rulebook's `xkill_pid`, which is `kill -9`
    and loses statdump's last output): `cubrid` (and CTP's
    wrapper) only wait for their cub_admin child, so a signal to their pid never reaches it, while
    `timeout` passes it to its whole process group. "The statement is running" is an event, not a
    delay: `wait_until` on `cubrid tranlist -f <db>` showing its text. Such a check needs a statement that runs for many
    seconds, and run time counts: the user dropped CBRD-27604's statdump-during-a-statement checks
    (three ~1-minute statements took the case from 18 s to 2-3.5 min) and put the behavior in the JIRA
    spec instead (2026-10-14).
11. **Concurrency** only when the defect needs it (pool/LIFO races, lock timeouts): N sessions × M
    iterations, each iteration's verdict one line, aggregated by `check_results` as in cbrd_27484.
12. **Crash detectors** around the risky phase: server pid before/after, core count delta,
    `grep -ic assertion` on the error-log delta. These are their own numbered checks.
    **Read a pid (or check up/down) from `cubrid server status` with `grep "Server ${dbname} "`** —
    the full server name and its trailing space. A bare `grep "${dbname}"` also matches a database
    whose name starts with `${dbname}` (db27645 and the companion case's db27645iv): the snapshot then
    holds two pids, and when the other case stops its server the check reports a restart that never
    happened (CBRD-27645 TC review, 2026-10-16). In CTP containers
    an optdebug assert's text never reaches `$CUBRID/log/server/<db>_*.err` (stderr is lost).
    **Count cores where CTP itself looks**: `find $init_path $CUBRID ${cur_path} -name "core*" -type f`,
    the set CTP's `do_check_more_errors` (shell/init_path/shell_utils.sh) searches after every case
    before it writes "NOK found core file". Never a host directory (`/data/core`) and never
    `dirname` of `/proc/sys/kernel/core_pattern`: where a CI machine drops its cores is unknown, and a
    directory named `core` matched by `-name "core"` without `-type f` counts itself (user, 2026-10-12,
    CBRD-27604; cbrd_27599 carried that form and was fixed on tc/pr-8137; the merged cbrd_27484 keeps it,
    a fix PR for a merged TC was closed by the user).
    A local run checks cores by our procedure, not by this find (verify.md §3): the local ctp-run puts
    cores in the container's `/data/core`, outside that set (user, 2026-10-12).
    A TC that reproduces a crash judges the new core files and the server `.err` right after the
    reproduction step, then removes exactly the core files that check found (by name, never a
    `core.*` glob over `$CUBRID`), so the closing `cubrid deletedb` does not report the same crash
    again; one that writes `FATAL ERROR` on purpose sets `export SKIP_CHECK_FATAL_ERROR=TRUE` after
    `init test` (rulebook).
13. **Verdict count**: lines in `<case>.result` = number of `write_ok`/`write_nok` calls that ran.
    Check it after the first CTP run (`CTP_KEEP_COPIES=1`).
14. **Every exit path** reaches `do_cleanup` then `finish`: an abort path ends `write_nok; do_cleanup;
    finish; exit 1`, and the normal path ends `do_cleanup; finish` with no `exit` after it.
    `rm -f` lists the case's own artifacts only.
15. **Numbers are judged with computed invariants** through `write_ok`/`write_nok` (the oracle fixed by
    the data, rule 6); a result of a line or two with an anchored grep. Multi-row output may use an
    answer file as the rulebook's "Answer files" section says: normalize with `format_csql_output` /
    `format_query_plan` / `format_path_output`, compare with `compare_result_between_files`, answer
    committed in `cases/`, one answer file for identical outputs (user, 2026-10-30).
16. No hardcoded paths (`/tmp`, `/home/...`); `$CUBRID`, `$init_path`, cwd only.
17. **Trace counters** (readkeys, rows, lookup rows, cache hits): compare the parallel run with its
    `NO_PARALLEL_SCAN` twin **and** with the count the data fixes. Never use fetch or ioread: they differ
    between parallel and serial runs even when both are right. Per-worker caches (SUBQUERY_CACHE,
    MEMOIZE) are fixed only as hit+miss. Worker XASL stats merge only when the gather is buildvalue or a
    mergeable list (cbrd_27184). Before CBRD-27184 a correlated subquery attached at chain depth k was
    counted k times, so checks at different depths show different multipliers. A partitioned inner
    table multiplies the outer nodes' counters by the partition count even in a serial run: compare only
    the partitioned node and its PARTITION lines. An aggregate with ROWNUM stays a row-by-row gather on
    every point, which makes it a stable control. FUNC `calls` are not always one per row: an aggregate
    argument is evaluated once more on both paths (domain resolution: 537 calls for 536 rows), and a
    declared select-list function under a mergeable-list gather reports one more call in parallel than
    serially. Judge them as "at least the row count" or "equal to the serial twin" (CBRD-27299).
18. **Old comparison points**: trees before 7355bcec7 (CBRD-27326, 2026-09-09) default
    `parallel_scan_page_threshold` to 2048 pages, so a 200k-row table is not scanned in parallel there;
    lower it with `change_db_parameter` when the pre point is older. The gather of plain LIMIT/ROWNUM
    queries changed from row by row to a mergeable list at e4a79972c (CBRD-27135); check the trace on the
    pre and dev installs before picking the query (cbrd_27217). Without `test_mode`, develop opens a
    parallel **index** scan only when the b-tree's user pages reach `parallel_scan_page_threshold` (256
    since 7355bcec7): a 110-page index stays serial on develop but runs in parallel on May-2026 points.
    Set `parallel_scan_page_threshold=16` in shell cases and probes of index scans (CBRD-26722).
19. **Margins** (user, 2026-10-08): a check whose outcome rests on an estimate (statistics, histograms,
    selectivity) keeps it ≥5x above or ≤1/5 of the threshold, and a page or row count ≥3x its threshold.
    Histograms and statistics come from samples and heap placement differs between builds and runs, so a
    value near a threshold flips. Write the margin into `Setup:`.
20. **Checks of one shape share one helper** (trace path check, warm-up, loop, measured delta), but each
    check keeps its own trace guard, so a plan change cannot make it pass without testing anything; a
    missing measurement (no memmon output) is a failure, never 0 (cbrd_27217 `loop_verdict`).
    A check that passes on a value near 0 (a statdump delta "< 1/5") passes just as well when its
    session ran nothing: prove the workload ran (its rows printed) in the same guard.
    CBRD-27604 (2026-10-14, caught by Codex on private-ex #4399): check 5 read only the statdump delta
    around 4 untraced scans → a csql timeout without an ERROR line would have passed → the 4 scans must
    print 200000.
21. A loop whose statements must fail on every execution runs `csql -e` (`--error-continue`); without it
    csql exits at the first error.
22. The b-tree user-page count the server checks is one more than `SHOW INDEX CAPACITY`'s
    `Num_total_page` for a non-empty index (3→4, 2→3); a page-count check asserts a range, not an
    exact value (CBRD-27100).
23. **No time checks** (user, 2026-10-12, CBRD-27604): never compare a measured duration with
    anything — trace `time:` / `fetch_time:`, a `SLEEP()` length, wall time from `SYS_DATETIME` or
    `date`, csql's "(N sec)", a ratio of two times, an expected timeout. CI machines swing between idle
    and heavily loaded, so such a bound is flaky however wide it looks. cbrd_27604 dropped "trace time
    ≤ wall × 1.1 + 100 ms and ≥ (wall − 300 ms) / 2, wall from the same session's SYS_DATETIME
    difference so csql start-up is excluded", written to catch CBRD-26512's 3–4x over-report. A clock or
    timing change gets no check under `shell/`; it becomes a `shell_perf` TC (rule 25) when a switch runs
    the old path, else the "성능 TC 필요" JIRA comment (pr-and-jira.md §5 kind 1).
24. **A check that needs the cached plan reused** runs the same text without `recompile` and proves the
    reuse with `cubrid plandump` (never `-d`, which drops the cache): the global `Recompiles:` count and the
    entry's `time_stored` must not change between the runs. A recompile keeps `time_stored`; a new entry
    gets its own. The entry's `reference count` is no proof, because parallel workers raise it too. The
    `recompile` hint is not in the plan hash text, so a `recompile` copy of the same query recompiles that
    entry; use it as the negative control (CBRD-27100 check 5).
25. **`shell_perf` TC** (judge.md R4 with a twin; user, 2026-10-30): same form as a shell TC, under
    `shell_perf/` at the path the issue type gives (`shell_perf/_06_issues/_26_2h/cbrd_<N>/` or
    `shell_perf/_40_guava/cbrd_<N>/`). Model: `shell_perf/_40_guava/cbrd_26678/cases/cbrd_26678.sh`.
    - Judge a **ratio of twins in the same run**: the same statement with the switch that runs the old
      path (hint or parameter) and without it, summed over a few repetitions after a warm-up. Never an
      absolute time, never a baseline from another run or another build.
    - The threshold sits at least 15% below the lowest ratio measured over at least 4 runs; a comment
      above it names the build, the machine (cores), the measured ratios and the margin. Ratios
      measured on this shared host only show the direction; they do not set the threshold.
    - A machine below the core count the ratio needs gets `write_nok` naming the count, never a quiet pass.
    - Next to the time check, a state check proves the new path ran (a trace token, a worker count, the
      result rows), so the TC cannot pass on time alone.
    - Expected verdicts: fix OK, pre NOK by the ratio (verify.md §5). Run with `just ctp shell_perf <dir>`.

## Checklist before saving

- `bash -n <file>` → no output
- `/usr/bin/grep -nE '^\s*(result_file|case_name|case_no|cur_path|run_mode|answer_no)=' <file>` → nothing
- `/usr/bin/grep -nE 'write_(ok|nok) "[^"]*[*?[]' <file>` → nothing (rule 8)
- `/usr/bin/grep -c 'write_ok\|write_nok' <file>` equals the `Test:` numbered lines (+ the abort paths)
- every function body: variables declared `local`
- the rulebook's `writing-rules.md` walked rule by rule against the file; a break is fixed or is one of
  "Where we differ" above
- line 1 `#!/bin/bash`, line 2 opens the DESCRIPTION block; every heredoc delimiter quoted unless its body expands a variable
- `/usr/bin/grep -nE '\[ +[`$]\(?|\[ +`' <file>` → nothing (a command substitution goes into a variable before `[ ]`)
- no `sleep` without a reason comment; every wait is `wait_until <whole seconds>`
- `finish` is the last command of the file and of every abort path; an abort path ends `exit 1` after `finish`; no `exit` at the normal end
- every background `&` has a matching `wait`; every csql in a loop has `timeout`
- the positive control is check 1 and exits the case on failure
- DESCRIPTION ≤ 40 lines, no workspace numbers
- no check reads a duration (`time:`, `fetch_time:`, `SYS_DATETIME`, `date`, `SLEEP`) — rule 23
- cores counted only with `find $init_path $CUBRID ${cur_path} -name "core*" -type f` — rule 12
- every `cubrid server status` lookup greps `"Server ${dbname} "` (full name + space) — rule 12
