# Zilch MVP Design Specification

**Date:** 2026-06-13  
**Project:** Zilch - Scale-to-Zero GCP Application Stack  
**Scope:** Phase 1 (MVP)  
**Status:** Design Review

---

## 1. Project Vision

Zilch helps solo developers, indie hackers, and non-backend engineers spin up a 100% free (scale-to-zero) application stack on Google Cloud Platform without touching the GCP web UI. It leverages Google Cloud Shell (web-based IDE) and Terraform to automate infrastructure provisioning.

**MVP Goal:** Deploy a working Cloud Run application with optional companion services (Firestore, Secrets, Cloud Storage, Firebase Auth, Vertex AI) in <5 minutes via a single interactive script.

---

## 2. Architecture Overview

### High-Level Flow

1. User opens Cloud Shell and runs: `chmod +x deploy.sh && ./deploy.sh`
2. Script validates: gcloud authentication, GCP project access
3. Script prompts: GCP Project ID, application name, feature toggles (5 optional services)
4. Script exports variables and runs: `terraform init && terraform apply -auto-approve`
5. Terraform provisions: Cloud Run + service account, plus enabled optional services
6. Script validates: Cloud Run health check (curl endpoint, retry 3x)
7. Script prints: Summary table with URLs, resource names, service account email
8. User receives: Environment variable names to use in their app code

### Key Design Decisions

- **Always Free Tier Enforcement:** All resources provisioned in `us-central1` (Iowa), `us-east1` (South Carolina), or `us-west1` (Oregon) only. Terraform validation blocks other regions.
- **Opt-In Philosophy:** All optional services default to `false`. Users explicitly enable what they need.
- **Service Account First:** Every deployment gets a dedicated, least-privilege service account. IAM bindings are conditional based on enabled services.
- **No Local State:** All Terraform state lives in GCP (Cloud Storage backend). No `.tfvars` files in repo.
- **Environment Variable Injection:** Resource IDs/names are injected as env vars into Cloud Run at deploy time. App discovers services by reading env vars + using Google Cloud SDKs with Application Default Credentials.

---

## 3. File Structure

```
zilch-gcp/
├── README.md                              # Quick intro, "Get Started" link to tutorial
├── tutorial.md                            # Cloud Shell interactive walkthrough (right sidebar)
├── deploy.sh                              # Interactive setup script (bash)
├── main.tf                                # Core infrastructure + all service toggles
├── variables.tf                           # Input variable definitions + validation
├── outputs.tf                             # Terraform outputs (URLs, resource IDs)
├── backend.tf                             # Terraform backend config (remote state in Cloud Storage)
├── terraform.tfvars.example               # Reference template (never committed)
├── .gitignore                             # Ignore .tfvars, .terraform/, state files
├── .github/workflows/validate.yml         # Optional: pre-commit Terraform linting
├── docs/
│   ├── superpowers/specs/
│   │   └── 2026-06-13-zilch-mvp-design.md (this file)
│   └── PHASE_2_TEMPLATE.md                # Instructions for adding Cloud Build, Artifact Registry
└── examples/
    └── example-app.py                     # (Phase 1.5) Simple Python app showing SDK usage
```

---

## 4. Deploy Script (`deploy.sh`) Behavior

### Execution Flow

