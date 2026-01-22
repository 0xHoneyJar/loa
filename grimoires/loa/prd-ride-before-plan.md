# PRD: Ground /plan-and-analyze in Codebase Reality

**Version**: 2.0.0
**Status**: Draft
**Author**: Claude (Product Manager)
**Date**: 2026-01-23
**Issue**: [#44](https://github.com/0xHoneyJar/loa/issues/44)
**Cycle**: cycle-007

---

## Executive Summary

This PRD proposes grounding `/plan-and-analyze` in codebase reality by automatically executing `/ride` as Phase 0.5 for brownfield projects. The tradeoff is explicit: **accuracy and grounding over speed**.

**Problem**: PRDs created via `/plan-and-analyze` have no awareness of existing code, leading to requirements that may already exist, conflict with current architecture, or miss existing constraints.

**Solution**: Automatically detect brownfield codebases and run `/ride` inline as Phase 0.5 before discovery begins. The codebase analysis becomes a first-class part of the PRD workflow, not an optional suggestion.

**Design Philosophy**: Slower is better when it means more accurate, grounded PRDs. The cost of a bad PRD (30+ minutes of rework) far exceeds the cost of a 5-15 minute `/ride` analysis.

---

## 1. Problem Statement

### Current State

`/plan-and-analyze` creates PRDs by:
1. Reading pre-existing documentation from `grimoires/loa/context/`
2. Conducting a 7-phase discovery interview with the user
3. Generating `grimoires/loa/prd.md` with source tracing

> From plan-and-analyze.md:4-7: "Launch PRD discovery with automatic context ingestion. Reads existing documentation from grimoires/loa/context/ before interviewing."

**The Gap**: This workflow has no awareness of existing code. When users run `/plan-and-analyze` on a repository with actual code, the generated PRD:
- May propose features that already exist
- May miss constraints imposed by current architecture
- May create requirements that conflict with existing patterns
- Lacks evidence-grounded understanding of what's already built

### Evidence of Problem

From issue #44:
> "When /plan-and-analyze is run on a repo that already has code, it should understand the codebase context before creating a PRD."

The `/ride` command already solves codebase understanding with a comprehensive 10-phase analysis:

> From ride.md:40-55: "/ride performs comprehensive codebase analysis... generates evidence-grounded PRD/SDD from actual code"

**The disconnect**: `/ride` and `/plan-and-analyze` operate independently with no integration.

### Why Option B (Auto-Run) Over Option A (Suggest)

| Approach | Pros | Cons |
|----------|------|------|
| **A: Soft Suggestion** | Fast, user choice | Users skip, bad PRDs result |
| **B: Auto-Run (Chosen)** | Guaranteed accuracy, grounded PRDs | Slower (5-15 min) |
| **C: Auto-Update Docs** | Convenient | Risky, may corrupt good docs |

**Decision**: Users explicitly prefer accuracy over speed. A bad PRD costs 30+ minutes of rework downstream. A 10-minute `/ride` is a worthwhile investment.

---

## 2. Goals & Success Metrics

### Primary Goal

Ground `/plan-and-analyze` in codebase reality by automatically running `/ride` for brownfield projects, ensuring PRDs reflect both user intent AND existing code state.

### Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| PRD grounding | 100% of brownfield PRDs include codebase citations | Audit PRD sources |
| Zero rework | 0 "already exists" discoveries in /architect phase | Manual audit |
| User satisfaction | Users prefer integrated flow over manual /ride | Survey |
| Greenfield UX | Zero added latency for greenfield projects | Timing |

### Non-Goals

- Speed optimization (accuracy is the priority)
- Skipping `/ride` for brownfield projects
- Modifying `/ride` command internals
- Real-time code monitoring

---

## 3. User Personas & Journeys

### Persona 1: Brownfield Developer (Primary)

**Context**: Has existing codebase (500+ lines), wants to add new feature or refactor.

**Current Journey** (Pain Points):
1. Runs `/plan-and-analyze`
2. Answers 7 phases of questions
3. Gets PRD that ignores existing code
4. Runs `/architect` - discovers conflicts with codebase
5. **Waste**: 30+ minutes revising PRD and SDD

**New Journey (Option B)**:
1. Runs `/plan-and-analyze`
2. System detects brownfield codebase
3. **Phase 0.5**: `/ride` executes automatically (~5-15 min)
4. User sees progress: "Analyzing codebase... extracting architecture..."
5. Phase 0: Context synthesis includes codebase reality
6. 7 phases informed by what actually exists
7. PRD accurately reflects existing state + proposed changes

### Persona 2: Greenfield Developer (Secondary)

**Context**: New project, no existing code.

**Current Journey**: Works perfectly.

**New Journey**: Identical to current. Detection is silent, no `/ride` runs, zero added latency.

### Persona 3: Returning Developer

**Context**: Has run `/ride` recently, wants to add another feature.

**Journey**:
1. Runs `/plan-and-analyze`
2. System detects recent `/ride` output (<7 days old)
3. Skips re-running `/ride`, uses cached reality
4. Proceeds directly to Phase 0 with existing codebase context

---

## 4. Functional Requirements

### FR-1: Codebase Detection (Pre-Flight)

**When** `/plan-and-analyze` is invoked,
**The system shall** detect if meaningful code exists in App Zone paths.

**Acceptance Criteria**:
- [ ] Detection completes in <5 seconds
- [ ] Checks standard paths: `src/`, `lib/`, `app/`, `packages/`, root `*.py`, `*.go`, etc.
- [ ] Handles monorepos and non-standard structures
- [ ] Returns: `GREENFIELD` | `BROWNFIELD` with summary stats
- [ ] Excludes non-source directories (node_modules, vendor, .git, dist, build)

**Detection Heuristics**:
```
Source file extensions: .ts, .tsx, .js, .jsx, .py, .go, .rs, .java, .rb, .php, .cs, .cpp, .c, .h
Threshold: >10 source files OR >500 lines = BROWNFIELD
Exclusions: node_modules, vendor, .git, dist, build, __pycache__, target, .next, .nuxt
```

### FR-2: Automatic /ride Execution (Phase 0.5)

**If** codebase is `BROWNFIELD` AND no recent `/ride` output exists,
**The system shall** automatically execute `/ride` as Phase 0.5.

**Acceptance Criteria**:
- [ ] `/ride` runs with default parameters (no user intervention)
- [ ] Progress updates shown: "Phase 0.5: Analyzing codebase..."
- [ ] `/ride` output written to standard locations (`grimoires/loa/reality/`)
- [ ] Errors in `/ride` are recoverable (user can retry or skip)
- [ ] Timeout protection: `/ride` aborts after 20 minutes with partial results

**User Feedback During Execution**:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Phase 0.5: Codebase Analysis (Brownfield Detected)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Detected: 47 source files, ~3,200 lines (TypeScript)

Running /ride to ground PRD in codebase reality...
  [■■■■■□□□□□] Extracting architecture...

This ensures your PRD reflects what already exists.
Estimated time: 5-10 minutes
```

### FR-3: Ride Output Integration (Phase 0)

**After** Phase 0.5 completes (or if recent `/ride` output exists),
**The system shall** integrate reality files as highest-priority context.

**Acceptance Criteria**:
- [ ] `reality/extracted-prd.md` loaded before user context
- [ ] `reality/extracted-sdd.md` informs technical phases
- [ ] `reality/component-inventory.md` prevents duplicate features
- [ ] Citations use `[CODE:file:line]` format
- [ ] Phase 0 presents: "Based on your existing codebase, I understand..."
- [ ] Conflicts between context/ and reality/ flagged for user resolution

**Context Priority Order**:
1. `grimoires/loa/reality/` (from /ride) - **highest priority, CODE IS TRUTH**
2. `grimoires/loa/context/` (user-provided docs)
3. Discovery interview responses

### FR-4: Cached Reality Detection

**If** recent `/ride` output exists (modified within 7 days),
**The system shall** skip Phase 0.5 and use cached results.

**Acceptance Criteria**:
- [ ] Check modification times on `grimoires/loa/reality/*.md`
- [ ] If all files <7 days old: skip `/ride`, show "Using recent codebase analysis"
- [ ] If files >7 days old: warn user, offer choice to re-run or proceed
- [ ] Configurable staleness threshold via `.loa.config.yaml`

**Stale Reality Warning**:
```
Your codebase analysis is 12 days old. The code may have changed.

Options:
1. Re-run /ride for fresh analysis (recommended)
2. Proceed with existing analysis (faster)
```

### FR-5: Greenfield Fast Path

**If** codebase is `GREENFIELD`,
**The system shall** skip Phase 0.5 entirely with no user interaction.

**Acceptance Criteria**:
- [ ] No prompt, no delay, no message
- [ ] Proceeds directly to Phase -1 (context assessment)
- [ ] Zero added latency for greenfield projects

### FR-6: Ride Error Recovery

**If** `/ride` fails or times out during Phase 0.5,
**The system shall** offer recovery options.

**Acceptance Criteria**:
- [ ] Capture `/ride` error message
- [ ] Offer: Retry, Skip (proceed without analysis), Abort
- [ ] If Skip: warn that PRD may miss existing functionality
- [ ] Partial results preserved if available

**Error Recovery Prompt**:
```
⚠️ Codebase analysis encountered an error:
   [error message]

Options:
1. Retry /ride analysis
2. Skip and proceed without codebase grounding (not recommended)
3. Abort /plan-and-analyze
```

---

## 5. Technical Requirements

### TR-1: Codebase Detection Script

Create `.claude/scripts/detect-codebase.sh`:

**Input**: None (uses cwd)
**Output**: JSON to stdout
```json
{
  "type": "GREENFIELD|BROWNFIELD",
  "files": 47,
  "lines": 3200,
  "language": "typescript",
  "paths_found": ["src/", "lib/"],
  "reality_exists": true,
  "reality_age_days": 3
}
```

**Exit Codes**:
- 0: Success (type in JSON)
- 1: Error

### TR-2: Ride Wrapper for Phase 0.5

The skill workflow calls `/ride` programmatically:

```python
# Pseudocode for skill execution
if codebase_detection.type == "BROWNFIELD":
    if not reality_exists or reality_age_days > 7:
        show_progress("Phase 0.5: Analyzing codebase...")
        result = execute_ride(timeout=1200)  # 20 min timeout
        if result.failed:
            handle_ride_error(result)
    else:
        show_message("Using recent codebase analysis (3 days old)")
```

### TR-3: Context File Updates

Update `plan-and-analyze.md` context_files:

```yaml
context_files:
  # Reality files from /ride (highest priority - CODE IS TRUTH)
  - path: "grimoires/loa/reality/extracted-prd.md"
    required: false
    priority: 1
    purpose: "Codebase-extracted PRD from /ride"

  - path: "grimoires/loa/reality/extracted-sdd.md"
    required: false
    priority: 1
    purpose: "Codebase-extracted architecture from /ride"

  - path: "grimoires/loa/reality/component-inventory.md"
    required: false
    priority: 1
    purpose: "Existing components to avoid duplication"

  - path: "grimoires/loa/reality/consistency-report.md"
    required: false
    priority: 1
    purpose: "Code vs docs consistency analysis"

  # User context files (secondary)
  - path: "grimoires/loa/context/*.md"
    required: false
    recursive: true
    priority: 2
    purpose: "Pre-existing project documentation for synthesis"
```

### TR-4: Pre-Flight Check

Add to `plan-and-analyze.md` pre_flight:

```yaml
- check: "script"
  script: ".claude/scripts/detect-codebase.sh"
  store_result: "codebase_detection"
  purpose: "Detect codebase type and reality file status"
```

### TR-5: Skill Workflow Update

Update `discovering-requirements/SKILL.md`:

**New Phase -0.5: Codebase Grounding**

```markdown
## Phase -0.5: Codebase Grounding (Brownfield Only)

**Trigger**: `codebase_detection.type == "BROWNFIELD"`

### Step 1: Check Reality Cache
- If `reality_exists` AND `reality_age_days <= 7`: Skip to Phase -1
- If `reality_age_days > 7`: Warn user, offer re-run or proceed
- If no reality: Execute /ride

### Step 2: Execute /ride (if needed)
- Show progress indicator with estimated time
- Run /ride with 20-minute timeout
- Handle errors with recovery options

### Step 3: Validate Output
- Verify reality files created
- Load into context for Phase 0
```

### TR-6: Configuration

Add to `.loa.config.yaml`:

```yaml
plan_and_analyze:
  codebase_grounding:
    enabled: true                    # Master toggle for Phase 0.5
    reality_staleness_days: 7        # Days before re-running /ride
    ride_timeout_minutes: 20         # Abort /ride after this time
    skip_on_ride_error: false        # If true, proceed without grounding on error
```

### TR-7: Performance Expectations

| Operation | Expected | Hard Limit |
|-----------|----------|------------|
| Codebase detection | <3s | 5s |
| Reality staleness check | <1s | 2s |
| /ride execution (Phase 0.5) | 5-15 min | 20 min |
| Context loading | <2s | 5s |

**Note**: Phase 0.5 is intentionally slow. This is a feature, not a bug.

---

## 6. Scope & Prioritization

### MVP (Sprint 1)

| Feature | Priority | Complexity | Effort |
|---------|----------|------------|--------|
| FR-1: Codebase detection script | P0 | Low | 3h |
| FR-2: Auto /ride execution | P0 | Medium | 4h |
| FR-3: Reality integration | P0 | Medium | 4h |
| FR-5: Greenfield fast path | P0 | Low | 1h |
| TR-3: Context file updates | P0 | Low | 1h |
| TR-5: Skill workflow update | P0 | Medium | 4h |

**Total MVP Estimate**: ~17 hours (1 sprint)

### Sprint 2 (Hardening)

| Feature | Priority | Effort |
|---------|----------|--------|
| FR-4: Cached reality detection | P1 | 3h |
| FR-6: Ride error recovery | P1 | 4h |
| TR-6: Configuration options | P1 | 2h |
| Documentation updates | P1 | 2h |

**Total Sprint 2**: ~11 hours

### Out of Scope

- Modifying `/ride` command behavior
- Partial `/ride` execution (lite mode)
- Real-time code monitoring
- Auto-updating existing code based on PRD

---

## 7. Risks & Mitigations

### Risk 1: /ride Takes Too Long

**Risk**: Users abandon `/plan-and-analyze` due to wait time.
**Probability**: Low (users explicitly chose accuracy over speed)
**Impact**: Medium
**Mitigation**:
- Clear progress indicators with time estimates
- 20-minute timeout prevents infinite waits
- Cached reality skips re-run for recent analyses

### Risk 2: /ride Fails Mid-Execution

**Risk**: `/ride` errors leave workflow in bad state.
**Probability**: Medium
**Impact**: Medium
**Mitigation**:
- Comprehensive error recovery (FR-6)
- User can skip and proceed (with warning)
- Partial results preserved when possible

### Risk 3: Stale Reality Leads to Bad PRD

**Risk**: Cached reality doesn't reflect recent code changes.
**Probability**: Medium
**Impact**: Medium
**Mitigation**:
- 7-day staleness threshold (configurable)
- Explicit warning when using old analysis
- User can always force re-run

### Risk 4: False Positive Brownfield Detection

**Risk**: Config-only repos trigger unnecessary /ride.
**Probability**: Low
**Impact**: Low (user sees it's quick)
**Mitigation**:
- Strict thresholds (>10 files OR >500 lines)
- Exclude common config-only patterns
- /ride is fast on small codebases anyway

### Risk 5: Greenfield Gets Delayed

**Risk**: Greenfield detection fails, runs /ride unnecessarily.
**Probability**: Very Low
**Impact**: Medium
**Mitigation**:
- Conservative detection (BROWNFIELD requires evidence)
- Silent fast path for greenfield
- Timeout protects worst case

---

## 8. Implementation Checklist

### Sprint 1: Core Integration

- [ ] Create `.claude/scripts/detect-codebase.sh`
  - [ ] Source file detection with extensions list
  - [ ] Line counting with wc -l
  - [ ] Language detection (most common extension)
  - [ ] Reality file existence and age check
  - [ ] JSON output format
  - [ ] Unit tests (bats)

- [ ] Update `.claude/commands/plan-and-analyze.md`
  - [ ] Add codebase detection pre-flight check
  - [ ] Add reality context files with priority
  - [ ] Update phase documentation

- [ ] Update `.claude/skills/discovering-requirements/SKILL.md`
  - [ ] Add Phase -0.5: Codebase Grounding section
  - [ ] Add brownfield detection decision tree
  - [ ] Add /ride execution with progress feedback
  - [ ] Update Phase 0 to integrate reality context
  - [ ] Update citation format guidance

- [ ] Testing
  - [ ] Test on greenfield repo (zero added latency)
  - [ ] Test on small brownfield (<100 files)
  - [ ] Test on medium brownfield (100-500 files)
  - [ ] Test with existing recent reality
  - [ ] Test with stale reality (>7 days)

### Sprint 2: Hardening

- [ ] Implement cached reality detection (FR-4)
- [ ] Implement error recovery flow (FR-6)
- [ ] Add configuration options (TR-6)
- [ ] Update CLAUDE.md with new workflow
- [ ] Update PROCESS.md Phase 1 description
- [ ] Add integration tests

---

## 9. User-Facing Changes

### Documentation Updates Required

1. **CLAUDE.md**: Update `/plan-and-analyze` description to mention automatic codebase grounding
2. **PROCESS.md**: Update Phase 1 to describe the integrated workflow
3. **INSTALLATION.md**: No changes (optional enhancement)

### New User Messages

**Brownfield Detection**:
```
━━━ Phase 0.5: Codebase Analysis ━━━
Detected brownfield project: 47 files, ~3,200 lines (TypeScript)
Running /ride to ground your PRD in codebase reality...
Estimated time: 5-10 minutes
```

**Using Cached Reality**:
```
━━━ Phase 0.5: Codebase Analysis ━━━
Using recent codebase analysis (3 days old)
Skipping /ride re-run. Use --fresh to force re-analysis.
```

**Greenfield Detection**:
```
(no message - silent fast path)
```

---

## Appendix A: Issue #44 Options - Revised Analysis

| Option | Proposal | Verdict | Rationale |
|--------|----------|---------|-----------|
| A: Suggest /ride first | Soft prompt | Rejected | Users skip suggestions, leads to bad PRDs |
| **B: Hook /ride into discovery** | Auto-run Phase 0.5 | **Adopted** | Guarantees grounded PRDs, acceptable slowdown |
| C: Auto-update docs | Modify existing PRD/SDD | Rejected | Risky, may corrupt good documentation |

**User Feedback**: "We don't mind being a bit slower if it means more accuracy and grounding in reality."

## Appendix B: /ride Output Files Used

| File | Purpose | Usage in PRD |
|------|---------|--------------|
| `reality/extracted-prd.md` | Codebase-derived requirements | Primary context for all phases |
| `reality/extracted-sdd.md` | Codebase-derived architecture | Technical phases (5, 7) |
| `reality/component-inventory.md` | Existing components | Prevent duplicate features (Phase 4) |
| `reality/consistency-report.md` | Code vs docs drift | Identify outdated context |

## Appendix C: Related Files

- `.claude/commands/plan-and-analyze.md` - Command definition
- `.claude/skills/discovering-requirements/SKILL.md` - Full skill workflow
- `.claude/commands/ride.md` - Ride command reference
- `.claude/skills/riding-codebase/SKILL.md` - Ride skill implementation (10 phases)
- `CLAUDE.md:165-167` - Current mount/ride recommendation

---

**PRD Status**: Ready for `/architect`
