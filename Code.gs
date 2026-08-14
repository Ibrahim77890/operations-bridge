/**
 * ============================================================
 * OpsBridge — Google Apps Script Control Plane
 * Task 3A
 * ============================================================
 *
 * Responsibilities:
 *   - Manage the Commands sheet
 *   - Read command rows
 *   - Parse parameters
 *   - Normalize input
 *   - Validate commands
 *   - Validate targets
 *   - Validate parameters
 *   - Build a safe JSON command payload
 *   - Preview commands
 *   - Prepare execution flow for Task 3B
 *
 * Task 3A DOES NOT execute Bash yet.
 * The HTTP bridge will be implemented in Task 3B.
 * ============================================================
 */


/* ============================================================
 * CONFIGURATION
 * ============================================================
 */

const CONFIG = {
  SHEET_NAME: 'Commands',

  COMMAND_COLUMN: 1,
  TARGET_COLUMN: 2,
  PARAMETERS_COLUMN: 3,

  STATUS_COLUMN: 4,
  EXECUTION_ID_COLUMN: 5,
  RESULT_COLUMN: 6,
  STARTED_AT_COLUMN: 7,
  FINISHED_AT_COLUMN: 8,

  HEADER_ROW: 1,
  FIRST_COMMAND_ROW: 2
};


/* ============================================================
 * COMMAND REGISTRY
 * ============================================================
 *
 * This is the security boundary for the control plane.
 *
 * A command must explicitly exist here.
 * A target must explicitly be allowed.
 * A parameter must explicitly be allowed.
 *
 * Do NOT allow arbitrary shell commands to come through
 * the spreadsheet.
 */

const COMMANDS = {

  health: {
    targets: ['host'],
    parameters: []
  },

  inventory: {
    targets: ['host'],
    parameters: []
  }

  /*
   * Future examples:
   *
   * test: {
   *   targets: ['my-api'],
   *   parameters: ['branch']
   * },
   *
   * deploy: {
   *   targets: ['my-api'],
   *   parameters: ['env']
   * }
   */
};


/* ============================================================
 * SHEET INITIALIZATION
 * ============================================================
 */

function initializeSheet() {

  const spreadsheet =
    SpreadsheetApp.getActiveSpreadsheet();

  let sheet =
    spreadsheet.getSheetByName(CONFIG.SHEET_NAME);

  if (!sheet) {
    sheet =
      spreadsheet.insertSheet(CONFIG.SHEET_NAME);
  }

  /*
   * WARNING:
   * This resets the Commands sheet.
   *
   * During development this is convenient.
   * Later we should replace this with a non-destructive
   * initialization routine.
   */

  sheet.clear();

  sheet
    .getRange(1, 1, 1, 8)
    .setValues([[
      'Command',
      'Target',
      'Parameters',
      'Status',
      'Execution ID',
      'Result',
      'Started At',
      'Finished At'
    ]]);

  sheet
    .getRange(1, 1, 1, 8)
    .setFontWeight('bold');

  /*
   * Example commands.
   */

  sheet
    .getRange(2, 1, 2, 3)
    .setValues([
      ['health', 'host', ''],
      ['inventory', 'host', '']
    ]);

  sheet.autoResizeColumns(1, 8);
}


/* ============================================================
 * PARAMETER PARSER
 * ============================================================
 *
 * Input:
 *
 *   branch=main env=staging
 *
 * Output:
 *
 *   {
 *     branch: "main",
 *     env: "staging"
 *   }
 *
 * Current syntax intentionally remains simple:
 *
 *   key=value key=value
 *
 * Values containing spaces are not supported yet.
 */

