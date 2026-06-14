# Welcome to Zilch 🚀

Zilch provisions a production-grade, serverless stack on Google Cloud Platform optimized to fit entirely inside GCP's **Always Free Tier**. No Dockerfiles, no local configurations, and no complex cloud consoles.

---

## 1. Quick Start

Execute the interactive provisioning script by running this command in your Cloud Shell terminal below:

```bash
chmod +x deploy.sh && ./deploy.sh
```

That's it! The script handles everything: authentication validation, state management, infrastructure provisioning, and health checks.

---

## 2. What Zilch Handles Automatically

**Region Enforcement:** Restricts all infrastructure to us-central1, us-east1, or us-west1 to secure free-tier eligibility.

**Remote State:** Seamlessly bootstraps an isolated Google Cloud Storage bucket to securely lock and track your state remotely.

**Least-Privilege Security:** Builds an application-specific Google Service Account with tight IAM boundaries matching only your chosen toggles.

**API Enablement:** Automatically activates required Google Cloud APIs (Cloud Run, Artifact Registry, and any optional services you select).

---

## 3. Understanding the Services (Optional Reading)

### Core: Cloud Run
Your app lives here. Cloud Run auto-scales from zero to handle traffic, and you only pay when requests arrive. The first 2M requests per month are free.

### Optional: Firestore
A serverless NoSQL database perfect for real-time data. Free tier gives you 1GB storage and 50K reads/day.

### Optional: Secret Manager
Securely store API keys, database passwords, and other credentials. Your Cloud Run service automatically gets permission to read them.

### Optional: Cloud Storage
A global file storage system. Upload user photos, documents, or any file. Free tier includes 5GB storage.

### Optional: Firebase Auth
Drop-in authentication. Users can sign up with email, Google, or other social providers. No code required to get started.

### Optional: Vertex AI
Access Google's Gemini AI models directly from your app. First 60 requests per minute are free.

---

## 4. Post-Deployment: Next Steps

Once the installation completes successfully:

### Deploy Your Own Code
```bash
gcloud run deploy YOUR_APP_NAME --source .
```

Replace `YOUR_APP_NAME` with your app's name. Point it to a GitHub repo or local directory with your code.

### Access Services from Your App
Your Cloud Run app automatically gets environment variables for each enabled service:

```python
# Example: Python app reading from Firestore
import os
from google.cloud import firestore

if os.getenv('ZILCH_FIRESTORE_DATABASE'):
    db = firestore.Client(database=os.getenv('ZILCH_FIRESTORE_DATABASE'))
    doc = db.collection('users').document('alice').get()
```

All Google Cloud client libraries use **Application Default Credentials (ADC)**, which means your app automatically authenticates as the service account Zilch created.

### Configure Firebase Auth (if enabled)
If you enabled Firebase Auth, visit the Firebase Console to set up sign-in methods:

```
https://console.firebase.google.com/project/YOUR_PROJECT_ID/authentication
```

Enable Email/Password, Google Sign-In, or other providers as needed.

### Monitor Your App
```bash
gcloud run logs read YOUR_APP_NAME --region=us-central1
```

### Track Your Usage
Monitor your free tier quotas at:

```
https://cloud.google.com/free/docs/always-free-usage-limits
```

---

## 5. Troubleshooting

**"Error: Active gcloud credential context not discovered"**
- Run: `gcloud auth login`
- Follow the browser popup to authenticate
- Return to Cloud Shell and try deploy.sh again

**"App deployed but health checks timed out"**
- Your app may take >30 seconds to start
- Check logs: `gcloud run logs read <app-name>`
- Ensure your app listens on `$PORT` (default: 8080)

**"Project not found" error**
- Double-check your Project ID spelling
- Confirm you have permissions in that project

**"Bucket already exists" error**
- Your state bucket from a previous deployment exists
- This is normal—deploy.sh will reuse it

---

## 6. Cost & Quotas

Zilch stays free as long as you stay within these limits:

| Service | Free Tier | Typical Hobby App |
|---------|-----------|------------------|
| Cloud Run | 2M requests/month | ✅ Covered |
| Firestore | 1GB storage, 50K reads/day | ✅ Covered |
| Cloud Storage | 5GB storage | ✅ Covered |
| Secret Manager | 6 secrets, 10K API calls/month | ✅ Covered |
| Firebase Auth | Unlimited users | ✅ Covered |
| Vertex AI | 60 req/min (Gemini) | ✅ Covered |

---

## 7. What's Next?

- **Fork or clone this repo** and customize it for your needs
- **Read the design spec** in `docs/superpowers/specs/` for architectural details
- **Explore Phase 2** features (Cloud Build, Artifact Registry) in the contribution guide
- **Join the community** and share your Zilch deployments

Happy building! 🎉
