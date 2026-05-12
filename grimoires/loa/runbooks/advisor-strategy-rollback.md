# Advisor-Strategy Rollback Runbook

> **Cycle**: 108 advisor-strategy benchmark
> **Audience**: operator (@janitooor) or any contributor with shell access
> **Purpose**: revert from `advisor_strategy.enabled: true` to advisor-everywhere
>            behavior in O(seconds), and document the in-flight kill-switch
>            semantics so the operator knows exactly what happens.

---

## TL;DR

Three rollback paths, in order of preference:

| Severity | Mechanism | Recovery time | Side effects |
|----------|-----------|---------------|--------------|
| Emergency | `LOA_ADVISOR_STRATEGY_DISABLE=1` env var | Next cheval invocation (≤5ms after process reads env) | None — kill-switch is per-invocation |
| Standard | Flip `advisor_strategy.enabled: false` in `.loa.config.yaml` | Next cheval invocation (config re-read per call per FR-7 IMP-007) | None — config flip is reversible |
| Surgical | Revert the cycle-108 PR merge commit | Whole feature branch unwound | All cycle-108 work reverted |

The emergency env var ALWAYS wins. There is no override.

---

## 1. Why you might need this

| Symptom | Likely cause | This runbook fixes? |
|---------|--------------|---------------------|
| `/audit-sprint` pass rate drops after switching to executor tier | Executor tier degraded on this sprint kind | ✓ (config flip per skill or globally) |
| MODELINV envelope shows `tier: "executor"` for a `/review-sprint` invocation | NFR-Sec1 bypass — should be caught by loader exit 78, but if seen, rollback now and investigate | ✓ EMERGENCY env var path |
| Cost-cap pre-estimate keeps tripping during benchmark | Executor tier model pricing changed; estimates stale | ✗ (operate at lower `--cost-cap-usd` instead) |
| Production cycle stuck in chain-exhaustion loop | Executor chain too narrow; `INCONCLUSIVE` rate >25% | ✓ (emergency env var) |
| You just want to know that cheval is using advisor tier | Diagnostic, not rollback | ✗ — check `.run/model-invoke.jsonl` last entry |

If your symptom is not listed above, do NOT use this runbook reflexively. Diagnose first.

---

## 2. EMERGENCY rollback — env var (preferred for in-flight runs)

When something is going wrong RIGHT NOW and a sprint is mid-execution:

```bash
export LOA_ADVISOR_STRATEGY_DISABLE=1
```

What happens:

- The next `cheval` invocation (and every subsequent one) returns `AdvisorStrategyConfig.disabled_legacy()` from `loa_cheval/config/loader.py::load_advisor_strategy()`. See SDD §3.3 step 1.
- The currently-running cheval invocation (the one that started before you set the env) completes at its current tier — no mid-call swap. This is intentional: swapping mid-call would invalidate the call's audit envelope.
- Every consumer (`/implement`, `/bug`, `/review-sprint`, `/audit-sprint`, `/plan-and-analyze`, `/architect`, `/sprint-plan`, Flatline, Bridgebuilder, Red Team) reads the env on its next invocation.
- MODELINV envelope records `payload.tier_source: "kill_switch"` for any envelope emitted while the env is set.

When to use:

