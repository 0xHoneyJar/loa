# Sprint Plan: Hounfour Upstream Extraction

**Version**: 1.1.0
**Date**: 2026-02-10
**PRD**: grimoires/loa/prd.md (v1.1.0)
**SDD**: grimoires/loa/sdd.md (v1.1.0)
**Issue**: loa-finn #31 (upstream extraction)
**Branch**: feature/hounfour-upstream-extraction

---

## Overview

3 sprints following the SDD migration strategy (§10). Sprint 1 delivers all MUST requirements with zero breaking changes. Sprints 2 and 3 deliver SHOULD requirements incrementally.

**Team**: Single AI agent (Claude Code)
**Extraction source**: `/home/merlin/Documents/thj/code/loa-finn/src/hounfour/` (229 files, 40,170 lines)

### Requirements Traceability

| FR | Priority | Sprint | Description |
|----|----------|--------|-------------|
| FR-1 | MUST | 1 | Config schema v2 |
| FR-2 | MUST | 1 | Provider abstraction (`model-invoke` + `cheval.py`) |
| FR-3 | MUST | 1 | Skill decomposition (8 persona.md) |
| FR-4 | MUST | 1 | Default templates |
| FR-8 | MUST | 1 | Skill schema update |
| FR-5 | SHOULD | 2 | Flatline Protocol unification |
| FR-6 | SHOULD | 3 | Cost ledger + `/cost-report` |
| FR-7 | SHOULD | 3 | Routing chains (fallback + downgrade) |

---

## Sprint 1: Ship Adapter — Foundation Layer

**Goal**: Ship the Hounfour provider abstraction with zero breaking changes on the native path. After this sprint, `model-invoke` works end-to-end for OpenAI and Anthropic providers, 8 core agents have `persona.md` files, and the config schema is in place.

**SDD Reference**: §10.1 (Phase 1: Ship Adapter)

### Task 1.1: Create `loa_cheval` Python package structure

- **Files**: `.claude/adapters/pyproject.toml`, `.claude/adapters/loa_cheval/__init__.py`, `.claude/adapters/loa_cheval/__version__.py`, `.claude/adapters/loa_cheval/types.py`
- **Description**: Create the Python package skeleton with `CompletionRequest`, `CompletionResult`, `Usage` dataclasses (SDD §4.2.3). Set up `pyproject.toml` with package metadata and version `1.0.0`. The `__init__.py` exports the public API surface (SDD §7.3.2).
- **Source**: loa-finn `src/hounfour/types.ts` for field definitions
- **Acceptance Criteria**:
  - [ ] `pyproject.toml` valid with `loa_cheval` as package name
  - [ ] `from loa_cheval import CompletionRequest, CompletionResult, Usage, __version__` works
  - [ ] Dataclass fields match SDD §4.2.3 exactly
  - [ ] `__version__` is `"1.0.0"`

### Task 1.2: Implement config system

- **Files**: `.claude/adapters/loa_cheval/config/loader.py`, `.claude/adapters/loa_cheval/config/interpolation.py`, `.claude/adapters/loa_cheval/config/validation.py`
- **Description**: Implement the 4-layer config merge pipeline (SDD §4.1.1): system defaults → project config → env vars → CLI args. Implement secret interpolation with `{env:VAR}` allowlist and `{file:path}` restrictions (SDD §4.1.3, §6.2). Implement JSON Schema validation for the config.
- **Source**: loa-finn `src/hounfour/registry.ts` for merge logic
- **Acceptance Criteria**:
  - [ ] Config merge produces correct output for defaults + project + env + CLI combinations
  - [ ] `{env:VAR}` restricted to `^LOA_.*`, `^OPENAI_API_KEY$`, `^ANTHROPIC_API_KEY$`, `^MOONSHOT_API_KEY$`
  - [ ] User-defined `secret_env_allowlist` patterns are additive (SDD §6.2)
  - [ ] `{file:path}` rejects symlinks, validates owner, checks mode ≤ 0640
  - [ ] Invalid interpolation patterns rejected with clear error messages
  - [ ] `--print-effective-config` outputs merged config with source annotations
  - [ ] JSON Schema validation catches invalid config structure

