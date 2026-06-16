# Cloud Scheduler

Cloud Scheduler is a fully managed cron job service. Enable it to run scheduled tasks on your Cloud Run service automatically.

## Overview

Cloud Scheduler lets you schedule HTTP requests to your Cloud Run endpoint at specified times.

**Use cases:**
- Daily backups or data exports
- Hourly metrics collection
- Nightly batch jobs
- Weekly reports or email digests
- Recurring cleanup tasks

## How It Works

1. You define a cron schedule (e.g., "0 0 * * *" = daily at midnight UTC)
2. Cloud Scheduler sends an HTTP POST to your Cloud Run service
3. Your app processes the request
4. Scheduler logs the result

```
Cloud Scheduler
    ↓ (daily at 00:00 UTC)
Cloud Run Service
    ↓ POST /api/cron
Your Application
    ↓ (does work: backup, export, cleanup, etc.)
Done
```

## Enabling Cloud Scheduler

In `.zilch.config`, set:
```bash
enable_scheduler=true
scheduler_schedule="0 0 * * *"      # Cron expression
scheduler_timezone="UTC"             # Timezone
scheduler_endpoint="/api/cron"       # Endpoint to POST to
```

Or enable during `./deploy.sh`:
```bash
❓ Enable Cloud Scheduler (serverless cron jobs) support? (y/n) [default: n]: y
👉 Cloud Scheduler cron expression [0 0 * * *]: 0 0 * * *
👉 Scheduler endpoint path [/api/cron]: /api/cron
```

## Configuration

### Cron Expression Format

```
   ┌─────── minute (0 - 59)
   │ ┌───── hour (0 - 23)
   │ │ ┌─── day of month (1 - 31)
   │ │ │ ┌─ month (1 - 12)
   │ │ │ │ ┌ day of week (0 - 6) (Sunday to Saturday)
   │ │ │ │ │
   │ │ │ │ │
   * * * * *
```

**Examples:**
```bash
0 0 * * *      # Daily at midnight UTC
0 */6 * * *    # Every 6 hours
0 2 * * 0      # Weekly on Sunday at 2 AM UTC
0 0 1 * *      # Monthly on the 1st at midnight UTC
*/15 * * * *   # Every 15 minutes
```

### Timezone

Zilch defaults to UTC, but you can customize:
```bash
scheduler_timezone="America/New_York"   # Or any IANA timezone
scheduler_timezone="Europe/London"
scheduler_timezone="Asia/Tokyo"
```

### Endpoint

The endpoint is the HTTP path on your Cloud Run service:
```bash
scheduler_endpoint="/api/cron"         # POST /api/cron
scheduler_endpoint="/webhooks/daily"   # POST /webhooks/daily
scheduler_endpoint="/tasks/cleanup"    # POST /tasks/cleanup
```

## Implementing the Endpoint

Your app must have an HTTP endpoint that handles the POST request.

**Python (Flask):**
```python
from flask import Flask, request

app = Flask(__name__)

@app.route('/api/cron', methods=['POST'])
def scheduled_job():
    # Your scheduled work here
    print("Running scheduled job...")
    # Do backup, export, cleanup, etc.
    return "OK", 200

@app.route('/', methods=['GET'])
def health():
    return "Hello", 200
```

**Node.js (Express):**
```javascript
const express = require('express');
const app = express();

app.post('/api/cron', async (req, res) => {
  // Your scheduled work here
  console.log('Running scheduled job...');
  // Do backup, export, cleanup, etc.
  res.status(200).send('OK');
});

app.get('/', (req, res) => {
  res.send('Hello');
});
```

**Go:**
```go
package main

import (
    "fmt"
    "log"
    "net/http"
)

func scheduledJob(w http.ResponseWriter, r *http.Request) {
    if r.Method != http.MethodPost {
        http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
        return
    }
    
    // Your scheduled work here
    fmt.Println("Running scheduled job...")
    w.WriteHeader(http.StatusOK)
    w.Write([]byte("OK"))
}

func main() {
    http.HandleFunc("/api/cron", scheduledJob)
    http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
        w.Write([]byte("Hello"))
    })
    
    port := os.Getenv("PORT")
    if port == "" {
        port = "8080"
    }
    log.Fatal(http.ListenAndServe(":"+port, nil))
}
```

