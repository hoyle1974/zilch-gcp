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

variable "mysql_disk_size_gb" {
  type        = number
  description = "Size of persistent disk for MySQL data (GB)"
  default     = 30

  validation {
    condition     = var.mysql_disk_size_gb >= 10 && var.mysql_disk_size_gb <= 1000
    error_message = "Disk size must be between 10 GB and 1000 GB."
  }
}
