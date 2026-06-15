# Phase 3: Advanced Services Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add 7 advanced GCP services (Pub/Sub, Cloud Tasks, BigQuery, Cloud KMS, Vision AI, Speech-to-Text, Translation) as optional toggles following Phase 1/2 patterns, enabling event-driven, async, analytics, and AI capabilities while maintaining Always Free tier compliance.

**Architecture:** Phase 3 extends the Phase 1/2 toggle pattern with 7 new services. Each service follows the same addition checklist: (1) variable in `variables.tf`, (2) conditional resource + IAM in `main.tf`, (3) environment variable injection to Cloud Run, (4) output in `outputs.tf`, (5) prompt in `deploy.sh`, (6) documentation updates. Services are independent—users enable any combination. Each service maintains Always Free tier limits and least-privilege IAM.

**Tech Stack:** Terraform (google provider), Bash scripting, GCP services (Pub/Sub, Cloud Tasks, BigQuery, Cloud KMS, Vertex AI Vision, Speech-to-Text, Translation)

---

## File Structure

### Files to Modify

- **`variables.tf`** — Add 7 new `enable_<service>` boolean variables (one per Phase 3 service)
- **`main.tf`** — Add resource definitions, IAM bindings, and conditional Cloud Run env vars for all 7 services
- **`outputs.tf`** — Add resource ID/name outputs for each enabled service
- **`deploy.sh`** — Add interactive prompts for each Phase 3 service, export TF_VAR variables
- **`tutorial.md`** — Add service descriptions and usage examples
- **`README.md`** — Update service table and file structure notes

### Files to Create

- None (all changes are additive to existing files)

---

## Implementation Tasks

### Task 1: Add Phase 3 Variables to `variables.tf`

**Files:**
- Modify: `variables.tf` (end of file)

- [ ] **Step 1: Read current end of variables.tf**

Run: `tail -20 variables.tf`

Expected: See Phase 1/2 variables ending with `enable_vertex_ai`

- [ ] **Step 2: Add Phase 3 service variables**

Append to `variables.tf`:

```hcl
variable "enable_pubsub" {
  type        = bool
  default     = false
  description = "Enable Pub/Sub for event streaming and messaging"
}

variable "enable_cloud_tasks" {
  type        = bool
  default     = false
  description = "Enable Cloud Tasks for async job queues"
}

variable "enable_bigquery" {
  type        = bool
  default     = false
  description = "Enable BigQuery for analytics and data warehousing"
}

variable "enable_cloud_kms" {
  type        = bool
  default     = false
  description = "Enable Cloud KMS for encryption key management"
}

variable "enable_vision_ai" {
  type        = bool
  default     = false
  description = "Enable Vision AI for image processing and analysis"
}

variable "enable_speech_to_text" {
  type        = bool
  default     = false
  description = "Enable Speech-to-Text API for audio transcription"
}

variable "enable_translation" {
  type        = bool
  default     = false
  description = "Enable Translation API for multi-language support"
}
```

Run: `cat >> variables.tf << 'EOF'`
(paste block above)
(then Ctrl+D to end)

- [ ] **Step 3: Verify additions**

Run: `tail -30 variables.tf | grep "enable_" | wc -l`

Expected: "12" (5 from Phase 1/2 + 7 from Phase 3)

- [ ] **Step 4: Format and validate**

Run: `terraform fmt variables.tf && terraform validate 2>&1 | head -5`

Expected: "Success!" or no formatting errors

- [ ] **Step 5: Commit**

```bash
git add variables.tf
git commit -m "feat: add Phase 3 variables for all 7 advanced services"
```

---

### Task 2: Add Pub/Sub Service to `main.tf`

**Files:**
- Modify: `main.tf` (after Phase 2 Cloud Build section)

- [ ] **Step 1: Locate Phase 2 Cloud Build section**

Run: `grep -n "PHASE 2:" main.tf | tail -1`

Expected: Line number where Phase 2 section starts

- [ ] **Step 2: Add Phase 3 marker and Pub/Sub resources after all Phase 2 resources**

Find the end of the Cloud Build trigger resource block (after `depends_on`), then add:

