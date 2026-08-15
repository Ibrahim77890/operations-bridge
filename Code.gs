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
  BRIDGE_TIMEOUT_MS: 30000
};

const COMMANDS = {
  health: { targets: ['host'], parameters: [] },
  inventory: { targets: ['host'], parameters: [] },
  security: { targets: ['host'], parameters: [] }
};

function initializeSheet() {
  const spreadsheet = SpreadsheetApp.getActiveSpreadsheet();
  let sheet = spreadsheet.getSheetByName(CONFIG.SHEET_NAME);
  if (!sheet) sheet = spreadsheet.insertSheet(CONFIG.SHEET_NAME);

  sheet.clear();
  sheet.getRange(1, 1, 1, 8).setValues([[
    'Command', 'Target', 'Parameters', 'Status', 'Execution ID',
    'Result', 'Started At', 'Finished At'
  ]]);
  sheet.getRange(1, 1, 1, 8).setFontWeight('bold');
  sheet.getRange(2, 1, 3, 3).setValues([
    ['health', 'host', ''],
    ['inventory', 'host', ''],
    ['security', 'host', '']
  ]);
  sheet.autoResizeColumns(1, 8);
}

function getCommandsSheet() {
  const sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(CONFIG.SHEET_NAME);
  if (!sheet) throw new Error(`Sheet "${CONFIG.SHEET_NAME}" does not exist.`);
  return sheet;
}

function readCommandRow(row) {
  const sheet = getCommandsSheet();
  validateRow(row);

  const command = String(sheet.getRange(row, CONFIG.COMMAND_COLUMN).getValue()).trim().toLowerCase();
  const target = String(sheet.getRange(row, CONFIG.TARGET_COLUMN).getValue()).trim().toLowerCase();
  const parameterString = String(sheet.getRange(row, CONFIG.PARAMETERS_COLUMN).getValue()).trim();

  if (!command) throw new Error(`Row ${row}: command is required.`);
  if (!target) throw new Error(`Row ${row}: target is required.`);

  return { sheet, row, command, target, parameters: parseParameters(parameterString) };
}

function writeExecutionResult(sheet, row, response, startedAt, finishedAt) {
  sheet.getRange(row, CONFIG.STATUS_COLUMN).setValue(response.success ? 'SUCCESS' : 'FAILED');
  sheet.getRange(row, CONFIG.EXECUTION_ID_COLUMN).setValue(
    response.result?.execution_id || response.execution_id || ''
  );
  sheet.getRange(row, CONFIG.RESULT_COLUMN).setValue(JSON.stringify(response.result || response));
  sheet.getRange(row, CONFIG.FINISHED_AT_COLUMN).setValue(finishedAt);
}

function writeExecutionFailure(sheet, row, error, finishedAt) {
  sheet.getRange(row, CONFIG.STATUS_COLUMN).setValue('FAILED');
  sheet.getRange(row, CONFIG.RESULT_COLUMN).setValue(error.message);
  sheet.getRange(row, CONFIG.FINISHED_AT_COLUMN).setValue(finishedAt);
}

function validateRow(row) {
  if (!Number.isInteger(row) || row < 2) {
    throw new Error('Select a valid command row below the header.');
  }
}

function parseParameters(input) {
  const parameters = {};
  if (!input || !String(input).trim()) return parameters;

  String(input).trim().split(/\s+/).forEach(token => {
    const separator = token.indexOf('=');
    if (separator === -1) throw new Error(`Invalid parameter "${token}". Expected key=value.`);

    const key = token.substring(0, separator).trim().toLowerCase();
    const value = token.substring(separator + 1).trim();
    if (!key) throw new Error(`Invalid parameter "${token}".`);
    if (!value) throw new Error(`Parameter "${key}" must have a value.`);
    parameters[key] = value;
  });

  return parameters;
}

function validateCommand(command, target) {
  const definition = COMMANDS[command];
  if (!definition) throw new Error(`Unsupported command: ${command}`);
  if (!definition.targets.includes(target)) {
    throw new Error(`Target "${target}" is not allowed for command "${command}".`);
  }
}

function validateParameters(command, parameters) {
  const definition = COMMANDS[command];
  const allowedParameters = definition?.parameters || [];
  const unknownParameters = Object.keys(parameters || {}).filter(
    parameter => !allowedParameters.includes(parameter)
  );

  if (unknownParameters.length > 0) {
    throw new Error(`Unsupported parameter(s) for "${command}": ${unknownParameters.join(', ')}`);
  }
}

