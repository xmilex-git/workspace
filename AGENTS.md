If the current environment is not Rocky Linux 8, connect with `ssh cubrid@192.168.6.34` and work in `~/dev/workspace` on that host. If SSH connection fails, follow the [forticlient-reconnect skill](/Users/song-ilhanmacmini/.codex/skills/forticlient-reconnect/SKILL.md) to restore the VPN, then retry SSH and continue there.

# AGENTS.md — CUBRID Tooling Repo

This repository is a **portable, standalone bundle of the CUBRID development tooling** —
the agent skills, harness config, and helper recipes used when working on CUBRID — extracted
from the main `cubrid` engine checkout so they can be deployed on their own (e.g. on a remote
GNU/Linux build host) without dragging along the database source tree.

It is **not** a CUBRID engine checkout. There is no `CMakeLists.txt`, no `src/`. If you are
looking for engine code, you are in the wrong directory.

## Layout

```
.
├── AGENTS.md                 # this file (the repo guide; CLAUDE.md is a symlink to it)
├── CLAUDE.md -> AGENTS.md     # so Claude, Codex, and other harnesses all read the same guide
├── cubrid.conf               # campaign cubrid.conf — single source of truth; `just conf` copies it
├── justfile                  # build/test/dev recipes (uses $HOME, ~/CUBRID, ~/cubrid-testtools/CTP)
├── .agents/
│   ├── AGENTS.md             # behavioral guidelines (think-before-coding, surgical changes, …)
│   └── skills/<name>/        # canonical home of every skill (each has a SKILL.md)
└── .claude/
    ├── CLAUDE.md             # behavioral guidelines (the Claude-flavored, longer variant)
    ├── locale/make_locale.sh # locale .so build helper (the built *.so is git-ignored, never committed)
    └── skills/<name>         # relative symlink -> ../../.agents/skills/<name>  (skill discovery)
```

## Skills

Every skill is a markdown prompt under `.agents/skills/<name>/SKILL.md`. Harnesses discover
skills via `.claude/skills/`, where each entry is a **relative symlink** back into
`.agents/skills/`.

`.agents/skills/` is the single source of truth; never edit a skill "through" the symlink as
if it were a separate copy. To add a skill, create it under `.agents/skills/` and add the
matching relative symlink under `.claude/skills/`.

## The `$WORKSPACE` convention

Because this repo is deployed *separately* from the CUBRID checkout it operates on, the current
working directory is this tool repo — **not** the CUBRID source tree. Skills that read or write
files inside a CUBRID checkout therefore cannot rely on the cwd. They **hard-require** the target
checkout to be passed explicitly as the first argument:

```bash
WORKSPACE="${1:?WORKSPACE required (pass the target CUBRID checkout)}"
```

There is **no cwd fallback** — passing the wrong directory silently is worse than failing loudly
on an unattended remote run. The skills that hard-require `$WORKSPACE` are exactly:

- **obsidian-vault** — operates on `"$WORKSPACE"/.claude/vault/`.
- **cubrid-server-control** — starts/stops the CUBRID server living in `$WORKSPACE`.

`ctp-run` keeps each run's evidence (console logs, CTP results, composed confs) on the NVMe home disk at
`/home/<user>/ctp-run-out/<tooling-repo>/` with cores on the HDD under `/bench/hdd/core/ctp/<run>/`, prunes the shard working copies when the run ends, and `just ctp-prune`
deletes old runs after their evidence was read (see its skill); it takes the install to test via `BUILD=`
(default `$CUBRID`) and needs `WORKSPACE` only to infer the testcase ref from the engine branch.
`cubrid-deps-check` also takes the workspace as its first argument (it diagnoses a checkout's
build/test dependencies). The other skills are workspace-agnostic or operate on fixed
infrastructure and take no `$WORKSPACE`.

## Code lookup in an engine worktree

Look up engine code with `tools/code-index/code-index <WORKSPACE> <command> <name>` first — it
answers from a build-free index of the task worktree that refreshes itself before every query:

| Question | Command |
|---|---|
| where X is defined (function, macro, type, member, enumerator, grammar rule, Java class) | `definition X` |
| X's source with line numbers | `body X` |
| a file's contents with line ranges | `outline <path>` |
| who calls X, from which function | `callers X` |
| every use of X | `references X` |

Every hit carries `{server,sa,cs}` — the libraries that compile its file — and `[...]`, the `#if`
conditions around it (e.g. `[#else of !defined(NDEBUG)]`); read both before following a call into
server code. Reach for rg when the target is a comment, a string, a regex, or a name code-index
reports as not found.

## Diagnostics

Run `cubrid-deps-check <workspace>` to get a read-only `[OK]/[MISS]/[WARN]` report of the build
and test prerequisites for a CUBRID checkout. It never mutates anything and never executes its
own fix suggestions — it only prints them.

## House rules

- **Never write scratch to `/tmp` or `$TMPDIR`** (the host's `/tmp` is tmpfs-backed and OOMs).
  CTP runs live under `/home/<user>/ctp-run-out/<tooling-repo>/` (see `ctp-run` above: pruned per run, `just ctp-prune` for old runs); use this tooling repository's `.git_ignored_dir/scratch/` for other local tooling artifacts. See `.agents/AGENTS.md` / `.claude/CLAUDE.md` for the full policy.
- The locale `*.so` artifacts and `.git_ignored_dir/` are git-ignored and must never be committed.
- **`rm -rf` takes only literal paths written out in full** — every target an absolute path typed as a
  plain string in the command itself. No variables (not even `${X:?}`-guarded), no globs, no command
  substitution, no loops or `xargs` building the list. Many targets → list them literally; a volatile
  CTP dir that plain rm cannot delete → `podman unshare rm -rf <the same literal path>`. The user
  denies any other form (2026-10-08).
- Read `.agents/AGENTS.md` (and the longer `.claude/CLAUDE.md`) before making code changes —
  they encode the behavioral guidelines this repo's owner expects.

## Agent skills

### Issue tracker

Issues are tracked as GitHub issues in `xmilex-git/workspace` (this repo's own remote; `gh` infers it). See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary — `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context — `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.
