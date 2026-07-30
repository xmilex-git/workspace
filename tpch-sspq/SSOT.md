# TPCH-SSPQ FK campaign — single source of truth

Status: specification frozen for clean restart  
Campaign ID: `tpch-sspq-fk-r1-20260730`

This file is the only normative document for the active TPCH-SSPQ campaign.
`README.md` may point here, but must not duplicate rules. Notion is an operational
mirror, not a rule source. Old commits, old ADRs, old reports and the single Notion
disposal record are never evidence for this campaign.

## 1. Objective and scope

Compare CUBRID and PostgreSQL on TPC-H SF10 for one session executing one query,
with histogram statistics and a controlled parallel configuration. For every
Q1–Q22, establish result equivalence, measure single-query-repeat WARM performance,
and complete plan, execution, profile, source and improvement analysis before
moving to the next query.

This is not an official TPC-H result. Do not report QphH, throughput or claims
about released product versions.

Query order is strictly:

`Q01 → Q02 → … → Q22`

Timeout queries use bounded analysis. They are not assigned a fabricated time.

## 2. Authority and contamination boundary

Authority order:

1. The user's latest direct instruction.
2. This file at the latest verified GitHub `main` commit.
3. Files explicitly referenced by this file at the same commit.
4. Current verified external state: engine catalogs, GJC/tmux and Notion.

If a direct instruction changes a measurement contract, update this file and
commit it before collecting more measurements.

The former PK-only campaign is contaminated because it omitted foreign keys from
the canonical CUBRID schema. Never:

- restore or read its reports, ADRs, raw files, candidate numbers or baselines;
- cite an old commit as measurement evidence;
- seed a candidate from the old Notion pages;
- compare a new result with an old value.

The only retained historical item is one Notion disposal record containing the
reason, date range, known commits, removed paths and an explicit reuse ban. It has
no relation to active databases.

## 3. Topology, paths and exact pins

| Role | Value |
|---|---|
| Normative repository | `https://github.com/xmilex-git/workspace` |
| Repository subdirectory | `tpch-sspq/` |
| Local control copy | `/Volumes/PSSD_T7/dev/workspace/tpch-sspq` |
| Remote measurement copy | SSH alias `34-ilhansong`, `~/dev/workspace/tpch-sspq` |
| Canonical CUBRID assets | `/home/cubrid/dev/cubrid/.vscode/TPC-H/scale10` |
| Raw root | `/data/tpch-sspq/tpch-sspq-fk-r1-20260730` |
| CUBRID source SHA | `607f1ee9fb2394de129e083602c84a6525fc685c` |
| PostgreSQL source SHA | `5713b437abed7085e7d59849c6e9e0f4f469633d` |

CUBRID SHA includes PR #7441 merge commit `b334446d6`.

Build both engines from clean worktrees into campaign-only prefixes. Never use a
dirty source checkout, shared install symlink or binary whose revision cannot be
proved. Record source SHA, build flags, ELF Build ID and executable path in every
query report.

Recommended build posture:

- CUBRID release/RelWithDebInfo: optimized, symbols present, assertions disabled.
- PostgreSQL optimized with debug symbols, assertions disabled, JIT disabled.
- Do not strip binaries.

Changing an engine SHA, compiler optimization, assertion mode or JIT is a campaign
contract change and requires a new campaign ID.

## 4. Safe Git synchronization

At the start of every GJC session:

1. `cd ~/dev/workspace`.
2. Run `git status --porcelain -- tpch-sspq`.
3. If the subdirectory is dirty, do not reset, checkout, clean or overwrite it.
   Recover or commit the durable work, or report the exact conflict.
4. Run `git fetch origin main`.
5. Run `git pull --ff-only origin main`.
6. Record `git rev-parse HEAD`.
7. Read this file completely.

“Use latest Git” applies to the workspace repository. Do not move the engine
source SHAs.

Never use `git reset --hard`, `git clean -fd`, force checkout or history rewrite.
Delete only paths explicitly covered by the initial cleanup manifest.

