# PRD: /ride Persistent Artifacts & Context-Aware Invocation

**Version**: 1.0.1
**Status**: Draft (revised per PR #272 Bridgebuilder review)
**Author**: Discovery Phase (plan-and-analyze)
**Issue**: [#270](https://github.com/0xHoneyJar/loa/issues/270)
**Date**: 2026-02-10

---

## 1. Problem Statement

The `/ride` skill defines 10+ phases that generate structured analysis artifacts (drift-report.md, governance-report.md, consistency-report.md, etc.), but **none of these artifacts are persisted to disk** when the skill completes. The output is rendered inline in the conversation and lost when the session ends.

This creates two downstream failures:

1. **`/translate-ride` is blocked**: The batch translation command expects 5 report files at specific paths. When invoked after `/ride`, it finds 0/5 artifacts and cannot proceed.

2. **Cross-session continuity is broken**: Other agents (e.g., during `/plan-and-analyze` or `/architect`) have no architecture grounding documents from `/ride` to build on. Each session starts from scratch.

**Source**: User feedback via `/feedback` command (Issue #270, v1.31.0).

## 2. Goals & Success Metrics

### Goals

| # | Goal | Measurable Outcome |
|---|------|--------------------|
| G1 | Artifacts persist after `/ride` completes | All 5 report files exist on disk after invocation |
| G2 | `/translate-ride` works end-to-end | Translation produces EXECUTIVE-INDEX.md from ride artifacts |
| G3 | Context-aware invocation (deferred) | `/plan-and-analyze` handles staleness externally; `/ride` always runs full |
| G4 | Architecture grounding available | Other agents can load ride-produced architecture context |

### Success Metrics

- **M1**: `/ride` → `ls grimoires/loa/drift-report.md` returns file (currently fails)
- **M2**: `/ride` → `/translate-ride` → `grimoires/loa/translations/EXECUTIVE-INDEX.md` exists (currently blocked)
- **M3**: `/plan-and-analyze` staleness check skips `/ride` when artifacts are fresh (deferred — FR-2)
- **M4**: Full `/ride` direct invocation completes all 10 phases with file persistence

## 3. User & Stakeholder Context

### Primary Persona: Loa Developer (Human Operator)

Runs `/ride` on brownfield codebases to generate analysis reports. Expects persistent output files they can review across sessions, share with team, and feed into downstream workflows (`/translate-ride`, `/architect`).

### Secondary Persona: Agent Pipeline

Other Loa skills (`/plan-and-analyze`, `/architect`, `/simstim`) invoke `/ride` internally for codebase grounding. These need lightweight, fast output — not the full 10-phase ceremony.

## 4. Functional Requirements

### FR-1: Artifact Persistence (MUST)

When `/ride` completes (direct invocation or full mode), the following files MUST exist on disk:

| Artifact | Path | Source Phase |
|----------|------|-------------|
| Drift Report | `grimoires/loa/drift-report.md` | Phase 4 |
| Consistency Report | `grimoires/loa/consistency-report.md` | Phase 5 |
| Governance Report | `grimoires/loa/governance-report.md` | Phase 7 |
| Hygiene Report | `grimoires/loa/reality/hygiene-report.md` | Phase 2b |
| Trajectory Audit | `grimoires/loa/trajectory-audit.md` | Phase 9 |

These paths are already defined in `SKILL.md` — the requirement is that they are actually written using the `Write` tool, not just rendered inline.

**Additionally**, the existing Phase 6 artifacts (PRD, SDD) and Phase 6.5 artifacts (reality files) must also be persisted as already specified in SKILL.md.

### FR-2: Context-Aware Invocation Mode (SHOULD — deferred)

> **Deferred rationale (v1.0.1)**: The SDD §4.3.2 "Practical Mode Detection" analysis concluded that `/ride` should always run FULL mode when invoked. The lightweight behavior is already achieved by `/plan-and-analyze` not invoking `/ride` at all when artifacts are fresh (via its Phase -0.5 staleness check). Adding mode-switching logic to SKILL.md would introduce complexity without benefit, since the calling skill already provides the optimization. If future requirements need lightweight mode, it can be added via a marker file (`.run/ride-caller.json`) or the `--phase` argument already supported by `ride.md`.

`/ride` could detect its invocation context and select an appropriate mode:

| Context | Detection | Mode | Behavior |
|---------|-----------|------|----------|
| Direct user call | No `LOA_RIDE_CALLER` env var, or `CALLER=user` | **Full** | All 10 phases, full artifact persistence |
| `/plan-and-analyze` internal | `LOA_RIDE_CALLER=plan-and-analyze` | **Lightweight** | Phases 0-2 + 6.5 only (reality files), skip reports |
| No prior artifacts exist | `drift-report.md` not found | **Full** | Override lightweight → full if no artifacts exist |
| `--full` flag | CLI argument | **Full** | Force full mode regardless of caller |

**Lightweight mode** would produce only:
- `grimoires/loa/reality/*` (token-optimized codebase interface)
- `grimoires/loa/context/claims-to-verify.md`
- Trajectory log entries

**Full mode** produces everything lightweight produces PLUS:
- All 5 analysis reports (FR-1)
- PRD and SDD (Phase 6)
- Legacy inventory and deprecation (Phases 3, 8)

**Current behavior**: `/ride` always runs FULL mode. Lightweight optimization is handled externally by `/plan-and-analyze`.

### FR-3: Architecture Grounding Document (SHOULD)

Generate a concise architecture overview for consumption by other agents:

- Path: `grimoires/loa/reality/architecture-overview.md`
- Content: System component diagram (ASCII), key data flows, technology stack summary, entry points
- Token budget: < 1500 tokens
- Updated during Phase 6.5 alongside other reality files

This serves as the "grounding document" that issue #270 requests so agents have structural understanding without loading full PRD/SDD.

### FR-4: `/translate-ride` Compatibility (MUST)

The artifacts produced by FR-1 must match the paths and format expected by `/translate-ride`:

| Translate-Ride Expects | Ride Produces | Status |
|------------------------|---------------|--------|
| `grimoires/loa/drift-report.md` | Phase 4 output | Currently missing → Fix |
| `grimoires/loa/governance-report.md` | Phase 7 output | Currently missing → Fix |
| `grimoires/loa/consistency-report.md` | Phase 5 output | Currently missing → Fix |
| `grimoires/loa/reality/hygiene-report.md` | Phase 2b output | Currently missing → Fix |
| `grimoires/loa/trajectory-audit.md` | Phase 9 output | Currently missing → Fix |
| `grimoires/loa/NOTES.md` | Phase 10 output | Already works |

### FR-5: Staleness Detection (SHOULD)

When `/ride` is invoked and artifacts already exist:

- Check `.reality-meta.json` for `generated_at` timestamp
- If < 7 days old: prompt user to skip/refresh (configurable via `ride.staleness_days`)
- If >= 7 days old: run full analysis
- If `--fresh` flag: always run full analysis regardless of age

## 5. Technical & Non-Functional Requirements

### NFR-1: Performance

- Lightweight mode: < 5 minutes for codebases under 50K lines
- Full mode: < 20 minutes for codebases under 50K lines (existing SKILL.md timeout)

### NFR-2: Token Budget Compliance

Reality files must stay within the existing SKILL.md token budgets (< 7000 tokens total). The new `architecture-overview.md` adds < 1500 tokens.

### NFR-3: Backward Compatibility

- No changes to `/ride` CLI invocation syntax
- Existing `context: fork` agent model preserved
- `/plan-and-analyze` continues to work with or without the mode detection
- `--fresh` flag behavior in `/plan-and-analyze` unchanged

### NFR-4: No Breaking Changes to SKILL.md Structure

The fix should work within the existing SKILL.md phase structure. The phases and their outputs are already correctly specified — the implementation gap is in ensuring the agent actually writes the files rather than rendering them inline.

## 6. Scope & Prioritization

### MVP (This PR)

1. **Artifact persistence** — Ensure all 5 analysis reports are written to disk (FR-1)
2. **Context-aware mode** — Lightweight vs. full invocation detection (FR-2)
3. **Translate-ride compatibility** — Verify end-to-end pipeline works (FR-4)

### Stretch

4. **Architecture grounding document** — New `architecture-overview.md` file (FR-3)
5. **Staleness detection** — Freshness check before re-running (FR-5)

### Out of Scope

- Modifying `/translate-ride` itself (it should work once artifacts exist)
- Changing the `/ride` phase structure or analysis methodology
- Adding new analysis dimensions beyond what SKILL.md already defines
- Cross-repo ride support (future enhancement)

## 7. Risks & Dependencies

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| SKILL.md instructions are correct but ignored by agent | High | High | Add explicit `Write` tool instructions with checkpoint verification |
| Fork context drops file writes | Medium | High | Verify `context: fork` allows Write tool; if not, change to `context: shared` |
| Lightweight mode misdetects context | Low | Medium | Fall back to full mode when unsure; `--full` escape hatch |
| Token budget exceeded with new architecture file | Low | Low | Strict < 1500 token limit; omit if over budget |

### Dependencies

- Existing SKILL.md phase definitions (already stable)
- `/translate-ride` artifact path expectations (already documented)
- `.reality-meta.json` schema for staleness detection

## 8. Implementation Hints

### Root Cause Analysis

The likely root cause is that SKILL.md tells the agent to "generate" or "create" artifacts, but doesn't include explicit `Write` tool invocations or file-write checkpoints. The agent renders the content in its response but may not invoke the Write tool to persist it.

### Suggested Approach

1. **Add explicit file-write checkpoints** after each artifact-producing phase in SKILL.md
2. **Add a verification step** at Phase 10 that checks all expected files exist on disk
3. **Add mode detection logic** at Phase 0 based on environment variable or invocation context
4. **Add `architecture-overview.md` template** to the reality file generation in Phase 6.5

### Key Files to Modify

| File | Change |
|------|--------|
| `.claude/skills/riding-codebase/SKILL.md` | Add file-write checkpoints, mode detection, architecture overview |
| `.claude/skills/riding-codebase/resources/references/output-formats.md` | Add architecture-overview template |
| `.loa.config.yaml.example` | Add `ride.staleness_days` config option |

---

*Generated from Issue #270 context via /plan-and-analyze. Codebase grounded against SKILL.md (443 lines), translate-ride command, and reality directory state.*
