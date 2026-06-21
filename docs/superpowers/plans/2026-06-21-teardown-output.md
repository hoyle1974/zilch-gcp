# Beginner-Friendly Teardown Output Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `zilch teardown` output beginner-friendly by suppressing verbose terraform output, categorizing cleanup failures, and providing a clear summary of what succeeded vs. what needs attention.

**Architecture:** Capture terraform destroy output and parse resource counts for progress; track each manual cleanup result with outcome category (deleted/already_gone/permission_denied/timeout/error); print one-line status per resource with indicator; summarize at end grouped by failure reason.

**Tech Stack:** Python subprocess capture, JSON parsing, Click output formatting

## Global Constraints

- Python 3.8+ (existing project requirement)
- Must maintain backward compatibility with existing teardown behavior (hard stop on actual errors)
- Output functions must use existing `output.py` helpers (section, success, warning, error, info)
- All new functions must have docstrings

---

## File Structure

**Modified files:**
- `output.py` — Add `get_outcome_indicator()` and `print_cleanup_summary()` helpers
- `terraform.py` — Update `destroy()` to capture output and show progress counts
- `zilch.py` — Refactor `_cleanup_gcp_resources()` to collect results; add `_print_cleanup_summary()` call

**No new files created** — all changes fit into existing modules.

---

## Task 1: Add Outcome Indicator Helper to output.py

**Files:**
- Modify: `output.py` (end of file)

**Interfaces:**
- Produces: `get_outcome_indicator(outcome: str) -> str` — returns emoji/text for outcome type
  - Input: one of `"deleted"`, `"already_gone"`, `"permission_denied"`, `"timeout"`, `"error"`
  - Output: indicator string (e.g., `"✓"`, `"ℹ️"`, `"🔐"`, `"⏱️"`, `"🚫"`)

**Steps:**

- [ ] **Step 1: Add outcome indicator function to output.py**

Open `output.py` and add this function at the end (before or after other helper functions):

```python
def get_outcome_indicator(outcome: str) -> str:
    """Get emoji/text indicator for cleanup outcome.
    
    Args:
        outcome: One of "deleted", "already_gone", "permission_denied", "timeout", "error"
    
    Returns:
        Indicator string with emoji
    """
    indicators = {
        "deleted": "✓",
        "already_gone": "ℹ️",
        "permission_denied": "🔐",
        "timeout": "⏱️",
        "error": "🚫",
    }
    return indicators.get(outcome, "?")
```

- [ ] **Step 2: Commit**

```bash
git add output.py
git commit -m "feat: add outcome indicator helper for teardown summary"
```

---

## Task 2: Add Cleanup Summary Formatter to output.py

**Files:**
- Modify: `output.py` (add new function)

**Interfaces:**
- Consumes: `get_outcome_indicator()` from Task 1
- Produces: `print_cleanup_summary(results: dict) -> None` — formats and prints cleanup summary
  - Input dict structure: `{"deleted": [...], "already_gone": [...], "permission_denied": [...], "timeout": [...], "error": [...]}`
  - Each list contains tuples: `(resource_name, error_reason)` where error_reason is optional for "deleted" and "already_gone"

**Steps:**

- [ ] **Step 1: Add cleanup summary function to output.py**

Add this function after `get_outcome_indicator()`:

