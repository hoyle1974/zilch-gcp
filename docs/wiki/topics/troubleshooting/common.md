---
title: Common Issues & Debugging
tags: [troubleshooting, python, zilch.py]
last_updated: 2026-06-20
source_count: 2
sources:
  - IMPLEMENTATION_SUMMARY.md
  - PYTHON_MIGRATION_PLAN.md
---

# Common Issues & Debugging

Quick solutions for issues you might hit when using Zilch's Python CLI (`zilch.py`).

## Deployment Issues

### "Error: State bucket already exists"
**What:** Terraform says the state bucket is already there.
**Why:** You've run `python3 zilch.py deploy` before, and `gcp.create_state_bucket()` detected and reused the existing bucket.
**Fix:** This is normal. Just continue with the deployment. Don't delete the bucket.

### "Error: Permission denied" during deploy
**What:** Terraform fails with IAM errors, or `zilch.py` exits early with a `GCPError`.
**Why:** Your GCP user doesn't have Editor role on the project (`gcp.validate_iam_permissions()` checks this before Terraform runs).
**Fix:** Ask the project owner to grant you Editor role:
```bash
gcloud projects add-iam-policy-binding PROJECT_ID \
  --member=user:YOUR_EMAIL \
  --role=roles/editor
```

### "Error: Project not found"
**What:** Can't find your GCP project.
**Why:** You used the Project **Name** instead of the Project **ID**. Caught by `gcp.validate_project()`.
**Fix:** In GCP Console, go to Settings. Copy the Project **ID** (not Name), and use that with `python3 zilch.py deploy`.

### "Deployment timed out"
**What:** `python3 zilch.py deploy` takes a long time or hangs.
**Why:** Terraform is stuck or GCP is slow. Terraform subprocess calls in `terraform.py` have generous but finite timeouts (e.g. 600 seconds for apply/destroy, 120 seconds for init).
**Fix:**
- Check your internet connection
- Press Ctrl+C and try again (`zilch.py` catches `KeyboardInterrupt` and exits cleanly)
- Check GCP status: https://status.cloud.google.com
- Look for errors in the output — Terraform usually says what failed

### "Found existing Terraform state lock"
**What:** `zilch.py` reports a stale lock before running Terraform.
**Why:** A previous deployment was interrupted (e.g. Ctrl+C during `terraform apply`) and left a lock file in the state bucket.
**Fix:** When prompted, confirm removal (`Remove stale lock and continue?`). In `--auto` mode, re-run interactively once to clear it, or remove manually:
```bash
gcloud storage rm gs://PROJECT_ID-zilch-tfstate/terraform/state/APP_NAME/.terraform.tfstate.lock.info
```

---

## Runtime Issues

### "App deployed but health checks timed out"
**What:** Cloud Run starts the container but `health_check.check_cloud_run_health()` marks it unresponsive after 3 retries.
**Why:** Your app doesn't listen on `$PORT` or takes too long to start.
**Fix:** See [Health Check Timeouts](health-checks.md).

### "Application crashes immediately"
**What:** Container starts but then exits.
**Why:** App has a startup error or unhandled exception.
**Fix:**
```bash
gcloud run logs read YOUR_APP_NAME --region=us-central1 --limit=50
```
Look for the error message. Common causes:
- Missing dependency (import error)
- Port already in use
- Environment variable missing
- Configuration file not found

### "Permission denied" when accessing a service
**What:** `PermissionDenied` or `Forbidden` error from Google Cloud.
**Why:** Service isn't enabled, or service account doesn't have permission.
**Fix:**
```bash
python3 zilch.py deploy  # Re-run and enable the service you need
```

### "Service isn't available"
**What:** Environment variable is empty (`ZILCH_FIRESTORE_DATABASE` is `None`).
**Why:** You didn't enable the service during deployment.
**Fix:** Re-run deployment and enable the service:
```bash
python3 zilch.py deploy
# Say "yes" to the service you want to enable
```

---

## Local Development Issues

### "Could not locate credentials" when testing locally
**What:** Google Cloud SDK can't find authentication credentials.
**Why:** You haven't set up Application Default Credentials.
**Fix:**
```bash
gcloud auth application-default login
```
This opens a browser to authenticate your account. After that, your code can access Google Cloud services.

### "google.auth.exceptions.DefaultCredentialsError"
**What:** Same as above.
**Fix:** Run `gcloud auth application-default login`.

### Code works on Cloud Run but not locally
**What:** Local tests fail but production works.
**Why:** Different credentials or missing environment variables locally.
**Fix:**
- Ensure you've run `gcloud auth application-default login`
- For local testing, set environment variables:
  ```bash
  export ZILCH_PROJECT_ID=my-project
  export ZILCH_FIRESTORE_DATABASE=my-db
  python app.py
  ```

