<!-- @loa-managed: true | version: 1.39.0 | hash: fc41a851ab8ab9ac778f7542426b0891905b21aff4e8c0f077564cb9def0166ePLACEHOLDER -->
<!-- WARNING: This file is managed by the Loa Framework. Do not edit directly. -->

# Loa Framework Instructions

Agent-driven development framework. Skills auto-load their SKILL.md when invoked.

## Reference Files

| Topic | Location |
|-------|----------|
| Configuration | `.loa.config.yaml.example` |
| Context/Memory | `.claude/loa/reference/context-engineering.md` |
| Protocols | `.claude/loa/reference/protocols-summary.md` |
| Scripts | `.claude/loa/reference/scripts-reference.md` |
| Beads | `.claude/loa/reference/beads-reference.md` |
| Run Bridge | `.claude/loa/reference/run-bridge-reference.md` |
| Flatline | `.claude/loa/reference/flatline-reference.md` |
| Memory | `.claude/loa/reference/memory-reference.md` |
| Guardrails | `.claude/loa/reference/guardrails-reference.md` |
| Hooks | `.claude/loa/reference/hooks-reference.md` |
| Agent Teams | `.claude/loa/reference/agent-teams-reference.md` |

## Beads-First Architecture (v1.29.0)

**Beads task tracking is the EXPECTED DEFAULT.** Working without beads is abnormal. Health checks run at every workflow boundary.

```bash
.claude/scripts/beads/beads-health.sh --json
```

**Protocol**: `.claude/protocols/beads-preflight.md` | **Reference**: `.claude/loa/reference/beads-reference.md`

## Three-Zone Model

| Zone | Path | Permission |
|------|------|------------|
| System | `.claude/` | NEVER edit |
| State | `grimoires/`, `.beads/`, `.ck/`, `.run/` | Read/Write |
| App | `src/`, `lib/`, `app/` | Confirm writes |

**Critical**: Never edit `.claude/` - use `.claude/overrides/` or `.loa.config.yaml`.

## File Creation Safety

**CRITICAL**: Bash heredocs silently corrupt source files containing `${...}` template literals.

| Method | Shell Expansion | When to Use |
|--------|-----------------|-------------|
| **Write tool** | None | Source files (.tsx, .jsx, .ts, .js, etc.) - PREFERRED |
| `<<'EOF'` (quoted) | None | Shell content with literal `${...}` |
| `<< EOF` (unquoted) | Yes | Shell scripts needing variable expansion only |

**Rule**: For source files, ALWAYS use Write tool. If heredoc required, ALWAYS quote the delimiter.

**Protocol**: `.claude/protocols/safe-file-creation.md`

## Configurable Paths (v1.27.0)

Grimoire and state file locations configurable via `.loa.config.yaml`. Overrides: `LOA_GRIMOIRE_DIR`, `LOA_BEADS_DIR`, `LOA_SOUL_SOURCE`, `LOA_SOUL_OUTPUT`. Rollback: `LOA_USE_LEGACY_PATHS=1`. Requires yq v4+.

## Golden Path (v1.30.0)

**5 commands for 90% of users.** All existing truename commands remain available for power users.

| Command | What It Does | Routes To |
|---------|-------------|-----------|
| `/loa` | Where am I? What's next? | Status + health + next step |
| `/plan` | Plan your project | `/plan-and-analyze` → `/architect` → `/sprint-plan` |
| `/build` | Build the current sprint | `/implement sprint-N` (auto-detected) |
| `/review` | Review and audit your work | `/review-sprint` + `/audit-sprint` |
| `/ship` | Deploy and archive | `/deploy-production` + `/archive-cycle` |

**Script**: `.claude/scripts/golden-path.sh`

## Workflow (Truenames)

| Phase | Command | Output |
|-------|---------|--------|
| 1 | `/plan-and-analyze` | PRD |
| 2 | `/architect` | SDD |
| 3 | `/sprint-plan` | Sprint Plan |
| 4 | `/implement sprint-N` | Code |
| 5 | `/review-sprint sprint-N` | Feedback |
| 5.5 | `/audit-sprint sprint-N` | Approval |
| 6 | `/deploy-production` | Infrastructure |

**Ad-hoc**: `/audit`, `/bug`, `/translate`, `/validate`, `/feedback`, `/compound`, `/enhance`, `/flatline-review`, `/update-loa`, `/loa`

**Run Mode**: `/run sprint-N`, `/run sprint-plan`, `/run-status`, `/run-halt`, `/run-resume`

