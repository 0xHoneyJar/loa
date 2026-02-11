# Security Audit: Sprint 2 — Autonomous Mode, Ledger Integration & Golden Path

**Auditor**: Paranoid Cypherpunk Auditor
**Sprint**: sprint-2 (cycle-001, Bug Mode #278)
**Date**: 2026-02-11
**Verdict**: APPROVED - LETS FUCKING GO

---

## Audit Scope

Files audited:
- `.claude/skills/run-mode/index.yaml` (135 lines)
- `.claude/skills/run-mode/SKILL.md` (550 lines — bug run mode section: lines 340-509)
- `.claude/scripts/golden-path.sh` (485 lines — new functions: lines 342-417, updated: 207-213, 309-315, 455-472)
- `.claude/commands/loa.md` (400 lines — new sections: 190, 233-244, 149, 155, bug example)

## Security Checklist

### 1. Path Traversal & File System Safety
**Status**: PASS

`golden_detect_active_bug()` uses glob `"${bugs_dir}"/*/state.json` — safe, only matches subdirectories. Bug IDs read from JSON via `jq -r '.bug_id // empty'`, not from filesystem paths. IDs are system-generated (`YYYYMMDD-{hex}` from `openssl rand -hex 3`) — no user text in paths.

`golden_detect_micro_sprint()` uses `_GP_A2A_DIR` (resolved from config) + `bug-${bug_id}` — bug_id is system-generated. Function only performs existence check (`[[ -f ]]`), never creates files.

`golden_get_bug_sprint_id()` same pattern — reads from system-generated paths via jq.

### 2. Secrets & Credentials
**Status**: PASS

No hardcoded secrets in any file. PR template uses `{placeholder}` syntax — no executable code. Confidence signals are all enums or integers (no user data in PR body except system-generated bug_title which was PII-scrubbed in Sprint 1 triage).

### 3. Injection Prevention
**Status**: PASS

All jq invocations use `-r` flag with literal field paths — no user-controlled jq expressions.
All bash variables properly quoted with `"${...}"` syntax.
No `eval`, `exec`, `system`, shell expansion, or backtick usage on any user-controlled data.
Sprint ID output from `golden_get_bug_sprint_id()` is system-generated `sprint-bug-{NNN}` — safe for `echo "/implement ${bug_sprint}"`.

### 4. State Integrity
**Status**: PASS

Bug state namespaced per-bug in `.run/bugs/{bug_id}/state.json` — prevents cross-bug interference.
Circuit breaker namespaced in `.run/bugs/{bug_id}/circuit-breaker.json`.
State transitions explicitly defined with invalid transition rejection requirement.
`schema_version: 1` field in state file for forward compatibility.
SKILL.md specifies atomic writes (temp + rename) — consistent with Sprint 1.

### 5. PII & Data Privacy
**Status**: PASS

PR confidence signals contain only enums and integers — no raw user data:
- `reproduction_strength`: enum (strong/weak/manual_only)
- `test_type`: enum (unit/integration/e2e/contract)
- `risk_level`: enum (low/medium/high)
- `files_changed`, `lines_changed`: integers

`bug_title` in PR body is PII-scrubbed by Sprint 1 triage (Phase 1 redaction + Phase 4 output scan). No additional PII surfaces introduced in Sprint 2.

### 6. Process Compliance — Quality Gate Preservation
**Status**: PASS

Bug run loop preserves ALL quality gates:
1. Triage (eligibility check — Sprint 1 phases 0-3)
2. `/implement` (test-first enforcement)
3. `/review-sprint` (code review gate)
4. `/audit-sprint` (security audit gate)
5. Draft PR (human approval gate)

No skip paths exist. `--allow-high` only bypasses the high-risk HALT gate — it does NOT skip review or audit. The `pr_merge` operation remains in `blocked_operations` in the safety config.

### 7. Autonomous Mode Safety
**Status**: PASS

Five layers of autonomous mode defense:
1. **ICE layer**: All git operations through `run-mode-ice.sh` wrapper
2. **Circuit breaker**: Bug-scoped (10 cycles, 2h) — tighter than standard (20, 8h)
3. **High-risk gate**: HALT for auth/payment/migration without explicit `--allow-high`
4. **Draft PR**: "CRITICAL: Bug PRs are ALWAYS draft. Never auto-merged." (line 490)
5. **Opt-in**: `run_mode.enabled: true` required + `allow_high: false` default

### 8. Golden Path Regression Safety
**Status**: PASS

All three updated functions use defensive early-return pattern:
- `_gp_journey_position()`: bug check first, falls through to standard on `return 1`
- `golden_suggest_command()`: bug check first, falls through to standard on `return 1`
- `golden_resolve_truename("build")`: bug check only when no override, falls through

When no `.run/bugs/` directory exists or all bugs are COMPLETED/HALTED, all functions return identical values to pre-Sprint-2 behavior. Zero regression risk.

### 9. Cross-Platform Compatibility
**Status**: PASS

`stat` command handles both Linux and macOS:
```bash
mtime=$(stat -c %Y "${state_file}" 2>/dev/null || stat -f %m "${state_file}" 2>/dev/null) || continue
```
GNU coreutils `-c %Y` tried first, BSD/macOS `-f %m` as fallback. Error suppression with `2>/dev/null` on both. `|| continue` skips files where neither works.

### 10. Danger Level Classification
**Status**: PASS

Run mode remains `danger_level: high` — correct for autonomous execution. The `allow_high` input has `default: false` — explicit opt-in only. Bug-scoped limits (10 cycles, 2h) are more conservative than standard run limits (20 cycles, 8h).

## Findings

No security issues found. Zero CRITICAL, zero HIGH, zero MEDIUM, zero LOW.

## Notes

- The `loa.md` implementation note (step 2b) uses `${active_bug}` in a path: `".run/bugs/${active_bug}/state.json"`. This is documentation guidance for the Claude agent, not directly executed shell. The `active_bug` value is system-generated (hex-only bug ID), so even if directly executed, path traversal is not possible.
- The `_gp_validate_sprint_id` regex (`^sprint-[1-9][0-9]*$`) won't match `sprint-bug-N` format, but this is intentional — bug sprint routing bypasses validation via the `golden_detect_active_bug` early return path. User-provided overrides still get validated.

## Decision

**APPROVED** — Sprint 2 passes security audit. No blocking findings.
Create COMPLETED marker.
