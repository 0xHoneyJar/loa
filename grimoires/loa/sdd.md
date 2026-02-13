# SDD: DX Hardening — Secrets Management, Mount Hygiene, Review Scope

**Version**: 1.0.0
**Status**: Draft
**Cycle**: cycle-008
**PRD Reference**: grimoires/loa/prd.md

## 1. System Architecture Overview

This cycle modifies four subsystems with minimal blast radius:

```
┌─────────────────────────────────────────────────────┐
│ FR-1: Lazy Interpolation                            │
│   interpolation.py → loader.py → adapter auth       │
├─────────────────────────────────────────────────────┤
│ FR-2: Credential Management                         │
│   /loa-credentials skill → credential providers     │
│   → interpolation.py integration                    │
├─────────────────────────────────────────────────────┤
│ FR-3: Mount Hygiene                                 │
│   mount-loa.sh → post-checkout cleanup              │
├─────────────────────────────────────────────────────┤
│ FR-4: Review Scope                                  │
│   .reviewignore → lib-content.sh → review tools     │
└─────────────────────────────────────────────────────┘
```

## 2. Component Design

### 2.1 Lazy Config Interpolation (FR-1)

**Problem**: `interpolation.py:interpolate_config()` eagerly resolves ALL `{env:*}` tokens at config load time. When only one provider is needed, missing env vars for OTHER providers cause `ConfigError`.

**Design**: Selective lazy interpolation — auth fields under `providers.*` are deferred until the specific provider is invoked.

#### 2.1.1 LazyValue Wrapper

New class in `interpolation.py`:

```python
class LazyValue:
    """Deferred interpolation token. Resolved on first str() access."""

    def __init__(self, raw: str, project_root: str,
                 extra_env_patterns=(), allowed_file_dirs=(),
                 commands_enabled=False):
        self._raw = raw
        self._project_root = project_root
        self._extra_env_patterns = extra_env_patterns
        self._allowed_file_dirs = allowed_file_dirs
        self._commands_enabled = commands_enabled
        self._resolved: str | None = None

    def resolve(self) -> str:
        if self._resolved is None:
            self._resolved = interpolate_value(
                self._raw, self._project_root,
                self._extra_env_patterns, self._allowed_file_dirs,
                self._commands_enabled
            )
        return self._resolved

    @property
    def raw(self) -> str:
        return self._raw

    def __str__(self) -> str:
        return self.resolve()

    def __repr__(self) -> str:
        return f"LazyValue({self._raw!r})"

    def __bool__(self) -> bool:
        return bool(self._raw)

    def __eq__(self, other) -> bool:
        if isinstance(other, str):
            return self.resolve() == other
        if isinstance(other, LazyValue):
            return self._raw == other._raw
        return NotImplemented
```

#### 2.1.2 Modified interpolate_config()

Add `lazy_paths` parameter — a set of dotted key prefixes where interpolation is deferred:

```python
_DEFAULT_LAZY_PATHS = {"providers.*.auth"}

def interpolate_config(config, project_root, ...,
                       lazy_paths=None) -> Dict[str, Any]:
    if lazy_paths is None:
        lazy_paths = _DEFAULT_LAZY_PATHS
    # When key matches a lazy_path pattern, wrap in LazyValue
    # instead of calling interpolate_value()
```

**Key insight**: Only `providers.*.auth` fields need lazy treatment. All other fields (endpoints, model names, aliases) are safe to resolve eagerly because they don't depend on secrets.

#### 2.1.3 Adapter Integration

In `_build_provider_config()` (cheval.py), the `auth` field is already extracted as a string. With `LazyValue`, it becomes:

```python
# No change needed in _build_provider_config — ProviderConfig.auth
# accepts LazyValue since LazyValue.__str__() triggers resolution.
# The adapter's _get_auth_header() calls str() which resolves.
```

The only change needed: ensure `ProviderConfig.auth` type hint accepts `str | LazyValue`.

#### 2.1.4 Error Messaging

When lazy resolution fails, the error should be specific:

```
ConfigError: Environment variable 'OPENAI_API_KEY' is not set.
  Required by: provider 'openai' (auth field)
  Agent: gpt-reviewer
  Hint: Run '/loa-credentials set OPENAI_API_KEY' to configure.
```

#### 2.1.5 Redaction Support

`redact_config()` must handle LazyValue without resolving:

```python
if isinstance(value, LazyValue):
    return f"***REDACTED*** (from {value.raw})"
```

#### 2.1.6 Files Modified

