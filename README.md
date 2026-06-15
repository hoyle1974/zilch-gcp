# Zilch: Scale-to-Zero GCP Infrastructure

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Zilch helps solo developers, indie hackers, and non-backend engineers deploy production-grade serverless applications on Google Cloud Platform without touching the web console.

## What is Zilch?

Zilch is an **interactive infrastructure automation framework** that:

- ✅ **Runs entirely in Google Cloud Shell** (no local setup required)
- ✅ **Deploys Cloud Run + 12 optional services** (Firestore, Secrets, Storage, Firebase Auth, Vertex AI, Pub/Sub, Cloud Tasks, BigQuery, Cloud KMS, Vision AI, Speech-to-Text, Translation)
- ✅ **Enforces Always Free tier compliance** (regions, quotas, best practices)
- ✅ **Manages state securely** (remote state in Cloud Storage)
- ✅ **Provides zero-friction UX** (interactive prompts, health checks, clear errors)
- ✅ **Automatic CI/CD** (Phase 2): Connect your GitHub repository. Every push to `main` auto-builds and deploys your app with zero manual steps.

## Getting Started

### 1. Open Google Cloud Shell

Click the **Cloud Shell** button in your GCP project or visit: https://shell.cloud.google.com

### 2. Clone This Repository

```bash
git clone https://github.com/hoyle1974/zilch-gcp.git
cd zilch-gcp
```

### 3. Run the Deployment Script

```bash
chmod +x deploy.sh && ./deploy.sh
```

The script will prompt you for:
- Your GCP Project ID
- Application name (e.g., `my-awesome-app`)
- Target region (us-central1, us-east1, us-west1)
- Feature toggles (Firestore, Secrets, Storage, Firebase Auth, Vertex AI)

Within 2-3 minutes, your app will be live.

## What Gets Provisioned?

### Core
- **Cloud Run Service** (public, auto-scaling, 2M requests/month free)
- **Service Account** (least-privilege identity)
- **Remote State Backend** (Google Cloud Storage)

### Optional Features
| Feature | Free Tier | Enable Via |
|---------|-----------|-----------|
| Firestore NoSQL DB | 1GB storage, 50K reads/day | `enable_firestore` |
| Secret Manager | 6 secrets, 10K API calls/month | `enable_secret_manager` |
| Cloud Storage | 5GB storage, 1GB/month download | `enable_cloud_storage` |
| Firebase Auth | Unlimited users | `enable_firebase_auth` |
| Vertex AI | 60 requests/min (Gemini) | `enable_vertex_ai` |
| Pub/Sub | 10 GB/month | `enable_pubsub` |
| Cloud Tasks | 1M tasks/month | `enable_cloud_tasks` |
| BigQuery | 1 TB queried/month | `enable_bigquery` |
| Cloud KMS | 6 keys, 10K calls/month | `enable_cloud_kms` |
| Vision AI | 1,000 images/month | `enable_vision_ai` |
| Speech-to-Text | 60 minutes/month | `enable_speech_to_text` |
| Translation | 500K characters/month | `enable_translation` |

## File Structure

```
zilch-gcp/
├── deploy.sh                            # Interactive setup + GitHub integration script
├── tutorial.md                          # Cloud Shell interactive walkthrough
├── main.tf                              # Terraform: all Phase 1-3 infrastructure
├── variables.tf                         # Terraform: input variables with validation
├── outputs.tf                           # Terraform: resource outputs (URLs, IDs)
├── backend.tf                           # Terraform: remote state in Cloud Storage
├── terraform.tfvars.example             # Template for variable values (never committed)
├── .zilch.config.example                # Template for deployment configuration
├── test-gcs-backend.sh                  # Helper: verify state backend setup
├── .gitignore                           # Git ignore rules
├── README.md                            # This file
└── docs/
    ├── PHASE_2_TEMPLATE.md              # Guide for extending with new services
    └── superpowers/
        ├── specs/
        │   ├── 2026-06-13-zilch-mvp-design.md      # Phase 1 architecture
        │   └── 2026-06-14-zilch-phase-2-design.md  # Phase 2 CI/CD design
        └── plans/
            └── 2026-06-15-zilch-phase-3-plan.md    # Phase 3 roadmap
```

