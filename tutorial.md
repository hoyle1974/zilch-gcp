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

## Phase 2: Cloud Build + GitOps (Automatic Deployment)

After the initial `./deploy.sh` setup, your app is ready for **continuous deployment**. Every push to your GitHub repository automatically triggers a build and deployment.

### How GitOps Works

1. **Code changes pushed to GitHub**
   ```bash
   git push origin main
   ```

2. **Cloud Build auto-detects the push**
   - Watches your repository (GitHub App connection)
   - Triggers immediately on push to `main` branch

3. **Cloud Build pipeline runs automatically**
   - Builds your container from `Dockerfile`
   - Pushes the image to Artifact Registry
   - Deploys to Cloud Run (zero downtime)

4. **Your app is live** (~5 minutes from push)

### Configuration: .zilch.config

Your GitHub repository contains `.zilch.config` - the source of truth for your deployment:

```
github_owner=your-username
github_repo=your-repo
gcp_project_id=your-project
enable_firestore=true
enable_cloud_build=true
# ... other toggles
```

**Important:** `.zilch.config` is PUBLIC-SAFE. Never put secrets here. Use GCP Secret Manager instead.

### Changing Infrastructure After Initial Deploy

To modify your infrastructure (e.g., add Firestore or enable new services):

1. **Edit `.zilch.config`** in your repo (locally or via GitHub web editor)
2. **Run `./deploy.sh` locally**
   ```bash
   ./deploy.sh  # Re-runs Terraform with new settings
   ```
3. **Push the updated `.zilch.config`** to GitHub
   ```bash
   git commit -am "chore: enable Firestore"
   git push origin main
   ```
4. **Cloud Build rebuilds** your app with the new infrastructure available

**Key Rule:** Infrastructure updates happen via `./deploy.sh` (local), not via git push. This prevents the deployment pipeline from corrupting itself.

### Rebuilding from Git History

If your current deployed image has a bug:
1. **Fix the code** and push to main
2. **Cloud Build automatically rebuilds** from the updated code
3. **New image deploys** (old image is discarded)

That's it—no manual rollback needed. All your code history is in git.

### Troubleshooting Cloud Build

**Build is stuck or slow:**
- Cloud Build takes 3-5 minutes (typical)
- Check progress: `gcloud builds log -stream LATEST --region=us-central1 --project=PROJECT_ID`

**Build failed - what to check:**
1. Dockerfile exists in repo root
2. Docker image builds locally: `docker build .`
3. Recent changes broke the build? Check git history

**No automatic deployments:**
- GitHub integration required manual setup (see initial deploy output)
- Verify Cloud Build trigger: `gcloud builds triggers list --project=PROJECT_ID`

---

## Phase 3: Advanced Services (Optional)

Phase 3 adds specialized services for event-driven architecture, data analytics, encryption, and AI capabilities.

### Pub/Sub - Event Streaming

Asynchronous messaging for decoupled application components. Publish events from your app and subscribe to them from other services.

**Free tier:** 10 GB/month of throughput

**Env vars:**
- `ZILCH_PUBSUB_TOPIC` — Topic name for publishing events
- `ZILCH_PUBSUB_SUBSCRIPTION` — Subscription name for consuming events

**Example usage:**
```python
import os
from google.cloud import pubsub_v1

if os.getenv('ZILCH_PUBSUB_TOPIC'):
    publisher = pubsub_v1.PublisherClient()
    topic_path = publisher.topic_path(os.getenv('GOOGLE_CLOUD_PROJECT'), os.getenv('ZILCH_PUBSUB_TOPIC'))
    publisher.publish(topic_path, b"event data")
```

### Cloud Tasks - Async Job Queues

Schedule and dispatch tasks to be processed asynchronously. Perfect for sending emails, processing images, or long-running operations.

**Free tier:** 1 million tasks/month

**Env var:**
- `ZILCH_CLOUD_TASKS_QUEUE` — Queue path for dispatching tasks

### BigQuery - Analytics & Data Warehousing

Serverless analytics warehouse for querying massive datasets. Store application events and run analytics.

**Free tier:** 1 TB of queried data per month

**Env var:**
- `ZILCH_BIGQUERY_DATASET` — Dataset ID for storing analytics data

### Cloud KMS - Encryption Key Management

Manage encryption keys for sensitive data. Use for encrypting customer data, API keys, and other secrets at rest.

**Free tier:** 6 active keys, 10K API calls/month

**Env var:**
- `ZILCH_KMS_KEY_ID` — Crypto key ID for encryption/decryption

### Vision AI - Image Processing

Analyze images using Google's machine learning models. Detect objects, faces, text, and more.

**Free tier:** 1,000 images/month

**Env var:**
- `ZILCH_VISION_AI_ENABLED` — Set to "true" if enabled

### Speech-to-Text - Audio Transcription

Convert audio to text using automatic speech recognition.

**Free tier:** 60 minutes/month

**Env var:**
- `ZILCH_SPEECH_TO_TEXT_ENABLED` — Set to "true" if enabled

### Translation API - Multi-Language Support

Translate text between 100+ languages programmatically.

**Free tier:** 500K characters/month

**Env var:**
- `ZILCH_TRANSLATION_ENABLED` — Set to "true" if enabled

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
