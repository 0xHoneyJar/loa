# Jam Geometry — Multi-Model Parallel Review Architecture

> Design document for the Jam collaboration geometry.
> Source: Bridgebuilder Deep Review Part III (cycle-026)
> Status: Design (not yet implemented)
> Prerequisite: Epistemic trust scopes (Sprint 9, Tasks 9.1-9.3)

## Concept

Jam geometry enables multi-model parallel review where independent models
review the same artifact simultaneously, then a synthesizer model produces
a unified review with per-model attribution.

Named after jazz jam sessions — musicians playing independently but
converging on shared harmonic structure. Compare: Miles Davis's second
quintet, where freedom within structure produced the highest-quality output.

## Three-Phase Workflow

### Phase 1: Divergent

Three models review the same PR/artifact independently and concurrently:

| Reviewer | Model | Trust Scopes | Role |
|----------|-------|-------------|------|
| `jam-reviewer-claude` | `claude-code:session` (native) | Full access | Primary reviewer with tool access |
| `jam-reviewer-gpt` | `openai:gpt-5.2` | architecture: full, business_logic: redacted, security: none | External skeptic |
| `jam-reviewer-kimi` | `moonshot:kimi-k2-thinking` | architecture: full, business_logic: redacted, security: none | Deep reasoning analysis |

Each reviewer receives the same diff and context, filtered through their
epistemic trust scopes (context_filter.py). Reviews are collected as
structured JSON.

**Infrastructure mapping**: Each reviewer is dispatched via `cheval.py` using
the existing `ProviderAdapter` interface. Concurrent execution uses Python
`asyncio.gather()` or sequential fallback.

### Phase 2: Synthesis

A fourth model (not one of the reviewers) synthesizes the three reviews:

| Synthesizer | Model | Trust Scopes | Why |
|-------------|-------|-------------|-----|
| `jam-synthesizer` | `anthropic:claude-sonnet-4-6` (cheap) | Full architecture, redacted business_logic | Lowest cost for text analysis |

The synthesizer receives:
- The original diff (filtered through its own epistemic scopes)
- All three reviewer outputs (unfiltered — these are structured JSON, not source code)

It produces:
- **Consensus findings**: Issues identified by 2+ reviewers
- **Unique insights**: Findings from only one reviewer (flagged for attention)
- **Disagreements**: Where reviewers conflict (both perspectives presented)
- **Attribution**: Each finding tagged with source reviewer(s)

### Phase 3: Harmony

The synthesized review is posted as a single PR comment with:
- Summary section (consensus + disagreements)
- Per-reviewer attribution tags
- Confidence scores based on inter-reviewer agreement
- Cost breakdown (transparency)

## Infrastructure Mapping

| Jam Component | Existing Infrastructure | Gap |
|---------------|------------------------|-----|
| Reviewer dispatch | `cheval.py` → `ProviderAdapter.complete()` | None — direct reuse |
| Cost tracking | `BudgetEnforcer.pre_call_atomic()` + `post_call()` | None — per-call metering |
| Context filtering | `context_filter.py` (Sprint 9) | None — new in this cycle |
| Concurrent execution | `asyncio` in adapter layer | Minor — need gather wrapper |
| Result collection | `CompletionResult` dataclass | None — direct reuse |
| PR posting | `bridge-github-trail.sh` | Minor — new format template |

## Cost Analysis

### Per Jam Review (estimated)

| Call | Model | Input Tokens | Output Tokens | Cost (micro-USD) |
|------|-------|-------------|---------------|-------------------|
| Reviewer 1 | claude-code:session (native) | N/A | N/A | 0 (unmetered) |
| Reviewer 2 | gpt-5.2 | ~8,000 | ~2,000 | 140,000 |
| Reviewer 3 | kimi-k2-thinking | ~8,000 | ~2,000 | ~100,000 |
| Synthesizer | claude-sonnet-4-6 | ~14,000 | ~1,500 | 64,500 |
| **Total** | | | | **~304,500** (~$0.30) |

> Note: Reviewer 1 runs as the native Claude Code session (model: native),
> which has direct file access and doesn't route through cheval.py. Its cost
> is unmetered — covered by the Claude Code subscription, not per-token billing.

### Comparison to Current Seance Geometry

| Geometry | Models | Calls | Estimated Cost | Quality |
|----------|--------|-------|---------------|---------|
| Seance (current) | 1 (GPT-5.2) | 1 | ~$0.14 | Single perspective |
| Jam (proposed) | 2 remote + native + synth | 4 | ~$0.30 | Multi-perspective + synthesis |

Cost increase: ~2.1x for multi-perspective coverage. Justified for:
- Major architectural changes
- Security-sensitive PRs
- Bridge iteration final reviews

NOT justified for:
- Routine code changes
- Documentation-only PRs
- Single-file fixes

## Phase 0: Scaffold via Flatline Protocol

The existing Flatline Protocol already implements parallel model calls
(primary + secondary). Jam extends this from 2 models to 3 + synthesizer.

Migration path:
1. Add `jam_geometry: false` feature flag (default off)
2. When enabled, Flatline's dual-model review becomes Jam's 3-model review
3. Synthesizer replaces Flatline's scoring step
4. Flatline's BLOCKER/HIGH_CONSENSUS semantics map to Jam's consensus detection

## Prerequisites

1. **Epistemic trust scopes** (Sprint 9, Tasks 9.1-9.3) — reviewers need
   context_access filtering to receive appropriate context
2. **Agent bindings** for Jam roles (Sprint 9, Task 9.5)
3. **Kimi-K2 adapter** — currently declared in model-permissions but no
   dedicated adapter exists (uses openai_compat)

## Open Questions

1. **Synthesizer independence**: Should the synthesizer be a model NOT used
   as a reviewer? (Current design: yes — prevents bias toward own findings)
2. **Partial failure**: What happens when 1 of 3 reviewers fails? Options:
   - Proceed with 2 reviews (degraded Jam)
   - Fall back to Seance geometry (single reviewer)
3. **Cost budgeting**: Should Jam reviews have their own budget bucket,
   or share with the general BudgetEnforcer?

## References

- Miles Davis's second quintet — freedom within structure
- Academic peer review — independent reviewers + editor (synthesizer)
- Bridgebuilder Deep Review Part III — "Jam: independent solo → collective synthesis"
- Ostrom's Principle #1 — boundary enforcement applied to knowledge access
