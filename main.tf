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

resource "google_service_account" "app" {
  account_id   = var.app_name
  display_name = "System Identity execution account for ${var.app_name}"
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
      }
    }
  }
  depends_on = [google_project_service.run]
}

resource "google_cloud_run_service_iam_member" "public" {
  service  = google_cloud_run_service.app.name
  location = google_cloud_run_service.app.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# --- OPTIONAL ARCHITECTURAL COMPONENT LAYERS ---

# 1. Firestore System Configuration Block
resource "google_firestore_database" "default" {
  count       = var.enable_firestore ? 1 : 0
  project     = var.gcp_project_id
  name        = "(default)"
  location_id = var.gcp_region == "us-central1" ? "us-central" : var.gcp_region
  type        = "FIRESTORE_NATIVE"
}

resource "google_project_iam_member" "firestore" {
  count   = var.enable_firestore ? 1 : 0
  project = var.gcp_project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.app.email}"
}

# 2. Secret Manager System Configuration Block
resource "google_secret_manager_secret" "example" {
  count     = var.enable_secret_manager ? 1 : 0
  project   = var.gcp_project_id
  secret_id = "${var.app_name}-example-secret"
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
resource "google_firebase_project" "default" {
  count   = var.enable_firebase_auth ? 1 : 0
  project = var.gcp_project_id
}

resource "google_project_iam_member" "firebase" {
  count   = var.enable_firebase_auth ? 1 : 0
  project = var.gcp_project_id
  role    = "roles/firebase.admin"
  member  = "serviceAccount:${google_service_account.app.email}"
}

# 5. Vertex AI Engine System Integration
resource "google_project_service" "aiplatform" {
  count              = var.enable_vertex_ai ? 1 : 0
  service            = "aiplatform.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_iam_member" "vertex_ai" {
  count   = var.enable_vertex_ai ? 1 : 0
  project = var.gcp_project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.app.email}"
  depends_on = [google_project_service.aiplatform]
}
