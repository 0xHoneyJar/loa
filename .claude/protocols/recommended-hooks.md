# Recommended Claude Code Hooks for Loa

This protocol documents recommended Claude Code hooks that enhance the Loa workflow.

## Overview

Claude Code hooks are event-driven automations configured in `.claude/settings.json`. They trigger shell commands or scripts when specific events occur.

**Reference**: [Claude Code Hooks Documentation](https://code.claude.com/docs/en/hooks)

---

## Hook Types

| Hook | Trigger | Use Case |
|------|---------|----------|
| `Setup` | `claude --init`, `--init-only`, `--maintenance` | Framework initialization, health checks |
| `SessionStart` | Session begins | Context loading, updates |
| `PreToolUse` | Before tool execution | Validation, blocking, context injection |
| `PostToolUse` | After tool execution | Logging, side effects |
| `PermissionRequest` | Permission dialog | Audit logging, auto-approval |
| `Notification` | On notifications | Alerts, external integrations |
| `Stop` | When assistant stops | Cleanup, state sync |
| `SessionEnd` | Session terminates | Final cleanup |

---

## Setup Hook (v2.1.10+)

The Setup hook triggers when users run `claude --init`, `--init-only`, or `--maintenance`. This is ideal for framework initialization and health checks.

### Configuration

```json
{
  "hooks": {
    "Setup": [{
      "matcher": "",
      "hooks": [{
        "type": "command",
        "command": ".claude/scripts/upgrade-health-check.sh"
      }]
    }]
  }
}
```

### Use Cases

| Use Case | Description |
|----------|-------------|
| **Health checks** | Validate configuration after upgrades |
| **Migrations** | Run schema migrations on init |
| **Dependencies** | Check required tools are installed |
| **Environment setup** | Set persistent environment variables via `CLAUDE_ENV_FILE` |

### Loa Default Setup Hook

Loa triggers `upgrade-health-check.sh` on `claude --init` to:
- Check beads_rust (br) migration status
- Detect deprecated settings
- Suggest new configuration options
- Recommend missing permissions

**Exit Codes**:
- `0` - All healthy, continue
- `1` - Warnings found, continue
- `2` - Critical issues, recommend action

---

## One-Time Hooks (`once: true`) (v2.1.0+)

Add `once: true` to hooks that only need to run once per session, not on every resume.

### Configuration

```json
{
  "hooks": {
    "SessionStart": [{
      "matcher": "",
      "hooks": [{
        "type": "command",
        "command": ".claude/scripts/check-updates.sh --notify",
        "async": true,
        "once": true
      }]
    }]
  }
}
```

### When to Use `once: true`

| Use Case | once:true? | Reason |
|----------|------------|--------|
| **Update checks** | YES | Only need to check once per session |
| **Welcome messages** | YES | Don't repeat on resume |
| **One-time initialization** | YES | Setup tasks only needed once |
| **Context loading** | NO | May need fresh context on resume |
| **State sync** | NO | Should run every time |
| **Logging** | NO | Want complete audit trail |

### Loa Default One-Time Hooks

```json
{
  "SessionStart": [{
    "matcher": "",
    "hooks": [{
      "type": "command",
      "command": ".claude/scripts/check-updates.sh --notify",
      "async": true,
      "once": true
    }]
  }]
}
```

**Rationale**: Update check only needs to run when session first starts, not when resuming from a checkpoint.

---

## Async Hooks (v2.1.0+)

Claude Code 2.1.0 introduced `async: true` for hooks, allowing them to run in the background without blocking execution.

### When to Use Async

| Use Case | Async? | Reason |
|----------|--------|--------|
| **Logging/Metrics** | YES | Side-effect only, shouldn't block |
| **Notifications** | YES | External calls, user doesn't wait |
| **Update checks** | YES | Network requests, non-critical |
| **Context injection** | NO | Must complete before tool runs |
| **Permission blocking** | NO | Decision required synchronously |

### Configuration

```json
{
  "hooks": {
    "PostToolUse": [{
      "matcher": "Bash",
      "hooks": [{
        "type": "command",
        "command": "./my-logging-hook.sh",
        "async": true,
        "timeout": 30
      }]
    }]
  }
}
```

### Loa Default Async Hooks

The following hooks run asynchronously by default in `.claude/settings.json`:

```json
{
  "hooks": {
    "SessionStart": [{
      "matcher": "",
      "hooks": [{
        "type": "command",
        "command": ".claude/scripts/check-updates.sh --notify",
        "async": true
      }]
    }],
    "PermissionRequest": [{
      "matcher": "",
      "hooks": [{
        "type": "command",
        "command": ".claude/scripts/permission-audit.sh log",
        "async": true
      }]
    }]
  }
}
```

**Rationale**:
- `check-updates.sh`: Network request to GitHub, non-critical notification
- `permission-audit.sh`: Pure audit logging, shouldn't slow down permission flow

### Context Cleanup Hook (PreToolUse)

Archives and cleans previous cycle's context before `/plan-and-analyze`:

```json
{
  "hooks": {
    "PreToolUse": [{
      "matcher": "Skill(plan-and-analyze.*)",
      "hooks": [{
        "type": "command",
        "command": ".claude/scripts/cleanup-context.sh --prompt"
      }]
    }]
  }
}
```

**Behavior**:
- Detects if `grimoires/loa/context/` has files from previous cycle
- Prompts user: Archive and proceed / Keep context / Abort
- Archives to cycle's archive directory before cleaning
- Exit code 2 (abort) blocks `/plan-and-analyze` from running

**NOT async**: Must complete before skill loads context files

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

### 4. Memory Injection Hook (PreToolUse) - v1.8.0

Inject relevant project memories before tool execution.

> **Note**: This hook is part of the Loa Memory Stack. It requires initialization
> via `memory-admin.sh init` and enabling in `.loa.config.yaml`.

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Read|Glob|Grep|WebFetch|WebSearch",
        "hooks": [
          {
            "type": "command",
            "command": ".claude/hooks/memory-inject.sh"
          }
        ]
      }
    ]
  }
}
```

**Configuration** (`.loa.config.yaml`):
```yaml
memory:
  pretooluse_hook:
    enabled: true
    thinking_chars: 1500
    similarity_threshold: 0.35
    max_memories: 3
    timeout_ms: 500
```

**Features**:
- Extracts last 1500 chars from Claude's thinking block
- Queries vector database for similar memories
- Injects top 3 memories via `additionalContext`
- Hash-based deduplication (skips if same query)
- Strict timeout enforcement (500ms)
- Graceful degradation (never blocks tool execution)

---

### 5. Sprint Completion Hook (PostToolUse)

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
2. **Use `async: true` for side-effects** - Logging, notifications, metrics
3. **Fail silently** - Use `|| true` to prevent blocking on errors
4. **Use matchers precisely** - Broad matchers trigger too often
5. **Log for debugging** - Write to `grimoires/loa/a2a/trajectory/hooks.log`
6. **Test in isolation** - Run scripts manually before adding as hooks
7. **Never async context injection** - Hooks returning `additionalContext` must be synchronous

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

- [Claude Code Hooks Documentation](https://code.claude.com/docs/en/hooks)
- [Claude Code Hooks Guide](https://code.claude.com/docs/en/hooks-guide)
- [Kiro Agent Hooks](https://kiro.dev/docs/hooks/)
- [Continuous-Claude-v3 Session Hooks](https://github.com/parcadei/Continuous-Claude-v3)
