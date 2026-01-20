# Recommended Claude Code Hooks for Loa

This protocol documents recommended Claude Code hooks that enhance the Loa workflow.

## Overview

Claude Code hooks are event-driven automations configured in `.claude/settings.json`. They trigger shell commands or scripts when specific events occur.

**Reference**: [Claude Code Hooks Documentation](https://docs.anthropic.com/en/docs/claude-code/hooks)

---

## Hook Types

| Hook | Trigger | Use Case |
|------|---------|----------|
| `PreToolUse` | Before tool execution | Validation, blocking |
| `PostToolUse` | After tool execution | Logging, side effects |
| `Notification` | On notifications | Alerts, external integrations |
| `Stop` | When assistant stops | Cleanup, state sync |

---

## Recommended Hooks for Loa

### 1. Session Continuity Hook (Stop)

Auto-checkpoint NOTES.md when session ends.

> **Note**: The script below is an **example only** and does not exist in the
> Loa repository. Create it yourself or adapt the pattern for your project.

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": ".claude/scripts/session-end-checkpoint.sh"
          }
        ]
      }
    ]
  }
}
```

**Script** (`.claude/scripts/session-end-checkpoint.sh`):
```bash
#!/usr/bin/env bash
set -euo pipefail

NOTES_FILE="grimoires/loa/NOTES.md"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

if [[ -f "$NOTES_FILE" ]]; then
    # Update timestamp in Session Continuity section
    if grep -q "## Session Continuity" "$NOTES_FILE"; then
        sed -i "s/Last Updated:.*/Last Updated: $TIMESTAMP/" "$NOTES_FILE"
    fi
fi
```

---

### 2. Grounding Check Hook (PreToolUse)

Warn before `/clear` if grounding ratio is low.

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": ".*clear.*",
        "hooks": [
          {
            "type": "command",
            "command": ".claude/scripts/grounding-check.sh --warn-only"
          }
        ]
      }
    ]
  }
}
```

---

### 3. Git Safety Hook (PreToolUse)

Prevent accidental pushes to upstream template.

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash.*git push.*",
        "hooks": [
          {
            "type": "command",
            "command": ".claude/scripts/git-safety.sh check-push"
          }
        ]
      }
    ]
  }
}
```

---

### 4. Sprint Completion Hook (PostToolUse)

Sync Beads when sprint is marked complete.

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write.*COMPLETED.*",
        "hooks": [
          {
            "type": "command",
            "command": "br sync 2>/dev/null || true"
          }
        ]
      }
    ]
  }
}
```

---

### 5. Test Auto-Run Hook (PostToolUse)

Run tests after code modifications (optional - can be noisy).

> **Note**: The script below is an **example only** and does not exist in the
> Loa repository. Create it yourself or adapt the pattern for your project.

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit.*\\.(py|js|ts)$",
        "hooks": [
          {
            "type": "command",
            "command": ".claude/scripts/auto-test.sh"
          }
        ]
      }
    ]
  }
}
```

**Script** (`.claude/scripts/auto-test.sh`):
```bash
#!/usr/bin/env bash
# Only run if tests directory exists and recent edit was in src/
if [[ -d "tests" ]] && [[ "$CLAUDE_TOOL_INPUT" == *"src/"* ]]; then
    npm test --silent 2>/dev/null || pytest -q 2>/dev/null || true
fi
```

---

### 6. Documentation Drift Hook (PostToolUse)

Check for drift after significant code changes.

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write.*\\.(py|js|ts|go|rs)$",
        "hooks": [
          {
            "type": "command",
            "command": ".claude/scripts/detect-drift.sh --quick --silent"
          }
        ]
      }
    ]
  }
}
```

---

## Full Configuration Example

Add to `.claude/settings.json`:

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": ".claude/scripts/session-end-checkpoint.sh"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash.*git push.*",
        "hooks": [
          {
            "type": "command",
            "command": ".claude/scripts/git-safety.sh check-push"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write.*COMPLETED.*",
        "hooks": [
          {
            "type": "command",
            "command": "br sync 2>/dev/null || true"
          }
        ]
      }
    ]
  }
}
```

---

## Patterns from Other Frameworks

### Kiro-Style File Event Hooks

Kiro triggers hooks on file save/create/delete. Claude Code can approximate this:

```json
{
  "PostToolUse": [
    {
      "matcher": "Write.*\\.tsx$",
      "hooks": [
        {
          "type": "command",
          "command": "echo 'Consider updating tests for this component'"
        }
      ]
    }
  ]
}
```

### Continuous-Claude-Style Transcript Parsing

Parse session transcript for automatic state extraction:

> **Note**: The script below is an **example only** and does not exist in the
> Loa repository. Create it yourself or adapt the pattern for your project.

```json
{
  "Stop": [
    {
      "matcher": "",
      "hooks": [
        {
          "type": "command",
          "command": ".claude/scripts/extract-session-state.sh"
        }
      ]
    }
  ]
}
```

---

## Hook Development Guidelines

1. **Keep hooks fast** - Long-running hooks degrade UX
2. **Fail silently** - Use `|| true` to prevent blocking on errors
3. **Use matchers precisely** - Broad matchers trigger too often
4. **Log for debugging** - Write to `grimoires/loa/a2a/trajectory/hooks.log`
5. **Test in isolation** - Run scripts manually before adding as hooks

---

## Disabling Hooks

To temporarily disable hooks:

```bash
# Set environment variable
export CLAUDE_HOOKS_DISABLED=1

# Or rename settings file
mv .claude/settings.json .claude/settings.json.bak
```

---

## References

- [Claude Code Hooks Documentation](https://docs.anthropic.com/en/docs/claude-code/hooks)
- [Kiro Agent Hooks](https://kiro.dev/docs/hooks/)
- [Continuous-Claude-v3 Session Hooks](https://github.com/parcadei/Continuous-Claude-v3)