| File | Change |
|------|--------|
| `.claude/adapters/loa_cheval/config/interpolation.py` | Add `LazyValue` class, modify `interpolate_config()` |
| `.claude/adapters/loa_cheval/config/loader.py` | Pass `lazy_paths` to `interpolate_config()` |
| `.claude/adapters/loa_cheval/config/redaction.py` | Handle `LazyValue` in `redact_config()` |
| `.claude/adapters/loa_cheval/types.py` | Update `ProviderConfig.auth` type hint |
| `.claude/adapters/tests/test_config.py` | Add lazy interpolation tests |

### 2.2 Credential Management (FR-2)

#### 2.2.1 Credential Provider Chain

New module: `.claude/adapters/loa_cheval/credentials/`

```
loa_cheval/credentials/
├── __init__.py          # Public API
├── providers.py         # Provider implementations
├── store.py             # Encrypted file store
└── health.py            # API key health checking
```

**Provider interface**:

```python
class CredentialProvider(ABC):
    @abstractmethod
    def get(self, credential_id: str) -> str | None: ...

class EnvProvider(CredentialProvider):
    """Reads from os.environ. Highest priority."""

class EncryptedFileProvider(CredentialProvider):
    """Reads from ~/.loa/credentials/store.json.enc"""

class DotenvProvider(CredentialProvider):
    """Reads from .env.local in project root."""

class CompositeProvider(CredentialProvider):
    """Chains providers in priority order."""
    def __init__(self, *providers: CredentialProvider): ...
    def get(self, credential_id: str) -> str | None:
        for p in self.providers:
            val = p.get(credential_id)
            if val is not None:
                return val
        return None
```

#### 2.2.2 Encrypted Store

```python
# store.py
import json
from pathlib import Path
from cryptography.fernet import Fernet

STORE_DIR = Path.home() / ".loa" / "credentials"
STORE_FILE = STORE_DIR / "store.json.enc"
KEY_FILE = STORE_DIR / ".key"

class EncryptedStore:
    def __init__(self):
        self._ensure_dir()
        self._fernet = self._load_or_create_key()

    def get(self, credential_id: str) -> str | None:
        data = self._load()
        return data.get(credential_id)

    def set(self, credential_id: str, value: str) -> None:
        data = self._load()
        data[credential_id] = value
        self._save(data)

    def list_keys(self) -> list[str]:
        return list(self._load().keys())

    def _ensure_dir(self):
        STORE_DIR.mkdir(parents=True, exist_ok=True)
        STORE_DIR.chmod(0o700)

    def _load_or_create_key(self) -> Fernet:
        if KEY_FILE.exists():
            key = KEY_FILE.read_bytes()
        else:
            key = Fernet.generate_key()
            KEY_FILE.write_bytes(key)
            KEY_FILE.chmod(0o600)
        return Fernet(key)

    def _load(self) -> dict:
        if not STORE_FILE.exists():
            return {}
        encrypted = STORE_FILE.read_bytes()
        return json.loads(self._fernet.decrypt(encrypted))

    def _save(self, data: dict) -> None:
        encrypted = self._fernet.encrypt(json.dumps(data).encode())
        STORE_FILE.write_bytes(encrypted)
        STORE_FILE.chmod(0o600)
```

#### 2.2.3 Health Check

```python
# health.py
HEALTH_CHECKS = {
    "OPENAI_API_KEY": {
        "url": "https://api.openai.com/v1/models",
        "header": "Authorization: Bearer {key}",
        "expect_status": 200,
    },
    "ANTHROPIC_API_KEY": {
        "url": "https://api.anthropic.com/v1/messages",
        "method": "POST",
        "header": "x-api-key: {key}",
        "expect_status": [200, 400],  # 400 = valid key, bad request body
    },
}
```

#### 2.2.4 Integration with interpolation.py

Modify `_resolve_env()` in `interpolation.py` to use the credential provider chain:

```python
# Before (eager, os.environ only):
value = os.environ.get(var_name)

# After (provider chain):
from loa_cheval.credentials import get_credential_provider
provider = get_credential_provider(project_root)
value = provider.get(var_name)
# Falls back to os.environ if provider returns None
```

#### 2.2.5 /loa-credentials Skill

New skill at `.claude/skills/managing-credentials/SKILL.md`:

| Command | Action |
|---------|--------|
| `/loa-credentials` | Interactive wizard: detects missing keys, prompts to set |
| `/loa-credentials status` | Table of all known credentials with configured/missing status |
| `/loa-credentials set <NAME>` | Prompts for value (never in command args), stores encrypted |
| `/loa-credentials test` | Health-checks each configured credential against its API |

