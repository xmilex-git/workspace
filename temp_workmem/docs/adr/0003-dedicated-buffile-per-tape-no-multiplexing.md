---
status: accepted
---

# Spill backing: per-worker private file, pgbuf-bypassed, addressed by page offset

> Terminology revised in #143; identifiers herein are historical. See CONTEXT.md appendix.

## Context

ADR 0002 makes worker outputs a logical Tapeset addressed by Tape-relative positions.
This ADR fixes how a Tape is physically backed, addressed, and distributed for parallel
read.

Facts that drive the decision:

- The #62 regression came from the raw-fd backing's *global page registry + per-tuple
  dirty-mark lock + double spill* — not from bypassing the shared buffer pool itself.
- Routing temp pages through the shared data buffer pool pollutes its LRU (FAIL-09).
- CUBRID list pages are never deallocated individually mid-life: `qfile_truncate_list`
  resets the whole list (`file_temp_truncate`), and random writes
  (`sort_split_input_temp_file` header rewrites, in-place column updates) never free pages
  or punch holes. A live list's data pages are therefore a dense sequence `0..N-1`.
- The existing per-sector page bitmap (`qfile_collect_list_sector_info`) exists only
  because the old backing allocates pages in shared temp-volume sectors interleaved with
  FTAB pages — it masks the list's data pages out of shared sectors. It is not a
  dealloc-hole tracker.

## Decision

A Tape's spilled pages live in a **per-worker private file** that **bypasses the shared
buffer pool entirely** — its own buffer + fd, owner-only writes, one dirty bit, batched
flush (PostgreSQL BufFile semantics). No shared page registry, no per-tuple lock, and the
pages never enter a pgbuf BCB.

- **Addressing is pure page-offset arithmetic.** A Tape's logical page space is
  `[membuf prefix in RAM] ++ [private-file pages]`; logical page N is `membuf[N]` for the
  prefix, else file offset `(N − prefix_count) × pagesize`. **No page directory, no sector
  list, no occupancy bitmap** — justified by "no mid-life dealloc + private flat file" (the
  file holds only this Tape's pages; no FTAB interleaving).
- **Parallel-read distribution is 64-page offset ranges**, handed out by an atomic
  `fetch_add` over the range index (work-stealing). The membuf prefix is claimed once via
  CAS; disk ranges are stolen by offset.
- **No sector scan, no per-sector bitmap, no sector prefetch.** Per-Tape sequential
  read-ahead in the private backing replaces sector prefetch.
- A worker owns **one private file per output Tape it produces**, not one per worker: sort
  emits one Tape; partitioning operators emit one Tape per (worker, partition/column) —
  see ADR 0004. A worker's several internal sort runs are merged to one before freeze.

## Considered Options

- **Per-worker private file + offset-range distribution (chosen):** pgbuf-free, O(1)
  offset addressing, no bitmap/sector metadata; matches PostgreSQL parallel sort /
  SharedTuplestore.
- **Reuse the sector + per-sector-bitmap work-stealing (`QFILE_LIST_SECTOR_SCAN_INFO`, the
  basis of PR #7173):** needed only because the *old* backing allocates pages in shared
  temp-volume sectors interleaved with FTAB. Moot once the backing is a private flat file
  with no dealloc.
- **logtape-style multiplex into one file (rejected):** needs a per-block chain + block
  recycling — complexity PostgreSQL pays only to bound peak disk across serial merge
  passes, absent at our parallel degree.

## Consequences

- **Diverges from PR #7173 — accepted.** That PR extends sector-based work-stealing on the
  *old* pgbuf/sector backing. The redesign uses offset-range distribution on the *new*
  backing. They coexist during expand→migrate; at contract (Phase 3) the sector machinery
  (`qfile_collect_list_sector_info`, `sector_page_iterator`, per-sector bitmap, sector
  prefetch) is retired. If #7173 merges first, the redesign rebases onto it and replaces
  its distribution for the new backing only.
- Per-Tape metadata is two scalars: `prefix_page_count`, `total_page_count`.
- The new backing must provide sequential read-ahead (the replacement for sector prefetch).
- TDE stays per-page on the private file; the membuf prefix is plaintext RAM.
