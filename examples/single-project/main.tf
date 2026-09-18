# Minimal usage of the Nodrik onboarding module against one project.
#
# This is a root module: it is the one place a provider block belongs.
# Run `terraform init && terraform plan` here against your own project
# to see exactly what Nodrik would be granted before applying anything.

terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0, < 8.0"
    }
  }
}

provider "google" {
  project = var.project_id
}

module "nodrik" {
  source = "../../terraform"

  tenant_service_account = var.tenant_service_account
  tenant_topic           = var.tenant_topic
  project_ids            = [var.project_id]
}
