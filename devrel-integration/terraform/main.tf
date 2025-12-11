# =============================================================================
# Main Terraform Configuration
# =============================================================================
# Onomancer Bot - Google Workspace Foundation
# Sprint 1 - Task 1.2: Terraform Project Bootstrap
# =============================================================================

# -----------------------------------------------------------------------------
# Provider Configuration
# -----------------------------------------------------------------------------

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# -----------------------------------------------------------------------------
# Workspace Module - Service Account, APIs, and Folder Structure
# -----------------------------------------------------------------------------

module "workspace" {
  source = "./modules/workspace"

  project_id                   = var.project_id
  region                       = var.region
  domain                       = var.domain
  organization_name            = var.organization_name
  service_account_id           = var.service_account_id
  service_account_display_name = var.service_account_display_name
  products                     = var.products
  personas                     = var.personas
  root_folder_name             = var.root_folder_name
  stakeholder_groups           = var.stakeholder_groups
  environment                  = var.environment
  labels                       = var.labels
}

# -----------------------------------------------------------------------------
# Monitoring Module (Optional - Basic health monitoring)
# -----------------------------------------------------------------------------

module "monitoring" {
  source = "./modules/monitoring"

  project_id               = var.project_id
  environment              = var.environment
  service_account_email    = module.workspace.service_account_email
  enable_uptime_monitoring = var.environment == "prod"
  labels                   = var.labels

  depends_on = [module.workspace]
}