## 5. Active repository allowlist

The clean active tree may contain only:

- `SSOT.md`;
- a minimal `README.md`;
- `.gitignore`;
- verified canonical queries and minimal engine dialects under `queries/`;
- FK/index DDL and catalog verification SQL under `schema/`;
- newly written measurement/verification harnesses under `harness/`;
- new campaign reports and small raw manifests under `reports/`.

Do not create repository-internal `.not_git_tracking`, `.git_ignored_dir` or hidden
scratch. Old `CONTEXT.md`, `docs/adr/`, reports, plans, manifests, candidate
alignment files and measurement harnesses are deleted from the active tree.

## 6. Query provenance and dialect

The CUBRID query source is:

`/home/cubrid/dev/cubrid/.vscode/TPC-H/scale10/queries/`

The active CUBRID Q1–Q22 files must byte-match that source. Record SHA-256 values.
PostgreSQL files are minimal syntax dialects derived from the verified CUBRID
files. Every dialect file has a generated diff and a one-line reason for each
change. Forbidden dialect changes include hints, join reordering, subquery
rewrites, extra predicates and semantic casts.

Q15 view creation, selection and drop are one logical query and must be handled in
one query session.

## 7. Schema contract

Reuse the existing SF10 databases. Do not reload data.

Before changing schema, capture per engine:

- database identity and server executable;
- table and row counts;
- PK, FK and index catalogs;
- statistics state;
- a deterministic catalog fingerprint.

The canonical CUBRID key DDL has eight PKs and eight FKs. Add these named FKs:

| Constraint | Child columns | Parent |
|---|---|---|
| `fk_nation_region` | `nation(n_regionkey)` | `region(r_regionkey)` |
| `fk_supplier_nation` | `supplier(s_nationkey)` | `nation(n_nationkey)` |
| `fk_customer_nation` | `customer(c_nationkey)` | `nation(n_nationkey)` |
| `fk_partsupp_supplier` | `partsupp(ps_suppkey)` | `supplier(s_suppkey)` |
| `fk_partsupp_part` | `partsupp(ps_partkey)` | `part(p_partkey)` |
| `fk_orders_customer` | `orders(o_custkey)` | `customer(c_custkey)` |
| `fk_lineitem_orders` | `lineitem(l_orderkey)` | `orders(o_orderkey)` |
| `fk_lineitem_partsupp` | `lineitem(l_partkey,l_suppkey)` | `partsupp(ps_partkey,ps_suppkey)` |

CUBRID FK constraints own B-tree indexes. PostgreSQL does not auto-create indexes
on referencing columns and has no option that enables it. PostgreSQL must therefore
create eight explicit `USING btree` indexes named `idx_fk_*`, with exactly the
child columns and order above. A PK left-prefix is not a substitute.

Schema patch rules:

- run CUBRID and PostgreSQL patch jobs concurrently because this is not a
  performance measurement;
- use independent preflight, logs and rollback DDL;
- if either side fails, do not measure;
- do not silently rename, replace or drop a conflicting existing object;
- after success, prove zero FK violations and exactly 8 expected FKs and 8
  corresponding child B-trees per engine;
- compare column order, referenced key, uniqueness and index method;
- reject unexpected schema objects.

The post-patch catalog fingerprint is the schema baseline.

## 8. Statistics contract

Only histogram-enabled configurations are in scope.

CUBRID:

- `update_statistics_update_histogram=yes`;
- 300 histogram buckets;
- update statistics after FK/index creation;
- do not measure the histogram-disabled or 4-bucket configuration.

PostgreSQL:

- run standard `ANALYZE` after FK/index creation;
- keep the engine-standard statistics implementation and target.

Do not force equal bucket counts across engines. Record actual target, histogram
and MCV catalog values. Name the track “histogram-enabled controlled comparison,”
not “default configuration.”

## 9. Parallel and NUMA contract

CUBRID:

- `parallelism=6`;
- `max_parallel_workers=100`.

PostgreSQL:

- `max_parallel_workers_per_gather=5`;
- `max_parallel_workers=5`;
- `parallel_leader_participation=on`;
- set higher process limits so they do not bind.

This is node/gather-cap control, not global-worker parity. Never infer actual
execution units from settings.

CPU and memory:

- SUT and client: CPUs `0-15`, memory node0;
- collectors: CPUs `20-23`;
- verify every related TID and NUMA page distribution before and after runs.

If a pooled CUBRID thread or a PG worker/io worker inherits a different affinity,
mark the run invalid, reapply affinity and rerun. If external CPU on the SUT set is
above 1.5 core-seconds per second before a run, wait. If it crosses the threshold
during a run, mark `INVALID_BACKGROUND_LOAD`.

Do not terminate another user's process or database. Only campaign-owned servers
may be stopped.

All CUBRID start/stop/restart operations must use:

`~/dev/workspace/.claude/skills/cubrid-server-control/scripts/cubrid-server-ctl.sh`

Never invoke raw `cubrid server start|stop|restart`.

## 10. Server ownership gate

Before every CUBRID block:

1. find `cub_master`, the database server and port 1523 owners;
2. resolve `/proc/<pid>/exe`;
3. compare executable, DB name and campaign prefix;
4. classify:
   - `OK`: campaign-owned and correct;
   - `FREE`: no owner; campaign may start its server through the wrapper;
   - `BLOCKED`: another owner; do not stop it and do not measure CUBRID.
5. after start, repeat identity checks, apply affinity to every TID and verify
   configured parameters.

Run the gate before and after each measurement block, not only once per session.

## 11. Correctness gate

Before performance work, run Q1–Q22 smoke on both engines and save full results.

- Canonically sort only queries without `ORDER BY`.
- Text, integers, dates, NULLs, row count and row set must match exactly.
- Preserve raw decimal text.
- Compare decimals with arbitrary precision and allow only:

  `abs(a-b) ≤ 1e-12 × max(1, abs(a), abs(b))`

  for output-scale differences.
- Never use tolerance to hide a different row set or predicate decision.
- A completed match receives `result-equivalent-at-SF10`.
- A mismatch blocks performance work for that query and records the first
  differing row plus a full diff summary.
- A timeout is `correctness unknown (censored)`.

## 12. Cache, connection and headline timing

The only headline regime is `single-query-repeat WARM`.

Per query:

1. open one CUBRID `csql -C` direct connection;
2. execute one uncounted warmup statement;
3. verify WARM;
4. execute three measured statements consecutively;
5. close the connection;
6. repeat as one PostgreSQL `psql` Unix-socket connection with one warmup and
   three measured statements.

Metadata connection mode:

`single-connection-four-statements`

Each statement uses simple-query parse/plan/execute. No prepared statement,
server-side prepare, connection pool or reconnect between measured statements.
Connection establishment is excluded. Per-statement client wall includes result
transfer and fixed file output. Record server plan and execution times separately.

WARM is proved, not assumed. Record physical read deltas and engine buffer
counters. A failed WARM gate invalidates the run and restarts at warmup.

The Q1–Q22 full stream is smoke/timeout discovery only. Never use stream times for
ratios, ranking or causal analysis.

Report all three values and use the median as headline. Also report mean and
within-block standard deviation. Do not claim a confidence interval from three
values. Extra repetitions are a diagnostic decision, not an automatic replacement
of valid values.

## 13. Timeout and bounded work

Timeout is 300 seconds:

- PostgreSQL: `statement_timeout=300s`;
- CUBRID: external watchdog plus orphan-work verification.

On first timeout, repeat once in an isolated WARM state. Two consecutive timeouts
give `censored ≥300s`. Do not perform the third measured timeout, substitute
300 seconds, interpolate, rank the item numerically or extend timeout.

The completing engine still receives its normal three runs. Capture bounded plan,
trace and perf within the 300-second window. Extending timeout requires direct
user approval.

