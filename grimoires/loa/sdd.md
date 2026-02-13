# SDD: Harness Engineering Adaptations — Safety Hooks, Deny Rules, Token Optimization

> Source: PRD cycle-011, Issue [#297](https://github.com/0xHoneyJar/loa/issues/297)
> Cycle: cycle-011

## 1. Overview

Six improvements to Loa's harness based on Trail of Bits and OpenAI patterns. All changes are additive — no existing functionality is removed or modified (except CLAUDE.loa.md optimization which restructures content).

### Component Map

| Component | Location | Type | Priority |
|-----------|----------|------|----------|
| Safety hooks | `.claude/hooks/safety/` | New directory + 3 scripts | P1 |
| Deny rules | `.claude/hooks/settings.deny.json` | New file | P2 |
| Stop hook | `.claude/hooks/safety/run-mode-stop-guard.sh` | New script | P3 |
| CLAUDE.md optimization | `.claude/loa/CLAUDE.loa.md` + reference files | Edit + new | P4 |
| Audit logger | `.claude/hooks/audit/mutation-logger.sh` | New directory + script | P5 |
| Invariant linter | `.claude/scripts/lint-invariants.sh` | New script | P6 |

## 2. Safety Hooks (P1)

### 2.1 Architecture

Claude Code hooks receive tool input via stdin as JSON and control execution via exit codes:

| Exit Code | Meaning | Effect |
|-----------|---------|--------|
| 0 | Allow | Execution proceeds; stdout JSON can add context |
| 1 | Non-blocking error | Warning logged, execution proceeds |
| 2 | Blocking error | Execution blocked; stderr message fed back to agent |

### 2.2 Hook: `block-destructive-bash.sh`

**Event**: `PreToolUse` with matcher `Bash`
**Location**: `.claude/hooks/safety/block-destructive-bash.sh`

Single hook that checks for multiple destructive patterns (rather than one hook per pattern):

```bash
#!/usr/bin/env bash
# Read tool input from stdin
input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command // empty')

# Pattern 1: rm -rf (suggest trash instead)
if echo "$command" | grep -qE '\brm\s+(-[a-zA-Z]*r[a-zA-Z]*f|--recursive\s+--force|-[a-zA-Z]*f[a-zA-Z]*r)\b'; then
  echo "BLOCKED: rm -rf detected. Use 'trash' or remove files individually." >&2
  exit 2
fi

# Pattern 2: git push --force to main/master
if echo "$command" | grep -qE 'git\s+push\s+.*--force.*\b(main|master)\b|git\s+push\s+--force'; then
  echo "BLOCKED: Force push detected. Use --force-with-lease or push to a feature branch." >&2
  exit 2
fi

# Pattern 3: git reset --hard
if echo "$command" | grep -qE 'git\s+reset\s+--hard'; then
  echo "BLOCKED: git reset --hard detected. This discards uncommitted work. Use git stash instead." >&2
  exit 2
fi

# Pattern 4: git clean -f (without -n dry-run)
if echo "$command" | grep -qE 'git\s+clean\s+-[a-zA-Z]*f' && ! echo "$command" | grep -qE 'git\s+clean\s+-[a-zA-Z]*n'; then
  echo "BLOCKED: git clean -f without -n (dry-run). Run with -n first to preview." >&2
  exit 2
fi

exit 0
```

**Design decisions**:
- Single script for all Bash safety patterns (reduces hook registration complexity)
- Uses `jq` to parse stdin JSON — `jq` is required by Loa already
- Patterns use `\b` word boundaries to avoid false positives
- Each block provides an actionable alternative, not just a rejection

### 2.3 Relationship to ICE

ICE (`run-mode-ice.sh`) protects git operations during `/run` mode specifically. Safety hooks provide defense-in-depth across ALL modes:

| Protection | ICE | Safety Hooks |
|------------|-----|-------------|
| Protected branch push | Yes (run mode) | Yes (all modes) |
| Force push | Yes (run mode) | Yes (all modes) |
| `rm -rf` | No | Yes |
| `git reset --hard` | No | Yes |
| `git clean -f` | No | Yes |
| Scope | Run mode only | Always active |

They complement each other — ICE handles run-mode-specific git workflow, hooks handle universal destructive patterns.

## 3. Deny Rules (P2)

### 3.1 File: `settings.deny.json`

**Location**: `.claude/hooks/settings.deny.json`

Template for recommended deny rules, merged into `~/.claude/settings.json` during `/mount` or `/loa setup`:

```json
{
  "_comment": "Recommended deny rules for Loa. Merge into ~/.claude/settings.json permissions section.",
  "permissions": {
    "deny": [
      "Read(~/.ssh/**)",
      "Edit(~/.ssh/**)",
      "Read(~/.aws/**)",
      "Edit(~/.aws/**)",
      "Read(~/.kube/**)",
      "Edit(~/.kube/**)",
      "Read(~/.gnupg/**)",
      "Edit(~/.gnupg/**)",
      "Read(~/.npmrc)",
      "Edit(~/.npmrc)",
      "Read(~/.pypirc)",
      "Edit(~/.pypirc)",
      "Read(~/.git-credentials)",
      "Edit(~/.git-credentials)",
      "Read(~/.config/gh/**)",
      "Edit(~/.config/gh/**)",
      "Edit(~/.bashrc)",
      "Edit(~/.zshrc)",
      "Edit(~/.profile)"
    ]
  }
}
```

### 3.2 Installation Script

**Location**: `.claude/scripts/install-deny-rules.sh`

```bash
#!/usr/bin/env bash
# Merge recommended deny rules into ~/.claude/settings.json
# Called by /mount and /loa setup with --auto or --prompt flag

SETTINGS="$HOME/.claude/settings.json"
DENY_TEMPLATE=".claude/hooks/settings.deny.json"

# ... reads template, merges into settings, backs up original
```

The script:
1. Backs up existing settings to `~/.claude/settings.json.bak`
2. Merges deny rules (additive — never removes existing rules)
3. Reports what was added

### 3.3 Auto-Install During /mount

The `/mount` skill calls `install-deny-rules.sh --auto` by default. Users can opt-out by passing `--no-deny-rules` to `/mount` or by setting `harness.deny_rules.auto_install: false` in `.loa.config.yaml`.

## 4. Stop Hook — Run Mode Guard (P3)

### 4.1 Hook: `run-mode-stop-guard.sh`

**Event**: `Stop`
**Location**: `.claude/hooks/safety/run-mode-stop-guard.sh`

When the agent attempts to stop (end the conversation), this hook checks if an autonomous run is active:

```bash
#!/usr/bin/env bash
# Check if run mode is active and sprint is incomplete

STATE_FILE=".run/sprint-plan-state.json"

if [[ ! -f "$STATE_FILE" ]]; then
  exit 0  # No run active, allow stop
fi

state=$(jq -r '.state // "UNKNOWN"' "$STATE_FILE")
current=$(jq -r '.sprints.current // "null"' "$STATE_FILE")

if [[ "$state" == "RUNNING" && "$current" != "null" ]]; then
  # Inject reminder via stdout JSON
  cat <<'EOF'
{"decision": "block", "reason": "Run mode is active (state=RUNNING, sprint=$current). Verify all acceptance criteria are met before stopping. Check .run/sprint-plan-state.json for sprint status."}
EOF
  exit 0  # Exit 0 with JSON decision to inject context
fi

exit 0
```

**Design**: Uses the `Stop` hook's JSON response to inject a context reminder rather than hard-blocking. The agent can still stop if it confirms acceptance criteria are met, but it can't silently rationalize incomplete work.

### 4.2 Bridge Mode Guard

Also checks `.run/bridge-state.json`:

```bash
BRIDGE_FILE=".run/bridge-state.json"
if [[ -f "$BRIDGE_FILE" ]]; then
  bridge_state=$(jq -r '.state // "UNKNOWN"' "$BRIDGE_FILE")
  if [[ "$bridge_state" == "ITERATING" || "$bridge_state" == "FINALIZING" ]]; then
    # Inject bridge reminder
  fi
fi
```

## 5. CLAUDE.md Token Optimization (P4)

### 5.1 Strategy: Moderate Reduction (~50%)

**Current**: 757 lines, 3433 words
**Target**: ~350-400 lines, ~1700 words

### 5.2 What Stays Inline

These sections are critical for immediate agent context and MUST stay in CLAUDE.loa.md:

| Section | Why |
|---------|-----|
| Three-Zone Model | Core safety boundary — agent needs this immediately |
| Process Compliance (NEVER/ALWAYS) | Generated from constraints.json — non-negotiable |
| Task Tracking Hierarchy | Prevents tool misuse |
| Workflow commands table | Agent needs to know what commands exist |
| Golden Path table | Primary navigation |
| File Creation Safety | Prevents heredoc corruption |
| Configurable Paths | Agent needs to resolve paths |
| Run Mode State Recovery | Critical for session continuity |

### 5.3 What Moves to Reference Files

| Section | Current Location | New Location |
|---------|-----------------|--------------|
| Beads-First Architecture details | Inline (50+ lines) | `.claude/loa/reference/beads-reference.md` |
| Run Bridge details | Inline (40+ lines) | `.claude/loa/reference/run-bridge-reference.md` |
| Flatline Protocol details | Inline (80+ lines) | `.claude/loa/reference/flatline-reference.md` |
| Persistent Memory details | Inline (30+ lines) | `.claude/loa/reference/memory-reference.md` |
| Invisible Prompt Enhancement | Inline (15+ lines) | `.claude/loa/reference/prompt-enhancement-reference.md` |
| Invisible Retrospective | Inline (25+ lines) | `.claude/loa/reference/retrospective-reference.md` |
| Input Guardrails details | Inline (40+ lines) | `.claude/loa/reference/guardrails-reference.md` |
| Post-Compact Recovery Hooks | Inline (25+ lines) | `.claude/loa/reference/hooks-reference.md` |
| Flatline Beads Loop | Inline (20+ lines) | `.claude/loa/reference/beads-reference.md` |

### 5.4 Pointer Format

Each extracted section is replaced with a 2-line pointer:

```markdown
## Flatline Protocol (v1.22.0)

Multi-model adversarial review. **Reference**: `.claude/loa/reference/flatline-reference.md`
```

Skills already load their own SKILL.md when invoked, so detailed protocol descriptions in CLAUDE.md are redundant for skill execution — the agent reads the reference file just-in-time when needed.

### 5.5 Measurement

Before and after metrics:
- Line count (`wc -l`)
- Word count (`wc -w`)
- Estimated tokens (words * 1.3)

## 6. Audit Logger (P5)

### 6.1 Hook: `mutation-logger.sh`

**Event**: `PostToolUse` with matcher `Bash`
**Location**: `.claude/hooks/audit/mutation-logger.sh`

```bash
#!/usr/bin/env bash
# Log Bash tool mutations to .run/audit.jsonl
input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command // empty')
exit_code=$(echo "$input" | jq -r '.tool_result.exit_code // 0')

# Only log mutating commands (skip reads)
if echo "$command" | grep -qEi '^(git |npm |pip |cargo |rm |mv |cp |mkdir |chmod |chown |docker |kubectl )'; then
  mkdir -p .run
  jq -n \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg cmd "$command" \
    --arg exit "$exit_code" \
    --arg cwd "$(pwd)" \
    '{ts: $ts, tool: "Bash", command: $cmd, exit_code: ($exit | tonumber), cwd: $cwd}' \
    >> .run/audit.jsonl
fi

exit 0
```

### 6.2 Log Format

JSONL (one JSON object per line), append-only:

```jsonl
{"ts":"2026-02-13T10:05:00Z","tool":"Bash","command":"git push","exit_code":0,"cwd":"/home/user/repo"}
{"ts":"2026-02-13T10:05:30Z","tool":"Bash","command":"npm install","exit_code":0,"cwd":"/home/user/repo"}
```

### 6.3 Log Rotation

`.run/audit.jsonl` is ephemeral — it lives in `.run/` which is gitignored and cleaned between cycles. No rotation needed. If file exceeds 10MB, the hook truncates to the last 1000 entries.

## 7. Mechanical Invariant Linter (P6)

### 7.1 Script: `lint-invariants.sh`

**Location**: `.claude/scripts/lint-invariants.sh`

Validates Loa structural invariants mechanically:

```bash
#!/usr/bin/env bash
# Lint Loa structural invariants
# Run: .claude/scripts/lint-invariants.sh [--fix] [--json]

ERRORS=0

# Invariant 1: No .claude/ files modified (except overrides, hooks, data)
check_system_zone_integrity() {
  local modified=$(git diff --name-only HEAD~1 2>/dev/null | grep '^\.claude/' | grep -v '^\.claude/overrides/' | grep -v '^\.claude/hooks/' | grep -v '^\.claude/data/')
  if [[ -n "$modified" ]]; then
    echo "WARN: System zone files modified: $modified"
    ((ERRORS++))
  fi
}

# Invariant 2: CLAUDE.loa.md hash matches expected
check_claude_md_integrity() {
  local expected_hash=$(head -1 .claude/loa/CLAUDE.loa.md | grep -oP 'hash: \K[a-f0-9]+')
  local actual_hash=$(tail -n +2 .claude/loa/CLAUDE.loa.md | sha256sum | cut -d' ' -f1)
  if [[ "$expected_hash" != "$actual_hash"* ]]; then
    echo "WARN: CLAUDE.loa.md integrity check failed"
    ((ERRORS++))
  fi
}

# Invariant 3: constraints.json is valid JSON
check_constraints_valid() {
  if ! jq empty .claude/data/constraints.json 2>/dev/null; then
    echo "ERROR: constraints.json is not valid JSON"
    ((ERRORS++))
  fi
}

# Invariant 4: All constraint-generated sections in CLAUDE.loa.md have matching hashes
check_constraint_sync() {
  # Verify that constraint-generated blocks are up to date
  local blocks=$(grep -c '@constraint-generated: start' .claude/loa/CLAUDE.loa.md)
  if [[ "$blocks" -eq 0 ]]; then
    echo "WARN: No constraint-generated blocks found in CLAUDE.loa.md"
    ((ERRORS++))
  fi
}

# Invariant 5: Required files exist
check_required_files() {
  local required=(".claude/loa/CLAUDE.loa.md" ".loa-version.json" ".loa.config.yaml")
  for f in "${required[@]}"; do
    if [[ ! -f "$f" ]]; then
      echo "ERROR: Required file missing: $f"
      ((ERRORS++))
    fi
  done
}
```

### 7.2 Integration Points

| Trigger | When |
|---------|------|
| `/mount` completion | Validates post-mount state |
| `/run` preflight | Part of pre-execution checks |
| `/audit-sprint` | Validates before sprint approval |
| Manual | `bash .claude/scripts/lint-invariants.sh` |

## 8. Settings Integration

### 8.1 Updated `settings.hooks.json`

```json
{
  "hooks": {
    "PreCompact": [...existing...],
    "UserPromptSubmit": [...existing...],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": ".claude/hooks/safety/block-destructive-bash.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": ".claude/hooks/audit/mutation-logger.sh"
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": ".claude/hooks/safety/run-mode-stop-guard.sh"
          }
        ]
      }
    ]
  }
}
```

### 8.2 Configuration

```yaml
# .loa.config.yaml
harness:
  safety_hooks:
    enabled: true
    block_rm_rf: true
    block_force_push: true
    block_reset_hard: true
    block_git_clean: true
  deny_rules:
    auto_install: true
  audit_logging:
    enabled: true
    max_file_size_mb: 10
  stop_guard:
    enabled: true
  invariant_linting:
    enabled: true
    on_mount: true
    on_run_preflight: true
```

## 9. File Manifest

| File | Action | Priority |
|------|--------|----------|
| `.claude/hooks/safety/block-destructive-bash.sh` | Create | P1 |
| `.claude/hooks/settings.deny.json` | Create | P2 |
| `.claude/scripts/install-deny-rules.sh` | Create | P2 |
| `.claude/hooks/safety/run-mode-stop-guard.sh` | Create | P3 |
| `.claude/loa/CLAUDE.loa.md` | Edit (optimize) | P4 |
| `.claude/loa/reference/beads-reference.md` | Create | P4 |
| `.claude/loa/reference/flatline-reference.md` | Create | P4 |
| `.claude/loa/reference/guardrails-reference.md` | Create | P4 |
| `.claude/loa/reference/hooks-reference.md` | Create | P4 |
| `.claude/loa/reference/memory-reference.md` | Create | P4 |
| `.claude/hooks/audit/mutation-logger.sh` | Create | P5 |
| `.claude/scripts/lint-invariants.sh` | Create | P6 |
| `.claude/hooks/settings.hooks.json` | Edit (add new hooks) | P1 |
