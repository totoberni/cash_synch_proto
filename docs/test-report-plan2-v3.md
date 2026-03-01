# Test Report — Plan 2 Phase 5.5 (Handshake Verification)

**Date**: 2026-03-01
**Tester**: test-agent
**Phase**: 5.5 — Pre-Phase 6 handshake verification

## Summary
8/8 PASS | 0/8 FAIL

## Results

| Test | Name | Status | Notes |
|------|------|--------|-------|
| H1 | Happy path + status code | PASS | statusCode=0, vpsAck=true, vpsBatchId=UUID, no error/vpsResponse fields, commits oldest-first, no Zone.Identifier, stub stored batch |
| H2 | VPS down (502) | PASS | statusCode=0, vpsAck=false, vpsStatus=502, no crash — GAS handled gracefully |
| H3 | VPS non-JSON response | PASS | statusCode=0, vpsAck=false, vpsStatus=200, vpsBatchId=null — JSON parse failure handled |
| H4 | VPS explicit ack:false | PASS | statusCode=0, vpsAck=false, vpsBatchId=null — explicit rejection handled correctly |
| H5 | Stub-safe mode | PASS | statusCode=0, vpsStatus="skipped", vpsAck=false, vpsBatchId=null — VPS call correctly skipped when CHANGE_TRACKER_ENABLED=false |
| H6 | Backward compatibility | PASS | statusCode=0, success=true — plan1 reportChange endpoint still works |
| H7 | Commit ordering | PASS | First commit: "Infrastructure done, awaiting autit" (2026-02-14), last: "docs: Phase 5..." (2026-03-01) — oldest-first confirmed |
| H8 | Zone.Identifier filter | PASS | Empty array — no Zone.Identifier artifacts in filesChanged |

## Artifacts
- Deployment: @9 (v2.0.1)
- Exec URL: https://script.google.com/macros/s/AKfycbwkujDPilxb1TdmVOgS0n7rxFFX2UFdfcbtQb2betQGFX-69dt43Tln634P4srzktFF/exec
- Stub port: 3456
- ngrok URL: https://resumptive-canonistic-ossie.ngrok-free.dev

## Curl Commands and Responses

### H1 — Happy path with status code verification

**Command (payload build + POST)**:
```bash
source .env
FROM=$(git log --reverse --pretty=format:"%H" | head -1)
TO=$(git rev-parse HEAD)
bash scripts/build-batch-payload.sh "$FROM" "$TO" "apps-script/src/" "manual" "handshake-test" "owner/cash_synch_proto" \
  | curl -sL -d @- -H "Content-Type: application/json" "$GAS_WEBAPP_URL" | jq .
```

**Response**:
```json
{
  "success": true,
  "correlationId": "gas_1772403083037_o0c2inq9",
  "tracking": {
    "statusCode": 0,
    "changeLogRow": 21,
    "vpsStatus": 200,
    "vpsAck": true,
    "vpsBatchId": "a9ae3066-2330-45e0-bdc5-6995748b0ade"
  }
}
```

**Commit ordering check**: `[first.message, last.message]` = `["Infrastructure done, awaiting autit", "docs: Phase 5 — v2.0.0 deployment, baseline tag, and project housekeeping"]`

**Zone.Identifier check**: `[]` (empty — no artifacts)

**Stub batch listing (last entry)**:
```json
{
  "batchId": "a9ae3066-2330-45e0-bdc5-6995748b0ade",
  "timestamp": "2026-03-01T22:11:24.423Z",
  "commitCount": 24,
  "repository": "owner/cash_synch_proto"
}
```

**Verification**: statusCode=0, no `error` field, no `vpsResponse` field, vpsAck=true, vpsBatchId is UUID, commits oldest-first, no Zone.Identifier, stub received and stored batch.

---

### H2 — VPS down (ngrok returns 502)

**Setup**: Killed stub server (`kill $(lsof -ti :3456)`), verified ngrok still running (1 tunnel active).

**Command**:
```bash
source .env
curl -sL -d '{
  "action": "reportBatch", "trigger": "manual", "triggeredBy": "failure-test",
  "repository": "owner/cash_synch_proto",
  "range": {"from": "aaa", "to": "bbb", "commitCount": 1},
  "commits": [{"sha": "aaa", "shortSha": "aaa", "author": "test", "message": "vps-down test", "timestamp": "2026-03-01T12:00:00Z"}],
  "filesChanged": ["test.gs"], "pathFilter": "apps-script/src/"
}' -H "Content-Type: application/json" "$GAS_WEBAPP_URL"
```

**Response**:
```json
{
  "success": true,
  "correlationId": "gas_1772403132036_sk5k3rmv",
  "tracking": {
    "statusCode": 0,
    "changeLogRow": 22,
    "vpsStatus": 502,
    "vpsAck": false,
    "vpsBatchId": null
  }
}
```

**Verification**: No crash, statusCode=0, vpsAck=false, vpsStatus=502. GitHub Action would NOT move last-documented tag.

**Teardown**: Restarted stub server, verified health OK.

---

### H3 — VPS non-JSON response

**Setup**: Killed stub, started temp non-JSON server:
```bash
node -e "require('http').createServer((q,r)=>{let d='';q.on('data',c=>d+=c);q.on('end',()=>{r.end('NOT JSON')})}).listen(3456)" &
```