## Deploy Your Own Code

Once Zilch completes, replace the Hello World container with your own:

```bash
gcloud run deploy YOUR_APP_NAME --source .
```

Point it to a GitHub repo with a `Dockerfile` and it will auto-build and deploy.

## Accessing Services from Your App

Your Cloud Run service automatically receives environment variables for each enabled service:

```python
# Example: Python app accessing Firestore
import os
from google.cloud import firestore

if os.getenv('ZILCH_FIRESTORE_DATABASE'):
    db = firestore.Client(database=os.getenv('ZILCH_FIRESTORE_DATABASE'))
    docs = db.collection('users').get()
```

All Google Cloud SDKs use **Application Default Credentials (ADC)**, which automatically authenticates as your app's service account.

## Environment Variables

Your app receives these env vars (if enabled):

```
ZILCH_PROJECT_ID          → Your GCP Project ID
ZILCH_APP_NAME            → Your application name
ZILCH_FIRESTORE_DATABASE  → Database name (if Firestore enabled)
ZILCH_SECRET_PREFIX       → Prefix for secrets (if Secrets enabled)
ZILCH_STORAGE_BUCKET      → Bucket name (if Storage enabled)
ZILCH_VERTEX_AI_ENABLED   → "true" (if Vertex AI enabled)
ZILCH_FIREBASE_ENABLED    → "true" (if Firebase Auth enabled)
```

## Monitoring & Logs

View your app's logs:

```bash
gcloud run logs read YOUR_APP_NAME --region=us-central1
```

Monitor resource usage:

```bash
gcloud run services describe YOUR_APP_NAME --region=us-central1
```

## Troubleshooting

### "Active gcloud credential context not discovered"
```bash
gcloud auth login
```

### "Project not found"
Double-check your Project ID and ensure you have IAM permissions.

### "App deployed but health checks timed out"
- Check logs: `gcloud run logs read <app-name>`
- Ensure your app listens on `$PORT` (default: 8080)
- Check that startup completes within 5 minutes

### "State bucket already exists"
This is normal on subsequent runs. Zilch reuses the existing bucket.

## Architecture & Design

For detailed architecture decisions, production guarantees, and design rationale, see:

📖 **[Zilch MVP Design Specification](docs/superpowers/specs/2026-06-13-zilch-mvp-design.md)**

## Implementation Status

**Phase 1:** Core Cloud Run + Firestore, Secrets, Storage, Firebase Auth, Vertex AI — ✅ Complete

**Phase 2:** Cloud Build + Artifact Registry (automatic container builds from GitHub) — ✅ Complete

**Phase 3:** Extended services (Pub/Sub, Cloud Tasks, BigQuery, Cloud KMS, Vision AI, Speech-to-Text, Translation) — ✅ All toggles implemented, integration guide in progress

All Phase 3 services support feature flags via `variables.tf`. See `docs/superpowers/specs/` for architecture details and `docs/superpowers/plans/` for roadmap.

## Cost & Quotas

All resources default to Always Free tier. Monitor usage at:

https://console.cloud.google.com/billing/reports

## License

MIT License — See LICENSE file for details.

## Contributing

This is an open-source project. Contributions welcome!

- Found a bug? [Create an issue](https://github.com/hoyle1974/zilch-gcp/issues)
- Want to add a service? [See Phase 3 Extension Guide](docs/PHASE_2_TEMPLATE.md)
- Have feedback? [Join discussions](https://github.com/hoyle1974/zilch-gcp/discussions)

## Support

- 📚 [Google Cloud Free Tier Limits](https://cloud.google.com/free/docs/always-free-usage-limits)
- 🔐 [Cloud Run Security Best Practices](https://cloud.google.com/run/docs/security)
- 🛠️ [Terraform Google Provider Docs](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

---

**Made with ❤️ for solo developers and indie hackers.**
