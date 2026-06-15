# Zilch: Scale-to-Zero GCP Infrastructure

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

> Deploy a production-grade serverless app on Google Cloud Platform in 2-3 minutes. From your browser. No console clicking, no IAM headaches, no credit card worries.

Zilch is built for solo developers, indie hackers, and anyone who'd rather spend time building features than fighting cloud infrastructure. If you've ever wasted an afternoon in the GCP console, this exists for you.

## How It Works

Zilch is a bash script that spins up a complete serverless stack using Terraform, right from Cloud Shell. Run `./deploy.sh`, answer a few prompts, and you're done. No Docker knowledge required. No IAM policy documents. No crossing your fingers hoping your bill stays under $50.

What you get:
- **Cloud Run** — Your app auto-scales from zero. Pay nothing when dormant.
- **12 optional add-ons** — Firestore, Postgres (via Secrets), Cloud Storage, Firebase Auth, Vertex AI, Pub/Sub, Cloud Tasks, BigQuery, Cloud KMS, Vision AI, Speech-to-Text, Translation
- **Always Free tier** — Zilch only provisions resources in regions that qualify. Your project won't accidentally bill you.
- **Remote state** — Terraform state lives safely in Cloud Storage, not in your repo.
- **GitHub auto-deploy** — Push to `main`, and your app redeploys automatically (Phase 2).
- **Zero complexity** — All the grunt work happens in one script. You focus on code.

## Getting Started (5 minutes)

**Step 1:** Open Cloud Shell
```bash
# Click the Cloud Shell icon in the GCP console, or go here:
https://shell.cloud.google.com
```

**Step 2:** Clone and run
```bash
git clone https://github.com/hoyle1974/zilch-gcp.git && cd zilch-gcp
chmod +x deploy.sh && ./deploy.sh
```

**Step 3:** Answer prompts
- Your GCP Project ID (e.g., `my-project-12345`)
- App name (e.g., `my-cool-app`)
- Region (us-central1, us-east1, or us-west1 — pick your nearest)
- Which services you want (Firestore? Storage? Vertex AI?)

**Step 4:** Watch it build
The script validates your setup, runs Terraform, and health-checks your app. You'll get a URL in 2-3 minutes. That's it.

**Step 5:** Deploy your code
```bash
gcloud run deploy my-cool-app --source .
```
Point it at any GitHub repo with a Dockerfile, and Cloud Build handles the rest.

## What Gets Provisioned?

### Always Included
- **Cloud Run** — Your app container. Scales to zero. 2M requests/month free.
- **Service Account** — A locked-down identity for your app. Only gets permissions for services you enable.
- **Remote Terraform State** — Lives in Cloud Storage. Safe, secure, shareable with your team.

### Pick What You Need

| Service | When You'd Use It | Free Tier |
|---------|------------------|-----------|
| **Firestore** | Real-time data, user profiles, game state | 1GB storage, 50K reads/day |
| **Secret Manager** | API keys, database passwords, tokens | 6 secrets free, 10K API calls/month |
| **Cloud Storage** | User uploads, files, images, backups | 5GB storage, 1GB download/month |
| **Firebase Auth** | User login with email, Google, GitHub, etc. | Unlimited users (same quotas as free tier) |
| **Vertex AI** | Call Gemini (GPT-like) from your app | 60 requests/min |
| **Pub/Sub** | Event streaming, message queues, async work | 10GB/month |
| **Cloud Tasks** | Delayed jobs, retries, scheduled tasks | 1M tasks/month |
| **BigQuery** | Analytics, SQL queries at scale | 1TB queried/month |
| **Cloud KMS** | Encryption key management | 6 keys free, 10K calls/month |
| **Vision AI** | Image recognition, OCR, object detection | 1K images/month |
| **Speech-to-Text** | Convert audio to text | 60 minutes/month |
| **Translation** | Translate between languages | 500K characters/month |

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

## Deploy Your Code

You have two options:

### Option 1: One-Off Deploy (Manual)
```bash
gcloud run deploy my-app --source .
```
This builds your code once and deploys it. You trigger it manually. Good for testing locally.

### Option 2: Auto-Deploy on Git Push (Recommended)
During `./deploy.sh`, if you enable Cloud Build and provide your GitHub repo, Zilch wires up a webhook. Now every `git push main` auto-builds and auto-deploys. No manual steps. This is what you want for a real project.

**Which should you use?**
- Testing locally? Manual deploy.
- Shipping to production? Auto-deploy. Set it once, forget it, ship features.

## Using Services in Your App

Zilch injects environment variables into your Cloud Run container. Your app reads them to know what's available.

```python
# Python example: read an env var to know if Firestore is enabled
import os
from google.cloud import firestore

if os.getenv('ZILCH_FIRESTORE_DATABASE'):
    # Firestore is enabled. Set it up.
    db = firestore.Client(database=os.getenv('ZILCH_FIRESTORE_DATABASE'))
    docs = db.collection('users').get()
else:
    # Firestore wasn't enabled during setup. Skip it.
    print("Firestore not available")
```

All Google Cloud SDKs use **Application Default Credentials (ADC)** — meaning your app automatically authenticates as its service account. No API keys to manage. No credentials files to hide. Just works.

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

**"Active gcloud credential context not discovered"**
```bash
gcloud auth login
```
You need to be logged in. The script will tell you exactly what to do.

**"Project not found"**
Check your Project ID. Type it exactly as it appears in the GCP console (lowercase, with hyphens).

**"App deployed but health checks timed out"**
Your container took too long to start or isn't listening on the right port.
```bash
# Check what's actually happening:
gcloud run logs read my-app-name --region=us-central1 --limit=20

# Your app must listen on $PORT (defaults to 8080)
# In Node: app.listen(process.env.PORT || 8080)
# In Python: app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))
```

**"State bucket already exists"**
Running deploy.sh twice? This is fine. Terraform will update what changed, create what's new, and leave the rest alone. You might see "1 changed, 0 added, 0 destroyed" — that's normal.

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

## Why Zilch?

Most GCP guides assume you're an infrastructure person. You're not. You're building a feature, a game, a side project. Infrastructure is the tax you pay to ship it. Zilch pays that tax for you.

**The problem Zilch solves:**
- Clicking around the GCP console is slow and error-prone.
- Most "quick start" guides are 10+ steps and you still miss an IAM permission.
- Terraform is powerful but overkill when you just want Cloud Run + Firestore.
- The Always Free tier is generous but easy to accidentally exceed.

**What Zilch doesn't do:**
- It's not a managed platform (like Heroku). You control your infrastructure via Terraform.
- It doesn't hide GCP. You still use `gcloud` commands, Google Cloud SDKs, and GCP dashboards.
- It's not a multi-cloud solution. If you want AWS, this isn't it.

But if you want to ship a serverless app on GCP in minutes without hiring a DevOps person, you're in the right place.

## Next Steps

1. **Read the reference app** — Clone [`zilch-reference-app`](https://github.com/hoyle1974/zilch-reference-app) to see a real Flask app using all Zilch services.
2. **Check the design docs** — [`docs/superpowers/specs/`](docs/superpowers/specs/) explains the architecture and "why" behind each choice.
3. **Deploy your own** — Customize deploy.sh for your team, or open an issue with ideas.

## Contributing & Support

- Found a bug? [Create an issue](https://github.com/hoyle1974/zilch-gcp/issues)
- Want to add a service? [See the extension guide](docs/PHASE_2_TEMPLATE.md)
- Have questions? [Check GCP Free Tier docs](https://cloud.google.com/free/docs/always-free-usage-limits) or open a discussion

## License

MIT — Use this however you want. No restrictions.
