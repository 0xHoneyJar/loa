# 01 — Vision and Tenets

> Status: ACCEPTED FOR IMPLEMENTATION by
> [`Decision 0003`](../decisions/0003-architecture-build-kit-implementation.md),
> with distribution mechanics narrowed by
> [`Decision 0004`](../decisions/0004-core-adapter-and-bundle-boundary.md).
> Nothing here amends accepted doctrine; where this document restates doctrine
> it cites it.

## 1. The product goal

The goal was fixed by Decision 0001 and is restated here as the north star:

> A person should be able to download loa-aleph, drop in their own research,
> and get a finished document out — a PRD, an SSD, a product-doctrine, an
> MVP-wedge selection — in either of two modes: **agent mode** (an agent
> executes an immutable Aleph Core bundle through a sanctioned host adapter) or
> **manual mode** (a person follows the same instructions by hand, with no
> agent, and reaches the same result).

The thing being built is therefore not an app and not a service. It is a
**method, packaged as a repository**: doctrine that constrains, contracts that
shape artifacts, instructions that execute, checks that verify, and fixtures
that prove. The agentic research method is what you get when a frontier agent
runs that method at full fidelity; manual mode is what you get when a human
runs it at reconstructable fidelity. Both are first-class.

## 2. Why this is worth building

Everyone doing serious work with LLMs now accumulates the same liability: a
sprawl of conversations, deep-research dumps, design notes, and half-decisions
whose value decays because nothing downstream can trust it. The naive fix — ask
a model to "summarize everything" — produces exactly the artifact Aleph's
doctrine forbids: a coherent-sounding summary of summaries, with silent
discards, duplicate conviction laundered as corroboration, contradictions
dissolved by smooth prose, and citations that decorate rather than support.

The 2026 research record backs the founding intuition (details and sources in
[`11-research-grounding.md`](11-research-grounding.md)):

- Generation cost keeps falling faster than verification cost; artifacts that
  *expose* their verification burden are worth more than artifacts that hide it.
- Citation fidelity and actual evidential influence are separable properties —
  a source can be cited cleanly without having shaped the conclusion.
- Decompose-then-verify (atomic claims checked independently against evidence)
  is the established backbone of long-form factuality work.
- Frontier agents are now dependable at exactly the shape of work this method
  requires: long-horizon multi-stage execution, parallel subagent fan-out,
  file-based memory, and self-verification against an explicit specification.

Aleph's bet: the durable moat is not a smarter summarizer, it is a **trustable
compression trail**. The Précis is trusted because it is inspectable, not
because it sounds coherent.

## 3. Naming

For internal use, this plan calls the whole thing **the Aleph Method**:

```
the Aleph Method = distillation (corpus → neutral Précis)
                 + projection (Précis → committed documents)
                 + the verification stack that makes both trustable
                 + the two runners (agent mode, manual mode) that execute it
```

## 4. The twelve tenets

Every design decision in this plan traces to one or more of these. The first
seven restate accepted doctrine; the last five are proposed extensions that
give the doctrine an executable shape.

