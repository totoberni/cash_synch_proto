# GAS Change Tracker — Sandbox Prototype

A Google Apps Script (GAS) web app that receives code change notifications via HTTP POST and forwards them to an external VPS. This is a sandbox prototype — the code will later migrate into the enterprise `apps-script/` directory.

## Architecture

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

## Prerequisites

- [clasp](https://github.com/nicholaschiang/clasp) (v3+) — Google Apps Script CLI
- [Node.js](https://nodejs.org/) (v18+) — for the local stub server
- [ngrok](https://ngrok.com/) — to tunnel localhost for GAS → VPS connectivity
- [jq](https://jqlang.github.io/jq/) — used by the bash trigger script
- A Google account with access to Apps Script and Google Sheets

## Setup

1. **Clone and install clasp** (if not already):
   ```bash
   npm install -g @nicholaschiang/clasp
   clasp login
   ```

2. **Create a Google Sheet** named `CashProto` (or any name). Note the Sheet ID from the URL.

3. **Create a GAS project** bound to the sheet:
   - Open the sheet → Extensions → Apps Script
   - Copy the Script ID from Project Settings

4. **Configure `.clasp.json`**:
   ```bash
   cd apps-script
   # .clasp.json should contain:
   # { "scriptId": "YOUR_SCRIPT_ID", "rootDir": "./src" }
   ```

5. **Push and deploy**:
   ```bash
   cd apps-script
   clasp push
   clasp deploy -d "v1.0.0"
   ```
   Note the deployment exec URL from the output.

6. **Set Script Properties** (Apps Script IDE → Project Settings → Script Properties):

   | Property | Value | Required |
   |----------|-------|----------|
   | `CHANGE_TRACKER_ENABLED` | `true` or `false` | Yes |
   | `CHANGE_TRACKER_VPS_URL` | ngrok HTTPS URL + `/changelog` | Only if VPS enabled |
   | `GAS_DEPLOYMENT_URL` | Your GAS `/exec` URL | Optional (included in VPS payload) |

## Configuration

The app is configured entirely via GAS Script Properties (no hardcoded values):

| Property | Purpose | Default behavior when missing |
|----------|---------|-------------------------------|
| `CHANGE_TRACKER_ENABLED` | Master switch for VPS forwarding | VPS calls skipped |
| `CHANGE_TRACKER_VPS_URL` | Endpoint to forward change data to | VPS calls skipped |
| `GAS_DEPLOYMENT_URL` | Included in the VPS payload for context | `"not-configured"` |

**Stub-safe mode**: If either `CHANGE_TRACKER_ENABLED` is `false` or `CHANGE_TRACKER_VPS_URL` is missing, the app skips VPS forwarding entirely. Changes are still logged to the `_CHANGE_LOG` sheet.

## Usage

### Post-push trigger script (recommended)

```bash
export GAS_WEBAPP_URL="https://script.google.com/macros/s/YOUR_DEPLOYMENT_ID/exec"
./scripts/post-push-notify.sh
```

The script automatically gathers git metadata (author, commit hash, message, changed files in `apps-script/src/`) and POSTs to the GAS web app.

A PowerShell equivalent is available for Windows:
```powershell
$env:GAS_WEBAPP_URL = "https://script.google.com/macros/s/YOUR_DEPLOYMENT_ID/exec"
.\scripts\post-push-notify.ps1
```

### Manual curl

```bash
# Report a change
curl -sL \
  -d '{"action":"reportChange","author":"your-name","files":["WebApp.gs"],"changelog":"description of change","commitHash":"abc1234"}' \
  -H "Content-Type: application/json" \
  "https://script.google.com/macros/s/YOUR_DEPLOYMENT_ID/exec" | jq .

# Health check
curl -sL "https://script.google.com/macros/s/YOUR_DEPLOYMENT_ID/exec?action=health" | jq .

# Ping
curl -sL "https://script.google.com/macros/s/YOUR_DEPLOYMENT_ID/exec?action=ping" | jq .
```

**Important**: Use `curl -sL -d '...'` for POST requests, NOT `curl -X POST`. GAS returns a 302 redirect; `-d` implies POST for the initial request and follows the redirect as GET, while `-X POST` forces POST on the redirect target (which returns 405).

## API Reference

### GET Endpoints

| Action | URL | Description |
|--------|-----|-------------|
| `ping` | `?action=ping` | Returns `{ status, timestamp, correlationId }` |
| `health` | `?action=health` | Returns spreadsheet info and sheet list |
| `getLogs` | `?action=getLogs&correlationId=X` | Fetches log entries from `_LOGS` sheet |

### POST Endpoints

#### `reportChange`

Reports a code change. Writes to `_CHANGE_LOG` sheet and optionally forwards to VPS.

**Request**:
```json
{
  "action": "reportChange",
  "author": "developer-name",
  "files": ["WebApp.gs", "ChangeTracker.gs"],
  "changelog": "Description of what changed",
  "commitHash": "abc1234"
}
```

| Field | Type | Required | Default |
|-------|------|----------|---------|
| `action` | string | Yes | — |
| `author` | string | No | `"unknown"` |
| `files` | string[] | Yes (non-empty) | — |
| `changelog` | string | Yes | — |
| `commitHash` | string | No | `null` |

**Response (success)**:
```json
{
  "success": true,
  "correlationId": "gas_1771157536049_5a1lb8dd",
  "tracking": {
    "changeLogRow": 8,
    "vpsStatus": 200,
    "vpsResponse": "{\"received\":true,\"timestamp\":\"...\"}",
    "error": null
  }
}
```

When VPS is not configured, `vpsStatus` is `"skipped"` and `vpsResponse` is `null`.

#### `writeLog`

Writes a log entry to the `_LOGS` sheet.

**Request**:
```json
{
  "action": "writeLog",
  "level": "INFO",
  "category": "manual",
  "message": "Log message here",
  "metadata": {}
}
```

## Stub Server

A zero-dependency Node.js server that simulates a VPS receiving change notifications.

```bash
# Start (default port 3456)
node stub-server/server.js

# Custom port
PORT=4000 node stub-server/server.js
```

Accepts `POST /changelog` — parses the JSON body, pretty-prints it with a timestamp, and returns `{ received: true, timestamp }`. All other routes return 404.

To expose it to GAS via ngrok:
```bash
ngrok http 3456
# Copy the HTTPS forwarding URL → set as CHANGE_TRACKER_VPS_URL in Script Properties
# Append /changelog to the URL (e.g., https://xxxx.ngrok-free.app/changelog)
```

## Enterprise Migration

To migrate this prototype into the enterprise repo:

1. **Copy** `apps-script/src/tracking/ChangeTracker.gs` into the enterprise `apps-script/src/tracking/` directory
2. **Apply the WebApp.gs diff**: add the `reportChange` case to the doPost switch and the `handleReportChange()` function
3. **Set Script Properties** in the enterprise GAS project (`CHANGE_TRACKER_ENABLED`, `CHANGE_TRACKER_VPS_URL`, `GAS_DEPLOYMENT_URL`)
4. **Update** the enterprise `apps-script/README.md` with the new endpoint documentation

No other files need to change — `CorrelationId.gs` and `LogService.gs` are already enterprise copies used as-is.

## File Structure

```
cash_synch_proto/
├── CLAUDE.md                          # Project conventions and agent rules
├── README.md                          # This file
├── plan.md                            # Implementation plan (5 phases)
├── gotchas.md                         # Known issues and workarounds
├── apps-script/
│   └── src/
│       ├── appsscript.json            # GAS manifest (V8, anonymous access)
│       ├── api/
│       │   ├── WebApp.gs              # HTTP endpoints (doGet, doPost)
│       │   ├── CLAUDE.md              # Module docs
│       │   └── changelog.md
│       ├── correlation/
│       │   ├── CorrelationId.gs       # Request correlation (enterprise copy, read-only)
│       │   ├── CLAUDE.md
│       │   └── changelog.md
│       ├── logging/
│       │   ├── LogService.gs          # Structured logging to _LOGS sheet (enterprise copy, read-only)
│       │   ├── CLAUDE.md
│       │   └── changelog.md
│       └── tracking/
│           ├── ChangeTracker.gs       # Change notification + VPS relay service
│           ├── CLAUDE.md
│           └── changelog.md
├── stub-server/
│   ├── server.js                      # Local VPS stub (Node.js, zero dependencies)
│   ├── CLAUDE.md
│   └── changelog.md
├── scripts/
│   ├── post-push-notify.sh            # Bash trigger script
│   ├── post-push-notify.ps1           # PowerShell trigger script
│   ├── CLAUDE.md
│   └── changelog.md
├── docs/
│   └── test-report.md                 # Phase 4 e2e test results
└── .orchestrator/
    └── state.md                       # Agent orchestration state
```
