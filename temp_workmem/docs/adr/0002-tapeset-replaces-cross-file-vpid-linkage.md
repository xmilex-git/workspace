---
status: accepted
---

# Worker outputs are joined by a logical Tapeset addressed by Tape-relative positions, not cross-file VPID linkage

> Terminology revised in #143; identifiers herein are historical. See CONTEXT.md appendix.

## Context

The old design connects worker output lists two ways, both keyed on physical page
identifiers (VPID):

- **Sequential:** `qfile_connect_list` rewrites page headers (`next_vpid`/`prev_vpid`)
  to splice different temp files into one `QFILE_LIST_ID`, asserting `membuf == NULL`
  (forcing real-VPID disk backing).
- **Random access:** a saved `QFILE_TUPLE_POSITION` addresses a tuple by `{vpid, offset}`
  and `qfile_jump_scan_tuple_position` jumps straight to it — used by hash list scan,
  file hash scan, parallel hash join probe, sort/merge join, scrollable cursors, and
  CONNECT BY.

Because both identities are physical VPIDs, neither can span mixed backing
(membuf + spill) or multiple per-worker files. e21917cfd already had to fork
`QFILE_TUPLE_POSITION` into a second `{raw_fd_segment_id, page_index, tuple_offset}`
coordinate behind a `coord_type` discriminator to cope — the same disease the
`membuf == NULL` assert reflects. Keeping connect alive by forcing `membuf == NULL`
real-VPID backing was tried (FAIL-06): robust parity passed but +209% perf, debug
crash, and orphan leak.

## Decision

Drop physical-VPID identity entirely.

- Sequential connection becomes a **logical Tapeset**: an ordered vector of frozen,
  read-only worker Tapes that a reader imports and scans (PostgreSQL logtape model).
  No page-header `next_vpid`/`prev_vpid` chaining.
- A tuple's address becomes a single **Tape-relative coordinate**
  `(tape_idx, logical_page_idx_within_tape, tuple_offset)`, replacing both the
  `{vpid, offset}` and `{raw_fd_segment_id, …}` variants and the `coord_type`
  discriminator. `logical_page_idx` spans the Tape's
  `[frozen membuf prefix] ++ [BufFile overflow]` page space, so a position stays valid
  across freeze.

The whole position-producing/consuming stack — hash list scan, file hash scan,
parallel hash join probe, sort/merge join save+jump, scrollable cursor, CONNECT BY,
`qfile_set_tuple_column_value_by_position` — is refactored onto this coordinate.
`qfile_connect_list`, the `coord_type` union, the raw-fd position path, and
`first_vpid`/`last_vpid` connection-identity are deleted in Phase 3.

## Considered Options

- **Logical Tapeset + Tape-relative coordinate (chosen):** backing-agnostic, no shared
  physical identity, matches the PostgreSQL blueprint.
- **Keep `connect_list`, force `membuf == NULL` real-VPID so splicing works (FAIL-06):**
  correct but +209% perf + debug crash + orphan leak — non-viable.

## Consequences

- CONNECT BY no longer serializes a tuple position into a result bit-column; positions
  are strictly intra-query (rebuilt per execution, never surviving the query). This is
  what makes changing the coordinate layout safe — there is no stored or cross-query
  position format to migrate.
- Backward and jump traversal can no longer follow a physical `prev_vpid`; a tuple is
  located purely from its Tape-relative coordinate within the owning Tape. The
  page-index representation is decided in ADR 0003 — a dedicated contiguous BufFile
  per Tape with O(1) arithmetic addressing and no page directory.
- The correctness gate must exercise the random-access consumers (hash probe,
  merge-join re-scan, scrollable jump, CONNECT BY) over multi-Tape results, not just
  sequential scans.
