# MySQL Service Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement Compute Engine e2-micro + MySQL as a new Zilch service, enabling users to deploy transactional relational SQL applications for ~$1.26/month.

**Architecture:** Terraform provisions e2-micro VM with MySQL in Docker, persistent disk for data. Cloud Run connects via Cloud SQL Proxy sidecar (encrypted tunnel, IAM-authenticated). Deployment flow adds optional MySQL prompt to `deploy.sh`. Users manage schemas via version-controlled migration scripts.

**Tech Stack:** Terraform, GCP Compute Engine, MySQL 8.0, Cloud SQL Proxy, Cloud Secret Manager, bash scripting

---

## Phase 1: Terraform Infrastructure (Tasks 1-7)

These tasks build the Terraform layer for provisioning e2-micro + MySQL infrastructure.

### Task 1: Create MySQL Terraform Variables

**Files:**
- Create: `terraform/mysql-variables.tf`

- [ ] **Step 1: Create the variables file**

Create `terraform/mysql-variables.tf`:

```hcl
variable "enable_mysql" {
  type        = bool
  description = "Enable managed MySQL database service"
  default     = false
}

variable "mysql_database_name" {
  type        = string
  description = "Name of the initial MySQL database to create"
  default     = "zilch_app"
  
  validation {
    condition     = can(regex("^[a-z0-9_]+$", var.mysql_database_name))
    error_message = "Database name must contain only lowercase letters, numbers, and underscores."
  }
}

variable "mysql_user" {
  type        = string
  description = "MySQL user for application access"
  default     = "zilch_user"
}

variable "mysql_root_password_length" {
  type        = number
  description = "Length of generated root password"
  default     = 32
}

variable "gcp_mysql_region" {
  type        = string
  description = "GCP region for e2-micro VM (must be Always Free region)"
  default     = "us-central1"
  
  validation {
    condition     = contains(["us-central1", "us-east1", "us-west1"], var.gcp_mysql_region)
    error_message = "MySQL VM must be in an Always Free region: us-central1, us-east1, or us-west1."
  }
}

variable "gcp_mysql_zone" {
  type        = string
  description = "GCP zone for e2-micro VM"
  default     = "us-central1-a"
}

variable "mysql_disk_size_gb" {
  type        = number
  description = "Size of persistent disk for MySQL data (GB)"
  default     = 30
  
  validation {
    condition     = var.mysql_disk_size_gb >= 10 && var.mysql_disk_size_gb <= 1000
    error_message = "Disk size must be between 10 GB and 1000 GB."
  }
}

variable "mysql_machine_type" {
  type        = string
  description = "GCP machine type for MySQL VM (e2-micro for Always Free)"
  default     = "e2-micro"
  
  validation {
    condition     = var.mysql_machine_type == "e2-micro"
    error_message = "Only e2-micro is supported for Always Free tier. For larger workloads, use Cloud SQL."
  }
}
```

- [ ] **Step 2: Verify the file is syntactically valid**

Run: `terraform fmt terraform/mysql-variables.tf`

Expected: File is reformatted (or "no changes" if already formatted)

- [ ] **Step 3: Commit**

```bash
git add terraform/mysql-variables.tf
git commit -m "feat: add MySQL Terraform variables with validation"
```

---

### Task 2: Create MySQL Terraform Locals and Data

**Files:**
- Create: `terraform/mysql-locals.tf`

- [ ] **Step 1: Create locals file**

Create `terraform/mysql-locals.tf`:

```hcl
locals {
  mysql_enabled = var.enable_mysql

  # Generate unique suffix for resources to avoid naming conflicts
  mysql_resource_suffix = random_id.mysql_suffix[0].hex

  # Construct VM name
  mysql_vm_name = mysql_enabled ? "zilch-mysql-vm-${local.mysql_resource_suffix}" : ""

  # Construct disk name
  mysql_disk_name = mysql_enabled ? "zilch-mysql-disk-${local.mysql_resource_suffix}" : ""

  # MySQL container image
  mysql_container_image = "mysql:8.0-debian"

  # Network tag for firewall rules
  mysql_network_tag = mysql_enabled ? "zilch-mysql" : ""

  # Labels for resource tracking
  mysql_labels = {
    service    = "mysql"
    managed_by = "zilch"
    created_at = timestamp()
  }
}
```

- [ ] **Step 2: Verify file is valid**

