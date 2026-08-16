# OpsBridge Operations

## Start Locally

```bash
export OPSBRIDGE_KEY="$(openssl rand -hex 32)"
./bridge.sh
```

## Probe

```bash
curl -s http://127.0.0.1:8080/health | jq .
curl -s http://127.0.0.1:8080/ready | jq .
curl -s http://127.0.0.1:8080/metrics -H "X-OpsBridge-Key: $OPSBRIDGE_KEY" | jq .
```

## Execute

```bash
curl -s http://127.0.0.1:8080/execute \
  -H 'Content-Type: application/json' \
  -H "X-OpsBridge-Key: $OPSBRIDGE_KEY" \
  -d '{"request_id":"REQ-manual-001","command":"health","target":"host","parameters":{"timeout":"30"}}' | jq .
```

Use a unique `request_id` for every execution.