```hcl
# --- PHASE 3: ADVANCED SERVICES ---

# Pub/Sub Topic for event streaming
resource "google_pubsub_topic" "app_events" {
  count = var.enable_pubsub ? 1 : 0

  name                       = "${var.app_name}-events"
  message_retention_duration = "86400s"  # 24 hours (free tier acceptable)
  project                    = var.gcp_project_id

  labels = {
    app = var.app_name
  }
}

# Pub/Sub Subscription for consuming events
resource "google_pubsub_subscription" "app_events_sub" {
  count = var.enable_pubsub ? 1 : 0

  name                 = "${var.app_name}-events-subscription"
  topic                = google_pubsub_topic.app_events[0].name
  ack_deadline_seconds = 20
  project              = var.gcp_project_id
}

# IAM: Allow Cloud Run service account to publish/subscribe
resource "google_project_iam_member" "pubsub_editor" {
  count   = var.enable_pubsub ? 1 : 0
  project = var.gcp_project_id
  role    = "roles/pubsub.editor"
  member  = "serviceAccount:${google_service_account.app.email}"
}
```

- [ ] **Step 3: Add Pub/Sub env var to Cloud Run**

Find the `google_cloud_run_service` resource's `containers.env` block. Add before the closing brace:

```hcl
    env {
      name  = "ZILCH_PUBSUB_TOPIC"
      value = var.enable_pubsub ? google_pubsub_topic.app_events[0].name : ""
    }

    env {
      name  = "ZILCH_PUBSUB_SUBSCRIPTION"
      value = var.enable_pubsub ? google_pubsub_subscription.app_events_sub[0].name : ""
    }
```

- [ ] **Step 4: Format and validate**

Run: `terraform fmt main.tf && terraform validate 2>&1 | head -5`

Expected: "Success!" or validation errors resolved

- [ ] **Step 5: Commit**

```bash
git add main.tf
git commit -m "feat: add Pub/Sub topic, subscription, and IAM to Phase 3"
```

---

### Task 3: Add Cloud Tasks Service to `main.tf`

**Files:**
- Modify: `main.tf` (after Pub/Sub section)

- [ ] **Step 1: Add Cloud Tasks queue after Pub/Sub**

After the `google_project_iam_member pubsub_editor` block, insert:

```hcl
# Cloud Tasks queue for async job processing
resource "google_cloud_tasks_queue" "app_jobs" {
  count = var.enable_cloud_tasks ? 1 : 0

  name     = "projects/${var.gcp_project_id}/locations/${var.gcp_region}/queues/${var.app_name}-jobs"
  location = var.gcp_region

  rate_limits {
    max_concurrent_dispatches = 100
    max_dispatches_per_second = 100
  }

  retry_config {
    max_attempts = 5
    min_backoff  = "0.1s"
    max_backoff  = "3600s"
  }
}

# IAM: Allow Cloud Run to dispatch tasks
resource "google_project_iam_member" "cloud_tasks_enqueuer" {
  count   = var.enable_cloud_tasks ? 1 : 0
  project = var.gcp_project_id
  role    = "roles/cloudtasks.enqueuer"
  member  = "serviceAccount:${google_service_account.app.email}"
}
```

- [ ] **Step 2: Add Cloud Tasks env var to Cloud Run**

In `google_cloud_run_service` env block, add:

```hcl
    env {
      name  = "ZILCH_CLOUD_TASKS_QUEUE"
      value = var.enable_cloud_tasks ? "projects/${var.gcp_project_id}/locations/${var.gcp_region}/queues/${var.app_name}-jobs" : ""
    }
```

- [ ] **Step 3: Format and validate**

Run: `terraform fmt main.tf && terraform validate 2>&1 | head -5`

Expected: "Success!"

- [ ] **Step 4: Commit**

```bash
git add main.tf
git commit -m "feat: add Cloud Tasks queue and IAM to Phase 3"
```

---

### Task 4: Add BigQuery Service to `main.tf`

**Files:**
- Modify: `main.tf` (after Cloud Tasks section)

- [ ] **Step 1: Add BigQuery dataset after Cloud Tasks**

After the `google_project_iam_member cloud_tasks_enqueuer` block, insert:

```hcl
# BigQuery dataset for analytics
resource "google_bigquery_dataset" "app_analytics" {
  count = var.enable_bigquery ? 1 : 0

  dataset_id                  = "${replace(var.app_name, "-", "_")}_analytics"
  friendly_name               = "${var.app_name} Analytics"
  description                 = "Analytics dataset for ${var.app_name}"
  location                    = var.gcp_region == "us-central1" ? "US" : var.gcp_region == "us-east1" ? "US" : "US"
  default_table_expiration_ms = 7776000000  # 90 days (free tier quota management)
  project                     = var.gcp_project_id

  labels = {
    app = var.app_name
  }
}

# IAM: Allow Cloud Run to write to BigQuery
resource "google_project_iam_member" "bigquery_data_editor" {
  count   = var.enable_bigquery ? 1 : 0
  project = var.gcp_project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.app.email}"
}
```

- [ ] **Step 2: Add BigQuery env var to Cloud Run**

In `google_cloud_run_service` env block, add:

```hcl
    env {
      name  = "ZILCH_BIGQUERY_DATASET"
      value = var.enable_bigquery ? google_bigquery_dataset.app_analytics[0].dataset_id : ""
    }
```

- [ ] **Step 3: Format and validate**

Run: `terraform fmt main.tf && terraform validate 2>&1 | head -5`

Expected: "Success!"

- [ ] **Step 4: Commit**

```bash
git add main.tf
git commit -m "feat: add BigQuery dataset and IAM to Phase 3"
```

---

### Task 5: Add Cloud KMS Service to `main.tf`

**Files:**
- Modify: `main.tf` (after BigQuery section)

- [ ] **Step 1: Add KMS keyring and key after BigQuery**

After the `google_project_iam_member bigquery_data_editor` block, insert:

```hcl
# Cloud KMS keyring for encryption
resource "google_kms_key_ring" "app_keys" {
  count    = var.enable_cloud_kms ? 1 : 0
  name     = "${var.app_name}-keyring"
  location = var.gcp_region
  project  = var.gcp_project_id
}

# Cloud KMS crypto key for encryption/decryption
resource "google_kms_crypto_key" "app_key" {
  count           = var.enable_cloud_kms ? 1 : 0
  name            = "${var.app_name}-key"
  key_ring        = google_kms_key_ring.app_keys[0].id
  rotation_period = "7776000s"  # 90 days
  project         = var.gcp_project_id

  labels = {
    app = var.app_name
  }
}

# IAM: Allow Cloud Run to use KMS for encryption
resource "google_project_iam_member" "kms_crypto_key_encrypter_decrypter" {
  count   = var.enable_cloud_kms ? 1 : 0
  project = var.gcp_project_id
  role    = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member  = "serviceAccount:${google_service_account.app.email}"
}
```

- [ ] **Step 2: Add KMS env var to Cloud Run**

In `google_cloud_run_service` env block, add:

```hcl
    env {
      name  = "ZILCH_KMS_KEY_ID"
      value = var.enable_cloud_kms ? google_kms_crypto_key.app_key[0].id : ""
    }
```

- [ ] **Step 3: Format and validate**

Run: `terraform fmt main.tf && terraform validate 2>&1 | head -5`

Expected: "Success!"

- [ ] **Step 4: Commit**

```bash
git add main.tf
git commit -m "feat: add Cloud KMS keyring and crypto key to Phase 3"
```

---

### Task 6: Add Vision AI Service to `main.tf`

**Files:**
- Modify: `main.tf` (after Cloud KMS section)

- [ ] **Step 1: Enable Vision AI API and add IAM**

After the `google_project_iam_member kms_crypto_key_encrypter_decrypter` block, insert:

```hcl
# Enable Vision AI API
resource "google_project_service" "vision_ai" {
  count   = var.enable_vision_ai ? 1 : 0
  service = "aiplatform.googleapis.com"
  project = var.gcp_project_id

  disable_on_destroy = false
}

# IAM: Allow Cloud Run to use Vision AI
resource "google_project_iam_member" "vision_ai_user" {
  count   = var.enable_vision_ai ? 1 : 0
  project = var.gcp_project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.app.email}"

  depends_on = [google_project_service.vision_ai]
}
```

- [ ] **Step 2: Add Vision AI env var to Cloud Run**

In `google_cloud_run_service` env block, add:

```hcl
    env {
      name  = "ZILCH_VISION_AI_ENABLED"
      value = var.enable_vision_ai ? "true" : ""
    }
```

- [ ] **Step 3: Format and validate**

Run: `terraform fmt main.tf && terraform validate 2>&1 | head -5`

Expected: "Success!"

