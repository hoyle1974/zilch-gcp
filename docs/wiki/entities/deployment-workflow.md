# Deployment Workflow

The deployment workflow is the complete process from running `./deploy.sh` to having a running application on Cloud Run.

## Overview

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Prerequisites Check (gcloud auth, IAM permissions)       │
├─────────────────────────────────────────────────────────────┤
│ 2. Load Configuration (from .zilch.config or prompt)        │
├─────────────────────────────────────────────────────────────┤
│ 3. Interactive Prompts (project, region, services to enable)│
├─────────────────────────────────────────────────────────────┤
│ 4. Create Remote State Bucket (for Terraform state)         │
├─────────────────────────────────────────────────────────────┤
│ 5. Terraform Init (initialize Terraform with backend)       │
├─────────────────────────────────────────────────────────────┤
│ 6. Terraform Apply (create/update all infrastructure)       │
├─────────────────────────────────────────────────────────────┤
│ 7. Health Check (verify Cloud Run is responding)            │
├─────────────────────────────────────────────────────────────┤
│ 8. Save Configuration (.zilch.config for next run)          │
├─────────────────────────────────────────────────────────────┤
│ 9. Display Summary (URLs, environment variables)            │
└─────────────────────────────────────────────────────────────┘
```

## Step 1: Prerequisites Check

`./deploy.sh` verifies you're ready to deploy:

✅ **gcloud authentication**
```bash
gcloud auth login  # If needed
```

✅ **GCP Project access**
- Must have Viewer role at minimum
- Must have Editor or Owner to create resources

✅ **Required permissions**
- Create service accounts
- Enable APIs
- Create Cloud Run services
- Create Cloud Storage buckets

If any check fails, the script exits with helpful instructions.

## Step 2: Load Configuration

The script looks for `.zilch.config` (a simple key-value file):

```bash
gcp_project_id=my-project
app_name=my-app
gcp_region=us-central1
enable_firestore=true
enable_pubsub=false
...
```

If `.zilch.config` exists, defaults are pre-filled in prompts. New users skip this step.

## Step 3: Interactive Prompts

The script asks:

### 1. Project ID
```
👉 Enter your target GCP Project ID: my-project
```
Must be an existing GCP project where you have Editor/Owner role.

### 2. Application Name
```
👉 Enter your application name [zilch-app]: my-app
```
Used as a prefix for all resources (my-app-storage, my-app-jobs, etc.)
Must be 3-30 lowercase alphanumeric characters or hyphens.

### 3. Region (Always Free Tier Only)
```
🌐 Choose your infrastructure anchor zone (Always Free Eligible):
  [1] us-central1 (Iowa - Preferred Default)
  [2] us-east1    (South Carolina)
  [3] us-west1    (Oregon)
Selection [1-3, default: 1]: 1
```
Zilch strictly enforces these three [Always Free regions](always-free-tier.md).

### 4. Services to Enable
```
❓ Enable Firestore NoSQL Database support? (y/n) [default: n]: y
❓ Enable Secret Manager Keys? (y/n) [default: n]: n
❓ Enable Cloud Storage Asset Buckets? (y/n) [default: n]: y
...
```

For each service, you choose yes/no. Enabled services:
- Get provisioned by Terraform
- Receive IAM roles for your service account
- Have [environment variables](environment-variables.md) passed to Cloud Run
- Count against [Always Free quotas](always-free-tier.md)

### 5. GitHub (if Cloud Build enabled)
```
⚙️  Cloud Build requires GitHub repository connection.
👉 Enter your GitHub username/org: myusername
👉 Enter your GitHub repository name: myrepo
```
Only asked if you enabled Cloud Build. Used to connect GitHub → Cloud Build → Cloud Run.

## Step 4: Create Remote State Bucket

Zilch creates a Cloud Storage bucket to store Terraform state:

```bash
STATE_BUCKET="${PROJECT_ID}-zilch-tfstate"
gcloud storage buckets create "gs://${STATE_BUCKET}" \
  --project="$PROJECT_ID" \
  --location="$GCP_REGION"
```

If the bucket already exists (from a previous run), Zilch reuses it.

**Why remote state?**
- Terraform state isn't lost if you clear Cloud Shell
- Multiple deployments from different shells work cleanly
- State is stored securely in Cloud Storage

After creation, the script waits for the bucket to be globally available (handles eventual consistency).

## Step 5: Terraform Init

Terraform initializes and connects to the remote backend:

```bash
terraform init \
  -backend-config="bucket=${STATE_BUCKET}" \
  -backend-config="prefix=terraform/state" \
  -reconfigure
