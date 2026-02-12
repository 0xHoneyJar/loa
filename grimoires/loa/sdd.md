# SDD: Onboarding UX — Hive-Inspired Improvements

**Version**: 1.0.0
**Status**: Draft
**Author**: Architecture Phase (architect)
**PRD**: `grimoires/loa/prd.md` (cycle-004)
**Date**: 2026-02-12

---

## 1. Architecture Overview

This cycle modifies 4 existing components and adds 6 new ones. All changes follow the three-zone model: new data files go in System Zone (`.claude/`), new command files go in System Zone (`.claude/commands/`), and runtime output goes to State Zone (`grimoires/`).

### Component Map

```
┌──────────────────────────────────────────────────────────────────────┐
│  MODIFIED COMPONENTS                                                  │
│                                                                        │
│  .claude/commands/loa.md ──────────── FR-1: Dynamic AskUserQuestion   │
│                                        menu with state-aware routing   │
│                                                                        │
│  .claude/scripts/mount-loa.sh ──────── FR-2: Post-mount verification  │
│                                        sequence after sync_zones()     │
│                                                                        │
│  .claude/scripts/golden-path.sh ────── FR-1: New helper function      │
│                                        golden_menu_options()           │
│                                                                        │
│  .claude/commands/plan.md ──────────── FR-4: Archetype selection      │
│                                        before Phase 1 interview       │
├──────────────────────────────────────────────────────────────────────┤
│  NEW COMPONENTS                                                        │
│                                                                        │
│  .claude/commands/loa-setup.md ──────── FR-3: Setup wizard command    │
│  .claude/scripts/loa-setup-check.sh ── FR-3: Validation engine       │
│  .claude/data/archetypes/*.yaml ──────  FR-4: Project templates       │
├──────────────────────────────────────────────────────────────────────┤
│  DEFERRED (P2/P3)                                                      │
│                                                                        │
│  FR-5: Use-case qualification ── Thin addition to /plan               │
│  FR-6: Auto-format construct ── Ships in loa-constructs repo          │
└──────────────────────────────────────────────────────────────────────┘
```

### Data Flow

```
User invokes /loa
  │
  ├── golden-path.sh → golden_menu_options() → state + option array
  │     ├── golden_detect_plan_phase()
  │     ├── golden_detect_sprint()
  │     ├── golden_detect_review_target()
  │     ├── golden_detect_active_bug()
  │     └── golden_check_ship_ready()
  │
  ├── loa-status.sh → version info + workflow state
  │
  ├── loa-doctor.sh --quick → health summary
  │
  └── AskUserQuestion ← dynamic menu from golden_menu_options()
       │
       └── User selects → Skill tool invocation (or fallback text)
```

---

## 2. Detailed Design

### 2.1 FR-1: Context-Aware Action Menu in `/loa`

#### 2.1.1 State Machine Specification

The menu state machine has **9 states** with deterministic transitions based on file presence. This addresses Flatline blocker SKP-002.

```
┌──────────────────────────────────────────────────────┐
│  STATE MACHINE — golden_detect_workflow_state()       │
│                                                        │
│  Inputs (file presence checks):                        │
│    P = prd.md exists                                   │
│    S = sdd.md exists                                   │
│    T = sprint.md exists                                │
│    B = active bug in .run/bugs/                        │
│    I = incomplete sprint exists                        │
│    R = sprint needs review                             │
│    A = sprint needs audit                              │
│    D = all sprints COMPLETED                           │
│                                                        │
│  Priority order (first match wins):                    │
│    1. B=true           → bug_active                    │
│    2. P=false          → initial                       │
│    3. S=false          → prd_created                   │
│    4. T=false          → sdd_created                   │
│    5. I=true, R=false  → implementing                  │
│    6. R=true, A=false  → reviewing                     │
│    7. A=true           → auditing                      │
│    8. D=true           → complete                      │
│    9. fallback         → sprint_planned                │
│                                                        │
│  Note: State 1 (bug_active) overrides ALL others.      │
│  State 9 catches edge case: sprint.md exists           │
│  but no sprint dirs yet created.                       │
└──────────────────────────────────────────────────────┘
```

#### 2.1.2 Menu Option Mapping

Each state maps to exactly 3 options (AskUserQuestion supports max 4; Slot 4 is always "View all commands"):

