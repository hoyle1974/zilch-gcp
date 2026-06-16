# Cloud Run

Cloud Run is Zilch's primary compute engine. It's a serverless container platform where your application code runs.

## What is Cloud Run?

Cloud Run is a Google Cloud managed service that automatically runs your containerized application code in response to HTTP requests. Key characteristics:

- **Serverless** — You don't manage servers, VMs, or infrastructure
- **Stateless** — Each request is independent; instances scale up/down automatically
- **Containerized** — Your app runs in a Docker container
- **Fully managed** — Automatic scaling, networking, monitoring, updates
- **Always Free tier** — 2 million requests/month, 360,000 GB-seconds/month compute time

## How Zilch Uses Cloud Run

Zilch provisions a single Cloud Run **service** named after your `app_name`. This service:

1. Receives HTTP requests from the internet (or internal callers)
2. Routes them to running container instances
3. Scales automatically (0-1000s of instances based on load)
4. Runs with a dedicated [Service Account](service-accounts.md) for IAM permissions

## Deployment Models

### Manual Deployment
```bash
gcloud run deploy MY_APP --source .
```
You push code locally; Cloud Run builds and deploys.

### Automatic Deployment (with Cloud Build)
When [Cloud Build](../services/cloud-build.md) is enabled, every push to your GitHub `main` branch automatically triggers a build and deployment.

## Configuration

### Environment Variables
Cloud Run passes [Environment Variables](environment-variables.md) to your container at startup. These tell your app which services are available (Firestore name, bucket names, topic names, etc.).

### Service Account
Your Cloud Run instance runs as a [Service Account](service-accounts.md) with least-privilege permissions. Only enabled services grant IAM roles to this account.

### Port & Health Checks
- Your app must listen on `$PORT` (default: 8080)
- Cloud Run performs health checks by sending HTTP requests
- If health checks fail repeatedly, the instance is restarted
- Startup timeout: 5 minutes

### Resource Allocation
- Memory: 256 MB (always free tier)
- CPU: Shared (always free tier)
- Timeout: 60 seconds per request (free tier)

## Monitoring

### Logs
View logs with:
```bash
gcloud run logs read APP_NAME --region=REGION
```

### Metrics
Zilch provisions [Cloud Monitoring](../services/cloud-monitoring.md) to track:
- Request count
- Error rates
- Latency
- Cold start times

## Scaling Behavior

| Scenario | Behavior |
|----------|----------|
| No requests for 15 min | Instances scale to 0 (fully idle, no costs) |
| Sudden traffic spike | New instances start automatically (within seconds) |
| Sustained load | Instances stay warm and scale horizontally |
| Request completes | Instance may stay warm for next request or scale down |

This is why Zilch fits the Always Free tier — idle applications cost nothing.

## Related Concepts

- **[Service Accounts & IAM](service-accounts.md)** — Identity and permissions model
- **[Environment Variables](environment-variables.md)** — How your app learns about enabled services
- **[Cloud Build](../services/cloud-build.md)** — Automated deployments
- **[Cloud Monitoring](../services/cloud-monitoring.md)** — Observability and alerts

## Troubleshooting

**"App deployed but health checks failed"**
- Check logs: `gcloud run logs read APP_NAME`
- Ensure app listens on `$PORT`
- Check startup completes within 5 minutes

**"Requests timing out"**
- Default timeout is 60 seconds
- Long-running tasks should use [Cloud Tasks](../services/cloud-tasks.md) instead

**"Cold starts are slow"**
- Zilch enables startup CPU boost on v2 for faster container initialization
- Keep dependencies minimal

---

**Links:** [Always Free Tier](always-free-tier.md) | [Terraform](terraform.md) | [Deployment Workflow](deployment-workflow.md)
