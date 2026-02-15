/**
 * Stub VPS Server — Minimal HTTP server for testing GAS change notifications
 *
 * Requirements:
 * - Zero dependencies (Node.js http module only)
 * - Accepts POST /changelog → parse JSON, pretty-print, return { received: true, timestamp }
 * - All other routes → 404
 *
 * Usage:
 *   node stub-server/server.js                  # Default port 3456
 *   PORT=4000 node stub-server/server.js        # Custom port
 */

const http = require('http');

const PORT = process.env.PORT || 3456;

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

        // Pretty-print the received payload
        console.log('\n' + '='.repeat(80));
        console.log(`[${timestamp}] Change notification received`);
        console.log('='.repeat(80));
        console.log(JSON.stringify(payload, null, 2));
        console.log('='.repeat(80) + '\n');

        // Return success response
        const response = {
          received: true,
          timestamp: timestamp
        };

        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify(response));

      } catch (err) {
        // Handle JSON parse error
        console.error(`[${timestamp}] ERROR: Invalid JSON received`);
        console.error('Body:', body);

        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({
          error: 'Invalid JSON',
          timestamp: timestamp
        }));
      }
    });

    return;
  }

  // All other routes → 404
  res.writeHead(404, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ error: 'Not found' }));
});

server.listen(PORT, () => {
  console.log('┌' + '─'.repeat(78) + '┐');
  console.log('│ Stub VPS Server — Change Notification Receiver' + ' '.repeat(31) + '│');
  console.log('├' + '─'.repeat(78) + '┤');
  console.log(`│ Listening on: http://localhost:${PORT}/changelog` + ' '.repeat(78 - 51 - String(PORT).length) + '│');
  console.log('│ Status: Waiting for notifications...' + ' '.repeat(41) + '│');
  console.log('└' + '─'.repeat(78) + '┘\n');
});
