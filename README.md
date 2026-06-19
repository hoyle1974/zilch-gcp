# Zilch: Scale-to-Zero GCP Infrastructure

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

> **Transparency Note:** This project was created with the help of LLMs (Claude and Gemini). We believe in being upfront about this — if you have concerns about using AI-assisted tools, we want you to know before deciding whether to use Zilch.

Zilch helps solo developers, indie hackers, and non-backend engineers deploy production-grade serverless applications on Google Cloud Platform without touching the web console. Deploy a working app in 2-3 minutes from Cloud Shell.

## What is Zilch?

Zilch is an interactive infrastructure-as-code framework that automates GCP serverless deployments via Terraform. Run `./deploy.sh` in Cloud Shell, answer a few prompts, and deploy a complete application stack in 2-3 minutes.

You get:
- **Cloud Run** — Serverless container platform, auto-scaling, 2M requests/month free
- **12 optional services** — Firestore, Secret Manager, Cloud Storage, Firebase Auth, Vertex AI, Pub/Sub, Cloud Tasks, BigQuery, Cloud KMS, Vision AI, Speech-to-Text, Translation
- **Always Free tier** — Only provisions in Always Free regions (us-central1, us-east1, us-west1)
- **Remote Terraform state** — Stored in Cloud Storage, not in your repo
- **Optional CI/CD** — Connect GitHub for push-to-deploy workflows
- **Least-privilege IAM** — Service account only has permissions for enabled services

## Getting Started

### 1. Open Cloud Shell

Click the **Cloud Shell** button in your GCP project or visit: https://shell.cloud.google.com

### 2. Clone and Deploy

```bash
git clone https://github.com/hoyle1974/zilch-gcp.git
cd zilch-gcp
chmod +x deploy.sh && ./deploy.sh
```

### 3. Answer Configuration Prompts

The script will ask for:
- Your GCP Project ID
- Application name
- Target region (us-central1, us-east1, or us-west1)
- Which optional services to enable (Firestore, Storage, Firebase Auth, etc.)

The deployment completes in 2-3 minutes. You'll receive a Cloud Run URL and environment variable names to use in your app.

### 4. Deploy Your Code

```bash
gcloud run deploy YOUR_APP_NAME --source .
```

This builds and deploys your application. For automatic deployments on git push, enable Cloud Build during the initial setup.

## What Gets Provisioned?

### Core
- **Cloud Run Service** — Serverless container platform, auto-scaling, 2M requests/month free
- **Service Account** — Least-privilege identity for your application
- **Remote State Backend** — Terraform state stored in Cloud Storage

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
├── main.tf                              # Terraform: Cloud Run and core services
├── variables.tf                         # Terraform: input variables with validation
├── outputs.tf                           # Terraform: resource outputs (URLs, IDs)
├── backend.tf                           # Terraform: remote state in Cloud Storage
├── terraform.tfvars.example             # Template for variable values (never committed)
├── .zilch.config.example                # Template for deployment configuration
├── test-gcs-backend.sh                  # Helper: verify state backend setup
├── .gitignore                           # Git ignore rules
├── README.md                            # This file
└── docs/
    └── wiki/                            # Structured knowledge base
        ├── INDEX.md                     # Wiki home and navigation
        ├── entities/                    # Core concept pages
        └── topics/                      # Topic-specific guides
```

## Deploying Your Application

### Manual Deployment

```bash
gcloud run deploy YOUR_APP_NAME --source .
```

Builds and deploys your application from the current directory or a GitHub repository.

### Automatic Deployment

If you enabled Cloud Build during `./deploy.sh`, every push to your GitHub repository's `main` branch automatically triggers a build and deployment. No manual steps required.

To set this up during initial deployment, provide your GitHub repository owner and name when prompted.

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

## Documentation & Knowledge Base

Zilch includes a wiki that synthesizes how the system works and how to build with it.

### 📚 [**Start with the Wiki**](docs/wiki/INDEX.md)

The wiki covers:
- How Zilch works (Cloud Run, Terraform, Service Accounts, etc.)
- How to deploy and configure your app
- How to use Zilch services from your code
- Troubleshooting common issues

For detailed service documentation, refer to the official [Google Cloud docs](https://cloud.google.com).

## Capabilities

Zilch provides a comprehensive serverless platform with:

- **Core Services:** Cloud Run, Firestore, Cloud Storage, Secret Manager, Firebase Authentication, Vertex AI
- **CI/CD:** Cloud Build + Artifact Registry for automatic container builds and deployments from GitHub
- **Extended Services:** Pub/Sub, Cloud Tasks, BigQuery, Cloud KMS, Vision AI, Speech-to-Text, Translation

All optional services support feature flags via `variables.tf`, allowing you to enable only what you need. See the [wiki](docs/wiki/INDEX.md) for detailed service documentation.

## Cost & Quotas

All resources default to Always Free tier. Monitor usage at:

https://console.cloud.google.com/billing/reports

## Architecture & Design Details

See the [wiki](docs/wiki/INDEX.md) for:
- Architecture and design decisions
- CI/CD setup and automation
- Service integration patterns
- Implementation guides and service integration roadmaps

## Reference Application

Clone [`zilch-reference-app`](https://github.com/hoyle1974/zilch-reference-app) to see a working example Flask application that demonstrates all Zilch services.

## Contributing

- Found a bug? [Create an issue](https://github.com/hoyle1974/zilch-gcp/issues)
- Want to add a service? [See the wiki development guide](docs/wiki/topics/development/extending-zilch.md)
- Have feedback? [Open a discussion](https://github.com/hoyle1974/zilch-gcp/discussions)

## Support

- 📚 [Google Cloud Free Tier Limits](https://cloud.google.com/free/docs/always-free-usage-limits)
- 🔐 [Cloud Run Security Best Practices](https://cloud.google.com/run/docs/security)
- 🛠️ [Terraform Google Provider Docs](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

## License

MIT License — See LICENSE file for details.
