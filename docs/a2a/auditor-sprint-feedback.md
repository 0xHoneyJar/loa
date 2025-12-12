# Sprint Security Audit Feedback

**Created by**: paranoid-auditor agent (via /audit-sprint)
**Read by**: sprint-task-implementer agent (via /implement)
**Date**: 2025-12-12
**Audit Status**: CHANGES_REQUIRED

---

## Audit Verdict

**Overall Status**: CHANGES_REQUIRED

**Risk Level**: HIGH

**Sprint Readiness**: NOT READY - SECURITY ISSUES FOUND

---

## Executive Summary

The Sprint 1 Terraform implementation has solid foundations but contains security gaps that must be addressed before production deployment. The primary concerns are:

1. **IAM over-permissions**: Service account granted `roles/drive.admin` at project level - too broad
2. **Secrets in state**: Service account private key stored in Terraform state
3. **Generated scripts**: Missing input validation and proper error handling

The secrets management (.gitignore, file permissions) is excellent. The architecture is well-structured. These issues are fixable without major refactoring.

---

## Critical Issues (Must Fix Before Proceeding)

### [CRITICAL-001] Service Account Key Stored in Terraform State

**Severity:** CRITICAL
**File:** `devrel-integration/terraform/modules/workspace/main.tf:87-98`

**Description:** The `google_service_account_key` resource stores the private key in Terraform state. Even with remote GCS backend, the state file contains the unencrypted private key material.

**Current Code:**
```hcl
resource "google_service_account_key" "onomancer_bot_key" {
  service_account_id = google_service_account.onomancer_bot.name
  private_key_type   = "TYPE_GOOGLE_CREDENTIALS_FILE"
}

resource "local_sensitive_file" "service_account_key" {
  content         = base64decode(google_service_account_key.onomancer_bot_key.private_key)
  filename        = "${path.root}/../secrets/google-service-account-key.json"
  file_permission = "0600"
}
```

**Impact:** If Terraform state is compromised (backup, logs, state bucket misconfiguration), attacker gains full Google Workspace access.

**Remediation:**
For Phase 1/Development, this is ACCEPTABLE with the following mitigations (already partially in place):
1. ✅ State bucket has restricted access (documented in README)
2. ✅ State bucket uses default GCS encryption
3. ✅ Local key file has 0600 permissions
4. **ADD**: Document this as known risk in README security section
5. **FUTURE**: Migrate to Google Secret Manager or Workload Identity for production

**Verdict:** ACCEPTABLE FOR DEV with documentation - not blocking

---

### [CRITICAL-002] IAM Role `roles/drive.admin` is Overly Permissive

**Severity:** HIGH (downgraded from CRITICAL after analysis)
**File:** `devrel-integration/terraform/modules/workspace/main.tf:63-69`

**Description:** Service account granted `roles/drive.admin` at PROJECT level. This role permits modifying ANY Google Drive content in the organization.

**Current Code:**
```hcl
resource "google_project_iam_member" "drive_admin" {
  project = var.project_id
  role    = "roles/drive.admin"
  member  = "serviceAccount:${google_service_account.onomancer_bot.email}"
}
```

**Impact:** Compromised service account can access/modify all Drive files in the organization.

**Analysis:** The code comment (lines 58-62) correctly explains why `roles/drive.file` is insufficient:
- Bot needs to create folders in shared drives
- Bot needs to manage permissions on folders it creates
- `roles/drive.file` only allows managing files the service account creates

**Remediation:**
1. **DOCUMENT** in README.md Security Considerations section:
   - Why `roles/drive.admin` is required
   - What permissions this grants
   - Risk mitigation (service account key protection)
2. **FUTURE** (Sprint 2+): Investigate custom IAM role with minimal permissions:
   - `drive.files.create`
   - `drive.files.delete` (on own files)
   - `drive.permissions.create`
   - `drive.permissions.update`

**Verdict:** ACCEPTABLE with documentation - Google Drive API limitations require this role

---

## High Priority Issues (Should Fix Before Production)

### [HIGH-001] Generated Scripts Missing Input Validation

**Severity:** HIGH
**Files:**
- `devrel-integration/terraform/modules/workspace/folders.tf:226-228`
- `devrel-integration/terraform/modules/workspace/permissions.tf:181`

**Description:** Generated TypeScript scripts don't validate inputs before using in API calls.

**Issue 1 - Query String Injection:**
```typescript
// folders.tf line 226 - vulnerable to special characters
let query = `name='${name}' and mimeType='application/vnd.google-apps.folder'`;
```

If folder name contains single quotes (e.g., "O'Reilly"), query breaks.

**Issue 2 - Silent Role Degradation:**
```typescript
// permissions.tf line 181 - silently defaults invalid roles
role: roleMapping[role] || 'reader'
```

Typos in permission rules silently degrade to 'reader' without warning.

**Remediation:**
1. Add escaping for folder names in Drive API queries:
```typescript
const escapedName = name.replace(/'/g, "\\'");
let query = `name='${escapedName}' and ...`;
```

2. Add validation for role values:
```typescript
if (!roleMapping[role]) {
  throw new Error(`Invalid role: ${role}. Valid roles: ${Object.keys(roleMapping).join(', ')}`);
}
```

