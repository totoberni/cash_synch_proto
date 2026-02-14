/**
 * Correlation ID Handler for Google Apps Script
 *
 * Receives and manages correlation IDs from the Web App
 * to enable end-to-end request tracing.
 */

/**
 * Get correlation ID from request parameters or headers
 * @param {Object} e - Event object from doGet/doPost
 * @returns {string} Correlation ID or generated one
 */
function getCorrelationIdFromRequest(e) {
  // Try to get from parameter (most reliable for GAS)
  if (e && e.parameter && e.parameter.correlationId) {
    return e.parameter.correlationId;
  }

  // Try to get from POST body
  if (e && e.postData && e.postData.contents) {
    try {
      var body = JSON.parse(e.postData.contents);
      if (body.correlationId) {
        return body.correlationId;
      }
    } catch (err) {
      // Ignore JSON parse errors
    }
  }

  // Generate a new one if not provided
  return generateGASCorrelationId();
}

/**
 * Generate a correlation ID in GAS
 * Format: gas_{timestamp}_{random}
 * @returns {string} Generated correlation ID
 */
function generateGASCorrelationId() {
  var timestamp = new Date().getTime();
  var random = Math.random().toString(36).substring(2, 10);
  return 'gas_' + timestamp + '_' + random;
}

/**
 * Store correlation ID in script properties for the current execution
 * @param {string} correlationId - The correlation ID to store
 */
function setCurrentCorrelationId(correlationId) {
  var cache = CacheService.getScriptCache();
  // Store for 10 minutes (max single execution time)
  cache.put('current_correlation_id', correlationId, 600);
}

/**
 * Get the current correlation ID from cache
 * @returns {string|null} The current correlation ID or null
 */
function getCurrentCorrelationId() {
  var cache = CacheService.getScriptCache();
  return cache.get('current_correlation_id');
}

/**
 * Validate correlation ID format
 * @param {string} correlationId - ID to validate
 * @returns {boolean} True if valid format
 */
function isValidCorrelationId(correlationId) {
  if (!correlationId || typeof correlationId !== 'string') {
    return false;
  }
  // Match: prefix_timestamp_randomhex
  var pattern = /^[a-z]+_\d+_[a-z0-9]+$/;
  return pattern.test(correlationId);
}
