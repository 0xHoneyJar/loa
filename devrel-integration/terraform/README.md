# Terraform - Onomancer Bot Google Workspace Foundation

This Terraform configuration provisions the Google Workspace infrastructure for the Onomancer Bot, including:

- **Service Account** with Google Drive and Docs API permissions
- **API Enablement** for Drive, Docs, Admin, and IAM APIs
- **Folder Structure** configuration for Google Drive
- **Stakeholder Permissions** setup scripts
- **Monitoring** configuration (production only)

## Prerequisites

### 1. Google Cloud Platform Setup

1. **Create a GCP Project:**
   ```bash
   gcloud projects create thj-onomancer-dev --name="Onomancer Bot Dev"
   ```

2. **Set the project as default:**
   ```bash
   gcloud config set project thj-onomancer-dev
   ```

3. **Enable billing for the project** (required for API usage)

4. **Authenticate with GCP:**
   ```bash
   gcloud auth application-default login
   ```

### 2. Google Workspace Setup

> **Note:** This must be completed manually before running Terraform.

1. **Create Google Workspace Organization:**
   - Go to [Google Workspace Admin](https://admin.google.com)
   - Create organization for "The Honey Jar"
   - Configure domain (thehoneyjar.xyz or custom domain)
   - Complete domain verification

2. **Create Google Groups (in Admin Console):**
   - `leadership@thehoneyjar.xyz` - Leadership team
   - `product@thehoneyjar.xyz` - Product team
   - `marketing@thehoneyjar.xyz` - Marketing team
   - `devrel@thehoneyjar.xyz` - DevRel team
   - `developers@thehoneyjar.xyz` - Developers

### 3. Terraform State Bucket

Create the GCS bucket for remote state:

```bash
# Create bucket
gcloud storage buckets create gs://thj-onomancer-terraform-state \
  --location=us-central1 \
  --uniform-bucket-level-access \
  --enable-versioning

# Set permissions (replace with your service account if using one)
gcloud storage buckets add-iam-policy-binding gs://thj-onomancer-terraform-state \
  --member="user:$(gcloud config get-value account)" \
  --role="roles/storage.objectAdmin"
```

### 4. Local Requirements

- Terraform >= 1.6.0
- Node.js >= 18.0.0 (for setup scripts)
- gcloud CLI

## Quick Start

### 1. Initialize Terraform

```bash
cd terraform
terraform init
```

### 2. Configure Environment

```bash
# For development
cp environments/dev/terraform.tfvars terraform.tfvars

# Edit terraform.tfvars with your values
# REQUIRED: Update project_id and domain
```

### 3. Plan and Apply

```bash
# Review changes
terraform plan

# Apply changes
terraform apply
```

### 4. Run Setup Scripts

After Terraform apply, run the generated scripts to create Google Drive folders:

```bash
# Install googleapis if not already installed
cd ..
npm install googleapis

# Create folder structure
npx ts-node scripts/setup-drive-folders.ts

# Set up permissions (after creating Google Groups)
npx ts-node scripts/setup-drive-permissions.ts
```

## Directory Structure

```
terraform/
├── main.tf                 # Root configuration and module invocation
├── variables.tf            # Input variable definitions
├── outputs.tf              # Output value definitions
├── versions.tf             # Terraform and provider version constraints
├── backend.tf              # Remote state configuration (GCS)
├── .gitignore              # Terraform-specific gitignore
├── README.md               # This file
├── modules/
│   ├── workspace/          # Google Workspace resources
│   │   ├── main.tf         # Service account and API enablement
│   │   ├── folders.tf      # Folder structure configuration
│   │   ├── permissions.tf  # Stakeholder permissions
│   │   ├── variables.tf    # Module input variables
│   │   └── outputs.tf      # Module outputs
│   └── monitoring/         # Monitoring configuration
│       └── main.tf         # Logging and alerting (prod only)
└── environments/
    ├── dev/
    │   └── terraform.tfvars    # Development environment values
    └── prod/
        └── terraform.tfvars    # Production environment values
```

## Generated Files

After running `terraform apply`, the following files are generated:

| File | Purpose |
|------|---------|
| `../secrets/google-service-account-key.json` | Service account credentials (SENSITIVE) |
| `../config/folder-structure.json` | Folder structure configuration for bot |
| `../config/folder-ids.json` | Actual folder IDs (after running setup script) |
| `../config/google-groups.json` | Google Groups configuration |
| `../scripts/setup-drive-folders.ts` | Script to create Drive folders |
| `../scripts/setup-drive-permissions.ts` | Script to set folder permissions |

## Configuration Variables

### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `project_id` | GCP Project ID | `thj-onomancer-dev` |
| `domain` | Google Workspace domain | `thehoneyjar.xyz` |

### Optional Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `region` | `us-central1` | GCP region |
| `service_account_id` | `onomancer-bot` | Service account ID |
| `products` | MiBera, FatBera, Interpol, Set & Forgetti | Product names |
| `personas` | Leadership, Product, Marketing, DevRel | Persona types |
| `environment` | `dev` | Environment (dev/staging/prod) |

## Folder Structure

The Terraform configuration creates this Google Drive folder hierarchy:

```
/The Honey Jar (root)
  /Products
    /MiBera
      /PRD
        /Executive Summaries
          /Leadership
          /Product
          /Marketing
          /DevRel
      /SDD
        /Executive Summaries/...
      /Sprints
        /Executive Summaries/...
      /Audits
        /Executive Summaries/...
    /FatBera
      ... (same structure)
    /Interpol
      ... (same structure)
    /Set & Forgetti
      ... (same structure)
  /Shared
    /Weekly Digests
    /Templates
```

## Permission Model

| Folder | Leadership | Product | Marketing | DevRel | Developers |
|--------|------------|---------|-----------|--------|------------|
| Leadership Summaries | Read | - | - | - | Read/Write |
| Product Summaries | - | Read | - | - | Read/Write |
| Marketing Summaries | - | - | Read | - | Read/Write |
| DevRel Summaries | - | - | - | Read | Read/Write |
| PRD Folders | Read | Read | - | - | Read/Write |
| SDD Folders | - | Read | - | Read | Read/Write |
| Sprint Folders | Read | Read | Read | Read | Read/Write |
| Audit Folders | Read | - | - | Read | Read/Write |
| Weekly Digests | Read | Read | Read | Read | Read/Write |
| Templates | - | - | - | - | Read/Write |

## Common Operations

### Adding a New Product

1. Edit `terraform.tfvars`:
   ```hcl
   products = [
     "MiBera",
     "FatBera",
     "Interpol",
     "Set & Forgetti",
     "NewProduct"  # Add new product
   ]
   ```

2. Apply changes:
   ```bash
   terraform apply
   ```

3. Re-run folder setup:
   ```bash
   npx ts-node scripts/setup-drive-folders.ts
   npx ts-node scripts/setup-drive-permissions.ts
   ```

### Rotating Service Account Key

```bash
# Generate new key
terraform taint google_service_account_key.onomancer_bot_key
terraform apply

# Restart the Discord bot to use new key
pm2 restart agentic-base-bot
```

### Switching Environments

```bash
# Development
terraform workspace select default
terraform plan -var-file=environments/dev/terraform.tfvars

# Production
terraform workspace select prod
terraform plan -var-file=environments/prod/terraform.tfvars
```

## Troubleshooting

### "Error enabling API"

Ensure billing is enabled for the GCP project:
```bash
gcloud beta billing accounts list
gcloud beta billing projects link PROJECT_ID --billing-account=ACCOUNT_ID
```

### "Permission denied" during folder creation

1. Verify service account has Drive API permissions
2. Check domain-wide delegation is enabled (if using Workspace)
3. Verify Google Groups exist in Admin Console

### "State lock" error

```bash
# Force unlock (use with caution)
terraform force-unlock LOCK_ID
```

### Folder IDs not exported

Run the folder setup script after `terraform apply`:
```bash
npx ts-node scripts/setup-drive-folders.ts
```

## Domain-Wide Delegation

For the service account to access Google Drive folders owned by the organization (not just files it creates), domain-wide delegation may be required.

### When Domain-Wide Delegation is Needed

- Accessing shared drives owned by the organization
- Managing folders created by other users
- Reading/writing documents across the organization

### When Domain-Wide Delegation is NOT Needed

- Bot only manages files/folders it creates itself
- All operations are within a shared drive where the service account is a member
- Using personal Google account (not Workspace)

### Enabling Domain-Wide Delegation

If you determine domain-wide delegation is required:

1. **Go to Google Admin Console:**
   - Navigate to: Security > API Controls > Domain-wide Delegation
   - URL: `https://admin.google.com/ac/owl/domainwidedelegation`

2. **Add Service Account:**
   - Click "Add new"
   - Enter the service account Client ID (found in GCP Console under Service Accounts)
   - Add the following OAuth scopes:
     ```
     https://www.googleapis.com/auth/drive
     https://www.googleapis.com/auth/documents
     ```

3. **Impersonation:**
   - When using the service account with domain-wide delegation, you must impersonate a user in the domain
   - Add `GOOGLE_IMPERSONATE_USER=user@yourdomain.com` to your `.env.local`

### Current Implementation

This Terraform configuration grants the service account `roles/drive.admin` and `roles/docs.editor` at the project level. For most use cases with shared drives, this is sufficient without domain-wide delegation, provided the service account is added as a member to the relevant shared drives.

## Credential Storage

Terraform generates two credential files in `secrets/`:

| File | Purpose |
|------|---------|
| `google-service-account-key.json` | Raw JSON credential file |
| `.env.local` | Environment variables for bot integration |

The `.env.local` file contains:
```bash
GOOGLE_SERVICE_ACCOUNT_EMAIL="onomancer-bot@project-id.iam.gserviceaccount.com"
GOOGLE_SERVICE_ACCOUNT_KEY_PATH="/absolute/path/to/google-service-account-key.json"
```

## Credential Rotation

To rotate the service account key:

1. **Taint the key resource:**
   ```bash
   terraform taint google_service_account_key.onomancer_bot_key
   ```

2. **Apply to generate new key:**
   ```bash
   terraform apply
   ```

3. **Update any systems using the old key:**
   - Restart Discord bot: `pm2 restart agentic-base-bot`
   - Old key is automatically invalidated

## Security Considerations

### 1. Service Account Key

The key is stored in `secrets/google-service-account-key.json`. Ensure:
- File permissions are 600 (owner read/write only)
- File is not committed to git (.gitignore includes it)
- Key is rotated periodically (see [Credential Rotation](#credential-rotation))

**Known Risk:** The service account private key is stored in Terraform state. For development, this is acceptable with the following mitigations:
- Remote state bucket (GCS) has restricted access
- State bucket uses default GCS encryption
- Local key file has 0600 permissions
- Key file is gitignored

**Production Recommendation:** Migrate to Google Secret Manager or Workload Identity Federation for production deployments to avoid storing keys in state.

### 2. IAM Role: `roles/drive.admin`

The service account is granted `roles/drive.admin` at the project level. This is a broad permission but **required** due to Google Drive API limitations.

**Why `roles/drive.admin` is necessary:**
- The bot needs to create folders in shared drives
- The bot needs to manage permissions on folders it creates (add stakeholder group access)
- `roles/drive.file` only allows managing files the service account itself creates
- Creating folders in existing shared drives requires admin-level access
- Setting permissions on folders requires `drive.permissions.create` and `drive.permissions.update`

**What this grants:**
- Full access to Google Drive files and folders in the organization
- Ability to create, delete, and modify any Drive content
- Ability to manage sharing permissions on any Drive content

**Risk mitigation:**
- Service account key is protected with 0600 permissions
- Key file is never committed to version control
- Service account has no other IAM roles beyond Drive and Docs access
- All Drive API calls are logged (enable Cloud Audit Logs for production)
- Key rotation is documented and should be performed periodically

**Future improvement:** Investigate creating a custom IAM role with minimal permissions:
- `drive.files.create`
- `drive.files.delete` (on own files only)
- `drive.permissions.create`
- `drive.permissions.update`

### 3. Terraform State Security

Contains sensitive data including service account private key. Ensure:
- GCS bucket has restricted access (only CI/CD and authorized operators)
- Bucket versioning is enabled for state recovery
- Consider using Terraform Cloud for enhanced security and state encryption
- Enable Object Versioning to recover from accidental state corruption

### 4. Google Groups

Managed manually in Google Admin Console. Ensure:
- Regular membership audits (quarterly recommended)
- Principle of least privilege (users only in groups they need)
- External sharing is disabled at organization level
- Group membership changes are logged and reviewed

## Support

For issues with this Terraform configuration:

1. Check the [Troubleshooting](#troubleshooting) section
2. Review Terraform logs: `TF_LOG=DEBUG terraform apply`
3. Consult Google Cloud documentation for API-specific issues
