const CONFIG = {
  SHEET_NAME: 'Commands',
  HISTORY_SHEET_NAME: 'ExecutionHistory',
  SCHEDULES_SHEET_NAME: 'Schedules',
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
  health: {
    targets: ['host'],
    parameters: {
      disk_threshold: { type: 'integer', min: 1, max: 100 },
      memory_threshold: { type: 'integer', min: 1, max: 100 }
    }
  },
  inventory: {
    targets: ['host'],
    parameters: {
      include_network: { type: 'boolean' }
    }
  },
  security: { targets: ['host'], parameters: [] },
  diagnose: {
    targets: ['host'],
    parameters: {
      cpu_threshold: { type: 'integer', min: 1, max: 100 },
      memory_threshold: { type: 'integer', min: 1, max: 100 },
      disk_threshold: { type: 'integer', min: 1, max: 100 }
    }
  }
};

const COMMON_PARAMETERS = {
  retries: { type: 'integer', min: 0, max: 5 },
  timeout: { type: 'integer', min: 1, max: 300 }
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
  sheet.getRange(2, 1, 7, 3).setValues([
    ['health', 'host', ''],
    ['inventory', 'host', ''],
    ['security', 'host', ''],
    ['diagnose', 'host', ''],
    ['health', 'host', 'disk_threshold=80'],
    ['diagnose', 'host', 'memory_threshold=90'],
    ['inventory', 'host', 'include_network=true']
  ]);
  sheet.getRange(2, CONFIG.STATUS_COLUMN, 7, 1).setValue('READY');
  sheet.autoResizeColumns(1, 8);
  initializeHistorySheet();
  initializeSchedulesSheet();
}

function initializeHistorySheet() {
  const spreadsheet = SpreadsheetApp.getActiveSpreadsheet();
  let sheet = spreadsheet.getSheetByName(CONFIG.HISTORY_SHEET_NAME);
  if (!sheet) sheet = spreadsheet.insertSheet(CONFIG.HISTORY_SHEET_NAME);

  if (sheet.getLastRow() === 0) {
    sheet.getRange(1, 1, 1, 8).setValues([[
      'Execution ID', 'Command', 'Target', 'Status', 'Started',
      'Finished', 'Duration', 'Parameters'
    ]]);
    sheet.getRange(1, 1, 1, 8).setFontWeight('bold');
    sheet.autoResizeColumns(1, 8);
  }
}

function initializeSchedulesSheet() {
  const spreadsheet = SpreadsheetApp.getActiveSpreadsheet();
  let sheet = spreadsheet.getSheetByName(CONFIG.SCHEDULES_SHEET_NAME);
  if (!sheet) sheet = spreadsheet.insertSheet(CONFIG.SCHEDULES_SHEET_NAME);

  if (sheet.getLastRow() === 0) {
    sheet.getRange(1, 1, 1, 6).setValues([[
      'Enabled', 'Command', 'Target', 'Parameters', 'Frequency', 'Last Run'
    ]]);
    sheet.getRange(1, 1, 1, 6).setFontWeight('bold');
    sheet.getRange(2, 1, 3, 6).setValues([
      [true, 'health', 'host', 'disk_threshold=80 retries=1 timeout=30', '15m', ''],
      [true, 'security', 'host', '', '6h', ''],
      [true, 'inventory', 'host', 'include_network=true', 'daily', '']
    ]);
    sheet.autoResizeColumns(1, 6);
  }
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
  sheet.getRange(row, CONFIG.STATUS_COLUMN).setValue(responseStatus(response));
  sheet.getRange(row, CONFIG.EXECUTION_ID_COLUMN).setValue(
    response.result?.execution_id || response.execution_id || ''
  );
  sheet.getRange(row, CONFIG.RESULT_COLUMN).setValue(JSON.stringify(response.result || response));
  sheet.getRange(row, CONFIG.FINISHED_AT_COLUMN).setValue(finishedAt);
}

function writeExecutionFailure(sheet, row, error, finishedAt) {
  sheet.getRange(row, CONFIG.STATUS_COLUMN).setValue(classifyFailureStatus(error));
  sheet.getRange(row, CONFIG.RESULT_COLUMN).setValue(error.message);
  sheet.getRange(row, CONFIG.FINISHED_AT_COLUMN).setValue(finishedAt);
}

function writeExecutionHistory(rowData, response, status, startedAt, finishedAt) {
  initializeHistorySheet();

  const historySheet = SpreadsheetApp
    .getActiveSpreadsheet()
    .getSheetByName(CONFIG.HISTORY_SHEET_NAME);
  const result = response?.result || {};
  const executionId = result.execution_id || response?.execution_id || '';
  const durationMs = result.duration_ms || '';

  historySheet.appendRow([
    executionId,
    rowData.command,
    rowData.target,
    status,
    startedAt,
    finishedAt,
    durationMs,
    JSON.stringify(rowData.parameters || {})
  ]);
}

function responseStatus(response) {
  if (response?.result?.status === 'TIMEOUT') return 'TIMEOUT';
  if (response?.result?.status === 'FAILED') return 'FAILED';
  return response?.success ? 'SUCCESS' : 'FAILED';
}

