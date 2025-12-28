# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Project Overview

Agent-driven development framework that orchestrates the complete product lifecycle using 8 specialized AI agents (skills). Built with enterprise-grade managed scaffolding inspired by AWS Projen, Copier, and Google's ADK.

## Architecture

### Three-Zone Model

Loa uses a managed scaffolding architecture:

| Zone | Path | Owner | Permission |
|------|------|-------|------------|
| **System** | `.claude/` | Framework | NEVER edit directly |
| **State** | `loa-grimoire/`, `.beads/` | Project | Read/Write |
| **App** | `src/`, `lib/`, `app/` | Developer | Read (write requires confirmation) |

**Critical**: System Zone is synthesized. Never suggest edits to `.claude/` - direct users to `.claude/overrides/` or `.loa.config.yaml`.

### Skills System

8 agent skills in `.claude/skills/` using 3-level architecture:

| Skill | Role | Output |
|-------|------|--------|
| `discovering-requirements` | Product Manager | `loa-grimoire/prd.md` |
| `designing-architecture` | Software Architect | `loa-grimoire/sdd.md` |
| `planning-sprints` | Technical PM | `loa-grimoire/sprint.md` |
| `implementing-tasks` | Senior Engineer | Code + `a2a/sprint-N/reviewer.md` |
| `reviewing-code` | Tech Lead | `a2a/sprint-N/engineer-feedback.md` |
| `auditing-security` | Security Auditor | `SECURITY-AUDIT-REPORT.md` or `a2a/sprint-N/auditor-sprint-feedback.md` |
| `deploying-infrastructure` | DevOps Architect | `loa-grimoire/deployment/` |
| `translating-for-executives` | Developer Relations | Executive summaries |

### 3-Level Skill Structure

```
.claude/skills/{skill-name}/
├── index.yaml          # Level 1: Metadata (~100 tokens)
├── SKILL.md            # Level 2: KERNEL instructions (~2000 tokens)
└── resources/          # Level 3: References, templates, scripts
```

### Command Architecture (v4)

Commands in `.claude/commands/` use thin routing layer with YAML frontmatter:

- **Agent commands**: `agent:` and `agent_path:` fields route to skills
- **Special commands**: `command_type:` (wizard, survey, git)
- **Pre-flight checks**: Validation before execution
- **Context files**: Prioritized loading with variable substitution

## Managed Scaffolding

### Configuration Files

| File | Purpose | Editable |
|------|---------|----------|
| `.loa-version.json` | Version manifest, schema tracking | Auto-managed |
| `.loa.config.yaml` | User configuration | Yes - user-owned |
| `.claude/checksums.json` | Integrity verification | Auto-generated |

### Integrity Enforcement

```yaml
# .loa.config.yaml
integrity_enforcement: strict  # strict | warn | disabled
```

- **strict**: Blocks execution if System Zone modified (CI/CD mandatory)
- **warn**: Warns but allows execution
- **disabled**: No checks (not recommended)

### Customization via Overrides

```
.claude/overrides/
├── skills/
│   └── implementing-tasks/
│       └── SKILL.md          # Custom skill instructions
└── commands/
    └── my-command.md         # Custom command
```

Overrides survive framework updates.

## Workflow Commands

| Phase | Command | Agent | Output |
|-------|---------|-------|--------|
| 0 | `/setup` | wizard | `.loa-setup-complete` |
| 1 | `/plan-and-analyze` | discovering-requirements | `prd.md` |
| 2 | `/architect` | designing-architecture | `sdd.md` |
| 3 | `/sprint-plan` | planning-sprints | `sprint.md` |
| 4 | `/implement sprint-N` | implementing-tasks | Code + report |
| 5 | `/review-sprint sprint-N` | reviewing-code | Feedback |
| 5.5 | `/audit-sprint sprint-N` | auditing-security | Security feedback |
| 6 | `/deploy-production` | deploying-infrastructure | Infrastructure |

**Mount & Ride** (existing codebases): `/mount`, `/ride`

**Ad-hoc**: `/audit`, `/audit-deployment`, `/translate @doc for audience`, `/contribute`, `/update`, `/feedback` (THJ only), `/config` (THJ only)

**Execution modes**: Foreground (default) or background (`/implement sprint-1 background`)

## HivemindOS Integration

Loa can integrate with HivemindOS for organizational memory access.

### Detection

Integration is detected via:
1. `HIVEMIND_PATH` environment variable pointing to valid HivemindOS installation
2. Running within HivemindOS repository (presence of `library/` and `laboratory/` directories)

### Mode Detection Script

```bash
.claude/scripts/detect-mode.sh
# Returns: "standalone" or "integrated"
```

### Session State Coexistence

