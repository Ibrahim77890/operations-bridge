Phase 01: Commands to be able to test

chmod +x agent.sh
./agent.sh help
./agent.sh health host
./agent.sh inventory host
./agent.sh something host (failure)
./agent.sh health something
./agent.sh health host | jq . (For json pretty print on terminal)


Phase 02: Commands to be able to test out

ibrahimq@DESKTOP-TGHOAVD:/mnt/e/Operations-Bridge$ ./agent.sh health host | jq .
[2026-08-14 16:22:42] [INFO] Workspace: /tmp/tmp.MgzRJghtPu
[2026-08-14 16:22:42] [INFO] Execution ID: EXEC-20260814162242-9416
[2026-08-14 16:22:42] [INFO] Running host health checks
[2026-08-14 16:22:42] [INFO] Checking memory
[2026-08-14 16:22:42] [INFO] Checking CPU
[2026-08-14 16:22:42] [INFO] Checking network
[2026-08-14 16:22:42] [INFO] Checking disk
[2026-08-14 16:22:48] [WARN] Attempt 1 failed; retrying in 1s
{
  "command": "health",
  "target": "host",
  "status": "OK",
  "checks": {
    "cpu": {
      "status": "OK",
      "value": "0.00"
    },
    "memory": {
      "status": "OK",
      "value": "10%"
    },
    "disk": {
      "status": "OK",
      "value": "2%"
    },
    "network": {
      "status": "OK"
    }
  },
  "execution_id": "EXEC-20260814162242-9416",
  "duration_ms": 10680
}



Phase 03: Bridge.sh configured
ibrahimq@DESKTOP-TGHOAVD:/mnt/e/Operations-Bridge$ curl -v \
  http://127.0.0.1:8080/execute \
  -H 'Content-Type: application/json' \
  -d '{"command":"health","target":"host","parameters":{}}'
*   Trying 127.0.0.1:8080...
* Connected to 127.0.0.1 (127.0.0.1) port 8080 (#0)
> POST /execute HTTP/1.1
> Host: 127.0.0.1:8080
> User-Agent: curl/7.81.0
> Accept: */*
> Content-Type: application/json
> Content-Length: 52
> 
* Mark bundle as not supporting multiuse
< HTTP/1.1 200 OK
< Content-Type: application/json
< Content-Length: 286
< Connection: close
< 
* Closing connection 0
{"success":true,"result":{"command":"health","target":"host","status":"OK","checks":{"cpu":{"status":"OK","value":"0.00"},"memory":{"status":"OK","value":"10%"},"disk":{"status":"OK","value":"2%"},"network":{"status":"OK"}},"execution_id":"EXEC-20260814235456-11032","duration_ms":870}}


