# Implementation Report — Sprint 1: Full-size adapters, Bridgebuilder and Flatline (cycle-126, global sprint 247)

**Cycle:** cycle-126 full-size · **PRD:** `grimoires/loa/prd.md` FR-1 (FR-1.1 … FR-1.9) · **SDD:** `grimoires/loa/sdd.md` §1.2 (D-1.1 … D-1.9) · **Plan:** `grimoires/loa/sprint.md` Sprint 1
**Implementer:** Fable 5.1 lead (`/run sprint-plan`, run-20260925-5f96cb0e, unattended) · **Date:** 2026-09-25 · **Epic:** bd-goo5 (tasks bd-gyij, bd-fqip, bd-y4cs, bd-1y44, bd-1s42, bd-02tj, bd-ybcq)

## Summary

Every size decision for a request now derives from the catalog entry actually resolved. cheval's input gate is a policy over the entry (`loa_cheval/routing/ceiling.py`): I1 `estimate + max_tokens ≤ context_window` shrinks the output budget to a 4,096 floor before refusing (per hop, recorded), and I2 sets the input bound to the calibrated value when one exists, else the entry's probed bound (180,000) — the catalog-derived bound applies only after calibration or under an explicit opt-in, where a request above the probed bound proceeds with `warn` when the provider's count or a low-uncertainty estimate says it fits and preempts with the calibration command otherwise. A provider's own size verdict is typed, retried once with the budget the provider's numbers allow, then ended without walking the chain; the observation is written to `.run/ceiling-observed.json`, bounds that entry until calibration, and the envelope names the probe command, which can now write the calibration into the catalog. Output defaults, the temperature default, beta headers, the health probe, the long-context price tier, Bridgebuilder's generated table / default model / reasoning class and Flatline's per-voice budget all follow the same entries. Kill switches restore today's behaviour (`LOA_CHEVAL_LEGACY_CEILING=1`, `LOA_CHEVAL_LEGACY_WIRE=1`).

Assumptions (Karpathy rule 1), each recorded in NOTES.md (2026-09-25 Decision Log): the provider's verdict is non-walkable, cheval's own estimate against a hop's window still walks (a larger window may fit); only the `input + max_tokens > limit` shape is retried (the input-only shape cannot be helped by a retry); a 429 on an unverified request is recorded but never lowers the bound; the count endpoint is consulted anywhere in the unverified zone, not only within 90 % of the bound; `--per-call-max-tokens` is the operator override and is kept; Bridgebuilder's reasoning flag is a union with the legacy regexes (headless hops keep the 30-minute budget) and provider-aware; the persona test's failure is an environment precondition present on `main`.

## Changes

