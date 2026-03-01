# plan.md — GAS Change Tracker Sandbox

**Status**: ACTIVE  
**Current Phase**: 1  
**Last Updated**: 2026-02-13

> **For orchestrator agents**: This is the single source of truth for implementation work.
> Read CLAUDE.md for project conventions. Check module changelogs before editing files.
> Update the "Status" field and "Current Phase" as you progress.

---

## Architecture Diagram

```
Developer (post-push script)
    │
    │  POST /exec  { action: "reportChange", author, files, changelog, commitHash }
    ▼
┌─────────────────────────────────────────────┐
│  GAS Web App (WebApp.gs — doPost)           │
│                                             │
│  1. Route to handleReportChange()           │
│  2. Validate payload                        │
│  3. Call ChangeTracker.notify()             │
│     ├─ Write row to _CHANGE_LOG sheet       │
│     ├─ Read VPS URL from Script Properties  │
│     ├─ If URL set → POST to VPS             │
│     └─ If URL empty → skip (stub-safe)      │
│  4. Write INFO trace to _LOGS via LogService│
│  5. Return result JSON to caller            │
└─────────────────────────────────────────────┘
    │
    │  POST /changelog  (UrlFetchApp.fetch)
    ▼
VPS / Local Stub Server
    │
    │  { received: true, timestamp }
    ▼
Response flows back through GAS to caller
```

---

## Phase 1 — Deploy Base Web App

**Goal**: Get doGet + doPost working with health, ping, writeLog, getLogs. Prove the sandbox behaves identically to the enterprise GAS.

**Agent assignment**: Orchestrator (direct, no subagent needed — these are file copies with minor edits).

### Task 1.1 — Copy Enterprise Files

| Action | Source | Target | Notes |
|--------|--------|--------|-------|
| COPY | Enterprise CorrelationId.gs (provided in CLAUDE.md context or uploaded) | `apps-script/src/correlation/CorrelationId.gs` | Verbatim, no changes |
| COPY | Enterprise LogService.gs | `apps-script/src/logging/LogService.gs` | Verbatim, no changes |
| CREATE | Based on enterprise WebApp.gs | `apps-script/src/api/WebApp.gs` | See Task 1.2 |

**Verification**: All three files exist at correct paths. `clasp status` from `apps-script/` shows them.

### Task 1.2 — Create Sandbox WebApp.gs

Create `apps-script/src/api/WebApp.gs` based on the enterprise version with these modifications:

**KEEP** (copy verbatim from enterprise):
- `doGet()` function — full routing: getLogs, health, ping
- `doPost()` function — routing structure with: writeLog action
- `handleGetLogs()` function
- `handleHealthCheck()` function

**REMOVE** (not needed in sandbox):
- `handleSyncRequest()` and the sync switch (referral, tasks, hr, finance)
- `handleReferralSync()`, `handleTasksSync()`, `handleHRSync()`, `handleFinanceSync()`
- The `sync` case in the doPost switch

**ADD** (placeholder for Phase 2):
- A comment in the doPost switch: `// Phase 2: reportChange action will be added here`

**Verification**: The file contains doGet, doPost, handleGetLogs, handleHealthCheck. No references to sync engines. A placeholder comment exists for reportChange.

### Task 1.3 — Push and Deploy

```bash
cd apps-script
clasp push
```

**Verification**: `clasp push` outputs "Pushed N files" with no errors. N should be 4 (appsscript.json + 3 .gs files).

### Task 1.4 — Test Base Endpoints

Run these curl commands and verify responses:

```bash
# Replace SCRIPT_ID with actual value from .clasp.json
GAS_DEV_URL="https://script.google.com/macros/s/SCRIPT_ID/dev"

# Test 1: Ping
curl -s "$GAS_DEV_URL?action=ping" | jq .
# EXPECT: { "status": "ok", "timestamp": "...", "correlationId": "gas_..." }

# Test 2: Health
curl -s "$GAS_DEV_URL?action=health" | jq .
# EXPECT: { "status": "healthy", "spreadsheet": { "id": "...", "name": "CashProto", "sheets": ... } }

# Test 3: Write a log
curl -s -X POST "$GAS_DEV_URL" \
  -H "Content-Type: application/json" \
  -d '{"action":"writeLog","level":"INFO","category":"test.setup","message":"Phase 1 verification"}' | jq .
# EXPECT: { "success": true, "correlationId": "gas_..." }

# Test 4: Retrieve that log
# Use the correlationId from Test 3
curl -s "$GAS_DEV_URL?action=getLogs&correlationId=CORRELATION_ID_FROM_TEST_3" | jq .
# EXPECT: { "correlationId": "...", "count": 1, "logs": [...] }
```