### Task 1.3: Implement provider adapters (OpenAI + Anthropic)

- **Files**: `.claude/adapters/loa_cheval/providers/base.py`, `.claude/adapters/loa_cheval/providers/openai_adapter.py`, `.claude/adapters/loa_cheval/providers/anthropic_adapter.py`
- **Description**: Implement `ProviderAdapter` ABC (SDD §4.2.3) with `complete()`, `validate_config()`, `health_check()`. Implement OpenAI adapter (pass-through + OpenAI-compatible) and Anthropic adapter (message format translation, thinking trace extraction). Request/response normalization per SDD §4.2.5 with canonical tool call format and feature support matrix. Context window enforcement per SDD §4.2.4. Graceful degradation: httpx preferred, fallback to urllib.request.
- **Source**: loa-finn `src/hounfour/registry.ts` provider implementations
- **Acceptance Criteria**:
  - [ ] `ProviderAdapter` ABC with `complete()`, `validate_config()`, `health_check()`
  - [ ] OpenAI adapter handles chat completions and tool calls
  - [ ] Anthropic adapter translates messages format, extracts thinking traces
  - [ ] `CompletionResult.thinking` is `None` for providers without thinking support (degrade silently)
  - [ ] Tool calls normalized to canonical format (SDD §4.2.5)
  - [ ] Context window enforcement raises `ContextTooLargeError` (exit code 7)
  - [ ] Fallback to `urllib.request` when httpx unavailable, with startup warning
  - [ ] Contract tests validate output against canonical JSON Schema
  - [ ] Default timeouts: connect=10s, read=120s, write=30s (configurable per provider)
  - [ ] Hung connection test: adapter does not block indefinitely on unresponsive provider
  - [ ] Supported API surface documented: messages, model, temperature, max_tokens, tools, tool_choice (NO streaming, NO JSON mode in MVP)
  - [ ] Edge case tests: multiple tool calls, malformed tool args, provider-specific refusal payloads
  - [ ] Unsupported features return clear error (not silent degradation) when explicitly requested

### Task 1.4: Implement alias resolution and agent binding lookup

- **Files**: `.claude/adapters/loa_cheval/routing/resolver.py`
- **Description**: Implement alias resolution (alias → `provider:model-id`) and agent binding lookup (agent name → model alias + temperature + requirements). Native guard: if agent has `requires.native_runtime: true`, refuse remote execution with exit code 2 (SDD §2.3). `native` is a reserved alias that cannot be reassigned.
- **Source**: loa-finn `src/hounfour/router.ts` for resolution logic
- **Acceptance Criteria**:
  - [ ] Alias resolution resolves `reviewer` → `openai:gpt-5.2` (per config)
  - [ ] Agent binding lookup resolves `reviewing-code` → model + temperature
  - [ ] `native` alias always resolves to Claude Code session
  - [ ] `native_runtime` guard blocks remote execution for restricted agents
  - [ ] Circular alias references detected and rejected
  - [ ] Unknown alias produces clear error (exit code 2)

### Task 1.5: Create `model-invoke` CLI entry point and shell wrapper

