# Verify on three optdebug builds

Everything here is **runtime work**: builds, CTP, servers. Delegate it to one Workflow worker
(`agent(prompt, { model: 'sonnet', effort: 'xhigh' })`) whose prompt contains §0 verbatim plus the
exact commands of §1–§4 with the placeholders filled. The lead reads the worker's `results.md` and
judges §5–§6. Only optdebug is used — release hides asserts and once produced four wrong diagnoses
(2026-09-19/20); QA generates answers on release, we do not.

## §0 Text to paste verbatim into every worker prompt

```
Delegation execution contract:
- Finite gate work (incremental build, unit, smoke — steps that each finish within ~10 min) runs as FOREGROUND blocking commands, chained in one continuous turn. run_in_background/nohup/monitors are FORBIDDEN for such steps. Only a full fresh build may go background, and then the SAME turn must bounded-poll its completion marker (`timeout ... until grep ...`) — never end a turn "waiting for a notification".
- The worker must deliver its final report in the same turn the work finishes, BEFORE going idle.

CTP execution rule (every suite):
- Every CTP run, whole or subset, goes through `just ctp <sql|medium|shell|ha_shell> [DIRS...]` (containers) or `just ctp-rerun <CI URL>`. Never `ctp.sh` on the host, never resurrect a host-side recipe. CTP's teardown runs `pkill cub` and `kill -9` over `ps -u $USER`.
- The testcase ref is never implicit: pass `PR=<n>` or `TC_REF=<ref>`, or `CTP_ARGS="--testcases-as-is --testcases <dir>"` for an unpushed worktree.
- `medium` and `ha_shell` are never sharded.

House rules: never write to /tmp; scratch goes under /home/cubrid/dev/workspace/.git_ignored_dir/scratch/tc-author/CBRD-<N>/. Run every command from /home/cubrid/dev/workspace. Report facts only; never fake a verdict. Match cores to your own server pids (core.<thread>.<pid>), not by timestamp.
```

## §1 The three builds

| point | merged mode | open mode |
|---|---|---|
| **pre** (직전) | `git -C ~/dev/cubrid-worktree/develop rev-parse <merge_commit>^` | `git -C ~/dev/cubrid-worktree/develop merge-base origin/develop <head_sha>` |
| **fix** (직후) | `<merge_commit>` | `<head_sha>` — build the PR head locally |
| **dev** (최신) | `git -C ~/dev/cubrid-worktree/develop fetch -q origin develop && git rev-parse origin/develop` | same |

Record all three **full** shas in `results.md`. Two issues may share a point (CBRD-27217 fix =
CBRD-27184 pre, `4c59c568f`); reuse an install that already exists under `~/optdebug/`.

**Archive first** (gha-ci keeps develop optdebug builds by full sha):

```bash
SHA=<full sha>; URL=http://192.168.1.48:30080/builds/develop/$SHA/debug/CUBRID.tar.gz
curl -sfI "$URL" | head -1            # HTTP/1.1 200 OK → archive exists
D=~/optdebug/CUBRID-cbrd<N>-<pre|fix|dev>; mkdir -p "$D"
curl -sf "$URL" | tar -xz -C "$D" --strip-components=1   # tarball root is CUBRID/
ls "$D/bin/cub_server" "$D/jdbc/cubrid_jdbc.jar"       # both must exist; no jar = CTP refuses sql
```

**Local build when the archive has no such sha** (sequential, never two builds at once; ccache at
`/home/cubrid/.ccache` makes a repeat tree fast):

```bash
WT=~/dev/cubrid-worktree/cbrd<N>-<pre|fix>
git -C ~/dev/cubrid-worktree/develop worktree add "$WT" <sha>        # open mode fix: the PR branch instead
cd /home/cubrid/dev/workspace
INSTALL_PREFIX=~/optdebug/CUBRID-cbrd<N>-<pre|fix> WORKSPACE="$WT" just build optdebug cbrd<N>-<pre|fix> \
  > .git_ignored_dir/scratch/tc-author/CBRD-<N>/build-<pre|fix>.log 2>&1
tail -3 .git_ignored_dir/scratch/tc-author/CBRD-<N>/build-<pre|fix>.log   # ends with "installed optdebug (...) -> <dir>"
```

