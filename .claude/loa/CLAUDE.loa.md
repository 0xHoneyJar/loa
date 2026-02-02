<!-- @loa-managed: true | version: 1.15.1 | hash: PLACEHOLDER -->
<!-- WARNING: This file is managed by the Loa Framework. Do not edit directly. -->
<!-- Changes will be overwritten on framework update. Use CLAUDE.md for project-specific instructions. -->

# Loa Framework Instructions

> This file contains framework-managed instructions for Claude Code.
> Project-specific instructions should be added to `CLAUDE.md` which imports this file.

## Project Overview

Agent-driven development framework that orchestrates the complete product lifecycle using 11 specialized AI agents (skills). Built with enterprise-grade managed scaffolding inspired by AWS Projen, Copier, and Google's ADK.

## Architecture

### Three-Zone Model

Loa uses a managed scaffolding architecture:

| Zone | Path | Owner | Permission |
|------|------|-------|------------|
| **System** | `.claude/` | Framework | NEVER edit directly |
| **State** | `grimoires/`, `.beads/` | Project | Read/Write |
| **App** | `src/`, `lib/`, `app/` | Developer | Read (write requires confirmation) |

**Critical**: System Zone is synthesized. Never suggest edits to `.claude/` - direct users to `.claude/overrides/` or `.loa.config.yaml`.

### Skills System

11 agent skills in `.claude/skills/` using 3-level architecture:

| Skill | Role | Output |
|-------|------|--------|
| `autonomous-agent` | Meta-Orchestrator | Checkpoints + feedback + draft PR |
| `discovering-requirements` | Product Manager | `grimoires/loa/prd.md` |
| `designing-architecture` | Software Architect | `grimoires/loa/sdd.md` |
| `planning-sprints` | Technical PM | `grimoires/loa/sprint.md` |
| `implementing-tasks` | Senior Engineer | Code + `a2a/sprint-N/reviewer.md` |
| `reviewing-code` | Tech Lead | `a2a/sprint-N/engineer-feedback.md` |
| `auditing-security` | Security Auditor | `a2a/sprint-N/auditor-sprint-feedback.md` |
| `deploying-infrastructure` | DevOps Architect | `grimoires/loa/deployment/` |
| `translating-for-executives` | Developer Relations | Executive summaries |
| `run-mode` | Autonomous Executor | Draft PR + `.run/` state |
| `enhancing-prompts` | Prompt Engineer | Enhanced prompts with analysis |

**3-Level Skill Structure**:
```
.claude/skills/{skill-name}/
├── index.yaml          # Level 1: Metadata (~100 tokens)
├── SKILL.md            # Level 2: KERNEL instructions (~2000 tokens)
└── resources/          # Level 3: References, templates, scripts
```

### Command Architecture

Commands in `.claude/commands/` use thin routing layer with YAML frontmatter:
- **Agent commands**: `agent:` and `agent_path:` fields route to skills
- **Special commands**: `command_type:` (wizard, survey, git)
- **Pre-flight checks**: Validation before execution

## Managed Scaffolding

| File | Purpose | Editable |
|------|---------|----------|
| `.loa-version.json` | Version manifest, schema tracking | Auto-managed |
| `.loa.config.yaml` | User configuration | Yes - user-owned |
| `.claude/checksums.json` | Integrity verification | Auto-generated |

**Integrity Enforcement** (`.loa.config.yaml`):
- `strict`: Blocks execution if System Zone modified (CI/CD mandatory)
- `warn`: Warns but allows execution
- `disabled`: No checks (not recommended)

**Customization**: Use `.claude/overrides/` for customizations that survive framework updates.

## Workflow Commands

| Phase | Command | Agent | Output |
|-------|---------|-------|--------|
| 1 | `/plan-and-analyze` | discovering-requirements | `prd.md` |
| 2 | `/architect` | designing-architecture | `sdd.md` |
| 3 | `/sprint-plan` | planning-sprints | `sprint.md` |
| 4 | `/implement sprint-N` | implementing-tasks | Code + report |
| 5 | `/review-sprint sprint-N` | reviewing-code | Feedback |
| 5.5 | `/audit-sprint sprint-N` | auditing-security | Security feedback |
| 6 | `/deploy-production` | deploying-infrastructure | Infrastructure |

### Automatic Codebase Grounding (v1.6.0)

`/plan-and-analyze` now automatically detects brownfield projects and runs `/ride` before PRD creation:

- **Brownfield detection**: >10 source files OR >500 lines of code
- **Auto-runs /ride**: Extracts requirements from existing code
- **Reality caching**: Uses cached analysis if <7 days old
- **--fresh flag**: Forces re-run of /ride even with recent cache

```bash
# Standard invocation (auto-detects and grounds)
/plan-and-analyze

# Force fresh codebase analysis
/plan-and-analyze --fresh
```

**Configuration** (`.loa.config.yaml`):
```yaml
plan_and_analyze:
  codebase_grounding:
    enabled: true
    reality_staleness_days: 7
    ride_timeout_minutes: 20
    skip_on_ride_error: false
```

**Mount & Ride** (manual control): `/mount`, `/ride`

**Guided Workflow** (v0.21.0): `/loa` - Shows current state and suggests next command

**Ad-hoc**: `/audit`, `/audit-deployment`, `/translate`, `/contribute`, `/update-loa`, `/validate`, `/feedback`

