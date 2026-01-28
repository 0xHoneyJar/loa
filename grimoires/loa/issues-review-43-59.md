# Issues Review: #43-59

**Branch**: `chore/reviewing-issues-43-59`
**Date**: 2026-01-28
**Purpose**: Plan and prioritize fixes before implementation

---

## Summary

| # | Title | State | Category | Priority |
|---|-------|-------|----------|----------|
| 43 | Grimoire Reality: Cross-repo ecosystem mapping | OPEN | Enhancement | P2 |
| 44 | Ground /plan-and-analyze in codebase reality | **CLOSED** | Enhancement | - |
| 45 | Goal Traceability & End-to-End Validation | **CLOSED** | Feature | - |
| 46 | Clean Upgrade System & Recursive JIT Context | **MERGED** | Feature | - |
| 47 | Exclude README/CHANGELOG from update merges | **CLOSED** | Bug Fix | - |
| 48 | RFC: Construct Feedback Protocol | OPEN | RFC | P3 |
| 49 | Ground /plan-and-analyze in codebase reality | **MERGED** | Feature | - |
| 50 | Security Audit Remediation v2 | **CLOSED** | Security | - |
| 51 | Goal Traceability & Guided Workflow | **MERGED** | Feature | - |
| 52 | README overloaded | **CLOSED** | Docs | - |
| 53 | Streamline README with links to detailed docs | **MERGED** | Docs | - |
| 54 | Research: Agent Readiness Standards | OPEN | Research | P3 |
| 55 | Auto-continue to next sprint in /run | OPEN | Feature | P1 |
| 56 | Mount script installs v0.6.0 instead of latest | OPEN | Bug | **P0** |
| 57 | Auto-create Sprint Ledger during onboarding | OPEN | Enhancement | P2 |
| 58 | Oracle script fails: Anthropic docs URLs changed | OPEN | Bug | P1 |
| 59 | /reality - Read-Only Codebase Query API | OPEN | Feature | P2 |

---

## OPEN Issues Requiring Action (7 total)

### P0 - Critical (Blocks Adoption)

#### #56 - Mount script installs v0.6.0 instead of latest (v1.5.0)

**Problem**: Hardcoded fallback version `0.6.0` in `mount-loa.sh` is used because `.claude/.loa-version.json` doesn't exist in repo.

**Impact**: HIGH - New users installing Loa get wildly outdated version

**Root Cause**:
```bash
# In mount-loa.sh create_manifest()
local upstream_version="0.6.0"  # Hardcoded fallback
```

**Fix Options**:
1. Add `.claude/.loa-version.json` to repo (simple)
2. Fetch version from GitHub releases API (dynamic)
3. Read from `CHANGELOG.md` or git tags (existing source)

**Recommendation**: Option 1 - Add the file. Keep it simple.

**Files to modify**:
- Create `.claude/.loa-version.json` (or similar location)
- Verify `mount-loa.sh` reads it correctly

**Effort**: Small (30 min)

---

### P1 - High Priority (User-Facing Issues)

#### #55 - Auto-continue to next sprint in /run

**Problem**: `/run sprint-plan` stops after Sprint 1 instead of continuing to Sprint 2.

**Expected**: Automatic progression through all sprints until completion or blocker.

**Files to investigate**:
- `.claude/skills/run-mode/SKILL.md`
- `.claude/protocols/run-mode.md`
- Run state tracking: `.run/state.json`

**Complexity**: Medium - Need to understand run mode state machine

**Effort**: Medium (2-4 hours)

---

#### #58 - Oracle script fails: Anthropic docs URLs changed

**Problem**: Anthropic moved Claude Code docs from `docs.anthropic.com` to `code.claude.com`.

**Current URLs (broken)**:
```bash
["docs"]="https://docs.anthropic.com/en/docs/claude-code"
["changelog"]="https://docs.anthropic.com/en/release-notes/claude-code"
```

**New URLs**:
```bash
["docs"]="https://code.claude.com/docs/en/overview"
["changelog"]="https://code.claude.com/docs/en/changelog"
```

**Fix**: Update SOURCES array in `anthropic-oracle.sh`

**Files to modify**:
- `.claude/scripts/anthropic-oracle.sh`

**Effort**: Small (15 min)

---

### P2 - Medium Priority (Enhancements)

#### #43 - Grimoire Reality: Cross-repo ecosystem mapping

**Problem**: `/ride` captures code structure but misses system behaviors, cross-repo relationships, and environment state.

**Proposed**:
- `grimoires/shared/ecosystem.md` - Multi-repo relationships
- `grimoires/shared/systems/` - System behavior documentation
- `/ecosystem` command

**Relation to #59**: This overlaps with the `/reality` proposal. Could be combined.

**Recommendation**: Defer until #59 is designed. Both address "cross-repo understanding."

**Effort**: Large (research + implementation)

---

#### #57 - Auto-create Sprint Ledger during onboarding

**Problem**: Users miss out on Sprint Ledger benefits because it's not auto-created.

