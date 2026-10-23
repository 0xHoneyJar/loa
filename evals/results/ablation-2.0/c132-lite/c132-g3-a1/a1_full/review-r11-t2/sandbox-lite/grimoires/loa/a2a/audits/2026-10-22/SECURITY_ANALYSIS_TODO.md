# Security analysis working file — sprint-1 audit (PR cycle-126 sprint-247), 2026-10-22

Scope: the 65 files of `pr/head.diff`. Trust levels: PROVIDER = HTTP response body from the configured endpoint (TLS first-party by default; proxy/endpoint override supported); CATALOG = `.claude/defaults/model-config.yaml` (System Zone, repo-tracked, trusted); ENV = operator environment; STATE = `.run/ceiling-observed.json` (State Zone, written by cheval).
`security-audit-scope.sh --json`: sources 11 (routes 7, handlers 4), sinks 410 (command_exec 218, file_operations 173, database_query 19), auth files 277, llm files 274 — whole-repo counts; the PR surface below is the subset traced.

## Phase 1A — recon (sources → sinks)

| # | Item | Trust | Location (head) | Status |
|---|------|-------|-----------------|--------|
| S1 | Provider 400/413 body → `is_context_limit_message` / `parse_context_limit` → `ProviderContextLimitError(input_tokens, limit, max_tokens)` | PROVIDER | `anthropic_adapter.py:361`, `:503`; `ceiling.py:172-198` | CONFIRMED → SEC-001 (no plausibility floor), SEC-006 (marker overlap) |
| S2 | Parsed numbers → `record_observed` → `.run/ceiling-observed.json` → `observed_for` → `input_bound` (second-order: stored data becomes the bound) | PROVIDER→STATE | `cheval.py:2005-2012`; `ceiling.py:122`, `:240-306` | CONFIRMED → SEC-001 (repro R5), SEC-003 (lockless RMW) |
| S3 | Raw provider text → `models_failed[].message_redacted` and stderr `_error_json` | PROVIDER | `cheval.py:2022`, `:2032` | CONFIRMED → SEC-002 (envelope path redacted by modelinv; stderr not) |
| S4 | `count_tokens` POST `{endpoint}/messages/count_tokens` with the full prompt + beta header | CATALOG endpoint | `anthropic_adapter.py:591-620` | SAFE — same data path as the request, failures swallowed to heuristic, logs only exception class |
| S5 | `health_check` GET `{endpoint}/models?limit=1` with `x-api-key` via new `http_get` | CATALOG endpoint | `anthropic_adapter.py:665-680`; `base.py:309-358` | PARTIAL → SEC-004 (redirects/scheme/unbounded body; pre-existing lineage), CQ-008 |
| S6 | `params.beta_headers` → `anthropic-beta` header | CATALOG | `anthropic_adapter.py:163-182` | SAFE — strict allowlist regex, ConfigError fail-closed, dedup, one header |
| S7 | `LOA_CHEVAL_CEILING_OBSERVED_PATH`, `LOA_CHEVAL_MAX_INPUT_TOKENS`, `LOA_CHEVAL_UNCALIBRATED_CEILING`, `LOA_CHEVAL_LEGACY_CEILING` | ENV | `ceiling.py:59-82`, `:211-222` | SAFE — int-parsed / enumerated; path override is operator-level (also honoured by `loa-status.sh:808`) |
| S8 | `pricing.long_context.{threshold_tokens, input_multiplier, output_multiplier, verified}` → `_long_context_fields` → `calculate_total_cost` | CATALOG | `pricing.py:168-173`, `:282-300` | CONFIRMED → CQ-004 (cache tokens), CQ-005 (`verified` ignored), CQ-006 (inf; repro R6b) |
| S9 | `tools/ceiling-probe-live.py --write-catalog [PATH]` → text edit of the catalog → `os.replace` | ENV/CLI | `ceiling-probe-live.py:101-176` | PARTIAL → DO-001 (0600 mode, temp leak, literal price map); API key from env only (`:195`) |
| S10 | `flatline_voice_max_tokens` → `MODEL_IDS[$key]` / `MODEL_MAX_OUTPUT[$key]` → `(( ))` → `--max-tokens` | CATALOG/alias | `flatline-orchestrator.sh:936-945`, `:1030` | SAFE for injection (digits validated before arithmetic); ARCH-002 for budget semantics |
| S11 | `gen-adapter-maps.sh` jq → bash `declare -A MODEL_MAX_OUTPUT` (model key unescaped into generated bash) | CATALOG | `gen-adapter-maps.sh:249-266` | SAFE / pre-existing pattern of the other maps; keys are catalog ids |
| S12 | `loa-status.sh _anthropic_ceiling_json`: alias → yq path interpolation; store → jq `--arg`/`--argjson` | CATALOG/STATE | `loa-status.sh:795-823` | PARTIAL → SEC-005 (yq interpolation; `obs` validated `^[0-9]+$` before `--argjson`) |
| S13 | `_multipass_is_anthropic` regex on model arg | CLI | `lib-multipass.sh:98` | SAFE (regex match only) → ARCH-004 drift |
| S14 | Bridgebuilder `isReasoningClass` → `GENERATED_REASONING[modelId]` / registry provider check | CATALOG | `multi-model-pipeline.ts:56-61` | SAFE (strict `=== true`, provider cross-check) |
| S15 | Bridgebuilder default `model: "opus"`, `maxInputTokens 200_000`, `maxOutputTokens 32_000` → `effectiveInputBudget` | CONFIG default | `config.ts:172-177` | CONFIRMED → ARCH-001 (alias unknown to budget tables) |
| S16 | `wire_temperature` → provider bodies (4 adapters) | CLI/binding | `base.py:177-184`; adapters | SAFE → CQ-007 (legacy-wire log noise) |
| S17 | Retry-layer shrink `request = replace(request, max_tokens=room)` with `room = limit − input_tokens` from S1 | PROVIDER | `retry.py:472-496` | CONFIRMED → CQ-003 (final-attempt degrade; repro R2); bounds `room ≥ 4096 and room < max_tokens` are SAFE |
| S18 | Walk gate `_lookup_max_input_tokens(..., max_tokens=_hop_budget)` vs `estimate_tokens(messages)` | internal | `cheval.py:2111-2135`; `:676-757` | CONFIRMED → CQ-001 (repro R1) |
| S19 | `_ceiling_unverified` head-only flag in D-1.1b arms | internal | `cheval.py:1843`, `:2256`, `:2297` | CONFIRMED → CQ-002 (repro R3), ARCH-003 |
| S20 | Secrets sweep (`sk-ant-`, `sk-`, `AKIA`, `api_key=`) over every head text file | — | all | SAFE — none |
| S21 | Test hygiene: `test_ceiling_probe_write_catalog.py` network? | — | `:22-85` | SAFE — imports the tool by path, uses `tmp_path`, deletes `ANTHROPIC_API_KEY` |
| S22 | `dist/` vs `resources/` for bridgebuilder | build | `dist/*` | N/A here — review spot-checked (reasoning table 31 entries, maxOutput 32000 ×12 in both); not re-run (no node_modules) |