```
┌─ Check Auth
│  └─ gcloud auth list → if not authenticated, prompt to run `gcloud auth login` → exit
├─ Get Project ID
│  └─ Prompt user: "Enter your GCP Project ID"
│  └─ Validate: gcloud projects describe <id> (fail if not found)
├─ Get App Name
│  └─ Prompt user: "Enter your application name (e.g., my-awesome-app)"
│  └─ Validate: alphanumeric, hyphens only, 3-30 chars
├─ Get Region (optional)
│  └─ Prompt user: "Choose region: [1] us-central1 (default) [2] us-east1 [3] us-west1"
│  └─ Set default: us-central1
├─ Feature Toggles
│  ├─ "Enable Firestore? (y/n)" → TF_VAR_enable_firestore
│  ├─ "Enable Secret Manager? (y/n)" → TF_VAR_enable_secret_manager
│  ├─ "Enable Vertex AI? (y/n)" → TF_VAR_enable_vertex_ai
│  ├─ "Enable Cloud Storage? (y/n)" → TF_VAR_enable_cloud_storage
│  └─ "Enable Firebase Auth? (y/n)" → TF_VAR_enable_firebase_auth
├─ State Bucket Bootstrap
│  ├─ Check if state bucket exists: gs://${PROJECT_ID}-zilch-tfstate
│  ├─ If not: gcloud storage buckets create gs://${PROJECT_ID}-zilch-tfstate --location=$REGION
│  └─ (Non-backend engineers don't manually create buckets; deploy.sh handles it)
├─ Terraform
│  ├─ Run: terraform init -backend-config="bucket=${PROJECT_ID}-zilch-tfstate"
│  │        (initializes with remote state backend pointing to the bootstrap bucket)
│  ├─ Run: terraform apply -auto-approve \
│  │        -var="gcp_project_id=$PROJECT_ID" \
│  │        -var="app_name=$APP_NAME" \
│  │        -var="gcp_region=$REGION" \
│  │        -var="enable_firestore=$FIRESTORE" \
│  │        ... (other toggles)
│  └─ On error: print Terraform error + helpful hint → exit 1
├─ Validation
│  ├─ Extract Cloud Run URL from terraform output
│  ├─ Health check: curl -s https://<URL>/ (retry 3x with 5s backoff, expect HTTP 200)
│  └─ On failure: print retry count + suggest troubleshooting
└─ Summary
   ├─ Print: ✅ Zilch deployed successfully!
   ├─ Print: Cloud Run URL, Service Account, Enabled Features
   ├─ Print: Environment variables your app should read
   └─ Print: Next steps (deploy your code, configure secrets, view logs)
```

### Error Handling Strategy (Hybrid)

**Fail Fast (validation stage):**
- Missing gcloud auth → exit immediately with clear message
- Invalid project ID → exit with "project not found" hint
- Invalid app name → exit with format requirements

**Graceful Failure (Terraform stage):**
- Terraform apply fails → print error + context (common causes: quota exceeded, missing permissions, API not enabled)
- Health check timeout → retry 3x, then print troubleshooting steps (check Cloud Run logs, verify app is stateless)

---

## 5. Terraform Configuration (`main.tf`, `variables.tf` & `backend.tf`)

### Backend Configuration (`backend.tf`)

The state bucket is created by `deploy.sh` before Terraform runs. The backend config is initialized dynamically at runtime:

```hcl
terraform {
  backend "gcs" {
    # Bucket name is passed via -backend-config flag in deploy.sh
    # Example: terraform init -backend-config="bucket=my-project-zilch-tfstate"
  }
}
```

This approach avoids hardcoding bucket names and supports multi-user/multi-project setups.

### Core Resources (Always Provisioned)

```hcl
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# Provider
provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

# Enable Required APIs
resource "google_project_service" "run" {
  service = "run.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "artifact_registry" {
  service = "artifactregistry.googleapis.com"
  disable_on_destroy = false
}

# Dedicated Service Account
resource "google_service_account" "app" {
  account_id   = var.app_name
  display_name = "Service account for ${var.app_name}"
}

# Cloud Run Service (public, Hello World image)
resource "google_cloud_run_service" "app" {
  name     = var.app_name
  location = var.gcp_region
  template {
    spec {
      service_account_name = google_service_account.app.email
      containers {
        image = "gcr.io/cloudrun/hello:latest"
        env {
          name  = "ZILCH_PROJECT_ID"
          value = var.gcp_project_id
        }
        env {
          name  = "ZILCH_APP_NAME"
          value = var.app_name
        }
        # Conditional env vars for enabled services (added below)
      }
    }
  }
}

# Cloud Run IAM: Allow public invocation
resource "google_cloud_run_service_iam_member" "public" {
  service  = google_cloud_run_service.app.name
  location = google_cloud_run_service.app.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}
```

### Optional Service Resources (Count-Based Toggles)

#### Firestore
```hcl
# Note: Free tier only supports the "(default)" database ID.
# Additional named databases incur hourly fees.
resource "google_firestore_database" "default" {
  count    = var.enable_firestore ? 1 : 0
  project  = var.gcp_project_id
  name     = "(default)"
  location = var.gcp_region
  type     = "FIRESTORE_NATIVE"
}

resource "google_project_iam_member" "firestore" {
  count   = var.enable_firestore ? 1 : 0
  project = var.gcp_project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.app.email}"
}
```

