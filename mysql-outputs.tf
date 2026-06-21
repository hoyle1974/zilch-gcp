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
  value       = try(google_compute_address.mysql[0].address, "")
  description = "Environment variable: ZILCH_MYSQL_HOST (public IP)"
}

output "zilch_mysql_port" {
  value       = var.enable_mysql ? tostring(random_integer.mysql_port[0].result) : ""
  description = "Environment variable: ZILCH_MYSQL_PORT (randomized per deployment)"
}

output "zilch_mysql_database" {
  value       = var.enable_mysql ? var.mysql_database_name : ""
  description = "Environment variable: ZILCH_MYSQL_DATABASE"
}