- An in-flight sprint is producing visibly bad output and you don't want to wait for the next config-load cycle.
- A poisoned `.loa.config.yaml` slipped through CI (shouldn't happen — loader exit 78 — but defense-in-depth).
- You're not sure the config flip will propagate fast enough and you want absolute certainty.

How to undo:

```bash
unset LOA_ADVISOR_STRATEGY_DISABLE
```

The kill-switch reverts within ≤5ms of the next invocation reading the env (well under NFR-P1's 5ms budget — the env-var check is the FIRST thing the loader does, before any I/O).

---

## 3. STANDARD rollback — config flip (preferred for non-urgent changes)

```bash
# Edit .loa.config.yaml — set advisor_strategy.enabled to false
yq eval -i '.advisor_strategy.enabled = false' .loa.config.yaml
git diff .loa.config.yaml   # verify
git add .loa.config.yaml
git commit -m "rollback: disable advisor_strategy (reason: <fill in>)"
```

What happens:

- Every cheval invocation re-reads `.loa.config.yaml::advisor_strategy` at load time (per-invocation, not per-process; FR-7 IMP-007).
- The next cheval call sees `enabled: false` and returns `disabled_legacy()`.
- The currently-running cheval invocation completes at the OLD tier (same in-flight semantics as the env var path).
- Operator-visible warning emitted on first invocation after the flip: `[advisor-strategy] INFO: enabled changed false<-true; legacy mode active`.

When to use:

- You want the rollback to be visible in git history (audit trail).
- You're rolling back during a benchmark or extended run where you want the change to be the canonical state, not just an env-var override on your local machine.
- You're rolling back a per-skill override rather than the whole feature (edit `per_skill_overrides` instead of `enabled`).

How to undo:

```bash
git revert <rollback-commit-sha>
```

---

## 4. In-flight kill-switch semantics (FR-7 IMP-007)

The two rollback paths above behave the SAME way when fired mid-sprint:

1. The currently-running cheval invocation completes at its current tier. Mid-call tier swap would corrupt the call's MODELINV envelope by mixing model output with metadata claiming a different model. We don't do that.
2. The NEXT cheval invocation reads the new state (env or config) and routes accordingly.
3. `.run/sprint-plan-state.json` records the transition in a `tier_transitions` array with timestamps.
4. MODELINV envelopes during the transition window show distinct `tier_source` values; downstream rollup (Sprint 2 T2.E) handles this naturally because it groups by `tier_source` not `tier` alone.

The behavior is **eventually consistent**, not transactional. If you flip mid-sprint, expect a brief mixed-tier window. To make the transition clean:

- Wait for `.run/sprint-plan-state.json::state` to reach `JACKED_OUT` between sprints
- Then flip
- Then `/run-resume` (if mid-run) or just start the next /run

---

## 5. SURGICAL rollback — revert the cycle-108 merge

This is the nuclear option. Use only if T1.A's atomic commit needs to be undone wholesale (e.g., the schema enum seeded incorrect skills and that's causing systemic failures).

```bash
# Find the merge commit on main
git log --merges --first-parent main | head -5

# Revert it (will conflict with anything that depends on the changes —
# expect to resolve)
git revert -m 1 <merge-sha>

# Push
git push origin main
```

What happens:

- All cycle-108 substrate (schema, loader, validator extension, SKILL.md role fields, CODEOWNERS additions) is undone in one commit.
- The validator's role-aware path becomes a no-op because no skill has `role:` anymore (and `LOA_VALIDATE_ROLE=1` only activates the path when role is present — see SDD §4.2).
- Existing integrations that depended on `cheval --role` parameters fail-closed (loader returns `disabled_legacy()`, role param ignored).

When to use this:

- Never, if at all possible. The standard config flip handles 99% of rollback scenarios with zero side effects.
- Only if there's a substantive defect in the substrate itself (not the policy).

---

## 6. Verification after rollback

```bash
# 1. Confirm cheval sees the disabled config
echo "Running cheval probe..."
LOA_ADVISOR_STRATEGY_DISABLE=1 .claude/adapters/cheval.py invoke --role implementation --skill smoke-test --dry-run 2>&1 | grep -E 'tier_source|enabled'
# Expect: tier_source: kill_switch (or config-disabled if you used the standard rollback)

# 2. Confirm MODELINV envelopes reflect the change
tail -3 .run/model-invoke.jsonl | jq -r '.payload | {tier, tier_source, role}'
# Expect: tier_source: kill_switch OR (advisor_strategy.enabled: false in config)

# 3. Run a full cycle smoke test
.claude/scripts/cycle-108-smoke.sh   # (Sprint 2 deliverable — not yet available)
```

---

## 7. Known failure modes during rollback

| Symptom | Cause | Fix |
|---------|-------|-----|
| `[advisor-strategy] EX_CONFIG: schema invalid` after config flip | Your `.loa.config.yaml` has a typo OR is on an old schema version | Run `python -m loa_cheval.config.loader --validate` to identify; restore from `git checkout HEAD~1 -- .loa.config.yaml` |
| Kill-switch env var has no effect | You're inside a subshell that didn't inherit the export | `env | grep LOA_ADVISOR_STRATEGY_DISABLE` to verify; re-export at parent shell |
| MODELINV envelopes still show `tier: "executor"` after flip | An in-flight invocation that started before the flip; wait for it to complete | Check `.run/model-invoke.jsonl | tail -1` timestamp vs your flip time |
| Validator now fails new SKILL.md PRs with "Missing role:" | Expected — T1.D validator enforces post-T1.A | Add `role:` to the new SKILL.md (see SDD §4.1) |

---

## 8. Provenance

- PRD §5 FR-7: rollback semantics requirement
- SDD §3.3 step 1: kill-switch wins at loader layer
- SDD §7.1: rollback design (single source of truth, no per-consumer override)
- SDD §20.6 ATK-A14 closure: symlink defenses (Sprint 1 T1.E pairs with this runbook)
- Implementing commits: fb5b3829 (T1.D), 8f5695f5 (T1.A)

---

> **Maintenance**: this runbook is a living document. When Sprint 2 ships
> the cost aggregator + cheval CLI flags, update §6 with concrete commands.
> Cycle-108 sprint-1 T1.L.
