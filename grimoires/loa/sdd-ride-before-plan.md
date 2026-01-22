# SDD: Ground /plan-and-analyze in Codebase Reality

**Version**: 1.0.0
**Status**: Draft
**Author**: Claude (Software Architect)
**Date**: 2026-01-23
**PRD**: `grimoires/loa/prd-ride-before-plan.md`
**Cycle**: cycle-007

---

## Executive Summary

This SDD describes the technical architecture for integrating `/ride` into `/plan-and-analyze` as Phase -0.5 (Codebase Grounding). The design prioritizes accuracy over speed, automatically running codebase analysis for brownfield projects to ensure PRDs are grounded in code reality.

**Key Design Decisions**:
1. New `detect-codebase.sh` script for fast brownfield detection
2. Workflow-level integration in `discovering-requirements` skill (not command-level)
3. Reality files loaded as highest-priority context via existing context_files mechanism
4. 7-day cache with configurable staleness threshold
5. Error recovery via AskUserQuestion with retry/skip/abort options

---

## 1. System Architecture

### 1.1 High-Level Component Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         /plan-and-analyze Workflow                       │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌──────────────────┐    ┌──────────────────┐    ┌──────────────────┐  │
│  │   Pre-Flight     │───▶│  Phase -0.5      │───▶│   Phase -1       │  │
│  │   Checks         │    │  Codebase        │    │   Context        │  │
│  │                  │    │  Grounding       │    │   Assessment     │  │
│  └──────────────────┘    └──────────────────┘    └──────────────────┘  │
│         │                        │                        │             │
│         ▼                        ▼                        ▼             │
│  ┌──────────────────┐    ┌──────────────────┐    ┌──────────────────┐  │
│  │ detect-codebase  │    │  /ride skill     │    │ assess-discovery │  │
│  │     .sh          │    │  (if needed)     │    │   -context.sh    │  │
│  └──────────────────┘    └──────────────────┘    └──────────────────┘  │
│         │                        │                        │             │
│         │                        ▼                        │             │
│         │                ┌──────────────────┐             │             │
│         │                │ grimoires/loa/   │             │             │
│         │                │   reality/       │◀────────────┘             │
│         │                │   ├── extracted- │   (loaded as context)    │
│         │                │   │   prd.md     │                          │
│         │                │   ├── extracted- │                          │
│         │                │   │   sdd.md     │                          │
│         │                │   └── ...        │                          │
│         │                └──────────────────┘                          │
│         │                                                               │
│         └───────────────────────┐                                       │
│                                 ▼                                       │
│                    ┌────────────────────────┐                          │
│                    │   Phase 0-8:           │                          │
│                    │   Discovery Interview   │                          │
│                    │   & PRD Generation      │                          │
│                    └────────────────────────┘                          │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### 1.2 Component Responsibilities

| Component | Responsibility | Location |
|-----------|---------------|----------|
| `detect-codebase.sh` | Fast detection of GREENFIELD vs BROWNFIELD | `.claude/scripts/` |
| `plan-and-analyze.md` | Command definition with context_files | `.claude/commands/` |
| `discovering-requirements/SKILL.md` | Workflow orchestration incl. Phase -0.5 | `.claude/skills/` |
| `/ride` skill | Full codebase analysis (existing) | `.claude/skills/riding-codebase/` |
| Reality files | Cached codebase analysis output | `grimoires/loa/reality/` |

### 1.3 Data Flow

```
1. User invokes /plan-and-analyze
        │
        ▼
2. Pre-flight: detect-codebase.sh runs
        │
        ├─── GREENFIELD ──▶ Skip to Phase -1 (zero latency)
        │
        └─── BROWNFIELD
                │
                ├─── reality/ exists AND <7 days old ──▶ Use cached reality
                │
                └─── reality/ missing OR >7 days old
                        │
                        ▼
                3. Execute /ride skill (5-15 min)
                        │
                        ▼
                4. reality/ files created
                        │
                        ▼
5. Phase -1: Context Assessment
   - Loads reality/ files (priority 1)
   - Loads context/ files (priority 2)
        │
        ▼
6. Phase 0-7: Discovery with codebase awareness
        │
        ▼
7. Phase 8: PRD generation with [CODE:file:line] citations
```

---

## 2. Component Design

### 2.1 detect-codebase.sh

**Purpose**: Fast detection of whether a codebase is GREENFIELD or BROWNFIELD.