**Verification**: All 4 tests return expected JSON. The Google Sheet now has a `_LOGS` tab with at least 1 entry.

### Task 1.5 — Commit

```bash
git add -A
git commit -m "feat: Phase 1 — base GAS web app with logging and correlation"
```

### Phase 1 Completion Criteria

- [ ] CorrelationId.gs exists at correct path (unmodified enterprise copy)
- [ ] LogService.gs exists at correct path (unmodified enterprise copy)
- [ ] WebApp.gs exists with ping, health, writeLog, getLogs (no sync handlers)
- [ ] `clasp push` succeeds
- [ ] All 4 curl tests pass
- [ ] `_LOGS` sheet auto-created in Google Sheet
- [ ] Committed to git

---

## Phase 2 — Add Change Tracking Infrastructure

**Goal**: Implement ChangeTracker.gs service and wire the reportChange action into WebApp.gs.

**Agent assignment**: Use `gas-tracker-agent` subagent for implementation.

### Task 2.1 — Create ChangeTracker.gs

**File**: `apps-script/src/tracking/ChangeTracker.gs`

**Read first**: `apps-script/src/tracking/CLAUDE.md` for the full specification.

Implement a singleton service object `ChangeTracker` with these methods:

```
var CHANGE_LOG_SHEET_NAME = '_CHANGE_LOG';

var ChangeTracker = {

  notify: function(changeData, correlationId) { ... }
    // 1. Write to _CHANGE_LOG sheet (always, even if VPS is down)
    // 2. If VPS configured and enabled → POST payload via UrlFetchApp
    // 3. Log result to LogService (category: changetracker.notify)
    // 4. Return { changeLogRow, vpsStatus, skipped }

  getOrCreateChangeLogSheet: function() { ... }
    // Same pattern as LogService.getOrCreateLogSheet()
    // Headers: timestamp, correlationId, author, files, changelog, commitHash, vpsUrl, vpsStatus, vpsResponse

  isVpsConfigured: function() { ... }
    // Read CHANGE_TRACKER_ENABLED and CHANGE_TRACKER_VPS_URL from Script Properties
    // Return true only if both are set and enabled !== "false"

  getVpsUrl: function() { ... }
    // Return CHANGE_TRACKER_VPS_URL from Script Properties

  buildPayload: function(changeData, correlationId) { ... }
    // Return: {
    //   scriptId: ScriptApp.getScriptId(),
    //   scriptEndpoint: PropertiesService.getScriptProperties().getProperty('GAS_DEPLOYMENT_URL') || 'not-configured',
    //   timestamp: new Date().toISOString(),
    //   correlationId: correlationId,
    //   change: {
    //     author: changeData.author,
    //     files: changeData.files,
    //     changelog: changeData.changelog,
    //     commitHash: changeData.commitHash || null
    //   }
    // }

  postToVps: function(url, payload) { ... }
    // UrlFetchApp.fetch(url, {
    //   method: 'post',
    //   contentType: 'application/json',
    //   payload: JSON.stringify(payload),
    //   muteHttpExceptions: true    // ← CRITICAL: prevents GAS from throwing on 4xx/5xx
    // })
    // Return { status: responseCode, body: truncatedResponseText }
};
```

**Key implementation details**:
- Use `var` for all declarations (enterprise convention).
- `muteHttpExceptions: true` in UrlFetchApp options — without this, GAS throws on non-2xx responses and the entire handler fails.
- Truncate VPS response body to 500 chars before writing to sheet (prevent sheet cell overflow).
- The `_CHANGE_LOG` sheet is **completely separate** from `_LOGS`. Never write change records to `_LOGS`.
- The LogService.info() call in `notify()` is a single lightweight trace: `LogService.info('changetracker.notify', 'Change notification processed', { author, fileCount, vpsStatus })`.

