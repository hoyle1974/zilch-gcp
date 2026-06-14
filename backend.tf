terraform {
  backend "gcs" {
    # Dynamically constructed at setup initialization via deploy.sh injection
    # Example: terraform init -backend-config="bucket=my-project-zilch-tfstate"
  }
}
