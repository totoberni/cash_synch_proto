# Task Queue — GAS Change Tracker Sandbox

> **Source of truth**: `plan.md` — this file is a derived work queue.
> **Updated**: (initial creation)

## Queue Rules
- Tasks are consumed in order unless parallelization is noted
- Each task references its plan.md phase/task ID
- Status: ⬜ QUEUED | 🔄 DELEGATED | ✅ DONE | 🚫 BLOCKED

---

## Phase 1 — Deploy Base Web App
**Assigned to**: Orchestrator (direct, no subagent)
**Depends on**: Phase 0 complete (human gate)

| ID | Task | Status | Agent | Notes |
|----|------|--------|-------|-------|
| 1.1 | Copy enterprise files (CorrelationId.gs, LogService.gs) | ⬜ QUEUED | orchestrator | Verbatim copies |
| 1.2 | Create sandbox WebApp.gs (stripped of sync handlers) | ⬜ QUEUED | orchestrator | See plan.md Task 1.2 |
| 1.3 | clasp push | ⬜ QUEUED | orchestrator | Verify N=4 files |
| 1.4 | Test base endpoints (ping, health, writeLog, getLogs) | ⬜ QUEUED | orchestrator | 4 curl tests |
| 1.5 | Git commit | ⬜ QUEUED | orchestrator | — |

## Phase 2 — Change Tracking Infrastructure
**Assigned to**: gas-tracker-agent
**Depends on**: Phase 1 complete

| ID | Task | Status | Agent | Notes |
|----|------|--------|-------|-------|
| 2.1 | Create ChangeTracker.gs | ⬜ QUEUED | gas-tracker-agent | Read tracking/CLAUDE.md first |
| 2.2 | Wire reportChange into WebApp.gs | ⬜ QUEUED | gas-tracker-agent | Depends on 2.1 |
| 2.3 | clasp push | ⬜ QUEUED | gas-tracker-agent | Verify file count +1 |
| 2.4 | Test reportChange (stub-safe + validation) | ⬜ QUEUED | gas-tracker-agent | 3 curl tests |
| 2.5 | Update changelogs + git commit | ⬜ QUEUED | gas-tracker-agent | — |

## Phase 3 — Stub Server & Trigger Scripts
**Assigned to**: tooling-agent
**Depends on**: None (can run parallel with Phase 2)

| ID | Task | Status | Agent | Notes |
|----|------|--------|-------|-------|
| 3.1 | Create stub-server/server.js | ⬜ QUEUED | tooling-agent | Zero deps, port 3456 |
| 3.2 | Create scripts/post-push-notify.sh | ⬜ QUEUED | tooling-agent | Bash, uses jq |
| 3.3 | Create scripts/post-push-notify.ps1 | ⬜ QUEUED | tooling-agent | PowerShell equivalent |
| 3.4 | Git commit | ⬜ QUEUED | tooling-agent | — |

## Phase 4 — End-to-End Testing
**Assigned to**: test-agent
**Depends on**: Phases 2+3 complete, human gates (stub server + ngrok + Script Properties)

| ID | Task | Status | Agent | Notes |
|----|------|--------|-------|-------|
| 4.1 | Test happy path (VPS connected) | ⬜ QUEUED | test-agent | Verify 3 outputs |
| 4.2 | Test stub-safe mode (VPS disconnected) | ⬜ QUEUED | test-agent | — |
| 4.3 | Test post-push script flow | ⬜ QUEUED | test-agent | — |
| 4.4 | Test error cases | ⬜ QUEUED | test-agent | — |
| 4.5 | Generate test report (docs/test-report.md) | ⬜ QUEUED | test-agent | — |
| 4.6 | Git commit | ⬜ QUEUED | test-agent | — |

## Phase 5 — Final Deployment & Documentation
**Assigned to**: Orchestrator (docs) + test-agent (re-verify)

| ID | Task | Status | Agent | Notes |
|----|------|--------|-------|-------|
| 5.1 | clasp deploy (production) | ⬜ QUEUED | orchestrator | Note deployment ID |
| 5.2 | Re-test against /exec URL | ⬜ QUEUED | test-agent | — |
| 5.3 | Write README.md | ⬜ QUEUED | orchestrator | 10 sections per plan |
| 5.4 | Final commit + tag v1.0.0 | ⬜ QUEUED | orchestrator | — |
