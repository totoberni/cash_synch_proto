# Changelog — tracking

<!-- AUTO-MANAGED: Entries appended by PostToolUse hook -->

## 2026-03-01 — Phase 5.5: API Response Hygiene + Status Codes

**Modified**: `ChangeTracker.gs`

**Summary**: Cleaned up API responses and added numeric status codes for both `notify()` and `notifyBatch()`.

**Changes**:
1. Added `statusCode: 0` to result init (success path) — set to `1` only in catch block
2. Removed `error: null` from result init — `error` field only present when `statusCode === 1`
3. Removed `vpsResponse: null` from result init in both methods
4. Removed `result.vpsResponse` assignment — full VPS response body no longer leaked to caller (persisted in `_CHANGE_LOG` sheet)
5. Updated JSDoc return types to document `statusCode: 0|1`

**Success response**: `{ statusCode: 0, changeLogRow: 18, vpsStatus: 200, vpsAck: true, vpsBatchId: "..." }`
**Error response**: `{ statusCode: 1, changeLogRow: null, vpsStatus: "skipped", error: "message" }`

## 2026-03-01 — Phase 1 (Plan 2): Batch Notification Support

**Modified**: `ChangeTracker.gs`

**Summary**: Added batch notification capability to ChangeTracker singleton for receiving multi-commit change batches from GitHub Actions.

**Methods added**:
- `notifyBatch(batchData, correlationId)` — Handles batch change notifications: writes batch summary to `_CHANGE_LOG` sheet, optionally forwards to VPS via `postToVps()`, parses VPS ack response (`ack: true` + `batchId`), updates sheet row with VPS result, logs via LogService
- `buildBatchPayload(batchData, correlationId)` — Constructs JSON payload for VPS with scriptId, scriptEndpoint, timestamp, correlationId, and full batch details (trigger, triggeredBy, repository, range, commits, filesChanged, pathFilter)

**Key features**:
- Reuses existing `getOrCreateChangeLogSheet()`, `isVpsConfigured()`, `getVpsUrl()`, and `postToVps()` methods
- Batch summary written to changelog column: "Batch: N commits (abc1234..def5678)"
- VPS ack parsing: extracts `ack` boolean and `batchId` from JSON response
- Stub-safe: gracefully skips VPS call if not configured (same pattern as `notify()`)
- No `let`/`const` — all `var` (enterprise convention)
- Existing `notify()`, `buildPayload()`, and `postToVps()` methods unchanged

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
