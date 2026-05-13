# advisor-strategy Migration Runbook

**Cycle**: cycle-108-advisor-strategy
**Status**: substrate shipped; adoption deferred per rollout-policy.md decision-fork (c')
**Companion**: `grimoires/loa/runbooks/advisor-strategy-rollback.md` (sprint-1 T1.L)

This runbook walks operators through enabling, monitoring, and rolling
back the cycle-108 advisor-strategy framework.

---

## 0. Pre-migration checklist

Before touching `advisor_strategy.enabled`:

- [ ] Read `grimoires/loa/cycles/cycle-108-advisor-strategy/rollout-policy.md`
      §1 (decision-fork outcome) and §3 (per-stratum guidance).
- [ ] Run `tools/modelinv-coverage-audit.py --threshold 0.90 --strict-threshold`.
      Coverage must be ≥90% on cycle-108 v1.2 envelope traffic before
      adoption can resolve from (c') to (a)/(b).
- [ ] Verify the signed baselines tag: `git tag -v cycle-108-baselines-pin-386bbe1779f7`.
- [ ] Confirm operator-approval.md §T3.F shows APPROVED.
- [ ] Confirm Sprint 4 review + audit gates are green.
- [ ] Allocate LLM API budget (default cap $50; raise via `--cost-cap-usd N`).

---

## 1. How to enable advisor-strategy (post-benchmark)

This section applies AFTER the operator-triggered real-data benchmark has
resolved the decision-fork to (a) or (b).

### 1.1 Enable globally (outcome (a))

Edit `.loa.config.yaml`:

```yaml
advisor_strategy:
  enabled: true
  tier_resolution: static
  defaults:
    planning: advisor
    review: advisor
    implementation: executor
  tier_aliases:
    advisor:
      anthropic: claude-opus-4-7
    executor:
      anthropic: claude-sonnet-4-6
  audited_review_skills:
    - reviewing-code
    - auditing-security
    # ... etc, populated via cycle-108-schema-guard CI flow
```

Commit + open PR. CI gate verifies:
- Schema validity (`.claude/data/schemas/advisor-strategy.schema.json`)
- audited_review_skills enum co-edited with SKILL.md role fields
- Atomic-seeding rule satisfied

### 1.2 Enable per-stratum (outcome (b))

Same as 1.1 but add per-skill overrides for strata that did NOT pass:

```yaml
advisor_strategy:
  enabled: true
  # ... as above ...
  per_skill_overrides:
    crypto-skill-1: advisor    # FAILing crypto stratum → pin to advisor
    crypto-skill-2: advisor
```

### 1.3 Verify the kill-switch

After enabling:

```bash
# Smoke: kill-switch overrides config
LOA_ADVISOR_STRATEGY_DISABLE=1 python3 .claude/adapters/cheval.py \
  --agent <some-agent> --role implementation --prompt "test"
# → should NOT use executor tier; legacy resolution path
```

---

## 2. Per-stratum operator decisions

After real-data benchmark, rollout-policy.md §3 will have firm per-stratum
recommendations. Operators may DEVIATE per-skill via `per_skill_overrides`,
but each deviation must be:

1. Recorded in `grimoires/loa/cycles/cycle-108-advisor-strategy/operator-approval.md`
2. Justified by a specific data point in `benchmark-report.md`
3. Reviewed within 30 days post-rollout (via the watch hook — §4 below)

NFR-Sec1 deviations are NOT permitted: skills bound to review/audit roles
MUST resolve to advisor tier, period. The loader rejects deviations with
ConfigError + a clear remediation hint.

---

## 3. How to roll back

Three paths, in increasing severity:

### 3.1 Disable at runtime (instant, reversible)

```bash
# Kill-switch env (any process):
export LOA_ADVISOR_STRATEGY_DISABLE=1
```

This is the fastest path. Restores cycle-107 behavior (legacy single-tier
resolution).

### 3.2 Flip the master switch (config)

```yaml
# .loa.config.yaml
advisor_strategy:
  enabled: false
```

Commit + push. CI validates; merged change propagates to all callers on
next config load.

### 3.3 Surgical revert (cycle-108 substrate removal)

See `grimoires/loa/runbooks/advisor-strategy-rollback.md` (sprint-1 T1.L)
for the three-path detailed procedure (env-var, config flip, surgical
revert of the cycle-108 PR).

---

## 4. Monitoring after rollout (30-day watch)

The post-merge hook at `.claude/hooks/post-merge/cycle-108-rollout-watch.sh`
(T4.B) fires on every merge to main and:

1. Queries `.run/model-invoke.jsonl` for executor-tier audit-failure
   envelopes within 30 days of rollout-commit-SHA.
2. If detected: auto-opens a revert PR setting `advisor_strategy.enabled: false`
   and escalates to operator via the alert channel.
3. After 30 days from rollout, hook becomes no-op.

Operator commands for manual monitoring:

```bash
# Per-stratum cost trend last 30 days:
bash tools/modelinv-rollup.sh --per-stratum --last-N-days 30 \
    --output-md grimoires/loa/cycles/cycle-108-advisor-strategy/post-rollout-30d.md

# Per-skill daily token spend (T4.D quota check):
bash tools/modelinv-rollup.sh --per-skill --last-N-days 1

# Coverage audit (still ≥90%?):
python3 tools/modelinv-coverage-audit.py --threshold 0.90
```

---

## 5. Troubleshooting

### 5.1 "advisor-strategy resolve failed: Provider 'X' not in tier_aliases"

Cause: agent bound to provider X but `tier_aliases.<tier>.X` not set.

Fix: add the provider entry, or accept the graceful fallback (cheval.py
falls back to the agent's bound model unchanged when provider not in
tier_aliases — see C-S2-1 in sprint-2 review).

### 5.2 "NFR-Sec1 violation: role=review resolved to tier=executor"

Cause: someone changed `defaults.review` to `executor` OR an audited_review_skill
got `per_skill_overrides.<skill>: executor`.

Fix: revert the change. NFR-Sec1 is hard-pinned at the loader; no override
path exists.

### 5.3 "REFUSED: baselines.json is UNSIGNED"

Cause: harness gate verifies signed baselines; you're running the benchmark
substrate without a signed pin.

Fix: complete T3.A.OP (operator signs the baselines tag). For dev/test
only: `LOA_BENCHMARK_ALLOW_UNSIGNED_BASELINES=1 tools/advisor-benchmark.sh ...`.

### 5.4 "[STRIP-ATTACK-DETECTED] cutoff=...; post-cutoff entries lack writer_version=1.2"

Cause: rollup tool found an envelope after the v1.2 cutoff that lacks the
writer_version marker — potential audit-chain tamper.

Fix: investigate the offending line. If accidental (e.g., a legacy emitter
stayed live during a config rollout), file a KF entry and patch the emitter.
If malicious, follow incident-response in CLAUDE.md.

### 5.5 "[CHAIN-VERIFY-FAILED]"

Cause: hash-chain validation failed on `.run/model-invoke.jsonl`.

Fix: `audit_recover_chain` from `.claude/scripts/audit-envelope.sh`. See
the rollback runbook §recovery for the full procedure.

### 5.6 30-day watch hook not firing

Cause: hook permissions or post-merge orchestrator misconfigured.

Fix: verify `.claude/hooks/post-merge/cycle-108-rollout-watch.sh` is
executable and listed in `post-merge-orchestrator.sh`'s active hook list.

---

## 6. Re-evaluation triggers

The decision-fork outcome is NOT immutable. Re-evaluate when:

| Signal | Action |
|--------|--------|
| Any FAIL stratum surfaces | Per-stratum FAIL veto fires — flip `enabled: false` for that stratum; re-benchmark within 30 days |
| Coverage drops below 90% | Pause new adoption; trigger coverage-improvement subtask |
| Cost reconciliation drift >20% | Refresh historical-medians.json; re-run cost-cap pre-estimate |
| Operator-flagged production regression | Investigate per §5.1–§5.5; potentially revert via §3 |
| 6 months elapsed since outcome (c') | Re-run real-data benchmark; promote (c') → (a)/(b) if signal warrants |

---

## 7. References

- `grimoires/loa/cycles/cycle-108-advisor-strategy/rollout-policy.md` (this companion)
- `grimoires/loa/cycles/cycle-108-advisor-strategy/prd.md`
- `grimoires/loa/cycles/cycle-108-advisor-strategy/sdd.md` §3 (config schema), §21.1 (canonical dataclass)
- `grimoires/loa/runbooks/advisor-strategy-rollback.md` (rollback procedures)
- `.loa.config.yaml.example` (commented config template)
- `.claude/data/schemas/advisor-strategy.schema.json` (schema)
- `tools/advisor-benchmark.sh` (harness; T2.A + T3.B baselines gate)
- `tools/modelinv-rollup.sh` (cost + coverage rollup)
- `tools/modelinv-coverage-audit.py` (coverage audit; T2.M)
