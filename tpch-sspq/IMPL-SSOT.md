# TPCH-SSPQ implementation campaign — single source of truth

Status: Phase 0 specification, frozen at the commit that introduces this file
Campaign ID: `tpch-sspq-impl-r1-20260803`

This file is the only normative document for the TPCH-SSPQ **implementation** campaign.
It is self-contained on purpose. A remote worker holding nothing but this file MUST be
able to execute its assigned work correctly. This document therefore never delegates a
rule to another document with a phrase such as "see `SSOT.md` section N". Every
operational rule this campaign needs is restated here in full.

**Phase gate.** Phase 2 (writing any engine code) MUST NOT begin until the user has
explicitly approved the Phase 1 ranking and the resulting candidate queue. Phase 0
(this document) and Phase 1 (fresh baseline + scoring + ranking) produce documents and
measurements only. There is no implicit promotion from Phase 1 to Phase 2.

---

## 1. Authority, pins, and Git synchronization

### 1-a. Authority order

1. The user's latest direct instruction.
2. This file — `tpch-sspq/IMPL-SSOT.md` — at the pinned, verified GitHub `main` commit.
3. This campaign's own Git artifacts: reports, raw manifests and priority ranking files
   under `tpch-sspq/impl/`, together with the raw evidence they index.
4. The Notion operational mirror.

Lower-numbered items win. Notion is a mirror; it is never a rule source and never
resolves a conflict against Git.

### 1-b. Contamination and evidence boundary

The previous measurement campaign's `tpch-sspq/SSOT.md`, its
`tpch-sspq/reports/improvement-registry.json`, its `tpch-sspq/reports/QNN/` reports and
its Notion mirror are **INPUT EVIDENCE ONLY**, and only for Phase 0 and Phase 1 of this
campaign. They supply candidate root causes, source citations, measured effect ranges
and evidence levels. Once this file exists at a pinned commit:

- they MUST NOT be treated as independent norms;
- an operational rule that appears there but not here is NOT in force here;
- their absolute wall-clock times MUST NOT be reused as this campaign's "before" values
  (see section 3);
- a conflict between them and this file is resolved in favour of this file, without
  discussion.

The measurement campaign's *identifiers* remain canonical: `IMP-001` … `IMP-031` keep
their meaning, and `next_id` is `IMP-032`. This campaign allocates no new IMP IDs unless
the user directs it to.

### 1-c. Pin table

| Item | Value |
|---|---|
| Campaign ID | `tpch-sspq-impl-r1-20260803` |
| Normative repository | `https://github.com/xmilex-git/workspace` |
| Normative file | `tpch-sspq/IMPL-SSOT.md` |
| Local control copy | `/Volumes/PSSD_T7/dev/workspace` |
| Remote worker copy | SSH alias `34-ilhansong`, `~/dev/workspace` |
| Workspace HEAD at campaign start | `f66c5c6f84193d7934802f5498ff9cd7dada8701` |
| Previous SSOT blob SHA (input evidence) | `510478846bff081d3223d3835069283a7cd2e47b` (`tpch-sspq/SSOT.md`) |
| Improvement registry blob SHA (input evidence) | `c38591819f8b34f52b6832d7fda41bc54a0077ba` (`tpch-sspq/reports/improvement-registry.json`) |
| Registry state, verified | `IMP-001`…`IMP-031` present, no duplicates, no gaps, `next_id = IMP-032` |
| CUBRID base SHA (frozen for the whole campaign) | `607f1ee9fb2394de129e083602c84a6525fc685c` |
| PostgreSQL reference SHA | `5713b437abed7085e7d59849c6e9e0f4f469633d` |
| Campaign raw root (remote) | `/data/tpch-sspq/tpch-sspq-impl-r1-20260803` |
| Notion improvement registry | page `7e108b3f-6aa5-4497-88fc-bbad8c80164c`, data source `collection://980756de-772e-4e18-8a1b-71ba1cfd11d7` |
| Notion Q01–Q22 database | page `4e97947e-5772-435b-a680-67d7d4a7ca7a`, data source `collection://5d23253e-d89d-44e9-837c-fc98b4042d63` |
| Notion operational state | page `3adf947f-1be1-810e-96c1-e1892035409a` |
| Notion schema snapshot (read-only) | `2026-08-02T16:33Z` |

The CUBRID base SHA is **frozen for the entire campaign**. Every worktree, every base
build and every patch branch starts from it. Changing it, or the compiler, linker,
optimization flags or assertion mode, is a campaign contract change requiring a new
campaign ID and explicit user approval.

### 1-d. Every worker verifies the pin before acting

Before any remote worker (GJC session, subagent, reconciler) performs campaign work it
MUST:

1. enter the workspace repository root and confirm the checked-out branch is `main`;
2. run `git status --porcelain -- tpch-sspq`; if the subdirectory is dirty it MUST NOT
   reset, checkout, clean or overwrite it — it either commits durable current-campaign
   work or reports the exact conflict;
3. `git fetch origin main` and `git pull --ff-only origin main`;
4. require local `HEAD`, remote `HEAD` and `origin/main` to agree;
5. record `git rev-parse HEAD` and `git rev-parse HEAD:tpch-sspq/IMPL-SSOT.md`;
6. compare both against the session-pinned `impl_ssot_commit` / `impl_ssot_blob_sha`;
7. read this file completely to EOF.

If the blob SHA of `tpch-sspq/IMPL-SSOT.md` on `origin/main` differs from the session
pin, the worker MUST allow only the currently running command to finish, preserve
artifacts, mark `IMPL_SSOT_DRIFT`, and block any new build or measurement stage until
the controller reconciles the contract. `origin/main` advancing for unrelated report
commits while the blob SHA is unchanged is NOT drift.

Workers MUST NOT pull, switch branches or change the pinned document during an active
IMP.

### 1-e. Commit → push → verify origin reachability

Durability has one definition in this campaign: **reachable from `origin/main`**.

Every durable write follows exactly this order:

1. `git add` only the intended paths (never `git add -A`, never `.DS_Store`, never
   unrelated pre-existing working-tree modifications);
2. `git commit`;
3. `git push origin main` (normal fast-forward push);
4. `git fetch origin && git merge-base --is-ancestor <commit> origin/main` and require
   success.

A commit that has not passed step 4 MUST NOT be cited as `report_commit`, MUST NOT be
mirrored to Notion, and MUST NOT be used to close an IMP. If the push is rejected, the
worker MUST NOT rebase, merge or force-push automatically; it preserves the work and
reports the blocker.

`git rebase`, `git reset --hard`, `git clean -fd`, force checkout, force push and any
history rewrite are FORBIDDEN on the workspace repository. Branch creation is confined
to the engine worktrees described in section 5; this campaign creates NO branches in the
workspace repository.

---

## 2. Candidate scoring methodology

Phase 1 scores every registry candidate and produces one ranking. The methodology below
is normative and MUST be reproduced verbatim in `tpch-sspq/impl/priority-ranking.md`.

### 2-a. Implementation Feasibility Score (0–100, higher = easier)

Weighted sum of four components, each scored 0–100 on the "easier is higher" scale:

| Component | Weight |
|---|---|
| LOC / diff scope | 40% |
| Files, subsystems and serialization blast radius | 20% |
| Correctness and concurrency risk | 25% |
| Test and dependency burden | 15% |

Rules:

- LOC scoring MUST use the **HIGH** estimate of the LOC band, never the optimistic or
  the likely one. Optimism in the estimate is not a feasibility advantage.
- **KLOC alone never decides difficulty.** A 30-line change to XASL serialization or to
  a lock protocol is harder than a 400-line change confined to one executor file. The
  blast-radius and correctness-risk components exist precisely to override raw size, and
  the written rationale MUST say which component dominated.
- The blast-radius component MUST explicitly consider: number of files, number of
  subsystems, whether XASL / wire format / persistent format / catalog format is
  touched, and whether client-server compatibility is affected.