No next run starts while an orphan backend, worker or CUBRID task remains.

## 14. Per-query mandatory pipeline

Every Q1–Q22 completes this pipeline before transition:

1. identity/schema/ownership/NUMA/cpuset preflight;
2. correctness gate;
3. estimated plans without execution;
4. CUBRID WARM + 3 headline runs;
5. PostgreSQL WARM + 3 headline runs;
6. actual plans and CUBRID trace in separate non-headline runs;
7. CPU/thread, `/proc` I/O, iostat, NUMA and buffer diagnostics;
8. separate perf cycles/instructions/call-graph runs;
9. CUBRID source `file:line` and PostgreSQL counterpart `file:line`;
10. causal multiplier decomposition;
11. improvement registry deduplication and relations;
12. raw manifest, report, Git commit and Notion sync/backfill;
13. completion checklist and `QUERY_COMPLETE`;
14. current GJC session removal and absence verification.

Do not defer deep analysis until all queries finish.

## 15. CPU and profile accounting

Record three CPU categories:

`executor_cpu`

- CUBRID: query threads in `cub_server`;
- PostgreSQL: leader backend and parallel workers.

`auxiliary_query_cpu`

- CUBRID: `csql` parse/plan/result work and attributable background threads;
- PostgreSQL: query io workers and `psql`, plus other processes only with direct
  attribution evidence.

`total_query_cpu = executor_cpu + auxiliary_query_cpu`

Use `total_query_cpu` in the causal multiplier card. Always report executor and
auxiliary separately. Unattributable work is `unattributed_background`, never
silently included.

Identify processes by PID, start time, parent relationship and CPU deltas. Record:

- planned workers;
- launched workers;
- maximum simultaneous active units;
- time-weighted active units using actual sample timestamp deltas;
- serial tail.

Never calculate time-weighted units from a nominal interval.

Perf is non-headline. Capture cycles, instructions, IPC and call graph. Attach to
verified process sets and validate resolved-sample coverage against `perf stat`.
Do not use an all-CPU profile whose sibling-thread symbols are unresolved.

## 16. Causal multiplier card

Every report begins with:

```text
R_wall [wall]
= F_plan [plan-shape]
× F_units [TWU correction]
× F_cpu [total query CPU-seconds]

F_cpu [total query CPU-seconds]
= F_work [named work event]
× F_cost [CPU-seconds or cycles / work event]
```

Example layout only:

`2.5316x = 1.0000x [plan] × 1.0239x [units] × 2.4727x [CPU-sec]`

Never copy example values.

Rules:

- attach event unit, denominator, formula, raw pointer and evidence type to every
  factor;
- assign numeric `F_plan=1.0000` only when structural equality or direct
  controlled evidence proves it; otherwise write `UNMEASURED`;
- show reconstruction residual;
- do not call the card closed while residual exceeds the report's measured error
  budget;
- do not double-count plan, work, cost and unit effects;
- use chained counterfactuals for direct plan A/B rather than mixing native and
  controlled denominators.

## 17. Source contrast

Every claimed problem requires:

| Item | CUBRID file:line | PostgreSQL file:line | Difference | Class |
|---|---|---|---|---|

Allowed classes:

- structural absence;
- same stage, lower measured cost;
- common to both engines.

“PostgreSQL uses a hash join” is not a source contrast. Point to the code that
implements or avoids the cost. A claim of absence must record searched paths,
symbols and patterns.

## 18. Improvement registry

The new registry starts empty at `IMP-001`. Old candidate IDs are prohibited.

Before creating a candidate, search by title, CUBRID source location, PostgreSQL
source location and root cause. Reuse an existing root cause and add Q relations
and evidence.

Required fields:

- `IMP-NNN`;
- root-cause title;
- affected Q relations;
- both source locations;
- exact evidence event and denominator;
- one-line explanation;
- effect range and evidence type;
- implementation direction;
- correctness/regression risk;
- validation criteria;
- predecessor, alternative and containment relations.