**Location**: `.claude/scripts/detect-codebase.sh`

**Interface**:
```bash
# Input: None (operates on cwd)
# Output: JSON to stdout
# Exit: Always 0 (errors reported in JSON)

./detect-codebase.sh
```

**Output Schema**:
```json
{
  "type": "GREENFIELD|BROWNFIELD",
  "files": 47,
  "lines": 3200,
  "language": "typescript",
  "paths_found": ["src/", "lib/"],
  "reality_exists": true,
  "reality_age_days": 3,
  "error": null
}
```

**Algorithm**:
```bash
#!/usr/bin/env bash
# detect-codebase.sh - Fast brownfield detection

set -euo pipefail

# Source extensions to detect
SOURCE_EXTENSIONS="ts|tsx|js|jsx|py|go|rs|java|rb|php|cs|cpp|c|h|swift|kt"

# Directories to exclude
EXCLUDES="node_modules|vendor|.git|dist|build|__pycache__|target|.next|.nuxt|.venv|venv"

# Paths to check for source files
SOURCE_PATHS="src lib app packages . cmd pkg internal"

# Thresholds
MIN_FILES=10
MIN_LINES=500

# Initialize counters
total_files=0
total_lines=0
primary_lang=""
paths_found=()

# Check reality directory
reality_exists=false
reality_age_days=999
if [[ -d "grimoires/loa/reality" ]]; then
  reality_file="grimoires/loa/reality/extracted-prd.md"
  if [[ -f "$reality_file" ]]; then
    reality_exists=true
    # Calculate age in days
    file_mtime=$(stat -c %Y "$reality_file" 2>/dev/null || stat -f %m "$reality_file")
    now=$(date +%s)
    age_seconds=$((now - file_mtime))
    reality_age_days=$((age_seconds / 86400))
  fi
fi

# Count source files and lines
for path in $SOURCE_PATHS; do
  if [[ -d "$path" ]]; then
    count=$(find "$path" -type f \
      -regextype posix-extended \
      -regex ".*\.($SOURCE_EXTENSIONS)$" \
      ! -path "*/$EXCLUDES/*" \
      2>/dev/null | wc -l)

    if [[ $count -gt 0 ]]; then
      paths_found+=("$path/")
      total_files=$((total_files + count))

      # Count lines
      lines=$(find "$path" -type f \
        -regextype posix-extended \
        -regex ".*\.($SOURCE_EXTENSIONS)$" \
        ! -path "*/$EXCLUDES/*" \
        -exec wc -l {} + 2>/dev/null | tail -1 | awk '{print $1}')
      total_lines=$((total_lines + lines))
    fi
  fi
done

# Determine primary language (most common extension)
if [[ $total_files -gt 0 ]]; then
  primary_lang=$(find . -type f \
    -regextype posix-extended \
    -regex ".*\.($SOURCE_EXTENSIONS)$" \
    ! -path "*/$EXCLUDES/*" \
    2>/dev/null | \
    sed 's/.*\.//' | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')
fi

# Determine type
if [[ $total_files -ge $MIN_FILES ]] || [[ $total_lines -ge $MIN_LINES ]]; then
  type="BROWNFIELD"
else
  type="GREENFIELD"
fi

# Output JSON
cat <<EOF
{
  "type": "$type",
  "files": $total_files,
  "lines": $total_lines,
  "language": "$primary_lang",
  "paths_found": $(printf '%s\n' "${paths_found[@]:-}" | jq -R . | jq -s .),
  "reality_exists": $reality_exists,
  "reality_age_days": $reality_age_days,
  "error": null
}
EOF
```

**Performance**: <5 seconds on typical codebases (using `find` with early exit patterns).

### 2.2 plan-and-analyze.md Updates

**Changes to Command Definition**:

```yaml
---
name: "plan-and-analyze"
version: "3.0.0"  # Bump from 2.1.0
description: |
  Launch PRD discovery with automatic context ingestion.
  For brownfield projects, automatically runs /ride to ground PRD in codebase reality.
  Reads existing documentation from grimoires/loa/context/ before interviewing.
  Initializes Sprint Ledger and creates development cycle automatically.

arguments:
  - name: "fresh"
    type: "flag"
    required: false
    description: "Force re-run of /ride even if recent reality exists"

agent: "discovering-requirements"
agent_path: "skills/discovering-requirements/"

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

  - path: "grimoires/loa/consistency-report.md"
    required: false
    priority: 1
    purpose: "Code vs docs consistency analysis"

  # User context files (secondary priority)
  - path: "grimoires/loa/context/*.md"
    required: false
    recursive: true
    priority: 2
    purpose: "Pre-existing project documentation for synthesis"

  # Nested context
  - path: "grimoires/loa/context/**/*.md"
    required: false
    priority: 2
    purpose: "Meeting notes, references, nested docs"

  # Integration context (if exists)
  - path: "grimoires/loa/a2a/integration-context.md"
    required: false
    priority: 3
    purpose: "Organizational context and conventions"

  # Ledger (for cycle awareness)
  - path: "grimoires/loa/ledger.json"
    required: false
    purpose: "Sprint Ledger for cycle management"

pre_flight:
  # NEW: Codebase detection
  - check: "script"
    script: ".claude/scripts/detect-codebase.sh"
    store_result: "codebase_detection"
    purpose: "Detect codebase type and reality file status"

  - check: "file_not_exists"
    path: "grimoires/loa/prd.md"
    error: "PRD already exists. Delete or rename grimoires/loa/prd.md to restart discovery."
    soft: true

  - check: "script"
    script: ".claude/scripts/assess-discovery-context.sh"
    store_result: "context_assessment"
    purpose: "Assess available context for synthesis strategy"

outputs:
  - path: "grimoires/loa/prd.md"
    type: "file"
    description: "Product Requirements Document"
  - path: "grimoires/loa/ledger.json"
    type: "file"
    description: "Sprint Ledger (created if needed)"
  - path: "grimoires/loa/reality/"
    type: "directory"
    description: "Codebase reality extraction (if brownfield)"

mode:
  default: "foreground"
  allow_background: false
---
```

### 2.3 discovering-requirements/SKILL.md Updates

**New Section: Phase -0.5 Codebase Grounding**

Insert after `<kernel_framework>` section, before `<workflow>`:

```markdown
<codebase_grounding>
## Phase -0.5: Codebase Grounding (Brownfield Projects)

**Trigger**: Pre-flight `codebase_detection.type == "BROWNFIELD"`

This phase automatically grounds the PRD in codebase reality by executing `/ride`.

### Decision Tree

```
codebase_detection.type?
├── GREENFIELD → Skip Phase -0.5, proceed to Phase -1
│
└── BROWNFIELD
    │
    ├── codebase_detection.reality_exists == true
    │   │
    │   ├── reality_age_days <= 7 → Use cached reality
    │   │   Output: "Using recent codebase analysis (N days old)"
    │   │
    │   └── reality_age_days > 7 → Stale reality warning
    │       Use AskUserQuestion:
    │       - "Re-run /ride for fresh analysis (recommended)"
    │       - "Proceed with existing analysis (faster)"
    │
    └── reality_exists == false → Execute /ride
        Output: "Running /ride to ground PRD in codebase reality..."
```

### Step 1: Display Detection Results

For BROWNFIELD:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Phase -0.5: Codebase Grounding
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Detected: {files} source files, ~{lines} lines ({language})
Paths: {paths_found}

{action_message}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Step 2: Execute /ride (if needed)

When `/ride` must run:

1. Invoke `/ride` skill programmatically (not via command)
2. Show progress updates to user
3. Set 20-minute timeout
4. Handle errors with recovery options

**Progress Feedback**:
```
Running /ride to ground your PRD in codebase reality...
This ensures your PRD reflects what already exists.
Estimated time: 5-10 minutes

Phase 1/10: Preflight & Integrity Check... ✓
Phase 2/10: Code Reality Extraction...
```

### Step 3: Error Recovery

If `/ride` fails or times out:

```
Use AskUserQuestion with options:
1. "Retry /ride analysis"
2. "Skip and proceed without codebase grounding (not recommended)"
3. "Abort /plan-and-analyze"
```

**If Skip selected**: Log warning to NOTES.md:
```markdown
## Blockers
- [ ] [UNRESOLVED] Codebase grounding skipped - PRD may miss existing functionality
```

### Step 4: Validate and Load Reality

After `/ride` completes:

1. Verify reality files exist:
   - `grimoires/loa/reality/extracted-prd.md`
   - `grimoires/loa/reality/extracted-sdd.md`
2. Files are auto-loaded via context_files mechanism
3. Proceed to Phase -1

### Configuration

Check `.loa.config.yaml` for overrides:

```yaml
plan_and_analyze:
  codebase_grounding:
    enabled: true                 # Set false to disable Phase -0.5
    reality_staleness_days: 7     # Cache validity period
    ride_timeout_minutes: 20      # Abort /ride after this
    skip_on_ride_error: false     # Auto-skip on error (not recommended)
