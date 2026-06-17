<!-- Scoping doc — observability enhancement. Research/design, not a merge-ready implementation. -->
# Scope: Per-iteration cost telemetry for loa loops

- **Origin:** top research opportunity (§5a / risk R3) from `linear-thinking-nonlinear-costs-loa-research.md`.
- **Type:** observability enhancement (NOT memoization — see non-goals).
- **Status:** SCOPED — ready to feed `/plan` (or a small cycle) when prioritized. No code in this PR.

## Problem (R3)

loa already *sees* cost — `MODELINV` records `cost_micro_usd` / `tokens_input` / `tokens_output` per invocation (`.claude/data/trajectory-schemas/model-events/model-invoke-complete.payload.schema.json`), and `economy.py` rolls it up **per-(skill, model)** (`.claude/adapters/loa_cheval/economy.py:1-3`). But there is **no iteration dimension**: neither MODELINV nor `economy.py` carries a `bridge_iteration` / loop-iteration tag (grep confirmed empty). So loa cannot answer the article's central empirical question for its own loops:

> Is a bridge/audit/run loop's cost **O(depth)** (linear re-spend per iteration) or **sub-linear** (convergence + shared context already working)?

Until this is measured, every cost-optimization opportunity in the research doc (findings-IR, voice pruning, convergence detection) rests on **unvalidated payoff estimates**. This is the prerequisite work.

## Goal / success criteria

A multi-iteration bridge (or audit/E2E/spiral) run produces a cost trace that attributes spend **per loop iteration**, and `cost-report.sh` can show whether per-iteration cost is flat, rising, or falling.

- **AC1** — MODELINV envelope carries an optional `loop_context` (`bridge|audit|e2e|spiral|null`) + `loop_iteration` (int ≥1) when emitted from inside an orchestrator loop; absent/null for one-shot calls (back-compat).
- **AC2** — `economy.py` emits a per-(`loop_context`, `loop_iteration`) roll-up and a **cost-delta-per-iteration** series for a given run/`bridge_id`.
- **AC3** — `cost-report.sh` gains an iteration view: per-iteration cost + Δ, and a one-line verdict ("cost is O(depth)" vs "converging").
- **AC4** — zero behavior change to routing/spend; purely additive observability. Existing MODELINV consumers and `economy.py` roll-ups unaffected when the new fields are absent.

## Design sketch (to be refined in /plan)

1. **Schema** — add `loop_context` (enum+null) and `loop_iteration` (int) to the MODELINV payload schema. Keep them **optional** (not in `required`) so every existing emitter/consumer stays valid (the schema-guard CI gate must stay green).
2. **Writer** — `loa_cheval/audit/modelinv.py` reads the two values from the invocation context (env vars `LOA_LOOP_CONTEXT` / `LOA_LOOP_ITERATION`, mirroring how other context flows to cheval) and stamps them on the envelope.
3. **Producers** — orchestrators that already track an iteration set the env at dispatch: `bridge-orchestrator.sh` (`iteration` var, `is_multi_model_iteration`), `post-pr-orchestrator.sh` (`audit.iteration` / `e2e.iteration`), spiral. One-line export per dispatch site; no logic change.
4. **Aggregator** — `economy.py`: a sibling roll-up keyed on (`loop_context`, `loop_iteration`) + a `cost_delta` between consecutive iterations of the same `bridge_id`/run.
5. **Surfacing** — extend `cost-report.sh` with an `--by-iteration` view.

## Non-goals (explicit)

- **No memoization / decision caching** of verdicts or planner state. The research doc §6 shows caching audit/consensus verdicts would propagate the KF-004 false-clean class (recurrence ≥28). This work only **measures**; it does not change what re-runs.
- **No voice pruning / convergence-detector changes.** Those are downstream, gated on the data this work produces.
- **No new model calls.** Telemetry is derived from envelopes already written.

## Effort / risk

- **Effort:** S–M. Mostly additive: 2 optional schema fields + writer + a few `export` lines in orchestrators + an `economy.py` roll-up + a `cost-report.sh` view.
- **Risk:** LOW. Optional fields preserve back-compat; the main watch-item is keeping the MODELINV schema-guard CI gate green (additive optional props only). Test-first: a fixture `.run/model-invoke.jsonl` with iteration-tagged entries → assert the per-iteration roll-up + delta.

## Process

Enhancement (new observability), not a bug → route via `/plan` (PRD/SDD/sprint) or a small dedicated cycle, NOT `/bug`. Tracked in beads as the entry point.
