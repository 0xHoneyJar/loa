# =============================================================================
# Workspace Module Variables
# =============================================================================
# Onomancer Bot - Google Workspace Foundation
# Sprint 1 - Tasks 1.3, 1.4, 1.5
# =============================================================================

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "Default GCP region"
  type        = string
}

variable "domain" {
  description = "Google Workspace domain"
  type        = string
}

variable "organization_name" {
  description = "Organization name"
  type        = string
}

variable "service_account_id" {
  description = "ID for the service account"
  type        = string
}

variable "service_account_display_name" {
  description = "Display name for the service account"
  type        = string
}

variable "products" {
  description = "List of product names for folder structure"
  type        = list(string)
}

variable "personas" {
  description = "List of persona names for executive summaries"
  type        = list(string)
}

variable "root_folder_name" {
  description = "Name of the root folder"
  type        = string
}

variable "stakeholder_groups" {
  description = "Map of stakeholder groups configuration"
  type = map(object({
    name        = string
    description = string
    access      = string
  }))
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "labels" {
  description = "Labels to apply to resources"
  type        = map(string)
}
