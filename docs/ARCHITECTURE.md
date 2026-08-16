# OpsBridge Architecture

OpsBridge has four runtime layers:

1. Google Apps Script reads command rows, validates input, and writes execution history.
2. `bridge.sh` authenticates HTTP requests, enforces request controls, and calls the agent.
3. `agent.sh` validates command parameters, applies timeout and retry policy, and dispatches commands.
4. `commands/*.sh` collect host health, inventory, security, and diagnostic data as structured JSON.

The command allowlist exists in Apps Script, the bridge, and the agent. That repetition is deliberate defense in depth.
