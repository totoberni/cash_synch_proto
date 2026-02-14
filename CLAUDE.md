# GAS Change Tracker Sandbox — CLAUDE.md

## Project Overview
Google Apps Script (GAS) web app that receives change notifications and forwards them to an external VPS.
This is a sandbox prototype — the code will later migrate into the enterprise `apps-script/` directory.

## Architecture
```
Developer (post-push script) → POST /exec → GAS Web App (doPost)
  → Write _CHANGE_LOG sheet row
  → Forward to VPS (if configured) via UrlFetchApp
  → Write trace to _LOGS via LogService
  → Return result JSON
```

## File Map
- `apps-script/src/api/WebApp.gs` — HTTP endpoints (doGet, doPost), routes by `action` parameter
- `apps-script/src/correlation/CorrelationId.gs` — Request correlation ID generation and propagation
- `apps-script/src/logging/LogService.gs` — Structured logging to `_LOGS` sheet (singleton service)
- `apps-script/src/tracking/ChangeTracker.gs` — NEW: Change notification service → VPS relay
- `stub-server/server.js` — Local Node.js stub that prints received payloads
- `scripts/` — Post-push trigger scripts (bash + PowerShell)

## Language & Runtime
- Google Apps Script (JavaScript, V8 runtime)
- No npm dependencies inside GAS — all code is vanilla JS
- GAS globals available: `UrlFetchApp`, `SpreadsheetApp`, `PropertiesService`, `CacheService`, `ContentService`, `ScriptApp`, `Logger`, `Utilities`, `Session`
- Node.js for stub-server only (zero dependencies)

## Conventions
- Service objects as singletons: `var ServiceName = { method: function() { ... } };`
- No ES6 modules — GAS loads all .gs files into a single global scope
- `var` not `let`/`const` (GAS V8 supports both, but enterprise uses `var` — match it)
- Error handling: try/catch → LogService.error() → return error in response JSON
- All HTTP responses: `ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(ContentService.MimeType.JSON)`
- Config via Script Properties (PropertiesService), never hardcoded
- `muteHttpExceptions: true` in every UrlFetchApp.fetch() call — CRITICAL

## Build & Deploy
```bash
cd apps-script && clasp push                        # Push to GAS
cd apps-script && clasp deploy -d "description"     # Create /exec deployment
cd apps-script && clasp deployments                 # List deployment IDs/URLs
```

## Test (dev URL — always runs HEAD)
```bash
GAS_DEV_URL="https://script.google.com/macros/s/1s0kbGNpO4CRjikhxvQHQwT7yTPDty9UfMqRW8_Z6zmH198F2iSyxgKXu/dev"
curl -s "$GAS_DEV_URL?action=ping" | jq .
curl -s "$GAS_DEV_URL?action=health" | jq .
```

## File Ownership — STRICT (agents must not cross these)
| Path | Owner | Access |
|------|-------|--------|
| `apps-script/src/api/WebApp.gs` | orchestrator / gas-tracker-agent | Orchestrator coordinates edits |
| `apps-script/src/tracking/ChangeTracker.gs` | gas-tracker-agent | Full ownership |
| `apps-script/src/correlation/CorrelationId.gs` | — | **READ-ONLY** (enterprise copy) |
| `apps-script/src/logging/LogService.gs` | — | **READ-ONLY** (enterprise copy) |
| `stub-server/` | tooling-agent | Full ownership |
| `scripts/` | tooling-agent | Full ownership |
| `docs/` | test-agent | Test reports |
| `.orchestrator/` | orchestrator | State management |
| `.claude/settings.json` | **HUMAN ONLY** | Agents cannot modify |

## DO NOT
- Do not modify CorrelationId.gs or LogService.gs — they are enterprise copies (enforced by settings.json deny rules)
- Do not use `let` or `const` in .gs files — use `var` for enterprise consistency
- Do not hardcode URLs — use Script Properties
- Do not write to `_LOGS` sheet directly — always go through LogService
- Do not write change records to `_LOGS` — use `_CHANGE_LOG` via ChangeTracker
- Do not add npm dependencies to the GAS code
- Do not modify .claude/settings.json — human-only (enforced by deny rules)
- Do not `git push` — human decides when to push
- Do not create, switch, or merge git branches autonomously

## Plan (source of truth for all implementation work)
@plan.md

## Orchestrator State
@.orchestrator/state.md

## Module Changelogs
@apps-script/src/api/changelog.md
@apps-script/src/tracking/changelog.md

## Mistakes and Gotchas
@gotchas.md