- The correctness/concurrency component MUST consider MVCC, latching, locking, worker
  lifecycle and memory ownership.
- The test/dependency component MUST consider whether an existing regression test covers
  the path, whether a new test must be authored, and whether a predecessor candidate is
  required first.

### 2-b. Evidence-adjusted Benefit Score (0–100)

Evidence weights, applied per affected query:

| Evidence level | Weight |
|---|---|
| Direct A/B | 1.00 |
| Lower bound | 0.90 |
| Attribution | 0.70 |
| Projection | 0.50 |
| Upper bound | 0.35 |
| Unmeasured | 0.00 |

Expected saving:

```text
expected_saved_seconds = Σ_q ( fresh_base_median_q
                             × conservative_effect_fraction_q
                             × evidence_weight_q )
```

Rules, all mandatory:

- `fresh_base_median_q` is this campaign's **fresh** Phase 1A CUBRID baseline median for
  query `q` (section 3). A previous campaign's absolute time MUST NOT be substituted.
- For a **direct A/B** candidate, `conservative_effect_fraction_q` is the observed effect
  rate from that A/B — not a rounded-up or extrapolated one.
- For a candidate whose effect is stated as a **range**, the conservative **lower bound**
  of the range MUST be used.
- A whole profile band MUST NOT be automatically treated as removable. If the evidence is
  "this band costs X", the removable fraction MUST be argued and stated; absent an
  argument, the band contributes its measured *reduction*, not its total.
- A `q_relation` with no numeric basis contributes **0 seconds**. It is still listed, so
  the reader can see it, but it adds nothing.
- Overlapping candidates' effects MUST NOT be summed. See section 4 for clusters.
- Every non-zero term MUST cite the raw evidence pointer that produced it.

Normalization:

```text
benefit_score = 100 × percentile_rank( log1p(expected_saved_seconds) )
```

over the scored candidate set. The `log1p` compression plus percentile ranking is chosen
so a single outlier candidate cannot dominate the ranking by arithmetic alone. Candidates
with `expected_saved_seconds = 0` all receive the bottom rank and MUST be marked
`NO_NUMERIC_BASIS`.

### 2-c. Total score and tie-breaks

```text
Total = 0.50 × Feasibility + 0.50 × Benefit
```

Ties in `Total` are broken in this exact order:

1. higher evidence level (Direct A/B > Lower bound > Attribution > Projection > Upper
   bound > Unmeasured);
2. lower correctness risk;
3. is a predecessor / enabler of another candidate;
4. smaller high-LOC estimate.

### 2-d. Sensitivity and ranking stability

The ranking MUST be recomputed with every evidence weight perturbed by ±0.15 (clamped to
`[0, 1]`), in both the pessimistic and the optimistic direction. If the identity or the
order of the top 5 changes materially under either perturbation, the ranking document
MUST carry the marker `RANKING_UNSTABLE`, name which candidates swapped, and state that
the queue order in that region is not evidence-supported. `RANKING_UNSTABLE` does not
block Phase 1 completion; it blocks silent reliance on a fragile order.

### 2-e. Required ranking table columns

`tpch-sspq/impl/priority-ranking.md` MUST carry a table with exactly these columns, and
`priority-ranking.json` MUST carry the same fields machine-readably:

1. canonical IMP ID (`IMP-NNN`, from the frozen registry);
2. lane (section 4);
3. fresh affected-query baseline (per-query medians used, from Phase 1A);
4. expected effect + evidence level;
5. expected saved seconds;
6. LOC estimate low / likely / high;
7. files and subsystems touched;
8. difficulty and risk rationale (prose, one to three sentences);
9. feasibility score / benefit score / total score;
10. predecessor / alternative / containment relations;
11. eligibility and blocker (eligible, or blocked with the exact blocker);
12. one-line ranking rationale.

---

## 3. Fresh baseline procedure (Phase 1A)

**No absolute wall time from any previous campaign is this campaign's "before".** Past
numbers may be cited as *expectations* in a plan; they are never the denominator of a
measured effect. Phase 1A collects a fresh Q01–Q22 CUBRID baseline from the immutable
base binary built at the frozen base SHA, and that baseline is the only "before" the
scoring and the A/B procedure may use.

### 3-a. CPU affinity and NUMA contract

#### Host topology (verified read-only on `34-ilhansong`)

| Fact | Value |
|---|---|
| CPU model | Intel(R) Xeon(R) Silver 4216 CPU @ 2.10GHz |
| Sockets × cores | 2 sockets × 16 cores |
| Threads per core | **1** (no SMT; CPUs 32–63 are offline) |
| Online CPUs | `0-31` |
| NUMA node 0 | CPUs `0-15`, 128565 MB |
| NUMA node 1 | CPUs `16-31`, 64502 MB |
| Node distances | local 10 / remote 21 |

#### Isolation mechanism: `taskset` affinity, NOT cpuset cgroups

The campaign host is a **rootless podman container**. `/proc/self/cgroup` shows
`libpod_parent/libpod-…`; `/` is an `overlay` mount. The cgroup hierarchy is **v1**, and
`/sys/fs/cgroup/cpuset` inside the container is **flat**: it exposes only the container's
own `cpuset.*` files, zero child cpusets exist, and no host cpuset can be enumerated.
Container-level values are `cpuset.cpus = 0-31`, `cpuset.effective_cpus = 0-31`,
`cpuset.mems = 0-1`, `cpuset.cpu_exclusive = 0`.

Whether a child cpuset cgroup *could* be created from inside the container was deliberately
NOT tested — doing so is a mutating command and Phase 0 recon is read-only. This is recorded
as an **untested assumption, not a proven impossibility**.

The isolation therefore uses **CPU affinity** (`taskset -c` / `sched_setaffinity`, with
`numactl` for memory binding), which is exactly what the previous measurement campaign
`tpch-sspq-fk-r1-20260730` used. That was verified empirically: the live
`cub_server tpch_sf10_q1` (PID 2737859) has **all 24 TIDs at affinity `0-15`**, and the live
`postgres` (PID 1433696) is likewise at `0-15`.

#### CPU assignment

| Role | CPUs | NUMA |
|---|---|---|
| SUT (`cub_server`) and client (`csql`) | `0-15` | memory node 0 |
| Collector / sampler processes | `20-23` | node 1 |
| Controller, GJC worker shell, compiler / build jobs | `24-31` | node 1 |
| Unassigned buffer | `16-19` | — |

Derivation: the prior measurement campaign already contracted SUT+client to CPUs `0-15`
on memory node 0 and collectors to CPUs `20-23` on this host. This campaign adds
controller/GJC/compiler on `24-31`. `0-15` therefore satisfies the requirement of not
overlapping `20-31`, keeps the SUT on the same physical cores and the same NUMA node the
existing SF10 database and buffer pool were measured on, and leaves `16-19` deliberately
unassigned as a separation band between the SUT and the collectors. With the topology above,
`0-15` is **exactly all of NUMA node 0**, which is also the memory-rich node (128565 MB
versus node 1's 64502 MB) — so the SUT owns one whole node's cores and that node's local
memory. Collectors (`20-23`) and controller/GJC/compiler (`24-31`) are both entirely on
node 1, off the SUT's node. Any other SUT CPU list would change the memory locality of the
measured engine and is a contract change.

Mandatory rules:

- `cub_server` MUST be started fresh with the correct CPU affinity **and** memory binding,
  applied **from process start** — the server is launched under `taskset -c 0-15` (or
  `numactl --cpunodebind=0 --membind=0`), never re-pinned after the fact.
- **Memory MUST be bound, not merely CPU affinity.** NUMA locality is the whole reason
  `0-15` was chosen, so the SUT MUST run with `numactl --membind=0` or an equivalent memory
  policy; CPU affinity alone does not satisfy this contract.
- After start, the affinity of **every** `cub_server` TID MUST be verified by iterating
  `/proc/<pid>/task/*` and checking each TID's affinity individually (for example
  `taskset -p <tid>` per entry). A single TID outside the SUT CPU list ⇒ the run is marked
  **INVALID immediately**, the server is restarted, and the run is repeated. Late-spawned
  pooled threads are the known failure mode; the check MUST therefore be repeated after each
  measurement block as well as before it.
