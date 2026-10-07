# Product Requirements Document: Operator Decisions (cycle-127)

**Version:** 1.0
**Date:** 2026-10-07
**Status:** Draft — autonomous run (maintainer delegation: *"do these on my behalf, I sign off on your weighted decision"*, then *"ship it all when ready … admin preapproval"*)
**Author:** Loa lead agent (Fable 5.1) for the maintainer
**Branch:** `feature/cycle-127-operator-decisions` from `main` `e70f2838` (cycle-126 merged)

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Problem Statement](#problem-statement)
3. [Goals & Success Metrics](#goals--success-metrics)
4. [User Personas & Use Cases](#user-personas--use-cases)
5. [Functional Requirements](#functional-requirements)
6. [Non-Functional Requirements](#non-functional-requirements)
7. [User Experience](#user-experience)
8. [Technical Considerations](#technical-considerations)
9. [Scope & Prioritization](#scope--prioritization)
10. [Success Criteria](#success-criteria)
11. [Risks & Mitigation](#risks--mitigation)
12. [Timeline & Milestones](#timeline--milestones)
13. [Appendix](#appendix)

> Sources: document structure per `discovering-requirements` Phase 8 template; decision record `grimoires/loa/NOTES.md` § Decision Log — 2026-10-07.

## Executive Summary

Cycle-126 left three decisions to the maintainer. The maintainer delegated them with admin preapproval, asking for the weighted choice a competitive-but-collaborative council would make given Loa's material reality: one maintainer, a primary host where the `agy` CLI is absent and the direct Anthropic API is geo-refused (KF-040), every Opus 5.5 hop running through `claude-bedrock`, and a 2.0 release-candidate line.

The three decisions: **(D1)** the `agy` (Antigravity) headless route becomes opt-in, default off — today it is planned on every host and fails where the CLI is absent (Bridgebuilder #1274 ran DEGRADED 2/3 for that reason), and its prompt travels on argv; **(D2)** `claude-opus-5-5` gets a catalog effort default of `high` — the vendor default is `medium`, one level below Opus 5's `high`, so every `opus` caller that passes no `--effort` lost a reasoning level when the alias retargeted in cycle-126; **(D3)** the Opus 5.5 input ceiling, held at the conservative 180K `loa:shortcut`, is probed through the route this host actually uses (the headless CLI on Bedrock), and a clean measured bound is recorded honestly as `operator_set`.

> Sources: `grimoires/loa/a2a/sprint-250/auditor-sprint-feedback.md` (bd-ugmi, bd-9qe2 context); `grimoires/loa/a2a/bridgebuilder-1274-triage.md` (the google voice failing on this host); claude-api skill reference 2026-10-07 (Opus 5.5 effort default `medium`); `docs/migration/v2.0-model-generation-floor.md` § Calibrate the input ceiling.

## Problem Statement

### The Problem
Three framework behaviours are wrong for the fleet's actual shape. A voice is planned that cannot exist on most hosts and degrades every multi-model verdict; the default Opus model reasons one level shallower than its predecessor without anyone having chosen that; and the framework's most capable default model is clamped to 18 % of its window because the only probe tool speaks to an endpoint the primary host cannot reach.

### User Pain Points
- **Degraded verdicts with no cause the operator can act on.** `/loa`, Bridgebuilder and Flatline report `DEGRADED — 2/3 voices` on hosts without `agy`; the fix (install an OAuth-authed Antigravity CLI) is not something most operators will do, and the prompt-on-argv exposure makes it a decision they should take knowingly.
- **A silent quality regression.** `opus` → `claude-opus-5-5` (cycle-126 bd-2fti) changed the effort default from `high` to `medium` for every review, audit, dissent and Flatline call that does not pass `--effort`.
- **A ceiling nobody can raise.** `tools/ceiling-probe-live.py` requires `ANTHROPIC_API_KEY` and the direct API; the primary host has neither, so the `loa:shortcut` 180K bound has no upgrade path.

### Current State
`gemini-headless` → `AgyHeadlessAdapter` on any host with `agy` on PATH; Bridgebuilder registers the google voice when `GOOGLE_API_KEY`/`GEMINI_API_KEY` is set; Flatline's tertiary is commented out in this repo's config "unless `agy` is installed". `cheval --effort` is sent only when a caller passes one; the headless adapter alone reads a catalog `extra.effort`. `claude-opus-5-5` carries `probed_ceiling: 180000`, `ceiling_calibration.source: conservative_default`.

### Desired State
An agy route that is off unless the operator says otherwise, reported as *not planned* (never *failed*) by every planner; an Opus 5.5 that reasons at `high` by default through both the HTTP and the CLI adapter unless the caller asks for less; a measured input bound for Opus 5.5 on this host's route, recorded with its provenance and a re-probe trigger.

> Sources: `.claude/adapters/loa_cheval/providers/__init__.py:55`; `.claude/skills/bridgebuilder-review/resources/config.ts:136`; `.loa.config.yaml:341-345`; `.claude/adapters/loa_cheval/providers/claude_headless_adapter.py` `_resolve_effort`; `.claude/adapters/loa_cheval/providers/anthropic_adapter.py:268-282`; `.claude/defaults/model-config.yaml:470-513`.

## Goals & Success Metrics

### Primary Goals
- **G-1 No planned voice that cannot exist.** On a host without `agy` and without the opt-in, no planner counts the agy route as a voice: Bridgebuilder, Flatline and the dissent report it as `planned: false` with a reason, not as a failure, and verdict quality is not DEGRADED on its account.
- **G-2 Opus 5.5 reasons at `high` by default.** A cheval call to `opus` (or `claude-opus-5-5`) with no `--effort` sends `output_config.effort: high` over HTTP and `--effort high` to the CLI; an explicit `--effort` still wins.
- **G-3 A measured Opus 5.5 bound on this host's route.** The probe runs through `claude-headless` on Bedrock; the result and its provenance are in the catalog (or the attempt and the reason are recorded if the bound is unclean).

### Key Performance Indicators (KPIs)
| KPI | Before | Target |
|---|---|---|
| Bridgebuilder verdict quality on a host without agy | DEGRADED 2/3 | not degraded on the google voice's account (voice `planned: false`) |
| Effort sent for an `opus` call with no `--effort` | none (vendor default `medium`) | `high` (HTTP and CLI), overridable |
| `claude-opus-5-5` input bound | 180,000 `conservative_default` | measured bound, `operator_set`, `calibrated_at` set; or 180,000 with the attempt recorded |

### Constraints
- One maintainer; unattended run; nothing outside the sanctioned implement → review → audit → PR → Bridgebuilder path.
- `agy` is not installed here and is never run here (operator instruction); the argv re-probe (bd-ugmi) stays operator-side.
- The direct Anthropic API is unreachable from this host (KF-040); Bedrock is the only Opus 5.5 route here.
- Probe spend is bounded (≤ $20) and goes to the Bedrock account.
- Nothing is published by the implementation; shipping (rc.3) follows the merge as a separate, preapproved step.

## User Personas & Use Cases

### Primary Persona: The maintainer-operator
Runs Loa on a host with one or two provider families. Wants `/loa` to tell the truth about which voices exist and why, wants review quality not to regress silently, and wants the model ceiling to reflect a measurement, not a guess.

### Secondary Persona: The unattended run agent
Dispatches review, audit and dissent through cheval. Needs a default effort that matches the gate's purpose and a voice plan that cannot fail on a predictable absence.

### Tertiary Persona: A downstream fleet operator
Installs Loa on a host with `agy` and wants Gemini back as a third voice. Flips one documented key, knowingly accepting the argv exposure the WARN names.

### Use Cases
- UC-1: `/loa` on a host without agy shows the google hop as "agy: opt-in (disabled)" and the breaker row unaffected; Bridgebuilder plans two voices and reports full quality.
- UC-2: A downstream operator sets the opt-in key; the agy route dispatches as before, with the existing one-time argv WARN.
- UC-3: `cheval invoke --model opus` with no `--effort` records `effort: high` in the MODELINV envelope; `--effort low` records `low`.
- UC-4: The operator runs the probe with `--transport claude-headless`; the catalog gains the measured bound and its `reprobe_trigger`; `cheval` preempts above the new bound instead of 180K.

## Functional Requirements

### FR-1: agy opt-in gate (D1)
- FR-1.1 A single boolean in `.loa.config.yaml` (`hounfour.headless.agy_opt_in`, default `false`) gates the agy route. Absent or `false`: the `AgyHeadlessAdapter` refuses to dispatch with a configuration error that names the key and the reason (prompt on argv; CLI must be OAuth-authed); it never spawns the binary.
- FR-1.2 Every planner distinguishes "route disabled by opt-in" from "route failed": the dissent envelope and the Flatline run record the voice as `planned: false, reason: opt_in_required`; Bridgebuilder does not register the google voice when its only route is agy and the opt-in is off, and reports full verdict quality for the voices it did plan; `run-preflight.sh` and `/loa` Providers show "agy: opt-in (disabled)".
- FR-1.3 With the opt-in `true`, behaviour is exactly today's (the one-time argv WARN included).
- FR-1.4 Documentation: migration addendum, `.loa.config.yaml.example` key with the rationale, bd-ugmi updated (decision recorded; argv re-probe remains operator-side).

### FR-2: Opus 5.5 catalog effort default (D2)
- FR-2.1 The catalog entry schema gains a typed `params.default_effort` (enum `low|medium|high|xhigh|max`); `claude-opus-5-5` sets `high`. Unknown values are rejected at validation like every other `params` gate.
- FR-2.2 cheval resolves effort once, at the chokepoint: explicit `--effort` (or request metadata) wins; else the resolved entry's `params.default_effort`; else none (vendor default). Both the HTTP adapter and the headless adapter receive the resolved value; the headless adapter's `extra.effort` rung keeps its place below the chokepoint value.
- FR-2.3 The MODELINV envelope records the effective effort and whether it came from the caller or the catalog.
- FR-2.4 Tests red first: a dry-run `opus` call with no `--effort` reports `high`; `--effort low` reports `low`; the HTTP adapter emits `output_config.effort: high`; the CLI adapter passes `--effort high`; a `claude-opus-5` call (no default) still sends nothing. Docs: migration addendum (replaces the "pass `--effort high`" caveat), SDD D-4.1 amendment note, CHANGELOG, bd-9qe2 closed.

### FR-3: Ceiling probe through the headless route (D3)
- FR-3.1 `tools/ceiling-probe-live.py --transport claude-headless` bisects the accepted input size by invoking the configured `CLAUDE_HEADLESS_BIN` (default `claude`) with the adapter's flags (`-p`, `--tools ""`, `--permission-mode plan`, `--no-session-persistence`, `--model <id>`, prompt on stdin), the same OK criterion (a completed response, not a text block), the same budget cap and record shape, plus `transport`, `cli_model` and the Bedrock profile in the record. The API transport is unchanged.
- FR-3.2 `--write-catalog` under the CLI transport writes `probed_ceiling` and `ceiling_calibration {source: operator_set, calibrated_at, sample_size: null, stale_after_days, reprobe_trigger}` where `reprobe_trigger` names the API-transport probe and the measured transport; the `loa:shortcut` marker is replaced by the provenance comment. A partial or unclean result writes nothing and exits 3.
- FR-3.3 The probe is run once for `claude-opus-5-5` on this host (`claude-bedrock`, `global.anthropic.claude-opus-5-5`), budget ≤ $20; the record is kept under `grimoires/loa/reports/`.
- FR-3.4 Every test that pins the 180K bound for `claude-opus-5-5` follows the catalog value by reading it, not by literal; tests that pin the policy (probed bound until calibrated) keep their meaning.

### FR clarifications from the Flatline review (2026-10-07)
- FR-1.5 One shared predicate decides "agy route planned"; the refusal is `INVALID_CONFIG` with `failure_class: opt_in_required` and never trips a breaker; `planned: false` reasons are `opt_in_required | binary_absent | no_credentials | no_route`; opt-in `true` with `agy` absent is a planned voice that fails; a one-time WARN names the key when `agy`/a Gemini key is present but the opt-in is off; a fake-`agy` negative test proves no spawn.
- FR-2.5 The default applies to the resolved catalog entry (aliases carry none); precedence caller > catalog > headless `extra.effort` > none; the envelope records `effort_source` and the effective wire value after adapter downgrades; an invalid catalog value is `none` with a WARN, never a crash.
- FR-3.5 The CLI transport measures the accepted size from the CLI's `usage`, verifies completion with a random needle echoed back, pins `--effort low --max-turns 1`, retries transient failures with backoff, always writes the record, writes the catalog only on a clean verified bound (tightening below 180K if that is what was measured), and carries provenance (`method: probed_headless`, `transport`, `cli_version`, Bedrock id, measured tokens) inside `ceiling_calibration` with `source: operator_set`.

## Non-Functional Requirements

### Performance
No new per-call work beyond one config read for the gate and one dictionary lookup for the effort default.

### Security
The gate is fail-closed (absent key = off). The argv exposure is named in the error and the docs; no credential is read or printed by the probe's CLI transport (the wrapper reads its own secret).

### Reliability
A disabled route is never a failed voice; verdict quality reflects planned voices only. The probe never writes the catalog on a partial result.

### Compliance
Zone rules: framework edits under the cycle-127 marker via `/implement`; state writes by the lead; the catalog write is a tracked, reviewed change.

## User Experience

### Key User Flows
`/loa` → Providers block reads "google · agy: opt-in (disabled) — set hounfour.headless.agy_opt_in: true" → operator decides. `cheval invoke --model opus …` → envelope `effort: high (catalog default)`. `tools/ceiling-probe-live.py --model claude-opus-5-5 --transport claude-headless --write-catalog` → catalog diff + record.

## Technical Considerations
See the SDD. The config key lives under `hounfour.headless` beside `mode`; the gate is read by the adapter (refusal) and by the planners (planning). The effort default is a typed `params` gate per the catalog's own rule ("a misspelt gate must not silently no-op"). The probe's CLI transport measures the CLI+Bedrock path, which is this host's only Opus 5.5 route; the API-transport bound remains unmeasured and is named in `reprobe_trigger`.

## Scope & Prioritization
In: FR-1 … FR-3 and their docs/tests. Out: moving the agy prompt off argv (needs an agy host — bd-ugmi), any change to Gemini HTTP routing (KF-001/008), raising other 5-family ceilings, publishing (a separate preapproved step after merge).

## Success Criteria
- SC-1 On this host, with no opt-in: `cheval` refuses an agy dispatch with the key named; Bridgebuilder's dry run plans two voices with full quality; `/loa` shows the opt-in line. With the key `true`: the adapter attempts the binary (absent here → the existing PROVIDER_UNAVAILABLE path).
- SC-2 Dry-run and adapter tests prove the effort resolution (FR-2.4); the migration caveat is gone.
- SC-3 The probe record exists; the catalog carries either the measured `operator_set` bound or the unchanged 180K plus a documented attempt; schema and catalog tests green.
- SC-4 Review and audit APPROVED (Fable) with cross-model dissent; CI green; one Bridgebuilder pass triaged; merged.

## Risks & Mitigation
| Risk | Mitigation |
|---|---|
| The Bedrock CLI route rejects large inputs for a non-size reason (KF-037 timeouts, KF-038 window) | the probe distinguishes size failures from others and stops on a non-size failure (exit 1) without writing |
| The probe spends more than planned | `--budget-usd 20` cap; partial = no write |
| A planner still counts the disabled voice | FR-1.2 tests per planner; the dissent envelope's `planned: false` reason is asserted |
| Catalog default effort raises cost for executor-class callers | only `claude-opus-5-5` carries a default; `cheap`/Sonnet entries unchanged; callers override |

## Timeline & Milestones
One sprint (global 251): implement → review → audit → PR → CI → Bridgebuilder → merge → ship.

## Appendix
- A. Decision record: `grimoires/loa/NOTES.md` § Decision Log — 2026-10-07.
- B. Evidence: `a2a/bridgebuilder-1274-triage.md` (google voice failure), `a2a/sprint-250/review-dissent-triage-run-1.md` (effort caveat origin), claude-api skill 2026-10-07 (Opus 5.5 effort default `medium`).
