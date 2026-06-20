# Compute Engine e2-micro VM for MySQL
resource "google_compute_instance" "mysql" {
  count          = var.enable_mysql ? 1 : 0
  name           = local.mysql_vm_name
  machine_type   = local.mysql_machine_type
  zone           = local.mysql_zone
  project        = var.gcp_project_id
  can_ip_forward = false

  tags = [local.mysql_network_tag]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 10
      type  = "pd-standard"
    }
    auto_delete = true
  }

  attached_disk {
    source      = google_compute_disk.mysql_data[0].id
    device_name = "mysql-data"
  }

  network_interface {
    network    = "default"
    subnetwork = data.google_compute_subnetwork.default[0].id

    # No external IP (security)
    access_config {
      nat_ip = null
    }
  }

  metadata = {
    enable-oslogin = "true"
  }

  metadata_startup_script = base64encode(templatefile("${path.root}/scripts/mysql-startup.sh", {
    RESOURCE_SUFFIX = local.mysql_resource_suffix
    PROJECT_ID      = var.gcp_project_id
  }))

  service_account {
    email  = google_service_account.mysql[0].email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  depends_on = [
    google_compute_disk.mysql_data,
    google_service_account.mysql,
  ]

  labels = local.mysql_labels
}

# Persistent disk for MySQL data
resource "google_compute_disk" "mysql_data" {
  count                     = var.enable_mysql ? 1 : 0
  name                      = local.mysql_disk_name
  type                      = "pd-standard"
  zone                      = local.mysql_zone
  size                      = var.mysql_disk_size_gb
  project                   = var.gcp_project_id
  physical_block_size_bytes = 4096

  labels = local.mysql_labels
}

# Service account for MySQL VM
resource "google_service_account" "mysql" {
  count       = var.enable_mysql ? 1 : 0
  account_id  = "zilch-mysql-${local.mysql_resource_suffix}"
  project     = var.gcp_project_id
  description = "Service account for Zilch MySQL VM"
}

# Data source to get the default subnetwork
data "google_compute_subnetwork" "default" {
  count   = var.enable_mysql ? 1 : 0
  name    = "default"
  region  = var.gcp_region
  project = var.gcp_project_id
}

# Firewall rule: Allow Cloud Run to connect to MySQL
resource "google_compute_firewall" "mysql_from_cloud_run" {
  count     = var.enable_mysql ? 1 : 0
  name      = "allow-cloud-run-to-mysql-${local.mysql_resource_suffix}"
  network   = "default"
  project   = var.gcp_project_id
  direction = "INGRESS"
  priority  = 1000

  allow {
    protocol = "tcp"
    ports    = ["3306"]
  }

  # Allow from Cloud Run service account
  source_service_accounts = [google_service_account.app.email]
  target_service_accounts = [google_service_account.mysql[0].email]

  depends_on = [google_service_account.mysql]
}

# Firewall rule: Allow SSH for bastion access
resource "google_compute_firewall" "mysql_ssh" {
  count     = var.enable_mysql ? 1 : 0
  name      = "allow-ssh-to-mysql-${local.mysql_resource_suffix}"
  network   = "default"
  project   = var.gcp_project_id
  direction = "INGRESS"
  priority  = 1000

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # Allow SSH from anywhere (GCP Cloud Shell, local machines)
  source_ranges = ["0.0.0.0/0"]
  target_tags   = [local.mysql_network_tag]
}

# Secret for MySQL root password
resource "google_secret_manager_secret" "mysql_root_password" {
  count     = var.enable_mysql ? 1 : 0
  secret_id = "zilch-mysql-root-password-${local.mysql_resource_suffix}"
  project   = var.gcp_project_id

  replication {
    auto {}
  }

  labels = local.mysql_labels
}

resource "google_secret_manager_secret_version" "mysql_root_password" {
  count       = var.enable_mysql ? 1 : 0
  secret      = google_secret_manager_secret.mysql_root_password[0].id
  secret_data = random_password.mysql_root[0].result
}

# Secret for MySQL application user password
resource "google_secret_manager_secret" "mysql_app_password" {
  count     = var.enable_mysql ? 1 : 0
  secret_id = "zilch-mysql-app-password-${local.mysql_resource_suffix}"
  project   = var.gcp_project_id

  replication {
    auto {}
  }

  labels = local.mysql_labels
}

resource "google_secret_manager_secret_version" "mysql_app_password" {
  count       = var.enable_mysql ? 1 : 0
  secret      = google_secret_manager_secret.mysql_app_password[0].id
  secret_data = random_password.mysql_app_user[0].result
}

# IAM: Allow Cloud Run service account to read MySQL password
resource "google_secret_manager_secret_iam_member" "mysql_app_password_accessor" {
  count     = var.enable_mysql ? 1 : 0
  secret_id = google_secret_manager_secret.mysql_app_password[0].id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.app.email}"
}

# IAM: Allow MySQL VM service account to read root password
resource "google_secret_manager_secret_iam_member" "mysql_root_password_accessor" {
  count     = var.enable_mysql ? 1 : 0
  secret_id = google_secret_manager_secret.mysql_root_password[0].id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.mysql[0].email}"
}

# IAM: Allow Cloud Run service account to access MySQL VM
resource "google_compute_instance_iam_member" "cloud_run_mysql_access" {
  count         = var.enable_mysql ? 1 : 0
  instance_name = google_compute_instance.mysql[0].name
  zone          = google_compute_instance.mysql[0].zone
  role          = "roles/compute.osLogin"
  member        = "serviceAccount:${google_service_account.app.email}"
  project       = var.gcp_project_id
}
