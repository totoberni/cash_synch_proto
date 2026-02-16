# Changelog — api

<!-- AUTO-MANAGED: Entries appended by PostToolUse hook -->

## 2026-02-16 — Phase 0: Clean Up Test Artifacts

**Modified**: `WebApp.gs`

**Summary**: Removed stray bash command from manual testing that would have caused GAS script error.

**Changes**:
- Removed line 19: `echo "// manual test $(date)"` (invalid JavaScript)
- Restored proper file structure: doGet now has clean flow from `var response;` directly to `try {` block

**Verification**:
- No `let`/`const` declarations (all `var` as per enterprise convention)
- No other test artifacts found in file
- File structure validated

## 2026-02-15 — Phase 2: reportChange Endpoint Integration

**Modified**: `WebApp.gs`

**Summary**: Added reportChange action to doPost handler and integrated with ChangeTracker service.

**Changes**:
1. Added `case 'reportChange':` to doPost switch statement (line 93-95)
2. Updated availableActions in default error response to include 'reportChange'
3. Added `handleReportChange(body, correlationId)` function after handleGetLogs (lines 166-189)

**handleReportChange functionality**:
- Validates required fields: `changelog` (must be string), `files` (must be non-empty array)
- Returns validation error with correlationId if validation fails
- Constructs changeData object with author (defaults to 'unknown'), files, changelog, commitHash
- Delegates to `ChangeTracker.notify()` for processing
- Returns success status, correlationId, and full tracking result object

**API contract**:
- Request: `{ action: "reportChange", author: string, files: string[], changelog: string, commitHash?: string }`
- Response (success): `{ success: true, correlationId: string, tracking: { changeLogRow, vpsStatus, vpsResponse, error? } }`
- Response (validation error): `{ error: string, correlationId: string }`