- **Files**: `.claude/adapters/cheval.py` (CLI entry point), `.claude/scripts/model-invoke`
- **Description**: Implement the CLI interface (SDD §4.2.2) with I/O contract: stdout = model response only, stderr = diagnostics/errors. Structured error JSON on stderr (SDD §4.2.2 Error Taxonomy). Shell wrapper: `exec python3 .claude/adapters/cheval.py "$@"`. Support `--agent`, `--input`, `--system`, `--model`, `--dry-run`, `--print-effective-config`, `--validate-bindings`, `--json-errors`, `--output-format`. Persona loading: when `--agent` is specified, resolve persona.md from `.claude/skills/{agent}/persona.md` and inject as system prompt. Resolution priority: `--system` flag > persona.md > SKILL.md fallback.
- **Source**: New implementation following SDD CLI spec
- **Acceptance Criteria**:
  - [ ] `model-invoke --agent reviewing-code --input file.md` produces model response on stdout
  - [ ] Errors are JSON on stderr when `--json-errors` set
  - [ ] Error taxonomy codes match SDD table (SUCCESS through CONTEXT_TOO_LARGE)
  - [ ] Exit codes match SDD table (0-7)
  - [ ] `--dry-run` validates config and prints resolved model without API call
  - [ ] `--validate-bindings` checks all agent names referenced by scripts exist in config
  - [ ] Shell wrapper is executable and delegates to cheval.py
  - [ ] stdout contains NO log messages (logs go to stderr only)
  - [ ] Persona resolution: `--system` > `persona.md` > SKILL.md fallback
  - [ ] `--print-effective-config` masks secret values (shows `***REDACTED***` not actual keys)

### Task 1.6: Create default config and JSON Schema

- **Files**: `.claude/defaults/model-config.yaml`, `.claude/schemas/model-config.schema.json`
- **Description**: Ship default provider registry, aliases, agent bindings, and pricing (SDD §4.1.2). JSON Schema validates the `hounfour:` config section. Defaults represent the conservative profile (maximize quality, most agents on native).
- **Source**: SDD §4.1.2 config schema example, loa-finn Hounfour config
- **Acceptance Criteria**:
  - [ ] `model-config.yaml` contains providers (openai, anthropic), aliases, agent bindings, metering defaults
  - [ ] Pricing in micro-USD integers
  - [ ] JSON Schema validates the example config without errors
  - [ ] Schema rejects invalid config (missing provider type, invalid alias format)
  - [ ] Default agent bindings match PRD FR-4 conservative profile

### Task 1.7: Create `persona.md` for 8 core agents

- **Files**: `.claude/skills/{8 agents}/persona.md`, `.claude/skills/{8 agents}/output-schema.md` (where applicable)
- **Description**: Decompose 8 core agents into model-portable structure (PRD FR-3, SDD §4.3). Each `persona.md` defines role, expertise, task structure, quality bar, and references output-schema.md. Must be model-agnostic (no Claude-specific or GPT-specific instructions).
- **Agents**: discovering-requirements, designing-architecture, planning-sprints, implementing-tasks, reviewing-code, auditing-security, translating-for-executives, riding-codebase
- **Source**: loa-finn `.claude/skills/*/persona.md` (16 files)
- **Acceptance Criteria**:
  - [ ] 8 `persona.md` files created, one per agent
  - [ ] Each persona defines role, inputs, outputs, quality criteria
  - [ ] No model-specific instructions (no "as Claude" or "as GPT")
  - [ ] `implementing-tasks` and `riding-codebase` have note: `native_runtime` only, persona for documentation
  - [ ] `output-schema.md` created for agents with structured output (reviewing-code, auditing-security)
  - [ ] Portability classification matches SDD §4.3.3

### Task 1.8: Update skill index schema

- **File**: `.claude/schemas/skill-index.schema.json`
- **Description**: Replace the hardcoded `"enum": ["sonnet", "opus", "haiku"]` with open string type (PRD FR-8, SDD §7.2).
- **Acceptance Criteria**:
  - [ ] `model` field is `"type": "string"` with `"default": "native"`
  - [ ] Description references Hounfour provider registry
  - [ ] Hardcoded enum removed
  - [ ] Existing skill index.yaml files still validate

### Task 1.9: Implement redaction/sanitization layer

