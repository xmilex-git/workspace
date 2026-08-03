# Campaign pause record — `tpch-sspq-impl-r1-20260803`

**Paused at:** 2026-08-03, by user instruction, to do implementation work elsewhere.
**Phase reached:** Phase 1A (fresh baseline) — in progress, not complete.
**Phase 2 status:** NOT STARTED. No engine source was modified, no candidate branch or
worktree was created, no patch was built. The Phase 1 ranking has not been produced and
therefore has not been approved.

This document is written in English to match the campaign corpus (`SSOT.md`, `IMPL-SSOT.md`,
the 22 per-query reports). It is the resume point. Read it together with the pinned
`tpch-sspq/IMPL-SSOT.md`.

---

## 1. The pin

| Field | Value |
|---|---|
| Pinned norm | `tpch-sspq/IMPL-SSOT.md` |
| Commit | `eccdd1ae58cd733ed3121585146d68b9ae54a73f` |
| Blob | `15b42ddca521444fa54b34b0fa8477ed2df643f6` |
| Lines | 1653 |
| Amendments in force | `AMEND-A` … `AMEND-G` |

Verify before acting, per section 1-d:

```bash
git -C <repo> fetch origin
git -C <repo> rev-parse eccdd1a:tpch-sspq/IMPL-SSOT.md   # -> 15b42ddc...
git -C <repo> merge-base --is-ancestor eccdd1a origin/main && echo REACHABLE
```

### Pin history

| Commit | Content |
|---|---|
| `9a8a86d` | IMPL-SSOT created (928 lines, 11 sections) |
| `783d2f0` | `AMEND-A` taskset affinity isolation (container has no child cpusets); `AMEND-B` pinned replicated build recipe |
| `ed6fb39` | `AMEND-C` runtime `cubrid.conf` pin; `AMEND-D` gate returned to 6.0 core-s/s; `AMEND-E` deterministic Phase 1A driver |
| `2de2404` | `AMEND-F` triage adjustments as ranking input, `external_tracking` lane, upstream scope-check gate |
| `eccdd1a` | `AMEND-G` fast Phase 1A regime (single server instance) with restart-variance calibration |

### Frozen references

| Item | Value |
|---|---|
| CUBRID base SHA | `607f1ee9fb2394de129e083602c84a6525fc685c` |
| PostgreSQL reference SHA | `5713b437abed7085e7d59849c6e9e0f4f469633d` |
| Improvement registry blob | `c38591819f8b34f52b6832d7fda41bc54a0077ba` |
| Registry contents | IMP-001 … IMP-031, no gaps, no duplicates, `next_id=IMP-032` |

---

## 2. What was completed

### 2.1 Environment (done, durable)

- Previous FK campaign's `cub_server tpch_sf10_q1` and `postgres` were stopped with user
  approval; SUT CPUs `0-15` freed. PostgreSQL data directory (20 G) preserved intact.
- Campaign directory skeleton created:
  `/home/cubrid/dev/tpch-sspq-impl-r1/{base-src,worktrees,install}` and
  `/data/tpch-sspq/tpch-sspq-impl-r1-20260803/{raw,work,prep}`.
- Provenance: `/data/tpch-sspq/tpch-sspq-impl-r1-20260803/prep/prep-record.txt`.

### 2.2 Immutable base install (done, durable — do not rebuild)

| Item | Value |
|---|---|
| Worktree | `/home/cubrid/dev/tpch-sspq-impl-r1/base-src` @ `607f1ee9f`, detached |
| Install | `/home/cubrid/dev/tpch-sspq-impl-r1/install/base` (715 M) |
| `cub_server` sha256 | `16abc26afa1db16992b6213ecc02adc193d674eb8ba91f0963ae414abd953199` |
| `cub_server` Build ID | `af122f60daeddc3179fe31cd6b9b490f8ebb3f2a` |
| Version | `CUBRID 11.5.0 (11.5.0.2366-607f1ee) 64bit release` |
| Installed `cubrid.conf` sha256 | `ad19f5ac1e7e983e4a0b1c113d21e25e096d02d3160445f9d10a2e8b6d9cb9ff` |

Recipe replication was **proven**: the `CMakeCache.txt` differs from the previous campaign's
in exactly 6 of 276 lines, all path-derived (`CMAKE_INSTALL_PREFIX` plus five paths that
follow from a different worktree location). No compiler, flag, generator, toggle,
dependency-source or linker-flag difference. Binary sha256 differs from the previous
campaign's, which is expected and not a defect — the prefix is embedded and the Build ID is
a link hash; section 6-a-1 states byte-identity is neither expected nor required.