**T1 — The procedure is the product.** The repo ships instructions plus checks,
not a black box. If a step cannot be written down precisely enough for a human
to follow it, it is not ready for an agent to run it either.
(Doctrine: PR #16 front-door framing; the wedge's manual-first precedent.)

**T2 — File-first, ledger-first.** Every stage consumes files and emits files.
No stage's output lives only in a model's context or a process's memory. The
run directory is the single source of truth; PRs are the checkpoints.
(Doctrine: `README.md` "File-first, not endpoint"; extension: the run
directory in [`02-system-architecture.md`](02-system-architecture.md).)

**T3 — Nothing load-bearing vanishes silently.** Once a source unit is elevated
to a candidate claim it must receive one of the seven dispositions. Grouping
compresses presentation, never inventory.
(Doctrine: the completeness contract, `docs/precis-wedge.md`.)

**T4 — Neutrality lives at the Précis.** The Précis never decides what it
becomes. Projection is a separate downstream stage that consumes without
mutating. (Doctrine: ADR 0001.)

**T5 — Two arms, one pipeline, per-cluster weighting.** Adversarial
stress-testing and convergent referent-reconciliation are always both
available; the dial is set per route cluster, never globally.
(Doctrine: ADR 0002, `docs/routing-and-clustering.md`.)

**T6 — External facts are never invented.** Whether prior art, competitors, or
reference architectures exist is not in the corpus. Externally-dependent
outputs stay marked `external-referent unresolved` until either a recorded
authority statement/sign-off resolves the referent in the current run or an
explicit research intake supplies it in a successor run whose manifest names
the prior run. Research material never extends a frozen corpus in place, and
the taint propagates compositionally up the provenance cone. (Doctrine: routing
doctrine §1, §8.)

**T7 — Traceable reconstructability across modes.** Manual mode keeps sparse
cards from which the full graph can be rebuilt; tool mode materializes the full
graph. The shared invariant is that "why this cluster?" always reopens source,
never a summary of summaries. (Doctrine: routing doctrine §9–§11.)

**T8 — Generation and verification are separated, and verification is
adversarial.** *(Proposed.)* No agent grades its own homework. Every judgment
stage (dispositions, merges, evidence roles, routing, synthesis) is followed by
fresh-context verifiers prompted to refute, not to confirm. Verifier
disagreement is not smoothed over — it resolves to `unresolved` and surfaces.
This is the runtime face of the doctrine's stress-test discipline, and it is
what the Fable 5 guidance says works: separate fresh-context verifier
subagents outperform self-critique.

**T9 — Blind context is enforced structurally.** *(Proposed.)* The corpus must
read as a blind input (the checker already enforces no answer-key leakage into
`corpus.md`). Agent mode extends the same principle to runtime: extraction
workers see only corpus; disposition judges see packets, not each other's
verdicts; verifiers see claims without the dispositions they are auditing where
the design calls for independent re-derivation. Leakage between stages is a
defect class, not a convenience.

**T10 — Deterministic where possible, judged where necessary, human where it
matters.** *(Proposed.)* Three verification tiers with a hard boundary between
them: the conformance kernel checks structure and accounting mechanically and
fail-closed; the verification harness judges semantic quality with model
panels; the human authority decides stance, external referents, acceptance, and
anything irreversible. No tier is allowed to impersonate another — the checker
never judges truth, the judges never gate merges to `main`, the human is never
asked to re-derive what the kernel can check.

**T11 — Capability claims require replay evidence.** *(Proposed, extending the
validation ledger.)* "The pipeline can do X" is only claimable after a golden
replay corpus exercises X end-to-end and the result is accepted. The validation
ledger (adversarial arm validated; convergent-heavy and hybrid not yet) is a
living artifact this plan extends to pipeline capabilities: extraction recall,
merge precision, disposition agreement, projection traceability — each earns
"validated" only against a golden corpus.

**T12 — Expose the verification burden; never reward volume.** *(Proposed,
from the daily-research findings.)* More sources, more packets, more prose are
not quality. Artifacts must carry the fields that make their weak points
findable: evidence roles, removal effects, confidence, known incompleteness.
An artifact that looks complete but hides an unverifiable load-bearing source
is the primary failure mode this system exists to prevent.

## 5. What "done" means at the system level

The system-level Definition of Done — the point at which the Aleph Method can
honestly be called v1 — is the conjunction of:

1. **Contracts done.** Every artifact in
   [`03-artifact-contracts.md`](03-artifact-contracts.md) has an accepted
   fixture and, where mechanically checkable, conformance checks added in
   lockstep. The v0 envelope has been revisited against the evidence and
   either amended or deliberately frozen by the authority.
2. **Both arms validated.** The adversarial arm (already validated by the
   Straylight precedent and slice-2) *and* the convergent-heavy /
   known-category-plus-novel-delta hybrid each have at least one accepted
   golden replay corpus, and the validation ledger says so.
3. **Agent mode proven.** A protocol-conforming host adapter has executed a
   full run on a real corpus (instance #1: the 333-conversation export curated
   to ~20 threads) under the runbook, producing a Précis that passed the
   conformance kernel, the verification harness, an independent audit, and
   authority acceptance — with the run directory and immutable bundle/runtime
   pins demonstrating every invariant.
4. **Manual mode proven.** A human has executed at least one bounded corpus by
   hand under the manual runbook, and an agent has reconstructed the full
   derivation graph from the human's sparse cards plus raw source (the
   reconstructability invariant demonstrated, not asserted).
5. **Projection proven.** At least one Tier-1 projection type and one Tier-2
   terminal rendering (recommended: PRD) each have an accepted template,
   fixture, projection-trace checks, and one accepted real output whose every
   load-bearing statement traces to claim IDs.
6. **Honesty preserved.** The known-limits sections still exist and are still
   true: anything unvalidated is still marked unvalidated; the do-not-build
   list is intact; no silent scope growth into business/market-intelligence
   territory or Freeside's product/platform territory occurred.

Anything less is not v1; it is a slice on the way there — which is fine,
because slices are how this repo moves.
