# Tape model — structure & hierarchy

How the temp work-memory connection structure (axis 2) nests, what each level's size is,
and how pages are addressed and distributed. **Term definitions live in
[`../CONTEXT.md`](../CONTEXT.md); the rationale lives in the ADRs.** This file is the
structural reference.

Related decisions: [ADR 0001](./adr/0001-holdable-results-reparent-not-copy.md) (holdable
reparent), [ADR 0002](./adr/0002-tapeset-replaces-cross-file-vpid-linkage.md) (logical
Tapeset, no VPID linkage), [ADR 0003](./adr/0003-dedicated-buffile-per-tape-no-multiplexing.md)
(per-worker private backing, offset addressing),
[ADR 0004](./adr/0004-partition-outputs-as-per-worker-tapes.md) (partition/column outputs
as per-worker Tapes).

## Containment

```
operation
└── Tapeset[ key ]            one per partition / per column (== one QFILE_LIST_ID)
    └── Tape[0 .. N-1]        one per Participant (worker)
        │  logical page space:  [ membuf prefix (RAM) ] ++ [ private-file pages (disk) ]
        ├── Chunk             contiguous 64-page OFFSET range  (parallel-read work unit)
        ├── Page              16 KB fixed                       (I/O unit)
        │   └── tuples        laid out forward; a long tuple may overflow across pages
        └── private file      per-worker, pgbuf-bypassed, owner-buffered, append-only
```

- A **Tapeset** is what a reader scans as one ordered tuple stream — one logical list.
- An operation may produce **many Tapesets**, keyed by a semantic dimension:
  - **Sort** → 1 Tapeset.
  - **Hash join** → P partitions × {build, probe} Tapesets (ADR 0004).
  - **Parallel-scan pre-aggregation** → one per column.
- Within a Tapeset, each **Participant** contributes **one Tape**; so a worker generally
  owns several Tapes (one per partition/column it writes).
- A Tape's spilled pages live in a **per-worker private file** that bypasses the shared
  buffer pool. A Tape that fits its work buffer is all membuf, no file (tiny / no spill).
- There is **no multiplexing** of multiple Tapes into a shared file, and **no page
  directory / no per-sector bitmap**.

## Sizes

| Level    | Size                           | Notes                                              |
|----------|--------------------------------|----------------------------------------------------|
| Page     | 16 KB (DB IO page size), fixed | smallest I/O unit; uniform across the DB           |
| Chunk    | 64 pages = ~1 MB               | unit of parallel-read distribution (offset range)  |
| Tape     | variable (KB … many GB)        | one worker's whole output for one Tapeset          |
| Tapeset  | sum of its Tapes               | one logical list; N Tapes = parallel degree        |

A Tape is **not** a fixed size and is **not** one page. "16 KB" is one page; a Tape holds
up to millions of them.

## Addressing — Tape position

A single tuple's address is a backing-agnostic **Tape position**:

```
(tape_idx, page_offset, tuple_offset)        [+ tplno]
```

Resolved by **pure offset arithmetic** — no directory, no sector list, no bitmap:

```
if page_offset < prefix_count:   page is membuf_prefix[page_offset]            (RAM)
else:                            file offset (page_offset - prefix_count) * pagesize  (disk)
```

This holds because a live list's pages are a **dense sequence** (no mid-life dealloc —
`qfile_truncate_list` resets the whole list, never frees individual pages) and the file is
**private** (only this Tape's pages, no FTAB interleaving).

- **Forward** scan: `page_offset + 1`. **Backward** scan / jump: `page_offset - 1` or a
  saved `(tape_idx, page_offset, offset)`. Both arithmetic; no `prev_vpid` walk.
- Per-Tape metadata is two scalars: `prefix_page_count`, `total_page_count`.
- Random-access consumers (hash list scan, parallel hash join probe, sort/merge-join
  re-scan, scrollable cursor, CONNECT BY) all mint and resolve this one coordinate.

## Parallel read (R2)

When a Tapeset feeds N downstream readers, work is handed out in **Chunks** — contiguous
**64-page offset ranges** over the whole logical page space (RAM prefix + private file) —
claimed via a shared atomic counter (`fetch_add` over the range index, work-stealing). The
membuf prefix is just the low offsets, range-distributed like any pages (RAM is immutable
and shared-address-space, so any reader reads it directly). **No per-sector bitmap, no
sector scan, no sector prefetch**; the private backing's own sequential read-ahead provides
prefetch. Overflow-continuation pages are skipped by every reader except the one that owns
the tuple's first page (which reassembles the whole tuple).

## Lifecycle (pointer)

A Tape/Tapeset is **transient** by default (freed when the query ends). Two exceptions, in
the ADRs and `../CONTEXT.md`:

- **Holdable**: ownership of the backing — the private-file handle **and** the RAM membuf
  prefix — is moved transaction → session at commit (zero copy, zero I/O; a tiny all-RAM
  result moves with no disk touch) — ADR 0001.
- **Cached-persist**: the result is copied out to the shared temp volume (the only
  copy-out class).

## Mapping to old structure and to PostgreSQL

| concept            | old (e21917cfd)                              | new model                              | PostgreSQL                            |
|--------------------|----------------------------------------------|----------------------------------------|---------------------------------------|
| connect lists      | `qfile_connect_list` (page-header next/prev VPID) | ordered Tape vector (Tapeset)          | `LogicalTapeSet` import               |
| one worker's output | spliced into a shared list via VPID chain   | one frozen Tape per (worker, key)      | one materialized tape per worker      |
| backing            | global raw-fd registry / pgbuf temp          | per-worker private file, pgbuf-bypassed | `BufFile`                             |
| tuple address      | `{vpid,offset}` or `{raw_fd_segment_id,…}`   | `(tape_idx, page_offset, tuple_offset)` | `(tape, block, offset)`               |
| parallel-read unit | 64-page sector + per-sector bitmap           | 64-page offset range (no bitmap)       | `chunk` (SharedTuplestore)            |
| hash-join partition | shared list + `part_mutexes` append-copy    | per-worker Tapes imported into Tapeset | per-participant files per batch       |
| backward/jump      | physical `prev_vpid` walk                    | `page_offset ± 1` arithmetic           | (logtape block chain — not used here) |

> Note: PR #7173 extends the old sector + per-sector-bitmap work-stealing on the
> pgbuf/sector backing. The new model uses offset-range distribution on the per-worker
> private backing; the sector machinery is retired at contract (ADR 0003).
