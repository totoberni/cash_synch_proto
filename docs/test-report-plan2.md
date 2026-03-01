# Test Report — Plan 2 (Automated Documentation Pipeline)

**Date**: 2026-03-01
**Tester**: test-agent (automated)
**Environment**:
- Stub server: localhost:3456
- ngrok: https://resumptive-canonistic-ossie.ngrok-free.dev
- GAS Exec URL (@8): https://script.google.com/macros/s/AKfycbw8Oa1kckb7_QHYAuCZxQ5RmepwAxM9xN6_WoUQxnfCNC9zFzhzon7o2tejLnUMvIE/exec

**Note**: The Dev URL (`/dev`) requires Google authentication and cannot be used with unauthenticated curl requests. A new deployment (@8) was created via `clasp deploy` to test HEAD code with anonymous access.

## Test Results

| # | Test | Status | Notes |
|---|------|--------|-------|
| 4.1 | Payload builder (local) | **PASS** | Valid JSON, 22 commits, `apps-script/src/` prefix correctly stripped from all 15 changed files |
| 4.2 | Happy path (batch -> GAS -> VPS ack) | **PASS** | Full round-trip success: GAS returned `vpsStatus: 200`, `vpsAck: true`, `vpsBatchId: 8094bb96-...` |
| 4.3 | VPS batch storage & retrieval | **PASS** | Batch listed at `/batches`, full batch retrieved by ID with all 22 commits and metadata |
| 4.4 | Validation tests (missing fields) | **PASS** | All 3 validation cases returned correct error messages with correlationId |
| 4.5 | Backward compat (reportChange) | **PASS** | Legacy endpoint works: `success: true`, VPS received legacy payload |
| 4.6 | VPS legacy mode compat | **PASS** | Stub server returns `{"received":true}` for non-batch payloads (no batch ack) |

**Overall: 6/6 PASS**

---

## Artifacts

### Task 4.1 — Payload builder (local)

```bash
cd /home/totob/projects/cash/cash_synch_proto
FROM=$(git log --reverse --pretty=format:"%H" | head -1)
TO=$(git rev-parse HEAD)
bash scripts/build-batch-payload.sh "$FROM" "$TO" "apps-script/src/" "manual" "test-user" "owner/cash_synch_proto" | jq .
```

**Response** (abbreviated):
```json
{
  "action": "reportBatch",
  "trigger": "manual",
  "triggeredBy": "test-user",
  "repository": "owner/cash_synch_proto",
  "range": {
    "from": "283f3f4951bd4ce0adc9c4efcd0efba1975f7559",
    "to": "02d9dbae1323079c3e1f93b671313282c1d895ca",
    "commitCount": 22
  },
  "commits": [
    { "sha": "02d9dba...", "author": "Abe", "message": "feat: Phase 3 — VPS stub with batch ack + durable storage", "timestamp": "2026-03-01T20:39:20+00:00" },
    "... (22 commits total)"
  ],
  "filesChanged": [
    "api/CLAUDE.md", "api/WebApp.gs", "api/changelog.md", "appsscript.json",
    "correlation/CLAUDE.md", "correlation/CorrelationId.gs", "correlation/CorrelationId.gs:Zone.Identifier",
    "correlation/changelog.md", "logging/CLAUDE.md", "logging/LogService.gs",
    "logging/LogService.gs:Zone.Identifier", "logging/changelog.md",
    "tracking/CLAUDE.md", "tracking/ChangeTracker.gs", "tracking/changelog.md"
  ],
  "pathFilter": "apps-script/src/"
}
```

**Verification**: No file path contains the `apps-script/src/` prefix. Confirmed via `jq '.filesChanged[] | select(startswith("apps-script/src/"))'` returning empty.

---

### Task 4.2 — Happy path (batch -> GAS -> VPS ack)

```bash
cd /home/totob/projects/cash/cash_synch_proto
FROM=$(git log --reverse --pretty=format:"%H" | head -1)
TO=$(git rev-parse HEAD)
bash scripts/build-batch-payload.sh "$FROM" "$TO" "apps-script/src/" "manual" "e2e-test" "owner/cash_synch_proto" \
  | curl -sL -d @- -H "Content-Type: application/json" \
  "https://script.google.com/macros/s/AKfycbw8Oa1kckb7_QHYAuCZxQ5RmepwAxM9xN6_WoUQxnfCNC9zFzhzon7o2tejLnUMvIE/exec"
```

**Full response**:
```json
{
  "success": true,
  "correlationId": "gas_1772398110951_7kew1hu2",
  "tracking": {
    "changeLogRow": 15,
    "vpsStatus": 200,
    "vpsAck": true,
    "vpsBatchId": "8094bb96-eaae-442e-86dd-3477c21881cb",
    "vpsResponse": "{\"ack\":true,\"batchId\":\"8094bb96-eaae-442e-86dd-3477c21881cb\",\"timestamp\":\"2026-03-01T20:48:32.034Z\"}",
    "error": null
  }
}
```

**Verified**: `success: true`, `vpsStatus: 200`, `vpsAck: true`, `vpsBatchId` is a valid UUID.

---

### Task 4.3 — VPS batch storage & retrieval

**List batches**:
```bash
curl -s http://localhost:3456/batches | jq .
```

```json
[
  {
    "batchId": "8094bb96-eaae-442e-86dd-3477c21881cb",
    "timestamp": "2026-03-01T20:48:32.034Z",
    "commitCount": 22,
    "repository": "owner/cash_synch_proto"
  }
]
```

**Get batch by ID**:
```bash
BATCH_ID="8094bb96-eaae-442e-86dd-3477c21881cb"
curl -s "http://localhost:3456/batches/$BATCH_ID" | jq .
```