`INSTALL_PREFIX` keeps `~/CUBRID` untouched. A full build may run in the background only with a
bounded poll in the same turn (§0). `just build` applies the campaign conf; the CTP runner pins its
own server parameters, so the install's conf does not matter for CTP.

**A sha older than 2026-07-15 has no `optdebug` preset** (`CMake Error: No such preset ... "optdebug"`).
The mode came with dab6cf7c3 (CBRD-27049). Port only its build files into the worktree, identically
on pre and fix, before `just build` (CBRD-26930, 2026-10-08: applied cleanly on 2026-06-25 trees):

```bash
git -C ~/dev/cubrid-worktree/develop show dab6cf7c3 -- CMakePresets.json CMakeLists.txt > "$R/optdebug-port.patch"
git -C "$WT" apply --3way "$R/optdebug-port.patch"
git -C "$WT" diff HEAD --stat -- src                      # must print nothing: engine sources unchanged
```

State the port in the PR body's verification section.

## §2 Generate the answer on the fix build (sql only)

```bash
TC=~/dev/cubrid-tc-worktree/cbrd_<N>            # or the tc/pr-<PR> worktree
DIR=<scenario-relative case dir, e.g. _36_guava/cbrd_<N> or _13_issues/_26_2h>
RUN=$DIR                                        # _13_issues: RUN=$DIR/cases/cbrd_<N>.sql (see below)
echo PLACEHOLDER > "$TC/sql/$DIR/answers/cbrd_<N>.answer"      # no answer = case skipped but PASSED
cd /home/cubrid/dev/workspace
CTP_ARGS="--testcases-as-is --testcases $TC" CTP_KEEP_COPIES=1 BUILD=~/optdebug/CUBRID-cbrd<N>-fix \
  just ctp sql $RUN 2>&1 | tee .git_ignored_dir/scratch/tc-author/CBRD-<N>/gen.log
```

The runner prints its run directory (`/home/cubrid/ctp-run-out/<tooling-repo>/sql-<timestamp>-<pid>`).
The output is `<run dir>/shard_0/testcases/sql/$DIR/cases/cbrd_<N>.result`. With the placeholder the
case is NOK, which is expected here. Then:

1. Block count check: `grep -c '^=====' <result>` must equal the number of statements
   (`grep -c ';[[:space:]]*$' <case>.sql` minus header/comment lines, which the checklist already
   made zero) — a mismatch means a statement did not run or a header `;` leaked in.
2. Read **every** block against the case's intent: twin blocks identical, the trace token present where
   the header promises it, no `Error:` block except the designed error cases, no `-493`, no `-1071`.
3. For `_13_issues` cases only: the `.result` of a flat `cases/` dir sits in the same run dir path.
   Pass the case file as `RUN`, never the flat dir: the runner then selects exactly that file. The flat
   dir holds other issues' cases, and one fixed after this issue's fix can core the pre or fix build
   and poison this case (CBRD-27327, 2026-10-08).
4. `cp <result> "$TC/sql/$DIR/answers/cbrd_<N>.answer"`.

Shell has no answer: run `CTP_ARGS="--testcases-as-is --testcases $TCEX" CTP_KEEP_COPIES=1 BUILD=<fix> just ctp shell <dir>`
and read `<run dir>/shard_0/testcases/shell/<dir>/cases/<name>.result`: one line per check, all `OK`.
The case's own logs are gone after `do_cleanup`; the measured values are in the xtrace at
`<run dir>/shard_0/CTP/result/shell/current_runtime_logs/test_local.log` (`+ workers=2` lines).
A pre build that is expected to crash runs with `NO_ABORT_ON_CORE=1`, otherwise the runner stops the
shard at the first core and the case writes no `.result` (CBRD-26930).
CTP reruns a failed shell case once inside the same run: `test_local.log` holds both executions
(`TEST START` blocks) but the `.result` holds only the last, and the runner still fails the run on
cores. For a probabilistic case, read every execution (CBRD-27293). A multi-round crash probe through
CTP leaves two cores per hit (cub_server and cub_admin): with `NO_ABORT_ON_CORE=1` also raise
`CTP_CRASH_LOOP_CORES` and `CTP_MAX_SHARD_CORES`, or the watchdog stops the shard.

