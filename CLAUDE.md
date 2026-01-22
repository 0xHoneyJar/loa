# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Project Overview

Agent-driven development framework that orchestrates the complete product lifecycle using 9 specialized AI agents (skills). Built with enterprise-grade managed scaffolding inspired by AWS Projen, Copier, and Google's ADK.

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

9 agent skills in `.claude/skills/` using 3-level architecture:

| Skill | Role | Output |
|-------|------|--------|
| `discovering-requirements` | Product Manager | `grimoires/loa/prd.md` |
| `designing-architecture` | Software Architect | `grimoires/loa/sdd.md` |
| `planning-sprints` | Technical PM | `grimoires/loa/sprint.md` |
| `implementing-tasks` | Senior Engineer | Code + `a2a/sprint-N/reviewer.md` |
| `reviewing-code` | Tech Lead | `a2a/sprint-N/engineer-feedback.md` |
| `auditing-security` | Security Auditor | `a2a/sprint-N/auditor-sprint-feedback.md` |
| `deploying-infrastructure` | DevOps Architect | `grimoires/loa/deployment/` |
| `translating-for-executives` | Developer Relations | Executive summaries |
| `run-mode` | Autonomous Executor | Draft PR + `.run/` state |

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

**Mount & Ride** (existing codebases): `/mount`, `/ride`

**Ad-hoc**: `/audit`, `/audit-deployment`, `/translate`, `/contribute`, `/update-loa`, `/validate`

**Run Mode**: `/run sprint-N`, `/run sprint-plan`, `/run-status`, `/run-halt`, `/run-resume`

**Continuous Learning**: `/retrospective`, `/skill-audit`

## Intelligent Subagents

| Subagent | Purpose | Verdict Levels |
|----------|---------|----------------|
| `architecture-validator` | SDD compliance checking | COMPLIANT, DRIFT_DETECTED, CRITICAL_VIOLATION |
| `security-scanner` | OWASP Top 10 vulnerability detection | CRITICAL, HIGH, MEDIUM, LOW |
| `test-adequacy-reviewer` | Test quality assessment | STRONG, ADEQUATE, WEAK, INSUFFICIENT |
| `documentation-coherence` | Per-task documentation validation | COHERENT, NEEDS_UPDATE, ACTION_REQUIRED |

**Usage**: `/validate`, `/validate architecture`, `/validate security`

## Key Protocols

### Structured Agentic Memory

Agents maintain persistent working memory in `grimoires/loa/NOTES.md`:
- **Current Focus**: Active task, status, blocked by, next action
- **Session Log**: Append-only event history table
- **Decisions**: Architecture/implementation decisions table
- **Blockers**: Checkbox list with [RESOLVED] marking
- **Technical Debt**: Issues for future attention
- **Learnings**: Project-specific knowledge
- **Session Continuity**: Recovery anchor

**Protocol**: See `.claude/protocols/structured-memory.md`

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

Checks: bd→br migration, deprecated settings, new config options, recommended permissions.

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
