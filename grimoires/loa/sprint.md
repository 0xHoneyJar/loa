# Sprint Plan: Declarative Execution Router + Adaptive Multi-Pass

> Cycle: cycle-034
> PRD: `grimoires/loa/prd.md`
> SDD: `grimoires/loa/sdd.md`
> Team: 1 AI developer
> Sprint duration: 1 sprint per session

---

## Sprint Overview

| Sprint | Global ID | Label | Goal |
|--------|-----------|-------|------|
| sprint-1 | sprint-41 | Core Route Table Infrastructure | Replace imperative router with declarative route table |
| sprint-2 | sprint-42 | Adaptive Multi-Pass + Token Estimation | Dynamic pass count + word-count estimation tier |
| sprint-3 | sprint-43 | Polish + Hardening | Capability caching, JSON fallback, result contract tests, CI policy |

**MVP**: Sprint 1 delivers the declarative router. Sprint 2 delivers adaptive multi-pass. Sprint 3 is hardening.

**Risk**: Sprint 1 is the highest-risk sprint (core routing refactor). Sprints 2-3 are additive.

---

## Sprint 1: Core Route Table Infrastructure

**Goal**: Replace the 56-line imperative `route_review()` with a declarative route table. All routing decisions driven by YAML configuration. Zero behavioral change for existing users.

**Global ID**: sprint-41

### Tasks

#### Task 1.1: Create lib-route-table.sh — Data Structures + Defaults

**Description**: Create `.claude/scripts/lib-route-table.sh` with parallel array data structures (`_RT_BACKENDS`, `_RT_CONDITIONS`, `_RT_CAPABILITIES`, `_RT_FAIL_MODES`, `_RT_TIMEOUTS`, `_RT_RETRIES`), associative array registries (`_CONDITION_REGISTRY`, `_BACKEND_REGISTRY`), and the default route table loader (`_rt_load_defaults()`).

**Acceptance Criteria**:
- [ ] File exists at `.claude/scripts/lib-route-table.sh`
- [ ] All 6 parallel arrays declared
- [ ] Both associative array registries declared
- [ ] `_rt_load_defaults()` loads hounfour → codex → curl cascade matching cycle-033 behavior
- [ ] `register_builtin_conditions()` maps 4 condition names to functions
- [ ] `register_builtin_backends()` maps 3 backend names to wrapper functions
- [ ] Backend wrappers (`_backend_hounfour`, `_backend_codex`, `_backend_curl`) call existing library functions
- [ ] No `eval` or dynamic function construction
- [ ] `_rt_validate_array_lengths()` asserts all `_RT_*` arrays have identical length before execution (Flatline SKP-002: parallel array desync guard)
- [ ] All append operations go through `_rt_append_route()` helper that atomically appends to all 6 arrays (Flatline SKP-002)

**Effort**: Medium
**Dependencies**: None

#### Task 1.2: Implement parse_route_table() + validate_route_table()

**Description**: YAML parser using `yq eval` to populate parallel arrays from `.loa.config.yaml`. Schema validation with fail-closed for custom routes, fail-open for defaults. Schema version check (rejects `route_schema > 1`). yq-missing detection with `LOA_ALLOW_DEFAULTS_WITHOUT_YQ` override (Flatline IMP-004).

**Acceptance Criteria**:
- [ ] `parse_route_table()` reads YAML routes into `_RT_*` arrays
- [ ] Falls back to `_rt_load_defaults()` when no `gpt_review.routes` in config
- [ ] Rejects `route_schema > 1` with clear upgrade message
- [ ] `validate_route_table()` checks: backend required + registered, when non-empty, fail_mode enum, at least one route, max routes policy (10)
- [ ] Fail-closed: custom routes with errors → exit 2
- [ ] Fail-open: no custom routes → use defaults with log
- [ ] yq-missing + config has routes → fail-closed (exit 2) unless `LOA_ALLOW_DEFAULTS_WITHOUT_YQ=1`
- [ ] yq v3 vs v4 detection: check `yq --version` for v4+ and reject v3 with clear error message (Flatline IMP-003)
- [ ] `LOA_ALLOW_DEFAULTS_WITHOUT_YQ` illegal in CI (`CI=true`) — always fail-closed (Flatline SKP-001)
- [ ] Per-route `timeout` and `retries` fields parsed with validation bounds: timeout 1-600s, retries 0-5 (Flatline IMP-002, SKP-005)
- [ ] Canonical YAML schema example included as comment block in lib-route-table.sh header (Flatline IMP-004)