## §3 Run the three builds in parallel (one foreground command)

```bash
cd /home/cubrid/dev/workspace
R=.git_ignored_dir/scratch/tc-author/CBRD-<N>
for p in pre fix dev; do
  CTP_ARGS="--testcases-as-is --testcases $TC" CTP_KEEP_COPIES=1 BUILD=~/optdebug/CUBRID-cbrd<N>-$p \
    just ctp sql $RUN > "$R/run-$p.log" 2>&1 &
done; wait
for p in pre fix dev; do echo "== $p"; grep -E 'RESULT:|\[NOK\]|\[OK\]|core' "$R/run-$p.log" | head -20; done
```

Containers are isolated, so three runs at once are fine (≈45 s each for a one-case dir, most of it
container start). Each run has `provenance.txt` naming the install; cite it in `results.md`.

## §4 Determinism on the fix build

Run §3's command with `for p in fix fix fix` (log names `run-fix-1..3`). All three must be `OK`.
A diff between them = nondeterministic output (heap order without `order by`, timing in a trace,
a threshold at the edge) → back to Step 3; never widen the answer. A case whose plan or parallel
decision rests on an estimate or a page count also runs 3 times on pre and dev (sampling and heap
placement move between runs); any flip → back to Step 3 with larger margins (sql-rules, shell-rules 19).
Points before 58aa0eddf (CBRD-27287, 2026-10-07) can drop the CAS connection when one statement calls an
undeclared stored function tens of thousands of times ("pending transmission reached IOV_MAX",
`change_exec_rights` -2). CQT reconnects and reruns, so the rows still match but later `show trace`
output is null. Cap undeclared calls near 1,000 per statement with a cheap leading filter (simple
comparisons are evaluated first); read a null trace by grepping the server log for `IOV_MAX` (CBRD-27299).

## §5 Expected verdicts — fill the table and compare

`results.md`:

```markdown
| build | sha | case | verdict | cores | expected | matches? |
| pre | <sha> | cbrd_<N> | NOK | 0 | NOK | yes |
| fix | <sha> | cbrd_<N> | OK ×3 | 0 | OK | yes |
| dev | <sha> | cbrd_<N> | OK | 0 | OK | yes |
```

A behavior whose setup statement exists only on develop (its syntax changed after the fix) gets a
develop-only file `cbrd_<N>_<topic>.sql`: its pre and post rows read "해당 없음 (<문법>이 수정 뒤 도입,
<commit>)", dev is OK ×3, and the PR cites the probe that showed the same behavior on the post point with
the old syntax (user, 2026-10-08, CBRD-27100 histograms: ANALYZE TABLE ... UPDATE HISTOGRAM → UPDATE
STATISTICS, 532ce4b6d). Run pre and post with the common file's path, not the directory (the directory
would run the develop-only file there and fail). The surest post-point proof is an old-syntax copy of
the file run on post, compared block by block with the develop answer.

An R5 issue that also specifies result changes keeps two files: `cbrd_<N>.sql` (correctness, pre OK)
and `cbrd_<N>_spec_change.sql` (the specified changes, pre NOK by design), so each row of the table
has one expectation (CBRD-27181).

| verdict (judge.md) | pre | fix | dev (merged mode) | dev (open mode) |
|---|---|---|---|---|
| R1 / R2 / R3 | **NOK** | OK | OK | NOK, same diff as pre (fix not merged yet) |
| R5 correctness TC | OK (results identical); **NOK** when the data triggers the defect deterministically (CBRD-26799) | OK | OK | OK |

