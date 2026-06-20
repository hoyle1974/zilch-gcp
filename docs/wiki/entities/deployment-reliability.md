# Deployment Reliability & Robustness

Zilch's deployment scripts (`deploy.sh` and `teardown.sh`) include sophisticated error handling and automatic recovery mechanisms to handle edge cases gracefully.

## Automatic Recovery Mechanisms

### 🔒 Stale State Lock Detection

**Problem:** If a deployment is interrupted or times out, Terraform leaves a lock file that blocks subsequent deployments.

**Solution:** 
- `deploy.sh` detects stale locks before attempting deployment
- In **interactive mode**: Displays lock details and asks for confirmation before cleanup
- In **auto mode**: Safely fails with recovery instructions
- Prevents silent failures that would be confusing to users

### 📦 Resource Import Recovery

**Problem:** Resources created outside Terraform (e.g., from manual gcloud commands or previous partial deployments) cause "already exists" errors.

**Solution:**
- Detects "Already Exists" errors during terraform apply
- Automatically imports existing resources into Terraform state
- Retries deployment with synchronized state
- Falls back to delete/recreate if import fails

**Example:** BigQuery datasets from previous runs are automatically imported, preventing redeployment failures.

### ✅ Idempotent Deployments

Zilch deployments are safe to run multiple times:
- Terraform state is maintained in remote storage (Cloud Storage)
- Terraform refresh before apply syncs with actual resources
- Redeployments verify and update resources instead of failing

## Tool Validation & Guidance

### Pre-Flight Checks

Both scripts validate required tools before attempting deployment:
- `gcloud` (Google Cloud CLI)
- `terraform` (Infrastructure as Code)
- `curl` (Health checks)
- `bq` (BigQuery operations)

### Cloud Shell Detection

If required tools are missing, scripts:
1. Detect if running in Google Cloud Shell (which has all tools)
2. Recommend Cloud Shell as the easiest approach
3. Provide installation links for local setup
4. Display helpful error messages with next steps

## Error Handling Strategy

### Graceful Degradation

- **Terraform errors:** Script continues with manual cleanup instead of exiting
- **Manual resource deletion:** Uses `|| true` to continue on failures
- **State bucket cleanup:** Warns if bucket can't be deleted (e.g., due to retention policies)

### Clear Error Messages

When errors occur, scripts provide:
- What went wrong
- Why it happened
- How to fix it
- Next steps to take

### Recovery Instructions

For common failure scenarios:
- **Stale locks:** "Remove this lock file with `gsutil rm ...`"
- **Missing tools:** "Use Cloud Shell or install terraform from ..."
- **Failed cleanup:** "Manually delete resources with `gcloud ...`"

## Region Support

Both `deploy.sh` and `teardown.sh` support all GCP regions:
- Deploy reads `gcp_region` from `.zilch.config`
- Teardown uses the same region for consistent cleanup
- Shared `common.sh` ensures both scripts stay synchronized

## Shared Configuration via common.sh

To keep `deploy.sh` and `teardown.sh` in perfect sync, shared functions are extracted into `common.sh`:

```bash
# Both scripts source common.sh for:
- check_required_tools()      # Tool validation
- load_config()               # Config file parsing
- validate_gcloud_auth()      # Authentication checks
- validate_project()          # Project validation
- set_gcp_context()          # GCP project setup
- get_terraform_vars()        # Terraform variables
- export_terraform_vars()     # Environment setup
```

**Benefits:**
- Single source of truth for shared logic
- Automatic synchronization (change once, both benefit)
- Easier to maintain and extend

## KMS Deletion Behavior

**Note:** Cloud KMS keyrings have a **30-day scheduled deletion window** (GCP security feature). When you run `teardown.sh`:
- KMS keyrings are marked for deletion
- They don't disappear immediately
- They're fully deleted after 30 days
- This is normal GCP behavior, not a bug

The teardown script acknowledges this with a message: `Deleting Cloud KMS keyrings (30-day scheduled deletion)...`

## BigQuery Dataset Cleanup

BigQuery datasets are safely deleted with `gcloud bigquery datasets delete`:
- Uses modern `gcloud bigquery` commands (not deprecated `bq` CLI)
- Specifies `--dataset` parameter correctly
- Handles filtering by app name pattern
- Continues on failures (doesn't block cleanup)

## Testing Recovery Mechanisms

To verify recovery works:

1. **Test stale lock recovery:**
   ```bash
   # Deploy, then interrupt with Ctrl+C
   ./deploy.sh
   # Ctrl+C during terraform apply
   
   # Run again - should detect and offer to recover
   ./deploy.sh
   ```

2. **Test idempotent deployment:**
   ```bash
   # Deploy twice
   ./deploy.sh
   ./deploy.sh  # Should complete without errors
   ```

3. **Test clean teardown:**
   ```bash
   ./teardown.sh  # Should cleanly delete all resources
   ```

## Monitoring & Debugging

If something goes wrong:

```bash
# Check Terraform state
terraform state list
terraform state show google_cloud_run_v2_service.app

# Check GCP resources
gcloud run services list
gcloud iam service-accounts list --filter="email:*YOUR_APP*"

# View deployment logs
gcloud run logs read YOUR_APP_NAME --region=us-central1

# Check state bucket
gsutil ls gs://PROJECT_ID-zilch-tfstate/
```

## Known Limitations

### What Can't Be Auto-Recovered
- **Missing GCP project:** Must exist before deployment
- **Insufficient IAM permissions:** User must have editor/owner role
- **Quota exhaustion:** Upgrade GCP project quotas manually
- **Network issues:** Requires connectivity to GCP APIs

### What Requires Manual Intervention
- **Firestore deletion:** Must be done separately with confirmation
- **Retained data:** Buckets with data require `--force` flag
- **Monitoring dashboards:** Created by monitoring service, not tracked by Terraform

## See Also

- [[deployment-workflow.md]] — How deploy.sh works
- [[terraform.md]] — Understanding Terraform state and operations
- [[remote-state.md]] — How Terraform stores state in Cloud Storage

---

**Last updated:** 2026-06-20