#### Secret Manager
```hcl
resource "google_secret_manager_secret" "example" {
  count   = var.enable_secret_manager ? 1 : 0
  project = var.gcp_project_id
  secret_id = "${var.app_name}-example-secret"
  replication {
    automatic = true
  }
}

resource "google_secret_manager_secret_version" "example" {
  count   = var.enable_secret_manager ? 1 : 0
  secret  = google_secret_manager_secret.example[0].id
  secret_data = "placeholder-secret-value"
}

resource "google_project_iam_member" "secret_manager" {
  count   = var.enable_secret_manager ? 1 : 0
  project = var.gcp_project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.app.email}"
}
```

#### Cloud Storage
```hcl
# Generate a random suffix to ensure globally unique bucket names
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "google_storage_bucket" "app" {
  count         = var.enable_cloud_storage ? 1 : 0
  project       = var.gcp_project_id
  name          = "${var.app_name}-storage-${random_id.bucket_suffix.hex}"
  location      = var.gcp_region
  force_destroy = true
}

resource "google_project_iam_member" "storage" {
  count   = var.enable_cloud_storage ? 1 : 0
  project = var.gcp_project_id
  role    = "roles/storage.objectUser"
  member  = "serviceAccount:${google_service_account.app.email}"
}
```

#### Firebase Auth
```hcl
resource "google_firebase_project" "default" {
  count   = var.enable_firebase_auth ? 1 : 0
  project = var.gcp_project_id
}

resource "google_project_iam_member" "firebase" {
  count   = var.enable_firebase_auth ? 1 : 0
  project = var.gcp_project_id
  role    = "roles/firebase.admin"
  member  = "serviceAccount:${google_service_account.app.email}"
}
```

#### Vertex AI
```hcl
resource "google_project_service" "aiplatform" {
  count   = var.enable_vertex_ai ? 1 : 0
  service = "aiplatform.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_iam_member" "vertex_ai" {
  count   = var.enable_vertex_ai ? 1 : 0
  project = var.gcp_project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.app.email}"
}
```

### Dynamic Environment Variables

The Cloud Run service injects conditional env vars using deterministic naming (no circular dependencies on resource outputs):

```hcl
# In google_cloud_run_service template.spec.containers block:

# Always-present env vars
env {
  name  = "ZILCH_PROJECT_ID"
  value = var.gcp_project_id
}

env {
  name  = "ZILCH_APP_NAME"
  value = var.app_name
}

# Conditional env vars (use ternary operators on variables only, not resource outputs)
env {
  name  = "ZILCH_FIRESTORE_DATABASE"
  value = var.enable_firestore ? "(default)" : ""
}

env {
  name  = "ZILCH_SECRET_PREFIX"
  value = var.enable_secret_manager ? "${var.app_name}-" : ""
}

env {
  name  = "ZILCH_STORAGE_BUCKET"
  value = var.enable_cloud_storage ? "${var.app_name}-storage-${random_id.bucket_suffix.hex}" : ""
}

env {
  name  = "ZILCH_VERTEX_AI_ENABLED"
  value = var.enable_vertex_ai ? "true" : ""
}

env {
  name  = "ZILCH_FIREBASE_ENABLED"
  value = var.enable_firebase_auth ? "true" : ""
}
```

**Design rationale:** Each env var is computed from input variables only (using ternary operators), not from resource outputs. This avoids circular dependencies and ensures the Cloud Run service can build its environment block deterministically before resources are created.

### Variables File (`variables.tf`)

```hcl
variable "gcp_project_id" {
  type        = string
  description = "GCP Project ID where resources will be created"
  validation {
    condition     = can(regex("^[a-z0-9-]{6,30}$", var.gcp_project_id))
    error_message = "Project ID must be 6-30 chars, lowercase letters, numbers, hyphens only"
  }
}

variable "gcp_region" {
  type        = string
  default     = "us-central1"
  description = "GCP region (must be Always Free tier eligible)"
  validation {
    condition     = contains(["us-central1", "us-east1", "us-west1"], var.gcp_region)
    error_message = "Region must be us-central1, us-east1, or us-west1 for Always Free tier"
  }
}

variable "app_name" {
  type        = string
  description = "Application name (used as resource prefix)"
  validation {
    condition     = can(regex("^[a-z0-9-]{3,30}$", var.app_name))
    error_message = "App name must be 3-30 chars, lowercase letters, numbers, hyphens only"
  }
}

variable "enable_firestore" {
  type        = bool
  default     = false
  description = "Enable Firestore (Native Mode) database"
}

variable "enable_secret_manager" {
  type        = bool
  default     = false
  description = "Enable Secret Manager for secure credential storage"
}

variable "enable_vertex_ai" {
  type        = bool
  default     = false
  description = "Enable Vertex AI (includes Gemini API access)"
}

variable "enable_cloud_storage" {
  type        = bool
  default     = false
  description = "Enable Cloud Storage bucket for file uploads/downloads"
}

variable "enable_firebase_auth" {
  type        = bool
  default     = false
  description = "Enable Firebase Authentication"
}
```

