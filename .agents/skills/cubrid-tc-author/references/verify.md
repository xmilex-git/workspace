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
STATISTICS, 532ce4b6d).

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

## §6a Probing an install before writing a shell case

Try the planned checks on the pre and dev installs before writing the case:
- **Through CTP**: copy a throwaway script into your TC worktree, run it with §3's command, delete it.
  A bare scratch tree is refused (no `shell/config/...excluded_list`).
- **Host server**: build a symlink tree over the install with private copies of `conf/`, `log/`, `tmp/`,
  `var/` and `databases/`, and give it its own port. Point `CUBRID_TMP` at a short symlink: the socket
  path must fit in 107 bytes, and the scratch path gives 114. Stop the server with the
  cubrid-server-control wrapper, and its cub_master with SIGTERM after checking that the CUBRID value in
  `/proc/<pid>/environ` is your tree. Never `cubrid service stop` or pkill (CBRD-27184).
- **A path with no trace token** (e.g. CREATE INDEX): CTP OK does not prove the case reaches the fixed
  branch. Run the case's SQL on a host server under `gdb` with `dprintf` on the fixed branch and on the
  worker start, on the dev install at least (CBRD-26799: a CHAR-padded design ran serial on develop
  and CTP still said OK). Local-build confs carry the campaign `parallelism=24`; set the value CTP pins.
  A path shared with SA can be proved with `csql -S` under gdb in the fast-sa namespaces. Set `dprintf`
  by `file:line` (a function name binds the PLT stub), and separate queries with
  `select repeat('M', <case line>)` markers (CBRD-27181).

## §7 Hygiene

- Read `provenance.txt` before deleting any run dir; delete this skill's run dirs
  (`rm -rf /home/cubrid/ctp-run-out/<tooling-repo>/sql-<timestamp>-<pid> || podman unshare rm -rf <same>`).
  Every `rm -rf` target is a literal absolute path typed out in the command: no variables, globs, loops
  or `xargs` (root AGENTS.md house rule; a variable-built rm was denied on CBRD-27177)
  after `results.md` is written; keep the regression dir of §6.
- Delete cores you analyzed; delete `~/optdebug/CUBRID-cbrd<N>-*` after the final report unless
  another issue shares the sha.
