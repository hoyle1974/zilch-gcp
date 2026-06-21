---
title: Deployment Workflow
tags: [deployment, python, zilch.py, terraform, workflow]
last_updated: 2026-06-20
source_count: 2
sources:
  - IMPLEMENTATION_SUMMARY.md
  - PYTHON_MIGRATION_PLAN.md
---

# Deployment Workflow

The deployment workflow is the complete process from running `python3 zilch.py deploy` to having a running application on Cloud Run. Orchestration is implemented in Python (`zilch.py` and its supporting modules), not bash — the legacy `deploy.sh` script has been removed from the repository.

## Overview

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Prerequisites Check (tools, gcloud auth, IAM permissions)│
├─────────────────────────────────────────────────────────────┤
│ 2. Load Configuration (.zilch.config via Pydantic model)    │
├─────────────────────────────────────────────────────────────┤
│ 3. Interactive Prompts (project, region, services to enable)│
├─────────────────────────────────────────────────────────────┤
│ 4. Save Configuration (.zilch.config for next run)          │
├─────────────────────────────────────────────────────────────┤
│ 5. GCP Setup (project context, enable APIs, state bucket)   │
├─────────────────────────────────────────────────────────────┤
│ 6. Terraform Init (initialize Terraform with backend)        │
├─────────────────────────────────────────────────────────────┤
│ 7. State Reconciliation (sequential resource imports)        │
├─────────────────────────────────────────────────────────────┤
│ 8. Terraform Apply (create/update all infrastructure)        │
├─────────────────────────────────────────────────────────────┤
│ 9. Health Check (verify Cloud Run is responding)            │
├─────────────────────────────────────────────────────────────┤
│ 10. Display Summary (URLs, environment variables)           │
└─────────────────────────────────────────────────────────────┘
```

This sequence is implemented by the `deploy` command in `zilch.py`, which delegates to focused modules:

| Module | Responsibility |
|--------|-----------------|
| `config.py` | `ZilchConfig` Pydantic model — load/save/validate `.zilch.config` |
| `cli.py` | Interactive Click prompts (project, app name, region, services) |
| `gcp.py` | Tool checks, gcloud auth, IAM/Firestore permission checks, state bucket creation |
| `terraform.py` | `TerraformExecutor` (init/plan/apply/destroy/import) and `StateImporter` |
| `health_check.py` | Post-deployment Cloud Run health checks |
| `output.py` | Formatted/colored console output and the deployment summary |

## Step 1: Prerequisites Check

`zilch.py deploy` verifies you're ready to deploy via `gcp.py`:

✅ **Required tools** — `gcp.check_required_tools()` confirms `gcloud`, `terraform`, `curl`, and `bq` are all on `PATH` (and warns if not running in Cloud Shell, which has them preinstalled).

✅ **gcloud authentication** — `gcp.validate_gcloud_auth()` runs:
```bash
gcloud auth login  # If needed
```

✅ **GCP Project access** — `gcp.validate_project()` and `gcp.validate_iam_permissions()` confirm:
- The project exists and is reachable
- You have Editor or Owner role to create resources

If any check fails, `zilch.py` raises a `GCPError` with a clear message and recovery instructions, then exits with a non-zero status.

## Step 2: Load Configuration

`zilch.py` looks for `.zilch.config` in the current directory and loads it through `ZilchConfig.load_from_file()` (in `config.py`), which parses the key=value file and validates every field with Pydantic:

```bash
gcp_project_id=my-project
app_name=my-app
gcp_region=us-central1
enable_firestore=true
enable_pubsub=false
...
```

If no `.zilch.config` exists, `zilch.py` copies `.zilch.config.template` into place and asks you to edit it before re-running. If `.zilch.config` exists, validated defaults are pre-filled in prompts. See [Configuration](configuration.md) for the full field reference and validation rules.

## Step 3: Interactive Prompts

Unless you pass `--auto`, `zilch.py deploy` asks (via `cli.py`):

### 1. Project ID
```
👉 Enter your target GCP Project ID: my-project
```
Must be an existing GCP project where you have Editor/Owner role. Handled by `cli.get_project_id()`.

### 2. Application Name
```
👉 Enter your application name [zilch-app]: my-app
```
Used as a prefix for all resources (my-app-storage, my-app-jobs, etc.). Validated by `ZilchConfig`'s `app_name` field validator: 3-30 lowercase alphanumeric characters or hyphens (`^[a-z0-9-]{3,30}$`).

### 3. Region (Always Free Tier Only)
```
🌐 Choose your infrastructure anchor zone (Always Free Eligible):
  [1] us-central1 (Iowa - Preferred Default)
  [2] us-east1    (South Carolina)
  [3] us-west1    (Oregon)
