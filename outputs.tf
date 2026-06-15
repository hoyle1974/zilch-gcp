output "cloud_run_url" {
  value       = google_cloud_run_service.app.status[0].url
  description = "The public web gateway address link assigned to the running app instance."
}

output "service_account_email" {
  value       = google_service_account.app.email
  description = "The locked service identity email context binding app processes."
}

output "storage_bucket" {
  value       = var.enable_cloud_storage ? "${var.app_name}-storage-${random_id.bucket_suffix.hex}" : null
  description = "The assigned storage destination identity label created."
}

output "gcp_project_id" {
  value       = var.gcp_project_id
  description = "GCP Project ID where resources were provisioned."
}

output "gcp_region" {
  value       = var.gcp_region
  description = "GCP Region where resources are running."
}

output "app_name" {
  value       = var.app_name
  description = "Application name used as resource prefix."
}

output "cloud_build_trigger_id" {
  value       = var.enable_cloud_build ? google_cloudbuild_trigger.app_build[0].id : null
  description = "Cloud Build trigger ID (for manual triggers)"
}

output "artifact_registry_repository" {
  value       = var.enable_cloud_build ? google_artifact_registry_repository.app_images[0].repository_id : null
  description = "Artifact Registry repository name"
}

output "cloud_build_service_account" {
  value       = var.enable_cloud_build ? google_service_account.cloud_build.email : null
  description = "Cloud Build service account (isolated, least-privilege)"
}
