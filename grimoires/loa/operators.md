---
schema_version: "1.0"
operators:
  - id: deep-name
    display_name: "Deep Name"
    github_handle: janitooor
    git_email: "121614318+deep-name@users.noreply.github.com"
    capabilities:
      - dispatch
      - merge
      - cycle.author
    active_since: "2026-05-03T00:00:00Z"
---

# Operators — cycle-098 Sprint 1B

This file is the **per-repo identity registry** referenced by L4 trust scopes,
L6 handoff `from`/`to` fields, and other Loa primitives that need verifiable
operator identity.

Schema and verification chain are defined in:

- **PRD §Cross-cutting Operator Identity Model** (`grimoires/loa/prd.md`)
- **SDD §Operator Identity Library** (`grimoires/loa/sdd.md`)

## Adding yourself as an operator

Open a PR that adds an entry under `operators:` with the schema fields below.
Schema validation runs at CI; structure is enforced.

| Field | Required | Notes |
|-------|----------|-------|
| `id` | yes | Slug — alphanumeric + dash; used as the verbatim reference in L4 trust scopes and L6 handoffs |
| `display_name` | yes | Human-readable name |
| `github_handle` | yes | GitHub username (no `@` prefix) |
| `git_email` | yes | The email address used in git commits; cross-checked when `verify_git_match: true` is set in `.loa.config.yaml` |
| `gpg_key_fingerprint` | optional | Hex GPG fingerprint; cross-checked against GPG-signed commits when `verify_gpg: true` |
| `capabilities` | yes | List of L4 trust scopes the operator may participate in (free-form for now; Sprint 4 adds taxonomy) |
| `active_since` | yes | ISO-8601 timestamp when this operator entry became active |
| `active_until` | optional | ISO-8601 offboarding marker. Historical entries are preserved for audit; never delete |

## Offboarding

Set `active_until` to the operator's last-active timestamp; do **not** remove
the entry. Audit logs reference historical operator IDs; deletion would break
provenance.

## Identity is per-repo, not global

Multi-repo operators have entries in each repo's `OPERATORS.md`. Cross-repo
identity reconciliation is operator-tooling, not a Loa primitive.
