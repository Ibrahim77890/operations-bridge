# OpsBridge Threat Model

## Assets

- `OPSBRIDGE_KEY`, used to authorize bridge calls.
- Local host execution capability exposed by `agent.sh`.
- Execution results, metrics, and security audit records.
- Google Sheets command and execution history data.

## Trust Boundaries

- Google Apps Script to HTTP bridge.
- HTTP bridge to Bash agent.
- Bash agent to local host tools.
- Runtime files under `OPSBRIDGE_RUNTIME_DIR`.

## Controls

- `X-OpsBridge-Key` is required for `/execute` and `/metrics`.
- `/execute` accepts only allowlisted command and target pairs.
- Request bodies, headers, command names, target names, parameters, and agent output are bounded.
- Parameters are validated as data and are never evaluated as shell code.
- `request_id` is required and rejected when replayed within the replay window.
- Rate limiting protects the bridge from repeated calls.
- Runtime files are created under a private directory with restrictive permissions where possible.
- Security audit events are written as JSON lines.

## Fail-Closed Behavior

Missing key, malformed JSON, invalid parameters, replayed request IDs, unsupported commands, oversized input, and rate-limit violations return controlled JSON errors and do not execute the agent.
