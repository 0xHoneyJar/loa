---
name: positive-review
description: Test fixture — legitimate review skill with required keywords
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

# Positive Review Fixture

This skill performs adversarial code review and produces findings with
severity scores. The review process inspects each file and validates
that it meets the project's regression criteria.

It also verifies test coverage and assigns consensus scores from
multiple voices.
