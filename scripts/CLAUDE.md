# Scripts — CLAUDE.md

## Files
- `post-push-notify.sh` — Bash script to gather git metadata and POST to GAS web app
- `post-push-notify.ps1` — PowerShell equivalent for Windows

## Common behavior
Both scripts:
1. Read `GAS_WEBAPP_URL` from environment (fallback to placeholder URL)
2. Gather from git: last commit message, short hash, author name, changed files in `apps-script/src/`
3. Construct JSON payload with `action: "reportChange"`
4. POST to the GAS web app URL
5. Print what's being sent and the response
6. Handle missing git gracefully (fallback values)

## Bash prerequisites
- `curl`, `jq`, `git` must be installed

## PowerShell prerequisites
- Built-in `Invoke-RestMethod` and `ConvertTo-Json` (no external tools)

## Owner
tooling-agent (Phase 3)
