# Changelog — tracking

<!-- AUTO-MANAGED: Entries appended by PostToolUse hook -->

## 2026-02-15 — Phase 2: ChangeTracker Service Implementation

**Created**: `ChangeTracker.gs`

**Summary**: Implemented full ChangeTracker singleton service with change notification and VPS relay capabilities.

**Methods implemented**:
- `notify(changeData, correlationId)` — Main entry point: writes to _CHANGE_LOG sheet, optionally forwards to VPS, logs result
- `getOrCreateChangeLogSheet()` — Auto-creates _CHANGE_LOG sheet with proper headers and column widths
- `isVpsConfigured()` — Checks Script Properties for CHANGE_TRACKER_ENABLED and CHANGE_TRACKER_VPS_URL
- `getVpsUrl()` — Returns VPS endpoint URL from Script Properties
- `buildPayload(changeData, correlationId)` — Constructs JSON payload with scriptId, scriptEndpoint, timestamp, correlationId, and change details
- `postToVps(url, payload)` — POSTs to VPS with muteHttpExceptions: true, returns status and truncated response body (500 char limit)

**Key features**:
- Stub-safe: skips VPS call gracefully if not configured
- Always writes to _CHANGE_LOG sheet first (audit trail even if VPS fails)
- Truncates VPS response to 500 chars to prevent sheet cell overflow
- Uses LogService.info() for lightweight traces to _LOGS
- All config via Script Properties (no hardcoded URLs)
- Uses `var` exclusively (enterprise convention)
- Critical `muteHttpExceptions: true` in UrlFetchApp.fetch() to prevent handler crashes on 4xx/5xx responses