**Verification**: File exists, contains `var ChangeTracker = { ... }` with all methods. No `let`/`const`. No hardcoded URLs.

### Task 2.2 — Wire reportChange into WebApp.gs

Edit `apps-script/src/api/WebApp.gs`:

**Add** to the `doPost` switch statement (replace the Phase 2 placeholder comment):

```javascript
case 'reportChange':
  response = handleReportChange(body, correlationId);
  break;
```

**Add** the handler function (after the existing handler functions):

```javascript
/**
 * Handle reportChange action — receives code change metadata and forwards to VPS
 * @param {Object} body - Request body with change details
 * @param {string} correlationId - Request correlation ID
 * @returns {Object} Result with tracking info
 */
function handleReportChange(body, correlationId) {
  // Validate required fields
  if (!body.changelog || typeof body.changelog !== 'string') {
    return { error: 'Missing or invalid field: changelog (string required)', correlationId: correlationId };
  }
  if (!body.files || !Array.isArray(body.files) || body.files.length === 0) {
    return { error: 'Missing or invalid field: files (non-empty array required)', correlationId: correlationId };
  }

  var changeData = {
    author: body.author || 'unknown',
    files: body.files,
    changelog: body.changelog,
    commitHash: body.commitHash || null
  };

  var result = ChangeTracker.notify(changeData, correlationId);

  return {
    success: !result.error,
    correlationId: correlationId,
    tracking: result
  };
}
```

**Verification**: The doPost switch contains the `reportChange` case. The `handleReportChange` function exists and calls `ChangeTracker.notify()`. The function validates `changelog` (string) and `files` (non-empty array).

### Task 2.3 — Push to GAS

```bash
cd apps-script
clasp push
```

**Verification**: `clasp push` succeeds. File count increased by 1 (ChangeTracker.gs added).

### Task 2.4 — Test reportChange (stub-safe mode)

At this point, no Script Properties are set, so VPS notification should be skipped:

```bash
GAS_DEV_URL="https://script.google.com/macros/s/SCRIPT_ID/dev"

# Test: reportChange with no VPS configured (stub-safe)
curl -s -X POST "$GAS_DEV_URL" \
  -H "Content-Type: application/json" \
  -d '{
    "action": "reportChange",
    "author": "test-agent",
    "files": ["ChangeTracker.gs", "WebApp.gs"],
    "changelog": "Phase 2 test — stub-safe mode",
    "commitHash": "abc1234"
  }' | jq .
# EXPECT: { "success": true, "correlationId": "gas_...", "tracking": { "vpsStatus": "skipped", ... } }
```

**Also test validation**:

```bash
# Missing changelog
curl -s -X POST "$GAS_DEV_URL" \
  -H "Content-Type: application/json" \
  -d '{"action": "reportChange", "files": ["test.gs"]}' | jq .
# EXPECT: { "error": "Missing or invalid field: changelog ..." }

# Empty files array
curl -s -X POST "$GAS_DEV_URL" \
  -H "Content-Type: application/json" \
  -d '{"action": "reportChange", "changelog": "test", "files": []}' | jq .
# EXPECT: { "error": "Missing or invalid field: files ..." }
```

**Verification**: Stub-safe test returns success with `vpsStatus: "skipped"`. Validation tests return appropriate error messages. Google Sheet has a `_CHANGE_LOG` tab with 1 row.

### Task 2.5 — Update Changelogs & Commit

Update `apps-script/src/tracking/changelog.md` and `apps-script/src/api/changelog.md` with entries for the work done.

```bash
git add -A
git commit -m "feat: Phase 2 — ChangeTracker service + reportChange endpoint"
```

### Phase 2 Completion Criteria