**Effort**: Medium
**Dependencies**: Task 1.1

#### Task 1.3: Implement execute_route_table() + _evaluate_conditions()

**Description**: The main execution loop that replaces imperative routing. Iterates routes in order, evaluates AND conditions, calls backend, validates result, handles fallthrough/hard_fail. Per-route timeout and retry support (Flatline IMP-002).

**Acceptance Criteria**:
- [ ] `execute_route_table()` iterates routes, first success wins
- [ ] `_evaluate_conditions()` implements AND logic over comma-separated condition names with whitespace trimming and empty-token rejection (Flatline SKP-003)
- [ ] Unknown conditions evaluate as false for defaults, validation error for custom routes (fail-closed) (Flatline SKP-003)
- [ ] Per-route timeout overrides global timeout (clamped to 1-600s)
- [ ] Per-route retries with `[route-table] retry N/M` logging (clamped to 0-5)
- [ ] Global max attempts cap: `_RT_MAX_TOTAL_ATTEMPTS` (default 10) — stops iteration if total attempts across all routes exceeds cap (Flatline SKP-005)
- [ ] Retry policy: retries apply to non-zero exit AND invalid JSON output; timeouts count as non-zero exit (Flatline SKP-005)
- [ ] Backend result validated via `validate_review_result()`
- [ ] `fallthrough` continues to next route; `hard_fail` returns exit 2
- [ ] All routes exhausted → exit 2
- [ ] Each attempt logged: `[route-table] trying backend=X, conditions=[Y], result=success|fail`

**Effort**: Medium
**Dependencies**: Task 1.1, Task 1.2

#### Task 1.4: Implement validate_review_result()

**Description**: Shared backend result contract gate (PRD FR-1.8). Checks JSON validity, required `verdict` field with enum, minimum length, and `findings` array type.

**Acceptance Criteria**:
- [ ] Returns 0 for valid result, 1 for invalid
- [ ] Checks: JSON validity via `jq empty`, `verdict` exists and is one of `APPROVED|CHANGES_REQUIRED|DECISION_NEEDED|SKIPPED`, length ≥ 20, `findings` is array if present
- [ ] Verdict-to-exit-code truth table defined and tested (Flatline IMP-006):
  - `APPROVED` → exit 0 (pipeline continues)
  - `CHANGES_REQUIRED` → exit 0 (pipeline continues, findings surfaced)
  - `DECISION_NEEDED` → exit 0 (pipeline continues, flagged for human)
  - `SKIPPED` → exit 0 (pipeline continues, logged as no-review)
  - Invalid/missing verdict → exit 1 (fallthrough to next route)
- [ ] Logs specific warning for each validation failure
- [ ] Backend returning exit 0 + garbage is treated as failure (fallthrough)

**Effort**: Small
**Dependencies**: None

#### Task 1.5: Implement init_route_table() + log_route_table() + _rt_apply_execution_mode()

**Description**: Single initialization entrypoint (idempotent, clears previous state per Flatline IMP-001). Config-to-code tracing (PRD G6). Execution mode filter for legacy `execution_mode` config key.

**Acceptance Criteria**:
- [ ] `init_route_table()` clears `_RT_*` arrays before populating (idempotency)
- [ ] Calls register → parse → CI opt-in check → validate in sequence
- [ ] CI opt-in: custom routes in CI require `LOA_CUSTOM_ROUTES=1`
- [ ] `log_route_table()` emits effective route table + SHA-256 hash to stderr
- [ ] `_rt_apply_execution_mode()` filters routes for `codex` and `curl` modes
- [ ] `auto` mode leaves table unmodified
- [ ] `codex` mode keeps codex (hard_fail) + curl
- [ ] `curl` mode keeps curl only (hard_fail)