- The NUMA page distribution of the server MUST be recorded before and after each block.
- The SUT CPUs SHOULD carry no non-campaign process. Where exclusivity cannot be
  enforced, **any run during which external CPU on the SUT CPUs exceeds 0.5 core-seconds
  per second is INVALID** (`INVALID_BACKGROUND_LOAD`).
- **The previous measurement campaign's 6.0 core-s/s quiet gate is NOT inherited.** That
  threshold was raised to keep a cross-engine comparison moving under sustained host
  load; this campaign measures a same-engine patch effect where the expected signal is
  often a few percent, so a 6.0 core-s/s tolerance would exceed the effect being
  measured. The gate here is 0.5 core-s/s and it is not negotiable without user approval.
- **No build, compression, hashing, archiving or Notion work may run concurrently with a
  performance measurement.** Compilation is confined to CPUs `24-31` *and* MUST NOT
  overlap in time with a measured block.

#### Shared container, out-of-scope neighbours

This campaign runs inside a container shared with other `cubrid`-owned workloads —
long-lived agent stacks, the PostgreSQL reference instance, and previous campaigns'
leftovers. Those processes are **out of campaign scope**. They MUST NEVER be stopped,
killed, re-niced or re-pinned by this campaign. Because affinity is advisory and the
container grants `0-31` to everyone, contention from those neighbours is handled **solely**
by the 0.5 core-s/s external-CPU invalidation gate above: a contended run is discarded, not
made quiet by force.

### 3-b. Server ownership gate

`tpch_sf10_q1` is the expected shared database identity for this campaign and is NOT to
be treated as a stray database. Nevertheless, **before and after every block**, the
worker MUST verify and record:

1. the `cub_master` and database-server PIDs and the port owner;
2. `/proc/<pid>/exe` resolved to a real path;
3. that the executable path is under this campaign's install prefix
   (`/home/cubrid/dev/tpch-sspq-impl-r1/install/...`);
4. the database identity, the port, the PID and the process start time;
5. a classification: `OK` (campaign-owned and correct), `FREE` (no owner; the campaign
   may start its own server), or `BLOCKED` (owned by someone else).

`BLOCKED` ⇒ do not stop it, do not measure. Another user's process or database MUST NOT
be terminated under any circumstance. Only campaign-owned servers may be stopped.

All CUBRID start/stop/restart operations MUST use the wrapper
`~/dev/workspace/.claude/skills/cubrid-server-control/scripts/cubrid-server-ctl.sh`.
Raw `cubrid server start|stop|restart` MUST NOT be invoked — it hangs forever when its
output is captured by a pipe.

### 3-c. Baseline collection

For each of Q01…Q22, on the immutable base binary:

1. restart the campaign server on the base binary and pass the gates in 3-a and 3-b;
2. open one direct campaign connection (`csql -C`), consuming all rows to a campaign-owned
   sink under `work/<IMP-ID>` or `work/baseline`, never to a terminal renderer;
3. execute uncounted warmup statements until **WARM convergence is proved**, not assumed:
   physical-read deltas and engine buffer counters MUST show convergence; a failed WARM
   gate invalidates the block and restarts at warmup;
4. execute the measured statements consecutively on that same connection, with no
   prepared statement, no pool and no reconnect between them; connection establishment is
   excluded from the timing;
5. record all individual values, the per-block median, the within-block dispersion
   (standard deviation and CV), and across blocks the **block dispersion**;
6. derive and record the **noise floor** for that query: the paired coefficient of
   variation of base-vs-base block medians. This noise floor is what section 6's MDE is
   computed from.

The per-query baseline used by section 2-b is the median over the converged WARM blocks.

Q15 is one logical unit (view creation, selection, drop) and MUST be handled in one
block, with the view proved absent before and dropped after.

Timeout handling: 300 seconds, external watchdog plus orphan-work verification. Two
consecutive timeouts give `censored ≥300s`. A censored query MUST NOT be assigned 300
seconds, interpolated or ranked numerically; it contributes `0` expected saved seconds
unless a candidate's evidence gives a separate numeric basis.

### 3-d. PostgreSQL's role

PostgreSQL is **never** the denominator of a patch effect. In this campaign it has
exactly two roles:

- **source contrast** — the reference implementation at
  `5713b437abed7085e7d59849c6e9e0f4f469633d` that motivates a candidate's change
  direction, cited by `file:line`;
- **environment sentinel** — an optional, clearly labelled check that the host itself has
  not changed between campaign phases.

A report MUST NOT express a patch's effect as a ratio against PostgreSQL. The patch
effect is always CUBRID-patched over CUBRID-base.

---

## 4. Candidate lanes, dependencies and overlap

### 4-a. Lanes

Every one of `IMP-001`…`IMP-031` MUST be assigned exactly one lane:

| Lane | Meaning |
|---|---|
| **Performance** | The candidate's purpose is to reduce measured execution cost. It is ranked, queued and A/B-verified. |
| **Enabler-Predecessor** | The candidate does not itself produce a headline improvement, but another candidate cannot be implemented or measured without it. |
| **Diagnostic-Measurement-correctness** | The candidate improves observability, plan/trace fidelity, or corrects a measurement-visible behaviour. It is not ranked for performance benefit. |
| **Deferred research** | The candidate is real but out of scope for this campaign: it requires a design decision, a persistent-format change, or research beyond a bounded patch. |

The **overall implementation ranking covers the Performance lane only**. A required
enabler is inserted into the queue **immediately ahead of** the dependent candidate it
unblocks; it inherits its position from the dependent, never from its own benefit score
(which is typically zero). Diagnostic and Deferred-research candidates are listed with
their lane and rationale but carry no queue position.

### 4-b. Dependencies

For each candidate the ranking MUST record `predecessor`, `alternative` and `containment`
relations, taken from the frozen registry and extended where Phase 1 analysis finds a new
one. A candidate whose predecessor is not in the approved queue is `blocked`, and the
eligibility column MUST name the blocker.

### 4-c. Overlap and containment clusters

Candidates that address the same cost on the same query form a **cluster**. A cluster MUST
be declared explicitly in the ranking, with a type:

- **predecessor cluster** — B requires A; both may be implemented, A first;
- **alternative cluster** — A and B are two ways to remove the same cost; at most one is
  queued, and the ranking states which and why;
- **containment cluster** — A's effect is a subset of B's; the contained candidate's
  expected saving is set to `0` for ranking purposes, with a note pointing at the
  containing candidate.

Double-counting suppression rule: within a cluster, the `expected_saved_seconds` of the
**highest-scoring member only** is counted toward any campaign-level total. The other
members' savings are recorded but explicitly marked `SUPPRESSED_OVERLAP` and excluded
from every sum. Cluster totals MUST NOT be produced by addition across members.

---

## 5. Engine branch and worktree strategy

### 5-a. Directory contract

```text
/home/cubrid/dev/tpch-sspq-impl-r1/                 campaign root
/home/cubrid/dev/tpch-sspq-impl-r1/base-src         clean base worktree @ frozen base SHA
/home/cubrid/dev/tpch-sspq-impl-r1/worktrees/IMP-NNN   candidate worktree
/home/cubrid/dev/tpch-sspq-impl-r1/install/base     immutable base install
/home/cubrid/dev/tpch-sspq-impl-r1/install/IMP-NNN  patched install
```

Rules:

- Every candidate worktree MUST be created from the frozen CUBRID base SHA
  `607f1ee9fb2394de129e083602c84a6525fc685c`.
