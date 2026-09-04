# CUBRID Port Registry (machine-local, multi-session)

Multiple Claude sessions on this host may run CUBRID servers concurrently. Before
starting any CUBRID server (or broker), a session MUST claim its ports here to
avoid collisions.

## Quick use (preferred): justfile recipes

```bash
just ports                      # show claims + live CUBRID listeners
just port-claim <db> <effort>   # auto-pick a free cubrid_port_id + broker block, record the claim
just port-release <db-or-port>  # drop the claim when the effort is done
```

The recipes implement the protocol below — use them instead of hand-editing.

## Protocol

1. Read the claims file: `.git_ignored_dir/port-registry/claims.md` (create the
   directory on demand; it is git-ignored because port claims are machine-local).
2. Check live usage too: `ss -ltn` — a claim protects against *agents*, not
   against processes started by humans.
3. Append one claim line (see format below) **before** starting the server.
4. Optionally broadcast to live sessions (`ListAgents` → `SendMessage`) when the
   claim overlaps something ambiguous.
5. Remove your line when the effort that claimed it is finished.

## Claim line format

```
| <cubrid_port_id> | <broker ports or -> | <db name> | <session/effort> | <date> |
```

## Known fixed occupants (do not claim)

- `1523` — default `cubrid_port_id`; long-running cub_master on this host.
- `1568` — `~/CUBRID/conf/cubrid.conf` install default.
- `30000-30999`, `33000-33999` — default broker ranges of existing installs.

## Recommended free range for agent claims

`1700-1799` for `cubrid_port_id`; `36000+` for brokers (one hundred-block per claim).

## CTP SQL kills every cub_* of the user — ports do not protect you

`~/cubrid-testtools/CTP/sql/bin/run.sh` `do_clean()` runs `pkill cub` (all of
this user's cub_master/cub_server/cub_broker/cub_cas, any port) plus shared-memory
removal at run start and cleanup. A CTP SQL run therefore takes down every other
CUBRID server on the host regardless of registry claims (incident: 2026-08-28,
a `_08_javasp` gate run killed the claimed mandb@1701). Before running CTP SQL
while any other server is claimed: use podman isolation (`just ctp`, the `ctp-run` skill)
or broadcast to live sessions and get an ack first.

## A per-build $CUBRID cannot stop a server it started on a shared master

`cub_master` puts its control socket at a path derived from the environment that
started **the master**, not the one starting a later server: on this host that is
`$HOME/CUBRID/var/CUBRID_SOCK`. So when several installs take turns on one port —
building to `INSTALL_PREFIX=$HOME/optdebug/CUBRID-<x>` and pointing `$CUBRID` at
each in turn, the usual pattern for an A/B — a stop issued with the per-build
`$CUBRID` active fails with `could not connect to master server`, even though the
server is plainly running. Export `CUBRID_TMP=$HOME/CUBRID/var/CUBRID_SOCK`
before the stop and it shuts down through the normal protocol.

Symptom to recognise: `cubrid server status` reports nothing while `ps` shows a
live `cub_server` and `ss -tlnp` shows the master holding the port. That is an
environment mismatch, not a hung or crashed server — do not reach for a kill.

When a run leaves a `cub_master` with no server attached (visible as a listener on
the claimed port with no matching `cub_server`), releasing the claim is not enough:
the master keeps the port. Confirm no `cub_server` belongs to it, then stop that
master by its exact pid. Never broaden this to `pkill cub` — that takes down every
other session's servers (see the CTP section above).
