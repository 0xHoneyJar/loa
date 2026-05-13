---
name: negative-bad-primary-role
description: Test fixture — primary_role violates advisor-wins-ties (implementation declared as primary_role for a role:review skill)
role: review
primary_role: implementation
cost-profile: moderate
capabilities:
  schema_version: 1
  read_files: true
  write_files: false
allowed-tools:
  - Read
---

# Bad primary_role Fixture

primary_role: implementation is a downgrade from role: review.
The advisor-wins-ties rule prohibits this — primary_role must be more
restrictive than role, never less. Adding plenty of review-class
keywords (review audit validate verify score consensus) so the
review-keyword heuristic does NOT trip; the failure must come from
the primary_role consistency check exclusively.
