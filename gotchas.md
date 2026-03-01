# Gotcha storage file
<!-- Uodate responsibility of ANY agent that solves a known issue of the codebase. Update and refer to accordingly -->
This file stores common issues that have been solved to allow other agents not to repeat the same mistakes

## Appendix A: GAS Gotchas You'll Hit

| Gotcha | Explanation | Workaround |
|--------|-------------|------------|
| `clasp push` doesn't update deployments | Deployments are frozen snapshots | Use `/dev` URL for testing, or `clasp deploy -i <id>` to update |
| Authorization required on first deploy | Google needs you to grant permissions to the script | Click through the OAuth consent screen manually |
| 6-minute execution limit | GAS kills scripts after 6 min | Not an issue for our lightweight POST handler |
| No `import`/`export` | All .gs files share one global scope | Use singleton objects and unique function names |
| `UrlFetchApp` can't hit localhost | GAS runs on Google's servers | Use ngrok/cloudflare tunnel to expose local server |
| Response caching | GAS sometimes caches GET responses | Add `&t={timestamp}` parameter to bust cache |
| `ContentService` vs `HtmlService` | ContentService = JSON/text, HtmlService = HTML pages | Always use ContentService for API responses |
| `appsscript.json` access vs deployment access | Changing `"access": "ANYONE_ANONYMOUS"` in appsscript.json does NOT update existing deployment access settings | Must also update "Who has access" in Apps Script IDE > Deploy > Manage deployments |
| Re-authorization after adding new files | Adding .gs files that use new scopes (SpreadsheetApp, CacheService, **UrlFetchApp**) requires re-authorization. **CRITICAL**: UrlFetchApp.fetch() will fail with "authorization required" error until manually authorized | Run any function in IDE to trigger OAuth consent (don't need to redeploy — authorization applies to script, not deployment). Open IDE → select any function → Run → approve OAuth dialog |
| `clasp push` skips unchanged files | If clasp thinks files haven't changed it prints "Skipping push" | Use `clasp push -f` to force push |
| curl POST to GAS exec URL returns 405 | GAS returns 302 redirect; using `-X POST` forces POST on the redirect target which only accepts GET | Use `curl -sL -d '...' -H "Content-Type: application/json" URL` — the `-d` flag implies POST for the initial request, and curl properly follows the 302 as GET |
| New deployment needed for access changes | Updating an existing deployment via `clasp deploy -i` may not apply access setting changes | Create a new deployment via IDE: Deploy > New deployment, set "Who has access" to "Anyone" |

## Appendix B: Dual-Clasp Architecture

| Gotcha | Explanation | Workaround |
|--------|-------------|------------|
| Two separate clasp projects | Sandbox and enterprise each have their own `.clasp.json` pointing to different GAS projects. `clasp push` from sandbox only affects sandbox GAS; enterprise push only affects enterprise GAS. | Always `cd` into the correct `apps-script/` directory before `clasp push`. Verify with `clasp status`. |
| Enterprise has no `.clasp.json` yet | Only `.clasp.json.example` exists with placeholder `YOUR_SCRIPT_ID_HERE` | Phase 6 Task 6.3: Copy `.clasp.json.example` to `.clasp.json` and set scriptId to `1xF9D62dLZJ7df0aNmKm82UJ6BZPGiOAKdxKdvWp0Ra-NVmmP60GrCQH4` |
| Enterprise WebApp.gs has `sync` routing | Enterprise doPost switch has `sync` and `writeLog` cases. Sandbox version is stripped down. | Phase 6 must ADD `reportBatch` case alongside `sync`, not replace the switch. See enterprise WebApp.gs lines 88-107. |
| Enterprise GAS re-authorization | Adding ChangeTracker.gs to enterprise introduces `UrlFetchApp` scope which may require re-authorization | After `clasp push` to enterprise, open IDE → select any function → Run → approve OAuth dialog |
| GitHub Actions in enterprise | Enterprise already has `ci.yml`. New `doc-batch.yml` must coexist without conflicts | Use separate workflow file, separate triggers, no shared state |

## Appendix C: Useful Clasp Commands

| Command | Description |
|---------|-------------|
| `clasp push` | Upload local code to GAS project |
| `clasp pull` | Download GAS project code locally |
| `clasp deploy -d "msg"` | Create new versioned deployment |
| `clasp deploy -i <id> -d "msg"` | Update existing deployment in-place |
| `clasp deployments` | List all deployments with IDs and URLs |
| `clasp open` | Open the GAS IDE in browser |
| `clasp logs` | View Stackdriver logs |
| `clasp status` | Show which files will be pushed |
| `clasp versions` | List all versions |

