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
while any other server is claimed: use podman isolation (`ctp-parallel` skill)
or broadcast to live sessions and get an ack first.
