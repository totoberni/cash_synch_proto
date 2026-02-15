/**
 * Change Tracker Service for Google Apps Script
 *
 * Receives code change notifications and forwards them to an external VPS.
 * Logs all changes to _CHANGE_LOG sheet for audit trail.
 */

var CHANGE_LOG_SHEET_NAME = '_CHANGE_LOG';

/**
 * ChangeTracker Service singleton
 */
var ChangeTracker = {
  /**
   * Notify the system of a code change
   * @param {Object} changeData - Change details { author, files, changelog, commitHash }
   * @param {string} correlationId - Request correlation ID
   * @returns {Object} Result object with changeLogRow, vpsStatus, and optional error
   */
  notify: function(changeData, correlationId) {
    var result = {
      changeLogRow: null,
      vpsStatus: 'skipped',
      vpsResponse: null,
      error: null
    };

    try {
      // 1. Always write to _CHANGE_LOG sheet first (even if VPS fails later)
      var sheet = this.getOrCreateChangeLogSheet();
      var timestamp = new Date().toISOString();
      var filesString = Array.isArray(changeData.files) ? changeData.files.join(', ') : '';

      // Prepare row data (will update vpsUrl, vpsStatus, vpsResponse after VPS call)
      var rowData = [
        timestamp,
        correlationId,
        changeData.author || 'unknown',
        filesString,
        changeData.changelog || '',
        changeData.commitHash || '',
        '', // vpsUrl - will be filled if VPS is configured
        'pending', // vpsStatus - will be updated
        '' // vpsResponse - will be filled if VPS responds
      ];

      var rowNumber = sheet.getLastRow() + 1;
      sheet.appendRow(rowData);
      result.changeLogRow = rowNumber;

      // 2. Check if VPS is configured and enabled
      if (this.isVpsConfigured()) {
        var vpsUrl = this.getVpsUrl();
        var payload = this.buildPayload(changeData, correlationId);

        // 3. POST to VPS
        var vpsResult = this.postToVps(vpsUrl, payload);

        // 4. Update the sheet row with VPS results
        sheet.getRange(rowNumber, 7).setValue(vpsUrl); // Column G: vpsUrl
        sheet.getRange(rowNumber, 8).setValue(vpsResult.status); // Column H: vpsStatus
        sheet.getRange(rowNumber, 9).setValue(vpsResult.body); // Column I: vpsResponse

        result.vpsStatus = vpsResult.status;
        result.vpsResponse = vpsResult.body;

        // 5. Log to LogService
        LogService.info('changetracker.notify', 'Change notification processed', {
          author: changeData.author,
          fileCount: changeData.files ? changeData.files.length : 0,
          vpsStatus: vpsResult.status,
          vpsUrl: vpsUrl
        });
      } else {
        // VPS not configured - update sheet to reflect skipped status
        sheet.getRange(rowNumber, 8).setValue('skipped');

        // Log that VPS was skipped
        LogService.info('changetracker.notify', 'Change notification processed (VPS skipped)', {
          author: changeData.author,
          fileCount: changeData.files ? changeData.files.length : 0,
          vpsStatus: 'skipped'
        });
      }
    } catch (err) {
      result.error = err.message;
      LogService.error('changetracker.notify', 'Change notification failed: ' + err.message, {
        error: err.message,
        stack: err.stack,
        author: changeData.author
      });
    }

    return result;
  },

  /**
   * Get or create the _CHANGE_LOG sheet with proper headers
   * @returns {GoogleAppsScript.Spreadsheet.Sheet} The change log sheet
   */
  getOrCreateChangeLogSheet: function() {
    var ss = SpreadsheetApp.getActiveSpreadsheet();
    var sheet = ss.getSheetByName(CHANGE_LOG_SHEET_NAME);

    if (!sheet) {
      sheet = ss.insertSheet(CHANGE_LOG_SHEET_NAME);
      // Add headers
      var headers = [
        'timestamp',
        'correlationId',
        'author',
        'files',
        'changelog',
        'commitHash',
        'vpsUrl',
        'vpsStatus',
        'vpsResponse'
      ];
      sheet.getRange(1, 1, 1, headers.length).setValues([headers]);
      sheet.getRange(1, 1, 1, headers.length).setFontWeight('bold');
      sheet.setFrozenRows(1);

      // Set column widths for readability
      sheet.setColumnWidth(1, 180);  // timestamp
      sheet.setColumnWidth(2, 200);  // correlationId
      sheet.setColumnWidth(3, 120);  // author
      sheet.setColumnWidth(4, 250);  // files
      sheet.setColumnWidth(5, 300);  // changelog
      sheet.setColumnWidth(6, 100);  // commitHash
      sheet.setColumnWidth(7, 250);  // vpsUrl
      sheet.setColumnWidth(8, 100);  // vpsStatus
      sheet.setColumnWidth(9, 300);  // vpsResponse
    }

    return sheet;
  },

  /**
   * Check if VPS is configured and enabled
   * @returns {boolean} True if VPS should be used
   */
  isVpsConfigured: function() {
    var props = PropertiesService.getScriptProperties();
    var enabled = props.getProperty('CHANGE_TRACKER_ENABLED');
    var vpsUrl = props.getProperty('CHANGE_TRACKER_VPS_URL');

    // Return true only if both are set and enabled is not explicitly "false"
    return (vpsUrl && vpsUrl.length > 0 && enabled !== 'false');
  },

  /**
   * Get the VPS URL from Script Properties
   * @returns {string} VPS URL or empty string
   */
  getVpsUrl: function() {
    var props = PropertiesService.getScriptProperties();
    return props.getProperty('CHANGE_TRACKER_VPS_URL') || '';
  },

  /**
   * Build the payload to send to VPS
   * @param {Object} changeData - Change details
   * @param {string} correlationId - Request correlation ID
   * @returns {Object} Payload object
   */
  buildPayload: function(changeData, correlationId) {
    var props = PropertiesService.getScriptProperties();

    return {
      scriptId: ScriptApp.getScriptId(),
      scriptEndpoint: props.getProperty('GAS_DEPLOYMENT_URL') || 'not-configured',
      timestamp: new Date().toISOString(),
      correlationId: correlationId,
      change: {
        author: changeData.author,
        files: changeData.files,
        changelog: changeData.changelog,
        commitHash: changeData.commitHash || null
      }
    };
  },

  /**
   * POST payload to VPS endpoint
   * @param {string} url - VPS endpoint URL
   * @param {Object} payload - Payload object to send
   * @returns {Object} Result with status code and truncated response body
   */
  postToVps: function(url, payload) {
    try {
      var response = UrlFetchApp.fetch(url, {
        method: 'post',
        contentType: 'application/json',
        payload: JSON.stringify(payload),
        muteHttpExceptions: true  // CRITICAL: prevents GAS from throwing on 4xx/5xx
      });

      var responseCode = response.getResponseCode();
      var responseText = response.getContentText();

      // Truncate response to 500 chars to prevent sheet cell overflow
      var truncatedResponse = responseText.length > 500
        ? responseText.substring(0, 500) + '... (truncated)'
        : responseText;

      return {
        status: responseCode,
        body: truncatedResponse
      };
    } catch (err) {
      // Network error or other exception
      return {
        status: 'error',
        body: 'Exception: ' + err.message
      };
    }
  }
};
