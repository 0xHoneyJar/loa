# Mode Manager Library

This library provides patterns for managing execution modes (Creative vs Secure) and implementing mode confirmation gates in Loa phases.

---

## Overview

Loa supports two execution modes:

| Mode | Purpose | Characteristics |
|------|---------|-----------------|
| **Creative** | Exploration, design, iteration | Faster feedback, fewer gates, broader exploration |
| **Secure** | Validation, auditing, deployment | HITL gates, stricter validation, security focus |

Mode determines agent behavior, available skills, and confirmation requirements.

---

## Mode State File

**Location**: `.claude/.mode`

**Schema**:
```json
{
  "current_mode": "creative",
  "set_at": "2025-12-19T10:30:00Z",
  "project_type": "game-design",
  "mode_switches": [
    {
      "from": "creative",
      "to": "secure",
      "reason": "Entering review phase",
      "phase": "review-sprint",
      "timestamp": "2025-12-19T14:00:00Z",
      "confirmed": true
    }
  ]
}
```

---

## Phase Mode Requirements

Different phases have different mode requirements based on their nature:

| Phase | Mode Rule | Rationale |
|-------|-----------|-----------|
| `/plan-and-analyze` | Project type default | Discovery benefits from creative exploration |
| `/architect` | Project type default | Architecture benefits from broad exploration |
| `/sprint-plan` | Project type default | Planning is creative work |
| `/implement` | Project type default | Implementation varies by project |
| `/review-sprint` | **Always Secure** | Code review requires rigorous validation |
| `/audit-sprint` | **Always Secure** | Security audits require maximum scrutiny |
| `/audit` | **Always Secure** | Codebase audits require security focus |
| `/audit-deployment` | **Always Secure** | Infrastructure review is security-critical |
| `/deploy-production` | **Always Secure** | Production deployment requires HITL gates |

### Project Type Defaults

| Project Type | Default Mode |
|--------------|--------------|
| `frontend` | Creative |
| `game-design` | Creative |
| `backend` | Creative |
| `cross-domain` | Creative |
| `contracts` | Secure |
| `indexer` | Secure |

---

## Mode Check Flow

At the start of each phase, run this flow:

```
Phase Start
    │
    ▼
Read .claude/.mode
    │
    ├─► File exists
    │       │
    │       ▼
    │   Parse current_mode
    │       │
    │       ▼
    │   Determine required_mode for this phase
    │       │
    │       ├─► current_mode == required_mode
    │       │       │
    │       │       └─► Proceed normally
    │       │
    │       └─► current_mode != required_mode
    │               │
    │               └─► Show Mode Confirmation Gate
    │                       │
    │                       ├─► User confirms switch
    │                       │       │
    │                       │       └─► Update .mode, proceed
    │                       │
    │                       └─► User declines
    │                               │
    │                               └─► Show warning, proceed anyway
    │
    └─► File missing
            │
            └─► Create with defaults, proceed
```

---

## Mode Confirmation Gate

When a mode mismatch is detected, show this confirmation:

```markdown
## Mode Mismatch Detected

**Current mode**: Creative
**Phase requires**: Secure

This phase ({phase_name}) operates in **Secure mode** which adds:
- Human-in-the-loop confirmation gates
- Stricter validation requirements
- Security-focused analysis

**Switch to Secure mode?**

[Yes, switch to Secure] [Stay in Creative mode]
```

### Using AskUserQuestion

Implement the gate using the AskUserQuestion tool:

```markdown
Use AskUserQuestion with:
- question: "This phase requires Secure mode. Switch from Creative to Secure?"
- header: "Mode"
- options:
  1. "Yes, switch" - "Enable HITL gates and stricter validation"
  2. "Stay in Creative" - "Proceed with current mode (not recommended for this phase)"
```

---

## Mode Switch Implementation

### Reading Current Mode

```bash
# Read mode file
if [ -f ".claude/.mode" ]; then
    CURRENT_MODE=$(cat .claude/.mode | jq -r '.current_mode')
    PROJECT_TYPE=$(cat .claude/.mode | jq -r '.project_type')
else
    CURRENT_MODE="unknown"
    PROJECT_TYPE="unknown"
fi
```

### Determining Required Mode

```bash
# Determine required mode for phase
get_required_mode() {
    local phase="$1"
    local project_type="$2"

    case "$phase" in
        review-sprint|audit-sprint|audit|audit-deployment|deploy-production)
            echo "secure"
            ;;
        plan-and-analyze|architect|sprint-plan|implement)
            # Use project type default
            case "$project_type" in
                contracts|indexer)
                    echo "secure"
                    ;;
                *)
                    echo "creative"
                    ;;
            esac
            ;;
        *)
            echo "creative"
            ;;
    esac
}
```

