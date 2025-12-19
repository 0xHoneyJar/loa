# Hivemind Connection Library

This library provides shared utilities for managing the Hivemind OS connection within Loa.

## Usage

Include this validation at the start of any Loa phase command that benefits from Hivemind context:
- `/plan-and-analyze` - PRD phase (context injection)
- `/architect` - Architecture phase (context injection, ADR surfacing)
- `/sprint-plan` - Sprint planning phase
- `/implement` - Implementation phase
- `/review-sprint` - Review phase

---

## Phase Start Validation

At the start of each phase, run this validation sequence:

### Step 1: Check Hivemind Connection

```bash
# Check if .hivemind symlink exists and is valid
if [ -L ".hivemind" ]; then
    if [ -d ".hivemind/library" ]; then
        echo "HIVEMIND_STATUS:connected"
    else
        echo "HIVEMIND_STATUS:broken_symlink"
    fi
else
    echo "HIVEMIND_STATUS:not_connected"
fi
```

**Interpretation**:
- `connected`: Hivemind is available, proceed with context injection
- `broken_symlink`: Symlink exists but target is missing, attempt repair
- `not_connected`: No Hivemind integration, proceed without organizational context

### Step 2: Validate Skill Symlinks

```bash
# List all skill symlinks and their status
SKILL_DIR=".claude/skills"
if [ -d "$SKILL_DIR" ]; then
    for skill in "$SKILL_DIR"/*; do
        if [ -L "$skill" ]; then
            if [ -e "$skill" ]; then
                echo "SKILL_OK:$(basename "$skill")"
            else
                echo "SKILL_BROKEN:$(basename "$skill")"
            fi
        fi
    done
else
    echo "SKILLS_DIR_MISSING"
fi
```

### Step 3: Attempt Repair for Broken Symlinks

If any skills are broken, attempt automatic repair:

```bash
SKILL_SOURCE=".hivemind/.claude/skills"
SKILL_TARGET=".claude/skills"

repair_skill() {
    local skill_name="$1"
    local source_path="$SKILL_SOURCE/$skill_name"
    local target_path="$SKILL_TARGET/$skill_name"

    if [ -d "$source_path" ]; then
        rm -f "$target_path"
        ln -sfn "$source_path" "$target_path"

        if [ -e "$target_path" ]; then
            echo "REPAIR_SUCCESS:$skill_name"
        else
            echo "REPAIR_FAILED:$skill_name"
        fi
    else
        echo "SOURCE_MISSING:$skill_name"
    fi
}

# Call for each broken skill
# repair_skill "lab-cubquests-game-design"
```

---

## Validation Response Handling

### If Hivemind Connected (Normal Operation)

```markdown
Hivemind Status: Connected
Skills: {N} loaded, {M} validated

Proceeding with organizational context injection...
```

### If Hivemind Disconnected (Graceful Degradation)

Show a notice but don't block:

```markdown
**Notice**: Hivemind not connected. Proceeding without organizational context.

To enable Hivemind integration, run `/setup` and select "Connect to Hivemind OS".
```

### If Skills Broken (Repair Attempted)

```markdown
**Warning**: {N} skill symlinks were broken.

Repair Results:
- lab-cubquests-game-design: Repaired successfully
- lab-frontend-design-systems: Could not repair (source missing)

Proceeding with available skills...
```

### If Repair Fails Completely

```markdown
**Warning**: Skill validation failed. Some features may be unavailable.

To reconfigure skills, run `/setup` and reconnect to Hivemind.

Proceeding without skill context...
```

---

## Mode State Validation

Read current mode from `.claude/.mode`:

```bash
if [ -f ".claude/.mode" ]; then
    cat ".claude/.mode"
else
    echo "MODE_FILE_MISSING"
fi
```

If mode file is missing or corrupted, create with defaults based on project type from `integration-context.md`:

```json
{
  "current_mode": "creative",
  "set_at": "{ISO_timestamp}",
  "project_type": "unknown",
  "mode_switches": []
}
```

---

## Integration Context Reading

Read project configuration from `loa-grimoire/a2a/integration-context.md`:

```bash
CONTEXT_FILE="loa-grimoire/a2a/integration-context.md"
if [ -f "$CONTEXT_FILE" ]; then
    # Extract project type
    grep -A1 "Project Type" "$CONTEXT_FILE" | tail -1 | sed 's/.*: //'
else
    echo "CONTEXT_MISSING"
fi
```

