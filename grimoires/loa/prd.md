# Product Requirements Document: Shell-lint rule for grep -c || echo 0 anti-pattern (#531)

**Date**: 2026-04-16
**Issue**: [#531](https://github.com/0xHoneyJar/loa/issues/531)
**Cycle**: cycle-079

## 1. Problem Statement

Under `set -o pipefail`, `grep -c 'pattern' FILE 2>/dev/null || echo "0"` produces `"0\n0"` when the count is zero. `grep -c` outputs `0` to stdout AND exits 1 (POSIX), so the `|| echo "0"` fallback fires and command substitution concatenates both outputs. Downstream arithmetic (`[[ $var -lt N ]]`) fails with syntax errors.

This bug class was found 3 independent times in cycle-075 (PRs #518, #524, #526). ~55 sites remain in `.claude/scripts/`.

## 2. Goals

1. Add a WARNING-level lint rule to `.github/workflows/shell-compat-lint.yml` that flags `grep -c ... || echo` and `wc -l ... || echo` patterns
2. Document the approved replacement: `awk '/pattern/{c++} END{print c+0}'`
3. Allowlist for test files and already-audited files with inline `# lint:allow-grep-c-fallback`

## 3. Non-Goals

- Fixing all ~55 existing sites in this PR (incremental migration)
- Changing the lint from WARNING to ERROR (that would block all PRs touching flagged files)

## 4. Success Criteria

| ID | Criterion | Verification |
|----|-----------|-------------|
| SC-1 | Lint rule flags `grep -c ... \|\| echo` pattern | CI workflow test |
| SC-2 | Lint rule flags `wc -l ... \|\| echo` pattern | CI workflow test |
| SC-3 | Test files (*.bats, *test*) are excluded | Allowlist in rule |
| SC-4 | Inline `# lint:allow-grep-c-fallback` suppresses the warning | Allowlist in rule |
| SC-5 | Rule is WARNING level (does not block PRs) | CI still passes with existing sites |
| SC-6 | Approved replacement documented in the lint output | Message text |

## 5. System Zone Write Authorization

Authorized for cycle-079: `.github/workflows/shell-compat-lint.yml`
