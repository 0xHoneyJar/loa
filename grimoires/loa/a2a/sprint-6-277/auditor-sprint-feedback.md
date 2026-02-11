# Sprint 3 (Global Sprint-6) — Security Audit

**Auditor**: Paranoid Cypherpunk Auditor
**Date**: 2026-02-11
**Verdict**: APPROVED - LETS FUCKING GO

## Executive Summary

Sprint 3 is a **net security improvement**. It remediates three previously-identified security advisories (ReDoS in pattern-match, command injection in tests-pass, placeholder Dockerfile digest) and adds a new CI-level trust boundary guard. Zero blocking findings. Zero high-severity findings.

## Security Review

### Task 3.1: ReDoS Guard — APPROVED

**pattern-match.sh:21-31** — Two-layer defense:
1. Length guard (200 chars, env-configurable) — catches complexity
2. Nested quantifier regex detection — catches the classic amplification patterns

**Analysis**: The detection regex itself is simple (no nested quantifiers, no ReDoS risk in the guard). The 200-char limit provides a second net. The per-grader timeout (60s default from grade.sh) is the final backstop. Defense-in-depth is sound.

**Residual risk**: Alternation-based complexity (`(a|b|c|...){n}`) could still be slow under the 200-char limit but is bounded by the grader timeout. Acceptable.

### Task 3.2: Command Injection Hardening — APPROVED

**tests-pass.sh:36-53** — Three-layer defense:
1. Allowlist validation (first token must match `node npx python3 pytest bash sh jest mocha`)
2. Metacharacter rejection (`[;|&\`$\\]`) blocks shell injection vectors
3. Array-based execution (`"${cmd_array[@]}"`) eliminates subshell interpretation

**Analysis**: This is a significant security upgrade from `bash -c "$test_command"`. The metacharacter check at line 37 uses `grep -qE` in single quotes — correctly matches literal special characters inside the character class. The `read -ra` splitting at line 43 handles multi-word commands (e.g., `npx jest --verbose` → `["npx", "jest", "--verbose"]`).

**Limitation noted**: Quoted arguments with spaces won't be preserved (`npx jest "path with spaces"` splits into 4 tokens). This is acceptable for a grader context where commands are defined in task YAML by trusted authors.

### Task 3.3: CI Trust Boundary — APPROVED

**eval.yml:66-101** — Static analysis guard:
- Scans `.sh` files in trusted eval directories for `source`/`.`/`eval` with variable expansion
- Comment lines correctly skipped (line 81)
- Fails CI with `::error` annotations pointing to specific files

**Analysis**: This is a second layer behind the primary protection (grade.sh's direct execution model at line 108: `"$grader_path" "$WORKSPACE" "${grader_args[@]}"`). The CI step scans the BASE branch copies (after step 3 copies base → pr), so it validates the trusted version. A PR can't inject source directives into the scanned files.

**Potential bypass**: Indirect execution via `bash -c "source ..."` wouldn't be caught. However, the direct execution model in grade.sh doesn't use `bash -c`, so this vector doesn't exist in the grader orchestration layer.

### Task 3.4: Early Stopping — APPROVED

**compare.sh:115-142, run-eval.sh:440-469** — Inline Python with shell variable interpolation.

**Security concern reviewed**: Variables `$es_passes`, `$es_failures`, `$remaining` are interpolated into Python code (run-eval.sh:446-448). These are internal integer counters (incremented at lines 434-437), not user-controlled input. No injection vector.

**Fail-safe**: `2>/dev/null || should_stop="false"` at line 449 — Python errors default to "don't stop", which is the safe direction (continue evaluating rather than skip).

### Task 3.5: Dockerfile Digest — APPROVED

**Dockerfile.sandbox:12** — Real digest `sha256:8ea90c4f037cc3c2f566eb46c53eaac005129113487eda4090058fe554578104` from `docker manifest inspect`. Eliminates the placeholder digest that could theoretically resolve to any image. Refresh instructions documented.

### Tasks 3.6–3.7: Documentation — NO SECURITY IMPACT

ADR and multi-model documentation. No code execution, no secrets, no sensitive data disclosure.

## Test Coverage Assessment

| Guard | Tests | Coverage |
|-------|-------|----------|
| ReDoS nested quantifiers | 3 patterns | `(a+)+`, `(a*)*`, `(a{2,}){2,}` |
| ReDoS length limit | 1 test | 201-char pattern |
| Positive regex | 1 test | Normal pattern passes |
| Injection: semicolon | 1 test | `echo hello; rm -rf /` |
| Injection: pipe | 1 test | `echo hello \| cat` |
| Injection: backtick | 1 test | `` echo \`whoami\` `` |
| Injection: dollar | 1 test | `echo $HOME` |
| Early stop: inevitable | 2 tests | 0/3 done, 0/1 done |
| Early stop: not yet | 2 tests | 3/3 done, 1/1 done |

**13 new security-relevant tests.** Adequate coverage for the attack surface.

## Blocking Findings

None.

## Advisory Findings

| # | Severity | Finding | Status |
|---|----------|---------|--------|
| A1 | LOW | `can_early_stop()` interpolates shell vars into Python code. While not exploitable (internal counters), `sys.argv` passing would be more robust. Matches existing convention (Wilson interval function). | Noted — style consistency |

## Checklist

- [x] No hardcoded secrets
- [x] No privilege escalation
- [x] Input validation present (ReDoS guard, metacharacter guard)
- [x] No information disclosure
- [x] Exit codes correct
- [x] Fail-safe defaults (early stop → false on error)
- [x] Tests cover security-relevant paths
- [x] CI guard positioned correctly in pipeline
- [x] Dockerfile digest is real, not placeholder
