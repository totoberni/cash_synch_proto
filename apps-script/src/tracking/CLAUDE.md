# Tracking Module — CLAUDE.md

## Files
- `ChangeTracker.gs` — Singleton service that logs code changes and forwards to VPS.

## ChangeTracker API
```
var ChangeTracker = {
  notify(changeData, correlationId)        → { changeLogRow, vpsStatus, skipped }
  getOrCreateChangeLogSheet()              → Sheet
  isVpsConfigured()                        → boolean
  getVpsUrl()                              → string
  buildPayload(changeData, correlationId)  → object
  postToVps(url, payload)                  → { status, body }
}
```

## Critical rules
1. **var ONLY** — no let, no const. Enterprise convention.
2. **muteHttpExceptions: true** — MANDATORY in every UrlFetchApp.fetch(). Without it, GAS throws on 4xx/5xx and the entire handler crashes.
3. **Sheet isolation** — Write change records to `_CHANGE_LOG` only. Use `LogService.info()` for lightweight traces to `_LOGS`. Never cross-write.
4. **Stub-safe** — If VPS is not configured (`isVpsConfigured()` returns false), skip the HTTP call gracefully. Return `vpsStatus: "skipped"`.
5. **No hardcoded URLs** — Read `CHANGE_TRACKER_VPS_URL` and `CHANGE_TRACKER_ENABLED` from Script Properties.
6. **Truncate VPS response** — Limit response body to 500 chars before writing to sheet cell.
7. **Sheet name variable** — Use `var CHANGE_LOG_SHEET_NAME = '_CHANGE_LOG'`. Do NOT use `LOG_SHEET_NAME` (that's LogService's).

## _CHANGE_LOG Headers
timestamp | correlationId | author | files | changelog | commitHash | vpsUrl | vpsStatus | vpsResponse

## Script Properties used
| Property | Purpose | Example |
|----------|---------|---------|
| CHANGE_TRACKER_VPS_URL | VPS endpoint URL | https://abc123.ngrok.io/changelog |
| CHANGE_TRACKER_ENABLED | Kill switch | "true" or "false" |
| GAS_DEPLOYMENT_URL | Self-reference for payload | https://script.google.com/macros/s/.../exec |

## Recent changes
@changelog.md
