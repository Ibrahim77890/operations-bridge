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
  -d '{"command":"diagnose","target":"host","parameters":{}}'
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
```

## Scheduling

Apps Script creates three sheets:

- `Commands`: on-demand operations.
- `ExecutionHistory`: audit log of attempted executions.
- `Schedules`: recurring operations.

Use the OpsBridge menu in Google Sheets:

- `Run Due Schedules` executes due rows in `Schedules`.
- `Create Scheduler Trigger` installs a 15-minute Apps Script trigger.

Apps Script uses `LockService.getScriptLock()` to prevent duplicate scheduled runs while the Bash agent still enforces its own execution lock.







Phase 04:
chmod +x agent.sh bridge.sh
./agent.sh health host | jq .
./agent.sh inventory host | jq .
./agent.sh security host | jq .
./agent.sh diagnose host | jq .

for cmd in health inventory security diagnose; do
    echo "Testing $cmd"

    ./agent.sh "$cmd" host |
        jq empty

    if [[ $? -eq 0 ]]; then
        echo "PASS: $cmd returned valid JSON"
    else
        echo "FAIL: $cmd returned invalid JSON"
    fi
done

