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

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# --- CLOUD RUN CONTAINER BLUEPRINT ORCHESTRATION ---

resource "google_cloud_run_service" "app" {
  name     = var.app_name
  location = var.gcp_region

  template {
    spec {
      service_account_name = google_service_account.app.email
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
      }
    }
  }

  # Prevents Terraform from overwriting Cloud Build deployments
  lifecycle {
    ignore_changes = [
      template[0].spec[0].containers[0].image
    ]
  }

  depends_on = [google_project_service.run]
}

resource "google_cloud_run_service_iam_member" "public" {
  service  = google_cloud_run_service.app.name
  location = google_cloud_run_service.app.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# --- PHASE 2: ARTIFACT REGISTRY + CLOUD BUILD ---

# Artifact Registry for container images
resource "google_artifact_registry_repository" "app_images" {
  count         = var.enable_cloud_build ? 1 : 0
  location      = var.gcp_region
  repository_id = "${var.app_name}-images"
  format        = "DOCKER"
  description   = "Container images for ${var.app_name} (Phase 2 Cloud Build)"

  # Cleanup: Keep ONLY current image (rebuild from git if needed)
  cleanup_policies {
    id     = "delete-all-old"
    action = "DELETE"
    condition {
      tag_state  = "UNTAGGED"
      older_than = "0s" # Delete ALL old builds immediately
    }
  }

  cleanup_policies {
    id     = "delete-old-tags"
    action = "DELETE"
    condition {
      tag_state  = "TAGGED"
      older_than = "604800s" # Keep last 7 days only (7 * 24 * 60 * 60 = 604800 seconds)
    }
  }
}

# Cloud Build trigger: watches GitHub main branch
resource "google_cloudbuild_trigger" "app_build" {
  count = var.enable_cloud_build ? 1 : 0

  project     = var.gcp_project_id
  name        = "${var.app_name}-trigger"
  description = "Auto-build ${var.app_name} on push to main"

  # IMPORTANT: User must manually connect GitHub via GCP Console
  # (GitHub OAuth cannot be done headlessly via Terraform)
  github {
    owner = var.github_owner
    name  = var.github_repo
    push {
      branch = "^main$" # Only main branch triggers
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
      args = [
        "run", "deploy", var.app_name,
        "--image", "${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/${google_artifact_registry_repository.app_images[0].repository_id}/app:latest",
        "--region", var.gcp_region,
        "--service-account", google_service_account.app.email,
        "--platform", "managed",
        "--allow-unauthenticated"
      ]
      id       = "deploy-run"
      wait_for = ["push-image"]
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

# --- PHASE 3: ADVANCED SERVICES ---

# Pub/Sub Topic for event streaming
resource "google_pubsub_topic" "app_events" {
  count = var.enable_pubsub ? 1 : 0

  name                       = "${var.app_name}-events"
  message_retention_duration = "86400s" # 24 hours (free tier acceptable)
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

# --- OPTIONAL ARCHITECTURAL COMPONENT LAYERS ---

# 1. Firestore System Configuration Block
# Note: Firestore database creation requires specific IAM permissions beyond Editor role.
# The API will be enabled, but database creation may fail. User can manually create via:
# gcloud firestore databases create --region=us-central1
# For now, we just enable the API and provide IAM access.
# resource "google_firestore_database" "default" {
#   count       = var.enable_firestore ? 1 : 0
#   project     = var.gcp_project_id
#   name        = "(default)"
#   location_id = var.gcp_region == "us-central1" ? "us-central" : var.gcp_region
#   type        = "FIRESTORE_NATIVE"
#   depends_on  = [google_project_service.firestore]
# }

resource "google_project_iam_member" "firestore" {
  count   = var.enable_firestore ? 1 : 0
  project = var.gcp_project_id
  role    = "roles/datastore.user"
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

# Note: firebaseauth.googleapis.com may require additional org-level permissions
# If Firebase Auth fails to enable, manually enable it via:
# gcloud services enable firebaseauth.googleapis.com --project=PROJECT_ID

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
