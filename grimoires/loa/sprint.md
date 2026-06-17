# Sprint Plan: Cycle-114 — Sprint S4 (Cost Telemetry & Tiering)

> **Cycle**: cycle-114-harness-modernization-opus-4.8
> **Sprint**: sprint-4 (local) / sprint-225 (global)
> **FRs**: FR-11, FR-12, FR-13, FR-14 (PRD §4b, SDD §2b)
> **Theme**: Cost telemetry & tiering — observability + cost-routing for the
> cheval substrate. Continuation of S3 (FR-8 effort-in-MODELINV).
> **Scope discipline**: observability/routing ONLY. NO memoization, NO
> `cache_control` writes (that is bd-w7bh), NO change to *what* re-runs.
> All new fields optional (NFR-2). Test-first (NFR-3).

## Tasks (ordered smallest → largest; each test-first)

### T4.1 — FR-13: Cheap-tier binding
- **Files**: `.claude/defaults/model-config.yaml` (+ regenerate derived maps if the binding feeds them).
- **Do**: bind `flatline-scorer` (currently `model: reviewer`) + any triage/classification workload to the `cheap`/`tiny` (Haiku-class) tier. Leave adversarial review voice bindings unchanged.
- **Test**: bats — assert the cheap subtask binds to tiny/cheap; assert an adversarial voice tier is unchanged; drift gate green.
- **AC**: `flatline-scorer` no longer on `reviewer`; CRITICAL/BLOCKER voice dispatch unchanged.

### T4.2 — FR-14: Wire budget DOWNGRADE
- **Files**: `.claude/adapters/loa_cheval/providers/retry.py` (+ `routing/chains.py` walker import).
- **Do**: on DOWNGRADE disposition, invoke `walk_downgrade_chain` to resolve + continue with a cheaper model; fail-open if no target.
- **Test**: pytest — DOWNGRADE invokes the walker (was a no-op); empty downgrade chain → fail-open (no error, log + proceed).
- **AC**: `retry.py` DOWNGRADE no longer logs "continuing with current model" as a dead end.

### T4.3 — FR-12: Cache-token telemetry
- **Files**: `loa_cheval/types.py` (`Usage`), `providers/anthropic_streaming.py`, `economy.py`.
- **Do**: add `cache_read_input_tokens` + `cache_creation_input_tokens` to `Usage`; parse them in the Anthropic streaming usage; roll them up in `economy.py`. Surfacing only — NO `cache_control` writes.
- **Test**: pytest — cache fields parsed from a usage fixture; absent → 0/None; economy roll-up includes them.
- **AC**: cache tokens visible end-to-end; back-compat when absent.

### T4.4 — FR-11: Per-iteration cost telemetry
- **Files**: schema `model-invoke-complete.payload.schema.json`, `audit/modelinv.py`, `bridge-orchestrator.sh` + `post-pr-orchestrator.sh` (env exports), `economy.py`, `cost-report.sh`.
- **Do**: optional `loop_context`+`loop_iteration` on MODELINV (additive optional props); writer reads `LOA_LOOP_CONTEXT`/`LOA_LOOP_ITERATION`; orchestrators export them; economy per-(context,iteration) roll-up + cost-delta; `cost-report.sh --by-iteration`.
- **Test**: pytest + bats — iteration-tagged MODELINV fixture → per-iteration roll-up + Δ; absent fields → unchanged; schema-guard green.
- **AC**: an operator can see per-iteration cost + Δ for a bridge/audit run.

## Verification
- `bash -n` on every edited shell script; pytest for cheval; bats for new/updated tests.
- Schema-guard CI gate stays green (additive optional props only).
- Drift gate green (any regenerated model maps in sync).
- Review (`/review-sprint`) + Audit (`/audit-sprint`) before merge.

> **Sources**: PRD §4b (FR-11…FR-14), SDD §2b; `cost-telemetry-scope.md`;
> `anthropic-advances-oracle-2026-06-17.md` §3a/§5.

## Implementation findings (pre-code grounding, 2026-06-17)

Grounding the tasks against the actual code surfaced two refinements the
oracle's surface grep did not capture — both are quality-vs-cost traps the
linear-nonlinear research §6 explicitly warns about:

- **FR-14 is MEDIUM, not S (architectural).** `retry.py`'s DOWNGRADE handler
  (`providers/retry.py:366`) operates on `(adapter, request)` and has no access
  to `ResolvedModel` / `AgentBinding` / `config` — the required inputs of
  `walk_downgrade_chain(original, agent, config)` (`routing/chains.py:140`).
  Resolution happens upstream in `cheval.py`. Correct fix: handle DOWNGRADE at
  the resolution/dispatch layer (or thread a downgrade-callback into the retry
  loop) — NOT a one-liner at `retry.py:367`. Re-scope before implementing.
- **FR-13 is a quality-vs-cost decision, not a blind retarget.**
  `flatline-scorer` (`model: reviewer` = `openai:gpt-5.5`, model-config.yaml:858)
  gates FLATLINE convergence (the bridge loop's pruning). Downgrading the scorer
  risks mis-firing the gate. Prefer `cheap` (Sonnet 4.6) over `tiny` (Haiku) and
  validate scoring parity empirically before committing. Pure-mechanical triage
  (not the convergence scorer) is the safer first Haiku binding.

**Recommended implementation order (revised):** FR-12 (cache-token telemetry —
pure additive, zero quality/behavior risk) → FR-11 (per-iteration telemetry —
additive, the measurement prerequisite) → FR-13 (tiering, with the cheap-vs-tiny
decision + parity check) → FR-14 (re-scoped to the resolution layer). The two
telemetry items are unambiguously safe; the two cost-routing items carry
quality tradeoffs that warrant care + (ideally) the very per-iteration data
FR-11/FR-12 produce.