**Effort**: Medium
**Dependencies**: Task 1.2, Task 1.3

#### Task 1.6: Legacy Router Kill-Switch (Flatline IMP-001)

**Description**: Add `LOA_LEGACY_ROUTER=1` env var that bypasses the declarative route table and uses the cycle-033 imperative `route_review()` implementation. Critical for production rollback if subtle regressions are discovered post-deployment.

**Acceptance Criteria**:
- [ ] When `LOA_LEGACY_ROUTER=1`, `route_review()` uses the original imperative implementation
- [ ] Legacy implementation preserved in `_route_review_legacy()` function
- [ ] Log line emitted: `[route-table] using legacy router (LOA_LEGACY_ROUTER=1)`
- [ ] Test verifying legacy router produces identical output to declarative router for default config
- [ ] Documented in lib-route-table.sh header comments

**Effort**: Small
**Dependencies**: Task 1.5

#### Task 1.7: Refactor route_review() in gpt-review-api.sh

**Description**: Replace the 56-line imperative `route_review()` with ~15 lines that: (1) `source lib-route-table.sh`, (2) call `init_route_table()`, (3) apply `execution_mode` filter, (4) `log_route_table()`, (5) `execute_route_table()`. Behavioral equivalence with cycle-033. Includes `LOA_LEGACY_ROUTER` check at top.

**Acceptance Criteria**:
- [ ] `route_review()` reduced from 56 to ~15 lines
- [ ] `source lib-route-table.sh` added near top of gpt-review-api.sh
- [ ] Zero imperative backend-selection logic remains (G1)
- [ ] Default behavior (no config) identical to cycle-033
- [ ] `execution_mode` override still works (auto/codex/curl)
- [ ] Both `execution_mode` and `routes` present → `routes` wins with warning
- [ ] Configuration precedence matrix enforced (Flatline IMP-009): `LOA_LEGACY_ROUTER` > `LOA_CUSTOM_ROUTES` > `execution_mode` > `routes` > defaults

**Effort**: Medium
**Dependencies**: Task 1.5, Task 1.6

#### Task 1.8: Golden Tests for Backend Selection Sequences

**Description**: Behavioral equivalence tests (PRD FR-1.10) asserting exact backend selection sequences for 7 representative scenarios. Uses mock backends via stub functions.

**Acceptance Criteria**:
- [ ] Tests in `.claude/scripts/tests/test-gpt-review-route-table.bats`
- [ ] 7 golden tests: all available, hounfour fails, full cascade, curl only, codex hard fail, invalid JSON, empty table
- [ ] Each test asserts exact sequence of attempted backends via log inspection
- [ ] Mock backends return configurable success/failure
- [ ] All 7 tests pass

**Effort**: Medium
**Dependencies**: Task 1.7

#### Task 1.9: Route Table Parser Tests

**Description**: Unit tests for `parse_route_table()` and `validate_route_table()` with YAML fixture files.

**Acceptance Criteria**:
- [ ] Tests in `.claude/scripts/tests/test-gpt-review-route-table.bats` (same file)
- [ ] 9 parser tests: valid 3 routes, empty routes, unknown backend, unknown condition, schema v2, max routes exceeded, missing when, invalid fail_mode, duplicate backend
- [ ] YAML fixture files in `.claude/scripts/tests/fixtures/gpt-review/route-configs/`
- [ ] All 9 tests pass
- [ ] All 117 existing tests still pass (regression)

**Effort**: Medium
**Dependencies**: Task 1.7

#### Task 1.10: Adversarial YAML Security Tests (Flatline IMP-010, SKP-010)

**Description**: Negative security tests with adversarial YAML fixture files to verify no injection, no eval, and safe handling of untrusted config values.

