# Deployment

1. Install dependencies: `bash`, `jq`, `socat`, `flock`, and `timeout`.
2. Run `sudo ./install.sh`.
3. Edit `/etc/opsbridge/opsbridge.env` and set a real `OPSBRIDGE_KEY`.
4. Run `sudo systemctl enable --now opsbridge`.
5. Confirm readiness with `curl http://127.0.0.1:8080/ready`.

Keep `OPSBRIDGE_KEY` out of Git and store it only in environment or service configuration.
