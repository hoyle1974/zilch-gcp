# Zilch Phase 2 Design Specification

**Date:** 2026-06-14  
**Project:** Zilch - Scale-to-Zero GCP Application Stack  
**Phase:** Phase 2 (Cloud Build + Artifact Registry)  
**Status:** Design Review

---

## 1. Vision

Phase 2 transforms Zilch from infrastructure-only into a **GitOps-enabled platform** where:
- User's GitHub repo becomes the source of truth (both infra + app code)
- Pushing to `main` branch automatically deploys both infrastructure and application changes
- Zero manual deployment steps after initial setup
- Stays completely within Always Free tier (120 build-minutes/day, 0.5GB image storage)

---

## 2. Architecture Overview

### High-Level Flow

```
1. Initial Setup (./deploy.sh)
   └─ User runs once with .zilch.config
   └─ Terraform provisions GCP infra + Cloud Build trigger

2. Continuous Deployment (automatic)
   └─ Developer pushes to main branch
   └─ Cloud Build triggers automatically
   └─ Builds container from Dockerfile
   └─ Pushes to Artifact Registry
   └─ Cloud Run pulls + deploys new image
   └─ Optional: Terraform re-applies if infra changed
```

### Key Components

- **GitHub Repo** - Source of truth (app code + infra)
- **Cloud Build** - CI/CD orchestrator (watches repo, triggers on push)
- **Artifact Registry** - Container image storage (Cloud Run pulls from here)
- **Cloud Run** - Runs the app (auto-pulls latest image from registry)
- **GCP Secret Manager** - Stores sensitive values (app reads at runtime)

---

## 3. Configuration Strategy

### `.zilch.config` (Public-Safe, Committed to GitHub)

```
github_owner=your-username
github_repo=your-project-name
gcp_project_id=test-z-1-499406
app_name=my-app
region=us-central1
enable_cloud_build=true
enable_firestore=true
enable_secret_manager=true
enable_cloud_storage=true
enable_firebase_auth=true
enable_vertex_ai=false
```

**Purpose:** User configures Zilch once; `.zilch.config` defines the desired state.

**Security:** Contains only non-sensitive configuration. Safe to commit publicly.

### Secrets (NOT in `.zilch.config`)

**Rule:** Passwords, API keys, tokens NEVER go in `.zilch.config`.

**Where to store secrets:**
- GCP Secret Manager (app reads at runtime)
- Example: `gcloud secrets create my-api-key --data-file=-`
- App discovers secrets via `ZILCH_SECRET_PREFIX` env var
- Example: App reads `my-app-api-key` from Secret Manager

---

## 4. Deployment Workflow

### First Time: Initial Infrastructure Setup

```bash
$ cd my-project  # User's GitHub repo (contains Dockerfile + .zilch.config)
$ bash zilch-deploy.sh

# Script:
# 1. Reads .zilch.config
# 2. Validates GCP project access
# 3. Runs Terraform to create:
#    - Cloud Run service
#    - Cloud Build trigger (watches GitHub repo for pushes)
#    - Artifact Registry
#    - Optional services (Firestore, Secrets, etc.)
# 4. Prints success + next steps
```

### Daily Development: Push to Deploy

```bash
$ git push origin main

# Automatic (no user action):
# 1. Cloud Build detects push
# 2. Clones repo at commit
# 3. Builds container: docker build -f Dockerfile -t registry-image .
# 4. Pushes to Artifact Registry
# 5. Cloud Run auto-pulls latest image
# 6. App deployed (zero downtime)
```

### Infrastructure Changes: Push Terraform to Deploy

```bash
# User edits Terraform files in repo (e.g., add Firestore)
$ git push origin main

# Cloud Build:
# 1. Detects push
# 2. Runs `terraform apply` (if Terraform files changed)
# 3. Updates infrastructure
# 4. Rebuilds + redeploys app
```

---

## 5. Component Details

### 5.1 Cloud Build

**Resources Created:**
- `google_cloudbuild_trigger` - Watches GitHub repo, triggers on push to `main`
- Executes `cloudbuild.yaml` from repo (or auto-generated default)

**Build Steps (Default):**
1. Clone repo at commit
2. Build container: `docker build -t REGISTRY_IMAGE:latest .`
3. Push to Artifact Registry
4. (Optional) Deploy to Cloud Run OR wait for Cloud Run auto-pull

**Trigger Logic:**
- Only on pushes to `main` branch
- Skipped if only `.zilch.config` changed (no rebuild needed)

**Build Time:**
- Free tier: 120 build-minutes/day (plenty for hobby projects)
- Typical build: 2-5 minutes

### 5.2 Artifact Registry

**Purpose:** Store built container images

**Configuration:**
- Repository name: `{app_name}-images`
- Location: Same region as Cloud Run (us-central1, us-east1, or us-west1)
- Cleanup strategy: Keep last 5 images (prevents exceeding 0.5GB free tier)

