# Agent Working Memory (NOTES.md)

> This file persists agent context across sessions and compaction cycles.
> Updated automatically by agents. Manual edits are preserved.

## Active Sub-Goals
<!-- Current objectives being pursued -->

**v0.9.0 Sprint 1 Complete - Foundation & Core Protocols**
- Sprint 1 implementation complete (6/6 tasks)
- Created: session-continuity.md, jit-retrieval.md, attention-budget.md (~930 lines)
- Updated: structured-memory.md (+80 lines), trajectory-evaluation.md (+120 lines)
- Documentation: Bead schema extensions, fork detection, tiered recovery
- Total: ~1,280 lines of protocol documentation
- Ready for review phase (/review-sprint sprint-1)

## Discovered Technical Debt
<!-- Issues found during implementation that need future attention -->

## Blockers & Dependencies
<!-- External factors affecting progress -->

## Session Continuity
<!-- Key context to restore on next session -->
| Timestamp | Agent | Summary |
|-----------|-------|---------|
| 2025-12-26 10:30 | discovering-requirements | ck integration PRD complete (1,780 lines). Context synthesized from LOA_CK_INTEGRATION_PROMPT.md + LOA_CK_CLI_PROMPT.md. Key insights: beads pattern, FAANG-tier standards, invisible enhancement. 5 gaps identified for clarification. |
| 2025-12-26 11:15 | designing-architecture | SDD complete (~15,000 words, 13 sections). Architectural decisions: Direct CLI (v1.0), MCP migration (v2.0), Trajectory archival (gzip), Minimal Beads, Single repo. Includes: System architecture, component design (6 major components), data architecture (ck index, trajectory JSONL, NOTES.md), security (4-layer integrity), integration points (commands + skills), performance (caching + optimization). Next: /sprint-plan |
| 2025-12-26 12:00 | planning-sprints | Sprint plan complete (6 sprints, 4 weeks). Breakdown: Sprint 1 (Foundation, 6 tasks, 15.5h), Sprint 2 (Core Search, 6 tasks, 40h), Sprint 3 (Context Mgmt, 8 tasks, 37h), Sprint 4 (Skills, 6 tasks, 27h), Sprint 5 (Quality, 8 tasks, 31h), Sprint 6 (Validation, 8 tasks, 21h). Total: 42 tasks, 171.5h estimated. Testing strategy: unit (bats, >80%), integration (E2E), performance (benchmarks), edge cases. MVP defined: 13 P0 features, 8 P1 enhancements. Risk mitigation: 7 risks addressed. Dependencies: 4 external, inter-sprint blockers mapped. Success criteria: PRD checklist + sprint gates. Next: /implement sprint-1 |
| 2025-12-27 09:15 | discovering-requirements | v0.9.0 Lossless Ledger Protocol PRD complete (550 lines). Context synthesized from LOA_LOSSLESS_LEDGER_PROMPT.md (1,284 lines) + LOA_LOSSLESS_LEDGER_CLI_PROMPT.md (415 lines). Paradigm: "Clear, Don't Compact" - treat context as disposable workspace, State Zone as lossless ledgers. Key features: Session Continuity Protocol, Synthesis Checkpoint (blocking), Tiered Ledger Recovery (3 levels), Attention Budget (Green/Yellow/Orange/Red), JIT Retrieval (97% token reduction), Grounding Ratio Enforcement (>=0.95), Negative Grounding for Ghost Features. User decisions: Integrate with ck (v0.8.0), target v0.9.0, configurable grounding enforcement. Next: /architect |
| 2025-12-27 09:45 | designing-architecture | v0.9.0 SDD complete (~900 lines, 13 sections). Architecture: Context Lifecycle Manager (Session Recovery, Synthesis Checkpoint, Attention Budget), Ledger Access Layer (Beads, NOTES.md, Trajectory), JIT Retrieval Layer (ck hybrid, fallback), Enforcement Layer (Grounding, Negative Grounding, Hooks), Self-Healing Layer (Git-backed, Template). User decisions: Hook-based enforcement (intercept /clear), Advisory attention monitoring (not blocking). Component design: 7 new protocols, 3 new scripts, hook integration. Data architecture: Extended NOTES.md (Session Continuity), Bead schema (decisions[], handoffs[], test_scenarios[]), Trajectory phases (session_handoff, delta_sync). Next: /sprint-plan |
| 2025-12-27 10:30 | planning-sprints | v0.9.0 Sprint plan complete (24 tasks, 4 sprints). Breakdown: Sprint 1 (Foundation, 6 tasks) - session-continuity, NOTES.md extension, jit-retrieval, attention-budget, trajectory schema, bead schema. Sprint 2 (Enforcement, 6 tasks) - grounding-enforcement protocol, grounding-check.sh, negative grounding, synthesis-checkpoint protocol, synthesis-checkpoint.sh, self-heal-state.sh. Sprint 3 (Integration, 6 tasks) - /ride update, config schema, skill integration, ck integration docs, beads CLI docs, CLAUDE.md update. Sprint 4 (Polish, 8 tasks) - unit tests, integration tests, edge cases, cross-references, CI validation, release docs, UAT, security prep. User decisions: Solo developer, 4 sprints. PRD traceability: All 11 FRs + 2 IRs mapped to tasks. Next: /implement sprint-1 |
| 2025-12-27 11:30 | implementing-tasks | v0.9.0 Sprint 1 implementation complete (6/6 tasks). Created: session-continuity.md (~350 lines, truth hierarchy, tiered recovery, delta-synthesis), jit-retrieval.md (~300 lines, 97% token reduction, ck/fallback methods), attention-budget.md (~280 lines, advisory thresholds, delta-sync). Updated: structured-memory.md (+80 lines, Session Continuity section template), trajectory-evaluation.md (+120 lines, session_handoff, delta_sync, grounding_check phases). Enhanced: Bead schema extensions in session-continuity.md (+150 lines, decisions[], test_scenarios[], handoffs[], fork detection). Total: ~1,280 lines protocol documentation. All acceptance criteria met. Ready for review: /review-sprint sprint-1 |