- `install/base` is **immutable** for the whole campaign. It is built once, its binary
  SHA-256 and ELF Build ID are recorded, and it is never rebuilt or overwritten. Every
  A/B uses that exact binary as B.
- The existing remote measurement checkouts (for example the FK campaign's
  `/home/cubrid/dev/tpch-sspq-fk-r1/cubrid-src`) and the shared
  `/home/cubrid/dev/cubrid` checkout MUST NEVER be modified, rebuilt, branched or
  checked out by this campaign. They are read-only references.

### 5-b. Branch naming and the one-branch rule

```text
impl/tpch-sspq-impl-r1-20260803/IMP-NNN-<slug>
```

- **One branch = one IMP = one verification hypothesis.**
- **NO patch stacking.** A branch contains the change for its own IMP and nothing else.
- A rejected or inconclusive patch MUST NOT be carried into the next candidate's branch.
- Stacking a predecessor branch under a dependent branch is allowed **only with explicit
  user approval**, recorded in both reports.
- An accepted patch MUST NOT be merged into CUBRID `main` automatically, or at all,
  within this campaign. Cumulative integration is a separate later phase (section 11) and
  requires user approval.

### 5-c. `implementation-plan.md` is written BEFORE any code change

For every IMP, `implementation-plan.md` MUST exist in the candidate worktree and be
committed on the candidate branch **before the first source edit**. It MUST contain:

1. the hypothesis, stated as a falsifiable claim about a named cost;
2. the exact CUBRID `file:line` locations to be changed;
3. the PostgreSQL reference `file:line` at the pinned reference SHA;
4. the expected changed files and the LOC band (low / likely / high);
5. the expected metric signature — the specific counter, event or profile band that MUST
   move, and in which direction;
6. the correctness risk and how it will be tested;
7. the target queries;
8. the negative-control queries — queries that MUST NOT change;
9. overlap and dependency relations;
10. the rollback method.

### 5-d. Hard stop on scope

Implementation MUST stop immediately, and the worker MUST report, if **either**:

- the actual change exceeds **150% of the high-LOC estimate**; or
- the change touches an **unanticipated subsystem**, **XASL serialization**, a
  **persistent format**, or the **lock protocol**.

This is a stop-and-report, not a judgment call. The partial work is preserved on the
branch and the campaign waits for the user.

---

## 6. Build, correctness and A/B measurement procedure

### 6-a. Build contract

- The base build and every patch build MUST use the **identical** compiler version,
  compiler flags, linker and assertion mode. Optimized build with symbols present,
  assertions disabled, binaries not stripped.
- For every build, record and commit: compiler and linker versions, the complete
  configure/build arguments, the install prefix, the binary **SHA-256**, the **ELF Build
  ID**, and the build log path.
- Before measuring, verify **zero source diff beyond the patch**: `git diff` between the
  candidate worktree and the frozen base SHA MUST contain only the intended candidate
  change plus `implementation-plan.md`.
- **Performance builds are separate from sanitizer/diagnostic builds.** An ASan/UBSan,
  assertion-enabled or instrumented build MUST NOT produce a headline A/B number, and its
  install prefix MUST be distinct.

### 6-a-1. Build recipe pin

**User decision.** This campaign **replicates the previous campaign's build state**
(`tpch-sspq-fk-r1-20260730`, worktree `/home/cubrid/dev/tpch-sspq-fk-r1/cubrid-src`) rather
than deriving the build from the base SHA's committed submodule pointers on their own. The
authoritative source of that state is that worktree — **never** the dirty shared checkout
`/home/cubrid/dev/cubrid`. Everything below was captured read-only in Phase 0b and is
normative.

#### Source pins

| Item | Pinned value | Notes |
|---|---|---|
| CUBRID base SHA | `607f1ee9fb2394de129e083602c84a6525fc685c` | detached HEAD; version banner `11.5.0.2366-607f1ee` |
| Submodule `cubrid-cci` | `2fb8d6d02c41386be0d56c3cfc6a14ad7e17ac15` | **initialized and checked out**; identical to the base SHA's recorded pointer |
| Submodule `cubrid-jdbc` | `e4947d1a4aafe93239542405d28567c59adca0ea` | **NOT initialized** — directory empty; see below |
| Submodule `cubridmanager` | `aee66659e11bec1b426ec11f872d36a9345425f8` | **NOT initialized** — directory empty; see below |

**No submodule drift exists.** The previous campaign's only initialized submodule
(`cubrid-cci`) sits exactly on the pointer recorded by the base SHA
(`git ls-tree 607f1ee9f -- cubrid-cci` ⇒ `2fb8d6d0…`). Replication and "use the base SHA's
recorded pointers" therefore coincide for `cubrid-cci`; they differ only in that the
previous campaign left `cubrid-jdbc` and `cubridmanager` **uninitialized**, and this campaign
MUST do the same.

- `cubrid-jdbc` and `cubridmanager` MUST be left uninitialized (empty directories).
  `WITH_JDBC` is `ON` in the cache but `build.sh`/CMake skip the JDBC packaging step when
  `$source_dir/cubrid-jdbc/src` is absent; the resulting install contains **no** `jdbc/`
  directory. Initializing them would change what gets built and is a contract change.
- The shared checkout `/home/cubrid/dev/cubrid` carries **different** submodule state —
  `cubrid-cci` at `ef5470ffae4aa934425145e393fefc81899c84a7` (`+`, differs from the recorded
  pointer) and `cubrid-jdbc` initialized at `4a40cb95c9c876f8ffea7640906ffae33d2efbf5`
  (`+`). That checkout MUST NOT be used, copied from, or treated as a reference for this
  campaign's build.
- Known benign dirt: after building, `cubrid-cci/win/cci_version.h` is regenerated, so
  `git status` in the parent shows ` M cubrid-cci`. This is a build side-effect, not a
  source change, and MUST NOT be counted as patch diff.
- `.gitmodules` at the base SHA (blob `158585a3dde3e606bb5d54459b868e07110be797`) pins the
  remotes `https://github.com/CUBRID/cubrid-manager-server`,
  `https://github.com/cubrid/cubrid-jdbc`, `https://github.com/CUBRID/cubrid-cci.git`. Only
  the `cubrid-cci` remote needs to be reachable, and only once per fresh worktree.

#### Preset files — corrected finding

`CMakeUserPresets.json` **does not exist** in the previous campaign's worktree
`/home/cubrid/dev/tpch-sspq-fk-r1/cubrid-src/`. The build depended solely on the **tracked**
`CMakePresets.json`:

| File | Presence | sha256 | Git |
|---|---|---|---|
| `CMakePresets.json` | present, unmodified | `1818a143464bf51eb7a84bcaa5c3fbb3da2c9ce8dab153f3d847e6ac113baacb` | tracked at base SHA, blob `1bdaed37aa2f693eec4844071beb4689d9bbd532` |
| `CMakeUserPresets.json` | **ABSENT** | — | untracked by design; not present |
| `build.sh` | present, unmodified | `f90b796bcc438189fada4c98b9a9f8c8606533a5312720198287be20a4091287` | tracked at base SHA, blob `05c5026caa903d4e0dbee21f9b4524bc8fc923ec`; **not used by this recipe** |

Normative rule: **`CMakeUserPresets.json` MUST NOT be created in `base-src` or in any
candidate worktree.** Before configuring, each worktree MUST assert that the file is absent
and that `sha256sum CMakePresets.json` equals `1818a143…`. A `CMakeUserPresets.json` does
exist in the shared checkout `/home/cubrid/dev/cubrid`
(sha256 `4a19ab4bfd96b94a34ab1069966980033ac558e3f8b268e2dabca25488f5fb16`); it overrides
`binaryDir`, the install prefix and the optimization flags, and copying it into a campaign
worktree would silently change the recipe. It MUST NOT be copied.

