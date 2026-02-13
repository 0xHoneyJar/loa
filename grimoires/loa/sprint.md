# Sprint Plan: DX Hardening — Secrets, Mount Hygiene, Review Scope

**Cycle**: cycle-008
**Issue**: https://github.com/0xHoneyJar/loa/issues/300
**PRD**: `grimoires/loa/prd.md`
**SDD**: `grimoires/loa/sdd.md`

---

## Overview

| Metric | Value |
|--------|-------|
| **Total Sprints** | 3 |
| **Total Tasks** | 21 |
| **Estimated Effort** | Medium (Python + shell + TypeScript) |
| **Dependencies** | `cryptography` Python package (Sprint 2) |

---

## Sprint 1: Lazy Interpolation + Mount Hygiene (FR-1, FR-3)

**Goal**: Fix the root cause of #300 (eager interpolation) and clean up mount hygiene for #299. These are the two P0 items with no external dependencies.

### Task 1.1: LazyValue Class in interpolation.py

**File**: `.claude/adapters/loa_cheval/config/interpolation.py`

**Description**: Create the `LazyValue` wrapper class that defers `{env:*}` token resolution until first `str()` access. Insert after `REDACTED` constant (line 25).

**Acceptance Criteria**:
- [ ] `LazyValue.__init__()` stores raw string and interpolation context
- [ ] `LazyValue.resolve()` calls `interpolate_value()` on first access, caches result
- [ ] `LazyValue.__str__()` triggers resolution
- [ ] `LazyValue.__repr__()` shows raw token, NOT resolved value
- [ ] `LazyValue.__bool__()` returns `True` if raw string is truthy
- [ ] `LazyValue.__eq__()` supports comparison with `str` and other `LazyValue`
- [ ] `LazyValue.raw` property exposes unresolved template string
- [ ] Resolution errors include provider context (which key, which provider, which agent)

### Task 1.2: Modify interpolate_config() for Lazy Paths

**File**: `.claude/adapters/loa_cheval/config/interpolation.py`

**Description**: Add `lazy_paths` parameter to `interpolate_config()`. When the current dotted key path matches a lazy path pattern (e.g., `providers.*.auth`), wrap the value in `LazyValue` instead of resolving it immediately.

**Acceptance Criteria**:
- [ ] `_DEFAULT_LAZY_PATHS = {"providers.*.auth"}` constant defined
- [ ] `interpolate_config()` accepts optional `lazy_paths` parameter (defaults to `_DEFAULT_LAZY_PATHS`)
- [ ] Recursive traversal tracks current dotted path (e.g., `providers.openai.auth`)
- [ ] Path matching supports `*` wildcard for dict key segments
- [ ] Non-matching paths still resolve eagerly (no behavior change)
- [ ] `_secret_keys` tracking still works for lazy paths (key is marked secret)
- [ ] `lazy_paths=set()` disables all lazy behavior (backward compatible)

### Task 1.3: Redaction Support for LazyValue

**Files**: `.claude/adapters/loa_cheval/config/interpolation.py`, `.claude/adapters/loa_cheval/config/redaction.py`

**Description**: Update `redact_config()` in interpolation.py and `redact_config_value()` in redaction.py to handle `LazyValue` instances without triggering resolution.

**Acceptance Criteria**:
- [ ] `redact_config()` detects `isinstance(value, LazyValue)` and returns `"***REDACTED*** (lazy: {raw})"` format
- [ ] `redact_config_value()` handles `LazyValue` similarly
- [ ] `redact_string()` handles `LazyValue` by operating on `raw` property
- [ ] `--dry-run` mode does NOT resolve any lazy values
- [ ] `cmd_print_config()` shows redacted lazy values with `(lazy)` marker

### Task 1.4: ProviderConfig Type Update

**File**: `.claude/adapters/loa_cheval/types.py`

**Description**: Update `ProviderConfig.auth` type hint to accept `str | LazyValue`. Import `LazyValue` with a conditional to avoid circular imports.

**Acceptance Criteria**:
- [ ] `ProviderConfig.auth` type hint updated to `str | Any` (or `Union[str, LazyValue]` with TYPE_CHECKING import)
- [ ] Existing code that reads `config.auth` as string works unchanged (via `LazyValue.__str__()`)
- [ ] No circular import issues

### Task 1.5: Loader Integration

