---
name: learning-20261021-eval-test-staging
loa-agent: reviewing-code
source: invisible_retrospective
extracted: 2026-10-21T13:15:00Z
---

Running a PR's own tests in the eval layout: pytest for .claude/adapters/tests resolves REPO_ROOT through symlinks, so the PR's .loa.config.yaml.example must be copied to the real workspace root (remove it afterwards); bats suites run from a scratch root holding tests/ plus a .claude symlink to the workspace framework.