### Outputs File (`outputs.tf`)

```hcl
output "cloud_run_url" {
  value       = google_cloud_run_service.app.status[0].url
  description = "The public URL of the Cloud Run service"
}

output "service_account_email" {
  value       = google_service_account.app.email
  description = "Service account email for the Cloud Run service"
}

output "firestore_database" {
  value       = var.enable_firestore ? google_firestore_database.default[0].name : null
  description = "Firestore database name (if enabled)"
}

output "secret_prefix" {
  value       = var.enable_secret_manager ? "${var.app_name}-" : null
  description = "Prefix for secrets in Secret Manager (if enabled)"
}

output "storage_bucket" {
  value       = var.enable_cloud_storage ? google_storage_bucket.app[0].name : null
  description = "Cloud Storage bucket name (if enabled)"
}

output "gcp_project_id" {
  value       = var.gcp_project_id
  description = "GCP Project ID"
}

output "gcp_region" {
  value       = var.gcp_region
  description = "GCP Region"
}

output "app_name" {
  value       = var.app_name
  description = "Application name"
}
```

---

## 6. Tutorial (`tutorial.md`)

### Structure

**Section 1: Quick Start (top, visible immediately)**
- One-line pitch: "Zilch deploys a scale-to-zero app on GCP in <5 minutes"
- The command: ````bash\nchmod +x deploy.sh && ./deploy.sh\n````
- "That's it!"

**Section 2: Expandable Sections (for those who want details)**
- What is Zilch? (mission statement)
- What is Cloud Shell? (why we use it)
- What services does Zilch offer?
- How does Terraform work?
- Troubleshooting: Common errors & fixes

**Section 3: Next Steps**
- Deploying your own code (gcloud run deploy)
- Accessing services from your app (code snippets)
- Monitoring & logs (gcloud run logs)
- **If Firebase Auth enabled:** Direct link to Firebase Console for configuring providers (Email, Google, etc.): `https://console.firebase.google.com/project/${PROJECT_ID}/authentication`

---

## 7. Service Discovery & Access Pattern

### How Apps Access Services

1. **Cloud Run automatically provides:**
   - `GOOGLE_CLOUD_PROJECT` env var (set by Google Cloud)
   - Bound service account with IAM roles
   - Application Default Credentials (ADC) in SDKs

2. **App reads resource names from env vars:**
   ```python
   # Example: Python app reading Firestore
   import os
   from google.cloud import firestore
   
   db = firestore.Client(database=os.getenv('ZILCH_FIRESTORE_DATABASE'))
   ```

3. **Environment variables injected by Terraform:**

| Service | Env Var | Example |
|---------|---------|---------|
| Firestore | `ZILCH_FIRESTORE_DATABASE` | `my-app` |
| Secret Manager | `ZILCH_SECRET_PREFIX` | `my-app-` |
| Cloud Storage | `ZILCH_STORAGE_BUCKET` | `my-app-storage-proj123` |
| Vertex AI | `ZILCH_VERTEX_AI_ENABLED` | `true` |
| Firebase Auth | `ZILCH_FIREBASE_ENABLED` | `true` |

4. **Deploy.sh prints these env var names in the summary,** so developers know what to configure in their app.

---

## 8. Post-Deploy Validation

After Terraform succeeds:

1. **Extract Cloud Run URL** from `terraform output cloud_run_url`
2. **Health check:** 
   ```bash
   curl -s --max-time 10 https://<URL>/
   ```
   - Expect: HTTP 200, response contains "Hello"
   - Retry: 3 times with 5-second backoff
   - If all retries fail: print troubleshooting hint (check logs, Cloud Run permissions, app startup time)
