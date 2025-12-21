# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Project Overview

Agent-driven development framework that orchestrates the complete product lifecycle using 8 specialized AI agents (skills). Designed for crypto/blockchain but applicable to any software project.

## Architecture

### Skills System

8 agent skills in `.claude/skills/` using 3-level architecture:

| Skill | Role | Output |
|-------|------|--------|
| `prd-architect` | Product Manager | `loa-grimoire/prd.md` |
| `architecture-designer` | Software Architect | `loa-grimoire/sdd.md` |
| `sprint-planner` | Technical PM | `loa-grimoire/sprint.md` |
| `sprint-task-implementer` | Senior Engineer | Code + `a2a/sprint-N/reviewer.md` |
| `senior-tech-lead-reviewer` | Tech Lead | `a2a/sprint-N/engineer-feedback.md` |
| `paranoid-auditor` | Security Auditor | `SECURITY-AUDIT-REPORT.md` or `a2a/sprint-N/auditor-sprint-feedback.md` |
| `devops-crypto-architect` | DevOps Architect | `loa-grimoire/deployment/` |
| `devrel-translator` | Developer Relations | Executive summaries |

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

## Workflow Commands

| Phase | Command | Agent | Output |
|-------|---------|-------|--------|
| 0 | `/setup` | wizard | `.loa-setup-complete` |
| 1 | `/plan-and-analyze` | prd-architect | `prd.md` |
| 2 | `/architect` | architecture-designer | `sdd.md` |
| 3 | `/sprint-plan` | sprint-planner | `sprint.md` |
| 4 | `/implement sprint-N` | sprint-task-implementer | Code + report |
| 5 | `/review-sprint sprint-N` | senior-tech-lead-reviewer | Feedback |
| 5.5 | `/audit-sprint sprint-N` | paranoid-auditor | Security feedback |
| 6 | `/deploy-production` | devops-crypto-architect | Infrastructure |

**Ad-hoc**: `/audit`, `/audit-deployment`, `/translate @doc for audience`, `/contribute`, `/update`, `/feedback` (THJ only), `/config` (THJ only)

**Execution modes**: Foreground (default) or background (`/implement sprint-1 background`)

## Key Protocols

### Feedback Loops

Three quality gates - see `.claude/protocols/feedback-loops.md` for details:

1. **Implementation Loop** (Phase 4-5): Engineer ↔ Senior Lead until "All good"
2. **Security Audit Loop** (Phase 5.5): After approval → Auditor review → "APPROVED - LETS FUCKING GO" or "CHANGES_REQUIRED"
3. **Deployment Loop**: DevOps ↔ Auditor until infrastructure approved

**Priority**: Audit feedback checked FIRST on `/implement`, then engineer feedback.

**Sprint completion marker**: `loa-grimoire/a2a/sprint-N/COMPLETED` created on security approval.

### Git Safety

Prevents accidental pushes to upstream template - see `.claude/protocols/git-safety.md`:

- 4-layer detection (cached → origin URL → upstream remote → GitHub API)
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
├── prd.md              # Product Requirements
├── sdd.md              # Software Design
├── sprint.md           # Sprint Plan
├── a2a/                # Agent-to-Agent communication
│   ├── index.md        # Audit trail index
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
| senior-tech-lead-reviewer | <3,000 | 3,000-6,000 | >6,000 |
| paranoid-auditor | <2,000 | 2,000-5,000 | >5,000 |
| sprint-task-implementer | <3,000 | 3,000-8,000 | >8,000 |
| devops-crypto-architect | <2,000 | 2,000-5,000 | >5,000 |

Use `.claude/scripts/context-check.sh` for assessment.

## Helper Scripts

```
.claude/scripts/
├── analytics.sh      # Analytics functions
├── git-safety.sh     # Template detection
├── context-check.sh  # Parallel execution assessment
└── preflight.sh      # Pre-flight validation
```

## MCP Integrations

Pre-configured servers in `.claude/settings.local.json`:
- **linear** - Feedback tracking
- **github** - Repository operations
- **vercel** - Deployment
- **discord** - Communication
- **web3-stats** - Blockchain data

## Key Conventions

- **Never skip phases** - each builds on previous
- **Review all outputs** - you're the final decision-maker
- **Security first** - especially for crypto projects
- **Trust the process** - thorough discovery prevents mistakes

## Related Files

- `README.md` - Quick start guide
- `PROCESS.md` - Detailed workflow documentation
- `.claude/protocols/` - Detailed protocol specifications
- `.claude/scripts/` - Helper bash scripts