**Stated risk (untracked-file hazard).** `CMakeUserPresets.json` is untracked in git, so a
recipe that depended on it would be reproducible only by hash-pinning it in this document.
Here the hazard is resolved in the strongest way available — the file is pinned **absent**,
and the entire preset input is a tracked, hash-pinned file. The absence assertion is
mandatory precisely because git will never report the file's reappearance.

#### Toolchain pins

| Tool | Pinned value |
|---|---|
| C compiler | `/usr/bin/cc` → gcc (GCC) 8.5.0 20210514 (Red Hat 8.5.0-22); `CMAKE_C_COMPILER_VERSION` `8.5.0`, id `GNU` |
| C++ compiler | `/usr/bin/c++` → g++ (GCC) 8.5.0 20210514 (Red Hat 8.5.0-22); `CMAKE_CXX_COMPILER_VERSION` `8.5.0`, id `GNU` |
| Linker | `/usr/bin/ld`, GNU ld version 2.30-123.el8 |
| cmake | 3.26.5 (`/usr/bin/cmake`) |
| Generator / make program | Ninja 1.8.2 (`/usr/bin/ninja-build`) |
| flex / bison | `/usr/bin/flex` 2.6.1, `/usr/bin/bison` 3.0.4 (SYSTEM) |
| git | 2.43.0 |

#### Configure settings (from the previous campaign's `CMakeCache.txt`)

| Variable | Value |
|---|---|
| `CMAKE_BUILD_TYPE` | `RelWithDebInfo` |
| `CMAKE_C_FLAGS` / `CMAKE_CXX_FLAGS` | *(empty)* |
| `CMAKE_C_FLAGS_RELWITHDEBINFO` | `-O2 -g -DNDEBUG` |
| `CMAKE_CXX_FLAGS_RELWITHDEBINFO` | `-O2 -g -DNDEBUG` |
| Assertions | **disabled** (`-DNDEBUG`) |
| `CMAKE_C_COMPILER` / `CMAKE_CXX_COMPILER` | `/usr/bin/cc` / `/usr/bin/c++` |
| `CMAKE_MAKE_PROGRAM` | `/usr/bin/ninja-build` |
| `CMAKE_GENERATOR` | `Ninja` |
| All linker flags (`EXE`/`SHARED`/`MODULE`/`STATIC`, all configs) | *(empty)* |
| `CMAKE_EXPORT_COMPILE_COMMANDS` | `ON` |
| `CMAKE_SKIP_RPATH` / `CMAKE_SKIP_INSTALL_RPATH` | `NO` / `NO` |
| `CMAKE_VERBOSE_MAKEFILE` | `FALSE` |
| `ENABLE_32BIT` | `OFF` |
| `ENABLE_SYSTEMTAP` | `ON` |
| `WITH_CCI` | `true` |
| `WITH_CMSERVER` | `ON` |
| `WITH_JDBC` | `ON` (no-op: `cubrid-jdbc` is uninitialized) |
| `WITH_BUNDLED_PREFIX` / `WITH_EXTERNAL_PREFIX` / `WITH_SYSTEM_PREFIX` | `BUNDLED` / `EXTERNAL` / `SYSTEM` |
| `WITH_LIBEDIT` / `WITH_LIBEXPAT` / `WITH_LIBJANSSON` / `WITH_LIBOPENSSL` / `WITH_LIBTBB` / `WITH_LIBUNIXODBC` / `WITH_LZ4` / `WITH_RE2` | `EXTERNAL` |
| `WITH_LIBFLEXBISON` | `SYSTEM` |

Corrections to earlier recon, from the authoritative cache: `CMAKE_C_COMPILER` /
`CMAKE_CXX_COMPILER` are the `cc`/`c++` symlinks (not literal `gcc`/`g++`), and the
`RelWithDebInfo` flags are plain `-O2 -g -DNDEBUG` with **no** `-finline-functions` and **no**
`-fdiagnostics-color` — those extras live only in the shared checkout's
`CMakeUserPresets.json`, which was not in play. There is no `FAISS_SIMD_MODE`,
`CMAKE_CXX_STANDARD` or `SUPPORT_XA` entry in the cache.

#### Exact build commands

The previous campaign did **not** invoke `build.sh`. It ran this tooling repo's justfile
`build` recipe (justfile sha256
`8c9092e503291f59fb9e966c1835407ffcd26126200e712cfdb1b1224a2fa2b1`, byte-identical local and
remote), which expands to exactly:

```bash
cd <worktree>
cmake --preset release -DCMAKE_INSTALL_PREFIX="<install-prefix>"
cmake --build "build_preset_release" -j <jobs> --target install
```

`cmake --preset release` resolves, via the tracked `CMakePresets.json`, to generator `Ninja`,
binary dir `${sourceDir}/build_preset_release`, `CMAKE_BUILD_TYPE=RelWithDebInfo`,
`CMAKE_EXPORT_COMPILE_COMMANDS=ON`, `WITH_CCI=true`. The bootstrap log confirms the preset
banner it emitted:

```text
Preset CMake variables:

  CMAKE_BUILD_TYPE="RelWithDebInfo"
  CMAKE_EXPORT_COMPILE_COMMANDS="ON"
  WITH_CCI="true"
```

and the compiler banner `-- The C compiler identification is GNU 8.5.0` /
`-- The CXX compiler identification is GNU 8.5.0`, with
`-- Build CUBRID 11.5.0.2366-607f1ee 64bit RelWithDebInfo on Linux x86_64`. The log contains
no other cmake or ninja command line — the install is driven by the `install` target, not by
a separate `ninja install`.

Campaign-specific invocation (this is the form workers MUST use):

```bash
INSTALL_PREFIX=/home/cubrid/dev/tpch-sspq-impl-r1/install/base \
WORKSPACE=/home/cubrid/dev/tpch-sspq-impl-r1/base-src \
  taskset -c 24-31 just build release
```

- `INSTALL_PREFIX` MUST be set. It both selects the per-variant prefix **and** stops the
  justfile from repointing the `~/CUBRID` symlink. Repointing `~/CUBRID` is FORBIDDEN in this
  campaign: `~/CUBRID` currently points at the previous campaign's install and other
  workloads in this container depend on it.
- The build MUST run under `taskset -c 24-31` per section 3-a, with `-j` matching that band
  (`JOBS=8`). The previous campaign built unconfined at the justfile default
  (`-j $(nproc)` = 32). **Parallelism affects wall time only, not binary content**, so this
  is not a recipe difference; the confinement is required by the CPU contract, not by the
  build.
- The justfile also copies this repo's prebuilt locale files into the install
  (`just install-locale`). That step is part of the replicated recipe and MUST NOT be
  skipped — the all-locales `.so` is required for execution.

#### Install prefix — the one intentional difference

| Variant | Prefix |
|---|---|
| Base | `/home/cubrid/dev/tpch-sspq-impl-r1/install/base` |
| Candidate | `/home/cubrid/dev/tpch-sspq-impl-r1/install/IMP-NNN` |

The previous campaign's prefix was `/home/cubrid/release/CUBRID-tpch-sspq-fk-r1-607f1ee9`.
**Changing `CMAKE_INSTALL_PREFIX` is the ONE intentional configure difference from the
previous campaign, and it MUST be the only one.** Any other configure divergence is a
contract change requiring user approval.

This campaign **builds its own immutable base install** and MUST NOT reuse
`/home/cubrid/release/CUBRID-tpch-sspq-fk-r1-607f1ee9`, nor the `~/CUBRID` symlink, as the
base binary `B`.

#### Reference fingerprints (sanity comparison only)

Previous campaign's install `/home/cubrid/release/CUBRID-tpch-sspq-fk-r1-607f1ee9`:

