# Proposal: Model-Tier Economization — Demote Per-Iteration Workloads to Cheaper Substrate

**Date**: 2026-05-16
**Author**: Session continuation working with @janitooor
**Status**: Draft — operator review
**Cost evidence**: This session's 4 BB sweeps (batches 5/6/7/8)
**Related**: KF-010 (cheval-delegate Google 300s timeout), `feedback_advisor_benchmark.md`, cycle-108 advisor-strategy

---

## TL;DR

Every workflow stage today resolves through `tier_aliases.advisor` (premium):
`claude-opus-4-7` / `gpt-5.5-pro` / `gemini-3.1-pro-preview`. Of those, `gpt-5.5-pro` at $30/$180 per Mtok dominates BB cost (91% of this session's $37 spend). The same `tier_aliases` block already defines an `executor` tier (`sonnet-4-6` / `gpt-5.3-codex` / `gemini-2.5-pro`) but nothing routes to it. **Shifting iterative workloads (BB + review + implementation) to `executor` cuts cost ~6× per BB run with minimal quality risk per the existing advisor-benchmark memory.**

## Cost evidence (this session — 2026-05-16)

| Voice | Model | $/Mtok in/out | Tokens (6 BBs sum) | $ spend | Share |
|-------|-------|---------------|---------------------|---------|-------|
| Anthropic | claude-opus-4.7 | $5 / $25 | 12 in / 47k out | $1.18 | 9% |
| **OpenAI** | **gpt-5.5-pro** | **$30 / $180** | 230k in / 31k out | **$12.50** | **91%** |
| Google | gemini-3.1-pro | $1.25 / $10 | (timed out) | $0.00 | 0% |
| **Total batch-5** | | | | **$13.68** | |

Average per BB run across 14 BB invocations this session: **$2.28**. Total session BB spend: **~$37**.

Anthropic's $1.18 across 6 runs is anomalously low — the `inputTokens=3` per call suggests prompt-caching is doing heavy lifting on the system prompt + persona. OpenAI sees the full 230k token cumulative input because BB's openai adapter likely doesn't share that cache.

## What the substrate already supports

`.loa.config.yaml::advisor_strategy.tier_aliases` (cycle-108) defines two tiers:

```yaml
tier_aliases:
  advisor:                          # premium — $$$
    anthropic: claude-opus-4-7      # $5 / $25
    openai: gpt-5.5-pro             # $30 / $180   ← cost driver
    google: gemini-3.1-pro-preview  # $1.25 / $10
  executor:                         # cheap — $
    anthropic: claude-sonnet-4-6    # $3 / $15
    openai: gpt-5.3-codex           # $1.75 / $14   ← 17× cheaper than 5.5-pro out
    google: gemini-2.5-pro          # $1.25 / $10
```

And the `defaults` block:

```yaml
defaults:
  planning: advisor
  review: advisor
  audit: advisor
  implementation: advisor
```

Every workflow stage is at `advisor`. There is no `economize` flag because the tier infrastructure is already in place — it's just unused for downgrade.

## Recommended tier-mapping policy

| Stage | Today | Proposed | Rationale |
|-------|-------|----------|-----------|
| `planning` (`/plan-and-analyze`, `/architect`, `/sprint-plan`) | advisor | **advisor** | 1-shot, high-leverage architectural decisions. Quality > cost. |
| `audit` (`/audit-sprint`, `/audit-deployment`, security audits) | advisor | **advisor** | Final-pass quality gate. Catches what other passes miss. Same rationale. |
| `review` (`/review-sprint`, BB iterations) | advisor | **executor** | Per-iteration BB cycles. Peer-review structure already recovers quality from weaker individual voices. |
| `implementation` (`/implement`) | advisor | **executor** | Routine code edits. Per `feedback_advisor_benchmark.md`: "Sonnet executor ≈ Opus quality for simple tasks at ~5x cheaper tokens." |

For BB specifically: `bridgebuilder.multi_model.models[1].model_id` (line 231 of `.loa.config.yaml`) is the direct swap point. Change `gpt-5.5-pro` → `gpt-5.5` (non-pro) to align with the executor tier.

## Projected savings

Per BB run, holding all else equal:

| Component | Current (advisor) | Proposed (executor) | Change |
|-----------|-------------------|---------------------|--------|
| OpenAI voice (230k in, 31k out at session-5 mean) | $12.50 / 6 PRs = $2.08 | gpt-5.5 ($5/$30): $1.15 + $0.93 = **$2.08** | 0% (same model, just non-pro variant) |
| OpenAI voice if swapped to gpt-5.3-codex | $2.08 | $0.40 + $0.43 = **$0.83** | **−60%** |
| OpenAI voice if swapped to gpt-5.5 (non-pro) explicitly | $2.08 | $1.15 + $0.93 = **$2.08** | wait, let me recheck |

(Recompute: gpt-5.5-pro is `$30/$180`, gpt-5.5 is `$5/$30`. For 230k in / 31k out: gpt-5.5-pro = $6.90 + $5.58 = $12.48 across 6 PRs = $2.08/PR. gpt-5.5 = $1.15 + $0.93 = $2.08 across 6 PRs = $0.35/PR. So swap to gpt-5.5 = **6× cheaper**.)

| Scenario | Per BB | 10 PRs/week | Yearly (at this session's rate) |
|----------|--------|-------------|-----------------------|
| Today (gpt-5.5-pro) | $2.28 | $22.80 | ~$1,185 |
| Swap to gpt-5.5 | ~$0.50 | $5.00 | ~$260 |
| Swap to gpt-5.3-codex | ~$0.30 | $3.00 | ~$155 |

The codex tier is meaningfully cheaper but `gpt-5.3-codex` is reasoning-class on `/v1/responses` and historically still slow; `gpt-5.5` (non-pro) on chat endpoint is the safe middle.

## Secondary benefit: latency + KF-010 mitigation

`gpt-5.5-pro` triggers `/v1/responses` reasoning mode with observed latency of **900-1100s on 95k diffs** (per the comment in `multi-model-pipeline.ts:30`). Non-pro `gpt-5.5` on the chat endpoint stays in the 30-200s range (this session's OpenAI voice averaged 117s).

Faster OpenAI completions → smaller wall-time window where concurrent BB sweeps overlap → less concurrent-load pressure on the cheval substrate → may reduce KF-010 Google timeout recurrence (correlated, not causal — but worth measuring).

## Empirical validation plan

Two-cycle A/B before rolling out the default change:

1. **Re-run BB on PR #804** (the heaviest remaining open PR — 5 disputed findings under advisor tier) using `executor` tier. Compare:
   - Total findings count
   - HIGH_CONSENSUS findings count (delta from advisor run)
   - Verdict (REQUEST_CHANGES vs COMMENT)
   - Wall time
   - Total $
2. **Re-run BB on a recently-merged advisor-tier PR** (e.g., #913) with `executor` tier. The advisor-tier outcome is known (clean, 0/0/0); does the executor tier reach the same verdict?

If both runs cost ≤ ⅓ of advisor + reach the same verdict (or only differ on LOW_VALUE findings), promote `executor` as the default for `review` + `implementation`. If the executor run misses HIGH findings the advisor run caught, hold the proposal and consider a hybrid (advisor for the primary anthropic voice, executor for openai + google).

## What's NOT in scope

- New skill (`/economize` or `/translate`) — the tier infrastructure already exists; no new code is needed beyond editing `.loa.config.yaml::defaults` and one BB models entry.
- `model_tier: budget | balanced | premium` user-facing switch — the existing `advisor` / `executor` tier names are perfectly adequate; just need the operator-side default to be configurable per workflow stage (which it already is).
- Multi-tier-per-stage routing logic — not necessary; the existing per-stage `defaults` field handles it.

## Recommended next action (for operator review)

1. Approve this proposal (or amend tier assignments).
2. I edit `.loa.config.yaml` to:
   - Set `advisor_strategy.defaults.review` → `executor`
   - Set `advisor_strategy.defaults.implementation` → `executor`
   - Set `run_bridge.bridgebuilder.multi_model.models[1].model_id` → `gpt-5.5`
3. Run the two-cycle empirical validation (above).
4. If validation passes: land the change as a PR; document the tier policy in `grimoires/loa/lore` for future agents.
5. If validation fails: revert the BB models entry, hold the broader change for a future cycle that can investigate finding-quality regressions more thoroughly.

## Open questions for operator

- Should `audit-deployment` (production infrastructure) stay at advisor even when other audits demote? (Probably yes — the blast radius is operator-side, so the quality premium is justified.)
- Should the `bridgebuilder` advisor-tier anthropic voice (`claude-opus-4-7`) also be considered for swap? Per the cost data, it's already $0.20/run thanks to prompt caching — swapping to `claude-sonnet-4-6` would save ~$0.10/run for ~10% of the spend, which doesn't justify the quality risk on the most-trusted voice in the consensus.
