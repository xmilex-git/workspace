---
name: jira
description: Look up CUBRID JIRA issue context. Use when a CBRD-XXXXX ticket is mentioned or when the user asks about a JIRA issue.
argument-hint: <CBRD-XXXXX>
---

Look up CUBRID JIRA issue context.

Given a JIRA ticket ID (e.g., CBRD-25123), fetch the issue details from the CUBRID JIRA REST API and present a comprehensive summary. The argument is the ticket ID.

If no ticket ID is provided, ask for one.

$ARGUMENTS

Steps:
1. First, verify the `uv` executable exists in PATH by running `which uv`. If it does not exist, **halt immediately** and tell the user: "Error: `uv` is not installed or not in PATH. Install it first: https://docs.astral.sh/uv/getting-started/installation/"

2. Verify `cubrid-jira` exists in PATH by running `which cubrid-jira`. If it does not exist, **halt immediately** and tell the user:

   ```
   Error: `cubrid-jira` is not installed.

   Install it:
       uv tool install git+https://github.com/vimkim/cubrid-jira
   ```

3. Use the Bash tool to run:

   ```
   cubrid-jira search TICKET_ID
   ```

4. Present the output to the user as-is. The command searches local cache first and fetches from JIRA if missing, outputting readable markdown.
5. If the command fails after a successful preflight, the JIRA instance is likely unreachable — report the exact error to the user rather than guessing.
6. A `cubrid-jira` subcommand that fails with a JQL or HTTP error is retried once after `uv tool install --force git+https://github.com/vimkim/cubrid-jira`, before any workaround: an install older than upstream `2b87ad6` talks to `http://jira.cubrid.org`, whose https redirect double-encodes the query. (P1)
