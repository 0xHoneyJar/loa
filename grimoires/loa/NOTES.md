# Agent Working Memory

## Current Focus

| Field | Value |
|-------|-------|
| **Active Task** | Cycle-030: Bridge Inquiry Infrastructure |
| **Status** | Sprint 6 (sprint-30) — Multi-Model Inquiry + Integration |
| **Blocked By** | None |
| **Next Action** | Complete sprint-30, bridge finalization |
| **Previous** | Cycle-029 archived; Sprints 4-5 (FR-5, FR-3, FR-1, FR-2) complete |

## Session Log

| Timestamp | Event | Details |
|-----------|-------|---------|
| 2026-02-12T00:00:00Z | Session started | Feature: Eileen Eval Feedback (#286) |
| 2026-02-12T00:05:00Z | Context ingested | PR #282 comments (6 from eileen1337, 4 from janitooor), eval codebase explored |
| 2026-02-12T00:10:00Z | Cycle archived | cycle-002 (Eval Sandbox) archived, cycle-003 created |
| 2026-02-12T00:15:00Z | Deep analysis completed | 8 Eileen suggestions mapped against current state, pros/cons documented |
| 2026-02-12T00:30:00Z | PRD v1.0.0 written | 10 FRs across 5 sprints, full Eileen roadmap (all 8 items) |
| 2026-02-12T00:35:00Z | Research PR created | PR #287 with 5 comment appendices for Eileen review |
| 2026-02-12T00:45:00Z | Bug triage started | Issue #288: /update-loa propagates workflow files |
| 2026-02-12T01:00:00Z | Bug triage complete | Bug 20260212-i288-991113, sprint-bug-7, beads bd-35g |

## Decisions

| ID | Decision | Reasoning | Date |
|----|----------|-----------|------|
| D-007 | Three-tier fallback: QMD → CK → grep | Maximizes availability — every environment gets context even without semantic tools | 2026-02-19 |
| D-008 | Token budget via jq reduce, not bash loop | Cleaner, atomic, avoids subshell variable scoping issues | 2026-02-19 |
| D-009 | SKILL.md integration via instruction steps, not code injection | Agent-level instructions are additive and non-breaking; shell scripts get direct function calls | 2026-02-19 |
| D-010 | Per-skill budget differentiation (1000-2500) | Bridge needs richest context; Gate 0 needs minimal known-issues check only | 2026-02-19 |
| D-011 | --skill flag for config-driven overrides | CLI flags take precedence, config overrides defaults, --skill reads skill_overrides section | 2026-02-19 |
| D-001 | Full Eileen scope (all 8 suggestions) | User chose ambitious scope; all items interconnect | 2026-02-12 |
| D-002 | Top 3 skills for output contracts | implementing-tasks, reviewing-code, auditing-security — highest risk and most structured output | 2026-02-12 |
| D-003 | Archive cycle-002 before starting | Eval Sandbox work already merged (PR #282 + #283 + #284 + #285) | 2026-02-12 |
| D-004 | No LLM-based judge graders in this cycle | Keeps grading deterministic; critic/reviser uses LLM in execution path only | 2026-02-12 |
| D-005 | Schema v2 backward compatible with v1 | v2 harness reads v1 results; prevents CI breakage during rollout | 2026-02-12 |
| D-006 | Two-pronged fix for #288 | .gitattributes merge=ours + post-merge revert step in update-loa.md | 2026-02-12 |

## Blockers

_None currently_

## Technical Debt

_None identified yet_

## Learnings

| ID | Learning | Source | Date |
|----|----------|--------|------|
| L-001 | Existing graders all return binary 0/100 — weighted_average composite strategy is unused | Codebase analysis | 2026-02-12 |
| L-002 | Skills have no version field in index.yaml — needed for prompt traceability | Codebase analysis | 2026-02-12 |
| L-003 | 24 JSON schemas exist in .claude/schemas/ but none validate skill output content | Codebase analysis | 2026-02-12 |
| L-004 | Skill output templates already define implicit contracts — formalization is incremental | SKILL.md analysis | 2026-02-12 |
| L-005 | Run-meta.json already captures git_sha and harness_version — partial instrumentation exists | run-eval.sh analysis | 2026-02-12 |
| L-006 | update.sh atomic swap path only copies .claude/ — already safe from workflow propagation | Bug #288 analysis | 2026-02-12 |
| L-007 | .gitattributes merge=ours only handles conflicts, not new file additions from upstream | Bug #288 analysis | 2026-02-12 |
| L-008 | Bridge max depth changed from 10 to 5 in v1.34.0 — existing configs with depth 6-10 will error | Bridge iter 3 fix | 2026-02-12 |
| L-009 | Keyword sanitization via `tr -cs '[:alnum:]'` prevents regex injection in grep tier | qmd-context-query.sh design | 2026-02-19 |
| L-010 | Path traversal prevention via `realpath` + `PROJECT_ROOT` prefix check — pattern from qmd-sync.sh | qmd-context-query.sh design | 2026-02-19 |
| L-011 | load_bridge_context() is defined but not wired into orchestration main loop — needs future call site | Sprint-15 review observation | 2026-02-19 |

## Session Continuity

**Recovery Anchor**: Bug triage complete. Next step: `/implement sprint-bug-7`.

**Key Context**:
- Bug: 20260212-i288-991113 (issue #288)
- Sprint: sprint-bug-7
- Beads: bd-35g
- Triage: `grimoires/loa/a2a/bug-20260212-i288-991113/triage.md`
- Sprint Plan: `grimoires/loa/a2a/bug-20260212-i288-991113/sprint.md`
- Fix: .gitattributes + update-loa.md post-merge revert
- Paused: cycle-003 (Eileen feedback PRD) — resume with `/architect` after bugfix

**If resuming**: Run `/implement sprint-bug-7` to fix the bug.

## [2026-02-17T22:37:09Z] Cycle 026 Created
- PRD: Hounfour Runtime Bridge — Model-Heterogeneous Agent Routing
- Source: #365 (feedback from Straylight construct build)
- Scope: Google adapter + Gemini 3 + Deep Research + Flatline routing + TeamCreate bridge
- Key finding: cycle-021 Gemini branch was shell-level, not Python adapter. Building fresh.
- Backed up: prd.md.cycle-025-bak, sdd.md.cycle-025-bak
