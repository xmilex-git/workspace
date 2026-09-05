9. when develop/execute/review CUBRID, use CUBRID_SSOT.md and justfile.

Whenever modifying CUBRID source code, ALWAYS consult the `cpp-perf-rules` skill (C/C++ performance rulebook) and apply its rules.

Division of labor: the lead performs implementation and verification planning. The following tasks MUST be handed off to a subagent: build, server start & query execution, data loading, core analysis, gdb analysis, error reproduction, and callstack analysis from a core file.

Delegation model: choose by the lead's model family — **GPT/Codex → Sol (`gpt-5.6-sol`); Claude → Sonnet** — using the current harness's subagent facility. Apply this routing to research subagents and execution workers, including existing map Notes or tickets that say "Sonnet"; preserve their task boundaries and execution contracts. An explicit user instruction about the worker model or direct lead execution takes precedence.

Delegation execution contract (CUBRID_SSOT.md 환경·운영 16–17 — include VERBATIM in every delegation prompt; incidents recur whenever it is omitted):
- Finite gate work (incremental build, unit, smoke — steps that each finish within ~10 min) runs as FOREGROUND blocking commands, chained in one continuous turn. run_in_background/nohup/monitors are FORBIDDEN for such steps. Only a full fresh build may go background, and then the SAME turn must bounded-poll its completion marker (`timeout ... until grep ...`) — never end a turn "waiting for a notification".
- The worker must deliver its final report in the same turn the work finishes, BEFORE going idle.

CTP execution rule (every suite; 2026-08-28 incident: CTP's teardown runs `pkill cub` and `kill -9` over `ps -u $USER`, killing EVERY cub_* of this user on any port — the port registry cannot protect against it):
- Every CTP run, whole or subset, by the lead or any delegated worker, goes through `just ctp <sql|medium|shell|ha_shell> [DIRS...]` (containers) or `just ctp-rerun <CI URL>`. Never `ctp.sh` on the host, never resurrect a host-side recipe. Include this rule in delegation prompts whenever the task may run CTP.
- The testcase ref is never implicit: pass `PR=<n>` or `TC_REF=<ref>`, or let it infer the PR from `WORKSPACE`. A run with none of the three refuses rather than validate a PR against develop testcases.
- `medium` and `ha_shell` are never sharded (`SHARDS>1` is refused). Details: the `ctp-run` skill; rationale: `docs/adr/0017-ctp-runner-on-cubridci-image.md`.

These guidelines intentionally bias toward caution, traceability, and minimal change over speed. For trivial tasks, use judgment.

0. Default Stance: Distrust and Verify

Treat external input, model output, and even future assumptions as untrusted until verified.

Do not blindly trust generated dates, inferred values, parsed fields, scores, or mappings. Reconstruct or validate them from reliable sources when possible. Clamp bounded values to their valid ranges. Test normal cases, mapped cases, None/empty cases, and tampered or malformed cases when relevant.

Prefer contractual thinking: define what is allowed, what is rejected, and what must be proven before the code relies on it.

1. Think Before Coding

Do not assume. Do not hide confusion. Surface tradeoffs early.

Before implementing:

State assumptions explicitly.
If uncertain, ask or name the uncertainty.
If multiple interpretations exist, present them instead of silently choosing one.
If a simpler approach exists, say so.
Push back when the requested solution seems overcomplicated, risky, or broader than necessary.
If something is unclear enough to affect correctness, stop and clarify.

For multi-step tasks, state a brief plan with verification points:

Implement or change X → verify with Y.
Add or update test Z → verify failure before fix when possible, then pass after fix.
Run relevant checks → verify no unintended behavior changed.
2. Define Boundaries Before Solving

Open scope by convergence, not expansion.

Before making changes, actively identify what will not be touched.

Examples:

Do not refactor adjacent code unless required.
Do not change formatting outside the edited lines.
Do not alter public behavior unrelated to the request.
Do not introduce new configuration, abstractions, or features unless explicitly required.

The goal is to make the change radius clear before implementation begins.

3. Simplicity First

Write the minimum code that solves the problem.

Avoid speculative engineering:

No features beyond what was asked.
No abstractions for single-use code.
No “flexibility” or “configurability” that was not requested.
No error handling for impossible scenarios.
No broad rewrites when a local fix is enough.

If the solution is 200 lines and could be 50, rewrite it.

Ask: “Would a senior engineer consider this overcomplicated?”
If yes, simplify.

4. Surgical Changes

Touch only what is necessary. Clean up only the mess created by the current change.

When editing existing code:

Match existing style, even if another style seems better.
Do not “improve” adjacent code, comments, names, or formatting.
Do not refactor unrelated code.
If unrelated dead code is noticed, mention it instead of deleting it.
Remove imports, variables, functions, or comments made unused by your own change.
Do not remove pre-existing dead code unless asked.

Every changed line should trace directly to the user’s request.

5. Make Decisions Traceable

Externalize important decisions as explicit objects.

For non-trivial choices, assign decision IDs such as D1, D2, D3, and record:

the decision,
the reason,
the cost or tradeoff,
the escape hatch or rollback path.

Do not leave important rationale only in your head or in chat. Put it where future maintainers can find it: code comments, design notes, PR descriptions, commit messages, or test names.

Use comments sparingly, but when a decision is non-obvious, document why the code is shaped that way.

6. Prefer Reversibility

Prefer changes that can be undone, isolated, or reviewed independently.

When possible:

Build on existing structure instead of replacing it wholesale.
Keep behavioral changes separate from mechanical cleanup.
Preserve the reason for change in a separate commit, note, or decision record.
Avoid irreversible migrations or broad rewrites unless clearly justified.
Prefer small reviewable diffs over large clever ones.

A good change should be easy to review, easy to revert, and easy to explain.

7. Goal-Driven Execution

Convert vague tasks into verifiable goals.

Examples:

“Add validation” → write tests for invalid inputs, then make them pass.
“Fix the bug” → write or identify a test that reproduces the bug, then make it pass.
“Refactor X” → confirm behavior before and after remains equivalent.
“Support new case Y” → test old cases and new case Y.

Define success criteria before or during implementation. Weak criteria like “make it work” should be replaced with concrete checks.

8. Completion Means More Than Code Running

A task is complete only when the full unit of work is current and verified.

Depending on the task, completion may include:

behavior implemented,
relevant tests added or updated,
existing tests still passing,
documentation updated,
comments or decision notes updated,
edge cases checked,
assumptions and limitations stated.

Code that merely runs is not necessarily done.

These guidelines are working if diffs become smaller, unnecessary rewrites decrease, overcomplication decreases, and clarifying questions happen before implementation mistakes rather than after them.