## Authentication

Cloud Scheduler uses OIDC (OpenID Connect) tokens to authenticate to Cloud Run. The request includes:

```
Authorization: Bearer eyJhbGc...
```

Your service account can receive these tokens automatically. No authentication code needed in your endpoint — Cloud Run verifies the token.

## Monitoring

### View Scheduled Jobs
```bash
gcloud scheduler jobs list --location=us-central1
```

### View Job Execution History
```bash
gcloud scheduler jobs describe zilch-reference-app-cron --location=us-central1
```

Shows:
- Last execution time
- Status (success/failure)
- Error messages if any

### View Logs
```bash
gcloud run logs read APP_NAME --region=us-central1
# Look for POST requests to /api/cron
```

## Free Tier Limits

- **3 free jobs per billing account per month** — Perfect for essential tasks
- Beyond 3: $0.10 per job per month
- Execution: $0.0001 per execution

Since Cloud Scheduler just calls Cloud Run via HTTP, you're mostly paying for Cloud Run's compute (which has a generous free tier).

## Examples

### Daily Backup
```python
@app.route('/api/cron/backup', methods=['POST'])
def backup():
    # Export Firestore data
    from google.cloud import firestore, storage
    db = firestore.Client()
    
    # Dump all collections
    collections = db.collections()
    backup_time = datetime.now().isoformat()
    bucket = storage.Client().bucket(os.getenv('ZILCH_STORAGE_BUCKET'))
    
    for collection in collections:
        docs = [doc.to_dict() for doc in collection.stream()]
        blob = bucket.blob(f"backups/{collection.id}-{backup_time}.json")
        blob.upload_from_string(json.dumps(docs))
    
    return "Backup complete", 200
```

### Hourly Metrics
```javascript
app.post('/api/cron/metrics', async (req, res) => {
  // Collect and log metrics
  const pubsub = require('@google-cloud/pubsub');
  const client = new pubsub.PubSub();
  const topic = client.topic(process.env.ZILCH_PUBSUB_TOPIC);
  
  const message = JSON.stringify({
    timestamp: new Date().toISOString(),
    metrics: {
      // Your metrics here
    }
  });
  
  await topic.publish(Buffer.from(message));
  res.status(200).send('Metrics published');
});
```

### Weekly Cleanup
```bash
# Schedule: 0 2 * * 0 (Sundays at 2 AM UTC)
@app.route('/api/cron/cleanup', methods=['POST'])
def cleanup():
    # Delete old documents
    from google.cloud import firestore
    db = firestore.Client()
    
    cutoff = datetime.now() - timedelta(days=30)
    
    # Delete old entries
    old_entries = db.collection('entries').where('created', '<', cutoff).stream()
    for doc in old_entries:
        doc.reference.delete()
    
    return "Cleanup complete", 200
```

## Troubleshooting

### Job Not Running
- Check timezone: Is the time correct for your timezone?
- Check endpoint: Does `/api/cron` exist and return 200?
- Check logs: `gcloud run logs read APP_NAME`

### "Permission denied" in execution
- Scheduler needs permission to call Cloud Run
- Zilch grants this automatically via IAM roles
- Check: `gcloud projects get-iam-policy PROJECT_ID`

### Slow Execution
- Cloud Run may cold-start (if idle)
- Zilch enables startup CPU boost to mitigate this
- Keep execution fast (<60 seconds, ideally <10 seconds)

## Related

- **[Cloud Run](../cloud-run.md)** — Where scheduled jobs run
- **[Environment Variables](../environment-variables.md)** — Access Pub/Sub topics, buckets, etc.
- **[Service Accounts & IAM](../service-accounts.md)** — OIDC token authentication
- **[Always Free Tier](../always-free-tier.md)** — 3 free jobs/month

---

**External Reference:** [Google Cloud Scheduler Docs](https://cloud.google.com/scheduler/docs)