| Binary | sha256 | ELF Build ID |
|---|---|---|
| `bin/cub_server` | `e5043f0e30cbf4a56f219f833f4f4833687ed774895779450e84550c3d6f2a13` | `4df41ee21300bf617bccd5e1d5c8522b074ef86e` |
| `bin/cub_master` | `2dd85d479561c1631b05b7f04843a9332a41bd756b46a7a4b13a895522279e0e` | `ca3ba5efa3db9141e14b9c8e6d52bf78ee42a378` |
| `bin/csql` | `2a2cc292b473cf8807f088bb62542bdad3d872944c637f681ec9f77159ba1908` | `e6638312c5e37e7e8fa8f16cb6bb74f21fe3ca59` |

These are recorded **as a sanity comparison only**. The build is **not** bit-reproducible —
the install prefix is embedded, paths and timestamps differ, and the ELF Build ID is a link
hash. **Byte-identical binaries are NOT expected and NOT required**, and a mismatch is NOT a
failure. What IS required is that this campaign's base build and **every** patch build use
the identical recipe pinned in this subsection.

#### Pre-build verification (mandatory, every build)

Before running cmake for any variant, the worker MUST assert and record:

1. `git -C <worktree> rev-parse HEAD` resolves to the frozen base SHA, or to a candidate
   commit whose `git diff 607f1ee9f` contains **only** the candidate patch plus
   `implementation-plan.md` (section 6-a), ignoring the known `cubrid-cci` build-artifact
   dirt;
2. `git -C <worktree> submodule status` shows `cubrid-cci` at `2fb8d6d0…` and both
   `cubrid-jdbc` and `cubridmanager` uninitialized (`-` prefix);
3. `sha256sum <worktree>/CMakePresets.json` = `1818a143464bf51eb7a84bcaa5c3fbb3da2c9ce8dab153f3d847e6ac113baacb`;
4. `<worktree>/CMakeUserPresets.json` **does not exist**;
5. `cc --version`, `c++ --version`, `ld -v`, `cmake --version`, `ninja-build --version` match
   the toolchain pins above;
6. after configuring, the generated `build_preset_release/CMakeCache.txt` matches the
   configure-settings table above, differing **only** in `CMAKE_INSTALL_PREFIX`.

Any mismatch ⇒ stop and report; do not build around it.

### 6-b. Correctness gate

Before-and-after canonical results MUST be **EXACTLY equal**:

- queries with `ORDER BY`: the ordered result sequence is compared exactly, including
  order;
- queries without `ORDER BY`: complete rows are canonically sorted and compared with
  **duplicate multiplicity preserved** — results are never converted to a set;
- decimals MUST be equal in **both value and scale**; raw decimal text is preserved;
- NULL, text, date and integer values MUST match exactly; row count and row multiset MUST
  match exactly;
- for Q15, the view MUST be proved absent before and dropped after (object cleanup
  verified).

Because base and patch are the same engine on the same data, there is **no cross-engine
tolerance**. Any difference at all is a failure.

Mandatory checks, all five:

1. a candidate-specific unit or regression test that exercises the changed code path;
2. the target query or queries;
3. every query in the IMP's `q_relations`;
4. a Q01–Q22 full result smoke;
5. for concurrency or memory candidates, separate stress and diagnostic tests
   (assertion-enabled and/or sanitizer build, run outside the performance regime).

Any mismatch ⇒ **stop immediately and escalate**. Do not "investigate around" a
correctness failure and continue measuring.

### 6-c. Performance A/B procedure

- **B** = the immutable base binary at `install/base`. **P** = the patched binary at
  `install/IMP-NNN`.
- Block order is balanced: `B → P → P → B`.
- For **each** block:
  1. restart the campaign server on that block's binary;
  2. pass the affinity / NUMA memory-binding / all-TID / ownership gates of section 3-a
     and 3-b;
  3. prove WARM convergence;
  4. execute **1 uncounted warmup** on one connection;
  5. execute **3 measured runs** on that same connection;
  6. re-verify all-TID affinity and ownership after the block.
- Per measured run, capture: wall time; executor CPU; auxiliary CPU; total CPU;
  cycles, instructions and IPC; the **candidate-specific work event** named in the
  implementation plan; `/proc` I/O counters, buffer counters, temp-file/temp-space usage
  and memory; time-weighted active units (TWU, computed from actual sample timestamp
  deltas, never from a nominal interval) and the serial tail; plan estimated rows versus
  actual rows.

Executor CPU is `cub_server` query threads. Auxiliary CPU is `csql` parse/plan/result
work and attributable background threads. `total_query_cpu = executor + auxiliary`. Work
that cannot be attributed is reported as `unattributed_background` and never silently
folded in.

### 6-d. Statistics

- At least **3 `B-P-P-B` cycles**, giving **6 block medians per variant**.
- The primary estimate is the **paired block-median P/B ratio**.
- The confidence interval is a **paired bootstrap 95% CI** over the block-median pairs.
- The minimum detectable effect is

  ```text
  MDE = max( 1% , 2 × baseline_paired_CV )
  ```

  where `baseline_paired_CV` is the noise floor measured in section 3-c for that query.
- Three values within a block are a dispersion estimate, not a confidence interval. A CI
  is only ever computed across block medians.

---

## 7. Accept / reject / inconclusive criteria

### 7-a. Accepted

ALL of the following MUST hold:

1. every correctness check in section 6-b passes;
2. the paired bootstrap 95% CI lies **entirely below 1.0**;
3. the point improvement is **≥ MDE**;
4. the **expected metric signature moved in the predicted direction** (the named counter,
   event or band from the implementation plan);
5. there is **no non-target regression**.

### 7-b. Inconclusive

The CI still contains 1.0 after a maximum of **12 pairs**. The candidate is recorded as
`inconclusive`, the branch is preserved, and no further pairs are collected without user
direction. An inconclusive result MUST NOT be reported as a small improvement.

### 7-c. Rejected

ANY of the following:

- a correctness failure;
- a significant performance degradation;
- the expected metric signature did not move;
- a significant regression above **3%** on a related query.

### 7-d. Plan-change control

- **Executor, buffer and expression candidates** MUST show the **same plan family and the
  same actual work volume** before and after. If the plan changed, the A/B is invalid and
  is marked `A/B_CONFOUNDED_PLAN_CHANGE`; the result MUST NOT be reported as a patch
  effect until the confound is removed or explained with a controlled plan.
- **Optimizer candidates** are the exception: the natural plan change **is** the
  treatment. For these, the natural-plan A/B is the **primary** result; where a
  plan-family-controlled comparison is possible (hint- or parameter-forced), it is added
  as a **secondary** result. The report MUST label which is which and MUST NOT mix
  natural and controlled denominators in one ratio.

### 7-e. Honest reporting of surprises

A measured effect outside the predicted range is **never hidden**. If the effect is in
the **opposite direction** from the prediction, or diverges from the prediction by **≥2×**
in either direction, the worker MUST perform a root-cause re-examination and report it —
including the possibility that the original evidence attribution was wrong.

---

## 8. GJC / tmux lifecycle and scratch policy

### 8-a. Roles

- The **main interactive session is the controller**. It plans, dispatches and relays.
- All SSH, tmux, engine and Notion work is **dispatched to freshly spawned general-purpose
  subagents**. The controller MUST NOT run recurring monitoring commands inline.
- **Forks are not used** in this campaign.

### 8-b. Remote invocation contract

- SSH alias: `34-ilhansong`.
- Binary: `~/.bun/bin/gjc`, invoked from a non-interactive shell.
- Required environment:

  ```bash
  export BUN_INSTALL="$HOME/.bun"
  export PATH="$BUN_INSTALL/bin:$PATH"
  export PI_STREAM_IDLE_TIMEOUT_MS=300000
  ```

- **One GJC session per query (Phase 1A) or per IMP (Phase 2).**
- **Never two measurement sessions at once.**