```

### Greenfield Fast Path

For GREENFIELD projects (no message, no delay):
- Skip Phase -0.5 entirely
- Proceed directly to Phase -1
- Zero added latency
</codebase_grounding>
```

**Update to Phase 0: Context Synthesis**

Add to Step 1 (Ingest All Context):

```markdown
### Step 1: Ingest All Context

**Priority Order**:
1. **Reality files** (from /ride): `grimoires/loa/reality/*.md`
   - These represent CODE TRUTH and take precedence
   - Use `[CODE:file:line]` citation format
2. **User context**: `grimoires/loa/context/*.md`
   - May conflict with reality - flag for resolution
3. **Integration context**: `grimoires/loa/a2a/integration-context.md`

**If reality files exist**, present codebase understanding first:

```markdown
## What I've Learned From Your Codebase

Based on `/ride` analysis of {files} source files:

### Existing Architecture
> From reality/extracted-sdd.md: "{architecture summary}"

Components: {component list}
Primary patterns: {patterns}

### Existing Features
> From reality/extracted-prd.md: "{features summary}"

{feature list with file references}

### What You're Proposing to Add
Based on your context/, you want to: {new feature summary}

I'll ensure the PRD accounts for existing code and proposes only new functionality.
```

**Conflict Resolution**:
If context/ and reality/ contradict:
- List specific contradictions
- Reality (code) takes precedence
- Ask user to confirm context is still relevant
```

---

## 3. Integration Points

### 3.1 /ride Skill Integration

The `/ride` skill is invoked programmatically, not via command dispatch.

**Invocation Method** (within discovering-requirements skill):

```markdown
When Phase -0.5 requires /ride execution:

1. Load riding-codebase skill instructions
2. Execute with default parameters:
   - No target argument (use cwd)
   - No phase restriction (full analysis)
   - No dry-run
3. Monitor for completion or timeout (20 min)
4. Capture any errors for recovery flow
```

**Why not command dispatch?**
- Command dispatch creates a new agent context
- Skill invocation preserves parent context
- Allows seamless error handling and state preservation

### 3.2 Context Files Loading

The `context_files` mechanism already handles file loading by priority.

**New Priority Scheme**:
```yaml
priority: 1  # Reality files (from /ride)
priority: 2  # User context files
priority: 3  # Integration context
```

**Loader Behavior**:
- Files loaded in priority order
- Higher priority files inform understanding of lower priority
- Conflicts flagged during Phase 0 synthesis

### 3.3 Configuration Integration

**New Config Section** (`.loa.config.yaml`):

```yaml
# Existing sections...

plan_and_analyze:
  codebase_grounding:
    enabled: true                    # Master toggle for Phase -0.5
    reality_staleness_days: 7        # Days before reality is considered stale
    ride_timeout_minutes: 20         # Abort /ride after this time
    skip_on_ride_error: false        # If true, auto-skip on error
```

**Reading Config** (in skill):
```bash
# Check if enabled
enabled=$(yq eval '.plan_and_analyze.codebase_grounding.enabled // true' .loa.config.yaml 2>/dev/null || echo "true")

# Get staleness threshold
staleness=$(yq eval '.plan_and_analyze.codebase_grounding.reality_staleness_days // 7' .loa.config.yaml 2>/dev/null || echo "7")
```

---

## 4. Error Handling

### 4.1 Error Categories

| Category | Trigger | Recovery |
|----------|---------|----------|
| Detection Error | `detect-codebase.sh` fails | Treat as GREENFIELD (safe default) |
| /ride Timeout | Exceeds 20 minutes | Offer retry/skip/abort |
| /ride Failure | Non-zero exit | Offer retry/skip/abort |
| Reality Corrupt | Files exist but unparseable | Re-run /ride |
| Config Missing | No .loa.config.yaml | Use defaults |

### 4.2 Recovery Flows

**Detection Error**:
```
detect-codebase.sh exit != 0 OR JSON parse fails
    │
    └──▶ Log warning: "Codebase detection failed, treating as greenfield"
         Proceed to Phase -1 (safe default)
```

**Ride Timeout/Failure**:
```
/ride fails OR timeout
    │
    └──▶ AskUserQuestion:
         ┌────────────────────────────────────────┐
         │ ⚠️ Codebase analysis encountered an    │
         │    error: {error_message}              │
         │                                        │
         │ Options:                               │
         │ 1. Retry /ride analysis                │
         │ 2. Skip (proceed without grounding)   │
         │ 3. Abort /plan-and-analyze            │
         └────────────────────────────────────────┘

         If Retry: Re-execute /ride
         If Skip: Log warning, proceed to Phase -1
         If Abort: Exit with error
```

### 4.3 Graceful Degradation

The system degrades gracefully at each failure point:

| Failure | Degradation |
|---------|-------------|
| Detection fails | Treat as greenfield (no /ride) |
| /ride fails + skip | PRD without codebase awareness |
| Reality files missing | Phase 0 uses only context/ |
| Config missing | Use hardcoded defaults |

---

## 5. Testing Strategy

### 5.1 Unit Tests (bats)

**`test-detect-codebase.bats`**:

```bash
#!/usr/bin/env bats

setup() {
  TEST_DIR=$(mktemp -d)
  cd "$TEST_DIR"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "empty directory is GREENFIELD" {
  run .claude/scripts/detect-codebase.sh
  [ "$status" -eq 0 ]
  [[ $(echo "$output" | jq -r '.type') == "GREENFIELD" ]]
}

@test "10+ source files is BROWNFIELD" {
  mkdir src
  for i in {1..15}; do
    echo "// file $i" > "src/file$i.ts"
  done

  run .claude/scripts/detect-codebase.sh
  [ "$status" -eq 0 ]
  [[ $(echo "$output" | jq -r '.type') == "BROWNFIELD" ]]
}

@test "500+ lines is BROWNFIELD" {
  mkdir src
  for i in {1..10}; do
    seq 1 60 > "src/file$i.ts"
  done

  run .claude/scripts/detect-codebase.sh
  [ "$status" -eq 0 ]
  [[ $(echo "$output" | jq -r '.type') == "BROWNFIELD" ]]
}

@test "node_modules excluded" {
  mkdir -p node_modules/pkg
  for i in {1..100}; do
    echo "// dep" > "node_modules/pkg/file$i.js"
  done

  run .claude/scripts/detect-codebase.sh
  [ "$status" -eq 0 ]
  [[ $(echo "$output" | jq -r '.type') == "GREENFIELD" ]]
}

@test "reality_exists detected" {
  mkdir -p grimoires/loa/reality
  echo "# PRD" > grimoires/loa/reality/extracted-prd.md

  run .claude/scripts/detect-codebase.sh
  [ "$status" -eq 0 ]
  [[ $(echo "$output" | jq -r '.reality_exists') == "true" ]]
}

@test "reality_age_days calculated" {
  mkdir -p grimoires/loa/reality
  echo "# PRD" > grimoires/loa/reality/extracted-prd.md
  touch -d "3 days ago" grimoires/loa/reality/extracted-prd.md

  run .claude/scripts/detect-codebase.sh
  [ "$status" -eq 0 ]
  [[ $(echo "$output" | jq -r '.reality_age_days') -le 4 ]]
}
```

### 5.2 Integration Tests

| Test Case | Setup | Expected |
|-----------|-------|----------|
| Greenfield + no context | Empty repo | Skip Phase -0.5, full interview |
| Brownfield + no reality | 50 source files | Run /ride, then interview |
| Brownfield + fresh reality | 50 files, reality <7 days | Skip /ride, use cached |
| Brownfield + stale reality | 50 files, reality >7 days | Prompt for re-run |
| Brownfield + /ride timeout | Mock 25 min /ride | Recovery prompt |

### 5.3 Manual Testing Checklist

- [ ] Greenfield repo: zero added latency confirmed
- [ ] Small brownfield (<100 files): /ride completes <5 min
- [ ] Medium brownfield (100-500 files): /ride completes <10 min
- [ ] Large brownfield (>500 files): /ride completes <15 min
- [ ] Cached reality used when <7 days old
- [ ] Stale warning shown when >7 days old
- [ ] Error recovery flow works
- [ ] Config override disables feature

---

## 6. Performance Considerations

### 6.1 Performance Targets

| Operation | Target | Hard Limit | Notes |
|-----------|--------|------------|-------|
| detect-codebase.sh | <3s | 5s | find with early exit |
| Reality staleness check | <1s | 2s | Single stat call |
| /ride execution | 5-15 min | 20 min | Depends on codebase size |
| Context loading | <2s | 5s | File I/O |

### 6.2 Optimization Strategies

**detect-codebase.sh Optimizations**:
1. Use `find` with `-quit` after threshold reached (early exit)
2. Process paths in order of likelihood (src/ first)
3. Cache results if called multiple times per session

**/ride Performance**:
- Not optimized (accuracy over speed is explicit design goal)
- 20-minute timeout prevents runaway execution
- Progress feedback maintains user confidence

