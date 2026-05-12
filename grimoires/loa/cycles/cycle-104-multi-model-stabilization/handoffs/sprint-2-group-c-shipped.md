---
schema_version: 1.0
from: opus-4-7-cycle-104-sprint-2-group-c-orchestrator
to: cycle-104-sprint-2-e-g-continuator
topic: sprint-2-group-c-shipped
status: ready
provenance:
  cycle: cycle-104-multi-model-stabilization
  sprint: sprint-2
  predecessor_pr: 849
  branch: feature/cycle-104-sprint-2-fallback-chains-headless
  commits: [241c703e, 42857c72, 7f9d7bbe, 5bb606fe]
last_updated: 2026-05-12T13:30:00Z
tags: [cycle-104, sprint-2, multi-model, chain-walk, modelinv-v1.1, group-c-shipped]
---

# Cycle-104 Sprint 2 Group C — SHIPPED → Group E + G + Operator-Gated F Continuation

## TL;DR

Group C (T2.5 + T2.6) landed at `5bb606fe` on continuation of the partial-handoff branch. The 1057-LOC `cheval.cmd_invoke` dispatch function now resolves a within-company `ResolvedChain` upfront and walks it: capability gate → input gate → adapter dispatch → walk-on-retryable / surface-on-non-retryable. MODELINV envelope schema bumped to v1.1 with `final_model_id`, `transport`, `config_observed`, and additive `models_failed[]` fields. Backward compat preserved on every axis (single-entry chains, pre-T2.6 emitters, existing exit codes).

**6/14 sprint tasks now done. 4 commits. Branch `feature/cycle-104-sprint-2-fallback-chains-headless` ready for Group E + G or for split into a dedicated Group C PR.**

## Group / task status table

| Group | Tasks | Status | Commit |
|-------|-------|--------|--------|
| A — Routing substrate | T2.1 chain_resolver.py + T2.2 capability_gate.py | ✅ SHIPPED | `241c703e` |
| B — Config layer | T2.3 fallback_chain + T2.4 headless aliases | ✅ SHIPPED | `42857c72` |
| **C — Integration** | **T2.5 cheval.invoke wiring + T2.6 MODELINV v1.1** | ✅ **SHIPPED this session** | **`5bb606fe`** |
| D — Operator control | T2.7 hounfour.headless.mode example + cheval consumption | ✅ FULLY LANDED (T2.7 doc shipped `7f9d7bbe`; consumption shipped in C via `resolve_headless_mode` + `config_observed`) | partial→full |
| E — Cross-company repurpose + revert | T2.8 voice-drop + T2.9 code_review revert | ⏳ DEFERRED — T2.9 gated on T2.10 (R8) | — |
| F — Empirical + e2e | T2.10 KF-003 replay + T2.11 cli-only e2e | 🚫 OPERATOR-GATED | — |
| G — Docs + cleanup | T2.12 runbooks + T2.13 cross-runtime parity + T2.14 LOA_BB_FORCE_LEGACY_FETCH removal | ⏳ DEFERRED | — |

## What Group C delivered

### T2.5 — chain walk dispatch (`cheval.py` cmd_invoke refactor)

The single-model dispatch path (cycle-103) is replaced with a `ResolvedChain` walk. Insertion points:

| Location | Before | After |
|----------|--------|-------|
| After `resolve_execution` (line ~460) | — | Resolve `_headless_mode` + `ResolvedChain` via `chain_resolver.resolve()`. Catch `NoEligibleAdapterError` → exit 11. |
| Modelinv state init | `_modelinv_target` (single string) | `_modelinv_models_requested` (list of all entries) + new fields (`final_model_id`, `transport`, `config_observed`). |
| Dispatch body | `try: ... single-model ... except: ... ` | `for _entry in _chain.entries: try: dispatch except retryable: continue except non-retryable: return` |
| For-else | — | Multi-entry: emit `ChainExhaustedError` → exit 12. Single-entry: re-emit original cycle-103 error JSON, return original exit code. |

