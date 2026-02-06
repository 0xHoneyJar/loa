---
name: build
description: Build the current sprint
output: Implemented code
command_type: workflow
---

# /build - Smart Sprint Builder

## Purpose

Build the current sprint. Auto-detects which sprint needs work and delegates to `/implement`. Zero arguments needed — just type `/build`.

**This is a Golden Path command.** It routes to the existing truename command (`/implement sprint-N`) with automatic sprint detection.

## Invocation

```
/build              # Build current sprint (auto-detected)
/build sprint-3     # Override: build specific sprint
```

## Workflow

### 1. Check Prerequisites

Verify a sprint plan exists:

```bash
source .claude/scripts/golden-path.sh
phase=$(golden_detect_plan_phase)
```

If `phase != "complete"`, show:
```
No sprint plan found. You need to plan before building.

Next: /plan
```

### 2. Detect Current Sprint

```bash
sprint=$(golden_detect_sprint)
```

If user provided an override argument (e.g., `sprint-3`), use that instead.

### 3. Route to Truename

| Condition | Action |
|-----------|--------|
| Sprint found | Execute `/implement {sprint}` |
| No sprint (all complete) | Show: "All sprints complete! Next: /review" |

### 4. Display Context

Before delegating, show what's happening:
```
Building sprint-2 (auto-detected)
→ Running /implement sprint-2
```

## Arguments

| Argument | Description |
|----------|-------------|
| `sprint-N` | Override: build a specific sprint |
| (none) | Auto-detect current sprint |

## Error Handling

| Error | Response |
|-------|----------|
| No sprint plan | "No sprint plan found. Run /plan first." |
| All sprints complete | "All sprints complete! Next: /review" |
| Invalid sprint ID | "Sprint not found in plan. Available: sprint-1, sprint-2, sprint-3" |

## Examples

### Auto-Detect
```
/build

  Building sprint-2 (auto-detected)
  Sprint 1: ✓ complete
  Sprint 2: ○ in progress  ← you are here
  Sprint 3: ○ not started

  → Running /implement sprint-2
```

### Override
```
/build sprint-3

  Building sprint-3 (manual override)
  → Running /implement sprint-3
```

### All Complete
```
/build

  All sprints complete!
  Sprint 1: ✓ complete
  Sprint 2: ✓ complete
  Sprint 3: ✓ complete

  Next: /review
```
