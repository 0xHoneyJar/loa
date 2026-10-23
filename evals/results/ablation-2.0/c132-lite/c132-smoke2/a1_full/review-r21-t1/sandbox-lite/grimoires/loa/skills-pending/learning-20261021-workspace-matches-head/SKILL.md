---
name: learning-20261021-workspace-matches-head
loa-agent: reviewing-code
source: invisible_retrospective
extracted: 2026-10-21T13:15:00Z
---

When the workspace .claude/ files are byte-identical to pr/head (cmp the touched scripts), untouched helpers and callers can be grepped there and the PR's Python/bats tests executed against the head framework instead of reviewing the diff blind.
