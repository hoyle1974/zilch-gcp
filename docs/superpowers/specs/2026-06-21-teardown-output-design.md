---
title: Beginner-Friendly Teardown Output Design
tags: [ux, teardown, output-formatting, user-experience]
last_updated: 2026-06-21
source_count: 1
sources:
  - zilch.py
---

# Beginner-Friendly Teardown Output Design

## Problem Statement

The current `zilch teardown` command produces output that is difficult for beginners to parse:

1. **Verbose terraform state refresh** — hundreds of lines showing "random_id.X: Refreshing state..." that obscure actual progress
2. **Unclear error messages** — raw gcloud stderr without categorization ("ERROR: (gcloud.tasks.queues.delete) NOT_FOUND...")
3. **Confusing success signals** — reports "Teardown complete!" even when multiple cleanup attempts fail
4. **No actionable guidance** — users can't distinguish between expected failures (resource already gone) and actual problems (permission denied)

## Goal

Make teardown output beginner-friendly by:
- Suppressing verbose terraform noise and showing meaningful progress
- Categorizing cleanup failures by reason (already gone, permission denied, timeout, error)
- Providing a clear summary that helps users understand what succeeded and what needs attention

## Design

### Phase 1: Terraform Destroy with Progress

**Current behavior:** Terraform destroy runs with full verbose output
```
random_id.bucket_suffix: Refreshing state... [id=dHFqVA]
random_integer.mysql_port[0]: Refreshing state... [id=35755]
random_password.mysql_root[0]: Refreshing state... [id=none]
... (hundreds of lines)
```

**New behavior:** Capture terraform output and display progress summary
```
→ Destroying resources (45 resources, 23 to delete)...
✓ Infrastructure destroyed
```

**Implementation:**
- Modify `terraform.py:TerraformExecutor.destroy()` to capture stdout/stderr
- Parse terraform JSON diagnostics to extract resource counts
- Display: `→ Destroying resources ({total} resources, {to_delete} to delete)...`
- Show ✓ or ⚠ based on terraform exit code

### Phase 2: Manual Cleanup with Categorized Results

**Current behavior:** Each cleanup command prints raw gcloud stderr on failure
```
⚠ Failed to delete Pub/Sub topic (events): ERROR: Failed to delete topic [projects/test-z-1-499406/topics/zilch-reference-app-events]: Resource not found (resource=zilch-reference-app-events).
⚠ Failed to delete Service account (app): ERROR: (gcloud.iam.service-accounts.delete) PERMISSION_DENIED: Permission 'iam.serviceAccounts.delete' denied on resource...
```

**New behavior:** Track each result and show one-line status with indicator
```
✓ Cloud Run service deleted
ℹ️ Pub/Sub topic (events): already gone
🔐 Service account (app): permission denied
⏱️ Cloud Tasks queue: timeout
🚫 BigQuery dataset: error
```

**Implementation:**
- Update `zilch.py:_cleanup_gcp_resources()` to:
  - Collect all results (resource_name, outcome, reason) instead of printing immediately
  - Categorize outcomes: "deleted" | "already_gone" | "permission_denied" | "timeout" | "error"
  - Return structured results dict for summary

- Define outcome categories:
  - `"deleted"` — gcloud command succeeded (returncode 0)
  - `"already_gone"` — gcloud returned "not found" or similar
  - `"permission_denied"` — gcloud returned permission error
  - `"timeout"` — subprocess.TimeoutExpired raised
  - `"error"` — all other failures

- Output one line per resource with indicator:
  - `✓` for deleted
  - `ℹ️` for already_gone
  - `🔐` for permission_denied
  - `⏱️` for timeout
  - `🚫` for error

### Phase 3: End-of-Teardown Summary

**Current behavior:** Simple "Teardown complete!" message
```
✓ Teardown complete!
```

