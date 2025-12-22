# Loa

[![Version](https://img.shields.io/badge/version-0.4.0-blue.svg)](CHANGELOG.md)
[![License](https://img.shields.io/badge/license-AGPL--3.0-green.svg)](LICENSE.md)

> *"The Loa are pragmatic entities... They're not worshipped for salvation—they're worked with for practical results."*

Agent-driven development framework using 8 specialized AI agents to orchestrate the complete product lifecycle—from requirements through production deployment.

## Quick Start

```bash
# 1. Clone and enter
git clone https://github.com/0xHoneyJar/loa.git && cd loa

# 2. Start Claude Code
claude

# 3. Run setup
/setup

# 4. Begin workflow
/plan-and-analyze
```

## The Workflow

| Phase | Command | Agent | Output |
|-------|---------|-------|--------|
| 0 | `/setup` | - | `.loa-setup-complete` |
| 1 | `/plan-and-analyze` | discovering-requirements | `loa-grimoire/prd.md` |
| 2 | `/architect` | designing-architecture | `loa-grimoire/sdd.md` |
| 3 | `/sprint-plan` | planning-sprints | `loa-grimoire/sprint.md` |
| 4 | `/implement sprint-N` | implementing-tasks | Code + report |
| 5 | `/review-sprint sprint-N` | reviewing-code | Approval/feedback |
| 5.5 | `/audit-sprint sprint-N` | auditing-security | Security approval |
| 6 | `/deploy-production` | deploying-infrastructure | Infrastructure |

### Ad-Hoc Commands

| Command | Purpose |
|---------|---------|
| `/audit` | Full codebase security audit |
| `/audit-deployment` | Infrastructure security review |
| `/translate @doc for audience` | Executive summaries |
| `/update` | Pull framework updates |
| `/contribute` | Create upstream PR |
| `/feedback` | Submit feedback (THJ only) |
| `/config` | Reconfigure MCP (THJ only) |

## The Agents (The Loa)

Eight specialized agents that ride alongside you:

1. **discovering-requirements** - Senior Product Manager
2. **designing-architecture** - Software Architect
3. **planning-sprints** - Technical PM
4. **implementing-tasks** - Senior Engineer
5. **reviewing-code** - Tech Lead
6. **deploying-infrastructure** - DevOps Architect
7. **auditing-security** - Security Auditor
8. **translating-for-executives** - Developer Relations

Each skill in `.claude/skills/{agent}/` with 3-level architecture:
- `index.yaml` - Metadata
- `SKILL.md` - KERNEL instructions
- `resources/` - Templates, scripts, references

## Key Features

### Two Quality Gates

1. **Code Review**: Tech lead reviews until "All good"
2. **Security Audit**: Auditor reviews until "APPROVED - LETS FUCKING GO"

### Feedback-Driven Development

```
/implement → /review-sprint → (feedback loop) → /audit-sprint → (security loop) → COMPLETED
```

### User Types

- **THJ developers**: Full analytics, MCP config, `/feedback`, `/config`
- **OSS users**: Streamlined experience, no analytics, core workflow access

## Repository Structure

```
.claude/
├── skills/           # Agent skills (3-level architecture)
├── commands/         # Slash commands (v4 thin routing)
├── protocols/        # Git safety, analytics, feedback loops
├── scripts/          # Helper bash scripts
└── settings.local.json

loa-grimoire/
├── context/                      # Pre-discovery docs (optional)
├── prd.md, sdd.md, sprint.md    # Planning docs
├── a2a/                          # Agent communication
│   └── sprint-N/                 # Per-sprint feedback
├── analytics/                    # THJ only
└── deployment/                   # Infrastructure docs
```

## Example Session

```bash
/setup                    # First-time config
/plan-and-analyze         # Define requirements
/architect                # Design architecture
/sprint-plan              # Plan sprints

# For each sprint:
/implement sprint-1       # Implement
/review-sprint sprint-1   # Code review
/implement sprint-1       # Fix feedback (if needed)
/audit-sprint sprint-1    # Security audit
/implement sprint-1       # Fix security issues (if needed)

# When all sprints complete:
/audit                    # Full security audit
/deploy-production        # Deploy
/feedback                 # Share experience (THJ only)
```

## Documentation

- **[PROCESS.md](PROCESS.md)** - Detailed workflow documentation
- **[CLAUDE.md](CLAUDE.md)** - Claude Code guidance
- **[CHANGELOG.md](CHANGELOG.md)** - Version history

## Why "Loa"?

In William Gibson's Sprawl trilogy, Loa are AI entities that "ride" humans through neural interfaces, guiding them through cyberspace. These agents don't replace you—they **ride with you**, channeling expertise through the interface.

## License

[AGPL-3.0](LICENSE.md) - You can use, modify, and distribute. If you deploy modifications (including as a network service), you must release source code.

## Links

- [Claude Code](https://claude.ai/code)
- [Repository](https://github.com/0xHoneyJar/loa)
- [Issues](https://github.com/0xHoneyJar/loa/issues)