**Command**: Same payload as H2.

**Response**:
```json
{
  "success": true,
  "correlationId": "gas_1772403161880_b053t05p",
  "tracking": {
    "statusCode": 0,
    "changeLogRow": 23,
    "vpsStatus": 200,
    "vpsAck": false,
    "vpsBatchId": null
  }
}
```

**Verification**: No crash, vpsAck=false (JSON parse failed), vpsStatus=200 (HTTP succeeded but content was not valid JSON ack).

**Teardown**: Killed temp server, restarted real stub, verified health OK.

---

### H4 — VPS returns explicit `{ ack: false }`

**Setup**: Killed stub, started temp ack:false server:
```bash
node -e "require('http').createServer((q,r)=>{let d='';q.on('data',c=>d+=c);q.on('end',()=>{r.setHeader('Content-Type','application/json');r.end(JSON.stringify({ack:false,reason:'storage full'}))})}).listen(3456)" &
```

**Command**: Same payload as H2.

**Response**:
```json
{
  "success": true,
  "correlationId": "gas_1772403194158_i2xmxsel",
  "tracking": {
    "statusCode": 0,
    "changeLogRow": 24,
    "vpsStatus": 200,
    "vpsAck": false,
    "vpsBatchId": null
  }
}
```

**Verification**: vpsAck=false, vpsBatchId=null. Tag would NOT move in GitHub Action (correct behavior).

**Teardown**: Killed temp server, restarted real stub, verified health OK.

---

### H5 — Stub-safe mode (VPS disabled)

**Setup**: Human set `CHANGE_TRACKER_ENABLED=false` in GAS Script Properties via the Apps Script IDE.

**Command**:
```bash
source .env
curl -sL -d '{
  "action": "reportBatch", "trigger": "manual", "triggeredBy": "stub-safe-test",
  "repository": "owner/cash_synch_proto",
  "range": {"from": "aaa", "to": "bbb", "commitCount": 1},
  "commits": [{"sha": "aaa", "shortSha": "aaa", "author": "test", "message": "stub-safe test", "timestamp": "2026-03-01T12:00:00Z"}],
  "filesChanged": ["test.gs"], "pathFilter": "apps-script/src/"
}' -H "Content-Type: application/json" "$GAS_WEBAPP_URL"
```

**Response**:
```json
{
  "success": true,
  "correlationId": "gas_1772403594421_dvuvupvs",
  "tracking": {
    "statusCode": 0,
    "changeLogRow": 26,
    "vpsStatus": "skipped",
    "vpsAck": false,
    "vpsBatchId": null
  }
}
```

**Verification**: statusCode=0, vpsStatus="skipped", vpsAck=false, vpsBatchId=null. VPS call correctly skipped. Stub server showed no new output.

**Teardown**: Human restored `CHANGE_TRACKER_ENABLED=true` in Script Properties.

---

### H6 — Backward compatibility (plan1 reportChange)

**Command**:
```bash
source .env
curl -sL -d '{"action":"reportChange","author":"compat-test","files":["test.gs"],"changelog":"Backward compat","commitHash":"abc123"}' \
  -H "Content-Type: application/json" "$GAS_WEBAPP_URL"
```

**Response**:
```json
{
  "success": true,
  "correlationId": "gas_1772403223427_l2hchwgb",
  "tracking": {
    "statusCode": 0,
    "changeLogRow": 25,
    "vpsStatus": 404
  }
}
```

**Verification**: statusCode=0, success=true. Plan1 single-change endpoint still works. vpsStatus=404 is expected (stub /changelog endpoint returns 404 for legacy single-change payloads without `.batch` field — this is stub behavior, not a GAS issue).

---

### H7 — Payload builder commit ordering

**Command (messages)**:
```bash
FROM=$(git log --reverse --pretty=format:"%H" | head -1)
TO=$(git rev-parse HEAD)
bash scripts/build-batch-payload.sh "$FROM" "$TO" "apps-script/src/" "manual" "order-test" "owner/cash_synch_proto" \
  | jq '.commits | [first.message, last.message]'
```

**Response**:
```json
[
  "Infrastructure done, awaiting autit",
  "docs: Phase 5 — v2.0.0 deployment, baseline tag, and project housekeeping"
]
```

**Command (timestamps)**:
```bash
bash scripts/build-batch-payload.sh "$FROM" "$TO" "apps-script/src/" "manual" "order-test" "owner/cash_synch_proto" \
  | jq '[.commits[0].timestamp, .commits[-1].timestamp]'
```

**Response**:
```json
[
  "2026-02-14T12:21:03+00:00",
  "2026-03-01T20:56:51+00:00"
]
```

**Verification**: First commit is oldest (2026-02-14), last is newest (2026-03-01). Oldest-first ordering confirmed.

---

### H8 — Payload builder Zone.Identifier filtering

**Command**:
```bash
bash scripts/build-batch-payload.sh "$FROM" "$TO" "apps-script/src/" "manual" "filter-test" "owner/cash_synch_proto" \
  | jq '.filesChanged | map(select(contains("Zone")))'
```

**Response**:
```json
[]
```

**Verification**: Empty array. No `:Zone.Identifier` entries in filesChanged output.
