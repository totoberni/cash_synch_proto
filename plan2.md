# plan2.md — Automated Documentation Pipeline

**Status**: DRAFT — Two-Part Plan (Local → VPS)
**Current Phase**: 0 Complete, Phases 1-3 Ready
**Last Updated**: 2026-03-01

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
2. Stub VPS server that prints received payloads (localhost:3456)
3. ngrok tunnel exposing stub server to GAS
4. Access to GitHub Actions
5. Enterprise Git repo (`enterprise-operations-platform/`)

**What does NOT exist**:
1. No production VPS (stub server + ngrok is the surrogate)
2. No enterprise GDrive access (can't validate on their Sheets)
3. No VPS provisioned (pending CEO approval — see VPSs.md)

**Plan 2 structure**:
- **PART A** (Phases 0-6): Build and test the entire pipeline locally using ngrok + stub server. This includes the sandbox batch endpoint, GitHub Actions workflow, VPS stub evolution, integration testing, and enterprise repo integration — all running against the local stub via ngrok.
- **PART B** (Phases V1-V5): Future migration from local ngrok to a production VPS. Covers provisioning, cutover, n8n orchestration, AI agent deployment, and documentation delivery. Deferred until CEO approves VPS spend and the local pipeline is proven.

The architecture is designed so that **the only change needed for VPS migration is swapping the ngrok URL for a VPS URL** in GAS Script Properties. All other components (GAS endpoints, GitHub Actions, payload contracts) remain identical.

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

# PART A — Local Pipeline (ngrok + Stub Server)

> All phases in Part A use the **local stub server** (localhost:3456) exposed via **ngrok** as the VPS surrogate. No production VPS is required. The goal is to prove the entire pipeline end-to-end before committing to VPS infrastructure.

---

## Phase 0 — Sandbox Hardening (COMPLETE)

Completed in commit `36b5e53`. Deliverables: `.env.example`, `scripts/dev-start.sh`, `.env` sourcing in trigger script, WebApp.gs cleanup. See `.orchestrator/state.md` for details.

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

## Phase 6 — Enterprise Integration (Local)

**Goal**: Migrate the sandbox pipeline into `enterprise-operations-platform` while still using the local ngrok + stub server. This proves the pipeline works in the enterprise context before any VPS is provisioned.

**Agent assignment**: Orchestrator direct (cross-codebase changes).

**Prerequisite**: Phases 1-5 complete and verified in sandbox. Access to enterprise GAS project (SISTEMA_DIPENDENTI_V9.2) for `clasp push`.

### Enterprise Codebase Context

The enterprise platform (`enterprise-operations-platform/`) is a Next.js 14 + Prisma + Supabase multi-tenant SaaS with:
- 81 API routes, 83 library modules, 78 components, 23 Prisma models
- 4 engines: Operations, HR, Finance, Referral (all frontend-complete)
- 17 Claude agents (Raulph orchestrator ecosystem)
- Existing CI/CD via GitHub Actions (`ci.yml`)
- GAS files at `apps-script/src/` with same structure as sandbox

**Target GAS project**: SISTEMA_DIPENDENTI_V9.2
- GAS Project ID: `1xF9D62dLZJ7df0aNmKm82UJ6BZPGiOAKdxKdvWp0Ra-NVmmP60GrCQH4`
- GAS IDE URL: `https://script.google.com/home/projects/1xF9D62dLZJ7df0aNmKm82UJ6BZPGiOAKdxKdvWp0Ra-NVmmP60GrCQH4/edit`
- Mapped Sheet: SISTEMA_DIPENDENTI_V9.3 (HR_SPREADSHEET_ID: `1DOCv_385d9RZcHHoc6uSen0JlpyxKVHSkaYQQNMcbiE`)
- Enterprise Engine: HR Engine

**Key difference from sandbox**: The enterprise WebApp.gs already has `sync` action routing (referral, tasks, hr, finance) that our sandbox stripped out. Migration means **adding** `reportBatch` alongside `sync`, not replacing it.

### Task 6.1 — Copy ChangeTracker.gs to Enterprise

**Copy**: `cash_synch_proto/apps-script/src/tracking/ChangeTracker.gs` → `enterprise-operations-platform/apps-script/src/tracking/ChangeTracker.gs`

This is a new file in the enterprise project. No merge conflicts.

**Also copy**: `cash_synch_proto/apps-script/src/tracking/changelog.md` → `enterprise-operations-platform/apps-script/src/tracking/changelog.md`

**Verification**: File exists in enterprise. Contains `notifyBatch`, `buildBatchPayload`, `notify`, `buildPayload`. No `let`/`const`.

### Task 6.2 — Merge reportBatch into Enterprise WebApp.gs

**Edit**: `enterprise-operations-platform/apps-script/src/api/WebApp.gs`

The enterprise `doPost` switch currently has:
```javascript
case 'sync':
  response = handleSyncRequest(body, correlationId);
  break;
case 'writeLog':
  // ...
```

**Add** after the existing cases (before `default`):
```javascript
case 'reportBatch':
  response = handleReportBatch(body, correlationId);
  break;
```

**Add** the `handleReportBatch()` function (copy from sandbox WebApp.gs — identical).

Update `availableActions` in the `default` error response to include `'reportBatch'`.

**Verification**: Enterprise doPost routes `sync`, `writeLog`, and `reportBatch`. `handleReportBatch` validates range, commits, repository. No sync handlers modified.

### Task 6.3 — Set up Enterprise clasp project

**Create**: `enterprise-operations-platform/apps-script/.clasp.json`

```json
{
  "scriptId": "1xF9D62dLZJ7df0aNmKm82UJ6BZPGiOAKdxKdvWp0Ra-NVmmP60GrCQH4",
  "rootDir": "src"
}
```

**Human gate**: Must have `clasp login` with access to the SISTEMA_DIPENDENTI_V9.2 project.

### Task 6.4 — Push and test enterprise GAS (stub-safe)

```bash
cd enterprise-operations-platform/apps-script && clasp push -f
```

Test with VPS disabled (no Script Properties set yet):

```bash
# Use the enterprise dev URL
ENTERPRISE_DEV_URL="https://script.google.com/macros/s/1xF9D62dLZJ7df0aNmKm82UJ6BZPGiOAKdxKdvWp0Ra-NVmmP60GrCQH4/dev"

curl -sL -d '{
  "action": "reportBatch",
  "trigger": "manual",
  "triggeredBy": "test-user",
  "repository": "owner/enterprise-operations-platform",
  "range": { "from": "aaaa", "to": "bbbb", "commitCount": 2 },
  "commits": [
    { "sha": "aaaa", "shortSha": "aaa", "author": "dev1", "message": "feat: X", "timestamp": "2026-03-01T10:00:00Z" }
  ],
  "filesChanged": ["api/WebApp.gs"],
  "pathFilter": "apps-script/src/"
}' -H "Content-Type: application/json" "$ENTERPRISE_DEV_URL" | jq .
```

**Expected**: `{ success: true, tracking: { vpsStatus: "skipped", vpsAck: false } }`

**Also verify**: Existing `sync` action still works (no regression).

### Task 6.5 — Configure Enterprise GAS for local stub

**Human gate**: Set Script Properties in SISTEMA_DIPENDENTI_V9.2 project:

| Property | Value | Notes |
|----------|-------|-------|
| `CHANGE_TRACKER_VPS_URL` | ngrok HTTPS URL + `/changelog` | e.g., `https://abc123.ngrok-free.app/changelog` |
| `CHANGE_TRACKER_ENABLED` | `true` | Enables VPS relay |
| `GAS_DEPLOYMENT_URL` | Enterprise exec URL | Self-reference in payload |

**Prerequisite**: Stub server running locally via `dev-start.sh` (from sandbox), ngrok active.

### Task 6.6 — Test enterprise GAS → local stub (happy path)

With stub server + ngrok running:

```bash
curl -sL -d '{
  "action": "reportBatch",
  "trigger": "manual",
  "triggeredBy": "e2e-enterprise-test",
  "repository": "owner/enterprise-operations-platform",
  "range": { "from": "aaaa", "to": "bbbb", "commitCount": 1 },
  "commits": [
    { "sha": "aaaa", "shortSha": "aaa", "author": "dev1", "message": "test: enterprise e2e", "timestamp": "2026-03-01T12:00:00Z" }
  ],
  "filesChanged": ["lib/sync/gas-client.ts"],
  "pathFilter": "src/"
}' -H "Content-Type: application/json" "$ENTERPRISE_DEV_URL" | jq .
```

**Verify**:
1. curl response: `{ success: true, tracking: { vpsStatus: 200, vpsAck: true, vpsBatchId: "..." } }`
2. Stub server terminal: Printed enterprise batch payload
3. `_CHANGE_LOG` sheet in SISTEMA_DIPENDENTI_V9.3: New batch row
4. Stub server `batches/` directory: New JSON file with enterprise payload

### Task 6.7 — Copy GitHub Actions workflow to enterprise

**Copy**: `cash_synch_proto/.github/workflows/doc-batch.yml` → `enterprise-operations-platform/.github/workflows/doc-batch.yml`

**Adapt**:
```yaml
env:
  GAS_WEBAPP_URL: ${{ secrets.GAS_WEBAPP_URL }}
  # Enterprise monitors sync module changes
  PATH_FILTER: 'src/lib/sync/'
```

**Also copy**: `cash_synch_proto/scripts/build-batch-payload.sh` → `enterprise-operations-platform/scripts/build-batch-payload.sh`

**Human gate**: Add `GAS_WEBAPP_URL` as GitHub secret in enterprise repo (value = enterprise exec URL).

### Task 6.8 — Test enterprise GitHub Action (dry run)

```bash
# From enterprise repo root, test payload builder locally
FROM=$(git log --reverse --pretty=format:"%H" | head -1)
TO=$(git rev-parse HEAD)

bash scripts/build-batch-payload.sh "$FROM" "$TO" "src/lib/sync/" "manual" "test-user" "owner/enterprise-operations-platform" | jq .
```

**Verify**: Valid JSON. `filesChanged` only contains `src/lib/sync/` files with prefix stripped.

Then trigger via GitHub UI: Actions → Documentation Batch → Run workflow → check `dry_run`.

**Verify**: Workflow runs, shows payload preview, reports "Dry run complete."

### Task 6.9 — Full enterprise e2e test (GitHub Action → GAS → local stub)

With stub + ngrok running, Script Properties configured, and `GAS_WEBAPP_URL` secret set:

Trigger the workflow without `dry_run`.

**Verify**:
1. GitHub Action: Builds payload, POSTs to GAS
2. GAS: Relays to local stub via ngrok
3. Stub: Returns `{ ack: true, batchId }`
4. GAS: Returns ack to GitHub Action
5. GitHub Action: Moves `last-documented` tag
6. `_CHANGE_LOG` sheet: New batch row with vpsStatus 200
7. Stub `batches/` directory: New JSON file

### Task 6.10 — Create enterprise deployment and commit

```bash
cd enterprise-operations-platform/apps-script
clasp push -f
clasp deploy -d "v1.0.0-doc-pipeline — reportBatch endpoint"
```

```bash
cd enterprise-operations-platform
git add apps-script/src/tracking/ChangeTracker.gs \
  apps-script/src/api/WebApp.gs \
  apps-script/src/tracking/changelog.md \
  .github/workflows/doc-batch.yml \
  scripts/build-batch-payload.sh
git commit -m "feat: Phase 6 — documentation pipeline (local, via ngrok stub)"
```

### Phase 6 Completion Criteria

- [ ] `ChangeTracker.gs` exists in enterprise project (new file)
- [ ] Enterprise `WebApp.gs` has `reportBatch` case alongside `sync` case
- [ ] Existing `sync` action not broken (regression check)
- [ ] Enterprise `.clasp.json` configured for SISTEMA_DIPENDENTI_V9.2
- [ ] `clasp push -f` succeeds for enterprise project
- [ ] Stub-safe test returns `{ success: true, vpsStatus: "skipped" }`
- [ ] Happy path test with local stub returns `vpsAck: true`
- [ ] `doc-batch.yml` in enterprise repo with adapted PATH_FILTER
- [ ] `build-batch-payload.sh` in enterprise repo
- [ ] `GAS_WEBAPP_URL` secret added to enterprise repo (human gate)
- [ ] GitHub Action dry run succeeds
- [ ] Full e2e test (Action → GAS → local stub → ack → tag) passes
- [ ] Enterprise GAS deployment created
- [ ] Committed to enterprise repo

---

**END OF PART A**

> At this point, the entire documentation pipeline is functional:
> - GitHub Actions detects new commits, builds batch payloads
> - GAS receives and relays to the local stub (via ngrok)
> - Stub acknowledges, tag moves, batch is stored
> - The pipeline works identically for both sandbox and enterprise repos
>
> **What's missing**: A real VPS to replace the local stub. This is covered in Part B.
> The critical insight is that **the only configuration change needed** is replacing the ngrok URL
> in GAS Script Properties with the VPS URL. Everything else is identical.

---

## Progress Tracker

### PART A — Local Pipeline

| Phase | Description | Status | Completed |
|-------|-------------|--------|-----------|
| 0 | Sandbox hardening (plan 1 extensions) | ✅ COMPLETE | 2026-02-16 |
| 1 | GAS batch endpoint (reportBatch + notifyBatch) | ⬜ NOT STARTED | — |
| 2 | GitHub Actions workflow (doc-batch.yml) | ⬜ NOT STARTED | — |
| 3 | Local stub evolution (ack + batch storage) | ⬜ NOT STARTED | — |
| 4 | End-to-end integration testing (local) | ⬜ NOT STARTED | — |
| 5 | Finalization + tag (sandbox v2.0.0) | ⬜ NOT STARTED | — |
| 6 | Enterprise integration (local) | ⬜ NOT STARTED | — |

### PART B — VPS Migration (Future)

| Phase | Description | Status | Completed |
|-------|-------------|--------|-----------|
| V1 | VPS provisioning + Docker stack | ⬜ NOT STARTED | — |
| V2 | ngrok → VPS cutover | ⬜ NOT STARTED | — |
| V3 | n8n orchestration | ⬜ NOT STARTED | — |
| V4 | AI documentation agents | ⬜ NOT STARTED | — |
| V5 | Documentation delivery | ⬜ NOT STARTED | — |

**Legend**: ⬜ NOT STARTED | 🔄 IN PROGRESS | ✅ COMPLETE | 🚫 BLOCKED

---

## Orchestrator Notes

### Part A Parallelization
- **Phase 0** is complete (sandbox hardened, .env set up).
- **Phases 1, 2, and 3 are fully independent.** All share the payload contracts defined in this document. No code dependency between them. Launch all three agents in parallel.
- **Phase 4** depends on all of 1, 2, 3 completing.
- **Phase 5** depends on 4 completing.
- **Phase 6** depends on 5 completing (sandbox must be proven before enterprise integration).

### Part B Parallelization
- **Phase V1** (provisioning) is independent — can start during Part A if CEO approves VPS spend.
- **Phases V2-V5** are sequential: cutover → orchestration → agents → delivery.
- **Phase V3** (n8n) can partially overlap with V2 if the VPS stack is provisioned early.

### Human Gates
- **Before Phase 2, Task 2.3**: Human must add `GAS_WEBAPP_URL` as a GitHub secret.
- **Before Phase 4**: Human must run `dev-start.sh` (or manual stub + ngrok), set Script Properties, `clasp push -f`.
- **Phase 5, Task 5.3**: Human must update the GitHub secret if the deployment URL changed.
- **Phase 6, Task 6.5**: Human must set enterprise GAS Script Properties (CHANGE_TRACKER_VPS_URL, CHANGE_TRACKER_ENABLED).
- **Before Phase V1**: CEO must approve VPS spend (see VPSs.md for cost analysis).
- **Phase V2, Task V2.3**: Human must update GAS Script Properties to swap ngrok URL for VPS URL.

### Risk Areas
- **GitHub Actions `contents: write` permission**: Needed to push the `last-documented` tag. If the repo has branch protection rules, the `GITHUB_TOKEN` may not have permission. Workaround: use a PAT as a secret, or configure branch protection to allow GitHub Actions.
- **ngrok free tier URL changes**: Every ngrok session gets a new URL. `dev-start.sh` mitigates this by printing the URL, but Script Properties still need manual update. No way around this without a paid ngrok domain.
- **`crypto.randomUUID()` availability**: Requires Node.js 19+. The stub should include a fallback for older Node versions.
- **GAS deployment caching**: After `clasp push`, test via `/dev` URL first. Only deploy when confirmed working.
- **Stale `last-documented` tag**: If someone manually moves or deletes the tag, the next Action run reprocesses a potentially large range. Not harmful but worth noting.
- **Enterprise WebApp.gs merge conflict**: Enterprise has `sync` action routing (referral, tasks, hr, finance). Must ADD `reportBatch` case alongside existing switch cases, not replace them.
- **Hetzner April 2026 price increase**: ~30-37% across all cloud tiers effective April 1, 2026. Budget accordingly (see VPSs.md for detailed pricing).
- **API costs dominate VPS costs**: VPS hosting (<€10/mo) is <5% of total spend. AI API costs (€50-400/mo at scale) are the real expense for multi-agent documentation workloads.

---

# PART B — VPS Migration & Production Scaling (Future)

> **Status**: NOT STARTED — Deferred until Part A is proven and CEO approves VPS spend.
> **Prerequisite**: All Part A phases (0-6) complete. Local pipeline working end-to-end.
> **Reference**: See VPSs.md for detailed VPS comparison, pricing, and multi-agent scaling analysis.

The only infrastructure change needed for VPS migration is **swapping the ngrok URL for a VPS URL** in GAS Script Properties. All GAS endpoints, GitHub Actions workflows, and payload contracts remain identical.

---

## Phase V1 — VPS Provisioning + Docker Stack

**Goal**: Provision a Hetzner cloud VPS and deploy the production Docker stack (n8n + PostgreSQL + Redis + webhook listener).

**Human gate**: CEO must approve VPS spend before this phase begins.

### Task V1.1 — Provision Hetzner VPS

| Setting | Value | Notes |
|---------|-------|-------|
| Provider | Hetzner Cloud | Best EU value (see VPSs.md) |
| Initial tier | CX33 (4 vCPU / 8 GB / 80 GB) | Supports 5-10 concurrent agents |
| Location | Falkenstein (fsn1) or Nuremberg (nbg1) | Lowest latency to EU |
| OS | Ubuntu 22.04 LTS | Docker-ready |
| SSH key | Add developer's public key | No password auth |
| Firewall | Allow 22 (SSH), 80 (HTTP), 443 (HTTPS) | Block all other inbound |

**Scale-up path**: CX33 → CX43 (16 GB) at 10-20 agents → CX53 (32 GB) at 20-40 agents. See VPSs.md "Scaling Roadmap".

### Task V1.2 — Install Docker + Docker Compose

```bash
# On the VPS
apt update && apt upgrade -y
apt install -y docker.io docker-compose-plugin
systemctl enable docker
usermod -aG docker $USER
```

### Task V1.3 — Deploy Docker Stack

Create `docker-compose.yml` on VPS:

```yaml
version: '3.8'

services:
  postgres:
    image: postgres:16-alpine
    restart: unless-stopped
    environment:
      POSTGRES_DB: docpipeline
      POSTGRES_USER: pipeline
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U pipeline"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    restart: unless-stopped
    command: redis-server --appendonly yes
    volumes:
      - redisdata:/data

  n8n:
    image: n8nio/n8n:latest
    restart: unless-stopped
    ports:
      - "5678:5678"
    environment:
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_DATABASE=docpipeline
      - DB_POSTGRESDB_USER=pipeline
      - DB_POSTGRESDB_PASSWORD=${DB_PASSWORD}
      - EXECUTIONS_MODE=queue
      - QUEUE_BULL_REDIS_HOST=redis
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=${N8N_USER}
      - N8N_BASIC_AUTH_PASSWORD=${N8N_PASSWORD}
      - WEBHOOK_URL=https://${VPS_DOMAIN}
    volumes:
      - n8ndata:/home/node/.n8n
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_started

  n8n-worker:
    image: n8nio/n8n:latest
    restart: unless-stopped
    command: n8n worker
    environment:
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_DATABASE=docpipeline
      - DB_POSTGRESDB_USER=pipeline
      - DB_POSTGRESDB_PASSWORD=${DB_PASSWORD}
      - EXECUTIONS_MODE=queue
      - QUEUE_BULL_REDIS_HOST=redis
      - N8N_WORKER_CONCURRENCY=5
      - OFFLOAD_MANUAL_EXECUTIONS_TO_WORKERS=true
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_started

  webhook-listener:
    build: ./webhook-listener
    restart: unless-stopped
    ports:
      - "3456:3456"
    environment:
      - DATABASE_URL=postgresql://pipeline:${DB_PASSWORD}@postgres:5432/docpipeline
      - N8N_WEBHOOK_URL=http://n8n:5678/webhook/doc-batch
    depends_on:
      postgres:
        condition: service_healthy

  caddy:
    image: caddy:2-alpine
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - caddydata:/data
      - caddycerts:/config

volumes:
  pgdata:
  redisdata:
  n8ndata:
  caddydata:
  caddycerts:
```

### Task V1.4 — Configure Caddy Reverse Proxy

Create `Caddyfile`:

```
{$VPS_DOMAIN} {
    handle /changelog* {
        reverse_proxy webhook-listener:3456
    }
    handle /n8n* {
        reverse_proxy n8n:5678
    }
    handle /docs* {
        root * /srv/docs
        file_server
    }
}
```

### Task V1.5 — Verify Stack

```bash
docker compose up -d
docker compose ps          # All services should be "running"
curl http://localhost:3456/health   # webhook-listener responds
curl http://localhost:5678          # n8n UI responds
```

### Phase V1 Completion Criteria

- [ ] Hetzner VPS provisioned and SSH accessible
- [ ] Docker + Docker Compose installed
- [ ] All 6 containers running (postgres, redis, n8n, n8n-worker, webhook-listener, caddy)
- [ ] Caddy serving HTTPS with auto-cert
- [ ] `curl https://<domain>/changelog` returns health response
- [ ] n8n UI accessible at `https://<domain>/n8n`

---

## Phase V2 — ngrok → VPS Cutover

**Goal**: Migrate the pipeline from the local ngrok tunnel to the production VPS. This is the critical switchover — the only change is a URL swap in GAS Script Properties.

**Prerequisite**: Phase V1 complete (VPS stack running). Part A Phase 6 complete (enterprise pipeline working via ngrok).

### Task V2.1 — Migrate webhook-listener Code

Copy `stub-server/server.js` to VPS `webhook-listener/` directory. Adapt for production:
- Add PostgreSQL storage (replace console.log with INSERT)
- Add health endpoint (`GET /health`)
- Add n8n trigger (POST to n8n webhook after storing batch)
- Keep the `POST /changelog` contract identical

### Task V2.2 — Verify VPS Endpoint

```bash
# From developer machine, test VPS endpoint directly
curl -sL -d '{"test": true, "action": "reportBatch"}' \
  -H "Content-Type: application/json" \
  https://<vps-domain>/changelog
# EXPECT: { "ack": true, "batchId": "..." }
```

### Task V2.3 — Swap GAS Script Properties (Human Gate)

In both GAS projects (sandbox + enterprise), update Script Properties:

| Property | Old Value | New Value |
|----------|-----------|-----------|
| `CHANGE_TRACKER_VPS_URL` | `https://<ngrok-id>.ngrok.io/changelog` | `https://<vps-domain>/changelog` |

**No other changes needed.** GAS code, GitHub Actions, payload contracts all remain identical.

### Task V2.4 — Verify Full Pipeline via VPS

```bash
# Trigger a test batch through the full pipeline
# GitHub Action → GAS → VPS (not ngrok)
# Verify: _CHANGE_LOG shows vpsStatus=200, VPS postgres has the batch
```

### Task V2.5 — Rollback Procedure

If VPS fails, rollback is instant:
1. Start local stub + ngrok: `./scripts/dev-start.sh`
2. Update `CHANGE_TRACKER_VPS_URL` in GAS Script Properties back to ngrok URL
3. Pipeline immediately works via local again

### Phase V2 Completion Criteria

- [ ] webhook-listener deployed on VPS with PostgreSQL storage
- [ ] `curl https://<domain>/changelog` returns ack response
- [ ] GAS Script Properties updated to VPS URL
- [ ] Full pipeline test passes (GitHub Action → GAS → VPS)
- [ ] Rollback procedure documented and tested
- [ ] ngrok no longer required for pipeline operation

### Enterprise Configuration Requirements

#### 1. GAS Script Properties (SISTEMA_DIPENDENTI_V9.2 project)

| Property | Value | Notes |
|----------|-------|-------|
| `CHANGE_TRACKER_VPS_URL` | `https://<vps-domain>/changelog` | VPS endpoint (replace ngrok) |
| `CHANGE_TRACKER_ENABLED` | `true` | Master switch |
| `GAS_DEPLOYMENT_URL` | The enterprise exec URL | Self-reference in payload |

#### 2. GitHub Secrets (enterprise-operations-platform repo)

| Secret | Value | Purpose |
|--------|-------|---------|
| `GAS_WEBAPP_URL` | Enterprise GAS exec URL | Used by doc-batch workflow |

#### 3. GitHub Actions Workflow Adaptation

The `doc-batch.yml` needs these enterprise-specific changes:

```yaml
env:
  # Enterprise paths to monitor (not just apps-script/src/)
  PATH_FILTER: 'src/lib/sync/'  # or broader: 'src/' for all changes
  # Could also be multi-path: monitor GAS + sync + API changes
```

**Dual trigger**:
- `workflow_dispatch` (manual, with dry_run option)
- `schedule: cron '0 9 */2 * *'` (every 48h)

#### 4. Static HTML Documentation Target

The documentation output will be a **static HTML file** (stub for now, to be replaced by CEO's actual file). Requirements:

| Aspect | Detail |
|--------|--------|
| Location | Local machine (CEO's) until VPS deployment |
| Format | Single-page HTML with embedded CSS |
| Content | Auto-generated documentation of SISTEMA_DIPENDENTI code changes |
| Update mechanism | VPS generates HTML → served via static file server or pushed to repo |
| Initial stub | Create `docs/sistema-dipendenti-docs.html` as placeholder |

### VPS Architecture (Post-Migration)

```
GitHub (enterprise-operations-platform)
    │
    │  Push / PR / Cron (48h)
    ▼
GitHub Actions (doc-batch.yml)
    │
    │  POST /exec { action: "reportBatch", ... }
    ▼
GAS Web App (SISTEMA_DIPENDENTI_V9.2)
    │
    ├── Write batch to _CHANGE_LOG sheet
    │
    │  POST /changelog { batch payload }
    ▼
VPS (Hetzner CX33, recommended)
    │
    ├── Receive batch, store durably (PostgreSQL)
    ├── Return { ack: true, batchId }
    │
    │  (Async processing)
    ├── Fetch diff from GitHub API
    │   GET /repos/owner/repo/compare/{from}...{to}
    ├── Process diff through AI agents (Claude/GPT API)
    ├── Generate HTML documentation
    ├── Update static HTML file
    └── Optionally push to repo or serve via HTTP
```

### Integration with Enterprise Sync Infrastructure

The enterprise already has sophisticated sync infrastructure:

| Existing Component | Relevance to Doc Pipeline |
|--------------------|--------------------------|
| `src/lib/sync/az-protocol.ts` | A↔Z protocol can be extended for doc sync |
| `src/lib/sync/queue-processor.ts` | Queue pattern reusable for doc generation queue |
| `src/lib/logging/logger.ts` | Unified logging for doc pipeline events |
| `src/lib/logging/correlation-id.ts` | Correlation IDs for tracking doc generation |
| `src/lib/sync/gas-client.ts` | GAS API client with correlation (reusable) |
| `bus/PROJECT_SYNC_STATE.md` | Can track doc pipeline state alongside sync state |

**Key insight**: The enterprise's `gas-client.ts` already handles GAS API calls with correlation ID propagation. The doc pipeline's GAS interaction can reuse this client rather than raw `curl` calls.

### Migration Phases (Enterprise-Specific)

#### Phase E1: GAS Endpoint Addition
1. Add `ChangeTracker.gs` to enterprise GAS project
2. Add `reportBatch` case to enterprise WebApp.gs
3. `clasp push` to SISTEMA_DIPENDENTI_V9.2 project
4. Test via `/dev` URL with stub payload
5. Set Script Properties

#### Phase E2: GitHub Actions Deployment
1. Copy `doc-batch.yml` to enterprise `.github/workflows/`
2. Adapt `PATH_FILTER` for enterprise paths (multiple options):
   - `src/lib/sync/` — sync module changes only
   - `apps-script/src/` — GAS code changes
   - `src/` — all source changes (broad)
   - `prisma/` — schema changes
3. Add `GAS_WEBAPP_URL` secret to enterprise repo
4. Test with `workflow_dispatch` dry run

#### Phase E3: VPS Deployment (Replaces Stub)
1. Provision Hetzner CX33 (see VPSs.md)
2. Deploy Docker stack: n8n + PostgreSQL + Redis + webhook listener
3. Configure VPS endpoint in GAS Script Properties
4. Disable ngrok (no longer needed)
5. Test full pipeline: GitHub Action → GAS → VPS → docs

#### Phase E4: HTML Documentation Generation
1. Create doc generation agent on VPS (calls Claude/GPT APIs)
2. Agent receives batch, fetches GitHub diff, generates documentation
3. Output: static HTML file with change documentation
4. Serve HTML via VPS HTTP server or push to repo
5. CEO accesses documentation via browser

#### Phase E5: Static HTML Sync to CEO's Machine
1. Implement sync mechanism (options):
   - **A**: VPS pushes HTML to GitHub repo (CEO pulls)
   - **B**: VPS serves HTML via HTTPS (CEO bookmarks URL)
   - **C**: VPS syncs to CEO's machine via rsync/SCP (requires access)
   - **D**: n8n workflow pushes to Google Drive (CEO's existing flow)
2. **Recommended**: Option B (simplest) or D (integrates with existing workflow)

### What We Need Now to Continue

| # | Requirement | Status | Blocker |
|---|-------------|--------|---------|
| 1 | Complete sandbox plan2 Phases 1-3 (batch endpoint, GitHub Actions, VPS stub) | Pending | No blocker — agents ready |
| 2 | Access to SISTEMA_DIPENDENTI_V9.2 GAS project (for clasp push) | **NEEDED** | Need clasp login + project access |
| 3 | Enterprise repo GitHub Actions access (for adding secrets + workflow) | **NEEDED** | Need repo admin access |
| 4 | Static HTML stub file for local development | Can create now | — |
| 5 | GAS project `.clasp.json` for enterprise project | **NEEDED** | Script ID: `1xF9D62dLZJ7df0aNmKm82UJ6BZPGiOAKdxKdvWp0Ra-NVmmP60GrCQH4` |
| 6 | VPS provisioning (Hetzner CX33) | Pending CEO approval | See VPSs.md |
| 7 | Domain name for VPS (optional, can use IP) | Pending | Low priority |
| 8 | AI API keys for doc generation (Claude, GPT) | **NEEDED** | For VPS agents |
| 9 | Enterprise `.env` values (for testing sync) | **NEEDED** | Supabase, DB credentials |
| 10 | GAS code from SISTEMA_DIPENDENTI_V9.2 project | **NEEDED** | clasp pull or manual copy |

### Spreadsheet → GAS → Enterprise Mapping

| Spreadsheet Name | Spreadsheet ID | GAS Project | Enterprise Engine | .env Key |
|------------------|----------------|-------------|-------------------|----------|
| Sistema_Contabile_Referral_v1 | `1ETubOs4yNB7IMGLvSTrwfXMqUz9zoQBoHJFhDEhoDkM` | (separate) | Referral | `REFERRAL_SPREADSHEET_ID` |
| LINK | `10vPjEYitf_xvn8idWo_UMEEyp0VULU3jqnV9EcJg1bA` | (separate) | Referral Links | `LINK_SPREADSHEET_ID` |
| SISTEMA_TASK_MANAGEMENT_V9.3 | `1dBNUsg4q--Mx65-VrpdYKQDKvPkcl8faL-Q-KrjGUA8` | (separate) | Operations | `TASKS_SPREADSHEET_ID` |
| **SISTEMA_DIPENDENTI_V9.3** | `1DOCv_385d9RZcHHoc6uSen0JlpyxKVHSkaYQQNMcbiE` | **`1xF9D62dLZJ7df0aNmKm82UJ6BZPGiOAKdxKdvWp0Ra-NVmmP60GrCQH4`** | **HR (target)** | `HR_SPREADSHEET_ID` |

### Plan Analysis: Are the Plans Correctly Setting Us Up?

**plan.md (Plan 1)**: Correctly implemented the single-commit change tracking foundation. All 5 phases complete. The architecture (trigger → GAS → VPS relay) is sound and directly transplantable.

**plan2.md (Plan 2)**: Correctly extends Plan 1 with batch processing via GitHub Actions. The handshake protocol (ack-based tag movement) is robust. However, the following gaps exist for enterprise migration:

| Gap | Impact | Resolution |
|-----|--------|------------|
| No enterprise-specific PATH_FILTER configuration | GitHub Action monitors wrong paths | Added in Phase E2 above |
| No HTML doc generation spec | VPS receives batches but has no doc output | Added Phase E4 above |
| No static HTML delivery mechanism | CEO can't access docs | Added Phase E5 above |
| Enterprise WebApp.gs has `sync` action (plan2 assumes our simplified version) | Merge conflict risk | Noted: must ADD case, not replace |
| Enterprise has `gas-client.ts` (TypeScript) for GAS calls | Opportunity to reuse instead of raw curl | Integration point documented |
| Enterprise has existing CI/CD (`ci.yml`) | New workflow must coexist | Use separate workflow file |
| Enterprise uses Raulph orchestrator (17 agents) | Doc pipeline agent should integrate | Can add `doc-pipeline` agent definition |
| No mention of SISTEMA_DIPENDENTI_V9.2 specifically | Plan was generic | Now mapped explicitly |

**Overall assessment**: The plans are ~80% correct for migration. This addendum fills the remaining 20% with enterprise-specific technical details.