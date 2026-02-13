# Loa Hooks

This directory contains Claude Code hooks for the Loa framework.

## Installation

**Option 1: Automatic (via /mount)**

The `/mount` command will offer to install hooks during framework setup.

**Option 2: Manual**

Merge `settings.hooks.json` into your `~/.claude/settings.json`. The template includes all hook registrations.

## Hook Registry

| Event | Matcher | Script | Purpose |
|-------|---------|--------|---------|
| PreCompact | (all) | `pre-compact-marker.sh` | Save state before compaction |
| UserPromptSubmit | (all) | `post-compact-reminder.sh` | Inject recovery after compaction |
| PreToolUse | Bash | `safety/block-destructive-bash.sh` | Block destructive commands |
| PostToolUse | Bash | `audit/mutation-logger.sh` | Log mutating commands |
| Stop | (all) | `safety/run-mode-stop-guard.sh` | Guard against premature exit |

## Post-Compact Recovery Hooks

Context recovery after compaction events.

1. **PreCompact** (`pre-compact-marker.sh`):
   - Runs before context compaction
   - Writes marker file with current state (run mode, simstim, skill, etc.)
   - Marker locations: `.run/compact-pending` (project) and `~/.local/state/loa-compact/compact-pending` (global)

2. **UserPromptSubmit** (`post-compact-reminder.sh`):
   - Runs on each user message
   - Checks for compaction marker
   - If found: injects recovery reminder into context, deletes marker
   - One-shot delivery (won't repeat)

## Safety Hooks (v1.37.0)

Defense-in-depth via Claude Code hooks. Active in ALL modes.

### PreToolUse:Bash — Destructive Command Blocking

**Script**: `safety/block-destructive-bash.sh`

Blocks dangerous patterns and suggests safer alternatives:

| Pattern | Blocked | Suggested Alternative |
|---------|---------|----------------------|
| `rm -rf` | Yes | Use `trash` or remove individually |
| `git push --force` | Yes | Use `--force-with-lease` |
| `git reset --hard` | Yes | Use `git stash` |
| `git clean -f` (no `-n`) | Yes | Run with `-n` first to preview |

Does NOT block: `rm file.txt`, `git push origin feature`, `git reset HEAD`, `git clean -nd`, `git push --force-with-lease`.

### Stop — Run Mode Guard

**Script**: `safety/run-mode-stop-guard.sh`

Checks for active autonomous runs before allowing stop:
- `.run/sprint-plan-state.json` (state=RUNNING)
- `.run/bridge-state.json` (state=ITERATING/FINALIZING)
- `.run/simstim-state.json` (state=RUNNING, phase=implementation)

Uses JSON `decision` field for soft block (context injection, not hard block).

### PostToolUse:Bash — Audit Logger

**Script**: `audit/mutation-logger.sh`

Logs mutating shell commands to `.run/audit.jsonl` in compact JSONL format:

```jsonl
{"ts":"2026-02-13T10:05:00Z","tool":"Bash","command":"git push","exit_code":0,"cwd":"/home/user/repo"}
```

Only logs: git, npm, pip, cargo, rm, mv, cp, mkdir, chmod, chown, docker, kubectl, make, yarn, pnpm, npx.

Auto-rotates at 10MB (keeps last 1000 entries).

## Deny Rules

**Template**: `settings.deny.json`
**Installer**: `.claude/scripts/install-deny-rules.sh`

Blocks agent access to credential stores at the Claude Code platform level:

| Path | Read | Edit |
|------|------|------|
| `~/.ssh/**` | Blocked | Blocked |
| `~/.aws/**` | Blocked | Blocked |
| `~/.kube/**` | Blocked | Blocked |
| `~/.gnupg/**` | Blocked | Blocked |
| `~/.npmrc` | Blocked | Blocked |
| `~/.pypirc` | Blocked | Blocked |
| `~/.git-credentials` | Blocked | Blocked |
| `~/.config/gh/**` | Blocked | Blocked |
| `~/.bashrc` | Allowed | Blocked |
| `~/.zshrc` | Allowed | Blocked |
| `~/.profile` | Allowed | Blocked |

Install: `bash .claude/scripts/install-deny-rules.sh --auto`

## Troubleshooting

**Hooks not firing?**
- Verify hooks are registered in `~/.claude/settings.json`
- Check scripts are executable: `chmod +x .claude/hooks/**/*.sh`
- Ensure scripts are run from project root

**Safety hook false positive?**
- The hook blocks `rm -rf` but allows `rm file.txt` — check your command
- `git push --force-with-lease` is explicitly allowed
- File an issue if a legitimate command is blocked

**Recovery message appearing incorrectly?**
- Delete stale markers: `rm -f .run/compact-pending ~/.local/state/loa-compact/compact-pending`

**Audit log too large?**
- Auto-rotates at 10MB
- Manually clear: `> .run/audit.jsonl`

## Files

### Active (registered in settings.hooks.json)

| Path | Event | Purpose |
|------|-------|---------|
| `pre-compact-marker.sh` | PreCompact | Creates marker before compaction |
| `post-compact-reminder.sh` | UserPromptSubmit | Injects reminder after compaction |
| `safety/block-destructive-bash.sh` | PreToolUse:Bash | Destructive command blocker |
| `safety/run-mode-stop-guard.sh` | Stop | Premature exit guard |
| `audit/mutation-logger.sh` | PostToolUse:Bash | Mutation audit logger |

### Optional (separate installation)

| Path | Event | Purpose |
|------|-------|---------|
| `memory-writer.sh` | PostToolUse | Memory observation capture (requires memory config) |
| `memory-inject.sh` | UserPromptSubmit | Memory injection on prompt (requires memory config) |

### Configuration

| Path | Purpose |
|------|---------|
| `settings.hooks.json` | Hook configuration template |
| `settings.deny.json` | Deny rules template |
| `README.md` | This documentation |
