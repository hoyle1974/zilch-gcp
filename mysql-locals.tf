locals {
  mysql_enabled = var.enable_mysql

  # Generate unique suffix for resources to avoid naming conflicts
  # (random_id.mysql_suffix is defined in Task 3: add random ID generators)
  mysql_resource_suffix = try(random_id.mysql_suffix[0].hex, "")

  # Construct VM name
  mysql_vm_name = local.mysql_enabled ? "zilch-mysql-vm-${local.mysql_resource_suffix}" : ""

  # Construct disk name
  mysql_disk_name = local.mysql_enabled ? "zilch-mysql-disk-${local.mysql_resource_suffix}" : ""

  # MySQL container image
  mysql_container_image = "mysql:8.0-debian"

  # Network tag for firewall rules
  mysql_network_tag = local.mysql_enabled ? "zilch-mysql" : ""

  # Machine type (hardcoded to e2-micro for Always Free)
  mysql_machine_type = "e2-micro"

  # Region and zone (derived from global gcp_region)
  mysql_region = var.gcp_region
  mysql_zone   = "${var.gcp_region}-a"

  # Labels for resource tracking
  mysql_labels = {
    service    = "mysql"
    managed_by = "zilch"
  }
}
