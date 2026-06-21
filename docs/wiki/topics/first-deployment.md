---
title: First Deployment Checklist
tags: [deployment, python, zilch.py, getting-started]
last_updated: 2026-06-20
source_count: 2
sources:
  - IMPLEMENTATION_SUMMARY.md
  - PYTHON_MIGRATION_PLAN.md
---

# First Deployment Checklist

Your checklist for a successful first deployment of Zilch infrastructure using the Python CLI (`zilch.py`).

## Pre-Deployment (5 minutes)

- [ ] **Create a GCP Project**
  - Go to https://console.cloud.google.com/projectcreate
  - Name it something like "zilch-test" or "my-app-project"
  - Note your Project ID (not the Project Name)

- [ ] **Enable Cloud Shell**
  - Click the Cloud Shell icon (>_ terminal icon) in the top right
  - Wait for Cloud Shell to load
  - Cloud Shell already has `gcloud`, `terraform`, and Python 3 preinstalled

- [ ] **Clone Zilch**
  ```bash
  git clone https://github.com/hoyle1974/zilch-gcp.git
  cd zilch-gcp
  ```

- [ ] **Set up the Python environment**
  ```bash
  python3 -m venv venv
  source venv/bin/activate
  make install
  # OR: pip install -r requirements.txt
  ```

- [ ] **Verify prerequisites**
  - You're logged in: `gcloud auth list`
  - You have Editor/Owner role on the project

## Deployment (3-5 minutes)

- [ ] **Run the deploy command**
  ```bash
  python3 zilch.py deploy
  ```

- [ ] **Answer prompts**
  - Project ID: Use the ID from step 1 (not the name)
  - App name: Something like "my-app" (lowercase, 3-30 chars — validated by `ZilchConfig`)
  - Region: Choose us-central1 (option 1) for best performance
  - Services: Start with just Core services (y/n for Phase 1)
  - Cloud Build: Say yes (enables automatic GitHub deployments)
  - GitHub: Provide your GitHub username and repo name

- [ ] **Wait for Terraform**
  - Takes 2-3 minutes
  - Watch for ✅ checkmarks
  - If errors occur, note them and check [Troubleshooting](troubleshooting/common.md)

  Want to see what would happen first, without changing anything?
  ```bash
  python3 zilch.py deploy --dry-run
  ```

## Post-Deployment (5 minutes)

- [ ] **Copy your Cloud Run URL**
  ```
  🎉 SUCCESS: Zilch Architecture Instantiated Successfully!
  📍 Service Endpoint URL: https://my-app-xyz.run.app
  ```
  Save this URL — it's your public app endpoint.

- [ ] **Verify infrastructure is running**
  ```bash
  curl https://my-app-xyz.run.app
  ```
  You should get a response (might be "Hello World" default image).

- [ ] **View your configuration**
  ```bash
  cat .zilch.config
  ```
  This file (validated and written by `config.py`'s `ZilchConfig`) saves your settings for the next deployment.

- [ ] **Check deployment status anytime**
  ```bash
  python3 zilch.py status
  ```
  Prints the Cloud Run URL, service account email, and storage bucket from the current Terraform outputs.

- [ ] **Check Cloud Run in console**
  - Visit: https://console.cloud.google.com/run
  - Select your region (us-central1, etc.)
  - Click your app name
  - See logs, metrics, settings

## Next Steps

### Option 1: Deploy Your Code
Replace the default "Hello World" image with your application:

```bash
gcloud run deploy YOUR_APP_NAME --source .
```

This builds your Docker container and deploys it.

### Option 2: Connect GitHub for Auto-Deployment
If you enabled Cloud Build during deployment:

1. Visit: https://console.cloud.google.com/cloud-build/repositories?project=YOUR_PROJECT_ID
2. Click "Connect Repository"
3. Select your GitHub repo
4. Authorize the Cloud Build GitHub App
5. Now every git push to `main` auto-deploys!

### Option 3: Use Your Services
Start writing code that uses Zilch services:

```python
import os
from google.cloud import firestore

# Environment variables from Zilch
db_name = os.getenv('ZILCH_FIRESTORE_DATABASE')
bucket_name = os.getenv('ZILCH_STORAGE_BUCKET')

# Service account auth is automatic
db = firestore.Client(database=db_name)
```

## Troubleshooting First Deployment

### ❌ "Health checks timed out"
- Means: Container started but app isn't responding
- Cause: App might not listen on `$PORT` or takes too long to start (the Python health check, `health_check.check_cloud_run_health()`, retries 3 times before giving up)
- Fix: The default "Hello World" image works; this means Zilch deployed correctly

### ❌ "Permission denied" error
- Cause: You don't have Editor role on the project (raised as a `GCPError` from `gcp.validate_iam_permissions()`)
- Fix: Ask someone with Owner role to grant you Editor
  ```bash
  gcloud projects add-iam-policy-binding PROJECT_ID \
    --member=user:YOUR_EMAIL \
    --role=roles/editor
  ```

### ❌ "Project not found"
- Cause: Wrong Project ID (used Project Name instead) — caught by `gcp.validate_project()`
- Fix: Use Project ID from Project Settings, not the display name

### ❌ Terraform errors
- Check that all APIs are enabled
- Verify you have Editor role
- Try running `python3 zilch.py deploy` again (sometimes transient — `terraform init` already retries 3 times automatically)
- Run `python3 zilch.py deploy --dry-run` to see a plan without applying

## Success Indicators

✅ You'll know deployment succeeded when you see:

```
=================================================================
 🎉 SUCCESS: Zilch Architecture Instantiated Successfully! 🎉
=================================================================
📍 Service Endpoint URL: https://my-app-xyz.run.app
👤 Bound Run Identity:   my-app@my-project.iam.gserviceaccount.com
🌐 Operational Region:   us-central1

📋 Available Runtime Application Discovery Environment Tunnels:
  ↳ ZILCH_FIRESTORE_DATABASE : (default)
  ↳ ZILCH_STORAGE_BUCKET     : my-app-storage-a1b2c3d4
  ...
```

## Cost Check

After deployment, verify you're within Always Free:

```bash
# View costs (should be $0)
gcloud billing accounts list
```

All Zilch services default to Always Free quotas. Monitor: https://console.cloud.google.com/billing/reports

---

**Congratulations!** Your Zilch infrastructure is running. Next: Deploy your code or connect GitHub.

**Links:** [Cloud Run](../entities/cloud-run.md) | [Always Free Tier](../entities/always-free-tier.md) | [Configuration](../entities/configuration.md) | [Deployment Workflow](../entities/deployment-workflow.md) | [Deployment Reliability](../entities/deployment-reliability.md)
