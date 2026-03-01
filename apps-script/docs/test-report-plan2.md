# Test Report — Plan 2 (Automated Documentation Pipeline)

**Date**: 2026-03-01
**Tester**: test-agent (automated)
**Result**: 6/6 PASS

## Environment

- Stub server: localhost:3456
- ngrok: https://resumptive-canonistic-ossie.ngrok-free.dev
- GAS Dev URL: https://script.google.com/macros/s/1s0kbGNpO4CRjikhxvQHQwT7yTPDty9UfMqRW8_Z6zmH198F2iSyxgKXu/dev
- GAS Exec URL: https://script.google.com/macros/s/AKfycbyt-ZCjQH5XA6IM_H90IOuLqXleUMC0sBTuv5Lc12-72EQX72J9osA-XWg3f5JRvHDn/exec
- GAS Deployment @8 (created during testing for anonymous access)

## Test Results

| # | Test | Status | Notes |
|---|------|--------|-------|
| 4.1 | Payload builder (local) | PASS | Valid JSON, 22 commits, apps-script/src/ prefix correctly stripped from all 15 files |
| 4.2 | Happy path (batch -> GAS -> VPS) | PASS | Full round-trip: vpsStatus: 200, vpsAck: true, vpsBatchId returned |
| 4.3 | VPS batch storage & retrieval | PASS | Batch listed at /batches, full batch retrievable by ID with all metadata |
| 4.4 | Validation tests (3 cases) | PASS | Missing range, missing commits, missing repository - all returned correct error messages |
| 4.5 | Backward compat (reportChange) | PASS | Legacy endpoint still works: success: true |
| 4.6 | VPS legacy mode compat | PASS | Non-batch payloads get received:true, not batch ack format |

## Test Commands

### 4.1 - Payload builder
```bash
FROM=$(git log --reverse --pretty=format:"%H" | head -1)
TO=$(git rev-parse HEAD)
bash scripts/build-batch-payload.sh "$FROM" "$TO" "apps-script/src/" "manual" "test-user" "owner/cash_synch_proto" | jq .
```

### 4.2 - Happy path (batch -> GAS -> VPS ack)
```bash
bash scripts/build-batch-payload.sh "$FROM" "$TO" "apps-script/src/" "manual" "e2e-test" "owner/cash_synch_proto" \
  | curl -sL -d @- -H "Content-Type: application/json" "$GAS_WEBAPP_URL" | jq .
```
Response: `{ success: true, tracking: { vpsStatus: 200, vpsAck: true, vpsBatchId: "..." } }`

### 4.3 - VPS batch storage
```bash
curl -s http://localhost:3456/batches | jq .
curl -s http://localhost:3456/batches/$BATCH_ID | jq .
```

### 4.4 - Validation tests
```bash
# Missing range -> error
curl -sL -d '{"action":"reportBatch","repository":"test/repo","commits":[{"sha":"abc"}]}' \
  -H "Content-Type: application/json" "$GAS_WEBAPP_URL" | jq .

# Missing commits -> error
curl -sL -d '{"action":"reportBatch","repository":"test/repo","range":{"from":"a","to":"b","commitCount":1}}' \
  -H "Content-Type: application/json" "$GAS_WEBAPP_URL" | jq .

# Missing repository -> error
curl -sL -d '{"action":"reportBatch","range":{"from":"a","to":"b","commitCount":1},"commits":[{"sha":"abc"}]}' \
  -H "Content-Type: application/json" "$GAS_WEBAPP_URL" | jq .
```

### 4.5 - Backward compatibility (reportChange)
```bash
curl -sL -d '{"action":"reportChange","author":"e2e-test","files":["test.gs"],"changelog":"Testing backward compatibility","commitHash":"abc123"}' \
  -H "Content-Type: application/json" "$GAS_WEBAPP_URL" | jq .
```

### 4.6 - VPS legacy mode
```bash
curl -s -d '{"scriptId":"test","change":{"author":"dev"}}' \
  -H "Content-Type: application/json" http://localhost:3456/changelog | jq .
```

## Issues Found (Non-Blocking)

1. **Dev URL requires Google auth**: GAS /dev URL cannot be used with unauthenticated curl. Created deployment @8 for anonymous testing. GAS platform limitation, not a code bug.
2. **Zone.Identifier files in filesChanged**: WSL2/NTFS artifacts appear in payload. Cosmetic - could add a filter to build-batch-payload.sh in the future.
