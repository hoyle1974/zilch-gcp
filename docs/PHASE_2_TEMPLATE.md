# Adding Phase 2 & 3 Services to Zilch

This guide shows exactly how to add new services (like Cloud Build, BigQuery, etc.) following Zilch's architectural patterns.

## The Pattern

Every service addition follows these 9 steps. Once you complete one, you understand the pattern for all others.

### Step 1: Define the Variable

Add a new boolean toggle to `variables.tf`:

```hcl
variable "enable_<service>" {
  type        = bool
  default     = false
  description = "Enable <Service Name> for <use case>"
}
```

Example:
```hcl
variable "enable_cloud_build" {
  type        = bool
  default     = false
  description = "Enable Cloud Build for automated container builds (free tier: 120 build-minutes/day)"
}
```

### Step 2: Enable Required APIs

In `main.tf`, add a `google_project_service` block inside the Core Resources section:

```hcl
resource "google_project_service" "service_name" {
  count              = var.enable_<service> ? 1 : 0
  service            = "<service-api>.googleapis.com"
  disable_on_destroy = false
}
```

Example (Cloud Build):
```hcl
resource "google_project_service" "cloudbuild" {
  count              = var.enable_cloud_build ? 1 : 0
  service            = "cloudbuild.googleapis.com"
  disable_on_destroy = false
}
```

### Step 3: Create the Service Resource

Add the main resource block to the Optional Architectural Component Layers section in `main.tf`:

```hcl
resource "google_<provider>_<resource>" "instance" {
  count   = var.enable_<service> ? 1 : 0
  project = var.gcp_project_id
  # ... resource-specific configuration
}
```

**Important:** Always use `count = var.enable_<service> ? 1 : 0` to make the resource conditional.

Example (Cloud Build trigger):
```hcl
resource "google_cloudbuild_trigger" "repo" {
  count     = var.enable_cloud_build ? 1 : 0
  project   = var.gcp_project_id
  name      = "${var.app_name}-build-trigger"
  filename  = "cloudbuild.yaml"
  # ... additional config
}
```

### Step 4: Bind IAM Roles

Determine which IAM role(s) the Cloud Run service account needs, then add:

```hcl
resource "google_project_iam_member" "<service>_role" {
  count   = var.enable_<service> ? 1 : 0
  project = var.gcp_project_id
  role    = "roles/<appropriate-role>"
  member  = "serviceAccount:${google_service_account.app.email}"
  depends_on = [google_project_service.<service>]
}
```

Example (Cloud Build):
```hcl
resource "google_project_iam_member" "cloud_build" {
  count   = var.enable_cloud_build ? 1 : 0
  project = var.gcp_project_id
  role    = "roles/cloudbuild.builds.editor"
  member  = "serviceAccount:${google_service_account.app.email}"
  depends_on = [google_project_service.cloudbuild]
}
```

### Step 5: Add Environment Variables

In the Cloud Run service template, add conditional env vars:

```hcl
env {
  name  = "ZILCH_<SERVICE>_<ATTRIBUTE>"
  value = var.enable_<service> ? "<deterministic-value>" : ""
}
```

**Key rule:** Use ONLY deterministic values from variables/locals. Never reference resource outputs (this causes circular dependencies).

Example:
```hcl
env {
  name  = "ZILCH_CLOUDBUILD_PROJECT"
  value = var.enable_cloud_build ? var.gcp_project_id : ""
}
```

### Step 6: Add Terraform Output

Export the service identifier in `outputs.tf`:

```hcl
output "<service>_<attribute>" {
  value       = var.enable_<service> ? <resource-reference> : null
  description = "Description of what this output represents."
}
```

Example:
```hcl
output "cloud_build_trigger_id" {
  value       = var.enable_cloud_build ? google_cloudbuild_trigger.repo[0].id : null
  description = "Cloud Build trigger ID for manual builds."
}
```

### Step 7: Update deploy.sh

Add a prompt in the feature toggles section:

```bash
CLOUD_BUILD=$(prompt_toggle "Cloud Build Container Automation")
```

Then pass it to `terraform apply`:

```bash
terraform apply -auto-approve \
  ... \
  -var="enable_cloud_build=${CLOUD_BUILD}" \
  ...
```

Finally, display it in the summary section:

```bash
if [ "$CLOUD_BUILD" == "true" ]; then echo "  ↳ ZILCH_CLOUDBUILD_PROJECT : ${PROJECT_ID}"; fi
```

### Step 8: Add Post-Deploy Validation

In `deploy.sh`, after the health check section, add service-specific validation:

```bash
if [ "$CLOUD_BUILD" == "true" ]; then
  echo "✓ Cloud Build enabled. Trigger ID: $(terraform output -raw cloud_build_trigger_id)"
fi
```

### Step 9: Update Documentation

- **tutorial.md:** Add a brief description under "Understanding the Services"
- **README.md:** Add the service to the feature table
- **This template:** Update example references if needed

---

