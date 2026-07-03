# Query Temp Work Memory

Glossary for the CUBRID query-spill / temp work-memory redesign. The design follows
PostgreSQL's model (logtape / BufFile / SharedFileSet), so the vocabulary below adopts
PostgreSQL's terms wherever PostgreSQL has one, to keep the design legible against that
blueprint.

## Language

### Result lifetime

**Query**:
A single statement execution, identified by its `query_id` within the owning transaction.
The lifetime unit that owns transient temp backing; reclaimed when the statement ends.
_Avoid_: request, cursor (a cursor can outlive the Query that produced it)

**Transient result**:
Intermediate or final query data that does not outlive its Query. The default for almost
all spill; never written to a shared pool.
_Avoid_: scratch, temp file

**Holdable result**:
A Transient result whose ownership is handed from the transaction to the Session at commit
so its cursor can keep reading it after the producing transaction ends, for the life of the
Session. Same backing as a Transient result with an extended lifetime — not a copy.
(PostgreSQL: a "held portal", backed by a `FileSet` — temp files that survive the
transaction and are reopened by one backend.)
_Avoid_: WITH HOLD copy

**Cached-persist result**:
A query result retained in the server-global result cache for reuse by later queries across
transactions and sessions, until eviction. Owned by the cache, not by any one Query or
Session. The only result class that is genuinely copied out.
_Avoid_: result cache list, preserved list

### Connection structure (PostgreSQL logtape model)

**Tape**:
A worker-owned, independently-readable sequential run of result tuples — the unit a worker
produces and the leader (or a held-cursor Session) imports. PostgreSQL `LogicalTape`.
_Avoid_: segment (in PostgreSQL a "segment" is a BufFile's 1 GB physical file piece — a
different thing), sub-list, connected list

**Tapeset**:
The ordered collection of Tapes a reader imports and scans as one logical tuple stream.
Replaces the old cross-file page-header linkage. PostgreSQL `LogicalTapeSet`.
_Avoid_: list chain, dependent list

**Freeze**:
Making a Tape immutable when its producing worker finishes, and publishing its share so
other backends can read it. PostgreSQL `LogicalTapeFreeze`.
_Avoid_: close, seal

**Import**:
A leader or Session attaching a frozen worker Tape into its Tapeset for read-only
sequential scan. PostgreSQL `LogicalTapeImport`.
_Avoid_: merge, connect, relink

**Tape position**:
A backing-agnostic address of one tuple inside a Tapeset — `(Tape, page-within-Tape, tuple-offset)`. What a reader jumps straight to (hash probe, merge-join re-scan, scrollable cursor), replacing the old physical-VPID address that forked per backing type.
_Avoid_: VPID position, raw-fd coordinate, tuple position

**Participant**:
A worker thread taking part in a parallel operation — producing a Tape, or reading Chunks.
PostgreSQL `participant`.
_Avoid_: slave, child

### Backing (PostgreSQL BufFile model)

**BufFile**:
The per-worker private temp file backing a Tape's spilled data: its own buffer plus a file
descriptor, owner-only append, addressed by page offset. Bypasses the shared buffer pool
(no pgbuf BCB), with no shared page registry and no per-page lock. A Tape that fits in its
work buffer has no BufFile. PostgreSQL `BufFile`.
_Avoid_: raw-fd (the removed global-registry backing), spill file, temp volume page

**Spill** (verb):
Writing data that overflowed the work buffer (work_mem) out to a BufFile on disk. The file
itself is a BufFile, not a "spill file".
_Avoid_: (use as a verb only)

**SharedFileSet**:
The shared namespace under which Participants' BufFiles live so the leader can Import them
across workers. PostgreSQL `SharedFileSet`.
_Avoid_: scratch dir, registry

**Chunk**:
A contiguous 64-page offset range handed to one reader as the unit of parallel-read work
distribution, claimed via an atomic counter (work-stealing). No occupancy bitmap: a live
list's pages are a dense sequence (no mid-life dealloc) backed by a per-worker private file.
PostgreSQL `chunk` (parallel scan / SharedTuplestore).
_Avoid_: sector (the old shared-volume 64-page allocation unit), page band, occupancy bitmap

**raw-fd**:
Names *only* the abandoned e21917cfd backing — a server-global page registry with a
per-tuple dirty-mark lock. Never used for the new per-Tape backing.
_Avoid_: (do not apply to the new design; use BufFile)
