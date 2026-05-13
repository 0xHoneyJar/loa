---
name: negative-no-role
description: Test fixture — MISSING role field (should fail validator)
cost-profile: moderate
capabilities:
  schema_version: 1
  read_files: true
  write_files: false
allowed-tools:
  - Read
---

# Negative Fixture — No Role

Validator MUST reject this with "Missing required 'role' field".