**Acceptance Criteria**:
- [ ] Adversarial YAML fixtures: shell injection in backend name, command substitution in condition name, extreme timeout (999999), extreme retries (999), YAML anchors/aliases, multiline strings in field values
- [ ] All adversarial fixtures handled safely (rejected or clamped, never executed)
- [ ] Backend names validated against registry before any function call
- [ ] Condition names validated against registry before any function call
- [ ] Timeout/retry values clamped to bounds (1-600s, 0-5)
- [ ] Tests in `test-gpt-review-route-table.bats`

**Effort**: Small
**Dependencies**: Task 1.9

---

## Sprint 2: Adaptive Multi-Pass + Token Estimation

**Goal**: Multi-pass review depth adapts to change complexity. Simple changes get 1 pass; complex changes get 3. Token estimation improved with word-count tier.

**Global ID**: sprint-42

### Tasks

#### Task 2.1: Implement classify_complexity()

**Description**: Deterministic complexity classifier in `lib-multipass.sh` using diff signals: files changed, lines changed, security-sensitive path denylist.

**Acceptance Criteria**:
- [ ] Function in `lib-multipass.sh` returning "low" | "medium" | "high"
- [ ] Counts files changed from `diff --git` markers
- [ ] Counts lines changed from `+`/`-` markers
- [ ] Security-sensitive denylist: `.claude/`, `lib-security`, `auth`, `credentials`, `secrets`, `.env`
- [ ] Security hit → always "high"
- [ ] >15 files OR >2000 lines → "high"
- [ ] >3 files OR >200 lines → "medium"
- [ ] Otherwise → "low"

**Effort**: Small
**Dependencies**: Sprint 1

#### Task 2.2: Implement reclassify_with_model_signals()

**Description**: Post-Pass-1 reclassifier combining deterministic signals with model-produced complexity. Single-pass requires BOTH signals low (PRD FR-2.1 dual-signal matrix).

**Acceptance Criteria**:
- [ ] Function in `lib-multipass.sh` taking `det_level` and `pass1_output`
- [ ] Extracts `risk_area_count` and estimates scope tokens from Pass 1 output
- [ ] Reads configurable thresholds from `.gpt_review.multipass.thresholds.*`
- [ ] Model level: risk_areas ≤ low_risk AND scope ≤ low_scope → "low"; risk_areas > high_risk OR scope > high_scope → "high"; else "medium"
- [ ] Dual-signal: BOTH low → "low"; EITHER high → "high"; else "medium"
- [ ] Missing complexity field defaults to "medium" (never single-pass)

**Effort**: Small
**Dependencies**: Task 2.1

#### Task 2.3: Modify run_multipass() for Adaptive Flow

**Description**: Integrate adaptive classification into the existing 3-pass orchestrator. When `multipass.adaptive: true` (default), classify before deciding pass count. Pass 1 always runs. Decision between Pass 1 and Pass 2.

**Acceptance Criteria**:
- [ ] Reads `adaptive` config key (default true)
- [ ] If `adaptive: false` → unchanged 3-pass behavior
- [ ] If adaptive: calls `classify_complexity()` before Pass 1
- [ ] After Pass 1: calls `reclassify_with_model_signals()` for final level
- [ ] `low` → returns Pass 1 output as combined review
- [ ] `high` → uses extended budgets from config for Pass 2
- [ ] `medium` → standard 3-pass
- [ ] Extended budgets configurable: `pass2_input` (default 30000), `pass2_output` (default 10000)

**Effort**: Medium
**Dependencies**: Task 2.1, Task 2.2

#### Task 2.4: Update estimate_token_count() — Word-Count Tier

**Description**: Insert word-count tier between tiktoken (Tier 1) and chars/4 (Tier 3) in `lib-multipass.sh`. Uses `wc -w * 4/3` formula.

