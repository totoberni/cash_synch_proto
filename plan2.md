# plan2.md — Automated Documentation Pipeline

**Status**: DRAFT
**Current Phase**: 0 - Not Started Yet
**Last Updated**: 2026-02-15

> **For orchestrator agents**: This is the single source of truth for plan 2 implementation.
> Read CLAUDE.md for project conventions. Read plan.md for plan 1 context.
> Check module changelogs before editing files. Update "Status" and "Current Phase" as you progress.

---

## Context: Where We Are

Plan 1 (`plan.md`) built a functional GAS Change Tracker sandbox:
- GAS web app receives `reportChange` POSTs, logs to `_CHANGE_LOG` sheet, relays to VPS
- Local stub server simulates VPS on localhost:3456 (via ngrok tunnel)
- Trigger scripts (`post-push-notify.sh`, `.ps1`) gather git metadata and POST to GAS
- Full e2e flow verified and tagged `v1.0.0`

**What exists**:
1. Local sandbox GAS deployment (tested, working)
2. Stub VPS server that prints received payloads
3. Access to GitHub Actions
4. Enterprise Git repo (but no GDrive/Sheets access to validate on their end)

**What does NOT exist**:
1. No enterprise GDrive access (can't validate on their Sheets — reason this sandbox exists)
2. No production VPS (stub server is the surrogate)

**Plan 2 goal**: Extend the sandbox into an automated documentation pipeline where GitHub Actions trigger batched documentation runs, GAS relays to VPS, and the VPS fetches diffs from GitHub API for AI-driven documentation. The architecture must be abstract enough to transplant to the enterprise codebase without rework.

---

## Architecture Diagram

```
           ┌─────────────────────────────────────────────────────────┐
           │  GitHub Actions                                         │
           │                                                         │
           │  Triggers: workflow_dispatch (manual) | cron (48h)      │
           │                                                         │
           │  1. Determine range: last-documented..HEAD              │
           │  2. Collect commits + changed files (apps-script/src/)  │
           │  3. POST lightweight payload to GAS /exec               │
           │  4. Check ack in response                               │
           │  5. On ack → move last-documented tag                   │
           └────────────────────┬────────────────────────────────────┘
                                │
                                │  POST /exec  { action: "reportBatch", ... }
                                ▼
           ┌─────────────────────────────────────────────────────────┐
           │  GAS Web App (WebApp.gs — doPost)                       │
           │                                                         │
           │  1. Route to handleReportBatch()                        │
           │  2. Validate batch payload                              │
           │  3. Call ChangeTracker.notifyBatch()                    │
           │     ├─ Write batch row to _CHANGE_LOG sheet             │
           │     ├─ Forward to VPS (if configured)                   │
           │     └─ Return ack status from VPS                       │
           │  4. Return result JSON (with ack) to caller             │
           └────────────────────┬────────────────────────────────────┘
                                │
                                │  POST /changelog  { batch payload }
                                ▼
           ┌─────────────────────────────────────────────────────────┐
           │  VPS                                                    │
           │                                                         │
           │  1. Receive batch, assign batchId                       │
           │  2. Durably store batch → return { ack: true, batchId } │
           │  3. Async: fetch full diff from GitHub API              │
           │     GET /repos/{owner}/{repo}/compare/{from}...{to}     │
           │  4. AI agents process diff → generate documentation     │
           └─────────────────────────────────────────────────────────┘
```

### Handshake Protocol

```
GitHub Action               GAS                    VPS
     │                       │                      │
     │  POST reportBatch     │                      │
     │ ─────────────────────>│                      │
     │                       │  POST /changelog     │
     │                       │ ────────────────────>│
     │                       │                      │  Store batch
     │                       │  { ack, batchId }    │
     │                       │ <────────────────────│
     │  { success, ack }     │                      │
     │ <─────────────────────│                      │
     │                       │                      │
     │  ack == true?         │                      │
     │  → move tag           │                      │
     │  ack != true?         │                      │
     │  → keep tag (retry    │                      │
     │    on next run)       │                      │
     │                       │                      │  Async: fetch diff
     │                       │                      │  from GitHub API,
     │                       │                      │  run AI agents
```

**Failure modes**:
- **VPS down**: GAS returns `vpsStatus: error`. GitHub Action sees no ack → tag doesn't move → next run retries same range + new commits.
- **GAS down**: GitHub Action gets HTTP error → tag doesn't move → same retry behavior.
- **VPS acks but processing fails**: VPS-internal concern. The batch is durably stored; VPS retries processing. GitHub's job is done.

---

## Payload Contracts

### reportBatch — GitHub Action → GAS

```json
{
  "action": "reportBatch",
  "trigger": "manual|scheduled",
  "triggeredBy": "github-username-or-cron",
  "repository": "owner/repo",
  "range": {
    "from": "abc1234def5678...",
    "to": "123abcd456efgh...",
    "commitCount": 4
  },
  "commits": [
    {
      "sha": "full-40-char-sha",
      "shortSha": "abc1234",
      "author": "developer-name",
      "message": "feat: added X",
      "timestamp": "2026-02-15T10:00:00Z"
    }
  ],
  "filesChanged": ["api/WebApp.gs", "tracking/ChangeTracker.gs"],
  "pathFilter": "apps-script/src/"
}
```

**Notes**:
- `filesChanged` paths are relative to `pathFilter` (stripped prefix).
- `range.from` and `range.to` are full SHAs (VPS needs them for GitHub API compare endpoint).
- `commits` array is ordered oldest-first.

### Batch relay — GAS → VPS

```json
{
  "scriptId": "GAS-script-id",
  "scriptEndpoint": "GAS-exec-url",
  "timestamp": "2026-02-15T12:00:00Z",
  "correlationId": "gas_...",
  "batch": {
    "trigger": "manual|scheduled",
    "triggeredBy": "github-username",
    "repository": "owner/repo",
    "range": { "from": "...", "to": "...", "commitCount": 4 },
    "commits": [ ... ],
    "filesChanged": [ ... ],
    "pathFilter": "apps-script/src/"
  }
}
```

### VPS ack response

```json
{
  "ack": true,
  "batchId": "vps-generated-uuid",
  "timestamp": "2026-02-15T12:00:01Z"
}
```

### GAS response to GitHub Action

```json
{
  "success": true,
  "correlationId": "gas_...",
  "tracking": {
    "changeLogRow": 12,
    "vpsStatus": 200,
    "vpsAck": true,
    "vpsBatchId": "vps-generated-uuid",
    "error": null
  }
}
```

GitHub Action checks: `response.tracking.vpsAck === true` before moving the tag.

---

## Agent Roster

The orchestrator may create and deploy these agents. Agent `.md` pragmas are suggested below.

### gas-batch-agent

**Owns**: `apps-script/src/api/WebApp.gs` (edits), `apps-script/src/tracking/ChangeTracker.gs` (edits)
**Role**: Implements the `reportBatch` GAS endpoint and `ChangeTracker.notifyBatch()` method.

**Suggested pragma** (`.claude/agents/gas-batch-agent.md`):
```
You implement GAS (Google Apps Script) endpoints. You own WebApp.gs and ChangeTracker.gs.
Rules:
- Use `var` only. No let/const.
- muteHttpExceptions: true in ALL UrlFetchApp.fetch() calls.
- Write change records to _CHANGE_LOG only. Use LogService.info() for traces.
- No hardcoded URLs — use Script Properties.
- Read plan2.md for payload contracts and method signatures.
- Read gotchas.md before debugging any GAS issue.
- Update module changelogs after completing work.
```

### actions-agent

**Owns**: `.github/workflows/`, `scripts/build-batch-payload.sh`
**Role**: Creates the GitHub Actions workflow and the batch payload builder script.

**Suggested pragma** (`.claude/agents/actions-agent.md`):
```
You create and maintain GitHub Actions workflows and supporting shell scripts.
Rules:
- Workflows must use workflow_dispatch + schedule triggers.
- Use actions/checkout@v4 with fetch-depth: 0 (full history).
- All secrets via ${{ secrets.X }} — never hardcode URLs or tokens.
- The batch payload builder script must be testable locally (not only in CI).
- Read plan2.md for payload contracts and the handshake protocol.
- Path filter: apps-script/src/ (parameterized, not hardcoded).
```

### vps-stub-agent

**Owns**: `stub-server/`
**Role**: Extends the stub server to implement the VPS handshake (ack + batchId) and batch storage.

**Suggested pragma** (`.claude/agents/vps-stub-agent.md`):
```
You maintain the local VPS stub server (Node.js, zero dependencies).
Rules:
- Zero npm dependencies. Node.js built-in modules only (http, crypto, fs).
- Implement the VPS contract as defined in plan2.md payload contracts.
- POST /changelog must return { ack: true, batchId: uuid, timestamp }.
- Durably store batches to a local JSON file (stub-server/batches/).
- Read plan2.md for the full VPS response contract.
```

### tooling-agent

**Owns**: `scripts/`, `.env.example`, `dev-start.sh`
**Role**: Dev environment tooling — startup scripts, config patterns, trigger script updates.

**Suggested pragma** (same as plan 1 with additions):
```
You create and maintain developer tooling: shell scripts, config files, dev environment setup.
Rules:
- Scripts must work on both Linux and WSL.
- Use .env file pattern for configuration (source if exists, fall back to env vars).
- dev-start.sh must manage stub server + ngrok as child processes with cleanup on exit.
- Read plan2.md for the .env variables and dev startup requirements.
```

### test-agent

**Owns**: `docs/`
**Role**: End-to-end testing and test report generation. Same as plan 1.

---

## Phase 0 — Sandbox Hardening (Plan 1 Extensions)

**Goal**: Improve the dev testing loop and prepare the payload contract for plan 2. Cleanup any artifacts from plan 1 manual testing.

**Agent assignment**: tooling-agent (Tasks 0.1–0.3), gas-batch-agent (Task 0.4), orchestrator direct (Task 0.5).

### Task 0.1 — Create .env config pattern

**Create** `.env.example` at project root:

```bash
# GAS Change Tracker — Environment Configuration
# Copy to .env and fill in your values. .env is gitignored.

# GAS web app deployment URL (from clasp deploy output)
GAS_WEBAPP_URL=https://script.google.com/macros/s/YOUR_DEPLOYMENT_ID/exec

# Stub server port (default: 3456)
STUB_SERVER_PORT=3456
```

**Create** `.env` at project root (gitignored, pre-filled with current sandbox values):

```bash
GAS_WEBAPP_URL=https://script.google.com/macros/s/AKfycbyt-ZCjQH5XA6IM_H90IOuLqXleUMC0sBTuv5Lc12-72EQX72J9osA-XWg3f5JRvHDn/exec
STUB_SERVER_PORT=3456
```

**Add** `.env` to `.gitignore` (create `.gitignore` if it doesn't exist).

**Verification**: `.env.example` is committed. `.env` exists locally but is gitignored. Running `git status` does not show `.env`.

### Task 0.2 — Create dev-start.sh

**File**: `scripts/dev-start.sh`

Single script that replaces the 3-terminal setup:

```
1. Source .env if it exists (for STUB_SERVER_PORT)
2. Check if port $STUB_SERVER_PORT is already in use → kill existing process
3. Start stub-server/server.js in background, capture PID
4. Start ngrok http $STUB_SERVER_PORT in background, capture PID
5. Poll http://localhost:4040/api/tunnels (ngrok local API) until ready (max 10s)
6. Extract HTTPS forwarding URL from ngrok API response
7. Print:
   - Stub server: http://localhost:$STUB_SERVER_PORT/changelog
   - ngrok URL: https://xxxx.ngrok-free.app/changelog
   - Instruction: "Set CHANGE_TRACKER_VPS_URL in GAS Script Properties to the ngrok URL above"
8. trap SIGINT/SIGTERM → kill stub server PID + ngrok PID
9. wait (keep running until ctrl+c)
```

**Prerequisites**: `node`, `ngrok`, `curl`, `jq` (for parsing ngrok API).

**Verification**: Running `bash scripts/dev-start.sh` from project root starts both services, prints the ngrok URL, and cleans up on ctrl+c.

### Task 0.3 — Update trigger script to source .env

**Edit**: `scripts/post-push-notify.sh`

Add after the `set -euo pipefail` line:

```bash
# Source .env if it exists (project root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"
if [ -f "$ENV_FILE" ]; then
    set -a
    source "$ENV_FILE"
    set +a
fi
```

This means the script auto-discovers `GAS_WEBAPP_URL` from `.env` without manual export. The existing env var fallback chain remains: explicit export > .env > placeholder.

**Verification**: Without exporting `GAS_WEBAPP_URL`, running `bash scripts/post-push-notify.sh` from project root uses the URL from `.env`.

### Task 0.4 — Clean up WebApp.gs

**Edit**: `apps-script/src/api/WebApp.gs`

Remove the stray line 19 (`echo "// manual test $(date)"`) left from manual testing. Push to GAS via `clasp push -f`.

**Verification**: `clasp push -f` succeeds. `curl ... ?action=ping` returns valid JSON (no script error).

### Task 0.5 — Commit Phase 0

```bash
git add .env.example .gitignore scripts/dev-start.sh scripts/post-push-notify.sh apps-script/src/api/WebApp.gs
git commit -m "chore: Phase 0 — dev environment hardening + cleanup"
```

### Phase 0 Completion Criteria

- [ ] `.env.example` committed with documented variables
- [ ] `.env` exists locally, gitignored
- [ ] `.gitignore` includes `.env`
- [ ] `scripts/dev-start.sh` starts stub + ngrok, prints URL, cleans up on exit
- [ ] `scripts/post-push-notify.sh` sources `.env` automatically
- [ ] WebApp.gs stray test line removed
- [ ] `clasp push -f` succeeds
- [ ] Committed to git

---

## Phase 1 — GAS Batch Endpoint

**Goal**: Add `reportBatch` action to WebApp.gs and `notifyBatch()` to ChangeTracker.gs. The GAS layer is a thin relay — it logs the batch to `_CHANGE_LOG` and forwards to VPS, returning the ack status.

**Agent assignment**: gas-batch-agent.

**Parallelization**: This phase can run in parallel with Phase 2 (GitHub Action) and Phase 3 (VPS stub). All three share the payload contracts defined above — no code dependency between them until integration testing.

### Task 1.1 — Add notifyBatch() to ChangeTracker.gs

**Edit**: `apps-script/src/tracking/ChangeTracker.gs`

Add a new method `notifyBatch` to the `ChangeTracker` singleton. This is separate from `notify()` — the plan 1 method stays intact for backward compatibility with the trigger scripts.

```javascript
/**
 * Notify the system of a batch of code changes
 * @param {Object} batchData - Batch details from GitHub Action
 *   { trigger, triggeredBy, repository, range: {from, to, commitCount}, commits: [...], filesChanged, pathFilter }
 * @param {string} correlationId - Request correlation ID
 * @returns {Object} Result with changeLogRow, vpsStatus, vpsAck, vpsBatchId, error
 */
notifyBatch: function(batchData, correlationId) {
  var result = {
    changeLogRow: null,
    vpsStatus: 'skipped',
    vpsAck: false,
    vpsBatchId: null,
    vpsResponse: null,
    error: null
  };

  try {
    // 1. Write batch to _CHANGE_LOG
    var sheet = this.getOrCreateChangeLogSheet();
    var timestamp = new Date().toISOString();
    var filesString = Array.isArray(batchData.filesChanged) ? batchData.filesChanged.join(', ') : '';
    var batchSummary = 'Batch: ' + (batchData.range ? batchData.range.commitCount : 0)
      + ' commits (' + (batchData.range ? batchData.range.from.substring(0, 7) : '?')
      + '..' + (batchData.range ? batchData.range.to.substring(0, 7) : '?') + ')';

    var rowData = [
      timestamp,
      correlationId,
      batchData.triggeredBy || 'unknown',
      filesString,
      batchSummary,
      batchData.range ? batchData.range.to : '',  // latest commit hash
      '',       // vpsUrl
      'pending', // vpsStatus
      ''         // vpsResponse
    ];

    var rowNumber = sheet.getLastRow() + 1;
    sheet.appendRow(rowData);
    result.changeLogRow = rowNumber;

    // 2. Forward to VPS if configured
    if (this.isVpsConfigured()) {
      var vpsUrl = this.getVpsUrl();
      var payload = this.buildBatchPayload(batchData, correlationId);
      var vpsResult = this.postToVps(vpsUrl, payload);

      // 3. Parse VPS ack from response
      var ackParsed = false;
      var batchId = null;
      try {
        var vpsBody = JSON.parse(vpsResult.body);
        ackParsed = vpsBody.ack === true;
        batchId = vpsBody.batchId || null;
      } catch (parseErr) {
        // VPS response wasn't valid JSON — ack is false
      }

      // 4. Update sheet row
      sheet.getRange(rowNumber, 7).setValue(vpsUrl);
      sheet.getRange(rowNumber, 8).setValue(vpsResult.status);
      sheet.getRange(rowNumber, 9).setValue(vpsResult.body);

      result.vpsStatus = vpsResult.status;
      result.vpsAck = ackParsed;
      result.vpsBatchId = batchId;
      result.vpsResponse = vpsResult.body;

      LogService.info('changetracker.notifyBatch', 'Batch notification processed', {
        trigger: batchData.trigger,
        commitCount: batchData.range ? batchData.range.commitCount : 0,
        vpsStatus: vpsResult.status,
        vpsAck: ackParsed
      });
    } else {
      sheet.getRange(rowNumber, 8).setValue('skipped');
      LogService.info('changetracker.notifyBatch', 'Batch notification processed (VPS skipped)', {
        trigger: batchData.trigger,
        commitCount: batchData.range ? batchData.range.commitCount : 0,
        vpsStatus: 'skipped'
      });
    }
  } catch (err) {
    result.error = err.message;
    LogService.error('changetracker.notifyBatch', 'Batch notification failed: ' + err.message, {
      error: err.message,
      stack: err.stack
    });
  }

  return result;
}
```

**Also add** `buildBatchPayload`:

```javascript
/**
 * Build the VPS payload for a batch notification
 * @param {Object} batchData - Batch details
 * @param {string} correlationId - Correlation ID
 * @returns {Object} Payload for VPS
 */
buildBatchPayload: function(batchData, correlationId) {
  var props = PropertiesService.getScriptProperties();
  return {
    scriptId: ScriptApp.getScriptId(),
    scriptEndpoint: props.getProperty('GAS_DEPLOYMENT_URL') || 'not-configured',
    timestamp: new Date().toISOString(),
    correlationId: correlationId,
    batch: {
      trigger: batchData.trigger || 'unknown',
      triggeredBy: batchData.triggeredBy || 'unknown',
      repository: batchData.repository || 'unknown',
      range: batchData.range || null,
      commits: batchData.commits || [],
      filesChanged: batchData.filesChanged || [],
      pathFilter: batchData.pathFilter || ''
    }
  };
}
```

**Key rules** (same as plan 1):
- `var` only.
- `muteHttpExceptions: true` — already in `postToVps()`, which is reused.
- Truncation — `postToVps()` already truncates to 500 chars.
- `_CHANGE_LOG` sheet — same sheet, same headers. Batch rows use the `changelog` column for the batch summary string.

**Verification**: ChangeTracker.gs contains both `notify` (unchanged) and `notifyBatch` (new). Contains `buildBatchPayload`. No `let`/`const`.

### Task 1.2 — Wire reportBatch into WebApp.gs

**Edit**: `apps-script/src/api/WebApp.gs`

Add to the `doPost` switch, after the `reportChange` case:

```javascript
case 'reportBatch':
  response = handleReportBatch(body, correlationId);
  break;
```

Update the `default` error response `availableActions` array to include `'reportBatch'`.

**Add** the handler function:

```javascript
/**
 * Handle reportBatch action — receives a batch of changes from GitHub Actions
 * @param {Object} body - Batch payload (see plan2.md payload contracts)
 * @param {string} correlationId - Request correlation ID
 * @returns {Object} Result with tracking info including VPS ack
 */
function handleReportBatch(body, correlationId) {
  // Validate required fields
  if (!body.range || typeof body.range !== 'object') {
    return { error: 'Missing or invalid field: range (object required)', correlationId: correlationId };
  }
  if (!body.range.from || !body.range.to) {
    return { error: 'Missing fields: range.from and range.to (commit SHAs required)', correlationId: correlationId };
  }
  if (!body.commits || !Array.isArray(body.commits) || body.commits.length === 0) {
    return { error: 'Missing or invalid field: commits (non-empty array required)', correlationId: correlationId };
  }
  if (!body.repository || typeof body.repository !== 'string') {
    return { error: 'Missing or invalid field: repository (string required, e.g. "owner/repo")', correlationId: correlationId };
  }

  var batchData = {
    trigger: body.trigger || 'unknown',
    triggeredBy: body.triggeredBy || 'unknown',
    repository: body.repository,
    range: body.range,
    commits: body.commits,
    filesChanged: body.filesChanged || [],
    pathFilter: body.pathFilter || ''
  };

  var result = ChangeTracker.notifyBatch(batchData, correlationId);

  return {
    success: !result.error,
    correlationId: correlationId,
    tracking: result
  };
}
```

**Verification**: The doPost switch has `reportBatch` case. `handleReportBatch` validates `range`, `commits`, and `repository`. Calls `ChangeTracker.notifyBatch()`.

### Task 1.3 — Push and test (stub-safe)

```bash
cd apps-script && clasp push -f
```

Test with VPS disabled (stub-safe):

```bash
source .env
curl -sL -d '{
  "action": "reportBatch",
  "trigger": "manual",
  "triggeredBy": "test-user",
  "repository": "owner/cash_synch_proto",
  "range": { "from": "aaaa", "to": "bbbb", "commitCount": 2 },
  "commits": [
    { "sha": "aaaa", "shortSha": "aaa", "author": "dev1", "message": "feat: X", "timestamp": "2026-02-15T10:00:00Z" },
    { "sha": "bbbb", "shortSha": "bbb", "author": "dev2", "message": "fix: Y", "timestamp": "2026-02-15T11:00:00Z" }
  ],
  "filesChanged": ["api/WebApp.gs"],
  "pathFilter": "apps-script/src/"
}' -H "Content-Type: application/json" "$GAS_WEBAPP_URL" | jq .
```

**Expected**: `{ success: true, tracking: { vpsStatus: "skipped", vpsAck: false } }`

Also test validation (missing range, empty commits, missing repository).

**Verification**: Stub-safe returns success. Validation errors return proper messages. `_CHANGE_LOG` has a batch row.

### Task 1.4 — Update changelogs and commit

Update `apps-script/src/tracking/changelog.md` and `apps-script/src/api/changelog.md`.

```bash
git add apps-script/src/api/WebApp.gs apps-script/src/tracking/ChangeTracker.gs \
  apps-script/src/api/changelog.md apps-script/src/tracking/changelog.md
git commit -m "feat: Phase 1 — reportBatch endpoint + ChangeTracker.notifyBatch()"
```

### Phase 1 Completion Criteria

- [ ] `ChangeTracker.notifyBatch()` implemented with ack parsing
- [ ] `ChangeTracker.buildBatchPayload()` implemented
- [ ] `handleReportBatch()` in WebApp.gs validates range, commits, repository
- [ ] `doPost` switch routes `reportBatch`
- [ ] `clasp push -f` succeeds
- [ ] Stub-safe test returns `{ success: true, vpsStatus: "skipped" }`
- [ ] Validation tests return proper errors
- [ ] `_CHANGE_LOG` has batch row
- [ ] `notify()` and `buildPayload()` unchanged (backward compatible)
- [ ] Changelogs updated, committed

---

## Phase 2 — GitHub Actions Workflow

**Goal**: Create a GitHub Actions workflow with dual triggers (manual + 48h cron) that determines the undocumented commit range, builds the batch payload, and POSTs to GAS.

**Agent assignment**: actions-agent.

**Parallelization**: Independent of Phase 1 (GAS) and Phase 3 (VPS stub). All share the payload contracts above. Integration tested in Phase 4.

### Task 2.1 — Create the workflow file

**File**: `.github/workflows/doc-batch.yml`

```yaml
name: Documentation Batch

on:
  workflow_dispatch:
    inputs:
      dry_run:
        description: 'Preview payload without sending'
        type: boolean
        default: false
  schedule:
    - cron: '0 9 */2 * *'   # Every 48h at 09:00 UTC

permissions:
  contents: write   # Needed to push the last-documented tag

env:
  GAS_WEBAPP_URL: ${{ secrets.GAS_WEBAPP_URL }}
  PATH_FILTER: 'apps-script/src/'

jobs:
  notify:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout (full history)
        uses: actions/checkout@v4
        with:
          fetch-depth: 0
          fetch-tags: true

      - name: Determine commit range
        id: range
        run: |
          # Check if last-documented tag exists
          if git rev-parse last-documented >/dev/null 2>&1; then
            FROM_SHA=$(git rev-parse last-documented)
          else
            # First run: use the initial commit
            FROM_SHA=$(git rev-list --max-parents=0 HEAD)
          fi
          TO_SHA=$(git rev-parse HEAD)

          if [ "$FROM_SHA" = "$TO_SHA" ]; then
            echo "skip=true" >> "$GITHUB_OUTPUT"
            echo "No new commits since last documentation run."
          else
            COMMIT_COUNT=$(git rev-list --count $FROM_SHA..$TO_SHA)
            echo "from=$FROM_SHA" >> "$GITHUB_OUTPUT"
            echo "to=$TO_SHA" >> "$GITHUB_OUTPUT"
            echo "count=$COMMIT_COUNT" >> "$GITHUB_OUTPUT"
            echo "skip=false" >> "$GITHUB_OUTPUT"
          fi

      - name: Build payload
        if: steps.range.outputs.skip == 'false'
        id: payload
        run: |
          bash scripts/build-batch-payload.sh \
            "${{ steps.range.outputs.from }}" \
            "${{ steps.range.outputs.to }}" \
            "${{ env.PATH_FILTER }}" \
            "${{ github.event_name == 'workflow_dispatch' && 'manual' || 'scheduled' }}" \
            "${{ github.actor }}" \
            "${{ github.repository }}" \
            > /tmp/payload.json

          echo "payload_path=/tmp/payload.json" >> "$GITHUB_OUTPUT"
          echo "--- Payload preview ---"
          cat /tmp/payload.json | jq .

      - name: POST to GAS (or dry run)
        if: steps.range.outputs.skip == 'false'
        id: post
        run: |
          if [ "${{ inputs.dry_run }}" = "true" ]; then
            echo "DRY RUN — payload not sent."
            echo "ack=dry_run" >> "$GITHUB_OUTPUT"
            exit 0
          fi

          RESPONSE=$(curl -sL \
            -d @/tmp/payload.json \
            -H "Content-Type: application/json" \
            "$GAS_WEBAPP_URL")

          echo "--- GAS Response ---"
          echo "$RESPONSE" | jq .

          # Extract ack from response
          VPS_ACK=$(echo "$RESPONSE" | jq -r '.tracking.vpsAck // false')
          echo "ack=$VPS_ACK" >> "$GITHUB_OUTPUT"

      - name: Move last-documented tag
        if: steps.range.outputs.skip == 'false' && steps.post.outputs.ack == 'true'
        run: |
          git tag -f last-documented ${{ steps.range.outputs.to }}
          git push -f origin last-documented
          echo "Tag last-documented moved to ${{ steps.range.outputs.to }}"

      - name: Report result
        if: always()
        run: |
          if [ "${{ steps.range.outputs.skip }}" = "true" ]; then
            echo "::notice::No new commits to document."
          elif [ "${{ steps.post.outputs.ack }}" = "true" ]; then
            echo "::notice::Batch documented. Tag moved to ${{ steps.range.outputs.to }}."
          elif [ "${{ steps.post.outputs.ack }}" = "dry_run" ]; then
            echo "::notice::Dry run complete. No changes made."
          else
            echo "::warning::VPS did not acknowledge batch. Tag NOT moved. Will retry on next run."
          fi
```

**Verification**: File is valid YAML. Workflow appears in GitHub Actions tab. `workflow_dispatch` shows manual trigger button with `dry_run` checkbox.

### Task 2.2 — Create the batch payload builder script

**File**: `scripts/build-batch-payload.sh`

This script is called by the GitHub Action but is also **runnable locally** for testing.

```
Usage: bash scripts/build-batch-payload.sh FROM_SHA TO_SHA PATH_FILTER TRIGGER TRIGGERED_BY REPOSITORY

Outputs: JSON payload to stdout (suitable for piping to a file or curl -d @-).
```

**Logic**:

```
1. Parse arguments: FROM_SHA, TO_SHA, PATH_FILTER, TRIGGER, TRIGGERED_BY, REPOSITORY
2. COMMIT_COUNT = git rev-list --count FROM_SHA..TO_SHA
3. COMMITS = git log FROM_SHA..TO_SHA --pretty=format:'{"sha":"%H","shortSha":"%h","author":"%an","message":"%s","timestamp":"%aI"}'
   → Collect into JSON array via jq
4. FILES_CHANGED = git diff --name-only FROM_SHA TO_SHA -- "$PATH_FILTER"
   → Strip PATH_FILTER prefix
   → Collect into JSON array via jq
5. Construct final JSON with jq:
   {
     action: "reportBatch",
     trigger, triggeredBy, repository,
     range: { from: FROM_SHA, to: TO_SHA, commitCount },
     commits: [...],
     filesChanged: [...],
     pathFilter: PATH_FILTER
   }
6. Output to stdout
```

**Prerequisites**: `git`, `jq`.

**Verification**: Running locally from project root with two known commit SHAs produces valid JSON. `jq .` parses it without error. `filesChanged` only contains files matching the path filter with prefix stripped.

### Task 2.3 — Add GAS_WEBAPP_URL as GitHub secret

**Manual step (human)**: In the GitHub repo, go to Settings → Secrets and variables → Actions → New repository secret:
- Name: `GAS_WEBAPP_URL`
- Value: the current exec URL

This task cannot be automated. The orchestrator should inform the user.

### Task 2.4 — Commit

```bash
git add .github/workflows/doc-batch.yml scripts/build-batch-payload.sh
git commit -m "feat: Phase 2 — GitHub Actions documentation batch workflow"
```

### Phase 2 Completion Criteria

- [ ] `.github/workflows/doc-batch.yml` has `workflow_dispatch` + `schedule` triggers
- [ ] `dry_run` input parameter works (previews payload, doesn't send)
- [ ] Workflow determines range via `last-documented` tag (handles missing tag on first run)
- [ ] `scripts/build-batch-payload.sh` produces valid JSON (testable locally)
- [ ] Path filter strips prefix from file paths
- [ ] Tag only moves when `vpsAck == true`
- [ ] `GAS_WEBAPP_URL` secret documented as human gate
- [ ] Committed to git

---

## Phase 3 — VPS Stub Evolution

**Goal**: Extend the stub server to implement the VPS handshake protocol (ack + batchId) and durable batch storage. The stub simulates what the real VPS will do.

**Agent assignment**: vps-stub-agent.

**Parallelization**: Independent of Phase 1 and Phase 2.

### Task 3.1 — Add POST /changelog batch handling with ack

**Edit**: `stub-server/server.js`

Modify the `POST /changelog` handler:

1. **Detect payload type**: If payload has `.batch` field → batch mode. Otherwise → legacy mode (existing behavior, backward compatible).
2. **Batch mode**:
   - Generate a `batchId` using `crypto.randomUUID()` (Node.js 19+) or fallback `crypto.randomBytes(16).toString('hex')`.
   - Pretty-print the batch (same as current behavior).
   - Return `{ ack: true, batchId: batchId, timestamp: ISO }`.
3. **Legacy mode**: Keep existing `{ received: true, timestamp }` response.

**Verification**: Legacy payloads still return `{ received: true, timestamp }`. Batch payloads return `{ ack: true, batchId: "...", timestamp }`.

### Task 3.2 — Add durable batch storage

**Create**: `stub-server/batches/` directory (gitignored, auto-created).

When a batch is received:
1. Write the full payload to `stub-server/batches/{batchId}.json`.
2. Console log: `Batch stored: batches/{batchId}.json`.

This simulates the "durably store" step from the handshake protocol. The real VPS would use a database.

**Add** `stub-server/batches/` to `.gitignore`.

**Verification**: After receiving a batch POST, a JSON file appears in `stub-server/batches/`. File contains the full payload.

### Task 3.3 — Add GET /batches listing endpoint

Add a new route to the stub server:

- `GET /batches` → Returns JSON array of stored batch summaries: `[{ batchId, timestamp, commitCount, repository }]`.
- `GET /batches/:id` → Returns the full stored batch payload.

This is useful for manual verification and will mirror a real VPS dashboard endpoint.

**Verification**: After storing batches, `curl http://localhost:3456/batches` returns the list. `curl http://localhost:3456/batches/{batchId}` returns the full payload.

### Task 3.4 — Commit

```bash
git add stub-server/server.js .gitignore
git commit -m "feat: Phase 3 — VPS stub with batch ack + durable storage"
```

### Phase 3 Completion Criteria

- [ ] `POST /changelog` returns `{ ack: true, batchId }` for batch payloads
- [ ] `POST /changelog` returns `{ received: true }` for legacy payloads (backward compatible)
- [ ] Batch payloads stored to `stub-server/batches/{batchId}.json`
- [ ] `GET /batches` returns batch listing
- [ ] `GET /batches/:id` returns full batch payload
- [ ] `stub-server/batches/` gitignored
- [ ] Zero npm dependencies maintained
- [ ] Committed to git

---

## Phase 4 — End-to-End Integration Testing

**Goal**: Verify the complete flow: GitHub Action (simulated locally) → GAS → VPS stub → ack → tag movement.

**Agent assignment**: test-agent.

**Prerequisite (human actions)**:
1. Stub server running (`bash scripts/dev-start.sh` or manually)
2. ngrok URL set in GAS Script Properties (`CHANGE_TRACKER_VPS_URL`)
3. `CHANGE_TRACKER_ENABLED = true` in Script Properties
4. Latest code pushed to GAS (`clasp push -f`)

### Task 4.1 — Test batch payload builder locally

```bash
# Use two known commits from the repo
FROM=$(git log --reverse --pretty=format:"%H" | head -1)
TO=$(git rev-parse HEAD)

bash scripts/build-batch-payload.sh "$FROM" "$TO" "apps-script/src/" "manual" "test-user" "owner/cash_synch_proto" | jq .
```

**Verify**: Valid JSON output. `commits` array has entries. `filesChanged` contains only `apps-script/src/` files with prefix stripped.

### Task 4.2 — Test reportBatch → GAS → VPS (happy path)

```bash
# Build payload and POST to GAS
FROM=$(git log --reverse --pretty=format:"%H" | head -1)
TO=$(git rev-parse HEAD)

bash scripts/build-batch-payload.sh "$FROM" "$TO" "apps-script/src/" "manual" "e2e-test" "owner/cash_synch_proto" \
  | curl -sL -d @- -H "Content-Type: application/json" "$GAS_WEBAPP_URL" | jq .
```

**Verify all three outputs**:
1. **curl response**: `{ success: true, tracking: { vpsStatus: 200, vpsAck: true, vpsBatchId: "..." } }`
2. **Stub server terminal**: Printed batch payload. Logged `Batch stored: batches/{batchId}.json`.
3. **`_CHANGE_LOG` sheet**: New row with batch summary in changelog column.

### Task 4.3 — Test VPS ack verification

```bash
# Verify batch was stored
curl -s http://localhost:3456/batches | jq .
```

**Verify**: Batch appears in listing with correct metadata.

### Task 4.4 — Test stub-safe mode (VPS disabled)

Set `CHANGE_TRACKER_ENABLED = false` in Script Properties.

Repeat Task 4.2 curl command.

**Verify**: Response has `vpsStatus: "skipped"`, `vpsAck: false`. Stub server shows no new output.

Re-enable: set `CHANGE_TRACKER_ENABLED = true`.

### Task 4.5 — Test VPS-down scenario (handshake failure)

Stop the stub server (keep ngrok running so GAS gets a 502).

Repeat Task 4.2 curl command.

**Verify**: Response still returns (no crash). `vpsAck: false`. `_CHANGE_LOG` has row with error status. This simulates the "tag doesn't move" condition.

### Task 4.6 — Test GitHub Action locally (dry run)

If `act` (GitHub Actions local runner) is available:

```bash
act workflow_dispatch -W .github/workflows/doc-batch.yml --input dry_run=true
```

Otherwise, verify the workflow YAML is valid by reading through it manually and confirming the step logic matches the payload builder output.

### Task 4.7 — Generate test report

**Create**: `docs/test-report-plan2.md`

| Test | Status | Notes |
|------|--------|-------|
| 4.1 Payload builder | PASS/FAIL | ... |
| 4.2 Happy path (batch → GAS → VPS ack) | PASS/FAIL | ... |
| 4.3 VPS batch storage | PASS/FAIL | ... |
| 4.4 Stub-safe mode | PASS/FAIL | ... |
| 4.5 VPS-down (no ack) | PASS/FAIL | ... |
| 4.6 GitHub Action dry run | PASS/FAIL/MANUAL | ... |

### Task 4.8 — Commit

```bash
git add docs/test-report-plan2.md
git commit -m "test: Phase 4 — plan 2 e2e integration testing"
```

### Phase 4 Completion Criteria

- [ ] Batch payload builder produces valid JSON from local commits
- [ ] Happy path: GAS relays to VPS, VPS returns ack, GAS returns ack to caller
- [ ] VPS stores batch durably and serves via GET /batches
- [ ] Stub-safe mode skips VPS gracefully
- [ ] VPS-down scenario: no crash, no ack, tag would not move
- [ ] Test report generated
- [ ] Committed to git

---

## Phase 5 — Finalization and Tag

**Goal**: Deploy updated GAS, set the `last-documented` baseline tag, final commit and tag.

**Agent assignment**: Orchestrator direct.

### Task 5.1 — Create new GAS deployment

```bash
cd apps-script
clasp push -f
clasp deploy -d "v2.0.0 — Batch documentation pipeline"
```

Note the new deployment ID and exec URL.

### Task 5.2 — Set last-documented baseline tag

```bash
git tag last-documented HEAD
```

This establishes the baseline for the first GitHub Action run. All commits before this tag are considered "already documented."

### Task 5.3 — Update .env and secrets

Update `.env` with new deployment URL (if changed).

**Human gate**: Update `GAS_WEBAPP_URL` GitHub secret with new exec URL.

### Task 5.4 — Final commit and tag

```bash
git add -A
git commit -m "docs: Phase 5 — v2.0.0 deployment + baseline tag"
git tag v2.0.0
```

### Phase 5 Completion Criteria

- [ ] New GAS deployment created
- [ ] `last-documented` tag set at HEAD
- [ ] `.env` updated with new deployment URL
- [ ] `GAS_WEBAPP_URL` GitHub secret updated (human gate)
- [ ] Committed and tagged `v2.0.0`

---

## Progress Tracker

| Phase | Description | Status | Completed |
|-------|-------------|--------|-----------|
| 0 | Sandbox hardening (plan 1 extensions) | ⬜ NOT STARTED | — |
| 1 | GAS batch endpoint | ⬜ NOT STARTED | — |
| 2 | GitHub Actions workflow | ⬜ NOT STARTED | — |
| 3 | VPS stub evolution | ⬜ NOT STARTED | — |
| 4 | End-to-end integration testing | ⬜ NOT STARTED | — |
| 5 | Finalization + tag | ⬜ NOT STARTED | — |

**Legend**: ⬜ NOT STARTED | 🔄 IN PROGRESS | ✅ COMPLETE | 🚫 BLOCKED

---

## Orchestrator Notes

### Parallelization Opportunities
- **Phases 1, 2, and 3 are fully independent.** All share the payload contracts defined in this document. No code dependency between them. Launch all three agents in parallel after Phase 0 completes.
- **Phase 0** is sequential — must complete before 1/2/3 since it cleans up WebApp.gs and sets up .env.
- **Phase 4** depends on all of 1, 2, 3.

### Human Gates
- **Before Phase 2, Task 2.3**: Human must add `GAS_WEBAPP_URL` as a GitHub secret.
- **Before Phase 4**: Human must run `dev-start.sh` (or manual stub + ngrok), set Script Properties, `clasp push -f`.
- **Phase 5, Task 5.3**: Human must update the GitHub secret if the deployment URL changed.

### Risk Areas
- **GitHub Actions `contents: write` permission**: Needed to push the `last-documented` tag. If the repo has branch protection rules, the `GITHUB_TOKEN` may not have permission. Workaround: use a PAT as a secret, or configure branch protection to allow GitHub Actions.
- **ngrok free tier URL changes**: Every ngrok session gets a new URL. `dev-start.sh` mitigates this by printing the URL, but Script Properties still need manual update. No way around this without a paid ngrok domain.
- **`crypto.randomUUID()` availability**: Requires Node.js 19+. The stub should include a fallback for older Node versions.
- **GAS deployment caching**: After `clasp push`, test via `/dev` URL first. Only deploy when confirmed working.
- **Stale `last-documented` tag**: If someone manually moves or deletes the tag, the next Action run reprocesses a potentially large range. Not harmful but worth noting.

### Enterprise Migration Checklist
When transplanting to enterprise:
1. Copy updated `ChangeTracker.gs` (with `notifyBatch` + `buildBatchPayload`)
2. Apply WebApp.gs diff (add `reportBatch` case + `handleReportBatch`)
3. Copy `.github/workflows/doc-batch.yml` (update `PATH_FILTER` and `GAS_WEBAPP_URL` secret)
4. Copy `scripts/build-batch-payload.sh`
5. Set GAS Script Properties for VPS
6. Add `GAS_WEBAPP_URL` as GitHub secret in enterprise repo
7. Set `last-documented` tag at desired starting point
8. No stub server needed — replace with real VPS endpoint