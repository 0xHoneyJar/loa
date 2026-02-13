# Post-Compact Recovery & Hooks Reference

> Extracted from CLAUDE.loa.md for token efficiency. See: `.claude/loa/CLAUDE.loa.md` for inline summary.

## Post-Compact Recovery Hooks (v1.28.0)

Loa provides automatic context recovery after compaction via Claude Code hooks.

### How It Works

1. **PreCompact Hook**: Saves current state to `.run/compact-pending`
2. **UserPromptSubmit Hook**: Detects marker, injects recovery reminder
3. **One-shot delivery**: Reminder appears once, marker is deleted

### Automatic Recovery

When compaction is detected, you will see a recovery reminder instructing you to:
1. Re-read this file (CLAUDE.md) for conventions
2. Check `.run/sprint-plan-state.json` - resume if `state=RUNNING`
3. Check `.run/bridge-state.json` - resume if `state=ITERATING` or `state=FINALIZING`
4. Check `.run/simstim-state.json` - resume from last phase
5. Review `grimoires/loa/NOTES.md` for learnings

### Installation

Hooks are in `.claude/hooks/`. To enable, merge `settings.hooks.json` into `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PreCompact": [{"matcher": "", "hooks": [{"type": "command", "command": ".claude/hooks/pre-compact-marker.sh"}]}],
    "UserPromptSubmit": [{"matcher": "", "hooks": [{"type": "command", "command": ".claude/hooks/post-compact-reminder.sh"}]}]
  }
}
```

See `.claude/hooks/README.md` for full documentation.

## Safety Hooks (v1.37.0)

### PreToolUse:Bash — Destructive Command Blocking

Blocks `rm -rf`, `git push --force`, `git reset --hard`, `git clean -f` with actionable alternatives.

**Script**: `.claude/hooks/safety/block-destructive-bash.sh`

### Stop — Run Mode Guard

Detects active `/run`, `/run-bridge`, or `/simstim` execution and injects context reminder before stopping.

**Script**: `.claude/hooks/safety/run-mode-stop-guard.sh`

### PostToolUse:Bash — Audit Logger

Logs mutating commands (git, npm, rm, mv, etc.) to `.run/audit.jsonl` in JSONL format.

**Script**: `.claude/hooks/audit/mutation-logger.sh`

## Deny Rules

Template of recommended file access deny rules for credential protection. Blocks agent access to `~/.ssh/`, `~/.aws/`, `~/.kube/`, `~/.gnupg/`, and credential stores.

**Template**: `.claude/hooks/settings.deny.json`
**Installer**: `.claude/scripts/install-deny-rules.sh`

## All Hook Registrations

See `.claude/hooks/settings.hooks.json` for the complete hook configuration.

| Event | Matcher | Script | Purpose |
|-------|---------|--------|---------|
| PreCompact | (all) | `pre-compact-marker.sh` | Save state before compaction |
| UserPromptSubmit | (all) | `post-compact-reminder.sh` | Inject recovery after compaction |
| PreToolUse | Bash | `safety/block-destructive-bash.sh` | Block destructive commands |
| PostToolUse | Bash | `audit/mutation-logger.sh` | Log mutating commands |
| Stop | (all) | `safety/run-mode-stop-guard.sh` | Guard against premature exit |