**Acceptance Criteria**:
- [ ] Tier 2 inserted between existing Tier 1 and Tier 3
- [ ] Formula: `(word_count * 4 + 2) / 3` (integer arithmetic)
- [ ] Falls through to chars/4 only if `wc -w` returns 0
- [ ] No new dependencies (wc is always available)

**Effort**: Small
**Dependencies**: Sprint 1

#### Task 2.5: Token Estimation Benchmark Corpus

**Description**: Create ≥10 code sample files with pre-computed tiktoken token counts. Test asserts word-count tier mean error ≤15% and p95 ≤25%.

**Acceptance Criteria**:
- [ ] Fixture files in `.claude/scripts/tests/fixtures/gpt-review/token-corpus/`
- [ ] ≥10 code samples: mix of bash, Python, JavaScript, JSON, prose
- [ ] Each sample has companion `.tokens` file with tiktoken count
- [ ] Test in `test-gpt-review-adaptive.bats` computes mean and p95 error
- [ ] Mean error ≤15%, p95 ≤25% for word-count tier

**Effort**: Medium
**Dependencies**: Task 2.4

#### Task 2.6: Adaptive Multi-Pass Tests

**Description**: Tests for `classify_complexity()`, `reclassify_with_model_signals()`, and the adaptive flow in `run_multipass()`.

**Acceptance Criteria**:
- [ ] Tests in `.claude/scripts/tests/test-gpt-review-adaptive.bats`
- [ ] 6 tests: small diff both low (1 pass), large diff det high (3 pass), security path (3 pass), det low model high (3 pass), det high model low (3 pass), adaptive disabled (3 pass)
- [ ] Mock diff content with known file/line counts
- [ ] Mock Pass 1 output with known complexity fields
- [ ] All 6 tests pass

**Effort**: Medium
**Dependencies**: Task 2.3

---

## Sprint 3: Polish + Hardening

**Goal**: Optimize capability detection, add JSON extraction fallback, add result contract tests, enforce CI policy constraints. Full regression verification.

**Global ID**: sprint-43

### Tasks

#### Task 3.1: Optimize detect_capabilities() — Cached Help Text

**Description**: Hoist `codex exec --help` call above the flag-probing loop in `lib-codex-exec.sh`. Single subprocess call instead of N calls.

**Acceptance Criteria**:
- [ ] `codex exec --help` called exactly once per `detect_capabilities()` invocation
- [ ] Help text stored in local variable, grep'd per flag
- [ ] Existing cache file logic unchanged
- [ ] Existing test coverage still passes

**Effort**: Small
**Dependencies**: Sprint 1

#### Task 3.2: Add Python3 JSON Decoder Fallback

**Description**: Add `json.JSONDecoder().raw_decode()` fallback between greedy regex (Tier 3) and error return (Tier 4) in `parse_codex_output()` in `lib-codex-exec.sh`.

**Acceptance Criteria**:
- [ ] Tier 3.5 added: Python3 raw_decode for arbitrary nesting
- [ ] Only invoked when python3 is available
- [ ] Falls through gracefully when python3 missing
- [ ] Output validated with `jq empty` before returning
- [ ] No functional change when greedy regex already succeeds

**Effort**: Small
**Dependencies**: Sprint 1

#### Task 3.3: Result Contract Tests

**Description**: Unit tests for `validate_review_result()` covering all validation paths.

**Acceptance Criteria**:
- [ ] 7 tests: valid approved, valid changes required, missing verdict, invalid verdict, too short, invalid JSON, findings not array
- [ ] Tests in `test-gpt-review-route-table.bats`
- [ ] All 7 tests pass

**Effort**: Small
**Dependencies**: Sprint 1 (Task 1.4)

#### Task 3.4: CI Policy Constraints

**Description**: Enforce `LOA_CUSTOM_ROUTES=1` requirement in CI. Add `GPT_REVIEW_ADAPTIVE` env var override for adaptive multi-pass.

