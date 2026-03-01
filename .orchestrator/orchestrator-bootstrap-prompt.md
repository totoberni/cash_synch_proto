# Orchestrator Bootstrap Prompt — Phase 5.5 Handshake Tests

You are the orchestrator for the GAS Change Tracker project. Your task is to complete **Phase 5.5** of plan2 — specifically the handshake verification tests (Task 5.5.3).

## Context

Phases 1-5 of plan2 are COMPLETE. Code fixes for Task 5.5.1 (API hygiene) have been applied locally:
- `ChangeTracker.gs`: Added `statusCode: 0|1`, removed `error: null` on success, removed `vpsResponse` leak
- `build-batch-payload.sh`: Added `--reverse` for oldest-first commit ordering, added Zone.Identifier filter

**The human must complete two steps before you can run tests:**
1. Update `GAS_DEPLOYMENT_URL` Script Property in GAS IDE to the @9 exec URL:
   `https://script.google.com/macros/s/AKfycbwkujDPilxb1TdmVOgS0n7rxFFX2UFdfcbtQb2betQGFX-69dt43Tln634P4srzktFF/exec`
2. Push and deploy: `cd apps-script && clasp push -f && clasp deploy -i AKfycbwkujDPilxb1TdmVOgS0n7rxFFX2UFdfcbtQb2betQGFX-69dt43Tln634P4srzktFF -d "v2.0.1 — API hygiene + handshake hardening"`

**Ask the human to confirm these steps are done before proceeding.**

## Your tasks

### 1. Verify human prerequisites
Confirm with the human:
- `GAS_DEPLOYMENT_URL` updated in Script Properties
- `clasp push -f` + `clasp deploy -i` completed
- Stub server running (`curl -s http://localhost:3456/health | jq .`)
- ngrok active (check `curl -s http://localhost:4040/api/tunnels | jq '.tunnels[0].public_url'`)

### 2. Delete old test report
```bash
rm docs/test-report-plan2.md
```

### 3. Delegate handshake tests to test-agent
Spawn the test-agent with this brief:

> Read `.orchestrator/plan2.md` Phase 5.5, Task 5.5.3 for the full test specification.
> Run all 8 tests (H1-H8) against the live GAS deployment.
> For tests H3 and H4, you will need to temporarily replace the stub server with one-liner Node scripts (commands provided in plan2.md). Restart the real stub server after each.
> Write results to `docs/test-report-plan2-v3.md` following the template in plan2.md.
> Source `.env` for the `GAS_WEBAPP_URL` variable.
> Use `curl -sL -d ... -H "Content-Type: application/json" "$GAS_WEBAPP_URL"` for all POST requests (never `-X POST`).
> Check `docs/gotchas.md` before debugging any failures.

### 4. Verify results
After test-agent completes:
- Read `docs/test-report-plan2-v3.md`
- Verify all 8 tests PASS
- If any FAIL: diagnose, fix, re-test (check `docs/gotchas.md` first)

### 5. Commit
```bash
git add docs/test-report-plan2-v3.md apps-script/src/tracking/ChangeTracker.gs scripts/build-batch-payload.sh apps-script/src/tracking/changelog.md
git commit -m "fix: Phase 5.5 — API hygiene + handshake verification (8/8 tests)"
```

### 6. Update state
- Update `.orchestrator/state.md` with Phase 5.5 completion
- Report results to human: test pass/fail summary, any issues, readiness for Phase 6

## Files to read first
1. `docs/gotchas.md` — known issues
2. `.orchestrator/plan2.md` — Phase 5.5 section (Task 5.5.3 has full test specs)
3. `.orchestrator/state.md` — current state
4. `CLAUDE.md` — project conventions

## Key rules
- Use `var` only in .gs files (no let/const)
- curl POST: use `-sL -d` not `-X POST` (302 redirect gotcha)
- All test reports go in `docs/` — NEVER in module subdirectories
- Do NOT `git push` — human decides when to push
- Check `docs/gotchas.md` before debugging any failure
