APPROVED - LETS FUCKING GO

# Security Audit Report: Sprint 2 (sprint-15) — Skill Integrations

**Auditor**: Paranoid Cypherpunk Security Auditor
**Sprint**: sprint-15 (cycle-027, Sprint 2)
**Date**: 2026-02-19
**Verdict**: APPROVED — No critical, high, or medium security issues found.

---

## Prerequisites Verified

| Check | Status |
|-------|--------|
| Engineer feedback: "All good" on line 1 | VERIFIED |
| Sprint 1 (sprint-14) completed | VERIFIED |
| Unit tests: 24/24 pass | VERIFIED (executed) |
| Integration tests: 22/22 pass | VERIFIED (executed) |
| Total: 46/46 tests pass | VERIFIED |

---

## Files Audited

| # | File | Lines Changed | Verdict |
|---|------|--------------|---------|
| 1 | `.claude/skills/implementing-tasks/SKILL.md:394-398` | 5 lines added (step 8) | PASS |
| 2 | `.claude/skills/reviewing-code/SKILL.md:316-320` | 5 lines added (step 8) | PASS |
| 3 | `.claude/skills/riding-codebase/SKILL.md:129-136` | 8 lines added (QMD Reality Context) | PASS |
| 4 | `.claude/scripts/bridge-orchestrator.sh:156-167` | 12 lines added (load_bridge_context) | PASS |
| 5 | `.claude/scripts/preflight.sh:289-301` | 13 lines added (check #8) | PASS |
| 6 | `.claude/scripts/qmd-context-integration-tests.sh` | 223 lines (new file) | PASS |

---

## Security Checklist

### 1. Secrets: PASS

No hardcoded credentials, API keys, tokens, or secrets found in any of the 6 modified/created files. The QMD context query system reads from grimoire state files only — no external credential stores or API services are accessed by the integration points.

### 2. Input Validation: PASS

**SKILL.md files (BB-408, BB-409, BB-410)**: These are agent instruction documents, not executable code. Query strings are specified as template patterns (`"<task_desc> <file_names>"`, `"<changed_files> <sprint_goal>"`, `"<module_names>"`) which the agent constructs from its own context — not from raw user input. The downstream `qmd-context-query.sh` (Sprint 1, already audited) validates all arguments.

**bridge-orchestrator.sh (BB-411)**: `load_bridge_context()` at line 157-167:
- `local query="${1:-}"` — safe default to empty string
- Query is passed double-quoted to the script: `--query "$query"` — no word splitting
- All other arguments are hardcoded literals (`--scope grimoires`, `--budget 2500`, `--format text`)

**preflight.sh (BB-412)**: Lines 289-301:
- `${2:-preflight}` — parameter expansion with safe default. Even though positional parameter `$2` is never passed by the caller on line 308-309, the default "preflight" always applies. This is a benign code smell, not a security issue.
- Query string construction: `"${2:-preflight} configuration prerequisites"` — double-quoted, no injection vector
- All other arguments are hardcoded literals

### 3. Command Injection: PASS

- **No `eval`** in any sprint-2 code. The only `eval` mention is a pre-existing security comment at `preflight.sh:43` (already addressed by using `bash -c`).
- **No unquoted expansions**: All variable expansions in shell scripts are double-quoted (`"$query"`, `"$PROJECT_ROOT"`, `"${2:-preflight}"`).
- **No backtick command substitution**: All command substitution uses `$(...)` form (safe, nestable).
- **`bridge-orchestrator.sh:161`**: The query script is invoked via absolute path `"$PROJECT_ROOT/.claude/scripts/qmd-context-query.sh"` — path is fully quoted, no user-controlled path components.
- **`preflight.sh:292`**: Script invoked via absolute path `"${PROJECT_ROOT}/.claude/scripts/qmd-context-query.sh"` — same safe pattern.

### 4. Path Traversal: PASS

**bridge-orchestrator.sh**: The `-x` check at line 160 validates the script exists and is executable before invocation. The path is constructed from `$PROJECT_ROOT` (derived from `git rev-parse --show-toplevel`), not user input.

**preflight.sh**: Same pattern — `-x` check at line 290 before execution. Path constructed from `${PROJECT_ROOT}` — no user-controlled path components.

**Integration tests**: The test script constructs paths from `PROJECT_ROOT=$(git rev-parse --show-toplevel)` and hardcoded relative paths. Temporary directory created with `mktemp -d` and cleaned up with `trap`. No user-controlled path traversal possible.

### 5. Information Disclosure: PASS

**preflight.sh**: QMD context output goes to stderr only (line 298-299: `echo "Known issues context:" >&2` and `echo "${skill_context}" >&2`). This is correct — preflight output should never leak to stdout where it could interfere with machine-parsed output.

**bridge-orchestrator.sh**: `BRIDGE_CONTEXT` is stored in a local-scope variable (line 159: `BRIDGE_CONTEXT=""`). Errors are redirected to `/dev/null` (line 165: `2>/dev/null`). The `|| BRIDGE_CONTEXT=""` fallback on failure ensures no error messages leak.

**SKILL.md files**: Advisory context only — explicitly labeled as subordinate to acceptance criteria. No internal paths leaked; instructions reference the script by its `.claude/` relative path which is within the repository.

### 6. Denial of Service: PASS

| Integration Point | Budget | Timeout | Safeguard |
|-------------------|--------|---------|-----------|
| `/implement` (BB-408) | 2000 tokens | Inherited from query script (5s default) | Budget enforced by `apply_token_budget()` in Sprint 1 code |
| `/review-sprint` (BB-409) | 1500 tokens | Same | Same |
| `/ride` (BB-410) | 2000 tokens | Same | Same |
| `/run-bridge` (BB-411) | 2500 tokens | Same | Plus `2>/dev/null` and `|| BRIDGE_CONTEXT=""` fallback |
| Gate 0 (BB-412) | 1000 tokens | Same | Plus `-x` guard and `|| skill_context=""` fallback |

All integration points have:
- Token budget limits enforced by the query script's `apply_token_budget()` (audited in Sprint 1)
- Per-tier timeout (default 5 seconds) enforced by the query script's `timeout` command
- `head -10` limit on grep results (Sprint 1 code)
- `head -c 200` limit on individual snippets (Sprint 1 code)

### 7. Code Quality: PASS

**Shell scripts**:
- `bridge-orchestrator.sh`: Has `set -euo pipefail` at line 24. New function follows existing code conventions. Error handling via `|| BRIDGE_CONTEXT=""` fallback.
- `preflight.sh`: `run_integrity_checks()` sets `set -euo pipefail` at line 155. New block follows existing check pattern (numbered sequentially as #8). Error handling via `|| skill_context=""` fallback.
- `qmd-context-integration-tests.sh`: Has `set -euo pipefail` at line 4. Proper cleanup with `trap "rm -rf '$TEMP_DIR'" EXIT` at line 179. All paths constructed safely.

**SKILL.md files**: All three modifications are purely additive (new steps appended to existing numbered lists). No existing behavior modified. All use identical graceful-degradation pattern: "If script missing, disabled, or returns empty: proceed normally (graceful no-op)".

---

## Adversarial Analysis

### Attack Surface Assessment

**Q: Can an attacker manipulate the QMD context to influence implementation decisions?**
A: No. All SKILL.md integrations explicitly state that context is "advisory" and that acceptance criteria/sprint plans remain the "source of truth." The context is additive information, not authoritative. An attacker would need to poison the grimoire state files first — which is a pre-existing trust boundary, not introduced by this sprint.

**Q: Can the `load_bridge_context()` function be called with a malicious query?**
A: The function accepts its query via positional parameter `$1`, which is always passed by the orchestrator (or defaults to empty via `${1:-}`). An empty query causes `qmd-context-query.sh` to return `[]` and exit 0 (line 111-114 of the query script). The query is passed double-quoted to `--query "$query"`, preventing word splitting or glob expansion.

**Q: Can the preflight `${2:-preflight}` be exploited?**
A: No. The function `run_integrity_checks()` is called from line 309 without arguments (just `run_integrity_checks`), so `$2` is always unset and the default "preflight" always applies. Even if `$2` were somehow set, it would be embedded in a double-quoted string passed to `--query`, and the query script validates/sanitizes inputs.

**Q: What happens if `qmd-context-query.sh` is deleted or replaced?**
A: Bridge orchestrator checks `-x` (executable) before calling. Preflight checks `-x` before calling. SKILL.md instructions say "If script missing... proceed normally." The framework's System Zone integrity checks (pre-existing) would detect unauthorized modifications to `.claude/scripts/`.

### Edge Cases Verified

| Scenario | Behavior | Status |
|----------|----------|--------|
| Script missing | All paths return empty/no-op | SAFE |
| Script not executable | `-x` check prevents invocation | SAFE |
| Config disabled (`qmd_context.enabled: false`) | Query returns `[]` immediately | SAFE |
| Query returns error | `|| BRIDGE_CONTEXT=""` / `|| skill_context=""` | SAFE |
| Empty query string | Returns `[]` and exits 0 | SAFE |
| Extremely long query | Truncated by grep's `head -10` and `head -c 200` limits | SAFE |
| Concurrent invocation | Each call is stateless — no shared mutable state | SAFE |

---

## Observations (Non-blocking)

### OBS-1: Dead function in bridge-orchestrator.sh (LOW)

`load_bridge_context()` is defined but never called from the main orchestration loop. The reviewer.md and engineer-feedback.md both acknowledge this. The function is available as a callable hook. Not a security issue — just dead code that should be wired in Sprint 3 or future work.

### OBS-2: Preflight parameter `${2:-preflight}` (INFO)

The positional parameter `$2` in `run_integrity_checks()` at line 293 is never passed. The default "preflight" always applies. This is benign — the fallback value is correct — but could be made more explicit. Not a security issue.

### OBS-3: Integration tests are structural, not runtime (INFO)

Tests verify presence of strings in files (grep-based), not actual runtime execution through the query pipeline. This is acceptable for Sprint 2 scope — the query script itself has 24 unit tests covering runtime behavior. A future sprint could add end-to-end smoke tests.

---

## Conclusion

All 6 files pass the full security checklist. The implementation is minimal, additive, and follows the established patterns. Every shell integration has proper quoting, error handling, timeouts, and budget enforcement. Every SKILL.md integration is advisory-only with explicit graceful degradation. No secrets, no injection vectors, no path traversal, no information disclosure, no DoS potential. 46/46 tests pass.

Sprint 2 (sprint-15) is **APPROVED** for merge.
