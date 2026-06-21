# Zilch Wiki Index

Complete catalog of all wiki pages. This index lists every markdown file in the wiki with a one-line summary.

---

## Getting Started (New Users)

1. **[First Deployment Checklist](topics/first-deployment.md)** — Step-by-step checklist for your first Zilch deployment using `python3 zilch.py deploy`
2. **[Deployment Workflow](entities/deployment-workflow.md)** — Complete step-by-step flow from prompts through Cloud Run health checks
3. **[Configuration Guide](entities/configuration.md)** — How `.zilch.config` works, validation rules, and how to customize settings

---

## Core Concepts (Understanding Zilch)

### Architecture & Infrastructure

- **[Cloud Run](entities/cloud-run.md)** — Zilch's primary serverless compute engine: scaling, configuration, resource allocation
- **[Terraform Infrastructure](entities/terraform.md)** — Infrastructure as Code: how resources are defined, variables, conditionals, state
- **[Remote State Backend](entities/remote-state.md)** — How Terraform stores state in Cloud Storage for team collaboration and safety

### Configuration & Identity

- **[Configuration Guide](entities/configuration.md)** — `.zilch.config` format, validation rules, ZilchConfig Pydantic model
- **[Service Accounts & IAM](entities/service-accounts.md)** — Least-privilege service accounts and how IAM roles map to enabled services
- **[Environment Variables](entities/environment-variables.md)** — How Zilch passes service configuration to your app at runtime

### Constraints & Reliability

- **[Always Free Tier](entities/always-free-tier.md)** — Free quotas by service, cost limits, monitoring, what happens if you exceed
- **[Deployment Reliability](entities/deployment-reliability.md)** — Error handling, auto-recovery mechanisms, state reconciliation, lock detection

---

## Building with Zilch (Development)

### Using Services in Code

- **[Service Integration Patterns](topics/development/service-patterns.md)** — How to read environment variables and use Google Cloud SDKs for Firestore, Storage, Pub/Sub, etc.
- **[Application Default Credentials](topics/development/application-default-credentials.md)** — Automatic authentication: how ADC works, local setup, permissions model

### Extending Zilch

- **[Extending Zilch with New Services](topics/development/extending-zilch.md)** — Complete 9-step pattern for adding services: variables, APIs, resources, IAM, env vars, outputs

---

## Troubleshooting

- **[Health Check Timeouts](topics/troubleshooting/health-checks.md)** — Debugging app startup: health check failures, port binding, Dockerfile issues, fixes
- **[Common Issues & Debugging](topics/troubleshooting/common.md)** — Deployment errors, runtime issues, local dev problems, configuration validation, quota issues

---

## Maintenance & Metadata

- **[Wiki Changelog](log.md)** — Git-like commit log of wiki changes and updates

---

## Quick Reference

### By Topic

| Topic | Pages |
|-------|-------|
| **Deployment** | Workflow, Reliability, Configuration, First Deployment |
| **Infrastructure** | Terraform, Cloud Run, Remote State |
| **Security & Auth** | Service Accounts, Environment Variables, ADC |
| **Development** | Service Patterns, Extending Zilch |
| **Troubleshooting** | Health Checks, Common Issues |
| **Cost Management** | Always Free Tier |

### By Audience

| Role | Start Here |
|------|-----------|
| **New users** | First Deployment → Deployment Workflow → Configuration |
| **Developers** | Service Patterns → Application Default Credentials → Extending Zilch |
| **DevOps/SRE** | Terraform → Deployment Reliability → Remote State |
| **Troubleshooters** | Common Issues → Health Checks → Deployment Workflow |

---

## External References

- **[Google Cloud Always Free Tier](https://cloud.google.com/free/docs/always-free-usage-limits)** — Official quota reference
- **[Cloud Run Documentation](https://cloud.google.com/run/docs)** — GCP's definitive Cloud Run guide
- **[Terraform Google Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)** — Terraform provider documentation

---

**Last updated:** 2026-06-20

Total pages indexed: 16 entities + topics