| State | Slot 1 (Recommended) | Slot 2 | Slot 3 |
|-------|---------------------|--------|--------|
| `initial` | "Plan a new project" | "Run setup wizard" | "Check system health" |
| `prd_created` | "Continue planning (architecture)" | "View PRD" | "Check system health" |
| `sdd_created` | "Continue planning (sprints)" | "View architecture" | "Check system health" |
| `sprint_planned` | "Build sprint-1" | "Review sprint plan" | "Check system health" |
| `implementing` | "Build sprint-{N}" | "Review sprint-{M}" | "Check system health" |
| `reviewing` | "Review sprint-{N}" | "Continue building" | "Check system health" |
| `auditing` | "Review sprint-{N}" | "Continue building" | "Check system health" |
| `complete` | "Ship this release" | "Plan new cycle" | "Check system health" |
| `bug_active` | "Fix bug: {title}" | "Return to feature sprint" | "Check system health" |

Where `{N}` is from `golden_detect_sprint()`, `{M}` is from `golden_detect_review_target()`, `{title}` is truncated to 40 chars.

#### 2.1.3 New Shell Functions

Add to `golden-path.sh`:

```bash
# Detect workflow state as a single string.
# Returns one of: initial, prd_created, sdd_created, sprint_planned,
#   implementing, reviewing, auditing, complete, bug_active
golden_detect_workflow_state() {
    # Priority 1: Active bug overrides everything
    if golden_detect_active_bug >/dev/null 2>&1; then
        echo "bug_active"
        return
    fi

    # Priority 2-4: Planning phases
    local plan_phase
    plan_phase=$(golden_detect_plan_phase)
    case "${plan_phase}" in
        discovery) echo "initial"; return ;;
        architecture) echo "prd_created"; return ;;
        sprint_planning) echo "sdd_created"; return ;;
    esac

    # Priority 5-8: Sprint states
    local sprint review_target
    sprint=$(golden_detect_sprint)
    review_target=$(golden_detect_review_target)

    if [[ -z "${sprint}" ]]; then
        # All sprints done
        if golden_check_ship_ready >/dev/null 2>&1; then
            echo "complete"
        else
            echo "reviewing"
        fi
        return
    fi

    local sprint_dir="${_GP_A2A_DIR}/${sprint}"
    if [[ ! -d "${sprint_dir}" ]]; then
        echo "sprint_planned"
    elif [[ -n "${review_target}" ]] && _gp_sprint_is_reviewed "${review_target}" 2>/dev/null; then
        echo "auditing"
    elif [[ -n "${review_target}" ]]; then
        echo "reviewing"
    else
        echo "implementing"
    fi
}

# Generate menu options as pipe-delimited lines for agent consumption.
# Each line: label|description|action
# Action is a skill name or special directive.
golden_menu_options() {
    local state
    state=$(golden_detect_workflow_state)

    case "${state}" in
        initial)
            echo "Plan a new project|Gather requirements and design your project|plan"
            echo "Run setup wizard|Check dependencies and configure Loa|loa-setup"
            echo "Check system health|Run full diagnostic check|loa doctor"
            ;;
        prd_created)
            echo "Continue planning (architecture)|Design system architecture from PRD|plan"
            echo "View PRD|Read the current requirements document|read:grimoires/loa/prd.md"
            echo "Check system health|Run full diagnostic check|loa doctor"
            ;;
        sdd_created)
            echo "Continue planning (sprints)|Create sprint plan from architecture|plan"
            echo "View architecture|Read the current design document|read:grimoires/loa/sdd.md"
            echo "Check system health|Run full diagnostic check|loa doctor"
            ;;
        sprint_planned)
            echo "Build sprint-1|Start implementing the first sprint|build"
            echo "Review sprint plan|Read the sprint breakdown|read:grimoires/loa/sprint.md"
            echo "Check system health|Run full diagnostic check|loa doctor"
            ;;
        implementing)
            local sprint
            sprint=$(golden_detect_sprint)
            local review_target
            review_target=$(golden_detect_review_target)
            echo "Build ${sprint}|Continue implementing the current sprint|build"
            if [[ -n "${review_target}" && "${review_target}" != "${sprint}" ]]; then
                echo "Review ${review_target}|Code review and security audit|review"
            else
                echo "Check progress|View detailed sprint status|loa"
            fi
            echo "Check system health|Run full diagnostic check|loa doctor"
            ;;
        reviewing|auditing)
            local review_target
            review_target=$(golden_detect_review_target)
            echo "Review ${review_target}|Code review and security audit|review"
            echo "Continue building|Resume sprint implementation|build"
            echo "Check system health|Run full diagnostic check|loa doctor"
            ;;
        complete)
            echo "Ship this release|Deploy to production and archive cycle|ship"
            echo "Plan new cycle|Archive current cycle and start fresh|archive-cycle"
            echo "Check system health|Run full diagnostic check|loa doctor"
            ;;
        bug_active)
            local active_bug_ref bug_id bug_title
            active_bug_ref=$(golden_detect_active_bug 2>/dev/null)
            bug_id=$(golden_parse_bug_id "${active_bug_ref}")
            local state_file="${PROJECT_ROOT}/.run/bugs/${bug_id}/state.json"
            bug_title=$(jq -r '.bug_title // "Unknown bug"' "${state_file}" 2>/dev/null)
            # Truncate title to 40 chars
            [[ ${#bug_title} -gt 40 ]] && bug_title="${bug_title:0:37}..."
            echo "Fix bug: ${bug_title}|Continue bug fix implementation|build"
            echo "Return to feature sprint|Switch back to planned work|build"
            echo "Check system health|Run full diagnostic check|loa doctor"
            ;;
    esac

    # Slot 4 is always present
    echo "View all commands|See all available Loa commands|help-full"
}
```

