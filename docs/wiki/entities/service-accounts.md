# Service Accounts & IAM

Zilch uses least-privilege service accounts to ensure your application has only the permissions it needs.

## What is a Service Account?

A service account is a non-human identity in GCP. Instead of logging in with a username/password, your Cloud Run application runs as a service account that has specific permissions (IAM roles) granted to it.

**Key advantages:**
- Applications authenticate automatically (no credentials to manage)
- Fine-grained permissions (app only has access to enabled services)
- Audit trail (all actions are tied to the service account)
- Revokable (disable a service account, app loses access)

## Zilch's Service Account Model

Zilch creates **two service accounts**:

### 1. Application Service Account (`app`)
- Runs your Cloud Run service
- Has permissions for enabled services only
- Example: If Firestore is enabled, it gets `roles/datastore.user`
- Used by Application Default Credentials (ADC)

### 2. Cloud Build Service Account (`app-builder`)
- Builds and deploys your container image
- Separate account for security isolation
- Only exists if [Cloud Build](../services/cloud-build.md) is enabled
- Permissions: push to Artifact Registry, deploy to Cloud Run

## How Permissions Work

### Feature Flags → IAM Roles

When you enable a service with `enable_*=true`:

1. Terraform adds the required IAM role to the app service account
2. Cloud Run uses that service account
3. Your code inherits the permission automatically

Example:
```bash
enable_firestore=true    # Deploy script prompt
                         ↓
                  Terraform adds
                         ↓
    roles/datastore.user to app service account
                         ↓
              Code can access Firestore
```

### Permission Table

| Service | Required Role | Details |
|---------|---------------|---------|
| Firestore | `roles/datastore.user` | Read/write documents |
| Secret Manager | `roles/secretmanager.secretAccessor` | Read secrets |
| Cloud Storage | `roles/storage.objectUser` | Read/write objects |
| Pub/Sub | `roles/pubsub.editor` | Publish/subscribe |
| Cloud Tasks | `roles/cloudtasks.enqueuer` | Enqueue tasks |
| BigQuery | `roles/bigquery.dataEditor` | Query and write tables |
| Cloud KMS | `roles/cloudkms.cryptoKeyEncrypterDecrypter` | Encrypt/decrypt |
| Vision AI | `roles/aiplatform.user` | Call Vision API |

## Application Default Credentials (ADC)

Your code uses ADC to automatically authenticate as the service account:

**Python:**
```python
from google.cloud import firestore
db = firestore.Client()  # Automatically uses service account
```

**Node.js:**
```javascript
const firestore = require('@google-cloud/firestore');
const db = new firestore.Firestore();  // Automatic ADC
```

**Java:**
```java
Firestore db = FirestoreClient.getFirestore();  // Automatic
```

No credentials file needed — Cloud Run injects the service account identity into the container.

## Security Best Practices

### ✅ Zilch Does Right
- **Least privilege** — Only enabled services get permissions
- **Isolated service accounts** — App and builder have separate identities
- **No hardcoded credentials** — Uses ADC for automatic auth
- **Audit trail** — All actions logged to Cloud Logging

### ⚠️ Things to Avoid
- **Don't grant `roles/editor`** — Too permissive
- **Don't disable ADC** — Would require managing credentials manually
- **Don't share service accounts** — Keep prod/staging isolated
- **Don't commit service account keys** — Use ADC or workload identity instead

## Viewing Service Accounts

```bash
# List all service accounts in project
gcloud iam service-accounts list

# Get permissions for a service account
gcloud projects get-iam-policy PROJECT_ID \
  --flatten='bindings[].members' \
  --filter='bindings.members:serviceAccount:*'
```

## Cloud Build Isolation

If [Cloud Build](../services/cloud-build.md) is enabled, the builder account has:
- `roles/artifactregistry.writer` — Push container images
- `roles/run.developer` — Deploy to Cloud Run
- `roles/iam.serviceAccountUser` — Use app service account
- `roles/logging.logWriter` — Write build logs

This separation ensures a compromised build system can't directly access your data services.

## Advanced: Custom Permissions

If you need permissions beyond what Zilch provides:

1. **Enable the service** via `enable_*=true`
2. **Manually grant additional roles**:
```bash
gcloud projects add-iam-policy-binding PROJECT_ID \
  --member=serviceAccount:APP_NAME@PROJECT_ID.iam.gserviceaccount.com \
  --role=roles/CUSTOM_ROLE
```
3. **Update your app code** to use the new permission

## Related

- **[Cloud Run](cloud-run.md)** — App runs as service account
- **[Environment Variables](environment-variables.md)** — How app discovers services
- **[Cloud Build](../services/cloud-build.md)** — Isolated builder service account
- **[Terraform](terraform.md)** — How permissions are declared

---

**External Reference:** [Google Cloud Service Accounts](https://cloud.google.com/docs/authentication/manage-identities)