---

## Full Validation Sequence

Combine all checks into a single validation at phase start:

```markdown
## Pre-Phase Validation

Running Hivemind connection check...

1. **Hivemind**: {Connected/Disconnected}
2. **Skills**: {N} loaded ({M} broken, {R} repaired)
3. **Mode**: {Creative/Secure}
4. **Project Type**: {type}

{Proceed with phase / Show warnings as needed}
```

---

## Error Recovery

### Symlink Target Moved

If Hivemind was moved to a different location:

1. Remove old symlink: `rm .hivemind`
2. Run `/setup` to reconfigure
3. Skills will be re-symlinked automatically

### Complete Reset

To completely reset Hivemind integration:

```bash
# Remove all Hivemind artifacts
rm -f .hivemind
rm -rf .claude/skills
rm -f .claude/.mode

# Re-run setup
# /setup
```

---

## Mode Switch Analytics (NEW)

When a mode switch occurs, log it to `loa-grimoire/analytics/usage.json`:

### Recording a Mode Switch

```bash
record_mode_switch() {
    local from_mode="$1"
    local to_mode="$2"
    local reason="$3"
    local phase="$4"

    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    ANALYTICS_FILE="loa-grimoire/analytics/usage.json"

    # Add mode switch to analytics
    jq --arg from "$from_mode" \
       --arg to "$to_mode" \
       --arg reason "$reason" \
       --arg phase "$phase" \
       --arg ts "$TIMESTAMP" '
      .mode_switches += [{
        "from": $from,
        "to": $to,
        "reason": $reason,
        "phase": $phase,
        "timestamp": $ts
      }]
    ' "$ANALYTICS_FILE" > "$ANALYTICS_FILE.tmp" && \
    mv "$ANALYTICS_FILE.tmp" "$ANALYTICS_FILE"
}

# Example usage:
# record_mode_switch "creative" "secure" "phase_requirement" "review-sprint"
```

### Mode Switch Triggers

Track mode switches when:

1. **Phase requirement**: Review/Audit phases require Secure mode
   ```
   from: creative, to: secure, reason: "Phase requires Secure mode"
   ```

2. **User confirmation**: User confirms mode switch at gate
   ```
   from: secure, to: creative, reason: "User confirmed switch"
   ```

3. **Project type change**: If project type changes during setup
   ```
   from: creative, to: secure, reason: "Project type changed to contracts"
   ```

### Updating .claude/.mode

When a mode switch occurs, update the mode file:

```bash
update_mode_file() {
    local new_mode="$1"
    local reason="$2"

    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    MODE_FILE=".claude/.mode"

    # Read current state
    current=$(cat "$MODE_FILE")

    # Update with new mode and add to switches array
    echo "$current" | jq \
        --arg mode "$new_mode" \
        --arg ts "$TIMESTAMP" \
        --arg reason "$reason" '
        .mode_switches += [{
          "from": .current_mode,
          "to": $mode,
          "reason": $reason,
          "timestamp": $ts
        }] |
        .current_mode = $mode |
        .set_at = $ts
    ' > "$MODE_FILE.tmp" && mv "$MODE_FILE.tmp" "$MODE_FILE"
}
```

### Updating summary.md

After recording mode switches, update the summary to include count:

```markdown
## Mode Analytics

| Metric | Value |
|--------|-------|
| Current Mode | {Creative/Secure} |
| Total Switches | {count} |
| Last Switch | {timestamp} |
```

### Non-Blocking Guarantee

Mode switch analytics are **NON-BLOCKING**:
- If jq fails, log warning but proceed
- If analytics file missing, create it first or skip
- Never let analytics failure affect mode switching

```bash
# Safe wrapper
safe_record_mode_switch() {
    if command -v jq &>/dev/null && [ -f "loa-grimoire/analytics/usage.json" ]; then
        record_mode_switch "$@" 2>/dev/null || echo "Warning: Mode switch analytics update failed"
    fi
}
```

---

*Library created as part of Sprint 1: Foundation*
*Extended with Mode Switch Analytics in Sprint 4*
*See SDD section 3.5.2 for symlink validation details*