If the `gjc session create` call's cwd or environment is not trustworthy, the controller
MUST verify from **inside the tmux body after creation**: the working directory, the IMP
ID, the pinned `impl_ssot_commit`, and that the session reports a `Working` state. A
session whose cwd or pin cannot be proved MUST be removed and recreated.

A dedicated **child tmux driver** — a tmux session spawned solely to host a long-running
block driver so it survives tool-call abort — is recorded as a **worker-owned driver, not
a measurement session**. Its exact name, its parent session and its PID MUST be recorded
in the operational state. `nohup`, `setsid` and disown MUST NOT be used for long-running
drivers; only a detached tmux session survives tool-call teardown.

### 8-c. Worker status block

The worker emits:

```yaml
TPCH_SSPQ_IMPL_STATUS:
  campaign_id: tpch-sspq-impl-r1-20260803
  imp_id: IMP-NNN            # or BASELINE for Phase 1A
  impl_ssot_commit: exact-git-sha
  impl_ssot_blob_sha: exact-blob-sha
  session_id: exact-id
  stage: exact-stage
  state: working|complete|blocked
  branch: impl/tpch-sspq-impl-r1-20260803/IMP-NNN-<slug>
  report_commit: sha-or-null
  verdict: accepted|rejected|inconclusive|null
  artifact_fingerprint: sha256-or-null
  timestamp: ISO-8601
  next_action: exact-action
```

The terminal state is `IMP_COMPLETE` (or `BASELINE_COMPLETE`), not merely an idle prompt.

### 8-d. Session teardown order

Strictly in this order:

1. run the QUERY/IMP completion checklist;
2. confirm the Git report, raw manifest and branch commits exist and are reachable from
   `origin/main`;
3. confirm the Notion sync succeeded, or that a durable backfill record was committed;
4. `gjc session remove <exact-id>`;
5. **only on failure** of step 4, `tmux kill-session -t <exact-id>` on the **exact target
   only** — never by pattern, never by prefix;
6. confirm absence in **both** `gjc session status <exact-id>` and
   `tmux has-session -t <exact-id>`;
7. only then create the next session.

### 8-e. Scratch policy

- **Never** `/tmp`. **Never** `$TMPDIR`. **Never** a hidden directory inside a repository.
- The **only** permitted remote scratch path is:

  ```text
  /data/tpch-sspq/tpch-sspq-impl-r1-20260803/work/<IMP-ID>
  ```

- The campaign raw root is `/data/tpch-sspq/tpch-sspq-impl-r1-20260803`, laid out as
  `raw/<IMP-ID>/` (immutable promoted evidence) and `work/<IMP-ID>/` (temporary).
- Before Phase 1A, the raw root MUST be absent or contain only this campaign's bootstrap
  artifacts. Pre-existing evidence from another campaign blocks bootstrap; it MUST NOT be
  reused and MUST NOT be silently deleted.
- Invalid runs stay under the raw root with an `INVALID.json` stating the reason, and are
  excluded from every calculation.

---

## 9. The 20-minute reconciler

A subagent runs every 20 minutes. It is **idempotent** and it MUST check, in this order:

1. the pinned `tpch-sspq/IMPL-SSOT.md` commit and blob SHA on `origin/main` against the
   session pin;
2. the exact IMP ID and session ID the session is supposed to be running;
3. `gjc session status <exact-id>`;
4. **two** `tmux capture-pane` samples, taken a short interval apart and **compared** — a
   single sample cannot distinguish "working" from "frozen";
5. campaign-owned processes, their CPU and their I/O;
6. CPU-affinity and NUMA state, and the presence of any `cub_server` TID whose affinity
   falls outside the SUT CPU list;
7. forward progress in build output, report and raw manifest;
8. engine branch commits and workspace report commits;
9. origin reachability of the latest durable commit;
10. Notion sync state, or a durable backfill record;
11. the blocker / stall / idle / complete state.

Actions:

- **If the session is `Working`, or a measurement process exists: do not intervene.**
  Not a nudge, not a status question.
- On a **stall** (`anthropic stream stalled` or two identical capture-pane samples with no
  process activity): verify it is the same IMP and the same session, then **resume
  immediately** in that same session.
- Only when the session has **stalled twice consecutively AND no durable artifact advanced
  at all** may the reconciler remove the session, verify absence both ways, and create
  **one** recovery session for the **same IMP**. A recovery session MUST read the existing
  plan, report and raw manifest and continue; it MUST NOT repeat valid measurements.
- On **idle**, run the completion checklist immediately — do not wait for the next poll.
- On `IMPL_SSOT_DRIFT`, allow the running command to finish, preserve artifacts, block new
  stages, and report.
- If Notion is unavailable, mark backfill and continue; Notion never blocks measurement.

Output discipline: emit **nothing** for an unchanged healthy poll. Report only changes,
state transitions and blockers, in **3–5 lines**.

---

## 10. Git, raw, report and Notion synchronization

### 10-a. Git deliverables

```text
tpch-sspq/impl/priority-ranking.md
tpch-sspq/impl/priority-ranking.json
tpch-sspq/impl/implementation-results.json
tpch-sspq/impl/IMP-NNN/report.md
tpch-sspq/impl/IMP-NNN/raw-manifest.json
```

`implementation-results.json` is the campaign-level ledger: one record per IMP with its
verdict, branch, build IDs, measured ratio, CI, report commit and Notion sync state.

### 10-b. Required `report.md` contents

Each `tpch-sspq/impl/IMP-NNN/report.md` MUST contain, in order:

1. **Identity, pins and diff** — IMP ID, lane, campaign ID, pinned IMPL-SSOT commit/blob,
   base SHA, branch name, commit SHA of the patch, and the diffstat;
2. **Actual changed LOC and files** — measured, compared against the plan's estimate band,
   with the 150% check evaluated explicitly;
3. **Correctness** — all five mandatory checks with their outcomes;
4. **Before/after timings** — every block median for B and P, plus the run-level values;
5. **Paired statistics** — the paired block-median ratio, the bootstrap 95% CI, the
   number of pairs, the noise floor and the MDE;
6. **Plan and work-volume stability** — plan family before and after, actual work event
   counts, and whether `A/B_CONFOUNDED_PLAN_CHANGE` applies;
7. **CPU, TWU and profile** — executor/auxiliary/total CPU, TWU and serial tail, and the
   profile bands that moved;
8. **Expected versus measured effect** — the prediction from the implementation plan
   against the measurement, with the section 7-e re-examination if they diverge;
9. **Regressions** — every non-target query checked, with its delta;
10. **Verdict** — `accepted` / `rejected` / `inconclusive`, with the criterion that
    decided it;
11. **Raw evidence index** — in the form
    `claim → raw file:line → formula → evidence type → SHA-256`;
12. **Branch, commit and build IDs** — binary SHA-256 and ELF Build ID for both B and P;
13. **Notion sync state** — synced, or the backfill record's idempotency key.

`raw-manifest.json` records, per artifact: the absolute remote path, byte size, SHA-256,
the creation command, campaign ID, IMP ID, GJC session ID, the pinned IMPL-SSOT
commit/blob, the CUBRID base SHA, validity and invalid reason, artifact type and producing
stage.

### 10-c. Ordering: Git first, Notion second

1. Git commit → push → **verify origin reachability** (section 1-e).
2. **Only then** Notion.

**Notion writes are performed ONLY by a freshly dispatched subagent with Notion tool
access.** The remote GJC worker has no Notion connector and MUST NOT attempt a Notion
write; its responsibility ends at Git commit and push. The controller MUST NOT issue
Notion write calls itself; it dispatches a subagent and relays the result.

### 10-d. Notion write protocol

1. **Fresh fetch immediately before writing** — never write from a stale read.
2. Minimal update.
3. **Server-side refetch after writing**, plus a corruption check: scan for an isolated
   literal `n` token (the symptom of two-glyph `\n` instead of real newlines) and for a
   literal `<` or `&lt;` inside what should be a rendered table. Content MUST be assembled
   with real newline characters; structural markup (`<table>`/`<tr>`/`<td>`, `##`
   headings, code fences) MUST NOT be escaped.

