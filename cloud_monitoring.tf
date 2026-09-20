# --- CLOUD MONITORING & BUDGET ALERTS ---

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

# Get the current billing account associated with the project
# Requires: gcloud beta billing accounts list to see available accounts
# For now, monitoring works but budget alerts require manual billing account setup
data "google_billing_account" "account" {
  count = 0 # Disabled: requires manual billing account ID configuration
  open  = true
}

# --- BUDGET ALERT WITH PUBSUB NOTIFICATION ---

# Create a Pub/Sub topic for budget alerts
resource "google_pubsub_topic" "budget_alerts" {
  count   = var.enable_monitoring ? 1 : 0
  name    = "${var.app_name}-budget-alerts"
  project = var.gcp_project_id

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
# Requires gcp_billing_account_id to be provided during deploy.sh setup
resource "google_billing_budget" "app_budget" {
  count           = var.enable_monitoring && var.billing_budget_limit_usd > 0 && var.gcp_billing_account_id != "" ? 1 : 0
  billing_account = var.gcp_billing_account_id
  display_name    = "${var.app_name} - Budget Alert (${var.billing_budget_limit_usd} USD/month)"

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
  count        = var.enable_monitoring ? 1 : 0
  display_name = "${var.app_name} Error Alerts"
  type         = "pubsub"
  enabled      = true
  project      = var.gcp_project_id

  labels = {
    topic = "projects/${var.gcp_project_id}/topics/${google_pubsub_topic.budget_alerts[0].name}"
  }
}

# Optional email channel, alongside the Pub/Sub one.
resource "google_monitoring_notification_channel" "app_email" {
  count        = var.enable_monitoring && var.alert_email != "" ? 1 : 0
  display_name = "${var.app_name} Alerts (email)"
  type         = "email"
  enabled      = true
  project      = var.gcp_project_id

  labels = {
    email_address = var.alert_email
  }
}

locals {
  alert_channels = var.enable_monitoring ? concat(
    [google_monitoring_notification_channel.app_alerts[0].id],
    google_monitoring_notification_channel.app_email[*].id,
  ) : []
}

# Alert Policy: server errors. Fires when the service returns more than 3 5xx
# responses in 5 minutes. (The resource keeps its old address, so an existing
# policy is updated in place; it used to alert on any high request count.)
resource "google_monitoring_alert_policy" "cloud_run_errors" {
  count        = var.enable_monitoring ? 1 : 0
  display_name = "${var.app_name} - 5xx responses"
  project      = var.gcp_project_id
  combiner     = "OR"

  conditions {
    display_name = "Cloud Run 5xx responses"

    condition_threshold {
      filter          = "resource.type=\"cloud_run_revision\" AND resource.label.service_name=\"${var.app_name}\" AND metric.type=\"run.googleapis.com/request_count\" AND metric.label.response_code_class=\"5xx\""
      duration        = "0s"
      comparison      = "COMPARISON_GT"
      threshold_value = 3

      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_DELTA"
        cross_series_reducer = "REDUCE_SUM"
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = local.alert_channels
}

# Uptime check on GET /health (public by design on the app) every 5 minutes.
resource "google_monitoring_uptime_check_config" "health" {
  count        = var.enable_monitoring ? 1 : 0
  display_name = "${var.app_name}-health"
  project      = var.gcp_project_id
  timeout      = "10s"
  period       = "300s"

  http_check {
    path         = "/health"
    port         = 443
    use_ssl      = true
    validate_ssl = true
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.gcp_project_id
      host       = trimprefix(google_cloud_run_v2_service.app.uri, "https://")
    }
  }
}

# Alert Policy: the uptime check has been failing for 5 minutes.
resource "google_monitoring_alert_policy" "health_check_failing" {
  count        = var.enable_monitoring ? 1 : 0
  display_name = "${var.app_name} - health check failing"
  project      = var.gcp_project_id
  combiner     = "OR"

  conditions {
    display_name = "Uptime check failing"

    condition_threshold {
      filter          = "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND metric.label.check_id=\"${google_monitoring_uptime_check_config.health[0].uptime_check_id}\" AND resource.type=\"uptime_url\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 1

      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_NEXT_OLDER"
        cross_series_reducer = "REDUCE_COUNT_FALSE"
        group_by_fields      = ["resource.*"]
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = local.alert_channels
}

# IAM: Allow Cloud Run service account to receive budget alerts
resource "google_pubsub_topic_iam_member" "budget_alerts_subscriber" {
  count  = var.enable_monitoring ? 1 : 0
  topic  = google_pubsub_topic.budget_alerts[0].name
  role   = "roles/pubsub.subscriber"
  member = "serviceAccount:${google_service_account.app.email}"
}
