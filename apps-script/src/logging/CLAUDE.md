# Logging Module — CLAUDE.md

## Files
- `LogService.gs` — Singleton service for structured logging to `_LOGS` sheet.

## Status
**READ-ONLY** — This is a verbatim copy from the enterprise codebase.
Do NOT modify this file. If the enterprise version changes, replace the entire file.

## API
```
var LogService = {
  info(category, message, data)    → void
  warn(category, message, data)    → void
  error(category, message, data)   → void
  getOrCreateLogSheet()            → Sheet  // Auto-creates _LOGS if missing
}
```

## Sheet: _LOGS
Headers: timestamp | level | category | message | data | correlationId

## Recent changes
@changelog.md
