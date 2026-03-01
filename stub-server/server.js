/**
 * Stub VPS Server — Minimal HTTP server for testing GAS change notifications
 *
 * Requirements:
 * - Zero dependencies (Node.js built-in modules only: http, crypto, fs, path)
 * - POST /changelog → detect batch vs legacy payloads
 *   - Legacy: parse JSON, pretty-print, return { received: true, timestamp }
 *   - Batch:  generate batchId, store to disk, return { ack: true, batchId, timestamp }
 * - GET /batches → list stored batches as JSON array
 * - GET /batches/:id → return full stored batch payload
 * - GET /health → return { status: "ok", batchCount, uptime }
 * - All other routes → 404
 *
 * Usage:
 *   node stub-server/server.js                  # Default port 3456
 *   PORT=4000 node stub-server/server.js        # Custom port
 */

const http = require('http');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const PORT = process.env.PORT || 3456;

// Resolve batches directory relative to this script's location
const BATCHES_DIR = path.join(__dirname, 'batches');

// Ensure batches directory exists on startup
if (!fs.existsSync(BATCHES_DIR)) {
  fs.mkdirSync(BATCHES_DIR, { recursive: true });
  console.log(`Created batches directory: ${BATCHES_DIR}`);
}

/**
 * Generate a unique batch ID.
 * Uses crypto.randomUUID() (Node.js 19+) with fallback for older versions.
 */
const generateBatchId = () => {
  if (typeof crypto.randomUUID === 'function') {
    return crypto.randomUUID();
  }
  return crypto.randomBytes(16).toString('hex');
};

/**
 * Read all batch files from the batches directory.
 * Returns an array of { batchId, timestamp, commitCount, repository }.
 */
const listBatches = () => {
  const files = fs.readdirSync(BATCHES_DIR).filter(f => f.endsWith('.json'));
  return files.map(file => {
    try {
      const content = JSON.parse(fs.readFileSync(path.join(BATCHES_DIR, file), 'utf8'));
      const batchId = path.basename(file, '.json');
      return {
        batchId,
        timestamp: content.timestamp || null,
        commitCount: (content.batch && content.batch.range && content.batch.range.commitCount) || 0,
        repository: (content.batch && content.batch.repository) || null
      };
    } catch (err) {
      return null;
    }
  }).filter(Boolean);
};

/**
 * Count batch files in the batches directory.
 */
const countBatches = () => {
  return fs.readdirSync(BATCHES_DIR).filter(f => f.endsWith('.json')).length;
};

const startTime = Date.now();

const server = http.createServer((req, res) => {
  const { method, url } = req;

  // Route: POST /changelog
  if (method === 'POST' && url === '/changelog') {
    let body = '';

    req.on('data', chunk => {
      body += chunk.toString();
    });

    req.on('end', () => {
      const timestamp = new Date().toISOString();

      try {
        const payload = JSON.parse(body);

        // Detect payload type: batch mode vs legacy mode
        const isBatch = payload.batch !== undefined;

        // Pretty-print the received payload
        console.log('\n' + '='.repeat(80));
        console.log(`[${timestamp}] ${isBatch ? 'Batch' : 'Change'} notification received`);
        console.log('='.repeat(80));
        console.log(JSON.stringify(payload, null, 2));
        console.log('='.repeat(80) + '\n');

        if (isBatch) {
          // --- Batch mode ---
          const batchId = generateBatchId();

          // Add metadata to stored payload
          const storedPayload = {
            ...payload,
            timestamp,
            batchId
          };

          // Write batch to disk
          const batchFile = path.join(BATCHES_DIR, `${batchId}.json`);
          fs.writeFileSync(batchFile, JSON.stringify(storedPayload, null, 2));
          console.log(`Batch stored: batches/${batchId}.json`);

          // Return batch ack response
          const response = {
            ack: true,
            batchId,
            timestamp
          };

          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify(response));

        } else {
          // --- Legacy mode (unchanged) ---
          const response = {
            received: true,
            timestamp
          };

          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify(response));
        }

      } catch (err) {
        // Handle JSON parse error
        console.error(`[${timestamp}] ERROR: Invalid JSON received`);
        console.error('Body:', body);

        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({
          error: 'Invalid JSON',
          timestamp
        }));
      }
    });

    return;
  }

  // Route: GET /health
  if (method === 'GET' && url === '/health') {
    const uptimeSeconds = Math.floor((Date.now() - startTime) / 1000);
    const response = {
      status: 'ok',
      batchCount: countBatches(),
      uptime: uptimeSeconds
    };

    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(response));
    return;
  }

  // Route: GET /batches/:id
  // Must be checked before GET /batches to avoid false match
  const batchIdMatch = method === 'GET' && url.match(/^\/batches\/([a-zA-Z0-9_-]+)$/);
  if (batchIdMatch) {
    const batchId = batchIdMatch[1];
    const batchFile = path.join(BATCHES_DIR, `${batchId}.json`);

    if (fs.existsSync(batchFile)) {
      try {
        const content = fs.readFileSync(batchFile, 'utf8');
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(content);
      } catch (err) {
        res.writeHead(500, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Failed to read batch file' }));
      }
    } else {
      res.writeHead(404, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: `Batch ${batchId} not found` }));
    }
    return;
  }

  // Route: GET /batches
  if (method === 'GET' && url === '/batches') {
    const batches = listBatches();
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(batches));
    return;
  }

  // All other routes -> 404
  res.writeHead(404, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ error: 'Not found' }));
});

server.listen(PORT, () => {
  console.log('┌' + '─'.repeat(78) + '┐');
  console.log('│ Stub VPS Server — Change Notification Receiver' + ' '.repeat(31) + '│');
  console.log('├' + '─'.repeat(78) + '┤');
  console.log(`│ POST /changelog      → Accept changes (legacy + batch)` + ' '.repeat(23) + '│');
  console.log(`│ GET  /batches        → List stored batches` + ' '.repeat(35) + '│');
  console.log(`│ GET  /batches/:id    → Retrieve batch by ID` + ' '.repeat(33) + '│');
  console.log(`│ GET  /health         → Server health check` + ' '.repeat(35) + '│');
  console.log('├' + '─'.repeat(78) + '┤');
  console.log(`│ Listening on: http://localhost:${PORT}` + ' '.repeat(78 - 39 - String(PORT).length) + '│');
  console.log(`│ Batch storage: ${BATCHES_DIR}` + ' '.repeat(Math.max(0, 78 - 18 - BATCHES_DIR.length)) + '│');
  console.log('│ Status: Waiting for notifications...' + ' '.repeat(41) + '│');
  console.log('└' + '─'.repeat(78) + '┘\n');
});
