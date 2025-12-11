# =============================================================================
# Terraform Variables Definition
# =============================================================================
# Onomancer Bot - Google Workspace Foundation
# Sprint 1 - Task 1.2: Terraform Project Bootstrap
# =============================================================================

# -----------------------------------------------------------------------------
# Google Cloud Project Configuration
# -----------------------------------------------------------------------------

variable "project_id" {
  description = "GCP project ID for the Onomancer Bot infrastructure"
  type        = string
}

variable "region" {
  description = "Default GCP region for resources"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "Default GCP zone for resources"
  type        = string
  default     = "us-central1-a"
}

# -----------------------------------------------------------------------------
# Organization Configuration
# -----------------------------------------------------------------------------

variable "organization_name" {
  description = "Name of the organization for Google Workspace (e.g., 'The Honey Jar')"
  type        = string
  default     = "The Honey Jar"
}

variable "domain" {
  description = "Domain name for Google Workspace (e.g., 'thehoneyjar.xyz')"
  type        = string
}

# -----------------------------------------------------------------------------
# Service Account Configuration
# -----------------------------------------------------------------------------

variable "service_account_id" {
  description = "ID for the Onomancer Bot service account"
  type        = string
  default     = "onomancer-bot"
}

variable "service_account_display_name" {
  description = "Display name for the service account"
  type        = string
  default     = "Onomancer Bot Service Account"
}

# -----------------------------------------------------------------------------
# Google Drive Configuration
# -----------------------------------------------------------------------------

variable "products" {
  description = "List of products/projects to create folder structures for"
  type        = list(string)
  default     = ["MiBera", "FatBera", "Interpol", "Set & Forgetti"]
}

variable "personas" {
  description = "List of personas for executive summary subfolders"
  type        = list(string)
  default     = ["Leadership", "Product", "Marketing", "DevRel"]
}

variable "root_folder_name" {
  description = "Name of the root Google Drive folder"
  type        = string
  default     = "The Honey Jar"
}

# -----------------------------------------------------------------------------
# Stakeholder Group Configuration
# -----------------------------------------------------------------------------

variable "stakeholder_groups" {
  description = "Map of stakeholder group names to their email prefixes"
  type = map(object({
    name        = string
    description = string
    access      = string # "reader" or "writer"
  }))
  default = {
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
}

# -----------------------------------------------------------------------------
# Environment Configuration
# -----------------------------------------------------------------------------

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# -----------------------------------------------------------------------------
# Tags/Labels
# -----------------------------------------------------------------------------

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "onomancer-bot"
    managed_by  = "terraform"
    environment = "dev"
  }
}
