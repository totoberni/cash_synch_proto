# Orchestrator State — GAS Change Tracker Sandbox

> **Updated**: 2026-02-16T11:10Z
> **Active Plan**: plan2.md (Automated Documentation Pipeline)
> **Session**: Phase 0 complete — README updated, plan2 trimmed. Awaiting user for next phases.

---

## Plan 1 Status (plan.md)
All phases complete. Tagged v1.0.0. See commit history below.

## Plan 2 Status (plan2.md)

### Current Phase
Phase: 0 (COMPLETE)
Next: Phases 1, 2, 3 (all independent — can launch in parallel)

### Phase Tracker
| Phase | Description | Status | Blocker | Commit |
|-------|-------------|--------|---------|--------|
| 0 | Sandbox hardening | ✅ COMPLETE | — | 36b5e53 |
| 1 | GAS batch endpoint (reportBatch + notifyBatch) | ⬜ NOT STARTED | — | — |
| 2 | GitHub Actions workflow (doc-batch.yml) | ⬜ NOT STARTED | Human: add GAS_WEBAPP_URL secret | — |
| 3 | VPS stub evolution (ack + batch storage) | ⬜ NOT STARTED | — | — |
| 4 | End-to-end integration testing | ⬜ NOT STARTED | Blocked by 1+2+3 | — |
| 5 | Finalization + tag | ⬜ NOT STARTED | Blocked by 4 | — |

### Phase 0 Deliverables
- `.env.example` — config template (committed)
- `.env` — local config with sandbox values (gitignored)
- `scripts/dev-start.sh` — single-command stub+ngrok startup
- `scripts/post-push-notify.sh` — now auto-sources `.env`
- `apps-script/src/api/WebApp.gs` — stray test line removed
- `clasp push -f` — succeeded (5 files)
- Agent definitions: `gas-batch-agent.md` created, `tooling-agent.md` updated

### Human Gates Pending
- **Phase 2, Task 2.3**: Add `GAS_WEBAPP_URL` as GitHub Actions secret
- **Phase 4**: Run `dev-start.sh`, set Script Properties, `clasp push -f`
- **Phase 5, Task 5.3**: Update GitHub secret if deployment URL changes

---

## Active Workers
None — awaiting user signal to launch Phases 1/2/3.

## Agent Roster (plan2)
| Agent | Scope | Status |
|-------|-------|--------|
| gas-batch-agent | WebApp.gs, ChangeTracker.gs | Created (.claude/agents/gas-batch-agent.md) |
| actions-agent | .github/workflows/, build-batch-payload.sh | Not yet created |
| vps-stub-agent | stub-server/ | Not yet created |
| tooling-agent | scripts/, .env.example | Updated for plan2 |
| test-agent | docs/ test reports | Unchanged from plan1 |

---

## Project Identifiers
- Script ID: 1s0kbGNpO4CRjikhxvQHQwT7yTPDty9UfMqRW8_Z6zmH198F2iSyxgKXu
- Google Sheet: CashProto (14dcXi9ug-wkdAJzN5gjaNyf6TroUNTnnyAurGfG8EP0)
- Dev URL: `https://script.google.com/macros/s/1s0kbGNpO4CRjikhxvQHQwT7yTPDty9UfMqRW8_Z6zmH198F2iSyxgKXu/dev`

### Deployments
| Version | Deployment ID | Description |
|---------|---------------|-------------|
| @4 | AKfycbw5S-VXJg6DB1QiYBDCOIOQEcD3neIltI_lMa8PLPNOBSiwo2-B4Tx6vmMNIPS38hPa | Phase 1 — base web app |
| @6 | AKfycbxXQwYK9wfIGozgxM5MXl52Ne0SPeWcAfOaRg-Rxk8p-JIKzHk3-xFCk4BHVGhXH76J | Phase 2 — ChangeTracker |
| @7 | AKfycbyt-ZCjQH5XA6IM_H90IOuLqXleUMC0sBTuv5Lc12-72EQX72J9osA-XWg3f5JRvHDn | v1.0.0 — final (plan1) |

### Active Exec URL
`https://script.google.com/macros/s/AKfycbyt-ZCjQH5XA6IM_H90IOuLqXleUMC0sBTuv5Lc12-72EQX72J9osA-XWg3f5JRvHDn/exec`

## Curl Pattern (IMPORTANT)
For POST: `curl -sL -d '...' -H "Content-Type: application/json" URL`
Do NOT use `-X POST` — it breaks on GAS 302 redirect. See gotchas.md.

## Decisions Made
- (plan1) Changed appsscript.json access to ANYONE_ANONYMOUS
- (plan1) curl POST must use `-d` not `-X POST` for GAS 302 redirect compatibility
- (plan1) UrlFetchApp needs separate OAuth authorization via IDE Run
- (plan2) plan2.md is READ-ONLY — state tracked here in .orchestrator/state.md
- (plan2) gas-batch-agent replaces gas-tracker-agent for plan2 GAS work
- (plan2) plan2.md Phase 0 section trimmed after completion (full spec preserved in git history)
- (plan2) README.md updated with detailed e2e testing workflow and URL update matrix

## Gotchas Encountered
See gotchas.md for full list.

## Commit History
| Commit | Description | Plan |
|--------|-------------|------|
| 49afb3c | Phase 0: repo scaffold | 1 |
| 8ea1392 | Phases 1+2: base web app + ChangeTracker | 1 |
| ce6774a | Phase 3: stub server + trigger scripts | 1 |
| 18401ee | Phase 4: e2e verification | 1 |
| 352bfdf | Phase 5: v1.0.0 production deployment + README | 1 |
| 509b1a3 | New plan (plan2.md added) | 2 |
| 36b5e53 | Phase 0: dev environment hardening + cleanup | 2 |
