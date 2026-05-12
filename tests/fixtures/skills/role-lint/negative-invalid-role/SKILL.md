---
name: negative-invalid-role
description: Test fixture — invalid role enum value
role: hacker
cost-profile: moderate
capabilities:
  schema_version: 1
  read_files: true
  write_files: false
allowed-tools:
  - Read
---

# Negative Fixture — Invalid Role Enum

Validator MUST reject this with "Invalid role 'hacker'".