**File**: `.claude/adapters/loa_cheval/config/loader.py`

**Description**: Pass `lazy_paths` parameter through `load_config()` to `interpolate_config()` at line 168.

**Acceptance Criteria**:
- [ ] `load_config()` passes `lazy_paths=_DEFAULT_LAZY_PATHS` to `interpolate_config()`
- [ ] `get_config()` caching works correctly with lazy values (cache stores LazyValues, not resolved strings)
- [ ] `get_effective_config_display()` uses redacted output for lazy values

### Task 1.6: Error Context Enhancement

**File**: `.claude/adapters/loa_cheval/config/interpolation.py`

**Description**: When `LazyValue.resolve()` fails (missing env var), produce an error message that includes the provider name, agent name, and a hint about `/loa-credentials`.

**Acceptance Criteria**:
- [ ] `LazyValue` accepts optional `context` dict (provider_name, agent_name)
- [ ] `ConfigError` message includes: which env var, which provider, which agent
- [ ] Error includes hint: `Run '/loa-credentials set <VAR>' to configure`
- [ ] Error message does NOT leak the expected value

### Task 1.7: Lazy Interpolation Tests

**File**: `.claude/adapters/tests/test_config.py`

**Description**: Add comprehensive tests for the `LazyValue` class and lazy interpolation behavior.

