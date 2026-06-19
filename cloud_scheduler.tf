# --- CLOUD SCHEDULER ---

# Enable Cloud Scheduler API
resource "google_project_service" "scheduler" {
  count   = var.enable_scheduler ? 1 : 0
  service = "cloudscheduler.googleapis.com"
  project = var.gcp_project_id

  disable_on_destroy = false
}

# Cloud Scheduler job template (customize schedule and endpoint as needed)
# Example: Daily job at midnight UTC
resource "google_cloud_scheduler_job" "app_cron" {
  count       = var.enable_scheduler ? 1 : 0
  name        = "${var.app_name}-cron"
  description = "Scheduled cron job for ${var.app_name}"
  schedule    = var.scheduler_schedule # e.g., "0 0 * * *" for daily at midnight
  time_zone   = var.scheduler_timezone # e.g., "UTC"
  region      = var.gcp_region
  project     = var.gcp_project_id

  http_target {
    http_method = "POST"
    uri         = "${endswith(google_cloud_run_v2_service.app.uri, "/") ? substr(google_cloud_run_v2_service.app.uri, 0, length(google_cloud_run_v2_service.app.uri) - 1) : google_cloud_run_v2_service.app.uri}${var.scheduler_endpoint}"
    headers = {
      "Content-Type" = "application/json"
    }

    oidc_token {
      service_account_email = google_service_account.app.email
      audience              = google_cloud_run_v2_service.app.uri
    }
  }

  depends_on = [
    google_project_service.scheduler,
    google_cloud_run_v2_service.app
  ]
}

# (Optional) Additional scheduler job for custom use cases
# Uncomment and customize as needed:
# resource "google_cloud_scheduler_job" "app_cleanup" {
#   count       = var.enable_scheduler ? 1 : 0
#   name        = "${var.app_name}-cleanup"
#   description = "Weekly cleanup job for ${var.app_name}"
#   schedule    = "0 2 * * 0"  # Weekly at 2 AM UTC on Sunday
#   time_zone   = "UTC"
#   region      = var.gcp_region
#   project     = var.gcp_project_id
#
#   http_target {
#     http_method = "POST"
#     uri         = "${google_cloud_run_v2_service.app.uri}/api/cleanup"
#     headers = {
#       "Content-Type" = "application/json"
#     }
#
#     oidc_token {
#       service_account_email = google_service_account.app.email
#       audience              = google_cloud_run_v2_service.app.uri
#     }
#   }
# }

# IAM: Allow Cloud Scheduler to invoke Cloud Run
resource "google_cloud_run_service_iam_member" "scheduler_invoker" {
  count    = var.enable_scheduler ? 1 : 0
  service  = google_cloud_run_v2_service.app.name
  location = google_cloud_run_v2_service.app.location
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.app.email}"
}
