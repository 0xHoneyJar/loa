# ADR-003: The Mechanical Floor — quality enforcement that survives a weaker model

> **Status**: Accepted
> **Released**: v1.196.0 (2026-07-10)
> **Predecessors**: ADR-001 (model-registry consolidation), ADR-002 (multi-model cheval substrate)
> **Sources**: cycles 116–120 (quality-per-token → session-economy → mechanical-floor → follow-ups); the v1.196.0 release-readiness work (Shell Tests burn-down, #1162 installer hardening)

---

## Context

By cycle-116, Loa's quality gates — review, audit, Flatline, Bridgebuilder,
red-team — were overwhelmingly *model-attention* gates: their correctness
depended on a strong model reading a prose instruction and choosing to comply.
Two forces made that fragile:

1. **Token economy pressure.** Operator usage across multiple repos showed the
   cost of running every gate on a top-tier model. The obvious lever — run
   cheaper/weaker models for more of the work — directly threatens gates that
   rely on the model being smart enough to self-police.
2. **Silent gate erosion.** Several gates had degraded to advisory-only or
   were structurally gameable: a review could emit a clean prose verdict while
   its machine signal disagreed; `--check-only` self-heal actually mutated;
   the Shell Tests CI check carried a **50-failure baseline** that had been red
   run-after-run for weeks, so it no longer gave a binary merge signal — a real
   regression would hide inside the noise.

The thesis that emerged: **a gate is only as strong as its weakest permitted
executor.** If the enforcement lives in the model's attention, a cheaper model
weakens it. If the enforcement lives in a script, a schema, a structural check,
or a budget floor, it holds regardless of who is driving.

## Decision

Move quality enforcement, wherever possible, from model attention into
**mechanical floors** — deterministic artifacts that fail closed:

1. **Machine-parseable verdicts.** Review/audit feedback ends with a
   `LOA-VERDICT` trailer; `verdict-derive.sh` enforces prose/trailer
   consistency under a **one-way rule** — findings can force `CHANGES_REQUIRED`,
   but zero counts can never *force* approval. A `status: clean | APPROVED` is
   impossible when verdict quality is degraded (ADR-002 voice-drop envelope).
2. **Validators as MUST gates, not advice.** `validate-artifact.sh` (PRD/SDD/
   sprint/bug-triage/translation), `validate-ac-verification.sh`, and the
   citation-**resolution** anti-fabrication gate (every `file:Lnn` cite must
   resolve to a real file+line) run as blocking steps, not suggestions.
3. **Structural checks over review prose.** `check-installer-safety.sh` (this
   release), the model-registry drift + REPO-MAP checksums, the no-direct-fetch
   scanner, the block-destructive carrier-scrub — each converts a "the reviewer
   should notice X" into "CI fails on X."
4. **Tiered dispatch with an enforced floor.** Cheaper models (`loa-scout` on
   Haiku, `claude-sonnet-5` executor tier) may do evidence-gathering and
   mechanical work, but verdict-bearing roles NEVER run on a pinned cheaper
   model (`validate-skill-capabilities.sh` rejects `model:`/`agent:` on
   `role: review|audit` skills), and orchestrators carry token/USD budgets.
5. **Empirical, pre-registered tier decisions.** Before downtiering a stage,
   run an A/B against a gold set under a decision rule fixed *in advance*
   (cycle-120 flatline-scorer A/B: the executor won the decision axis but the
   flip was held because a pre-registered calibration clause failed — the
   discipline is the point).

The release-readiness work is the thesis applied to itself: the chronic Shell
Tests baseline was burned 50 → ~0 so the merge gate is binary again, and the
#1162 P1 installer risks were converted from an audit *document* into an
enforcing checker + fixtures + patched scripts.

## Alternatives considered

- **Keep instruction-only gates, mandate a strong model everywhere.** Rejected:
  token cost is the operator's stated constraint, and "always use the big
  model" is exactly the discipline that erodes first under pressure.
- **Advisory checks + human review.** Rejected for autonomous flows: an
  advisory check that only warns is indistinguishable from a passing check to
  an autonomous agent (the Shell Tests baseline is the cautionary tale).
- **Fix the test baseline by deleting/loosening the failing tests.** Rejected:
  several "failing" tests were catching real bugs (release-notes pipefail
  crash, installer boundary bypass, self-heal check-only mutation). The floor
  is only credible if it's honest.

## Consequences

- **Positive:** merges gate themselves again; cheaper models are safe for the
  mechanical majority of work; every review/audit verdict is machine-checkable;
  destructive-action and network-egress classes are structurally fenced.
- **Cost:** more CI surface and more schema/checksum maintenance (each
  taxonomy growth now trips a deliberate pin — e.g. the `error_class` and
  `calling_primitive` catch-ups in this release were pin bumps, by design).
- **Residual:** mechanical floors catch *classes*, not novel judgment. Open
  work is tracked as a verified work-now queue (see the 2026-07-10 triage);
  the floors reduce how often novel judgment is even needed.

## Outcome

v1.196.0 ships with a green Shell Tests gate, the installer P1 closed with
enforcement, and the tiered-dispatch floor documented and linted. The arc's
methodology is preserved in
`grimoires/loa/reports/mechanical-floor-methodology-2026-07-07.md`.