**Run Bridge**: `/run-bridge`, `/run-bridge --depth N`, `/run-bridge --resume`

## Key Protocols

- **Memory**: Maintain `grimoires/loa/NOTES.md`
- **Feedback**: Check audit feedback FIRST, then engineer feedback
- **Karpathy**: Think Before Coding, Simplicity First, Surgical Changes, Goal-Driven
- **Git Safety**: 4-layer upstream detection with soft block

## Process Compliance

**CRITICAL**: These rules prevent the AI from bypassing Loa's quality gates.

### NEVER Rules

| Rule | Why |
|------|-----|
<!-- @constraint-generated: start process_compliance_never | hash:64c9a09343312a4d -->
<!-- DO NOT EDIT — generated from .claude/data/constraints.json -->
| NEVER write application code outside of `/implement` skill invocation (OR when a construct with declared `workflow.gates` owns the current workflow) | Code written outside `/implement` bypasses review and audit gates |
| NEVER use Claude's `TaskCreate`/`TaskUpdate` for sprint task tracking when beads (`br`) is available | Beads is the single source of truth for task lifecycle; TaskCreate is for session progress display only |
| NEVER skip from sprint plan directly to implementation without `/run sprint-plan`, `/run sprint-N`, or `/bug` triage (OR when a construct with `workflow.gates` declares pipeline composition) | `/run` wraps implement+review+audit in a cycle loop with circuit breaker. `/bug` produces a triage handoff that feeds directly into `/implement`. |
| NEVER skip `/review-sprint` and `/audit-sprint` quality gates (Yield when construct declares `review: skip` or `audit: skip`) | These are the only validation that code meets acceptance criteria and security standards |
| NEVER use `/bug` for feature work that doesn't reference an observed failure | `/bug` bypasses PRD/SDD gates; feature work must go through `/plan` |
<!-- @constraint-generated: end process_compliance_never -->
### ALWAYS Rules

| Rule | Why |
|------|-----|
<!-- @constraint-generated: start process_compliance_always | hash:345d40b9155bfc9c -->
<!-- DO NOT EDIT — generated from .claude/data/constraints.json -->
| ALWAYS use `/run sprint-plan`, `/run sprint-N`, or `/bug` for implementation | Ensures review+audit cycle with circuit breaker protection. `/bug` enforces the same cycle for bug fixes. |
| ALWAYS create beads tasks from sprint plan before implementation (if beads available) | Tasks without beads tracking are invisible to cross-session recovery |
| ALWAYS complete the full implement → review → audit cycle | Partial cycles leave unreviewed code in the codebase |
| ALWAYS check for existing sprint plan before writing code (Yield when construct declares `sprint: skip`) | Prevents ad-hoc implementation without requirements traceability |
| ALWAYS validate bug eligibility before `/bug` implementation | Prevents feature work from bypassing PRD/SDD gates via `/bug`. Must reference observed failure, regression, or stack trace. |
<!-- @constraint-generated: end process_compliance_always -->
### Permission Grants (MAY Rules)

Positive rights that agents may exercise at their discretion. Precedence: `NEVER > MUST > ALWAYS > SHOULD > MAY`. When exercising a MAY permission, cite the constraint ID.

| Rule | Why |
|------|-----|
<!-- @constraint-generated: start permission_grants | hash:d9c73e5a5b716954 -->
<!-- DO NOT EDIT — generated from .claude/data/constraints.json -->
| MAY question the framing of requirements during `/plan-and-analyze` and bridge reviews when analysis warrants reframing | The deepest architectural insights come from questioning the frame, not just analyzing within it. Permission to ask 'is this the right problem?' enables the level of inquiry that produced findings like lot_invariant-as-social-contract and Ostrom-as-governance. |
| MAY allocate time for Vision Registry exploration when a captured vision is relevant to current work | The Vision Registry captures speculative insights but none have ever been explored. Permission to allocate effort enables the 20% creative exploration that transforms captured ideas into actionable proposals. |
| MAY propose alternative architectural approaches during bridge reviews and `/review-sprint` | Architectural evolution requires the ability to propose alternatives. Reviews that only check conformance to existing patterns cannot discover when the pattern itself should change. |
| MAY create SPECULATION findings during planning and review skills — excluded from `/implement` and `/audit-sprint` | SPECULATION is currently scoped to bridge reviews only. Extending to planning and review skills enables creative architectural thinking at the stages where it has the most impact, while excluding implementation and audit where it could rationalize unsafe changes. |
<!-- @constraint-generated: end permission_grants -->
### Task Tracking Hierarchy

