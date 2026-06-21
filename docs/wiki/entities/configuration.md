---
title: Configuration Guide
tags: [configuration, python, pydantic, zilch.py]
last_updated: 2026-06-20
source_count: 2
sources:
  - IMPLEMENTATION_SUMMARY.md
  - PYTHON_MIGRATION_PLAN.md
---

# Configuration Guide

Zilch stores your deployment settings in `.zilch.config`, a simple key-value file that persists your choices between deployments. The file format is unchanged from earlier versions of the tool, but it is now loaded, validated, and written by a typed Python model — `ZilchConfig` (in `config.py`) — instead of manual shell parsing.

## What is .zilch.config?

`.zilch.config` is a text file read and written by `python3 zilch.py deploy`. It contains:
- Your GCP Project ID
- Application name
- Region choice
- Which services are enabled
- Feature toggles for Scheduler and Monitoring

Example:
```bash
gcp_project_id=my-project
app_name=my-app
gcp_region=us-central1
enable_firestore=true
enable_pubsub=false
enable_scheduler=true
scheduler_schedule="0 0 * * *"
...
```

## File Location

```
zilch-gcp/
└── .zilch.config          # Your deployment config (created by zilch.py)
```

The file is ignored by git (see `.gitignore`) because it can contain project-specific identifiers.

## How Loading Works: `ZilchConfig`

`ZilchConfig` is a Pydantic `BaseModel` defined in `config.py` with over 25 typed fields and default values. Loading replaces what used to be manual `case`/quote-stripping logic with a single call:

```python
config = ZilchConfig.load_from_file(".zilch.config")
```

Internally, `load_from_file()`:
1. Reads the file and prepends a `[DEFAULT]` section so Python's `configparser` can parse plain `key=value` lines
2. Strips surrounding quotes from values
3. Constructs a `ZilchConfig` instance, which runs every field validator automatically
4. Raises `ValueError` with a clear message if any field fails validation

Unknown keys in the file are ignored (`model_config = {"extra": "ignore"}`), so old or experimental settings don't break loading.

## Creating .zilch.config

### First Run
On first deployment, if no `.zilch.config` exists, `zilch.py deploy` copies `.zilch.config.template` into the current directory and exits, asking you to edit it and re-run. Once a config file is present, the interactive prompts (driven by `cli.py`) collect any missing values:
```bash
👉 Enter your target GCP Project ID: my-project
👉 Enter your application name [zilch-app]: my-app
🌐 Choose your infrastructure anchor zone (Always Free Eligible):
  [1] us-central1 (Iowa - Preferred Default)
  [2] us-east1    (South Carolina)
  [3] us-west1    (Oregon)
Selection [1-3, default: 1]: 1
❓ Enable Firestore NoSQL Database support? (y/n) [default: n]: y
...
```

After prompts complete (and before any GCP calls are made), `zilch.py` calls `config.save_to_file(".zilch.config")`.

### Subsequent Runs
The next time you run `python3 zilch.py deploy`, it loads `.zilch.config` via `ZilchConfig.load_from_file()` and uses those values as defaults. You can press Enter to accept them or change any value, or skip prompts entirely with `--auto`:

```bash
python3 zilch.py deploy --auto
```

## Configuration Options

These map directly to fields on `ZilchConfig`.

### GCP Settings
```bash
gcp_project_id=my-project        # Your GCP Project ID (required)
app_name=my-app                  # Application name (required)
gcp_region=us-central1           # Always Free region only
```

### Core Services
```bash
enable_firestore=true            # Firestore NoSQL Database
enable_secret_manager=true       # Secret Manager
enable_cloud_storage=true        # Cloud Storage
enable_firebase_auth=true        # Firebase Authentication
enable_vertex_ai=true            # Vertex AI / Gemini
```

### CI/CD & Automation
```bash
enable_cloud_build=true          # Cloud Build (recommended; defaults to true)
github_owner=myusername          # GitHub username/org (if Cloud Build enabled)
github_repo=myrepo               # GitHub repository name (if Cloud Build enabled)
```

### Advanced Services (Optional)
```bash
enable_pubsub=true               # Pub/Sub Event Streaming
enable_cloud_tasks=true          # Cloud Tasks Job Queues
enable_bigquery=true             # BigQuery Analytics
enable_cloud_kms=true            # Cloud KMS Encryption
enable_vision_ai=true            # Vision AI Image Processing
enable_speech_to_text=true       # Speech-to-Text
enable_translation=true          # Translation API
```

