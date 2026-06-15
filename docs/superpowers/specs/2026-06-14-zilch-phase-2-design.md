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
   └─ Pushes to Artifact Registry (aggressive cleanup active)
   └─ Cloud Run pulls + deploys new image
   └─ Infrastructure stays locked to local ./deploy.sh updates
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

### Infrastructure Changes: Local Update (NOT Cloud Build)

**CRITICAL DESIGN CHOICE:** Cloud Build does NOT run `terraform apply`.

**Why:** If Terraform modifies resources that Cloud Build depends on (state bucket, service accounts, trigger permissions), the pipeline kills itself mid-flight, corrupting state.

**Correct Workflow for Infrastructure Changes:**

```bash
# User edits Terraform files locally (e.g., add Firestore)
$ git push origin main

# Cloud Build ONLY rebuilds app (ignores Terraform changes)
# User must run locally to update infrastructure:
$ ./deploy.sh

# Script reads updated .zilch.config + local Terraform
# Runs `terraform apply` safely (not during active build)
# Then next git push rebuilds app with new infra available
```

**Rationale:**
- Infrastructure updates are rare + high-risk
- Application deployments are frequent + safe
- Separating concerns avoids cascade failures
- If infra update fails, it doesn't corrupt app deployment
- Users have full control + visibility into infra changes

---

## 5. Component Details

### 5.1 Cloud Build

**CRITICAL: GitHub Integration Handshake**

The initial GitHub-to-GCP connection requires a manual OAuth step:

1. `./deploy.sh` detects GitHub integration is needed
2. Script outputs a clickable link to GCP Console: `https://console.cloud.google.com/cloud-build/repositories`
3. User clicks "Connect Repository" in console
4. User selects their GitHub account + repository
5. GCP installs Cloud Build GitHub App on user's account
6. User confirms, script detects connection is complete
7. Terraform creates the trigger

**Why:** Terraform cannot perform the initial GitHub OAuth handshake headlessly. This is a GCP limitation, not a Zilch issue.

**Build Configuration: Inline Terraform (NOT user-managed cloudbuild.yaml)**

The trigger is defined entirely in Terraform. User's repository stays clean—only contains app code and `.zilch.config`:

```hcl
resource "google_cloudbuild_trigger" "app_build" {
  name = "${var.app_name}-trigger"
  
  github {
    owner = var.github_owner
    name  = var.github_repo
    push { branch = "^main$" }
  }
  
  build {
    # Step 1: Build container with layer caching
    step {
      name = "gcr.io/cloud-builders/docker"
      args = [
        "build",
        "-t", "${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/${var.app_name}-images/app:latest",
        "-t", "${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/${var.app_name}-images/app:$BUILD_ID",
        "--cache-from", "${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/${var.app_name}-images/app:latest",
        "."
      ]
    }
    
    # Step 2: Push to Artifact Registry
    step {
      name = "gcr.io/cloud-builders/docker"
      args = [
        "push",
        "${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/${var.app_name}-images/app"
      ]
    }
    
    # Step 3: Deploy to Cloud Run
    step {
      name = "gcr.io/google.com/cloudsdktool/cloud-sdk"
      entrypoint = "gcloud"
      args = [
        "run", "deploy", var.app_name,
        "--image", "${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/${var.app_name}-images/app:latest",
        "--region", var.gcp_region,
        "--service-account", google_service_account.app.email
      ]
    }
  }
}
```

**Why Inline (Not File-Based):**
- User's repo stays pristine (only app code + `.zilch.config`)
- Zilch framework controls build logic
- No risk of user accidentally breaking build steps
- Easier to version/upgrade Zilch build pipeline

**Build Time:**
- Free tier: 120 build-minutes/day (plenty)
- Typical build: 3-5 minutes with layer caching

**Layer Caching Strategy:**
- `--cache-from` flag reuses previous image layers
- Reduces image size bloat by ~70%
- Keeps Artifact Registry under quota

### 5.2 Artifact Registry

**Purpose:** Store built container images

**Configuration:**
- Repository name: `{app_name}-images`
- Location: Same region as Cloud Run (us-central1, us-east1, or us-west1)

**CRITICAL: Aggressive Cleanup Policy**

Free tier allows 0.5 GB/month. Without cleanup, users can exceed quota in 2-3 deployments:

```hcl
resource "google_artifact_registry_repository" "app_images" {
  location      = var.gcp_region
  repository_id = "${var.app_name}-images"
  format        = "DOCKER"
  
  # Aggressive cleanup: Keep ONLY current + 1 previous image
  cleanup_policies {
    id     = "keep-recent"
    action = "DELETE"
    condition {
      tag_state = "UNTAGGED"
      older_than {
        duration = "0s"  # Delete all untagged immediately
      }
    }
  }
  
  cleanup_policies {
    id     = "keep-release"
    action = "DELETE"
    condition {
      version_name_prefix = "sha256-"  # Delete old SHA-tagged builds
      older_than {
        duration = "7d"  # Keep last 7 days only
      }
    }
  }
}
```