| Tool | Use For | Do NOT Use For |
|------|---------|----------------|
<!-- @constraint-generated: start task_tracking_hierarchy | hash:441e3fde55f977ca -->
<!-- DO NOT EDIT — generated from .claude/data/constraints.json -->
| `br` (beads_rust) | Sprint task lifecycle: create, in-progress, closed | — |
| `TaskCreate`/`TaskUpdate` | Session-level progress display to user | Sprint task tracking |
| `grimoires/loa/NOTES.md` | Observations, blockers, cross-session memory | Task status |
<!-- @constraint-generated: end task_tracking_hierarchy -->
**Protocol**: `.claude/protocols/implementation-compliance.md`

## Run Mode State Recovery (v1.27.0)

**CRITICAL**: After context compaction or session recovery, ALWAYS check for active run mode.

Check `.run/sprint-plan-state.json`:

| State | Meaning | Action |
|-------|---------|--------|
| `RUNNING` | Active autonomous execution | Resume immediately, do NOT ask for confirmation |
| `HALTED` | Stopped due to error/blocker | Await `/run-resume` |
| `JACKED_OUT` | Completed successfully | No action needed |

Read `sprints.current` for active sprint. Update `timestamps.last_activity` on each action.

## Post-Compact Recovery Hooks (v1.28.0)

Automatic context recovery after compaction. PreCompact saves state, UserPromptSubmit injects recovery reminder (one-shot).

**Reference**: `.claude/loa/reference/hooks-reference.md`

## Run Bridge — Autonomous Excellence Loop (v1.35.0)

Iterative improvement loop with kaironic termination. Check `.run/bridge-state.json` for state recovery.

### Bridge Constraints

| Rule | Why |
|------|-----|
<!-- @constraint-generated: start bridge_constraints | hash:b275e2abcc060ceb -->
<!-- DO NOT EDIT — generated from .claude/data/constraints.json -->
| ALWAYS use `/run sprint-plan` (not direct `/implement`) within bridge iterations | Bridge iterations must inherit the implement→review→audit cycle with circuit breaker protection |
| ALWAYS post Bridgebuilder review as PR comment after each bridge iteration | GitHub trail provides auditable history of iterative improvement decisions |
| ALWAYS ensure Grounded Truth claims cite `file:line` source references | Ungrounded claims in GT files propagate misinformation across sessions and agents |
| ALWAYS use YAML format for lore entries with `id`, `term`, `short`, `context`, `source`, `tags` fields | Consistent schema enables programmatic lore queries and cross-skill integration |
| ALWAYS include source bridge iteration and PR in vision entries | Vision entries without provenance cannot be traced back to the context that inspired them |
| ALWAYS load and validate bridgebuilder-persona.md before enriched review iterations | Persona-less reviews produce convergence-only output without educational depth |
| SHOULD include PRAISE findings only when warranted by genuinely good engineering decisions | Forced praise dilutes the signal; authentic recognition of quality reinforces good patterns |
| SHOULD populate educational fields (faang_parallel, metaphor, teachable_moment) only with confident, specific insights | Generic educational content wastes reviewer attention; depth over coverage |
<!-- @constraint-generated: end bridge_constraints -->

**Reference**: `.claude/loa/reference/run-bridge-reference.md`

## BUTTERFREEZONE — Agent-Grounded README (v1.35.0)

Token-efficient, provenance-tagged project summary. Scripts: `butterfreezone-gen.sh`, `butterfreezone-validate.sh`. Skill: `/butterfreezone`.

## Flatline Protocol (v1.22.0)

Multi-model adversarial review (Opus + GPT-5.2). HIGH_CONSENSUS auto-integrates, BLOCKER halts autonomous workflows.

**Reference**: `.claude/loa/reference/flatline-reference.md`

## Invisible Prompt Enhancement (v1.17.0)

Prompts automatically enhanced before skill execution. Silent, logged to trajectory.

## Invisible Retrospective Learning (v1.19.0)

Learnings auto-detected during skill execution. Quality gates: Depth, Reusability, Trigger Clarity, Verification.

## Input Guardrails & Danger Level (v1.20.0)

Pre-execution validation. PII filtering (blocking), injection detection (blocking), relevance check (advisory).

**Reference**: `.claude/loa/reference/guardrails-reference.md`

## Persistent Memory (v1.28.0)