```python
def print_cleanup_summary(results: dict) -> None:
    """Print cleanup results summary grouped by outcome.
    
    Args:
        results: Dict with keys: "deleted", "already_gone", "permission_denied", "timeout", "error"
                 Each value is list of (resource_name, reason) tuples
    """
    # Count by outcome (skip outcomes with no results)
    counts = {k: len(v) for k, v in results.items() if v}
    
    if not counts:
        return  # No failures, skip summary
    
    section("Teardown Summary")
    
    # Show deleted resources
    if "deleted" in counts and counts["deleted"] > 0:
        indicator = get_outcome_indicator("deleted")
        click.echo(f"{indicator} Deleted: {counts['deleted']} resources")
    
    # Show already gone
    if "already_gone" in counts and counts["already_gone"] > 0:
        indicator = get_outcome_indicator("already_gone")
        click.echo(f"{indicator} Already gone: {counts['already_gone']} resources (not found — Terraform handled these)")
    
    # Show permission denied
    if "permission_denied" in counts and counts["permission_denied"] > 0:
        indicator = get_outcome_indicator("permission_denied")
        click.echo(f"{indicator} Permission denied: {counts['permission_denied']} resources (may need project owner)")
    
    # Show timeouts
    if "timeout" in counts and counts["timeout"] > 0:
        indicator = get_outcome_indicator("timeout")
        click.echo(f"{indicator} Timeouts: {counts['timeout']} resource(s)")
    
    # Show errors
    if "error" in counts and counts["error"] > 0:
        indicator = get_outcome_indicator("error")
        click.echo(f"{indicator} Errors: {counts['error']} resource(s)")
    
    click.echo()
```

- [ ] **Step 2: Commit**

```bash
git add output.py
git commit -m "feat: add cleanup summary formatter for outcome grouping"
```

---

## Task 3: Refactor _cleanup_gcp_resources() to Collect and Categorize Results

**Files:**
- Modify: `zilch.py:364-396` (the `_cleanup_gcp_resources()` function)

**Interfaces:**
- Consumes: (none)
- Produces: `_cleanup_gcp_resources(config: ZilchConfig) -> dict` — returns results dict
  - Structure: `{"deleted": [...], "already_gone": [...], "permission_denied": [...], "timeout": [...], "error": [...]}`
  - Each value is list of `(resource_name, error_message)` tuples

**Steps:**

- [ ] **Step 1: Rewrite _cleanup_gcp_resources() to return structured results**

In `zilch.py`, find the teardown function and locate the manual cleanup section (around line 269-270). Change:

```python
        # Manual cleanup of resources that might not be terraform-managed
        section("Manual Cleanup")
        _cleanup_gcp_resources(config)
```

To:

```python
        # Manual cleanup of resources that might not be terraform-managed
        section("Manual Cleanup")
        cleanup_results = _cleanup_gcp_resources(config)
        
        # Show summary of cleanup results
        from output import print_cleanup_summary
        print_cleanup_summary(cleanup_results)
```

- [ ] **Step 2: Commit**

```bash
git add zilch.py
git commit -m "feat: call cleanup summary after manual cleanup phase"
```

---

## Task 4: Refactor _cleanup_gcp_resources() Implementation

**Files:**
- Modify: `zilch.py:364-396` (replace the `_cleanup_gcp_resources()` function)

**Interfaces:**
- Consumes: (none)
- Produces: `_cleanup_gcp_resources(config: ZilchConfig) -> dict` — returns results dict
  - Structure: `{"deleted": [...], "already_gone": [...], "permission_denied": [...], "timeout": [...], "error": [...]}`
  - Each value is list of `(resource_name, error_message)` tuples

**Steps:**

- [ ] **Step 1: Rewrite _cleanup_gcp_resources() function body**

Replace the existing `_cleanup_gcp_resources()` function (lines 364-396 in zilch.py) with:

```python
def _cleanup_gcp_resources(config: ZilchConfig) -> dict:
    """Manually clean up GCP resources, collect and categorize results.
    
    Returns dict with outcome categories:
        "deleted": list of (resource_name, None) tuples
        "already_gone": list of (resource_name, reason) tuples
        "permission_denied": list of (resource_name, reason) tuples
        "timeout": list of (resource_name, None) tuples
        "error": list of (resource_name, reason) tuples
    """
    results = {
        "deleted": [],
        "already_gone": [],
        "permission_denied": [],
        "timeout": [],
        "error": [],
    }
    
    resources_to_clean = [
        ("Cloud Run", ["gcloud", "run", "services", "delete", config.app_name, f"--region={config.gcp_region}", "--quiet"]),
        ("Service account (app)", ["gcloud", "iam", "service-accounts", "delete", f"{config.app_name}@{config.gcp_project_id}.iam.gserviceaccount.com", "--quiet"]),
        ("Service account (Cloud Build)", ["gcloud", "iam", "service-accounts", "delete", f"{config.app_name}-builder@{config.gcp_project_id}.iam.gserviceaccount.com", "--quiet"]),
        ("Pub/Sub topic (events)", ["gcloud", "pubsub", "topics", "delete", f"{config.app_name}-events", "--quiet"]),
        ("Pub/Sub topic (budget alerts)", ["gcloud", "pubsub", "topics", "delete", f"{config.app_name}-budget-alerts", "--quiet"]),
        ("Pub/Sub subscription (events)", ["gcloud", "pubsub", "subscriptions", "delete", f"{config.app_name}-events-subscription", "--quiet"]),
        ("Cloud Build logs bucket", ["gcloud", "storage", "buckets", "delete", f"gs://{config.gcp_project_id}_cloudbuild", "--quiet"]),
        ("Firestore database", ["gcloud", "firestore", "databases", "delete", "--database=(default)", "--quiet"]),
        ("Artifact Registry", ["gcloud", "artifacts", "repositories", "delete", f"{config.app_name}-images", f"--location={config.gcp_region}", "--quiet"]),
        ("BigQuery dataset", ["gcloud", "bigquery", "datasets", "delete", "--dataset=" + config.app_name.replace("-", "_") + "_analytics", "--quiet"]),
        ("Cloud Build trigger", ["gcloud", "builds", "triggers", "delete", f"{config.app_name}-trigger", "--quiet"]),
        ("Cloud Tasks queue", ["gcloud", "tasks", "queues", "delete", f"{config.app_name}-jobs", f"--location={config.gcp_region}", "--quiet"]),
        ("KMS keyring", ["gcloud", "kms", "keyrings", "delete", f"{config.app_name}-keyring", f"--location={config.gcp_region}", "--quiet"]),
    ]

    for resource_name, cmd in resources_to_clean:
        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                timeout=30,
                check=False,
            )
            
            if result.returncode == 0:
                # Success
                from output import get_outcome_indicator
                indicator = get_outcome_indicator("deleted")
                click.echo(f"{indicator} {resource_name} deleted")
                results["deleted"].append((resource_name, None))
            else:
                # Categorize failure
                stderr = result.stderr.decode("utf-8", errors="replace").strip() if result.stderr else ""
                stdout = result.stdout.decode("utf-8", errors="replace").strip() if result.stdout else ""
                error_text = stderr or stdout
                
                from output import get_outcome_indicator
                
                # Determine outcome category
                if "not found" in error_text.lower() or "not_found" in error_text.lower() or "does not exist" in error_text.lower():
                    outcome = "already_gone"
                    indicator = get_outcome_indicator(outcome)
                    click.echo(f"{indicator} {resource_name}: already gone")
                    results[outcome].append((resource_name, error_text))
                elif "permission_denied" in error_text.lower() or "permission denied" in error_text.lower() or "iam_permission_denied" in error_text.lower():
                    outcome = "permission_denied"
                    indicator = get_outcome_indicator(outcome)
                    click.echo(f"{indicator} {resource_name}: permission denied")
                    results[outcome].append((resource_name, error_text))
                else:
                    # Generic error
                    outcome = "error"
                    indicator = get_outcome_indicator(outcome)
                    click.echo(f"{indicator} {resource_name}: error")
                    results[outcome].append((resource_name, error_text))
        
        except subprocess.TimeoutExpired:
            from output import get_outcome_indicator
            indicator = get_outcome_indicator("timeout")
            click.echo(f"{indicator} {resource_name}: timeout")
            results["timeout"].append((resource_name, None))
        except Exception as e:
            from output import get_outcome_indicator
            indicator = get_outcome_indicator("error")
            click.echo(f"{indicator} {resource_name}: error")
            results["error"].append((resource_name, str(e)))
    
    return results
```

- [ ] **Step 2: Commit**

```bash
git add zilch.py
git commit -m "refactor: _cleanup_gcp_resources returns categorized results instead of printing"
```

---

## Task 5: Update terraform.py destroy() to Capture and Show Progress

**Files:**
- Modify: `terraform.py:229-274` (the `destroy()` method)

