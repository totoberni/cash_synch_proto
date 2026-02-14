---
globs: ["**/*"]
---

# Orchestrator Protocol Rules

## File ownership is STRICT
Before editing any file, verify you are the designated owner per CLAUDE.md File Ownership table.
If you are not the owner, do NOT edit the file. Report the need to the orchestrator instead.

## Protected files — NEVER modify
- `.claude/settings.json` — Human-only. Deny rules enforced at tool level.
- `.claude/settings.local.json` — Human-only.
- `apps-script/src/correlation/*` — Enterprise read-only copies.
- `apps-script/src/logging/*` — Enterprise read-only copies.
These protections are enforced by settings.json deny rules. Do not attempt to circumvent them.

## Plan.md is the source of truth
All implementation specs come from `plan.md`. Do not invent requirements.
If something is ambiguous, check plan.md first, then ask the orchestrator.

## Gotchas discipline
- Before debugging a failure, check `gotchas.md` for known issues
- The `check-gotchas-on-error.sh` hook auto-surfaces relevant gotchas when Bash commands fail
- When you solve a new issue, append it to `gotchas.md` so future agents benefit
- Format: add a row to the relevant appendix table, or create a new section if needed

## Changelog discipline
After completing work on any module, update that module's `changelog.md`.
The PostToolUse hook handles individual file edits automatically.
You must add a summary entry for logical units of work (e.g., "Implemented ChangeTracker.notify()").

## Git discipline
- NEVER create, switch, or merge branches autonomously
- NEVER `git push` — the human decides when to push
- Commits must use conventional format: `feat:`, `fix:`, `test:`, `docs:`, `chore:`
- One commit per phase completion (as specified in plan.md)

## GAS-specific rules
- All .gs files use `var` only. No `let`/`const`.
- All UrlFetchApp.fetch() calls must include `muteHttpExceptions: true`
- Sheet names starting with `_` are system sheets. Use the correct one for your module.
- `_CHANGE_LOG` for ChangeTracker. `_LOGS` for LogService. Never mix.

## Communication
- Agents report results by returning structured summaries to the orchestrator
- If blocked, state exactly what you're blocked on and what human action is needed
- If you encounter an error not covered by plan.md or gotchas.md, log it and report to orchestrator