**New behavior:** Grouped summary by outcome reason
```
━━━ Teardown Summary ━━━
✓ Deleted: 15 resources
ℹ️ Already gone: 8 resources (not found — Terraform handled these)
🔐 Permission denied: 2 resources (may need project owner)
⏱️ Timeouts: 1 resource
🚫 Errors: 1 resource (check logs if needed)

✓ Teardown complete! State bucket removed, local files cleaned.
```

**Implementation:**
- Add helper function to `output.py` for formatting summary sections
- Count results by outcome category
- Display summary only if there were failures
- Include brief guidance for each failure category:
  - `already_gone`: "Terraform handled these"
  - `permission_denied`: "may need project owner"
  - `timeout`: (no guidance)
  - `error`: "check logs if needed"

### Phase 4: Full Teardown Flow with New Output

```
━━━ Zilch Infrastructure Teardown ━━━
⚠️  WARNING: This action is IRREVERSIBLE

... (existing prerequisites section) ...

━━━ Terraform ━━━
→ Destroying resources (45 resources, 23 to delete)...
✓ Infrastructure destroyed

━━━ Manual Cleanup ━━━
✓ Cloud Run service deleted
ℹ️ Pub/Sub topic (events): already gone
✓ Pub/Sub topic (budget alerts): deleted
ℹ️ Pub/Sub subscription (events): already gone
🔐 Service account (app): permission denied
🔐 Service account (Cloud Build): permission denied
... (continue for all resources) ...

━━━ Teardown Summary ━━━
✓ Deleted: 15 resources
ℹ️ Already gone: 8 resources (not found — Terraform handled these)
🔐 Permission denied: 2 resources (may need project owner)

━━━ Cleanup ━━━
→ Removing state bucket test-z-1-499406-zilch-tfstate
✓ State bucket removed
→ Removing local Terraform state
✓ Local Terraform state removed

✓ Teardown complete! All infrastructure cleaned up.
```

## Implementation Details

### Changes to `terraform.py`

**Modify `destroy()` method:**
- Add `capture_output=True` to subprocess.run
- Parse stdout to extract resource counts (from terraform JSON diagnostics)
- Display progress: `→ Destroying resources ({total}, {to_delete} to delete)...`
- Return success/failure flag as before

### Changes to `zilch.py`

**Modify `_cleanup_gcp_resources()` method:**
- Change return type from None to Dict[str, List[tuple]]
- Structure: `{"deleted": [...], "already_gone": [...], "permission_denied": [...], "timeout": [...], "error": [...]}`
- Each list contains tuples: `(resource_name, error_reason)`
- Collect all results before printing
- After all cleanup, call new summary function

**Add new `_print_cleanup_summary()` function:**
- Takes the results dict
- Groups by outcome category
- Prints formatted summary with counts and guidance

### Changes to `output.py`

**Add helper functions:**
- `print_cleanup_summary(results: Dict[str, List]) -> None` — format and print grouped summary
- `get_outcome_indicator(outcome: str) -> str` — return emoji/symbol for outcome type

## Success Criteria

- [x] Terraform destroy suppresses verbose refresh output and shows resource counts
- [x] Each cleanup attempt shows one-line status with indicator
- [x] Summary groups failures by reason (permission_denied, already_gone, timeout, error)
- [x] No raw gcloud stderr visible to user
- [x] Users can quickly scan and understand: what was deleted, what was already gone, what needs attention
- [x] Beginner can take action based on failure categories (e.g., "permission denied — ask project owner")

## Edge Cases

1. **No failures:** Skip summary section, just show "✓ Teardown complete!"
2. **All failures:** Show full summary with all categories (some counts may be 0)
3. **Terraform destroy failure:** Show ⚠ indicator, continue to manual cleanup
4. **Timeout during terraform:** Catch TimeoutExpired, continue to manual cleanup

## Related Files

- `zilch.py` — main teardown command and cleanup logic
- `terraform.py` — terraform destroy execution
- `output.py` — output formatting utilities