#### 2.1.4 loa.md Changes

Replace the existing static AskUserQuestion block (lines 202-215) with:

```markdown
## User Prompts (v1.34.0 — Context-Aware Menu)

After displaying status, generate a dynamic menu:

1. Run `golden_menu_options` from `golden-path.sh` to get state-aware options
2. Parse the pipe-delimited output into AskUserQuestion format
3. Present options to the user

The first option is always the recommended action and should be labeled "(Recommended)".
The last option is always "View all commands".

### Routing

When the user selects an option, invoke the corresponding skill:

| Action Value | Invoke |
|-------------|--------|
| `plan` | Invoke `/plan` skill |
| `build` | Invoke `/build` skill |
| `review` | Invoke `/review` skill |
| `ship` | Invoke `/ship` skill |
| `loa-setup` | Invoke `/loa setup` skill |
| `loa doctor` | Run `.claude/scripts/loa-doctor.sh` |
| `archive-cycle` | **Confirm first** ("This will archive the current cycle. Continue?"), then invoke `/archive-cycle` |
| `read:PATH` | Read and display the file |
| `help-full` | Display the `/loa --help-full` output |

**Fallback**: If a skill invocation is denied or fails, display the equivalent command
as a copyable code block so the user can invoke it manually.
```

#### 2.1.5 Destructive Action Safety

Only one menu action is destructive: "Plan new cycle" (`archive-cycle`). The command file instructs the agent to confirm before invoking. No other menu options are destructive.

---

### 2.2 FR-2: Interactive Post-Mount Verification

#### 2.2.1 Integration Point

Insert verification between feature gate enforcement and the completion banner in `mount-loa.sh` (after line 1192):

```bash
  # === Post-Mount Verification ===
  verify_mount "$@"
```

#### 2.2.2 verify_mount() Function

