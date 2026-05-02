# Adding a New Provider to Loa

> **Status**: Reference guide — produced as cycle-096 Sprint 2 Task 2.3 (FR-9). The Bedrock implementation in cycle-096 is the worked example for every step. **Read this before adding a fifth provider.**
>
> **Goal traceability**: Closes PRD G-2 ("Adding a fifth provider takes ≤ 1 day of work for a contributor familiar with the codebase").

This guide walks the **six coordinated edit sites** required to add a new model provider to Loa, using AWS Bedrock (cycle-096) as the reference implementation. Every step cites the exact file and the cycle-096 commit that created it, so a contributor can `git show` the change, copy the structure, and adapt for their target provider.

## Quick reference

| # | Edit site | What changes | cycle-096 commit |
|---|---|---|---|
| 1 | `.claude/defaults/model-config.yaml` | Provider registry entry + models + pricing + (optional) aliases | `de5db56` |
| 2 | `.claude/adapters/loa_cheval/providers/<name>_adapter.py` | Python adapter subclass | `a0bca7f` |
| 3 | `.claude/adapters/loa_cheval/providers/__init__.py` | Adapter registry binding | `a0bca7f` |
| 4 | `.claude/adapters/cheval.py` `_build_provider_config()` | Provider-specific schema field propagation (only if new ModelConfig/ProviderConfig fields) | `a0bca7f` |
| 5 | `.claude/data/model-permissions.yaml` | Trust scope entries per `provider:model` | `a4b1444` |
| 6 | `.claude/scripts/lib-security.sh` `_SECRET_PATTERNS` | Token regex prefix (if new vendor token format) | `f63ecc1` |

After every six-site change, regenerate `generated-model-maps.sh`:

```bash
bash .claude/scripts/gen-adapter-maps.sh
bash .claude/scripts/gen-adapter-maps.sh --check  # verify no drift
```

## Validation checklist

These commands MUST all return green before opening a PR:

```bash
# 1. Generator drift check
bash .claude/scripts/gen-adapter-maps.sh --check
# Expected: "OK: ... matches YAML"

# 2. Cycle-094 G-7 cross-map invariant
bats tests/integration/model-registry-sync.bats
# Expected: 13/13 (or higher with provider-specific extensions)

# 3. Adapter unit tests
cd .claude/adapters && python3 -m pytest tests/test_<provider>_adapter.py
# Expected: ≥ 85% coverage on the new adapter file

# 4. Cross-language parser invariant (any colon-bearing model IDs)
bats tests/integration/parser-cross-language.bats
# Expected: 13/13

# 5. Live integration (key-gated; skips clean without credentials)
cd .claude/adapters && python3 -m pytest tests/test_<provider>_live.py
# Expected: passes against real provider OR skips with clear reason
```

## Critical: Cycle-094 G-7 cross-map invariant

`tests/integration/model-registry-sync.bats` enforces that every model ID present in `MODEL_PROVIDERS` agrees on its provider with `MODEL_TO_PROVIDER_ID` in red-team-model-adapter. **A new provider entry that lands in YAML but doesn't propagate through the generator + bash maps will fail this test.** Always run the validation commands.

The test exists because cycle-082 and cycle-093 lost work to silent map drift — adding a provider used to require touching 4 hand-maintained tables that drifted apart. Don't undo that progress.

---

## Step-by-step (Bedrock as worked example)

### Step 1: Provider registry entry — `.claude/defaults/model-config.yaml`

Add a new provider block under `providers:`. Mirror the structure of an existing provider for any fields you don't have a strong opinion about.

**Worked example (Bedrock, commit `de5db56`)**: see `.claude/defaults/model-config.yaml` lines 182-247 for the full block.

Required fields:

