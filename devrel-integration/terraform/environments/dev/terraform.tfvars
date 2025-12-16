# =============================================================================
# Development Environment Configuration
# =============================================================================
# Onomancer Bot - Google Workspace Foundation
# Sprint 1 - Task 1.2: Terraform Project Bootstrap
#
# INSTRUCTIONS:
# 1. Copy this file to terraform.tfvars.local (gitignored)
# 2. Update project_id and domain with your values
# 3. Run: terraform init
# 4. Run: terraform plan -var-file=environments/dev/terraform.tfvars
# =============================================================================

# GCP Project Configuration
# REQUIRED: Replace with your GCP project ID
project_id = "thj-onomancer-dev"
region     = "us-central1"
zone       = "us-central1-a"

# Google Workspace Configuration
# REQUIRED: Replace with your domain
domain            = "thehoneyjar.xyz"
organization_name = "The Honey Jar"

# Service Account Configuration
service_account_id           = "onomancer-bot-dev"
service_account_display_name = "Onomancer Bot (Development)"

# Products to create folder structure for
products = [
  "MiBera",
  "FatBera",
  "Interpol",
  "Set & Forgetti"
]

# Personas for executive summaries
personas = [
  "Leadership",
  "Product",
  "Marketing",
  "DevRel"
]

# Root folder name
root_folder_name = "The Honey Jar (Dev)"

# Environment
environment = "dev"

# Labels
labels = {
  project     = "onomancer-bot"
  managed_by  = "terraform"
  environment = "dev"
  team        = "devrel"
}

# Stakeholder groups
stakeholder_groups = {
  leadership = {
    name        = "leadership"
    description = "Leadership team with access to executive summaries"
    access      = "reader"
  }
  product = {
    name        = "product"
    description = "Product team with access to PRDs, SDDs, and sprint reports"
    access      = "reader"
  }
  marketing = {
    name        = "marketing"
    description = "Marketing team with access to marketing summaries"
    access      = "reader"
  }
  devrel = {
    name        = "devrel"
    description = "DevRel team with access to technical documentation"
    access      = "reader"
  }
  developers = {
    name        = "developers"
    description = "Developers with full read/write access"
    access      = "writer"
  }
}
