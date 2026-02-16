# GAS Change Tracker — Sandbox Prototype

Sandbox prototype for an automated documentation pipeline. A GAS web app receives code change notifications, logs them to Google Sheets, and relays them to a VPS where AI agents generate documentation from code diffs.

Built as a local sandbox because enterprise GDrive access is not yet available. All components are designed to transplant directly into the enterprise codebase.

## Status

| Plan | Description | State |
|------|-------------|-------|
| [plan.md](plan.md) | Base GAS web app + single-commit change tracking | Complete (v1.0.0) |
| [plan2.md](plan2.md) | Batched documentation pipeline via GitHub Actions | In progress |

## Architecture

### Current (plan 1) — Single-commit notifications

```
Developer (post-push script)
    │  POST { action: "reportChange", author, files, changelog, commitHash }
    ▼
GAS Web App → _CHANGE_LOG sheet → VPS stub
```

### Target (plan 2) — Batched documentation pipeline

```
GitHub Actions (manual or 48h cron)
    │
    │  Determine undocumented range: last-documented..HEAD
    │  POST { action: "reportBatch", range, commits, filesChanged, repository }
    ▼
GAS Web App → _CHANGE_LOG sheet → VPS
    │                                  │
    │  { ack: true, batchId }          │  Fetch diff via GitHub API
    │  ← ── ── ── ── ── ── ── ── ── ──│  AI agents generate docs
    ▼
GitHub Action moves last-documented tag (only on ack)
```

Key difference: the VPS fetches full diffs from GitHub API using the commit range — no large payloads through GAS.

## Prerequisites