`~/CUBRID` still points at the previous campaign's install and **must not be used or
repointed**. Submodules replicate the previous campaign exactly: `cubrid-cci` initialized at
`2fb8d6d02c41386be0d56c3cfc6a14ad7e17ac15`, `cubrid-jdbc` and `cubridmanager` left
uninitialized (hence no `install/base/jdbc/`).

Provenance: `/data/tpch-sspq/tpch-sspq-impl-r1-20260803/prep/base-build-record.txt`.

### 2.3 Phase 1B feasibility assessment (done — `tpch-sspq/impl/feasibility-assessment.json`)

All 31 candidates assessed by direct read-only source inspection at the base SHA. Feasibility
scores span 12.8–86.7, median 49.5.

Lane split: `performance` 23, `enabler` 1 (IMP-005), `diagnostic` 1 (IMP-017),
`deferred_research` 6 (IMP-002, 007, 011, 020, 026, 028).

Structural findings that constrain the queue:

- **No candidate changes a persistent storage or catalog format.**
- **Write path** (stop-and-report before implementing): IMP-002, 007, 010, 013, 018.
- **XASL serialization** (independent hard stop, section 5-d): IMP-006, 023, 024, 028.
  IMP-001 is adjacent — `aggregate_accumulator` is packed at `xasl_to_stream.c:5567-5581`,
  so its new state must stay runtime-only or it joins this list.
- **Missing prerequisites in CUBRID, not merely difficult**: IMP-028 (semi/anti join absent,
  0 grep hits tree-wide), IMP-002 (no `BufferAccessStrategy` equivalent, 0 hits),
  IMP-007 (no async I/O infrastructure; `fileio_read_pages` is log/DWB-only).
- **Exclusivity and ordering**: IMP-002 ⟂ IMP-007; IMP-003 ⊃ IMP-004; IMP-015 ⟂ IMP-016;
  IMP-017 → IMP-016; IMP-005 → IMP-009, IMP-012 (also same 176-line file, must be
  sequenced); IMP-014 ⊃ IMP-011 on Q09; IMP-028 ⊃ IMP-031;
  **IMP-021 ⊃ IMP-015, IMP-023** (it removes the workload they accelerate — order matters or
  the first two are measured and then rendered moot); IMP-003 / IMP-022 edit the same
  function region and conflict under the one-branch rule.
- **Registry `difficulty` disagreements**: IMP-010 (one line, but hands a single-owner
  private LRU list to N pooled workers — risk-dominated), IMP-030 (the replacement is *more*
  accurate than the current string round-trip, so "results unchanged" cannot be the
  acceptance criterion), IMP-023 / IMP-027 (new components, not tweaks), IMP-019, IMP-018.
- **Three registry "predecessors" are not build-order dependencies**: IMP-002→010,
  IMP-008→020, IMP-001→030 are re-scoping notes.

### 2.4 Triage adjustments (done — `tpch-sspq/impl/triage-adjustments.{json,md}`)

From a user-led triage of the Notion evidence, normative under `AMEND-F` section 2-b-1.

| ID | Adjustment |
|---|---|
| IMP-001 | `BENEFIT_PENDING_DENOMINATOR` — prototype measured ≈13%, refuting removal of the full 62.35% band. **Blocked on one datum: whether 13% is wall or CPU.** No numeric benefit score, no rank position until resolved. Not rejected. |
| IMP-002 | `BENEFIT_CONFOUNDED` — the Q04 1.160 core-s attribution is confounded with the IMP-018 mechanism; effective evidence weight 0.00 until IMP-018 and IMP-010 are fixed. Independent of its `deferred_research` reason. |
| IMP-012 | `PRIORITY_DISAGREEMENT` — 0.138 s projection does not support the registry's P0. Discovery `Priority` left untouched. |
| IMP-013 | `BENEFIT_BASIS_CORRECTED` — use the realistic 0.47 core-s target, not the 32.7% band upper bound. |

