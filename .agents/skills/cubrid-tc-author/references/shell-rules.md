# Shell testcase rules (CTP `shell` suite, cubrid-testcases-private-ex)

Work in the TC worktree from [pr-and-jira.md](pr-and-jira.md) §1 (`~/dev/cubrid-tc-ex-worktree/cbrd_<N>`
in merged mode). Model files on private-ex develop: `shell/_06_issues/_26_2h/cbrd_27484/cases/cbrd_27484.sh`
(concurrent sessions, pid/core/assert detectors) and `shell/_06_issues/_26_2h/cbrd_27486/cases/cbrd_27486.sh`
(parameter + per-session observation). CTP's own guide: `~/cubrid-testtools/doc/shell_guide.md` §5.

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
    exit 0
}

# --- Setup phase ----------------------------------------------------------
change_db_parameter "<param>=<value>"
cubrid server stop ${dbname} > /dev/null 2>&1
cubrid deletedb ${dbname} > /dev/null 2>&1
rm -rf ${dbname}
mkdir -p ${dbname}
cd ${dbname}
cubrid_createdb ${dbname} --db-volume-size=128M --log-volume-size=64M > ../createdb.log 2>&1
createdb_rc=$?
cd ..
[ ${createdb_rc} -eq 0 ] || abort_test "createdb.log"
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
[ `grep -cE "^[[:space:]]*<expected rows>[[:space:]]*$" load.log` -eq 1 ] || abort_test "dataset not loaded"

# --- Case 1: positive control ----------------------------------------------
...
if [ -n "${workers}" ] && [ "${workers}" -ge 2 ]; then
    write_ok "<label>"
else
    write_nok "<label> : expected ..., got workers='${workers}' (cores=`nproc`)"
    cat trace.log
    do_cleanup
    finish
    exit 0
fi

# --- Crash detectors ---------------------------------------------------------
server_pid_before=`cubrid server status 2>&1 | grep "${dbname}" | sed -e 's/.*pid //' -e 's/[^0-9]//g'`
core_before=`find $CUBRID ./ -maxdepth 3 \( -name "core" -o -name "core.*" \) 2>/dev/null | sort -u | wc -l`
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

1. **Header**: the `:<<'DESCRIPTION'` block with `Issue:` / `Setup:` / `Test:` (numbered, one line
   per `write_ok`/`write_nok` check), at most 40 lines, user-visible terms. No workspace numbers.
2. **Placement**: judge.md §2 table; the directory name equals the script name.
3. **Own database** (`db<N>`), created inside its own directory with explicit volume sizes;
   `cubrid server stop/deletedb` **before** createdb too (a crashed earlier run leaves it registered).
4. **Parameters** only through `change_db_parameter "k=v"` (restored by `finish`); never edit
   `cubrid.conf` by hand. Add `change_db_parameter "call_stack_dump_on_error=no"` when the case
   provokes errors on purpose. Pin every parameter the tested path depends on: installs from
   `just build` carry the campaign conf (`double_write_buffer_size=0`, `log_max_archives=0`,
   `log_buffer_size=256M`), archive installs and CI carry the stock one. A case that depends on page
   flushing sets `double_write_buffer_size=2097152` (bytes only; `2M` makes createdb fail with
   "Value type does not match parameter type").
5. **First check is a positive control**: prove the tested path is reached (`parallel workers: N`
   with N ≥ 2, the new statistic name, the trace token). If it fails, `write_nok` with the measured
   values plus `nproc` and the relevant parameter, then cleanup and `exit 0` — the remaining checks
   would pass vacuously otherwise (cbrd_27484 case 1, cbrd_27486 case 1).
6. **Oracle values are fixed by the data** (`4 x 600 x 8 = 19200`) and written in `Setup:`; never
   measured once and pasted.
7. **Helpers**: every variable in a function is `local`; never name anything `result_file`,
   `case_name`, `case_no`, `cur_path`, `pids`, `run_mode`, `answer_no`. Reuse of `pids` is only
   safe if the case never calls `xkill` between setting and reading it.
8. **One write per result line**: `echo "${count:-NO_RESULT}"`, `awk '... {print $1; exit}'`; never
   `printf` + `echo` pairs. Background sessions: `run_session ... > out_N.log 2> session_N.err &`.
9. **Grep anchors**: counts with `^[[:space:]]*19200[[:space:]]*$`; literal dots escaped
   (`grep -o "0\.00"` — an unescaped `0.00` matched pid 40000, cbrd_26123 2026-10-07); pids compared
   as whole strings, never substrings of `ps` lines.
10. **Bounded waiting**: `timeout ${csql_timeout} csql ...` on every csql in a loop; poll with a counter
    (`while [ $i -le 30 ]; do ...; sleep 1; done`), never a fixed `sleep 60` as the only synchronization.
11. **Concurrency** only when the defect needs it (pool/LIFO races, lock timeouts): N sessions × M
    iterations, each iteration's verdict one line, aggregated by `check_results` as in cbrd_27484.
12. **Crash detectors** around the risky phase: server pid before/after, core count delta
    (`$CUBRID`, `./`, `/data/core`), `grep -ic assertion` on the error-log delta. These are their own
    numbered checks. In CTP containers an optdebug assert's text never reaches
    `$CUBRID/log/server/<db>_*.err` (stderr is lost), so the core-count delta is the detector that
    works (CBRD-27293: 3 server cores, 0 assertion lines).
13. **Verdict count**: lines in `<case>.result` = number of `write_ok`/`write_nok` calls that ran.
    Check it after the first CTP run (`CTP_KEEP_COPIES=1`).
14. **Every exit path** reaches `do_cleanup` then `finish`; the normal path ends `do_cleanup; finish`.
    `rm -f` lists the case's own artifacts only.
15. No `.answer` files and no `compare_result_between_files` for new cases: judge with computed
    invariants through `write_ok`/`write_nok` (both model files; QA merged them).
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
21. A loop whose statements must fail on every execution runs `csql -e` (`--error-continue`); without it
    csql exits at the first error.
22. The b-tree user-page count the server checks is one more than `SHOW INDEX CAPACITY`'s
    `Num_total_page` for a non-empty index (3→4, 2→3); a page-count check asserts a range, not an
    exact value (CBRD-27100).

## Checklist before saving

- `bash -n <file>` → no output
- `/usr/bin/grep -nE '^\s*(result_file|case_name|case_no|cur_path|run_mode|answer_no)=' <file>` → nothing
- `/usr/bin/grep -c 'write_ok\|write_nok' <file>` equals the `Test:` numbered lines (+ the abort paths)
- every function body: variables declared `local`
- `finish` is the last command of the file and of every `exit` path; `exit 0` after `finish`, never before
- every background `&` has a matching `wait`; every csql in a loop has `timeout`
- the positive control is check 1 and exits the case on failure
- DESCRIPTION ≤ 40 lines, no workspace numbers