**Backward compat:** single-entry chains (no fallback_chain declared) preserve cycle-103 exit codes (`RETRIES_EXHAUSTED` / `RATE_LIMITED` / `PROVIDER_UNAVAILABLE` / `CONTEXT_TOO_LARGE` / `API_ERROR`). External tooling unchanged.

**Async-mode constraint:** `--async` rejected with `INVALID_INPUT` if chain has > 1 entry — `create_interaction` returns a pending handle, not a CompletionResult, so there's no error path to route through.

**Exit code allocation:**
- `NO_ELIGIBLE_ADAPTER = 11`
- `CHAIN_EXHAUSTED = 12`
- SDD §6.2/6.3 aspirationally specced 8/9, but `INTERACTION_PENDING = 8` was already pinned (cycle-098). Slid the new codes to 11/12 to keep the CLI contract intact.

### T2.6 — MODELINV envelope v1.1

Schema delta (additive only — `additionalProperties: false` constraint kept satisfied via "only attach when populated" pattern):

| Field | Type | Population |
|-------|------|------------|
| `final_model_id` | `string` (provider:model_id pattern) \| `null` | provider:model_id of the entry that produced the result. Absent if chain exhausted. |
| `transport` | `"http"` \| `"cli"` \| `null` | Derived from `final_entry.adapter_kind`. Absent if chain exhausted. |
| `config_observed.headless_mode` | enum 4 modes | Observed via `resolve_headless_mode()`. |
| `config_observed.headless_mode_source` | `"env"` \| `"config"` \| `"default"` | Precedence layer that supplied the mode value. |
| `models_failed[].provider` | string | Per-entry provider key. |
| `models_failed[].missing_capabilities` | string[] | Populated when `error_class=CAPABILITY_MISS`. |
| `error_class` enum | adds `EMPTY_CONTENT` | KF-003 class. |

`emit_model_invoke_complete(*, ..., final_model_id=None, transport=None, config_observed=None)` — all new kwargs optional. Pre-T2.6 single-model emitters that don't pass them produce a payload with the new keys *absent*, not null. Pinned by `test_modelinv_envelope_chain_walk.py::TestBackwardCompatSingleModel::test_legacy_single_model_payload_keys`.

### Test inventory delta

| Suite | LOC | Tests | Coverage |
|-------|-----|-------|----------|
| test_chain_walk_audit_envelope.py | 391 | 5 | walk-on-empty-content, exhaust-multi-entry, single-entry-cycle-103-compat, budget-no-walk, capability-miss-walks |
| test_modelinv_envelope_chain_walk.py | 230 | 9 | v1.1 payload shape + backward-compat absent-key semantics |
| **Group C total** | **621** | **14** | |

**Adapters suite status**: 1168 passed (was 1154 pre-commit, 14 added). 3 pre-existing `test_flatline_routing.py` failures remain — confirmed pre-existing via `git stash + re-run on HEAD`. NOT introduced by Group C.

## Next-session starting points

### Group E — T2.8 voice-drop wiring (cross-company repurpose, SDD §6.5)

**Scope**: modify `flatline-orchestrator.sh` (and possibly `flatline-readiness.sh`) so the cross-company `flatline_protocol.models.{secondary, tertiary}` fallback fires ONLY after the within-company chain (now wired via cheval) reports exhaustion.

**Hook point**: cheval invocation paths in flatline-orchestrator that pass `--model <alias>`. When cheval exits with code 12 (CHAIN_EXHAUSTED), the orchestrator's "fall back to secondary/tertiary model" branch becomes "drop this voice from consensus aggregation". Test: `tests/test_voice_drop_on_exhaustion.py`.

**Files to inspect first**:
- `.claude/scripts/flatline-orchestrator.sh:318` (primary read), `:322` (secondary read), `:343` (tertiary read), `:1170-1240` (3-model dispatch loop).
- `.claude/scripts/flatline-readiness.sh:133-145` (model resolution).