### Docker image builds locally but fails on Cloud Build
**What:** `gcloud run deploy` or Cloud Build fails.
**Why:** Dependencies missing, or Dockerfile has issues.
**Fix:**
```bash
# Test your Dockerfile locally
docker build -t myapp .
docker run -p 8080:8080 myapp

# Visit http://localhost:8080 and verify it works
```

---

## Zilch CLI / Python Environment Issues

### "command not found: zilch.py" or "python3: command not found"
**What:** Shell can't find `zilch.py` or Python itself.
**Why:** You're not in the `zilch-gcp` directory, or Python 3 isn't installed/activated.
**Fix:**
```bash
cd zilch-gcp
python3 --version   # Should be 3.8+
python3 zilch.py --help
```

### "ModuleNotFoundError: No module named 'click'" (or 'pydantic', 'requests')
**What:** `zilch.py` fails immediately on import.
**Why:** Dependencies aren't installed in your current Python environment.
**Fix:**
```bash
python3 -m venv venv
source venv/bin/activate
make install
# OR: pip install -r requirements.txt
```

### "No .zilch.config or template found"
**What:** `zilch.py deploy` exits immediately with this error.
**Why:** Neither `.zilch.config` nor `.zilch.config.template` exists in the current directory.
**Fix:** Make sure you're in the `zilch-gcp` directory and that the repo checkout is complete:
```bash
cd zilch-gcp
ls .zilch.config.template  # Should exist in a fresh checkout
```

---

## Configuration Issues

### "Can't find .zilch.config"
**What:** `zilch.py` complains the config file is missing.
**Why:** You're not in the right directory, or you haven't completed a first deploy yet.
**Fix:** Make sure you're in the `zilch-gcp` directory:
```bash
cd zilch-gcp
ls .zilch.config  # Should exist after a successful deploy
```

### "Invalid config: ... Invalid app name" or "Region must be one of: ..."
**What:** `ZilchConfig.load_from_file()` raises `ValueError` and `zilch.py` exits before touching GCP.
**Why:** A field in `.zilch.config` failed Pydantic validation — for example, `app_name` isn't 3-30 lowercase letters/numbers/hyphens, or `gcp_region` isn't `us-central1`, `us-east1`, or `us-west1`.
**Fix:**
- Get your Project ID from GCP Console → Settings (Project IDs are lowercase with hyphens, e.g. `my-project-123`; Project Names can have spaces and capitals)
- Fix the offending field in `.zilch.config`, or delete the file and re-run `python3 zilch.py deploy` to regenerate it via prompts

### "Wrong region selected"
**What:** Infrastructure deployed to wrong region.
**Why:** This shouldn't be possible — `ZilchConfig`'s `gcp_region` validator rejects anything other than `us-central1`, `us-east1`, or `us-west1` at config-load time.
**Fix:** If you see infrastructure in another region, check whether it was created by a different tool or a manual `terraform apply`. Re-run `python3 zilch.py deploy` and choose one of the three Always Free regions.

---

## Cost & Quota Issues

### "Service quota exceeded"
**What:** API returns quota exceeded error.
**Why:** You've exceeded the Always Free tier limit for that month.
**Fix:**
- Check usage: https://console.cloud.google.com/billing/reports
- Review [Always Free Tier](../../entities/always-free-tier.md) limits
- Wait until next month (quotas reset monthly)
- Upgrade to paid if needed

### "Unexpected charges appeared"
**What:** You got a bill when you expected free tier.
**Why:** Used service outside Always Free region, or exceeded free quota.
**Fix:**
- Check which resources ran: https://console.cloud.google.com/billing/reports
- Verify region (must be us-central1, us-east1, or us-west1)
- Check Cloud Run logs for unexpected traffic
- If overcharged, contact GCP support

---

## Still Stuck?

1. **Check `zilch.py status` and logs first:**
   ```bash
   python3 zilch.py status
   gcloud run logs read YOUR_APP_NAME --region=us-central1 --limit=100
   ```

2. **Run the test suite** to confirm your local environment is sane:
   ```bash
   make test
   ```

3. **Search the issue:**
   - Cloud Run: https://cloud.google.com/run/docs/troubleshooting
   - Terraform: https://registry.terraform.io/providers/hashicorp/google/latest/docs

4. **Ask for help:**
   - [Open an issue](https://github.com/hoyle1974/zilch-gcp/issues)
   - Include: error message, logs, and what you were trying to do

---

**Links:** [Health Check Timeouts](health-checks.md) | [Always Free Tier](../../entities/always-free-tier.md) | [Deployment Workflow](../../entities/deployment-workflow.md) | [Deployment Reliability](../../entities/deployment-reliability.md) | [Configuration](../../entities/configuration.md)
