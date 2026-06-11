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

### PreToolUse:Bash — Team Role Guard (v1.39.0)

Enforces lead-only constraints when `LOA_TEAM_MEMBER` is set (Agent Teams mode). Blocks `br` commands, `.run/*.json` overwrites, and `git commit/push` for teammates. Complete no-op when `LOA_TEAM_MEMBER` is unset. Fail-open design.

**Script**: `.claude/hooks/safety/team-role-guard.sh`

### PreToolUse:Write/Edit — Team Role Guard (v1.39.0)

Extends defense-in-depth to the Write and Edit tools. When `LOA_TEAM_MEMBER` is set, blocks writes to the System Zone (`.claude/`) and top-level state files (`.run/*.json`). Allows writes to teammate-owned paths (`.run/bugs/*/`, `grimoires/`, `app/`). Complete no-op when `LOA_TEAM_MEMBER` is unset. Fail-open design.

**Script**: `.claude/hooks/safety/team-role-guard-write.sh`

### PreToolUse:Skill — Team Skill Guard (v1.39.0)

Enforces the Skill Invocation Matrix mechanically when `LOA_TEAM_MEMBER` is set (Agent Teams mode). Blocks lead-only skill invocations (`/plan-and-analyze`, `/architect`, `/sprint-plan`, `/simstim`, `/run-bridge`, etc.) for teammates. Uses blocklist-based matching against `tool_input.skill`. Complete no-op when `LOA_TEAM_MEMBER` is unset. Fail-open design.

**Script**: `.claude/hooks/safety/team-skill-guard.sh`

### Stop — Run Mode Guard

Detects active `/run`, `/run-bridge`, or `/simstim` execution and injects context reminder before stopping.

**Script**: `.claude/hooks/safety/run-mode-stop-guard.sh`

### PostToolUse:Bash — Audit Logger

Logs mutating commands (git, npm, rm, mv, etc.) to `.run/audit.jsonl` in JSONL format.

**Script**: `.claude/hooks/audit/mutation-logger.sh`

### PostToolUse:Write/Edit — Write Audit Logger (v1.39.0)

Logs Write and Edit tool file modifications to `.run/audit.jsonl` in JSONL format. Captures file path, tool name, team identity, and timestamp. Does NOT log file content (privacy, size). Complements `mutation-logger.sh` to ensure all file modifications — whether via Bash, Write, or Edit — appear in the audit trail.

**Script**: `.claude/hooks/audit/write-mutation-logger.sh`

## Deny Rules

Template of recommended file access deny rules for credential protection. Blocks agent access to `~/.ssh/`, `~/.aws/`, `~/.kube/`, `~/.gnupg/`, and credential stores.

**Template**: `.claude/hooks/settings.deny.json`
**Installer**: `.claude/scripts/install-deny-rules.sh`

## Known Scope Boundaries (cycle-114 FR-7)

The safety layer is a **fence against routine destructive mistakes**, not a
hardened security boundary. It defends two surfaces:

- **Filesystem destruction** — `block-destructive-bash.sh` blocks `rm -rf` on
  catastrophic paths, force-push, hard-reset, `DROP`/`TRUNCATE`, etc.
- **Credential reads** — `settings.deny.json` blocks access to `~/.ssh/`,
  `~/.aws/`, `~/.kube/`, `~/.gnupg/`, and credential stores.

It does **NOT** guard:

- **Network egress / data exfiltration.** There is no monitoring or restriction
  of outbound data — `curl`/`wget` POSTs, `scp`, cloud uploads (S3, gcs), or
  bulk transfers of repository contents are not inspected. Preventing
  exfiltration is the **operator's responsibility**, via network policy /
  firewall / egress proxy external to Claude Code (Claude Code's own auto-mode
  classifier provides some bulk-exfil detection, but Loa does not add a guard).
- **Documented bypass classes.** Newline statement separators, subshell
  wrapping (`bash -c`, `$(...)`), `eval`/base64 decode, SQL comments containing
  `WHERE`, python scripts loaded from disk, and `jq` absent from PATH all bypass
  `block-destructive-bash.sh` by design — see cycle-111 SDD §11 for the full
  accepted-bypass list and rationale.

Treat the safety hooks as defense-in-depth against accidental damage by
autonomous agents — not as a sandbox.

## All Hook Registrations

See `.claude/hooks/settings.hooks.json` for the complete hook configuration.

