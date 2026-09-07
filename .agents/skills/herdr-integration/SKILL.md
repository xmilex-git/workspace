---
name: herdr-integration
description: "Delegate Codex execution tasks to Claude Sonnet using herdr agent in a dedicated task session. Use for repository-mandated build, validation, execution, reproduction and core/gdb delegation through Herdr."
---

# Herdr integration

S0 remains in its current conversation and execution environment. Claude Sonnet runs in a fresh, dedicated Herdr session for each delegated job. Use native Herdr waits; no Codex conversation migration, callback bridge or Python polling loop.

## Prepare a task session

1. Read the installed `herdr --help`, `herdr agent`, `herdr workspace`, and `herdr session` syntax. Confirm `claude` is available. No `HERDR_ENV` inheritance is required for S0; always target the explicit session. Do not install official integration hooks merely to run this workflow.
2. Choose a never-reused session name and worker name. Check `herdr session list --json` to avoid existing sessions. Record the task, explicit checkout, names, start time, and absolute deadline **7200 seconds after session creation begins** under the tooling repository's `.git_ignored_dir/scratch/herdr-integration/<task-id>/`. All logs/results go there, never `/tmp`.
3. Launch `herdr --session <name> server` as a detached infrastructure process with stdout/stderr captured in that directory. This is the session host, not a background build/test. Record its PID. Wait briefly for startup readiness using bounded startup retries only; then create a workspace with `herdr --session <name> workspace create --cwd <checkout> --label <task-id> --no-focus`. Parse `.result.root_pane.pane_id`; never invent IDs or attach to the user's default session.
4. Start Sonnet in the returned shell pane:

```bash
herdr --session <name> agent start <worker> --kind claude --pane <pane-id> -- --model sonnet
```

Preserve existing user permissions; do not add approval-bypass flags. A startup error may leave an agent alive: inspect its state/output rather than starting duplicates. If preparation fails, save the error and stop the owned session.

## Delegate and wait

Give Claude the bounded task, explicit checkout, absolute report path, deadline, and success criteria. Include the repository's delegation execution contract verbatim, plus its container-only CTP rules when relevant. Claude executes the task itself, saves a final report including commands/results/blockers, and finishes in the same turn. It does not create another coordinator or send callbacks to S0.

Compute `remaining_ms = max(0, (deadline - current_time) * 1000)` immediately before every wait. Never reset the 2-hour budget after questions, retries or follow-up work. If no time remains, proceed to timeout cleanup.

```bash
herdr --session <name> agent prompt <worker> "<task and execution contract>" --wait --timeout <remaining_ms>
```

The native wait returns on idle/done/blocked. After dispatch, S0 waits on that call or does independent work outside the delegated scope. If the shell tool yields a running process handle, resume that same handle with bounded waits; a tool yield is not a worker state transition. Native `agent wait <worker> --timeout <remaining_ms>` resumes waiting after an answered dialog or interrupted CLI wait.

**Preserve context isolation.** While the worker runs, leave its terminal, logs, intermediate artifacts and investigation to the worker. Do not poll `agent get`/`agent read`, tail its files, or duplicate its analysis to narrate progress. If a user-facing update is required, state that the delegated task is awaiting its result; that is not a reason to inspect the worker.

Inspect only when the native wait returns an actionable event:

- **Idle/done:** read the final report first. Idle is not proof of success; verify the report against the assigned criteria. Request a concise missing result if necessary. Read terminal output only to recover a missing report or clarify a specific reported failure.
- **Blocked/question/approval:** use `agent get` and a bounded `agent read --source recent-unwrapped --lines 120` to identify the exact request, then handle it below.
- **Transport failure or deadline expiry:** inspect only enough state/output for recovery or cleanup. `--source visible` is reserved for those exceptions when the worker is still running, or an explicit user request to inspect it.

Keep raw evidence on disk. Bring the worker's conclusions, verification summary and relevant evidence paths into S0's context; load a specific excerpt only when a concrete decision requires it.

## Handle approval and questions

When blocked, the requesting Codex reads the exact dialog and decides the answer. Within existing user authorization, respond using `agent send-keys` for an approval dialog or `agent prompt` for a normal textual question once the frontend accepts prompts. Do not send a prompt into an approval dialog or blindly approve every request.

Ask the user through S0 only for new authorization or information unavailable from the task/context. Keep the owned session while awaiting an answer, but the original 2-hour deadline still applies. No timer or background supervisor is installed. On receiving an answer, recheck the deadline before resuming work; if expired, perform timeout cleanup instead. Native wait cannot automatically close a session while S0 is awaiting user input.

A transport error is not proof the task failed. Inspect the named agent and saved report before retrying; do not duplicate a command that may already have run.

## Finish and close

On confirmed success or failure, preserve the report and relevant terminal output first. Then stop the dedicated session with `herdr session stop <name> --json`, verify it is no longer running, and write `closed` in the task directory. Delete the stopped session entry with `herdr session delete <name> --json` after results are outside the session directory. Never stop S0, the default session, or another task's session.

On deadline expiry, preserve state/output, request interruption with `agent send-keys <worker> ctrl+c`, allow **10 seconds** for cleanup, then stop the dedicated session and record timeout failure. S0 performs this cleanup when the native wait times out or it observes the expired deadline. A native wait timeout alone does not stop Claude. If session shutdown fails, explicitly report the remaining session/processes; do not declare cleanup complete or use a user-wide kill.

Retain saved task results after session deletion. Only transient Herdr sessions are automatically removed. Follow-up implementation decisions and the final user report remain S0's responsibility.