```yaml
providers:
  <name>:
    type: <name>                          # Adapter discriminator (matches the registry key in step 3)
    endpoint: "https://api.<vendor>.com/v1" # Or templated form (e.g., "{region}" placeholder for AWS)
    auth: "{env:<VENDOR>_API_KEY}"        # LazyValue interpolation
    models:
      <model-id>:
        capabilities: [chat, ...]         # See list below
        context_window: 128000             # Tokens
        token_param: max_tokens            # Wire name for the output-token-budget parameter
        pricing:
          input_per_mtok: <integer>        # Micro-USD per million tokens (matches metering)
          output_per_mtok: <integer>
```

Optional fields (use as needed):

| Field | Purpose | When to use |
|---|---|---|
| `connect_timeout` | seconds (default 10) | Tighten for fast failover |
| `read_timeout` | seconds (default 120) | Raise for vision/long-running |
| `endpoint_family: chat \| responses` | OpenAI-only routing | Required on every OpenAI model |
| `params: {temperature_supported: false}` | Wire-protocol gates | Anthropic Opus 4 family (#641) |
| `extra: {thinking_level: high}` | Provider-specific feature config | Google Gemini thinking config |
| `fallback_chain: ["provider:model"]` | Probe-driven fallback | Cycle-095 fallback design |
| `probe_required: true` | Latent entry until probe confirms | Cycle-093 sprint-3 pattern |
| **`api_format: {chat: converse, ...}`** | Per-capability dispatch table | **Bedrock pattern**; cycle-096 added this |
| **`fallback_to: "anthropic:claude-opus-4-7"`** | Versioned cross-provider mapping | **Required when `compliance_profile: prefer_bedrock` is in play** |
| **`fallback_mapping_version: 1`** | Bumps when behavior delta breaks equivalence | **Companion to `fallback_to`** |

Capabilities vocabulary: `chat`, `tools`, `function_calling`, `thinking_traces`, `code`, `vision`, `deep_research`. See cycle-095 SDD §3.4 for the full list.

If your provider needs config fields beyond the existing schema (cycle-096 added `region_default`, `auth_modes`, `compliance_profile` for Bedrock — see step 4), extend the `ProviderConfig` / `ModelConfig` dataclasses in `loa_cheval/types.py`.

### Step 2: Python adapter — `.claude/adapters/loa_cheval/providers/<name>_adapter.py`

Subclass `ProviderAdapter` from `base.py`. Implement three required methods:

```python
class <Name>Adapter(ProviderAdapter):
    PROVIDER_TYPE = "<name>"

    def complete(self, request: CompletionRequest) -> CompletionResult:
        """Send request, return normalized result."""

    def validate_config(self) -> List[str]:
        """Return list of error strings; empty list = valid."""

    def health_check(self) -> bool:
        """Quick reachability probe."""
```

**Worked example (Bedrock, commit `a0bca7f`)**: `.claude/adapters/loa_cheval/providers/bedrock_adapter.py` (834 lines).

Key patterns to mirror:

1. **Reuse `http_post` from base.py** — never roll your own HTTP client unless you have a strong reason. Bedrock did because of URL-encoding requirements but kept httpx as the underlying library.
2. **Define provider-specific exception classes** that subclass `ChevalError`. Downstream handlers catch the base; you get typed errors. Bedrock added `OnDemandNotSupportedError`, `ModelEndOfLifeError`, `EmptyResponseError`, `QuotaExceededError`, `RegionMismatchError`.
3. **Helper functions for transformations** — separate `_transform_messages()`, `_transform_tools_to_<provider>()`, `_extract_<provider>_directive()`. Tests can exercise them in isolation.
4. **Config-load-time validation** — `validate_config()` should catch as much as possible at config-load rather than first-request-time. Bedrock's `validate_config()` checks endpoint, auth, type, auth_modes contents, and the SKP-003 `prefer_bedrock`-requires-`fallback_to` invariant.
5. **Register the auth value with the redaction layer** — `register_value_redaction(auth)` at request time (or in `__init__`) prevents token leaks via stderr / stdout / exception messages.

### Step 3: Adapter registry — `.claude/adapters/loa_cheval/providers/__init__.py`

Add your adapter class to the dispatch dict:

```python
from loa_cheval.providers.<name>_adapter import <Name>Adapter

_ADAPTER_REGISTRY: Dict[str, Type[ProviderAdapter]] = {
    "openai": OpenAIAdapter,
    "anthropic": AnthropicAdapter,
    "google": GoogleAdapter,
    "bedrock": BedrockAdapter,    # ← cycle-096
    "<name>": <Name>Adapter,       # ← your addition
}
```

This is a one-line edit per provider. The `get_adapter(config)` factory uses `config.type` (set in step 1) to look up the class.

### Step 4: Schema propagation — `.claude/adapters/cheval.py` `_build_provider_config()`

Only required if you added new `ModelConfig` or `ProviderConfig` fields in step 1.

**Worked example (Bedrock, commit `a0bca7f`)**: see `.claude/adapters/cheval.py:152-200`. Added the following lines for cycle-096:

```python
# In ModelConfig construction:
api_format=model_data.get("api_format"),
fallback_to=model_data.get("fallback_to"),
fallback_mapping_version=model_data.get("fallback_mapping_version"),

# In ProviderConfig construction:
region_default=prov.get("region_default"),
auth_modes=prov.get("auth_modes"),
compliance_profile=prov.get("compliance_profile"),
```

The corresponding fields must already exist on the dataclasses in `.claude/adapters/loa_cheval/types.py`. Cycle-096 added them — see commit `a0bca7f` `types.py` diff.

### Step 5: Trust scopes — `.claude/data/model-permissions.yaml`

Add an entry per model with the 7-dimensional trust vocabulary from Hounfour v8:

```yaml
<provider>:<model-id>:
  trust_level: high | standard | none
  trust_scopes:
    data_access: none | medium | high
    financial: none | medium | high
    delegation: none | limited | high
    model_selection: none
    governance: none
    external_communication: none
    context_access:
      architecture: full | summary | redacted | none
      business_logic: full | redacted | none
      security: full | redacted | none
      lore: full | summary | none
  execution_mode: remote_model | native_runtime
  capabilities:
    file_read: false
    file_write: false
    command_execution: false
    network_access: false
  notes: >
    Brief description of the routing path, security posture, and any
    asymmetry between trust_level and operational scopes.
```

**Worked example (Bedrock, commit `a4b1444`)**: see `.claude/data/model-permissions.yaml` for `bedrock:us.anthropic.*` entries. The pattern is to mirror the upstream provider's trust scopes — Bedrock-routed Anthropic mirrors `anthropic:claude-*`.

### Step 6: Secret-redaction patterns — `.claude/scripts/lib-security.sh`

If your provider issues tokens with a recognizable prefix (e.g., `sk-ant-`, `AKIA`, `ABSK`), add a regex to `_SECRET_PATTERNS`:

```bash
readonly _SECRET_PATTERNS=(
  'sk-ant-api[0-9A-Za-z_-]{20,}'
  'sk-proj-[0-9A-Za-z_-]{20,}'
  ...
  '<NEW>[A-Za-z0-9+/=]{36,}'    # ← your provider's prefix; cycle-096 added ABSK
)
```

The Python redaction layer (`.claude/adapters/loa_cheval/config/redaction.py`) maintains a parallel list. Update both for full bash + Python coverage.

**Worked example (Bedrock, commit `f63ecc1`)**: 2-line addition to `_SECRET_PATTERNS`.

### Generator regeneration

After all six edits, regenerate the bash maps:

```bash
bash .claude/scripts/gen-adapter-maps.sh
bash .claude/scripts/gen-adapter-maps.sh --check
```

This rewrites `.claude/scripts/generated-model-maps.sh`. Commit the regenerated file.

---

## Bearer-token vs. SigV4 / OAuth (auth modality)

Loa's existing four providers (openai, google, anthropic, bedrock) all use Bearer-token-style auth via the `auth: "{env:VAR}"` LazyValue pattern. If your provider needs request-signing (AWS SigV4, AWS Signature V2, OAuth flows, mTLS), the cycle-096 pattern reserves `auth_modes` schema for forward-compat:

```yaml
auth_modes:
  - api_key      # Bearer-token (current default)
  - sigv4        # designed in cycle-096 SDD; not built in v1
  - oauth        # designed-only in your provider's spec
```

The loader rejects unsupported modes at config load (`_reject_unsupported_bedrock_auth_modes` in `loader.py`). Mirror this pattern: add a `_reject_unsupported_<provider>_auth_modes` helper that raises `ConfigError` on unknown modes.

If your provider requires SigV4 (or any non-Bearer scheme) **and** you want to ship in v1, add the signing module under `loa_cheval/auth/<scheme>.py` and import lazily from your adapter. Add a `requirements-<provider>.txt` for any heavyweight dependencies (boto3, etc.); the default install path stays minimal.

---

## Compliance-aware fallback (`fallback_to`)

Cycle-096 introduced the `compliance_profile` schema field for Bedrock. Use the same pattern if your provider has a same-model dual-routing scenario (e.g., Vertex AI for Gemini, Azure OpenAI for OpenAI).

**Schema** (per-provider):

```yaml
compliance_profile: bedrock_only | prefer_bedrock | none
```

**Per-model `fallback_to`** declares the explicit direct-provider equivalent — **no heuristic name matching**. Loader rejects `prefer_bedrock` mode when any model lacks this field (cycle-096 SKP-003).

**Runtime dispatch**: Your adapter's `complete()` should wrap an inner method with try/except for transient errors (`ProviderUnavailableError`, `RateLimitError`) and dispatch to the `fallback_to` target when `compliance_profile in ("prefer_<provider>", "none")`. See `bedrock_adapter.py:_fallback_to_direct()` (commit `8a17a7d`) for the worked example.

**Audit logging**: emit stderr warning + `logger.warning("compliance_fallback_cross_provider_warned: ...")` for the warned-fallback mode; silent for the `none` mode. Tag `result.metadata` with `fallback="cross_provider"` so downstream cost-ledger consumers can distinguish primary vs fallback responses.

---

## Token age tracking (NFR-Sec11 pattern)

If your provider's tokens are long-lived (Bearer-token style, no automatic rotation), implement a token-age sentinel mirroring `bedrock_token_age.py`:

1. SHA256-hint sentinel at `$LOA_CACHE_DIR/<provider>-token-age.json` with `{token_hint, first_seen, last_seen}`
2. `record_token_use(token, max_age_days=N)` called in your adapter's `complete()`
3. Graduated stderr warnings at 67% / 89% / 100% of `max_age_days` (cycle-096 default 90 days = 60/80/90)
4. Token rotation detected by hint mismatch — sentinel reset, in-process latches reset

If your provider has automatic token rotation (OAuth refresh, STS expiry), the tracking can be lighter or omitted. Document the choice in the adapter docstring.

---

## Test harness

A new provider needs four test files:

| File | Purpose | cycle-096 example |
|---|---|---|
| `.claude/adapters/tests/test_<provider>_adapter.py` | Unit tests for adapter (mocked HTTP) | `test_bedrock_adapter.py` (49 tests, 700+ lines) |
| `.claude/adapters/tests/test_<provider>_live.py` | Live integration (key-gated, skips clean) | `test_bedrock_live.py` (3 tests) |
| `.claude/adapters/tests/test_<provider>_<security_concern>.py` | Adversarial / redaction / compliance tests | `test_bedrock_redaction_adversarial.py` (20 tests, 6 leak paths) |
| `tests/integration/model-registry-sync.bats` | Extend the cross-map invariant test if your provider has unusual ID shape | cycle-096 added the colon-bearing alias regression |

Coverage target: **≥ 85% on the new adapter file**. Branch coverage on `_classify_error` (or your error taxonomy mapper) is most important — every error branch needs a fixture.

Live integration test SHOULD use `pytest.mark.skipif(not _has_token(), ...)` for fork-PR safety. Load the token from env or from project `.env` (gitignored). Never paste a real token in test source.

---

## Recurring CI smoke (optional but recommended)

If your provider is contract-volatile (newer vendors evolve API shapes), add a recurring CI smoke workflow at `.github/workflows/<provider>-contract-smoke.yml`. See cycle-096 Sprint 2 Task 2.5 (the workflow that lands alongside this guide) for the worked example.

The workflow should:
- Run on schedule (daily / weekly) AND on pull_request changes to provider files AND on workflow_dispatch
- Issue 1-2 minimal probe calls per day (cost-bounded with a per-run cap)
- Fixture-diff structural keys (not values) against committed baseline
- Fail loud + open issue on drift
- Skip clean on fork PRs (no CI secret access)

---

## Cost cap discipline

Add a per-run cost cap to your CI smoke workflow. Cycle-096's smoke caps at `<= 500_000` micro-USD ($0.50) per run with both pre-flight estimation and post-flight cost-ledger assertion. Monthly cap at `<= 15_000_000` micro-USD ($15). See `.github/workflows/bedrock-contract-smoke.yml` for the pattern.

If your provider charges more per call (Opus, GPT-4 turbo, etc.), use `tiny`/`flash`/`haiku` equivalents for smoke probes. Save full-model probes for one-shot validation events (releases, vendor announcements).

---

## Documentation handoff

Update three documents when your provider lands:

1. **`grimoires/loa/NOTES.md`** — Decision Log entry under your cycle: provider rationale, design tradeoffs, [ACCEPTED-DEFERRED] items
2. **`grimoires/loa/sdd.md`** (cycle SDD) — provider plugin architecture extension; reference cycle-096 §1.4 as the pattern
3. **This guide** — add a row to the "Quick reference" table if you discovered a new edit site (e.g., a vendor-specific config layer)

---

## Common pitfalls (Bedrock-discovered)

| Pitfall | Where it bit | Mitigation |
|---|---|---|
| Bare model ID instead of inference profile | Day 1 of Bedrock implementation — HTTP 400 surfaced | Test with the real ID from `ListFoundationModels` / vendor equivalent BEFORE writing model-config.yaml entries |
| URL contains colons (Bedrock model IDs `:0` suffix) | `gen-adapter-maps.sh` jq `split(":")[1]` lost trailing parts | Centralized `parse_provider_model_id` helper splits on FIRST colon only; covered by cycle-096 cross-language test |
| Tool schema wrapping varies per vendor | Bedrock requires `inputSchema.json: <schema>` envelope | Document and test the wrapping in your adapter's tool transform helper |
| Thinking-trace format diverges between vendors | Direct-Anthropic uses `thinking.type: enabled`; Bedrock-Anthropic uses `thinking.type: adaptive` | Adapter translates per-provider; expose only one canonical shape to callers |
| Response shape camelCase vs snake_case | Bedrock returns `inputTokens`; cheval Usage takes `input_tokens` | Adapter normalization in `_parse_response` |
| Pricing varies by routing path | Same Anthropic model on Bedrock vs direct API may have different rates | Live-fetch at sprint execution, freeze in YAML, document quarterly refresh cadence |
| Daily-quota responses arrive as 200 OK with body pattern | Non-HTTP-coded errors slip past generic 5xx-retry logic | Body-pattern detection + process-scoped circuit breaker (`threading.Event`) |
| Token rotation breaks redaction cache | Long-running processes with mid-process rotation | `clear_registered_values()` + `record_token_use()` rotation detection |

---

## When to bump `fallback_mapping_version`

Per cycle-096 SDD §6.2: bump when AWS or the upstream vendor ships a behavior delta that breaks equivalence between your Bedrock-routed model and its direct-API fallback. Examples:

- Vendor adds a new content block type that only one routing path supports
- Tool-call semantic changes (e.g., parallel vs sequential tool execution)
- Pricing model changes that affect cost-ledger accuracy
- Capability removal (e.g., thinking traces dropped on one path)

The version bump triggers an operator-acknowledgment flow gated by sentinel file `${LOA_CACHE_DIR}/<provider>-fallback-version-acked`. Operators see a stderr warning until they ack the new version.

---

## Sprint planning template (copy-adapt)

When planning your provider-add cycle:

```
Sprint 0: Contract Verification Spike (BLOCKING for Sprint 1)
  - Live API probes (~6 calls)
  - Versioned `<provider>-contract-v1.json` fixture
  - Token lifecycle metadata capture
  - Backup account contact identification

Sprint 1: Provider v1 Functional
  - YAML SSOT entry
  - Python adapter
  - Bearer auth (or your auth modality)
  - Day-1 model coverage
  - Region/account configuration
  - Naming discipline (no default alias retargeting)
  - Health probe
  - Error taxonomy classifier
  - Cross-region profiles (if applicable)
  - Live integration test
  - Trust scope entries
  - Two-layer secret redaction
  - Adversarial redaction tests
  - Streaming non-support assertion (if v1 doesn't support streaming)
  - Token age sentinel (if Bearer + long-lived)
  - Compliance fallback (if same-model dual-routing applies)

Sprint 2: Plugin Guide + IR Runbook + Recurring Smoke + E2E
  - This guide (per-provider sections)
  - IR runbook ("If your <provider> token is compromised")
  - Recurring CI smoke workflow
  - Fixture evolution policy
  - Quarterly pricing-refresh reminder
  - Final E2E goal validation
```

---

## Incident-response runbook (NFR-Sec9 — your provider)

When a token is compromised or exposed:

1. **Immediate revocation** — vendor console (e.g., AWS → Bedrock → API keys → revoke; Anthropic → console.anthropic.com → API keys → revoke)
2. **Clear in-process redaction registry**:
   ```python
   from loa_cheval.config.redaction import clear_registered_values
   clear_registered_values()
   ```
   (or restart the process — the registry is process-scoped)
3. **Cache invalidation**:
   ```bash
   .claude/scripts/model-health-probe.sh --invalidate <provider>
   rm -f $LOA_CACHE_DIR/<provider>-token-age.json   # forces fresh sentinel on next call
   ```
4. **Audit-log query** — find calls made with the compromised token:
   ```bash
   jq -r 'select(.token_hint == "<last-4-of-SHA256>") | {timestamp, model_id, request_id}' \
     grimoires/loa/a2a/cost-ledger.jsonl
   ```
5. **Blast-radius assessment** — which Loa workflows used this token? Cross-reference cost-ledger entries against your sprint history
6. **Update env var** with new token; verify with `model-invoke --validate-bindings`
7. **Document incident** in `grimoires/loa/NOTES.md` Decision Log
8. **Update key rotation cadence** in NOTES if the compromise revealed a process gap

The cycle-095 cost guardrails (`max_cost_per_session_micro_usd` in `model-config.yaml`) provide a damage-cap layer — even a leaked token can't burn more than the session budget without surfacing a circuit-breaker trip.

---

## Test fixture conventions

When you commit fixture files (probe captures, contract versioned snapshots):

- **Always redact account IDs**, ARNs, region-specific account paths
- **Round timing values** to 100ms boundaries (precise timing fingerprints accounts)
- **Use `<acct>` placeholders** rather than `0000000` (signals redaction was applied)
- **Verify with `lib-security.sh redact_secrets`** that no token last-4-hash matches before commit
- **Per-version fixtures** (`v1.json`, `v2.json`): keep prior version in tree for one cycle as a regression backstop

---

## Lessons learned (cycle-096 — what the polished steps don't show)

The walkthrough above presents cycle-096 as a tidy six-edit-site pipeline. It wasn't. Future contributors should know what the iteration cost actually looked like so they budget accordingly and don't blame themselves when the same patterns surface again.

**The PRD/SDD changelog is the honest version of this guide.** Read these entries in order — each one is a finding that overturned a prior assumption:

- **PRD v1.0 → v1.1** (Flatline pass): added FR-12 region-prefix sanity, FR-13 thinking-trace translation, NFR-Sec8 token-age sentinel. Surfaced 5 BLOCKERS we did not see in the initial draft.
- **PRD v1.1 → v1.2**: added FR-11 daily-quota circuit breaker, NFR-Sec11 token lifecycle controls. Surfaced after live probes against operator account revealed quota semantics that public docs did not describe.
- **PRD v1.2 → v1.3**: added compliance_profile 4-step deterministic defaulting rule. Surfaced when prefer_bedrock without explicit fallback_to was found to be footgun-shaped under hostile config.
- **SDD v1.0 → v1.1** (Flatline pass): versioned `fallback_to` mapping field, value-based redaction promoted to PRIMARY (regex demoted to SECONDARY), threading.Event circuit breaker, Sprint 0 G-S0-CONTRACT artifact gate.
- **SDD v1.1 → v1.2**: §6.7 Bedrock feature flag (`hounfour.bedrock.enabled`) + migration sentinel after seeing how silently the defaulting rule changed operator behavior.

**Discoveries that arrived only via probes** (Sprint 0 G-S0-2), not by reading docs:

- **Bare `anthropic.*` model IDs are rejected** — Bedrock requires `us.anthropic.*` / `global.anthropic.*` inference profile IDs. The error is HTTP 400 ("on-demand throughput unsupported"), not 404.
- **`thinking.type=enabled` is rejected** by Bedrock-routed Opus 4.7 — Bedrock requires `adaptive`, with `output_config.effort` instead of `budget_tokens`. Adapter must translate.
- **`tools` schema requires `inputSchema.json` envelope wrapping** — direct-Anthropic accepts the schema directly; Bedrock wraps it.
- **Token format is `ABSKR…` (5-char prefix), 40+ chars** — important for the value-based redaction path and the secret_env_allowlist regex.
- **End-of-life models return HTTP 404** while invalid identifiers return HTTP 400 — error-classifier must branch on body content, not just status code (see `tests/fixtures/bedrock/probes/E2-404-not-found.json` vs `E3-404-end-of-life.json`).

**Process patterns that paid off**:

- **Two-pass Flatline review on PRD/SDD before sprint planning** — caught structural issues that would have cascaded through implementation.
- **Live probes (Sprint 0) before any code** — cycle-096 G-S0-CONTRACT artifact (`tests/fixtures/bedrock/contract/v1.json`) became the single source of truth across the implementation. Future providers should follow the same pattern.
- **Bridgebuilder review on the cycle-096 PR** caught fixture hygiene findings (account ID prose leak in `redaction_notes`, mislabeled E3 fixture status code) that escaped both the senior reviewer and the security auditor.

**What this guide cannot anticipate** for the next provider:

- Vendor onboarding (account setup, IAM, billing approvals)
- Domain-specific I/O shape edge cases (Mistral's chat templates, Cohere reranking models)
- Regression cost when `model-permissions.yaml` trust scopes need to widen

Treat the "≤1-day" target as aspirational until cycle-097+ provides empirical data. Update *this guide* — not just your own NOTES.md — when you discover the next missed pattern.

**Cycle-096 artifact pointers** (read these before starting):

- **PR #662** (`feat/cycle-096-aws-bedrock`) — full diff, review/audit comments, Bridgebuilder findings. The git history is the durable record (`grimoires/loa/archive/` is gitignored).
- `tests/fixtures/bedrock/contract/v1.json` and `tests/fixtures/bedrock/probes/README.md` (the contract you are extending — committed in cycle-096)
- `git log --grep="cycle-096" --oneline` — 18 cycle-096 commits show the iteration order: probes first, then PRD/SDD, then implementation, then hardening
- Specific learning commits worth reading:
  - `73431db feat(cycle-095): model currency` — sets up the model registry that cycle-096 extends
  - `e9e5805 fix(cheval): Opus 4 temperature gate + Google/Gemini API key allowlist` — the multi-provider redaction patterns cycle-096's two-layer redaction generalizes

---

*This guide is the FR-9 deliverable for cycle-096 Sprint 2 (Task 2.3). When the next provider lands and uncovers a missed pattern, please update this guide rather than discovering it again.*