**Interfaces:**
- Consumes: (none)
- Produces: Same as before — returns bool (success/failure)

**Steps:**

- [ ] **Step 1: Update destroy() to capture output and show progress**

Replace the `destroy()` method in `terraform.py` (lines 229-274) with:

```python
    def destroy(self, vars_dict: Dict[str, str], force: bool = False) -> bool:
        """Destroy Terraform infrastructure with progress feedback.

        Args:
            vars_dict: Dictionary of Terraform variables
            force: Skip confirmation

        Returns:
            True if destroy succeeded, False if it had errors (but may have partially succeeded)
        """
        # Build variable arguments
        var_args = []
        for key, value in vars_dict.items():
            if isinstance(value, bool):
                var_args.append(f'-var={key}={str(value).lower()}')
            else:
                var_args.append(f'-var={key}={value}')

        cmd = [
            "terraform",
            "-chdir=" + str(self.working_dir),
            "destroy",
            "-lock=false",  # Disable state locking (GCS backend issue)
        ]

        if force:
            cmd.append("-auto-approve")

        cmd.extend(var_args)

        try:
            result = subprocess.run(
                cmd,
                timeout=600,  # 10 minutes
                check=False,  # Don't fail on non-zero exit - allow cleanup to continue
                cwd=str(self.working_dir),
                capture_output=True,  # Capture output to parse and summarize
                text=True,
            )
            
            # Parse output to extract resource counts for progress display
            output_lines = (result.stdout + result.stderr).split('\n') if result.stdout or result.stderr else []
            
            # Count resource refresh lines to show progress
            refresh_count = sum(1 for line in output_lines if 'Refreshing state' in line)
            destroy_count = sum(1 for line in output_lines if 'destroyed' in line.lower())
            
            # Show progress summary
            if refresh_count > 0 or destroy_count > 0:
                info(f"Destroying resources ({refresh_count} resources, {destroy_count} to delete)...")
            else:
                info("Running terraform destroy...")
            
            if result.returncode == 0:
                success("Infrastructure destroyed")
                return True
            else:
                warning("Terraform destroy completed with warnings/errors (continuing cleanup)")
                return False
        except subprocess.TimeoutExpired:
            raise TerraformError("Terraform destroy timed out")
```

- [ ] **Step 2: Commit**

```bash
git add terraform.py
git commit -m "feat: capture terraform destroy output and show progress counts"
```

---

## Task 6: Manual Test of Full Teardown Flow

**Files:**
- Test: Manual testing (no test file)

**Interfaces:**
- Consumes: All changes from Tasks 1-5

**Steps:**

- [ ] **Step 1: Deploy a test infrastructure (if not already deployed)**

```bash
cd /Users/jstrohm/code/zilch-reference-app
python3 ~/code/zilch-gcp/zilch.py deploy --auto
```

Wait for deployment to complete.

- [ ] **Step 2: Run teardown and verify output format**

```bash
cd /Users/jstrohm/code/zilch-reference-app
python3 ~/code/zilch-gcp/zilch.py teardown --force
```

**Expected output sections:**
1. Prerequisites section (existing)
2. Terraform section with progress: `→ Destroying resources (45 resources, 23 to delete)...`
3. Manual Cleanup section with one-line status per resource:
   - `✓ Cloud Run service deleted`
   - `ℹ️ Pub/Sub topic (events): already gone`
   - `🔐 Service account (app): permission denied`
   - etc.
4. Teardown Summary section with grouped counts:
   ```
   ✓ Deleted: 15 resources
   ℹ️ Already gone: 8 resources (not found — Terraform handled these)
   🔐 Permission denied: 2 resources (may need project owner)
   ```
5. Cleanup section (existing)
6. Final success message

- [ ] **Step 3: Verify each category appears**

Verify that the output shows:
- At least one ✓ (deleted)
- At least one ℹ️ (already_gone)
- At least one 🔐 (permission_denied) — expected due to service account permissions
- No raw gcloud errors visible
- Summary groups failures by reason (not by resource type)

- [ ] **Step 4: Commit (note: no code changes, just verification)**

```bash
git status
# Should show clean working tree
```