The skill invokes Python helpers from `loa_cheval/credentials/` via `python3 -c` calls.

#### 2.2.6 Files Created/Modified

| File | Change |
|------|--------|
| `.claude/adapters/loa_cheval/credentials/__init__.py` | New — public API |
| `.claude/adapters/loa_cheval/credentials/providers.py` | New — provider implementations |
| `.claude/adapters/loa_cheval/credentials/store.py` | New — encrypted file store |
| `.claude/adapters/loa_cheval/credentials/health.py` | New — API health checks |
| `.claude/adapters/loa_cheval/config/interpolation.py` | Modified — use credential provider chain |
| `.claude/skills/managing-credentials/SKILL.md` | New — skill definition |
| `.claude/skills/managing-credentials/index.yaml` | New — skill metadata |
| `.claude/adapters/tests/test_credentials.py` | New — credential provider tests |

### 2.3 Clean Mount Grimoire Initialization (FR-3)

#### 2.3.1 Design

Add a `clean_grimoire_state()` function in `mount-loa.sh` that runs AFTER the `git checkout` of `grimoires/loa/` from upstream. This removes framework development artifacts while preserving structural files.

#### 2.3.2 Implementation

```bash
# mount-loa.sh — new function after sync_zones()
clean_grimoire_state() {
  local grimoire_dir="${TARGET_DIR}/grimoires/loa"

  # Remove framework development artifacts
  local artifacts=(
    "prd.md" "sdd.md" "sprint.md" "ledger.json"
    "BEAUVOIR.md" "SOUL.md"
  )
  for artifact in "${artifacts[@]}"; do
    rm -f "${grimoire_dir}/${artifact}"
  done

  # Remove framework a2a and archive directories (contents only)
  rm -rf "${grimoire_dir}/a2a/"*
  rm -rf "${grimoire_dir}/archive/"*

  # Preserve directory structure
  mkdir -p "${grimoire_dir}/a2a/trajectory"
  mkdir -p "${grimoire_dir}/archive"
  mkdir -p "${grimoire_dir}/context"
  mkdir -p "${grimoire_dir}/memory"

  # Initialize clean ledger
  cat > "${grimoire_dir}/ledger.json" << 'LEDGER_EOF'
{
  "version": "1.0.0",
  "cycles": [],
  "active_cycle": null,
  "active_bugfix": null,
  "global_sprint_counter": 0,
  "bugfix_cycles": []
}
LEDGER_EOF

  # Create NOTES.md template if missing
  if [[ ! -f "${grimoire_dir}/NOTES.md" ]]; then
    cat > "${grimoire_dir}/NOTES.md" << 'NOTES_EOF'
# Project Notes

## Learnings

## Blockers

## Observations
NOTES_EOF
  fi

  log "Grimoire state cleaned — ready for /plan-and-analyze"
}
```

#### 2.3.3 Call Site

In `sync_zones()`, after the grimoire git checkout:

```bash
# Existing (line 382):
git checkout "$LOA_REMOTE_NAME/$LOA_BRANCH" -- grimoires/loa 2>/dev/null || { ... }

# Add after:
clean_grimoire_state
```

#### 2.3.4 Remount Safety

When `--force` is used, the clean function only removes files that match known framework artifact patterns. User-created files in `context/` are preserved.

#### 2.3.5 Files Modified

| File | Change |
|------|--------|
| `.claude/scripts/mount-loa.sh` | Add `clean_grimoire_state()`, call after grimoire sync |

### 2.4 Review Scope Filtering with .reviewignore (FR-4)

#### 2.4.1 Architecture

Two-layer filtering with a shared utility:

```
Layer 1: Zone auto-detection (from .loa-version.json)
  → System zone excluded by default
  → State zone excluded unless user-modified in PR

Layer 2: .reviewignore file (user-customizable)
  → Gitignore-style glob patterns
  → Auto-populated by /mount
  → Applied additively on top of Layer 1
```

**Shared utility**: `.claude/scripts/review-scope.sh`

```bash
# review-scope.sh — Shared review scope filtering utility
# Usage: review-scope.sh [--diff-files FILE_LIST] [--no-reviewignore]
# Output: Filtered file list to stdout (one per line)
#
# Reads:
#   .loa-version.json — for zone detection
#   .reviewignore — for user patterns
#
# Filters:
#   1. Zone auto-detection: system zone excluded
#   2. .reviewignore patterns: user exclusions applied
#   3. Output: remaining files (app zone + user-modified state zone)
```

