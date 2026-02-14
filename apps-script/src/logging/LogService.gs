/**
 * Log Service for Google Apps Script
 *
 * Provides structured logging with correlation ID support.
 * Logs are stored in a dedicated _LOGS sheet for retrieval.
 */

var LOG_SHEET_NAME = '_LOGS';
var LOG_ARCHIVE_PREFIX = '_LOGS_ARCHIVE_';
var MAX_LOG_ROWS = 10000;

/**
 * Log Service singleton
 */
var LogService = {
  /**
   * Write a log entry to the _LOGS sheet
   * @param {string} level - Log level: DEBUG, INFO, WARN, ERROR
   * @param {string} category - Log category (e.g., 'sync.start', 'api.call')
   * @param {string} message - Log message
   * @param {Object} metadata - Optional metadata object
   * @param {string} correlationId - Optional correlation ID (uses current if not provided)
   */
  write: function(level, category, message, metadata, correlationId) {
    try {
      var sheet = this.getOrCreateLogSheet();
      var corrId = correlationId || getCurrentCorrelationId() || 'unknown';

      var row = [
        new Date().toISOString(),           // timestamp
        corrId,                              // correlationId
        level || 'INFO',                     // level
        'GAS',                               // layer (always GAS in this context)
        category || 'general',               // category
        message || '',                       // message
        JSON.stringify(metadata || {}),      // metadata as JSON
        metadata && metadata.executionTimeMs ? metadata.executionTimeMs : null  // executionTimeMs
      ];

      sheet.appendRow(row);

      // Check if rotation needed
      if (sheet.getLastRow() > MAX_LOG_ROWS) {
        this.rotateLog();
      }
    } catch (err) {
      // Last resort: native Logger
      Logger.log('LogService.write failed: ' + err.message);
    }
  },

  /**
   * Get or create the _LOGS sheet with proper headers
   * @returns {GoogleAppsScript.Spreadsheet.Sheet} The log sheet
   */
  getOrCreateLogSheet: function() {
    var ss = SpreadsheetApp.getActiveSpreadsheet();
    var sheet = ss.getSheetByName(LOG_SHEET_NAME);

    if (!sheet) {
      sheet = ss.insertSheet(LOG_SHEET_NAME);
      // Add headers
      var headers = [
        'timestamp',
        'correlationId',
        'level',
        'layer',
        'category',
        'message',
        'metadata',
        'executionTimeMs'
      ];
      sheet.getRange(1, 1, 1, headers.length).setValues([headers]);
      sheet.getRange(1, 1, 1, headers.length).setFontWeight('bold');
      sheet.setFrozenRows(1);

      // Set column widths
      sheet.setColumnWidth(1, 180);  // timestamp
      sheet.setColumnWidth(2, 200);  // correlationId
      sheet.setColumnWidth(3, 60);   // level
      sheet.setColumnWidth(4, 60);   // layer
      sheet.setColumnWidth(5, 120);  // category
      sheet.setColumnWidth(6, 400);  // message
      sheet.setColumnWidth(7, 300);  // metadata
      sheet.setColumnWidth(8, 100);  // executionTimeMs
    }

    return sheet;
  },

  /**
   * Rotate logs by archiving old entries
   */
  rotateLog: function() {
    var ss = SpreadsheetApp.getActiveSpreadsheet();
    var sheet = ss.getSheetByName(LOG_SHEET_NAME);

    if (!sheet || sheet.getLastRow() <= MAX_LOG_ROWS) {
      return;
    }

    // Create archive sheet
    var archiveName = LOG_ARCHIVE_PREFIX + Utilities.formatDate(
      new Date(),
      Session.getScriptTimeZone(),
      'yyyyMMdd_HHmmss'
    );
    var archiveSheet = ss.insertSheet(archiveName);

    // Copy all data to archive
    var dataRange = sheet.getDataRange();
    dataRange.copyTo(archiveSheet.getRange(1, 1));

    // Clear main sheet except headers
    if (sheet.getLastRow() > 1) {
      sheet.deleteRows(2, sheet.getLastRow() - 1);
    }

    this.info('log.rotate', 'Log rotated to ' + archiveName, { archiveName: archiveName });
  },

  /**
   * Fetch logs by correlation ID
   * @param {string} correlationId - The correlation ID to search for
   * @param {number} limit - Max number of logs to return (default 100)
   * @returns {Array} Array of log entries
   */
  fetchByCorrelationId: function(correlationId, limit) {
    var maxResults = limit || 100;
    var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(LOG_SHEET_NAME);

    if (!sheet || sheet.getLastRow() <= 1) {
      return [];
    }

    var data = sheet.getDataRange().getValues();
    var headers = data[0];
    var results = [];

    // Find correlationId column index
    var corrIdIndex = headers.indexOf('correlationId');
    if (corrIdIndex === -1) corrIdIndex = 1; // Fallback to column B

    // Search from newest to oldest (bottom to top)
    for (var i = data.length - 1; i > 0 && results.length < maxResults; i--) {
      if (data[i][corrIdIndex] === correlationId) {
        var entry = {};
        for (var j = 0; j < headers.length; j++) {
          var value = data[i][j];
          // Parse metadata JSON
          if (headers[j] === 'metadata' && typeof value === 'string') {
            try {
              value = JSON.parse(value);
            } catch (e) {
              // Keep as string if not valid JSON
            }
          }
          entry[headers[j]] = value;
        }
        results.push(entry);
      }
    }

    // Return in chronological order
    return results.reverse();
  },

  // Convenience methods

  debug: function(category, message, metadata) {
    this.write('DEBUG', category, message, metadata);
  },

  info: function(category, message, metadata) {
    this.write('INFO', category, message, metadata);
  },

  warn: function(category, message, metadata) {
    this.write('WARN', category, message, metadata);
  },

  error: function(category, message, metadata) {
    this.write('ERROR', category, message, metadata);
  },

  /**
   * Log a timed operation
   * @param {string} category - Log category
   * @param {string} message - Log message
   * @param {Function} fn - Function to execute and time
   * @returns {*} Result of the function
   */
  timed: function(category, message, fn) {
    var startTime = new Date().getTime();
    try {
      var result = fn();
      var elapsed = new Date().getTime() - startTime;
      this.info(category, message + ' completed', { executionTimeMs: elapsed });
      return result;
    } catch (err) {
      var elapsed = new Date().getTime() - startTime;
      this.error(category, message + ' failed: ' + err.message, {
        executionTimeMs: elapsed,
        error: err.message,
        stack: err.stack
      });
      throw err;
    }
  }
};

/**
 * Cleanup old archived logs (keep last 10)
 */
function cleanupArchivedLogs() {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheets = ss.getSheets();
  var archives = [];

  for (var i = 0; i < sheets.length; i++) {
    var name = sheets[i].getName();
    if (name.indexOf(LOG_ARCHIVE_PREFIX) === 0) {
      archives.push({ sheet: sheets[i], name: name });
    }
  }

  // Sort by name (which includes timestamp)
  archives.sort(function(a, b) {
    return b.name.localeCompare(a.name);
  });

  // Delete all but the 10 most recent
  for (var i = 10; i < archives.length; i++) {
    ss.deleteSheet(archives[i].sheet);
  }

  if (archives.length > 10) {
    LogService.info('log.cleanup', 'Cleaned up ' + (archives.length - 10) + ' old log archives');
  }
}
