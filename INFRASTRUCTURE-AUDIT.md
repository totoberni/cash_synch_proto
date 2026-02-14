# Infrastructure Audit v2 — GAS Change Tracker Orchestrator Setup

> Generated: 2026-02-14
> For: Alberto — Merged version (my agent infra + git repo's GAS conventions)

---

## What changed from v1

| File | Change |
|------|--------|
| `.claude/settings.json` | **Merged** — Added enterprise file write protection, settings.json self-protection, clasp login deny, gotchas hook. Used `$CLAUDE_PROJECT_DIR` path format. |
| `.claude/hooks/check-gotchas-on-error.sh` | **NEW** — Fires on Bash failures, searches gotchas.md for relevant known issues, surfaces them as context. |
| `.claude/hooks/update-changelog.sh` | **Updated** — Uses `$CLAUDE_PROJECT_DIR` path format. Added gotchas.md to skip list. |
| `.claude/commands/deploy.md` | **NEW** — `/deploy` slash command for `clasp deploy` workflow with gotcha notes. |
| `CLAUDE.md` | **Merged** — Combined git version (GAS globals, DO NOT section, @plan.md, @gotchas.md) with my version (@.orchestrator/state.md, module boundaries table). Added actual Script ID and dev URL. |
| `.claude/agents/orchestrator.md` | **Updated** — Added Script ID, gotchas handling, settings.json protection rule. |
| `.claude/agents/gas-tracker-agent.md` | **Updated** — Added Script ID, gotchas.md in pre-start checklist, settings.json to NEVER TOUCH. |
| `.claude/agents/tooling-agent.md` | **Updated** — Added gotchas.md reference, settings.json to NEVER TOUCH. |
| `.claude/agents/test-agent.md` | **Updated** — Added Script ID/dev URL, gotchas caching note, settings.json to NEVER TOUCH. |
| `.claude/rules/orchestrator-protocol.md` | **Updated** — Added protected files section (settings.json, enterprise copies), gotchas discipline section. |

## Deployment: copy-paste replacement

Extract the zip to your repo root. These files **replace** the git versions:

```
CLAUDE.md                                    ← REPLACE (merged version)
.claude/settings.json                        ← REPLACE (merged version)
.claude/hooks/update-changelog.sh            ← REPLACE (updated paths)
.claude/hooks/check-gotchas-on-error.sh      ← NEW (create)
.claude/commands/deploy.md                   ← NEW (create)
.claude/commands/push-gas.md                 ← NEW (create)
.claude/commands/test-gas.md                 ← NEW (create)
.claude/commands/status.md                   ← NEW (create)
.claude/agents/orchestrator.md               ← NEW (create)
.claude/agents/gas-tracker-agent.md          ← NEW (create)
.claude/agents/tooling-agent.md              ← NEW (create)
.claude/agents/test-agent.md                 ← NEW (create)
.claude/rules/orchestrator-protocol.md       ← NEW (create)
.orchestrator/state.md                       ← NEW (create dir + file)
.orchestrator/task-queue.md                  ← NEW (create)
.orchestrator/active-tasks.md                ← NEW (create)
.orchestrator/decisions.md                   ← NEW (create)
.orchestrator/changelog.md                   ← NEW (create)
.orchestrator/inbox/.gitkeep                 ← NEW (create dir + file)
apps-script/src/api/CLAUDE.md               ← NEW (create)
apps-script/src/api/changelog.md             ← NEW (create)
apps-script/src/correlation/CLAUDE.md        ← NEW (create)
apps-script/src/correlation/changelog.md     ← NEW (create)
apps-script/src/logging/CLAUDE.md            ← NEW (create)
apps-script/src/logging/changelog.md         ← NEW (create)
apps-script/src/tracking/CLAUDE.md           ← NEW (create)
apps-script/src/tracking/changelog.md        ← NEW (create)
stub-server/CLAUDE.md                        ← NEW (create)
stub-server/changelog.md                     ← NEW (create)
scripts/CLAUDE.md                            ← NEW (create)
scripts/changelog.md                         ← NEW (create)
```

These existing git files are **kept as-is** (not in zip):
```
gotchas.md                                   ← KEEP (already exists, referenced by @import)
plan.md                                      ← KEEP (already exists, referenced by @import)
apps-script/.clasp.json                      ← KEEP (already exists with correct Script ID)
apps-script/appsscript.json                  ← KEEP (if exists)
```

## Post-copy steps

```bash
# 1. Make hooks executable
chmod +x .claude/hooks/update-changelog.sh
chmod +x .claude/hooks/check-gotchas-on-error.sh

# 2. Verify jq is installed (required by both hooks)
jq --version

# 3. Set env vars
export CLAUDE_CODE_SUBAGENT_MODEL=sonnet
export CLAUDE_CODE_EFFORT_LEVEL=medium

# 4. Start orchestrator
tmux new -s orchestrator
claude --agent orchestrator
```

## Protection layers

| What's protected | How | Why |
|-----------------|-----|-----|
| Enterprise files (CorrelationId.gs, LogService.gs) | settings.json deny: Write/Edit/MultiEdit on `apps-script/src/correlation/*` and `logging/*` | Verbatim enterprise copies, must not be modified |
| Settings.json itself | settings.json deny: Write/Edit/MultiEdit on `**/*settings.json` and `.claude/settings.json` | Prevents agents from weakening their own permissions |
| .env files | settings.json deny: Read/Write on `.env*` | Secrets protection |
| Git push/merge/branch delete | settings.json deny on those commands | Human-only operations |
| clasp login | settings.json deny on `clasp login*` | Auth is human-only |

## Gotchas integration

The gotchas system works at three levels:

1. **`gotchas.md`** — Human-curated + agent-appended knowledge base of solved issues. Imported into CLAUDE.md via `@gotchas.md`, so it loads at every session start.

2. **`check-gotchas-on-error.sh` hook** — Fires automatically on every failed Bash command. Extracts keywords from the error output and searches gotchas.md for matching entries. Surfaces them as inline context so the agent sees relevant workarounds immediately.

3. **Agent protocol** — All agent definitions include "read gotchas.md before you start" and "append to gotchas.md when you solve something new". The orchestrator-protocol rules enforce this globally.