#### 2.4.2 review-scope.sh Design

```bash
#!/usr/bin/env bash
# review-scope.sh — Review scope filtering
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/bootstrap.sh"

# Parse .loa-version.json for zone definitions
detect_zones() {
  local version_file="${PROJECT_ROOT}/.loa-version.json"
  if [[ ! -f "$version_file" ]]; then
    return 1  # Not a Loa project
  fi

  SYSTEM_ZONE=$(jq -r '.zones.system // ".claude"' "$version_file")
  STATE_ZONES=$(jq -r '.zones.state[]? // empty' "$version_file")
  # App zone is everything else
}

# Parse .reviewignore patterns
load_reviewignore() {
  local ignore_file="${PROJECT_ROOT}/.reviewignore"
  IGNORE_PATTERNS=()
  if [[ -f "$ignore_file" ]]; then
    while IFS= read -r line; do
      # Skip comments and blank lines
      [[ -z "$line" || "$line" =~ ^# ]] && continue
      IGNORE_PATTERNS+=("$line")
    done < "$ignore_file"
  fi
}

# Check if file matches any ignore pattern
is_excluded() {
  local file="$1"

  # Layer 1: Zone auto-detection
  if [[ "$file" == "${SYSTEM_ZONE}/"* ]]; then
    return 0  # Excluded
  fi

  # Layer 2: .reviewignore patterns
  for pattern in "${IGNORE_PATTERNS[@]}"; do
    # Handle directory patterns (trailing /)
    if [[ "$pattern" == */ ]]; then
      [[ "$file" == "${pattern}"* ]] && return 0
    fi
    # Handle glob patterns
    # Use bash pattern matching for simple cases
    if [[ "$file" == $pattern ]]; then
      return 0
    fi
  done

  return 1  # Not excluded
}

# Main: filter file list
filter_files() {
  detect_zones || return 0  # Not Loa — pass everything through
  load_reviewignore

  while IFS= read -r file; do
    if ! is_excluded "$file"; then
      echo "$file"
    fi
  done
}
```

#### 2.4.3 .reviewignore Template

Created during `/mount`:

```gitignore
# Review scope exclusions (auto-generated by Loa)
# Edit to customize which files review tools examine

# Framework system zone
.claude/

# Process artifacts
grimoires/loa/a2a/
grimoires/loa/archive/
.beads/
.run/

# Config (Loa-managed)
.loa-version.json
.loa.config.yaml.example

# User additions below
```

#### 2.4.4 Integration with Existing Review Tools

**GPT review (`gpt-review-api.sh`)**:
- In `prepare_content()` (from `lib-content.sh`), pipe diff file list through `review-scope.sh`:

```bash
# Before building review content
FILTERED_FILES=$(echo "$DIFF_FILES" | review-scope.sh)
```

Alternatively, modify `file_priority()` in `lib-content.sh` to return priority `-1` (skip) for excluded files, and modify `prepare_content()` to drop `-1` priority files entirely.

**Bridgebuilder**:
- Already has `LOA_EXCLUDE_PATTERNS` in `truncation.ts` — add `.reviewignore` reading support
- Read `.reviewignore` from repo root and merge patterns with `LOA_EXCLUDE_PATTERNS`

**Audit-sprint**:
- Add zone-awareness instruction to SKILL.md: "When reviewing Loa-mounted projects, focus audit on app zone files. Use `review-scope.sh` to determine which files are in scope."

#### 2.4.5 Mount Integration

Add `.reviewignore` creation to `mount-loa.sh`:

```bash
# In sync_zones() or root_file_sync()
create_reviewignore() {
  local ignore_file="${TARGET_DIR}/.reviewignore"
  if [[ ! -f "$ignore_file" ]]; then
    cat > "$ignore_file" << 'REVIEWIGNORE_EOF'
# Review scope exclusions (auto-generated by Loa)
.claude/
grimoires/loa/a2a/
grimoires/loa/archive/
.beads/
.run/
.loa-version.json
.loa.config.yaml.example
REVIEWIGNORE_EOF
    log "Created .reviewignore"
  fi
}
```

#### 2.4.6 Files Created/Modified

| File | Change |
|------|--------|
| `.claude/scripts/review-scope.sh` | New — shared review scope filtering utility |
| `.claude/scripts/lib-content.sh` | Modified — integrate review-scope.sh for filtering |
| `.claude/scripts/mount-loa.sh` | Modified — create `.reviewignore` during mount |
| `.claude/skills/auditing-security/SKILL.md` | Modified — add zone-awareness instruction |
| `.claude/skills/bridgebuilder-review/resources/core/truncation.ts` | Modified — read `.reviewignore` |
| `.reviewignore` | New template file |

