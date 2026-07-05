---
status: accepted
---

# Frozen Tapes are read concurrently via a shared fd with per-reader scratch, not per-reader file handles

> Terminology revised in #143; identifiers herein are historical. See CONTEXT.md appendix.

## Context

R2 (SSOT #75 §3.2 B2) requires that when a frozen Tapeset feeds N downstream
readers, a single frozen Tape can be read by N participants concurrently with no
lock beyond the work-stealing chunk cursor. The landed infra does not yet satisfy
this:

- `qfile::buffile_tape` is **single-reader**: one owned `m_readbuf` scratch, and
  `tape::page_at` / `release_page` are a single cursor (qfile_tape.hpp:129-165).
- `qfile::tapeset_scan` is **single-cursor** (one `m_page`/`m_tape_idx`/
  `m_page_offset`).
- `qfile::buffile::read_page` is **not re-entrant on the TDE path**: it preads
  ciphertext into the member `m_stored` and decrypts into the member `m_plain`
  (qfile_buffile.cpp:499/509/514), so two threads reading the same TDE BufFile
  corrupt each other's page. `wmg003` (TDE) is a gate database, so this race is
  not hypothetical. The plaintext path still races the non-atomic
  `m_metrics.pages_read++`.
- `chunk_distributor` (qfile_chunk.hpp) already hands out 64-page offset ranges
  via a single `std::atomic fetch_add`, but it only distributes ranges — it does
  not itself read pages, so the read path above is the gap.

PostgreSQL was used as the blueprint (evidence §H-7). PG's own `BufFile` is also a
single-cursor object (buffile.c:71-105; `BufFileReadCommon` mutates
`pos`/`nbytes`/`curOffset`, :594), so PG never shares one BufFile across readers.
Instead each reader (`SharedTuplestoreAccessor`) opens the file `O_RDONLY` into its
**own** BufFile and reads into its **own** `read_buffer`
(sharedtuplestore.c:84/538-540); the only shared mutable state is the chunk cursor
`p->read_page` advanced under a lock (:510-523). PG does per-reader `open` because
its workers are **separate processes** (a BufFile struct cannot be shared) and it
absorbs the fd cost through **vfd pooling**. CUBRID workers are **threads** sharing
one address space, and `qfile::buffile` holds a **raw `int m_fd`** with no vfd pool.

## Decision

A frozen Tape's backing is treated as **immutable shared state read through one
shared fd with `pread`, and all mutable read state is per-reader.**

- The frozen `qfile::buffile` exposes **offset-stateless reads**: `full_pread` on
  the shared fd at a computed offset (already used at qfile_buffile.cpp:499). A
  shared fd is safe because `pread` does not touch the fd's file position and there
  are no writes after freeze.
- `buffile::read_page` is refactored to be **re-entrant**: the caller supplies the
  cipher/plain scratch (the member `m_stored`/`m_plain` leave the read path), and
  `pages_read` becomes atomic or per-reader. This is the CUBRID analogue of PG's
  per-accessor `read_buffer`.
- Each reader gets a lightweight **per-reader Tape view** holding its own page
  scratch and its own TDE-decrypt scratch; it resolves logical page N by the same
  offset arithmetic as `buffile_tape` (prefix RAM vs `read_page(N - prefix)`),
  sharing only the immutable backing.
- The single shared mutable read object stays the **`chunk_distributor` atomic
  chunk cursor** (lock-free `fetch_add`) — PG's `p->read_page`, but without the
  lock.
- Overflow-continuation pages are reassembled only by the reader that owns the
  tuple's first page; other readers skip them, mirroring PG's
  `chunk_header.overflow` skip (sharedtuplestore.c:556-560).

## Considered Options

- **Shared fd + `pread` + per-reader scratch (chosen):** honours PG's real
  invariant (immutable shared file, per-reader buffer, only the chunk cursor
  shared) and fits CUBRID's threaded model — one fd per Tape, concurrent `pread`,
  `pgbuf_fixes == 0` by construction.
- **A BufFile handle (and fd) opened per reader, PG's literal shape (rejected):**
  faithful to `BufFileOpenFileSet(O_RDONLY)`, but PG only tolerates it because of
  vfd pooling. `qfile::buffile`'s raw fd has no pool, so this multiplies real OS
  fds by (readers × Tapes × Tapesets) and risks fd exhaustion at parallel degree.
- **A lock around the single shared read scratch (rejected):** serialises the read
  hot path and violates SSOT §3.2 B2's "no lock beyond the chunk cursor."

## Consequences

- `buffile::read_page` loses its member read scratch and gains caller-supplied
  scratch; `buffile_tape`/`tapeset_scan` gain a per-reader view (the single
  `m_readbuf` is no longer the read unit for parallel readers). The single-reader
  sequential scan (R1) keeps working as a degenerate one-reader view.
- This per-reader-view + overflow-skip mechanism is the 2A-0 **hard prerequisite**:
  it is built and unit-verified (N-reader concurrent view with no race, including a
  TDE Tape on `wmg003`; per-chunk overflow reassembly) **before** any live
  `chunk_distributor` wiring. `pgbuf_fixes == 0` holds trivially (pread bypasses
  pgbuf); the CoV ≤ 15% balance gate and the N-reader race test run on the live
  view.
- Concurrency safety rests on the freeze contract: **no writes after freeze**.
  Anything that would mutate a Tape after publish is forbidden.
- PG parity: this is `SharedTuplestoreAccessor.read_buffer` over a `SharedFileSet`
  file, with PG's per-process fd collapsed into one shared fd — legal only because
  CUBRID is threaded.
