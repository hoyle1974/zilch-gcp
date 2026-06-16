# Configuration Guide

Zilch stores your deployment settings in `.zilch.config`, a simple key-value file that persists your choices between deployments.

## What is .zilch.config?

`.zilch.config` is a bash-readable text file created by `./deploy.sh`. It contains:
- Your GCP Project ID
- Application name
- Region choice
- Which services are enabled
- Feature toggles for Scheduler and Monitoring

Example:
```bash
gcp_project_id=my-project
app_name=my-app
gcp_region=us-central1
enable_firestore=true
enable_pubsub=false
enable_scheduler=true
scheduler_schedule="0 0 * * *"
...
```

## File Location

```
zilch-gcp/
└── .zilch.config          # Your deployment config (created by deploy.sh)
```

The file is ignored by git (see `.gitignore`).

## Creating .zilch.config

### First Run
On first deployment, you have no `.zilch.config`. The script prompts for everything:
```bash
👉 Enter your target GCP Project ID: my-project
👉 Enter your application name [zilch-app]: my-app
🌐 Choose your infrastructure anchor zone (Always Free Eligible):
  [1] us-central1 (Iowa - Preferred Default)
  [2] us-east1    (South Carolina)
  [3] us-west1    (Oregon)
Selection [1-3, default: 1]: 1
❓ Enable Firestore NoSQL Database support? (y/n) [default: n]: y
...
```

After deployment completes, a `.zilch.config` file is created with your answers.

### Subsequent Runs
The next time you run `./deploy.sh`, it loads `.zilch.config` and uses those values as defaults. You can press Enter to accept them or change any value:

```bash
✓ Configuration loaded
👉 Enter your target GCP Project ID [my-project]: 
👉 Enter your application name [my-app]: 
❓ Enable Firestore NoSQL Database support? (y/n) [default: y]: 
```

## Configuration Options

### GCP Settings
```bash
gcp_project_id=my-project        # Your GCP Project ID (required)
app_name=my-app                  # Application name (required)
gcp_region=us-central1           # Always Free region only
```

### Phase 1: Core Services
```bash
enable_firestore=true            # Firestore NoSQL Database
enable_secret_manager=true       # Secret Manager
enable_cloud_storage=true        # Cloud Storage
enable_firebase_auth=true        # Firebase Authentication
enable_vertex_ai=true            # Vertex AI / Gemini
```

### Phase 2: CI/CD
```bash
enable_cloud_build=true          # Cloud Build (recommended)
github_owner=myusername          # GitHub username/org (if Cloud Build enabled)
github_repo=myrepo               # GitHub repository name (if Cloud Build enabled)
```

### Phase 3: Advanced Services
```bash
enable_pubsub=true               # Pub/Sub Event Streaming
enable_cloud_tasks=true          # Cloud Tasks Job Queues
enable_bigquery=true             # BigQuery Analytics
enable_cloud_kms=true            # Cloud KMS Encryption
enable_vision_ai=true            # Vision AI Image Processing
enable_speech_to_text=true       # Speech-to-Text
enable_translation=true          # Translation API
```

### Phase 4: Scheduler & Monitoring
```bash
enable_scheduler=true            # Cloud Scheduler cron jobs
scheduler_schedule="0 0 * * *"   # Cron expression (daily at midnight)
scheduler_timezone="UTC"         # Timezone for cron
scheduler_endpoint="/api/cron"   # Cloud Run endpoint to call

enable_monitoring=true           # Cloud Monitoring with budget alerts
billing_account_name="My Billing Account"  # (optional, auto-detected)
billing_budget_limit_usd=10      # Monthly budget in USD
```

## Modifying Configuration

### Edit Manually
You can manually edit `.zilch.config` before running `./deploy.sh`:

```bash
# Open in your editor
nano .zilch.config

# Then run deploy.sh
./deploy.sh
```

### Or Re-run Deploy Script
The easier way is to just run `./deploy.sh` and answer the prompts with your new values. The script will detect changes and apply them via Terraform.

## Updating Services

If you want to enable/disable a service after initial deployment:

1. Run `./deploy.sh`
2. Answer prompts (press Enter to keep existing values, or change them)
3. Change the `enable_*=true/false` answers
4. Terraform will add or remove services as needed

Example: Enable BigQuery that was previously disabled
```bash
✓ Configuration loaded
👉 Enter your target GCP Project ID [my-project]: 
...
❓ Enable BigQuery Analytics Engine support? (y/n) [default: false]: y
# Now BigQuery will be created and added to your app
```

## Terraform Variables

Under the hood, Zilch converts `.zilch.config` values to Terraform variables:

```bash
terraform apply \
  -var="gcp_project_id=my-project" \
  -var="app_name=my-app" \
  -var="enable_firestore=true" \
  ...
```

Each variable is validated:
- Project ID must be 6-30 lowercase alphanumeric + hyphens
- App name must be 3-30 lowercase alphanumeric + hyphens
- Region must be us-central1, us-east1, or us-west1
- Service flags must be `true` or `false`

## Resetting Configuration

To start over with a fresh deployment:

1. **Delete `.zilch.config`**:
```bash
rm .zilch.config
```

2. **Run `./deploy.sh`** — All prompts will show defaults instead of your previous values

3. **Or create a new project** — Use a different GCP Project ID to isolate completely

## Configuration Persistence

Zilch saves `.zilch.config` after successful deployment, ensuring your settings are saved. This allows:

- **Quick re-runs** — `./deploy.sh` works immediately with saved config
- **Team consistency** — All developers use the same config
- **Version control aware** — `.gitignore` prevents committing `.zilch.config` (it may contain sensitive info)

## Advanced: Using .zilch.config in Scripts

You can source `.zilch.config` in other scripts:

```bash
#!/bin/bash
source .zilch.config

echo "Deploying to project: $gcp_project_id"
echo "App name: $app_name"

if [ "$enable_firestore" == "true" ]; then
    echo "Firestore is enabled"
fi
```

## Related

- **[Deployment Workflow](deployment-workflow.md)** — How config is used during deployment
- **[Terraform](terraform.md)** — How config becomes Terraform variables
- **[Environment Variables](environment-variables.md)** — Runtime config (different from .zilch.config)

---

**Security Note:** Don't commit `.zilch.config` to git if it contains sensitive information. Use secrets management for production credentials instead.