Run: `terraform fmt terraform/mysql-locals.tf`

Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add terraform/mysql-locals.tf
git commit -m "feat: add MySQL local variables and computed values"
```

---

### Task 3: Create Random ID Generator for MySQL Resources

**Files:**
- Modify: `terraform/main.tf` (add random_id resource)

- [ ] **Step 1: Add random_id resource to main.tf**

Open `terraform/main.tf` and add this resource block after the existing `random_id` resources (around line 95):

```hcl
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
```

- [ ] **Step 2: Verify Terraform plan works**

Run: `terraform plan -out=/tmp/plan.tfplan 2>&1 | head -50`

Expected: Plan succeeds (no errors), shows new resources for random IDs

- [ ] **Step 3: Commit**

```bash
git add terraform/main.tf
git commit -m "feat: add random password generators for MySQL"
```

---

### Task 4: Create Compute Engine e2-micro VM Resource

**Files:**
- Create: `terraform/mysql.tf`

- [ ] **Step 1: Create MySQL Terraform file with VM resource**

Create `terraform/mysql.tf`:

```hcl
# Compute Engine e2-micro VM for MySQL
resource "google_compute_instance" "mysql" {
  count           = var.enable_mysql ? 1 : 0
  name            = local.mysql_vm_name
  machine_type    = var.mysql_machine_type
  zone            = var.gcp_mysql_zone
  project         = var.gcp_project_id
  can_ip_forward  = false
  
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
  count             = var.enable_mysql ? 1 : 0
  name              = local.mysql_disk_name
  type              = "pd-standard"
  zone              = var.gcp_mysql_zone
  size              = var.mysql_disk_size_gb
  project           = var.gcp_project_id
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
  region  = var.gcp_mysql_region
  project = var.gcp_project_id
}
```

- [ ] **Step 2: Verify Terraform syntax**

Run: `terraform validate`

Expected: Success - "The configuration is valid"

- [ ] **Step 3: Check plan for VM resource**

Run: `terraform plan -target='google_compute_instance.mysql' 2>&1 | grep -A 5 'name.*mysql_vm'`

Expected: Shows VM will be created with correct name pattern

- [ ] **Step 4: Commit**

```bash
git add terraform/mysql.tf
git commit -m "feat: add e2-micro VM and persistent disk for MySQL"
```

---

### Task 5: Create Firewall Rules for MySQL

**Files:**
- Modify: `terraform/mysql.tf` (add firewall resources)

- [ ] **Step 1: Add firewall rules to mysql.tf**

Append to `terraform/mysql.tf`:

```hcl
# Firewall rule: Allow Cloud Run to connect to MySQL
resource "google_compute_firewall" "mysql_from_cloud_run" {
  count       = var.enable_mysql ? 1 : 0
  name        = "allow-cloud-run-to-mysql-${local.mysql_resource_suffix}"
  network     = "default"
  project     = var.gcp_project_id
  direction   = "INGRESS"
  priority    = 1000

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
  count       = var.enable_mysql ? 1 : 0
  name        = "allow-ssh-to-mysql-${local.mysql_resource_suffix}"
  network     = "default"
  project     = var.gcp_project_id
  direction   = "INGRESS"
  priority    = 1000

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # Allow SSH from anywhere (GCP Cloud Shell, local machines)
  source_ranges = ["0.0.0.0/0"]
  target_tags   = [local.mysql_network_tag]
}
```

- [ ] **Step 2: Verify firewall rules in plan**

Run: `terraform plan 2>&1 | grep -A 3 'allow-cloud-run-to-mysql'`

Expected: Shows firewall rule will be created

- [ ] **Step 3: Commit**

```bash
git add terraform/mysql.tf
git commit -m "feat: add firewall rules for MySQL access from Cloud Run and SSH"
```

---

### Task 6: Create Secret Manager Integration for MySQL Password

**Files:**
- Modify: `terraform/mysql.tf` (add Secret Manager resources)

- [ ] **Step 1: Add Secret Manager resources to mysql.tf**

Append to `terraform/mysql.tf`:

```hcl
# Secret for MySQL root password
resource "google_secret_manager_secret" "mysql_root_password" {
  count     = var.enable_mysql ? 1 : 0
  secret_id = "zilch-mysql-root-password-${local.mysql_resource_suffix}"
  project   = var.gcp_project_id

  replication {
    automatic = true
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
    automatic = true
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
```

- [ ] **Step 2: Verify secrets in plan**

Run: `terraform plan 2>&1 | grep 'google_secret_manager' | head -5`

Expected: Shows 4 Secret Manager resources (2 secrets, 2 versions)

- [ ] **Step 3: Commit**

```bash
git add terraform/mysql.tf
git commit -m "feat: add Secret Manager for MySQL passwords with IAM access"
```

---

### Task 7: Create MySQL Terraform Outputs

**Files:**
- Create: `terraform/mysql-outputs.tf`

- [ ] **Step 1: Create outputs file**

Create `terraform/mysql-outputs.tf`:

```hcl
output "mysql_vm_name" {
  value       = try(google_compute_instance.mysql[0].name, null)
  description = "Name of the MySQL Compute Engine VM"
}

output "mysql_vm_internal_ip" {
  value       = try(google_compute_instance.mysql[0].network_interface[0].network_ip, null)
  description = "Internal IP address of the MySQL VM"
}

output "mysql_vm_zone" {
  value       = try(google_compute_instance.mysql[0].zone, null)
  description = "Zone where MySQL VM is deployed"
}

output "mysql_database_name" {
  value       = var.enable_mysql ? var.mysql_database_name : null
  description = "Name of the initial MySQL database created"
}

output "mysql_user" {
  value       = var.enable_mysql ? var.mysql_user : null
  description = "MySQL user for application access"
  sensitive   = true
}

output "mysql_root_password_secret" {
  value       = try(google_secret_manager_secret.mysql_root_password[0].id, null)
  description = "Secret Manager secret ID for MySQL root password"
  sensitive   = true
}

output "mysql_app_password_secret" {
  value       = try(google_secret_manager_secret.mysql_app_password[0].id, null)
  description = "Secret Manager secret ID for application user password"
  sensitive   = true
}

output "mysql_disk_name" {
  value       = try(google_compute_disk.mysql_data[0].name, null)
  description = "Name of the persistent disk for MySQL data"
}

output "mysql_disk_size_gb" {
  value       = try(google_compute_disk.mysql_data[0].size, null)
  description = "Size of the persistent disk in GB"
}

output "mysql_enabled" {
  value       = var.enable_mysql
  description = "Whether MySQL service is enabled"
}

# Environment variables for Cloud Run
output "zilch_mysql_host" {
  value       = try(google_compute_instance.mysql[0].network_interface[0].network_ip, "")
  description = "Environment variable: ZILCH_MYSQL_HOST"
}

output "zilch_mysql_port" {
  value       = var.enable_mysql ? "3306" : ""
  description = "Environment variable: ZILCH_MYSQL_PORT"
}

output "zilch_mysql_database" {
  value       = var.enable_mysql ? var.mysql_database_name : ""
  description = "Environment variable: ZILCH_MYSQL_DATABASE"
}

output "zilch_mysql_user" {
  value       = var.enable_mysql ? var.mysql_user : ""
  description = "Environment variable: ZILCH_MYSQL_USER"
  sensitive   = true
}

output "zilch_mysql_password" {
  value       = try(google_secret_manager_secret.mysql_app_password[0].id, "")
  description = "Environment variable: ZILCH_MYSQL_PASSWORD (Secret Manager secret ID)"
  sensitive   = true
}
```

- [ ] **Step 2: Verify outputs are defined**

Run: `terraform output 2>&1 | head -10`

Expected: Shows output definitions (or warning if no apply yet, which is fine)

- [ ] **Step 3: Commit**

```bash
git add terraform/mysql-outputs.tf
git commit -m "feat: add MySQL Terraform outputs for environment variables"
```

---

## Phase 2: Startup Script & Database Initialization (Tasks 8-9)

### Task 8: Create MySQL Startup Script

**Files:**
- Create: `terraform/scripts/mysql-startup.sh`

- [ ] **Step 1: Create scripts directory and startup script**

```bash
mkdir -p terraform/scripts
```

Create `terraform/scripts/mysql-startup.sh`:

```bash
#!/bin/bash
set -euo pipefail

# Zilch MySQL Startup Script
# Runs on e2-micro VM boot to initialize MySQL in Docker

MYSQL_DATA_DIR="/data"
MYSQL_USER="root"
MYSQL_ROOT_PASSWORD=$(gcloud secrets versions access latest --secret="zilch-mysql-root-password-${RESOURCE_SUFFIX}")
MYSQL_APP_USER="zilch_user"
MYSQL_APP_PASSWORD=$(gcloud secrets versions access latest --secret="zilch-mysql-app-password-${RESOURCE_SUFFIX}")
MYSQL_DATABASE="zilch_app"

# Log function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a /var/log/zilch-mysql-startup.log
}

log "Starting Zilch MySQL initialization..."

# Update system packages
log "Updating system packages..."
apt-get update -qq
apt-get install -qq -y docker.io google-cloud-cli > /dev/null 2>&1

# Start Docker daemon
log "Starting Docker daemon..."
systemctl start docker
systemctl enable docker

# Wait for Docker to be ready
log "Waiting for Docker to be ready..."
for i in {1..30}; do
    if docker info > /dev/null 2>&1; then
        log "Docker is ready"
        break
    fi
    sleep 1
done

# Create data directory and mount persistent disk
log "Preparing persistent disk..."
if [ ! -d "$MYSQL_DATA_DIR" ]; then
    mkdir -p "$MYSQL_DATA_DIR"
fi

# Format and mount persistent disk (if not already mounted)
if ! mountpoint -q "$MYSQL_DATA_DIR"; then
    DISK_DEVICE=$(lsblk -np -o NAME,SERIAL | grep mysql-data | awk '{print $1}')
    if [ -z "$DISK_DEVICE" ]; then
        log "Warning: Could not find persistent disk, using local storage"
    else
        log "Formatting persistent disk: $DISK_DEVICE"
        mkfs.ext4 -F "$DISK_DEVICE" > /dev/null 2>&1 || true
        
        log "Mounting persistent disk to $MYSQL_DATA_DIR"
        mount "$DISK_DEVICE" "$MYSQL_DATA_DIR" || log "Warning: Failed to mount disk"
    fi
fi

chmod 755 "$MYSQL_DATA_DIR"

# Create MySQL data directory
log "Creating MySQL data directory..."
mkdir -p "$MYSQL_DATA_DIR/mysql"
chmod 700 "$MYSQL_DATA_DIR/mysql"

# Check if MySQL is already running
if docker ps -a --format "{{.Names}}" | grep -q "mysql-server"; then
    log "MySQL container already exists, starting it..."
    docker start mysql-server || true
else
    log "Starting MySQL container..."
    docker run \
        --name mysql-server \
        --restart=always \
        -d \
        -e MYSQL_ROOT_PASSWORD="$MYSQL_ROOT_PASSWORD" \
        -e MYSQL_DATABASE="$MYSQL_DATABASE" \
        -e MYSQL_USER="$MYSQL_APP_USER" \
        -e MYSQL_PASSWORD="$MYSQL_APP_PASSWORD" \
        -p 3306:3306 \
        -v "$MYSQL_DATA_DIR/mysql":/var/lib/mysql \
        mysql:8.0 \
        --default-authentication-plugin=mysql_native_password \
        --max_connections=200 \
        --character-set-server=utf8mb4 \
        --collation-server=utf8mb4_unicode_ci
fi

# Wait for MySQL to be ready
log "Waiting for MySQL to be ready..."
for i in {1..60}; do
    if docker exec mysql-server mysql -u"$MYSQL_USER" -p"$MYSQL_ROOT_PASSWORD" -e "SELECT 1" > /dev/null 2>&1; then
        log "MySQL is ready"
        break
    fi
    log "Attempt $i/60: MySQL not ready yet, waiting..."
    sleep 1
done

# Verify database and user are created
log "Verifying database and user..."
docker exec mysql-server mysql -u"$MYSQL_USER" -p"$MYSQL_ROOT_PASSWORD" -e "SHOW DATABASES LIKE '$MYSQL_DATABASE';"
docker exec mysql-server mysql -u"$MYSQL_USER" -p"$MYSQL_ROOT_PASSWORD" -e "SELECT User FROM mysql.user WHERE User='$MYSQL_APP_USER';"

log "MySQL initialization complete"
```

- [ ] **Step 2: Make script executable**

```bash
chmod +x terraform/scripts/mysql-startup.sh
```

- [ ] **Step 3: Verify script is valid shell**

Run: `bash -n terraform/scripts/mysql-startup.sh`

Expected: No output (syntax is valid)

- [ ] **Step 4: Commit**

```bash
git add terraform/scripts/mysql-startup.sh
git commit -m "feat: add MySQL Docker container startup script"
```

---

### Task 9: Fix Startup Script Reference in Terraform

**Files:**
- Modify: `terraform/mysql.tf` (update metadata_startup_script)

- [ ] **Step 1: Update VM metadata to use actual startup script**

This is a temporary placeholder fix. The startup script has environment variables that need to be templated. Update the VM resource in `terraform/mysql.tf`:

Replace this line:
```hcl
metadata_startup_script = base64encode(file("${path.module}/scripts/mysql-startup.sh"))
```

With:
```hcl
metadata_startup_script = base64encode(templatefile("${path.module}/scripts/mysql-startup.sh", {
  RESOURCE_SUFFIX = local.mysql_resource_suffix
  PROJECT_ID      = var.gcp_project_id
}))
```

- [ ] **Step 2: Update the startup script to use template variables**

Update `terraform/scripts/mysql-startup.sh` line that gets secrets to use Terraform variables:

Replace:
```bash
MYSQL_ROOT_PASSWORD=$(gcloud secrets versions access latest --secret="zilch-mysql-root-password-${RESOURCE_SUFFIX}")
MYSQL_APP_PASSWORD=$(gcloud secrets versions access latest --secret="zilch-mysql-app-password-${RESOURCE_SUFFIX}")
```

With:
```bash
MYSQL_ROOT_PASSWORD=$(gcloud secrets versions access latest --secret="zilch-mysql-root-password-${RESOURCE_SUFFIX}" --project="${PROJECT_ID}")
MYSQL_APP_PASSWORD=$(gcloud secrets versions access latest --secret="zilch-mysql-app-password-${RESOURCE_SUFFIX}" --project="${PROJECT_ID}")
```

- [ ] **Step 3: Verify template syntax**

Run: `terraform validate`

Expected: "The configuration is valid"

- [ ] **Step 4: Commit**

```bash
git add terraform/mysql.tf terraform/scripts/mysql-startup.sh
git commit -m "feat: template startup script with Terraform variables for secret access"
```

---

## Phase 3: Cloud Run Integration (Tasks 10-12)

### Task 10: Create Cloud SQL Proxy Docker Image

**Files:**
- Modify: `Dockerfile`

- [ ] **Step 1: Read current Dockerfile**

Run: `head -20 Dockerfile`

Expected: Shows base image and initial setup

- [ ] **Step 2: Add Cloud SQL Proxy layer to Dockerfile**

Update the `Dockerfile` to include Cloud SQL Proxy. Add this before the final CMD or ENTRYPOINT (typically near the end):

```dockerfile
# Install Cloud SQL Proxy (MySQL support)
RUN curl -o /usr/local/bin/cloud_sql_proxy https://dl.google.com/cloudsql/cloud_sql_proxy.linux.amd64 && \
    chmod +x /usr/local/bin/cloud_sql_proxy

# Create startup wrapper script that runs both Cloud SQL Proxy and the app
RUN cat > /app/start.sh <<'EOF'
#!/bin/bash
set -e

if [ ! -z "${ZILCH_MYSQL_HOST:-}" ]; then
    echo "Starting Cloud SQL Proxy for MySQL..."
    /usr/local/bin/cloud_sql_proxy \
        -ip_address_types=PRIVATE \
        -instances="${GCP_PROJECT_ID}:${GCP_REGION}:${ZILCH_MYSQL_VM_NAME}" \
        -use_http_health_check \
        &
    PROXY_PID=$!
    echo "Cloud SQL Proxy started (PID: $PROXY_PID)"
    sleep 2
fi

echo "Starting application..."
exec "$@"
EOF
chmod +x /app/start.sh
```

Modify the ENTRYPOINT to use the wrapper (assuming current ENTRYPOINT is `ENTRYPOINT ["python", "app.py"]` or similar):

```dockerfile
ENTRYPOINT ["/app/start.sh"]
CMD ["python", "app.py"]  # or whatever your current CMD is
```

- [ ] **Step 3: Verify Dockerfile syntax**

Run: `docker build --dry-run . 2>&1 | head -20`

Expected: Docker build plan shows no errors (or just shows what would be built)

- [ ] **Step 4: Commit**

```bash
git add Dockerfile
git commit -m "feat: add Cloud SQL Proxy to Cloud Run Dockerfile for MySQL connectivity"
```

---

### Task 11: Add MySQL Environment Variables to Cloud Run Service

**Files:**
- Modify: `terraform/main.tf` (update cloud_run_service resource)

- [ ] **Step 1: Locate Cloud Run service resource**

Run: `grep -n "resource.*google_cloud_run_service" terraform/main.tf | head -1`

Expected: Shows line number of Cloud Run service resource

- [ ] **Step 2: Add MySQL environment variables to Cloud Run**

In the `google_cloud_run_service` resource, find the `environment` section within `env` and add:

```hcl
# MySQL environment variables (if enabled)
{
  name  = "ZILCH_MYSQL_HOST"
  value = var.enable_mysql ? google_compute_instance.mysql[0].network_interface[0].network_ip : ""
},
{
  name  = "ZILCH_MYSQL_PORT"
  value = var.enable_mysql ? "3306" : ""
},
{
  name  = "ZILCH_MYSQL_DATABASE"
  value = var.enable_mysql ? var.mysql_database_name : ""
},
{
  name  = "ZILCH_MYSQL_USER"
  value = var.enable_mysql ? var.mysql_user : ""
},
{
  name  = "ZILCH_MYSQL_PASSWORD"
  value = var.enable_mysql ? "sm://${google_secret_manager_secret.mysql_app_password[0].id}" : ""
},
{
  name  = "ZILCH_MYSQL_VM_NAME"
  value = var.enable_mysql ? google_compute_instance.mysql[0].name : ""
},
{
  name  = "GCP_PROJECT_ID"
  value = var.gcp_project_id
},
{
  name  = "GCP_REGION"
  value = var.gcp_region
},
```

- [ ] **Step 2: Add dependency on MySQL resources**

In the Cloud Run service resource, add a `depends_on` block:

```hcl
depends_on = concat(
  [
    # existing dependencies...
  ],
  var.enable_mysql ? [
    google_compute_instance.mysql[0],
    google_secret_manager_secret_version.mysql_app_password[0],
  ] : []
)
```

- [ ] **Step 3: Verify Terraform plan**

Run: `terraform plan 2>&1 | grep -A 2 'ZILCH_MYSQL'`

Expected: Shows MySQL environment variables in the plan

- [ ] **Step 4: Commit**

```bash
git add terraform/main.tf
git commit -m "feat: add MySQL environment variables to Cloud Run service"
```

---

### Task 12: Add IAM Binding for Cloud Run to Access MySQL VM

**Files:**
- Modify: `terraform/mysql.tf` (add IAM binding)

- [ ] **Step 1: Add IAM binding resource**

Append to `terraform/mysql.tf`:

```hcl
# IAM: Allow Cloud Run service account to access MySQL VM
resource "google_compute_instance_iam_member" "cloud_run_mysql_access" {
  count         = var.enable_mysql ? 1 : 0
  instance_name = google_compute_instance.mysql[0].name
  zone          = google_compute_instance.mysql[0].zone
  role          = "roles/compute.osLogin"
  member        = "serviceAccount:${google_service_account.app.email}"
  project       = var.gcp_project_id
}
```

- [ ] **Step 2: Verify IAM in plan**

Run: `terraform plan 2>&1 | grep -A 1 'osLogin'`

Expected: Shows IAM member binding for Cloud Run access

- [ ] **Step 3: Commit**

```bash
git add terraform/mysql.tf
git commit -m "feat: add IAM binding for Cloud Run to access MySQL VM"
```

---

## Phase 4: Migration Script & Database Tools (Tasks 13-15)

### Task 13: Create Migration Script

**Files:**
- Create: `db/migrate.sh`
- Create: `db/migrations/.gitkeep`

- [ ] **Step 1: Create migrations directory**

```bash
mkdir -p db/migrations
touch db/migrations/.gitkeep
```

- [ ] **Step 2: Create migrate.sh script**

Create `db/migrate.sh`:

```bash
#!/bin/bash
set -euo pipefail

# Zilch MySQL Migration Runner
# Usage: ./migrate.sh [up|down|status|--dry-run]

MIGRATIONS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/migrations" && pwd)"
METADATA_FILE="$MIGRATIONS_DIR/.migration_metadata.json"

# Get MySQL connection parameters
MYSQL_HOST="${ZILCH_MYSQL_HOST:=127.0.0.1}"
MYSQL_PORT="${ZILCH_MYSQL_PORT:=3306}"
MYSQL_DATABASE="${ZILCH_MYSQL_DATABASE:=zilch_app}"
MYSQL_USER="${ZILCH_MYSQL_USER:=zilch_user}"
MYSQL_PASSWORD="${ZILCH_MYSQL_PASSWORD:=}"

# Options
DRY_RUN=false
DIRECTION="up"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        up|down|status)
            DIRECTION="$1"
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

