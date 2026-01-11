# Loa ↔ Loa Registry Integration Specification

**Version:** 1.0.0
**Status:** Ready for Implementation
**Author:** Architecture Review
**Date:** 2025-12-31

---

## Executive Summary

This specification defines how the Loa framework loads and validates skills from the Loa Skills Registry. It covers authentication, license validation, directory structure, and the handoff between the CLI plugin and framework runtime.

**Key Decisions:**
- RS256 (asymmetric) JWT signing - framework only needs public key
- Built-in skills always take precedence over registry skills
- 24-hour offline grace period (configurable by tier)
- Skills installed to `.claude/constructs/` (separate from built-in `.claude/skills/`)

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Directory Structure](#2-directory-structure)
3. [Configuration Schema](#3-configuration-schema)
4. [License Format](#4-license-format)
5. [Validation Flow](#5-validation-flow)
6. [API Changes Required](#6-api-changes-required)
7. [CLI Changes Required](#7-cli-changes-required)
8. [Framework Changes Required](#8-framework-changes-required)
9. [Security Model](#9-security-model)
10. [Error Handling](#10-error-handling)
11. [Migration Plan](#11-migration-plan)
12. [Test Plan](#12-test-plan)

---

## 1. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│  User's Project (Loa-enabled)                                   │
│                                                                 │
│  .claude/                                                       │
│  ├── skills/                    ← Built-in framework skills     │
│  ├── registry/                  ← NEW: Registry-installed       │
│  │   ├── skills/                                                │
│  │   │   └── <slug>/                                            │
│  │   │       ├── index.yaml                                     │
│  │   │       ├── SKILL.md                                       │
│  │   │       ├── resources/                                     │
│  │   │       └── .license.json  ← License file                  │
│  │   ├── packs/                                                 │
│  │   │   └── <slug>/                                            │
│  │   │       ├── manifest.json                                  │
│  │   │       └── .license.json                                  │
│  │   └── .constructs-meta.json    ← Registry state cache          │
│  ├── overrides/                 ← User customizations           │
│  └── scripts/                                                   │
│       └── registry-loader.sh    ← NEW: License validation       │
│                                                                 │
│  ~/.loa/                        ← Global config (user home)     │
│  ├── credentials.json           ← Auth tokens per registry      │
│  ├── config.json                ← Registry URLs, cache settings │
│  └── cache/                     ← Downloaded skill cache        │
│       └── skills/<slug>.tar.gz                                  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ HTTPS (authenticated)
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  Loa Registry API (api.loaskills.dev)                           │
│                                                                 │
│  GET  /v1/skills/:slug/download   ← Files + license token       │
│  POST /v1/skills/:slug/validate   ← Refresh/validate license    │
│  GET  /v1/packs/:slug/download    ← Pack files + license        │
│  GET  /v1/auth/public-key         ← NEW: RS256 public key       │
│  GET  /v1/auth/me                 ← User tier info              │
└─────────────────────────────────────────────────────────────────┘
```

### Data Flow

1. **Installation** (CLI → API → Local):
   - User runs `/loa-registry install <slug>`
   - CLI authenticates with stored credentials
   - API validates subscription tier, returns files + signed license JWT
   - CLI writes files to `.claude/constructs/skills/<slug>/`
   - CLI writes `.license.json` with JWT and metadata

2. **Runtime Loading** (Framework):
   - Loa scans `.claude/constructs/skills/` for installed skills
   - For each skill, calls `registry-loader.sh` to validate license
   - Valid licenses → skill loaded into available skills
   - Invalid/expired → skill skipped with warning

3. **License Refresh** (Background):
   - On `/setup` or when license nearing expiry
   - CLI/framework calls `POST /v1/skills/:slug/validate`
   - New license JWT written to `.license.json`

---

## 2. Directory Structure

### Project Level: `.claude/constructs/`

```
.claude/constructs/
├── skills/
│   └── {slug}/                    # e.g., "thj/terraform-assistant"
│       ├── index.yaml             # Skill metadata (standard format)
│       ├── SKILL.md               # Skill instructions
│       ├── resources/             # Templates, scripts, references
│       │   ├── templates/
│       │   └── scripts/
│       └── .license.json          # License file (hidden)
├── packs/
│   └── {slug}/                    # e.g., "gtm-collective"
│       ├── manifest.json          # Pack manifest
│       ├── skills/                # Embedded skills (if any)
│       ├── commands/              # Embedded commands (if any)
│       └── .license.json          # Pack license
└── .constructs-meta.json            # Installation metadata
```

### User Level: `~/.loa/`

```
~/.loa/
├── credentials.json               # Per-registry authentication
├── config.json                    # Global settings
└── cache/
    └── skills/
        └── {slug}-{version}.tar.gz  # Downloaded archives
```

### Why Separate from `.claude/skills/`?

1. **Clear ownership** - Framework skills vs registry skills
2. **License enforcement** - Only registry/ needs validation
3. **Update safety** - Framework updates won't touch registry skills
4. **Conflict prevention** - Built-in skills always win by path priority

---

## 3. Configuration Schema

### `~/.loa/config.json`

```json
{
  "version": "1.0.0",
  "registries": [
    {
      "name": "default",
      "url": "https://api.loaskills.dev/v1",
      "default": true
    },
    {
      "name": "enterprise",
      "url": "https://registry.company.com/v1",
      "default": false
    }
  ],
  "cache": {
    "enabled": true,
    "ttl_hours": 168,
    "max_size_mb": 500,
    "path": "~/.loa/cache"
  },
  "offline": {
    "grace_period_hours": 24
  },
  "auto_update": {
    "enabled": true,
    "check_on_setup": true,
    "check_interval_hours": 24
  }
}
```

### `~/.loa/credentials.json`

```json
{
  "default": {
    "type": "api_key",
    "key": "sk_live_abc123...",
    "user_id": "usr_uuid",
    "email": "user@example.com",
    "tier": "pro",
    "cached_at": "2025-01-15T10:00:00Z"
  },
  "enterprise": {
    "type": "oauth",
    "access_token": "eyJ...",
    "refresh_token": "eyJ...",
    "expires_at": "2025-01-20T12:00:00Z",
    "user_id": "usr_uuid",
    "tier": "enterprise"
  }
}
```

### `.claude/constructs/.constructs-meta.json`

```json
{
  "schema_version": 1,
  "installed_skills": {
    "thj/terraform-assistant": {
      "version": "1.2.0",
      "installed_at": "2025-01-15T10:00:00Z",
      "updated_at": "2025-01-20T14:30:00Z",
      "registry": "default",
      "license_expires": "2025-03-31T23:59:59Z",
      "from_pack": null
    },
    "thj/k8s-helper": {
      "version": "2.0.0",
      "installed_at": "2025-01-15T10:00:00Z",
      "registry": "default",
      "license_expires": "2025-03-31T23:59:59Z",
      "from_pack": "gtm-collective"
    }
  },
  "installed_packs": {
    "gtm-collective": {
      "version": "1.0.0",
      "installed_at": "2025-01-15T10:00:00Z",
      "registry": "default",
      "license_expires": "2025-03-31T23:59:59Z",
      "skills": ["thj/k8s-helper", "thj/ci-helper"]
    }
  },
  "last_update_check": "2025-01-20T08:00:00Z"
}
```

### `.loa.config.yaml` additions (framework config)

```yaml
# Existing config...

# NEW: Registry integration
registry:
  enabled: true
  default_url: "https://api.loaskills.dev/v1"
  public_key_cache_hours: 24
  load_on_startup: true
  validate_licenses: true
  offline_grace_hours: 24
  auto_refresh_threshold_hours: 24
  reserved_skill_names:
    - discovering-requirements
    - designing-architecture
    - planning-sprints
    - implementing-tasks
    - reviewing-code
    - auditing-security
    - deploying-infrastructure
    - riding-codebase
    - mounting-framework
    - translating-for-executives
```

---

## 4. License Format

### `.license.json` (stored per skill/pack)

```json
{
  "schema_version": 1,
  "type": "skill",
  "slug": "thj/terraform-assistant",
  "version": "1.2.0",
  "registry": "default",
  "token": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...",
  "tier": "pro",
  "watermark": "a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6",
  "issued_at": "2025-01-15T10:00:00Z",
  "expires_at": "2025-03-31T23:59:59Z",
  "offline_valid_until": "2025-04-07T23:59:59Z"
}
```

### JWT Token Payload (RS256 signed)

```json
{
  "sub": "usr_abc123",
  "skill": "thj/terraform-assistant",
  "version": "1.2.0",
  "tier": "pro",
  "watermark": "a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6",
  "lid": "lic_xyz789",
  "iss": "https://api.loaskills.dev",
  "aud": "loa-skills-client",
  "iat": 1705312800,
  "exp": 1711929599
}
```

### JWT Header

```json
{
  "alg": "RS256",
  "typ": "JWT",
  "kid": "key-2025-01"
}
```

### Offline Grace Period by Tier

| Tier | Grace Period |
|------|-------------|
| Free | 24 hours |
| Pro | 24 hours |
| Team | 72 hours (3 days) |
| Enterprise | 168 hours (7 days) |

The `offline_valid_until` is calculated as:
```
offline_valid_until = expires_at + grace_period_hours
```

---

## 5. Validation Flow

### 5.1 Runtime License Check

```
┌─────────────────────────────────────────────────────────────┐
│ Loa scans .claude/constructs/skills/ for skill directories   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
              ┌───────────────────────────────┐
              │ For each skill directory:     │
              │ Check .license.json exists    │
              └───────────────────────────────┘
                     │              │
                    NO             YES
                     │              │
                     ▼              ▼
              ┌──────────┐  ┌─────────────────────┐
              │ SKIP     │  │ Parse license file  │
              │ (orphan  │  │ Verify JWT signature│
              │  skill)  │  │ with cached pubkey  │
              └──────────┘  └─────────────────────┘
                                     │
                          ┌──────────┴──────────┐
                          │                     │
                    SIG VALID            SIG INVALID
                          │                     │
                          ▼                     ▼
              ┌─────────────────┐       ┌──────────┐
              │ Check expires_at│       │ SKIP     │
              │ vs current time │       │ (tampered│
              └─────────────────┘       └──────────┘
                     │
          ┌──────────┴──────────┐
          │                     │
     NOT EXPIRED            EXPIRED
          │                     │
          ▼                     ▼
   ┌──────────┐    ┌────────────────────────┐
   │ LOAD     │    │ Check offline_valid_   │
   │ SKILL    │    │ until vs current time  │
   └──────────┘    └────────────────────────┘
                            │
                 ┌──────────┴──────────┐
                 │                     │
           IN GRACE              PAST GRACE
                 │                     │
                 ▼                     ▼
          ┌──────────┐          ┌──────────┐
          │ LOAD +   │          │ SKIP     │
          │ WARN     │          │ (expired)│
          └──────────┘          └──────────┘
```

### 5.2 Pre-Expiry Refresh

Triggered when `expires_at < now + auto_refresh_threshold_hours`:

```
┌─────────────────────────────────────────────────────────────┐
│ License expires in < 24 hours (configurable)                │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
              ┌───────────────────────────────┐
              │ Attempt network request       │
              │ POST /v1/skills/:slug/validate│
              │ Body: { "token": "<jwt>" }    │
              └───────────────────────────────┘
                              │
               ┌──────────────┴──────────────┐
               │              │              │
           SUCCESS        REVOKED      NETWORK_ERR
               │              │              │
               ▼              ▼              ▼
        ┌──────────┐  ┌──────────┐  ┌──────────┐
        │ Update   │  │ Delete   │  │ Keep     │
        │ license  │  │ .license │  │ current  │
        │ file     │  │ + skill  │  │ (grace)  │
        └──────────┘  └──────────┘  └──────────┘
```

### 5.3 Skill Loading Priority

When Loa discovers skills, it loads in this order:

1. **Built-in skills** (`.claude/skills/`) - Always loaded, no validation
2. **User overrides** (`.claude/overrides/skills/`) - Override built-in SKILL.md
3. **Registry skills** (`.claude/constructs/skills/`) - License validation required

**Conflict Resolution:**
- If registry skill has same name as built-in → **Built-in wins, registry skipped**
- API should prevent publishing skills with reserved names
- Reserved names list maintained in `.loa.config.yaml`

---

## 6. API Changes Required

### 6.1 New Endpoint: Public Key

```
GET /v1/auth/public-key
```

**Response:**
```json
{
  "keys": [
    {
      "kid": "key-2025-01",
      "alg": "RS256",
      "use": "sig",
      "key": "-----BEGIN PUBLIC KEY-----\nMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8A...\n-----END PUBLIC KEY-----"
    }
  ],
  "active_kid": "key-2025-01"
}
```

**Notes:**
- Supports key rotation (multiple keys)
- `active_kid` indicates which key signs new tokens
- Old keys kept for validation of existing tokens
- Cache-Control: max-age=86400 (24 hours)

### 6.2 Modified: License Generation

**File:** `apps/api/src/services/license.ts`

Change from HS256 to RS256:

```typescript
// Current (HS256):
const token = await new SignJWT(payload)
  .setProtectedHeader({ alg: 'HS256' })
  .sign(new TextEncoder().encode(process.env.JWT_SECRET));

// New (RS256):
const privateKey = await importPKCS8(process.env.LICENSE_PRIVATE_KEY, 'RS256');
const token = await new SignJWT(payload)
  .setProtectedHeader({ alg: 'RS256', kid: 'key-2025-01' })
  .sign(privateKey);
```

**New Environment Variables:**
```bash
LICENSE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n..."
LICENSE_PUBLIC_KEY="-----BEGIN PUBLIC KEY-----\n..."
LICENSE_KEY_ID="key-2025-01"
```

### 6.3 Modified: Skill Download Response

**File:** `apps/api/src/routes/skills.ts`

Add `offline_valid_until` to license response:

```typescript
// In download endpoint
const graceHours = getGracePeriodHours(userTier); // 24/24/72/168
const offlineValidUntil = new Date(expiresAt.getTime() + graceHours * 3600000);

return {
  skill: { name, slug, version },
  files: [...],
  license: {
    token,
    tier,
    watermark,
    expires_at: expiresAt.toISOString(),
    offline_valid_until: offlineValidUntil.toISOString()
  }
};
```

### 6.4 New: Reserved Names Validation

**File:** `apps/api/src/routes/skills.ts`

Add to skill creation endpoint:

```typescript
const RESERVED_SKILL_NAMES = [
  'discovering-requirements',
  'designing-architecture',
  'planning-sprints',
  'implementing-tasks',
  'reviewing-code',
  'auditing-security',
  'deploying-infrastructure',
  'riding-codebase',
  'mounting-framework',
  'translating-for-executives',
];

// In POST /v1/skills
if (RESERVED_SKILL_NAMES.includes(body.name)) {
  throw new ApiError(400, 'RESERVED_NAME',
    `Skill name '${body.name}' is reserved for built-in framework skills`);
}
```

### 6.5 Modified: Validate Endpoint Response

**File:** `apps/api/src/routes/skills.ts`

Ensure validate returns refreshed license:

```typescript
// POST /v1/skills/:slug/validate
// Request: { token: string }
// Response (valid):
{
  valid: true,
  skill: "thj/terraform-assistant",
  version: "1.2.0",
  tier: "pro",
  expires_at: "2025-06-30T23:59:59Z",      // Refreshed
  offline_valid_until: "2025-07-01T23:59:59Z",
  new_token: "eyJ..."                        // NEW: refreshed JWT
}

// Response (invalid):
{
  valid: false,
  reason: "REVOKED" | "EXPIRED" | "TIER_DOWNGRADED" | "INVALID_TOKEN"
}
```

---

## 7. CLI Changes Required

### 7.1 Updated Install Paths

**File:** `packages/loa-registry/src/lib/paths.ts`

```typescript
// Old paths
export const SKILLS_DIR = '.claude/skills';
export const PACKS_DIR = '.claude/packs';

// New paths
export const CONSTRUCTS_DIR = '.claude/constructs';
export const CONSTRUCTS_SKILLS_DIR = '.claude/constructs/skills';
export const CONSTRUCTS_PACKS_DIR = '.claude/constructs/packs';
export const CONSTRUCTS_META_FILE = '.claude/constructs/.constructs-meta.json';

// User-level paths
export const LOA_HOME = path.join(os.homedir(), '.loa');
export const CREDENTIALS_FILE = path.join(LOA_HOME, 'credentials.json');
export const CONFIG_FILE = path.join(LOA_HOME, 'config.json');
export const CACHE_DIR = path.join(LOA_HOME, 'cache', 'skills');
```

### 7.2 Updated Install Command

**File:** `packages/loa-registry/src/commands/install.ts`

```typescript
// Change installation target
const skillDir = path.join(CONSTRUCTS_SKILLS_DIR, slug);

// Write license with offline_valid_until
const licenseFile: LicenseFile = {
  schema_version: 1,
  type: 'skill',
  slug,
  version,
  registry: registryName,
  token: license.token,
  tier: license.tier,
  watermark: license.watermark,
  issued_at: new Date().toISOString(),
  expires_at: license.expires_at,
  offline_valid_until: license.offline_valid_until,
};

await writeJson(path.join(skillDir, '.license.json'), licenseFile);

// Update registry-meta.json
await updateRegistryMeta('skills', slug, {
  version,
  installed_at: new Date().toISOString(),
  registry: registryName,
  license_expires: license.expires_at,
  from_pack: null,
});
```

### 7.3 New License Commands

**File:** `packages/loa-registry/src/commands/license.ts` (NEW)

```typescript
// /loa-registry license status
export async function licenseStatus(): Promise<void> {
  const skills = await getInstalledRegistrySkills();

  console.log('\nInstalled Skills License Status:\n');
  console.log('Skill                      Version   Status     Expires');
  console.log('─'.repeat(65));

  for (const skill of skills) {
    const status = await validateLicense(skill.path);
    const statusIcon = status.valid
      ? (status.gracePeriod ? '⚠️' : '✓')
      : '✗';

    console.log(`${skill.slug.padEnd(26)} ${skill.version.padEnd(9)} ${statusIcon.padEnd(10)} ${status.expiresAt || 'N/A'}`);
  }
}

// /loa-registry license refresh [slug]
export async function licenseRefresh(slug?: string): Promise<void> {
  const skills = slug
    ? [await getInstalledSkill(slug)]
    : await getInstalledRegistrySkills();

  for (const skill of skills) {
    try {
      const result = await refreshLicense(skill);
      if (result.success) {
        console.log(`✓ Refreshed: ${skill.slug}`);
      } else {
        console.log(`✗ Failed: ${skill.slug} - ${result.reason}`);
      }
    } catch (err) {
      console.log(`✗ Error: ${skill.slug} - ${err.message}`);
    }
  }
}

// /loa-registry license validate <slug>
export async function licenseValidate(slug: string): Promise<void> {
  const skill = await getInstalledSkill(slug);
  const result = await validateLicenseOnline(skill);

  console.log(`\nLicense for ${slug}:`);
  console.log(`  Valid: ${result.valid}`);
  console.log(`  Tier: ${result.tier}`);
  console.log(`  Expires: ${result.expires_at}`);
  console.log(`  Offline Until: ${result.offline_valid_until}`);

  if (!result.valid) {
    console.log(`  Reason: ${result.reason}`);
  }
}
```

### 7.4 RS256 Validation

**File:** `packages/loa-registry/src/lib/license.ts`

```typescript
import { jwtVerify, importSPKI } from 'jose';

let cachedPublicKey: CryptoKey | null = null;
let publicKeyCachedAt: number = 0;
const PUBLIC_KEY_CACHE_MS = 24 * 60 * 60 * 1000; // 24 hours

async function getPublicKey(registryUrl: string): Promise<CryptoKey> {
  const now = Date.now();
  if (cachedPublicKey && (now - publicKeyCachedAt) < PUBLIC_KEY_CACHE_MS) {
    return cachedPublicKey;
  }

  const response = await fetch(`${registryUrl}/auth/public-key`);
  const { keys, active_kid } = await response.json();
  const activeKey = keys.find(k => k.kid === active_kid);

  cachedPublicKey = await importSPKI(activeKey.key, 'RS256');
  publicKeyCachedAt = now;

  return cachedPublicKey;
}

export async function verifyLicenseToken(
  token: string,
  registryUrl: string
): Promise<LicensePayload | null> {
  try {
    const publicKey = await getPublicKey(registryUrl);
    const { payload } = await jwtVerify(token, publicKey, {
      issuer: 'https://api.loaskills.dev',
      audience: 'loa-skills-client',
    });
    return payload as LicensePayload;
  } catch (err) {
    console.error('License verification failed:', err.message);
    return null;
  }
}

export async function validateSkillLicense(skillDir: string): Promise<ValidationResult> {
  const licensePath = path.join(skillDir, '.license.json');

  // Check file exists
  if (!await fileExists(licensePath)) {
    return { valid: false, reason: 'NO_LICENSE_FILE' };
  }

  const license = await readJson<LicenseFile>(licensePath);

  // Verify JWT signature
  const registryUrl = await getRegistryUrl(license.registry);
  const payload = await verifyLicenseToken(license.token, registryUrl);

  if (!payload) {
    return { valid: false, reason: 'INVALID_SIGNATURE' };
  }

  const now = new Date();
  const expiresAt = new Date(license.expires_at);
  const offlineValidUntil = new Date(license.offline_valid_until);

  // Check if expired
  if (now < expiresAt) {
    return {
      valid: true,
      skill: license.slug,
      version: license.version,
      expiresAt: license.expires_at,
    };
  }

  // Check grace period
  if (now < offlineValidUntil) {
    return {
      valid: true,
      gracePeriod: true,
      skill: license.slug,
      version: license.version,
      expiresAt: license.expires_at,
      offlineValidUntil: license.offline_valid_until,
    };
  }

  // Expired beyond grace
  return { valid: false, reason: 'EXPIRED' };
}
```

---

## 8. Framework Changes Required

### 8.1 New Script: registry-loader.sh

**File:** `.claude/scripts/registry-loader.sh`

```bash
#!/usr/bin/env bash
# Registry skill license validation for Loa framework
# Called before loading skills from .claude/constructs/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONSTRUCTS_DIR="${SCRIPT_DIR}/../registry"
CONFIG_FILE="${HOME}/.loa/config.json"

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

# Load config
get_grace_period_hours() {
  if [[ -f "$CONFIG_FILE" ]]; then
    jq -r '.offline.grace_period_hours // 24' "$CONFIG_FILE"
  else
    echo "24"
  fi
}

# Validate a single skill license
# Returns: 0 (valid), 1 (expired), 2 (invalid), 3 (missing)
validate_skill_license() {
  local skill_dir="$1"
  local license_file="${skill_dir}/.license.json"

  # Check license file exists
  if [[ ! -f "$license_file" ]]; then
    return 3
  fi

  # Parse expiration dates
  local expires_at offline_valid_until
  expires_at=$(jq -r '.expires_at' "$license_file")
  offline_valid_until=$(jq -r '.offline_valid_until' "$license_file")

  local now expires_ts offline_ts
  now=$(date +%s)
  expires_ts=$(date -d "$expires_at" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$expires_at" +%s)
  offline_ts=$(date -d "$offline_valid_until" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$offline_valid_until" +%s)

  # Check if valid
  if [[ $now -lt $expires_ts ]]; then
    return 0  # Valid
  fi

  # Check grace period
  if [[ $now -lt $offline_ts ]]; then
    return 1  # Expired but in grace period
  fi

  return 2  # Expired beyond grace
}

# List all registry skills with status
list_registry_skills() {
  local skills_dir="${CONSTRUCTS_DIR}/skills"

  if [[ ! -d "$skills_dir" ]]; then
    echo "No registry skills installed"
    return 0
  fi

  echo "Registry Skills:"
  echo "─────────────────────────────────────────────────"

  for skill_path in "$skills_dir"/*; do
    if [[ -d "$skill_path" ]]; then
      local slug version status_icon
      slug=$(basename "$skill_path")

      if [[ -f "${skill_path}/.license.json" ]]; then
        version=$(jq -r '.version' "${skill_path}/.license.json")
      else
        version="unknown"
      fi

      validate_skill_license "$skill_path"
      case $? in
        0) status_icon="${GREEN}✓${NC}" ;;
        1) status_icon="${YELLOW}⚠${NC}" ;;
        2) status_icon="${RED}✗${NC}" ;;
        3) status_icon="${RED}?${NC}" ;;
      esac

      printf "  %b %s (%s)\n" "$status_icon" "$slug" "$version"
    fi
  done
}

# Get loadable skills (valid or in grace period)
get_loadable_skills() {
  local skills_dir="${CONSTRUCTS_DIR}/skills"
  local loadable=()

  if [[ ! -d "$skills_dir" ]]; then
    echo ""
    return 0
  fi

  for skill_path in "$skills_dir"/*; do
    if [[ -d "$skill_path" ]]; then
      validate_skill_license "$skill_path"
      local status=$?

      if [[ $status -eq 0 || $status -eq 1 ]]; then
        loadable+=("$skill_path")

        # Warn if in grace period
        if [[ $status -eq 1 ]]; then
          local slug=$(basename "$skill_path")
          echo -e "${YELLOW}⚠ Warning: License for '$slug' expired, using offline grace period${NC}" >&2
        fi
      fi
    fi
  done

  printf '%s\n' "${loadable[@]}"
}

# Pre-load hook - called by framework before loading registry skill
skill_preload_hook() {
  local skill_dir="$1"
  local slug=$(basename "$skill_dir")

  validate_skill_license "$skill_dir"
  local status=$?

  case $status in
    0)
      return 0
      ;;
    1)
      echo -e "${YELLOW}⚠ License for '$slug' expired - using offline grace period${NC}" >&2
      return 0
      ;;
    2)
      echo -e "${RED}✗ License expired for '$slug' - skill will not load${NC}" >&2
      echo "  Run '/loa-registry license refresh' to renew" >&2
      return 1
      ;;
    3)
      echo -e "${RED}✗ No license found for '$slug' - skill will not load${NC}" >&2
      echo "  Run '/loa-registry install $slug' to reinstall" >&2
      return 1
      ;;
  esac
}

# Main
case "${1:-list}" in
  list)
    list_registry_skills
    ;;
  loadable)
    get_loadable_skills
    ;;
  validate)
    if [[ -z "${2:-}" ]]; then
      echo "Usage: registry-loader.sh validate <skill-dir>"
      exit 1
    fi
    validate_skill_license "$2"
    exit $?
    ;;
  preload)
    if [[ -z "${2:-}" ]]; then
      echo "Usage: registry-loader.sh preload <skill-dir>"
      exit 1
    fi
    skill_preload_hook "$2"
    ;;
  *)
    echo "Usage: registry-loader.sh [list|loadable|validate|preload] [args]"
    exit 1
    ;;
esac
```

### 8.2 New Protocol: registry-integration.md

**File:** `.claude/protocols/registry-integration.md`

```markdown
# Registry Integration Protocol

This protocol defines how the Loa framework integrates with the Loa Skills Registry for loading licensed third-party skills.

## Overview

Registry skills are installed via the `loa-registry` CLI plugin and loaded at runtime by the Loa framework after license validation.

## Directory Structure

```
.claude/
├── skills/              # Built-in framework skills (always loaded)
├── registry/            # Registry-installed skills
│   ├── skills/          # Individual skills
│   │   └── <slug>/
│   │       ├── index.yaml
│   │       ├── SKILL.md
│   │       ├── resources/
│   │       └── .license.json
│   ├── packs/           # Installed packs
│   └── .constructs-meta.json
└── overrides/           # User customizations
```

## Skill Loading Priority

1. **Built-in skills** (`.claude/skills/`) - Always loaded, no validation
2. **User overrides** (`.claude/overrides/skills/`) - Applied to built-in skills
3. **Registry skills** (`.claude/constructs/skills/`) - Loaded after license validation

## License Validation

Before loading any registry skill:

1. Check `.license.json` exists in skill directory
2. Verify JWT signature using cached public key from registry
3. Check `expires_at` timestamp
4. If expired, check `offline_valid_until` for grace period
5. Allow loading if valid or within grace period
6. Block loading if expired beyond grace period

## Conflict Resolution

If a registry skill has the same name as a built-in skill:
- **Built-in always wins**
- Registry skill is silently skipped
- Reserved names cannot be published to registry

## Offline Behavior

When network is unavailable:
- Use cached public key for JWT verification
- Honor `offline_valid_until` grace period
- Display warning when using grace period
- Block skill when grace period exceeded

## Commands

The `loa-registry` CLI plugin provides:
- `/loa-registry install <slug>` - Install skill
- `/loa-registry license status` - Show license status
- `/loa-registry license refresh` - Refresh expiring licenses

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `LOA_REGISTRY_URL` | Registry API URL | `https://api.loaskills.dev/v1` |
| `LOA_OFFLINE_GRACE_HOURS` | Grace period override | `24` |

## Error Handling

| Condition | Behavior |
|-----------|----------|
| Missing `.license.json` | Skip skill, warn user |
| Invalid JWT signature | Skip skill, warn user |
| Expired license | Skip skill, prompt refresh |
| In grace period | Load skill, display warning |
| Reserved name conflict | Skip registry skill silently |
```

### 8.3 Updated .loa.config.yaml Schema

Add to existing schema documentation:

```yaml
# Registry integration configuration
registry:
  # Enable/disable registry skill loading
  enabled: true

  # Default registry URL
  default_url: "https://api.loaskills.dev/v1"

  # How long to cache the public key (hours)
  public_key_cache_hours: 24

  # Load registry skills on startup
  load_on_startup: true

  # Validate licenses before loading
  validate_licenses: true

  # Offline grace period (hours) - can be overridden by tier
  offline_grace_hours: 24

  # Refresh licenses this many hours before expiry
  auto_refresh_threshold_hours: 24

  # Skills that cannot be loaded from registry (conflict protection)
  reserved_skill_names:
    - discovering-requirements
    - designing-architecture
    - planning-sprints
    - implementing-tasks
    - reviewing-code
    - auditing-security
    - deploying-infrastructure
    - riding-codebase
    - mounting-framework
    - translating-for-executives
```

### 8.4 Updated CLAUDE.md

Add new section to CLAUDE.md:

```markdown
## Registry Integration

The Loa framework can load skills from the Loa Skills Registry, a SaaS marketplace for third-party AI agent skills.

### Installation

Registry skills are installed via the `loa-registry` CLI plugin:

```bash
/loa-registry login            # Authenticate
/loa-registry search "query"   # Find skills
/loa-registry install <slug>   # Install skill
```

### Directory Structure

Registry skills are installed to `.claude/constructs/skills/`, separate from built-in skills in `.claude/skills/`.

### License Validation

Each registry skill includes a `.license.json` file with a signed JWT token. The framework validates this token before loading the skill:

1. Valid license → Skill loaded normally
2. Expired but in grace period → Skill loaded with warning
3. Expired beyond grace → Skill blocked, user prompted to refresh

### Conflict Resolution

Built-in framework skills always take precedence over registry skills with the same name. This prevents malicious registry skills from hijacking core functionality.

### Configuration

Registry integration is configured in `.loa.config.yaml`:

```yaml
registry:
  enabled: true
  validate_licenses: true
  offline_grace_hours: 24
```

See `.claude/protocols/registry-integration.md` for full protocol specification.
```

---

## 9. Security Model

### 9.1 JWT Security

| Property | Value | Rationale |
|----------|-------|-----------|
| Algorithm | RS256 | Asymmetric - client only needs public key |
| Issuer | `https://api.loaskills.dev` | Verify token source |
| Audience | `loa-skills-client` | Prevent token misuse |
| Key Rotation | Supported via `kid` | Old keys kept for existing tokens |

### 9.2 Credential Storage

| File | Permissions | Contents |
|------|-------------|----------|
| `~/.loa/credentials.json` | 600 | API keys, OAuth tokens |
| `.license.json` | 644 | License JWT (signed, not secret) |

### 9.3 Watermark Tracking

Each license includes a unique `watermark`:
- Generated server-side from user ID + timestamp + random bytes
- Embedded in license JWT
- Can be embedded in downloaded skill files (comment headers)
- Enables abuse detection without intrusive DRM

### 9.4 Reserved Names

The following skill names are reserved and cannot be published to the registry:

1. `discovering-requirements`
2. `designing-architecture`
3. `planning-sprints`
4. `implementing-tasks`
5. `reviewing-code`
6. `auditing-security`
7. `deploying-infrastructure`
8. `riding-codebase`
9. `mounting-framework`
10. `translating-for-executives`

This prevents registry skills from hijacking core framework functionality.

### 9.5 Offline Grace Period

Grace periods are client-enforced (honor system):
- Prevents lock-out during travel/connectivity issues
- Server can detect abuse via usage patterns
- Tier-based duration (Free/Pro: 24h, Team: 72h, Enterprise: 168h)

---

## 10. Error Handling

### 10.1 User-Facing Messages

**Expired License:**
```
⚠️  License expired for 'thj/terraform-assistant'
   Expired: 2 days ago

   To continue using this skill:
   1. Run '/loa-registry license refresh'
   2. Or renew your subscription at loaskills.dev/billing

   Skill will be skipped during this session.
```

**Offline Grace Period:**
```
📡 Offline mode - using cached license
   License will expire in 18 hours without reconnection

   Skill 'thj/terraform-assistant' loaded successfully
```

**Tier Upgrade Required:**
```
🔒 'thj/advanced-skill' requires a Pro subscription

   Your tier: Free
   Required: Pro

   Upgrade at loaskills.dev/pricing
```

**Revoked License:**
```
🚫 License revoked for 'thj/terraform-assistant'
   Reason: Subscription cancelled

   The skill has been disabled. To re-enable:
   1. Renew subscription at loaskills.dev/billing
   2. Run '/loa-registry install thj/terraform-assistant'
```

**Invalid Signature:**
```
⚠️  License verification failed for 'thj/terraform-assistant'
   The license file may be corrupted or tampered with.

   To fix:
   1. Run '/loa-registry uninstall thj/terraform-assistant'
   2. Run '/loa-registry install thj/terraform-assistant'
```

### 10.2 Error Codes

| Code | HTTP | Description |
|------|------|-------------|
| `TIER_UPGRADE_REQUIRED` | 402 | User tier insufficient for skill |
| `LICENSE_EXPIRED` | 403 | License expired, refresh failed |
| `LICENSE_REVOKED` | 403 | License explicitly revoked |
| `INVALID_LICENSE_TOKEN` | 400 | JWT verification failed |
| `RESERVED_NAME` | 400 | Cannot publish reserved skill name |
| `SKILL_NOT_FOUND` | 404 | Skill doesn't exist in registry |

---

## 11. Migration Plan

### Phase 1: API Changes (loa-registry repo)

**Sprint 16 Tasks:**
1. Generate RS256 key pair, add to environment
2. Create `/v1/auth/public-key` endpoint
3. Modify license generation to use RS256
4. Add `offline_valid_until` to download response
5. Add reserved names validation to skill creation
6. Update tests

### Phase 2: CLI Changes (loa-registry repo)

**Sprint 17 Tasks:**
1. Update paths to use `.claude/constructs/`
2. Add RS256 verification to license validation
3. Implement `license` subcommand (status/refresh/validate)
4. Update install/update/uninstall commands
5. Add `.constructs-meta.json` management
6. Update tests

### Phase 3: Framework Changes (loa template repo - PR)

**Sprint 18 Tasks:**
1. Create `.claude/scripts/registry-loader.sh`
2. Create `.claude/protocols/registry-integration.md`
3. Update `.loa.config.yaml` schema
4. Update `CLAUDE.md` with registry documentation
5. Wire skill discovery to include registry skills
6. Test end-to-end flow

### Backward Compatibility

- Existing skills in `.claude/skills/` continue to work
- Old licenses (HS256) will fail validation → users re-install
- No data migration needed - registry is new feature

---

## 12. Test Plan

### 12.1 API Tests

```typescript
describe('License RS256', () => {
  it('signs licenses with RS256');
  it('includes kid in JWT header');
  it('validates with public key only');
});

describe('Public Key Endpoint', () => {
  it('returns active key');
  it('supports key rotation');
  it('sets cache headers');
});

describe('Reserved Names', () => {
  it('rejects creating skill with reserved name');
  it('allows non-reserved names');
});
```

### 12.2 CLI Tests

```typescript
describe('Install', () => {
  it('writes to .claude/constructs/skills/');
  it('creates .license.json with offline_valid_until');
  it('updates .constructs-meta.json');
});

describe('License Validation', () => {
  it('validates RS256 signature');
  it('returns valid for non-expired license');
  it('returns grace period for recently expired');
  it('returns invalid for old expired license');
});

describe('License Commands', () => {
  it('shows status for all installed skills');
  it('refreshes expiring licenses');
  it('validates specific skill');
});
```

### 12.3 Framework Tests

```bash
# registry-loader.sh tests
test_validate_valid_license()
test_validate_expired_license()
test_validate_grace_period()
test_validate_missing_license()
test_list_registry_skills()
test_get_loadable_skills()
test_preload_hook()
```

### 12.4 E2E Tests

```typescript
describe('Registry Integration E2E', () => {
  it('installs skill and validates license');
  it('loads skill in framework');
  it('blocks expired skill');
  it('refreshes expiring license');
  it('handles offline grace period');
  it('prevents reserved name conflicts');
});
```

---

## Appendix A: Key Pair Generation

```bash
# Generate RS256 key pair
openssl genrsa -out license-private.pem 2048
openssl rsa -in license-private.pem -pubout -out license-public.pem

# Convert to single-line for env vars
echo "LICENSE_PRIVATE_KEY=\"$(cat license-private.pem | tr '\n' '\\' | sed 's/\\/\\n/g')\""
echo "LICENSE_PUBLIC_KEY=\"$(cat license-public.pem | tr '\n' '\\' | sed 's/\\/\\n/g')\""
```

---

## Appendix B: Example License JWT

**Header:**
```json
{
  "alg": "RS256",
  "typ": "JWT",
  "kid": "key-2025-01"
}
```

**Payload:**
```json
{
  "sub": "usr_abc123def456",
  "skill": "thj/terraform-assistant",
  "version": "1.2.0",
  "tier": "pro",
  "watermark": "a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6",
  "lid": "lic_xyz789ghi012",
  "iss": "https://api.loaskills.dev",
  "aud": "loa-skills-client",
  "iat": 1705312800,
  "exp": 1711929599
}
```

**Full Token:**
```
eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6ImtleS0yMDI1LTAxIn0.eyJzdWIiOiJ1c3JfYWJjMTIzZGVmNDU2Iiwic2tpbGwiOiJ0aGovdGVycmFmb3JtLWFzc2lzdGFudCIsInZlcnNpb24iOiIxLjIuMCIsInRpZXIiOiJwcm8iLCJ3YXRlcm1hcmsiOiJhMWIyYzNkNGU1ZjZnN2g4aTlqMGsxbDJtM240bzVwNiIsImxpZCI6ImxpY194eXo3ODlnaGkwMTIiLCJpc3MiOiJodHRwczovL2FwaS5sb2Fza2lsbHMuZGV2IiwiYXVkIjoibG9hLXNraWxscy1jbGllbnQiLCJpYXQiOjE3MDUzMTI4MDAsImV4cCI6MTcxMTkyOTU5OX0.SIGNATURE
```