function classifyFailureStatus(error) {
  return /timeout|timed out/i.test(error.message) ? 'TIMEOUT' : 'FAILED';
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
  const schema = Object.assign({}, COMMON_PARAMETERS, definition?.parameters || {});
  const unknownParameters = Object.keys(parameters || {}).filter(
    parameter => !Object.prototype.hasOwnProperty.call(schema, parameter)
  );

  if (unknownParameters.length > 0) {
    throw new Error(`Unsupported parameter(s) for "${command}": ${unknownParameters.join(', ')}`);
  }

  Object.keys(parameters || {}).forEach(parameter => {
    validateParameterValue(parameter, parameters[parameter], schema[parameter]);
  });
}

function validateParameterValue(name, value, definition) {
  if (definition.type === 'integer') {
    if (!/^\d+$/.test(String(value))) throw new Error(`Parameter "${name}" must be an integer.`);

    const numberValue = Number(value);
    if (numberValue < definition.min || numberValue > definition.max) {
      throw new Error(`Parameter "${name}" must be between ${definition.min} and ${definition.max}.`);
    }
  }

  if (definition.type === 'boolean' && !['true', 'false'].includes(String(value))) {
    throw new Error(`Parameter "${name}" must be true or false.`);
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
  const payload = buildCommandPayload(rowData.command, rowData.target, rowData.parameters);
  const startedAt = new Date();

  rowData.sheet.getRange(row, CONFIG.STATUS_COLUMN).setValue('RUNNING');
  rowData.sheet.getRange(row, CONFIG.STARTED_AT_COLUMN).setValue(startedAt);
  rowData.sheet.getRange(row, CONFIG.EXECUTION_ID_COLUMN).clearContent();
  rowData.sheet.getRange(row, CONFIG.RESULT_COLUMN).clearContent();

  try {
    const response = callBridge(payload);
    const finishedAt = new Date();
    const status = responseStatus(response);

    writeExecutionResult(rowData.sheet, row, response, startedAt, finishedAt);
    writeExecutionHistory(rowData, response, status, startedAt, finishedAt);
    return response;
  } catch (error) {
    const finishedAt = new Date();
    const status = classifyFailureStatus(error);

    writeExecutionFailure(rowData.sheet, row, error, finishedAt);
    writeExecutionHistory(rowData, {}, status, startedAt, finishedAt);
    throw error;
  }
}

function executePayload(payload) {
  validateCommand(payload.command, payload.target);
  validateParameters(payload.command, payload.parameters || {});

  const startedAt = new Date();
  const rowData = {
    command: payload.command,
    target: payload.target,
    parameters: payload.parameters || {}
  };

  try {
    const response = callBridge(payload);
    const finishedAt = new Date();
    writeExecutionHistory(rowData, response, responseStatus(response), startedAt, finishedAt);
    return response;
  } catch (error) {
    const finishedAt = new Date();
    writeExecutionHistory(rowData, {}, classifyFailureStatus(error), startedAt, finishedAt);
    throw error;
  }
}

function runScheduledOperations() {
  const lock = LockService.getScriptLock();
  if (!lock.tryLock(5000)) return;

  try {
    const sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(CONFIG.SCHEDULES_SHEET_NAME);
    if (!sheet || sheet.getLastRow() < 2) return;

    const rows = sheet.getRange(2, 1, sheet.getLastRow() - 1, 6).getValues();
    const now = new Date();

    rows.forEach((row, index) => {
      const enabled = row[0] === true;
      const command = String(row[1]).trim().toLowerCase();
      const target = String(row[2]).trim().toLowerCase();
      const parameters = parseParameters(row[3]);
      const frequency = String(row[4]).trim().toLowerCase();
      const lastRun = row[5] instanceof Date ? row[5] : null;

      if (!enabled || !isScheduleDue(frequency, lastRun, now)) return;

      const payload = buildCommandPayload(command, target, parameters);
      executePayload(payload);
      sheet.getRange(index + 2, 6).setValue(now);
    });
  } finally {
    lock.releaseLock();
  }
}

function isScheduleDue(frequency, lastRun, now) {
  if (!lastRun) return true;

  const elapsedMs = now.getTime() - lastRun.getTime();
  const intervalMs = frequencyToMs(frequency);
  return elapsedMs >= intervalMs;
}

function frequencyToMs(frequency) {
  if (frequency === 'daily') return 24 * 60 * 60 * 1000;
  if (/^\d+m$/.test(frequency)) return Number(frequency.slice(0, -1)) * 60 * 1000;
  if (/^\d+h$/.test(frequency)) return Number(frequency.slice(0, -1)) * 60 * 60 * 1000;
  throw new Error(`Unsupported schedule frequency: ${frequency}`);
}

function createSchedulerTrigger() {
  ScriptApp.newTrigger('runScheduledOperations')
    .timeBased()
    .everyMinutes(15)
    .create();
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
    .addItem('Run Due Schedules', 'runScheduledOperations')
    .addItem('Create Scheduler Trigger', 'createSchedulerTrigger')
    .addSeparator()
    .addItem('Initialize Sheet', 'initializeSheet')
    .addToUi();
}

function testBridgeConnection() {
  const payload = {
    command: 'health',
    target: 'host',
    parameters: {}
  };

  const response = callBridge(payload);

  Logger.log(
    JSON.stringify(response, null, 2)
  );
}

function testTask4Commands() {
  const commands = [
    'health',
    'inventory',
    'security',
    'diagnose'
  ];

  commands.forEach(command => {
    const payload = {
      command: command,
      target: 'host',
      parameters: {}
    };

    const response = callBridge(payload);

    Logger.log(
      `${command}: ${JSON.stringify(response)}`
    );
  });
}
