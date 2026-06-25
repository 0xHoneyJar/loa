# PRD — Cheval Headless: Baseline Refactor + AGV Migration

> **Standalone plan** (not a registered cycle). Generated from
> `grimoires/loa/proposals/headless-adapters/headless-adapter-expansion.md`. Leaves the active
> cycle-114 PRD + ledger untouched; promote to a formal cycle when 114 ships.
> Scope: **Phase 1 (foundation refactor) + Phase 2 (AGV)**. Phase 3 (GLM via
> OpenRouter) is a follow-on, out of scope here.

## 1. Problem Statement

Two coupled problems in cheval's headless-CLI layer:

1. **The Google headless voice is dead.** `gemini-headless` shells the `gemini` CLI (Gemini Code Assist for individuals), which Google retired → `IneligibleTierError` on every dispatch → circuit breaker trips → the Google voice silently drops from Flatline / multi-model review.
2. **The headless adapters are clone debt.** Five adapters (claude/codex/cursor/gemini/grok) total **2,766 lines** and are ~75% identical (`_build_prompt`/`health_check`/`_compute_timeout` md5-identical modulo names; `complete()` near-verbatim). Adding more (AGV, later GLM) without a base multiplies the rot.

> Sources: #1089 (gemini-headless dead → Antigravity); #1027 + `grimoires/loa/proposals/codebase-refactor-review-2026-06-12.md` R8/R1; line counts verified `wc -l` 2026-06-19 (2,766 ln across 5 adapters).

## 2. Goals & Success Metrics

| Goal | Metric |
|---|---|
| Restore the Google headless voice | `gemini-headless` dispatch returns a clean completion via `agy`; Flatline shows the Google voice live; **#1089 closed** |
| Pay down clone debt before adding more | 5 adapters collapse onto one `HeadlessCLIAdapter` base; each subclass ≤ ~150 ln; cluster drops ~2,766 → ~700–900 ln |
| No behavior regressions | All 38 headless test files green before AND after the refactor |
| Make the next adapter cheap | A new headless terminal = one registry-table row + a ~120-ln subclass |

> Sources: brief §Phase 1/2 acceptance; 38 test files verified 2026-06-19.

## 3. Users & Stakeholders

- **Primary**: the operator + any agent running Flatline / Bridgebuilder / adversarial multi-model review — they need the Google voice live and the headless layer maintainable.
- **Secondary**: future adapter authors (AGV now, GLM/others later) — they inherit the base + table.

## 4. Functional Requirements

**Phase 1 — Foundation (Full R8 sweep)**
- **FR-1** — Add `HeadlessCLIAdapter(ProviderAdapter)` template base: shared `complete()` + class-attribute-driven prompt/health/timeout/validate; subclasses override only `_build_command` / `_parse_output` / `_classify_error`. (R8)
- **FR-2** — Migrate all 5 existing adapters (claude/codex/cursor/gemini/grok) onto the base, behavior-preserving. The 38 headless test files are the pin.
- **FR-3** — Derive the headless-provider registries from ONE declarative table (root cause of the "#966 config-dead" bug). (R1)
- **FR-4** — Adjacent cleanups in the sweep (operator may trim at sprint-plan): R10 split `base.py` (891 ln) by consumer group; R11 structurally guard the output-swallow class.

**Phase 2 — AGV migration**
- **FR-5** — Repoint the `gemini-headless` terminal to shell the `agy` (Antigravity) CLI via `-p`; swap auth to `agy`'s **OAuth** (spike T4.1: no API-key flag exists). Implemented as a thin subclass on the FR-1 base.
- **FR-6** — Handle `agy`'s non-TTY stdout behavior (documented CI gotcha) so non-interactive cheval dispatch yields clean parseable output.
- **FR-7** — Preserve the `gemini-headless` name + all aliases (`model-config.yaml:752`) so existing configs/refs resolve unchanged; keep `gemini-api` (#1091) as the HTTP fallback.

> Sources: brief §Decisions 1–4; `model-config.yaml:321` (gemini-headless terminal) + `:752` (alias); #1091 (gemini-api).

## 5. Technical & Non-Functional

- **Behavior preservation** — the 38 headless test files must pass unchanged; collapse the per-adapter clone test suites into one parametrized suite where possible (R8 companion).
- **No new gates** — the refactor adds no `workflow.gates`; cheval routing semantics (chains, circuit breaker, voice-drop) are preserved.
- **Auth prerequisite** — an OAuth-authenticated `agy` on the cheval host (spike T4.1: `agy models` → exit 0; no API-key flag); document in the headless-mode runbook.
- **Chain ordering** — confirm `gemini-headless` (agy CLI) vs `gemini-api` (HTTP) precedence under each `LOA_HEADLESS_MODE`.

## 6. Scope & Prioritization

- **In scope**: FR-1…FR-7 (Phase 1 foundation refactor + Phase 2 AGV). Sequenced **refactor-first** — AGV lands as a subclass on the new base, not a 6th clone.
- **Out of scope (follow-on)**: Phase 3 — GLM-5.2 via a new OpenRouter HTTP provider (`z-ai/glm-5.2`); GLM-as-council-voice decision. Separate plan.
- **Affordable because**: the `gemini-api` HTTP stopgap (#1091) already covers the Google voice, so #1089 isn't bleeding while the base refactor lands first.

## 7. Risks & Dependencies

| Risk | Sev | Mitigation |
|---|---|---|
| `agy` non-TTY stdout behavior breaks headless parsing | **High → Low** | **retired by spike T4.1**: the `--sandbox --dangerously-skip-permissions` flags + a closed stdin (`stdin=DEVNULL`) → clean plain-text, exit 0, zero ANSI |
| `agy` headless auth not set up on cheval host | Med | document + verify in a smoke run before declaring #1089 closed |
| Refactor blast radius (touches all 5 live adapters) | Med | 38 test files pin behavior; gemini-api stopgap covers the gap during the work |
| Repoint vs new-terminal regret | Low | decided: repoint keeps all aliases; reversible |

> **Dependencies**: `agy` CLI installed + authed; the R8 review doc; the 38 existing headless tests as the safety net.
