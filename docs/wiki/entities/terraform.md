# Terraform Infrastructure

Zilch uses Terraform (Infrastructure as Code) to define and manage all GCP resources in a reproducible, version-controlled way.

## What is Terraform?

Terraform is a tool for writing infrastructure as code. Instead of clicking buttons in the GCP console, you write `.tf` files that describe what infrastructure you want, and Terraform creates it.

**Benefits:**
- **Reproducible** — Deploy the same infrastructure every time
- **Version controlled** — Infrastructure changes tracked in git
- **Auditable** — See exactly what was created and why
- **Reusable** — Copy patterns to new projects
- **Destroy safely** — Tear down all resources cleanly

## Zilch's Terraform Structure

```
main.tf                  # Core Cloud Run + service definitions
variables.tf             # Input variables (what users can customize)
outputs.tf               # Output values (URLs, IDs, etc.)
backend.tf               # Remote state storage configuration
cloud_scheduler.tf       # Cloud Scheduler (Phase 4)
cloud_monitoring.tf      # Cloud Monitoring (Phase 4)
.terraform/              # Terraform modules cache (auto-generated)
.terraform.lock.hcl      # Dependency versions (for consistency)
terraform.tfvars         # Variable values (created by deploy.sh)
```

## How Zilch Uses Terraform

### 1. Deploy Script Collects Configuration
```bash
./deploy.sh
# You answer prompts:
# - GCP Project ID
# - App name
# - Region
# - Which services to enable
```

### 2. Variables Passed to Terraform
```bash
terraform apply \
  -var="gcp_project_id=my-project" \
  -var="app_name=my-app" \
  -var="enable_firestore=true" \
  -var="enable_pubsub=true" \
  ...
```

### 3. Terraform Creates/Updates Resources
- Creates Cloud Run service
- Creates enabled services (Firestore, Storage, etc.)
- Sets up IAM roles and permissions
- Writes state to remote backend (Cloud Storage)

### 4. Deploy Script Extracts Outputs
```bash
RUN_URL=$(terraform output -raw cloud_run_url)
echo "Your app is at: $RUN_URL"
```

## Key Terraform Concepts

### Resources
A "resource" is something you want to create. Examples:

```hcl
# Create a Cloud Run service
resource "google_cloud_run_v2_service" "app" {
  name     = var.app_name
  location = var.gcp_region
  # ... configuration
}

# Create a service account
resource "google_service_account" "app" {
  account_id   = var.app_name
  display_name = "Service account for ${var.app_name}"
}

# Create an IAM role binding
resource "google_project_iam_member" "firestore" {
  project = var.gcp_project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.app.email}"
}
```

### Variables
Variables let users customize without editing Terraform files:

```hcl
variable "app_name" {
  type        = string
  description = "Your application name"
  validation {
    condition     = can(regex("^[a-z0-9-]{3,30}$", var.app_name))
    error_message = "App name must be 3-30 lowercase alphanumeric characters or hyphens."
  }
}

variable "enable_firestore" {
  type        = bool
  default     = false
  description = "Enable Firestore NoSQL Database"
}
```

### Conditionals
Use `count` to create resources only if a feature is enabled:

```hcl
# Only create Firestore IAM binding if enable_firestore is true
resource "google_project_iam_member" "firestore" {
  count   = var.enable_firestore ? 1 : 0
  project = var.gcp_project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.app.email}"
}
```

### Outputs
Outputs are values Terraform returns after creation:

```hcl
output "cloud_run_url" {
  value       = google_cloud_run_v2_service.app.uri
  description = "Your app's public URL"
}

output "service_account_email" {
  value       = google_service_account.app.email
  description = "Service account identity"
}
```

## Terraform Workflow

### Initialize (First Time)
```bash
terraform init -backend-config="bucket=my-project-zilch-tfstate"
```
Downloads providers, sets up remote state backend.

### Plan
```bash
terraform plan \
  -var="gcp_project_id=my-project" \
  -var="app_name=my-app"
```
Shows what Zilch will create/modify without actually creating anything.

### Apply
```bash
terraform apply -auto-approve \
  -var="gcp_project_id=my-project" \
  -var="app_name=my-app"
```
Executes the plan, creates resources, writes state.

### Destroy
```bash
terraform destroy -auto-approve
```
Deletes all resources. (Zilch provides `teardown.sh` for safe deletion.)

## Remote State Backend

Zilch stores Terraform state in a Cloud Storage bucket instead of locally:

```hcl
# backend.tf
terraform {
  backend "gcs" {
    bucket = "my-project-zilch-tfstate"
    prefix = "terraform/state"
  }
}
```

**Why remote state?**
- Multiple developers can deploy the same app
- State isn't lost if you clear your Cloud Shell
- Prevents accidental infrastructure divergence
- Terraform can read state to know what's deployed

## State Management

### State File
The `.tfstate` file is sensitive — it contains:
- Resource IDs
- Configuration values
- Possibly secrets

Never commit to git. Zilch stores it remotely with encryption at rest.

### State Locking
When multiple people run Terraform simultaneously, state locking prevents conflicts:
```bash
# Terraform automatically acquires a lock during apply/destroy
# Other runs wait until the lock is released
```

## Debugging

### See Current State
```bash
terraform state list              # All resources
terraform state show RESOURCE_ID  # Details of one resource
```

### Inspect Terraform Files
```bash
terraform validate   # Check syntax
terraform fmt        # Format files nicely
terraform graph       # Show dependency graph
```

### Destroy Specific Resource
```bash
terraform destroy -target=google_cloud_run_v2_service.app
```
(Use carefully — removes only that resource, may break dependencies.)

## Extending Zilch

To add a new service:

1. Create a variable in `variables.tf`:
```hcl
variable "enable_my_service" {
  type    = bool
  default = false
}
```

2. Add resource definitions in `main.tf` (or new file):
```hcl
resource "google_project_service" "my_service" {
  count   = var.enable_my_service ? 1 : 0
  service = "myservice.googleapis.com"
}
```

3. Grant IAM permissions to service account:
```hcl
resource "google_project_iam_member" "my_service" {
  count   = var.enable_my_service ? 1 : 0
  project = var.gcp_project_id
  role    = "roles/myservice.user"
  member  = "serviceAccount:${google_service_account.app.email}"
}
```

4. Add to `.zilch.config` in `deploy.sh` for persistence
5. Add prompt in `deploy.sh` for interactive enablement

## Related

- **[Remote State Backend](remote-state.md)** — How state is stored
- **[Deployment Workflow](deployment-workflow.md)** — How deploy.sh calls Terraform
- **[Service Accounts & IAM](service-accounts.md)** — What permissions are granted

---

**External Reference:** [Terraform Google Provider Docs](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