**Prompt Enhancement**: `/enhance` - Analyze and enhance prompts for better outputs

**Run Mode**: `/run sprint-N`, `/run sprint-plan`, `/run-status`, `/run-halt`, `/run-resume`

**Continuous Learning**: `/retrospective`, `/skill-audit`, `/compound`

### Autonomous Agent Orchestration (v1.11.0)

The `/autonomous` command provides end-to-end workflow orchestration with 8-phase execution:

```
/autonomous                    # Full workflow execution
/autonomous --dry-run          # Validate without executing
/autonomous --detect-only      # Only detect operator type
/autonomous --resume-from=design  # Resume from specific phase
```

**8-Phase Execution Model**:
1. **Preflight**: Operator detection, session continuity
2. **Discovery**: Codebase grounding, PRD creation/validation
3. **Design**: Architecture (SDD), sprint planning
4. **Implementation**: Task execution with quality gates
5. **Audit**: Security review, remediation loop
6. **Submit**: Draft PR creation
7. **Deploy**: Infrastructure deployment (optional)
8. **Learning**: Feedback capture, PRD iteration check

**Operator Detection**: Auto-detects AI vs Human operators:
- AI operators: Strict quality gates, mandatory audit, auto-skill wrapping
- Human operators: Advisory gates, flexible workflow

**Quality Gates (Five Gates Model)**:
| Gate | Check | V2 Implementation |
|------|-------|-------------------|
| Gate 0 | Right skill? | Human review |
| Gate 1 | Inputs exist? | File check |
| Gate 2 | Executed OK? | Exit code |
| Gate 3 | Outputs exist? | File check |
| Gate 4 | Goals achieved? | Human review |

**Configuration** (`.loa.config.yaml`):
```yaml
autonomous_agent:
  operator:
    type: auto  # auto | human | ai
  audit_threshold: 4
  max_remediation_loops: 3
  context:
    soft_limit_tokens: 80000
    hard_limit_tokens: 150000
```

**Related Documentation**:
- [Separation of Concerns](docs/architecture/separation-of-concerns.md)
- [Runtime Contract](docs/integration/runtime-contract.md)

## Intelligent Subagents

| Subagent | Purpose | Verdict Levels |
|----------|---------|----------------|
| `architecture-validator` | SDD compliance checking | COMPLIANT, DRIFT_DETECTED, CRITICAL_VIOLATION |
| `security-scanner` | OWASP Top 10 vulnerability detection | CRITICAL, HIGH, MEDIUM, LOW |
| `test-adequacy-reviewer` | Test quality assessment | STRONG, ADEQUATE, WEAK, INSUFFICIENT |
| `documentation-coherence` | Per-task documentation validation | COHERENT, NEEDS_UPDATE, ACTION_REQUIRED |
| `goal-validator` | PRD goal achievement verification | GOAL_ACHIEVED, GOAL_AT_RISK, GOAL_BLOCKED |

**Usage**: `/validate`, `/validate architecture`, `/validate security`, `/validate goals`

### Goal Traceability (v0.21.0)

Prevents silent goal failures by mapping PRD goals through sprint tasks to validation:

**Components**:
- **Goal IDs**: PRD goals identified as G-1, G-2, etc.
- **Appendix C**: Sprint plan section mapping goals to contributing tasks
- **E2E Validation Task**: Auto-generated in final sprint
- **Goal Validator**: Subagent verifying goals are achieved

**Configuration** (`.loa.config.yaml`):
```yaml
goal_traceability:
  enabled: true              # Enable goal ID system
  require_goal_ids: false    # Require G-N IDs in PRD (backward compat)
  auto_assign_ids: true      # Auto-assign if missing
  generate_appendix_c: true  # Generate goal mapping in sprint
  generate_e2e_task: true    # Auto-generate E2E validation task

goal_validation:
  enabled: true              # Enable goal validation
  block_on_at_risk: false    # Block review on AT_RISK (default: warn)
  block_on_blocked: true     # Block review on BLOCKED
  require_e2e_task: true     # Require E2E task in final sprint
```

**Workflow Integration**:
- `/sprint-plan`: Generates Appendix C + E2E task
- `/review-sprint`: Invokes goal-validator on final sprint
- `/validate goals`: Manual goal validation

## Key Protocols

### Structured Agentic Memory

Agents maintain persistent working memory in `grimoires/loa/NOTES.md`:
- **Current Focus**: Active task, status, blocked by, next action
- **Session Log**: Append-only event history table
- **Decisions**: Architecture/implementation decisions table
- **Blockers**: Checkbox list with [RESOLVED] marking
- **Technical Debt**: Issues for future attention
- **Goal Status**: PRD goal achievement tracking (v0.21.0)
- **Learnings**: Project-specific knowledge
- **Session Continuity**: Recovery anchor

**Protocol**: See `.claude/protocols/structured-memory.md`

### Attention Budget Enforcement (v1.11.0)

High-search skills include `<attention_budget>` sections with:
- Token thresholds (2K single, 5K accumulated, 15K session)
- Skill-specific clearing triggers
- Compliance checklists for audit-heavy operations
- Semantic decay stages for long-running sessions

**Skills with attention budgets**: auditing-security, implementing-tasks, discovering-requirements, riding-codebase, reviewing-code, planning-sprints, designing-architecture