```bash
verify_mount() {
    local quiet=false json=false strict=false
    local warnings=0 errors=0
    local checks=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --quiet) quiet=true ;;
            --json) json=true ;;
            --strict) strict=true ;;
        esac
        shift
    done

    # Check 1: Framework files
    if [[ -f ".claude/commands/loa.md" ]]; then
        checks+=('{"name":"framework","status":"pass","detail":"Core files synced"}')
    else
        checks+=('{"name":"framework","status":"fail","detail":"Missing core framework files"}')
        errors=$((errors + 1))
    fi

    # Check 2: Configuration
    if [[ -f ".loa.config.yaml" ]]; then
        checks+=('{"name":"config","status":"pass","detail":".loa.config.yaml created"}')
    else
        checks+=('{"name":"config","status":"fail","detail":"Missing .loa.config.yaml"}')
        errors=$((errors + 1))
    fi

    # Check 3: Required deps
    for dep in jq yq git; do
        if command -v "$dep" >/dev/null 2>&1; then
            local ver
            ver=$("$dep" --version 2>&1 | head -1)
            checks+=("{\"name\":\"dep_${dep}\",\"status\":\"pass\",\"detail\":\"${ver}\"}")
        else
            checks+=("{\"name\":\"dep_${dep}\",\"status\":\"fail\",\"detail\":\"Not found\"}")
            errors=$((errors + 1))
        fi
    done

    # Check 4: Optional tools
    for tool_pair in "br:beads (task tracking)" "ck:ck (semantic search)"; do
        local tool="${tool_pair%%:*}"
        local label="${tool_pair#*:}"
        if command -v "$tool" >/dev/null 2>&1; then
            local ver
            ver=$("$tool" --version 2>&1 | head -1)
            checks+=("{\"name\":\"opt_${tool}\",\"status\":\"pass\",\"detail\":\"${ver}\"}")
        else
            checks+=("{\"name\":\"opt_${tool}\",\"status\":\"warn\",\"detail\":\"${label} not installed (optional)\"}")
            warnings=$((warnings + 1))
        fi
    done

    # Check 5: API key presence (NFR-8: boolean only)
    if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
        checks+=('{"name":"api_key","status":"pass","detail":"ANTHROPIC_API_KEY is set"}')
    else
        checks+=('{"name":"api_key","status":"warn","detail":"ANTHROPIC_API_KEY not set (needed for Claude Code)"}')
        warnings=$((warnings + 1))
    fi

    # Exit code: 0=success+warnings, 1=failure, 1=strict+warnings
    local exit_code=0
    if [[ "$errors" -gt 0 ]]; then
        exit_code=1
    elif [[ "$strict" == "true" && "$warnings" -gt 0 ]]; then
        exit_code=1
    fi

    # Output (Flatline SKP-004: use jq for safe JSON generation)
    if [[ "$json" == "true" ]]; then
        # Use jq -n for safe JSON assembly (no manual string concatenation)
        jq -n \
            --arg status "$([ "$errors" -gt 0 ] && echo "fail" || echo "pass")" \
            --argjson errors "$errors" \
            --argjson warnings "$warnings" \
            --argjson checks "$(printf '%s\n' "${checks[@]}" | jq -s '.')" \
            '{status: $status, errors: $errors, warnings: $warnings, checks: $checks}'
    elif [[ "$quiet" != "true" ]]; then
        echo ""
        log "[VERIFY] Post-mount health check..."
        for check_json in "${checks[@]}"; do
            local st nm dt
            st=$(echo "$check_json" | jq -r '.status')
            dt=$(echo "$check_json" | jq -r '.detail')
            case "$st" in
                pass) info "  ✓ ${dt}" ;;
                warn) warn "  ⚠ ${dt}" ;;
                fail) error " ✗ ${dt}" ;;
            esac
        done
        echo ""
    fi

    return "$exit_code"
}
```

#### 2.2.3 Exit Code Contract

| Exit Code | Meaning | When |
|-----------|---------|------|
| 0 | Success (may include warnings) | All required checks pass |
| 1 | Failure | Required dep missing OR mount failed OR `--strict` with warnings |

---

### 2.3 FR-3: Setup Wizard — `/loa setup`

#### 2.3.1 Two-File Architecture

| File | Zone | Purpose |
|------|------|---------|
| `.claude/commands/loa-setup.md` | System | Agent instructions for interactive wizard |
| `.claude/scripts/loa-setup-check.sh` | System | Shell validation engine (standalone) |

#### 2.3.2 loa-setup-check.sh

Outputs JSONL (one JSON object per line) for easy parsing:

```bash
#!/usr/bin/env bash
set -euo pipefail

# loa-setup-check.sh — Environment validation
# Usage: .claude/scripts/loa-setup-check.sh [--json]
# Each check outputs one JSON line to stdout.
# Exit: 0 if all required pass, 1 if any required fail.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

errors=0

# Step 1: API key (NFR-8: zero key material)
if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
    echo '{"step":1,"name":"api_key","status":"pass","detail":"ANTHROPIC_API_KEY is set"}'
else
    echo '{"step":1,"name":"api_key","status":"warn","detail":"ANTHROPIC_API_KEY not set"}'
fi

# Step 2: Required deps
for dep in jq yq git; do
    if command -v "$dep" >/dev/null 2>&1; then
        ver=$("$dep" --version 2>&1 | head -1)
        echo "{\"step\":2,\"name\":\"dep_${dep}\",\"status\":\"pass\",\"detail\":\"${ver}\"}"
    else
        echo "{\"step\":2,\"name\":\"dep_${dep}\",\"status\":\"fail\",\"detail\":\"Not found — required\"}"
        errors=$((errors + 1))
    fi
done

# Step 3: Optional tools
if command -v br >/dev/null 2>&1; then
    ver=$(br --version 2>&1 | head -1)
    echo '{"step":3,"name":"beads","status":"pass","detail":"'"$ver"'"}'
else
    echo '{"step":3,"name":"beads","status":"warn","detail":"Not installed","install":"cargo install beads_rust"}'
fi

if command -v ck >/dev/null 2>&1; then
    ver=$(ck --version 2>&1 | head -1)
    echo '{"step":3,"name":"ck","status":"pass","detail":"'"$ver"'"}'
else
    echo '{"step":3,"name":"ck","status":"warn","detail":"Not installed","install":"See INSTALLATION.md"}'
fi

# Step 4: Configuration status
if [[ -f ".loa.config.yaml" ]]; then
    flatline=$(yq '.flatline_protocol.enabled // false' .loa.config.yaml 2>/dev/null || echo "unknown")
    memory=$(yq '.memory.enabled // true' .loa.config.yaml 2>/dev/null || echo "unknown")
    enhance=$(yq '.prompt_enhancement.invisible_mode.enabled // true' .loa.config.yaml 2>/dev/null || echo "unknown")
    echo '{"step":4,"name":"config","status":"pass","features":{"flatline":'"$flatline"',"memory":'"$memory"',"enhancement":'"$enhance"'}}'
else
    echo '{"step":4,"name":"config","status":"warn","detail":".loa.config.yaml not found"}'
fi

exit "$( [ "$errors" -gt 0 ] && echo 1 || echo 0 )"
```