Selection [1-3, default: 1]: 1
```
`cli.get_region()` collects the choice; `ZilchConfig`'s `gcp_region` validator strictly enforces these three [Always Free regions](always-free-tier.md) — any other value raises a validation error.

### 4. Services to Enable
```
❓ Enable Firestore NoSQL Database support? (y/n) [default: n]: y
❓ Enable Secret Manager Keys? (y/n) [default: n]: n
❓ Enable Cloud Storage Asset Buckets? (y/n) [default: n]: y
...
```
`cli.get_services_interactive()` walks every `enable_*` flag on `ZilchConfig` using `prompt_toggle()`. Enabled services:
- Get provisioned by Terraform
- Receive IAM roles for your service account
- Have [environment variables](environment-variables.md) passed to Cloud Run
- Count against [Always Free quotas](always-free-tier.md)

If you enable Cloud Scheduler or Cloud Monitoring, `cli.get_scheduler_config()` / `cli.get_monitoring_config()` collect their extra fields (cron expression, timezone, budget limit, etc.).

### 5. GitHub (if Cloud Build enabled)
```
⚙️  Cloud Build requires GitHub repository connection.
👉 Enter your GitHub username/org: myusername
👉 Enter your GitHub repository name: myrepo
```
Only asked if `enable_cloud_build` is true and `github_owner`/`github_repo` aren't already set. Used to connect GitHub → Cloud Build → Cloud Run.

## Step 4: Save Configuration

`zilch.py` persists the validated config immediately after prompts via `ZilchConfig.save_to_file(".zilch.config")`, before touching GCP. On the next run, these become defaults — pass `--auto` to skip prompts entirely and redeploy with the saved config.

## Step 5: GCP Setup

`_setup_gcp()` in `zilch.py` calls into `gcp.py` to:
- Set the active gcloud project context (`gcp.set_project_context()`)
- Enable required APIs for the selected services (`gcp.enable_required_apis()`)
- Create the remote state bucket if it doesn't already exist (`gcp.create_state_bucket()`):

```python
state_bucket = f"{project_id}-zilch-tfstate"
```

If the bucket already exists (from a previous run), Zilch reuses it.

**Why remote state?**
- Terraform state isn't lost if you clear Cloud Shell
- Multiple deployments from different shells work cleanly
- State is stored securely in Cloud Storage

`gcp.py` also detects a stale Terraform state lock at this point (`check_terraform_lock_exists()`) and offers to remove it (`remove_terraform_lock()`) — see [Deployment Reliability](deployment-reliability.md).

## Step 6: Terraform Init

`TerraformExecutor.init()` (in `terraform.py`) wraps `terraform init` as a subprocess:

```bash
terraform -chdir=<script_dir> init \
  -backend-config="bucket=${STATE_BUCKET}" \
  -backend-config="prefix=terraform/state/${APP_NAME}" \
  -reconfigure
