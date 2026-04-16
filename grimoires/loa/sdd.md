# Software Design Document: Shell-lint rule for grep -c || echo 0 (#531)

**Date**: 2026-04-16
**Issue**: [#531](https://github.com/0xHoneyJar/loa/issues/531)
**Cycle**: cycle-079

## 1. Change

Add a new WARNING rule section to `.github/workflows/shell-compat-lint.yml` following the existing pattern (sed -i, readlink -f, grep -P, etc.).

### Detection patterns

```
grep -c ... || echo
wc -l ... || echo
```

Regex: `(grep\s+-c.*\|\|\s*echo|wc\s+-l.*\|\|\s*echo)`

### Allowlist

- Test files: `*test*`, `*.bats`
- Inline suppression: lines containing `# lint:allow-grep-c-fallback`
- The lint rule file itself

### Severity

WARNING (not ERROR) — existing ~55 sites would block all PRs otherwise.

### Recommended fix (in lint output)

```
Use: count=$(awk '/pattern/{c++} END{print c+0}' FILE)
Instead of: count=$(grep -c 'pattern' FILE 2>/dev/null || echo 0)
```
