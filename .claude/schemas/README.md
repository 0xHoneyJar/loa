# Loa JSON Schemas

JSON Schema definitions for validating agent outputs and trajectory entries.

## Purpose

These schemas provide structured output validation for Loa's agent system, ensuring consistent document formats and enabling Claude's Structured Outputs feature integration.

## Schema Files

| Schema | Purpose | Target Files |
|--------|---------|--------------|
| `prd.schema.json` | Product Requirements Document | `grimoires/loa/prd.md` (YAML frontmatter) |
| `sdd.schema.json` | Software Design Document | `grimoires/loa/sdd.md` (YAML frontmatter) |
| `sprint.schema.json` | Sprint Plan | `grimoires/loa/sprint.md` (YAML frontmatter) |
| `trajectory-entry.schema.json` | Agent reasoning trace | `grimoires/loa/a2a/trajectory/*.jsonl` |

## Usage

### Validate a File

```bash
# Auto-detect schema based on file path
.claude/scripts/schema-validator.sh validate grimoires/loa/prd.md

# Specify schema explicitly
.claude/scripts/schema-validator.sh validate output.json --schema prd

# Validation modes
.claude/scripts/schema-validator.sh validate file.md --mode strict  # Fail on errors
.claude/scripts/schema-validator.sh validate file.md --mode warn    # Warn only
.claude/scripts/schema-validator.sh validate file.md --mode disabled # Skip validation
```

### List Available Schemas

```bash
.claude/scripts/schema-validator.sh list
```

## Schema Format

All schemas follow JSON Schema Draft-07 specification:

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "https://loa.dev/schemas/prd.schema.json",
  "title": "Product Requirements Document",
  "description": "Schema for validating PRD output",
  "type": "object",
  "properties": {
    ...
  },
  "required": [...]
}
```

## Configuration

Schema validation can be configured in `.loa.config.yaml`:

```yaml
structured_outputs:
  enabled: true
  validation_mode: "warn"  # strict | warn | disabled
  schemas:
    prd: ".claude/schemas/prd.schema.json"
    sdd: ".claude/schemas/sdd.schema.json"
    sprint: ".claude/schemas/sprint.schema.json"
```

## Integration with Claude Structured Outputs

These schemas are designed to work with Claude's Structured Outputs feature (beta header: `structured-outputs-2025-11-13`). When enabled, Claude guarantees output conformance to the specified schema.

For API integration, schemas can be passed directly to the Claude API:

```python
response = client.messages.create(
    model="claude-opus-4-6",
    messages=[...],
    response_format={
        "type": "json_schema",
        "json_schema": json.load(open(".claude/schemas/prd.schema.json"))
    }
)
```

## Extended Thinking Integration

The `trajectory-entry.schema.json` schema supports extended thinking traces:

```json
{
  "thinking_trace": {
    "steps": ["Step 1: Analyze...", "Step 2: Consider..."],
    "duration_ms": 1500,
    "tokens_used": 450
  }
}
```

This enables logging Claude's internal reasoning for complex agents like `reviewing-code`, `auditing-security`, and `designing-architecture`.

## Related Documentation

- [Claude Structured Outputs](https://docs.anthropic.com/en/docs/build-with-claude/structured-outputs)
- [Extended Thinking](https://docs.anthropic.com/en/docs/build-with-claude/extended-thinking)
- [JSON Schema Specification](https://json-schema.org/specification-links.html#draft-7)
