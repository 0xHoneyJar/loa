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

**Ad-hoc**: `/audit`, `/audit-deployment`, `/translate @doc for audience`, `/contribute`, `/update`, `/feedback` (THJ only), `/config` (THJ only)

**Execution modes**: Foreground (default) or background (`/implement sprint-1 background`)

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
├── context/            # Pre-discovery documentation (optional)
├── prd.md              # Product Requirements
├── sdd.md              # Software Design
├── sprint.md           # Sprint Plan
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
└── validate-mcp.sh           # MCP configuration validation
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
- `.claude/scripts/` - Helper bash scripts
