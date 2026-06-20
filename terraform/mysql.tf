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

  metadata_startup_script = base64encode(file("${path.module}/scripts/mysql-startup.sh"))

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
