# Sprint 11 (local sprint-7) — Implementation Report

## Sprint: Test Coverage Hardening — Trust Scopes, Multi-Adapter & Invariant Verification

**Branch**: `feat/cycle-026-hounfour-routing`
**Global Sprint ID**: sprint-11
**Status**: Implementation complete, pending review

---

## Summary

Created 5 new test files and extended 1 existing test file, adding 192 new tests
(+113 subtests) to the adapter test suite. Total suite now at 485 tests (all passing).

## Tasks Completed

### Task 7.1: Trust Scopes Validation Tests
**File**: `.claude/adapters/tests/test_trust_scopes.py`
**Tests Added**: 27 (including subtests)

- `TestTrustScopesSchema` — validates all models have trust_scopes, all 6 dimensions,
  no unknown dimensions, valid values, backward-compat trust_level
- `TestClaudeCodeSessionScopes` — verifies claude-code:session has expected high-privilege scopes
- `TestRemoteModelScopes` — openai, moonshot, qwen, anthropic have correct restricted scopes
- `TestGoogleModelScopes` — gemini models all-none, deep-research-pro delegation:limited,
  all Google models are execution_mode: remote_model
- `TestModelCoverage` — minimum 9 entries, all have execution_mode and capabilities

### Task 7.2: Multi-Flag Feature Flag Combination Tests
**File**: `.claude/adapters/tests/test_feature_flags.py`
**Tests Added**: 18

- `TestAllFlagsEnabled` — default config: all providers + metering + thinking resolve correctly
- `TestGoogleDisabledDeepResearchEnabled` — alias resolution vs validation when provider removed
- `TestMeteringDisabledAdaptersEnabled` — disabled metering returns ALLOW, routing independent
- `TestThinkingDisabled` — thinking_budget=0 disables thinking config
- `TestFlatlineRoutingWithoutGoogle` — native_runtime blocks fallback, unhealthy skips
- `TestAllFlagsDisabled` — only native agents resolve with no external providers
- `TestFlagPrecedence` — config overrides default, on_exceeded modes (block/downgrade/warn)

### Task 7.3: Budget + Fallback Chain Integration Tests
**File**: `.claude/adapters/tests/test_budget_fallback.py`
**Tests Added**: 22

- `TestDowngradeTriggersFallback` — DOWNGRADE triggers walk_downgrade_chain
- `TestDowngradeRespectsNativeRuntime` — native_runtime blocks downgrade and fallback
- `TestDowngradeChainWalk` — reviewer → cheap via config chain
- `TestBlockAction` — BLOCK action halts invocation (pre_call and atomic)
- `TestWarnAction` — WARN at threshold and on_exceeded: warn
- `TestBudgetUsesConfigValues` — custom limit, high limit, standalone check_budget
- `TestAtomicPreCallPostCallZeroCost` — interaction_id dedup, disabled metering no-op
- `TestFallbackChainCapabilityCheck` — thinking_traces required, deep_research required

### Task 7.4: Conservation Invariant Property-Based Tests
**File**: `.claude/adapters/tests/test_conservation_invariant.py`
**Tests Added**: 25

- `TestConservationPropertyHypothesis` (conditional on hypothesis install) — 200-example
  property tests for INV-001: cost*1M + remainder == tokens*price
- `TestRemainderAccumulatorPropertyHypothesis` — accumulator conservation across 5 carries
- `TestConservationPropertyRange` — deterministic conservation tests across representative
  token/price samples (156 pairs)
- `TestRemainderAccumulatorConservation` — exact carry, multi-step, large remainder,
  independent scopes
- `TestTotalCostConservation` — token mode, task mode, hybrid mode
- `TestLedgerEntryRoundTrip` — known pricing, zero tokens, task pricing
- `TestDailySpendNonNegative` — initial zero, monotonic increase
- `TestOverflowGuard` — overflow detection, max safe product boundary

### Task 7.5: Google Adapter Recovery Edge Cases
**File**: `.claude/adapters/tests/test_google_adapter.py` (extended)
**Tests Added**: 13

- `TestInteractionPersistence` additions — stale interactions loadable, corrupted file → empty dict
- `TestSemaphorePools` — standard (max 5) and deep research (max 3) use separate pools
- `TestApiVersionOverride` — default v1beta, URL construction with model colon, interactions
  path, endpoint normalization (no double version), endpoint without version
- `TestAuthHeader` — auth via x-goog-api-key header, not in URL query param
- `TestMaxRetriesExhausted` — 503 exhaustion raises ProviderUnavailableError, poll retries
  surface error (not swallowed)

### Task 7.6: Cross-Adapter Routing Integration Tests
**File**: `.claude/adapters/tests/test_multi_adapter.py`
**Tests Added**: 23

- `TestCrossAdapterAgentResolution` — agents resolve to correct provider across all 3 + native
- `TestGoogleToOpenAIFallback` — google → openai via alias, deep_research blocked, reverse
  chains for openai → anthropic and anthropic → openai
- `TestValidateBindingsMultiAdapter` — valid config, missing google/openai provider, missing
  model, capability mismatch
- `TestAliasChainResolution` — direct alias, chained alias, direct provider:model, native
- `TestAdapterRegistry` — openai, google, anthropic registered, get_adapter returns GoogleAdapter
- `TestChainValidation` — valid chains, unresolvable fallback, duplicate target detection
- `TestModelOverride` — override to different providers, blocked for native_runtime

## Test Coverage Metrics

| Metric | Before | After |
|--------|--------|-------|
| Total test files | 14 | 19 |
| Total tests | 293 | 485 |
| Subtests | ~80 | 193 |
| Trust scopes tests | 0 | 27 |
| Multi-flag combo tests | 0 | 18 |
| Budget+fallback integration | 0 | 22 |
| Conservation invariant | 0 | 25 |
| Google adapter edge cases | 54 | 67 |
| Cross-adapter routing | 0 | 23 |

## Key Design Decisions

1. **Fallback chain entries use aliases, not raw provider names**: The resolver only handles
   `provider:model` format or aliases from the aliases dict. Chain entries like `"reviewer"`
   resolve through the alias system.

2. **Hypothesis property tests are conditionally defined**: Class bodies referencing `@given`
   decorators execute at import time, so `skipif` is insufficient. The classes are inside a
   `try/except ImportError` block.

3. **Conservation invariant tested as cross-cutting property**: Not just pricing, but the
   full pipeline (pricing → budget → ledger) preserves the invariant.

## Acceptance Criteria Verification

- [x] Trust scopes: all models have 6 dimensions, valid values, backward-compat trust_level
- [x] Google models: all-none scopes, deep-research delegation:limited, execution_mode: remote_model
- [x] Multi-flag: metering disabled + adapters, thinking disabled, no providers, flag precedence
- [x] Budget + fallback: DOWNGRADE → chain walk, native_runtime guard, capability check
- [x] Conservation: INV-001 (cost*1M + remainder == tokens*price) across representative range
- [x] Google edge cases: stale interactions, semaphore pools, URL construction, auth header
- [x] Cross-adapter: agent resolution, fallback chains, validation, alias resolution, registry
- [x] All 485 tests passing (9 skipped — hypothesis not installed)
