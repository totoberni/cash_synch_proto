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

## Appendix B: Useful Clasp Commands

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