- **Files**: `.claude/adapters/loa_cheval/config/redaction.py`
- **Description**: Implement a dedicated redaction layer that sanitizes all output paths. Exception handler wraps httpx/urllib errors to strip Authorization headers, env var values, and API keys from exception messages and tracebacks. `--print-effective-config` masks all `{env:}` and `{file:}` resolved values as `***REDACTED***` showing only source annotation. Secrets are NEVER passed as CLI args (enforced by reading in-process only). All HTTP client loggers are configured to redact Authorization headers.
- **Acceptance Criteria**:
  - [ ] Custom exception handler wraps provider errors, strips auth values
  - [ ] `--print-effective-config` shows `auth: "***REDACTED*** (from env:OPENAI_API_KEY)"` not actual key
  - [ ] httpx debug logging cannot leak Authorization header
  - [ ] Python tracebacks from cheval.py cannot expose env var values
  - [ ] Query parameters in error URLs are redacted
  - [ ] Nested config structures with secret values are recursively redacted

### Task 1.10: Retry logic with global attempt budget

- **Files**: `.claude/adapters/loa_cheval/providers/retry.py`
- **Description**: Implement retry logic with exponential backoff + jitter (SDD §4.2.6). Global attempt budget: `MAX_TOTAL_ATTEMPTS=6`, `MAX_PROVIDER_SWITCHES=2` (SDD §4.2.7). Budget check before each attempt. Circuit breaker check before each attempt. **Extension points**: Retry loop must expose hooks for budget accounting (pre-call cost estimate, post-call reconciliation) and metrics collection — these are consumed by Sprint 3 but the interfaces must exist in Sprint 1 to avoid refactoring.
- **Source**: loa-finn `src/hounfour/router.ts` retry logic
- **Acceptance Criteria**:
  - [ ] Exponential backoff with jitter on rate limit
  - [ ] Global attempt counter enforced (max 6 total attempts per invocation)
  - [ ] Provider switch counter enforced (max 2 switches per invocation)
  - [ ] Budget check hook: `pre_call_hook(request) -> BudgetStatus` (no-op in Sprint 1, wired in Sprint 3)
  - [ ] Post-call hook: `post_call_hook(result) -> None` (no-op in Sprint 1, wired in Sprint 3)
  - [ ] Circuit breaker state checked before each attempt
  - [ ] `RetriesExhaustedError` raised when limits reached

### Task 1.11: Native path regression suite

- **Files**: `.claude/adapters/tests/test_native_regression.py`
- **Description**: Define what "native path" means concretely and build automated golden tests. Capture current behavior of existing scripts/skills before any changes: command invocations, expected stdout/stderr patterns, exit codes. Run before AND after Sprint 1 changes to verify zero regression.
- **Acceptance Criteria**:
  - [ ] Baseline captured: `model-adapter.sh` exit codes and output format for review/skeptic modes
  - [ ] Baseline captured: `flatline-orchestrator.sh` invocation pattern (unchanged in Sprint 1)
  - [ ] Baseline captured: `gpt-review-api.sh` invocation pattern (unchanged in Sprint 1)
  - [ ] `model-invoke --agent implementing-tasks` rejects remote execution (native_runtime guard)
  - [ ] `model-invoke --agent riding-codebase` rejects remote execution (native_runtime guard)
  - [ ] All native-bound skills pass through without model-invoke involvement
  - [ ] Regression test runs as part of CI/test suite

### Task 1.12: Tests — config, providers, redaction

- **Files**: `.claude/adapters/tests/test_config.py`, `.claude/adapters/tests/test_providers.py`, `.claude/adapters/tests/test_redaction.py`, `.claude/adapters/tests/fixtures/`
- **Description**: Comprehensive test suite (SDD §9). Config merge tests. Provider conformance tests with golden fixtures validating canonical schema (not just byte-equality). Forced-failure redaction tests (SDD §6.2) that assert no secrets leak via httpx exceptions, tracebacks, or debug logs.
- **Acceptance Criteria**:
  - [ ] Config merge pipeline tests (defaults + project + env + CLI)
  - [ ] Invalid interpolation patterns rejected
  - [ ] OpenAI golden fixture: request serialization + response deserialization
  - [ ] Anthropic golden fixture: message format translation + thinking trace extraction
  - [ ] Tool call normalization test (both providers → canonical format)
  - [ ] Redaction test: forced httpx error does not leak Authorization header
  - [ ] Redaction test: traceback from cheval.py does not contain env var values
  - [ ] Context window enforcement test (input > model limit → exit code 7)