- [ ] **Step 4: Commit**

```bash
git add main.tf
git commit -m "feat: add Vision AI API and IAM to Phase 3"
```

---

### Task 7: Add Speech-to-Text Service to `main.tf`

**Files:**
- Modify: `main.tf` (after Vision AI section)

- [ ] **Step 1: Enable Speech-to-Text API and add IAM**

After the `google_project_iam_member vision_ai_user` block, insert:

```hcl
# Enable Speech-to-Text API
resource "google_project_service" "speech_to_text" {
  count   = var.enable_speech_to_text ? 1 : 0
  service = "speech.googleapis.com"
  project = var.gcp_project_id

  disable_on_destroy = false
}

# IAM: Allow Cloud Run to use Speech-to-Text
resource "google_project_iam_member" "speech_client" {
  count   = var.enable_speech_to_text ? 1 : 0
  project = var.gcp_project_id
  role    = "roles/speech.client"
  member  = "serviceAccount:${google_service_account.app.email}"

  depends_on = [google_project_service.speech_to_text]
}
```

- [ ] **Step 2: Add Speech-to-Text env var to Cloud Run**

In `google_cloud_run_service` env block, add:

```hcl
    env {
      name  = "ZILCH_SPEECH_TO_TEXT_ENABLED"
      value = var.enable_speech_to_text ? "true" : ""
    }
```

- [ ] **Step 3: Format and validate**

Run: `terraform fmt main.tf && terraform validate 2>&1 | head -5`

Expected: "Success!"

- [ ] **Step 4: Commit**

```bash
git add main.tf
git commit -m "feat: add Speech-to-Text API and IAM to Phase 3"
```

---

### Task 8: Add Translation Service to `main.tf`

**Files:**
- Modify: `main.tf` (after Speech-to-Text section)

- [ ] **Step 1: Enable Translation API and add IAM**

After the `google_project_iam_member speech_client` block, insert:

```hcl
# Enable Translation API
resource "google_project_service" "translate" {
  count   = var.enable_translation ? 1 : 0
  service = "translate.googleapis.com"
  project = var.gcp_project_id

  disable_on_destroy = false
}

# IAM: Allow Cloud Run to use Translation API
resource "google_project_iam_member" "translate_client" {
  count   = var.enable_translation ? 1 : 0
  project = var.gcp_project_id
  role    = "roles/cloudtranslate.agent"
  member  = "serviceAccount:${google_service_account.app.email}"

  depends_on = [google_project_service.translate]
}
```

- [ ] **Step 2: Add Translation env var to Cloud Run**

In `google_cloud_run_service` env block, add:

```hcl
    env {
      name  = "ZILCH_TRANSLATION_ENABLED"
      value = var.enable_translation ? "true" : ""
    }
```

- [ ] **Step 3: Format and validate**

Run: `terraform fmt main.tf && terraform validate 2>&1 | head -5`

Expected: "Success!"

- [ ] **Step 4: Commit**

```bash
git add main.tf
git commit -m "feat: add Translation API and IAM to Phase 3"
```

---

### Task 9: Add Phase 3 Outputs to `outputs.tf`

**Files:**
- Modify: `outputs.tf` (at end)

- [ ] **Step 1: Append all Phase 3 outputs**

```bash
cat >> outputs.tf << 'EOF'

output "pubsub_topic" {
  value       = var.enable_pubsub ? google_pubsub_topic.app_events[0].name : null
  description = "Pub/Sub topic name for event streaming (if enabled)"
}

output "pubsub_subscription" {
  value       = var.enable_pubsub ? google_pubsub_subscription.app_events_sub[0].name : null
  description = "Pub/Sub subscription name (if enabled)"
}

output "cloud_tasks_queue" {
  value       = var.enable_cloud_tasks ? google_cloud_tasks_queue.app_jobs[0].name : null
  description = "Cloud Tasks queue name for async jobs (if enabled)"
}

output "bigquery_dataset" {
  value       = var.enable_bigquery ? google_bigquery_dataset.app_analytics[0].dataset_id : null
  description = "BigQuery dataset ID for analytics (if enabled)"
}

output "kms_key_id" {
  value       = var.enable_cloud_kms ? google_kms_crypto_key.app_key[0].id : null
  description = "Cloud KMS crypto key ID for encryption (if enabled)"
}

output "vision_ai_enabled" {
  value       = var.enable_vision_ai ? "true" : "false"
  description = "Vision AI is enabled"
}

output "speech_to_text_enabled" {
  value       = var.enable_speech_to_text ? "true" : "false"
  description = "Speech-to-Text API is enabled"
}

output "translation_enabled" {
  value       = var.enable_translation ? "true" : "false"
  description = "Translation API is enabled"
}
EOF
```

