# Application Default Credentials

How Zilch automatically authenticates your app to Google Cloud services.

## The Pattern: No Configuration Needed

When Zilch deploys your app, it runs on Cloud Run under a [Service Account](../../entities/service-accounts.md). All Google Cloud SDKs automatically detect and use this service account — no API keys, credentials files, or configuration required.

This is called **Application Default Credentials (ADC)**.

## How It Works

```
1. Zilch creates a Service Account for your app (e.g., my-app@my-project.iam.gserviceaccount.com)
2. Cloud Run runs your container as this Service Account
3. Google Cloud SDKs detect the service account automatically
4. All API calls are authenticated as this service account
5. IAM controls what the service account can do
```

## In Code

You don't need to do anything special:

```python
# This works automatically — no credentials file needed
from google.cloud import firestore

db = firestore.Client()  # ADC authenticates automatically
docs = db.collection('users').get()
```

```javascript
// This works automatically — no credentials file needed
const admin = require('firebase-admin');
const db = admin.firestore();

const doc = await db.collection('users').doc('alice').get();
```

```go
// This works automatically — no credentials file needed
ctx := context.Background()
client, err := firestore.NewClient(ctx, projectID)
```

## What ADC Checks (In Order)

The Google Cloud SDKs check for credentials in this order:

1. **Environment variable** `GOOGLE_APPLICATION_CREDENTIALS` — If you've set this (local dev)
2. **Cloud Run** — If running on Cloud Run, use the service account automatically
3. **GKE** — If running on Google Kubernetes Engine, use the node's service account
4. **Compute Engine** — If running on Compute Engine, use the default service account
5. **Local default** — If you've run `gcloud auth application-default login` locally

## For Local Development

When developing locally, you have two options:

### Option 1: Use Your Own GCP Credentials (Easier)

```bash
gcloud auth application-default login
```

This lets you test code locally using your own GCP credentials. Your code will work exactly the same way it does on Cloud Run.

### Option 2: Use a Service Account Key (Less Recommended)

Create a service account key in the GCP console and set it:

```bash
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json
python app.py
```

⚠️ **Warning:** Never commit service account keys to git. If you use this approach, add `key.json` to `.gitignore`.

## Permissions Model

The service account Zilch creates has **only the permissions needed for your enabled services**:

| Service | Roles Granted |
|---------|---|
| Cloud Firestore | `roles/datastore.user` (read/write) |
| Cloud Storage | `roles/storage.admin` (full access to your bucket) |
| Secret Manager | `roles/secretmanager.secretAccessor` (read only) |
| Vertex AI | `roles/aiplatform.user` (API access) |
| Pub/Sub | `roles/pubsub.editor` (publish/subscribe) |
| Cloud Tasks | `roles/cloudtasks.taskEnqueuer` (create tasks) |
| BigQuery | `roles/bigquery.dataEditor` (read/write tables) |

If you try to access a service that isn't enabled, you'll get a **permission denied** error.

## Debugging Authentication Issues

### Error: "Permission denied" or "Forbidden"

**Cause:** Service account doesn't have IAM role for that service.

**Fix:** Re-run `./deploy.sh` and enable the service you need.

```bash
./deploy.sh
# Answer "yes" to the service you want to enable
```

### Error: "Could not locate credentials"

**Cause:** Running locally without setting up ADC.

**Fix:** Set up local credentials:

```bash
gcloud auth application-default login
```

### Error: "Project not found"

**Cause:** SDK can't determine the GCP project ID.

**Fix:** Set it explicitly (for local dev only):

```bash
export GOOGLE_CLOUD_PROJECT=my-project-id
python app.py
```

Or in code:

```python
from google.cloud import firestore

db = firestore.Client(project='my-project-id')
```

## Best Practices

1. **Don't hardcode credentials** — Rely on ADC
2. **Don't commit service account keys** — Use `gcloud auth` instead
3. **Test locally with your own credentials** — `gcloud auth application-default login`
4. **In production, Zilch handles it** — No configuration needed on Cloud Run
5. **Use least privilege** — Only enable services you actually use

## Verifying ADC Works

To test that your code can authenticate:

```python
from google.cloud import firestore
from google.api_core import exceptions

try:
    db = firestore.Client()
    # This is a read operation that checks authentication
    _ = db.collection('test').limit(1).get()
    print("✅ Authentication successful")
except exceptions.Unauthenticated:
    print("❌ Not authenticated")
except exceptions.PermissionDenied:
    print("❌ No permission for this service")
```

---

**Links:** [Service Accounts](../../entities/service-accounts.md) | [Service Integration Patterns](service-patterns.md)