**Acceptance Criteria**:
- [ ] Test `LazyValue.__str__()` triggers resolution
- [ ] Test `LazyValue.__repr__()` shows raw token
- [ ] Test `LazyValue` caches resolved value (second call doesn't re-resolve)
- [ ] Test `LazyValue.__eq__()` with str and LazyValue
- [ ] Test `interpolate_config()` with `lazy_paths={"providers.*.auth"}` wraps auth fields
- [ ] Test eager fields (endpoints, aliases) still resolve immediately
- [ ] Test `lazy_paths=set()` disables lazy behavior
- [ ] Test missing env var in lazy path produces contextual error
- [ ] Test `redact_config()` handles LazyValue without resolving
- [ ] Test `model-invoke --dry-run` succeeds without any API keys set
- [ ] Test mixed lazy/eager config (some providers lazy, others resolved)
- [ ] Minimum 15 test cases

### Task 1.8: Clean Grimoire State Function

**File**: `.claude/scripts/mount-loa.sh`

**Description**: Add `clean_grimoire_state()` function that removes framework development artifacts from `grimoires/loa/` after the git checkout. Insert after line 389 (after grimoire sync in `sync_zones()`).

**Acceptance Criteria**:
- [ ] Removes: `prd.md`, `sdd.md`, `sprint.md`, `BEAUVOIR.md`, `SOUL.md` from `grimoires/loa/`
- [ ] Removes contents of `a2a/` and `archive/` directories (not the dirs themselves)
- [ ] Preserves directory structure: `a2a/trajectory/`, `archive/`, `context/`, `memory/`
- [ ] Initializes clean `ledger.json` with empty cycles, `global_sprint_counter: 0`
- [ ] Creates `NOTES.md` template if not present
- [ ] Does NOT remove user-placed files in `context/` (remount with `--force` safety)
- [ ] Called after `git checkout ... -- grimoires/loa` in `sync_zones()`
- [ ] Logged: "Grimoire state cleaned — ready for /plan-and-analyze"

### Task 1.9: Mount Hygiene Tests

**File**: `tests/unit/mount-clean.bats`

**Description**: BATS tests for the clean grimoire state functionality.

**Acceptance Criteria**:
- [ ] Test artifact removal: prd.md, sdd.md, sprint.md removed
- [ ] Test directory preservation: a2a/, archive/, context/ exist after clean
- [ ] Test clean ledger.json initialization (empty cycles, counter 0)
- [ ] Test NOTES.md template creation
- [ ] Test user files in context/ are preserved
- [ ] Test idempotent: running twice produces same result
- [ ] Test --force remount does not delete user context files
- [ ] Minimum 10 test cases

### Task 1.10: CHANGELOG and Version Bump

**Files**: `CHANGELOG.md`, `.loa-version.json`

**Description**: Add changelog entry for Sprint 1 changes. Bump patch version.

**Acceptance Criteria**:
- [ ] CHANGELOG has entry under `[Unreleased]` for lazy interpolation fix
- [ ] CHANGELOG has entry for mount hygiene cleanup
- [ ] References issues #300 and #299
- [ ] `.loa-version.json` version bumped

---

## Sprint 2: Credential Management (FR-2)

**Goal**: Build the credential provider chain and `/loa-credentials` skill. Depends on Sprint 1 for `LazyValue` and the modified interpolation pipeline.

### Task 2.1: Credential Provider Interface and Implementations

**Files**: `.claude/adapters/loa_cheval/credentials/__init__.py`, `.claude/adapters/loa_cheval/credentials/providers.py`

**Description**: Create the credential provider module with `CredentialProvider` ABC, `EnvProvider`, `DotenvProvider`, and `CompositeProvider`.

**Acceptance Criteria**:
- [ ] `CredentialProvider` ABC with `get(credential_id) -> str | None`
- [ ] `EnvProvider` reads from `os.environ`
- [ ] `DotenvProvider` reads from `.env.local` in project root (parses `KEY=VALUE` lines)
- [ ] `CompositeProvider` chains providers in priority order (env → encrypted → dotenv)
- [ ] `get_credential_provider(project_root)` factory function returns configured `CompositeProvider`
- [ ] `__init__.py` exports public API: `get_credential_provider`, `CredentialProvider`
- [ ] Providers are stateless and cheap to instantiate

### Task 2.2: Encrypted File Store

**File**: `.claude/adapters/loa_cheval/credentials/store.py`

**Description**: Fernet-encrypted credential storage at `~/.loa/credentials/`.

**Acceptance Criteria**:
- [ ] `EncryptedStore` class with `get()`, `set()`, `delete()`, `list_keys()` methods
- [ ] Auto-creates `~/.loa/credentials/` directory with 0700 permissions
- [ ] Auto-generates Fernet key on first use, stored at `.key` with 0600 permissions
- [ ] `store.json.enc` encrypted with Fernet (AES-128-CBC + HMAC)
- [ ] `store.json.enc` has 0600 permissions
- [ ] Graceful handling of corrupted store (re-initialize with warning)
- [ ] `EncryptedFileProvider(CredentialProvider)` wraps `EncryptedStore` for chain integration
- [ ] `cryptography` package imported with helpful error if missing

### Task 2.3: Credential Health Checks

**File**: `.claude/adapters/loa_cheval/credentials/health.py`

**Description**: API key health checking against provider endpoints.

**Acceptance Criteria**:
- [ ] `HEALTH_CHECKS` dict maps credential IDs to check configs (URL, header, expected status)
- [ ] `check_credential(credential_id, value) -> HealthResult` performs HTTP check
- [ ] `check_all(provider) -> list[HealthResult]` checks all configured credentials
- [ ] `HealthResult` namedtuple with `credential_id`, `status` (ok/error/missing), `message`
- [ ] Timeout of 10s per check
- [ ] Does NOT log or print credential values

### Task 2.4: Interpolation Integration

**File**: `.claude/adapters/loa_cheval/config/interpolation.py`

**Description**: Modify `_resolve_env()` (within `interpolate_value()`) to use the credential provider chain instead of raw `os.environ.get()`.

**Acceptance Criteria**:
- [ ] `_resolve_env()` calls `credential_provider.get(var_name)` first
- [ ] Falls back to `os.environ.get(var_name)` if provider returns None
- [ ] `_ENV_ALLOWLIST` check still enforced BEFORE provider lookup
- [ ] `LazyValue` resolution path uses the same provider chain
- [ ] No behavior change when credential provider module is not available (graceful import)

### Task 2.5: /loa-credentials Skill

**Files**: `.claude/skills/managing-credentials/SKILL.md`, `.claude/skills/managing-credentials/index.yaml`

**Description**: Create the `/loa-credentials` skill with interactive credential management.

**Acceptance Criteria**:
- [ ] SKILL.md defines skill workflow for `status`, `set <NAME>`, `test` subcommands
- [ ] Default invocation (no args): interactive wizard detecting missing keys
- [ ] `status`: table showing each known credential with configured/missing/valid status
- [ ] `set <NAME>`: prompts for value via AskUserQuestion (never in command args)
- [ ] `test`: runs health checks on all configured credentials
- [ ] index.yaml registered with danger_level: `safe`
- [ ] Skill invokes Python helpers via `python3 -c` or `python3 -m loa_cheval.credentials`
- [ ] Clear output formatting with green/red status indicators

### Task 2.6: .env.local Gitignore Integration

**File**: `.claude/scripts/mount-loa.sh`

**Description**: Add `.env.local` to `.gitignore` template during mount.

**Acceptance Criteria**:
- [ ] `.env.local` line added to `.gitignore` if not already present
- [ ] Added during `root_file_sync()` or equivalent mount phase
- [ ] Idempotent: running mount twice doesn't duplicate the line

### Task 2.7: Credential Provider Tests

**File**: `.claude/adapters/tests/test_credentials.py`

**Description**: Comprehensive tests for the credential provider chain.

**Acceptance Criteria**:
- [ ] Test `EnvProvider` reads from os.environ
- [ ] Test `DotenvProvider` reads from .env.local file
- [ ] Test `EncryptedFileProvider` read/write cycle
- [ ] Test `CompositeProvider` priority chain (env wins over encrypted)
- [ ] Test encrypted store file permissions (0600)
- [ ] Test encrypted store directory permissions (0700)
- [ ] Test corrupted store recovery
- [ ] Test health check with mocked HTTP responses
- [ ] Test `get_credential_provider()` factory
- [ ] Test integration with `interpolate_value()` via provider chain
- [ ] Minimum 15 test cases

### Task 2.8: CHANGELOG Update

**File**: `CHANGELOG.md`

**Description**: Add changelog entries for credential management features.

**Acceptance Criteria**:
- [ ] Entry for `/loa-credentials` command
- [ ] Entry for encrypted credential store
- [ ] Entry for credential provider chain integration
- [ ] References issue #300

---

## Sprint 3: Review Scope Filtering (FR-4)

**Goal**: Implement `.reviewignore` and shared review scope utility. Integrate with all review tools. Independent of Sprints 1-2.

### Task 3.1: review-scope.sh Shared Utility

**File**: `.claude/scripts/review-scope.sh`

**Description**: Create the shared review scope filtering utility that reads `.loa-version.json` for zone detection and `.reviewignore` for user patterns.

**Acceptance Criteria**:
- [ ] `detect_zones()` reads `.loa-version.json` for system/state/app zone definitions
- [ ] `load_reviewignore()` parses `.reviewignore` (gitignore-style: comments, blank lines, globs)
- [ ] `is_excluded()` checks file against zone exclusions + .reviewignore patterns
- [ ] `filter_files()` reads stdin, outputs only non-excluded files to stdout
- [ ] `--no-reviewignore` flag bypasses .reviewignore patterns (power user)
- [ ] `--diff-files FILE` reads file list from file instead of stdin
- [ ] Graceful when `.loa-version.json` missing (pass everything through)
- [ ] Graceful when `.reviewignore` missing (zone detection only)
- [ ] Script is executable and sources bootstrap.sh

### Task 3.2: .reviewignore Template

**File**: `.reviewignore` (project root)

**Description**: Create the default `.reviewignore` template with sane defaults for Loa-mounted projects.

**Acceptance Criteria**:
- [ ] Excludes: `.claude/`, `grimoires/loa/a2a/`, `grimoires/loa/archive/`, `.beads/`, `.run/`
- [ ] Excludes: `.loa-version.json`, `.loa.config.yaml.example`
- [ ] Has comment section for user additions
- [ ] Gitignore-compatible syntax (validated against common glob implementations)

### Task 3.3: Mount Integration for .reviewignore

**File**: `.claude/scripts/mount-loa.sh`

**Description**: Create `.reviewignore` during mount if it doesn't exist.

**Acceptance Criteria**:
- [ ] `create_reviewignore()` function creates template at project root
- [ ] Only creates if file doesn't already exist (preserves user edits)
- [ ] Called during `root_file_sync()` or `sync_zones()`
- [ ] Logged: "Created .reviewignore"

### Task 3.4: lib-content.sh Integration

**File**: `.claude/scripts/lib-content.sh`

**Description**: Integrate review-scope.sh into `prepare_content()` to filter diff files before priority-based truncation.

**Acceptance Criteria**:
- [ ] `prepare_content()` pipes diff file list through `review-scope.sh` before priority sorting
- [ ] Excluded files are counted and reported in the summary section
- [ ] `file_priority()` returns `-1` for review-scope-excluded files as a fallback
- [ ] Token budget is applied AFTER scope filtering (more tokens for in-scope files)
- [ ] Backward compatible: no `.reviewignore` → no filtering (existing behavior)

### Task 3.5: GPT Review Integration

**File**: `.claude/scripts/gpt-review-api.sh`

**Description**: Integrate review scope filtering into GPT review content preparation.

**Acceptance Criteria**:
- [ ] Content is filtered through `review-scope.sh` before building review prompt
- [ ] System zone changes detected by `detect_system_zone_changes()` still reported as info
- [ ] `--no-reviewignore` flag passthrough supported
- [ ] Filtered file count logged for debugging

### Task 3.6: Bridgebuilder Integration

**File**: `.claude/skills/bridgebuilder-review/resources/core/truncation.ts`

**Description**: Add `.reviewignore` reading support to Bridgebuilder's truncation pipeline.

**Acceptance Criteria**:
- [ ] `loadReviewIgnore()` function reads `.reviewignore` from repo root
- [ ] Patterns merged with existing `LOA_EXCLUDE_PATTERNS`
- [ ] Applied in `truncateFiles()` Step 0 (Loa-aware filtering), before Step 1 (user patterns)
- [ ] `.reviewignore` patterns use same matching as gitignore (directory trailing `/`, glob `*`)
- [ ] Graceful when file missing (existing LOA_EXCLUDE_PATTERNS still apply)

### Task 3.7: Audit-Sprint Zone Awareness

**File**: `.claude/skills/auditing-security/SKILL.md`

**Description**: Add zone-awareness instruction to the audit skill so it focuses on app zone code.

**Acceptance Criteria**:
- [ ] Instruction added: "When reviewing Loa-mounted projects, focus audit on app zone files"
- [ ] References `review-scope.sh` for determining which files are in scope
- [ ] `.reviewignore` patterns respected when selecting audit targets
- [ ] Override instruction: `--no-reviewignore` to audit everything

### Task 3.8: Review Scope Tests

**File**: `tests/unit/review-scope.bats`

**Description**: Comprehensive BATS tests for the review scope filtering utility.

**Acceptance Criteria**:
- [ ] Test zone detection from `.loa-version.json`
- [ ] Test `.reviewignore` parsing: comments, blank lines, glob patterns, directory patterns
- [ ] Test system zone exclusion (`.claude/` always excluded)
- [ ] Test state zone exclusion (`.beads/`, `.run/`)
- [ ] Test app zone passthrough (everything else passes)
- [ ] Test `--no-reviewignore` bypasses custom patterns
- [ ] Test missing `.loa-version.json` (pass everything through)
- [ ] Test missing `.reviewignore` (zone detection only)
- [ ] Test combined zone + .reviewignore filtering
- [ ] Test piping diff file list through filter
- [ ] Minimum 12 test cases

### Task 3.9: CHANGELOG and Final Version Bump

**Files**: `CHANGELOG.md`, `README.md`, `.loa-version.json`

**Description**: Add changelog entries for review scope features and finalize version bump.

**Acceptance Criteria**:
- [ ] CHANGELOG has `## [1.35.0]` entry with all Sprint 1-3 changes
- [ ] Finalize `[Unreleased]` section into versioned header
- [ ] README version badge updated
- [ ] `.loa-version.json` version set to `1.35.0`
- [ ] Why This Release section explains issues #300, #299, #303

---

## Sprint Dependencies

```
Sprint 1 (Lazy Interp + Mount) ──→ Sprint 2 (Credentials)
                                       │
Sprint 3 (Review Scope) ─── independent ┘
```

Sprint 2 depends on Sprint 1 (credential provider chain integrates with `LazyValue` + modified `interpolate_value()`). Sprint 3 is fully independent and could run in parallel with Sprint 2.

## Risk Mitigation

| Risk | Sprint | Mitigation |
|------|--------|------------|
| LazyValue breaks existing config loading | 1 | Comprehensive backward compat tests; `lazy_paths=set()` escape hatch |
| `cryptography` package not available | 2 | Graceful import with clear error message; env-only fallback |
| `.reviewignore` glob syntax inconsistency | 3 | Use bash `[[ == $pattern ]]` matching; test against gitignore spec |
| Bridgebuilder TypeScript changes conflict | 3 | Merge with existing LOA_EXCLUDE_PATTERNS; don't replace |
| Mount cleanup too aggressive | 1 | Preserve user files in `context/`; only remove known artifacts |
