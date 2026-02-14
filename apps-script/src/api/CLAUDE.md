# API Module — CLAUDE.md

## Files
- `WebApp.gs` — Main entry point. Routes doGet (getLogs, health, ping) and doPost (writeLog, reportChange).

## Conventions
- Use `var` for all declarations (enterprise convention)
- doPost routes via a switch on `body.action`
- Each action has a dedicated `handleXxx()` function
- Always generate a correlationId via `CorrelationId.generate()` at the top of doGet/doPost
- Return JSON via `ContentService.createTextOutput(JSON.stringify(...)).setMimeType(ContentService.MimeType.JSON)`

## What NOT to include
- No sync handlers (handleSyncRequest, handleReferralSync, etc.) — those are enterprise-only
- No direct sheet manipulation — delegate to LogService or ChangeTracker

## Phase 2 modification
The `reportChange` case in doPost calls `handleReportChange()` which delegates to `ChangeTracker.notify()`.
See `plan.md` Task 2.2 for the exact code.

## Recent changes
@changelog.md
