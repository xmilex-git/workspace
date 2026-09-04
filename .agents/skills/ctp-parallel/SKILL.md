---
name: ctp-parallel
description: >-
  RETIRED — renamed to ctp-run, which now runs every CTP suite (sql, medium,
  shell, HA/shell), not just parallel sql. Use the ctp-run skill instead.
---

# ctp-parallel is now `ctp-run`

This skill was renamed on 2026-09-04 when the runner grew from "parallel sql" to
"every CTP suite, whole or subset, plus CI-failure reproduction". Everything lives
in `.agents/skills/ctp-run/`.

| old | new |
|---|---|
| `just ctp-parallel` | `just ctp sql` |
| `just ctp-sql-isolated <dirs>` | `just ctp sql <dirs>` |
| `just ctp-medium-isolated [dirs]` | `just ctp medium [dirs]` |
| `just shell-debug* <dirs>` | `just ctp shell <dirs>` |
| `just ha-provision` + `just ha-shell <bucket>` | `just ctp ha_shell <bucket>` |

Two things changed beyond the name, and both will bite a copied old command:

- The container image is now the CI one (`cubridci/cubridci:test_rl8.10`), not a
  locally built `ctp-parallel:local`.
- A testcase ref is mandatory: pass `PR=<n>` or `TC_REF=<ref>`, or let it infer
  the PR from `WORKSPACE`. Runs no longer default to develop.

See `.agents/skills/ctp-run/SKILL.md` and
`docs/adr/0017-ctp-runner-on-cubridci-image.md`.
