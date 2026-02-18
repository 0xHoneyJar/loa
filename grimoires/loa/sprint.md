# Sprint Plan: Hounfour Runtime Bridge — Model-Heterogeneous Agent Routing

> Cycle: cycle-026 | PRD: grimoires/loa/prd.md | SDD: grimoires/loa/sdd.md
> Source: [#365](https://github.com/0xHoneyJar/loa/issues/365), [#368](https://github.com/0xHoneyJar/loa/pull/368)
> Sprints: 9 (6 completed + 3 new) | Phase 2: Bridgebuilder Advances
> Bridgebuilder Review: [Part I](https://github.com/0xHoneyJar/loa/pull/368#issuecomment-3919141410), [Part II](https://github.com/0xHoneyJar/loa/pull/368#issuecomment-3919146469), [Part III](https://github.com/0xHoneyJar/loa/pull/368#issuecomment-3919161951)
> Flatline: Reviewed (2 HIGH_CONSENSUS integrated, 1 DISPUTED accepted, 6 BLOCKERS addressed)
> Phase 1.5 added: 2026-02-18 (Hounfour v7 Protocol Alignment)

## Completed Sprints (Phase 1 + Phase 1.5 + Bridge Iterations)

### Sprint 1: GoogleAdapter — Standard Gemini Models (sprint-5) [COMPLETED]
### Sprint 2: Deep Research Adapter (sprint-6) [COMPLETED]
### Sprint 3: Metering Activation + Flatline Routing + Feature Flags (sprint-7) [COMPLETED]
### Sprint 4: Hounfour v7 Protocol Alignment (sprint-8) [COMPLETED]
### Sprint 5: Bridge Iteration 1 — Metering Correctness (sprint-9) [COMPLETED]
### Sprint 6: Bridge Iteration 2 — Resilience Hardening (sprint-10) [COMPLETED]

---

## Phase 2: Bridgebuilder Advances

Source: Three-part Bridgebuilder deep review identifying architectural advances beyond code correctness. These sprints implement the concrete proposals from Parts I-III.

---

## Sprint 7: Test Coverage Hardening — Trust Scopes, Multi-Adapter & Invariant Verification [COMPLETED]

**Goal**: Fill the test gaps identified in the Bridgebuilder review. The existing test suite (14 Python files, ~4700 lines) is strong on individual components but weak on cross-cutting concerns: trust scopes have zero dedicated tests, budget+fallback integration is partial, multi-flag combinations are untested, and the conservation invariant is verified nowhere. This sprint closes those gaps.

**Global Sprint ID**: sprint-11

### Task 7.1: Create dedicated trust_scopes test file

**File**: `.claude/adapters/tests/test_trust_scopes.py` (new)

Trust scopes were migrated in Sprint 4 but have no validation tests. The 6-dimensional model maps directly to Ostrom's governance principles — and governance without enforcement is poetry.

**Acceptance Criteria**:
- [x] Test `model-permissions.yaml` loads and parses all 6 dimensions for each model entry
- [x] Test `claude-code:session` has expected scopes (high data_access, financial, delegation, model_selection; none governance)
- [x] Test `openai:gpt-5.2` has all-none scopes (read-only remote model)
- [x] Test Google model entries (added Sprint 6) have correct scopes (data_access: none, delegation: limited for deep-research)
- [x] Test trust_scopes schema validation: reject unknown dimensions, reject invalid values (not in high/medium/low/none/limited)
- [x] Test backward compat: `trust_level` summary field still present alongside `trust_scopes`
- [x] Test all entries in model-permissions.yaml are covered (no model has scopes undefined)
- [x] Validate Ostrom Principle #1: every registered provider has a trust scope entry (boundary enforcement)

### Task 7.2: Multi-flag feature flag combination tests

**File**: `.claude/adapters/tests/test_feature_flags.py` (new)

Existing tests check individual flags. The Bridgebuilder review notes that real-world configurations involve multiple flags simultaneously, and the interaction between flags is untested.

**Acceptance Criteria**:
- [x] Test all-flags-enabled (default) works end-to-end
- [x] Test `google_adapter: false` + `deep_research: true` — deep_research should be blocked (parent disabled)
- [x] Test `metering: false` + `google_adapter: true` — adapter works, no budget enforcement
- [x] Test `thinking_traces: false` + `google_adapter: true` — adapter works, no thinking config in request body
- [x] Test `flatline_routing: true` + `google_adapter: false` — Flatline falls back to non-Google providers
- [x] Test all-flags-disabled — no external calls, no metering, no thinking
- [x] Test flag precedence: config file vs environment variable override
- [x] All tests mocked (no live API)

### Task 7.3: Budget + fallback chain integration tests

**File**: `.claude/adapters/tests/test_budget_fallback.py` (new)

Budget enforcement and fallback routing are tested independently but never together. The Bridgebuilder review identifies this as a critical gap: "What happens when a budget-exceeded model triggers fallback to a cheaper model?"

**Acceptance Criteria**:
- [x] Test DOWNGRADE action triggers fallback chain walk
- [x] Test fallback candidate satisfies agent requires (native_runtime guard respected during downgrade)
- [x] Test downgrade from `google:gemini-3-pro` to `openai:gpt-4o-mini` via configured chain
- [x] Test downgrade impossible for `native_runtime: true` agents (cannot leave Claude Code)
- [x] Test BLOCK action returns exit code 6 without invoking any provider
- [x] Test WARN action allows invocation but logs warning
- [x] Test budget check uses daily_micro_usd from config, not hardcoded value
- [x] Test atomic pre_call + provider failure + post_call records zero cost (Sprint 5 fix verified end-to-end)

### Task 7.4: Conservation invariant property-based tests

**File**: `.claude/adapters/tests/test_conservation_invariant.py` (new)

The Bridgebuilder review identifies the conservation invariant as the most important architectural property in the system. It spans three layers (pricing → budget → ledger) but is tested nowhere as a cross-cutting property. This task implements property-based tests that verify the invariant holds across randomized inputs.

**Acceptance Criteria**:
- [x] Property test: for any valid (tokens, price_per_mtok), `cost + remainder == tokens * price_per_mtok`
- [x] Property test: `RemainderAccumulator` across N random additions, `sum(yielded_costs) + accumulator.remainder == sum(raw_products)`
- [x] Property test: `create_ledger_entry()` + `calculate_total_cost()` round-trip preserves total (no precision loss)
- [x] Property test: sequence of `pre_call_atomic()` + `post_call()` never produces negative daily spend
- [x] Property test: hybrid pricing mode satisfies `total == token_cost + per_task_cost + remainder_carry`
- [x] Uses hypothesis library for property-based testing (add to test requirements if not present)
- [x] Minimum 100 examples per property, shrinking enabled for failure reproduction
- [x] Document the invariant being tested in each property's docstring (cite Bridgebuilder review Part II)

### Task 7.5: Google adapter recovery and edge case tests

**File**: `.claude/adapters/tests/test_google_adapter.py` (extend)

Extend the existing Google adapter tests with recovery edge cases identified in the review.

**Acceptance Criteria**:
- [x] Test interaction persistence: create_interaction → crash (simulate) → resume polling from persisted state
- [x] Test interaction persistence: stale .dr-interactions.json with dead interaction → no hang
- [x] Test Deep Research cancellation after completion (idempotent, no error)
- [x] Test Deep Research unknown status in poll response → continue polling (not crash)
- [x] Test concurrent standard + Deep Research requests share the correct semaphore pools
- [x] Test API version override via `model_config.extra.api_version` → URL constructed correctly
- [x] Test auth mode: header (default) vs query param (legacy) → correct request format
- [x] Test max retries exhausted → final error surfaced (not swallowed by retry loop)

### Task 7.6: Cross-adapter routing integration tests

**File**: `.claude/adapters/tests/test_multi_adapter.py` (new)

Test that routing works correctly when multiple adapters are registered simultaneously.

**Acceptance Criteria**:
- [x] Test agent binding resolution: `deep-researcher` → Google, `reviewing-code` → OpenAI, `native` → Claude Code
- [x] Test circuit breaker trip on Google → fallback to OpenAI for agents that don't require Google-specific capabilities
- [x] Test `validate_bindings()` catches missing provider for any configured agent
- [x] Test alias chain: `deep-thinker` → alias → `google:gemini-3-pro` → GoogleAdapter
- [x] Test adapter registry contains all 3 providers (openai, anthropic, google)
- [x] All tests mocked

---

## Sprint 8: Cross-Repository Invariant Infrastructure & Eval Harness Fix

**Goal**: Implement the cross-repository invariant verification infrastructure proposed in Bridgebuilder Part III, and investigate the 50% eval regression pass rate identified in Part I. The invariant system creates formal property declarations that span Loa's `RemainderAccumulator`, hounfour's `MonetaryPolicy`, and arrakis's `lot_invariant` — enabling CI verification across all three codebases.

**Global Sprint ID**: sprint-12

### Task 8.1: Create invariants declaration schema

**File**: `.claude/schemas/invariants.schema.json` (new)

Define the JSON Schema for cross-repository invariant declarations. This is the formal expression of the social contract identified in Bridgebuilder Part II.

**Acceptance Criteria**:
- [ ] Schema defines `invariants` array with `id`, `description`, `properties` (string array of formal property expressions), `verified_in` (array of repo+file+function references)
- [ ] Schema validates `severity` field: `"critical"` (must never be violated), `"important"` (should be verified), `"advisory"` (best-effort)
- [ ] Schema validates `category` field: `"conservation"`, `"monotonicity"`, `"ordering"`, `"bounded"`, `"idempotent"`
- [ ] JSON Schema draft 2020-12 compatible
- [ ] Example invariant validates against schema

### Task 8.2: Declare Hounfour economic invariants

**File**: `grimoires/loa/invariants.yaml` (new)

Declare the invariants identified across the ecosystem. These become the formal social contract.

**Acceptance Criteria**:
- [ ] INV-001: Conservation — `sum(input_costs) == sum(distributed_costs) + sum(remainders)`, severity: critical
  - verified_in: `loa:pricing.py:RemainderAccumulator.add`, `loa:pricing.py:calculate_cost_micro`
- [ ] INV-002: Non-negative spend — `daily_spend >= 0` at all times, severity: critical
  - verified_in: `loa:budget.py:pre_call_atomic`, `loa:ledger.py:update_daily_spend`
- [ ] INV-003: Deduplication — `len(unique(interaction_ids)) == len(ledger_entries_for_interactions)`, severity: important
  - verified_in: `loa:budget.py:post_call`, `loa:ledger.py:append_ledger`
- [ ] INV-004: Budget monotonicity — daily spend counter only increases within a day (never decremented), severity: critical
  - verified_in: `loa:budget.py:post_call`, `loa:ledger.py:update_daily_spend`
- [ ] INV-005: Trust boundary — no model exceeds its trust_scopes at runtime, severity: critical
  - verified_in: `loa:resolver.py:resolve_execution`, `loa:model-permissions.yaml`
- [ ] Cross-repo references annotated with `protocol: loa-hounfour@7.0.0` for ecosystem traceability
- [ ] YAML validates against schema from Task 8.1

### Task 8.3: Implement invariant verification script

**File**: `.claude/scripts/verify-invariants.sh` (new)

Script that reads `invariants.yaml`, locates each `verified_in` reference, and confirms the referenced function/class exists in the codebase.

**Acceptance Criteria**:
- [ ] Reads `grimoires/loa/invariants.yaml`
- [ ] For each invariant, for each `verified_in` entry where `repo == "loa"`:
  - Verify the file exists
  - Verify the function/class exists in the file (grep for definition)
  - Report PASS/FAIL per invariant
- [ ] For cross-repo references (repo != "loa"): report SKIP with note (verified in external CI)
- [ ] Exit code 0 if all local invariants pass, 1 if any fail
- [ ] Output format compatible with `butterfreezone-validate.sh` pattern
- [ ] Integrates with `quality-gates.bats` as an optional check

### Task 8.4: Add invariant verification to existing test suite

**File**: `tests/unit/invariant-verification.bats` (new)

BATS tests that exercise the invariant verification script.

**Acceptance Criteria**:
- [ ] Test script finds all declared invariants in valid codebase
- [ ] Test script detects missing function (simulate by declaring non-existent function reference)
- [ ] Test script detects missing file
- [ ] Test script handles empty invariants.yaml gracefully
- [ ] Test cross-repo references are SKIPped (not FAILed)
- [ ] Test exit codes: 0 for all-pass, 1 for any-fail

### Task 8.5: Investigate eval regression 50% pass rate

**File**: `.claude/scripts/tests/eval-regression-analysis.sh` (new)

The Bridgebuilder review Part I flags that 10 regression eval tasks consistently show 50% pass rate. This is suspicious — "If one trial consistently passes and one consistently fails across all tasks, the signal is in the harness, not the code."

**Acceptance Criteria**:
- [ ] Script runs each failing eval task 4 times, recording pass/fail per trial
- [ ] Output: per-task breakdown showing which trial(s) pass and which fail
- [ ] If pattern is "trial 1 always passes, trial 2 always fails" → report as HARNESS_BUG
- [ ] If pattern is truly random 50/50 → report as FLAKY
- [ ] If pattern is "always fails" → report as REGRESSION
- [ ] Analysis saved to `.run/eval-regression-analysis.json`
- [ ] Document findings in NOTES.md

### Task 8.6: Fix eval harness (conditional on Task 8.5 findings)

**Acceptance Criteria**:
- [ ] If HARNESS_BUG: fix the harness to eliminate the systematic trial failure
- [ ] If FLAKY: add retry logic or increase trial count
- [ ] If REGRESSION: create bug report for each failing task
- [ ] After fix: all 10 previously-failing tasks pass at >80% rate
- [ ] Existing passing tasks remain unaffected

---

## Sprint 9: Epistemic Trust Scopes & Jam Geometry Architecture [COMPLETED]

**Goal**: Implement the epistemic trust scopes proposed in Bridgebuilder Part III (context_access dimension controlling what models *know*), and design the Jam geometry architecture for multi-model parallel review with independent synthesis. The epistemic dimension is the mechanism that makes the Maroon collaboration geometry safe — agents can coordinate through shared state while being protected from each other's sensitive contexts.

**Global Sprint ID**: sprint-13

### Task 9.1: Extend trust_scopes schema with epistemic dimension

**File**: `.claude/data/model-permissions.yaml`, `.claude/schemas/model-config.schema.json`

Add the `context_access` dimension to trust_scopes. This implements Ostrom Principle #1 applied to *knowledge* rather than *action*.

**Acceptance Criteria**:
- [x] `context_access` added as 7th trust_scopes dimension with sub-fields:
  - `architecture`: full/summary/none — visibility into SDD, PRD, protocol docs
  - `business_logic`: full/redacted/none — visibility into implementation code
  - `security`: full/redacted/none — visibility into audit findings, vulnerability details
  - `lore`: full/summary/none — visibility into institutional knowledge
- [x] `claude-code:session` (native): full/full/full/full (unrestricted — it already has file access)
- [x] `openai:gpt-5.2` (remote reviewer): full/redacted/none/full (sees architecture + lore, not security details)
- [x] `google:deep-research-pro` (remote research): summary/none/none/summary (minimal context, focused on research task)
- [x] `google:gemini-3-pro` (remote reasoning): full/redacted/none/full (architecture-aware reasoning)
- [x] Schema JSON updated with `context_access` sub-schema
- [x] Backward compatible: `context_access` optional, defaults to all-full if missing

### Task 9.2: Implement epistemic scope filtering in request builder

**File**: `.claude/adapters/loa_cheval/routing/context_filter.py` (new)

When building a request for a remote model, filter the context (system prompt, appended context) based on the model's epistemic trust scopes.

**Acceptance Criteria**:
- [x] `filter_context(messages, trust_scopes)` function filters message content based on `context_access` dimensions
- [x] `architecture: none` → strip SDD/PRD content from system messages
- [x] `architecture: summary` → replace full SDD with executive summary (first 500 chars + section headers)
- [x] `business_logic: redacted` → replace function bodies with signatures only (regex-based)
- [x] `security: none` → strip security audit findings, vulnerability markers, CVE references
- [x] `lore: summary` → include `short` fields only (not `context`)
- [x] Filtering is additive: messages not matching any filter category pass through unchanged
- [x] Filter applied in `cheval.py` *after* agent binding resolution, *before* adapter.complete()
- [x] Log filtered dimensions: `{event: "context_filtered", model: "...", dimensions: {"architecture": "redacted", ...}}`
- [x] No filtering for `native_runtime` models (they have file access anyway)

### Task 9.3: Epistemic trust scopes tests

**File**: `.claude/adapters/tests/test_epistemic_scopes.py` (new)

**Acceptance Criteria**:
- [x] Test full access: all dimensions = full → no filtering applied
- [x] Test architecture: none → SDD/PRD content stripped from system messages
- [x] Test architecture: summary → truncated to headers + first paragraph
- [x] Test business_logic: redacted → function bodies replaced with `[redacted]`
- [x] Test security: none → CVE references, audit findings stripped
- [x] Test lore: summary → only `short` fields preserved
- [x] Test native_runtime models bypass filtering entirely
- [x] Test missing context_access → defaults to all-full (backward compat)
- [x] Test mixed dimensions: architecture: full + security: none → architecture preserved, security stripped
- [x] All tests use fixture messages with identifiable content for each category

### Task 9.4: Design Jam geometry for multi-model review

**File**: `docs/architecture/jam-geometry.md` (new)

Design document for the Jam geometry proposal from Bridgebuilder Part III. This is a design artifact, not code — but it needs to be grounded in the existing infrastructure to be implementable.

**Acceptance Criteria**:
- [x] Document the three-phase workflow: Divergent → Synthesis → Harmony
- [x] Divergent phase: Claude, GPT-5.2, Kimi-K2 review the same PR independently (use existing `cheval.py` infrastructure)
- [x] Synthesis phase: a *different* model (not one of the reviewers) synthesizes the three reviews
  - Identify disagreements, consensus findings, and unique insights from each
  - Synthesizer model selection: lowest trust_scopes model capable of text analysis (cost optimization)
- [x] Harmony phase: unified review posted with per-model attribution
- [x] Map to existing infrastructure: `ProviderAdapter` for divergent calls, `BudgetEnforcer` for cost tracking, `trust_scopes` for access control
- [x] Estimate cost per Jam review (3 divergent + 1 synthesis call, using current pricing)
- [x] Compare to current Seance geometry (1 model, 1 review): quality tradeoffs, cost tradeoffs
- [x] Reference: Miles Davis's second quintet (freedom within structure), academic peer review (independent reviewers + editor)
- [x] Identify prerequisite: epistemic trust scopes (Task 9.1-9.3) — reviewers need appropriate context_access
- [x] Identify Phase 0: use existing Flatline Protocol as scaffold (it already does parallel model calls)

### Task 9.5: Update model-config.yaml with Jam geometry routing

**File**: `.claude/defaults/model-config.yaml`

Add agent bindings for the Jam geometry roles.

**Acceptance Criteria**:
- [x] `jam-reviewer-claude` agent binding: `model: native`, `requires: {thinking_traces: true}`
- [x] `jam-reviewer-gpt` agent binding: `model: reviewer` (openai:gpt-5.2)
- [x] `jam-reviewer-kimi` agent binding: `model: reasoning` (moonshot:kimi-k2-thinking)
- [x] `jam-synthesizer` agent binding: `model: cheap` (anthropic:claude-sonnet-4-6) — lowest cost for text synthesis
- [x] Each reviewer has appropriate `context_access` in model-permissions.yaml
- [x] Feature flag: `hounfour.feature_flags.jam_geometry: false` (opt-in, not default)

### Task 9.6: Update BUTTERFREEZONE and Ground Truth

Run finalization artifacts for the new sprint additions.

**Acceptance Criteria**:
- [x] BUTTERFREEZONE.md regenerated with Phase 2 sprint context
- [x] `butterfreezone-validate.sh` passes (17/17+ checks)
- [x] Ground truth checksums updated
- [x] `invariants.yaml` checksummed in ground truth

---

## Dependency Graph (Phase 2)

```
Sprint 7 (Test Hardening)
    │
    ├──── Sprint 8 (Invariants + Eval Fix)    [independent of Sprint 7]
    │
    └──── Sprint 9 (Epistemic + Jam)          [blocks on Sprint 7 Task 7.1 for trust scope foundation]
```

Sprints 7 and 8 are parallelizable.
Sprint 9 depends on trust scope tests from Sprint 7 (validates the foundation before extending it).

## Risk Assessment (Phase 2)

| Risk | Sprint | Mitigation |
|------|--------|------------|
| hypothesis library not available in test env | S7 | Fallback to manual property tests with range loops |
| Eval harness root cause not deterministic | S8 | Document findings even if fix isn't clear-cut |
| Epistemic filtering too aggressive (strips needed context) | S9 | Default to all-full; filtering is opt-in per model |
| Jam geometry cost exceeds budget for routine reviews | S9 | Feature flag default=false; cost estimate before activation |
| Cross-repo invariant references drift | S8 | verify-invariants.sh designed for CI; drift detected on each run |

## Success Criteria (Phase 2)

1. Trust scopes have dedicated test coverage (100% of model-permissions entries validated)
2. Conservation invariant verified by property-based tests across pricing/budget/ledger
3. Multi-flag feature combinations tested (minimum 6 combination scenarios)
4. Budget+fallback integration tested end-to-end (DOWNGRADE → chain walk → cheaper model)
5. Cross-repository invariants declared in formal schema (minimum 5 invariants)
6. Invariant verification script runs in CI (exit code 0)
7. Eval regression root cause identified and documented
8. Epistemic trust scopes implemented with 4 context_access dimensions
9. Context filtering applied to remote model requests based on epistemic scopes
10. Jam geometry design document complete with cost analysis and implementation roadmap
11. All existing tests still pass (zero regressions)
