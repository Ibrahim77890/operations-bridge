# Operations Bridge

OpsBridge is a small Bash operations engine exposed through an authenticated HTTP bridge and controlled from Google Apps Script.

## Commands

```bash
./agent.sh help
./agent.sh health host
./agent.sh inventory host
./agent.sh security host
./agent.sh diagnose host
./agent.sh health host "disk_threshold=80 retries=1 timeout=30"
./agent.sh diagnose host "memory_threshold=90 timeout=30"
./agent.sh inventory host "include_network=false"
```

Pretty-print a result:

```bash
./agent.sh diagnose host | jq .
```

## Structure

```text
agent.sh
bridge.sh
lib/
  logging.sh
  json.sh
  validation.sh
  system.sh
  network.sh
  security.sh
commands/
  health.sh
  inventory.sh
  security.sh
  diagnose.sh
tests/
  test_health.sh
  test_inventory.sh
  test_security.sh
  test_diagnose.sh
  test_bridge.sh
```

## Bridge

Start the bridge with a secret key:

```bash
export OPSBRIDGE_KEY="$(openssl rand -hex 32)"
./bridge.sh
```

Call it locally:

```bash
curl -i http://127.0.0.1:8080/execute \
  -H 'Content-Type: application/json' \
  -H "X-OpsBridge-Key: $OPSBRIDGE_KEY" \
  -d '{"request_id":"REQ-manual-001","command":"diagnose","target":"host","parameters":{}}'
```

Each `/execute` request must use a unique `request_id`. Reusing a request ID inside the replay window is rejected.

Operational endpoints:

```bash
curl -s http://127.0.0.1:8080/health | jq .
curl -s http://127.0.0.1:8080/ready | jq .
curl -s http://127.0.0.1:8080/metrics \
  -H "X-OpsBridge-Key: $OPSBRIDGE_KEY" | jq .
```

## Tests

Run tests one at a time because the agent uses an exclusive execution lock:

```bash
bash tests/test_health.sh
bash tests/test_inventory.sh
bash tests/test_security.sh
bash tests/test_diagnose.sh
bash tests/test_bridge.sh
bash tests/test_parameters.sh
bash tests/test_reliability.sh
bash tests/test_concurrency.sh
bash tests/test_hardening.sh
```

## Scheduling

Apps Script creates three sheets:

- `Commands`: on-demand operations.
- `ExecutionHistory`: audit log of attempted executions.
- `Schedules`: recurring operations.
- `SecurityAudit`: Apps-side execution and transport failures.
- `Dashboard`: summary view of total, successful, failed, and timed-out executions.

Use the OpsBridge menu in Google Sheets:

- `Run Due Schedules` executes due rows in `Schedules`.
- `Create Scheduler Trigger` installs a 15-minute Apps Script trigger.
- `Update Dashboard` refreshes execution counters.

Apps Script uses `LockService.getScriptLock()` to prevent duplicate scheduled runs while the Bash agent still enforces its own execution lock.

## Production Files

- `config/defaults.env`: non-secret runtime defaults.
- `.env.example`: template for secret environment configuration.
- `deploy/opsbridge.service`: systemd unit for Linux deployment.
- `install.sh`: installs files, service user, and systemd unit.
- `uninstall.sh`: removes the systemd service while preserving config and installed files.
- `scripts/doctor.sh`: checks bridge dependencies and runs an agent smoke test.
- `docs/`: threat model, architecture, operations, deployment, and recovery notes.
