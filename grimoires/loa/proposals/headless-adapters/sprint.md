# Sprint Plan — Cheval Headless: Baseline Refactor + AGV

> Standalone plan (NOT registered in the Sprint Ledger). For `prd.md` + `sdd.md`
> in this dir. Sequenced refactor-first. The 38 headless test files
> (`.claude/adapters/tests/test_*headless*`) are the behavior pin throughout.
> Prereq for Sprint 4: an authenticated `agy` CLI on the cheval host.

## Sequencing

```
S1 base+migrate (R8)  →  S2 declarative table (R1)  →  S3 R10/R11 (trimmable)  →  S4 agy spike+repoint (#1089)
                                                                                    └ S4.1 spike GATES S4.2–4.6
```
S1–S3 = Phase 1 (refactor, independent of AGV). S4 = Phase 2 (AGV). S4.1 can be pulled forward to de-risk early (it only gates S4, not S1–S3).

---

## Sprint 1 — HeadlessCLIAdapter base + migrate (R8)

**Goal:** collapse the 5 clones (2,766 ln) onto one intermediate base; behavior unchanged.

| Task | Acceptance criteria |
|---|---|
| **T1.1** Add `HeadlessCLIAdapter(ProviderAdapter)`: final `complete()` template + `_build_prompt`/`validate_config`/`health_check`/`_compute_timeout`/effort/4 error-raises/`_cli_binary`; abstract hooks `_build_command`/`_parse_output`/`_raise_for_error`; class attrs (`_BIN_DEFAULT`/`_BIN_ENV`/`_CONNECT_FLOOR`/`_READ_FLOOR`/`_ALLOWED_EFFORTS`/`_PROMPT_TRANSPORT`) | base class unit-tested in isolation (a fake subclass exercises the template); no behavior asserted yet |
| **T1.2** Migrate `ClaudeHeadlessAdapter` onto the base (template source) | `test_claude_headless_adapter.py` green **unchanged**; subclass ≤ ~150 ln |
| **T1.3** Migrate codex / cursor / gemini / grok one-at-a-time | each adapter's test file green **unchanged** after its migration; per-adapter quirks (cursor envelope-preamble, codex JSONL, grok prompt-file) preserved via hooks |
| **T1.4** Collapse the 5 clone test suites into one parametrized suite (inject `adapter_cls` + 3 hooks + fixtures); keep per-adapter LIVE tests | parametrized suite covers all 5; total coverage ≥ pre-refactor; live tests still gated by `LOA_*_HEADLESS_LIVE=1` |

**Verification:** all 38 headless test files green; cluster line count drops materially (measure vs 2,766 baseline).
**Risk:** medium (touches all 5 live adapters) — mitigated by one-at-a-time migration + the test pin.

---

## Sprint 2 — Declarative registry table (R1)

**Goal:** one table is the single source for headless terminals (kills the "#966 config-dead" drift).

| Task | Acceptance criteria |
|---|---|
| **T2.1** Add `providers/headless_registry.py` with `HEADLESS_TERMINALS` (type → `HeadlessSpec{cls, bin_default, bin_env, prompt_transport, …}`) | table defined for all 5 terminals |
| **T2.2** Derive `_ADAPTER_REGISTRY` + `cli_adapter_types()` from the table (remove the hand-maintained dict) | `get_adapter()` resolves all 5 from the table; no second list to drift |
| **T2.3** Reconcile the terminal facts the table now owns vs `model-config.yaml` (no duplicate source of truth) | a test asserts table ↔ model-config consistency for the 5 terminals |

**Verification:** registry/factory tests green; "add a terminal = one row" proven by a throwaway fixture row.

---

## Sprint 3 — Adjacent cleanups (R10 + R11) — *operator-trimmable*

**Goal:** improve the base we built on. Drop this sprint if scope must shrink.

