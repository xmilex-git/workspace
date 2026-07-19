# DEFECT-OV3 fix: global DWB drain per no-redo page flush, not a per-VPID retire primitive

- Status: Superseded by ADR-0002 (`0002-b2-bulk-pages-take-ordinary-flush-path.md`, 2026-07-16 — the B2 design removes the direct DWB-bypass write entirely, so the drain this ADR justified no longer exists; body preserved for the historical record)
- Date: 2026-07-15

## Context

The no-redo parallel bulk index loader (`btree_load.c`, `BT_LOAD_PROVIDER`) writes real leaf/
non-leaf/overflow content directly, bypassing the double-write buffer (DWB) via
`PGBUF_DWB_FLUSH_SKIP`. A page's earlier allocation-time init image — and any later opportunistic
background/checkpoint flush taken while the page sat dirty and unlatched — goes through the
*ordinary*, DWB-staged path instead. If that stale, DWB-staged copy syncs to the page's final disk
location *after* the direct bypass write, it silently restores a pristine-empty page inside the
finished chain (DEFECT-OV3: checkdb `key_cnt >= 0` assertion; sealed 3/3 repro with DWB on vs 0/3
with DWB off on the identical 8GB `bulkidx_tpl` clone basis).

No VPID-scoped "retire/invalidate this pending DWB entry" primitive exists anywhere in
`double_write_buffer.{c,hpp}` — the only drain primitive, `dwb_flush_force()`, synchronously flushes
the *entire* DWB, not a single VPID's entry. This was confirmed by direct API investigation before
implementing the fix (`.not_git_tracking/bulk_index_build/artifacts/u-g001/phase3-fix/SUMMARY.md`).

## Decision

Fix `[bulkidx] V2-11` calls `dwb_flush_force()` — a global, whole-DWB synchronous drain — inside
`btree_log_page()`'s `no_redo` branch, immediately before every no-redo page's direct bypass flush.
The caller still holds the page's write latch at that point, so no new staging of that specific VPID
can begin before the flush lands, making the direct write provably the last write to reach disk for
that VPID — regardless of how many times the page was staged into DWB earlier in its construction
(allocation-time init image, or any intermediate unfix/refix cycle).

An allocation-time-only variant (flush just the fresh init image once, before publishing a span to
the provider pool) was implemented and empirically falsified first: it still reproduced the defect
2/2 trials on the sealed clone-basis repro (a fourth/fifth distinct VPID), because the hazard is not
confined to the allocation moment — a page can be re-exposed to an ordinary/DWB-mediated flush
attempt at any later unfix during its no-redo construction (`pgbuf_bcb_safe_flush_internal()`'s
write-latch check only *defers* such an attempt when a different thread holds the latch; the
deferred flush still fires with its original DWB policy on the next unfix, whoever's that is).

## Consequences

- **Cost accepted**: `dwb_flush_force()` drains the *entire* DWB on every no-redo page's final flush,
  under 16-way parallel bulk load — a real throughput cost, not scoped to the single VPID being
  written. No narrower fix was found that empirically closes the window (see Considered Options).
  Post-fix TIER-B regression and clone-basis seal timings showed no measurable regression against the
  available baselines this session, but this has not been load-tested at production scale/concurrency
  beyond the sealed repro basis.
- **A future per-VPID DWB retire primitive is the recorded, deliberately-deferred optimization** — do
  not build it speculatively; only if the global drain's cost is later measured to matter at a scale
  this session didn't test.
- **Any future change to this fix's mechanism must re-run the full fail-before-fix seal** (8GB
  `bulkidx_tpl` clone basis, DWB on vs off) before being trusted — code review and unit-level testing
  alone already proved insufficient once in this same investigation (the falsified allocation-time
  attempt compiled cleanly and looked reasonable, but only the expensive seal caught its failure).
- A future per-VPID retire primitive should restore the pgbuf/DWB boundary mediation (btree_load
  currently calls the DWB API directly — accepted for the minimal fix, not a precedent).

## Considered Options

1. **(Chosen) Global `dwb_flush_force()` drain in `btree_log_page`'s `no_redo` branch, at the final
   flush.** Provably closes the window (page is write-latched by the caller at the drain point, so no
   new staging of that VPID can occur before the subsequent bypass write). Cost: global drain,
   per-page, in a hot parallel path.
2. **Allocation-time-only DWB bypass for the init image** (flush once, before span publish).
   Rejected: empirically falsified — reproduced 2/2 on the sealed repro basis. Incomplete coverage:
   only protects the first moment of a page's no-redo lifetime, not later unfix/refix cycles.
3. **A new, per-VPID DWB retire/invalidate primitive.** Would close the window with a narrower cost
   profile, but does not exist today and was out of scope for a minimal fix in this defect slice.
   Recorded as the future optimization, not built.
