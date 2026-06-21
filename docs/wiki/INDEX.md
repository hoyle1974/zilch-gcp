# Zilch Wiki

A minimal knowledge base for understanding Zilch. This wiki synthesizes how Zilch works, not a replacement for Google Cloud docs.

## Getting Started

1. **[Deployment Workflow](entities/deployment-workflow.md)** — How `./deploy.sh` works
2. **[Configuration](entities/configuration.md)** — What `.zilch.config` is and how to customize it
3. **[First Deployment](topics/first-deployment.md)** — Prerequisites and verification
4. **[Deployment Reliability](entities/deployment-reliability.md)** — Error recovery and robustness features

---

## Core Concepts

### Understanding Zilch
- **[Cloud Run](entities/cloud-run.md)** — Zilch's compute engine and how apps scale
- **[Always Free Tier](entities/always-free-tier.md)** — Cost constraints that shape Zilch
- **[Terraform](entities/terraform.md)** — How Zilch defines infrastructure as code
- **[Remote State](entities/remote-state.md)** — Where Terraform stores state
- **[Service Accounts](entities/service-accounts.md)** — How Zilch authenticates your app
- **[Environment Variables](entities/environment-variables.md)** — How services talk to your app

---

## Building with Zilch

### Development
- **[Application Patterns](topics/development/service-patterns.md)** — How to use Zilch services from your code
- **[Application Default Credentials](topics/development/application-default-credentials.md)** — How authentication works
- **[Extending Zilch](topics/development/extending-zilch.md)** — Adding new services

---

## Roadmap & Future Plans

- **[MySQL Service Plan](topics/roadmap-mysql-service.md)** — Planned relational SQL database support

---

## Troubleshooting

- **[Health Check Timeouts](topics/troubleshooting/health-checks.md)** — App won't start
- **[Common Issues](topics/troubleshooting/common.md)** — General debugging

---

## See Also

- **[Google Cloud Free Tier](https://cloud.google.com/free/docs/always-free-usage-limits)** — Official quota reference
- **[Cloud Run Docs](https://cloud.google.com/run/docs)** — GCP's definitive reference
- **[Terraform Google Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)** — IaC reference

---

**Last updated:** 2026-06-20