function parseParameters(input) {

  const parameters = {};

  if (!input || !String(input).trim()) {
    return parameters;
  }

  const tokens =
    String(input)
      .trim()
      .split(/\s+/);

  tokens.forEach(function(token) {

    const separator =
      token.indexOf('=');

    if (separator === -1) {
      throw new Error(
        `Invalid parameter "${token}". Expected key=value.`
      );
    }

    const key =
      token
        .substring(0, separator)
        .trim()
        .toLowerCase();

    const value =
      token
        .substring(separator + 1)
        .trim();

    if (!key) {
      throw new Error(
        `Invalid parameter "${token}".`
      );
    }

    if (!value) {
      throw new Error(
        `Parameter "${key}" must have a value.`
      );
    }

    parameters[key] = value;
  });

  return parameters;
}


/* ============================================================
 * COMMAND VALIDATION
 * ============================================================
 */

function validateCommand(command, target) {

  const definition =
    COMMANDS[command];

  /*
   * Check command exists.
   */

  if (!definition) {
    throw new Error(
      `Unsupported command: ${command}`
    );
  }

  /*
   * Check target is explicitly allowed.
   */

  if (!definition.targets.includes(target)) {

    throw new Error(
      `Target "${target}" is not allowed for command "${command}".`
    );
  }
}


/* ============================================================
 * PARAMETER VALIDATION
 * ============================================================
 */

function validateParameters(command, parameters) {

  const definition =
    COMMANDS[command];

  if (!definition) {
    throw new Error(
      `Unsupported command: ${command}`
    );
  }

  const allowedParameters =
    definition.parameters || [];

  const suppliedParameters =
    Object.keys(parameters || {});

  /*
   * Find parameters that aren't explicitly allowed.
   */

  const unknownParameters =
    suppliedParameters.filter(function(parameter) {

      return !allowedParameters.includes(parameter);

    });

  if (unknownParameters.length > 0) {

    throw new Error(
      `Unsupported parameter(s) for "${command}": ` +
      unknownParameters.join(', ')
    );
  }
}


/* ============================================================
 * BUILD COMMAND PAYLOAD
 * ============================================================
 */

function buildCommandPayload(
  command,
  target,
  parameters
) {

  /*
   * Validate command + target.
   */

  validateCommand(
    command,
    target
  );

  const normalizedParameters =
    parameters || {};

  /*
   * Validate parameters.
   */

  validateParameters(
    command,
    normalizedParameters
  );

  /*
   * Return the canonical payload.
   */

  return {
    command: command,
    target: target,
    parameters: normalizedParameters
  };
}


/* ============================================================
 * READ COMMAND ROW
 * ============================================================
 */

function readCommandRow(row) {

  const sheet =
    SpreadsheetApp
      .getActiveSpreadsheet()
      .getSheetByName(CONFIG.SHEET_NAME);

  if (!sheet) {

    throw new Error(
      `Sheet "${CONFIG.SHEET_NAME}" does not exist.`
    );
  }

  validateRow(row);

  /*
   * Read command.
   */

  const command =
    String(
      sheet
        .getRange(
          row,
          CONFIG.COMMAND_COLUMN
        )
        .getValue()
    )
      .trim()
      .toLowerCase();

  /*
   * Read target.
   */

  const target =
    String(
      sheet
        .getRange(
          row,
          CONFIG.TARGET_COLUMN
        )
        .getValue()
    )
      .trim()
      .toLowerCase();

  /*
   * Read parameter string.
   */

  const parameterString =
    String(
      sheet
        .getRange(
          row,
          CONFIG.PARAMETERS_COLUMN
        )
        .getValue()
    )
      .trim();

  /*
   * Required fields.
   */

  if (!command) {

    throw new Error(
      `Row ${row}: command is required.`
    );
  }

  if (!target) {

    throw new Error(
      `Row ${row}: target is required.`
    );
  }

  /*
   * Parse parameters.
   */

  const parameters =
    parseParameters(parameterString);

  return {
    sheet: sheet,
    row: row,
    command: command,
    target: target,
    parameters: parameters
  };
}


/* ============================================================
 * ROW VALIDATION
 * ============================================================
 */

function validateRow(row) {

  if (
    !Number.isInteger(row) ||
    row < CONFIG.FIRST_COMMAND_ROW
  ) {

    throw new Error(
      'Select a valid command row below the header.'
    );
  }
}