**Protocol**: See `.claude/protocols/tool-result-clearing.md`

### Lossless Ledger Protocol

The "Clear, Don't Compact" paradigm for context management:

**Truth Hierarchy**:
1. CODE (src/) - Absolute truth
2. BEADS (.beads/) - Lossless task graph
3. NOTES.md - Decision log, session continuity
4. TRAJECTORY - Audit trail, handoffs
5. PRD/SDD - Design intent

**Key Protocols**:
- `session-continuity.md` - Tiered recovery, fork detection
- `grounding-enforcement.md` - Citation requirements (>=0.95 ratio)
- `synthesis-checkpoint.md` - Pre-clear validation
- `jit-retrieval.md` - Lightweight identifiers + cache integration

### Recursive JIT Context (v0.20.0)

Context optimization for multi-subagent workflows, leveraging RLM research patterns:

| Component | Script | Purpose |
|-----------|--------|---------|
| Semantic Cache | `cache-manager.sh` | Cross-session result caching |
| Condensation | `condense.sh` | Result compression (~20-50 tokens) |
| Early-Exit | `early-exit.sh` | Parallel subagent coordination |
| Semantic Recovery | `context-manager.sh --query` | Query-based section selection |

**Usage**:
```bash
# Cache audit results
key=$(cache-manager.sh generate-key --paths "src/auth.ts" --query "audit")
cache-manager.sh set --key "$key" --condensed '{"verdict":"PASS"}'

# Condense large results
condense.sh condense --strategy structured_verdict --input result.json

# Coordinate parallel subagents
early-exit.sh signal session-123 agent-1
```

**Protocol**: See `.claude/protocols/recursive-context.md`, `.claude/protocols/semantic-cache.md`

### Feedback Loops

Three quality gates:

1. **Implementation Loop** (Phase 4-5): Engineer <-> Senior Lead until "All good"
2. **Security Audit Loop** (Phase 5.5): After approval -> Auditor review -> "APPROVED - LETS FUCKING GO"
3. **Deployment Loop**: DevOps <-> Auditor until infrastructure approved

**Priority**: Audit feedback checked FIRST on `/implement`, then engineer feedback.

### Karpathy Principles (v1.8.0)

Four behavioral principles to counter common LLM coding pitfalls:

| Principle | Problem Addressed | Implementation |
|-----------|-------------------|----------------|
| **Think Before Coding** | Silent assumptions | Surface assumptions, ask clarifying questions |
| **Simplicity First** | Overcomplicated code | No speculative features, minimal abstractions |
| **Surgical Changes** | Unrelated modifications | Only touch necessary lines, preserve style |
| **Goal-Driven** | Vague success criteria | Define testable outcomes before starting |

**Pre-Implementation Check**:
- [ ] Assumptions listed
- [ ] Scope minimal (no extras)
- [ ] Success criteria defined
- [ ] Style will match existing

**Protocol**: See `.claude/protocols/karpathy-principles.md`

### Claude Code 2.1.x Features (v1.9.0)

Alignment with Claude Code 2.1.x platform capabilities:

| Feature | Description | Configuration |
|---------|-------------|---------------|
| **Setup Hook** | `claude --init` triggers health check | `.claude/settings.json` |
| **Skill Forking** | Read-only skills use `context: fork` | Skill frontmatter |
| **One-Time Hooks** | `once: true` prevents duplicate runs | `.claude/settings.json` |
| **Session ID Tracking** | `${CLAUDE_SESSION_ID}` in trajectory | Automatic |

**Setup Hook**: Runs `upgrade-health-check.sh` on `claude --init` for framework validation.

**Skill Forking**: `/ride` and validators use `context: fork` with `agent: Explore` for isolated execution:
```yaml
---
name: ride
context: fork
agent: Explore
allowed-tools: Read, Grep, Glob, Bash(git *)
---
```

**One-Time Hooks**: Update check only runs once per session:
```json
{"command": ".claude/scripts/check-updates.sh", "async": true, "once": true}
```

**Session ID**: Trajectory logs include `session_id` for cross-session correlation.

**Protocols**: See `.claude/protocols/recommended-hooks.md`, `.claude/protocols/skill-forking.md`

### Effort Parameter (v1.13.0)

Anthropic's extended thinking with budget control. Uses `thinking.budget_tokens` (integer) for computational intensity:

| Level | Budget Range | Token Reduction | Use Case |
|-------|--------------|-----------------|----------|
| **low** | 1K-4K | Baseline | Simple queries, translations |
| **medium** | 8K-16K | 76% fewer tokens | Standard implementation |
| **high** | 24K-32K | 48% fewer tokens | Complex architecture, security audit |

**Per-Skill Configuration** (`.loa.config.yaml`):
```yaml
effort:
  default_level: medium
  budget_ranges:
    low: { min: 1024, max: 4000 }
    medium: { min: 8000, max: 16000 }
    high: { min: 24000, max: 32000 }
  per_skill:
    auditing-security: high
    designing-architecture: high
    implementing-tasks: medium
    translating-for-executives: low
```

