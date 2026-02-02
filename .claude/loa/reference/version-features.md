# Version Features Reference

Detailed documentation for version-specific features. For changelog, see `CHANGELOG.md`.

---

## v1.17.0 - Upstream Learning Flow

Enables users to contribute project learnings back to the Loa framework.

**Commands**: `/propose-learning`, post-retrospective hook

**Key Features**:
- Silent detection after `/retrospective`
- PII anonymization (API keys, JWT, private keys, DB creds)
- Weighted scoring: quality(25%) + effectiveness(30%) + novelty(25%) + generality(20%)
- 90-day cooldown for rejected proposals

---

## v1.15.1 - Two-Tier Learnings Architecture

Framework learnings ship with Loa, project learnings accumulate over time.

| Tier | Location | Weight |
|------|----------|--------|
| Framework | `.claude/loa/learnings/` | 1.0 |
| Project | `grimoires/loa/a2a/compound/` | 0.9 |

**40 Seeded Learnings**: patterns, anti-patterns, decisions, troubleshooting

---

## v1.15.0 - Projen-Style Ownership

Framework files use managed scaffolding with integrity markers.

**Key Features**:
- `_loa_marker` metadata in JSON/YAML
- `_loa_managed` comments in Markdown/scripts
- `/loa-eject` command for ownership transfer

---

## v1.14.0 - Skill Best Practices

Skills align with Vercel AI SDK and Anthropic tool-writing best practices.

**New Fields**: `inputExamples`, `effort_hint`, `danger_level`, `categories`

---

## v1.13.0 - Anthropic Context Features

**Effort Parameter**: Budget-controlled extended thinking
**Context Editing**: 84% token reduction in long sessions
**Memory Schema**: Cross-session knowledge persistence

See `.claude/loa/reference/context-engineering.md` for details.

---

## v1.11.0 - Autonomous Agent & Oracle

**Autonomous Agent**: 8-phase end-to-end workflow orchestration
**Oracle**: Extended with Loa compound learnings
**Smart Feedback Routing**: Auto-detect target repository
**WIP Branch Testing**: `/update-loa` checkout mode

---

## v1.10.0 - Compound Learning

Cross-session pattern detection and knowledge consolidation.

**Commands**: `/compound`, `/retrospective --batch`, `/skill-audit`

**Visual Communication**: Mermaid diagram rendering

---

## v1.9.0 - Claude Code 2.1.x Alignment

| Feature | Description |
|---------|-------------|
| Setup Hook | `claude --init` triggers health check |
| Skill Forking | `context: fork` for isolated execution |
| One-Time Hooks | `once: true` prevents duplicate runs |
| Session ID | Trajectory logs include `session_id` |

---

## v1.8.0 - Karpathy Principles

Four behavioral principles to counter LLM coding pitfalls:
1. Think Before Coding
2. Simplicity First
3. Surgical Changes
4. Goal-Driven

---

## v1.7.0 - Search Orchestration

`search-orchestrator.sh` provides ck-first semantic search with grep fallback.

---

## v1.6.0 - Automatic Codebase Grounding

`/plan-and-analyze` auto-detects brownfield projects and runs `/ride`.

**Detection**: >10 source files OR >500 lines of code

---

## v0.21.0 - Goal Traceability

Prevents silent goal failures with G-N IDs, Appendix C, and E2E validation.

---

## v0.20.0 - Recursive JIT Context

Context optimization for multi-subagent workflows:
- Semantic Cache
- Condensation
- Early-Exit coordination
- Semantic Recovery
