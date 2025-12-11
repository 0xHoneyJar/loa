# =============================================================================
# Terraform Output Values
# =============================================================================
# Onomancer Bot - Google Workspace Foundation
# Sprint 1 - Task 1.2: Terraform Project Bootstrap
#
# These outputs are exported for use by the Discord bot at runtime.
# The folder IDs are essential for the GoogleDocsStorageService to store
# documents in the correct locations.
# =============================================================================

# -----------------------------------------------------------------------------
# Service Account Outputs
# -----------------------------------------------------------------------------

output "service_account_email" {
  description = "Email address of the Onomancer Bot service account"
  value       = module.workspace.service_account_email
}

output "service_account_id" {
  description = "ID of the Onomancer Bot service account"
  value       = module.workspace.service_account_id
}

output "service_account_key_name" {
  description = "Name of the service account key (sensitive data stored in secrets manager)"
  value       = module.workspace.service_account_key_name
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Google Drive Folder Structure Outputs
# -----------------------------------------------------------------------------

output "root_folder_id" {
  description = "ID of the root Google Drive folder"
  value       = module.workspace.root_folder_id
}

output "products_folder_id" {
  description = "ID of the /Products folder"
  value       = module.workspace.products_folder_id
}

output "shared_folder_id" {
  description = "ID of the /Shared folder"
  value       = module.workspace.shared_folder_id
}

output "product_folder_ids" {
  description = "Map of product names to their folder IDs"
  value       = module.workspace.product_folder_ids
}

output "weekly_digests_folder_id" {
  description = "ID of the /Shared/Weekly Digests folder"
  value       = module.workspace.weekly_digests_folder_id
}

output "templates_folder_id" {
  description = "ID of the /Shared/Templates folder"
  value       = module.workspace.templates_folder_id
}

# -----------------------------------------------------------------------------
# Folder ID JSON Export
# -----------------------------------------------------------------------------
# This output provides a complete mapping of folder names to IDs
# for use by the Discord bot's GoogleDocsStorageService

output "folder_structure_json" {
  description = "Complete folder structure as JSON for bot runtime configuration"
  value       = module.workspace.folder_structure_json
}

# -----------------------------------------------------------------------------
# Stakeholder Group Outputs
# -----------------------------------------------------------------------------

output "stakeholder_group_emails" {
  description = "Map of stakeholder group names to their email addresses"
  value       = module.workspace.stakeholder_group_emails
}

# -----------------------------------------------------------------------------
# API Enablement Status
# -----------------------------------------------------------------------------

output "enabled_apis" {
  description = "List of enabled Google Cloud APIs"
  value       = module.workspace.enabled_apis
}

# -----------------------------------------------------------------------------
# Project Information
# -----------------------------------------------------------------------------

output "project_id" {
  description = "GCP project ID"
  value       = var.project_id
}

output "domain" {
  description = "Google Workspace domain"
  value       = var.domain
}

output "environment" {
  description = "Deployment environment"
  value       = var.environment
}
