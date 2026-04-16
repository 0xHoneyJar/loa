# Sprint Plan: Cycle-079 — Shell-lint rule for grep -c || echo 0 (#531)

**PRD**: `grimoires/loa/prd.md`
**SDD**: `grimoires/loa/sdd.md`
**Issue**: [#531](https://github.com/0xHoneyJar/loa/issues/531)
**Branch**: `chore/shell-lint-grep-c-fallback-531`

## Sprint 1 (single sprint)

### Task 1: Add lint rule to shell-compat-lint.yml
Add WARNING section for `grep -c ... || echo` and `wc -l ... || echo` patterns.
Follow existing rule structure (sed -i, readlink -f, grep -P sections).
Include allowlist for test files and inline suppression comment.

### Task 2: Verify lint doesn't block CI
Run the lint section locally to confirm it produces WARNINGs, not ERRORs, for existing sites.

### Task 3: Create PR
