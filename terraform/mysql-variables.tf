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
