# =============================================================================
# Monitoring Module - Main Configuration
# =============================================================================
# Onomancer Bot - Google Workspace Foundation
# Sprint 1 - Optional monitoring infrastructure
# =============================================================================

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "service_account_email" {
  description = "Service account email to monitor"
  type        = string
}

variable "enable_uptime_monitoring" {
  description = "Enable uptime monitoring (production only)"
  type        = bool
  default     = false
}

variable "labels" {
  description = "Labels to apply to resources"
  type        = map(string)
}

# -----------------------------------------------------------------------------
# Enable Monitoring API
# -----------------------------------------------------------------------------

resource "google_project_service" "monitoring_api" {
  project            = var.project_id
  service            = "monitoring.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "logging_api" {
  project            = var.project_id
  service            = "logging.googleapis.com"
  disable_on_destroy = false
}

# -----------------------------------------------------------------------------
# Logging Sink for Audit Logs
# -----------------------------------------------------------------------------
# Captures API calls made by the service account for audit purposes

resource "google_logging_project_sink" "audit_sink" {
  count = var.environment == "prod" ? 1 : 0

  name        = "onomancer-bot-audit-sink"
  project     = var.project_id
  destination = "logging.googleapis.com/projects/${var.project_id}/locations/global/buckets/_Default"

  filter = <<-EOT
    protoPayload.authenticationInfo.principalEmail="${var.service_account_email}"
    AND protoPayload.serviceName="drive.googleapis.com"
  EOT

  unique_writer_identity = true

  depends_on = [
    google_project_service.logging_api
  ]
}

# -----------------------------------------------------------------------------
# Alert Policy for API Errors
# -----------------------------------------------------------------------------

resource "google_monitoring_alert_policy" "api_errors" {
  count = var.enable_uptime_monitoring ? 1 : 0

  display_name = "Onomancer Bot - API Errors"
  project      = var.project_id
  combiner     = "OR"

  conditions {
    display_name = "High API Error Rate"

    condition_threshold {
      filter          = "resource.type=\"consumed_api\" AND resource.label.service=\"drive.googleapis.com\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 10

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  notification_channels = []

  documentation {
    content   = "The Onomancer Bot service account is experiencing high API error rates with Google Drive API."
    mime_type = "text/markdown"
  }

  user_labels = var.labels

  depends_on = [
    google_project_service.monitoring_api
  ]
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "audit_sink_name" {
  description = "Name of the audit logging sink"
  value       = var.environment == "prod" ? google_logging_project_sink.audit_sink[0].name : "disabled"
}

output "monitoring_enabled" {
  description = "Whether monitoring is enabled"
  value       = var.enable_uptime_monitoring
}