### Task 1.13: Validation — compatibility matrix and integration test

- **Description**: Run the migration linter (`model-invoke --validate-bindings`). Verify native_runtime guard rejects remote execution for restricted agents. Verify existing skills continue to work unchanged. Cross-check all file paths against SDD component ownership table.
- **Acceptance Criteria**:
  - [ ] `model-invoke --validate-bindings` passes
  - [ ] `model-invoke --agent implementing-tasks --dry-run` fails with exit code 2 (native_runtime guard)
  - [ ] `model-invoke --agent reviewing-code --dry-run` succeeds (resolves to openai:gpt-5.2)
  - [ ] All new files are in correct zones (System Zone for `.claude/`, State Zone for `grimoires/`)
  - [ ] `.loa.config.yaml.example` updated with Hounfour config sections
  - [ ] No changes to any existing SKILL.md files

---

## Sprint 2: Flatline Unification

**Goal**: Route all Flatline Protocol and GPT review model calls through `model-invoke` / `cheval.py`. Convert `model-adapter.sh` to a compatibility shim. Feature-flagged behind `hounfour.flatline_routing`.

**SDD Reference**: §10.2 (Phase 2: Flatline Unification)
**Depends on**: Sprint 1 (adapter must be working)

### Task 2.1: Update `flatline-orchestrator.sh` to use `model-invoke`

- **File**: `.claude/scripts/flatline-orchestrator.sh`
- **Description**: Replace direct model-adapter.sh calls with `model-invoke --agent flatline-reviewer` and `model-invoke --agent flatline-skeptic` (SDD §4.4.2). Gate behind `hounfour.flatline_routing: true` config flag (default false). When flag is false, use existing model-adapter.sh path. When true, use model-invoke.
- **Acceptance Criteria**:
  - [ ] Feature flag `hounfour.flatline_routing` controls routing path
  - [ ] With flag=false: behavior identical to pre-sprint (model-adapter.sh)
  - [ ] With flag=true: calls route through `model-invoke --agent flatline-reviewer`
  - [ ] 4 parallel Phase 1 calls still work (reviewer + skeptic × 2 models)
  - [ ] Phase 2 cross-scoring calls route through `model-invoke`
  - [ ] Error handling preserves existing degraded-mode behavior

### Task 2.2: Update `gpt-review-api.sh` to use `model-invoke`

- **File**: `.claude/scripts/gpt-review-api.sh`
- **Description**: Replace direct curl calls to OpenAI with `model-invoke --agent gpt-reviewer`. Same feature flag as Task 2.1. Preserve existing verdict parsing (APPROVED/CHANGES_REQUIRED/DECISION_NEEDED).
- **Acceptance Criteria**:
  - [ ] With flag=true: GPT review routes through `model-invoke`
  - [ ] Verdict parsing unchanged (JSON response → verdict extraction)
  - [ ] `--expertise` and `--context` files passed through to model-invoke system prompt
  - [ ] `--iteration` and `--previous` re-review support preserved
  - [ ] Error handling maps model-invoke exit codes to existing error codes

### Task 2.3: Convert `model-adapter.sh` to compatibility shim

- **File**: `.claude/scripts/model-adapter.sh`
- **Description**: Replace the 827-line bash implementation with a thin shim (SDD §4.4.3) that maps legacy `--model`/`--mode` flags to `model-invoke --agent` format. The shim is activated when `hounfour.flatline_routing: true`. Original implementation preserved as `model-adapter.sh.legacy` for rollback.
- **Acceptance Criteria**:
  - [ ] Shim maps `--mode review` → `--agent flatline-reviewer`
  - [ ] Shim maps `--mode skeptic` → `--agent flatline-skeptic`
  - [ ] Shim maps `--mode score` → `--agent flatline-scorer`
  - [ ] Shim maps `--mode dissent` → `--agent flatline-dissenter`
  - [ ] All legacy flags pass through to model-invoke equivalent
  - [ ] Original `model-adapter.sh` backed up as `.legacy`
  - [ ] When feature flag=false, shim delegates to `.legacy` implementation

