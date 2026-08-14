const CONFIG = {
  SHEET_NAME: 'Commands',

  COMMAND_COLUMN: 1,
  TARGET_COLUMN: 2,
  PARAMETERS_COLUMN: 3,

  STATUS_COLUMN: 4,
  EXECUTION_ID_COLUMN: 5,
  RESULT_COLUMN: 6,
  STARTED_AT_COLUMN: 7,
  FINISHED_AT_COLUMN: 8
};

function initializeSheet() {
  const spreadsheet = SpreadsheetApp.getActiveSpreadsheet();

  let sheet = spreadsheet.getSheetByName(CONFIG.SHEET_NAME);

  if (!sheet) {
    sheet = spreadsheet.insertSheet(CONFIG.SHEET_NAME);
  }

  sheet.clear();

  sheet.getRange(1, 1, 1, 8).setValues([[
    'Command',
    'Target',
    'Parameters',
    'Status',
    'Execution ID',
    'Result',
    'Started At',
    'Finished At'
  ]]);

  sheet.getRange(1, 1, 1, 8).setFontWeight('bold');

  sheet.getRange(2, 1, 2, 3).setValues([
    ['health', 'host', ''],
    ['inventory', 'host', '']
  ]);

  sheet.autoResizeColumns(1, 8);
}

function parseParameters(input) {
  const parameters = {};

  if (!input || !String(input).trim()) {
    return parameters;
  }

  const tokens = String(input).trim().split(/\s+/);

  tokens.forEach(token => {
    const separator = token.indexOf('=');

    if (separator === -1) {
      throw new Error(
        `Invalid parameter "${token}". Expected key=value.`
      );
    }

    const key = token.substring(0, separator).trim();
    const value = token.substring(separator + 1).trim();

    if (!key) {
      throw new Error(`Invalid parameter "${token}".`);
    }

    parameters[key] = value;
  });

  return parameters;
}

const COMMANDS = {
  health: {
    targets: ['host']
  },

  inventory: {
    targets: ['host']
  }
};

function validateCommand(command, target) {
  const definition = COMMANDS[command];

  if (!definition) {
    throw new Error(`Unsupported command: ${command}`);
  }

  if (!definition.targets.includes(target)) {
    throw new Error(
      `Target "${target}" is not allowed for command "${command}".`
    );
  }
}


initializeSheet()
parseParameters('branch=main env=staging')

function executeCommand(command, target, parameters) {
  validateCommand(command, target);

  const payload = {
    command: command,
    target: target,
    parameters: parameters
  };

  const options = {
    method: 'post',

    contentType: 'application/json',

    payload: JSON.stringify(payload),

    muteHttpExceptions: true,

    headers: {
      'X-OpsBridge-Key': getBridgeKey()
    }
  };

  const response = UrlFetchApp.fetch(
    getBridgeUrl(),
    options
  );

  const statusCode = response.getResponseCode();

  const body = response.getContentText();

  if (statusCode < 200 || statusCode >= 300) {
    throw new Error(
      `Bridge returned HTTP ${statusCode}: ${body}`
    );
  }

  return JSON.parse(body);
}

function getBridgeUrl() {
  const properties =
    PropertiesService.getScriptProperties();

  const url = properties.getProperty('BRIDGE_URL');

  if (!url) {
    throw new Error('BRIDGE_URL is not configured.');
  }

  return url;
}

function getBridgeUrl() {
  const properties =
    PropertiesService.getScriptProperties();

  const url = properties.getProperty('BRIDGE_URL');

  if (!url) {
    throw new Error('BRIDGE_URL is not configured.');
  }

  return url;
}

function executeSelectedRow(row) {
  const sheet =
    SpreadsheetApp
      .getActiveSpreadsheet()
      .getSheetByName(CONFIG.SHEET_NAME);

  if (!sheet) {
    throw new Error(
      `Sheet "${CONFIG.SHEET_NAME}" does not exist.`
    );
  }

  const command =
    String(
      sheet.getRange(row, CONFIG.COMMAND_COLUMN).getValue()
    ).trim();

  const target =
    String(
      sheet.getRange(row, CONFIG.TARGET_COLUMN).getValue()
    ).trim();

  const parameterString =
    String(
      sheet.getRange(row, CONFIG.PARAMETERS_COLUMN).getValue()
    ).trim();

  if (!command) {
    throw new Error(`Row ${row}: command is required.`);
  }

  if (!target) {
    throw new Error(`Row ${row}: target is required.`);
  }

  const parameters =
    parseParameters(parameterString);

  const startedAt = new Date();

  sheet
    .getRange(row, CONFIG.STATUS_COLUMN)
    .setValue('RUNNING');

  sheet
    .getRange(row, CONFIG.STARTED_AT_COLUMN)
    .setValue(startedAt);

  try {
    const response =
      executeCommand(
        command,
        target,
        parameters
      );

    const finishedAt = new Date();

    sheet
      .getRange(row, CONFIG.STATUS_COLUMN)
      .setValue(
        response.success ? 'SUCCESS' : 'FAILED'
      );

    sheet
      .getRange(row, CONFIG.EXECUTION_ID_COLUMN)
      .setValue(
        response.execution_id || ''
      );

    sheet
      .getRange(row, CONFIG.RESULT_COLUMN)
      .setValue(
        JSON.stringify(response.result || response)
      );

    sheet
      .getRange(row, CONFIG.FINISHED_AT_COLUMN)
      .setValue(finishedAt);

  } catch (error) {

    const finishedAt = new Date();

    sheet
      .getRange(row, CONFIG.STATUS_COLUMN)
      .setValue('FAILED');

    sheet
      .getRange(row, CONFIG.RESULT_COLUMN)
      .setValue(error.message);

    sheet
      .getRange(row, CONFIG.FINISHED_AT_COLUMN)
      .setValue(finishedAt);

    throw error;
  }
}


function onOpen() {
  SpreadsheetApp
    .getUi()
    .createMenu('OpsBridge')
    .addItem(
      'Execute Selected Row',
      'executeActiveRow'
    )
    .addItem(
      'Initialize Sheet',
      'initializeSheet'
    )
    .addToUi();
}

function executeActiveRow() {
  const sheet =
    SpreadsheetApp
      .getActiveSpreadsheet()
      .getActiveSheet();

  const row = sheet.getActiveRange().getRow();

  if (row <= 1) {
    throw new Error(
      'Select a command row, not the header.'
    );
  }

  executeSelectedRow(row);
}