function buildCommandPayload(command, target, parameters) {
  const normalizedParameters = parameters || {};
  validateCommand(command, target);
  validateParameters(command, normalizedParameters);
  return { command, target, parameters: normalizedParameters };
}

function getBridgeUrl() {
  const url = PropertiesService.getScriptProperties().getProperty('BRIDGE_URL');
  if (!url) throw new Error('BRIDGE_URL is not configured.');
  return url;
}

function getBridgeKey() {
  const key = PropertiesService.getScriptProperties().getProperty('BRIDGE_KEY');
  if (!key) throw new Error('BRIDGE_KEY is not configured.');
  return key;
}

function callBridge(payload) {
  const options = {
    method: 'post',
    contentType: 'application/json',
    payload: JSON.stringify(payload),
    headers: { 'X-OpsBridge-Key': getBridgeKey() },
    muteHttpExceptions: true,
    followRedirects: false
  };

  let response;
  try {
    response = UrlFetchApp.fetch(getBridgeUrl(), options);
  } catch (error) {
    throw new Error(`Unable to reach OpsBridge: ${error.message}`);
  }

  const statusCode = response.getResponseCode();
  const body = response.getContentText();
  let data;

  try {
    data = JSON.parse(body);
  } catch (error) {
    throw new Error(`Bridge returned invalid JSON. HTTP ${statusCode}: ${body}`);
  }

  if (statusCode < 200 || statusCode >= 300) {
    throw new Error(`Bridge HTTP ${statusCode}: ${data.error || body}`);
  }

  return data;
}

function previewSelectedRow(row) {
  const rowData = readCommandRow(row);
  const payload = buildCommandPayload(rowData.command, rowData.target, rowData.parameters);

  rowData.sheet.getRange(row, CONFIG.STATUS_COLUMN).setValue('READY');
  rowData.sheet.getRange(row, CONFIG.EXECUTION_ID_COLUMN).clearContent();
  rowData.sheet.getRange(row, CONFIG.RESULT_COLUMN).setValue(JSON.stringify(payload));
  rowData.sheet.getRange(row, CONFIG.STARTED_AT_COLUMN).clearContent();
  rowData.sheet.getRange(row, CONFIG.FINISHED_AT_COLUMN).clearContent();
  return payload;
}

function executeSelectedRow(row) {
  const rowData = readCommandRow(row);
  const startedAt = new Date();

  rowData.sheet.getRange(row, CONFIG.STATUS_COLUMN).setValue('RUNNING');
  rowData.sheet.getRange(row, CONFIG.STARTED_AT_COLUMN).setValue(startedAt);
  rowData.sheet.getRange(row, CONFIG.EXECUTION_ID_COLUMN).clearContent();
  rowData.sheet.getRange(row, CONFIG.RESULT_COLUMN).clearContent();

  try {
    const payload = buildCommandPayload(rowData.command, rowData.target, rowData.parameters);
    const response = callBridge(payload);
    const finishedAt = new Date();
    writeExecutionResult(rowData.sheet, row, response, startedAt, finishedAt);
    return response;
  } catch (error) {
    const finishedAt = new Date();
    writeExecutionFailure(rowData.sheet, row, error, finishedAt);
    throw error;
  }
}

function getActiveCommandRow() {
  const sheet = SpreadsheetApp.getActiveSpreadsheet().getActiveSheet();
  if (sheet.getName() !== CONFIG.SHEET_NAME) {
    throw new Error(`Select a row on the "${CONFIG.SHEET_NAME}" sheet.`);
  }

  const activeRange = sheet.getActiveRange();
  if (!activeRange) throw new Error('Select a command row.');

  const row = activeRange.getRow();
  validateRow(row);
  return row;
}

function previewActiveRow() {
  return previewSelectedRow(getActiveCommandRow());
}

function executeActiveRow() {
  return executeSelectedRow(getActiveCommandRow());
}

function onOpen() {
  SpreadsheetApp.getUi()
    .createMenu('OpsBridge')
    .addItem('Preview Selected Row', 'previewActiveRow')
    .addItem('Execute Selected Row', 'executeActiveRow')
    .addSeparator()
    .addItem('Initialize Sheet', 'initializeSheet')
    .addToUi();
}
