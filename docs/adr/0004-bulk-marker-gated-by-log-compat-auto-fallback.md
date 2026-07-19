# Mixed-version clusters auto-fall back to the logged index build

- Status: Accepted (boss decision 2026-07-18)
- Date: 2026-07-18

## Context

The no-redo bulk build introduces a new WAL record class (RVBT_BULK_BUILD_DURABLE = 130). A log
stream containing it is unreadable by older releases: an old standby in a rolling HA upgrade, or a
downgraded node, fails dispatch on the unknown recovery index and dies at replication/restart
(code review §8). The record is load-bearing — without the marker the no-redo path must not run,
because media recovery could neither suppress nor clean up the unlogged index pages.

## Decision

Marker emission — and with it the whole no-redo/parallel bulk path — is gated on the log-format
compatibility of every log consumer. While an incompatible reader may consume the log (rolling
upgrade window, old standby, pending downgrade), CREATE INDEX **automatically falls back to the
legacy fully-logged build**. The fallback is observable: the server emits one NOTIFICATION line
("bulk build fell back to the logged path: incompatible log consumer") so operators can tell a
policy fallback from a performance regression. The gate rides the existing release/log
compatibility machinery rather than a new handshake.

## Consequences

- Same-version clusters and single-node deployments (every benchmark condition) pay zero cost; the
  measured speedups are unaffected.
- During a mixed-version window index builds run at legacy speed — the only accepted "performance
  loss" scenario of the review, chosen over the alternatives: rejecting CREATE INDEX outright
  (needless outage) or emitting record 130 unguarded (kills old readers — the defect under review).
- The wire-protocol versioning of BTREE_LOADINDEX (review §7) is a prerequisite and ships with the
  same change: legacy peers negotiate `eligible_no_redo = false` and the pre-change reply layout.
- The policy is to be recorded on the public tracking issue (JIRA CBRD-27071) once the
  implementation lands, not before.