#### 2.3.3 loa-setup.md Command

The command file instructs the agent to:

1. Run `.claude/scripts/loa-setup-check.sh` and parse JSONL output
2. Present Steps 1-3 as formatted output (pass/warn/fail for each check)
3. For Step 4, use AskUserQuestion with `multiSelect: true`:

```yaml
question: "Which features would you like to enable?"
options:
  - label: "Flatline Protocol"
    description: "Multi-model adversarial review (Opus + GPT-5.2)"
  - label: "Persistent Memory"
    description: "Cross-session observation storage"
  - label: "Prompt Enhancement"
    description: "Invisible prompt improvement before skill execution"
  - label: "Keep current settings"
    description: "Don't change .loa.config.yaml"
multiSelect: true
```

4. If user selects features (and not "Keep current settings"), update `.loa.config.yaml` via `yq`:
   ```bash
   yq -i '.flatline_protocol.enabled = true' .loa.config.yaml
   yq -i '.memory.enabled = true' .loa.config.yaml
   ```
5. Display summary

The `--check` flag runs `loa-setup-check.sh --json` and displays raw JSON without interactive prompts.

---

### 2.4 FR-4: Project Archetype Templates

#### 2.4.1 Template Schema

```yaml
# .claude/data/archetypes/{name}.yaml
name: "REST API"
description: "Backend API service with authentication, CRUD, and documentation"
tags: ["backend", "api", "web"]
context:
  vision: |
    A RESTful API service following industry best practices.
  technical:
    - "RESTful API design with versioned endpoints (/api/v1/...)"
    - "Authentication (JWT or session-based) with refresh tokens"
    - "Input validation at API boundaries"
    - "OpenAPI/Swagger documentation generated from code"
    - "Database migrations with rollback support"
  non_functional:
    - "Response time < 200ms p95 for read operations"
    - "Rate limiting per API key"
    - "CORS configuration for frontend origins"
    - "Structured JSON logging with request tracing"
  testing:
    - "Integration tests for all endpoints"
    - "Auth flow tests (login, refresh, revoke)"
    - "Error response format validation"
  risks:
    - "SQL injection via unvalidated query parameters"
    - "Broken authentication (OWASP A07:2021)"
    - "Mass assignment vulnerabilities"
```

#### 2.4.2 Template Set

| File | Name | Tags |
|------|------|------|
| `rest-api.yaml` | REST API | backend, api, web |
| `cli-tool.yaml` | CLI Tool | cli, terminal, args |
| `library.yaml` | Library / Package | library, package, api |
| `fullstack.yaml` | Full-Stack App | fullstack, frontend, backend |

#### 2.4.3 Integration with plan.md

Add before the existing Phase 0 (Context Synthesis) instructions:

```markdown
## Archetype Selection (v1.34.0)

Before starting discovery, check if this is a first-time project:

1. Check: does `grimoires/loa/prd.md` exist? → If yes, SKIP archetypes.
2. Check: does ledger.json have any completed cycles? → If yes, SKIP.
3. If both empty, list archetypes from `.claude/data/archetypes/`:
   ```bash
   for f in .claude/data/archetypes/*.yaml; do
     name=$(yq '.name' "$f")
     desc=$(yq '.description' "$f")
     echo "$name: $desc"
   done
   ```
4. Present via AskUserQuestion (user can select "Other" to skip).
5. On selection, read the YAML and write context to `grimoires/loa/context/archetype.md`.
6. Proceed to Phase 0 — context ingestion picks up archetype.md automatically.
```

#### 2.4.4 Context Output Format

When an archetype is selected, write to `grimoires/loa/context/archetype.md`:

```markdown
# Project Archetype: {name}

> Auto-generated from `.claude/data/archetypes/{file}`. Modify freely.

## Vision
{context.vision}

## Technical Context
{for each context.technical: "- {item}"}

## Non-Functional Requirements
{for each context.non_functional: "- {item}"}

## Testing Strategy
{for each context.testing: "- {item}"}

## Known Risks
{for each context.risks: "- {item}"}
```

---

## 3. File Inventory

### Modified Files

| File | Change | LOC Delta |
|------|--------|-----------|
| `.claude/commands/loa.md` | Replace static menu with dynamic routing | +45, -15 |
| `.claude/scripts/golden-path.sh` | Add `golden_detect_workflow_state()` + `golden_menu_options()` | +90 |
| `.claude/scripts/mount-loa.sh` | Add `verify_mount()` function + call site | +65 |
| `.claude/commands/plan.md` | Add archetype selection before Phase 1 | +25 |

### New Files

| File | Purpose | LOC |
|------|---------|-----|
| `.claude/commands/loa-setup.md` | Setup wizard command | ~80 |
| `.claude/scripts/loa-setup-check.sh` | Validation engine | ~80 |
| `.claude/data/archetypes/rest-api.yaml` | REST API template | ~30 |
| `.claude/data/archetypes/cli-tool.yaml` | CLI Tool template | ~30 |
| `.claude/data/archetypes/library.yaml` | Library template | ~30 |
| `.claude/data/archetypes/fullstack.yaml` | Full-Stack template | ~30 |

### Estimated Total: ~505 lines

---

## 4. Testing Strategy

### Framework Eval Tasks

| Task | Grader | Tests |
|------|--------|-------|
| `golden-menu-initial.yaml` | `pattern-match.sh` | `golden_menu_options` returns "Plan a new project" when no PRD |
| `golden-menu-implementing.yaml` | `pattern-match.sh` | Menu includes correct sprint-N label |
| `golden-menu-bug.yaml` | `pattern-match.sh` | Bug mode overrides normal menu |
| `golden-state-determinism.yaml` | `exit-code.sh` | Same file state always produces same workflow state |
| `mount-verify-pass.yaml` | `exit-code.sh` | `verify_mount` returns 0 with all deps |
| `mount-verify-json.yaml` | `pattern-match.sh` | `verify_mount --json` produces valid JSON |
| `setup-check-redaction.yaml` | `pattern-match.sh` | No `sk-` patterns in output |
| `archetype-schema.yaml` | `pattern-match.sh` | All archetypes have required fields |

### Manual Testing

| Scenario | Expected |
|----------|----------|
| `/loa` with no PRD | Menu: "Plan a new project (Recommended)" |
| `/loa` mid-sprint-2 | Menu: "Build sprint-2 (Recommended)" |
| `/loa` with active bug | Menu: "Fix bug: {title} (Recommended)" |
| `/loa` all done | Menu: "Ship this release (Recommended)" |
| Mount on fresh repo | Verification summary shown |
| `/loa setup` | 4-step wizard completes |
| `/plan` first time | Archetype menu shown |

---

## 5. Security Considerations

| Concern | Mitigation |
|---------|-----------|
| API key in output | NFR-8: Boolean presence + length only. No `sk-` patterns anywhere. |
| Destructive menu | "Plan new cycle" requires confirmation. "Start over" removed. |
| Config modification | Setup wizard requires AskUserQuestion consent. |
| Template injection | Archetypes are static YAML in System Zone (read-only). |

---

## 6. Rollback Plan

All changes are additive and independently revertable:

| Component | Rollback |
|-----------|----------|
| `/loa` menu | Revert `loa.md` to static 3-option menu |
| `verify_mount()` | Remove function call from mount-loa.sh |
| `/loa setup` | Delete loa-setup.md + loa-setup-check.sh |
| Archetypes | Delete `.claude/data/archetypes/`. `/plan` skips to standard interview. |
| `golden_menu_options()` | Remove from golden-path.sh. Only `/loa` calls it. |
