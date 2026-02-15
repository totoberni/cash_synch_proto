/**
 * Web App Entry Point for GAS Change Tracker Sandbox
 *
 * Routes HTTP requests to appropriate handlers.
 * Based on enterprise WebApp.gs with sync handlers removed.
 */

/**
 * Handle GET requests
 * @param {Object} e - Event object from Google Apps Script
 * @returns {TextOutput} JSON response
 */
function doGet(e) {
  var correlationId = getCorrelationIdFromRequest(e);
  setCurrentCorrelationId(correlationId);

  var action = (e && e.parameter && e.parameter.action) ? e.parameter.action : '';
  var response;
  echo "// manual test $(date)" 
  try {
    switch (action) {
      case 'ping':
        response = {
          status: 'ok',
          timestamp: new Date().toISOString(),
          correlationId: correlationId
        };
        break;

      case 'health':
        response = handleHealthCheck(correlationId);
        break;

      case 'getLogs':
        response = handleGetLogs(e, correlationId);
        break;

      default:
        response = {
          error: 'Unknown action: ' + action,
          availableActions: ['ping', 'health', 'getLogs'],
          correlationId: correlationId
        };
    }
  } catch (err) {
    LogService.error('webapp.doGet', 'Unhandled error in doGet: ' + err.message, {
      action: action,
      error: err.message,
      stack: err.stack
    });
    response = {
      error: 'Internal error: ' + err.message,
      correlationId: correlationId
    };
  }

  return ContentService.createTextOutput(JSON.stringify(response))
    .setMimeType(ContentService.MimeType.JSON);
}

/**
 * Handle POST requests
 * @param {Object} e - Event object from Google Apps Script
 * @returns {TextOutput} JSON response
 */
function doPost(e) {
  var correlationId = getCorrelationIdFromRequest(e);
  setCurrentCorrelationId(correlationId);

  var response;

  try {
    var body = {};
    if (e && e.postData && e.postData.contents) {
      body = JSON.parse(e.postData.contents);
    }

    var action = body.action || '';

    switch (action) {
      case 'writeLog':
        var level = body.level || 'INFO';
        var category = body.category || 'manual';
        var message = body.message || '';
        var metadata = body.metadata || {};
        LogService.write(level, category, message, metadata, correlationId);
        response = {
          success: true,
          correlationId: correlationId
        };
        break;

      case 'reportChange':
        response = handleReportChange(body, correlationId);
        break;

      default:
        response = {
          error: 'Unknown action: ' + action,
          availableActions: ['writeLog', 'reportChange'],
          correlationId: correlationId
        };
    }
  } catch (err) {
    LogService.error('webapp.doPost', 'Unhandled error in doPost: ' + err.message, {
      error: err.message,
      stack: err.stack
    });
    response = {
      error: 'Internal error: ' + err.message,
      correlationId: correlationId
    };
  }

  return ContentService.createTextOutput(JSON.stringify(response))
    .setMimeType(ContentService.MimeType.JSON);
}

/**
 * Handle health check — returns spreadsheet info
 * @param {string} correlationId - Request correlation ID
 * @returns {Object} Health status with spreadsheet details
 */
function handleHealthCheck(correlationId) {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheets = ss.getSheets();
  var sheetNames = [];
  for (var i = 0; i < sheets.length; i++) {
    sheetNames.push(sheets[i].getName());
  }

  return {
    status: 'healthy',
    correlationId: correlationId,
    spreadsheet: {
      id: ss.getId(),
      name: ss.getName(),
      sheets: sheetNames
    },
    timestamp: new Date().toISOString()
  };
}

/**
 * Handle getLogs — fetch logs by correlation ID
 * @param {Object} e - Event object with parameters
 * @param {string} correlationId - Request correlation ID
 * @returns {Object} Logs matching the requested correlation ID
 */
function handleGetLogs(e, correlationId) {
  var targetCorrelationId = (e && e.parameter && e.parameter.correlationId)
    ? e.parameter.correlationId
    : correlationId;
  var limit = (e && e.parameter && e.parameter.limit)
    ? parseInt(e.parameter.limit, 10)
    : 100;

  var logs = LogService.fetchByCorrelationId(targetCorrelationId, limit);

  return {
    correlationId: targetCorrelationId,
    count: logs.length,
    logs: logs
  };
}

/**
 * Handle reportChange action — receives code change metadata and forwards to VPS
 * @param {Object} body - Request body with change details
 * @param {string} correlationId - Request correlation ID
 * @returns {Object} Result with tracking info
 */
function handleReportChange(body, correlationId) {
  // Validate required fields
  if (!body.changelog || typeof body.changelog !== 'string') {
    return { error: 'Missing or invalid field: changelog (string required)', correlationId: correlationId };
  }
  if (!body.files || !Array.isArray(body.files) || body.files.length === 0) {
    return { error: 'Missing or invalid field: files (non-empty array required)', correlationId: correlationId };
  }

  var changeData = {
    author: body.author || 'unknown',
    files: body.files,
    changelog: body.changelog,
    commitHash: body.commitHash || null
  };

  var result = ChangeTracker.notify(changeData, correlationId);

  return {
    success: !result.error,
    correlationId: correlationId,
    tracking: result
  };
}
