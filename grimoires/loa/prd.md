# PRD: Bridgebuilder Constellation — From Pipeline to Deliberation

> Cycle-046 | Created: 2026-02-28
> Sources: PR #429 Bridge Reviews (iter 1-2), Deep Bridgebuilder Review (Parts 1-4), Vision Registry

## 1. Problem Statement

PR #429 (Review Pipeline Hardening) achieved convergence with zero actionable findings, but the Bridgebuilder identified three categories of improvements across 2 bridge iterations and 4 deep review parts:

1. **Code Quality Polish**: 6 LOW findings from bridge iterations 1-2 that were correctly deferred during convergence but are worth addressing. These include JSON encoding safety, redundant cleanup, stderr suppression, fence stripping robustness, version tagging, and Hounfour seam naming.

2. **Deliberation Structure**: The deep review identified that the review pipeline operates as a sequential pipeline where each stage is blind to the others' findings. The Red Team code-vs-design gate would produce higher-quality findings if it could read the audit/review findings that preceded it. This is the "deliberative council" pattern — the difference between jurors voting sequentially and jurors discussing.

3. **Pipeline Self-Awareness**: The pipeline reviews application code but cannot review itself. When a PR modifies `.claude/scripts/` or `.claude/skills/`, the Red Team gate should automatically compare those changes against the pipeline's own SDDs. Pipeline bugs have multiplicative impact.

4. **Architectural Pattern Codification**: The "Governance Isomorphism" — governed access to scarce resources through multi-perspective evaluation with fail-closed semantics — recurs across loa-freeside, loa-dixie, loa-hounfour, and loa. It should be captured as lore and the compliance gate should be parameterized for reuse.

> Sources: bridge-20260228-170473-iter1-full.md, bridge-20260228-170473-iter2-full.md, bridge-deep-review-part1.md through part4.md

## 2. Goals & Success Metrics

| Goal | Metric | Target |
|------|--------|--------|
| All carried LOW findings resolved | 0 LOW findings remaining from PR #429 bridge | 6/6 addressed |
| Red Team gate context-aware | `--prior-findings` flag accepted and used | Findings reference prior review context |
| Pipeline self-review trigger | Auto-detection of .claude/ changes | Self-review fires when pipeline modified |
| Governance Isomorphism captured | Lore entry queryable | Pattern discoverable in future bridge reviews |
| Compliance gate parameterizable | Header keywords from config | Security is one instance, others configurable |

## 3. Functional Requirements

### FR-1: Code Quality Polish (P1)

Address all 6 carried LOW findings from PR #429's bridge convergence.

| ID | Finding | File | Fix |
|----|---------|------|-----|
| FR-1.1 | printf '%s' not JSON-safe for arbitrary strings | flatline-orchestrator.sh:1686 | Use `jq -n --arg` for proper JSON encoding |
| FR-1.2 | Redundant rm -f after trap EXIT | red-team-code-vs-design.sh:313,316 | Remove manual cleanup; trust the trap |
| FR-1.3 | Model adapter stderr suppressed | red-team-code-vs-design.sh:310 | Capture stderr to temp file; surface on failure |
| FR-1.4 | sed fence stripping is line-oriented | red-team-code-vs-design.sh:312 | Add multi-pass extraction for edge cases |
| FR-1.5 | v1.45.0 version tag in SKILL.md | simstim SKILL.md:95 | Replace with cycle reference |
| FR-1.6 | get_model_tertiary() seam unnamed | flatline-orchestrator.sh:203-219 | Add comment naming the Hounfour router seam |

### FR-2: Deliberative Council Pattern (P0)

Add context from earlier review stages to the Red Team code-vs-design gate.

| ID | Requirement |
|----|------------|
| FR-2.1 | Add `--prior-findings <path>` flag to red-team-code-vs-design.sh |
| FR-2.2 | When provided, include prior findings summary in the model prompt |
| FR-2.3 | Wire the flag in the run-mode SKILL.md — pass engineer-feedback.md and auditor-sprint-feedback.md paths |
| FR-2.4 | Budget prior findings into the token budget (1/3 SDD, 1/3 diff, 1/3 prior findings) |

### FR-3: Pipeline Self-Review (P1)

Enable the pipeline to review changes to itself.

| ID | Requirement |
|----|------------|
| FR-3.1 | Detect when PR touches `.claude/scripts/` or `.claude/skills/` files |
| FR-3.2 | Map pipeline scripts to their governing SDDs/SKILL.md specifications |
| FR-3.3 | Auto-trigger Red Team gate against pipeline SDDs when pipeline changes detected |
| FR-3.4 | Integrate into bridge-orchestrator.sh as optional phase |

### FR-4: Governance Isomorphism Lore + Compliance Generalization (P1)

Codify the cross-ecosystem pattern and parameterize the compliance gate.

| ID | Requirement |
|----|------------|
| FR-4.1 | Create lore entry for Governance Isomorphism pattern |
| FR-4.2 | Extract security header keywords from red-team-code-vs-design.sh to config |
| FR-4.3 | Support named compliance gate profiles in .loa.config.yaml |
| FR-4.4 | Document the cross-repo SDD index schema for future implementation |

## 4. Non-Functional Requirements

| Requirement | Details |
|-------------|---------|
| Backward compatibility | All changes must be additive; existing red-team behavior unchanged without new flags |
| Config-gated | New features (self-review, compliance profiles) default to disabled |
| Token budget | Prior findings must fit within existing model context window limits |
| Performance | Pipeline self-review must not add more than 30s to bridge iteration time |

## 5. Out of Scope

- Cross-repository compliance (requires multi-repo infrastructure — strategic, not this cycle)
- Alternative Flatline topologies (study group, free jazz, rave — requires design RFC)
- Review pipeline reputation system (requires metrics collection infrastructure)
- CRDT-style simstim state (requires architectural redesign of state machine)
