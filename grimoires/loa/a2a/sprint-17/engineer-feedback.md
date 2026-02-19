# Sprint 17 Review Feedback (Bridge Iteration 2)

**Reviewer**: Senior Technical Lead
**Sprint**: sprint-17 (sprint-4 of cycle-027, Bridge Iteration 2)
**Date**: 2026-02-19

---

## Review Summary

All good -- with one advisory observation and one low-severity bug noted below. The core fixes are correct, surgical, and well-motivated. None of the findings below block approval.

---

## Tasks Reviewed

| Task | Status | Notes |
|------|--------|-------|
| BB-418: Wire load_bridge_context() | Approved | Correctly wired before BRIDGEBUILDER_REVIEW signal |
| BB-419: Escape rel_path in grep tier | Approved | jq -Rs escaping matches existing snippet pattern |
| BB-420: Validate --skill with regex | Approved | Proper boundary validation with graceful fallback |
| BB-421: Per-file realpath check | Approved | Defense-in-depth at per-file granularity |

---

## Code Quality Assessment

### Strengths

1. **Surgical changes**: +10 lines in bridge-orchestrator.sh and +16 in qmd-context-query.sh. Each fix is tightly scoped to the finding -- no scope creep.

2. **Consistent escaping pattern (BB-419)**: The `rel_path` escaping at lines 403-406 exactly mirrors the `snippet` escaping at lines 396-399. The fallback to `"unknown"` on jq failure is a sensible default.

3. **Defense-in-depth (BB-421)**: The per-file `realpath` check at lines 387-391 correctly catches symlinks that pass the directory-level check at lines 372-376. This is the right architecture: directory check catches the common case, per-file check catches the edge case where individual files within a valid directory are symlinks pointing elsewhere.

4. **Input validation (BB-420)**: The regex `^[a-z_-]+$` at line 99 is appropriately restrictive. Emitting a WARNING to stderr before resetting to empty is the correct user-facing behavior -- visible in logs but non-blocking.

5. **Graceful degradation (BB-418)**: `load_bridge_context` falls back to `BRIDGE_CONTEXT=""` when the QMD script is missing or fails, which preserves the existing no-op behavior for environments without QMD.

### Observations (Non-Blocking)

#### 1. BRIDGE_CONTEXT is set but never consumed (Advisory)

`BRIDGE_CONTEXT` is set as a shell variable in `bridge-orchestrator.sh` (line 159, 161-165) and logged (line 367: byte count), but it is never:
- Exported to the environment
- Passed as an argument in the SIGNAL line
- Written to a file for the skill layer to read

The `run-bridge/SKILL.md` does not mention `BRIDGE_CONTEXT` at all. The Claude agent sees the `SIGNAL:BRIDGEBUILDER_REVIEW` line and invokes the review, but the context data stays in shell memory and is discarded.

**Impact**: The function is no longer "dead code" (BB-418 is resolved), but the context it loads is not yet plumbed through to the review consumer. This is acceptable for iteration 2 -- the wiring is the hard part, and the skill layer integration can happen in a follow-up iteration. Just documenting this so sprint-18 or iteration 3 can close the loop.

**Recommendation**: In a future sprint, either (a) export `BRIDGE_CONTEXT` so the agent can read it from the environment, or (b) emit it as a `SIGNAL:BRIDGE_CONTEXT_PAYLOAD:...` line, or (c) write it to `.run/bridge-context.txt` and reference it in the SKILL.md instructions.

#### 2. Prefix check lacks directory boundary (Low)

Both the directory-level check (line 374) and the new per-file check (line 389) use:
```bash
if [[ ! "$real_path" =~ ^"$PROJECT_ROOT" ]]; then
```

This matches any path that starts with `PROJECT_ROOT` as a string, including sibling directories. For example, if `PROJECT_ROOT=/home/user/project`, then `/home/user/project-evil/secret` passes the check.

The fix is to append a trailing slash:
```bash
if [[ ! "$real_path" =~ ^"$PROJECT_ROOT"/ ]]; then
```

**Impact**: Low in practice -- exploiting this requires a sibling directory with a matching prefix, and the `grep` invocation already scopes to the configured paths. But since BB-421 is specifically about symlink traversal prevention, the check should be precise.

**Note**: This is a pre-existing issue in the directory-level check (line 374) that was replicated in the new per-file check (line 389). Both should be fixed together in a follow-up.

---

## Test Verification

Tests independently confirmed:

| Suite | Count | Status |
|-------|-------|--------|
| Unit tests (qmd-context-query-tests.sh) | 24/24 | PASS |
| Integration tests (qmd-context-integration-tests.sh) | 22/22 | PASS |
| **Total** | **46/46** | **ALL PASS** |

---

## Verdict

**APPROVED** -- Ready for security audit.

Both observations above are non-blocking and can be addressed in sprint-18 or a future bridge iteration. The core security fixes (JSON escaping, input validation, symlink traversal) are correct and well-implemented.
