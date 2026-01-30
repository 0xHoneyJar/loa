# Loa Framework Overrides

This directory allows you to customize Loa behavior **without editing System Zone files**. Your overrides survive framework updates (`/update-loa`).

## Purpose

The `.claude/` directory (System Zone) is managed by the framework and regenerated during updates. Direct edits will be lost. Use `.claude/overrides/` instead to preserve your customizations.

## Usage

### Custom ck Configuration

Create `.claude/overrides/ck-config.yaml` to customize ck semantic search settings:

```yaml
# .claude/overrides/ck-config.yaml
ck:
  model: "jina-code"  # Override default nomic-v1.5
  thresholds:
    semantic: 0.5      # Stricter than default 0.4
    hybrid: 0.6
    regex: 0.7
```

See `ck-config.yaml.example` for full configuration options.

### Custom Skill Instructions

Override any skill's behavior by creating a matching directory structure:

```
.claude/overrides/
└── skills/
    └── implementing-tasks/
        └── SKILL.md          # Your customized skill instructions
```

## Configuration Precedence

1. **`.claude/overrides/*`** (highest priority - your customizations)
2. **`.loa.config.yaml`** (project settings)
3. **`.claude/*`** (framework defaults - fallback)

## Important

- ✅ **DO**: Place customizations in `.claude/overrides/`
- ❌ **DON'T**: Edit `.claude/` files directly (will be overwritten)
- ✅ **DO**: Version control your overrides
- ❌ **DON'T**: Version control `.claude/` (framework-managed)

## Version

Introduced in Loa v0.7.0 as part of the managed scaffolding architecture.
