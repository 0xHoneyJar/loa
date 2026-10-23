# Reviewer concerns — sprint-1 (PR: cycle-127 sprint-251 operator decisions)

Phase 2 notes for the cross-model dissent. Line numbers are head-file lines.

1. `AgyOptInRequiredError` subclasses `ConfigError` (types.py:503). cheval's chain walk hard-aborts on ConfigError
   (cheval.py ~2545 "STATIC misconfig ... falls through to the hard-abort arm"). Under `hounfour.headless.mode: prefer-cli`
   the chain resolver puts CLI hops first, so with the opt-in off (new default) every Google model aborts at the agy hop with
   INVALID_CONFIG before the HTTP rung is tried. Planners (flatline-orchestrator.sh:534, bridgebuilder config.ts:182) treat
   only `cli-only` as agy-routed, so they PLAN the voice and cheval then refuses it — a failed/DEGRADED voice, the outcome FR-1
   says cannot happen.
2. adversarial-review.sh filters only the companion chain (4083); the primary chain (`model` + `fallback_chain`, walked at 4134)
   is not filtered, so a gemini-headless primary hop with the opt-in off is dispatched, exits 2, and is recorded as a failed hop.
   Also `_adv_agy_filter_chain` (2360) matches only the `gemini-headless` canonical name, not a Google HTTP model under cli-only.
3. Catalog: claude-opus-5-5 written as `operator_set` 936000 from a probe whose own outcome was `partial` (model-config.yaml:496);
   the tool writes only on `clean`. `sample_size: null`. Measured through Bedrock, applied to the HTTP anthropic adapter too.
4. test_anthropic_catalog_floor.py:146-147 — for a calibrated entry `cap = entry["effective_input_ceiling"]`, making
   `expected == entry["effective_input_ceiling"]` a tautology.
5. loader.agy_opt_in_enabled (loader.py:113-126) re-parses the whole system catalog + project config on every complete(),
   health_check() and validate_config() call; cwd-walk root rather than the root cheval loaded.
6. resolve_effort (cheval.py:907-908) warns "sets both" for HTTP entries whose extra.effort is never read.
7. validateApiKeys default parameter `readAgyGate()` (config.ts:190) reads `.loa.config.yaml` relative to process cwd for any
   caller that passes no gate (main.ts untouched); the pipeline passes repoRoot.
8. agy validate_config() now always reports an error on a default install (agy_headless_adapter.py:261) — any
   whole-catalog validation path would fail by default.