**Verdict:** SHOULD FIX - Add input validation to generated scripts

---

### [HIGH-002] Provider Versions Not Pinned Exactly

**Severity:** MEDIUM (not HIGH - supply chain risk is theoretical)
**File:** `devrel-integration/terraform/versions.tf:12-20`

**Description:** Provider versions use `~>` range constraints allowing minor version drift.

**Current:**
```hcl
google = "~> 5.0"      # Allows 5.0-5.999
google-beta = "~> 5.0"
```

**Impact:** Minor version updates could introduce breaking changes or vulnerabilities.

**Remediation:**
```hcl
google = "= 5.27.0"    # Pin exact version
google-beta = "= 5.27.0"
```

**Verdict:** RECOMMENDED - Pin exact versions in .terraform.lock.hcl

---

### [HIGH-003] No Notification Channels for Monitoring Alerts

**Severity:** MEDIUM
**File:** `devrel-integration/terraform/modules/monitoring/main.tf:101`

**Description:** Alert policy defined but `notification_channels = []` means alerts are never sent.

**Remediation:** Add notification channel configuration or document as TODO for production setup.

**Verdict:** ACCEPTABLE FOR DEV - Document as production requirement

---

## Medium Priority Issues (Address Soon)

### [MED-001] Developers Group Has Writer Access Everywhere

**Severity:** MEDIUM
**File:** `devrel-integration/terraform/modules/workspace/permissions.tf:227-236`

**Description:** All folders get developers group with `writer` role, including Executive Summaries.

**Analysis:** This may be intentional - developers maintain all documentation. Review with stakeholders if Executive Summaries should be read-only for developers.

**Verdict:** REVIEW with stakeholders - may be intentional design

---

### [MED-002] Error Handling in Generated Scripts

**Severity:** MEDIUM
**File:** `devrel-integration/terraform/modules/workspace/permissions.tf:188-194`

**Description:** Permission errors caught but script continues. No final verification that permissions were set correctly.

**Remediation:** Add summary at end of script showing:
- Folders processed: X
- Permissions set successfully: Y
- Permissions failed: Z (with details)

**Verdict:** SHOULD FIX - Add validation summary to scripts

---

## Security Checklist Status

### Secrets & Credentials
- [✅] No hardcoded secrets in code
- [✅] Secrets loaded from environment variables
- [✅] No secrets in logs or error messages
- [✅] Proper .gitignore for secret files
- [✅] File permissions set to 0600
- [✅] Sensitive Terraform outputs marked

### IAM & Authorization
- [⚠️] Least privilege - `roles/drive.admin` broader than ideal but necessary
- [✅] No `roles/owner` or `roles/editor` on project
- [✅] Stakeholder permissions follow documented model
- [✅] Domain-wide delegation documented (not enabled)

### Terraform Security
- [✅] Remote state backend configured (GCS)
- [✅] State locking via GCS metadata
- [⚠️] Provider versions use range constraints (recommend pinning)
- [✅] No sensitive data in variable defaults
- [✅] Sensitive outputs marked

### Generated Scripts
- [⚠️] Input validation needed for special characters
- [✅] No command injection vulnerabilities
- [✅] Proper authentication via service account
- [⚠️] Error handling could be more robust

---

## Positive Findings

The implementation demonstrates strong security practices in several areas:

1. **Excellent .gitignore coverage** - Comprehensive rules for secrets, state files, credentials
2. **Proper file permissions** - 0600 on all sensitive files
3. **Good documentation** - README includes security considerations
4. **Modular architecture** - Clean separation of concerns
5. **Idempotent design** - Setup scripts check for existing folders
6. **Environment separation** - Dev/prod tfvars properly isolated

---

## Recommendations (Non-Blocking)

1. **Add to README Security Section:**
   - Document why `roles/drive.admin` is required
   - Document service account key storage approach
   - Add key rotation instructions (already partially present)

2. **For Production (Future Sprints):**
   - Consider Google Secret Manager for key storage
   - Investigate custom IAM role with minimal permissions
   - Add Cloud Audit Logs for Drive API calls
   - Implement automated key rotation

3. **Script Improvements:**
   - Add input escaping for folder names
   - Add role validation with clear error messages
   - Add summary output showing success/failure counts

---

## Next Steps

**Required Actions (2 items):**

1. **Document IAM decision in README** (15 min)
   - Add section explaining `roles/drive.admin` requirement
   - Document risk and mitigations

2. **Add input validation to generated scripts** (30 min)
   - Escape single quotes in folder names for Drive API queries
   - Validate role values before use

**After fixes:**
1. Run `/implement` to address feedback
2. Re-run `/audit-sprint` to verify fixes
3. After approval, proceed to Sprint 2

---

## Auditor Sign-off

**Auditor**: paranoid-auditor (Paranoid Cypherpunk Auditor)
**Date**: 2025-12-12
**Audit Scope**: Sprint 1 Terraform implementation security
**Verdict**: CHANGES_REQUIRED

**Note**: The issues identified are MODERATE severity. The implementation is fundamentally sound with good security practices. The required changes are documentation and minor script improvements - not architectural rework.

---

**Trust no one. Verify everything. Two items must be fixed before proceeding.**
