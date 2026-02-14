# GAS Change Tracker Sandbox — CLAUDE.md

## Project Overview
Google Apps Script (GAS) web app that receives change notifications and forwards them to an external VPS.
This is a sandbox prototype — the code will later migrate into the enterprise `apps-script/` directory.

## Architecture
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

## Build & Deploy
- Push code: `cd apps-script && clasp push`
- Deploy: `cd apps-script && clasp deploy -d "description"`
- Test (dev): `curl "https://script.google.com/macros/s/{SCRIPT_ID}/dev?action=ping"`
- Test (prod): `curl "https://script.google.com/macros/s/{DEPLOYMENT_ID}/exec?action=ping"`

## File Ownership (agents)
- `apps-script/src/api/WebApp.gs` — Shared (orchestrator coordinates edits)
- `apps-script/src/tracking/ChangeTracker.gs` — tracking-agent
- `apps-script/src/correlation/CorrelationId.gs` — READ-ONLY (copied from enterprise, do not modify)
- `apps-script/src/logging/LogService.gs` — READ-ONLY (copied from enterprise, do not modify)
- `stub-server/` — tooling-agent
- `scripts/` — tooling-agent

## DO NOT
- Do not modify CorrelationId.gs or LogService.gs — they are enterprise copies
- Do not use `let` or `const` in .gs files — use `var` for enterprise consistency
- Do not hardcode URLs — use Script Properties
- Do not write to `_LOGS` sheet directly — always go through LogService
- Do not add npm dependencies to the GAS code

## Plan
@plan.md

## Module Changelogs
@apps-script/src/api/changelog.md
@apps-script/src/tracking/changelog.md

## Mistakes and gotchas
@gotchas.md