- [ ] **Step 2: Verify outputs**

Run: `tail -40 outputs.tf | grep "output"` | wc -l`

Expected: "8" (the 8 new Phase 3 outputs)

- [ ] **Step 3: Commit**

```bash
git add outputs.tf
git commit -m "feat: add Phase 3 service outputs to outputs.tf"
```

---

### Task 10: Add Phase 3 Prompts to `deploy.sh`

**Files:**
- Modify: `deploy.sh` (feature toggle section)

- [ ] **Step 1: Locate feature toggle prompts**

Run: `grep -n "Enable Cloud Storage" deploy.sh`

Expected: Line number of the storage prompt

- [ ] **Step 1.1: Add Phase 3 config defaults at top**

Find the config initialization section (around line 32-42) and add these defaults after `ENABLE_CLOUD_BUILD="false"`:

```bash
ENABLE_PUBSUB="false"
ENABLE_CLOUD_TASKS="false"
ENABLE_BIGQUERY="false"
ENABLE_CLOUD_KMS="false"
ENABLE_VISION_AI="false"
ENABLE_SPEECH_TO_TEXT="false"
ENABLE_TRANSLATION="false"
```

- [ ] **Step 1.2: Add Phase 3 config mapping**

Find the config loading section (around line 44-60) and add these lines after the existing ENABLE_* mappings:

```bash
    [ -n "$enable_pubsub" ] && ENABLE_PUBSUB="$enable_pubsub"
    [ -n "$enable_cloud_tasks" ] && ENABLE_CLOUD_TASKS="$enable_cloud_tasks"
    [ -n "$enable_bigquery" ] && ENABLE_BIGQUERY="$enable_bigquery"
    [ -n "$enable_cloud_kms" ] && ENABLE_CLOUD_KMS="$enable_cloud_kms"
    [ -n "$enable_vision_ai" ] && ENABLE_VISION_AI="$enable_vision_ai"
    [ -n "$enable_speech_to_text" ] && ENABLE_SPEECH_TO_TEXT="$enable_speech_to_text"
    [ -n "$enable_translation" ] && ENABLE_TRANSLATION="$enable_translation"
```

- [ ] **Step 2: Add Phase 3 service prompts after existing toggles**

Find the line with `ENABLE_VERTEX_AI=$(prompt_toggle...)` (around line 177) and after it, add:

```bash

# Phase 3: Advanced Services
echo ""
ENABLE_PUBSUB=$(prompt_toggle "Pub/Sub Event Streaming" "$ENABLE_PUBSUB")
ENABLE_CLOUD_TASKS=$(prompt_toggle "Cloud Tasks Job Queues" "$ENABLE_CLOUD_TASKS")
ENABLE_BIGQUERY=$(prompt_toggle "BigQuery Analytics Engine" "$ENABLE_BIGQUERY")
ENABLE_CLOUD_KMS=$(prompt_toggle "Cloud KMS Encryption Keys" "$ENABLE_CLOUD_KMS")
ENABLE_VISION_AI=$(prompt_toggle "Vision AI Image Processing" "$ENABLE_VISION_AI")
ENABLE_SPEECH_TO_TEXT=$(prompt_toggle "Speech-to-Text Audio Transcription" "$ENABLE_SPEECH_TO_TEXT")
ENABLE_TRANSLATION=$(prompt_toggle "Translation API Multi-Language" "$ENABLE_TRANSLATION")
```

- [ ] **Step 3: Add Phase 3 variables to terraform apply command**

Find the `terraform apply -auto-approve` command (around line 280-300) and add these lines before the closing of the terraform apply command:

```bash
  -var="enable_pubsub=${ENABLE_PUBSUB}" \
  -var="enable_cloud_tasks=${ENABLE_CLOUD_TASKS}" \
  -var="enable_bigquery=${ENABLE_BIGQUERY}" \
  -var="enable_cloud_kms=${ENABLE_CLOUD_KMS}" \
  -var="enable_vision_ai=${ENABLE_VISION_AI}" \
  -var="enable_speech_to_text=${ENABLE_SPEECH_TO_TEXT}" \
  -var="enable_translation=${ENABLE_TRANSLATION}" \
