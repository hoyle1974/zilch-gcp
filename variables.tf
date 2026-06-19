variable "gcp_project_id" {
  type        = string
  description = "Target infrastructure destination Google Cloud Project ID"
  validation {
    condition     = can(regex("^[a-z0-9-]{6,30}$", var.gcp_project_id))
    error_message = "Project IDs must match 6-30 lowercase characters, numbers, and hyphens only."
  }
}

variable "gcp_region" {
  type        = string
  default     = "us-central1"
  description = "Target runtime region zone restricted to core active free tiers"
  validation {
    condition     = contains(["us-central1", "us-east1", "us-west1"], var.gcp_region)
    error_message = "Zilch deployment zone must fall inside us-central1, us-east1, or us-west1 to maintain Always Free tier rules."
  }
}

variable "app_name" {
  type        = string
  description = "Service container namespace identifier prefix used for resources"
  validation {
    condition     = can(regex("^[a-z0-9-]{3,30}$", var.app_name))
    error_message = "Application display prefix naming structure must use 3-30 lowercase characters or hyphens."
  }
}

variable "enable_firestore" {
  type        = bool
  default     = false
  description = "Enable Firestore NoSQL Database (requires Firestore Admin IAM role; free tier: 1GB storage, 50K reads/day)"
}

variable "enable_secret_manager" {
  type        = bool
  default     = false
  description = "Enable Secret Manager for secure credential storage"
}

variable "enable_vertex_ai" {
  type        = bool
  default     = false
  description = "Enable Vertex AI (includes Gemini API access, free: 60 req/min)"
}

variable "enable_cloud_storage" {
  type        = bool
  default     = false
  description = "Enable Cloud Storage bucket for file uploads/downloads (free tier: 5GB)"
}

variable "enable_firebase_auth" {
  type        = bool
  default     = false
  description = "Enable Firebase Authentication for social login"
}

variable "github_owner" {
  type        = string
  default     = ""
  description = "GitHub repository owner (username or organization)"
}

variable "github_repo" {
  type        = string
  default     = ""
  description = "GitHub repository name (without owner)"
}

variable "enable_cloud_build" {
  type        = bool
  default     = true
  description = "Enable Cloud Build CI/CD (recommended but optional)"
}

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

# --- CLOUD SCHEDULER & MONITORING ---

variable "enable_scheduler" {
  type        = bool
  default     = false
  description = "Enable Cloud Scheduler for serverless cron jobs (3 free jobs/month)"
}

variable "scheduler_schedule" {
  type        = string
  default     = "0 0 * * *"
  description = "Cloud Scheduler cron expression (e.g., '0 0 * * *' for daily at midnight UTC)"
}

variable "scheduler_timezone" {
  type        = string
  default     = "UTC"
  description = "Timezone for Cloud Scheduler cron execution"
}

variable "scheduler_endpoint" {
  type        = string
  default     = "/api/cron"
  description = "Cloud Run endpoint path that Cloud Scheduler will POST to"
}

variable "enable_monitoring" {
  type        = bool
  default     = false
  description = "Enable Cloud Monitoring with budget alerts (requires `gcloud auth application-default set-quota-project <project-id>` for billing API access)"
}

variable "billing_account_name" {
  type        = string
  default     = "My Billing Account"
  description = "Display name of the GCP billing account to monitor"
}

variable "billing_budget_limit_usd" {
  type        = number
  default     = 10
  description = "Monthly billing budget threshold in USD for alert triggers"
}

variable "allow_unauthenticated_access" {
  type        = bool
  default     = true
  description = "Allow unauthenticated access to Cloud Run service (set to false for internal-only services like background workers or APIs)"
}

variable "gcp_billing_account_id" {
  type        = string
  default     = ""
  description = "GCP Billing Account ID (from: gcloud beta billing accounts list). Required to enable budget alerts. Leave empty to disable."
}