/* ============================================================
 * PREVIEW SELECTED ROW
 * ============================================================
 *
 * This function does NOT contact the Bash bridge.
 *
 * It only:
 *
 *   1. Reads the row
 *   2. Parses parameters
 *   3. Validates everything
 *   4. Creates the JSON payload
 *   5. Displays the payload in the sheet
 */

function previewSelectedRow(row) {

  const rowData =
    readCommandRow(row);

  const payload =
    buildCommandPayload(
      rowData.command,
      rowData.target,
      rowData.parameters
    );

  /*
   * Mark the command as ready.
   */

  rowData.sheet
    .getRange(
      row,
      CONFIG.STATUS_COLUMN
    )
    .setValue('READY');

  /*
   * Preview does not have an execution ID.
   */

  rowData.sheet
    .getRange(
      row,
      CONFIG.EXECUTION_ID_COLUMN
    )
    .clearContent();

  /*
   * Display JSON payload.
   */

  rowData.sheet
    .getRange(
      row,
      CONFIG.RESULT_COLUMN
    )
    .setValue(
      JSON.stringify(payload)
    );

  /*
   * Preview isn't an execution,
   * so there are no execution timestamps.
   */

  rowData.sheet
    .getRange(
      row,
      CONFIG.STARTED_AT_COLUMN
    )
    .clearContent();

  rowData.sheet
    .getRange(
      row,
      CONFIG.FINISHED_AT_COLUMN
    )
    .clearContent();

  return payload;
}


/* ============================================================
 * GET ACTIVE COMMAND ROW
 * ============================================================
 */

function getActiveCommandRow() {

  const sheet =
    SpreadsheetApp
      .getActiveSpreadsheet()
      .getActiveSheet();

  /*
   * Make sure the user is working on Commands.
   */

  if (
    sheet.getName() !==
    CONFIG.SHEET_NAME
  ) {

    throw new Error(
      `Select a row on the "${CONFIG.SHEET_NAME}" sheet.`
    );
  }

  const activeRange =
    sheet.getActiveRange();

  if (!activeRange) {

    throw new Error(
      'Select a command row.'
    );
  }

  const row =
    activeRange.getRow();

  validateRow(row);

  return row;
}


/* ============================================================
 * PREVIEW ACTIVE ROW
 * ============================================================
 */

function previewActiveRow() {

  const row =
    getActiveCommandRow();

  return previewSelectedRow(row);
}


/* ============================================================
 * BRIDGE CONFIGURATION
 * ============================================================
 *
 * These functions are intentionally present now so the
 * control-plane architecture is ready for Task 3B.
 *
 * DO NOT configure them yet unless the bridge exists.
 */

function getBridgeUrl() {

  const properties =
    PropertiesService
      .getScriptProperties();

  const url =
    properties.getProperty(
      'BRIDGE_URL'
    );

  if (!url) {

    throw new Error(
      'BRIDGE_URL is not configured.'
    );
  }

  return url;
}


function getBridgeKey() {

  const properties =
    PropertiesService
      .getScriptProperties();

  const key =
    properties.getProperty(
      'BRIDGE_KEY'
    );

  if (!key) {

    throw new Error(
      'BRIDGE_KEY is not configured.'
    );
  }

  return key;
}


/* ============================================================
 * SEND COMMAND TO BRIDGE
 * ============================================================
 *
 * TASK 3B / 3C
 *
 * This function should NOT be expected to work yet.
 *
 * It will eventually:
 *
 *   Apps Script
 *       ↓
 *   HTTPS
 *       ↓
 *   Bash bridge
 *       ↓
 *   agent.sh
 */

