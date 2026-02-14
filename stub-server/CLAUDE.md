# Stub Server — CLAUDE.md

## Files
- `server.js` — Minimal HTTP server that simulates a VPS receiving change notifications.

## Requirements
- **Zero dependencies** — Node.js built-in `http` module only. No npm install.
- Port 3456 (configurable via `PORT` env var)
- `POST /changelog` → parse JSON body, pretty-print with timestamp, return `{ received: true, timestamp }`
- All other routes → 404
- Startup: print listening URL and "waiting for notifications" message

## Usage
```bash
node stub-server/server.js                  # Default port 3456
PORT=4000 node stub-server/server.js        # Custom port
```

## Owner
tooling-agent (Phase 3)