- [ ] `ChangeTracker.gs` exists with all methods (notify, getOrCreateChangeLogSheet, isVpsConfigured, getVpsUrl, buildPayload, postToVps)
- [ ] `WebApp.gs` has reportChange case in doPost switch
- [ ] `handleReportChange()` validates changelog (string) and files (non-empty array)
- [ ] `clasp push` succeeds
- [ ] Stub-safe test returns `{ success: true, tracking: { vpsStatus: "skipped" } }`
- [ ] Validation error tests return proper error messages
- [ ] `_CHANGE_LOG` sheet auto-created with correct headers
- [ ] `_LOGS` sheet has a `changetracker.notify` entry
- [ ] Changelogs updated
- [ ] Committed to git

---

## Phase 3 — Local Stub Server & Trigger Scripts

**Goal**: Create the local VPS stub and the post-push trigger scripts.

**Agent assignment**: Use `tooling-agent` subagent. This phase is fully independent from Phase 2 and could run in parallel.

### Task 3.1 — Create Stub Server

**File**: `stub-server/server.js`

Requirements:
- Zero dependencies — only Node.js built-in `http` module.
- Listens on port 3456 (configurable via `PORT` env var).
- Accepts `POST /changelog` — parses JSON body, pretty-prints it with a timestamp header.
- Returns `{ received: true, timestamp: <ISO string> }` with status 200.
- Any other route returns 404.
- On startup, prints the listening URL and a "waiting for notifications" message.

**Verification**: `node stub-server/server.js` starts without errors. `curl -X POST http://localhost:3456/changelog -H "Content-Type: application/json" -d '{"test":true}'` prints the payload on the server terminal and returns `{"received":true,"timestamp":"..."}`.

### Task 3.2 — Create Bash Trigger Script

**File**: `scripts/post-push-notify.sh`

Requirements:
- Reads `GAS_WEBAPP_URL` from environment (with fallback to a placeholder).
- Gathers from git: last commit message (`git log -1 --pretty=format:"%s"`), short hash, author name, changed files in `apps-script/src/`.
- Constructs JSON payload with `action: "reportChange"`.
- POSTs to GAS web app URL via curl.
- Prints: what it's sending (author, hash, files) and the response.
- Handles missing git gracefully (falls back to "unknown" / "manual push").
- Uses `jq` for constructing the files JSON array (document as prerequisite in a comment).

**Verification**: Make it executable (`chmod +x`). Running `./scripts/post-push-notify.sh` from the repo root produces sensible output even if GAS_WEBAPP_URL isn't set (should show the curl command and note the placeholder URL).

### Task 3.3 — Create PowerShell Trigger Script

**File**: `scripts/post-push-notify.ps1`

Requirements:
- Same logic as bash script but in PowerShell.
- Reads `$env:GAS_WEBAPP_URL` with fallback.
- Uses `Invoke-RestMethod` for the POST.
- Uses `ConvertTo-Json` for payload construction (no jq dependency).
- Works on Windows without any additional tools installed.

**Verification**: File exists and is syntactically valid PowerShell.

### Task 3.4 — Commit

```bash
git add -A
git commit -m "feat: Phase 3 — stub server + post-push trigger scripts (bash + PowerShell)"
```

### Phase 3 Completion Criteria

- [ ] `stub-server/server.js` starts and accepts POST /changelog
- [ ] `scripts/post-push-notify.sh` is executable and gathers git metadata
- [ ] `scripts/post-push-notify.ps1` exists and is valid PowerShell
- [ ] No external dependencies in stub-server (zero npm packages)
- [ ] Committed to git

---

## Phase 4 — End-to-End Testing

**Goal**: Verify the complete flow: trigger script → GAS → VPS stub. Test both happy path and stub-safe mode.

**Agent assignment**: Use `test-agent` subagent.

**Prerequisite (human action)**: The user must have:
1. Started the stub server: `node stub-server/server.js`
2. Started ngrok: `ngrok http 3456`
3. Set Script Properties in GAS (via Apps Script IDE → Project Settings → Script Properties):
   - `CHANGE_TRACKER_VPS_URL` = ngrok HTTPS URL + `/changelog`
   - `CHANGE_TRACKER_ENABLED` = `true`
   - `GAS_DEPLOYMENT_URL` = the GAS dev or exec URL

If the user has not done this yet, **the agent should inform the user of these prerequisites and wait**.

