# Run Bridge Reference — Autonomous Excellence Loop

> Extracted from CLAUDE.loa.md for token efficiency. See: `.claude/loa/CLAUDE.loa.md` for inline summary.

## How It Works (v1.35.0)

```
PREFLIGHT → JACK_IN → ITERATING ↔ ITERATING → FINALIZING → JACKED_OUT
                ↓           ↓                      ↓
              HALTED ← ← HALTED ← ← ← ← ← ← HALTED
                ↓
          ITERATING (resume) or JACKED_OUT (abandon)
```

Each iteration: Run sprint-plan → Bridgebuilder review → Parse findings → Flatline check → GitHub trail → Vision capture. Loop terminates when severity-weighted score drops below threshold for consecutive iterations (kaironic termination).

## Usage

```bash
/run-bridge                    # Default: 3 iterations
/run-bridge --depth 5          # Up to 5 iterations
/run-bridge --per-sprint       # Per-sprint review granularity
/run-bridge --resume           # Resume interrupted bridge
/run-bridge --from sprint-plan # Start from existing sprint plan
```

## Bridge State Recovery

Check `.run/bridge-state.json`:

| State | Meaning | Action |
|-------|---------|--------|
| `ITERATING` | Active bridge loop | Continue autonomously |
| `HALTED` | Stopped due to error | Await `/run-bridge --resume` |
| `FINALIZING` | Post-loop GT + RTFM | Continue autonomously |
| `JACKED_OUT` | Completed | No action |

## Key Components

| Component | Script |
|-----------|--------|
| Orchestrator | `bridge-orchestrator.sh` |
| State Machine | `bridge-state.sh` |
| Findings Parser | `bridge-findings-parser.sh` |
| Vision Capture | `bridge-vision-capture.sh` |
| GitHub Trail | `bridge-github-trail.sh` |
| Ground Truth | `ground-truth-gen.sh` |

## Lore Knowledge Base

Cultural and philosophical context in `.claude/data/lore/`:

| Category | Entries | Description |
|----------|---------|-------------|
| Mibera | Core, Cosmology, Rituals, Glossary | Mibera network mysticism framework |
| Neuromancer | Concepts, Mappings | Gibson's Sprawl trilogy mappings |

Skills query lore at invocation time via `index.yaml`. Use `short` fields inline, `context` for teaching moments.

## Configuration

```yaml
run_bridge:
  enabled: true
  defaults:
    depth: 3
    flatline_threshold: 0.05
    consecutive_flatline: 2
```

## Post-PR Integration (Amendment 1, cycle-053)

The Bridgebuilder is also wired into the post-PR validation orchestrator as a dedicated phase. When enabled, it runs after `FLATLINE_PR` and before `READY_FOR_HITL`, closing the feedback loop between external adversarial review and Loa's internal state machine.

### Opt-in config

```yaml
post_pr_validation:
  phases:
    bridgebuilder_review:
      enabled: false           # Default off — progressive rollout
      auto_triage_blockers: true
      depth: 5                 # Bridge iteration depth
```

### Finding triage pipeline

After `bridge-orchestrator.sh` writes findings to `.run/bridge-reviews/*.json`, `post-pr-triage.sh` processes each finding:

| Severity | Action | Queue |
|----------|--------|-------|
| CRITICAL / BLOCKER | `dispatch_bug` (autonomous mode) | `.run/bridge-pending-bugs.jsonl` |
| HIGH / HIGH_CONSENSUS | `log_only` (no gate in autonomous mode) | trajectory log |
| MEDIUM / LOW / DISPUTED | `log_only` | trajectory log |
| PRAISE | `lore_candidate` | `.run/bridge-lore-candidates.jsonl` |
| REFRAME / SPECULATION | `defer` | trajectory log |

Every decision writes a JSON line to `grimoires/loa/a2a/trajectory/bridge-triage-<DATE>.jsonl` with a **mandatory reasoning field** (schema: `.claude/data/trajectory-schemas/bridge-triage.schema.json`) — this satisfies HITL design decision #1 (autonomous acts with logged reasoning, human audits post-hoc).

### Bug queue consumption

`.run/bridge-pending-bugs.jsonl` contains one JSON object per pending auto-dispatched bug. The next `/bug` invocation should consume the queue:

1. Read oldest entry with `status: "pending_dispatch"` from `.run/bridge-pending-bugs.jsonl`
2. Use its `finding` object and `reasoning` field as the bug description
3. Invoke `/bug` with the synthesized context
4. On success: update the entry's `status` to `dispatched` and record the created bug ID

### Kaironic termination pattern

The post-PR phase is now **iterative with convergence detection** (since cycle-053 PR #466 v3 findings):

```
for iter in 1..depth:
  run bridge-orchestrator.sh --depth 1  # one adversarial review
  run post-pr-triage.sh                  # triage + write .run/bridge-triage-convergence.json
  read convergence.state:
    FLATLINE       → break (nothing left to converge on, jack out)
    KEEP_ITERATING → next iteration
```

Convergence is signaled by `state: "FLATLINE"` in `.run/bridge-triage-convergence.json` when both `actionable_high == 0` AND `blocker_count == 0`. This matches the Neuromancer-inspired kaironic termination from `/run-bridge`: *the loop jacks out when there is nothing left to converge on.*

Empirical validation (PR #466, three manual passes demonstrating convergence):

| Pass | HIGH_CONSENSUS | DISPUTED | BLOCKER | Action |
|------|----------------|----------|---------|--------|
| 1    | 2              | 5        | 0       | Fix 2 HIGH |
| 2    | 3              | 9        | 0       | Fix 2 HIGH |
| 3    | **0**          | 7        | 0       | **FLATLINE → jack out** |

The disputed findings that remain after convergence have `delta > 300` across models (one model flags, others don't), which by definition is low-actionable signal. This is the stopping condition: not "all findings resolved" but "no cross-model consensus on HIGH severity."

### Skip flags

Pass `--skip-bridgebuilder` to `post-pr-orchestrator.sh` to bypass this phase even when enabled.

### References

- Design rationale: `grimoires/loa/proposals/close-bridgebuilder-loop.md`
- Sprint plan: `grimoires/loa/proposals/amendment-1-sprint-plan.md`
- Tracking issue: 0xHoneyJar/loa#464 Part B
