# Health Check Timeouts

**Symptom:** "App deployed but health checks timed out" or "Cloud Run instance failed to start."

## What Are Health Checks?

Cloud Run sends HTTP requests to your app every few seconds:

```
Cloud Run: GET http://localhost:8080/
Your App: (should respond within 5 seconds)
```

If your app doesn't respond quickly enough (3 consecutive failures), the instance is marked unhealthy and restarted.

## Why Do They Fail?

| Reason | Solution |
|--------|----------|
| App doesn't listen on `$PORT` | Change app to listen on env var `$PORT` (default 8080) |
| App takes >5 minutes to start | Reduce startup time or use startup CPU boost |
| App crashes on startup | Check logs: `gcloud run logs read APP_NAME` |
| App listens on wrong port | Change from 8080 to actual port in code |
| Wrong entrypoint | Verify `CMD` or entrypoint in Dockerfile |

## Debugging

### 1. Check Logs
```bash
gcloud run logs read zilch-reference-app --region=us-central1 --limit=50
```

Look for:
- Port binding errors: "Address already in use"
- Import errors: "ModuleNotFoundError"
- Startup failures: Crash traces

Example healthy log:
```
Listening on :8080
2026-06-15T10:30:45.123Z startup complete
```

Example unhealthy log:
```
Error: listen EACCES: permission denied 0.0.0.0:8080
```

### 2. Test Locally
Build and run your container locally to test startup:

```bash
docker build -t myapp .
docker run -p 8080:8080 myapp
```

Visit `http://localhost:8080` — should respond immediately.

### 3. Check Dockerfile
Ensure your `Dockerfile`:
- Sets the right `WORKDIR`
- Installs dependencies
- Exposes port 8080 (not required, but good practice)
- Has correct `CMD` or `ENTRYPOINT`

Example Python `Dockerfile`:
```dockerfile
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY . .
CMD ["python", "app.py"]  # Must listen on $PORT
```

Example Node.js `Dockerfile`:
```dockerfile
FROM node:18-alpine
WORKDIR /app
COPY package*.json .
RUN npm install
COPY . .
EXPOSE 8080
CMD ["npm", "start"]  # Must listen on process.env.PORT
```

## Common Fixes

### Fix 1: Listen on $PORT Environment Variable

**Python (Flask):**
```python
import os
from flask import Flask

app = Flask(__name__)

@app.route('/')
def hello():
    return 'Hello World'

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 8080))
    app.run(host='0.0.0.0', port=port)
```

**Node.js (Express):**
```javascript
const express = require('express');
const app = express();

app.get('/', (req, res) => {
  res.send('Hello World');
});

const port = process.env.PORT || 8080;
app.listen(port, () => {
  console.log(`Listening on :${port}`);
});
```

**Go:**
```go
package main

import (
    "fmt"
    "log"
    "net/http"
    "os"
)

func main() {
    port := os.Getenv("PORT")
    if port == "" {
        port = "8080"
    }

    http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
        fmt.Fprintf(w, "Hello World")
    })

    log.Fatal(http.ListenAndServe(":"+port, nil))
}
```

### Fix 2: Ensure Startup Completes Quickly
- Avoid long initialization in main code
- Move heavy startup to lazy loading
- Reduce image size (fewer dependencies = faster boot)

### Fix 3: Use Startup CPU Boost
For slow-starting apps, Zilch enables startup CPU boost on Cloud Run v2:

The app gets extra CPU for the first startup phase, then drops to normal resources.

### Fix 4: Increase Startup Timeout
If your app legitimately needs >5 minutes:

```bash
# Manually (after initial deployment)
gcloud run deploy APP_NAME \
  --region=REGION \
  --startup-timeout=600  # 10 minutes
```

## Monitoring Health Checks

### View Revisions
```bash
gcloud run revisions list --service=APP_NAME --region=us-central1
```

Shows:
- How many revisions (versions) are running
- Traffic split between them
- If revisions are healthy or failed

### Check Container Logs
```bash
gcloud run logs read APP_NAME --region=us-central1 --tail=100
```

Tail logs in real-time to see startup sequence.

### Check via Console
- Visit: https://console.cloud.google.com/run
- Select region and app
- Click "Revisions" tab
- See health status, error messages

## Quick Checklist

- [ ] App listens on `$PORT` env var (default 8080)
- [ ] App responds to GET / within 5 seconds
- [ ] No errors in startup logs: `gcloud run logs read`
- [ ] Dockerfile has correct `CMD` or `ENTRYPOINT`
- [ ] Dependencies installed in image
- [ ] No permission issues (can listen on port)
- [ ] Tested locally: `docker run` works

## Still Failing?

1. **Check logs carefully** — first error is usually the root cause
2. **Simplify** — deploy just a "Hello World" to test
3. **Test locally** — ensure Docker image runs on your machine
4. **Check IAM** — verify your service account has permissions
5. **Ask for help** — post logs on [GitHub Issues](https://github.com/hoyle1974/zilch-gcp/issues)

---

**Links:** [Cloud Run](../../entities/cloud-run.md) | [Deployment Workflow](../../entities/deployment-workflow.md)