### Task 2.4: Add `flatline-scorer` and `flatline-dissenter` agent bindings

- **Files**: `.claude/defaults/model-config.yaml`, `.claude/skills/flatline-knowledge/persona.md` (or relevant skill)
- **Description**: The Flatline Protocol uses 4 roles: reviewer, skeptic, scorer, dissenter. Sprint 1 covered reviewer and skeptic. Add agent bindings and persona.md for the remaining 2 roles.
- **Acceptance Criteria**:
  - [ ] `flatline-scorer` agent binding added (model: reviewer)
  - [ ] `flatline-dissenter` agent binding added (model: reasoning)
  - [ ] Both agents have persona.md with role, inputs, output format
  - [ ] `model-invoke --validate-bindings` still passes with new agents

### Task 2.5: Integration test — Flatline end-to-end through model-invoke

- **Description**: Run a complete Flatline review cycle (review + skeptic + cross-scoring) through the new model-invoke path. Compare output structure and verdict quality against the legacy path.
- **Acceptance Criteria**:
  - [ ] Flatline review with `hounfour.flatline_routing: true` produces valid consensus JSON
  - [ ] HIGH_CONSENSUS, DISPUTED, BLOCKER categories populated correctly
  - [ ] Cost ledger entries created for each model call (if Sprint 3 not yet done, verify via dry-run)
  - [ ] Feature flag toggle does not require restart or cache invalidation
  - [ ] Rollback to legacy path works by setting flag=false

---

## Sprint 3: Cost Ledger + Routing Chains

**Goal**: Ship framework-level cost tracking with JSONL ledger and `/cost-report` command. Implement fallback/downgrade routing chains with circuit breaker state management.

**SDD Reference**: §10.3 (Phase 3: Cost Ledger + Routing)
**Depends on**: Sprint 2 (Flatline unified through model-invoke)

### Task 3.1: Implement JSONL cost ledger with atomic writes

- **Files**: `.claude/adapters/loa_cheval/metering/ledger.py`, `.claude/adapters/loa_cheval/metering/pricing.py`
- **Description**: Implement JSONL append with `fcntl.flock` (SDD §4.5.2). Atomic daily spend counter with flock-protected read-modify-write (SDD §4.5.3). Integer micro-USD arithmetic for cost calculation. Retry accounting: each attempt is a separate entry with same `trace_id`.
- **Source**: loa-finn `src/hounfour/pricing.ts` for cost calculation
- **Acceptance Criteria**:
  - [x] Ledger entries match SDD §4.5.1 format exactly
  - [x] `fcntl.flock(LOCK_EX)` used for concurrent append safety
  - [x] Daily spend counter file `.daily-spend-{date}.json` atomically updated
  - [x] Integer micro-USD arithmetic (no floating point)
  - [x] Missing usage fields produce `usage_source: "estimated"` entries
  - [x] Unknown pricing produces `pricing_source: "unknown"` with `cost_micro_usd: 0`
  - [x] Retry entries share `trace_id` but have unique `request_id`
  - [x] Corruption recovery: truncate to last valid JSONL line on read, log warning count
  - [x] Supported platforms documented: Linux, macOS (local filesystem only — NFS/network mounts unsupported)
  - [x] `.run/` lifecycle: circuit breaker files cleaned on successful completion, stale files expire after 24h

### Task 3.2: Implement budget enforcement

- **Files**: `.claude/adapters/loa_cheval/metering/budget.py`
- **Description**: Pre-call budget check using daily spend counter (SDD §4.5.3). Returns ALLOW, WARN, DOWNGRADE, or BLOCK. Best-effort under concurrency (documented overshoot bound). Post-call reconciliation updates actual cost. Integrate into retry loop (SDD §4.2.6 updated).
- **Acceptance Criteria**:
  - [x] Pre-call check reads daily counter (O(1), not ledger scan)
  - [x] BLOCK status raises `BudgetExceededError` (exit code 6)
  - [x] DOWNGRADE status triggers downgrade chain walker
  - [x] WARN status logs warning to stderr
  - [x] Post-call reconciliation updates daily counter and ledger
  - [x] Overshoot bound documented: `MAX_TOTAL_ATTEMPTS × max_cost_per_call`