Session-spanning observations in `grimoires/loa/memory/observations.jsonl`. Query via `.claude/scripts/memory-query.sh`.

**Reference**: `.claude/loa/reference/memory-reference.md`

## Post-Merge Automation (v1.36.0)

Automated pipeline on merge to main: classify → semver → changelog → GT → RTFM → tag → release → notify.

### Merge Constraints

| Rule | Why |
|------|-----|
<!-- @constraint-generated: start merge_constraints | hash:a4e518ce81f64b8d -->
<!-- DO NOT EDIT — generated from .claude/data/constraints.json -->
| ALWAYS use `post-merge-orchestrator.sh` for pipeline execution, not ad-hoc commands | Orchestrator provides state tracking, idempotency, and audit trail |
| NEVER create tags manually — always use semver-bump.sh for version computation | Manual tags bypass conventional commit parsing and may produce incorrect versions |
| RTFM gaps MUST be logged but MUST NOT block the pipeline | Documentation drift is informational, not a release blocker |
| ALWAYS check for existing work before acting — all phases must be idempotent | Retries and re-runs must not produce duplicate tags, releases, or CHANGELOG entries |
| Full pipeline (CHANGELOG, GT, RTFM, Release) MUST only run for cycle-type PRs | Bugfix and other PRs get patch bump + tag only to avoid unnecessary processing |
<!-- @constraint-generated: end merge_constraints -->

## Safety Hooks (v1.37.0)

Defense-in-depth via Claude Code hooks. Active in ALL modes (interactive, autonomous, simstim).

| Hook | Event | Purpose |
|------|-------|---------|
| `block-destructive-bash.sh` | PreToolUse:Bash | Block `rm -rf`, force-push, reset --hard, clean -f |
| `team-role-guard.sh` | PreToolUse:Bash | Enforce lead-only ops in Agent Teams (no-op in single-agent) |
| `team-role-guard-write.sh` | PreToolUse:Write/Edit | Block teammate writes to System Zone, state files, and append-only files |
| `team-skill-guard.sh` | PreToolUse:Skill | Block lead-only skill invocations for teammates |
| `run-mode-stop-guard.sh` | Stop | Guard against premature exit during autonomous runs |
| `mutation-logger.sh` | PostToolUse:Bash | Log mutating commands to `.run/audit.jsonl` |
| `write-mutation-logger.sh` | PostToolUse:Write/Edit | Log Write/Edit file modifications to `.run/audit.jsonl` |

**Deny Rules**: `.claude/hooks/settings.deny.json` — blocks agent access to `~/.ssh/`, `~/.aws/`, `~/.kube/`, `~/.gnupg/`, credential stores.

**Reference**: `.claude/loa/reference/hooks-reference.md`

## Agent Teams Compatibility (v1.39.0)

When Claude Code Agent Teams (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`) is active, additional rules apply. Without Agent Teams, this section has no effect.

### Agent Teams Constraints

| Rule | Why |
|------|-----|
<!-- @constraint-generated: start agent_teams_constraints | hash:c020-teamcreate -->
<!-- DO NOT EDIT — generated from .claude/data/constraints.json -->
| MUST restrict planning skills to team lead only — teammates implement, review, and audit only | Planning skills assume single-writer semantics |
| MUST serialize all beads operations through team lead — teammates report via SendMessage | SQLite single-writer prevents lock contention |
| MUST only let team lead write to `.run/` state files — teammates report via SendMessage | Read-modify-write pattern prevents lost updates |
| MUST coordinate git commit/push through team lead — teammates report completed work via SendMessage | Git working tree and index are shared mutable state |
| MUST NOT modify .claude/ (System Zone) — framework files are lead-only, enforced by PreToolUse:Write/Edit hook | System Zone changes alter constraints/hooks for all agents |
<!-- @constraint-generated: end agent_teams_constraints -->

### Task Tracking in Agent Teams Mode

| Tool | Single-Agent Mode | Agent Teams Mode |
|------|------------------|------------------|
| `br` (beads) | Sprint lifecycle | Sprint lifecycle (lead ONLY) |
| `TaskCreate`/`TaskUpdate` | Session display only | Team coordination + session display |
| `SendMessage` | N/A | Teammate → lead status reports |
| `NOTES.md` | Observations | Observations (prefix with `[teammate-name]`) |

**Reference**: `.claude/loa/reference/agent-teams-reference.md`

## Conventions

- Never skip phases - each builds on previous
- Never edit `.claude/` directly
- Security first
