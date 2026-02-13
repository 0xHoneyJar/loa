---
parallel_threshold: 3000
timeout_minutes: 5
zones:
  system:
    path: .claude
    permission: read
  state:
    paths: [grimoires/loa]
    permission: read
  app:
    paths: [src, lib, app]
    permission: none
---

# BUTTERFREEZONE Generation Skill

<objective>
Generate and validate BUTTERFREEZONE.md — the agent-grounded README that provides
token-efficient, provenance-tagged, checksum-verified project context for AI agents.
Every claim cites its source. No butter, no hype.
</objective>

<zone_constraints>
- READ: .loa.config.yaml (configuration)
- READ: grimoires/loa/ground-truth/ (Tier 1 input)
- READ: package.json, Cargo.toml, etc. (Tier 2 input)
- WRITE: BUTTERFREEZONE.md (output)
- EXECUTE: .claude/scripts/butterfreezone-gen.sh
- EXECUTE: .claude/scripts/butterfreezone-validate.sh
</zone_constraints>

<input_guardrails>
- danger_level: safe
- No PII or secrets in output (redaction enforced by gen script)
- No network access required
</input_guardrails>

<constraints>
- C-BFZ-001: ALWAYS run validation after generation
- C-BFZ-002: NEVER skip provenance tagging
- C-BFZ-003: ALWAYS respect word budget (3200 total, 800 per section)
- C-BFZ-004: NEVER include secrets in output (redaction is enforced)
- C-BFZ-005: ALWAYS preserve manual sections (sentinel markers)
</constraints>

<workflow>
## Phase 1: Configuration Check

```bash
# Check if butterfreezone is enabled
enabled=$(yq '.butterfreezone.enabled // true' .loa.config.yaml 2>/dev/null || echo "true")
if [[ "$enabled" != "true" ]]; then
    echo "BUTTERFREEZONE is disabled in config. Enable with butterfreezone.enabled: true"
    exit 0
fi
```

## Phase 2: Generation

### Default Mode (generate + validate)

```bash
# Generate BUTTERFREEZONE.md
.claude/scripts/butterfreezone-gen.sh --verbose --json

# Check exit code
# 0 = success
# 2 = config error
# 3 = Tier 3 bootstrap (limited output)
```

### Validate-Only Mode

```bash
# Validate existing file
.claude/scripts/butterfreezone-validate.sh --file BUTTERFREEZONE.md --json
```

### Dry-Run Mode

```bash
# Preview without writing
.claude/scripts/butterfreezone-gen.sh --dry-run
```

## Phase 3: Validation

```bash
# Always validate after generation
.claude/scripts/butterfreezone-validate.sh --file BUTTERFREEZONE.md

# With strict mode if requested
.claude/scripts/butterfreezone-validate.sh --file BUTTERFREEZONE.md --strict
```

## Phase 4: Report

Report results to user:
- Generation tier used (1/2/3)
- Word count vs budget
- Validation results (pass/warn/fail per check)
- Any redacted content warnings
- Staleness status
</workflow>

<error_handling>
| Error | Cause | Resolution |
|-------|-------|------------|
| Exit 2 from gen | Config error | Check .loa.config.yaml |
| Exit 3 from gen | Tier 3 bootstrap | Add package.json or run /ride first |
| Validation FAIL | Structure issues | Review and fix reported issues |
| Validation WARN | Advisory issues | Regenerate or accept advisory |
</error_handling>
