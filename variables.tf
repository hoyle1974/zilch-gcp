variable "gcp_project_id" {
  type        = string
  description = "Target infrastructure destination Google Cloud Project ID"
  validation {
    condition     = can(regex("^[a-z0-9-]{6,30}$", var.gcp_project_id))
    error_message = "Project IDs must match 6-30 lowercase characters, numbers, and hyphens only."
  }
}

variable "gcp_region" {
  type        = string
  default     = "us-central1"
  description = "Target runtime region zone restricted to core active free tiers"
  validation {
    condition     = contains(["us-central1", "us-east1", "us-west1"], var.gcp_region)
    error_message = "Zilch deployment zone must fall inside us-central1, us-east1, or us-west1 to maintain Always Free tier rules."
  }
}

variable "app_name" {
  type        = string
  description = "Service container namespace identifier prefix used for resources"
  validation {
    condition     = can(regex("^[a-z0-9-]{3,30}$", var.app_name))
    error_message = "Application display prefix naming structure must use 3-30 lowercase characters or hyphens."
  }
}

variable "enable_firestore" {
  type    = bool
  default = false
  description = "Enable Firestore NoSQL Database (free tier: 1GB storage, 50K reads/day)"
}

variable "enable_secret_manager" {
  type    = bool
  default = false
  description = "Enable Secret Manager for secure credential storage"
}

variable "enable_vertex_ai" {
  type    = bool
  default = false
  description = "Enable Vertex AI (includes Gemini API access, free: 60 req/min)"
}

variable "enable_cloud_storage" {
  type    = bool
  default = false
  description = "Enable Cloud Storage bucket for file uploads/downloads (free tier: 5GB)"
}

variable "enable_firebase_auth" {
  type    = bool
  default = false
  description = "Enable Firebase Authentication for social login"
}
