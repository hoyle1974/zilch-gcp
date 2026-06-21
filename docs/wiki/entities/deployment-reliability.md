---
title: Deployment Reliability & Robustness
tags: [reliability, python, error-handling, terraform, state-management]
last_updated: 2026-06-20
source_count: 2
sources:
  - IMPLEMENTATION_SUMMARY.md
  - PYTHON_MIGRATION_PLAN.md
---

# Deployment Reliability & Robustness

Zilch's deployment tool (`zilch.py`, implemented across `config.py`, `gcp.py`, `terraform.py`, and `health_check.py`) includes structured error handling and automatic recovery mechanisms to handle edge cases gracefully. This logic previously lived in `deploy.sh`/`teardown.sh`/`common.sh`; those bash scripts have been superseded by the Python modules described below.

## Automatic Recovery Mechanisms

### 🔒 Stale State Lock Detection

**Problem:** If a deployment is interrupted or times out, Terraform leaves a lock file that blocks subsequent deployments.

**Solution:**
- `gcp.check_terraform_lock_exists(state_bucket, app_name)` detects a stale lock before `zilch.py` attempts Terraform operations
- In **interactive mode**: `zilch.py` prompts for confirmation (`click.confirm("Remove stale lock and continue?")`) before calling `gcp.remove_terraform_lock()`
- In **auto mode** (`--auto`): if a lock is found and removal isn't confirmable, `zilch.py` exits with a clear error rather than silently corrupting state
- Prevents silent failures that would be confusing to users

### 📦 Resource Import Recovery (State Reconciliation)

**Problem:** Resources created outside Terraform (e.g., from manual `gcloud` commands or a previous partial deployment) cause "already exists" errors during `terraform apply`.

**Solution:** `_reconcile_state()` in `zilch.py` builds a list of `(resource_type, resource_id, display_name)` tuples for resources that commonly already exist (service accounts, Cloud Run service, Artifact Registry repo, and conditionally BigQuery dataset, Firestore database, Cloud Build logs bucket, Cloud Tasks queue, KMS keyring/key) and passes them to `StateImporter.import_all()` (in `terraform.py`) **before** `terraform apply` runs.

`StateImporter` imports resources **sequentially**, not in parallel:

```python
class StateImporter:
    """Import multiple resources sequentially to avoid Terraform state lock contention."""

    def import_all(self, resources, vars_dict) -> Dict[str, bool]:
        for resource_type, resource_id, display_name in resources:
            success_flag = self._import_with_retry(
                resource_type, resource_id, display_name, vars_dict
            )
            ...
```

This is a deliberate design choice: Terraform takes an exclusive write lock on remote state for every `terraform import`, so running imports concurrently (e.g. with a thread pool) causes "Error acquiring the state lock" failures against each other. Sequential execution with per-resource retry (`_import_with_retry`, up to 2 attempts, checking `terraform state list` first to skip resources already tracked) is simpler and avoids that contention entirely. Imports that still fail after retries are logged as warnings, and the deployment proceeds — `terraform apply` will surface a clearer error for that specific resource if it's truly a conflict.

**Example:** A BigQuery dataset left over from a previous run is detected as not yet in state, imported via `TerraformExecutor.import_resource()`, and the subsequent `apply` updates it instead of failing with "already exists."

### ✅ Idempotent Deployments

Zilch deployments are safe to run multiple times:
- Terraform state is maintained in remote storage (Cloud Storage), addressed per-app via `terraform/state/{app_name}` prefix
- State reconciliation (above) runs before every apply, syncing Terraform's view with actual GCP resources
- Redeployments verify and update resources instead of failing on "already exists"

## Tool Validation & Guidance

### Pre-Flight Checks

`gcp.check_required_tools()` validates required tools before attempting deployment:
- `gcloud` (Google Cloud CLI)
- `terraform` (Infrastructure as Code)

(`curl`/`bq` are no longer directly required by the orchestration layer — HTTP health checks use the `requests` library, and BigQuery cleanup uses `gcloud bigquery` rather than the legacy `bq` CLI.)

### Cloud Shell Detection

`gcp.is_cloud_shell()` detects whether `zilch.py` is running inside Google Cloud Shell (which has all required tools preinstalled). If tools are missing and Cloud Shell isn't detected, `zilch.py` recommends Cloud Shell as the easiest path and prints installation guidance for local setup.

## Error Handling Strategy

### Custom Exceptions

Python's structured exceptions replace bash's scattered `set -e`/silent-failure patterns:

```python
class GCPError(Exception): ...      # gcp.py
class TerraformError(Exception): ... # terraform.py
```

Every subprocess call into `gcloud`/`terraform` is wrapped in `try`/`except`, and failures are converted into one of these exception types with a user-facing message, e.g.:

```python
raise GCPError(
    "Authentication failed. You're not logged in to GCP. Run:\n"
    "  gcloud auth login"
)
```

### Graceful Degradation

- **Terraform destroy errors:** `TerraformExecutor.destroy()` runs with `check=False` and returns a boolean rather than raising, so `zilch.py teardown` can continue with manual cleanup even if `terraform destroy` reports problems
- **Manual resource deletion:** `_cleanup_gcp_resources()` in `zilch.py` runs each `gcloud ... delete --quiet` command with `check=False` and only logs a warning on failure, so one missing resource doesn't block cleanup of the rest
- **State bucket cleanup:** Logged as a warning (not fatal) if the bucket can't be deleted (e.g., due to retention policies)

