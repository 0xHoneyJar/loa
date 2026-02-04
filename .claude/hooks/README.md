# Loa Hooks

This directory contains Claude Code hooks for the Loa framework.

## Post-Compact Recovery Hooks

These hooks ensure Claude recovers context after compaction events.

### Installation

**Option 1: Automatic (via /mount)**

The `/mount` command will offer to install hooks during framework setup.

**Option 2: Manual**

Add the following to your `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PreCompact": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": ".claude/hooks/pre-compact-marker.sh"
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": ".claude/hooks/post-compact-reminder.sh"
          }
        ]
      }
    ]
  }
}
```

### How It Works

1. **PreCompact** (`pre-compact-marker.sh`):
   - Runs before context compaction
   - Writes marker file with current state (run mode, simstim, skill, etc.)
   - Marker locations: `.run/compact-pending` (project) and `~/.local/state/loa-compact/compact-pending` (global)

2. **UserPromptSubmit** (`post-compact-reminder.sh`):
   - Runs on each user message
   - Checks for compaction marker
   - If found: injects recovery reminder into context, deletes marker
   - One-shot delivery (won't repeat)

### Recovery Instructions

When compaction is detected, Claude is reminded to:

1. Re-read CLAUDE.md for project conventions
2. Check `.run/sprint-plan-state.json` for active run mode
3. Check `.run/simstim-state.json` for active simstim
4. Review `grimoires/loa/NOTES.md` for learnings

### Troubleshooting

**Hooks not firing?**
- Verify hooks are registered in `~/.claude/settings.json`
- Check scripts are executable: `chmod +x .claude/hooks/*.sh`
- Ensure PROJECT_ROOT is set or scripts are run from project root

**Recovery message appearing incorrectly?**
- Delete stale markers: `rm -f .run/compact-pending ~/.local/state/loa-compact/compact-pending`

### Files

| File | Purpose |
|------|---------|
| `pre-compact-marker.sh` | Creates marker before compaction |
| `post-compact-reminder.sh` | Injects reminder after compaction |
| `settings.hooks.json` | Hook configuration template |
| `README.md` | This documentation |