Lane/status: IMP-028 and IMP-025 → `external_tracking` (PR #7533); IMP-007 →
`external_tracking`, status `watch` (CBRD-26788). All excluded from self-implementation.

Upstream scope-check gate before starting: IMP-003, 022, 019, 011, 014 against CBRD-27127,
CBRD-27036, CBRD-27037, CBRD-27094, CBRD-27113 and PR #7453. **Recorded set-to-set** — no
per-candidate mapping was supplied, so each gated candidate is checked against all six.

Evidence confirmed sound in triage: IMP-027, 011, 014, 015, 018, 010.

Preserved tension, deliberately unresolved: IMP-011 and IMP-014 appear in both the
scope-gate list and the evidence-sound list. Both hold — sound evidence does not exempt a
candidate from the gate.

### 2.5 IMP-015 implementation spec

`tpch-sspq/impl/IMP-015-implementation-spec.md` (commit `eacebcf`) was contributed from a
separate grilling session (decisions D1–D5). It was **not** produced by this campaign's
Phase 1 and has not been reconciled against the ranking, which does not yet exist.

---

## 3. What is INCOMPLETE

### 3.1 Phase 1A fresh baseline — the blocking item

**No usable campaign baseline exists.** Two regimes were attempted.

**Restart regime (superseded by `AMEND-G`, retained as calibration evidence):**

- `/data/tpch-sspq/tpch-sspq-impl-r1-20260803/raw-restart-calibration/` — 323 files
- Q01–Q05: 6 accepted blocks each. **Q06: 5 accepted** (block 5 invalidated —
  `WARM_NOT_CONVERGED` on attempts 1/2/4, `INVALID_BACKGROUND_LOAD` on attempt 3 at external
  mean 5.997 / p95 6.466 / max 6.944 core-s/s). **Q07: 1 block, no reference capture —
  unusable.**
- Total **35 accepted blocks**, walls spanning 0.353 s (Q02) to 31.19 s (Q01).
- Attempt-level discards, visible only in the driver log: 50 attempts, 35 accepted,
  **14 discarded** (12 `WARM_NOT_CONVERGED`, 2 `INVALID_BACKGROUND_LOAD`). Roughly one
  attempt in four is discarded on this host — this matters for Phase 2 cycle planning and
  for the risk of hitting the 12-pair inconclusive ceiling.
- The set spans a mid-run re-pin (`ed6fb39` → `2de2404`, harness switched 04:43:25Z).
  Sections 3/6/7/8/9 are byte-identical across those blobs, so there is no measurement
  impact. Evidence: `work/BASELINE/repin-record.json`.

**Fast regime (`AMEND-G`, the regime to resume with): NOT STARTED.**
`/data/tpch-sspq/tpch-sspq-impl-r1-20260803/raw/` contains **0 files**. The driver script and
the sweep had not begun when the pause was called.

### 3.2 Phase 1B ranking — not started

`priority-ranking.md` / `.json` do not exist. Benefit scores, total scores, the sensitivity
ranking and the `UNPROVABLE_ON_THIS_HOST` determinations all require the Phase 1A baseline.

### 3.3 Notion — not synced

No `Impl *` field has been written. The nine fields named in section 10-e do not yet exist on
the Notion data source; section 10-e provides a body-section fallback if the data source
cannot be extended. Discovery fields (`Priority`, `Difficulty`, `Expected effect`, `Status`,
`Evidence level`, `Evidence event`, `Category`, `Queries`) must never be overwritten.

---

## 4. Why the regime changed (do not re-derive)

Under the restart regime, per-query cost measured out at roughly
`6 × (49 s + 33.7 × query_wall)`. Only 4 executions per block are measured (1 uncounted
warmup + 3 measured); the remaining ~30 execution-equivalents were **WARM re-convergence**,
because every block restarted the server and emptied the 8192M data buffer. Restart itself
was only ~49 s × 132 blocks ≈ 1.8 h of a ~16 h projection. Q01 ran ≈ 9 min/block, of which
12 of 16 statements were uncounted warm-up.

`AMEND-G` therefore moves Phase 1A to one continuous server instance, WARM established once
per query, 6 blocks × (1 uncounted warmup + 3 measured) with no restart between blocks.
Projected per-query cost `~202 × wall` → `~34 × wall`; projected sweep ≈ 2.5–3 h.

**The statistical cost, and why the calibration exists:** per-block restart is what made
blocks independent. Six blocks on one warm instance share buffer state, so paired CV — and
therefore `MDE = max(1%, 2 × baseline paired CV)` — comes out optimistically small. Phase 2's
`B → P → P → B` A/B **cannot** avoid restarts because it swaps binaries, so an MDE derived
from a restart-free baseline would understate real A/B noise and cause false accepts. The
Q01–Q06 restart-regime data is re-measured under the fast regime, the CV ratio yields an
inflation factor, and that factor corrects the fast-regime CVs of all queries. Phase 2 accept
decisions use the inflated MDE. **Without this correction the campaign over-accepts.**

---

## 5. Environment knowledge (verified — do not rediscover)

- Host is a **rootless podman container**. cgroup v1, flat `cpuset` hierarchy, zero child
  cpusets. Isolation is `taskset` + `numactl`, never cpuset cgroups.
- Xeon Silver 4216, 2×16 cores, 1 thread/core, online CPUs `0-31`.
  **NUMA node 0 = CPUs 0-15 (128565 MB); node 1 = CPUs 16-31 (64502 MB).**
- CPU contract: SUT/client `0-15` + `--membind=0`; collector `20-23`; controller/compiler
  `24-31`; `16-19` separation band.
- **Affinity must wrap the wrapper**: `taskset -c 0-15 numactl --membind=0
  cubrid-server-ctl.sh start`. `resources.cpp:190` caches the mask in a function-local static
  at server start, so post-hoc `taskset` provably cannot work.
- **TID count is time-dependent**: ~26–32 immediately after start, ~126–132 once the pool has
  grown. An all-TID check right after start is not equivalent to one taken later.
- 8192M allocates fine even when `numactl -H` shows node 0 free ≈ 4 GB; reclaim covers it.
  Zero memory failures in 36 blocks.
- **External CPU load is real work outside the container** (`steal == 0`, container-visible
  `ps` ≈ 10%). Measured with zero campaign processes: mean 1.94, p95 10.02, max 16.03
  core-s/s. This is why the gate is 6.0 and not 0.5 (`AMEND-D`), and why the gate does not
  guarantee the environment can resolve small effects.
- **Never pipe a `cubrid` command** — it hangs forever. Redirect to a file with `timeout` and
  `</dev/null`. `cubrid service stop` exits **1** on this install because of the not-running
  broker and not-installed manager sub-steps; key on `++ cubrid master stop: success`.
- Out-of-scope neighbours, never to be stopped or re-pinned: tmux `1gjc`, tmux `claude`, the
  codex stack, the gjc bun daemons, VTune, tradingcodex. They are pinned to `24-31` and do
  not contend with the SUT.
- `just` is not on the remote non-interactive PATH; it is at `/home/cubrid/.local/bin/just`.
- `csql` drops `csql.err` into the cwd, polluting the harness directory.
- Invariants: plan estimate = `SET OPTIMIZATION LEVEL 514`; actuals = `SET TRACE ON` +
  `SHOW TRACE`; statement time regex `\((\d+\.\d+) sec\) Committed`; `perf stat -p <pid>` +
  SIGINT works (perf 4.18); server start ≈ 30–45 s.
- Campaign temp dir is `/data/tpch-sspq/tpch-sspq-impl-r1-20260803/work/tmp`. Never `/tmp`
  or `$TMPDIR` — the host's `/tmp` is tmpfs-backed.

### WARM gate parameters — per query, `window / level_tol / spread_sanity / max_statements`

Q01 4/0.02/0.05/12 · Q02 4/0.02/0.05/40 · Q03 4/0.02/0.05/20 · Q04 4/0.01/0.03/20 ·
Q05 4/0.04/0.07/24 · Q06 4/0.04/0.07/40 · Q07 4/0.04/0.07/16 · Q08 4/0.03/0.05/40 ·
Q09 4/0.03/0.05/20 · Q10 4/0.03/0.05/20 · Q11 6/0.03/0.05/20 · Q12 6/0.02/0.05/20 ·
Q13 6/0.01/0.05/20 · Q14 6/0.02/0.05/22 · Q15 4/0.01/0.03/20 · Q16 6/0.015/0.05/30 ·
Q17 6/0.03/0.07/40 · Q18 4/0.02/0.045/12 · Q19 4/0.02/0.045/12 · Q20 4/0.02/0.06/20 ·
Q21 4/0.01/0.03/12 · Q22 4/0.01/0.03/20

Q15's unit is the logical session, not the statement. **Q05/Q06/Q07 tolerances were widened
to 0.04/0.07** (decision D1 in `harness/warm_params.json`) because the previous campaign's
values failed to converge; 0.04 sits above the measured n=20 stationary null max of 3.49% and
well below the 13.17% warming signal. This is a methodology choice and must remain visible in
the eventual baseline report.

### Known documentation defect

Section 8-b's harness table is **still understated**: `CUBRID_TMP=/tmp` appears in **6**
files (add `telemetry_run.py:24`, `q15_session.py:54` to the four listed) and `CAMPAIGN`
appears in **7** locations (add `headline_run.py:24`, `telemetry_run.py:26` to the five
listed). Correct this in the next amendment.

---

## 6. Artifacts

### In Git (`origin/main`)

| Path | Content |
|---|---|
| `tpch-sspq/IMPL-SSOT.md` | the pinned norm, 1653 lines, `AMEND-A`…`AMEND-G` |
| `tpch-sspq/impl/feasibility-assessment.json` | 31 candidates, feasibility half of the ranking |
| `tpch-sspq/impl/triage-adjustments.json` / `.md` | benefit adjustments, lane changes, scope gates |
| `tpch-sspq/impl/IMP-015-implementation-spec.md` | from a separate session, not reconciled |
| `tpch-sspq/impl/CAMPAIGN-PAUSE.md` | this document |

### On the remote

| Path | Content |
|---|---|
| `/home/cubrid/dev/tpch-sspq-impl-r1/base-src` | base worktree @ `607f1ee9f` |
| `/home/cubrid/dev/tpch-sspq-impl-r1/install/base` | immutable base install |
| `/home/cubrid/dev/tpch-sspq-impl-r1/harness/` | campaign-local harness (~21 files) |
| `/data/.../prep/` | `prep-record.txt`, `base-build-record.txt`, stop and build logs |
| `/data/.../raw-restart-calibration/` | 323 files, Q01–Q06 + partial Q07, README |
| `/data/.../raw/` | **empty** — the fast-regime sweep never ran |
| `/data/.../work/BASELINE/` | driver logs, `repin-record.json`, probe traces |

---

## 7. Open items requiring the user

1. **IMP-001 denominator** — is the internal prototype's ≈13% a **wall** or a **CPU**
   reduction? `expected_saved_seconds` multiplies a wall median, so applying a CPU-side
   figure would overstate the benefit, possibly by a large factor. IMP-001 has no benefit
   score and no rank position until this is answered.
2. **Upstream ticket mapping** — CBRD-27127 / 27036 / 27037 / 27094 / 27113 and PR #7453 are
   recorded set-to-set against IMP-003 / 022 / 019 / 011 / 014. A per-candidate mapping would
   narrow the gate.
3. **`external_tracking` closeout (OQ-F4)** — section 11-b has no step that discharges the
   tracking obligation. Before closeout the campaign must confirm whether PR #7533 merged
   (IMP-025, IMP-028) and how CBRD-26788 resolved (IMP-007).
4. **Phase 2 approval** — the Phase 1 ranking and candidate queue have not been produced, so
   nothing has been approved. Phase 2 must not begin until they are.

---

## 8. How to resume

1. Verify the pin (section 1 above). Read `tpch-sspq/IMPL-SSOT.md` in full — it is the
   authority, and it has repeatedly proven more accurate than dispatch prompts.
2. Confirm the remote is clean: no `cub_server` / `cub_master` / `csql`, ports 1523 and 5442
   free, no campaign tmux session, and `raw-restart-calibration/` still holding 323 files.
   Do not disturb the out-of-scope neighbours.
3. Run the **fast-regime Phase 1A sweep** per `AMEND-G`: a single resumable script, one
   server instance, Q01–Q06 first so the calibration comparison lands early, then Q07–Q22.
   Commit the campaign-local harness — it is still untracked in git, so the measurement is
   currently irreproducible.
4. Derive the restart-variance inflation factor from Q01–Q06 (both regimes) and produce
   `fresh-baseline.json`, `fresh-baseline.md` and `restart-variance-calibration.json`,
   including per-query paired CV and **corrected** MDE.
5. Produce the Phase 1B ranking from three inputs: `feasibility-assessment.json`,
   `triage-adjustments.json`, and the fresh baseline. Flag any candidate whose predicted
   effect falls below its target queries' corrected MDE as `UNPROVABLE_ON_THIS_HOST`.
6. Sync Notion using the `Impl *` fields only, then report the ranking and the candidate
   queue and **wait for user approval** before any Phase 2 work.

**Do not begin Phase 2 implementation without that approval.**
