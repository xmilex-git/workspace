---
name: cubrid-shell-run
description: >-
  RETIRED — CTP shell tests now run through the ctp-run skill inside podman
  (`just ctp shell <dirs>`), because host-side CTP kills every cub_* process of
  this user. Use the ctp-run skill instead.
---

# Focused shell runs moved to `ctp-run`

Host-side CTP shell execution was removed on 2026-09-04. CTP's shell
`init_path/init.sh` kills every process of the running user (`pkill cub`,
`kill -9` over `ps -u $USER`), so a focused shell run would stop other sessions'
servers no matter which ports they had claimed. It now runs in a container like
every other suite.

| old | new |
|---|---|
| `just shell-debug <dir>` | `just ctp shell <dir>` |
| `just shell-debug-selected <dirs...>` | `just ctp shell <dirs...>` |
| `just shell-debug-optdebug <dirs...>` | `BUILD=~/optdebug/CUBRID-<ver> just ctp shell <dirs...>` |
| `just shell-debug-interactive` | (dropped — an interactive picker no agent could drive) |

The `<dir>` argument changed shape: it is now **relative to the scenario root**
(`shell/`), e.g. `_06_issues/_13_1h/bug_bts_10818`, not an absolute path into the
testcase checkout. And a testcase ref is mandatory (`PR=`, `TC_REF=`, or inferred
from `WORKSPACE`) — no more silent develop.

The pre-run broadcast-and-ack ritual is gone with it: containers cannot kill each
other's servers.

See `.agents/skills/ctp-run/SKILL.md` and
`docs/adr/0017-ctp-runner-on-cubridci-image.md`.