**Acceptance Criteria**:
- [ ] When `CI=true` and custom routes detected, default blocks unless `LOA_CUSTOM_ROUTES=1`
- [ ] `GPT_REVIEW_ADAPTIVE=0` disables adaptive multi-pass regardless of config
- [ ] `GPT_REVIEW_ADAPTIVE=1` enables adaptive regardless of config
- [ ] Unset → uses config value
- [ ] Test coverage for both env var overrides

**Effort**: Small
**Dependencies**: Sprint 1, Sprint 2

#### Task 3.5: Full Integration Verification

**Description**: Run all existing tests to verify zero regression. Document any test modifications needed.

**Acceptance Criteria**:
- [ ] All 117 existing tests from cycle-033 pass
- [ ] All new tests from Sprints 1-3 pass
- [ ] Zero test modifications to existing tests
- [ ] If any existing test needs modification, document reason and get approval

**Effort**: Small
**Dependencies**: All previous tasks

---

## Risk Register

| Risk | Sprint | Mitigation |
|------|--------|------------|
| Route table parse error breaks routing | 1 | Fail-closed for custom, fail-open for defaults. Golden tests. Kill-switch via `LOA_LEGACY_ROUTER=1` (IMP-001). |
| Parallel array desync | 1 | Atomic `_rt_append_route()` helper + `_rt_validate_array_lengths()` invariant check (SKP-002). |
| Adaptive classification too aggressive | 2 | Dual-signal requires BOTH agreement. Denylist for security paths. |
| yq v4 not available or wrong version | 1 | Version detection (v3 vs v4), fail-closed + env override, `LOA_ALLOW_DEFAULTS_WITHOUT_YQ` illegal in CI (IMP-003, SKP-001). |
| Existing tests break | 3 | Sprint 3 dedicated to regression verification |
| Backend result contract too strict | 1 | Conservative thresholds (20 char min), iterative tuning |
| Runaway retries/timeouts | 1 | Bounds: timeout 1-600s, retries 0-5, global max attempts cap 10 (SKP-005). |
| Untrusted YAML in CI | 1 | Adversarial security tests, registry validation before execution, clamped bounds (SKP-010). |
| Config precedence confusion | 1 | Explicit precedence matrix documented + tested (IMP-009). |

## Flatline Sprint Review Integration

Flatline Protocol reviewed this sprint plan with 80% model agreement.

**HIGH_CONSENSUS integrated (5)**:
- IMP-001 (avg 880): Legacy router kill-switch via `LOA_LEGACY_ROUTER=1` → Task 1.6
- IMP-003 (avg 770): yq v3/v4 version detection → Task 1.2
- IMP-004 (avg 830): Canonical YAML schema example in lib-route-table.sh → Task 1.2
- IMP-006 (avg 865): Verdict-to-exit-code truth table → Task 1.4
- IMP-009 (avg 795): Configuration precedence matrix → Task 1.7

**DISPUTED resolved (2)**:
- IMP-002 (GPT 420, Opus 820): Rejected — concurrency/locking over-scoped for bash CLI tool. SDD already documents single-process assumption.
- IMP-010 (GPT 840, Opus 450): Accepted — adversarial YAML security tests added → Task 1.10

**BLOCKERS addressed (5)**:
- SKP-001 (900): Addressed by IMP-003 (yq version pinning) + `LOA_ALLOW_DEFAULTS_WITHOUT_YQ` illegal in CI → Task 1.2
- SKP-002 (860): Addressed by `_rt_append_route()` atomic helper + `_rt_validate_array_lengths()` invariant → Task 1.1
- SKP-003 (720): Addressed by whitespace trimming + empty-token rejection in `_evaluate_conditions()` → Task 1.3
- SKP-005 (740): Addressed by bounds clamping (timeout 1-600s, retries 0-5) + global max attempts cap → Task 1.3
- SKP-010 (760): Addressed by adversarial YAML security tests + registry validation → Task 1.10

## Definition of Done

- All acceptance criteria checked
- All new code has test coverage
- All 117 existing tests pass without modification
- Sprint review + audit cycle passed
- No new security vulnerabilities introduced