### Updating Mode File

```bash
# Switch mode and record in history
switch_mode() {
    local from_mode="$1"
    local to_mode="$2"
    local reason="$3"
    local phase="$4"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Update mode file with jq
    jq --arg to "$to_mode" \
       --arg ts "$timestamp" \
       --arg from "$from_mode" \
       --arg reason "$reason" \
       --arg phase "$phase" '
        .current_mode = $to |
        .set_at = $ts |
        .mode_switches += [{
            "from": $from,
            "to": $to,
            "reason": $reason,
            "phase": $phase,
            "timestamp": $ts,
            "confirmed": true
        }]
    ' .claude/.mode > .claude/.mode.tmp && mv .claude/.mode.tmp .claude/.mode
}
```

---

## Mode-Specific Behavior

### Creative Mode

When in Creative mode:
- Faster iteration cycles
- Broader exploration allowed
- Fewer confirmation gates
- More permissive validation
- Focus on discovery and design

**Skills activated**:
- `lab-creative-mode-operations`
- Design-focused skills

### Secure Mode

When in Secure mode:
- HITL confirmation gates
- Stricter validation
- Security-first analysis
- Audit trail requirements
- Production-ready focus

**Skills activated**:
- `lab-security-mode-operations`
- `lib-hitl-gate-patterns`
- Audit-focused skills

---

## Warning on Mode Mismatch

If user declines mode switch, show warning:

```markdown
**Warning**: Proceeding in Creative mode for a phase that recommends Secure mode.

Phase: `/review-sprint`
Current: Creative | Recommended: Secure

This may result in:
- Less rigorous code review
- Missing security considerations
- Reduced audit trail

Continuing at your discretion...
```

---

## Mode Recovery

### Missing Mode File

If `.claude/.mode` is missing:

```bash
# Create default mode file based on integration-context.md
create_default_mode_file() {
    local project_type="unknown"

    # Try to read from integration-context.md
    if [ -f "loa-grimoire/a2a/integration-context.md" ]; then
        project_type=$(grep -A1 "Project Type" loa-grimoire/a2a/integration-context.md | tail -1 | sed 's/.*: //' | tr -d ' ')
    fi

    # Determine default mode
    local default_mode="creative"
    case "$project_type" in
        contracts|indexer)
            default_mode="secure"
            ;;
    esac

    # Create mode file
    cat > .claude/.mode << EOF
{
  "current_mode": "$default_mode",
  "set_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "project_type": "$project_type",
  "mode_switches": []
}
EOF

    echo "Created .claude/.mode with mode=$default_mode for project_type=$project_type"
}
```

### Corrupted Mode File

If mode file is corrupted (invalid JSON):

1. Log warning about corruption
2. Read project type from `integration-context.md`
3. Recreate mode file with defaults
4. Proceed with phase

---

## Integration with Phase Commands

Each phase command should include mode checking at the start:

```markdown
## Phase 0: Mode Check

1. Read current mode from `.claude/.mode`
2. Determine required mode for this phase
3. If mismatch:
   - Show mode confirmation gate using AskUserQuestion
   - If confirmed: Update mode file, record switch
   - If declined: Show warning, proceed
4. Proceed with phase execution
```

### Example Integration in `/review-sprint`

```markdown
## Pre-Phase: Mode Confirmation

This phase requires **Secure mode** for rigorous code review.

1. Read `.claude/.mode`
2. If `current_mode` is not "secure":
   - Use AskUserQuestion:
     Question: "Code review requires Secure mode. Switch now?"
     Options: ["Yes, switch to Secure", "Stay in current mode"]
   - If "Yes": Update .claude/.mode, proceed
   - If "Stay": Show warning, proceed anyway
3. Proceed with review
```

---

## Analytics Integration

Mode switches should be tracked in analytics (Sprint 4 feature):

```json
{
  "mode_switches": [
    {
      "from": "creative",
      "to": "secure",
      "phase": "review-sprint",
      "timestamp": "2025-12-19T14:00:00Z"
    }
  ]
}
```

This enables:
- Understanding mode usage patterns
- Identifying phases that trigger most switches
- Tracking team mode preferences

---

*Library created as part of Sprint 2: Context Injection*
*See SDD section 3.2 for mode architecture details*