| Task | Acceptance criteria |
|---|---|
| **T3.1** Split `base.py` (891 ln) by consumer group (subprocess-lib / context-lib / config-lib) | imports updated; full adapter suite green; no behavior change |
| **T3.2** Structurally guard the output-swallow class (R11 — highest correctness payoff) | a test reproduces a swallowed-output case and the guard catches it |

**Verification:** full cheval adapter suite green.

---

## Sprint 4 — agy spike + AGV repoint (Phase 2 — closes #1089)

**Goal:** the `gemini-headless` terminal dispatches via `agy`; Google voice restored.

| Task | Acceptance criteria |
|---|---|
| **T4.1 SPIKE (GATE)** Resolve against the real `agy` on the host: (a) invocation `-p`/`--print` + prompt transport (stdin/`--prompt-file`/argv), (b) output JSON shape, (c) auth flow + cred env vars, (d) the non-TTY stdout behavior + workaround | a one-page spike note answering (a)–(d); **gates T4.2–T4.6** |
| **T4.2** `AgyHeadlessAdapter(HeadlessCLIAdapter)` — `_build_command` = `agy -p <prompt> --model <label> --sandbox --dangerously-skip-permissions` with stdin closed (`</dev/null`), `_PROMPT_TRANSPORT=argv` (spike: agy is argv like gemini — ARG_MAX cliff PERSISTS, NOT fixed); `_parse_output` = **plain-text passthrough + `estimate_tokens()`** (clone grok's `_build_result`, NOT a JSON parser); `_raise_for_error` (agy markers), bin/auth class-attrs | unit tests with mocked `agy` green (command incl. the sandbox pairing, plain-text parse, error paths) |
| **T4.3** FR-6 non-TTY handling — `_build_command` emits the spike's pairing `--sandbox --dangerously-skip-permissions` and closes stdin (`</dev/null`) so agy doesn't hang on a tool-permission prompt; parse the clean plain-text stdout | a test feeding non-TTY plain-text stdout parses to a clean `CompletionResult` |
| **T4.4** Repoint registry row `gemini-headless` → `AgyHeadlessAdapter`; update `model-config.yaml` `extra.cli_model` → an agy model **label** (human-readable, e.g. `"Gemini 3.1 Pro (High)"` — spike: agy takes the label from `agy models`, NOT an API id); **keep the `gemini-headless` type string + aliases** (`:752`) | `get_adapter("gemini-headless")` returns the agy adapter; existing aliases/refs resolve unchanged |
| **T4.5** Update `_HEADLESS_STRIPPED_AUTH_VARS` (base.py:511) for agy creds; document the agy auth prereq in `grimoires/loa/runbooks/headless-mode.md` | env-strip test covers agy vars; runbook updated |
| **T4.6** Live `agy` smoke (gated by `LOA_AGY_HEADLESS_LIVE=1`) — real dispatch returns a clean completion; Flatline shows the Google voice live | smoke passes on the host; **#1089 closeable** |

**Verification:** gemini-headless tests adapted to agy green; live smoke passes; circuit breaker no longer trips on `IneligibleTierError`.
**Risk:** T4.3 (non-TTY) was **High** — the spike (T4.1) **retired it to Low** (`--sandbox --dangerously-skip-permissions </dev/null`; gated PASS). ARG_MAX on huge diffs is unchanged from gemini (agy is argv; no `--prompt-file`) — `gemini-api` HTTP covers oversized diffs.

---

## Out of scope (follow-on plan)

Phase 3 — GLM-5.2 via a new OpenRouter `kind:http` provider (`z-ai/glm-5.2`). NOT a headless clone; rides the existing HTTP adapter path. Separate PRD/SDD when 114 ships.

## Execution note

This plan is standalone (no ledger). To execute under Loa gates, it must be promoted to a registered cycle first (when cycle-114 ships) so `/run` / `/implement` can track sprints. Until then it's a design reference. T4.1 (spike) is safe to run anytime to de-risk AGV.
