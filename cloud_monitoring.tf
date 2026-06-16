# --- PHASE 4: CLOUD MONITORING & BUDGET ALERTS (Emergency Circuit Breaker) ---

# Enable Monitoring API
resource "google_project_service" "monitoring" {
  count   = var.enable_monitoring ? 1 : 0
  service = "monitoring.googleapis.com"
  project = var.gcp_project_id

  disable_on_destroy = false
}

# Enable Cloud Billing API (required for budget operations)
resource "google_project_service" "billing" {
  count   = var.enable_monitoring ? 1 : 0
  service = "cloudbilling.googleapis.com"
  project = var.gcp_project_id

  disable_on_destroy = false
}

# Get the current billing account (requires authenticated context)
# This is informational for the monitoring setup
data "google_billing_account" "account" {
  count            = var.enable_monitoring ? 1 : 0
  display_name     = var.billing_account_name
  open              = true
}

# --- BUDGET ALERT WITH PUBSUB NOTIFICATION ---

# Create a Pub/Sub topic for budget alerts
resource "google_pubsub_topic" "budget_alerts" {
  count     = var.enable_monitoring ? 1 : 0
  name      = "${var.app_name}-budget-alerts"
  project   = var.gcp_project_id

  labels = {
    app = var.app_name
  }
}

# Subscription for budget alerts (developers can subscribe to notifications)
resource "google_pubsub_subscription" "budget_alerts_sub" {
  count   = var.enable_monitoring ? 1 : 0
  name    = "${var.app_name}-budget-alerts-sub"
  topic   = google_pubsub_topic.budget_alerts[0].name
  project = var.gcp_project_id

  push_config {
    push_endpoint = "${google_cloud_run_v2_service.app.uri}/api/budget-alert"

    oidc_token {
      service_account_email = google_service_account.app.email
    }
  }
}

# Billing Budget: Alert at key thresholds (50%, 100%, 150%)
resource "google_billing_budget" "app_budget" {
  count            = var.enable_monitoring && var.billing_budget_limit_usd > 0 ? 1 : 0
  billing_account  = data.google_billing_account.account[0].id
  display_name     = "${var.app_name} - Budget Alert (${var.billing_budget_limit_usd} USD/month)"

  budget_filter {
    projects = ["projects/${data.google_client_config.current.project}"]
  }

  amount {
    specified_amount {
      currency_code = "USD"
      units         = floor(var.billing_budget_limit_usd)
      nanos         = floor((var.billing_budget_limit_usd - floor(var.billing_budget_limit_usd)) * 1000000000)
    }
  }

  threshold_rules {
    threshold_percent = 50.0
  }

  threshold_rules {
    threshold_percent = 100.0
  }

  threshold_rules {
    threshold_percent = 150.0
  }
}

# Get current GCP project for billing budget
data "google_client_config" "current" {}

# --- MONITORING: ALERT POLICY FOR ERROR RATE ---

# Notification channel (Email - configure manually via console or use alternative)
resource "google_monitoring_notification_channel" "app_alerts" {
  count           = var.enable_monitoring ? 1 : 0
  display_name    = "${var.app_name} Error Alerts"
  type            = "pubsub"
  enabled         = true
  project         = var.gcp_project_id

  labels = {
    channel_name = "budget-alerts"
  }

  user_labels = {
    severity = "critical"
  }
}

# Alert Policy: High error rate on Cloud Run (triggers circuit breaker)
resource "google_monitoring_alert_policy" "cloud_run_errors" {
  count       = var.enable_monitoring ? 1 : 0
  display_name = "${var.app_name} - High Error Rate Alert"
  project     = var.gcp_project_id
  combiner    = "OR"

  conditions {
    display_name = "Cloud Run Error Rate > 5%"

    condition_threshold {
      filter          = "metric.type=\"run.googleapis.com/request_count\" AND resource.type=\"cloud_run_revision\" AND resource.label.service_name=\"${var.app_name}\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0.05

      trigger {
        count = 1
      }
    }
  }

  notification_channels = var.enable_monitoring ? [google_monitoring_notification_channel.app_alerts[0].id] : []
}

# IAM: Allow Cloud Run service account to receive budget alerts
resource "google_pubsub_topic_iam_member" "budget_alerts_subscriber" {
  count   = var.enable_monitoring ? 1 : 0
  topic   = google_pubsub_topic.budget_alerts[0].name
  role    = "roles/pubsub.subscriber"
  member  = "serviceAccount:${google_service_account.app.email}"
}
