terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

# --- CORE PLATFORM SYSTEM RESOURCES ---

resource "google_project_service" "run" {
  service            = "run.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "artifact_registry" {
  service            = "artifactregistry.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "firestore" {
  service            = "firestore.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "secretmanager" {
  service            = "secretmanager.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "cloudbuild" {
  count              = var.enable_cloud_build ? 1 : 0
  service            = "cloudbuild.googleapis.com"
  disable_on_destroy = false
}

resource "google_service_account" "app" {
  account_id   = var.app_name
  display_name = "System Identity execution account for ${var.app_name}"
}

# Dedicated service account for Cloud Build (minimal permissions)
resource "google_service_account" "cloud_build" {
  account_id   = "${var.app_name}-builder"
  display_name = "Cloud Build service account for ${var.app_name}"
  description  = "Isolated service account for secure CI/CD builds"
}

# Permission 1: Push images to Artifact Registry
resource "google_project_iam_member" "builder_artifact_registry" {
  count   = var.enable_cloud_build ? 1 : 0
  project = var.gcp_project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.cloud_build.email}"
}

# Permission 2: Deploy to Cloud Run
resource "google_project_iam_member" "builder_cloud_run" {
  count   = var.enable_cloud_build ? 1 : 0
  project = var.gcp_project_id
  role    = "roles/run.developer"
  member  = "serviceAccount:${google_service_account.cloud_build.email}"
}

# Permission 3: Use the app service account (for Cloud Run to pull secrets)
resource "google_project_iam_member" "builder_iam" {
  count   = var.enable_cloud_build ? 1 : 0
  project = var.gcp_project_id
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${google_service_account.cloud_build.email}"
}

# Permission 4: Write logs to Cloud Logging
resource "google_project_iam_member" "builder_logging" {
  count   = var.enable_cloud_build ? 1 : 0
  project = var.gcp_project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.cloud_build.email}"
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "random_id" "queue_suffix" {
  byte_length = 2
}

resource "random_id" "kms_suffix" {
  byte_length = 2
}

resource "random_id" "mysql_suffix" {
  count       = var.enable_mysql ? 1 : 0
  byte_length = 2
}