- [clasp](https://github.com/nicholaschiang/clasp) (v3+) — Google Apps Script CLI
- [Node.js](https://nodejs.org/) (v18+) — for the local stub server
- [ngrok](https://ngrok.com/) — to tunnel localhost for GAS → VPS connectivity
- [jq](https://jqlang.github.io/jq/) — used by trigger and payload builder scripts
- A Google account with Apps Script and Google Sheets access

## Quick Start

```bash
# 1. Configure
cp .env.example .env          # Fill in your GAS deployment URL

# 2. Start dev environment (stub server + ngrok in one terminal)
bash scripts/dev-start.sh

# 3. Set the printed ngrok URL in GAS Script Properties:
#    CHANGE_TRACKER_VPS_URL = https://xxxx.ngrok-free.app/changelog
#    CHANGE_TRACKER_ENABLED = true

# 4. Test
curl -sL "$GAS_WEBAPP_URL?action=ping" | jq .
```

## Configuration

### .env (local, gitignored)

```bash
GAS_WEBAPP_URL=https://script.google.com/macros/s/YOUR_DEPLOYMENT_ID/exec
STUB_SERVER_PORT=3456
```

### GAS Script Properties (Apps Script IDE → Project Settings)

| Property | Purpose | When missing |
|----------|---------|--------------|
| `CHANGE_TRACKER_ENABLED` | Master switch for VPS forwarding | VPS calls skipped |
| `CHANGE_TRACKER_VPS_URL` | VPS endpoint (ngrok URL + `/changelog`) | VPS calls skipped |
| `GAS_DEPLOYMENT_URL` | Included in VPS payload for context | `"not-configured"` |

### GitHub Secrets (for plan 2)

| Secret | Purpose |
|--------|---------|
| `GAS_WEBAPP_URL` | GAS exec URL for the documentation batch workflow |

## API Reference

### GET

| Action | URL | Response |
|--------|-----|----------|
| `ping` | `?action=ping` | `{ status, timestamp, correlationId }` |
| `health` | `?action=health` | `{ status, spreadsheet: { id, name, sheets } }` |
| `getLogs` | `?action=getLogs&correlationId=X` | `{ count, logs: [...] }` |

### POST

All POST requests use: `curl -sL -d '...' -H "Content-Type: application/json" URL`
Do NOT use `-X POST` — GAS 302 redirect breaks it. See [gotchas.md](gotchas.md).

#### reportChange (plan 1)

Single-commit notification from trigger scripts.

```json
{
  "action": "reportChange",
  "author": "dev-name",
  "files": ["WebApp.gs"],
  "changelog": "description of change",
  "commitHash": "abc1234"
}
```

Response: `{ success, correlationId, tracking: { changeLogRow, vpsStatus, vpsResponse } }`

#### reportBatch (plan 2)

Batched documentation request from GitHub Actions.

```json
{
  "action": "reportBatch",
  "trigger": "manual|scheduled",
  "triggeredBy": "github-username",
  "repository": "owner/repo",
  "range": { "from": "full-sha", "to": "full-sha", "commitCount": 4 },
  "commits": [{ "sha": "...", "shortSha": "...", "author": "...", "message": "...", "timestamp": "..." }],
  "filesChanged": ["api/WebApp.gs"],
  "pathFilter": "apps-script/src/"
}
```

Response: `{ success, correlationId, tracking: { changeLogRow, vpsStatus, vpsAck, vpsBatchId } }`

The GitHub Action only moves the `last-documented` tag when `vpsAck == true`.

#### writeLog

```json
{ "action": "writeLog", "level": "INFO", "category": "manual", "message": "..." }
```

## Stub Server

Zero-dependency Node.js server simulating the VPS.

```bash
node stub-server/server.js           # Port 3456 (default)
PORT=4000 node stub-server/server.js  # Custom port
```

**Endpoints** (plan 2):
- `POST /changelog` — Accepts change/batch payloads. Returns `{ ack: true, batchId }` for batches, `{ received: true }` for legacy.
- `GET /batches` — Lists stored batches.
- `GET /batches/:id` — Returns full batch payload.

Batches are stored to `stub-server/batches/` (gitignored).

## Enterprise Migration

1. Copy `apps-script/src/tracking/ChangeTracker.gs` to enterprise
2. Apply WebApp.gs diff: add `reportChange` + `reportBatch` cases and handlers
3. Copy `.github/workflows/doc-batch.yml` (update `PATH_FILTER` and secrets)
4. Copy `scripts/build-batch-payload.sh`
5. Set GAS Script Properties + GitHub secrets
6. Set `last-documented` tag at desired starting point
7. No stub server needed — point to real VPS

`CorrelationId.gs` and `LogService.gs` are already enterprise copies used as-is.

## File Structure

```
cash_synch_proto/
├── CLAUDE.md                          # Project conventions and agent rules
├── README.md                          # This file
├── plan.md                            # Plan 1: base GAS web app (complete)
├── plan2.md                           # Plan 2: batched documentation pipeline
├── gotchas.md                         # Known issues and workarounds
├── .env.example                       # Environment config template
├── apps-script/
│   └── src/
│       ├── appsscript.json            # GAS manifest
│       ├── api/
│       │   └── WebApp.gs              # HTTP endpoints (doGet, doPost)
│       ├── correlation/
│       │   └── CorrelationId.gs       # Enterprise copy, read-only
│       ├── logging/
│       │   └── LogService.gs          # Enterprise copy, read-only
│       └── tracking/
│           └── ChangeTracker.gs       # Change notification + VPS relay
├── .github/
│   └── workflows/
│       └── doc-batch.yml              # Documentation batch workflow (plan 2)
├── stub-server/
│   ├── server.js                      # Local VPS stub
│   └── batches/                       # Stored batch payloads (gitignored)
├── scripts/
│   ├── dev-start.sh                   # One-command dev environment
│   ├── build-batch-payload.sh         # Batch payload builder (used by GitHub Action)
│   ├── post-push-notify.sh            # Single-commit trigger (plan 1)
│   └── post-push-notify.ps1           # PowerShell equivalent
├── docs/
│   ├── test-report.md                 # Plan 1 test results
│   └── test-report-plan2.md           # Plan 2 test results
└── .orchestrator/
    └── state.md                       # Agent orchestration state
```
