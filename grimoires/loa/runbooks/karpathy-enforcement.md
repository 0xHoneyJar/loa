# Karpathy Enforcement — Operator Runbook

> **Cycle**: karpathy-enforcement-v1 ([#961](https://github.com/0xHoneyJar/loa/issues/961))
> **Companion**: PR #960 (inline 4 principles in `CLAUDE.loa.md`)
> **Protocol doc**: `.claude/protocols/karpathy-principles.md`
> **Upstream concept**: [multica-ai/andrej-karpathy-skills](https://github.com/multica-ai/andrej-karpathy-skills)

---

## What v1 ships

Two enforcement mechanics + one observability stream:

| Mechanic | Where | When fires |
|---|---|---|
| **Surgical-Changes diff-size hook** | `.claude/hooks/quality/karpathy-surgical-diff-check.sh` | After every Write/Edit/NotebookEdit, when session diff total exceeds threshold |
| **Goal-Driven success-criteria gate** | `.claude/skills/implementing-tasks/SKILL.md` `<karpathy_goal_driven_gate>` | At /implement start, when sprint.md lacks a "Success criteria"/"Acceptance criteria"/"Verification" section |
| **Trajectory log** | `grimoires/loa/a2a/trajectory/karpathy-{date}.jsonl` | Whenever either of the above fires a warn/skip event |

All three are **WARN-mode by default**. No tool calls are blocked in v1. `enforce: block` is the v2 escalation path; the v1 hook returns 0 even with that key set.

---

## Configuration

In `.loa.config.yaml`:

```yaml
karpathy_principles:
  surface_assumptions: true        # advisory — used by skills (no v1 hook consumer)
  surgical_diff_warning: true      # G-1 hook master switch
  diff_lines_per_task: 100         # G-1 threshold
  simplicity_check: true           # v2-reserved
  max_abstraction_depth: 2         # v2-reserved
  require_success_criteria: true   # G-3 gate
  enforce: warn                    # warn | block (v1 honors warn only)
```

Operators opt in by copying the block from `.loa.config.yaml.example`. When keys are absent, the hook defaults to: `surgical_diff_warning: true`, `diff_lines_per_task: 100`.

---

## When the surgical-warn fires

```
[karpathy-surgical-warn] Session diff total 271 lines exceeds threshold 100.
Karpathy principle 3 (Surgical Changes): verify every changed line traces to
the stated task. State: .run/karpathy-task-state.jsonl
```

Operator response options:

| Response | When | Action |
|---|---|---|
| **Acknowledge + continue** | The task legitimately requires the diff size (large refactor, test+impl pair, etc.) | No action needed. Note rationale in PR description. |
| **Split the PR** | The diff has unrelated changes (the "while I'm here" anti-pattern) | Stash the unrelated changes, push the focused diff, file the rest as separate PRs. |
| **Lower the threshold for this skill** | The skill consistently produces over-budget diffs (sign of poor scoping) | Tune `diff_lines_per_task` lower OR file an issue describing the pattern. v2 will introduce per-skill thresholds calibrated from trajectory data. |

The warn is **informational only** — it does not block the Write/Edit. The session state file (`.run/karpathy-task-state.jsonl`) shows the running total + file list.

---

## When the goal-driven gate fires

When `/implement sprint-N` starts and `sprint.md` lacks a "Success criteria" section, the gate surfaces via `AskUserQuestion`:

```
Sprint-N lacks a written success criteria block. Karpathy principle 4
(Goal-Driven) requires testable verification before implementation.

[P]rovide criteria now / [S]kip with rationale / [A]bort
```

| Choice | When | Effect |
|---|---|---|
| **Provide criteria now** | Operator can articulate the testable verification | Agent appends a "Success Criteria" section to sprint.md, then proceeds |
| **Skip with rationale** | Trusted batch run; criteria implicit in the issue body the sprint was generated from | Agent logs the skip + rationale to trajectory, then proceeds |
| **Abort** | Realize you need to revise sprint.md first | Agent exits cleanly; no tool calls fire |

To disable the gate entirely (for trusted autonomous-loop modes):

```yaml
karpathy_principles:
  require_success_criteria: false
```

---

## Reading the trajectory log

```bash
# Today's events
tail -20 grimoires/loa/a2a/trajectory/karpathy-$(date -u +%Y-%m-%d).jsonl

# All warn events for a session
jq 'select(.session_id == "simstim-...")' grimoires/loa/a2a/trajectory/karpathy-*.jsonl

# Frequency by file
jq -s 'group_by(.session_id) | map({session: .[0].session_id, warns: length})' \
    grimoires/loa/a2a/trajectory/karpathy-*.jsonl
```

Schema: `.claude/data/trajectory-schemas/karpathy-check.payload.schema.json`.

---

## Forward look

| Phase | Scope | Status |
|---|---|---|
| v1 | Hook + config + trajectory + Goal-Driven gate | **THIS** |
| v2 | Per-skill `diff_lines_per_task` thresholds calibrated empirically from Phase B data; `enforce: block` semantics ship; cyclomatic-complexity check; success-criteria gate hardens from "ask" to "block-without-rationale" | Future cycle |
| v3 | AST-level abstraction-depth analysis (multi-language); LLM-in-the-loop auto-suggestion for simpler alternatives | Future cycle |

The trajectory data from v1 becomes the calibration substrate for v2. After ~N weeks of accumulated events, the operator can run a roll-up to identify skills where surgical-warns fire most often, and either (a) tune those skills' planning to produce tighter sprints, or (b) ship per-skill threshold overrides.

---

## When to disable

| Scenario | Recommended disable |
|---|---|
| Bulk refactor cycle (e.g., framework-wide rename) | Set `surgical_diff_warning: false` for the duration; restore after |
| First-time onboarding of an autonomous-swarm operator (signal overload) | Start with `enforce: warn` (default); leave gate `require_success_criteria: true` |
| CI runs against the framework itself | Hook is no-op in CI (no PostToolUse events); no action needed |

To temporarily disable the gate in a single session:

```bash
LOA_CONFIG_OVERRIDE=/dev/null /implement sprint-N
```

The `LOA_CONFIG_OVERRIDE=/dev/null` makes both the hook and the gate read an empty config and fall through to defaults — but with the hook's `surgical_diff_warning` defaulting to `true`, the warn still fires. To suppress entirely, supply a config that explicitly sets `surgical_diff_warning: false`.

---

## Cross-references

- Origin: [#961](https://github.com/0xHoneyJar/loa/issues/961)
- Companion PR (inline CLAUDE.loa.md): [#960](https://github.com/0xHoneyJar/loa/pull/960)
- PRD: `grimoires/loa/prd.md` (cycle-local; gitignored)
- SDD: `grimoires/loa/sdd.md` (cycle-local; gitignored)
- Protocol doc: `.claude/protocols/karpathy-principles.md`
- Upstream concept: [multica-ai/andrej-karpathy-skills](https://github.com/multica-ai/andrej-karpathy-skills)
