# PRD: Declarative Execution Router + Adaptive Multi-Pass Review

> Cycle: cycle-034 | Author: soju + Claude
> Predecessor: cycle-033 (Codex CLI Integration for GPT Review)
> Source: [#403](https://github.com/0xHoneyJar/loa/issues/403) (Bridgebuilder review findings)
> Design Context: Bridgebuilder review of [PR #401](https://github.com/0xHoneyJar/loa/pull/401)
> Priority: P1 — architectural maturation of review pipeline from cycle-033

---

## 1. Problem Statement

Cycle-033 introduced a 3-tier execution router (`route_review()` in `gpt-review-api.sh:91-147`) that cascades through Hounfour → Codex → curl. The implementation is functional and well-tested (117 tests, bridge flatlined at 0), but the control flow is **imperative** — a 56-line if/else cascade that hard-codes backend selection logic, condition checking, and fallback semantics in bash.

This creates three problems:

1. **Operator rigidity**: Adding, removing, or reordering backends requires modifying `route_review()` — a critical function where bugs have high blast radius. Operators cannot customize routing without code changes.

2. **Fixed review depth**: The multi-pass sandwich always runs 3 passes (xhigh→high→xhigh) regardless of change complexity. A 50-line single-file fix gets the same 3 Codex invocations as a 5,000-line, 40-file refactor. This wastes API budget on simple changes and may under-review complex ones.

3. **Token estimation drift**: The chars/4 fallback heuristic in `estimate_token_count()` can be 40-50% wrong for code with heavy punctuation, causing budget enforcement to make incorrect truncation decisions.

> Sources: PR #401 Bridgebuilder review [Part 2](https://github.com/0xHoneyJar/loa/pull/401#issuecomment-3943330704), [Part 3](https://github.com/0xHoneyJar/loa/pull/401#issuecomment-3943331305)

---

## 2. Vision

A review pipeline where **routing is data, not code** — operators configure execution backends, conditions, and fallback behavior in `.loa.config.yaml`, and the pipeline adapts review depth to content complexity. Configuration becomes a first-class, diffable, auditable artifact.

**FAANG parallel**: Envoy Proxy replaced hand-coded service routing with declarative YAML configuration. The effect: operators changed traffic routing without deploying code, and routing rules entered version control alongside application config.

---

## 3. Goals & Success Metrics

### G1: Declarative Execution Router
**Metric**: Zero imperative backend-selection logic in `route_review()`. All routing decisions driven by YAML configuration.
**Acceptance**: `route_review()` reduced from 56 lines of if/else to a generic loop over a parsed route table.

### G2: Adaptive Multi-Pass
**Metric**: Pass count varies based on Pass 1 complexity analysis. Simple changes get 1 pass; complex changes get 3.
**Acceptance**: A test demonstrating that a small diff triggers single-pass mode while a large diff triggers 3-pass mode.

### G3: Token Estimation Accuracy (Flatline IMP-009)
**Metric**: Mean estimation error ≤15% for code content (currently up to 50% with chars/4). Measured as p95 ≤25%.
**Acceptance**: Word-count fallback tier reduces estimation error against a **benchmark corpus** of ≥10 code samples with pre-computed tiktoken token counts. Test asserts mean error ≤15% and p95 ≤25% across the corpus.

### G4: Technical Quality Improvements
**Metric**: Capability detection caches help text; JSON extraction handles arbitrary nesting.
**Acceptance**: Tests pass for deeply nested JSON; capability detection makes exactly 1 subprocess call.

### G5: Backward Compatibility (Flatline SKP-002)
**Metric**: Zero regression in existing 117 tests. Behavioral equivalence at failure boundaries.
**Acceptance**: All existing tests pass without modification. Users with no `gpt_review.routes` config get identical behavior to cycle-033. **Golden tests** assert exact backend selection sequences, exit codes, and logging for representative failure modes (backend unavailable, invalid JSON, auth error, timeout).

### G6: Config-to-Code Tracing (Flatline IMP-006)
**Metric**: Every routing decision can be traced from YAML config to executed code path.
**Acceptance**: Startup logs the effective route table (backend names, conditions, fail modes) and its SHA-256 hash. Each backend attempt logs `[route-table] trying backend=X, conditions=[Y,Z], result=success|fail`.

---

## 4. Functional Requirements

### FR-1: Declarative Routing Table (P0)

#### FR-1.1: YAML Schema

```yaml
# .loa.config.yaml
gpt_review:
  enabled: true
  routes:
    - backend: hounfour
      when:
        - flatline_routing_enabled
        - model_invoke_available
      capabilities: [agent_binding, metering, trust_scopes]
      fail_mode: fallthrough  # fallthrough | hard_fail

    - backend: codex
      when:
        - codex_available
      capabilities: [sandbox, ephemeral, multi_pass, tool_access]
      fail_mode: fallthrough

    - backend: curl
      when: [always]
      capabilities: [basic]
      fail_mode: hard_fail  # last resort — failure is terminal
```

- `backend`: identifies which execution function to call
- `when`: list of condition names that must ALL be true (AND logic)
- `capabilities`: metadata for downstream decision-making (e.g., multi-pass only if backend has `multi_pass`)
- `fail_mode`: `fallthrough` continues to next route on failure; `hard_fail` returns error immediately

#### FR-1.2: Condition Registry

Conditions are named boolean functions registered at startup:

| Condition | Implementation |
|-----------|---------------|
| `flatline_routing_enabled` | `is_flatline_routing_enabled()` from lib-curl-fallback.sh |
| `model_invoke_available` | `[[ -x "$MODEL_INVOKE" ]]` |
| `codex_available` | `codex_is_available` from lib-codex-exec.sh (exit 0) |
| `always` | Built-in, always true |

New conditions can be added by registering a function name in a bash associative array.

#### FR-1.3: Backend Registry

Backends are named execution functions:

| Backend | Function | Library |
|---------|----------|---------|
| `hounfour` | `call_api_via_model_invoke` | lib-curl-fallback.sh |
| `codex` | Codex exec path (single or multi-pass) | lib-codex-exec.sh |
| `curl` | `call_api` | lib-curl-fallback.sh |

#### FR-1.4: Schema Validation (Flatline IMP-001)

Route table MUST be validated at parse time with strict rules:

| Rule | Behavior on Violation |
|------|----------------------|
| `backend` is required string, must be in backend registry | Hard error, exit 2 |
| `when` is required non-empty array of strings | Hard error, exit 2 |
| `fail_mode` is optional, must be `fallthrough` or `hard_fail` | Default `fallthrough`, warn |
| At least one route must exist | Hard error, exit 2 |
| Last route should be `hard_fail` (advisory) | Warning only |
| Condition names must be in condition registry | Treat as `false`, warn |
| No duplicate backend names | Warning only (first wins) |

When custom routes are present and invalid: **fail-closed** (hard error, non-zero exit).
When no custom routes present: **fail-open** (use built-in defaults, log reason).

#### FR-1.5: Schema Version (Flatline IMP-005)

Route table includes a version field for forward compatibility:

```yaml
gpt_review:
  route_schema: 1  # Semantic version for route table format
  routes: [...]
```

Parser rejects `route_schema > 1` with a clear upgrade message.

#### FR-1.6: Default Config

When no `gpt_review.routes` key exists in config, the router uses a built-in default that exactly matches cycle-033 behavior:

```
hounfour (fallthrough) → codex (fallthrough) → curl (hard_fail)
```

This ensures **zero breaking changes** for existing installations.

#### FR-1.7: `execution_mode` Override

The existing `gpt_review.execution_mode` config key (`auto`, `codex`, `curl`) continues to work as a shorthand:
- `curl`: filters routes to only `curl` backend
- `codex`: filters routes to only `codex` and `curl` backends, `codex` in hard_fail mode
- `auto`: uses full route table

If both `execution_mode` and `routes` are specified, `routes` takes precedence.

#### FR-1.8: Backend Result Contract (Flatline IMP-002)

All backends must return output that passes `validate_review_result()`:

| Check | Requirement |
|-------|-------------|
| JSON validity | `jq empty` succeeds |
| Required field | `.verdict` exists and is one of `APPROVED`, `CHANGES_REQUIRED`, `DECISION_NEEDED` |
| Minimum length | Response ≥ 20 characters |
| Schema compliance | `.findings` is array if present |

A backend that returns exit 0 but fails validation is treated as **failure** (fallthrough to next route).

#### FR-1.9: Capability Gating (Flatline IMP-007)

When multi-pass mode is requested, the router checks the selected backend's `capabilities` array:
- If backend has `multi_pass` → execute multi-pass
- If backend lacks `multi_pass` → downgrade to single-pass with warning
- If no backend with `multi_pass` is available → use combined prompt on selected backend

Capability checks happen AFTER route selection, not during. The router selects the first available backend, then the multipass orchestrator checks capabilities.

#### FR-1.10: Golden Tests (Flatline IMP-004)

Add behavioral equivalence tests that assert the exact sequence of attempted backends for representative scenarios:

| Scenario | Expected Sequence |
|----------|------------------|
| All backends available | `hounfour` (success) |
| Hounfour fails, codex available | `hounfour` (fail) → `codex` (success) |
| Hounfour + codex fail | `hounfour` (fail) → `codex` (fail) → `curl` (success) |
| `execution_mode: curl` | `curl` (success) |
| `execution_mode: codex`, codex unavailable | `codex` (hard fail) |
| Backend returns invalid JSON | Backend (fail validation) → next route |
| Empty route table after filtering | Hard error, exit 2 |

### FR-2: Adaptive Multi-Pass (P1)

#### FR-2.1: Dual-Signal Complexity Classification (Flatline IMP-003)

Classification uses BOTH deterministic diff signals AND model-produced complexity analysis. Single-pass mode requires agreement from both signals.

**Deterministic signals** (computed before any API call):

| Signal | Source | Low Threshold | High Threshold |
|--------|--------|---------------|----------------|
| Files changed | `git diff --stat` | ≤3 files | >15 files |
| Lines changed | `git diff --stat` | ≤200 lines | >2000 lines |
| Security-sensitive paths | denylist match | 0 matches | any match → never single-pass |

**Model signals** (from Pass 1 output):

| Signal | Source | Low Threshold | High Threshold |
|--------|--------|---------------|----------------|
| Risk areas | Pass 1 `risk_area_count` | ≤3 | >6 |
| Scope tokens | Pass 1 output size | ≤500 tokens | >2000 tokens |

**Classification matrix**:

| Deterministic | Model | Result |
|---------------|-------|--------|
| Low | Low | `low` → single-pass |
| Low | Medium/High | `medium` → 3-pass |
| Medium/High | Low | `medium` → 3-pass |
| Medium/High | Medium | `medium` → 3-pass |
| Any | High | `high` → 3-pass with extended budgets |
| Security-sensitive | Any | `high` → always 3-pass |

#### FR-2.2: Configuration

```yaml
gpt_review:
  multipass:
    adaptive: true  # false = always 3-pass (cycle-033 behavior)
    thresholds:
      low_risk_areas: 3
      low_scope_tokens: 500
      high_risk_areas: 6
      high_scope_tokens: 2000
    budgets:
      high_complexity:
        pass2_input: 30000   # up from default 20000
        pass2_output: 10000  # up from default 6000
```

#### FR-2.3: Pass 1 Schema Extension

Pass 1 prompt already asks for `scope_analysis, dependency_map, risk_areas, test_gaps`. Add a structured complexity field:

```json
{
  "complexity": {
    "risk_area_count": 5,
    "files_affected": 12,
    "scope_category": "medium"
  }
}
```

If Pass 1 doesn't return a valid complexity field, default to `medium` (3-pass).

### FR-3: Token Estimation Improvement (P2)

#### FR-3.1: Three-Tier Estimation

```
Tier 1: tiktoken (python3, ≤5% error)
Tier 2: word-count heuristic (~1.33 tokens/word, ≤15% error for code)
Tier 3: chars/4 heuristic (≤10% error for English, up to 50% for code)
```

The word-count tier uses `wc -w` with a multiplier:
```bash
echo $(( (word_count * 4 + 2) / 3 ))  # ~1.33 tokens per word
```

### FR-4: Capability Detection Optimization (P2)

#### FR-4.1: Cache Help Text

`detect_capabilities()` should invoke `codex exec --help` exactly once, cache the output, and grep against it for each flag:

```bash
local help_text
help_text=$(codex exec --help 2>&1) || true

for flag in "${_CODEX_PROBE_FLAGS[@]}"; do
  # grep against $help_text, not a fresh subprocess
done
```

### FR-5: Robust JSON Extraction (P2)

#### FR-5.1: Python3 JSON Decoder Fallback

After the regex-based greedy extraction (2-level nesting) fails, try `python3 -c` with `json.JSONDecoder().raw_decode()`:

```bash
greedy=$(printf '%s' "$raw" | python3 -c "
import json, sys
s = sys.stdin.read()
idx = s.index('{')
obj, _ = json.JSONDecoder().raw_decode(s[idx:])
print(json.dumps(obj))
" 2>/dev/null) || greedy=""
```

This handles arbitrary nesting depth and is correct by construction.

---

## 5. Non-Functional Requirements

### NFR-1: Backward Compatibility
All 117 existing tests must pass without modification. The default route table must produce identical behavior to cycle-033's imperative router.

### NFR-2: Performance
Route table parsing happens once at startup (not per-review). YAML is parsed via `yq` and cached in bash associative arrays.

### NFR-3: Security
- No new secret patterns introduced
- Route conditions must not evaluate arbitrary code (named functions only, no `eval`)
- Env-only auth boundary unchanged

### NFR-4: Testability
Each new component must be independently testable:
- Route table parser: test with fixture YAML files
- Condition registry: test each condition in isolation
- Adaptive multi-pass: test complexity classification with mock Pass 1 outputs
- Token estimation: test against known code samples with pre-computed token counts

---

## 6. Scope & Prioritization

### In Scope (MVP)

| Priority | Feature | Risk |
|----------|---------|------|
| P0 | Declarative routing table (FR-1) | Medium — core refactor |
| P1 | Adaptive multi-pass (FR-2) | Low — extends existing |
| P2 | Token estimation improvement (FR-3) | Low — additive |
| P2 | Capability detection optimization (FR-4) | Low — constant-factor |
| P2 | Robust JSON extraction (FR-5) | Low — additive |

### Out of Scope

- **Custom condition expressions**: FR-1.2 uses named functions, not arbitrary expression evaluation. Custom conditions require code changes.
- **Multi-backend parallelism**: Routes are tried sequentially (first success wins). Parallel execution across backends is deferred.
- **Auth boundary refactor**: The Hounfour vs shell-level auth relationship is documented but not changed. Reconciliation deferred to a future Hounfour protocol cycle.
- **Declarative prompt templates**: Prompt construction remains in code. Only routing is declarative.
- **Cost tracking integration**: Per-pass cost attribution via Freeside metering is noted as a future direction but not implemented here.

---

## 7. Risks & Dependencies

### R1: YAML Parsing Reliability (Flatline SKP-001)
**Risk**: `yq` must be available. Config parsing errors could silently fall back to defaults. YAML edge cases (empty arrays, nulls, anchors, multiline strings) are common and hard to handle safely in bash.
**Mitigation**: Strict schema validation via `validate_route_table()`. **Fail-closed** when custom routes are present (hard error, non-zero exit). **Fail-open** only when no custom routes exist (use built-in defaults). Emit explicit `using default routes because: <reason>` log line. Test against multiple yq v4 minor versions and YAML edge cases.

### R2: Condition Function Injection
**Risk**: If condition names are evaluated dynamically, an attacker could inject function names.
**Mitigation**: Condition registry is a fixed associative array populated at source time. Only registered condition names are accepted. Unknown conditions are treated as false with a warning.

### R3: Adaptive Multi-Pass Model Compliance (Flatline SKP-004)
**Risk**: Pass 1 may not return the expected `complexity` field if the model ignores schema instructions. Prompt injection in diff content could game the classifier.
**Mitigation**: **Dual-signal classification** — do NOT base pass reduction solely on model output. Require BOTH deterministic signals from the diff itself (files changed, lines changed, presence of security-sensitive paths) AND model-produced complexity field to enter single-pass mode. Add injection-resistant parsing (strict JSON extraction + schema validation). Maintain a `never-single-pass` denylist for critical file patterns (`.claude/`, `lib-security.sh`, auth modules).

### R3.1: Failure Semantics (Flatline SKP-003)
**Risk**: In bash, commands can return success while producing unusable output (empty JSON, truncated response, schema mismatch). If the router treats that as success, it delivers garbage. If it treats too many cases as failure, it cascades to curl unnecessarily.
**Mitigation**: Standardize **backend result contract**: required fields (`verdict`), minimum length, JSON validity, schema compliance. Implement a shared `validate_review_result()` gate that determines success/failure consistently across all backends. Document and test fallthrough behavior for invalid, empty, or schema-noncompliant output.

### R3.2: Supply-Chain Risk in CI (Flatline SKP-006)
**Risk**: If an attacker modifies `.loa.config.yaml` (or compromised repo does), they can force expensive routes, disable fallbacks, or create configurations that hang.
**Mitigation**: Policy constraints: max routes (default 10), max total attempts, max total time per review. Allow/deny lists for backends in CI. Require explicit opt-in for non-default routing in CI via `LOA_CUSTOM_ROUTES=1` environment variable. Log effective route table hash at startup for auditability.

### R4: Dependency on cycle-033
**Risk**: This cycle modifies files created in cycle-033. If PR #401 is not merged, this cycle's changes will conflict.
**Mitigation**: Branch from `feat/cycle-033-codex-integration` or from `main` after PR #401 merges.

---

## 8. Technical Constraints

- **Shell only**: All changes are in bash scripts (`.claude/scripts/`). No new languages or runtimes.
- **yq v4+ required**: Route table parsing uses `yq eval` with array iteration.
- **python3 optional**: Used for tiktoken (Tier 1) and JSON decoder fallback (FR-5). Absence degrades gracefully.
- **Existing library structure**: Changes to `lib-codex-exec.sh`, `lib-curl-fallback.sh`, `lib-multipass.sh`, and `gpt-review-api.sh`. New library: `lib-route-table.sh`.
- **Test framework**: bats-core for all new tests.
