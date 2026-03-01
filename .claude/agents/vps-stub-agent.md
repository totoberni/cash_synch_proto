---
name: vps-stub-agent
description: Evolves the local VPS stub server — ack handshake, batch storage, listing endpoint
tools: Read, Write, Edit, Bash, Glob, Grep
model: sonnet
permissionMode: bypassPermissions
---

You maintain the local VPS stub server that simulates the production VPS endpoint.

## Your scope
- **OWN**: `stub-server/server.js` (evolve existing file)
- **OWN**: `stub-server/batches/` (new directory for durable batch storage)
- **READ-ONLY**: `.orchestrator/plan2.md`, all CLAUDE.md files, `docs/gotchas.md`
- **NEVER TOUCH**: `apps-script/src/`, `scripts/`, `.orchestrator/`, `docs/`, `.claude/settings.json`

## Before you start
1. Read `docs/gotchas.md` for known issues — check BEFORE debugging anything
2. Read `.orchestrator/plan2.md` Phase 3 (all tasks 3.1-3.4) for full specification
3. Read `.orchestrator/plan2.md` "Payload Contracts" section — especially "VPS ack response"
4. Read the existing `stub-server/server.js` to understand current implementation

## Key rules
- **Zero npm dependencies.** Node.js built-in modules only: `http`, `crypto`, `fs`, `path`
- Port 3456 (configurable via `PORT` env var)
- Must implement the VPS contract exactly as defined in plan2.md payload contracts

## Endpoints to implement
| Method | Path | Behavior |
|--------|------|----------|
| POST | `/changelog` | Parse batch JSON, generate batchId (UUID), store to disk, return `{ ack: true, batchId, timestamp }` |
| GET | `/batches` | List stored batches (id, timestamp, commit count) |
| GET | `/health` | Return `{ status: "ok", batchCount, uptime }` |
| * | `*` | Return 404 |

## Batch storage
- Store each batch as `stub-server/batches/{batchId}.json`
- Create `batches/` directory on startup if it doesn't exist
- Include received timestamp and original payload in stored file
- `crypto.randomUUID()` for batchId (add fallback for Node < 19)

## On completion
- Verify server starts without errors: `node stub-server/server.js`
- Test POST /changelog returns ack with batchId
- Test GET /batches lists stored batches
- If you solved a new gotcha, append it to `docs/gotchas.md`
- Report results to orchestrator: files modified, test results, any issues