```

This:
- Downloads the Google provider
- Creates `.terraform/` directory
- Connects to the remote state bucket
- Sets up Terraform for the first time (or reconfigures for a new bucket)

`TerraformExecutor.init()` retries up to 3 times on failure (handles transient network issues).

## Step 7: State Reconciliation

Before applying, `_reconcile_state()` builds a list of resources that may already exist outside Terraform's state (service accounts, Cloud Run service, Artifact Registry repo, and conditionally BigQuery, Firestore, Cloud Build logs bucket, Cloud Tasks queue, KMS keyring/key) and hands them to `StateImporter.import_all()`.

`StateImporter` imports resources **sequentially**, not in parallel — concurrent `terraform import` calls against the same remote state file fail with "Error acquiring the state lock," so each resource is imported one at a time with retry-on-failure. See [Deployment Reliability](deployment-reliability.md) for details on this design choice.

## Step 8: Terraform Apply

`TerraformExecutor.apply()` wraps `terraform apply`:

```bash
terraform -chdir=<script_dir> apply -auto-approve \
  -var="gcp_project_id=my-project" \
  -var="app_name=my-app" \
  -var="gcp_region=us-central1" \
  -var="enable_firestore=true" \
  -var="enable_pubsub=false" \
  ... (all ZilchConfig fields, via to_terraform_vars())
```

What Terraform creates:
- Cloud Run service
- Service accounts and IAM roles
- Enabled APIs (Firestore, Storage, etc.)
- Resource names (buckets, queues, topics)
- Environment variable mappings

Terraform writes state to the remote bucket. State includes what resources were created, their IDs/configurations, the service account email, Cloud Run URL, etc.

Run `python3 zilch.py deploy --dry-run` (alias `--preview`) to call `TerraformExecutor.plan()` instead of `apply()` — it shows what would change without applying anything.

If apply fails, `TerraformError` is raised and `zilch.py` exits with a clear message. You can also inspect manually:
```bash
terraform validate
terraform plan
```

## Step 9: Health Check

Once deployed, `_run_health_checks()` calls `health_check.check_cloud_run_health()`:

```python
url = tf.get_output("cloud_run_url")
check_cloud_run_health(url, retries=3, timeout=10)
```

It issues an HTTP GET with retry and backoff. Expected responses:
- `2xx` — App is healthy ✅
- `401` — Auth required, but app is running ✅
- `404` — App doesn't have a root handler, but container is running ✅
- `5xx` or timeout — App crashed or failed startup ❌ (logged as a warning, deployment is not rolled back)

Troubleshooting: [Health Checks](../topics/troubleshooting/health-checks.md)

## Step 10: Display Summary

Finally, `_print_summary()` collects Terraform outputs and billing info and calls `output.print_deployment_summary()`:

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

This tells you where your app is running (URL), what identity it's using (service account), what [environment variables](environment-variables.md) are available, and what to do next.

## After Deployment

### Option 1: Deploy Your Code
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
python3 zilch.py deploy
# Change enable_* answers, or just re-confirm defaults
# Terraform applies changes incrementally
```

Or non-interactively with the saved config:

```bash
python3 zilch.py deploy --auto
```

To update application code:

```bash
gcloud run deploy my-app --source .
# Or: git push main (if Cloud Build is enabled)
```

## Tearing Down

```bash
python3 zilch.py teardown          # Interactive, requires typed confirmations
python3 zilch.py teardown --force  # Skips confirmations
```

`teardown` is implemented entirely in Python (`zilch.py`'s `teardown` command) — it runs `terraform destroy`, then performs manual cleanup of resources Terraform might have missed, removes the state bucket, and clears local Terraform state files.

## Related

- **[Cloud Run](cloud-run.md)** — What gets deployed
- **[Terraform](terraform.md)** — Infrastructure declarations
- **[Configuration](configuration.md)** — `.zilch.config` and `ZilchConfig` details
- **[Deployment Reliability](deployment-reliability.md)** — Error handling, retries, state reconciliation
- **[Remote State Backend](remote-state.md)** — Where state is stored
- **[Environment Variables](environment-variables.md)** — Runtime config

---

**Troubleshooting:** See [Deployment Failures](../topics/troubleshooting/deployment.md) and [Common Issues](../topics/troubleshooting/common.md)