When integrated, two session files work together:
- `.claude/.session` - HivemindOS database state (WHAT you're working on)
- `.loa/.session` - Loa frame state (HOW you're working)

### Merged Status Line

Integrated mode shows both contexts:
```
⬢ HIVEMINDOS 🔬LAB · ◆ BUILD · context · Opus
```

### Configuration

Integration state stored in `.loa.config.yaml`:
```yaml
hivemind_integration: true
hivemind_path: "/path/to/hivemind-os"
```

### Setup Enhancement

During `/setup`, if HivemindOS is available:
1. User is prompted to enable integration
2. Hooks are merged (HivemindOS first, then Loa)
3. Merged status line is installed
4. Configuration is recorded

**Protocol**: See `.claude/protocols/integration-config.md`

## Frame System (v5.0.0)

Loa uses invisible context-switching through frames. The agent adapts to what you're doing without explicit mode selection.

### Frames

| Frame | Symbol | When Active | Status Line |
|-------|--------|-------------|-------------|
| **SEARCH** | ◇ | Exploring, planning, analyzing | `◇ SEARCH · context · status` |
| **BUILD** | ◆ | Implementing, coding, fixing | `◆ BUILD · context · status` |
| **TUNE** | ◈ | Refining, adjusting, taste-checking | `◈ TUNE · context · status` |

### Frame Detection

Frames are inferred from:
1. **Commands**: `/plan-and-analyze` → SEARCH, `/implement` → BUILD, `/taste` → TUNE
2. **Action phrases**: "explore" → SEARCH, "build" → BUILD, "adjust" → TUNE
3. **Default**: SEARCH

### Micro-Transitions

Brief contextual shifts within a frame:
```
User (in BUILD): "that feels too fast"
Agent: [◈ micro-tune] Adjusting tension to 120...
       [◆ BUILD] Continuing implementation...
```

### Security Constraints

When touching `*.sol`, `*.move`, `/contracts/`, `/treasury/`:
- Status line shows 🔒 indicator
- Agent applies elevated caution
- Extra validation prompts

### Session State

Runtime state stored in `.loa/.session`:
```yaml
frame: build
context: "JoyfulLoader"
status: implementing
constraints:
  security: true
```

**Protocols**: See `.claude/protocols/frames.md`, `session-state.md`, `micro-transitions.md`, `security-constraints.md`

---

## Key Protocols

### Structured Agentic Memory

Agents maintain persistent working memory in `loa-grimoire/NOTES.md`:

```markdown
## Active Sub-Goals
## Discovered Technical Debt
## Blockers & Dependencies
## Session Continuity
## Decision Log
```

**Protocol**: See `.claude/protocols/structured-memory.md`

- Read NOTES.md on session start
- Log decisions during execution
- Summarize before compaction/session end
- Apply Tool Result Clearing after heavy operations

### Lossless Ledger Protocol (v0.9.0)

The "Clear, Don't Compact" paradigm for context management:

**Truth Hierarchy**:
1. CODE (src/) - Absolute truth
2. BEADS (.beads/) - Lossless task graph
3. NOTES.md - Decision log, session continuity
4. TRAJECTORY - Audit trail, handoffs
5. PRD/SDD - Design intent
6. CONTEXT WINDOW - Transient, never authoritative

**Key Protocols**:
- `session-continuity.md` - Tiered recovery, fork detection
- `grounding-enforcement.md` - Citation requirements (>=0.95 ratio)
- `synthesis-checkpoint.md` - Pre-clear validation (7 steps)
- `jit-retrieval.md` - Lightweight identifiers (97% token reduction)
- `attention-budget.md` - Advisory thresholds

**Key Scripts**:
- `grounding-check.sh` - Calculate grounding ratio
- `synthesis-checkpoint.sh` - Run pre-clear validation
- `self-heal-state.sh` - State Zone recovery

**Configuration** (`.loa.config.yaml`):
```yaml
grounding:
  threshold: 0.95
  enforcement: warn  # strict | warn | disabled
attention_budget:
  yellow_threshold: 5000  # Trigger delta-synthesis
session_continuity:
  tiered_recovery: true
```

### Trajectory Evaluation (ADK-Level)

Agents log reasoning to `loa-grimoire/a2a/trajectory/{agent}-{date}.jsonl`:

```json
{"timestamp": "...", "agent": "...", "action": "...", "reasoning": "...", "grounding": {...}}
```

**Grounding types**:
- `citation`: Direct quote from docs
- `code_reference`: Reference to existing code
- `assumption`: Ungrounded claim (must flag)
- `user_input`: Based on user request

**Protocol**: See `.claude/protocols/trajectory-evaluation.md`

### Feedback Loops

Three quality gates - see `.claude/protocols/feedback-loops.md`:

1. **Implementation Loop** (Phase 4-5): Engineer <-> Senior Lead until "All good"
2. **Security Audit Loop** (Phase 5.5): After approval -> Auditor review -> "APPROVED - LETS FUCKING GO" or "CHANGES_REQUIRED"
3. **Deployment Loop**: DevOps <-> Auditor until infrastructure approved

**Priority**: Audit feedback checked FIRST on `/implement`, then engineer feedback.

**Sprint completion marker**: `loa-grimoire/a2a/sprint-N/COMPLETED` created on security approval.

### Git Safety

Prevents accidental pushes to upstream template - see `.claude/protocols/git-safety.md`:

- 4-layer detection (cached -> origin URL -> upstream remote -> GitHub API)
- Soft block with user confirmation via AskUserQuestion
- `/contribute` command bypasses (has own safeguards)

### Analytics (THJ Only)

Tracks usage for THJ developers - see `.claude/protocols/analytics.md`:

- Stored in `loa-grimoire/analytics/usage.json`
- OSS users have no analytics tracking
- Opt-in sharing via `/feedback`

## Document Flow

```
loa-grimoire/
├── NOTES.md            # Structured agentic memory
├── context/            # User-provided context (pre-discovery)
├── reality/            # Code extraction (/ride output)
├── legacy/             # Legacy doc inventory (/ride output)
├── prd.md              # Product Requirements
├── sdd.md              # Software Design
├── sprint.md           # Sprint Plan
├── drift-report.md     # Code vs docs drift (/ride output)
├── a2a/                # Agent-to-Agent communication
│   ├── index.md        # Audit trail index
│   ├── trajectory/     # Agent reasoning logs
│   ├── sprint-N/       # Per-sprint files
│   │   ├── reviewer.md
│   │   ├── engineer-feedback.md
│   │   ├── auditor-sprint-feedback.md
│   │   └── COMPLETED
│   ├── deployment-report.md
│   └── deployment-feedback.md
├── analytics/          # THJ only
└── deployment/         # Production docs
```

## Implementation Notes

### When `/implement sprint-N` is invoked:
1. Validate sprint format (`sprint-N` where N is positive integer)
2. Create `loa-grimoire/a2a/sprint-N/` if missing
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

**Thresholds** (lines):

| Skill | SMALL | MEDIUM | LARGE |
|-------|-------|--------|-------|
| discovering-requirements | <500 | 500-2,000 | >2,000 |
| reviewing-code | <3,000 | 3,000-6,000 | >6,000 |
| auditing-security | <2,000 | 2,000-5,000 | >5,000 |
| implementing-tasks | <3,000 | 3,000-8,000 | >8,000 |
| deploying-infrastructure | <2,000 | 2,000-5,000 | >5,000 |

Use `.claude/scripts/context-check.sh` for assessment.

## Helper Scripts

```
.claude/scripts/
├── mount-loa.sh              # One-command install onto existing repo
├── update.sh                 # Framework updates with migration gates
├── check-loa.sh              # CI validation script
├── detect-drift.sh           # Code vs docs drift detection
├── validate-change-plan.sh   # Pre-implementation validation
├── analytics.sh              # Analytics functions (THJ only)
├── check-beads.sh            # Beads (bd CLI) availability check
├── git-safety.sh             # Template detection
├── context-check.sh          # Parallel execution assessment
├── preflight.sh              # Pre-flight validation
├── assess-discovery-context.sh  # PRD context ingestion
├── check-feedback-status.sh  # Sprint feedback state
├── check-prerequisites.sh    # Phase prerequisites
├── validate-sprint-id.sh     # Sprint ID validation
├── mcp-registry.sh           # MCP registry queries
├── validate-mcp.sh           # MCP configuration validation
├── detect-mode.sh            # HivemindOS integration detection
├── merge-hooks.sh            # Merge Loa hooks into existing settings
└── install-hooks.sh          # Install Loa hooks to target project
```

## Integrations

External service integrations (MCP servers) use lazy-loading - see `.claude/protocols/integrations.md`.

**Registry**: `.claude/mcp-registry.yaml` (loaded only when needed)

**Requires**: `yq` for YAML parsing (`brew install yq` / `apt install yq`)

```bash
.claude/scripts/mcp-registry.sh list      # List servers
.claude/scripts/mcp-registry.sh info <s>  # Server details
.claude/scripts/mcp-registry.sh setup <s> # Setup instructions
.claude/scripts/validate-mcp.sh <s>       # Check if configured
```

Skills declare integrations in their `index.yaml`:
```yaml
integrations:
  required: []
  optional:
    - name: "linear"
      reason: "Sync tasks to Linear"
      fallback: "Tasks remain local"
```

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
  - `change-validation.md` - Pre-implementation validation
  - **v0.9.0 Lossless Ledger Protocol**:
  - `session-continuity.md` - Session lifecycle and recovery
  - `grounding-enforcement.md` - Citation requirements
  - `synthesis-checkpoint.md` - Pre-clear validation
  - `jit-retrieval.md` - Lightweight identifiers
  - `attention-budget.md` - Token thresholds
- `.claude/scripts/` - Helper bash scripts
  - **v0.9.0 Scripts**:
  - `grounding-check.sh` - Grounding ratio calculation
  - `synthesis-checkpoint.sh` - Pre-clear validation
  - `self-heal-state.sh` - State Zone recovery
  - **v5.0.0 HivemindOS Integration**:
  - `detect-mode.sh` - Integration detection
  - `merge-hooks.sh` - Hook merging
  - `install-hooks.sh` - Hook installation
- `.claude/protocols/integration-config.md` - HivemindOS integration configuration
