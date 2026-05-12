---
name: negative-sham-review
description: Test fixture — claims role review but body has no review keywords (ATK-A13)
role: review
primary_role: review
cost-profile: moderate
capabilities:
  schema_version: 1
  read_files: true
  write_files: false
allowed-tools:
  - Read
---

# Sham Review Fixture

This skill claims role review but actually does nothing review-related.
Body intentionally lacks the required keywords. Validator MUST warn
(soft warning unless REVIEW-EXEMPT comment is present).

Adding bland filler content with no specific review semantics.
