# Service Integration Patterns

How to use Zilch services from your application code.

## The Pattern: Read Environment Variables, Use SDKs

Every Zilch service works the same way:

1. Check if the service is enabled: `os.getenv('ZILCH_SERVICE_NAME')`
2. Get service details from environment variables
3. Use the official Google Cloud SDK with Application Default Credentials (automatic)

## Core Services

### Firestore Database

```python
import os
from google.cloud import firestore

# Check if enabled
if os.getenv('ZILCH_FIRESTORE_DATABASE'):
    db = firestore.Client(
        database=os.getenv('ZILCH_FIRESTORE_DATABASE')
    )
    doc = db.collection('users').document('alice').get()
    if doc.exists:
        print(doc.to_dict())
```

```javascript
const admin = require('firebase-admin');
const db = admin.firestore();

if (process.env.ZILCH_FIRESTORE_DATABASE) {
    const doc = await db.collection('users').doc('alice').get();
    if (doc.exists) {
        console.log(doc.data());
    }
}
```

### Cloud Storage

```python
from google.cloud import storage

if os.getenv('ZILCH_STORAGE_BUCKET'):
    bucket_name = os.getenv('ZILCH_STORAGE_BUCKET')
    storage_client = storage.Client()
    bucket = storage_client.bucket(bucket_name)
    
    # Upload
    blob = bucket.blob('my-file.txt')
    blob.upload_from_string('Hello World')
    
    # Download
    downloaded = blob.download_as_string()
```

### Secret Manager

```python
from google.cloud import secretmanager

if os.getenv('ZILCH_SECRET_PREFIX'):
    secret_prefix = os.getenv('ZILCH_SECRET_PREFIX')
    project_id = os.getenv('ZILCH_PROJECT_ID')
    
    client = secretmanager.SecretManagerServiceClient()
    secret_name = f"projects/{project_id}/secrets/{secret_prefix}-api-key/versions/latest"
    response = client.access_secret_version(request={"name": secret_name})
    api_key = response.payload.data.decode('UTF-8')
```

### Vertex AI (Gemini)

```python
import os
import vertexai
from vertexai.generative_models import GenerativeModel

if os.getenv('ZILCH_VERTEX_AI_ENABLED'):
    project_id = os.getenv('ZILCH_PROJECT_ID')
    region = os.getenv('ZILCH_REGION', 'us-central1')
    
    vertexai.init(project=project_id, location=region)
    model = GenerativeModel("gemini-1.5-flash")
    response = model.generate_content("Hello, how are you?")
    print(response.text)
```

## Optional Services

### Pub/Sub (Messaging)

```python
from google.cloud import pubsub_v1

if os.getenv('ZILCH_PUBSUB_TOPIC'):
    project_id = os.getenv('ZILCH_PROJECT_ID')
    topic_name = os.getenv('ZILCH_PUBSUB_TOPIC')
    
    publisher = pubsub_v1.PublisherClient()
    topic_path = publisher.topic_path(project_id, topic_name)
    
    # Publish event
    message_json = json.dumps({"user": "alice", "event": "login"})
    message_bytes = message_json.encode('utf-8')
    future = publisher.publish(topic_path, data=message_bytes)
    print(f"Published message id: {future.result()}")
```

### Cloud Tasks (Job Queue)

```python
from google.cloud import tasks_v2

if os.getenv('ZILCH_CLOUD_TASKS_QUEUE'):
    project_id = os.getenv('ZILCH_PROJECT_ID')
    queue_name = os.getenv('ZILCH_CLOUD_TASKS_QUEUE')
    region = os.getenv('ZILCH_REGION', 'us-central1')
    
    client = tasks_v2.CloudTasksClient()
    queue_path = client.queue_path(project_id, region, queue_name)
    
    # Schedule a task
    task = {
        'http_request': {
            'http_method': tasks_v2.HttpMethod.POST,
            'url': 'https://my-app.run.app/worker',
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'job_id': '123'}).encode()
        }
    }
    response = client.create_task(request={'parent': queue_path, 'task': task})
    print(f"Created task: {response.name}")
```

### BigQuery (Analytics)

```python
from google.cloud import bigquery

if os.getenv('ZILCH_BIGQUERY_DATASET'):
    dataset_id = os.getenv('ZILCH_BIGQUERY_DATASET')
    project_id = os.getenv('ZILCH_PROJECT_ID')
    
    client = bigquery.Client(project=project_id)
    
    # Insert row
    table_id = f"{project_id}.{dataset_id}.events"
    rows_to_insert = [
        {"user_id": "alice", "event": "login", "timestamp": 1234567890}
    ]
    errors = client.insert_rows_json(table_id, rows_to_insert)
    if errors:
        print(f"Errors: {errors}")
```

## Environment Variable Reference

| Variable | When Set | Value |
|----------|----------|-------|
| `ZILCH_PROJECT_ID` | Always | Your GCP project ID |
| `ZILCH_APP_NAME` | Always | Your app name |
| `ZILCH_REGION` | Always | us-central1, us-east1, or us-west1 |
| `ZILCH_FIRESTORE_DATABASE` | Firestore enabled | Database ID |
| `ZILCH_STORAGE_BUCKET` | Cloud Storage enabled | Bucket name |
| `ZILCH_SECRET_PREFIX` | Secret Manager enabled | Secret name prefix |
| `ZILCH_VERTEX_AI_ENABLED` | Vertex AI enabled | "true" |
| `ZILCH_PUBSUB_TOPIC` | Pub/Sub enabled | Topic name |
| `ZILCH_CLOUD_TASKS_QUEUE` | Cloud Tasks enabled | Queue name |
| `ZILCH_BIGQUERY_DATASET` | BigQuery enabled | Dataset ID |

## Common Pattern: Conditional Logic

Always check if a service is enabled before using it:

```python
import os
from google.cloud import firestore, storage, secretmanager

# Safe initialization
if os.getenv('ZILCH_FIRESTORE_DATABASE'):
    db = firestore.Client()
else:
    db = None

if os.getenv('ZILCH_STORAGE_BUCKET'):
    storage_client = storage.Client()
else:
    storage_client = None

# In your handler
def save_user(name, photo):
    if db:
        db.collection('users').document(name).set({'name': name})
    
    if storage_client and photo:
        bucket = storage_client.bucket(os.getenv('ZILCH_STORAGE_BUCKET'))
        bucket.blob(f'photos/{name}.jpg').upload_from_string(photo)
```

## SDK Documentation

For detailed API reference, consult official Google Cloud docs:

- **[Firestore Python](https://cloud.google.com/python/docs/reference/cloud-firestore/latest)** | **[Node.js](https://cloud.google.com/javascript/docs/reference/firestore/latest)** | **[Go](https://cloud.google.com/go/docs/reference/cloud.google.com/go/firestore/latest)**
- **[Cloud Storage Python](https://cloud.google.com/python/docs/reference/storage/latest)** | **[Node.js](https://cloud.google.com/javascript/docs/reference/storage/latest)**
- **[Vertex AI Python](https://cloud.google.com/python/docs/reference/vertexai/latest)** | **[Node.js](https://cloud.google.com/javascript/docs/reference/ai/latest)**
- **[Pub/Sub Python](https://cloud.google.com/python/docs/reference/pubsub/latest)** | **[Node.js](https://cloud.google.com/javascript/docs/reference/pubsub/latest)**

---

**Links:** [Application Default Credentials](application-default-credentials.md) | [Deployment Workflow](../entities/deployment-workflow.md)