error() {
    echo "ERROR: $*" >&2
    exit 1
}

# Initialize metadata file if not exists
if [ ! -f "$METADATA_FILE" ]; then
    echo '{"applied": [], "pending": []}' > "$METADATA_FILE"
fi

# MySQL query helper
run_sql() {
    local query="$1"
    
    if [ "$DRY_RUN" = true ]; then
        echo "[DRY-RUN] $query"
    else
        mysql \
            -h "$MYSQL_HOST" \
            -P "$MYSQL_PORT" \
            -u "$MYSQL_USER" \
            ${MYSQL_PASSWORD:+-p"$MYSQL_PASSWORD"} \
            "$MYSQL_DATABASE" \
            -e "$query"
    fi
}

# Run SQL file
run_sql_file() {
    local file="$1"
    
    if [ "$DRY_RUN" = true ]; then
        log "[DRY-RUN] Would execute: $file"
        cat "$file" | head -5
        echo "..."
    else
        log "Executing: $(basename "$file")"
        mysql \
            -h "$MYSQL_HOST" \
            -P "$MYSQL_PORT" \
            -u "$MYSQL_USER" \
            ${MYSQL_PASSWORD:+-p"$MYSQL_PASSWORD"} \
            "$MYSQL_DATABASE" \
            < "$file"
    fi
}

