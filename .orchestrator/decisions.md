# Decisions Log — GAS Change Tracker Sandbox

> Architecture decisions and lessons learned. Append-only.

## Decision Format
```
### DEC-NNN: Title
**Date**: YYYY-MM-DD | **Phase**: N | **By**: orchestrator/agent-name
**Context**: Why this came up
**Decision**: What was decided
**Consequence**: What this means going forward
```

---

### DEC-001: Dedicated sheets for change tracking vs logging
**Date**: 2026-02-14 | **Phase**: Design | **By**: plan author
**Context**: ChangeTracker needs to write records. LogService already uses `_LOGS`.
**Decision**: Use `_CHANGE_LOG` (separate sheet) for change records. Never write to `_LOGS` from ChangeTracker except lightweight trace lines via LogService.info().
**Consequence**: Variable name `CHANGE_LOG_SHEET_NAME` must differ from LogService's `LOG_SHEET_NAME`. No namespace collision.

### DEC-002: var-only convention for GAS code
**Date**: 2026-02-14 | **Phase**: Design | **By**: plan author
**Context**: Enterprise codebase uses `var` exclusively. Mixing `let`/`const` would create inconsistency when migrating.
**Decision**: All GAS code uses `var`. No `let`, no `const`.
**Consequence**: Agents must be explicitly told. Add to module CLAUDE.md files and root conventions.

### DEC-003: muteHttpExceptions is mandatory
**Date**: 2026-02-14 | **Phase**: Design | **By**: plan author
**Context**: Without `muteHttpExceptions: true`, GAS throws on 4xx/5xx from VPS, crashing the entire handler.
**Decision**: Every UrlFetchApp.fetch() call must include `muteHttpExceptions: true`.
**Consequence**: This is the #1 GAS mistake. Highlight in tracking/CLAUDE.md and agent prompts.