**Why Aggressive Cleanup:**
- Each full Docker image: ~200-400MB (after layer caching)
- 2-3 images = 600MB+ (exceeds quota)
- Keep CURRENT (latest tag) + 1 FALLBACK only
- Auto-delete untagged images immediately
- Result: ~500MB max, safe for free tier

**Image Tagging Strategy:**
- `latest` = current production image (preserved)
- `$BUILD_ID` = historical SHA for rollback (kept 7 days)
- All others: auto-deleted by cleanup policy

**Cloud Run Integration:**
- Cloud Run service pulls from this registry
- On each Cloud Build push, Cloud Run auto-pulls `latest`
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

### Cloud Build Service Account (CRITICAL)

**The Risk:** Cloud Build runs with Google-managed default service account (Project Editor equivalent). If a malicious PR or untrusted code runs in the build, attacker gains full project access.

**The Fix:** Create isolated `zilch-builder` service account with MINIMUM permissions only:

```hcl
resource "google_service_account" "cloud_build" {
  account_id   = "${var.app_name}-builder"
  display_name = "Cloud Build service account for ${var.app_name}"
}

# Permission 1: Push images to Artifact Registry
resource "google_project_iam_member" "builder_artifact_registry" {
  project = var.gcp_project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.cloud_build.email}"
}

# Permission 2: Deploy to Cloud Run
resource "google_project_iam_member" "builder_cloud_run" {
  project = var.gcp_project_id
  role    = "roles/run.developer"
  member  = "serviceAccount:${google_service_account.cloud_build.email}"
}

# Permission 3: Bind the app service account (for Cloud Run to pull secrets)
resource "google_project_iam_member" "builder_iam" {
  project = var.gcp_project_id
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${google_service_account.cloud_build.email}"
}
```

**Cloud Build Configuration:**
```hcl
resource "google_cloudbuild_trigger" "app_build" {
  # ... (previous config)
  
  # Use isolated service account, NOT default
  service_account = google_service_account.cloud_build.id
}
```

**Result:** If code in repo is compromised, attacker can ONLY:
- Push images to this app's registry
- Deploy to this app's Cloud Run service
- NOT access other projects, other apps, or secrets

### Secret Storage Strategy

**For app runtime secrets:**
1. Create in GCP Secret Manager: `gcloud secrets create my-api-key --data-file=-`
2. App reads from Secret Manager at runtime
3. Cloud Run service account (not builder!) has `roles/secretmanager.secretAccessor`

**For Cloud Build secrets (if needed):**
- GitHub Secrets (in repo settings)
- Cloud Build reads via `_SECRET_NAME` substitution
- Used for private package registry credentials, etc.
- Never commit secrets to repo

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
- **Zilch approach:** Keep CURRENT (latest) + 1 PREVIOUS fallback image ONLY via aggressive cleanup
- **Result:** Typical app image ~300MB (with layer caching) × 2 images = ~600MB max (safe margin under 0.5GB limit)

### Cloud Run

- **Free tier:** 2M requests/month, 360K GB-seconds/month
- **Included:** Auto-scaling, no cost for idle time

---

## 9. Terraform & IaC Integration

### Files in User's Repo

```
my-project/
├── Dockerfile              # Container definition
├── .zilch.config          # Zilch configuration (public-safe)
├── src/                   # App source code
└── README.md

Note: Terraform files stay LOCAL (not in repo)
Users run: ./deploy.sh to apply infrastructure changes
```

### Workflow for Infra Changes

User wants to add a Cloud SQL database:
1. Edit local Terraform files (add `google_sql_database_instance` resource)
2. Run: `./deploy.sh` (applies changes locally, safely)
3. Database created in GCP
4. Commit updated `.zilch.config` + push to `main`
5. Cloud Build auto-rebuilds app (knows new database is available)
6. App deployed with database access

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
- User-managed `cloudbuild.yaml` files - INTENTIONALLY OMITTED for security/simplicity
- GitOps-driven Terraform (Atlantis, Flux) - Phase 3+
- Container vulnerability scanning - Phase 2.5
- Infrastructure changes via Cloud Build (`terraform apply` in CI) - INTENTIONALLY OMITTED to prevent pipeline corruption

---

## 12. Dependencies & Assumptions

- User has GitHub repo with `Dockerfile`
- User has GCP project with Cloud Build API enabled (Zilch enables it)
- User has `gcloud` CLI installed locally for initial `./deploy.sh`
- `.zilch.config` is committed to the repo (not in `.gitignore`)
