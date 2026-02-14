# /deploy — Deploy GAS Web App

Create or update a versioned deployment of the GAS web app.

## Steps

### 1. Push latest code
```bash
cd apps-script && clasp push
```
Verify: "Pushed N files" with no errors.

### 2. Check existing deployments
```bash
cd apps-script && clasp deployments
```
Note: The first entry (with `@HEAD`) is the dev deployment — it always runs latest code.
Other entries are frozen versioned deployments.

### 3. Deploy
**New deployment:**
```bash
cd apps-script && clasp deploy -d "v1.0.0 — description"
```

**Update existing deployment in-place:**
```bash
cd apps-script && clasp deploy -i DEPLOYMENT_ID -d "v1.0.1 — description"
```

### 4. Verify
Test the `/exec` URL (frozen deployment):
```bash
curl -s "https://script.google.com/macros/s/DEPLOYMENT_ID/exec?action=ping" | jq .
```
Expect: `{ "status": "ok", "timestamp": "...", "correlationId": "gas_..." }`

### 5. Record
- Note the deployment ID and /exec URL
- Update `.orchestrator/state.md` with the deployment URL if this is a milestone

## Gotchas
- `clasp push` does NOT update existing deployments — you must `clasp deploy` separately
- `/dev` URL always runs HEAD (latest pushed code)
- `/exec` URL runs the frozen deployment version — test against the right one
- First deploy may require OAuth consent screen approval in browser
