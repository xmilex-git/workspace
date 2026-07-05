---
status: accepted
---

# Holdable cursor results are reparented to the session, not copied

> Terminology revised in #143; identifiers herein are historical. See CONTEXT.md appendix.

## Context

A WITH HOLD cursor must keep reading its result after the producing transaction
commits. CUBRID's temp backing is owned by the transaction (`owner_tran_index`,
`query_id`) and reaped at transaction end, so a result on that backing cannot
survive commit as-is.

## Decision

Holdable results transfer ownership of their existing temp backing from the
transaction to the session at commit (a handle/pointer move), exactly as `develop`
does via `qentry_to_sentry` + `session_preserve_temporary_files`. We do **not** copy
the result set. The query result cache is the **only** class that is copied out — to
the shared temp volume — because it must be shared across sessions until eviction.

This reverses the raw-fd redesign's `qmgr_materialize_to_pgbuf` ("Class-B sink"),
which scanned and re-wrote every tuple at every holdable commit.

## Considered Options

- **Reparent (chosen):** explicit ownership transfer in code; no per-commit copy;
  matches `develop` and PostgreSQL's held-portal ResourceOwner reparenting.
- **Copy/move to pgbuf temp volume:** reuses existing `file_temp_preserve` and the
  teardown infra untouched, but pays a full-result-set copy on every holdable
  commit — the regression this redesign exists to remove.
- **Flush the RAM membuf prefix to the private file on hold, then reparent only the file:**
  bounded (≤ work_mem) but pays one-time I/O and forces a tiny all-RAM result to disk;
  rejected in favor of a zero-I/O ownership move.

## Consequences

- Reaper liveness must widen from `(owner_tran, query_id) live` to
  `(owner_tran, query_id) live OR session-held`, so it never unlinks a live held
  cursor's backing after commit.
- The new per-worker backing must register with the session teardown path
  (`session_free_sentry_data`) so normal logout and abnormal disconnect free it
  (orphan-zero preserved).
- The reparented backing has two parts, both moved by **ownership — no copy, no flush**:
  the per-worker private file (handle move) and the **RAM membuf prefix** (its buffer
  ownership moves query/work_mem → session; a tiny all-RAM result reparents with zero I/O).
  The prefix leaves work_mem and becomes session-held memory; `session_free_sentry_data`
  frees it too, so session-kill orphan-zero covers RAM, not just files.
- The held-cursor read path and the parallel leader's worker-Tape Import path collapse
  into one mechanism: read-only sequential Import of an ordered, frozen Tapeset
  (PostgreSQL logtape model). A holdable result may itself be multi-Tape.
- Boot-sweep is unchanged: a server restart kills the session and therefore the
  holdable result, which is correct.

## Amendments

- **2026-07-02 (#94, interim deviation):** holdable was temporarily unified with
  the other Class-B sinks onto `qmgr_materialize_to_pgbuf` (full copy at commit)
  to close the R1 client-0-row hole with a single verified path; zero-copy
  reparent was explicitly deferred (SSOT #75 P9). The escape hatch named in the
  #94 D-record — "holdable만 materialize 진입 술어에서 분기 빼면 됨" — is what
  #111 exercised.
- **2026-07-03 (#111, decision restored):** holdable commit again reparents a
  NEW (Tapeset)-backed result to the session with zero copy. Mechanically this
  is even leaner than the original sketch: `qmgr_clear_trans_wakeup` already
  hands the whole `QFILE_LIST_ID *` to the session by pointer
  (`qentry_to_sentry`), so skipping the materialize call for NEW-backed lists
  IS the reparent — the single-owner Tapeset rides the pointer, the held-tape
  census stays flat across the move, and `session_free_sentry_data` →
  `qfile_clear_list_id` already destroys an owned Tapeset at session end.
  Post-commit client fetches route through the session-restored query entry
  into the #120a/b Tapeset serve facade; the facade's page space
  (marker volid + Tapeset-intrinsic global page index) is identical before and
  after the move, so a fetch stream spanning the commit boundary stays valid.
  Raw-fd-backed holdable results still materialize (legacy VPID-wire
  requirement) until Phase3 removes raw-fd; the query result cache remains the
  only copied-out class, exactly as this ADR decided.