### FR-1.1 / FR-1.4 / FR-1.7 — ceiling policy, estimator, self-correction (Task 1.2, Task 1.3)
| File | Change |
|---|---|
| `.claude/adapters/loa_cheval/routing/ceiling.py` (new) | `policy_from_env` (`legacy` > `derived` > `probed`), `input_bound` (calibrated / probed / derived / observed / I1 / guard / legacy, every basis named), `fit_max_tokens` (I1 auto-shrink to the 4,096 floor), `gate` (`dispatch` / `warn` / `preempt` with the CLI override, the near-bound and unverified-zone count, the uncertainty rule), `GateEstimate` / `GateOutcome.as_envelope`, `is_context_limit_message` / `parse_context_limit` (the two Anthropic message shapes), the observed store (`observed_store_path` — `LOA_CHEVAL_CEILING_OBSERVED_PATH` or `<repo>/.run/ceiling-observed.json`, `load_observed`, `observed_for` reducing only the two context classes, `record_observed` atomic write-to-temp + `os.replace`), `PROBE_COMMAND` |
| `.claude/adapters/loa_cheval/types.py` | `ProviderContextLimitError` (`CONTEXT_TOO_LARGE`, non-retryable; `status`, `input_tokens`, `limit`, `max_tokens`); `CompletionRequest.temperature: Optional[float] = None` |
| `.claude/adapters/loa_cheval/providers/base.py` | `InputEstimate` / `estimate_input` (method, chars, non-ASCII share, tool payload → `uncertainty`), `NON_ASCII_HIGH_SHARE = 0.20`; `_NON_ANTHROPIC_DEFAULT_OUTPUT_CAP = 16_000` and `default_max_tokens` for every provider; `wire_temperature`; `http_get` |
| `.claude/adapters/loa_cheval/providers/anthropic_adapter.py` | context-limit classification on both HTTP paths (400/413 → `ProviderContextLimitError` with the parsed numbers); `count_tokens` (`POST /v1/messages/count_tokens`, same system/messages/tools/beta headers, None on any failure); `_BETA_HEADER_RE` + `_beta_header_value` (allowlisted, joined, `ConfigError` otherwise); temperature only when set (legacy wire 0.7); `_headers`, `_tiny_model_id`, `health_check` via `GET /v1/models?limit=1` then a one-token message — no retired snapshot id |
| `.claude/adapters/loa_cheval/providers/{openai,google,bedrock}_adapter.py` | `wire_temperature` — nothing on the wire unless set |
| `.claude/adapters/loa_cheval/providers/retry.py` | `ProviderContextLimitError` arm: one shrink to `limit − input` (≥ floor, smaller than requested) for the `input + max_tokens` shape, `max_tokens_shrunk` on the result; otherwise propagate — never a third attempt |
| `.claude/adapters/cheval.py` | pre-flight: `estimate_input` → `gate()` for the head entry (I1 shrink of `base_request.max_tokens`, `warn` stderr line + `operator_visible_warn`, `preempt` with `ceiling_policy` / `ceiling_basis` in the error JSON), envelope `capability_evaluation` gains `input_ceiling`, `estimator`, `max_tokens_shrunk`, `ceiling_policy`, `ceiling_unverified`; `LOA_CHEVAL_LEGACY_CEILING=1` takes the unchanged `_preflight_check` branch; per-hop I1 fit before the walk gate (floor miss → `ROUTING_MISS`, shrink recorded), `_lookup_max_input_tokens(..., max_tokens=)` returns the policy bound (36K wall unchanged); `_calibration_needed_exit` (observed row, `calibration_needed`, `[preflight] calibration_needed` line, typed exit) used by the new `ProviderContextLimitError` arm (`CEILING_UNVERIFIED_LIMIT` above the probed bound, `PROVIDER_CONTEXT_LIMIT` under it) and by `RateLimitError` while unverified (`RATE_LIMIT_UNVERIFIED`, no bound); the retry layer's shrink lands in the envelope on success; `_raw_model_entry`; the request scaffold no longer forces `temperature=0.7` |
| `.claude/defaults/model-config.yaml` | every Anthropic HTTP entry: `probed_ceiling: 180000`, `account_limits: {tier: unverified, itpm: null}`; the 5-family: `params.beta_headers: []`, `pricing.long_context: {threshold_tokens: 200000, input_multiplier: 2.0, output_multiplier: 1.5, verified: false}` (162 added lines, comments only otherwise) |
| `tools/ceiling-probe-live.py` | `write_catalog` (line-level edit inside the model's block: `effective_input_ceiling`, `ceiling_calibration` source/calibrated_at/sample_size, `account_limits` tier/itpm; every other line byte-identical; `ValueError` on a missing block or field), `--write-catalog [PATH]`, `--tier`, `--itpm`, `--allow-partial` (a partial bisection is refused otherwise), atomic write |
| `.claude/scripts/loa-status.sh` | `_anthropic_ceiling_json` (the `opus` target's bound: calibrated / observed / probed, the observation shown next to the default bound, the probe command); Providers block `ceiling:` line; `--json .providers.providers.anthropic.ceiling` |
| `.claude/adapters/tests/conftest.py` | `LOA_CHEVAL_CEILING_OBSERVED_PATH` isolated per test like the ledgers |

### FR-1.9 — cost visibility (Task 1.7)
| File | Change |
|---|---|
| `.claude/adapters/loa_cheval/metering/pricing.py` | `PricingEntry.long_context_threshold / _input_multiplier / _output_multiplier`, `_long_context_fields`, `CostBreakdown.long_context_applied`; `calculate_total_cost` applies the multipliers to the whole request when `input_tokens > threshold` |
| `.claude/adapters/loa_cheval/metering/ledger.py` | row `long_context: true` when the premium was billed |
| `.claude/scripts/cost-report.sh` | `long_context_rows` (JSON, empty envelope, markdown line) |

### FR-1.5 — Bridgebuilder (Task 1.4)
| File | Change |
|---|---|
| `.claude/skills/bridgebuilder-review/scripts/gen-bb-registry.ts` | reads `max_output_tokens`, `params.thinking_adaptive`, `capabilities`; `BB_OUTPUT_CAP = 32_000`; `maxOutput = min(declared ?? providerDefault, cap)`; `reasoning` per entry in `GENERATED_MODEL_REGISTRY` + `GENERATED_REASONING` |
| `resources/core/truncation.generated.ts`, `resources/config.generated.ts`, `dist/`, `.build-manifest.json` | regenerated (`npm run build`; `tools/check-bb-dist-fresh.sh` clean) |
| `resources/core/multi-model-pipeline.ts` | `isReasoningClass`: the generated flag (provider-aware) first, legacy regexes kept as a union |
| `resources/config.ts` | `DEFAULTS.model = "opus"`, `maxInputTokens 200_000`, `maxOutputTokens 32_000` |
| `resources/personas/quick.md`, `security.md`, `SKILL.md` | `# model: tiny` / `# model: opus`; default row names the alias |
| `resources/__tests__/truncation-registry.test.ts` (new), `multi-model-pipeline-timeout.test.ts`, `config.test.ts`, `truncation.test.ts` | new assertions; pins moved deliberately (`claude-sonnet-4-6` maxOutput 8,192 → 32,000 and reasoning-class per its yaml flag; `claude-sonnet-4-5-20250929` unchanged at 8,192 and on the ladder; defaults 200K/32K/`opus`) |

### FR-1.6 — Flatline (Task 1.5)
| File | Change |
|---|---|
| `.claude/scripts/gen-adapter-maps.sh` → `generated-model-maps.sh` | `MODEL_MAX_OUTPUT` (canonical id → `max_output_tokens`; 14 rows) |
| `.claude/scripts/flatline-orchestrator.sh` | `FLATLINE_VOICE_MAX_TOKENS_CAP=64000`, `flatline_voice_max_tokens` (alias via `MODEL_IDS`, `min(cap, declared)`, empty when undeclared or maps not loaded); `call_model` passes it unless `--per-call-max-tokens` overrides; `FLATLINE_REVIEW_MAX_TOKENS` / `FLATLINE_SCORE_MAX_TOKENS` removed |
| `tests/unit/flatline-max-tokens.bats` (new, 6), `cycle-124-dispatch-budgets.bats` B1–B3, `effort-dispatch.bats` ED-8, `flatline-call-model-schema.bats` | harnesses source the generated maps and the helper; expectations 16000 → 64000 |

### FR-1.4 estimator in bash, docs, record (Task 1.6)
| File | Change |
|---|---|
| `.claude/scripts/lib-multipass.sh` | `_MULTIPASS_MODEL` (set by `run_multipass`), `_multipass_is_anthropic`, `estimate_token_count text [model]` → `ceil(chars / 3.5)` for Anthropic passes, tiktoken / heuristic path otherwise |
| `tests/unit/multipass-estimator.bats` (new, 3) | the bound per alias / id / global; the other path stays |
| `CHANGELOG.md` `[Unreleased]` | `### Changed` FR-1 entry |
| `.claude/loa/reference/multi-model-reference.md` | cycle-126 paragraph (policy, envs, envelope fields, probe) |
| `grimoires/loa/REPO-MAP.md` (+ `.checksum`), `.claude/checksums.json` | regenerated (validate consistent, `--check` clean) |
| `grimoires/loa/NOTES.md` | 2026-09-25 Decision Log (deviations above, environment findings) |

## Test-first record

- Task 1.1 wrote the failing suites before each implementation: `test_ceiling_policy.py` (module absent → 10 red → green; then the store/parse/gate cases), `test_full_size_adapter_defaults.py` (19 red on the missing constant / regex / helper → green), `test_long_context_pricing.py` (4), `test_estimator_uncertainty.py` (6), `test_count_tokens_fallback.py` (2), `test_ceiling_retry.py` (4), `test_ceiling_e2e.py` (11, the 600K request through the real gate with a fake transport), `test_ceiling_probe_write_catalog.py` (3), `test_transport_matrix.py` (10), the catalog-floor additions (5), the 600K row in `test_input_size_consumers.py`, `flatline-max-tokens.bats` (6), `multipass-estimator.bats` (3), `LSP-5`, `CR-8`, BB `truncation-registry.test.ts` + timeout/config/truncation pins.
- Defects the tests caught in-sprint: the per-hop I1 fit shrank a CLI hop's explicit budget (199,997 ≠ 200,000 in `test_max_tokens_defaults`) → the fit applies only to ceiling-bearing entries; the opt-in zone with a `high` estimate at 600K would never consult the count endpoint under a strict "≥ 0.9 × bound" trigger → the count is consulted throughout the unverified zone; the retry layer put the shrink on the request instead of the result → recorded on the result and picked up by the envelope; the status line hid an observation above the probed bound → shown next to the default bound; numeric tiers were written unquoted (`tier: 4` parsed as an int) → quoted; the generated reasoning flag let an unknown provider through → provider-aware; `flatline_voice_max_tokens` on a harness without the maps → guarded `declare -p`.
- Deliberately moved expectations (each named in the diff): `test_max_tokens_defaults` (openai/google/xai/bedrock defaults 4096 → `min(16000, declared)`, dry-run gpt-5.5 16000), `test_anthropic_catalog_floor` (new invariants; the old computed-value assertion still holds), BB `config.test.ts` defaults, `truncation.test.ts` sonnet-4-6 maxOutput, `multi-model-pipeline-timeout.test.ts` (sonnet-4-6 reasoning per its yaml flag; the ladder examples use the 4.5 snapshot), Flatline B1–B3 / ED-8 (16000 → 64000).
- Results: `.claude/adapters/tests` **2409 passed, 6 skipped** (whole suite; `test_bedrock_live` deselected as always); bats **353/353** across `cost-report`, `loa-status-providers`, `multipass-estimator`, `flatline-max-tokens`, `cycle-124-dispatch-budgets`, `effort-dispatch`, `flatline-call-model-schema`, `flatline-orchestrator-max-tokens`, `cycle-124-live-scaffold`, `flatline-model-validation` and the fence corpus `block-destructive-bash` (281); Bridgebuilder `npm test` **754 pass / 1 fail** — the one failure is `__tests__/persona.test.ts`, which exits at the API-key precondition in a shell without `ANTHROPIC_API_KEY` presence and fails identically on `main` (verified in a throwaway worktree at `HEAD`; unchanged by this sprint); `gen-adapter-maps.sh --check` OK; `repo-map-gen.sh --validate` consistent; checksums `--check` clean; `tools/check-bb-dist-fresh.sh` clean.
- Environment note: this venv lacked `httpx`, `rfc8785` and `cryptography`; installed locally so the whole suite runs (the `test_ledger_isolation` failure seen first was the audit emitter failing soft on the missing `cryptography`, on `main` too).

## AC Verification (sprint.md)

### `test_anthropic_catalog_floor.py` asserts, per Anthropic entry, I1 (`estimate + max_tokens ≤ context_window`, auto-shrink to the 4,096 floor) and I2 (probed bound by default; calibrated value when `calibrated_at` is set; derived bound `context_window − max_tokens` only under the opt-in or calibration) — never `max()` with the probed value.
- **Status**: ✓ Met
- **Evidence**: `test_i1_and_i2_per_entry_from_the_fields` (bound + default budget ≤ window; default bound ≤ probed; derived only under the opt-in; legacy = the literal), `test_walk_gate_threshold_is_the_policy_bound_not_the_literal`, `test_every_http_entry_carries_the_probed_bound_and_account_limits`; the module never takes a `max()` (`ceiling.py:input_bound` — I1 and the guard only lower).

### A 600,000-token fixture request to `claude-fable-5-1`: `preempt` at the probed bound by default; `action: warn` under `LOA_CHEVAL_UNCALIBRATED_CEILING=derived` with a `low` estimate or a count-endpoint result, `preempt` with a calibration message for a `high` estimate; `preempt` at 36K in legacy transport; today's behaviour under `LOA_CHEVAL_LEGACY_CEILING=1`; a calibrated entry uses its calibrated value; a simulated provider limit above the probed bound yields one retry, `CEILING_UNVERIFIED_LIMIT`, no chain walk, an observed-bound file and `preempt` on the next call; a 170K input on a 200K entry under the 64K default shrinks `max_tokens` (recorded) instead of failing.
- **Status**: ✓ Met
- **Evidence**: `test_ceiling_e2e.py` — `test_default_policy_preempts_600k_at_the_probed_bound` (exit 7, `PREFLIGHT_PREEMPT`, basis `probed`); `test_opt_in_low_estimate_warns_and_dispatches` (`warn`, dispatched once at 64K, `ceiling_unverified`); `test_opt_in_high_estimate_preempts_with_the_calibration_command` (CJK prompt); `test_opt_in_count_endpoint_is_authoritative` (a `count_tokens` of 611,000 settles a `high` estimate → `warn`); `test_legacy_transport_wall_still_owns_the_walk_gate` (streaming off → the 36K wall, `ROUTING_MISS`, `CHAIN_EXHAUSTED`); `test_legacy_ceiling_kill_switch_is_todays_behaviour` (literal + preempt, no I1 shrink, `ceiling_policy: legacy`); `test_calibrated_entry_uses_its_calibrated_value` (640K); `test_provider_limit_above_the_probed_bound_is_not_walked_and_lowers_the_bound` (one dispatch of a two-entry chain, `CEILING_UNVERIFIED_LIMIT`, observed row, `calibration_needed`, the next call preempts at the observed bound, a smaller one proceeds) with `test_ceiling_retry.py` for the single retry; `test_170k_on_a_200k_entry_shrinks_the_output_budget_instead_of_failing` (64,000 → ~30,000, recorded). The catalog fixture is the entry shape the live catalog now carries; `test_transport_matrix.py` runs the same policy against the live catalog.

### `calculate_total_cost` applies the long-context multipliers above the threshold; `beta_headers` values failing the allowlist regex are a config error; `LOA_CHEVAL_MAX_INPUT_TOKENS` lowers the bound.
- **Status**: ✓ Met
- **Evidence**: `test_long_context_pricing.py` (below/at/above the threshold, missing multipliers default to 1); `test_full_size_adapter_defaults.py::test_beta_headers_outside_the_allowlist_are_a_config_error` (5 shapes) and `::test_beta_headers_are_joined_when_declared_and_absent_otherwise`; `test_ceiling_policy.py::test_max_input_guard_lowers_any_bound` and the `guard` case in `test_gate_opt_in_warns_on_low_uncertainty_and_preempts_on_high`.

### `test_transport_matrix.py` agrees across cheval, the BB registry and the Flatline cap resolver for every (provider, transport) row.
- **Status**: ✓ Met
- **Evidence**: 9 rows × (output default, input bound, read timeout, `anthropic-beta`, count method) through `default_max_tokens`, `_lookup_max_input_tokens`, `_nonstreaming_read_timeout`, `_beta_header_value`, `gate`; `test_bridgebuilder_and_flatline_agree_with_the_same_rows` parses `truncation.generated.ts` and `generated-model-maps.sh` against the catalog and the two caps.

### `default_max_tokens` returns `min(cap, max_output_tokens)` for every provider with a declaration and 4,096 only without one; `temperature` is absent from the wire unless set (present at 0.7 under `LOA_CHEVAL_LEGACY_WIRE=1`).
- **Status**: ✓ Met
- **Evidence**: `test_full_size_adapter_defaults.py` (4 providers, Anthropic unchanged, kill switch, the named constant; Anthropic body without/with/dropped temperature; OpenAI chat + responses bodies; the single `wire_temperature` rule), `test_max_tokens_defaults.py` (moved expectations), `test_anthropic_cache_control` / `test_bedrock_adapter` / `test_google_adapter` still green.

### Generated BB table: `maxOutput 32000` and `reasoning: true` for `claude-opus-5`, `claude-sonnet-5`, `claude-fable-5-1`; `deriveTimeoutMs` → 1,800,000 for the three; `DEFAULTS.model === "opus"`; `tools/check-bb-dist-fresh.sh` clean.
- **Status**: ✓ Met
- **Evidence**: `truncation-registry.test.ts` (three × 32,000 / 160,000; `claude-headless` 8,192; default 4,096; flags), `multi-model-pipeline-timeout.test.ts` (three → 30 min; haiku → ladder; headless kept), `config.test.ts` (`opus`, 200K, 32K); `tools/check-bb-dist-fresh.sh` clean after `npm run build`.

### Flatline `call_model` passes `--max-tokens 64000` for a 128K entry and the catalog value for a smaller one.
- **Status**: ✓ Met
- **Evidence**: `flatline-max-tokens.bats` FMT-1 (64000 for every mode), FMT-2 (gpt-5.2 16000, gemini-3.1-pro-preview 32000), FMT-3 (alias), FMT-4 (undeclared → no flag), FMT-5 (override), FMT-6 (no literal); `cycle-124-dispatch-budgets` B1–B4 and `effort-dispatch` ED-8 on the new value.

### Health probe test: models endpoint path and the `tiny`-alias fallback; no `claude-3-` literal in the adapter.
- **Status**: ✓ Met
- **Evidence**: `test_full_size_adapter_defaults.py::test_health_probe_uses_the_models_endpoint_then_the_tiny_alias_and_no_retired_id` (GET first, POST on 404 with the cheapest declared id, source scan) and `::test_health_probe_is_true_on_a_models_endpoint_200_without_a_message_call`.

### All existing adapter suites, BB `tsx --test`, fence corpus, `repo-map-gen.sh --validate`, checksums `--check` green.
- **Status**: ✓ Met (one pre-existing BB environment failure stated)
- **Evidence**: numbers in the test-first record above; the persona test fails on `main` in the same shell for the same reason and is outside this sprint's diff.

## Deliverables not in the plan's list, and the plan items read differently
- `PER_CALL_MAX_TOKENS` / `--per-call-max-tokens` kept as the override (the plan called it dead; it is the issue-#675 operator flag with its own bats case) — the literals it defaulted to are gone.
- Bridgebuilder `isReasoningClass`: union with the legacy regexes and provider-aware, not a replacement (a replacement would have dropped the headless hops' budget, #1013).
- `retry.py` retries only the `input + max_tokens > limit` shape; the input-only shape propagates at once (a retry cannot change the input).

## Review round 1 — fixes applied

- **DISS-001 / HIGH (engineer-feedback-round-1.md)** — the unverified-zone flag was head-global. Fixed in `cheval.py`: `_hop_unverified` is computed per hop from that hop's entry and fitted budget (`input_bound(hop_entry, max_tokens=hop_budget, …)`: uncalibrated and `estimate > probed`, only under the opt-in and with the gate on) and is what the `ProviderContextLimitError` and `RateLimitError` arms consult; the head's flag remains only for the envelope's `ceiling_unverified`. Red test first: `test_ceiling_e2e.py::test_unverified_status_is_per_hop_not_inherited_from_the_head` (head unverified fails walkably → the calibrated fallback's 429 walks as `PROVIDER_OUTAGE`, no calibration record, chain exhausted normally; the calibrated fallback's provider verdict is `PROVIDER_CONTEXT_LIMIT`) — failed with `['PROVIDER_OUTAGE', 'RATE_LIMIT_UNVERIFIED']` before the fix, green after. Whole adapters suite re-run green.

- **Dissent chunk a DISS-001 / HIGH** — `record_observed` had no interprocess lock (4 × 25 concurrent appends kept 36 rows). Fixed: `flock(LOCK_EX)` on `<store>.lock` held from `load_observed` through `os.replace` (`_record_observed_locked`); red test `test_ceiling_policy.py::test_record_observed_is_serialised_across_processes` (100 of 100 rows, no temp files).
- **Dissent chunk c DISS-001 / HIGH** — the long-context premium multiplied floored per-category costs. Fixed: `_premium_cost_micro` computes `floor(tokens × rate × multiplier / 1e6)` with `Fraction(str(multiplier))` (exact decimals), keeps the remainder and the overflow guard; red test `test_long_context_pricing.py::test_premium_is_applied_before_flooring_not_to_rounded_categories` (3 × 1.25 × 1.5 → 5, not 4; 1.1 × 10 → 11 exactly).
- Dissent coverage: the whole-diff run saw 24K of 77K tokens and skipped `ceiling.py`; the review re-ran the voice per focused chunk (a core, b cheval, c adapters/metering, d scripts/tools, e BB/catalog, f tests — `adversarial-review-<chunk>.json` beside the merged envelope, every rejected-payload sidecar kept and hand-triaged: all empty). Chunks a, b, c re-run against the fixed HEAD for round 2.

## Review round 2 — fix applied

- **Dissent chunk c (round 2) DISS-001 / HIGH** — `_long_context_fields` let a non-finite multiplier through (`.inf`, `nan`, `1e309`) and the exact-decimal premium then raised inside `calculate_total_cost`. Fixed in `62aab641`: `_mult` requires `math.isfinite(m) and m > 0`, else `1.0` (the parser's contract); red test `test_long_context_pricing.py::test_non_finite_or_absurd_multipliers_are_ignored_not_fatal` (seven malformed shapes, cost 20 µ$ and no exception) — failed with `inf == 1.0` before the fix, green after. Chunk c round 3 clean.

## Next

`/review-sprint sprint-1` (dissent on the diff, every schema-rejected payload hand-triaged) → `/audit-sprint sprint-1` → COMPLETED → ledger 247 `completed` → Sprint 2.
