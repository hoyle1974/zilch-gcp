# Zilch Wiki

Welcome to the Zilch knowledge base. This is a structured, interlinked reference for understanding and using Zilch to deploy serverless applications on Google Cloud Platform.

## Quick Start Paths

**I want to...**
- [Deploy my first app → Getting Started](#getting-started)
- [Understand what Zilch does → Core Concepts](#core-concepts)
- [Learn about a specific service → Services Directory](#services-directory)
- [Troubleshoot an issue → Troubleshooting](#troubleshooting)
- [Understand the architecture → Architecture](#architecture)

---

## Getting Started

1. **[Deployment Workflow](entities/deployment-workflow.md)** — Step-by-step guide to running `./deploy.sh`
2. **[Configuration Guide](entities/configuration.md)** — What `.zilch.config` is and how to customize it
3. **[First Deployment Checklist](topics/first-deployment.md)** — Prerequisites and verification steps

---

## Core Concepts

### Platform & Infrastructure
- **[Cloud Run](entities/cloud-run.md)** — Zilch's compute engine (serverless container platform)
- **[Always Free Tier](entities/always-free-tier.md)** — Cost constraints and quotas
- **[Terraform Infrastructure](entities/terraform.md)** — How Zilch defines infrastructure as code
- **[Remote State Backend](entities/remote-state.md)** — Cloud Storage bucket for Terraform state

### Operations & Security
- **[Service Accounts & IAM](entities/service-accounts.md)** — Least-privilege identity model
- **[Environment Variables](entities/environment-variables.md)** — Runtime configuration passed to Cloud Run

---

## Services Directory

### Data & Storage
- **[Firestore](entities/services/firestore.md)** — NoSQL document database
- **[Cloud Storage](entities/services/cloud-storage.md)** — Object storage for files
- **[BigQuery](entities/services/bigquery.md)** — Analytics and data warehousing

### Authentication & Security
- **[Firebase Auth](entities/services/firebase-auth.md)** — Social login and authentication
- **[Secret Manager](entities/services/secret-manager.md)** — Secure credential storage
- **[Cloud KMS](entities/services/cloud-kms.md)** — Encryption key management

### AI & Machine Learning
- **[Vertex AI](entities/services/vertex-ai.md)** — AI/ML API access (Gemini)
- **[Vision AI](entities/services/vision-ai.md)** — Image analysis and processing
- **[Speech-to-Text](entities/services/speech-to-text.md)** — Audio transcription
- **[Translation API](entities/services/translation.md)** — Multi-language support

### CI/CD & Automation
- **[Cloud Build](entities/services/cloud-build.md)** — Automated builds from GitHub
- **[Artifact Registry](entities/services/artifact-registry.md)** — Container image registry
- **[Cloud Scheduler](entities/services/cloud-scheduler.md)** — Serverless cron jobs

### Messaging & Events
- **[Pub/Sub](entities/services/pubsub.md)** — Event streaming and messaging
- **[Cloud Tasks](entities/services/cloud-tasks.md)** — Async job queues

### Monitoring & Operations
- **[Cloud Monitoring](entities/services/cloud-monitoring.md)** — Alerts and budget tracking

---

## Architecture

### Deployment Architecture
- **[Deployment Workflow](entities/deployment-workflow.md)** — How `./deploy.sh` works
- **[Infrastructure as Code](entities/terraform.md)** — Terraform resource structure
- **[Service Account Permissions](entities/service-accounts.md)** — IAM roles and bindings

### Network & Runtime
- **[Cloud Run Container Model](entities/cloud-run.md)** — How containers run and scale
- **[Environment Variables & Secrets](entities/environment-variables.md)** — Application configuration

---

## Troubleshooting

Common issues and solutions organized by symptom:

- **[Health Check Timeouts](topics/troubleshooting/health-checks.md)** — App deployed but health checks failed
- **[Permission Errors](topics/troubleshooting/permissions.md)** — IAM or API access issues
- **[Deployment Failures](topics/troubleshooting/deployment.md)** — Terraform or Cloud Build errors
- **[State & Backend Issues](topics/troubleshooting/state.md)** — Remote state bucket problems

---

## Operations

### Maintenance
- **[Viewing Logs](topics/operations/logs.md)** — Debugging with Cloud Run logs
- **[Monitoring Usage](topics/operations/monitoring.md)** — Checking quotas and free tier limits
- **[Updating Configuration](topics/operations/updates.md)** — Re-running `./deploy.sh`
- **[Infrastructure Teardown](topics/operations/teardown.md)** — Destroying resources safely

---

## Development

### Building Apps for Zilch
- **[Application Development Guide](topics/development/building-apps.md)** — Using Zilch services in your code
- **[SDK & Authentication](topics/development/application-default-credentials.md)** — Application Default Credentials (ADC)
- **[Service Integration Patterns](topics/development/service-patterns.md)** — Common code patterns

---

## Reference

### File Structure
```
zilch-gcp/
├── deploy.sh              # Interactive deployment script
├── teardown.sh            # Infrastructure destruction script
├── main.tf                # Terraform: infrastructure definitions
├── variables.tf           # Terraform: input variables
├── outputs.tf             # Terraform: resource outputs
├── backend.tf             # Terraform: remote state configuration
├── cloud_scheduler.tf     # Terraform: Cloud Scheduler resources
├── cloud_monitoring.tf    # Terraform: Cloud Monitoring resources
├── README.md              # Quick start guide (this file)
└── docs/
    └── wiki/              # Structured knowledge base
        ├── INDEX.md       # This file
        ├── entities/      # Core concept pages
        └── topics/        # Topic-specific guides
```

### External References
- **[Google Cloud Always Free Tier](https://cloud.google.com/free/docs/always-free-usage-limits)** — Official quota limits
- **[Cloud Run Documentation](https://cloud.google.com/run/docs)** — Google Cloud reference
- **[Terraform Google Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)** — IaC reference

---

## Contributing to This Wiki

This wiki is maintained by Claude Code and grows as Zilch evolves. When you:
- Add a new service or feature → Create an entity page
- Discover a common issue → Add to troubleshooting
- Implement a pattern → Add to development guide
- Learn something valuable → Update related pages with cross-references

The goal is for this wiki to become increasingly valuable as a synthesis of all Zilch knowledge, not just a collection of raw documentation.

---

## Map of Concepts

[Cloud Run] ← manages → [Service Accounts & IAM]
     ↓
[Environment Variables] ← fed by → [Secret Manager], [Firestore], [Cloud Storage]
     ↓
[Application Code] ← built by → [Cloud Build]
     ↓
[Artifact Registry] ← stores → [Container Images]

[Cloud Scheduler] → triggers → [Cloud Run Endpoints]
[Cloud Monitoring] → alerts on → [Cloud Run Metrics]

[Always Free Tier] ← constrains → [Cloud Run], [Services]
[Terraform] ← defines → [Infrastructure]
[Remote State Backend] ← managed by → [Terraform]

---

**Last updated:** 2026-06-15  
**Status:** Core documentation complete, maintained incrementally