Evidence type is one of direct A/B, profile attribution, projection, upper bound
or lower bound. Never sum overlapping effects.

Status:

`observed → measured → validated → implemented`

Do not mark `validated` without correctness evidence. During a Notion outage, do
not allocate temporary IDs.

## 19. Raw evidence and manifests

Raw root:

`/data/tpch-sspq/tpch-sspq-fk-r1-20260730`

Layout:

- `raw/Q01` … `raw/Q22`: immutable evidence;
- `work/QNN`: temporary working files.

At query completion, promote required files to raw and delete dispensable work.
Repository reports contain a small `raw-manifest.json` with:

- absolute remote path;
- byte size and SHA-256;
- creation command;
- campaign ID, QNN and GJC session ID;
- SSOT commit and engine SHAs;
- validity and invalid reason;
- artifact type and producing stage.

Invalid runs remain under the new campaign raw root with `INVALID.json` but are
excluded from calculations.

Evidence index format:

`claim → raw file:line → formula → evidence type → SHA-256`

## 20. Report format

Every `reports/QNN/report.md` uses these fixed sections:

1. Identity
2. Correctness
3. Headline timings and causal multiplier card
4. Plan
5. Execution telemetry
6. Profile
7. Source contrast
8. Causal decomposition details
9. Improvements
10. Evidence index
11. Notion sync
12. Completion checklist

Headline fields include:

- all three CUBRID times and CUBRID median seconds;
- all three PostgreSQL times and PostgreSQL median seconds;
- median wall ratio;
- correctness and censoring status.

Use the same field names in Git reports and Notion.

## 21. Notion operational mirror

The existing master URL remains stable but is cleaned to contain:

- one unlinked PK-only disposal record;
- a new Q1–Q22 database with 22 empty rows;
- a new empty improvement registry;
- one operational-state page.

Required query fields:

- QNN and status;
- campaign ID and SSOT commit;
- exact GJC session ID;
- correctness/censoring;
- CUBRID seconds, PostgreSQL seconds and ratio;
- causal multiplier summary;
- report commit and raw manifest link;
- improvement relations;
- content fingerprint and last verified timestamp.

Rules are not copied to Notion.

Write path:

1. official Notion connector;
2. logged-in Aside browser;
3. Git `notion_backfill_pending`.

Always fetch, minimally update and refetch. Do not mix write paths in one
reconciliation. Notion failure never blocks measurement, deep analysis or query
transition.

Backfill idempotency key:

`campaign_id + QNN + session_id + report_commit + content_fingerprint`

Clear pending only after server-side refetch.

## 22. GJC/tmux lifecycle

Use SSH alias `34-ilhansong`, official `gjc session` and tmux. Do not use
remote-claude or Telegram for normal operation.

Normal lifecycle:

1. prove no previous measurement session exists;
2. create one session with `PI_STREAM_IDLE_TIMEOUT_MS=300000`;
3. record exact session ID in operational state;
4. send the single-line Q-specific prompt;
5. capture tmux and prove the correct QNN was received;
6. keep that session for the query;
7. after durable completion, remove it;
8. verify absence with both `gjc session status` and `tmux has-session`;
9. only then create the next query session.

Never run two measurement sessions concurrently.

The worker emits:

```yaml
TPCH_SSPQ_STATUS:
  campaign_id: tpch-sspq-fk-r1-20260730
  query: QNN
  session_id: exact-id
  stage: exact-stage
  state: working|complete|blocked
  report_commit: sha-or-null
  artifact_fingerprint: sha256-or-null
  timestamp: ISO-8601
  next_action: exact-action
```

Final state is `QUERY_COMPLETE`, not merely an idle prompt.

If `gjc session remove` refuses a live tmux session, verify exact session ID, QNN
and idle state, then use `tmux kill-session -t <exact-id>`. Never kill by pattern.

## 23. Twenty-minute reconciler

Every 20 minutes:

1. read latest GitHub `SSOT.md` commit;
2. fetch Notion operational state if available;
3. inspect exact `gjc session status`;
4. capture exact tmux tail;
5. inspect relevant measurement processes;
6. inspect report/manifest Git commits;
7. reconcile only the missing transition.

Actions:

- active `Working` or measurement process: do nothing;
- idle prompt: immediately evaluate completion; do not wait 40 minutes;
- missing checklist item: steer the exact missing item in the same session;
- `anthropic stream stalled`: immediately resume the same verified session;
- stall in two consecutive checks with no new durable artifact: remove the
  session, verify absence and create one recovery session for the same QNN;
- `QUERY_COMPLETE`: verify report/manifest, attempt Notion sync, then close and
  transition;
- Notion unavailable: mark backfill and continue;
- unchanged healthy state: no user notification.

Recovery sessions must read the existing report/raw manifest and continue; they
must not repeat valid headline measurements.

## 24. Failure history and mandatory prevention

| Prior failure | Prevention |
|---|---|
| Completed query remained idle for hours | `QUERY_COMPLETE` plus immediate idle checklist |
| `gjc session remove` live refusal stopped transition | exact-target tmux kill fallback and dual absence check |
| short stream watchdog produced repeated stalls | `PI_STREAM_IDLE_TIMEOUT_MS=300000`, immediate resume, two-strike recovery |
| Notion connector outage blocked all work | official → Aside → nonblocking Git backfill |
| wrong/shared CUBRID service interrupted runs | executable/DB/port ownership gate before and after blocks |
| new pooled threads escaped cpuset | all-TID pre/post validation and invalidation |
| nominal sampler interval understated TWU | actual timestamp-delta weighting |
| PG sampler counted io workers as executor | explicit executor/auxiliary process classification |
| all-CPU perf lost sibling symbols | verified PID attachment and sample-coverage check |
| invalid CUBRID plan/trace commands executed queries | use SQL `SET OPTIMIZATION LEVEL 514` and validated trace syntax |
| alternating variants evicted each other's cache | group identical query variants and re-warm per block |
| PK-only schema contradicted canonical DDL | mandatory 8-FK/8-index fingerprint gate |
| completion depended on Telegram/remote-claude | SSH/GJC/tmux is the normal control plane |

## 25. Escalation rules

Automatically decide reversible implementation details that do not change this
contract.

Stop and ask the user only for:

- a schema/data/engine SHA/measurement-contract change;
- destructive action outside the explicit cleanup manifest;
- an unknown process or database that would have to be stopped;
- result-equivalence failure;
- repeated infrastructure failure after the documented recovery path;
- timeout extension;
- multiple scientifically valid but materially different interpretations.

Do not ask the user questions already answered by this file.

## 26. Query completion gate

A query can transition only when:

- preflight and correctness status are recorded;
- three valid headline values exist for each completing engine;
- timeout has two confirmations if censored;
- plan, execution, profile and source contrast sections are complete;
- causal multiplier card has evidence or explicit `UNMEASURED` factors;
- improvement deduplication and relations are complete or Notion backfill is
  durably recorded without temporary IDs;
- every claim is indexed to raw evidence and checksum;
- report and manifest are committed;
- `QUERY_COMPLETE` is emitted;
- current session is removed and absence verified.

## 27. Campaign bootstrap gate

Before Q01:

1. clean old active Git files and hidden scratch; verify absence;
2. clean Notion and create the new structures;
3. verify clean engine worktrees/builds/prefixes and exact binary SHAs;
4. capture pre-schema catalogs;
5. apply CUBRID and PostgreSQL FK/index patches concurrently;
6. verify 8 FK/8 B-tree parity and zero violations;
7. rebuild histogram-enabled statistics and capture catalogs;
8. verify query hashes and dialect diffs;
9. run result-equivalence smoke;
10. create exactly one Q01 GJC session and begin the mandatory pipeline.

No partial bootstrap state may be called campaign start.