**Cloud Run Integration:**
- Cloud Run service configured to pull from this registry
- On each Cloud Build push, Cloud Run auto-pulls the new image
- No manual `gcloud run deploy` needed

### 5.3 `.zilch.config` Parsing

**Phase 1 (`deploy.sh` initial run):**
- Script reads `.zilch.config`
- Extracts: `github_owner`, `github_repo`, feature toggles
- Validates config (required fields, format)
- Passes to Terraform

**Phase 2 and beyond:**
- `.zilch.config` is the source of truth
- Users edit it directly in GitHub
- Optional: Separate `zilch-update` command reads `.zilch.config` and applies changes
- Or: Users re-run `./deploy.sh` if they want interactive prompts (both workflows supported)

---

## 6. Security Model

### What Goes in `.zilch.config`

✅ **Safe to commit publicly:**
- GitHub owner/repo
- GCP project ID
- App name, region
- Feature toggles
- Build configuration

### What Never Goes in `.zilch.config`

❌ **NEVER commit to GitHub:**
- GCP service account keys
- API tokens or passwords
- Database credentials
- Third-party API keys
- Encryption keys

### Secret Storage Strategy

**For app runtime secrets:**
1. Create in GCP Secret Manager: `gcloud secrets create my-api-key --data-file=-`
2. App reads from Secret Manager at runtime
3. Cloud Run service account has `roles/secretmanager.secretAccessor` (auto-bound by Zilch)

**For Cloud Build secrets (if needed):**
- GitHub Secrets (in repo settings)
- Cloud Build reads via `_SECRET_NAME` substitution
- Used for building app (e.g., private package registry credentials)

---

## 7. GitHub Integration Details

### Initial Setup (First Time)

1. User creates GitHub repo with:
   - `Dockerfile` (defines how to build app)
   - `.zilch.config` (Zilch configuration)
   - App source code
   - Optional: `cloudbuild.yaml` (Cloud Build steps)

2. User runs `./deploy.sh` in this repo
   - Script reads `.zilch.config`
   - Creates Cloud Build trigger that watches this GitHub repo
   - Trigger authenticates via GitHub App (installed during first deploy)

### Automatic Deployments

- Cloud Build listens for pushes to `main` branch
- On push:
  - Clones repo at commit
  - Runs build steps (build container, push to registry)
  - Cloud Run auto-pulls new image

### Build Skipping (Optimization)

- If only `.zilch.config` or `*.md` files changed, skip build
- If Terraform files changed, also run `terraform apply`
- Configurable via `.gitattributes` or `cloudbuild.yaml`

---

## 8. Always Free Tier Compliance

### Cloud Build

- **Free tier:** 120 build-minutes/day
- **Zilch approach:** Typical build takes 3-5 minutes
- **Result:** ~24 builds/day possible (plenty for hobby projects)

### Artifact Registry

- **Free tier:** 0.5 GB/month storage
- **Zilch approach:** Keep last 5 images only (auto-cleanup)
- **Result:** Typical app image: ~500MB - 1GB, so 5 images = rotate frequently, stay under limit

### Cloud Run

- **Free tier:** 2M requests/month, 360K GB-seconds/month
- **Included:** Auto-scaling, no cost for idle time

---

## 9. Terraform & IaC Integration

### Files in User's Repo

```
my-project/
├── Dockerfile              # Container definition
├── .zilch.config          # Zilch configuration
├── main.tf                # User's infra (Terraform)
├── variables.tf           # Variables
├── src/                   # App source code
└── README.md
```

### Workflow for Infra Changes

User wants to add a Cloud SQL database:
1. Edit `main.tf` (add `google_sql_database_instance` resource)
2. Commit + push to `main`
3. Cloud Build detects push
4. Cloud Build runs `terraform apply`
5. Database created in GCP
6. App rebuilt and deployed

---

## 10. Success Criteria

✅ User runs `./deploy.sh` once → full infrastructure is live  
✅ User pushes code to `main` → automatic build + deploy (no manual steps)  
✅ Cloud Build completes in < 10 minutes  
✅ Artifact Registry stays under 0.5 GB (auto-cleanup)  
✅ `.zilch.config` is safe to commit publicly (no secrets)  
✅ Cloud Run pulls new image within 1 minute of Cloud Build push  
✅ All resources stay within Always Free tier  

---

## 11. Out of Scope (Phase 3+)

- Multi-branch deployments (staging, production) - Phase 3
- Canary deployments - Phase 3
- Custom build steps via `cloudbuild.yaml` - Phase 2.5
- GitOps-driven Terraform (Atlantis, Flux) - Phase 3+
- Container vulnerability scanning - Phase 2.5

---

## 12. Dependencies & Assumptions

- User has GitHub repo with `Dockerfile`
- User has GCP project with Cloud Build API enabled (Zilch enables it)
- User has `gcloud` CLI installed locally for initial `./deploy.sh`
- `.zilch.config` is committed to the repo (not in `.gitignore`)
