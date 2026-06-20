---
status: candidate
mode: ARCH (OSTROM)
authored: 2026-06-19
authored_by: paired /plan session — "support AGV (Antigravity) + GLM-5.2; improve the baseline first; we are architecting this"
feeds: PRD → SDD → sprint-plan (this is the crystallization brief; promote before /implement)
boundary: model routing / adapter architecture. AGV (#1089) references an observed failure; GLM is a feature.
---

# Cheval headless: improve the baseline, then AGV, then GLM

## TL;DR

Three phases, **refactor-first** (the operator's "improve the baseline before adding more"):

```
Phase 1  FOUNDATION   Full R8 sweep — collapse the 5 headless clones onto one base + a declarative table
Phase 2  AGV  (now)   repoint gemini-headless → the `agy` (Antigravity) CLI; closes #1089
Phase 3  GLM  (after) reach hosted GLM-5.2 via a new OpenRouter HTTP provider
```

Split sequencing: Phase 1+2 are one cycle (AGV is the live-down #1089 fix); Phase 3 is a later experiment cycle.

## Grounded context (verified this session)

- **#1089 (OPEN)** — `gemini-headless` CLI is dead (Google retired "Code Assist for individuals" → Antigravity). The Google flatline voice silently drops. PR **#1091** already shipped `gemini-api` (HTTP, `GOOGLE_API_KEY`) as a stopgap — **so the Google voice is NOT fully down; urgency is mitigated**, which is what makes "refactor-first" affordable.
- **#1027 (OPEN)** — the 5 headless adapters (claude/codex/cursor/gemini/grok) are ~75% clones (~448 ln each); the `HeadlessCLIAdapter` base (R8) + declarative registry (R1) refactor was meant to land *before* adding more. It didn't. AGV as a 6th raw clone makes it worse → do the base first.
- **AGV is viable** ([codelab](https://codelabs.developers.google.com/antigravity-cli-hands-on)) — the `agy` CLI has a `-p`/`--print` non-interactive mode; auth is OAuth (device-code over SSH) or API key. **Risk:** documented non-TTY stdout behavior change ([antigravitylab](https://antigravitylab.net/en/articles/integrations/antigravity-cli-agy-headless-non-tty-stdout-ci)) — cheval shells it non-TTY, so the adapter must handle it.
- **GLM premise overturned** — GLM-5.2 is **756B → cloud-only** (`glm-5.2:cloud`); it does not run locally. So "ollama-headless local" is moot. It's a *hosted* model, reachable via OpenRouter HTTP (`z-ai/glm-5.2`, 1M ctx). Cheval is already a router → add a hosted backend, not a local one.

## Decisions (this session)

| # | Decision | Choice |
|---|---|---|
| 1 | Refactor debt (#1027) | **Refactor first** — baseline before adding more |
| 2 | Refactor scope | **Full R8 sweep** — R8 base + R1 declarative table + adjacent headless cleanups (R10 split `base.py`, R11 output-swallow guard) |
| 3 | AGV terminal shape | **Repoint `gemini-headless` → `agy`** — keep the name + all aliases/refs, swap binary (gemini→agy) + auth underneath |
| 4 | GLM access path | **OpenRouter HTTP provider** (`z-ai/glm-5.2`), kind:http — rides the existing HTTP adapter shape, not a headless clone |
| 5 | Sequencing | **AGV now, GLM after** (split by urgency) |
| 6 | GLM voice semantics | **DEFERRED** to Phase 3 planning (experiment-only vs flatline council voice) |

## Phase 1 — Foundation (Full R8 sweep)

The "improve the baseline" the operator asked for; **must land before AGV** so AGV is a thin subclass, not a 6th clone.

- **R8** — `HeadlessCLIAdapter(ProviderAdapter)` template base: shared `complete()` + class-attribute-driven prompt/health/timeout/validate; subclasses keep only `_build_command`/`_parse_output`/`_classify_error` (~120 ln). The 5 existing adapters (claude/codex/cursor/gemini/grok) migrate onto it.
- **R1** — derive the headless registries from ONE declarative table (root cause of the "#966 config-dead" bug); a new adapter becomes a table row + a thin subclass.
- **Adjacent (operator may trim):** R10 (split `base.py`'s 891 ln by consumer group), R11 (structurally guard the output-swallow class).
- **Acceptance:** the 108 existing headless tests pin behavior (green before+after); the 5 adapters collapse onto the base; the registry is one table; net line count drops materially (~1,563 → ~700 in the cluster).
- **Risk:** medium (touches all 5 live adapters). Mitigation: tests pin behavior; gemini-api HTTP stopgap covers the Google voice during the work.

## Phase 2 — AGV (now)

- **Repoint** the `gemini-headless` terminal: swap the shelled binary `gemini -p` → `agy -p/--print`, update auth (OAuth device-code / API key), as a thin subclass on the Phase-1 base. Keep the `gemini-headless` name + aliases so every existing config/ref resolves unchanged. `gemini-api` (#1091) stays as the HTTP fallback.
- **Handle the non-TTY stdout gotcha** explicitly (the documented `agy` CI behavior) — likely the highest-effort part of the adapter.
- **Acceptance:** `gemini-headless` dispatch resolves via `agy` and returns a clean completion non-TTY; the Google flatline voice is restored on a live `agy` auth; circuit breaker no longer trips on `IneligibleTierError`; **#1089 closed**. Tests + a live `agy` smoke run.
- **Prereq (operator):** an authenticated `agy` install on the machine that runs cheval (OAuth once, or an API key).

## Phase 3 — GLM via OpenRouter (after)

- Add **OpenRouter** as a new `kind:http` provider (one `OPENROUTER_API_KEY`); register `z-ai/glm-5.2` (1M ctx). Rides cheval's existing HTTP adapter pattern (`google_adapter`/`openai_adapter` shape) — **no headless clone, no local infra**.
- **Open decision (deferred):** is GLM-5.2 an experiment-only terminal (manual `/flatline-review` etc.) or wired into the default flatline council as an independent z.ai voice? Decide at Phase-3 planning.
- **Acceptance:** GLM-5.2 reachable through cheval for experimentation (a `/flatline-review` or direct invoke lands on `z-ai/glm-5.2`); cost/quaranteed-routing behavior documented.

## Open items / risks

- **AGV non-TTY stdout** — the load-bearing adapter risk; design around it (Phase 2).
- **`agy` auth in headless/CI** — device-code vs API key; the operator's machine must be set up.
- **Repoint vs gemini-api coexistence** — confirm chain order (agy CLI terminal vs gemini-api HTTP fallback) under each headless mode.
- **GLM as council voice** — deferred; a hosted third-party in a gate has cost + reliability implications.
- **Refactor blast radius** — Phase 1 touches all 5 live adapters; the 108 tests are the safety net.

## Loa gate path

This is a **candidate** crystallization brief. Next: promote → PRD (`/plan-and-analyze` reads this) → SDD (`/architect`) → sprint-plan. Phase 1+2 = one cycle; Phase 3 = a later experiment cycle.
