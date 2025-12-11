# =============================================================================
# Terraform Backend Configuration
# =============================================================================
# Onomancer Bot - Google Workspace Foundation
# Sprint 1 - Task 1.2: Terraform Project Bootstrap
#
# Remote state is stored in Google Cloud Storage (GCS) with:
# - State locking via GCS object metadata
# - Encryption at rest (default GCS encryption)
# - Versioning enabled for state history
#
# SETUP INSTRUCTIONS:
# 1. Create the GCS bucket manually or via gcloud CLI:
#    gcloud storage buckets create gs://thj-onomancer-terraform-state \
#      --location=us-central1 \
#      --uniform-bucket-level-access \
#      --enable-versioning
#
# 2. Grant the service account access:
#    gcloud storage buckets add-iam-policy-binding gs://thj-onomancer-terraform-state \
#      --member="serviceAccount:terraform@YOUR_PROJECT.iam.gserviceaccount.com" \
#      --role="roles/storage.objectAdmin"
#
# 3. Initialize Terraform with the backend:
#    terraform init
# =============================================================================

terraform {
  backend "gcs" {
    # State bucket - must be created before running terraform init
    # Bucket name format: {org-prefix}-{project}-terraform-state
    bucket = "thj-onomancer-terraform-state"

    # State file path within the bucket
    # Using environment prefix for state file isolation
    prefix = "onomancer-bot"
  }
}

# =============================================================================
# ALTERNATIVE: Local Backend for Development
# =============================================================================
# Uncomment the block below and comment out the GCS backend above
# if you want to use local state during initial development.
#
# WARNING: Local state should NOT be used in production!
# It doesn't support team collaboration or state locking.
# =============================================================================
#
# terraform {
#   backend "local" {
#     path = "terraform.tfstate"
#   }
# }
