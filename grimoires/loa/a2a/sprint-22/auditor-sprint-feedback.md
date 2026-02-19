# Security Audit: Sprint 22 — Manifest Reader + Workflow Activator

**Auditor**: Paranoid Cypherpunk Auditor
**Date**: 2026-02-19
**Sprint**: sprint-1 (global sprint-22)
**Cycle**: cycle-029 — Construct-Aware Constraint Yielding

## Pre-requisite Verification

Senior Technical Lead approval: **VERIFIED** ("All good" in engineer-feedback.md)

## Security Checklist Results

### 1. construct-workflow-read.sh

| Check | Status | Evidence |
|-------|--------|----------|
| Shell injection prevention | PASS | All user input flows through jq (safe JSON parsing), no eval/exec |
| Path traversal prevention | PASS | Manifest path passed directly to jq as file arg (no interpolation) |
| Input validation | PASS | All gate values validated against readonly allowlists |
| Error handling | PASS | `set -euo pipefail`, `die()` to stderr, fail-closed on parse errors |
| No secrets | PASS | No credentials, tokens, or keys |
| No info disclosure | PASS | Error messages contain field names only, no system paths |

**Key Safety Mechanisms:**

1. **Fail-closed design** (Line 148): `jq -e '.workflow // empty' ... || exit 1` — any parse failure exits with code 1, which means "no workflow" and full pipeline applies. An attacker cannot craft a malformed manifest to bypass constraints.

2. **implement: skip enforcement** (Lines 82-84, 128-130): Checked in BOTH full-read and gate-query paths. No bypass possible.

3. **Readonly validation sets** (Lines 18-25): Valid values are `readonly` constants — cannot be modified at runtime.

### 2. construct-workflow-activate.sh

| Check | Status | Evidence |
|-------|--------|----------|
| Path traversal — manifest | PASS | Lines 57-64: `realpath` resolves symlinks, prefix check against PACKS_PREFIX |
| Path traversal — --complete | LOW | Line 203: sprint_id not validated against format pattern |
| Shell injection | PASS | All values via `jq --arg` (safe escaping), no `eval` |
| State file integrity | PASS | Written via `jq -cn` (atomic JSON construction), no string concat |
| Audit log integrity | PASS | Append-only via `>>`, JSON constructed via `jq -cn --arg` |
| Destructive operations | PASS | Only `rm -f` on state file (Line 195) — expected behavior |
| Race conditions | PASS | Single-writer (construct workflows are sequential) |
| Privilege escalation | PASS | No sudo, no system-wide operations |

**Detailed Analysis:**

1. **Manifest Path Security** (Lines 57-64):
   ```bash
   real_manifest="$(realpath "$manifest" 2>/dev/null)"
   real_prefix="$(realpath "$PACKS_PREFIX" 2>/dev/null)"
   if [[ "$real_manifest" != "$real_prefix"* ]]; then
     die "Manifest must be within ..."
   fi
   ```
   `realpath` resolves symlinks before comparison. A symlink at `.claude/constructs/packs/evil -> /etc/` would resolve to `/etc/manifest.json` which fails the prefix check. Correct.

2. **Audit Log Safety** (Lines 132-145, 181-192):
   All values passed via `jq --arg` which JSON-escapes special characters. Newlines, quotes, and backslashes in construct names cannot corrupt the JSONL format.

3. **State File Lifecycle**:
   - Created: Only via `cmd_activate` which validates manifest
   - Read: By `cmd_check` and `cmd_gate` with staleness check
   - Deleted: Only via `cmd_deactivate`
   - No world-writable permissions (inherits umask)

### 3. Protocol Document

| Check | Status | Evidence |
|-------|--------|----------|
| No dangerous instructions | PASS | All examples use safe patterns |
| No eval-like patterns | PASS | Code blocks are documentation only |
| Security invariants documented | PASS | Security Invariants table present |

## Vulnerability Assessment

### Path Traversal Analysis
- **Manifest path**: MITIGATED via `realpath` + prefix check
- **--complete sprint_id**: LOW risk — caller is trusted construct SKILL.md, but format not validated. Sprint IDs should match `^sprint-[0-9]+$`.

### Constraint Bypass Analysis
- **Risk**: LOW
- **Analysis**: A construct can only activate if its manifest is within `.claude/constructs/packs/`. Installation requires explicit user action. The `implement: required` invariant prevents complete pipeline bypass.
- **Residual risk**: A malicious construct pack could declare `audit: skip` to bypass security audit. This is by design — construct authors are trusted (per PRD NF-2).

### State File Manipulation Analysis
- **Risk**: ACCEPTABLE
- **Analysis**: `.run/` is not git-tracked. Manual edits to `.run/construct-workflow.json` could fake an active construct. However, this is prompt-level enforcement — the same trust model as all other constraint enforcement. A human who can edit `.run/` already has full system access.

## Verdict

**APPROVED - LETS FUCKING GO**

Sprint 1 demonstrates security-conscious design:

1. **Fail-closed by default**: Parse errors → no workflow → full pipeline
2. **Path validation**: `realpath` + prefix check prevents traversal
3. **Safe JSON construction**: `jq --arg` throughout, no string interpolation into JSON
4. **Observable**: Every activation/deactivation logged to audit trail
5. **Invariant enforcement**: `implement: required` cannot be bypassed

No blocking security issues found. Ready for merge.
