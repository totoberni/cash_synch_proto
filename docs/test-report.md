# Test Report — Phase 4 End-to-End Testing

**Date**: 2026-02-15
**Tester**: orchestrator + test-agent
**GAS Deployment**: v6 (/exec URL)

---

## Test Results

| Test ID | Test Name | Status | Notes |
|---------|-----------|--------|-------|
| 4.1 | Happy Path (VPS Connected) | PASS | vpsStatus: 200, stub server received payload |
| 4.2 | Stub-Safe Mode (VPS Disabled) | MANUAL | Requires human to toggle Script Properties |
| 4.3 | Post-Push Script Flow | PASS | Script gathers git metadata, POSTs to GAS, VPS receives |
| 4.4 | Error Handling (VPS Down) | MANUAL | Requires human to stop stub server |

---

## Test 4.1 — Happy Path (VPS Connected)

**Command**:
```bash
curl -sL -H "Content-Type: application/json" -d '{
  "action": "reportChange",
  "author": "e2e-test",
  "files": ["WebApp.gs", "ChangeTracker.gs"],
  "changelog": "End-to-end test with VPS connected",
  "commitHash": "e2e1234"
}' "https://script.google.com/macros/s/AKfycbxXQwYK9wfIGozgxM5MXl52Ne0SPeWcAfOaRg-Rxk8p-JIKzHk3-xFCk4BHVGhXH76J/exec"
```

**Response**:
```json
{
  "success": true,
  "correlationId": "gas_1771156931694_kme6o7s3",
  "tracking": {
    "changeLogRow": 6,
    "vpsStatus": 200,
    "vpsResponse": "{\"received\":true,\"timestamp\":\"2026-02-15T12:02:12.598Z\"}",
    "error": null
  }
}
```

**Verified**: curl response has vpsStatus 200, stub server printed payload, `_CHANGE_LOG` sheet has row.

---

## Test 4.2 — Stub-Safe Mode (VPS Disabled)

**Status**: MANUAL — requires human to set `CHANGE_TRACKER_ENABLED=false` in Script Properties.

Previously verified during Phase 2 testing (pre-VPS config):
```json
{"success":true,"correlationId":"gas_1771155398611_dcq8hr07","tracking":{"changeLogRow":2,"vpsStatus":"skipped","vpsResponse":null,"error":null}}
```

---

## Test 4.3 — Post-Push Script Flow

**Command**:
```bash
GAS_WEBAPP_URL="https://script.google.com/macros/s/AKfycbxXQwYK9wfIGozgxM5MXl52Ne0SPeWcAfOaRg-Rxk8p-JIKzHk3-xFCk4BHVGhXH76J/exec" \
  bash scripts/post-push-notify.sh
```

**Response**:
```json
{
  "success": true,
  "correlationId": "gas_1771157084905_v9yb32qy",
  "tracking": {
    "changeLogRow": 7,
    "vpsStatus": 200,
    "vpsResponse": "{\"received\":true,\"timestamp\":\"2026-02-15T12:04:46.206Z\"}",
    "error": null
  }
}
```

**Note**: Fixed `set -euo pipefail` + `grep` exit code bug in script during testing (grep returns 1 when no matches, killing the script).

---

## Test 4.4 — Error Handling (VPS Down)

**Status**: MANUAL — requires human to stop stub server, keep ngrok running.

**Expected**: Response returns (no crash), `vpsStatus` shows error code (e.g., 502), `_CHANGE_LOG` has error row.

---

## Issues Encountered & Resolved

| Issue | Resolution |
|-------|------------|
| GAS exec URL returns 302 to sign-in | Created new deployment with anonymous access via IDE |
| curl `-X POST` returns 405 on GAS redirect | Use `-d` flag instead (implies POST, follows 302 as GET) |
| UrlFetchApp authorization not granted | Added temp `testUrlFetch()` function in IDE, ran it to trigger OAuth |
| post-push-notify.sh fails with pipefail | Wrapped grep in `{ grep ... \|\| true; }` to handle no-match exit code |

---

## Artifacts

| Artifact | Value |
|----------|-------|
| Script ID | `1s0kbGNpO4CRjikhxvQHQwT7yTPDty9UfMqRW8_Z6zmH198F2iSyxgKXu` |
| Deployment ID | `AKfycbxXQwYK9wfIGozgxM5MXl52Ne0SPeWcAfOaRg-Rxk8p-JIKzHk3-xFCk4BHVGhXH76J` |
| Exec URL | `https://script.google.com/macros/s/AKfycbxXQwYK9wfIGozgxM5MXl52Ne0SPeWcAfOaRg-Rxk8p-JIKzHk3-xFCk4BHVGhXH76J/exec` |
| Stub Server | `http://localhost:3456` |
| Google Sheet | CashProto (`14dcXi9ug-wkdAJzN5gjaNyf6TroUNTnnyAurGfG8EP0`) |
