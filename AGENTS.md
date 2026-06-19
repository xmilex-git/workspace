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
`.agents/skills/`:

```
.claude/skills/<name> -> ../../.agents/skills/<name>
```

`.agents/skills/` is the single source of truth; never edit a skill "through" the symlink as
if it were a separate copy. To add a skill, create it under `.agents/skills/` and add the
matching relative symlink under `.claude/skills/`.

Bundled skills: caveman, ctp-parallel, cubrid-build, cubrid-deps-check, cubrid-jira-issue-write,
cubrid-manual, cubrid-pr-create, cubrid-pr-review, cubrid-server-control, cubrid-shell-run,
design-an-interface, grill-me, grill-with-docs, improve-codebase-architecture, jira,
md-to-presentation, obsidian-vault, remote-claude, remote-codex, setup-matt-pocock-skills,
to-issues, to-prd, triage, write-a-skill.

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
- **cubrid-shell-run** — writes its scratch conf under `"$WORKSPACE/.claude/scratch/"`.

`cubrid-deps-check` also takes the workspace as its first argument (it diagnoses a checkout's
build/test dependencies). The other skills are workspace-agnostic or operate on fixed
infrastructure and take no `$WORKSPACE`.

## Diagnostics

Run `cubrid-deps-check <workspace>` to get a read-only `[OK]/[MISS]/[WARN]` report of the build
and test prerequisites for a CUBRID checkout. It never mutates anything and never executes its
own fix suggestions — it only prints them.

## House rules

- **Never write scratch to `/tmp` or `$TMPDIR`** (the host's `/tmp` is tmpfs-backed and OOMs).
  Use the workspace's own `.claude/scratch/` for workspace-scoped temp files, or `~/.claude/scratch/`
  otherwise. See `.agents/AGENTS.md` / `.claude/CLAUDE.md` for the full policy.
- The locale `*.so` artifacts and `.git_ignored_dir/` are git-ignored and must never be committed.
- Read `.agents/AGENTS.md` (and the longer `.claude/CLAUDE.md`) before making code changes —
  they encode the behavioral guidelines this repo's owner expects.