## Example: Complete Cloud Build Addition

### 1. variables.tf
```hcl
variable "enable_cloud_build" {
  type    = bool
  default = false
  description = "Enable Cloud Build for CI/CD (free: 120 build-minutes/day)"
}
```

### 2. main.tf (APIs)
```hcl
resource "google_project_service" "cloudbuild" {
  count              = var.enable_cloud_build ? 1 : 0
  service            = "cloudbuild.googleapis.com"
  disable_on_destroy = false
}
```

### 3. main.tf (Resource)
```hcl
resource "google_cloudbuild_trigger" "repo" {
  count     = var.enable_cloud_build ? 1 : 0
  project   = var.gcp_project_id
  name      = "${var.app_name}-build-trigger"
  description = "Auto-build on push to main branch"
  filename  = "cloudbuild.yaml"

  github {
    owner = "your-github-user"
    name  = var.app_name
    push {
      branch = "^main$"
    }
  }
}
```

### 4. main.tf (IAM)
```hcl
resource "google_project_iam_member" "cloud_build" {
  count   = var.enable_cloud_build ? 1 : 0
  project = var.gcp_project_id
  role    = "roles/cloudbuild.builds.editor"
  member  = "serviceAccount:${google_service_account.app.email}"
  depends_on = [google_project_service.cloudbuild]
}
```

### 5. main.tf (Env Vars)
```hcl
env {
  name  = "ZILCH_CLOUDBUILD_PROJECT"
  value = var.enable_cloud_build ? var.gcp_project_id : ""
}
```

### 6. outputs.tf
```hcl
output "cloud_build_trigger_id" {
  value       = var.enable_cloud_build ? google_cloudbuild_trigger.repo[0].id : null
  description = "Cloud Build trigger ID"
}
```

### 7. deploy.sh (Prompts)
```bash
CLOUD_BUILD=$(prompt_toggle "Cloud Build Container Automation")
```

### 8. deploy.sh (terraform apply)
```bash
terraform apply -auto-approve \
  ... \
  -var="enable_cloud_build=${CLOUD_BUILD}" \
  ...
```

### 9. deploy.sh (Summary)
```bash
if [ "$CLOUD_BUILD" == "true" ]; then 
  echo "  ↳ ZILCH_CLOUDBUILD_PROJECT : $(terraform output -raw cloud_build_trigger_id)"
fi
```

---

## Common Pitfalls

❌ **Don't reference resource outputs in env vars**
```hcl
# WRONG - causes circular dependency
env {
  name  = "ZILCH_BUCKET"
  value = google_storage_bucket.app[0].name  # ❌ Doesn't work!
}
```

✅ **Do use deterministic values only**
```hcl
# CORRECT - uses variables/locals only
env {
  name  = "ZILCH_BUCKET"
  value = var.enable_storage ? "${var.app_name}-storage-${random_id.bucket_suffix.hex}" : ""
}
```

❌ **Don't forget count conditions**
```hcl
# WRONG - always created
resource "google_storage_bucket" "app" {
  name = "${var.app_name}-bucket"  # ❌ Creates even if disabled!
}
```

✅ **Always use count**
```hcl
# CORRECT - only created if enabled
resource "google_storage_bucket" "app" {
  count = var.enable_storage ? 1 : 0
  name  = "${var.app_name}-bucket"
}
```

❌ **Don't hardcode resource values**
```hcl
# WRONG - user can't customize
resource "google_cloud_run_service" "app" {
  location = "us-central1"  # ❌ Forces region!
}
```

✅ **Always use variables**
```hcl
# CORRECT - respects user's region choice
resource "google_cloud_run_service" "app" {
  location = var.gcp_region
}
```

---

## Testing Your Addition

After adding a service, test it end-to-end:

```bash
# 1. Make sure Terraform lints cleanly
terraform validate

# 2. Plan the changes
terraform plan -var="enable_<service>=true" \
  -var="gcp_project_id=YOUR_PROJECT" \
  -var="app_name=test-app"

# 3. Run the full deploy script (if you've updated it)
./deploy.sh
```

---

## PR Checklist

Before submitting a PR to add a new service:

- [ ] Added variable to `variables.tf`
- [ ] Added API enablement to `main.tf`
- [ ] Added resource to `main.tf` with `count` condition
- [ ] Added IAM role binding to `main.tf`
- [ ] Added env vars to Cloud Run template
- [ ] Added output to `outputs.tf`
- [ ] Updated `deploy.sh` with prompt and terraform apply var
- [ ] Updated `deploy.sh` summary section
- [ ] Added post-deploy validation (if applicable)
- [ ] Updated `tutorial.md` with service description
- [ ] Updated `README.md` feature table
- [ ] Ran `terraform validate` successfully
- [ ] Tested `./deploy.sh` end-to-end

---

## Questions?

Refer to the [Zilch MVP Design Specification](superpowers/specs/2026-06-13-zilch-mvp-design.md) for architectural decisions and rationale.