```

Make sure these use the uppercase variable names (ENABLE_PUBSUB, etc.) that match the shell variables, and are added before the final line of the terraform apply command.

- [ ] **Step 4: Verify syntax**

Run: `bash -n deploy.sh && echo "✓ Syntax OK"`

Expected: "✓ Syntax OK"

- [ ] **Step 5: Commit**

```bash
git add deploy.sh
git commit -m "feat: add Phase 3 service prompts and variable exports to deploy.sh"
```

---

### Task 11: Update `tutorial.md` with Phase 3 Services

**Files:**
- Modify: `tutorial.md` (in service descriptions section)

- [ ] **Step 1: Find Phase 2 section in tutorial**

Run: `grep -n "Phase 2:" tutorial.md`

Expected: Line number of Phase 2 section

- [ ] **Step 2: Add Phase 3 service descriptions after Phase 2 section**

Before the "Troubleshooting" section, add:

```markdown

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

```

- [ ] **Step 3: Verify markdown syntax**

Run: `grep -c "###" tutorial.md`

Expected: At least 13 (7 Phase 3 services + existing sections)

- [ ] **Step 4: Commit**

```bash
git add tutorial.md
git commit -m "docs: add Phase 3 service descriptions and usage examples to tutorial"
```

---

### Task 12: Update `README.md` Service Table

**Files:**
- Modify: `README.md` (service table in "What Gets Provisioned" section)

- [ ] **Step 1: Locate service table**

Run: `grep -n "Optional Features" README.md`

Expected: Line number of table

- [ ] **Step 2: Add Phase 3 services to the table**

Find the table with services (around line 52) and add these rows after the existing Phase 1/2 services:

```markdown
| Pub/Sub | 10 GB/month | `enable_pubsub` |
| Cloud Tasks | 1M tasks/month | `enable_cloud_tasks` |
| BigQuery | 1 TB queried/month | `enable_bigquery` |
| Cloud KMS | 6 keys, 10K calls/month | `enable_cloud_kms` |
| Vision AI | 1,000 images/month | `enable_vision_ai` |
| Speech-to-Text | 60 minutes/month | `enable_speech_to_text` |
| Translation | 500K characters/month | `enable_translation` |
```

- [ ] **Step 3: Update file structure section**

Find the file structure listing and update the main.tf and variables.tf lines to mention Phase 3:

```markdown
├── main.tf                      # Phase 1 + Phase 2 + Phase 3 infrastructure
├── variables.tf                 # Includes all service toggle variables
```

- [ ] **Step 4: Update Phase 2 & 3 section at end of README**

Find the section "Phase 2 & 3 (Future)" and replace with:

```markdown
## Phase & 3 (Advanced Services)

**Phase 2:** Cloud Build + Artifact Registry (automatic container builds) — ✅ Complete

**Phase 3:** Pub/Sub, Cloud Tasks, BigQuery, Cloud KMS, Vision AI, Speech-to-Text, Translation APIs — In Progress

See `docs/superpowers/plans/` for implementation roadmap.
```

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "docs: update README service table and phase status for Phase 3"
```

---

### Task 13: Update `.zilch.config.example` with Phase 3 Services

**Files:**
- Modify: `.zilch.config.example`

- [ ] **Step 1: Read current .zilch.config.example**

Run: `cat .zilch.config.example`

Expected: See current Phase 1/2 configuration options

- [ ] **Step 2: Add Phase 3 service toggles**

Find the "Optional Features" section and add after the existing toggles:

```bash
# Phase 3: Advanced Services
# enable_pubsub=false
# enable_cloud_tasks=false
# enable_bigquery=false
# enable_cloud_kms=false
# enable_vision_ai=false
# enable_speech_to_text=false
# enable_translation=false
```

- [ ] **Step 3: Verify file**

Run: `grep -c "enable_" .zilch.config.example`

Expected: "14" (7 Phase 1/2 + 7 Phase 3)

- [ ] **Step 4: Commit**

```bash
git add .zilch.config.example
git commit -m "docs: add Phase 3 service options to .zilch.config.example"
```

