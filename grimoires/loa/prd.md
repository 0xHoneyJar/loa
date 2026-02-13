# PRD: DX Hardening — Secrets Management, Mount Hygiene, Review Scope

**Version**: 1.0.0
**Status**: Draft
**Author**: Discovery Phase (plan-and-analyze)
**Cycle**: cycle-008
**Issues**: #300, #299, #303

## 1. Problem Statement

Three user-facing DX issues compound to degrade the experience for developers adopting Loa on new projects:

1. **Secrets Management Gap (#300)**: cheval.py eagerly resolves ALL `{env:*}` config interpolations at load time, even for providers not needed by the current operation. A GPT review (`/gpt-review`) fails if `ANTHROPIC_API_KEY` is missing, even though only `OPENAI_API_KEY` is needed. Beyond the bug, there is no centralized credential management — users must manually export env vars, with no validation, no secure storage, and no integration path to future platform infrastructure (indra/arrakis).

2. **Mount Hygiene (#299)**: `mount-loa.sh:380-389` runs `git checkout "$LOA_REMOTE_NAME/$LOA_BRANCH" -- grimoires/loa` which copies the framework's own development cycle artifacts (PRD, SDD, sprint.md, ledger.json referencing upstream issues) into fresh user projects. This causes `/plan` to report "planning complete" and `/build` to attempt implementing Loa's own framework tasks.

3. **Review Scope (#303)**: Review tools (Bridgebuilder, `/gpt-review`, `/audit-sprint`) process system zone files (`.claude/`, Loa framework code) alongside user application code. While Bridgebuilder has a Loa-aware filtering system (`truncation.ts:156-163`), it may not be enabled or working correctly for all review paths. GPT review and audit-sprint lack equivalent filtering. This wastes significant tokens on code the user doesn't own.

> Sources: Issue #300 (feedback submission), Issue #299 (feedback submission), Issue #303 (feedback submission), hive credential pattern analysis

## 2. Goals & Success Metrics

### Primary Goals

| Goal | Metric | Target |
|------|--------|--------|
| Credential management works out of the box | `/gpt-review` succeeds with only the needed API key set | 100% |
| Fresh mounts start clean | `/plan` on freshly mounted project says "no PRD found" | 100% |
| Review tools focus on user code | System zone files excluded from review diff | >95% token reduction on framework files |

### Secondary Goals

| Goal | Metric |
|------|--------|
| Credential interface ready for indra/arrakis integration | Provider abstraction supports pluggable backends |
| User can customize review exclusions | `.reviewignore` file respected by all review tools |
| Zero regression in existing workflows | All existing tests pass |

## 3. User & Stakeholder Context

### Primary Persona: Downstream Developer

A developer who has installed Loa via `/mount` onto their own project repo. They:
- Expect `/plan` to start fresh discovery for THEIR project
- Expect review tools to review THEIR code changes, not Loa framework internals
- Want to supply API keys once and have them work across all tools
- May not be deeply familiar with Loa internals or the Three-Zone Model

### Secondary Persona: Power User / Framework Developer

A developer who works on Loa itself or customizes it extensively. They:
- May want to review system zone changes in Loa's own PRs
- Need the ability to override exclusion defaults
- May integrate with indra/arrakis platform infrastructure

## 4. Functional Requirements

### FR-1: Lazy Config Interpolation (Fix #300 Root Cause)

**Current behavior**: `interpolation.py:112-138` uses `_INTERP_RE.sub(_replace, value)` which eagerly resolves ALL `{env:*}` tokens at config load time.

**Required behavior**: Only resolve `{env:*}` tokens for the provider/agent actually being invoked. Two-phase interpolation:
1. **Phase 1 (load time)**: Parse config but leave `{env:*}` tokens as-is
2. **Phase 2 (invocation time)**: Resolve only the tokens needed for the resolved provider

**Acceptance criteria**:
- `model-invoke --agent gpt-reviewer` succeeds with only `OPENAI_API_KEY` set (no `ANTHROPIC_API_KEY`)
- `model-invoke --agent opus` succeeds with only `ANTHROPIC_API_KEY` set
- `--dry-run` mode does NOT require any API keys
- Existing tests in `tests/test_config.py` updated to cover lazy resolution
- Error messages clearly state WHICH key is missing for WHICH provider

### FR-2: Credential Management Command (`/loa-credentials`)

A new skill that provides interactive credential setup, validation, and secure local storage.

**Subcommands**:

| Command | Description |
|---------|-------------|
| `/loa-credentials` | Interactive setup wizard — prompts for each missing key |
| `/loa-credentials status` | Show which credentials are configured, which are missing |
| `/loa-credentials set <name>` | Set a specific credential (prompted, not in command args) |
| `/loa-credentials test` | Health-check all configured credentials against their APIs |

**Storage architecture** (inspired by hive pattern, simplified):

```
~/.loa/credentials/
├── store.json.enc    # Fernet-encrypted credential store
└── .key              # Encryption key (0600 permissions)
```

**Retrieval priority** (CompositeStorage pattern from hive):
1. Process environment variable (highest priority — CI/CD, explicit export)
2. Encrypted local store (`~/.loa/credentials/`)
3. `.env.local` in project root (convenience for local dev)

**Provider abstraction**:
```python
class CredentialProvider(ABC):
    @abstractmethod
    def get(self, credential_id: str) -> str | None: ...
    @abstractmethod
    def set(self, credential_id: str, value: str) -> None: ...
    @abstractmethod
    def health_check(self, credential_id: str) -> bool: ...
```

Concrete implementations:
- `EnvProvider` — reads from `os.environ`
- `EncryptedFileProvider` — reads from `~/.loa/credentials/store.json.enc`
- `DotenvProvider` — reads from `.env.local`
- (Future) `IndraProvider` — delegates to indra/arrakis platform

**Integration with cheval.py**:
- `interpolation.py` uses the credential provider chain instead of raw `os.environ.get()`
- Allowlist (`_ENV_ALLOWLIST`) still applies for security
- Template syntax unchanged: `{env:OPENAI_API_KEY}` — but resolution goes through provider chain

**Acceptance criteria**:
- `/loa-credentials` prompts for OPENAI_API_KEY, ANTHROPIC_API_KEY
- `/loa-credentials status` shows green/red per credential
- `/loa-credentials test` validates keys against actual API endpoints
- Encrypted store created at `~/.loa/credentials/` with 0600 permissions
- cheval.py resolves credentials from the provider chain
- Plain text secrets never appear in command output or logs

### FR-3: Clean Mount Grimoire Initialization (#299)

**Current behavior**: `mount-loa.sh:382` runs `git checkout "$LOA_REMOTE_NAME/$LOA_BRANCH" -- grimoires/loa` which pulls all grimoire content from upstream, including framework development artifacts.

**Required behavior**: Mount initializes a clean grimoire template without upstream development state.

**Implementation**:
1. After `git checkout`, remove framework development artifacts:
   - `grimoires/loa/prd.md`
   - `grimoires/loa/sdd.md`
   - `grimoires/loa/sprint.md`
   - `grimoires/loa/ledger.json`
   - `grimoires/loa/a2a/` (entire directory contents except template README)
   - `grimoires/loa/archive/` (entire directory)
2. Initialize a clean `ledger.json` with `{"version": "1.0.0", "cycles": [], "active_cycle": null, ...}`
3. Preserve structural files: `grimoires/loa/context/README.md`, `grimoires/loa/NOTES.md` (template), `grimoires/loa/BEAUVOIR.md` (if exists)

**Acceptance criteria**:
- Fresh mount on new project: `grimoires/loa/prd.md` does NOT exist
- Fresh mount: `grimoires/loa/ledger.json` has empty cycles array
- Fresh mount: `/plan` starts discovery from scratch
- Remount (`--force`): existing user artifacts are preserved (not overwritten)
- Context files placed by user before mount are NOT deleted

### FR-4: Review Scope Filtering with `.reviewignore` (#303)

**Current state**: Bridgebuilder has `LOA_EXCLUDE_PATTERNS` in `truncation.ts:156-163` that excludes `.claude/**`, `grimoires/**`, `.beads/**`. But:
- GPT review (`/gpt-review`) does not use this filtering
- Audit-sprint does not use this filtering
- Users cannot customize the exclusion patterns

**Required behavior**: Layered review scope filtering.

**Layer 1 — Auto-detected zone filtering (sane defaults)**:
- All review tools detect Three-Zone Model via `.loa-version.json`
- System zone (`.claude/`) excluded by default
- State zone (`grimoires/`, `.beads/`) excluded unless user-modified in the PR
- App zone always included

**Layer 2 — `.reviewignore` file (user customization)**:
- New file at project root: `.reviewignore`
- Gitignore-style glob patterns
- Auto-populated by `/mount` with sane defaults
- Users can add/remove patterns
- All review tools read this file

**Template `.reviewignore`**:
```gitignore
# Framework-managed (auto-generated by Loa)
.claude/
grimoires/loa/a2a/
grimoires/loa/archive/
.beads/
.run/

# User additions below
```

**Review tool integration**:
- `bridge-github-trail.sh` → already has Loa filtering; ensure it's enabled by default
- `gpt-review-api.sh` → add file filtering before building review prompt
- `audit-sprint` skill → add zone-aware diff scoping
- Shared utility: `.claude/scripts/review-scope.sh` that reads `.reviewignore` + zone detection, outputs filtered file list

**Acceptance criteria**:
- Bridgebuilder review on Loa-mounted repo excludes `.claude/` files from diff
- `/gpt-review` on Loa-mounted repo excludes `.claude/` files
- `/audit-sprint` focuses on app zone code
- `.reviewignore` patterns respected by all three tools
- Users can add custom patterns (e.g., `vendor/`, `generated/`)
- Override: `--no-reviewignore` flag to review everything (power user)

## 5. Technical & Non-Functional Requirements

### Security

- Encrypted credential store uses Fernet (AES-128-CBC + HMAC) — same as hive pattern
- Encryption key file has 0600 permissions, never committed to git
- Credential values use redaction in any log/output context
- `.env.local` added to `.gitignore` template during mount
- `_ENV_ALLOWLIST` in interpolation.py enforced for all resolution paths

### Portability

- Credential storage at `~/.loa/credentials/` works on Linux and macOS
- Python `cryptography` package required (add to cheval.py dependencies)
- `.reviewignore` uses gitignore-compatible glob syntax (implemented via `fnmatch` or `pathspec`)

### Performance

- Lazy interpolation should NOT add measurable latency (deferred string substitution)
- Review scope filtering runs before diff construction (token savings upstream of LLM call)

### Backward Compatibility

- Existing `{env:*}` interpolation syntax unchanged
- Users who set all env vars see no behavior change
- `.reviewignore` is additive — repos without it use zone auto-detection defaults
- Mount script change only affects NEW mounts (existing repos unaffected)

## 6. Scope & Prioritization

### MVP (This Cycle)

| Priority | Feature | Issue |
|----------|---------|-------|
| P0 | Lazy config interpolation fix | #300 |
| P0 | Clean mount grimoire initialization | #299 |
| P1 | `.reviewignore` + shared review scope utility | #303 |
| P1 | `/loa-credentials` command (basic: set, status, test) | #300 |
| P1 | GPT review and audit-sprint scope filtering | #303 |

### Future (Not This Cycle)

| Feature | Dependency |
|---------|------------|
| IndraProvider for credential chain | indra/arrakis platform launch |
| macOS Keychain / Linux secret-tool integration | User demand signal |
| OAuth2 provider flow (like hive) | Platform integration |
| Artifact externalization (`~/.loa/projects/<repo>/`) | Larger architectural decision |
| `.reviewignore` IDE plugin integration | Community contribution |

### Out of Scope

- HashiCorp Vault integration (enterprise feature)
- Full hive-style multi-tier OAuth2 system
- Automated cleanup of already-committed artifacts in git history
- Review tool changes for non-Loa repos

## 7. Risks & Dependencies

### Technical Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Lazy interpolation breaks edge cases in routing chains | Medium | High | Comprehensive test coverage of fallback/downgrade chains |
| `.reviewignore` glob syntax incompatible across tools | Low | Medium | Use shared utility, standardize on gitignore spec |
| Fernet encryption key management UX friction | Medium | Medium | Auto-generate on first `/loa-credentials` run, clear instructions |

### Dependencies

| Dependency | Status | Risk |
|------------|--------|------|
| `cryptography` Python package for Fernet | Available via pip | Low — well-maintained |
| cheval.py test suite | Exists (`tests/test_config.py`) | Low |
| Bridgebuilder truncation.ts | Already has Loa filtering | Low — extend existing |
| indra/arrakis platform | Not yet available | None — designed as future provider |

## Appendix A: Hive Credential Pattern Reference

The hive credential system (`adenhq/hive`) provides the architectural inspiration for FR-2. Key patterns adopted:

| Hive Pattern | Loa Adaptation |
|-------------|----------------|
| `CredentialStore` central facade | `/loa-credentials` command + provider chain |
| `CompositeStorage` (encrypted → env fallback) | Env → encrypted store → .env.local chain |
| `CredentialUsageSpec` template resolution | Lazy `{env:*}` interpolation via provider chain |
| `SecretStr` for safe logging | Redaction in cheval.py output |
| `EncryptedFileStorage` with Fernet | `~/.loa/credentials/store.json.enc` |
| Interactive `/hive-credentials` skill | Interactive `/loa-credentials` skill |

Patterns NOT adopted (future):
- OAuth2 provider flows → wait for indra/arrakis
- HashiCorp Vault backend → enterprise scope
- Server-synced credential cache → platform dependency
