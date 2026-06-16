# Environment Variables

Zilch passes configuration to your application via environment variables. These variables tell your code which services are available and how to find them.

## How It Works

When you enable a service in `.zilch.config`, Zilch:

1. Provisions the service (e.g., creates a Firestore database)
2. Passes the service's name/ID to Cloud Run as an environment variable
3. Your app reads the variable and connects to the service

Example:
```bash
enable_firestore=true        # User enables Firestore
              ↓
      Terraform creates Firestore database
              ↓
      Cloud Run receives:  ZILCH_FIRESTORE_DATABASE="(default)"
              ↓
      Your code reads it:   db_name = os.getenv('ZILCH_FIRESTORE_DATABASE')
```

## Available Variables

### Core Application
```
ZILCH_PROJECT_ID     → Your GCP Project ID
ZILCH_APP_NAME       → Your application name (from deploy.sh)
```

### Data Services
```
ZILCH_FIRESTORE_DATABASE    → Firestore database name (if enabled)
                              Example: "(default)"

ZILCH_STORAGE_BUCKET        → Cloud Storage bucket name (if enabled)
                              Example: "my-app-storage-a1b2c3d4"

ZILCH_BIGQUERY_DATASET      → BigQuery dataset ID (if enabled)
                              Example: "my_app_analytics"

ZILCH_KMS_KEY_ID            → Cloud KMS crypto key ID (if enabled)
                              Example: "projects/my-project/locations/us-central1/keyRings/my-app-keyring/cryptoKeys/my-app-key"
```

### Integration Services
```
ZILCH_SECRET_PREFIX         → Prefix for secrets (if enabled)
                              Example: "my-app-"
                              Use: my-app-api-key, my-app-db-password

ZILCH_PUBSUB_TOPIC          → Pub/Sub topic name (if enabled)
                              Example: "my-app-events"

ZILCH_PUBSUB_SUBSCRIPTION   → Pub/Sub subscription name (if enabled)
                              Example: "my-app-events-subscription"

ZILCH_CLOUD_TASKS_QUEUE     → Cloud Tasks queue path (if enabled)
                              Example: "projects/my-project/locations/us-central1/queues/my-app-jobs"
```

### AI/ML Services
```
ZILCH_VERTEX_AI_ENABLED     → "true" if Vertex AI enabled
ZILCH_FIREBASE_ENABLED      → "true" if Firebase Auth enabled
ZILCH_VISION_AI_ENABLED     → "true" if Vision AI enabled
ZILCH_SPEECH_TO_TEXT_ENABLED → "true" if Speech-to-Text enabled
ZILCH_TRANSLATION_ENABLED    → "true" if Translation enabled
```

### Scheduler & Monitoring
```
ZILCH_SCHEDULER_ENABLED     → "true" if Cloud Scheduler enabled
ZILCH_MONITORING_ENABLED    → "true" if Cloud Monitoring enabled
```

## Reading Environment Variables

### Python
```python
import os

project_id = os.getenv('ZILCH_PROJECT_ID')
app_name = os.getenv('ZILCH_APP_NAME')
firestore_db = os.getenv('ZILCH_FIRESTORE_DATABASE')

# Check if service is enabled
if os.getenv('ZILCH_PUBSUB_TOPIC'):
    topic_name = os.getenv('ZILCH_PUBSUB_TOPIC')
    # Initialize Pub/Sub client
```

### Node.js / JavaScript
```javascript
const projectId = process.env.ZILCH_PROJECT_ID;
const appName = process.env.ZILCH_APP_NAME;
const firestoreDb = process.env.ZILCH_FIRESTORE_DATABASE;

// Check if enabled
if (process.env.ZILCH_PUBSUB_TOPIC) {
    const topicName = process.env.ZILCH_PUBSUB_TOPIC;
}
```

### Go
```go
package main

import (
    "os"
)

func main() {
    projectID := os.Getenv("ZILCH_PROJECT_ID")
    appName := os.Getenv("ZILCH_APP_NAME")
    
    if pubsubTopic := os.Getenv("ZILCH_PUBSUB_TOPIC"); pubsubTopic != "" {
        // Pub/Sub is enabled
    }
}
```

## Common Patterns

### Conditional Service Initialization
```python
if os.getenv('ZILCH_FIRESTORE_DATABASE'):
    from google.cloud import firestore
    db = firestore.Client()
    # Use db for database operations
else:
    db = None  # Service not enabled
```

### Secret Manager Prefix
Secrets are stored with your app name as a prefix:
```bash
# In deploy.sh, ZILCH_SECRET_PREFIX is set to "my-app-"
# So you create secrets like:
gcloud secrets create my-app-api-key --data-file=api-key.txt
gcloud secrets create my-app-db-password --data-file=password.txt

# In your code:
from google.cloud import secretmanager
client = secretmanager.SecretManagerServiceClient()
prefix = os.getenv('ZILCH_SECRET_PREFIX')
api_key_name = f"{prefix}api-key"
response = client.access_secret_version(request={"name": api_key_name})
```

### Cloud Tasks Queue Path
```python
from google.cloud import tasks_v2
import os

client = tasks_v2.CloudTasksClient()
queue_path = os.getenv('ZILCH_CLOUD_TASKS_QUEUE')

# Use queue_path directly in Cloud Tasks calls
task = client.create_task(request={"parent": queue_path, "task": {...}})
```

## Environment at Deployment Time

Zilch sets these when running `./deploy.sh`:
```bash
# From deploy.sh prompts
gcp_project_id                  # Your GCP Project ID
app_name                        # Application name
gcp_region                      # Always Free region
enable_firestore, etc.          # Feature flags

# Terraform outputs
ZILCH_FIRESTORE_DATABASE        # After Terraform creates resources
ZILCH_STORAGE_BUCKET            # Resource names/IDs
ZILCH_PUBSUB_TOPIC
... (all resource-based variables)
```

## Updating Variables

To change which variables are available:

1. **Edit `.zilch.config`**: Add/remove `enable_*` flags
2. **Re-run `./deploy.sh`**: Creates/destroys services, updates env vars
3. **Redeploy your app**: New env vars are available in Cloud Run

## Related

- **[Configuration Guide](configuration.md)** — How `.zilch.config` works
- **[Service Accounts & IAM](service-accounts.md)** — Authentication (separate from env vars)
- **[Cloud Run](cloud-run.md)** — How Cloud Run injects variables
- **Services directory** — Each service page lists its variables

---

**Tip:** Use environment variables for configuration, not hardcoding. This makes your app portable and testable.
