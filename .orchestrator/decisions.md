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

### DEC-004: Stable deployment URL via in-place updates
**Date**: 2026-02-16 | **Phase**: Plan 2, Phase 0 | **By**: orchestrator
**Context**: Every `clasp deploy` creates a new /exec URL, forcing manual updates to `.env`, Script Properties, and GitHub secrets. This breaks automation and is error-prone.
**Decision**: Use `clasp deploy -i <DEPLOYMENT_ID>` (in-place update) to keep the /exec URL stable. Store `GAS_DEPLOYMENT_ID` in `.env`. The `post-push-notify.sh` script auto-pushes and deploys before notifying when `GAS_DEPLOYMENT_ID` is configured.
**Consequence**: After initial setup, the /exec URL never changes. `.env` and Script Properties only need configuration once. The trigger script becomes a one-command "push + deploy + notify" flow. In enterprise, the VPS URL is also stable, making the entire pipeline fully automated.

### DEC-003: muteHttpExceptions is mandatory
**Date**: 2026-02-14 | **Phase**: Design | **By**: plan author
**Context**: Without `muteHttpExceptions: true`, GAS throws on 4xx/5xx from VPS, crashing the entire handler.
**Decision**: Every UrlFetchApp.fetch() call must include `muteHttpExceptions: true`.
**Consequence**: This is the #1 GAS mistake. Highlight in tracking/CLAUDE.md and agent prompts.
