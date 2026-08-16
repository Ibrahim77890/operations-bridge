# Recovery

## Bridge Will Not Start

Run:

```bash
./scripts/doctor.sh
```

Then check:

```bash
systemctl status opsbridge
journalctl -u opsbridge -n 100 --no-pager
```

## Unauthorized Requests

- Confirm the running bridge process was started with the same `OPSBRIDGE_KEY`.
- Confirm Apps Script `BRIDGE_KEY` matches the bridge key.
- Confirm the request includes `X-OpsBridge-Key`.

## Replay Rejections

Generate a new `request_id` for every `/execute` request.