### 6.3 Caching Strategy

**Reality Cache**:
- Validity: 7 days (configurable)
- Invalidation: Manual via `--fresh` flag
- Storage: `grimoires/loa/reality/`

**No Additional Caching**:
- Detection results are fast enough (<5s) to not cache
- Context files loaded fresh each session

---

## 7. Security Considerations

### 7.1 Script Safety

**detect-codebase.sh**:
- No user input (operates on cwd)
- No network access
- No file writes
- `set -euo pipefail` for strict mode

### 7.2 /ride Safety

- Inherits existing /ride security model
- Read-only access to App Zone
- Write access only to State Zone (grimoires/)
- No external network calls

### 7.3 Configuration Safety

- Config file is user-owned (can't be modified by framework)
- Defaults are safe (enabled, 7-day cache, no auto-skip)
- Invalid config falls back to defaults

---

## 8. Migration & Rollout

### 8.1 Backward Compatibility

- **Greenfield projects**: Zero behavior change
- **Existing brownfield users**: New behavior (automatic /ride)
- **Opt-out**: `codebase_grounding.enabled: false` in config

### 8.2 Rollout Plan

1. **Sprint 1**: Core implementation
   - detect-codebase.sh
   - Skill workflow updates
   - Context file priority

2. **Sprint 2**: Hardening
   - Error recovery
   - Configuration options
   - Documentation updates

3. **v1.6.0 Release**: Feature complete

### 8.3 Feature Flag

During development, can be disabled via config:

```yaml
plan_and_analyze:
  codebase_grounding:
    enabled: false  # Disable until stable
```

---

## 9. File Inventory

### 9.1 New Files

| File | Purpose |
|------|---------|
| `.claude/scripts/detect-codebase.sh` | Codebase type detection |
| `.claude/scripts/tests/test-detect-codebase.bats` | Unit tests |

### 9.2 Modified Files

| File | Changes |
|------|---------|
| `.claude/commands/plan-and-analyze.md` | Add context_files for reality, add pre-flight check |
| `.claude/skills/discovering-requirements/SKILL.md` | Add Phase -0.5 section |
| `CLAUDE.md` | Document new workflow |
| `PROCESS.md` | Update Phase 1 description |

### 9.3 No Changes Required

| File | Reason |
|------|--------|
| `.claude/commands/ride.md` | Existing functionality unchanged |
| `.claude/skills/riding-codebase/SKILL.md` | Invoked as-is |
| `grimoires/loa/reality/` | Output directory, already exists |

---

## 10. Appendices

### Appendix A: Full detect-codebase.sh Script

See Section 2.1 for complete implementation.

### Appendix B: Context Priority Matrix

| Priority | Source | Trust Level | Citation Format |
|----------|--------|-------------|-----------------|
| 1 | reality/extracted-prd.md | CODE TRUTH | `[CODE:file:line]` |
| 1 | reality/extracted-sdd.md | CODE TRUTH | `[CODE:file:line]` |
| 1 | consistency-report.md | CODE TRUTH | `[DRIFT:section]` |
| 2 | context/*.md | User claims | `> From file.md:line` |
| 3 | integration-context.md | Org context | `> From integration:line` |

### Appendix C: Error Messages

| Code | Message | User Action |
|------|---------|-------------|
| E001 | "Codebase detection failed" | Automatic fallback to greenfield |
| E002 | "/ride timed out after 20 minutes" | Retry, skip, or abort |
| E003 | "/ride failed: {error}" | Retry, skip, or abort |
| E004 | "Reality files corrupt or missing" | Re-run /ride |

---

**SDD Status**: Ready for `/sprint-plan`