### Clear Error Messages

Per the migration plan's error-message standard, every error should:
1. **State what failed** (clear, no jargon)
2. **Explain why** (context)
3. **Suggest recovery** (actionable next step)

Example (good):
```
✗ Authentication failed
You're not logged in to GCP. Run:
  gcloud auth login
```

### Recovery Instructions

For common failure scenarios:
- **Stale locks:** `zilch.py` offers to remove the lock interactively, or tells you to re-run with confirmation
- **Missing tools:** Recommends Cloud Shell or links to install `terraform`/`gcloud`
- **Failed manual cleanup:** Logged per-resource as a warning with the underlying `gcloud` error so you can finish manually

## Region Support

`zilch.py` enforces the same three Always Free regions (`us-central1`, `us-east1`, `us-west1`) for both `deploy` and `teardown` via `ZilchConfig.gcp_region`'s validator — there's a single source of truth for the region, read from `.zilch.config`, so deploy and teardown can never disagree about where resources live.

## Configuration & Validation as Reliability

Where the old bash scripts relied on shared shell functions (`common.sh`) to keep `deploy.sh` and `teardown.sh` in sync, the Python implementation gets the same guarantee for free: both `deploy` and `teardown` commands in `zilch.py` load the **same** `ZilchConfig` instance from `.zilch.config` via `config.py`, so there's no risk of the two commands drifting out of sync on validation rules, defaults, or field names. `gcp.py` and `terraform.py` are imported by both code paths rather than duplicated.

## KMS Deletion Behavior

**Note:** Cloud KMS keyrings have a **30-day scheduled deletion window** (GCP security feature). When you run `python3 zilch.py teardown`:
- KMS keyrings are marked for deletion (via `gcloud kms keyrings delete` in `_cleanup_gcp_resources()`)
- They don't disappear immediately
- They're fully deleted after 30 days
- This is normal GCP behavior, not a bug

## BigQuery Dataset Cleanup

BigQuery datasets are deleted in `_cleanup_gcp_resources()` using:
```bash
gcloud bigquery datasets delete --dataset=<app_name>_analytics --quiet
```
- Uses modern `gcloud bigquery` commands (not the deprecated `bq` CLI)
- Dataset name is derived from `app_name` (hyphens replaced with underscores) plus `_analytics`
- Continues on failure (doesn't block the rest of teardown) — failures are logged as warnings with the underlying stderr

## Testing Recovery Mechanisms

Recovery logic is covered by automated tests (`tests/test_gcp.py`, `tests/test_config.py` — 25 tests total, all passing) that mock `subprocess` calls rather than requiring a live GCP project:

- `test_check_terraform_lock_exists` / `test_check_terraform_lock_not_exists`
- `test_remove_terraform_lock_success` / `test_remove_terraform_lock_failure`
- `test_setup_firestore_permissions_success` / `test_setup_firestore_permissions_failure`
- `test_create_state_bucket_already_exists`

Run them with:
```bash
make test
# or: pytest tests/ -v
```

To exercise recovery manually against a real project:

1. **Test stale lock recovery:**
   ```bash
   python3 zilch.py deploy
   # Ctrl+C during terraform apply

   python3 zilch.py deploy
   # Should detect the lock and offer to recover
   ```

2. **Test idempotent deployment:**
   ```bash
   python3 zilch.py deploy --auto
   python3 zilch.py deploy --auto  # Should complete without errors
   ```

3. **Test clean teardown:**
   ```bash
   python3 zilch.py teardown --force  # Should cleanly delete all resources
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
gcloud storage ls gs://PROJECT_ID-zilch-tfstate/

# Check current status via zilch.py
python3 zilch.py status
```

## Known Limitations

### What Can't Be Auto-Recovered
- **Missing GCP project:** Must exist before deployment
- **Insufficient IAM permissions:** User must have editor/owner role
- **Quota exhaustion:** Upgrade GCP project quotas manually
- **Network issues:** Requires connectivity to GCP APIs

### What Requires Manual Intervention
- **Firestore deletion:** Must be done separately with confirmation (Firestore database deletion is included in `_cleanup_gcp_resources()` but is one-way)
- **Retained data:** Buckets with data require manual deletion with `--force`/explicit confirmation
- **Monitoring dashboards:** Created by the monitoring service, not tracked by Terraform

### Phase 1 Scope Limitations

Per `IMPLEMENTATION_SUMMARY.md`, the current Python implementation is Phase 1 of the migration. Notably not yet included:
- No async support — uses `ThreadPoolExecutor`-style concurrency in the original plan was superseded by the sequential `StateImporter` design above for correctness; no concurrency is used for imports
- `.zilch.config` is still the `.ini`-style key=value format (a TOML migration is a Phase 2+ idea, not yet implemented)
- No package distribution (`pip install zilch`) — `zilch.py` is run directly from the repo with a local virtualenv

## See Also

- [[deployment-workflow.md]] — Full step-by-step deploy/teardown flow
- [[configuration.md]] — `ZilchConfig` validation and `.zilch.config` format
- [[terraform.md]] — Understanding Terraform state and operations
- [[remote-state.md]] — How Terraform stores state in Cloud Storage

---

**Last updated:** 2026-06-20