## Decision Log
<!-- Major decisions with rationale -->

**Decision: Follow beads integration pattern for ck**
- **Rationale**: Proven pattern in Loa for optional enhancements
- **Pattern**: Surface at setup, invisible to user, graceful degradation, zero friction
- **Source**: LOA_CK_INTEGRATION_PROMPT.md:72-94

**Decision: Require word-for-word code citations**
- **Rationale**: References alone insufficient for reviewing-code agent audit
- **Format**: `"<claim>: <code_quote> [<absolute_path>:<line>]"`
- **Source**: LOA_CK_INTEGRATION_PROMPT.md:1386-1420

**Decision: Mandate self-audit checkpoint before completion**
- **Rationale**: Ensures grounding ratio ≥0.95, prevents ungrounded claims
- **Gate**: Task NOT complete if any checklist item fails
- **Source**: LOA_CK_INTEGRATION_PROMPT.md:1542-1629

**Decision: Implement Negative Grounding for Ghost Features**
- **Rationale**: Single query insufficient to confirm absence
- **Protocol**: TWO diverse semantic queries, both returning 0 results
- **High Ambiguity**: Flag for human audit if 0 code + >3 doc mentions
- **Source**: LOA_CK_INTEGRATION_PROMPT.md:1323-1378

**Decision: Direct CLI invocation for v1.0, MCP migration for v2.0**
- **Rationale**: Simpler deployment, lower attack surface, easier debugging (v1.0). MCP enables connection pooling, health checks, Claude Desktop integration (v2.0)
- **v1.0**: subprocess.run() with explicit PATH, no shell=True, 30s timeout
- **v2.0**: MCP server with L1 cache, reconnection logic, standardized tool interface
- **Source**: User approval, SDD §2.1

**Decision: Archive trajectory logs to compressed storage**
- **Rationale**: Full audit trail required for security-critical projects, but raw JSONL consumes excessive disk space
- **Policy**: 30 days active (raw JSONL), compress to .jsonl.gz after 30d, purge after 365d
- **Format**: gzip level 6 (balance speed vs. size)
- **Source**: User approval, SDD §4.2

**Decision: Minimal Beads integration (Ghost/Shadow tracking only)**
- **Rationale**: Keep integration scope tight for v1.0, avoid feature creep
- **Scope**: Track Ghost Features (liability priority 2), Shadow Systems (debt priority 1)
- **Out of Scope**: Sprint planning, trajectory sync, automated task creation beyond Ghost/Shadow
- **Source**: User approval, SDD §7.3

**Decision: Single repository only for v1.0**
- **Rationale**: Multi-repo adds significant complexity (federated search, cross-repo dependencies)
- **v1.0**: PROJECT_ROOT = single git repository, .ck/ index per repo
- **v2.0+**: Multi-repo workspaces with federated search
- **Source**: User approval, SDD §12.2
