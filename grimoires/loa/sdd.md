# Software Design Document: Operator Decisions (cycle-127)

**Version:** 1.0
**Date:** 2026-10-07
**Status:** Draft — autonomous run (maintainer delegation with admin preapproval)
**PRD:** `grimoires/loa/prd.md` (FR-1 … FR-3, G-1 … G-3)
**Branch:** `feature/cycle-127-operator-decisions` from `main` `e70f2838`

## Table of Contents

1. [Project Architecture](#1-project-architecture)
2. [Software Stack](#2-software-stack)
3. [Database Design](#3-database-design)
4. [UI Design](#4-ui-design)
5. [API Specifications](#5-api-specifications)
6. [Error Handling Strategy](#6-error-handling-strategy)
7. [Testing Strategy](#7-testing-strategy)
8. [Development Phases](#8-development-phases)
9. [Known Risks and Mitigation](#9-known-risks-and-mitigation)
10. [Open Questions](#10-open-questions)
11. [Appendix](#11-appendix)

## 1. Project Architecture

### 1.1 Principle
Three narrow changes at existing seams. Nothing new is dispatched; a route is gated, a default is resolved where every other request field is resolved, and a measurement tool gains a second transport. Every change is fail-closed: an absent key means off, an unresolved default means "send nothing" (today's behaviour), a partial probe writes nothing.

### 1.2 FR-1 — agy opt-in gate
- **D-1.1 The key.** `hounfour.headless.agy_opt_in: boolean` in `.loa.config.yaml`, default `false`, beside `hounfour.headless.mode` (`.loa.config.yaml.example:741`). Read through the existing project-config layer (`loa_cheval/config/loader.py` `load_project_config` → `hounfour`), so the adapter and cheval see one value. No environment override (a planner must not be talked into a voice by ambient env; the audit-round convention of cycle-126).
- **D-1.2 The adapter refuses.** `AgyHeadlessAdapter` checks the key before any binary discovery or spawn. Off → raise the existing configuration-error class with the message `agy headless route is opt-in: set hounfour.headless.agy_opt_in: true (the prompt travels on the CLI's argv, readable by local users; the CLI must be OAuth-authed)`; exit class `INVALID_CONFIG`, retryable false, `failure_class: opt_in_required`. On → today's path unchanged (binary discovery, the one-time argv WARN, dispatch).
- **D-1.3 Planners plan around it.** The seam is the failure class: `adversarial-review.sh` (companion planning), `flatline-orchestrator.sh` (tertiary), Bridgebuilder (`config.ts` model registration via `cheval-delegate`) and `run-preflight.sh` / `loa-status.sh` (Providers) treat an agy route whose opt-in is off as **not planned** (`planned: false, reason: opt_in_required`) rather than as a failed voice: `voices_planned` excludes it, verdict quality is computed over planned voices only, and `/loa` prints `google · agy: opt-in (disabled; hounfour.headless.agy_opt_in)`. Bridgebuilder resolves the gate before registering the google voice: when the google route is `gemini-headless`/agy (the host has no `GOOGLE_API_KEY` HTTP route or `hounfour.headless.mode` is `cli-only`), the voice is skipped with the reason logged, so `verdict_quality` is not DEGRADED on its account. Where a voice is planned by an operator-authored chain (`companion_chain`, Flatline `tertiary`) the same `planned: false` reason applies — an explicit configuration naming agy does not override the opt-in; the WARN names both keys.
- **D-1.4 Tests.** Adapter: off → refusal before discovery (no subprocess, asserted by a spy); on → discovery proceeds (binary absent here → the existing `PROVIDER_UNAVAILABLE`). Dissent: a companion chain naming `gemini-headless` with the opt-in off yields `planned: false, reason: opt_in_required` and a two-voice verdict quality that is not DEGRADED on its account; with the opt-in on and no binary, the voice fails as today. Bridgebuilder (`__tests__`): registration skips google when the route is agy and the opt-in is off; verdict quality counts planned voices. Preflight/`/loa`: the Providers line. Each red first.

### 1.3 FR-2 — Opus 5.5 catalog effort default
- **D-2.1 The field.** `params.default_effort` (enum `low|medium|high|xhigh|max`) added to `$defs/modelEntry.properties.params` in `model-config-v3.schema.json` (the block is `additionalProperties: false` by design — "a misspelt gate must not silently no-op"). `claude-opus-5-5` sets `default_effort: high` with a comment citing the vendor default `medium` (claude-api reference 2026-10-07) and Opus 5's `high`. No other entry sets it in this cycle.
- **D-2.2 One chokepoint.** In `cheval.py`, where the `CompletionRequest` is built (`effort=getattr(args, "effort", None)` at the three sites), effort becomes `args.effort or entry.params.default_effort or None` through one helper `resolve_effort(args, entry) -> (value, source)` with `source ∈ {caller, catalog, none}`. The adapters are unchanged in contract: the HTTP adapter already emits `output_config.effort` when `request.effort` is set (`anthropic_adapter.py:268-282`, with `_effort_for_model` downgrades), the headless adapter already puts `request.effort` first (`_resolve_effort`). The headless `extra.effort` rung stays as a lower-precedence legacy.
- **D-2.3 Record it.** The MODELINV envelope gains `effort_source` next to `effort` (schema addition, additive). `--dry-run` prints `effort: high (catalog default)` / `effort: low (caller)`.
- **D-2.4 Docs.** Migration addendum: the "pass `--effort high`" caveat is replaced by the default and the override; SDD cycle-126 D-4.1 amendment gets a one-line pointer; CHANGELOG; bd-9qe2 closed with the evidence.

### 1.4 FR-3 — Ceiling probe through the headless route
- **D-3.1 Transport option.** `tools/ceiling-probe-live.py --transport {api,claude-headless}` (default `api`, unchanged). `claude-headless` invokes `${CLAUDE_HEADLESS_BIN:-claude}` with exactly the adapter's shape (`-p --output-format json --permission-mode plan --no-session-persistence --tools "" --model <id>`, prompt on stdin, `--max-turns 1` if the adapter uses it — mirror `claude_headless_adapter.py:255-300`), one call per bisection step, `max_tokens`-equivalent kept small (the adapter's own output cap flag if any). OK criterion: a completed JSON result with a `result`/`stop_reason` and no `is_error`; a size failure is the CLI reporting the provider's context/token-limit message (`is_context_limit_message` / `is_token_limit_message` reused from `loa_cheval.routing.ceiling` by adding the adapters path to `sys.path` as the orchestrator does); any other failure stops with exit 1. Cost accounting uses the catalog pricing for the id (Bedrock pricing differs; the record notes `pricing_basis: catalog_estimate`).
- **D-3.2 Record and write.** The record adds `transport`, `cli_bin`, `cli_model` (the wrapper's resolved id when discoverable — `ANTHROPIC_DEFAULT_OPUS_MODEL` for `opus`), `host_route` note. `--write-catalog` with `--transport claude-headless` sets `probed_ceiling: <largest_ok>` and `ceiling_calibration: {source: operator_set, calibrated_at: <now>, sample_size: null, stale_after_days: <existing or 90>, reprobe_trigger: "API-transport probe (tools/ceiling-probe-live.py --transport api) from a host with ANTHROPIC_API_KEY; this bound was measured through claude-headless on Bedrock (<cli_model>) on <date>"}`; the `loa:shortcut` marker comment on the entry is replaced by the provenance comment. `partial: true` (budget cap) or any non-size failure → exit 3 / 1, nothing written.
- **D-3.3 Consumers.** `cheval` already derives the bound from `probed_ceiling` until `calibrated_at` is set and from `ceiling_calibration` after (cycle-124/126 policy); `ceiling_stale` follows `stale_after_days`. Bridgebuilder's generated registry (`gen-bb-registry.ts`) and `generated-model-maps.sh` regenerate from the catalog; their tests read the catalog value.
- **D-3.4 The run.** `CLAUDE_HEADLESS_BIN=$HOME/.local/bin/claude-bedrock tools/ceiling-probe-live.py --model claude-opus-5-5 --transport claude-headless --min-tokens-probe 180000 --max-tokens-probe 1000000 --budget-usd 20 --output grimoires/loa/reports/2026-10-07-opus-5-5-ceiling-probe-cli.json [--write-catalog]` run by the lead once, after the tool's tests are green; the catalog write is a reviewed diff in the sprint. Tests pinning `180000` for `claude-opus-5-5` (`cycle-124-anthropic-catalog.bats`, `model-config-v3-schema.bats`, `loa-status-providers.bats` LSP-5, `gen-bb-registry-codegen.bats`, `test_anthropic_catalog_floor.py`, `test_ceiling_e2e.py`, `test_input_size_consumers.py`, `test_providers.py`, `test_ceiling_probe_write_catalog.py`, `migrate-preserve-thresholds.bats`, `adversarial-review-companion.bats`) are audited: policy pins stay, literal pins of the Opus 5.5 value read the catalog.

## 2. Software Stack
Bash (hooks, orchestrators, bats), Python 3.13 (cheval, adapters, probe, pytest), TypeScript (Bridgebuilder, vitest). No new dependency.

## 3. Database Design
None. State: `.loa.config.yaml` (operator), `.claude/defaults/model-config.yaml` (catalog), `grimoires/loa/reports/` (probe record), MODELINV envelope (additive field).

## 4. UI Design
`/loa` Providers line for the google hop; `cheval --dry-run` effort line; the probe's stderr progress and JSON record.

## 5. API Specifications
- `hounfour.headless.agy_opt_in: boolean` (default false).
- `params.default_effort: low|medium|high|xhigh|max` (catalog entry).
- MODELINV `effort_source: caller|catalog|none` (additive).
- `tools/ceiling-probe-live.py --transport {api,claude-headless}`; record fields `transport`, `cli_bin`, `cli_model`, `pricing_basis`.

## 6. Error Handling Strategy
Gate off → `INVALID_CONFIG` / `opt_in_required`, never a spawn. Planners map that class to `planned: false`. Effort: an invalid catalog value fails schema validation (load time), never a silent no-op. Probe: non-size failure → exit 1 and no write; budget cap → exit 3 and no write; the record is written in every case with `partial`/`error` set.

## 7. Testing Strategy
Red first for every behaviour (D-1.4, D-2.4, D-3.4). Suites: adapter pytest (`tests/test_agy_*`, `test_ceiling_*`, `test_effort_*`), `tests/unit/adversarial-review-companion.bats` (planned/not-planned), Bridgebuilder vitest (registration + verdict quality), `run-preflight`/`loa-status-providers` bats, `model-config-v3-schema.bats` (the new enum, a bad value rejected), `cycle-124-anthropic-catalog.bats`, codegen regen tests, `test_ceiling_probe_write_catalog.py` (CLI transport write shape, partial → no write). Live: the one probe run (D-3.4) with its record; a dry-run `cheval invoke --model opus` showing `effort: high (catalog default)`; a `/loa` run showing the opt-in line.

## 8. Development Phases
One sprint, global 251 (see `grimoires/loa/sprint.md`).

## 9. Known Risks and Mitigation
| Risk | Mitigation |
|---|---|
| Bridgebuilder's registration seam cannot see `.loa.config.yaml` | `cheval-delegate` returns the `opt_in_required` class on a probe call; BB maps it to "not planned" — the gate is enforced by the adapter either way |
| The CLI transport's OK criterion misreads a thinking-only turn as failure | OK = completed result without `is_error`; the adapter's output cap keeps turns short (the probe asks for "Reply: ok.") |
| The measured bound exceeds Bedrock's per-request limit on another region/profile | `reprobe_trigger` names the transport and profile; the observed-bound store still preempts on a live provider error |
| A literal 180K pin left behind turns red after the write | the sweep in D-3.4 runs before the write; codegen regen + the full affected suites after |

## 10. Open Questions
None blocking. Whether Bedrock's accepted input for `global.anthropic.claude-opus-5-5` reaches 1M is what the probe answers.

## 11. Appendix
### A. Catalog values used
`claude-opus-5-5`: `context_window 1,000,000`, `max_output_tokens 128,000`, `probed_ceiling 180,000`, `ceiling_calibration.source conservative_default`, pricing $4 / $20 per MTok (API; Bedrock billed separately).
### B. The headless command shape mirrored by the probe
`claude_headless_adapter.py:255-300`: `-p`, `--output-format json`, `--permission-mode plan`, `--no-session-persistence`, `--tools ""`, `--model <id>`, optional `--effort`, `--json-schema`, `--system-prompt`/`--append-system-prompt`.