# List migrations
list_migrations() {
    find "$MIGRATIONS_DIR" -name "*.sql" -type f | sort
}

# Apply pending migrations
migrate_up() {
    log "Starting migrations (up)..."
    
    for migration_file in $(list_migrations); do
        migration_name=$(basename "$migration_file")
        
        if grep -q "$migration_name" "$METADATA_FILE"; then
            log "Skipping already-applied: $migration_name"
        else
            log "Applying: $migration_name"
            run_sql_file "$migration_file"
            
            # Record as applied
            if [ "$DRY_RUN" = false ]; then
                # Append to applied list in metadata
                temp_file=$(mktemp)
                jq --arg name "$migration_name" \
                    '.applied += [$name]' \
                    "$METADATA_FILE" > "$temp_file"
                mv "$temp_file" "$METADATA_FILE"
                log "Recorded: $migration_name"
            fi
        fi
    done
    
    log "Migrations complete"
}

# Show status
show_status() {
    log "Migration Status"
    log "================"
    
    applied=$(jq -r '.applied[]' "$METADATA_FILE" 2>/dev/null | wc -l)
    log "Applied: $applied"
    
    log "Applied migrations:"
    jq -r '.applied[]' "$METADATA_FILE" 2>/dev/null | while read -r line; do
        log "  ✓ $line"
    done
    
    log ""
    log "Pending migrations:"
    for migration_file in $(list_migrations); do
        migration_name=$(basename "$migration_file")
        if ! grep -q "$migration_name" "$METADATA_FILE"; then
            log "  ○ $migration_name"
        fi
    done
}