### Task 4.1 — Test Happy Path (VPS Connected)

```bash
GAS_URL="<the GAS dev or exec URL>"

# Full reportChange with VPS connected
curl -s -X POST "$GAS_URL" \
  -H "Content-Type: application/json" \
  -d '{
    "action": "reportChange",
    "author": "e2e-test",
    "files": ["WebApp.gs", "ChangeTracker.gs"],
    "changelog": "End-to-end test with VPS connected",
    "commitHash": "e2e1234"
  }' | jq .
```

**Verify all three outputs**:
1. **curl response**: `{ "success": true, "tracking": { "vpsStatus": 200, ... } }`
2. **Stub server terminal**: Printed the full JSON payload with `scriptId`, `scriptEndpoint`, `change` object.
3. **Google Sheet `_CHANGE_LOG`**: New row with vpsStatus = 200.
4. **Google Sheet `_LOGS`**: New `changetracker.notify` INFO entry.

### Task 4.2 — Test Stub-Safe Mode (VPS Disconnected)

Set `CHANGE_TRACKER_ENABLED` to `false` in Script Properties (or remove `CHANGE_TRACKER_VPS_URL`).

Repeat the same curl command from 4.1.

**Verify**:
1. **curl response**: `{ "success": true, "tracking": { "vpsStatus": "skipped", ... } }`
2. **Stub server terminal**: No new output (nothing was sent).
3. **Google Sheet `_CHANGE_LOG`**: New row with vpsStatus = "skipped".

Re-enable after testing: set `CHANGE_TRACKER_ENABLED` back to `true`.

### Task 4.3 — Test Post-Push Script Flow

```bash
# Set the env var
export GAS_WEBAPP_URL="<the GAS URL>"

# Make a trivial change to trigger a commit
echo "// e2e test $(date)" >> apps-script/src/api/WebApp.gs
git add -A && git commit -m "test: e2e post-push script verification"

# Run the trigger
./scripts/post-push-notify.sh
```

**Verify**: Script prints the gathered metadata and the response. Stub server shows the payload. `_CHANGE_LOG` has a new row.

### Task 4.4 — Test Error Cases

```bash
# VPS returns error (stop the stub server, keep ngrok running)
# The ngrok URL will return 502 when the stub is down

curl -s -X POST "$GAS_URL" \
  -H "Content-Type: application/json" \
  -d '{
    "action": "reportChange",
    "author": "error-test",
    "files": ["test.gs"],
    "changelog": "Testing VPS error handling"
  }' | jq .
```