| Event | Matcher | Script | Purpose |
|-------|---------|--------|---------|
| PreCompact | (all) | `pre-compact-marker.sh` | Save state before compaction |
| UserPromptSubmit | (all) | `post-compact-reminder.sh` | Inject recovery after compaction |
| PreToolUse | Bash | `safety/block-destructive-bash.sh` | Block destructive commands |
| PreToolUse | Bash | `safety/team-role-guard.sh` | Enforce lead-only ops in Agent Teams |
| PreToolUse | Write | `safety/team-role-guard-write.sh` | Block teammate writes to System Zone, state files, and append-only files |
| PreToolUse | Edit | `safety/team-role-guard-write.sh` | Block teammate edits to System Zone, state files, and append-only files |
| PreToolUse | Skill | `safety/team-skill-guard.sh` | Block lead-only skill invocations for teammates |
| PostToolUse | Bash | `audit/mutation-logger.sh` | Log mutating commands |
| PostToolUse | Write | `audit/write-mutation-logger.sh` | Log Write tool file modifications |
| PostToolUse | Edit | `audit/write-mutation-logger.sh` | Log Edit tool file modifications |
| Stop | (all) | `safety/run-mode-stop-guard.sh` | Guard against premature exit |
| PreToolUse | Write/Edit | `compliance/implement-gate.sh` | ADVISORY: App Zone write outside /implement |

## Compliance Hooks — Agent Hook Pattern (v1.40.0)

### When to Use Agent vs Shell Hooks

| Criterion | Shell Hook | Compliance Hook |
|-----------|-----------|----------------|
| Detection | Pattern matching (regex) | State file reading + integrity checks |
| Failure mode | Fail-open (allow) | Fail-ask (prompt user) |
| Performance | <10ms | <100ms (file I/O) |
| Scope | Syntax-level (command text) | Semantic-level (active skill context) |

### implement-gate.sh (FR-7 Prototype)

**Type**: Command hook (ADVISORY)
**Trigger**: PreToolUse on Write/Edit
**Detection**: Reads `.run/sprint-plan-state.json`, `.run/simstim-state.json`, `.run/state.json`

**Decision matrix**:

| File Zone | State Found | State Valid | Decision |
|-----------|------------|-------------|----------|
| Non-App | Any | Any | `allow` |
| App | RUNNING | Fresh + has plan_id | `allow` |
| App | RUNNING | Stale (>24h) | `ask` |
| App | RUNNING | Missing plan_id | `ask` |
| App | JACKED_OUT/HALTED | — | `ask` |
| App | Missing/corrupt | — | `ask` |

**Installation**: Merge into `~/.claude/settings.json` PreToolUse hooks:
```json
{
  "matcher": "Write|Edit",
  "hooks": [{"type": "command", "command": ".claude/hooks/compliance/implement-gate.sh"}]
}
```

**Known limitations**:
- Cannot detect direct `/implement` without `/run` (no state file)
- Heuristic only — not authoritative skill context (platform doesn't expose this)
- Labeled ADVISORY in all output messages

**Tests**: `tests/unit/compliance-hook.bats` (7 tests)

## block-destructive-bash.sh — Full Pattern Set & Posture (moved from CLAUDE.loa.md)

Blocks 12 destructive shapes: `rm -rf` (context-aware: blocks `/`, `~`, `$HOME`, `*`, `.`, `./.git`; allows `./build`, `./node_modules`, `/tmp/*`), `git push --force`/`-f`, `git reset --hard`, `git clean -f`, `git branch -D`/force-delete, `git stash drop`/`clear`, `git checkout -- <path>`, SQL `DROP {DATABASE,TABLE,SCHEMA}`, `TRUNCATE`, `DELETE FROM` no-WHERE (multi-statement loop), `kubectl delete namespace`, `kubectl delete --all`/`-A`. Audit-log trail to `.run/audit.jsonl` on every block with sanitized command + matched substring. Ported from Anthropic DCG public pattern set (cycle-111).

**Defense-in-depth posture (cycle-111)**: this hook is a fence against routine destructive mistakes by autonomous agents — NOT a hardened security boundary. Documented accepted bypass classes (cycle-111 SDD §11): newline statement separators, subshell wrapping (`bash -c '...'` quoted-differently, `$(...)`), eval/base64 decode, SQL comments containing WHERE, python scripts loaded from disk, jq absent from PATH. ERE flavor: GNU/BSD-compatible extensions (`\s`, `\b`), NOT strict POSIX. Latency budget: p95 < 80ms across 100 invocations (bash startup + jq + 13 grep passes).