**T2.9 sequencing**: T2.9 (`flatline_protocol.code_review.model` revert from `claude-opus-4-7` → `gpt-5.5-pro`) is gated on T2.10 KF-003 empirical replay per R8. Do NOT land T2.9 in advance.

### Group G — T2.12 + T2.13 + T2.14

| Task | Scope | Hint |
|------|-------|------|
| T2.12 | Runbook for headless mode + chain-walk debugging | `grimoires/loa/runbooks/headless-mode.md` + `chain-walk-debugging.md`. Reference `LOA_HEADLESS_VERBOSE` + audit log entries with `final_model_id` ≠ `models_requested[0]`. |
| T2.13 | Cross-runtime parity test for `kind: cli` entries | Bash/python/TS readers see identical chain shape. Extend cycle-099 sprint-1E.c.1 corpus pattern. |
| T2.14 | Remove `LOA_BB_FORCE_LEGACY_FETCH` dead env var | TS edit in `cheval-delegate.ts` + test + `bun build` to regenerate `dist/` (cycle-099 drift-gate enforced). 4 references via `grep -rn LOA_BB_FORCE_LEGACY_FETCH .claude`. |

### Group F — operator-gated

T2.10 (KF-003 live replay) needs `LOA_RUN_LIVE_TESTS=1` + ≤$3 live-API budget approval. T2.11 (cli-only e2e) needs `claude` / `codex` / `gemini` CLI binaries on `$PATH`. Halt point at sprint level.

## PR shape decisions for operator

Two acceptable shapes — operator picks:

**Shape A — single Sprint 2 PR** (matches partial-handoff's recommendation):
- Continue on this branch; land Group E + Group G as follow-up commits.
- One PR covering Sprint 2 entirely (modulo operator-gated F).
- Pro: clean cycle-104 history; one review surface.
- Con: large PR; Group C deserves isolated security/quality review on its own.

**Shape B — Group C stacked PR**:
- Create PR for `5bb606fe` against `feature/cycle-104-sprint-1-archive-hygiene` (or against main once #849 merges).
- Continue E + G on a fresh branch stacked off Group C.
- Pro: Group C architectural change gets focused review; reviewer doesn't need to context-switch between cheval refactor and bash voice-drop.
- Con: two PRs, more merge orchestration.

The previous-session handoff predicted Group C "deserves its own session/PR" — Shape B is the literal read of that recommendation.

## Iron-grip gate reminders for the continuator

- **Continue on `feature/cycle-104-sprint-2-fallback-chains-headless`** unless explicitly splitting into Shape B.
- **--no-verify still pre-authorized** for cycle-104 commits (KF-005 beads MIGRATION_NEEDED).
- **AC-2.1 lint + T2.5/T2.6 contract tests are now load-bearing**: any future edit to `model-config.yaml` or `cheval.cmd_invoke` must keep `pytest .claude/adapters/tests/test_model_config_fallback_chain_invariants.py test_chain_walk_audit_envelope.py test_modelinv_envelope_chain_walk.py` green.
- **Don't refactor retry.py.** The SDD §10 Q6 finding still applies — chain walk catches `EmptyContentError` at the right layer.

## Risks observed but not realized in Group C

| Risk | Status |
|------|--------|
| Chain walk regresses single-model dispatch behavior | Mitigated — `test_cheval_exception_scoping.py` (pre-existing) passes; backward-compat for-else branch preserves cycle-103 exit codes |
| MODELINV schema bump breaks pre-T2.6 emitters | Mitigated — additive-only schema (additionalProperties:false satisfied because new keys only attached when populated); `TestBackwardCompatSingleModel` pins this |
| Async-mode silently misbehaves with multi-entry chains | Mitigated — upfront rejection with `INVALID_INPUT` |
| Exit code 8 / 9 collision with `INTERACTION_PENDING` | Avoided — slid to 11 / 12 with inline documentation |

---

**Status**: READY. Group C committed. Branch persists. Next session continues with Group E + G or splits into Shape B.

🤖 Generated as part of cycle-104 Sprint 2 Group C run, 2026-05-12