**Proposed**:
1. `/sprint-plan` creates ledger if missing (with prompt)
2. `/mount` offers to create missing artifacts
3. Document ledger schema

**Files to modify**:
- `.claude/skills/planning-sprints/SKILL.md`
- `.claude/scripts/mount-loa.sh`

**Effort**: Medium (1-2 hours)

---

#### #59 - /reality - Read-Only Codebase Query API

**Problem**: Agents integrating with external codebases waste tokens loading full source.

**Proposed**:
- `/ride` generates `grimoires/loa/reality/` artifacts
- `/reality` command queries these files
- Cross-repo support with `--repo` flag
- Token-optimized, machine-readable output

**Reality folder structure**:
```
grimoires/loa/reality/
├── index.md          # Hub/router
├── structure.md      # Directory map
├── api-surface.md    # Public functions
├── interfaces.md     # Integration points
├── contracts.md      # Deployed addresses
├── types.md          # Data structures
└── entry-points.md   # Where to start
```

**Relation to #43**: This is the more focused version. Implement this first.

**Effort**: Large (new command + skill modifications)

---

### P3 - Low Priority (Research/RFC)

#### #48 - RFC: Construct Feedback Protocol

**Summary**: Define how Child Constructs report learnings upstream to Loa and Registry.

**Key concepts**:
- `grimoires/{construct}/upstream.md` pattern
- Signal routing (Registry vs Loa vs Self)
- Evidence thresholds for auto-filing
- `/feedback` inherited command

**Status**: RFC only - no implementation requested yet

**Action**: Review RFC, provide feedback, leave open for discussion

**Effort**: None (review only)

---

#### #54 - Research: Agent Readiness Standards

**Summary**: Research cross-framework compatibility (Codex, Loa, Claude Code).

**Key questions**:
- Should Loa generate `AGENTS.md` for Codex compatibility?
- Can skills be exposed in cross-framework format?
- Agent readiness audit skill?

**Status**: Research task, not implementation

**Action**: Leave open as research tracker

**Effort**: None (research backlog)

---

## Dependency Graph

```
#56 (P0) ─────────────────────────────> Can be fixed immediately
                                        (no dependencies)

#58 (P1) ─────────────────────────────> Can be fixed immediately
                                        (no dependencies)

#55 (P1) ─────────────────────────────> Can be fixed immediately
                                        (no dependencies)

#57 (P2) ─────────────────────────────> Can be fixed immediately
                                        (no dependencies)

#43 (P2) ──────> Depends on #59 design
    ↓
#59 (P2) ─────────────────────────────> Can be designed independently

#48 (P3) ─────────────────────────────> RFC - no implementation
#54 (P3) ─────────────────────────────> Research - no implementation
```

---

## Recommended Fix Order

### Batch 1: Quick Fixes (< 1 hour total)

| Order | Issue | Effort | Reason |
|-------|-------|--------|--------|
| 1 | #56 | 30 min | P0 - Blocks new user adoption |
| 2 | #58 | 15 min | P1 - Straightforward URL update |

### Batch 2: Medium Fixes (2-4 hours)

| Order | Issue | Effort | Reason |
|-------|-------|--------|--------|
| 3 | #55 | 2-4 hr | P1 - Improves run mode usability |
| 4 | #57 | 1-2 hr | P2 - Better onboarding experience |

### Batch 3: Design Work (Requires Planning)

| Order | Issue | Effort | Reason |
|-------|-------|--------|--------|
| 5 | #59 | Large | P2 - Valuable feature, needs design |
| 6 | #43 | Large | P2 - Combine with #59 research |

### Batch 4: Backlog (No immediate action)

| Issue | Action |
|-------|--------|
| #48 | Review RFC, leave open |
| #54 | Track as research backlog |

---

## Closed Issues (Already Resolved)

These issues are closed and need no action:

- **#44** - Ground /plan-and-analyze (closed by #49)
- **#45** - Goal Traceability (closed by #51)
- **#46** - Clean Upgrade & Recursive JIT (merged)
- **#47** - Exclude README/CHANGELOG (closed)
- **#49** - Ground /plan-and-analyze (merged)
- **#50** - Security Remediation v2 (closed)
- **#51** - Goal Traceability & Guided Workflow (merged)
- **#52** - README overloaded (closed by #53)
- **#53** - Streamline README (merged)

---

## Pre-Implementation Checklist

Before starting fixes:

- [ ] Review current `mount-loa.sh` to understand version detection
- [ ] Review `anthropic-oracle.sh` URL handling
- [ ] Review run-mode protocol for sprint continuation logic
- [ ] Review sprint-plan skill for ledger creation logic

---

## Questions for Discussion

1. **#56**: Should we also bump the banner version from v0.9.0?
2. **#55**: What triggers "sprint complete" detection?
3. **#57**: Should ledger creation be opt-out or opt-in?
4. **#59**: Should /reality be a separate command or part of /ride?
