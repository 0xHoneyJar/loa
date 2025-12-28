# Integration Configuration Protocol

**Version**: 1.0.0
**Status**: Active
**Last Updated**: 2025-12-28

---

## Purpose

This protocol defines the configuration schema for Loa + HivemindOS integration, stored in `.loa.config.yaml`.

---

## Configuration File

**Location**: `.loa.config.yaml` (project root)
**Owner**: User (survives framework updates)
**Format**: YAML

---

## Schema

```yaml
# .loa.config.yaml
# User-owned configuration for Loa framework

# =============================================================================
# Core Settings
# =============================================================================

# Loa version (auto-updated on framework update)
version: "5.0.0"

# Frame system configuration
frames:
  # Enable/disable frame detection
  enabled: true
  # Default frame on session start (search | build | tune)
  default: search

# =============================================================================
# HivemindOS Integration (added by /setup)
# =============================================================================

# Whether HivemindOS integration is enabled
hivemind_integration: true

# Path to HivemindOS installation
hivemind_path: "/Users/username/Documents/GitHub/hivemind-os"

# Integration preferences
integration:
  # Status line mode
  # - merged: Show both HivemindOS database and Loa frame (default when integrated)
  # - loa-only: Show only Loa frame
  # - hivemind-only: Show only HivemindOS database
  status_line_mode: merged

  # Hook execution order
  # Defines which system's hooks run first
  hooks_order:
    session_start:
      - hivemind  # Load organizational context first
      - loa       # Then initialize frame state
    user_prompt:
      - loa       # Frame detection on each prompt

# =============================================================================
# Grounding (from Lossless Ledger Protocol)
# =============================================================================

grounding:
  # Minimum grounding ratio required
  threshold: 0.95
  # Enforcement mode: strict | warn | disabled
  enforcement: warn

# =============================================================================
# Attention Budget
# =============================================================================

attention_budget:
  # Token threshold for yellow warning
  yellow_threshold: 5000

# =============================================================================
# Session Continuity
# =============================================================================

session_continuity:
  # Enable tiered recovery
  tiered_recovery: true
```

---

## Field Definitions

### Core Settings

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `version` | string | - | Loa framework version |
| `frames.enabled` | boolean | `true` | Enable frame detection |
| `frames.default` | string | `search` | Default frame on session start |

### HivemindOS Integration

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `hivemind_integration` | boolean | `false` | Whether integration is enabled |
| `hivemind_path` | string | `null` | Absolute path to HivemindOS installation |
| `integration.status_line_mode` | string | `merged` | How to display status line |
| `integration.hooks_order` | object | - | Hook execution order |

### Status Line Modes

| Mode | Description | Output Format |
|------|-------------|---------------|
| `merged` | Show both contexts | `⬢ HIVEMINDOS 🔬LAB · ◆ BUILD · context · Opus` |
| `loa-only` | Show only Loa frame | `◆ BUILD · context · Opus` |
| `hivemind-only` | Show only HivemindOS | `⬢ HIVEMINDOS 🔬LAB · Opus` |

---

## Reading Configuration

**Bash**:
```bash
# Simple key extraction
yaml_get() {
    local file="$1"
    local key="$2"
    grep -E "^${key}:" "$file" 2>/dev/null | head -1 | sed 's/^[^:]*: *//'
}

# Check integration status
INTEGRATION=$(yaml_get ".loa.config.yaml" "hivemind_integration")
if [[ "$INTEGRATION" == "true" ]]; then
    HIVEMIND_PATH=$(yaml_get ".loa.config.yaml" "hivemind_path")
fi
```

**Agent**:
```
Read .loa.config.yaml and check hivemind_integration field.
If true, use merged status line and enable HivemindOS skills.
```

---

## Writing Configuration

Configuration is typically written by:
1. `/setup` command during initial setup
2. Manual user editing for preferences
3. Framework update scripts (version field only)

**During Setup**:
```bash
# Create or update .loa.config.yaml
cat >> .loa.config.yaml << EOF

# HivemindOS integration (added $(date -u +"%Y-%m-%dT%H:%M:%SZ"))
hivemind_integration: true
hivemind_path: "$HIVEMIND_PATH"
EOF
```

---

## Backwards Compatibility

Missing fields should use sensible defaults:

| Field | Default if Missing |
|-------|-------------------|
| `hivemind_integration` | `false` (standalone mode) |
| `hivemind_path` | `null` |
| `integration.status_line_mode` | `merged` (if integrated) |
| `frames.enabled` | `true` |
| `frames.default` | `search` |

---

## Migration

### From No Config

When `.loa.config.yaml` doesn't exist:
1. Create with minimal settings
2. Set `hivemind_integration: false`
3. Set `frames.enabled: true`

### From Pre-Integration Loa

When existing config lacks integration fields:
1. Add `hivemind_integration: false`
2. Leave other fields unchanged

---

## Related Files

| File | Purpose |
|------|---------|
| `.loa-setup-complete` | Marker with full setup state (JSON) |
| `.loa/.session` | Runtime frame state (YAML) |
| `.claude/.session` | HivemindOS database state (YAML) |
| `.claude/settings.json` | Claude Code hooks configuration |

---

## See Also

- `session-state.md` - Loa session state protocol
- `frames.md` - Frame system protocol
- Integration SDD (Section 15.5)