# Main
case "$DIRECTION" in
    up)
        migrate_up
        ;;
    status)
        show_status
        ;;
    *)
        error "Unknown direction: $DIRECTION"
        ;;
esac
```

- [ ] **Step 2: Make scripts executable**

```bash
chmod +x db/migrate.sh
```

- [ ] **Step 3: Verify script syntax**

Run: `bash -n db/migrate.sh`

Expected: No output (syntax is valid)

- [ ] **Step 4: Commit**

```bash
git add db/migrate.sh db/migrations/.gitkeep
git commit -m "feat: add migration script and database tooling"
```

---

### Task 14: Create Template Migration File

**Files:**
- Create: `db/init-schema.sql`

- [ ] **Step 1: Create template schema file**

Create `db/init-schema.sql`:

```sql
-- Zilch MySQL Initial Schema Template
-- Users can modify this or add their own migrations

-- Example: Users table
-- CREATE TABLE users (
--     id INT AUTO_INCREMENT PRIMARY KEY,
--     email VARCHAR(255) NOT NULL UNIQUE,
--     name VARCHAR(255),
--     created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
--     updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
--     INDEX idx_email (email)
-- ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Example: Products table
-- CREATE TABLE products (
--     id INT AUTO_INCREMENT PRIMARY KEY,
--     name VARCHAR(255) NOT NULL,
--     price DECIMAL(10, 2) NOT NULL,
--     stock INT DEFAULT 0,
--     created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
--     INDEX idx_name (name)
-- ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Verify database is ready
SELECT "Zilch MySQL database is ready" AS status;
```

- [ ] **Step 2: Create first migration from template**

Copy the template to create the first actual migration:

```bash
cp db/init-schema.sql db/migrations/001-initial-schema.sql
```

Edit `db/migrations/001-initial-schema.sql` to uncomment the example tables (or leave them commented for users to customize).

- [ ] **Step 3: Commit**

```bash
git add db/init-schema.sql db/migrations/001-initial-schema.sql
git commit -m "feat: add template schema files for database migrations"
```

---

### Task 15: Create Migration Testing Script

**Files:**
- Create: `scripts/test-mysql-migrations.sh` (optional, for CI/CD later)

- [ ] **Step 1: Create test script**

Create `scripts/test-mysql-migrations.sh`:

```bash
#!/bin/bash
set -euo pipefail

# Test MySQL migrations locally or in CI/CD

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

error() {
    echo "ERROR: $*" >&2
    exit 1
}

# Check if MySQL is accessible
log "Testing MySQL connectivity..."
mysql -h "${ZILCH_MYSQL_HOST:=127.0.0.1}" \
       -P "${ZILCH_MYSQL_PORT:=3306}" \
       -u "${ZILCH_MYSQL_USER:=zilch_user}" \
       ${ZILCH_MYSQL_PASSWORD:+-p"$ZILCH_MYSQL_PASSWORD"} \
       "${ZILCH_MYSQL_DATABASE:=zilch_app}" \
       -e "SELECT 1" || error "Could not connect to MySQL"

log "MySQL is accessible"

# Run migrations
log "Running migrations..."
cd "$(dirname "${BASH_SOURCE[0]}")/.."
./db/migrate.sh up || error "Migration failed"

# Show status
log "Migration status:"
./db/migrate.sh status

log "All tests passed"
```

- [ ] **Step 2: Make executable**

```bash
chmod +x scripts/test-mysql-migrations.sh
```

- [ ] **Step 3: Commit**

```bash
git add scripts/test-mysql-migrations.sh
git commit -m "feat: add migration testing script"
```

---

## Phase 5: Deployment Script Integration (Tasks 16-18)

### Task 16: Add MySQL Prompt to deploy.sh

**Files:**
- Modify: `deploy.sh`

- [ ] **Step 1: Locate the configuration prompts section in deploy.sh**

Run: `grep -n "Ask user for.*region\|Ask user for" deploy.sh | head -3`

Expected: Shows line numbers of existing prompts

- [ ] **Step 2: Add MySQL prompt after existing service prompts**

Find the section where Zilch prompts for service enablement (usually after region/app name). Add this prompt:

```bash
# MySQL Database (NEW)
echo ""
echo "=== MySQL Database (Optional) ==="
echo "Deploy a free MySQL database on Compute Engine?"
echo "  • Cost: ~\$1.26/month (compute free, minimal storage)"
echo "  • Good for: Transactional relational data"
echo "  • Size: 1-10GB datasets, 100-500 writes/sec"
echo ""
read -p "Enable MySQL? (y/n) [default: n]: " ENABLE_MYSQL
ENABLE_MYSQL="${ENABLE_MYSQL:-n}"

if [[ "$ENABLE_MYSQL" == "y" || "$ENABLE_MYSQL" == "yes" ]]; then
    TERRAFORM_VARS="$TERRAFORM_VARS -var=enable_mysql=true"
    echo "✓ MySQL will be provisioned"
    
    # Optional: Ask for database name
    read -p "Enter MySQL database name [default: zilch_app]: " MYSQL_DB_NAME
    MYSQL_DB_NAME="${MYSQL_DB_NAME:-zilch_app}"
    TERRAFORM_VARS="$TERRAFORM_VARS -var=mysql_database_name=$MYSQL_DB_NAME"
else
    TERRAFORM_VARS="$TERRAFORM_VARS -var=enable_mysql=false"
    echo "✓ MySQL will not be provisioned"
fi
```

- [ ] **Step 2: Add post-deployment MySQL instructions**

After the Terraform apply succeeds, add:

```bash
# Display MySQL connection info (if enabled)
if [[ "$ENABLE_MYSQL" == "y" || "$ENABLE_MYSQL" == "yes" ]]; then
    echo ""
    echo "=== MySQL Database Ready ==="
    MYSQL_HOST=$(terraform output -raw zilch_mysql_host 2>/dev/null || echo "")
    MYSQL_USER=$(terraform output -raw zilch_mysql_user 2>/dev/null || echo "")
    
    echo "Connection details:"
    echo "  Host: $MYSQL_HOST"
    echo "  Port: 3306"
    echo "  Database: $MYSQL_DB_NAME"
    echo "  User: $MYSQL_USER"
    echo ""
    echo "To manage your database:"
    echo "  1. Cloud SQL Proxy (local dev):"
    echo "     cloud-sql-proxy compute/$GCP_PROJECT_ID/$GCP_REGION/\$VM_NAME &"
    echo "     mysql -h 127.0.0.1 -u $MYSQL_USER -p"
    echo ""
    echo "  2. SSH to VM (bastion access):"
    echo "     gcloud compute ssh \$VM_NAME --zone=$GCP_ZONE"
    echo ""
    echo "  3. Database migrations:"
    echo "     ./db/migrate.sh up"
    echo "     ./db/migrate.sh status"
    echo ""
fi
```

- [ ] **Step 3: Verify deploy.sh syntax**

Run: `bash -n deploy.sh`

Expected: No output (syntax is valid)

- [ ] **Step 4: Commit**

```bash
git add deploy.sh
git commit -m "feat: add MySQL enablement prompts to deploy.sh"
```

---

### Task 17: Add MySQL to .gitignore

**Files:**
- Modify: `.gitignore`

- [ ] **Step 1: Add patterns to .gitignore**

Append to `.gitignore`:

```
# MySQL migration metadata
db/migrations/.migration_metadata.json

# Local MySQL backups
db/backups/
*.sql.bak

# MySQL logs
mysql-*.log
```

- [ ] **Step 2: Verify .gitignore syntax**

Run: `git check-ignore db/migrations/.migration_metadata.json && echo "Pattern matched" || echo "No match"`

Expected: "Pattern matched"

- [ ] **Step 3: Commit**

```bash
git add .gitignore
git commit -m "feat: add MySQL-related patterns to .gitignore"
```

---

### Task 18: Update README with MySQL Service Documentation

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Locate "Optional Features" section in README**

Run: `grep -n "Optional Features" README.md`

Expected: Shows line number

- [ ] **Step 2: Add MySQL to the features table**

In the Optional Features table, add this row after the existing services:

```markdown
| MySQL Database | ~$1.26/month | Transactional relational SQL, Cloud SQL Proxy access | `enable_mysql` |
```

- [ ] **Step 3: Add MySQL connection section**

After the "Accessing Services" section, add:

```markdown
### MySQL Database

If you enabled MySQL, your Cloud Run service automatically receives connection details:

```python
import mysql.connector
import os

if os.getenv('ZILCH_MYSQL_HOST'):
    db = mysql.connector.connect(
        host=os.getenv('ZILCH_MYSQL_HOST'),
        port=int(os.getenv('ZILCH_MYSQL_PORT', 3306)),
        user=os.getenv('ZILCH_MYSQL_USER'),
        password=os.getenv('ZILCH_MYSQL_PASSWORD'),
        database=os.getenv('ZILCH_MYSQL_DATABASE')
    )
    cursor = db.cursor()
    cursor.execute("SELECT 1")
```

**Manage your database schema:**

```bash
# Create new migration
cat > db/migrations/002-add-users-table.sql <<EOF
CREATE TABLE users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL
);
EOF

# Apply migrations
./db/migrate.sh up

# Check status
./db/migrate.sh status
```

**Direct access (local development):**

```bash
# Install Cloud SQL Proxy
cloud-sql-proxy compute/PROJECT_ID/REGION/zilch-mysql-vm &

# Connect locally
mysql -h 127.0.0.1 -u zilch_user -p
```

**Direct access (SSH bastion):**

```bash
gcloud compute ssh zilch-mysql-vm --zone=us-central1-a
mysql -u zilch_user -p
```
```

- [ ] **Step 4: Add troubleshooting section for MySQL**

Add to README troubleshooting section:

```markdown
### MySQL Connection Errors

If your app can't connect to MySQL:

1. Verify MySQL is running:
   ```bash
   gcloud compute instances list | grep mysql
   ```

2. Check Cloud SQL Proxy logs in Cloud Run:
   ```bash
   gcloud run logs read YOUR_APP_NAME --limit=50
   ```

3. Test direct connection:
   ```bash
   cloud-sql-proxy compute/PROJECT_ID/REGION/zilch-mysql-vm &
   mysql -h 127.0.0.1 -u zilch_user -p
   ```
```

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "docs: add MySQL service documentation to README"
```

---

## Phase 6: Testing & Validation (Tasks 19-21)

### Task 19: Terraform Plan Validation

**Files:**
- No files modified

- [ ] **Step 1: Run Terraform format check**

Run: `terraform fmt -check terraform/`

Expected: No output (all files are properly formatted) or lists files needing formatting

- [ ] **Step 2: Run Terraform validation**

Run: `terraform validate`

Expected: "The configuration is valid"

- [ ] **Step 3: Generate Terraform plan**

Run: `terraform plan -out=/tmp/plan.tfplan`

Expected: Plan succeeds, shows resources that would be created

- [ ] **Step 4: Inspect plan for MySQL resources**

Run: `terraform show /tmp/plan.tfplan | grep -E "google_compute_instance|google_compute_disk|google_secret_manager" | head -10`

Expected: Shows MySQL-related resources in the plan

- [ ] **Step 5: Document findings**

Run (no action needed):
```
Expected resources in plan:
  - google_compute_instance.mysql (if enable_mysql=true)
  - google_compute_disk.mysql_data
  - google_secret_manager_secret (2x for passwords)
  - google_compute_firewall (2x for MySQL and SSH)
  - google_service_account.mysql
```

---

### Task 20: Mock Deployment Test

**Files:**
- No files modified

- [ ] **Step 1: Validate with enable_mysql=false (existing behavior)**

Run: `terraform plan -var=enable_mysql=false -out=/tmp/plan_no_mysql.tfplan 2>&1 | tail -5`

Expected: Plan shows no MySQL resources (empty or only existing resources)

- [ ] **Step 2: Validate with enable_mysql=true**

Run: `terraform plan -var=enable_mysql=true -out=/tmp/plan_with_mysql.tfplan 2>&1 | grep -c 'google_compute'`

Expected: Shows count > 0 (MySQL resources included)

- [ ] **Step 3: Compare plans**

Run: `terraform show /tmp/plan_with_mysql.tfplan | grep -c 'google_' && terraform show /tmp/plan_no_mysql.tfplan | grep -c 'google_'`

Expected: MySQL plan shows more resources than non-MySQL plan

---

### Task 21: Documentation Verification

**Files:**
- No files modified

- [ ] **Step 1: Verify wiki roadmap document exists and links are valid**

Run: `grep -o '\[.*\](.*mysql' docs/wiki/topics/roadmap-mysql-service.md | head -5`

Expected: Shows internal links are formatted correctly

- [ ] **Step 2: Verify implementation plan document exists**

Run: `test -f docs/superpowers/plans/2026-06-19-mysql-service-implementation.md && echo 'Plan exists' || echo 'Plan missing'`

Expected: "Plan exists"

- [ ] **Step 3: Verify design spec document exists**

Run: `test -f docs/superpowers/specs/2026-06-19-mysql-service-design.md && echo 'Spec exists' || echo 'Spec missing'`

Expected: "Spec exists"

- [ ] **Step 4: Check for TODOs or unresolved items in documentation**

Run: `grep -r "TODO\|FIXME\|XXX" docs/superpowers/specs/2026-06-19-mysql-service-design.md || echo 'No TODOs found'`

Expected: "No TODOs found" (or only "Target Release: TBD" which is intentional)

---

## Success Criteria Checklist

All MVP success criteria from the design spec:

- [ ] ✅ `enable_mysql=true` provisions e2-micro + MySQL in < 2 minutes
- [ ] ✅ Cloud Run app can connect without manual configuration
- [ ] ✅ All environment variables (ZILCH_MYSQL_*) populated correctly
- [ ] ✅ `./db/migrate.sh up` runs .sql files successfully
- [ ] ✅ Cloud SQL Proxy access pattern works (local development)
- [ ] ✅ SSH bastion access pattern works (direct VM access)
- [ ] ✅ Migration script access pattern works (version-controlled schemas)
- [ ] ✅ Documented with working examples (README + wiki)
- [ ] ✅ Error messages are clear and actionable
- [ ] ✅ All three access patterns tested and verified

---

## Execution Handoff

**Plan complete and saved to `docs/superpowers/plans/2026-06-19-mysql-service-implementation.md`.**

Two execution options:

**1. Subagent-Driven (Recommended)** — I dispatch a fresh subagent per task, review between tasks, iterate quickly

**2. Inline Execution** — Execute tasks in this session using executing-plans skill, batch with checkpoints

Which approach would you prefer?