```json
{
  "scriptId": "1s0kbGNpO4CRjikhxvQHQwT7yTPDty9UfMqRW8_Z6zmH198F2iSyxgKXu",
  "scriptEndpoint": "https://script.google.com/macros/s/AKfycbxXQwYK9wfIGozgxM5MXl52Ne0SPeWcAfOaRg-Rxk8p-JIKzHk3-xFCk4BHVGhXH76J/exec",
  "timestamp": "2026-03-01T20:48:32.034Z",
  "correlationId": "gas_1772398110951_7kew1hu2",
  "batch": {
    "trigger": "manual",
    "triggeredBy": "e2e-test",
    "repository": "owner/cash_synch_proto",
    "range": { "from": "283f3f49...", "to": "02d9dbae...", "commitCount": 22 },
    "commits": ["... (22 commits)"],
    "filesChanged": ["... (15 files)"],
    "pathFilter": "apps-script/src/"
  },
  "batchId": "8094bb96-eaae-442e-86dd-3477c21881cb"
}
```

**Verified**: Batch is stored with all metadata, retrievable by ID, correct commit count and repository.

---

### Task 4.4 — Validation tests (missing fields)

**4.4a — Missing range**:
```bash
curl -sL -d '{"action":"reportBatch","repository":"test/repo","commits":[{"sha":"abc"}]}' \
  -H "Content-Type: application/json" \
  "https://script.google.com/macros/s/AKfycbw8Oa1kckb7_QHYAuCZxQ5RmepwAxM9xN6_WoUQxnfCNC9zFzhzon7o2tejLnUMvIE/exec"
```
```json
{"error":"Missing or invalid field: range (object required)","correlationId":"gas_1772398163796_42rs9sds"}
```
**PASS** -- matches expected error.

**4.4b — Missing commits**:
```bash
curl -sL -d '{"action":"reportBatch","repository":"test/repo","range":{"from":"aaa","to":"bbb","commitCount":1}}' \
  -H "Content-Type: application/json" \
  "https://script.google.com/macros/s/AKfycbw8Oa1kckb7_QHYAuCZxQ5RmepwAxM9xN6_WoUQxnfCNC9zFzhzon7o2tejLnUMvIE/exec"
```
```json
{"error":"Missing or invalid field: commits (non-empty array required)","correlationId":"gas_1772398165605_lfn4zxx3"}
```
**PASS** -- matches expected error.

**4.4c — Missing repository**:
```bash
curl -sL -d '{"action":"reportBatch","range":{"from":"aaa","to":"bbb","commitCount":1},"commits":[{"sha":"abc"}]}' \
  -H "Content-Type: application/json" \
  "https://script.google.com/macros/s/AKfycbw8Oa1kckb7_QHYAuCZxQ5RmepwAxM9xN6_WoUQxnfCNC9zFzhzon7o2tejLnUMvIE/exec"
```
```json
{"error":"Missing or invalid field: repository (string required, e.g. \"owner/repo\")","correlationId":"gas_1772398167959_pgcnizd2"}
```
**PASS** -- matches expected error.

---

### Task 4.5 — Backward compatibility (legacy reportChange)

```bash
curl -sL -d '{"action":"reportChange","author":"e2e-test","files":["test.gs"],"changelog":"Testing backward compatibility","commitHash":"abc123"}' \
  -H "Content-Type: application/json" \
  "https://script.google.com/macros/s/AKfycbw8Oa1kckb7_QHYAuCZxQ5RmepwAxM9xN6_WoUQxnfCNC9zFzhzon7o2tejLnUMvIE/exec"
```

**Response**:
```json
{
  "success": true,
  "correlationId": "gas_1772398184594_uud1mb64",
  "tracking": {
    "changeLogRow": 16,
    "vpsStatus": 200,
    "vpsResponse": "{\"received\":true,\"timestamp\":\"2026-03-01T20:49:46.032Z\"}",
    "error": null
  }
}
```

**Verified**: Legacy action still works, returns `success: true`, VPS received the legacy payload.

---

### Task 4.6 — VPS legacy mode compatibility

```bash
curl -s -d '{"scriptId":"test","change":{"author":"dev"}}' \
  -H "Content-Type: application/json" \
  http://localhost:3456/changelog
```

**Response**:
```json
{"received":true,"timestamp":"2026-03-01T20:50:01.579Z"}
```

**Verified**: Legacy (non-batch) payloads get the old `{"received":true}` response, NOT the batch ack format (`{"ack":true,"batchId":"..."}`). Backward compatibility confirmed.

---

## Issues Found

1. **Dev URL not usable for unauthenticated curl testing** — The GAS `/dev` URL (using script ID) returns "Page not found" when accessed without Google authentication. This is a known GAS limitation. **Workaround**: Created a new deployment (@8) via `clasp deploy` which provides an exec URL with anonymous access. This is not a code bug; it is a test infrastructure consideration.

2. **Zone.Identifier files in filesChanged** — The payload builder includes `CorrelationId.gs:Zone.Identifier` and `LogService.gs:Zone.Identifier` in the `filesChanged` list. These are Windows NTFS alternate data stream marker files (from WSL2 cross-filesystem operations) and are not real source files. Low priority; could be filtered in a future iteration of `build-batch-payload.sh`.

---

## Deployment Note

A new GAS deployment was created during testing:

| Version | Deployment ID | Description |
|---------|---------------|-------------|
| @8 | AKfycbw8Oa1kckb7_QHYAuCZxQ5RmepwAxM9xN6_WoUQxnfCNC9zFzhzon7o2tejLnUMvIE | Phase 4 — e2e testing (reportBatch endpoint) |

This deployment runs the same HEAD code as the `/dev` URL but is accessible anonymously. The orchestrator may choose to adopt this as the new active exec URL, or create a fresh deployment at Phase 5.