## 3. Data Flow

### 3.1 Credential Resolution (Lazy Path)

```
Config load (loader.py)
  ├─ Layer 1-4 merge → merged config
  ├─ interpolate_config(lazy_paths={"providers.*.auth"})
  │   ├─ Non-auth fields: resolve eagerly (endpoints, aliases)
  │   └─ Auth fields: wrap in LazyValue("{env:OPENAI_API_KEY}")
  └─ Cache merged config with LazyValues

Agent invocation (cheval.py)
  ├─ resolve_execution("gpt-reviewer") → (binding, resolved_model)
  ├─ resolved_model.provider = "openai"
  ├─ _build_provider_config("openai")
  │   └─ ProviderConfig(auth=LazyValue("{env:OPENAI_API_KEY}"))
  ├─ get_adapter(provider_config)
  └─ adapter._get_auth_header()
      └─ str(self.config.auth) → LazyValue.resolve()
          └─ credential_provider.get("OPENAI_API_KEY")
              ├─ Try: os.environ["OPENAI_API_KEY"]
              ├─ Try: ~/.loa/credentials/store.json.enc
              └─ Try: .env.local
```

### 3.2 Review Scope Pipeline

```
Diff generated (git diff / PR files)
  ├─ review-scope.sh
  │   ├─ Layer 1: detect_zones() from .loa-version.json
  │   │   └─ Exclude: .claude/** (system zone)
  │   └─ Layer 2: load_reviewignore()
  │       └─ Exclude: .reviewignore patterns
  ├─ Filtered file list
  └─ Passed to review tool:
      ├─ gpt-review: lib-content.sh prepare_content()
      ├─ bridgebuilder: truncation.ts truncateFiles()
      └─ audit-sprint: zone-aware focus instruction
```

## 4. Testing Strategy

### 4.1 Unit Tests

| Test File | Coverage |
|-----------|----------|
| `tests/test_config.py` | LazyValue class, lazy interpolation paths, mixed eager/lazy |
| `tests/test_credentials.py` | Provider chain, encrypted store, dotenv loading, composite |
| `tests/unit/review-scope.bats` | Zone detection, .reviewignore parsing, file filtering |
| `tests/unit/mount-clean.bats` | Clean grimoire initialization, artifact removal, preservation |

### 4.2 Integration Tests

| Test | Validates |
|------|-----------|
| `model-invoke --agent gpt-reviewer --dry-run` with only OPENAI_API_KEY | Lazy interpolation doesn't fail on missing ANTHROPIC_API_KEY |
| `model-invoke --agent opus --dry-run` with only ANTHROPIC_API_KEY | Symmetric lazy test |
| `/loa-credentials set + model-invoke` | Credential store integration |
| Fresh mount + `/plan` | No stale artifacts, starts clean |
| GPT review on Loa-mounted repo | System zone excluded from review |

### 4.3 Backward Compatibility Tests

| Test | Validates |
|------|-----------|
| All env vars set + config load | No behavior change (eager path still works) |
| No `.reviewignore` file | Zone auto-detection still filters |
| Existing mounts without `.reviewignore` | Graceful degradation |

## 5. Security Considerations

- **Encryption key**: Auto-generated Fernet key at `~/.loa/credentials/.key` with 0600 permissions
- **Store file**: `store.json.enc` with 0600 permissions, never committed to git
- **Credential input**: Always via interactive prompt (never in command arguments)
- **Redaction**: `LazyValue.raw` used for redaction display, never the resolved value
- **Allowlist**: `_ENV_ALLOWLIST` in interpolation.py still enforced — credential providers cannot bypass it
- **.env.local**: Added to `.gitignore` template during mount
- **No secrets in logs**: `LazyValue.__repr__()` shows raw token, not resolved value

## 6. Sprint Decomposition Guidance

| Sprint | Focus | Dependencies |
|--------|-------|-------------|
| Sprint 1 | FR-1 (lazy interpolation) + FR-3 (mount cleanup) | None — independent, highest priority |
| Sprint 2 | FR-2 (credential management) | FR-1 (uses LazyValue + provider chain) |
| Sprint 3 | FR-4 (review scope) | None — independent |

Sprint 1 and Sprint 3 are independent and could theoretically run in parallel. Sprint 2 depends on Sprint 1 for the lazy interpolation infrastructure.
