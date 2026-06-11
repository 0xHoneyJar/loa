# ADR: Native `Workflow` Tool Adoption (cycle-114 FR-10)

> **Status**: Proposed (decision-record only) — **NO orchestration code lands this cycle**
> **Cycle**: cycle-114-harness-modernization-opus-4.8
> **Source**: `/oracle` audit `grimoires/pub/research/anthropic-updates-2026-05-31.md` (Recommended Action #9)
> **Decision owner**: @janitooor

---

## 0. Scope guard

This document is a **decision record**. Cycle-114 ships it as the entirety of
audit action #9. It deliberately writes **no orchestration-migration code**, adds
no dependency on the native `Workflow` tool, and changes no dispatch path. Any
implementation requires a separate, explicitly-scoped cycle that satisfies the
go/no-go criteria in §5.

## 1. Context

Claude Code 2.1.154 shipped **dynamic workflows** — a native `Workflow` tool that
orchestrates tens-to-hundreds of Claude subagents from a deterministic JS script
(`agent()` / `parallel()` / `pipeline()`), with per-agent worktree isolation,
structured-output schemas, token budgets, and resume-from-runId. `/workflows`
shows live runs. "ultracode" pairs `xhigh` effort with standing permission to
launch these workflows.

Loa today runs a bespoke orchestration substrate in bash/Python/TS: the spiral
orchestrator + harness, `/run` run-mode, `/run-bridge`, the Flatline orchestrator,
the Bridgebuilder TS tool, and the cheval multi-vendor router. The `/oracle`
audit estimated ~80% of the *dispatch* mechanics overlap what `Workflow` now does
natively — but flagged that Loa's *differentiated value* is orthogonal to dispatch.

## 2. What native `Workflow` does well (candidate fits)

The native tool is a strong fit where the work is **Claude-only fan-out with a
deterministic shape**:

- **Parallel sprint-task implementation** — independent tasks in a sprint fanned
  out via `parallel()`, each in its own worktree.
- **Parallel per-file audit / review** — `pipeline()` over changed files: review
  → adversarially-verify, with each file advancing independently.
- **Spiral / run-bridge iteration loops** — the loop-until-converged shape maps
  cleanly onto a `Workflow` loop with `resume-from-runId`, replacing hand-rolled
  bash state machines + `claude -p` subprocess management.

Benefits: deterministic ordering, built-in worktree isolation, resume, token
budgets, and far less bespoke subprocess/state code to maintain.

## 3. What Loa must keep bespoke (non-fits)

Native `Workflow` orchestrates **Claude subagents only**. Loa's load-bearing,
non-replaceable capabilities are:

- **Cross-vendor adversarial consensus** — Flatline votes Opus + GPT + Gemini.
  `Workflow` cannot dispatch GPT/Gemini; this requires the cheval router's
  chain-walk + voice-drop.
- **Quality-gate convergence** — implement → review → audit → flatline with a
  circuit breaker is *judgment + convergence detection*, not just fan-out.
- **Audit envelopes** — MODELINV / trajectory / hash-chained cycle records are a
  forensic substrate native workflows do not provide.
- **Cost-per-clean-output economy** (now effort-aware after FR-8) — keyed to the
  cheval invoke path.

## 4. Proposed scoped pilot (if approved later)

A **single, reversible** pilot — not a migration:

- **Target**: one read-only, Claude-only stage — *parallel `/audit-sprint`
  per-file review*. It has no cross-vendor requirement and no write side-effects.
- **Shape**: `pipeline(changedFiles, review, adversariallyVerify)` returning
  structured findings; Loa's existing audit gate consumes the merged findings and
  still renders the verdict.
- **Isolation**: the pilot wraps a *new* opt-in path behind a config flag
  (`native_workflow.audit_fanout.enabled: false` by default); the bespoke audit
  path remains the default and the fallback.
- **Measurement**: compare wall-clock, token cost, and finding-parity against the
  bespoke path on the same PRs across N runs before considering wider adoption.

## 5. Decision criteria (go / no-go)

Proceed to the pilot cycle ONLY if all hold:

1. **Parity**: native-fanout audit findings match the bespoke path's
   HIGH/CRITICAL set on a benchmark PR set (no missed blockers).
2. **Cost**: measured token cost ≤ the bespoke path (or a quantified,
   operator-accepted premium for the wall-clock gain).
3. **Reversibility**: the flag-off path is byte-identical to today.
4. **No gate erosion**: the verdict, circuit breaker, and audit envelopes remain
   owned by Loa — `Workflow` is the *dispatch engine*, never the *judge*.

If any criterion fails, **do not adopt**; the bespoke substrate stays.

## 6. Decision

**Record the analysis; defer implementation.** Cycle-114 closes audit action #9
with this ADR. Native `Workflow` is a promising dispatch engine for Claude-only
fan-out, but adoption is gated on a measured, reversible pilot in a future cycle
under the §5 criteria. Loa's quality gates and cross-vendor consensus remain
bespoke regardless.

> **Provenance**: `/oracle` audit 2026-05-31 (action #9); operator scope decision
> 2026-06-01 ("carve #9 out to an ADR"); cross-vendor / keep-bespoke analysis from
> the audit's orchestration-overlap matrix.
