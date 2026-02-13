# Red Team — Generative Adversarial Security Design

## Purpose

Use the Flatline Protocol's red team mode to generate creative attack scenarios against design documents. Produces structured attack scenarios with consensus classification and architectural counter-designs.

## Invocation

```bash
/red-team grimoires/loa/sdd.md
/red-team grimoires/loa/sdd.md --focus "agent-identity,token-gated-access"
/red-team grimoires/loa/sdd.md --mode quick
/red-team grimoires/loa/sdd.md --depth 2 --mode deep
/red-team --spec "Users authenticate via wallet signature and receive a JWT"
```

## Arguments

| Argument | Flag | Default | Description |
|----------|------|---------|-------------|
| document | positional | required | Path to document to red-team |
| spec | `--spec` | — | Inline spec text (creates temp document) |
| focus | `--focus` | all | Comma-separated attack surface categories |
| section | `--section` | all | Specific document section to target |
| depth | `--depth` | 1 | Attack-counter_design iterations |
| mode | `--mode` | standard | Execution mode: quick, standard, deep |

## Workflow

1. **Validate Config**: Check `red_team.enabled: true` in `.loa.config.yaml`
2. **Input Handling**: Load document or create temp file from `--spec`
3. **Surface Loading**: Load attack surfaces from registry, filter by `--focus`
4. **Invoke Orchestrator**: Call `flatline-orchestrator.sh --mode red-team`
5. **Present Results**: Show attack summary with consensus categories
6. **Human Gate**: If any severity >800, require human acknowledgment

## Execution Modes

| Mode | Models | Cross-Validation | Counter-Design | Budget |
|------|--------|-------------------|----------------|--------|
| Quick | 2 (primary only) | Skip | Inline only | 50K tokens |
| Standard | 4 (primary + secondary) | Full | Full synthesis | 200K tokens |
| Deep | 4 + iteration | Full | Full + multi-depth | 500K tokens |

### Quick Mode Restrictions

- Outputs labeled **UNVALIDATED**
- Cannot produce `CONFIRMED_ATTACK` — all findings are `THEORETICAL` or `CREATIVE_ONLY`
- No cross-validation performed
- For exploratory use only, not for gating decisions

## Consensus Categories

| Category | Criteria | Meaning |
|----------|----------|---------|
| CONFIRMED_ATTACK | Both models score >700 | Attack is realistic and should be addressed |
| THEORETICAL | One model >700, other ≤700 | Plausible but models disagree |
| CREATIVE_ONLY | Neither model scores >700 | Novel but neither model finds it convincing |
| DEFENDED | Both models >700 AND counter-design exists | Attack is real but already has effective defense |

**Score Examples**:
- GPT=850, Opus=900 → CONFIRMED_ATTACK (both >700)
- GPT=800, Opus=400 → THEORETICAL (one >700, other ≤700)
- GPT=650, Opus=750 → THEORETICAL (Opus >700, GPT ≤700)
- GPT=500, Opus=600 → CREATIVE_ONLY (neither >700)
- GPT=300, Opus=200 → CREATIVE_ONLY (neither >700)

## Human Validation Gate

When any attack scores severity >800:

**Interactive mode**: Present attack details and require acknowledgment:
```
HUMAN REVIEW REQUIRED

ATK-003: Confused Deputy in Ensemble Routing
Severity: 920/1000
Consensus: CONFIRMED_ATTACK

[A]cknowledge / [D]ismiss / [E]scalate
```

**Autonomous mode**: Write to `pending-review.json` for later human review.

## Output Files

| File | Permissions | Content |
|------|-------------|---------|
| `.run/red-team/rt-{id}-result.json` | 0644 | Full JSON result |
| `.run/red-team/rt-{id}-report.md` | 0600 | Full report (restricted) |
| `.run/red-team/rt-{id}-summary.md` | 0644 | Safe summary for PR/CI |
| `.run/red-team/.ci-safe` | 0644 | Manifest of CI-safe files |

## Error Handling

| Error | Cause | Resolution |
|-------|-------|------------|
| "red_team.enabled is not true" | Config toggle off | Set `red_team.enabled: true` |
| "Input blocked by sanitizer" | Credentials in document | Remove credentials from input |
| "Budget exceeded" | Token limit hit | Use lower execution mode |
| "Orchestrator failed" | Model invocation error | Check API keys, retry |

## Configuration

```yaml
red_team:
  enabled: true
  mode: standard
  thresholds:
    confirmed_attack: 700
    theoretical: 400
    human_review_gate: 800
  budgets:
    quick_max_tokens: 50000
    standard_max_tokens: 200000
    deep_max_tokens: 500000
```

## Simstim Integration

When `red_team.simstim.auto_trigger: true`, the red team automatically runs as Phase 4.5 (RED TEAM SDD) during the simstim workflow, after FLATLINE SDD review and before PLANNING.

## Related

- `/flatline-review` — Standard Flatline Protocol quality review
- `/audit` — Codebase security audit (implementation-level)
- `.claude/data/attack-surfaces.yaml` — Attack surface registry
- `.claude/data/red-team-golden-set.json` — Calibration corpus
