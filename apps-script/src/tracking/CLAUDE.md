# Tracking Module — CLAUDE.md

## Purpose
Forwards code change notifications to an external VPS via HTTP POST.
Writes a full audit record to the `_CHANGE_LOG` sheet (dedicated, separate from `_LOGS`).

## Key Patterns
- Follows LogService singleton pattern: `var ChangeTracker = { ... };`
- Stub-safe: if VPS URL not in Script Properties, skip POST gracefully (return {skipped: true})
- Uses UrlFetchApp.fetch() for outbound HTTP (same as enterprise webhook senders)
- Auto-creates `_CHANGE_LOG` sheet on first use (same pattern as LogService.getOrCreateLogSheet)

## _CHANGE_LOG Sheet Schema
timestamp | correlationId | author | files | changelog | commitHash | vpsUrl | vpsStatus | vpsResponse

## Script Properties Read
- CHANGE_TRACKER_VPS_URL — target endpoint (empty = skip)
- CHANGE_TRACKER_ENABLED — "true" or "false"
- GAS_DEPLOYMENT_URL — self-reference URL sent in payload

## Recent Changes
@changelog.md
