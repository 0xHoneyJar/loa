# Loa Framework Reference Documentation

This directory contains detailed reference documentation that is **not loaded by default** into Claude's context. These files are consulted on-demand when specific information is needed.

## Why Reference Files?

Claude Code recommends keeping CLAUDE.md under ~500 lines. Reference documentation is separated here to:
- Reduce token usage at session start
- Keep core instructions focused and followable
- Allow detailed lookup when needed

## Reference Files

| File | Contents |
|------|----------|
| `protocols-summary.md` | Protocol documentation (Structured Memory, Lossless Ledger, Feedback Loops, etc.) |
| `scripts-reference.md` | Helper scripts documentation and usage |
| `version-features.md` | Version-specific feature documentation (v1.x.0) |
| `context-engineering.md` | Context editing, memory schema, effort parameter, attention budgets |

## When to Consult

- **protocols-summary.md**: When implementing or debugging protocol-related behavior
- **scripts-reference.md**: When using helper scripts (or run `script.sh --help`)
- **version-features.md**: When needing details about specific version features
- **context-engineering.md**: When working with context management, memory, or effort settings

## Configuration Examples

See `.loa.config.yaml.example` in the project root for comprehensive configuration examples organized by feature.

## See Also

- `.claude/skills/*/SKILL.md` - Skill-specific documentation (loaded on-demand when skill is invoked)
- `CHANGELOG.md` - Version history
- `.claude/protocols/` - Full protocol specifications
