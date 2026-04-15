# Security Audit — Cycle-072

**Date**: 2026-04-15
**Auditor**: Cypherpunk Auditor (independent audit)
**Branch**: `feat/spiral-cost-optimization-cycle-072`
**Scope**: 5 bash scripts, 4 test files, 2 config files

---

## Security Checklist

### Secrets (PASS)
- No hardcoded credentials in any script
- Secret scanning chain implemented (`spiral-evidence.sh:312-341`)
- Allowlist uses YAML with governance fields (owner/reason/expires)
- Regex pattern at line 326 matches common secret patterns

### Command Injection (PASS)
- All jq calls use `--arg` / `--argjson` for parameter binding (no string interpolation)
- `yq eval` uses quoted config keys (`.claude/scripts/spiral-harness.sh:49`)
- `git diff` output piped to grep, not interpolated into commands
- No `eval` on user-controlled input

### Input Validation (PASS)
- CLI args validated: `[[ -z "$TASK" ]] && { error "--task required"; exit 2; }` (harness:167)
- Profile validated: unknown falls back to `standard` (harness:85-88)
- Budget validated: `_check_budget` compares numeric values (evidence.sh:247)
- Lock timeout has hardcoded default (scheduler.sh:32)

### File Permissions (PASS)
- Flight recorder: `umask 077` + `chmod 600` (evidence.sh:46-47)
- Cost sidecar: atomic write via tmp+mv (harness.sh:532-535)
- Lock PID file: written with standard permissions, cleaned on exit via trap

### Path Traversal (PASS)
- No user-controlled path construction
- All paths derived from config or CLI flags with no `..` injection
- `CYCLE_DIR` is operator-provided but used as directory prefix only

### Race Conditions (ADVISORY)
- Scheduler uses flock with stale lock recovery (scheduler.sh:121-151)
- PID+hostname+timestamp fingerprint for lock identity
- Conservative stale check: dead PID AND 5-minute age required
- **Note**: Manual `spiral-harness.sh` invocation outside scheduler bypasses flock — documented as TOCTOU advisory in Bridgebuilder CRITICAL-1

### Error Information Disclosure (PASS)
- Error messages go to stderr, not stdout
- No stack traces or internal paths exposed to end users
- Flight recorder is 600-permission, not world-readable

---

## Findings

### MEDIUM-1: Auto-escalation grep may match task descriptions too broadly

**Location**: `spiral-harness.sh:111`
**Pattern**: `grep -qiE 'auth|crypto|secret|token|key|cert|permission|security'`
**Risk**: "key" and "token" are common English words. A task like "Add keyboard shortcut key bindings" would trigger unnecessary escalation to full profile.
**Severity**: MEDIUM — false positive escalation wastes cost but doesn't compromise security.
**Recommendation**: Tighten patterns to require word boundaries or multi-word context (e.g., `api.key|auth.token|secret.key`).

### LOW-1: gitleaks exit code semantics may vary

**Location**: `spiral-evidence.sh:315`
**Risk**: Different gitleaks versions have different exit code conventions for "secrets found."
**Severity**: LOW — regex fallback catches what gitleaks misses.
**Recommendation**: Pin expected gitleaks version or check `--version` at runtime.

### LOW-2: Scheduling window times are UTC-only with no user feedback

**Location**: `spiral-scheduler.sh:158-160`, `spiral-orchestrator.sh:421`
**Risk**: Operator confusion about when windows fire.
**Severity**: LOW — documented in config comments, but easy to misconfigure.

---

## Verdict

APPROVED

No CRITICAL or HIGH security findings. 1 MEDIUM (auto-escalation false positives — cost waste, not security risk) and 2 LOW (operational, not security). All jq uses `--arg`. No secrets. No injection paths. File permissions correct. Lock handling robust.

The implementation is secure for production use.