Deviations and what they mean:
- **pre OK where NOK expected** → the case does not reach the fixed path. Return to Step 3 (data
  size, hint, missing twin). After **two** authoring rounds still OK on pre → **STOP**: report; the
  issue may be R6 (no TC possible) and the user decides.
- **fix NOK** → the case or the answer is wrong (reread the diff of `.result` vs `.answer`), or a
  develop assert fired (a core: read `console.log` for `Assertion`; a server abort poisons every
  later statement with -581/-669/-677 — judge only the statements before it).
- **pre run by directory after an abort**: the next file's setup fails with -581, so it runs over the
  previous file's tables and its traces are null (CBRD-27299: the subquery file summed the hash-join
  file's `t_mid`). Read pre's per-case behavior from per-file runs or standalone probes.
- **dev differs from fix** → §6.

## §6 Latest-develop regression

A `dev` run that shows a core, an `Assertion` line, or a result diff **while pre and fix behave as
expected** is a develop regression, not a TC defect. Procedure:
1. Rerun `dev` alone once (flake check: DST windows, PL socket flake, placement leaks are known
   false alarms — see `docs/ci-flaky-cases.md`).
2. If it repeats: keep that run dir, copy `console.log`, the `.result` diff and `provenance.txt` into
   `<rundir>/regression/`; for a core, have the worker take a backtrace with gdb against the extracted
   install (`gdb <install>/bin/cub_server <core> -batch -ex bt`) and save it there.
3. Do **not** open the PR. Go to Step 7 with the regression comment (pr-and-jira.md §5 kind 3).
   The wayfinder ticket stays open and assigned; note "회귀 대기" in its body.

## §6b A result change the fix itself made

When a shape gives a different result on post than on pre and dev agrees with post, but the issue
promised unchanged results (CBRD-27041: a page-copy scan reads stale values of rows its own statement
changed later on the same page), it is neither an R5 pass nor a §6 regression. **STOP** and report.
The user's answer for CBRD-27041 (2026-10-08), the default unless told otherwise: keep the shape out
of the TC, push the TC branch to the fork without a PR, file a workspace issue for the result change,
post one JIRA comment on the issue that describes the change (repro SQL, three-point table) and says the
TC PR follows once it is resolved, linking the fork branch; the wayfinder ticket stays open as 회귀 대기.
Two kinds, decided by whether the TC needs the changed shape:
- **The TC must pin the changed shape** (CBRD-27041's page-copy result; CBRD-27071's two inputs) → the
  default above: hold the PR on the fork, the ticket waits as 회귀 대기.
- **The changed shape is a defect outside an otherwise complete TC** (CBRD-26722: SELECT ... FOR UPDATE
  under a parallel index scan takes no row locks; the TC never needed that shape) → open the PR now with
  the shape excluded, and STOP only to let the user decide how the defect is filed (2026-10-09: JIRA
  CBRD-27593 with a Regress link to the feature, title picked by the user). The PR body names the JIRA
  key where it lists what the TC leaves out; the check is added after that issue is fixed.

## §6a Probing an install before writing a shell case

Try the planned checks on the pre and dev installs before writing the case:
- **Through CTP**: copy a throwaway script into your TC worktree, run it with §3's command, delete it.
  A bare scratch tree is refused (no `shell/config/...excluded_list`).
- **Host server**: build a symlink tree over the install with private copies of `conf/`, `log/`, `tmp/`,
  `var/` and `databases/`, and give it its own port. Point `CUBRID_TMP` at a short symlink: the socket
  path must fit in 107 bytes, and the scratch path gives 114. Stop the server with the
  cubrid-server-control wrapper, and its cub_master with SIGTERM after checking that the CUBRID value in
  `/proc/<pid>/environ` is your tree. Never `cubrid service stop` or pkill (CBRD-27184).
