# =============================================================================
# Production Environment Configuration
# =============================================================================
# Onomancer Bot - Google Workspace Foundation
# Sprint 1 - Task 1.2: Terraform Project Bootstrap
#
# INSTRUCTIONS:
# 1. Copy this file to terraform.tfvars.local (gitignored)
# 2. Update project_id and domain with your production values
# 3. Ensure proper access controls before deploying to production
# 4. Run: terraform workspace select prod
# 5. Run: terraform plan -var-file=environments/prod/terraform.tfvars
# =============================================================================

# GCP Project Configuration
# REQUIRED: Replace with your production GCP project ID
project_id = "thj-onomancer-prod"
region     = "us-central1"
zone       = "us-central1-a"

# Google Workspace Configuration
# REQUIRED: Replace with your production domain
domain            = "thehoneyjar.xyz"
organization_name = "The Honey Jar"

# Service Account Configuration
service_account_id           = "onomancer-bot"
service_account_display_name = "Onomancer Bot"

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

# Root folder name (production - no suffix)
root_folder_name = "The Honey Jar"

# Environment
environment = "prod"

# Labels
labels = {
  project     = "onomancer-bot"
  managed_by  = "terraform"
  environment = "prod"
  team        = "devrel"
}

# Stakeholder groups (same as dev, but using production domain)
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
