---
name: "setup"
version: "1.1.0"
description: |
  First-time Loa setup wizard for onboarding and project initialization.
  Detects user type, configures MCP integrations, initializes analytics.

command_type: "wizard"

arguments: []

pre_flight:
  - check: "file_not_exists"
    path: ".loa-setup-complete"
    error: "Setup already completed. Run /config to modify MCP settings."

integrations_source: ".claude/mcp-registry.yaml"

outputs:
  - path: ".loa-setup-complete"
    type: "file"
    description: "Setup marker with user type and configuration"
  - path: "loa-grimoire/analytics/usage.json"
    type: "file"
    description: "Analytics file (THJ users only)"

mode:
  default: "foreground"
  allow_background: false
---

# Setup

## Purpose

First-time setup wizard that initializes Loa for a new project. Determines user type (THJ vs OSS), configures MCP integrations, and initializes analytics tracking.

## Invocation

```
/setup
```

## Workflow

### Phase 0: User Type Detection

Ask the user to identify their pathway:
- **THJ Developer**: Full analytics, MCP configuration, `/feedback` and `/config` access
- **OSS User**: Streamlined setup, no analytics, documentation pointers

### Phase 0.5: Template Detection

Detect if this repository is a fork/template of Loa:

1. Check origin remote URL for known templates
2. Check upstream/loa remote for template references
3. Query GitHub API for fork relationship (if `gh` CLI available)

Store detection result for Git Safety features.

### Phase 1A: THJ Developer Setup

1. Display welcome message with command overview
2. Show analytics notice (cannot be disabled)
3. Initialize `loa-grimoire/analytics/usage.json`
4. Offer MCP integration selection (multiSelect)
5. Provide setup instructions for selected MCPs
6. Create `.loa-setup-complete` marker

### Phase 1B: OSS User Setup

1. Display welcome message with documentation pointers
2. Create `.loa-setup-complete` marker (no analytics)
3. Point to GitHub issues for support

## Arguments

| Argument | Description | Required |
|----------|-------------|----------|
| None | | |

## Outputs

| Path | Description |
|------|-------------|
| `.loa-setup-complete` | Marker file with user type and config |
| `loa-grimoire/analytics/usage.json` | Usage metrics (THJ only) |
| `loa-grimoire/analytics/summary.md` | Human-readable summary (THJ only) |

## User Type Differences

| Feature | THJ Developer | OSS User |
|---------|---------------|----------|
| Analytics | Full tracking | None |
| `/feedback` | Available | Unavailable |
| `/config` | Available | Unavailable |
| MCP Setup | Guided wizard | Manual |

## MCP Integrations

Available servers are defined in `.claude/mcp-registry.yaml`.

Use helper scripts to query the registry:
```bash
.claude/scripts/mcp-registry.sh list      # List all servers
.claude/scripts/mcp-registry.sh groups    # List server groups
.claude/scripts/mcp-registry.sh info <server>  # Get setup instructions
```

### Server Groups (THJ developers)

| Group | Description | Servers |
|-------|-------------|---------|
| essential | Recommended for all | linear, github |
| deployment | Production workflows | github, vercel |
| crypto | Blockchain projects | web3-stats, github |
| communication | Team communication | discord |
| productivity | Document tools | gdrive |

## Marker File Format

```json
{
  "completed_at": "ISO-8601 timestamp",
  "framework_version": "0.4.0",
  "user_type": "thj|oss",
  "mcp_servers": ["list", "of", "configured"],
  "git_user": "developer@example.com",
  "template_source": {
    "detected": true,
    "repo": "0xHoneyJar/loa",
    "detection_method": "origin_url",
    "detected_at": "ISO-8601 timestamp"
  }
}
```

## Error Handling

| Error | Cause | Resolution |
|-------|-------|------------|
| "Setup already completed" | `.loa-setup-complete` exists | Run `/config` to modify MCP settings |
| "Cannot determine user type" | User didn't respond | Re-run `/setup` and select an option |

## Next Step

After setup: `/plan-and-analyze` to create Product Requirements Document
