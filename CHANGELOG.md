# Changelog

All notable changes to Loa will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2025-12-19

### Added
- Initial release of Loa agent-driven development framework
- 8 specialized AI agents (the Loa):
  - **prd-architect** - Product requirements discovery and PRD creation
  - **architecture-designer** - System design and SDD creation
  - **sprint-planner** - Sprint planning and task breakdown
  - **sprint-task-implementer** - Implementation with feedback loops
  - **senior-tech-lead-reviewer** - Code review and quality gates
  - **devops-crypto-architect** - Production deployment and infrastructure
  - **paranoid-auditor** - Security and quality audits
  - **devrel-translator** - Technical to executive translation
- 10 slash commands for workflow orchestration:
  - `/plan-and-analyze` - PRD creation
  - `/architect` - SDD creation
  - `/sprint-plan` - Sprint planning
  - `/implement` - Sprint implementation
  - `/review-sprint` - Code review
  - `/audit-sprint` - Sprint security audit
  - `/deploy-production` - Production deployment
  - `/audit` - Codebase security audit
  - `/audit-deployment` - Deployment infrastructure audit
  - `/translate` - Executive translation
- Agent-to-Agent (A2A) communication system
- Dual quality gates (code review + security audit)
- Background execution mode for parallel agent runs
- MCP server integrations (Linear, GitHub, Vercel, Discord, web3-stats)
- `loa-grimoire/` directory for Loa process artifacts
- `app/` directory for generated application code
- Comprehensive documentation (PROCESS.md, CLAUDE.md)
- Secret scanning workflow (TruffleHog, GitLeaks)
- AGPL-3.0 licensing

### Directory Structure
```
app/                    # Application source code (generated)
loa-grimoire/           # Loa process artifacts
├── prd.md              # Product Requirements Document
├── sdd.md              # Software Design Document
├── sprint.md           # Sprint plan
├── a2a/                # Agent-to-agent communication
└── deployment/         # Production infrastructure docs
```

[0.1.0]: https://github.com/0xHoneyJar/loa/releases/tag/v0.1.0