3. **Print summary table:**
   ```
   ✅ Zilch Deployed Successfully!
   
   Cloud Run Service: my-awesome-app
   URL: https://my-awesome-app-abc123.run.app
   Region: us-central1
   Service Account: my-awesome-app@my-project.iam.gserviceaccount.com
   
   Enabled Features:
   ✓ Firestore (ZILCH_FIRESTORE_DATABASE=my-awesome-app)
   ✓ Secret Manager (ZILCH_SECRET_PREFIX=my-awesome-app-)
   ✓ Vertex AI (ZILCH_VERTEX_AI_ENABLED=true)
   
   Next Steps:
   1. Deploy your code: gcloud run deploy my-awesome-app --source .
   2. Set a secret: gcloud secrets create my-awesome-app-api-key --data-file=-
   3. View logs: gcloud run logs read my-awesome-app --region=us-central1
   4. See examples: https://github.com/zilch/examples
   ```

---

## 9. Adding Services Template (Phase 2 & Beyond)

Every new service follows this reusable checklist:

### Checklist for Adding [Service Name]

1. **Define Variable** (`variables.tf`)
   - Add: `variable "enable_<service>" { type = bool, default = false }`

2. **Create Resource** (`main.tf`)
   - Add resource block with `count = var.enable_<service> ? 1 : 0`
   - Enable required APIs in `google_project_service` blocks

3. **Bind IAM** (`main.tf`)
   - Determine role(s) needed by Cloud Run service account
   - Add `google_project_iam_member` block (conditional)

4. **Update Cloud Run** (`main.tf`)
   - Add env var(s) to `locals.env_vars` (conditional)
   - Export resource ID/name for app discovery

5. **Add Output** (`outputs.tf`)
   - Export resource ID/name: `value = var.enable_<service> ? resource[0].name : null`

6. **Update Script** (`deploy.sh`)
   - Add prompt: `read -p "Enable [Service]? (y/n): " SERVICE_RESPONSE`
   - Export: `export TF_VAR_enable_<service>=$([ "$SERVICE_RESPONSE" = "y" ] && echo "true" || echo "false")`

7. **Add Validation** (`deploy.sh` post-deploy)
   - Test service is accessible (API call, query, etc.)
   - Print in summary table

8. **Document** (`tutorial.md`, `README.md`)
   - Add usage example
   - Show env var name
   - Link to Google Cloud docs

9. **Write Phase 2/3 PR** with these changes

---

## 10. Scope & Dependencies

### Phase 1 (MVP) — This Design
- Cloud Run (public, always-free tier)
- Firestore (optional)
- Secret Manager (optional)
- Cloud Storage (optional)
- Firebase Auth (optional)
- Vertex AI (optional)

### Phase 2 (Build Automation)
- Cloud Build (CI/CD pipeline)
- Artifact Registry (container image storage + auto-cleanup)

### Phase 3 (Advanced)
- Pub/Sub (event streaming)
- Cloud Tasks (async job queues)
- BigQuery (analytics)
- Cloud KMS (encryption)
- Vision AI, Speech-to-Text, Translation APIs

---

## 11. Always Free Tier Compliance

**Regions enforced (Terraform validation):**
- `us-central1` (Iowa) — preferred, lowest latency for US
- `us-east1` (South Carolina)
- `us-west1` (Oregon)

**Free tier quotas (per service, Phase 1):**
- Cloud Run: 2M requests/month, 360K GB-seconds/month
- Firestore: 1GB storage, 50K reads/day, 20K writes/day
- Secret Manager: 6 active secrets, 10K API calls/month
- Cloud Storage: 5GB storage, 1GB/month download
- Firebase Auth: Free tier for basic auth (no SMS costs)
- Vertex AI: Free API calls (Gemini API within quota)

Deploy.sh will print: "Your app is running on Google's Always Free tier. See https://cloud.google.com/always-free for quotas."

---

## 12. Success Criteria

✅ User runs `./deploy.sh` in Cloud Shell  
✅ Script prompts for project ID, app name, feature toggles  
✅ Terraform provisions all requested resources in <2 minutes  
✅ Cloud Run service is publicly accessible and responds to requests  
✅ All IAM bindings are correct (app can access enabled services)  
✅ Deploy.sh prints summary with env var names  
✅ User can immediately write code using the env vars and Google Cloud SDKs  
✅ No manual GCP web UI steps required  
✅ No local `.tfvars` or state files in git  
✅ All resources in Always Free-eligible regions  

---

## 13. Out of Scope (Phase 2+)

- Custom container image deployment (users will do `gcloud run deploy`)
- CI/CD pipeline (Cloud Build — Phase 2)
- Multi-region setup
- Private Cloud Run (always public in Phase 1)
- Terraform state management (will use Cloud Storage backend auto-created by GCP)
- Example application code (will provide in separate repo or Phase 2)
