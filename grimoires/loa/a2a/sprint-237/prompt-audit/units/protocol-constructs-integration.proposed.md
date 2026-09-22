# Registry Integration Protocol

Protocol for loading and managing registry-installed skills in the Loa framework.

## Overview

The Registry Integration enables commercial skill distribution through the Loa Constructs registry. Skills are JWT-signed, license-validated, and loaded at runtime alongside local skills.

**Production Services:**

| Service | URL | Status |
|---------|-----|--------|
| API | `https://api.constructs.network/v1` | Live |
| Health | `https://api.constructs.network/v1/health` | Live |

**Key Principles:**
- Local skills always take precedence over registry skills
- License validation uses RS256 JWT signatures
- Offline operation supported with grace periods
- Skills load on-demand during `/setup`

## Directory Structure

```
.claude/constructs/
├── skills/
│   └── {vendor}/
│       └── {skill-slug}/
│           ├── .license.json      # JWT license token
│           ├── index.yaml         # Skill metadata
│           ├── SKILL.md           # Skill instructions
│           └── resources/         # Optional resources
├── packs/
│   └── {pack-name}/
│       ├── .license.json          # Pack license
│       ├── manifest.yaml          # Pack manifest
│       └── skills/                # Skills in pack
└── .constructs-meta.json            # Installation metadata
```

## Skill Loading Priority

Skills are discovered and loaded in priority order:

| Priority | Source | Path | License Required |
|----------|--------|------|------------------|
| 1 (highest) | Local | `.claude/skills/{name}/` | No |
| 2 | Override | `.claude/overrides/skills/{name}/` | No |
| 3 | Registry | `.claude/constructs/skills/{vendor}/{name}/` | Yes |
| 4 (lowest) | Pack | `.claude/constructs/packs/{pack}/skills/{name}/` | Yes (pack license) |

**Conflict Resolution:**
- Same-named skill: Higher priority wins, lower is ignored
- Local skill + Registry skill: Local skill loads, registry skill skipped
- No warning for conflicts (silent priority resolution)

## License Validation Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                      License Validation Flow                        │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  1. Read .license.json                                              │
│     │                                                               │
│     ├─ Missing? → EXIT_MISSING (3)                                  │
│     │                                                               │
│     ▼                                                               │
│  2. Extract JWT token                                               │
│     │                                                               │
│     ├─ Invalid JSON? → EXIT_ERROR (5)                               │
│     │                                                               │
│     ▼                                                               │
│  3. Decode JWT header → Get key_id                                  │
│     │                                                               │
│     ├─ Malformed JWT? → EXIT_INVALID (4)                            │
│     │                                                               │
│     ▼                                                               │
│  4. Fetch/cache public key for key_id                               │
│     │                                                               │
│     ├─ Network error + no cache? → EXIT_ERROR (5)                   │
│     │                                                               │
│     ▼                                                               │
│  5. Verify JWT signature (RS256)                                    │
│     │                                                               │
│     ├─ Invalid signature? → EXIT_INVALID (4)                        │
│     │                                                               │
│     ▼                                                               │
│  6. Check expiry (exp claim)                                        │
│     │                                                               │
│     ├─ Within validity? → EXIT_VALID (0)                            │
│     │                                                               │
│     ├─ Within grace period? → EXIT_GRACE (1)                        │
│     │                                                               │
│     └─ Beyond grace? → EXIT_EXPIRED (2)                             │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Grace Periods by Tier

| License Tier | Grace Period | Use Case |
|--------------|--------------|----------|
| `individual` | 24 hours | Personal use |
| `pro` | 24 hours | Professional use |
| `team` | 72 hours | Small teams |
| `enterprise` | 168 hours (7 days) | Large organizations |

### JWT Token Structure

```json
{
  "header": {
    "alg": "RS256",
    "typ": "JWT",
    "kid": "key-id-from-registry"
  },
  "payload": {
    "iss": "constructs.network",
    "sub": "vendor/skill-slug",
    "aud": "loa-framework",
    "iat": 1704067200,
    "exp": 1735689600,
    "scope": "skill:load",
    "tier": "pro",
    "features": ["advanced"]
  }
}
```

## Offline Behavior

The registry supports offline operation with these behaviors:

| Scenario | Behavior |
|----------|----------|
| Offline + Valid cached license | Skill loads normally |
| Offline + Expired (in grace) | Skill loads with warning |
| Offline + Expired (beyond grace) | Skill blocked |
| Offline + No cached key | Skill blocked (can't validate) |
| `LOA_OFFLINE=1` | Skip all network calls, use cache only |

**Key Caching:**
- Public keys cached in `~/.loa/cache/public-keys/`
- Default cache duration: 24 hours (configurable)
- Metadata stored in `{key_id}.meta.json`

## CLI Commands

### constructs-loader.sh

```bash
# List all registry skills with license status
constructs-loader.sh list

# List all registry packs with status
constructs-loader.sh list-packs

# Get paths of loadable skills (valid or grace period)
constructs-loader.sh loadable

# Validate a single skill's license
constructs-loader.sh validate <skill-dir>

# Validate a pack's license
constructs-loader.sh validate-pack <pack-dir>

# Pre-load hook for skill loading integration
constructs-loader.sh preload <skill-dir>

# List skills in a pack
constructs-loader.sh list-pack-skills <pack-dir>

# Get pack version from manifest
constructs-loader.sh get-pack-version <pack-dir>

# Check for available updates
constructs-loader.sh check-updates
```

### license-validator.sh

```bash
# Validate a license file
license-validator.sh validate <license-file> [skill-dir]

# Check license status only
license-validator.sh status <license-file>

# Refresh public key cache
license-validator.sh refresh-key <key-id>
```

## Exit Codes

| Code | Constant | Meaning |
|------|----------|---------|
| 0 | `EXIT_VALID` | License valid, skill can load |
| 1 | `EXIT_GRACE` | License expired but in grace period |
| 2 | `EXIT_EXPIRED` | License expired beyond grace period |
| 3 | `EXIT_MISSING` | License file not found |
| 4 | `EXIT_INVALID` | Invalid signature or malformed JWT |
| 5 | `EXIT_ERROR` | Other error (network, parsing, etc.) |

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `LOA_CONSTRUCTS_DIR` | `.claude/constructs` | Registry content directory |
| `LOA_CACHE_DIR` | `~/.loa/cache` | Cache directory for keys |
| `LOA_REGISTRY_URL` | `https://api.constructs.network/v1` | Registry API endpoint |
| `LOA_OFFLINE` | `0` | Set to `1` for offline-only mode |
| `LOA_OFFLINE_GRACE_HOURS` | `24` | Override default grace period |
| `LOA_REGISTRY_ENABLED` | `true` | Master toggle for registry |
| `LOA_AUTO_REFRESH_THRESHOLD_HOURS` | `24` | Refresh warning threshold |
| `NO_COLOR` | unset | Disable colored output |

## Configuration (.loa.config.yaml)

```yaml
registry:
  enabled: true                        # Master toggle
  default_url: "https://api.constructs.network/v1"
  public_key_cache_hours: 24           # Key cache duration
  load_on_startup: true                # Load skills during /setup
  validate_licenses: true              # Enable signature validation
  offline_grace_hours: 24              # Default grace period
  auto_refresh_threshold_hours: 24     # Refresh warning threshold
  check_updates_on_setup: true         # Auto-check updates
  reserved_skill_names:                # Protected names
    - "discovering-requirements"
    - "designing-architecture"
    - "planning-sprints"
    - "implementing-tasks"
    - "reviewing-code"
    - "auditing-security"
    - "deploying-infrastructure"
    - "translating-for-executives"
```

**Precedence Order:**
1. Environment variable (highest priority)
2. `.loa.config.yaml` configuration
3. Default value (lowest priority)

## Error Messages

### License Expired (Beyond Grace)

```
✗ License expired for 'vendor/skill-name'
   Expired: 3 days ago
   Grace period: 24 hours (exceeded)

   To renew: Visit https://www.constructs.network/
```

### Invalid Signature

```
✗ Invalid license signature for 'vendor/skill-name'
   The license file may be corrupted or tampered with.

   To fix: Re-download from https://www.constructs.network/
```

### Missing License

```
✗ No license found for 'vendor/skill-name'
   Registry skills require a valid license file.

   Expected: .claude/constructs/skills/vendor/skill-name/.license.json
```

### Network Error (No Cache)

```
⚠ Cannot validate 'vendor/skill-name' (offline, no cached key)
   Public key for 'key-id' not in cache.

   Connect to internet to fetch key, or wait for cached key.
```

### Grace Period Warning

```
⚠ License expiring soon for 'vendor/skill-name'
   Expires: in 12 hours

   Skill will continue to work for 24 more hours after expiry.
   To renew: Visit https://www.constructs.network/
```

## Integration with /setup

During `/setup` command execution:

1. **Skill Discovery**: Scans `.claude/constructs/skills/` for installed skills
2. **License Validation**: Validates each skill's `.license.json`
3. **Status Display**: Shows validation status with icons
4. **Loadable Skills**: Returns paths of skills that can load (valid or grace)
5. **Update Check**: Optionally checks for available updates

```bash
# Example /setup integration
loadable_skills=$(constructs-loader.sh loadable)
for skill_path in $loadable_skills; do
    # Load skill into framework
done
```

## Registry Meta File

The `.constructs-meta.json` file tracks installation state:

```json
{
  "schema_version": 1,
  "installed_skills": {
    "vendor/skill-name": {
      "version": "1.0.0",
      "installed_at": "2026-01-01T00:00:00Z",
      "registry": "default"
    }
  },
  "installed_packs": {
    "pack-name": {
      "version": "1.0.0",
      "installed_at": "2026-01-01T00:00:00Z",
      "skills": ["skill-1", "skill-2"]
    }
  },
  "last_update_check": "2026-01-02T00:00:00Z"
}
```

## Version Control (Automatic Gitignore)

**Important**: Installed constructs contain user-specific licenses and copyrighted content that should NOT be committed to version control.

The loader automatically adds `.claude/constructs/` to `.gitignore` when:
- Installing skills (`validate`)
- Installing packs (`validate-pack`)
- Running `ensure-gitignore` command explicitly

**Why constructs are gitignored:**
1. **License watermarks**: Each license contains user-specific identifiers
2. **Copyrighted content**: Skills are licensed per-user, not per-repo
3. **Team workflows**: Each developer should install with their own credentials

**Manual check:**
```bash
# Verify gitignore is configured
constructs-loader.sh ensure-gitignore

# Check if already gitignored
git check-ignore -v .claude/constructs/
```

**If accidentally committed:**
```bash
# Remove from tracking but keep local files
git rm -r --cached .claude/constructs/
git commit -m "fix: remove licensed constructs from tracking"
```

## Security Considerations

1. **Signature Verification**: All licenses use RS256 JWT signatures
2. **Key Rotation**: Public keys have expiry, cached with metadata
3. **No Secrets in Code**: API keys never stored locally
4. **Offline Grace**: Prevents lock-out during network issues
5. **Reserved Names**: Core skills cannot be overridden by registry
6. **Auto-Gitignore**: Prevents accidental commit of licensed content

## Troubleshooting

### Skill Not Loading

1. Check license status: `constructs-loader.sh validate <skill-dir>`
2. Verify file exists: `ls -la <skill-dir>/.license.json`
3. Check key cache: `ls ~/.loa/cache/public-keys/`
4. Try offline mode: `LOA_OFFLINE=1 constructs-loader.sh validate <skill-dir>`

### License Validation Fails

1. Re-download license from registry portal
2. Check system time is accurate (JWT uses timestamps)
3. Clear key cache: `rm -rf ~/.loa/cache/public-keys/*`
4. Verify network connectivity to `api.constructs.network`

### Pack Skills Not Found

1. Verify pack license: `constructs-loader.sh validate-pack <pack-dir>`
2. Check manifest: `cat <pack-dir>/manifest.yaml`
3. List pack skills: `constructs-loader.sh list-pack-skills <pack-dir>`

## Related Documents

- **PRD**: `grimoires/loa/prd.md` (FR-SCR-01, FR-SCR-02, FR-LIC-01)
- **SDD**: `grimoires/loa/sdd.md` (§5 Implementation, §9 Error Handling)
- **Scripts**: `.claude/scripts/constructs-*.sh`, `.claude/scripts/license-validator.sh`
- **Tests**: `tests/unit/test_*.bats`, `tests/integration/test_*.bats`