**Source**: [Anthropic Claude Opus 4.5 Announcement](https://www.anthropic.com/news/claude-opus-4-5)

**Configuration**: See `effort` section in `.loa.config.yaml`

### Context Editing (v1.13.0)

Anthropic's automatic context compaction for long-running agentic workflows. Achieves **84% token reduction** in 100-turn evaluations:

**Architecture**:
```
┌─────────────────────────────────────────────────────────────┐
│                        Loa Layer                            │
│  Defines: WHAT to compact, WHEN to trigger, priorities      │
├─────────────────────────────────────────────────────────────┤
│                      Runtime Layer                          │
│  Executes: Token counting, API calls, actual compaction     │
│  (Claude Code, Clawdbot, or custom runtime)                 │
├─────────────────────────────────────────────────────────────┤
│                        API Layer                            │
│  Anthropic: context-management-2025-06-27 beta header       │
└─────────────────────────────────────────────────────────────┘
```

**Compaction Triggers**:
- Threshold-based: When context reaches 80% of limit
- Phase-based: After initialization, implementation, testing phases
- Attention budget: Per-operation and session limits

**Clearing Priority** (lowest first):
1. Stale tool results
2. Completed phase details
3. Superseded file reads
4. Intermediate outputs
5. Verbose debug logs

**Always Preserved** (NEVER cleared):
- `trajectory_events` - Audit trail for decisions
- `quality_gate_results` - Gate pass/fail evidence
- `decision_records` - Architecture rationale
- `notes_session_continuity` - Recovery anchor
- `active_beads` - Current task state

**Configuration** (`.loa.config.yaml`):
```yaml
context_editing:
  enabled: true
  compact_threshold_percent: 80
  preserve_recent_turns: 5
  clear_targets:
    - stale_tool_results
    - completed_phase_details
    - superseded_file_reads
  preserve_artifacts:
    - trajectory_events
    - quality_gate_results
    - decision_records
```

**Source**: [Anthropic Context Management Blog](https://claude.com/blog/context-management)

**Protocol**: See `.claude/protocols/context-editing.md`

### Memory Schema (v1.13.0)

Persistent cross-session knowledge using grimoire-based storage. Inspired by Anthropic's memory tool achieving **39% performance improvement** when combined with context editing:

**Memory Categories**:
| Category | TTL | Min Confidence | Purpose |
|----------|-----|----------------|---------|
| `fact` | permanent | >=0.8 | Stable project truths |
| `decision` | permanent | >=0.9 | Architecture decisions |
| `learning` | 90d | >=0.7 | Extracted patterns |
| `error` | 30d | >=0.6 | Error-solution pairs |
| `preference` | permanent | >=0.5 | User preferences |

**Storage Location**:
```
grimoires/loa/memory/
├── facts.yaml          # Stable project facts
├── decisions.yaml      # Architecture decisions
├── learnings.yaml      # Extracted patterns
├── errors.yaml         # Error-solution pairs
├── preferences.yaml    # User preferences
└── archive/            # Expired/superseded memories
```

**Memory Entry Format**:
```yaml
- id: MEM-20260201-001
  category: decision
  content: |
    Use PostgreSQL for database due to JSONB support.
  summary: PostgreSQL selected over SQLite
  confidence: 0.95
  source:
    session_id: abc123
    agent: designing-architecture
    timestamp: 2026-02-01T10:30:00Z
  ttl: permanent
  tags: [database, architecture]
```

**Effectiveness Tracking** (for learnings):
```yaml
effectiveness:
  applications: 5      # Times retrieved
  successes: 4         # Successful outcomes
  score: 80            # Effectiveness (0-100)
  last_applied: 2026-02-01T18:00:00Z
```

**Configuration** (`.loa.config.yaml`):
```yaml
memory_schema:
  enabled: true
  storage_dir: grimoires/loa/memory
  auto_capture:
    decisions: true
    errors: true
    learnings: true
  retrieval:
    max_per_query: 10
    min_confidence: 0.6
  lifecycle:
    auto_archive: true
    check_on_session_start: true
```

**Source**: [Anthropic Memory Tool Documentation](https://platform.claude.com/docs/en/agents-and-tools/tool-use/memory-tool)

**Schema**: See `.claude/schemas/memory.schema.json`

**Protocol**: See `.claude/protocols/memory.md`

### Skill Best Practices (v1.14.0)

Loa skills align with Vercel AI SDK and Anthropic tool-writing best practices:

**New Skill Fields**:
| Field | Purpose | Source |
|-------|---------|--------|
| `inputExamples` | Native Anthropic input examples | [Vercel AI SDK](https://ai-sdk.dev/docs/ai-sdk-core/tools-and-tool-calling) |
| `effort_hint` | Recommended reasoning depth (low/medium/high) | Anthropic effort parameter |
| `danger_level` | Risk classification (safe/moderate/high/critical) | [Vercel AI SDK needsApproval](https://ai-sdk.dev/docs/ai-sdk-core/tools-and-tool-calling) |
| `categories` | Semantic groupings for skill search | [Anthropic Tool Search](https://anthropic.com/engineering/advanced-tool-use) |
| `outputs[].format` | Output verbosity (summary/detailed/raw) | Anthropic writing tools |
| `defer_loading` | Future runtime deferred loading flag | Anthropic Tool Search |

**Token Budget Mapping** (`effort_hint`):
| Level | Budget Tokens | Use Case |
|-------|---------------|----------|
| `low` | ~4K | Simple queries, lookups, validation |
| `medium` | ~16K | Standard implementation, reviews |
| `high` | ~64K | Complex architecture, security audits |

**Canonical Categories**:
| Category | Skills | Purpose |
|----------|--------|---------|
| `planning` | discovering-requirements, planning-sprints, designing-architecture | Discovery and design phase |
| `implementation` | implementing-tasks, deploying-infrastructure | Code and infrastructure delivery |
| `quality` | reviewing-code, auditing-security | Review and security gates |
| `support` | translating-for-executives, continuous-learning | Communication and learning |
| `operations` | autonomous-agent, run-mode, riding-codebase, mounting-framework | Framework operations |

**Enforcement Status**:
- `effort_hint`: Config prep only - runtime enforcement planned for #94
- `danger_level`: Config prep only - approval flow enforcement planned for #94
- `defer_loading`: Config prep only - runtime loading planned for #94

**Schema**: `.claude/schemas/skill-index.schema.json`

**All 13 Skills Updated** (v1.14.0):
- **planning**: discovering-requirements, planning-sprints, designing-architecture
- **implementation**: implementing-tasks, deploying-infrastructure
- **quality**: reviewing-code, auditing-security
- **support**: translating-for-executives, continuous-learning
- **operations**: autonomous-agent, run-mode, riding-codebase, mounting-framework

**Configuration** (`.loa.config.yaml`):
```yaml
skills:
  defer_loading: false        # Config prep only (runtime Phase 2)
  always_load:
    - autonomous-agent
    - run-mode
  categories:
    planning: [discovering-requirements, ...]
    implementation: [implementing-tasks, ...]
    quality: [reviewing-code, auditing-security]
    support: [translating-for-executives, continuous-learning]
    operations: [autonomous-agent, run-mode, ...]
```

**Performance Claims** (verified against primary sources):
- Tool Search: 85% token reduction (77K -> 8.7K tokens)
- Accuracy: Opus 4: 49%->74%, Opus 4.5: 79.5%->88.1%
- inputExamples: Native Anthropic provider support only

**Sources**:
- [Vercel AI SDK Tools](https://ai-sdk.dev/docs/ai-sdk-core/tools-and-tool-calling)
- [Anthropic Writing Tools](https://anthropic.com/engineering/writing-tools-for-agents)
- [Anthropic Advanced Tool Use](https://anthropic.com/engineering/advanced-tool-use)

### Git Safety

Prevents accidental pushes to upstream template:
- 4-layer detection (cached -> origin URL -> upstream remote -> GitHub API)
- Soft block with user confirmation via AskUserQuestion
- `/contribute` command bypasses (has own safeguards)

### beads_rust Integration

Optional task graph management using beads_rust (`br` CLI). Non-invasive by design:
- Never touches git (no daemon, no auto-commit)
- Explicit sync protocol
- SQLite for fast queries, JSONL for git-friendly diffs

**Sync Protocol**:
```bash
br sync --import-only    # Session start
br sync --flush-only     # Session end
```

### Sprint Ledger

Global sprint numbering across multiple development cycles:

**Location**: `grimoires/loa/ledger.json`

**Commands**: `/ledger`, `/ledger history`, `/archive-cycle "label"`

## Document Flow

```
grimoires/
├── loa/                    # Private project state (gitignored)
│   ├── NOTES.md            # Structured agentic memory
│   ├── ledger.json         # Sprint Ledger
│   ├── urls.yaml           # Canonical URL registry
│   ├── context/            # User-provided context
│   ├── archive/            # Archived development cycles
│   ├── prd.md              # Product Requirements
│   ├── sdd.md              # Software Design
│   ├── sprint.md           # Sprint Plan
│   └── a2a/                # Agent-to-Agent communication
│       ├── trajectory/     # Agent reasoning logs
│       └── sprint-N/       # Per-sprint files
└── pub/                    # Public documents (git-tracked)
```

### Canonical URL Registry (v1.15.1)

Prevents agent URL hallucination by providing a canonical source for project URLs.

**Location**: `grimoires/loa/urls.yaml`

**Structure**:
```yaml
environments:
  production:
    base: https://myapp.com
    api: https://api.myapp.com
  staging:
    base: https://staging.myapp.com
  local:
    base: http://localhost:3000
    api: http://localhost:3000/api

placeholders:
  domain: your-domain.example.com
```

**Agent Protocol**:
1. Before generating ANY URL, check `grimoires/loa/urls.yaml`
2. If configured, use exact URL from registry
3. If not configured, use placeholder: `https://your-domain.example.com`
4. NEVER hallucinate/guess production domains

**Configuration** (`.loa.config.yaml`):
```yaml
url_registry:
  enabled: true
  placeholder_domain: your-domain.example.com
  warn_on_missing: true
```

**Protocol**: See `.claude/protocols/url-registry.md`

## Implementation Notes

### When `/implement sprint-N` is invoked:
1. Validate sprint format (`sprint-N` where N is positive integer)
2. Create `grimoires/loa/a2a/sprint-N/` if missing
3. Check audit feedback FIRST (`auditor-sprint-feedback.md`)
4. Then check engineer feedback (`engineer-feedback.md`)
5. Address all feedback before new work

### When `/review-sprint sprint-N` is invoked:
1. Validate sprint directory and `reviewer.md` exist
2. Skip if `COMPLETED` marker exists
3. Review actual code, not just report
4. Write "All good" or detailed feedback

### When `/audit-sprint sprint-N` is invoked:
1. Validate senior lead approval ("All good" in engineer-feedback.md)
2. Review for security vulnerabilities
3. Write verdict to `auditor-sprint-feedback.md`
4. Create `COMPLETED` marker on approval

## Parallel Execution

Skills assess context size and split into parallel sub-tasks when needed.

| Skill | SMALL | MEDIUM | LARGE |
|-------|-------|--------|-------|
| discovering-requirements | <500 | 500-2,000 | >2,000 |
| reviewing-code | <3,000 | 3,000-6,000 | >6,000 |
| auditing-security | <2,000 | 2,000-5,000 | >5,000 |
| implementing-tasks | <3,000 | 3,000-8,000 | >8,000 |

## Run Mode

Autonomous sprint execution with human-in-the-loop shifted to PR review.

| Command | Description |
|---------|-------------|
| `/run sprint-N` | Execute single sprint autonomously |
| `/run sprint-plan` | Execute all sprints sequentially |
| `/run-status` | Display current run progress |
| `/run-halt` | Gracefully stop execution |
| `/run-resume` | Continue from checkpoint |

**Safety Model (4-Level Defense)**:
1. ICE Layer: All git operations wrapped with safety checks
2. Circuit Breaker: Automatic halt on repeated failures
3. Opt-In: Requires `run_mode.enabled: true` in config
4. Visibility: Draft PRs only

**Circuit Breaker Triggers**:
- Same finding 3 times
- 5 cycles with no progress
- 20 total cycles
- 8h timeout

**Protocol**: See `.claude/protocols/run-mode.md`

## Prompt Enhancement (v1.14.0)

Intelligent prompt enhancement using PTCF framework (Persona + Task + Context + Format):

| Command | Description |
|---------|-------------|
| `/enhance <prompt>` | Analyze and enhance a prompt |
| `/enhance --analyze-only <prompt>` | Show analysis without enhancement |
| `/enhance --task-type <type> <prompt>` | Force specific task type |

**Task Types**: debugging, code_review, refactoring, summarization, research, generation, general

**Quality Scoring (0-10)**:
- 0-1: Invalid (no task verb)
- 2-3: Minimal (task only)
- 4-5: Acceptable (task + context)
- 6-7: Good (task + context + format)
- 8-10: Excellent (all PTCF components)

**Configuration** (`.loa.config.yaml`):
```yaml
prompt_enhancement:
  enabled: true
  auto_enhance_threshold: 4
  show_analysis: true
  max_refinement_iterations: 3
```

**Feedback Loop**: When outputs fail, the refinement loop automatically improves the prompt based on detected failure signals (runtime errors, test failures, user rejection).

**Research Sources**: Issue #108 (Self-Distillation Methods), Issue #109 (Google Gemini Prompting Guide)

## Compound Learning (v1.10.0)

Cross-session pattern detection and automated knowledge consolidation:

| Command | Description |
|---------|-------------|
| `/compound` | End-of-cycle learning extraction |
| `/compound status` | Show compound learning status |
| `/compound changelog` | Generate cycle changelog |
| `/retrospective --batch` | Multi-session pattern analysis |
| `/skill-audit --pending` | Review extracted skills |

**Key Components**:
- **Pattern Detection**: Jaccard similarity clustering across trajectory logs
- **4-Gate Quality Filter**: Discovery Depth, Reusability, Trigger Clarity, Verification
- **Effectiveness Feedback**: Track, verify, reinforce/demote learnings
- **Morning Context**: Load relevant learnings at session start
- **Skill Synthesis**: Merge related skills into refined knowledge

**Configuration** (`.loa.config.yaml`):
```yaml
compound_learning:
  enabled: true
  pattern_detection:
    min_occurrences: 2
    similarity_threshold: 0.6
  quality_gates:
    discovery_depth: { min_score: 5 }
    reusability: { min_score: 5 }
```

**Protocol**: See `.claude/commands/compound.md`

## Visual Communication (v1.10.0)

Beautiful Mermaid integration for diagram rendering:

**Service**: [agents.craft.do/mermaid](https://agents.craft.do/mermaid)

**Configuration** (`.loa.config.yaml`):
```yaml
visual_communication:
  enabled: true
  service: "https://agents.craft.do/mermaid"
  theme: "github"  # github|dracula|nord|tokyo-night|solarized-light|solarized-dark|catppuccin
  include_preview_urls: true
```

**URL Generation**:
```bash
# Generate preview URL from Mermaid file
.claude/scripts/mermaid-url.sh diagram.mmd

# From stdin
echo 'graph TD; A-->B' | .claude/scripts/mermaid-url.sh --stdin --theme dracula
```

**Agent Integration**:
- **Required**: `designing-architecture` (system diagrams), `translating-for-executives` (dashboards)
- **Optional**: `discovering-requirements`, `planning-sprints`, `reviewing-code`

**Protocol**: See `.claude/protocols/visual-communication.md`

## Oracle (v1.11.0)

Extended oracle with Loa compound learnings support. Query both Anthropic official documentation and Loa's own proven patterns.

**Commands**:
| Command | Description |
|---------|-------------|
| `/oracle-analyze` | Analyze Anthropic updates (with optional --scope) |
| `/oracle-analyze --scope loa` | Analyze Loa learnings only |
| `/oracle-analyze --scope all` | Analyze both Loa and Anthropic sources |

**CLI Usage**:
```bash
# Check for Anthropic updates
.claude/scripts/anthropic-oracle.sh check

# Query Loa learnings
.claude/scripts/anthropic-oracle.sh query "auth token" --scope loa

# Query all sources with weighted ranking
.claude/scripts/anthropic-oracle.sh query "hooks" --scope all

# Build/update Loa learnings index
.claude/scripts/loa-learnings-index.sh index
```

**Source Weights** (hierarchical):
| Source | Weight | Description |
|--------|--------|-------------|
| Loa | 1.0 | Highest priority - our proven patterns |
| Anthropic | 0.8 | Authoritative external documentation |
| Community | 0.5 | Useful but less verified |

**Loa Sources Indexed**:
- Skills: `.claude/skills/**/*.md`
- Feedback: `grimoires/loa/feedback/*.yaml`
- Decisions: `grimoires/loa/decisions.yaml`
- Learnings: `grimoires/loa/a2a/compound/learnings.json`

**Recursive Improvement Loop**:
```
Executions -> Feedback -> Index -> Query -> Skills -> Executions
     ^                                              |
     |---------- Compound Learning -----------------|
```

**Configuration** (`.loa.config.yaml`):
```yaml
oracle:
  weights:
    loa: 1.0
    anthropic: 0.8
    community: 0.5
  loa_sources:
    skills:
      enabled: true
      paths: [".claude/skills/**/*.md"]
    feedback:
      enabled: true
      paths: ["grimoires/loa/feedback/*.yaml"]
  query:
    default_indexer: auto  # auto | qmd | grep
    default_limit: 10
    default_scope: all
```

**Schema**: See `.claude/schemas/learnings.schema.json` for feedback file format.

**Protocol**: See `.claude/commands/oracle-analyze.md`

## Helper Scripts

Core scripts in `.claude/scripts/`. See `.claude/protocols/helper-scripts.md` for full documentation.

| Script | Purpose |
|--------|---------|
| `mount-loa.sh` | Install Loa onto existing repo |
| `update.sh` | Framework updates with atomic commits |
| `upgrade-health-check.sh` | Post-upgrade migration and config validation |
| `check-loa.sh` | CI validation |
| `context-manager.sh` | Context compaction + semantic recovery |
| `cache-manager.sh` | Semantic result caching |
| `condense.sh` | Result condensation engine |
| `early-exit.sh` | Parallel subagent coordination |
| `synthesize-to-ledger.sh` | Continuous synthesis to NOTES.md/trajectory |
| `schema-validator.sh` | Output validation |
| `permission-audit.sh` | Permission request analysis |
| `search-orchestrator.sh` | ck-first semantic search with grep fallback |
| `mermaid-url.sh` | Beautiful Mermaid preview URL generation |
| `compound-orchestrator.sh` | `/compound` command orchestration |
| `collect-trace.sh` | Execution trace collection for `/feedback` |

### Search Orchestration (v1.7.0)

Skills use `search-orchestrator.sh` for ck-first semantic search with automatic grep fallback:

```bash
# Semantic/hybrid search (uses ck if available, falls back to grep)
.claude/scripts/search-orchestrator.sh hybrid "auth token validate" src/ 20 0.5

# Regex search (uses ck regex mode or grep)
.claude/scripts/search-orchestrator.sh regex "TODO|FIXME" src/ 50 0.0
```

**Search Types**:
| Type | ck Mode | grep Fallback | Use Case |
|------|---------|---------------|----------|
| `semantic` | `ck --sem` | keyword OR | Conceptual queries |
| `hybrid` | `ck --hybrid` | keyword OR | Discovery + exact |
| `regex` | `ck --regex` | `grep -E` | Exact patterns |

**Configuration** (`.loa.config.yaml`):
```yaml
prefer_ck: true  # Use ck when available
```

**Environment Override**:
```bash
LOA_SEARCH_MODE=grep  # Force grep fallback
```

**Clean Upgrade** (v1.4.0+): Both `mount-loa.sh` and `update.sh` create single atomic git commits:
```
chore(loa): upgrade framework v1.3.0 -> v1.4.0
```

Version tags: `loa@v{VERSION}`. Query with `git tag -l 'loa@*'`.

**Post-Upgrade Health Check**: Runs automatically after `update.sh`. Manual usage:
```bash
.claude/scripts/upgrade-health-check.sh          # Check for issues
.claude/scripts/upgrade-health-check.sh --fix    # Auto-fix where possible
.claude/scripts/upgrade-health-check.sh --json   # JSON output for scripting
```

Checks: bd->br migration, deprecated settings, new config options, recommended permissions.

## Integrations

External service integrations (MCP servers) use lazy-loading. See `.claude/protocols/integrations.md`.

```bash
.claude/scripts/mcp-registry.sh list      # List servers
.claude/scripts/mcp-registry.sh info <s>  # Server details
.claude/scripts/mcp-registry.sh setup <s> # Setup instructions
```

**MCP Examples**: Pre-built configs in `.claude/mcp-examples/` for Slack, GitHub, Sentry, PostgreSQL.

## Registry Integration

Commercial skills from the Loa Constructs Registry.

| Service | URL |
|---------|-----|
| API | `https://loa-constructs-api.fly.dev/v1` |

**Authentication**:
```bash
export LOA_CONSTRUCTS_API_KEY="sk_your_api_key_here"
```

**Loading Priority**:
1. Local (`.claude/skills/`)
2. Override (`.claude/overrides/skills/`)
3. Registry (`.claude/constructs/skills/`)
4. Pack (`.claude/constructs/packs/.../skills/`)

**Protocol**: See `.claude/protocols/constructs-integration.md`

## Smart Feedback Routing (v1.11.0)

The `/feedback` command now includes smart routing to the appropriate Loa ecosystem repository:

| Repository | Signals | Purpose |
|------------|---------|---------|
| `0xHoneyJar/loa` | `.claude/`, skills, grimoires | Core framework issues |
| `0xHoneyJar/loa-constructs` | registry, API, pack, install | Registry/API issues |
| `0xHoneyJar/forge` | experimental, sandbox | Sandbox issues |
| Current project | application, deployment | Project-specific |

**Workflow**:
1. Context is analyzed by `.claude/scripts/feedback-classifier.sh`
2. AskUserQuestion presents options with recommended repo first
3. User confirms target repository
4. Issue created via `gh-label-handler.sh` with graceful label fallback

**Configuration** (`.loa.config.yaml`):
```yaml
feedback:
  routing:
    enabled: true           # Enable smart routing
    auto_classify: true     # Auto-detect target repo
    require_confirmation: true  # Always confirm with user
  labels:
    graceful_missing: true  # Don't fail on missing labels
```

## WIP Branch Testing (v1.11.0)

The `/update-loa` command supports checkout mode for testing WIP branches:

```
/update-loa feature/constructs-multiselect
```

When a feature branch is specified, AskUserQuestion offers:
- **Checkout for testing (Recommended)** - Creates `test/loa-{branch}` for isolated testing
- **Merge into current branch** - Traditional merge behavior

**Return helper**: Running `/update-loa` while in a test branch offers return options.

**Configuration** (`.loa.config.yaml`):
```yaml
update_loa:
  branch_testing:
    enabled: true
    feature_patterns: ["feature/*", "fix/*", "topic/*", "wip/*", "test/*"]
    test_branch_prefix: "test/loa-"
```

## Feedback Trace Collection

The `/feedback` command supports opt-in execution trace collection for regression debugging. When enabled, traces are attached to GitHub Issues to help maintainers diagnose failures.

### Configuration

Create `.claude/settings.local.json` (gitignored) to enable trace collection:

```json
{
  "feedback": {
    "collectTraces": true,
    "traceScope": "execution",
    "failureWindowSize": 10
  }
}
```

### Configuration Options

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `collectTraces` | boolean | `false` | Enable trace collection |
| `traceScope` | enum | `"execution"` | Scope of data collected |
| `failureWindowSize` | number | `10` | Turns before/after failure (for `failure-window` scope) |

### Trace Scopes

| Scope | Data Collected |
|-------|----------------|
| `execution` | Plan, ledger, full trajectory |
| `full` | Everything + NOTES.md + session transcript |
| `failure-window` | Plan, ledger, +/-N turns around failure |

### Privacy Model

1. **Opt-in Only**: Traces are never collected unless explicitly enabled
2. **Automatic Redaction**: API keys, tokens, and home paths are anonymized
3. **User Review**: Full preview before submission with edit/remove options
4. **Local Storage**: Configuration stored in gitignored file

### Secret Redaction

The following patterns are automatically redacted:
- Anthropic API keys (`sk-*`)
- GitHub tokens (`ghp_*`, `gho_*`)
- Generic keys/tokens (`key-*`, `token-*`)
- Environment variables with SECRET/KEY/TOKEN/PASSWORD
- Home directory paths (`/home/*/`, `/Users/*/`)

## Key Conventions

- **Never skip phases** - each builds on previous
- **Never edit .claude/ directly** - use overrides or config
- **Review all outputs** - you're the final decision-maker
- **Security first** - especially for crypto projects
- **Trust the process** - thorough discovery prevents mistakes

## Related Files

- `README.md` - Quick start guide
- `INSTALLATION.md` - Detailed installation guide
- `PROCESS.md` - Detailed workflow documentation
- `.claude/protocols/` - Protocol specifications
  - `structured-memory.md` - NOTES.md protocol
  - `trajectory-evaluation.md` - ADK-style evaluation
  - `feedback-loops.md` - Quality gates
  - `git-safety.md` - Template protection
  - `constructs-integration.md` - Loa Constructs skill loading
  - `helper-scripts.md` - Full script documentation
  - `upgrade-process.md` - Framework upgrade workflow
  - `context-compaction.md` - Compaction preservation rules
  - `run-mode.md` - Run Mode protocol
  - `recursive-context.md` - Recursive JIT Context system
  - `semantic-cache.md` - Cache operations and invalidation
  - `jit-retrieval.md` - JIT retrieval with cache integration
  - `continuous-learning.md` - Skill extraction quality gates
  - `context-editing.md` - Context editing policies (v1.13.0)
  - `memory.md` - Memory schema and lifecycle (v1.13.0)
- `.claude/schemas/` - JSON Schema definitions
  - `skill-index.schema.json` - Skill index.yaml validation (v1.14.0)