### Scheduling & Monitoring (Optional)
```bash
enable_scheduler=true            # Cloud Scheduler cron jobs
scheduler_schedule="0 0 * * *"   # Cron expression (daily at midnight)
scheduler_timezone="UTC"         # Timezone for cron
scheduler_endpoint="/api/cron"   # Cloud Run endpoint to call

enable_monitoring=true           # Cloud Monitoring with budget alerts
billing_account_name="My Billing Account"  # (optional, auto-detected)
billing_budget_limit_usd=10      # Monthly budget in USD
```

### MySQL (Optional)
```bash
enable_mysql=false               # MySQL database
mysql_database_name=zilch_app    # Database name
```

### Access Control & Billing
```bash
allow_unauthenticated_access=true   # Cloud Run public access
gcp_billing_account_id=             # Optional explicit billing account ID
```

## Validation Rules

Every field is validated by a Pydantic `@field_validator` at load time and at construction time — invalid values are rejected before any GCP API calls are made:

| Field | Rule |
|-------|------|
| `app_name` | 3-30 lowercase letters, numbers, hyphens: `^[a-z0-9-]{3,30}$` |
| `gcp_region` | Must be exactly one of `us-central1`, `us-east1`, `us-west1` |
| `scheduler_schedule` | Must have 5 whitespace-separated cron fields |
| `billing_budget_limit_usd` | Must parse as a positive number |

A bad value produces a `ValueError` with a specific message (e.g. "Invalid app name: must be 3-30 lowercase letters/numbers/hyphens") instead of a generic shell-parsing failure.

## Modifying Configuration

### Edit Manually
You can manually edit `.zilch.config` before running `zilch.py`:

```bash
nano .zilch.config
python3 zilch.py deploy --auto
```

### Or Re-run Deploy
Run `python3 zilch.py deploy` (without `--auto`) and answer the prompts with your new values; press Enter on any prompt to keep the loaded default.

## Updating Services

If you want to enable/disable a service after initial deployment:

1. Run `python3 zilch.py deploy`
2. Answer prompts (press Enter to keep existing values, or change them)
3. Change the `enable_*=true/false` answers
4. Terraform will add or remove services as needed

Example: enabling BigQuery that was previously disabled
```bash
✓ Config loaded
👉 Enter your target GCP Project ID [my-project]: 
...
❓ Enable BigQuery Analytics support? (y/n) [default: false]: y
# Now BigQuery will be created and added to your app
```

## Terraform Variables

`ZilchConfig.to_terraform_vars()` converts the validated config into the dictionary `TerraformExecutor.apply()` uses to build `-var=` arguments:

```python
def to_terraform_vars(self) -> dict:
    return {
        "gcp_project_id": self.gcp_project_id,
        "app_name": self.app_name,
        "gcp_region": self.gcp_region,
        "enable_firestore": self.enable_firestore,
        ...
    }
```

`TerraformExecutor` then lower-cases booleans (`true`/`false`) when building the `terraform apply`/`plan`/`destroy` command line — no manual string formatting is needed in `zilch.py` itself.

## Resetting Configuration

To start over with a fresh deployment:

1. **Delete `.zilch.config`**:
```bash
rm .zilch.config
```

2. **Run `python3 zilch.py deploy`** — Prompts will show built-in defaults instead of your previous values

3. **Or create a new project** — Use a different GCP Project ID to isolate completely

## Configuration Persistence

`zilch.py` saves `.zilch.config` via `ZilchConfig.save_to_file()` right after prompts complete (before any infrastructure changes are attempted). This allows:

- **Quick re-runs** — `python3 zilch.py deploy --auto` works immediately with saved config
- **Team consistency** — All developers use the same config
- **Version control aware** — `.gitignore` prevents committing `.zilch.config` (it may contain sensitive info)

## Advanced: Loading Config in Other Tools

Because `ZilchConfig` is a plain Pydantic model, other Python tooling in the repo can load and reuse it instead of re-parsing the file:

```python
from config import ZilchConfig

config = ZilchConfig.load_from_file(".zilch.config")
print(f"Deploying to project: {config.gcp_project_id}")
print(f"App name: {config.app_name}")

if config.enable_firestore:
    print("Firestore is enabled")
```

## Related

- **[Deployment Workflow](deployment-workflow.md)** — How config is loaded, saved, and used during deployment
- **[Deployment Reliability](deployment-reliability.md)** — How `gcp.py` and `terraform.py` handle config-driven setup failures
- **[Terraform](terraform.md)** — How config becomes Terraform variables
- **[Environment Variables](environment-variables.md)** — Runtime config (different from `.zilch.config`)

---

**Security Note:** Don't commit `.zilch.config` to git if it contains sensitive information. Use secrets management for production credentials instead.
