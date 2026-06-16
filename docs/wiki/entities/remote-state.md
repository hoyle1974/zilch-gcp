# Remote State Backend

Zilch stores Terraform state in a Cloud Storage bucket instead of locally. This is critical for team collaboration and preventing infrastructure divergence.

## What is Terraform State?

State is a file (`.tfstate`) that Terraform creates to track what resources exist in your GCP project. It contains:

- Resource IDs (Cloud Run service name, bucket names, etc.)
- Configurations (how many replicas, what IAM roles, etc.)
- Sensitive data (database passwords, API keys)

**Without state**, Terraform can't know:
- What it created before
- What to update vs. create vs. destroy
- Which resource corresponds to which Terraform code

## Why Remote State?

### ❌ Problems with Local State

```
Computer 1: ./deploy.sh
            ↓ creates .terraform/terraform.tfstate
            
Computer 2: ./deploy.sh
            ↓ doesn't have the state file
            ↓ thinks resources don't exist
            ↓ tries to create them again (ERROR!)
```

Local state (on your machine) causes conflicts when multiple people deploy.

### ✅ Benefits of Remote State

```
Computer 1: ./deploy.sh
            ↓ reads state from Cloud Storage
            ↓ updates resources
            ↓ writes state back to Cloud Storage
            
Computer 2: ./deploy.sh
            ↓ reads state from Cloud Storage (up-to-date!)
            ↓ deploys correctly
```

Remote state ensures everyone sees the same infrastructure.

## Zilch's Remote State Setup

### State Bucket
```bash
STATE_BUCKET="${PROJECT_ID}-zilch-tfstate"
# Example: "my-project-zilch-tfstate"
```

Zilch creates this bucket in your target region (Always Free tier).

### Backend Configuration
```hcl
# backend.tf
terraform {
  backend "gcs" {
    bucket = "my-project-zilch-tfstate"
    prefix = "terraform/state"
  }
}
```

This tells Terraform: "Store state in this Cloud Storage bucket."

### Initialization
```bash
terraform init \
  -backend-config="bucket=my-project-zilch-tfstate" \
  -backend-config="prefix=terraform/state"
```

This connects Terraform to the remote backend.

## How Deployment Uses Remote State

```
1. ./deploy.sh creates state bucket
                ↓
2. terraform init connects to bucket
                ↓
3. terraform apply reads state from bucket
                ↓
4. Terraform compares desired vs. actual
                ↓
5. Terraform applies changes
                ↓
6. terraform writes new state to bucket
```

## State File Contents

The `.tfstate` file (stored in Cloud Storage) includes:

```json
{
  "version": 4,
  "terraform_version": "1.0.0",
  "serial": 5,
  "lineage": "abc-123",
  "outputs": {
    "cloud_run_url": {
      "value": "https://my-app-xyz.run.app"
    }
  },
  "resources": [
    {
      "type": "google_cloud_run_v2_service",
      "name": "app",
      "instances": [
        {
          "attributes": {
            "id": "my-app",
            "location": "us-central1",
            "name": "my-app",
            "uri": "https://my-app-xyz.run.app"
          }
        }
      ]
    },
    ...
  ]
}
```

Key sections:
- **outputs** — Values Terraform returns (URLs, IDs)
- **resources** — All created resources and their configurations

## State Locking

When multiple people run `terraform apply` simultaneously:

```
Person 1: terraform apply
          ↓ locks state file
          ↓ applies changes
          ↓ releases lock

Person 2: terraform apply (waits for lock)
          ↓ acquires lock
          ↓ applies changes
          ↓ releases lock
```

State locking (automatic with Cloud Storage) prevents corruption.

## Accessing State

### View State from Command Line
```bash
# List all resources
terraform state list

# See details of one resource
terraform state show google_cloud_run_v2_service.app

# Get specific value
terraform state show google_cloud_run_v2_service.app | grep uri
```

### Access from Cloud Console
```
https://console.cloud.google.com/storage/browser?project=PROJECT_ID
  └─ my-project-zilch-tfstate
      └─ terraform/state/default.tfstate  (the state file)
```

## Protecting State

State files contain sensitive information (secrets, passwords, API keys). Zilch's setup ensures:

✅ **Encryption at rest** — Cloud Storage default encryption
✅ **Access control** — Only your service account can read/write
✅ **Not in git** — `.terraform/` is gitignored
✅ **Remote** — Not on your local machine (safer)

### Manual Security Measures
```bash
# Enable versioning (recover old states if needed)
gcloud storage buckets update gs://my-project-zilch-tfstate \
  --enable-versioning

# Restrict public access
gcloud storage buckets update gs://my-project-zilch-tfstate \
  --uniform-bucket-level-access
```

## Migrating State

If you need to move a deployment to a different bucket/backend:

```bash
# 1. Initialize with new backend
terraform init -migrate-state \
  -backend-config="bucket=new-bucket"

# 2. Confirm migration
yes

# State is moved from old to new bucket
```

## Troubleshooting State Issues

### "Backend initialization failed"
- Bucket doesn't exist: `terraform init` will create it
- Wrong bucket name: Check `backend.tf`
- Permission denied: Check your IAM role

### "State lock timeout"
- Another deployment is in progress
- Wait or manually unlock:
```bash
terraform force-unlock LOCK_ID
```

### "State divergence"
- Resource was deleted manually outside Terraform
- Solution: `terraform refresh` to sync state with actual resources

## Advanced: State Removal

If you want to remove a resource from state without destroying it:

```bash
terraform state rm google_cloud_run_v2_service.app
```

The resource stays in GCP, but Terraform forgets about it. (Don't do this unless you know why.)

## Related

- **[Terraform](terraform.md)** — State is part of Terraform's core
- **[Deployment Workflow](deployment-workflow.md)** — Where state is used
- **[Cloud Run](cloud-run.md)** — A resource tracked in state

---

**Security**: Never delete the state bucket without backing it up. If lost, you'll lose track of what Terraform created.
