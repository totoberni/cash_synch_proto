# Changelog — scripts

<!-- AUTO-MANAGED: Entries appended by PostToolUse hook -->

## 2026-02-15 — Phase 3 Implementation (tooling-agent)

### Added
- `post-push-notify.sh` — Bash trigger script for post-push change notifications
  - Reads GAS_WEBAPP_URL from environment (fallback to placeholder)
  - Gathers git metadata: commit message, short hash, author name, changed files in apps-script/src/
  - Constructs JSON payload with `action: "reportChange"`
  - POSTs via curl using `-d` flag (not `-X POST`) to handle GAS 302 redirects correctly
  - Pretty-printed output with color codes
  - Gracefully handles missing git (fallback values)
  - Uses `jq` for JSON array construction (documented as prerequisite)
  - Made executable via chmod +x

- `post-push-notify.ps1` — PowerShell equivalent for Windows
  - Same functionality as bash script
  - Reads `$env:GAS_WEBAPP_URL` with fallback
  - Uses `Invoke-RestMethod` for HTTP POST
  - Uses `ConvertTo-Json` for payload construction (no external dependencies)
  - Gracefully handles missing git
  - Works on Windows without additional tools