### 10-e. Fields this campaign writes

The Notion improvement-registry data source
`collection://980756de-772e-4e18-8a1b-71ba1cfd11d7` has this **existing** schema, observed
read-only at `2026-08-02T16:33Z`:

| Property | Type |
|---|---|
| `Improvement` | title |
| `IMP ID` | auto_increment_id |
| `Root cause` | text |
| `CUBRID source` | text |
| `PostgreSQL source` | text |
| `Expected effect` | text |
| `Deduplication notes` | text |
| `Priority` | select — `P0`,`P1`,`P2`,`P3` |
| `Difficulty` | select — `Low`,`Medium`,`High`,`Very high` |
| `Risk` | select — `Low`,`Medium`,`High`,`Very high` |
| `Status` | select — `Candidate`,`Measuring`,`Validated`,`Rejected`,`Deferred` |
| `Evidence level` | select — `Direct A/B`,`Attribution`,`Projection`,`Upper bound`,`Lower bound`,`Unmeasured` |
| `Evidence event` | multi_select — `wall`,`CPU seconds`,`cycles`,`instructions`,`IO`,`plan`,`units`,`correctness` |
| `Category` | multi_select — `옵티마이저`,`병렬성`,`표현식·타입`,`버퍼·I/O`,`집계·정렬`,`인덱스`,`중간결과`,`MVCC`,`저장구조` |
| `Queries` | relation → `collection://5d23253e-d89d-44e9-837c-fc98b4042d63` |

This campaign writes **only** the following NEW fields (or, if the data source cannot be
extended, a dedicated `## 구현 캠페인 tpch-sspq-impl-r1-20260803` body section carrying the
same labelled values):

```text
Impl campaign          text     — tpch-sspq-impl-r1-20260803
Impl rank              number   — queue position, or empty for non-Performance lanes
Impl feasibility score number   — 0-100
Impl benefit score     number   — 0-100
Impl total score       number   — 0-100
Impl lane              select   — Performance | Enabler-Predecessor |
                                  Diagnostic-Measurement-correctness | Deferred research
Impl status            select   — Queued | Planned | Implementing | Measuring |
                                  Accepted | Rejected | Inconclusive | Blocked
Impl report            text/url — tpch-sspq/impl/IMP-NNN/report.md at the report commit
Impl measured effect   text     — paired ratio, 95% CI, pair count, MDE
```

**The discovery fields `Priority`, `Difficulty` and `Expected effect` MUST NEVER be
overwritten by this campaign.** They record what the measurement campaign found and they
remain that record. If this campaign's implementation experience contradicts them, the
contradiction is written into `Impl measured effect` and the report — not over the
original field. `Root cause`, `CUBRID source`, `PostgreSQL source`, `Evidence level`,
`Evidence event`, `Category` and `Queries` are likewise read-only to this campaign.
`Status` (the discovery status) is also not overwritten; implementation state lives in
`Impl status`.

Notion **prose MUST be written in Korean**. Identifiers, paths, SHAs, command lines, enum
values and field names stay verbatim in English.

### 10-f. Backfill convention

When a Notion write cannot complete, an idempotent record MUST be appended to
`tpch-sspq/impl/notion_backfill_pending.jsonl`, mirroring the convention of
`tpch-sspq/reports/notion_backfill_pending.jsonl`. The idempotency key is:

```text
campaign_id + IMP-NNN + session_id + report_commit + content_fingerprint
```

The record MUST carry the full intended payload, not a pointer. A pending record is
cleared **only** after a successful server-side refetch confirms the write. Temporary,
local-only or Notion-only state is prohibited: Git is always written first and is always
the source of truth.

---

## 11. Escalation and campaign closeout

### 11-a. Escalation — stop and ask, never decide unilaterally

- changing this IMPL-SSOT or any pin in section 1-c;
- any schema, data or persistent-format change;
- a destructive action outside the explicit cleanup manifest;
- needing to stop another user's process or database;
- a **correctness mismatch** of any size;
- source scope exceeding **150%** of the high LOC estimate;
- an unanticipated **XASL / wire / disk / cache compatibility** change;
- the change widening into the **lock / latch / MVCC protocol**;
- an **unintended A/B plan change** that cannot be controlled away;
- a significant **>3% regression on a non-target query**;
- a measured effect in the **opposite direction** from expectation;
- repeated infrastructure failure after the documented recovery path;
- multiple scientifically valid but materially different implementation options;
- any cumulative merge, or landing anything on CUBRID `main`.

Additionally and explicitly: **if a candidate would change persistent storage format,
catalog format, or a write path, STOP AND REPORT BEFORE IMPLEMENTING.** Not after a
prototype, not after a measurement — before the first line of code.

Reversible implementation details that do not change this contract are decided
automatically. Questions this file already answers MUST NOT be asked.

### 11-b. Closeout

The campaign is complete only when:

1. every IMP in the user-approved queue has a recorded verdict — `accepted`, `rejected`
   or `inconclusive` — with its deciding criterion;
2. the accepted, rejected and inconclusive **branch lists** are published in
   `implementation-results.json`;
3. per-result Git / raw / Notion consistency is verified: every report commit reachable
   from `origin/main`, every raw manifest artifact hash present, every Notion row synced
   or backfilled;
4. **after user approval**, a cumulative branch containing the accepted candidates is
   created from the frozen base SHA;
5. the cumulative branch passes a **base-versus-cumulative Q01–Q22 correctness** run under
   the section 6-b rules;
6. a **cumulative performance A/B** is run under the section 6-c/6-d regime;
7. a final report and final raw manifest are committed, pushed and verified reachable;
8. the absence of all campaign GJC sessions, tmux sessions and campaign processes is
   verified;
9. **merge into any upstream branch waits for explicit user approval.** Producing the
   cumulative branch is not permission to land it.

---

## Revision history

Amendments to this file are a contract change (section 11-a) and are made only on explicit
user approval. Each amendment gets an ID and is listed here; the pinned commit and blob SHA
that every worker verifies (section 1-d) change with each entry.

| ID | Commit | Change |
|---|---|---|
| — | `9a8a86d` | Original: IMPL-SSOT for campaign `tpch-sspq-impl-r1-20260803`, sections 1–11. |
| `AMEND-A` | this commit | Section 3-a rewritten: the isolation mechanism is **`taskset` / `sched_setaffinity` affinity plus `numactl` memory binding**, not cpuset cgroups. Reason: the host is a rootless podman container whose cgroup-v1 `cpuset` hierarchy is flat with zero child cpusets; the previous campaign achieved its isolation purely via affinity, verified on the live `cub_server`. Verified host topology (Xeon Silver 4216, 2×16 cores, 1 thread/core, online `0-31`, node 0 = `0-15`/128565 MB, node 1 = `16-31`/64502 MB) recorded. The CPU assignment table, the 0.5 core-s/s invalidation gate and the non-inheritance of the previous 6.0 core-s/s gate are **unchanged**. Shared-container neighbours declared out of scope. Sections 6-c and 9 reworded to match. |
| `AMEND-B` | this commit | New section 6-a-1 **Build recipe pin**: the campaign replicates the previous campaign's build state (`tpch-sspq-fk-r1-20260730`) rather than deriving it from the base SHA's committed submodule pointers alone. Records literal submodule SHAs and initialization state, the tracked `CMakePresets.json` sha256 with `CMakeUserPresets.json` pinned **absent**, the full `CMakeCache.txt`-derived configure settings, the toolchain pins, the literal cmake/ninja command lines, the per-variant install prefix as the single intentional difference, the reference binary fingerprints as a non-binding sanity comparison, and a mandatory pre-build verification list. |