- **Many candidate shapes**: one throwaway probe script with a `probe <tag> <query>` helper measures
  every shape's trace and counters on all three points in one parallel CTP run (about 25 s a point;
  CBRD-27217 `probe3/`). A throwaway dir inside the TC worktree (`sql/<dir>_probe/cases` + a placeholder
  answer) runs alone through `just ctp sql <dir>_probe`, in parallel with the answer run; remove it before
  the commit. Always run probes with `NO_ABORT_ON_CORE=1` and put last the shapes that can
  hit a known develop assert (NL inner GROUP BY or analytic correlated subqueries, CBRD-27572): a core
  stops the shard and loses every shape after it (CBRD-27184).
- **A path with no trace token** (e.g. CREATE INDEX): CTP OK does not prove the case reaches the fixed
  branch. Run the case's SQL on a host server under `gdb` with `dprintf` on the fixed branch and on the
  worker start, on the dev install at least. On optdebug a `dprintf` that prints a local
  ("value has been optimized out") aborts the gdb script and the detach kills the server: print only
  `$_thread`, arguments or globals, and group the hits per call (CBRD-26799 `pc2/summarize.py`). (CBRD-26799: a CHAR-padded design ran serial on develop
  and CTP still said OK). Local-build confs carry the campaign `parallelism=24`; set the value CTP pins.
  A path shared with SA can be proved with `csql -S` under gdb in the fast-sa namespaces. Set `dprintf`
  by `file:line` (a function name binds the PLT stub), and separate queries with
  `select repeat('M', <case line>)` markers; count only markers whose number is a select line, since
  `repeat()` in the data fires the same dprintf (CBRD-27181).
- **A specified limit where the old and new paths differ is a path probe in CI**: when the issue fixes
  such a limit (CBRD-27181: 101 backtracking points give -623 on the old loop and a result on the new
  one), put one probe per dispatch condition (collation, ESCAPE) into the TC; it outlives a gdb proof.
- **Path proof without gdb**: when the fix logs with `er_log_debug` (on by default in optdebug), count
  its lines between markers. SA: `select * from mark_<x>;` leaves `Unknown class "dba.mark_<x>"` in the
  job's csql.err. CS: a duplicate-key insert into `t_mark` leaves `key: N` and the statement in the
  server log. Parallel paths log once per worker (CBRD-27041).
- **Locks need two sessions**: a fix that opens a new parallel read path gets a throwaway shell probe
  where session 1 runs `SELECT ... FOR UPDATE` on that path and session 2 runs `set transaction lock
  timeout 1` and UPDATEs a selected row; it must time out on every point, as with the `no_parallel_scan`
  twin. A single-session sql TC cannot see a lost lock (CBRD-26722 `probe/lockprobe.sh`).
- **fast-sa runs with --no-auto-commit**: a CTP case that relies on autocommit needs `commit;` after its
  setup, or the case's own rollback undoes the setup.
- **See estimates and predicate order**: CTP masks digits, so margins are invisible there. Add
  `;plan detail` to a fast-sa input: it prints each predicate's selectivity and the check order
  (CBRD-27100 measured every margin this way).
- **Draft fast, then CTP**: run a draft case on the three installs with `tools/fast-gate/fast-sa.sh`
  (csql -S, about 3 s each) to compare twin blocks and points; locale-loaded collations (utf8_gen*,
  utf8_de_exp_ai_ci) are unknown in SA and show only in CTP.

## §7 Hygiene

- Read `provenance.txt` before deleting any run dir; delete this skill's run dirs
  (`rm -rf /home/cubrid/ctp-run-out/<tooling-repo>/sql-<timestamp>-<pid> || podman unshare rm -rf <same>`).
  Every `rm -rf` target is a literal absolute path typed out in the command: no variables, globs, loops
  or `xargs` (root AGENTS.md house rule; a variable-built rm was denied on CBRD-27177)
  after `results.md` is written; keep the regression dir of §6.
- Delete cores you analyzed; delete `~/optdebug/CUBRID-cbrd<N>-*` after the final report unless
  another issue shares the sha.
