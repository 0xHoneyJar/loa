# Loa Helper Scripts

Bash utilities for deterministic operations in the Loa framework.

## Script Inventory

| Script | Purpose | Exit Codes |
|--------|---------|------------|
| `analytics.sh` | Analytics helper functions (THJ only) | 0=success |
| `context-check.sh` | Context size assessment for parallel execution | 0=success |
| `git-safety.sh` | Template repository detection | 0=template, 1=not template |
| `preflight.sh` | Pre-flight validation functions | 0=pass, 1=fail |
| `check-feedback-status.sh` | Check sprint feedback state | 0=success, 1=error, 2=invalid |
| `validate-sprint-id.sh` | Validate sprint ID format | 0=valid, 1=invalid |
| `check-prerequisites.sh` | Check phase prerequisites | 0=OK, 1=missing |

## Usage Examples

### Check Feedback Status
```bash
./.claude/scripts/check-feedback-status.sh sprint-1
# Returns: AUDIT_REQUIRED | REVIEW_REQUIRED | CLEAR
```

### Validate Sprint ID
```bash
./.claude/scripts/validate-sprint-id.sh sprint-1
# Returns: VALID | INVALID|reason
```

### Check Prerequisites
```bash
./.claude/scripts/check-prerequisites.sh --phase implement
./.claude/scripts/check-prerequisites.sh --phase review --sprint sprint-1
# Returns: OK | MISSING|file1,file2,...
```

### Assess Context Size
```bash
source ./.claude/scripts/context-check.sh
assess_context "implementing-tasks"
# Returns: total=1247 category=SMALL
```

### Check Template Repository
```bash
source ./.claude/scripts/git-safety.sh
detect_template
# Returns: detection method or exit 1
```

### Get User Type
```bash
source ./.claude/scripts/analytics.sh
get_user_type
# Returns: thj | oss | unknown
```

## Design Principles

1. **Fail fast** - `set -euo pipefail` in all scripts
2. **Parseable output** - Structured return values (e.g., `KEY|value`)
3. **Exit codes** - 0=success, 1=error, 2=invalid input
4. **No side effects** - Scripts read state, don't modify it
5. **Cross-platform** - POSIX-compatible where possible