function sendCommandToBridge(
  command,
  target,
  parameters
) {

  const payload =
    buildCommandPayload(
      command,
      target,
      parameters
    );

  const options = {

    method: 'post',

    contentType:
      'application/json',

    payload:
      JSON.stringify(payload),

    muteHttpExceptions:
      true,

    headers: {
      'X-OpsBridge-Key':
        getBridgeKey()
    }
  };

  const response =
    UrlFetchApp.fetch(
      getBridgeUrl(),
      options
    );

  const statusCode =
    response.getResponseCode();

  const body =
    response.getContentText();

  if (
    statusCode < 200 ||
    statusCode >= 300
  ) {

    throw new Error(
      `Bridge returned HTTP ${statusCode}: ${body}`
    );
  }

  let parsed;

  try {

    parsed =
      JSON.parse(body);

  } catch (error) {

    throw new Error(
      `Bridge returned invalid JSON: ${body}`
    );
  }

  return parsed;
}


/* ============================================================
 * EXECUTE SELECTED ROW
 * ============================================================
 *
 * This function is wired for the future bridge.
 *
 * Until Task 3B/3C is implemented, executing a row will
 * fail because BRIDGE_URL / BRIDGE_KEY aren't configured.
 */

function executeSelectedRow(row) {

  const rowData =
    readCommandRow(row);

  /*
   * Validate everything BEFORE changing the status.
   */

  const payload =
    buildCommandPayload(
      rowData.command,
      rowData.target,
      rowData.parameters
    );

  const startedAt =
    new Date();

  /*
   * Mark as running.
   */

  rowData.sheet
    .getRange(
      row,
      CONFIG.STATUS_COLUMN
    )
    .setValue('RUNNING');

  rowData.sheet
    .getRange(
      row,
      CONFIG.STARTED_AT_COLUMN
    )
    .setValue(startedAt);

  try {

    /*
     * Task 3B/3C will connect this to the Bash bridge.
     */

    const response =
      sendCommandToBridge(
        payload.command,
        payload.target,
        payload.parameters
      );

    const finishedAt =
      new Date();

    /*
     * Determine result status.
     */

    rowData.sheet
      .getRange(
        row,
        CONFIG.STATUS_COLUMN
      )
      .setValue(
        response.success
          ? 'SUCCESS'
          : 'FAILED'
      );

    /*
     * Store execution ID.
     */

    rowData.sheet
      .getRange(
        row,
        CONFIG.EXECUTION_ID_COLUMN
      )
      .setValue(
        response.execution_id || ''
      );

    /*
     * Store result.
     */

    rowData.sheet
      .getRange(
        row,
        CONFIG.RESULT_COLUMN
      )
      .setValue(
        JSON.stringify(
          response.result || response
        )
      );

    /*
     * Store finish timestamp.
     */

    rowData.sheet
      .getRange(
        row,
        CONFIG.FINISHED_AT_COLUMN
      )
      .setValue(
        finishedAt
      );

    return response;

  } catch (error) {

    const finishedAt =
      new Date();

    /*
     * Record failure in Sheet.
     */

    rowData.sheet
      .getRange(
        row,
        CONFIG.STATUS_COLUMN
      )
      .setValue('FAILED');

    rowData.sheet
      .getRange(
        row,
        CONFIG.RESULT_COLUMN
      )
      .setValue(
        error.message
      );

    rowData.sheet
      .getRange(
        row,
        CONFIG.FINISHED_AT_COLUMN
      )
      .setValue(
        finishedAt
      );

    /*
     * Keep the Apps Script execution marked as failed
     * during development so the error is visible in the
     * execution log.
     */

    throw error;
  }
}


/* ============================================================
 * EXECUTE ACTIVE ROW
 * ============================================================
 */

function executeActiveRow() {

  const row =
    getActiveCommandRow();

  return executeSelectedRow(row);
}


/* ============================================================
 * GOOGLE SHEETS MENU
 * ============================================================
 */

function onOpen() {

  SpreadsheetApp
    .getUi()
    .createMenu('OpsBridge')

    .addItem(
      'Preview Selected Row',
      'previewActiveRow'
    )

    .addItem(
      'Execute Selected Row',
      'executeActiveRow'
    )

    .addSeparator()

    .addItem(
      'Initialize Sheet',
      'initializeSheet'
    )

    .addToUi();
}