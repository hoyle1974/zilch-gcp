# Common Issues & Debugging

Quick solutions for issues you might hit when using Zilch.

## Deployment Issues

### "Error: State bucket already exists"
**What:** Terraform says the state bucket is already there.  
**Why:** You've run `./deploy.sh` before, and Zilch reused the existing bucket.  
**Fix:** This is normal. Just continue with the deployment. Don't delete the bucket.

### "Error: Permission denied" during deploy
**What:** Terraform fails with IAM errors.  
**Why:** Your GCP user doesn't have Editor role on the project.  
**Fix:** Ask the project owner to grant you Editor role:
```bash
gcloud projects add-iam-policy-binding PROJECT_ID \
  --member=user:YOUR_EMAIL \
  --role=roles/editor
```

### "Error: Project not found"
**What:** Can't find your GCP project.  
**Why:** You used the Project **Name** instead of the Project **ID**.  
**Fix:** In GCP Console, go to Settings. Copy the Project **ID** (not Name), and use that in `./deploy.sh`.

### "Deployment timed out"
**What:** `./deploy.sh` takes >10 minutes or hangs.  
**Why:** Terraform is stuck or GCP is slow.  
**Fix:** 
- Check your internet connection
- Press Ctrl+C and try again
- Check GCP status: https://status.cloud.google.com
- Look for errors in the output — Terraform usually says what failed

---

## Runtime Issues

### "App deployed but health checks timed out"
**What:** Cloud Run starts the container but marks it unhealthy.  
**Why:** Your app doesn't listen on `$PORT` or takes >5 minutes to start.  
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
./deploy.sh  # Re-run and enable the service you need
```

### "Service isn't available"
**What:** Environment variable is empty (`ZILCH_FIRESTORE_DATABASE` is `None`).  
**Why:** You didn't enable the service during `./deploy.sh`.  
**Fix:** Re-run deployment and enable the service:
```bash
./deploy.sh
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

## Configuration Issues

### "Can't find .zilch.config"
**What:** Script complains the config file is missing.  
**Why:** You're not in the right directory.  
**Fix:** Make sure you're in the `zilch-gcp` directory:
```bash
cd zilch-gcp
ls .zilch.config  # Should exist
```

### "Invalid project ID" in .zilch.config
**What:** Deployment fails with "invalid format" for project.  
**Why:** You used Project Name instead of Project ID, or it has special characters.  
**Fix:** 
- Get your Project ID from GCP Console → Settings
- Project IDs are lowercase with hyphens (e.g., `my-project-123`)
- Project Names can have spaces and capitals

### "Wrong region selected"
**What:** Infrastructure deployed to wrong region.  
**Why:** You chose us-west2 or another region not in Always Free Tier.  
**Fix:** Re-run `./deploy.sh` and choose us-central1, us-east1, or us-west1. These are the only Always Free regions.

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

1. **Check logs first:**
   ```bash
   gcloud run logs read YOUR_APP_NAME --region=us-central1 --limit=100
   ```

2. **Search the issue:**
   - Cloud Run: https://cloud.google.com/run/docs/troubleshooting
   - Terraform: https://registry.terraform.io/providers/hashicorp/google/latest/docs

3. **Ask for help:**
   - [Open an issue](https://github.com/hoyle1974/zilch-gcp/issues)
   - Include: error message, logs, and what you were trying to do

---

**Links:** [Health Check Timeouts](health-checks.md) | [Always Free Tier](../../entities/always-free-tier.md) | [Deployment Workflow](../../entities/deployment-workflow.md)
