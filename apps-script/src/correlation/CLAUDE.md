# Correlation Module — CLAUDE.md

## Files
- `CorrelationId.gs` — Generates unique correlation IDs for request tracing.

## Status
**READ-ONLY** — This is a verbatim copy from the enterprise codebase.
Do NOT modify this file. If the enterprise version changes, replace the entire file.

## API
```
var CorrelationId = {
  generate()  → string  // Returns "gas_" + Utilities.getUuid()
}
```

## Recent changes
@changelog.md