---

### Task 14: Terraform Validation & Testing

**Files:**
- Test: Phase 3 Terraform configuration

- [ ] **Step 1: Validate all Terraform files**

Run: `terraform fmt -check main.tf variables.tf outputs.tf && echo "✓ Format OK"`

Expected: "✓ Format OK"

- [ ] **Step 2: Run Terraform validate**

Run: `terraform validate 2>&1 | head -20`

Expected: "Success!" or "Variables are not allowed in /path/to/config (which is fine—we'll pass them at runtime)"

- [ ] **Step 3: Count Phase 3 resources**

Run: `grep -c 'enable_pubsub\|enable_cloud_tasks\|enable_bigquery\|enable_cloud_kms\|enable_vision_ai\|enable_speech_to_text\|enable_translation' main.tf`

Expected: 50+ (multiple references per service: resource blocks, IAM, env vars, etc.)

- [ ] **Step 4: Verify deploy.sh syntax**

Run: `bash -n deploy.sh && echo "✓ Syntax OK"`

Expected: "✓ Syntax OK"

- [ ] **Step 5: Check Phase 3 prompts in deploy.sh**

Run: `grep -c 'prompt_toggle.*Event Streaming\|prompt_toggle.*Job Queues\|prompt_toggle.*Analytics' deploy.sh`

Expected: "3" (at least the first 3 Phase 3 services)

- [ ] **Step 6: Commit validation summary**

```bash
git add -A
git commit -m "test: validate Phase 3 Terraform configuration and deploy.sh syntax"
```

---

## Self-Review Checklist

**Spec Coverage:**
- ✅ Section "Phase 3 (Advanced)" from design spec → All 7 services in Tasks 2-8
- ✅ Service discovery via env vars → Each service task includes Cloud Run env var injection
- ✅ Always Free tier compliance → BigQuery (1TB/month), KMS (6 keys), Vision AI (1K images), etc. specified in outputs/docs
- ✅ Least-privilege IAM → Each service has specific IAM role (pubsub.editor, cloudtasks.enqueuer, etc.)
- ✅ Optional toggles → Task 1 adds 7 boolean variables (all default to false)
- ✅ deploy.sh integration → Task 10 adds interactive prompts and TF_VAR exports (with config file support)
- ✅ Config file templates → Task 13 updates .zilch.config.example with Phase 3 options
- ✅ Documentation → Task 11 (tutorial.md) and Task 12 (README.md) updates

**Placeholder Scan:**
- ✅ All resource blocks have concrete attributes (no TBD, no "add error handling")
- ✅ All IAM roles are specific (e.g., `roles/pubsub.editor`, not generic)
- ✅ All env var names follow pattern `ZILCH_<SERVICE>_<PROPERTY>`
- ✅ All Terraform blocks include `count = var.enable_<service> ? 1 : 0` (conditional)
- ✅ All steps show exact commands with expected output

**Type Consistency:**
- ✅ Variable names: `enable_pubsub`, `enable_cloud_tasks`, etc. (all lowercase, all follow pattern)
- ✅ Resource names: `google_pubsub_topic.app_events`, `google_cloud_tasks_queue.app_jobs`, etc. (consistent).
- ✅ Env var names: All start with `ZILCH_` prefix (consistent with Phase 1/2)
- ✅ Service account reference: All use `google_service_account.app.email` (consistent)
- ✅ IAM member syntax: All use `"serviceAccount:${google_service_account.app.email}"` (consistent)

**No Missing Requirements:**
- ✅ All 7 Phase 3 services included (Pub/Sub, Cloud Tasks, BigQuery, KMS, Vision AI, Speech-to-Text, Translation)
- ✅ Terraform + deploy.sh + docs for all services
- ✅ Always Free tier limits documented in Task 11/12
- ✅ Conditional resource creation (all use count) to avoid cost overruns
- ✅ API enablement for Vision AI, Speech-to-Text, Translation (Tasks 6-8)

---

**Plan complete and saved to `docs/superpowers/plans/2026-06-15-zilch-phase-3-plan.md`.**

Two execution options:

**1. Subagent-Driven (Recommended)** — I dispatch a fresh subagent per task, review code between tasks, fast iteration with oversight

**2. Inline Execution** — Execute all tasks sequentially in this session using executing-plans, with checkpoints for review

Which approach?