```

This:
- Downloads the Google provider
- Creates `.terraform/` directory
- Connects to the remote state bucket
- Sets up Terraform for the first time (or reconfigures for a new bucket)

Zilch retries up to 3 times (handles transient network issues).

## Step 6: Terraform Apply

Terraform creates all infrastructure:

```bash
terraform apply -auto-approve \
  -var="gcp_project_id=my-project" \
  -var="app_name=my-app" \
  -var="gcp_region=us-central1" \
  -var="enable_firestore=true" \
  -var="enable_pubsub=false" \
  ... (all enabled services)
```

What Terraform creates:
- Cloud Run service
- Service accounts and IAM roles
- Enabled APIs (Firestore, Storage, etc.)
- Resource names (buckets, queues, topics)
- Environment variable mappings

Terraform writes state to the remote bucket. State includes:
- What resources were created
- Their IDs and configurations
- Service account email, Cloud Run URL, etc.

If any error occurs, the script exits. Check logs:
```bash
terraform validate      # Check syntax
terraform apply -out=plan.txt  # See what would change
```

## Step 7: Health Check

Once deployed, Zilch verifies the app is responding:

```bash
RUN_URL=$(terraform output -raw cloud_run_url)
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$RUN_URL")
```

Expected responses:
- `2xx` — App is healthy ✅
- `401` — Auth required, but app is running ✅
- `404` — App doesn't have a root handler, but container is running ✅
- `5xx` or timeout — App crashed or failed startup ❌

If health checks fail, the script shows:
```
⚠️ Warning: App deployed but health checks timed out.
Review your Cloud Run execution engine console logs...
```

Troubleshooting: [Health Checks](../topics/troubleshooting/health-checks.md)

## Step 8: Save Configuration

Zilch persists your choices to `.zilch.config`:

```bash
cat > .zilch.config << EOF
gcp_project_id=my-project
app_name=my-app
gcp_region=us-central1
enable_firestore=true
enable_pubsub=false
... (all settings)
EOF
```

On the next run, these become defaults — you can just press Enter to redeploy with the same config.

## Step 9: Display Summary

Finally, the script shows your deployed infrastructure:

```
🎉 SUCCESS: Zilch Architecture Instantiated Successfully!
📍 Service Endpoint URL: https://my-app-abc123.run.app
👤 Bound Run Identity:   my-app@my-project.iam.gserviceaccount.com
🌐 Operational Region:   us-central1

📋 Available Runtime Application Discovery Environment Tunnels:
  ↳ ZILCH_FIRESTORE_DATABASE : (default)
  ↳ ZILCH_STORAGE_BUCKET     : my-app-storage-a1b2c3d4
  ...
```

This tells you:
- Where your app is running (URL)
- What identity it's using (service account)
- What [environment variables](environment-variables.md) are available
- What to do next

## After Deployment

### Option 1: Deploy Your Code
Deploy your application code to Cloud Run:

```bash
gcloud run deploy my-app --source .
```

This builds your code in a Docker container and uploads it to Cloud Run. (Replaces the default "hello world" image.)

### Option 2: Set Up Automatic Deployments
If you enabled [Cloud Build](../services/cloud-build.md), connect your GitHub repo:
- Visit: https://console.cloud.google.com/cloud-build/repositories?project=my-project
- Click "Connect Repository"
- Select your GitHub account and repo
- Authorize Cloud Build

Now every push to `main` automatically builds and deploys.

### Option 3: Access Services
Start using the enabled services in your code:

```python
import os
from google.cloud import firestore

# Cloud Run provides environment variables + service account auth
db_name = os.getenv('ZILCH_FIRESTORE_DATABASE')
db = firestore.Client(database=db_name)

docs = db.collection('users').stream()
```

## Redeploying

To update infrastructure (enable/disable services):

```bash
./deploy.sh
# Change enable_* answers, or just re-confirm defaults
# Terraform applies changes incrementally
```

To update application code:

```bash
gcloud run deploy my-app --source .
# Or: git push main (if Cloud Build is enabled)
```

## Related

- **[Cloud Run](cloud-run.md)** — What gets deployed
- **[Terraform](terraform.md)** — Infrastructure declarations
- **[Configuration](configuration.md)** — .zilch.config details
- **[Remote State Backend](remote-state.md)** — Where state is stored
- **[Environment Variables](environment-variables.md)** — Runtime config

---

**Troubleshooting:** See [Deployment Failures](../topics/troubleshooting/deployment.md)