**Verify**: Response still returns (doesn't crash). `_CHANGE_LOG` has a row with vpsStatus showing the error code. `_LOGS` has an error or warning entry.

### Task 4.5 — Generate Test Report

Create `docs/test-report.md` summarizing all test results:

```markdown
# Test Report — Phase 4

| Test | Status | Notes |
|------|--------|-------|
| 4.1 Happy Path | PASS/FAIL | ... |
| 4.2 Stub-Safe | PASS/FAIL | ... |
| 4.3 Post-Push Script | PASS/FAIL | ... |
| 4.4 Error Handling | PASS/FAIL | ... |

## Artifacts
- Deployment URL: ...
- Stub server port: 3456
- ngrok URL: ...
```

### Task 4.6 — Commit

```bash
git add -A
git commit -m "test: Phase 4 — end-to-end verification complete"
```

### Phase 4 Completion Criteria

- [ ] Happy path test passes (VPS receives payload, status 200)
- [ ] Stub-safe test passes (skipped gracefully, no HTTP error)
- [ ] Post-push script flow works end-to-end
- [ ] Error case handled gracefully (no crash, logged appropriately)
- [ ] `_CHANGE_LOG` has rows for all test scenarios
- [ ] `_LOGS` has corresponding trace entries
- [ ] Test report generated at `docs/test-report.md`
- [ ] Committed to git

---

## Phase 5 — Final Deployment & Documentation

**Goal**: Create a production deployment, re-test against it, and write the README.

**Agent assignment**: Orchestrator direct (documentation) + `test-agent` (re-verification).

### Task 5.1 — Create Production Deployment

```bash
cd apps-script
clasp deploy -d "v1.0.0 — Change tracker prototype"
# Note the deployment ID and /exec URL
```

### Task 5.2 — Re-Test Against Production URL

Run the same tests from Phase 4 Tasks 4.1 and 4.2, but using the `/exec` URL instead of `/dev`.

**Verify**: Both tests pass with the production deployment URL.

### Task 5.3 — Write README.md

**File**: `README.md` at repo root.

Sections:
1. **Overview** — What this project does (one paragraph).
2. **Architecture** — The trigger → GAS → VPS flow diagram (from plan.md).
3. **Prerequisites** — clasp, Node.js, ngrok, Google account.
4. **Setup** — Reference to SETUP-phase0-human.md or inline the key steps.
5. **Configuration** — Script Properties table (CHANGE_TRACKER_VPS_URL, CHANGE_TRACKER_ENABLED, GAS_DEPLOYMENT_URL).
6. **Usage** — How to use the post-push script. Curl examples for manual testing.
7. **API Reference** — The reportChange endpoint: method, URL, request body schema, response schema.
8. **Stub Server** — How to run it, what it does.
9. **Migration** — How to move this into the enterprise repo (the 2-file diff).
10. **File Structure** — Tree diagram of the repo.

### Task 5.4 — Final Commit & Tag

```bash
git add -A
git commit -m "docs: Phase 5 — production deployment + README"
git tag v1.0.0
```

### Phase 5 Completion Criteria

- [ ] Production deployment created via `clasp deploy`
- [ ] Tests pass against `/exec` URL
- [ ] README.md covers all sections listed above
- [ ] Git tag `v1.0.0` created
- [ ] All changelogs up to date

---

## Progress Tracker

| Phase | Description | Status | Completed |
|-------|-------------|--------|-----------|
| 0 | Sandbox setup (human) | ⬜ NOT STARTED | — |
| 1 | Base web app deploy | ⬜ NOT STARTED | — |
| 2 | Change tracking infrastructure | ⬜ NOT STARTED | — |
| 3 | Stub server + trigger scripts | ⬜ NOT STARTED | — |
| 4 | End-to-end testing | ⬜ NOT STARTED | — |
| 5 | Final deploy + docs | ⬜ NOT STARTED | — |

**Legend**: ⬜ NOT STARTED | 🔄 IN PROGRESS | ✅ COMPLETE | 🚫 BLOCKED

---

## Orchestrator Notes

### Parallelization Opportunities
- **Phase 3 can run in parallel with Phase 2.** The stub server and trigger scripts don't depend on ChangeTracker.gs being implemented — they just need to know the payload format (documented in CLAUDE.md).
- **Within Phase 2**, Task 2.1 (ChangeTracker.gs) and the stub work are independent. But Task 2.2 (WebApp.gs edit) depends on 2.1 being complete.

### Human Gates
- **Before Phase 1**: Human must complete Phase 0 setup (clasp login, Sheet created, Script ID configured).
- **Before Phase 4**: Human must start stub server + ngrok and set Script Properties. The agent cannot do these — they require browser interaction and local processes.

### Risk Areas
- **GAS deployment caching**: If tests fail after `clasp push`, remind the user to test via `/dev` URL (always runs HEAD) rather than `/exec` (frozen deployment).
- **UrlFetchApp errors**: If `muteHttpExceptions: true` is missing, GAS throws on 4xx/5xx and the entire handler returns an error. This is the most common GAS mistake.
- **Global scope collisions**: All .gs files share one namespace. Variable names like `CHANGE_LOG_SHEET_NAME` must be unique across all files. The enterprise uses `LOG_SHEET_NAME` for the logs sheet — don't reuse that name.

### Enterprise Migration Checklist (for later)
When GDrive access is granted:
1. Copy `apps-script/src/tracking/ChangeTracker.gs` → enterprise `apps-script/src/tracking/ChangeTracker.gs`
2. Apply the WebApp.gs diff: add `reportChange` case + `handleReportChange` function
3. Set Script Properties in enterprise GAS project
4. Update enterprise `apps-script/README.md` with new endpoint docs
5. No other files change
