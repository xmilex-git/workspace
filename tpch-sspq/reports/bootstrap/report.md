# TPCH-SSPQ FK campaign — bootstrap report

Campaign ID: `tpch-sspq-fk-r1-20260730`
SSOT commit: `1d6a5ea6ddaf03fe6d89e986c41433f667257aa7`
SSOT blob: `fe21c548d52bb1490b271d9bbcef5722b82f7157`
Raw root: `/data/tpch-sspq/tpch-sspq-fk-r1-20260730`

## 1. Identity

| Engine | Source SHA | Install prefix | Binary SHA-256 | ELF Build ID |
|---|---|---|---|---|
| CUBRID | `607f1ee9fb2394de129e083602c84a6525fc685c` (incl. PR #7441 `b334446d6`) | `/home/cubrid/release/CUBRID-tpch-sspq-fk-r1-607f1ee9` | `e5043f0e30cbf4a56f219f833f4f4833687ed774895779450e84550c3d6f2a13` | `4df41ee21300bf617bccd5e1d5c8522b074ef86e` |
| PostgreSQL | `5713b437abed7085e7d59849c6e9e0f4f469633d` | `/home/cubrid/pg/pg20devel-5713b437` | `f55cd1d705d0bc1656709d88ecdd8b7b5cf49706095022ec27fb745357b6602b` | `5f2cb2987765c612638c278f85cfc85c211fffe1` |

Both source SHAs were verified with a live `git rev-parse HEAD` against their respective build checkouts (not directory-name inference); PR #7441 confirmed as an ancestor of the CUBRID HEAD via `git merge-base --is-ancestor`. Full build details (compiler/linker, configure args, assertions/JIT state) are in `build-manifest.json`, frozen per SSOT.md section 3.

Ownership gate (SSOT section 10): `cub_master`/`cub_server` and `postmaster` both resolve via `/proc/<pid>/exe` to the pinned campaign binaries above, running against campaign-only `CUBRID_DATABASES`/`PGDATA` prefixes. No conflicting or unknown process was found on either engine's port.

## 2. Schema (SSOT section 7)

All 8 named foreign keys and their 8 corresponding child B-tree indexes were applied on both engines per `schema/fk-cubrid.sql` / `schema/fk-postgresql.sql` (apply logs: `cubrid-fk-apply.log`/`.exit`=0, `postgresql-fk-apply.log`/`.exit`=0). Post-apply catalog dumps (`cubrid-post-schema.txt`, `cubrid-post-indexes.txt`, `postgresql-post-schema.txt`) confirm exact child-column order and index method for every constraint, including the composite `fk_lineitem_partsupp (l_partkey, l_suppkey)`.

Zero-violation proof: a per-FK anti-join count (child rows with no matching parent) was run live against both engines. All 8 counts are 0 on both engines. Evidence: `cubrid-fk-violations.log` (SHA-256 `b79f6d9deb3ee441b18421b0acad913c0edad71479454b7c481249172cf04f1b`), `postgresql-fk-violations.log` (SHA-256 `c5b9b42fc50c0a8029c8ccea7f9af4c5ddd2d53def6764a04e5d49a5cf39c8af`). PostgreSQL's `pg_constraint.convalidated = true` for all 8 rows.

## 3. Statistics (SSOT section 8)

**Gap found and fixed during bootstrap**: `cubrid.conf` was missing `update_statistics_update_histogram`, `parallelism`, and `max_parallel_workers`. These were added (`update_statistics_update_histogram=yes`, `parallelism=6`, `max_parallel_workers=100`) and the server was restarted through the mandated `cubrid-server-ctl.sh` wrapper (exit 0); identity was re-verified post-restart. A backup of the prior config was kept as `cubrid.conf.pre-stats-contract.bak` on the remote host.

`UPDATE STATISTICS ... WITH FULLSCAN` was then run on all 8 CUBRID tables (`cubrid-update-stats.log`, exit 0) and `ANALYZE VERBOSE` on all 8 PostgreSQL tables (`postgresql-analyze.log`, exit 0, `pg_stat_user_tables.last_analyze` timestamps confirmed fresh).

**Histogram bucket count is `UNMEASURED`.** CUBRID 11.5.0 stores per-column histograms as an opaque serialized `VARBIT` blob in `_db_histogram.histogram_values` with no SQL-exposed bucket-count field or child catalog — decoding it would require reverse-engineering an undocumented binary format, which risks fabricating a number. Target bucket count (300, per SSOT) is configured and confirmed via `cubrid.conf`; NDV-based catalog evidence (e.g. `nation.n_regionkey` NDV=5) is recorded as a secondary signal that low-cardinality columns behave as SSOT expects (fewer effective buckets than target).

## 4. Query provenance (SSOT section 6)

All 22 canonical CUBRID query files (Q01–Q22, with Q15 split into `q15_create_view`/`q15_select`/`q15_drop_view`) byte-match the canonical source at `/home/cubrid/dev/cubrid/.vscode/TPC-H/scale10/queries/` — SHA-256-verified, zero mismatches. All PostgreSQL dialect files contain only pure syntax translations: `DATE_ADD`/`DATE_SUB(...)` → standard `date ± interval 'n' unit` arithmetic (9 queries), and one bracket-to-double-quote identifier fix in Q11. None are hints, join reordering, subquery rewrites, extra predicates, or semantic casts. Each non-empty `queries/diff/*.diff` now carries a one-line `# Reason:` annotation (added during this bootstrap pass — the diffs previously lacked the SSOT-required reason).

## 5. Correctness gate — Q01–Q22 result-equivalence smoke (SSOT section 11)

**All 22 QNNs (Q15 counted once) = `result-equivalent-at-SF10`. Zero mismatches, zero censored.**

Harness: `harness/smoke_check.py` (committed this bootstrap). Enforces a hard 300-second cap per query via `subprocess.run(..., timeout=300)` on both engines; never triggered (largest observed gap ~150s on Q18→Q19). Full smoke run took ~14.5 minutes wall time. Ordered queries compared as exact sequences; unordered queries canonically sorted with duplicate multiplicity preserved; numeric fields compared with `abs(a-b) ≤ 1e-12 × max(1,|a|,|b|)` tolerance only, never applied to non-numeric fields. Q15's view (`revenue0`) was confirmed absent before `create_view` and absent again after `drop_view`, on both engines.

Per-query row counts and evidence files are recorded in `raw-manifest.json` (`smoke_query_output` / `smoke_summary` artifact types) and the raw evidence itself lives under `work/smoke/*.out` and `work/smoke/smoke-summary.json` on the raw root.

## 6. Evidence index

`claim → raw file:line → formula → evidence type → SHA-256`, see `raw-manifest.json` for the full indexed list (byte size + SHA-256 per artifact). Representative entries:

- FK zero-violation, CUBRID → `cubrid-fk-violations.log` → per-FK anti-join COUNT(*) → direct A/B → `b79f6d9d...`
- FK zero-violation, PostgreSQL → `postgresql-fk-violations.log` → per-FK anti-join COUNT(*) → direct A/B → `c5b9b42f...`
- Q01–Q22 correctness → `work/smoke/smoke-summary.json` → per-query row/sequence comparison → direct A/B → `ce10b4dd...`

## 7. Notion sync

Notion master page structure (disposal record, Q1–22 database, empty improvement-registry mirror, operational-state page) was already present from a prior bootstrap attempt. The operational-state page was stale (referenced commit `3351320`, phase `BOOTSTRAP_CUBRID_BUILD_RUNNING`) and is updated as part of this bootstrap's completion to reflect the pinned SSOT commit and `BOOTSTRAP_COMPLETE` phase.

## 8. Completion checklist

- [x] Active-tree allowlist verified, local/remote synced and pinned
- [x] Raw root contains only campaign-matching artifacts, no stale content
- [x] `reports/improvement-registry.json` created (empty, `next_id: IMP-001`)
- [x] Build manifest written and frozen (`reports/bootstrap/build-manifest.json`)
- [x] 8 FK + 8 child B-tree parity verified both engines, zero violations proven live
- [x] Statistics contract fulfilled (CUBRID histogram config fixed + fullscan rebuild; PostgreSQL ANALYZE); bucket count explicitly `UNMEASURED` with documented reason
- [x] Canonical query SHA-256 verified for all 22 queries; dialect diffs carry required reason annotations
- [x] Q01–Q22 result-equivalence smoke: 22/22 `result-equivalent-at-SF10`
- [ ] This report, manifest, and registry committed and pushed to `origin/main` (in progress — this commit)
- [ ] Notion operational-state page refreshed post-push
- [ ] Q01 GJC session created only after the above two are durable
