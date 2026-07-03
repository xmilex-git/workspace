---
status: accepted
---

# Overflow tuples are a contiguous page run with an offset back-pointer, reassembled by the first-page owner

## Context

A tuple larger than one 16 KB page is an **overflow tuple**. In the old backing
(list_file.c) the first page is flagged (`QFILE_GET_TUPLE_COUNT == -2` /
`QFILE_OVERFLOW_PAGE_ID != NULL_PAGEID`) and its continuation pages are linked by a
physical **VPID chain** (`QFILE_OVERFLOW_PAGE_ID`/`QFILE_OVERFLOW_VOL_ID`), walked
by `qfile_assemble_overflow_tuple`. That VPID linkage is exactly what ADR 0002
deletes, so the new model needs a different representation.

The landed new scan does **not** handle overflow yet: `tapeset_scan::retrieve`
asserts false and returns S_ERROR on an overflow page, with the comment that
reassembly "is defined by the producer (Phase 1B / migration), not by the 1A scan
contract" (qfile_tape.cpp:387-395). So this is a #78 (2A-0) decision, paired with
ADR 0005's concurrent read.

The hard case is R2 parallel read. `chunk_distributor` hands out 64-page offset
ranges that ignore tuple boundaries, so a reader's chunk can **start in the middle
of an overflow tuple** (on a continuation page). A reader that naively reads a
continuation page as a tuple start gets a garbage/zero-length tuple — the same
class as #77 / FAIL-10 (`db_private_alloc(0)` spurious OOM from a mis-positioned
parallel worker). Sequential (single-cursor) scan never hits this because it
always follows tuples from their start.

A single overflow tuple can be very large: the tuple-length and
`QFILE_OVERFLOW_TUPLE_PAGE_SIZE` fields are 4-byte ints, so up to ~2 GB (≈1 GB is
realistic for wide rows / large aggregates). At 16 KB pages that is ~65 536
contiguous pages ≈ 1024 chunks. The design must therefore (a) skip such a run in
O(1), not page-by-page, and (b) never let every reader re-read the run just to
detect that it is continuation.

## Decision

In the new per-worker append-only flat backing an overflow tuple is a **contiguous
run of logical pages** (the producer appends continuation pages immediately after
the start page), addressed by offset — no VPID chain.

- The **start page** keeps the existing overflow flag and records the tuple's total
  size, from which the run length (number of continuation pages) is computed.
- Each **continuation page** records, in the header fields vacated by the old
  overflow VPID, **two Tape-relative offsets** (never VPIDs): the **first-page
  offset** of its tuple and the tuple's **run end**. A reader that lands on any
  continuation page learns the run's full extent from that one page — O(1), no
  per-page walk.
- **First-page-owner reassembly:** the reader whose chunk contains the tuple's
  start page reassembles it, reading the contiguous continuation pages **forward
  even past its own chunk boundary** (safe: the Tape is frozen/immutable and read
  by offset `pread` through the per-reader view of ADR 0005).
- A reader whose chunk **starts on a continuation page** reads those offsets; if the
  first page lies outside (before) its chunk it **skips the entire run in O(1)** to
  the next tuple-start page (it never owns a tuple it did not start) **and advances
  the shared chunk cursor past the run's end**, so the run's other continuation
  chunks are not separately claimed and re-read by every reader. This is the
  offset-model equivalent of PostgreSQL's `chunk_header.overflow` skip +
  `read_next_page`→shared-cursor bump (sharedtuplestore.c:512-560). A giant run
  (e.g. a ~1 GB tuple ≈ 65 536 pages ≈ 1024 chunks) is thus read once by its
  first-page owner, never 1024× by skippers.

## Considered Options

- **Contiguous run + offset back-pointer + first-page-owner (chosen):** natural for
  an append-only flat file (continuation pages are already contiguous), minimal
  page-header change (one offset replaces the old overflow VPID), O(1) detection.
- **Force each overflow tuple to fit within one 64-page chunk (chunk alignment /
  padding) (rejected):** removes cross-chunk reassembly, but a tuple larger than a
  chunk (> ~1 MB) cannot be aligned, and padding wastes space.

## Consequences

- The page-header overflow VPID field is repurposed to a logical offset; the old
  VPID overflow path is among the symbols retired at Phase 3 (contract).
- 2A-0 builds and unit-verifies this with overflow tuples that span a chunk
  boundary (a reader starting mid-tuple skips correctly; the first-page owner
  reassembles across the boundary), on the same N-reader / TDE harness as ADR 0005.
- Structurally forecloses the #77 / FAIL-10 mis-positioning class on the new path.
- Single-cursor sequential scan (R1) reassembles the run inline; the skip logic is
  only exercised by parallel chunk readers (R2).
- A reassembly buffer of the whole tuple size (up to ~1–2 GB) is **inherent and
  pre-existing**: the old path already allocs the full size (`qfile_reallocate_tuple`
  list_file.c:3492 / `qfile_assemble_overflow_tuple`), and PostgreSQL caps a
  MinimalTuple at MaxAllocSize for the same reason. The new model does not change
  this — the consumer still receives one contiguous tuple.
- A single tuple is an **indivisible parallel-read work unit**: one logical value is
  reassembled by one reader; a tuple cannot be split across readers. Parallelism is
  across the *other* tuples. The CoV ≤ 15% balance gate is therefore measured on
  representative multi-tuple data; a workload of one giant tuple is intrinsically
  single-reader, not a balance regression.
