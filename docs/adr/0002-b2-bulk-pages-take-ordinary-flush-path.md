# B2: no-redo bulk index pages take the ordinary flush path (content-WAL-only-skip)

- Status: Proposed (boss review; supersedes ADR-0001)
- Date: 2026-07-16

## Context

The no-redo bulk index build originally wrote final bulk page images directly to disk,
bypassing both the WAL-force step and the double-write buffer
(`btree_log_page()`'s `no_redo` branch: `pgbuf_flush_with_wal_policy(..., PGBUF_WAL_FLUSH_SKIP,
PGBUF_DWB_FLUSH_SKIP)`). Mixing that bypass channel with the ordinary, DWB-staged channel used by
the same pages' allocation-time init images produced DEFECT-OV3: a stale DWB-staged copy could land
*after* the direct bypass write and silently restore a pristine-empty page inside a committed chain
(sealed 3/3 repro DWB-on vs 0/3 DWB-off on the 8GB `bulkidx_tpl` clone basis). ADR-0001 sealed that
window with a global `dwb_flush_force()` drain before every no-redo page's direct write — correct,
but it introduced a per-page *global* synchronization point into the hot 16-way parallel path, and
the bypass still left bulk pages without DWB torn-page protection.

A subsequent performance re-review (R8, falsified-then-redone under critic review: the historical
speedups and the R8 numbers were all measured at `double_write_buffer_size=0`, hiding the drain's
cost with DWB on) prompted a design re-decision (36-B2-LogTouchpoint-Review + 37-B2-Plan-Author,
boss-adopted 2026-07-16).

What no-redo actually eliminates is exactly one log record class: the bulk pages' full-page content
redo (`RVBT_COPYPAGE`). Everything else was always still logged: page-init records
(`RVBT_GET_NEWPAGE`, `RVPGBUF_NEW_PAGE`) — the source of each bulk page's REAL init LSA —
file bookkeeping (`RVFL_*`), sector reservations, the sticky-root COPYPAGE publish (exactly 1),
the `RVBT_BULK_BUILD_DURABLE` marker, and the sysop chain.

## Decision

Bulk builds skip **only** the content redo logging. All bulk page disk writes take the **ordinary
flush path** — background flusher, eviction, checkpoint, and DWB staging when enabled —
exactly like any other dirty page (`[bulkidx] B2-01`). The now-dead WAL/DWB flush-policy
machinery (`PGBUF_WAL_FLUSH_POLICY`/`PGBUF_DWB_FLUSH_POLICY`, `pgbuf_flush_with_wal_policy()`)
is removed (`[bulkidx] B2-02`, behavior-neutral: the only SKIP callsite died in B2-01).

Durability before publication comes from a single pre-publication barrier in `xbtree_load_index`,
inside the `no_redo` guard, ordered before the sysop attach / marker / commit chain:

1. `pgbuf_flush_all (thread_p, NULL_VOLID)` — one pass over the buffer pool, flushing every dirty
   frame regardless of volume;
2. `fileio_synchronize_all (thread_p)` — drains the DWB (partial blocks included) and fsyncs every
   permanent volume.

Order matters: pool flush first, DWB drain + fsync second. `fileio_synchronize_all` alone is
insufficient — it never writes pgbuf dirty frames, so without step 1 a marker could become durable
while bulk content was memory-only (silent loss; empirically demonstrated by the §6-L3
minus-barrier negative control).

### Amendment 2026-07-16: B2-S1 scopes the barrier (boss directive)

The global barrier was measured as a fixed 99–345 ms/build cost (I/O-wait-bound, dominated by
the pool sweep and third-party write volume). `[bulkidx] B2-S1` scopes it to the build's own
files while keeping the durability contract bit-for-bit:

1. enumerate the allocated data pages of `{btid->vfid, btid->ovfid}` from their partial/full
   sector tables (`file_get_all_data_sectors`; file-table pages are WAL-logged bookkeeping and
   are masked out),
2. flush each page iff still buffered and dirty (new primitive
   `pgbuf_flush_page_if_exists_and_dirty`; a probe miss proves the page is on disk or
   DWB-staged, because a dirty bcb is never victimized before being flushed),
3. drain the DWB once per build (`dwb_flush_force`, no-op when disabled),
4. fsync only the volumes hosting the files' sectors.

Completeness was proven from source before implementation (all 12 `btree_log_page` callsites
target the two files; the serial overflow-key path is fully WAL-logged; sector tables are the
file's ownership ledger; the barrier runs single-threaded after worker join with no allocation
before the publish chain). Any scoped failure falls back to the global barrier; the hidden
server parameter `bulk_build_scoped_barrier` (default on) forces the global barrier when off;
the empty-index path keeps the global barrier. "Marker durable ⇒ content durable" is unchanged
and was re-proven dynamically (kill sweeps K1–K5, forced multi-volume span with the scoped
log's volid set exactly matching the independently derived span set).

Measured honesty note: at realistic 8M-row scale the scoped-vs-global barrier delta shrinks
(~182 vs ~195 ms) because the build's own dirty pages dominate the pool — the win concentrates
on small/medium builds and on not flushing third-party pages. The remaining parallel-mode gap
vs the V2-11 baseline (+6.7…12.4%) was attributed by measurement to lost parallel write overlap
(V2-11's 16 workers wrote pages concurrently; B2 funnels index-page I/O through single-threaded
channels), NOT to the flush daemon (refuted: worker-wait counters zero, gap persists with the
daemon idle at a 4 GB pool, daemon-thread CPU identical).

### Multi-volume coverage proof (no per-build bookkeeping)

- Flush side: `pgbuf_flush_all_helper`'s skip condition
  `(volid != NULL_VOLID && volid != bufptr->vpid.volid)` is volume-unfiltered at `NULL_VOLID` —
  the barrier does not need to know the affected-volume set at all.
- Sync side: `fileio_synchronize_all` fsyncs **every** permanent volume via
  `fileio_traverse_permanent_volume` after the DWB drain.
- DWB blocks with multi-volume slots are a designed case: per-slot volume descriptors, and every
  touched volume in `flush_volumes_info[]` is fsynced.

Hence initial volumes, mid-build `disk_extend` additions, and generic volumes are all provably
covered with zero tracking.

### Why the init LSA stays (and why equal-LSA restaging is safe)

Bulk pages keep their REAL allocation-time init LSA. It is load-bearing: (a) the first flush's
WAL-force covers only the init LSA and later content changes are unlogged, so
`oldest_unflush_lsa` stays NULL and the WAL-force step cleanly no-ops; (b) checkpoint redo-min
excludes NULL `oldest_unflush_lsa` pages; (c) equal-LSA restagings are the DWB's designed
"flushing to disk without logging" case (slot-hash dedup: same block invalidates the older slot,
different block pre-flushes the older block — the final content always lands last); (d) the
on-disk LSA equals the init LSA, so the restart redo guard blocks re-applying the init record
(no pristine re-initialization of committed pages).

## Consequences

- **OV3 is structurally extinct**, not sealed: with no bypass final-write channel, the
  "stale staged copy lands later" ordering inversion cannot be expressed. The ADR-0001 global
  drain and its per-page global synchronization point are removed with it.
- **Torn-page protection restored**: bulk pages are DWB-protected before and after publication,
  like every ordinary page.
- **Cost accepted (boss decision 2026-07-16)**: with DWB on, every bulk page write is doubled
  through DWB staging (write amplification ~2× on the bulk data volume). The boss ruled this
  acceptable without a separate measurement gate: DWB write amplification is unavoidable by
  design, and real deployments commonly build indexes with DWB off — so the performance gate is
  judged at dwb=0 only (≥90% of the historical parallel speedups; b2-plan-v1 §5 boss amend).
  In exchange: no global per-page drain, parallel scaling restored, and structural immunity
  instead of a sealed race.
- **One barrier cost per build**: `pgbuf_flush_all` scans the pool once and also flushes other
  transactions' dirty pages (checkpoint-class side cost, accepted). A ledger-walk alternative was
  rejected: serial builds have no ledger, and already-victimized clean pages would force
  build-proportional random re-reads.
- Recovery-side machinery is untouched and still required: `RVBT_BULK_BUILD_DURABLE` marker,
  restore cleanup, the D1fix2 bookkeeping-redo exemption class, and the D2 restart guard are all
  orthogonal to how bulk pages reach disk.
- Rollback: B2 is two revertible commits (`git revert B2-02 && git revert B2-01` restores the
  sealed V2-11 fallback exactly).

## Considered Options

1. **(Chosen) Ordinary flush path + single pre-publication flush+sync barrier.** Structural
   elimination of the mixed-channel hazard; torn protection back; two mechanical commits.
2. **Keep V2-11 (per-page global DWB drain before direct bypass write).** Sealed but pays a global
   synchronization point per page in the hot parallel path, keeps bulk pages torn-unprotected, and
   keeps the bypass machinery alive (ADR-0001 — superseded).
3. **Per-VPID DWB retire primitive.** ADR-0001's deferred optimization; irrelevant under B2 (there
   is no bypass write to order against). Not built.
4. **Ledger-walk barrier (flush only the build's own pages).** Rejected: parallel-only (no serial
   ledger) and forces disk re-reads of victimized clean pages; `pgbuf_flush_all` is one pool scan
   with dirty-only I/O.
5. **P2 LSA-stamp variant.** Deferred (follow-up ticket): B2 restores DWB torn protection, real
   init LSAs leave no zero-LSA blind spot; minimal-diff wins.
