You are a runtime worker for the CUBRID tooling repo at /home/cubrid/dev/workspace (read its AGENTS.md house rules first: never write scratch to /tmp or $TMPDIR). Scratch: T=<TICKET SCRATCH, e.g. /home/cubrid/dev/workspace/.git_ignored_dir/scratch/312-343> (exists; subdir counters/). Do NOT commit, push, or post anything. Do not edit any source file, test case or script. This is lane B of three gate lanes the lead launched at the same time (the others run the whole CTP suite on the install and a release build with stand-alone probes); do not touch their work.

Delegation execution contract (verbatim; obey strictly):
- Finite gate work (incremental build, unit, smoke — steps that each finish within ~10 min) runs as FOREGROUND blocking commands, chained in one continuous turn. run_in_background/nohup/monitors are FORBIDDEN for such steps. Only a full fresh build may go background, and then the SAME turn must bounded-poll its completion marker (`timeout ... until grep ...`) — never end a turn "waiting for a notification".
- The worker must deliver its final report in the same turn the work finishes, BEFORE going idle.

No CTP in this lane.

Environment notes: set variables inline (`VAR=x cmd`, never `env VAR=x cmd` — ~/.local/bin/env shadows /usr/bin/env). Use /usr/bin/grep for -E/-P. rm only literal paths (never variable-prefixed globs, never wildcards). Install O=/home/cubrid/dev/workspace/.git_ignored_dir/scratch/dpin/install-optdebug (built from the engine commit under test; lane A's CTP shards copy it when they start). The runner below never writes to O: every stack mounts O as the read-only lower of a volatile overlay and takes its conf (the campaign cubrid.conf plus the stack's parallelism) and its logs in the overlay. So there is no install copy and no `just conf` in this lane — never run `just conf`, the old counter harness, or anything else on O itself.

Runner: V=/home/cubrid/dev/workspace/tools/fast-gate. fast-counters.sh runs the unchanged JDBC DomainBench harness over 9 client/server stacks at once (8 for the p0 cells, 1 for p24), each in its own user+mount+IPC+PID+net namespace with volatile overlays over the install and a reflink snapshot of the bench database: private ports and shm, no fsync, every process dies with its namespace. Its output has the old harness's layout: <out>/output/counters-p0.tsv, counters-p24.tsv (+ .err), <out>/logs/provenance.txt; per stack <out>/s/<n>/ (stack.log, bench.tsv/.err, up-install/log = the stack's server and broker logs).

Note on the Bash tool: its checker refuses compound commands that mention a path containing "git" (every path here contains .git_ignored_dir) together with `&`, `wait` or loops. Run each command below as ONE plain command exactly as written.

Steps (foreground, one continuous turn):
1. `date -u +%FT%TZ` (record as START); `test -e $T/counters/<LABEL> && echo EXISTS` (if it exists, STOP and report); `sha256sum $O/lib/libcubrid.so`.
2. Counters: `bash $V/fast-counters.sh $T/counters/<LABEL> $O; echo rc=$?` (Bash timeout 600000; about 2 minutes). If rc is not 0, report `cat $T/counters/<LABEL>/s/<n>/stack.log` for every failed stack and the error lines of the files under its up-install/log/, then continue.
3. Compare: `python3 <COMPARE SCRIPT, e.g. $T/counters/compare-t343.py> <LABEL> | tee $T/counters/<LABEL>-compare.txt`.
4. Report `cat $T/counters/<LABEL>/logs/provenance.txt` and the FULL content of $T/counters/<LABEL>-compare.txt.
5. Leftovers: `pgrep -u $USER -a -f DomainBench` (expected none; lane A's container processes are not yours) and `find /bench/hdd/core -maxdepth 1 -newermt 'START' -name 'core.*'` (paths only; do not analyze or delete).

Final report: libcubrid.so hash; runner rc; provenance; the FULL compare output; leftovers and cores.