resource "random_password" "mysql_root" {
  count            = var.enable_mysql ? 1 : 0
  length           = var.mysql_root_password_length
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "random_password" "mysql_app_user" {
  count            = var.enable_mysql ? 1 : 0
  length           = var.mysql_root_password_length
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "random_integer" "mysql_port" {
  count = var.enable_mysql ? 1 : 0
  min   = 30000
  max   = 65535
}

# --- CLOUD RUN CONTAINER BLUEPRINT ORCHESTRATION ---

resource "google_cloud_run_v2_service" "app" {
  name     = var.app_name
  location = var.gcp_region

  template {
    service_account = google_service_account.app.email
    # Note: To enable startup CPU boost for faster health checks on lightweight apps:
    # gcloud run services update APP_NAME --region=REGION --cpu-boost

    containers {
      image = "gcr.io/cloudrun/hello:latest"

      env {
        name  = "ZILCH_PROJECT_ID"
        value = var.gcp_project_id
      }
      env {
        name  = "ZILCH_APP_NAME"
        value = var.app_name
      }
      env {
        name  = "ZILCH_FIRESTORE_DATABASE"
        value = var.enable_firestore ? "(default)" : ""
      }
      env {
        name  = "ZILCH_SECRET_PREFIX"
        value = var.enable_secret_manager ? "${var.app_name}-" : ""
      }
      env {
        name  = "ZILCH_STORAGE_BUCKET"
        value = var.enable_cloud_storage ? "${var.app_name}-storage-${random_id.bucket_suffix.hex}" : ""
      }
      env {
        name  = "ZILCH_VERTEX_AI_ENABLED"
        value = var.enable_vertex_ai ? "true" : ""
      }
      env {
        name  = "ZILCH_FIREBASE_ENABLED"
        value = var.enable_firebase_auth ? "true" : ""
      }
      env {
        name  = "ZILCH_PUBSUB_TOPIC"
        value = var.enable_pubsub ? google_pubsub_topic.app_events[0].name : ""
      }
      env {
        name  = "ZILCH_PUBSUB_SUBSCRIPTION"
        value = var.enable_pubsub ? google_pubsub_subscription.app_events_sub[0].name : ""
      }
      env {
        name  = "ZILCH_CLOUD_TASKS_QUEUE"
        value = var.enable_cloud_tasks ? "projects/${var.gcp_project_id}/locations/${var.gcp_region}/queues/${var.app_name}-jobs" : ""
      }
      env {
        name  = "ZILCH_BIGQUERY_DATASET"
        value = var.enable_bigquery ? google_bigquery_dataset.app_analytics[0].dataset_id : ""
      }
      env {
        name  = "ZILCH_KMS_KEY_ID"
        value = var.enable_cloud_kms ? google_kms_crypto_key.app_key[0].id : ""
      }
      env {
        name  = "ZILCH_VISION_AI_ENABLED"
        value = var.enable_vision_ai ? "true" : ""
      }
      env {
        name  = "ZILCH_SPEECH_TO_TEXT_ENABLED"
        value = var.enable_speech_to_text ? "true" : ""
      }
      env {
        name  = "ZILCH_TRANSLATION_ENABLED"
        value = var.enable_translation ? "true" : ""
      }
      env {
        name  = "ZILCH_MYSQL_HOST"
        value = var.enable_mysql ? google_compute_instance.mysql[0].network_interface[0].network_ip : ""
      }
      env {
        name  = "ZILCH_MYSQL_PORT"
        value = var.enable_mysql ? tostring(random_integer.mysql_port[0].result) : ""
      }
      env {
        name  = "ZILCH_MYSQL_DATABASE"
        value = var.enable_mysql ? var.mysql_database_name : ""
      }
      env {
        name  = "ZILCH_MYSQL_USER"
        value = var.enable_mysql ? var.mysql_user : ""
      }
      env {
        name  = "ZILCH_MYSQL_PASSWORD"
        value = var.enable_mysql ? "sm://${google_secret_manager_secret.mysql_app_password[0].id}" : ""
      }
      env {
        name  = "ZILCH_MYSQL_VM_NAME"
        value = var.enable_mysql ? google_compute_instance.mysql[0].name : ""
      }
      env {
        name  = "GCP_PROJECT_ID"
        value = var.gcp_project_id
      }
      env {
        name  = "GCP_REGION"
        value = var.gcp_region
      }
    }
  }

  # Prevents Terraform from overwriting deployments made by gcloud CLI or Cloud Build
  # Ignores image updates, annotations, and labels which are frequently changed externally
  lifecycle {
    ignore_changes = [
      template[0].containers[0].image,
      annotations,
      labels
    ]
  }

  depends_on = [
    google_project_service.run,
    google_compute_instance.mysql,
    google_secret_manager_secret_version.mysql_app_password,
  ]
}

resource "google_cloud_run_service_iam_member" "public" {
  count    = var.allow_unauthenticated_access ? 1 : 0
  service  = google_cloud_run_v2_service.app.name
  location = google_cloud_run_v2_service.app.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# --- ARTIFACT REGISTRY + CLOUD BUILD ---

# Cloud Build storage bucket for build logs (auto-created by GCP, but we manage lifecycle here)
resource "google_storage_bucket" "cloud_build_logs" {
  count         = var.enable_cloud_build ? 1 : 0
  project       = var.gcp_project_id
  name          = "${var.gcp_project_id}_cloudbuild"
  location      = var.gcp_region
  force_destroy = false

  # Cleanup: Delete old Cloud Build logs after 30 days (prevents unbounded storage costs)
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
}

# Artifact Registry for container images
resource "google_artifact_registry_repository" "app_images" {
  count         = var.enable_cloud_build ? 1 : 0
  location      = var.gcp_region
  repository_id = "${var.app_name}-images"
  format        = "DOCKER"
  description   = "Container images for ${var.app_name} (Cloud Build)"

  # Cleanup: Keep ONLY current image (rebuild from git if needed)
  cleanup_policies {
    id     = "delete-all-old"
    action = "DELETE"
    condition {
      tag_state  = "UNTAGGED"
      older_than = "86400s" # Delete images older than 1 day to prevent transient retrieval errors during rollouts
    }
  }

}

# Cloud Build trigger: watches GitHub main branch
resource "google_cloudbuild_trigger" "app_build" {
  count = var.enable_cloud_build ? 1 : 0

  project     = var.gcp_project_id
  name        = "${var.app_name}-trigger"
  description = "Auto-build ${var.app_name} on push to main"

  # 1st gen: GitHub block (proven working)
  github {
    owner = var.github_owner
    name  = var.github_repo
    push {
      branch = "^main$"
    }
  }

  # Inline build steps (NOT cloudbuild.yaml file)
  build {
    # Step 1: Build container with layer caching
    step {
      name = "gcr.io/cloud-builders/docker"
      args = [
        "build",
        "-t", "${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/${google_artifact_registry_repository.app_images[0].repository_id}/app:latest",
        "-t", "${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/${google_artifact_registry_repository.app_images[0].repository_id}/app:$BUILD_ID",
        "--cache-from", "${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/${google_artifact_registry_repository.app_images[0].repository_id}/app:latest",
        "."
      ]
      id = "build-image"
    }

    # Step 2: Push to Artifact Registry
    step {
      name = "gcr.io/cloud-builders/docker"
      args = [
        "push",
        "${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/${google_artifact_registry_repository.app_images[0].repository_id}/app"
      ]
      id       = "push-image"
      wait_for = ["build-image"]
    }

    # Step 3: Deploy to Cloud Run
    step {
      name       = "gcr.io/google.com/cloudsdktool/cloud-sdk"
      entrypoint = "gcloud"
      args = concat(
        [
          "run", "deploy", var.app_name,
          "--image", "${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/${google_artifact_registry_repository.app_images[0].repository_id}/app:latest",
          "--region", var.gcp_region,
          "--service-account", google_service_account.app.email,
          "--platform", "managed"
        ],
        var.allow_unauthenticated_access ? ["--allow-unauthenticated"] : ["--no-allow-unauthenticated"]
      )
      id       = "deploy-run"
      wait_for = ["push-image"]
    }

    # Logging configuration (required when using custom service account)
    options {
      logging = "CLOUD_LOGGING_ONLY"
    }
  }

  # Use isolated service account (NOT default)
  service_account = google_service_account.cloud_build.id

  depends_on = [
    google_artifact_registry_repository.app_images,
    google_service_account.cloud_build,
    google_project_iam_member.builder_artifact_registry,
    google_project_iam_member.builder_cloud_run,
    google_project_iam_member.builder_iam
  ]
}

# --- ADVANCED SERVICES (OPTIONAL) ---

# Enable Pub/Sub API
resource "google_project_service" "pubsub" {
  count   = var.enable_pubsub ? 1 : 0
  service = "pubsub.googleapis.com"
  project = var.gcp_project_id

  disable_on_destroy = false
}

# Pub/Sub Topic for event streaming
resource "google_pubsub_topic" "app_events" {
  count      = var.enable_pubsub ? 1 : 0
  depends_on = [google_project_service.pubsub[0]]

  name                       = "${var.app_name}-events"
  message_retention_duration = "86400s" # 24 hours (free tier acceptable)
  project                    = var.gcp_project_id

  labels = {
    app = var.app_name
  }
}

# Pub/Sub Subscription for consuming events
resource "google_pubsub_subscription" "app_events_sub" {
  count      = var.enable_pubsub ? 1 : 0
  depends_on = [google_project_service.pubsub[0]]

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

# Enable Cloud Tasks API
resource "google_project_service" "cloud_tasks" {
  count   = var.enable_cloud_tasks ? 1 : 0
  service = "cloudtasks.googleapis.com"
  project = var.gcp_project_id

  disable_on_destroy = false
}

# Cloud Tasks queue for async job processing
resource "google_cloud_tasks_queue" "app_jobs" {
  count = var.enable_cloud_tasks ? 1 : 0

  name     = "${var.app_name}-jobs-${random_id.queue_suffix.hex}"
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

  depends_on = [google_project_service.cloud_tasks[0]]
}

# IAM: Allow Cloud Run to dispatch tasks
resource "google_project_iam_member" "cloud_tasks_enqueuer" {
  count   = var.enable_cloud_tasks ? 1 : 0
  project = var.gcp_project_id
  role    = "roles/cloudtasks.enqueuer"
  member  = "serviceAccount:${google_service_account.app.email}"
}

# Enable BigQuery API
resource "google_project_service" "bigquery" {
  count   = var.enable_bigquery ? 1 : 0
  service = "bigquery.googleapis.com"
  project = var.gcp_project_id

  disable_on_destroy = false
}

# BigQuery dataset for analytics
resource "google_bigquery_dataset" "app_analytics" {
  count = var.enable_bigquery ? 1 : 0

  dataset_id                  = "${replace(var.app_name, "-", "_")}_analytics"
  friendly_name               = "${var.app_name} Analytics"
  description                 = "Analytics dataset for ${var.app_name}"
  location                    = var.gcp_region
  default_table_expiration_ms = 7776000000 # 90 days (free tier quota management)
  project                     = var.gcp_project_id

  labels = {
    app = var.app_name
  }

  depends_on = [google_project_service.bigquery[0]]
}

# IAM: Allow Cloud Run to write to BigQuery
resource "google_project_iam_member" "bigquery_data_editor" {
  count   = var.enable_bigquery ? 1 : 0
  project = var.gcp_project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.app.email}"
}

# IAM: Allow Cloud Run to run BigQuery jobs
resource "google_project_iam_member" "bigquery_job_user" {
  count   = var.enable_bigquery ? 1 : 0
  project = var.gcp_project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.app.email}"
}

# Enable Cloud KMS API
resource "google_project_service" "kms" {
  count   = var.enable_cloud_kms ? 1 : 0
  service = "cloudkms.googleapis.com"
  project = var.gcp_project_id

  disable_on_destroy = false
}

# Cloud KMS keyring for encryption
resource "google_kms_key_ring" "app_keys" {
  count    = var.enable_cloud_kms ? 1 : 0
  name     = "${var.app_name}-keyring-${random_id.kms_suffix.hex}"
  location = var.gcp_region
  project  = var.gcp_project_id

  depends_on = [google_project_service.kms[0]]
}

# Cloud KMS crypto key for encryption/decryption
resource "google_kms_crypto_key" "app_key" {
  count           = var.enable_cloud_kms ? 1 : 0
  name            = "${var.app_name}-key"
  key_ring        = google_kms_key_ring.app_keys[0].id
  rotation_period = "7776000s" # 90 days

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

# Enable Cloud Vision API
resource "google_project_service" "vision_api" {
  count   = var.enable_vision_ai ? 1 : 0
  service = "vision.googleapis.com"
  project = var.gcp_project_id

  disable_on_destroy = false
}

# IAM: Allow Cloud Run to use Vision AI
resource "google_project_iam_member" "vision_ai_user" {
  count      = var.enable_vision_ai ? 1 : 0
  project    = var.gcp_project_id
  role       = "roles/aiplatform.user"
  member     = "serviceAccount:${google_service_account.app.email}"
  depends_on = [google_project_service.vision_api]
}

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
  role    = "roles/cloudtranslate.user"
  member  = "serviceAccount:${google_service_account.app.email}"

  depends_on = [google_project_service.translate]
}

# --- OPTIONAL ARCHITECTURAL COMPONENT LAYERS ---

# 1. Firestore System Configuration Block
# Firestore Native mode provides ACID transactions and SQL-like queries.
# Now provisioned directly via Terraform with appropriate IAM setup.
resource "google_firestore_database" "default" {
  count   = var.enable_firestore ? 1 : 0
  project = var.gcp_project_id
  name    = "(default)"
  # Firestore multi-region locations: nam5 (North America), eur3 (Europe)
  # All three US regions (us-central1, us-east1, us-west1) map to nam5
  location_id = "nam5"
  type        = "FIRESTORE_NATIVE"
  depends_on  = [google_project_service.firestore]
}

resource "google_project_iam_member" "firestore" {
  count   = var.enable_firestore ? 1 : 0
  project = var.gcp_project_id
  role    = "roles/datastore.editor"
  member  = "serviceAccount:${google_service_account.app.email}"
}

# 2. Secret Manager System Configuration Block
resource "google_secret_manager_secret" "example" {
  count      = var.enable_secret_manager ? 1 : 0
  project    = var.gcp_project_id
  secret_id  = "${var.app_name}-example-secret"
  depends_on = [google_project_service.secretmanager]
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "example" {
  count       = var.enable_secret_manager ? 1 : 0
  secret      = google_secret_manager_secret.example[0].id
  secret_data = "placeholder-secret-value"

  lifecycle {
    ignore_changes = [secret_data]
  }
}

resource "google_project_iam_member" "secret_manager" {
  count   = var.enable_secret_manager ? 1 : 0
  project = var.gcp_project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.app.email}"
}

# 3. Cloud Storage System Configuration Block
resource "google_storage_bucket" "app" {
  count         = var.enable_cloud_storage ? 1 : 0
  project       = var.gcp_project_id
  name          = "${var.app_name}-storage-${random_id.bucket_suffix.hex}"
  location      = var.gcp_region
  force_destroy = true
}

resource "google_project_iam_member" "storage" {
  count   = var.enable_cloud_storage ? 1 : 0
  project = var.gcp_project_id
  role    = "roles/storage.objectUser"
  member  = "serviceAccount:${google_service_account.app.email}"
}

# 4. Firebase Authentication Provisioning Engine
# Enable Firebase APIs (Firebase project is created via console, not Terraform)
resource "google_project_service" "firebase" {
  count              = var.enable_firebase_auth ? 1 : 0
  service            = "firebase.googleapis.com"
  disable_on_destroy = false
}

# Enable Identity Toolkit API (required for complete Firebase Auth setup)
resource "google_project_service" "identity_toolkit" {
  count              = var.enable_firebase_auth ? 1 : 0
  service            = "identitytoolkit.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_iam_member" "firebase" {
  count      = var.enable_firebase_auth ? 1 : 0
  project    = var.gcp_project_id
  role       = "roles/firebase.viewer"
  member     = "serviceAccount:${google_service_account.app.email}"
  depends_on = [google_project_service.firebase]
}

# 5. Vertex AI Engine System Integration
resource "google_project_service" "aiplatform" {
  count              = var.enable_vertex_ai ? 1 : 0
  service            = "aiplatform.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_iam_member" "vertex_ai" {
  count      = var.enable_vertex_ai ? 1 : 0
  project    = var.gcp_project_id
  role       = "roles/aiplatform.user"
  member     = "serviceAccount:${google_service_account.app.email}"
  depends_on = [google_project_service.aiplatform]
}

# Cloud Logging: Allow Cloud Run to write logs
resource "google_project_iam_member" "logging_writer" {
  project = var.gcp_project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.app.email}"
}

# Cloud Monitoring: Allow Cloud Run to write metrics
resource "google_project_iam_member" "monitoring_writer" {
  project = var.gcp_project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.app.email}"
}