### Task 3.3: Implement fallback and downgrade chain walker

- **Files**: `.claude/adapters/loa_cheval/routing/chains.py`
- **Description**: Config-driven routing chains (SDD §4.1.2 routing section). Fallback: provider down → walk chain, skip entries missing required capabilities. Downgrade: budget exceeded → walk chain to cheaper model. Cycle detection to prevent infinite loops.
- **Source**: loa-finn `src/hounfour/router.ts` `walkChain()` with cycle detection
- **Acceptance Criteria**:
  - [x] Fallback chain walks when provider is unavailable
  - [x] Capability filtering: skip fallback entries that don't satisfy agent's `requires`
  - [x] Downgrade chain walks when budget exceeded
  - [x] Cycle detection rejects circular chains at config validation time
  - [x] Chain depth limited by `MAX_PROVIDER_SWITCHES` (2)
  - [x] Resolution is deterministic (config-driven, no randomness)
  - [x] Routing decision trace logged to stderr: `[routing] agent=reviewing-code → alias=reviewer → openai:gpt-5.2 (reason: direct_match)`
  - [x] Scenario-based tests: budget+fallback combined, capability filtering skip, circuit breaker+downgrade

### Task 3.4: Implement circuit breaker state management

- **Files**: `.claude/adapters/loa_cheval/routing/circuit_breaker.py`
- **Description**: File-based circuit breaker per provider (SDD §4.2.6). State machine: CLOSED → OPEN → HALF_OPEN → CLOSED. State persisted in `.run/circuit-breaker-{provider}.json`. Configurable thresholds (failure_threshold, reset_timeout, half_open_max_probes, count_window).
- **Acceptance Criteria**:
  - [x] CLOSED → OPEN when failure_count ≥ threshold within count_window
  - [x] OPEN → HALF_OPEN after reset_timeout expires
  - [x] HALF_OPEN → CLOSED on successful probe
  - [x] HALF_OPEN → OPEN on failed probe (timer restarts)
  - [x] State file matches SDD format
  - [x] OPEN provider skipped immediately in retry loop (no wasted attempts)

### Task 3.5: Ship `/cost-report` command

- **Files**: `.claude/scripts/cost-report.sh`, new skill registration
- **Description**: Read JSONL ledger and generate markdown summary with per-agent, per-model, and per-provider breakdowns. Total cost for today, last 7 days, last 30 days. Top N most expensive invocations.
- **Acceptance Criteria**:
  - [x] Reads `grimoires/loa/a2a/cost-ledger.jsonl`
  - [x] Markdown table with per-agent cost breakdown
  - [x] Markdown table with per-model cost breakdown
  - [x] Daily, weekly, monthly summaries
  - [x] Gracefully handles corrupted JSONL lines (skip + warning count)
  - [x] Works with empty ledger (no error, shows zero costs)

### Task 3.6: Tests — metering, budget, routing, circuit breaker

- **Files**: `.claude/adapters/tests/test_pricing.py`, `.claude/adapters/tests/test_routing.py`, `.claude/adapters/tests/test_circuit_breaker.py`
- **Description**: Comprehensive tests for Sprint 3 components.
- **Acceptance Criteria**:
  - [x] Integer micro-USD arithmetic produces expected values for known token counts
  - [x] Budget enforcement triggers at correct thresholds
  - [x] Missing usage fields produce estimated costs
  - [x] Fallback chain resolves correctly with capability filtering
  - [x] Downgrade chain resolves when budget exceeded
  - [x] Circular chain detection works
  - [x] Circuit breaker state transitions correct
  - [x] Daily spend counter handles concurrent increments
  - [x] Cost report generates valid markdown from test ledger

