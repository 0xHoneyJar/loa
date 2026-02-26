# Vision: Bash Template Rendering Anti-Pattern

**ID**: vision-002
**Source**: Bridge iteration 1 of bridge-20260213-c012rt
**PR**: #317
**Date**: 2026-02-13T00:00:00Z
**Status**: Exploring
**Tags**: [security, bash, template-rendering]

## Insight

Bash parameter expansion (`${var//pattern/replacement}`) is fundamentally unsafe for template rendering when replacement content may contain:
1. **Template markers** — causes cascading substitution (template injection)
2. **Backslashes/special chars** — mangled by bash string operations
3. **Large content** — O(n*m) performance causes OOM on documents >100KB

## Potential

Replace all template-rendering instances of `${var//pattern/replacement}` with safe alternatives:
- `jq --arg` for JSON/YAML construction
- `awk gsub()` for multi-line template replacement
- `printf '%s'` with positional args (no shell expansion)

## Connection Points

- Bridgebuilder finding: vision-002, severity 8/10
- Bridge: bridge-20260213-c012rt, iteration 1
- Active exploration: cycle-042 FR-3
