# Always Free Tier

The Always Free tier is Google Cloud's permanent free quota. Zilch is designed to stay within these limits, keeping your application completely free to run.

## What is Always Free?

Always Free is different from the 3-month $300 trial credit:
- **Permanent** — Available indefinitely, not just 3 months
- **Specific services and quotas** — Not all GCP services have free tiers
- **Regional** — Some quotas vary by region
- **Renewed monthly** — Monthly quotas (like API calls) reset each month

## Zilch's Always Free Strategy

Zilch **strictly targets Always Free regions**:
- `us-central1` (Iowa)
- `us-east1` (South Carolina)  
- `us-west1` (Oregon)

By restricting deployments to these regions, Zilch guarantees you stay within the free tier.

## Key Free Quotas

### Cloud Run (Compute)
- **2 million requests/month** — HTTP requests handled
- **360,000 GB-seconds/month** — Compute time (enough for ~1,200 hours of low-memory service)
- **0 cost when idle** — Instances scale to zero, no charges

### Data Services
| Service | Free Quota | See |
|---------|-----------|-----|
| Firestore | 1 GB storage, 50K reads/day | [Firestore](../services/firestore.md) |
| Cloud Storage | 5 GB storage, 1 GB/month outbound | [Cloud Storage](../services/cloud-storage.md) |
| BigQuery | 1 TB queried/month | [BigQuery](../services/bigquery.md) |
| Cloud KMS | 6 keys, 10K API calls/month | [Cloud KMS](../services/cloud-kms.md) |

### APIs & Services
| Service | Free Quota |
|---------|-----------|
| Secret Manager | 6 secrets, 10K API calls/month |
| Firebase Auth | Unlimited users |
| Pub/Sub | 10 GB/month throughput |
| Cloud Tasks | 1 million tasks/month |
| Vision AI | 1,000 images/month |
| Speech-to-Text | 60 minutes/month |
| Translation | 500K characters/month |
| Vertex AI | 60 requests/minute (Gemini) |

## Monitoring Usage

### Check Free Tier Status
```bash
gcloud billing accounts list
gcloud billing accounts describe ACCOUNT_ID
```

### View Quotas Per Service
```bash
gcloud compute project-info describe --project=PROJECT_ID
```

### GCP Console
Visit: https://console.cloud.google.com/billing/reports

## Staying Safe

### Budget Alerts
Zilch includes [Cloud Monitoring](../services/cloud-monitoring.md) with budget alerts. When you're approaching limits, alerts notify you to:
- Upgrade your plan if needed
- Optimize your application
- Disable expensive features

### Cost Estimation
Before adding a service, check its free tier. For example:
- Enabling Firestore → 1 GB free, then $0.06/GB
- Enabling BigQuery → 1 TB query/month free, then $6.25 per TB

### Regional Awareness
Always Free limits are sometimes **regional**. Zilch's region restriction ensures you're in the generous Always Free zones.

## What Happens If You Exceed Limits?

1. **Service degrades or stops** — Requests fail with quota errors
2. **Charges may apply** — Overage billing kicks in
3. **Alerts fire** — [Cloud Monitoring](../services/cloud-monitoring.md) notifies you
4. **You can disable services** — Remove `enable_*=true` from `.zilch.config` and re-run `./deploy.sh`

## Emergency Circuit Breaker

If you're worried about unexpected charges, Zilch provides an **emergency circuit breaker** via [Cloud Monitoring](../services/cloud-monitoring.md) that can automatically disable traffic when budget thresholds are exceeded.

## Optimization Tips

- **Scale to zero** — Idle Cloud Run services cost nothing; keep apps stateless
- **Batch requests** — Combine API calls to reduce quota consumption
- **Use BigQuery efficiently** — Query only the data you need (it's charged per GB scanned)
- **Enable services selectively** — Only turn on services you actually use
- **Monitor regularly** — Check your quotas weekly during development

## Related

- **[Cloud Run](cloud-run.md)** — Primary compute (generous free tier)
- **[Cloud Monitoring](../services/cloud-monitoring.md)** — Budget alerts
- **[Deployment Workflow](deployment-workflow.md)** — How Zilch stays within limits

---

**External Reference:** [Google Cloud Always Free Limits](https://cloud.google.com/free/docs/always-free-usage-limits)
