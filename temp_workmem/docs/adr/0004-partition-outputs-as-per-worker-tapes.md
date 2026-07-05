---
status: accepted
---

# Partition and per-column outputs are per-worker Tapes imported into a Tapeset, not a shared list assembled under a mutex

> Terminology revised in #143; identifiers herein are historical. See CONTEXT.md appendix.

## Context

A parallel operation can emit several output lists keyed by a semantic dimension:

- Hash join (Grace) partitions the build and probe inputs into P partition lists each.
- Parallel-scan pre-aggregation writes per-column intermediate lists.

(Sort emits a single output.)

Today hash join assembles each partition into one **shared** `part_list_id[p]`: every
worker buffers tuples in a per-worker staging list (`temp_part_list_id[p]`), then appends
it into the shared partition list under `part_mutexes[p]` (`qfile_append_list`) — a
write-side mutex plus a full append-copy per partition.

## Decision

Each (worker, partition/column) is its own frozen **Tape**. A partition (or column) is a
**Tapeset** that imports the per-worker Tapes read-only and scans them as one stream
(ADR 0002). The semantic dimension (partition id / column) stays carried by **separate
`QFILE_LIST_ID`s** (an array, as today); the participant dimension within each is the Tape
vector. The per-worker-staging + `part_mutexes` + `qfile_append_list` copy is removed.

## Consequences

- No partition write-mutex and no append-copy: workers write their own Tapes
  independently, the consumer imports them. Matches PostgreSQL parallel-hash batches
  (per-participant files per batch).
- A worker owns one per-worker private backing file per (partition/column) it writes
  (ADR 0003), so a worker generally owns several Tapes.
- A partition consumer reads all of a partition's tuples by scanning the Tapeset
  (order-independent for the join), using 64-page offset-range distribution for parallel
  readers (ADR 0003).
