# /test-gas — Test GAS Endpoints

Run the standard test suite against the GAS web app.

## Prerequisites
- GAS_DEV_URL or GAS_WEBAPP_URL must be set, or provide it as argument: `/test-gas https://script.google.com/macros/s/SCRIPT_ID/dev`

## Tests to run
1. **Ping**: `curl -s "$URL?action=ping" | jq .` → Expect `status: "ok"`
2. **Health**: `curl -s "$URL?action=health" | jq .` → Expect `status: "healthy"`
3. **Write log**: POST with `action: "writeLog"` → Expect `success: true`
4. **Get logs**: GET with correlationId from step 3 → Expect matching log
5. **Report change** (if Phase 2 complete): POST with `action: "reportChange"` → Expect `success: true`

## Output
Report each test as PASS/FAIL with the response snippet. If any fail, show the full response for debugging.