## Phase 1B — investigate notes

- S1→S2→gate: the only guard between an upstream integer and the next request's bound is `_pos_int` (> 0). Repro R5 drives the bound to 1 with one body. The newer framework tree in this workspace has `_plausible_observed` ("r251-4 S7 (audit run-2 n38)") — not in the PR.
- S3: `modelinv.redact_payload_strings` runs on the envelope (patched out in the PR's e2e harness, which is why the tests pass with raw text); stderr JSON has no redactor on this path. Pre-existing arms print `str(_e)` identically (`cheval.py:2157`, `:2245`).
- S17: `continue` on the last iteration → generic `RetriesExhaustedError` (last_error "unknown") → cheval's exhausted arm walks.
- S18: pre-flight count stored in `_walk_estimate` (`:1842`) but the walk gate re-estimates (`:2119`); both hops in the repro share the 180K probed bound → CHAIN_EXHAUSTED.
- Deferred (time budget): the Bedrock/Google/OpenAI adapters' error paths were read for the temperature change only; no context-limit typing was added for them in this PR (Anthropic only), so no new sink there.

## Phase 1C — dissent

`adversarial-review.sh --type audit --sprint-id sprint-1 --diff-file pr/head.diff --json` → `adversarial-audit.json`: gpt-5.5-pro + claude-headless, both completed, independent; 6 findings (1 HIGH, 3 MEDIUM, 2 LOW), 0 rejected payloads. Triage table in the feedback file.

## Repro checks

`test_audit_repro.py` (this directory) — 7 checks, all FAIL against the PR on the overlay at `/tmp/aroot` (workspace framework tree + PR files + a 9-symbol `types.py` shim for the newer untouched modules). PR's own 12 test files on the same overlay: 163 passed, 1 failed (workspace config artefact: advisor tier → `claude-headless`).
