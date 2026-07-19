# No-redo bulk-index file identity is a server-issued create LSA

- Status: Accepted (boss decision 2026-07-18; supersedes the time_creation token and the client-supplied provenance descriptor)
- Date: 2026-07-18

## Context

The no-redo bulk index build leaves a marker log record (RVBT_BULK_BUILD_DURABLE) so that recovery can
(a) suppress redo against pages of files whose content was never redo-logged and (b) clean up
committed no-redo indexes that a media restore cannot replay. Both actions must bind to *the exact
file instance the build created* — not merely to a VFID, which the file manager recycles after DROP.

The reviewed branch (82f2d7639) had three related P1 defects (code review §4-6, all verified against
source):

1. redo suppression keyed only on current-VFID membership — a recycled VFID lets a stale marker
   suppress redo belonging to a new, fully-logged index;
2. the marker's create token was `FILE_HEADER.time_creation`, a `time(NULL)` value with seconds
   granularity — same-second re-creation of a same-shape index collides, so restore cleanup can
   delete a legitimate replacement index;
3. build provenance (`eligible_no_redo`, BTID, create LSA, class set) was supplied by the client and
   only range-checked by the server — skew or a bad descriptor can publish a no-redo index without a
   marker, or a marker pointing at someone else's B-tree.

## Decision

One identity concept seals all three: **the server issues the identity, and the identity is the
file-creation LSA.**

- At bulk index file creation the server records the creation log position (create LSA) as the
  file's generation token and registers a pending-build entry (BTID, create LSA, expected class
  set) in server-side transaction state.
- The marker's `create_token` carries this create LSA. Publication/commit refuses a marker that
  does not exactly match the registered pending build; client-supplied provenance is reduced to a
  request hint and never trusted for identity.
- Redo suppression and restore cleanup act only on an exact `(VFID, create LSA)` match. Any
  ambiguity (missing header, mismatched token) fails safe: no suppression, no deletion.

An LSA is database-monotonic and unique per log position, so collision is structurally impossible
(unlike wall-clock seconds), and it is already the currency of every other recovery decision.

## Consequences

- Marker payload and the file-side token change once (payload version bump); recovery matchers
  compare `(VFID, create LSA)` instead of `(VFID, time_creation)`.
- Whether the create LSA lives in a new file-header field (disk-compat gated) or reuses the
  existing INT64 creation slot for bulk-built index files is an implementation choice to be settled
  with the fix for review items 4-6; the decision here is only *what* the identity is and *who*
  issues it.
- Build-path performance cost is zero (one LSA capture at file creation, one compare during
  recovery); the review's verification rows for VFID reuse, same-second re-creation, and mismatched
  descriptors collapse into a single identity test axis.

## Considered Options

1. **(Chosen) Server-issued create LSA as the single identity.** Kills defects 4/5/6 with one
   concept and one format change; monotonic by construction.
2. **Patch each defect separately** (generation counter for 5, membership+identity checks for 4,
   server token for 6). Smaller individual diffs but three parallel validation mechanisms and a
   persistent risk that one of them drifts.
3. **UUID generation token.** Collision-free but introduces a new randomness dependency and a wider
   header field for no benefit over an LSA the server already owns.