### Task 3.7: Update `.loa.config.yaml.example` with full Hounfour config

- **File**: `.loa.config.yaml.example`
- **Description**: Add complete Hounfour configuration sections showing all options with comments. Include routing, metering, budget, and circuit breaker settings.
- **Acceptance Criteria**:
  - [x] All Hounfour config sections present with inline documentation
  - [x] Example validates against JSON Schema
  - [x] Comments explain each field's purpose and default value
  - [x] Feature flag section (`hounfour.flatline_routing`) documented

---

## Rollback Plan

| Sprint | Rollback Steps | Criteria |
|--------|---------------|----------|
| Sprint 1 | Remove `.claude/adapters/`, `.claude/defaults/model-config.yaml`, `.claude/schemas/model-config.schema.json`. Restore `skill-index.schema.json` model enum. Remove `persona.md` files from skills. Remove `.claude/scripts/model-invoke`. | Native regression suite fails; config schema breaks existing `.loa.config.yaml` |
| Sprint 2 | Set `hounfour.flatline_routing: false`. Restore `model-adapter.sh` from `.legacy` backup. No script changes needed — feature flag gates all new paths. | Flatline review produces wrong/missing verdicts; model-invoke call failures |
| Sprint 3 | Disable metering (`hounfour.metering.enabled: false`). Remove `.daily-spend-*` files and circuit breaker state from `.run/`. Cost ledger is append-only and can remain. | Budget enforcement blocks valid calls; circuit breaker thrashing |

---

## Risk Mitigations

| Risk | Sprint | Mitigation |
|------|--------|------------|
| Single-agent scope risk | 1 | Full implement→review→audit cycle enforced per sprint; native regression suite as stop-the-line gate; Task 1.13 is explicit integration checkpoint |
| Python cold start latency | 1 | Config caching; 200ms is <1% of Flatline runtime |
| Provider API drift | 1 | Conformance tests validate canonical schema, not just fixtures |
| Config merge unexpected results | 1 | `--print-effective-config` debug command + merge tests |
| loa-finn import breaks | 1 | Semantic versioning via `__version__`; downstream contract tests |
| Flatline refactor breaks review | 2 | Feature flag defaults to false; legacy `.legacy` backup |
| Budget overshoot under concurrency | 3 | Best-effort with documented bounds; daily counter is O(1) |
| Circular routing chains | 3 | Detected at config validation time, not runtime |

---

## Success Criteria

| Metric | Sprint 1 | Sprint 2 | Sprint 3 |
|--------|----------|----------|----------|
| M1: Configurable providers | 2 (OpenAI + Anthropic) | — | 4+ (any configured) |
| M2: Skills with persona.md | 8/19 | 10/19 (+2 Flatline) | — |
| M3: Skill schema model options | Alias-based | — | — |
| M4: Ad-hoc API calls bypassing adapter | 2 (unchanged) | 0 (all unified) | — |
| M5: Cost tracking granularity | — | — | Per-agent, per-model JSONL |

---

## NFR Compliance

| NFR | Verification | Sprint |
|-----|-------------|--------|
| NFR-1: Zero breaking changes on native | Native guard in model-invoke; compatibility matrix tests | 1 |
| NFR-2: Python dependency management | requirements.txt + graceful urllib fallback | 1 |
| NFR-3: Three-Zone compliance | All new code in System Zone (.claude/); ledger in State Zone | 1 |
| NFR-4: Backward compatibility | Feature flag for Flatline; model-adapter.sh shim | 2 |
| NFR-5: Performance | Config cached; ledger append < 10ms; daily counter O(1) | 3 |

---

*Generated from PRD v1.1.0 + SDD v1.1.0 (both Flatline-reviewed) via /sprint-plan. Flatline sprint review integrated 5 HIGH_CONSENSUS and resolved 6 BLOCKERS into v1.1.0. Aligned to SDD §10 migration strategy: Phase 1 = Sprint 1, Phase 2 = Sprint 2, Phase 3 = Sprint 3.*
