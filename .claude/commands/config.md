---
name: "config"
version: "1.1.0"
description: |
  Configure MCP integrations for THJ team members post-setup.
  Reads available servers from the MCP registry.

command_type: "wizard"

arguments: []

integrations_source: ".claude/mcp-registry.yaml"

pre_flight:
  - check: "file_exists"
    path: ".loa-setup-complete"
    error: "Loa setup has not been completed. Run /setup first."

  - check: "content_contains"
    path: ".loa-setup-complete"
    pattern: '"user_type":\\s*"thj"'
    error: |
      MCP configuration is only available for THJ team members.

      If you are a THJ team member and need to reconfigure, please delete
      the .loa-setup-complete file and run /setup again.

      For issues or feature requests, please open a GitHub issue at:
      https://github.com/0xHoneyJar/loa/issues

outputs:
  - path: ".loa-setup-complete"
    type: "file"
    description: "Updated marker with new MCP configuration"
  - path: "loa-grimoire/analytics/usage.json"
    type: "file"
    description: "Updated analytics with MCP info"

mode:
  default: "foreground"
  allow_background: false
---

# Config

## Purpose

Configure MCP integrations for THJ team members after initial setup. Add connections to Linear, GitHub, Vercel, Discord, or web3-stats services.

## Invocation

```
/config
```

## Prerequisites

- Setup completed (`.loa-setup-complete` exists)
- User type is `thj` (THJ team member)

## Workflow

### Phase 1: Current Configuration Status

Read `.loa-setup-complete` and display:
- Currently configured MCP servers
- Available (unconfigured) MCP servers

### Phase 2: Check for Unconfigured MCPs

If all MCPs are already configured, display message and stop.

### Phase 3: MCP Selection

Read available servers from `.claude/mcp-registry.yaml` and offer multiSelect:
- Show unconfigured servers with descriptions from registry
- Group options: essential, deployment, crypto, all
- Individual server selection
- Skip - Exit without configuring

Use `.claude/scripts/mcp-registry.sh list` to get available servers.

### Phase 4: MCP Configuration

Provide guided setup instructions for each selected MCP.

### Phase 5: Update Marker File

Update `.loa-setup-complete` with newly configured MCPs.

### Phase 6: Update Analytics

Update `loa-grimoire/analytics/usage.json` with MCP configuration.

### Phase 7: Completion Summary

Display newly configured and total configured servers.

## Arguments

| Argument | Description | Required |
|----------|-------------|----------|
| None | | |

## Outputs

| Path | Description |
|------|-------------|
| `.loa-setup-complete` | Updated marker file |
| `loa-grimoire/analytics/usage.json` | Updated analytics |

## MCP Setup Instructions

Setup instructions are maintained in `.claude/mcp-registry.yaml`.

To get setup instructions for any server:
```bash
.claude/scripts/mcp-registry.sh setup <server-name>
```

Example:
```bash
.claude/scripts/mcp-registry.sh setup github
.claude/scripts/mcp-registry.sh setup linear
```

## Error Handling

| Error | Cause | Resolution |
|-------|-------|------------|
| "Setup not completed" | Missing `.loa-setup-complete` | Run `/setup` first |
| "Only available for THJ" | User type is `oss` | Delete marker and re-run `/setup` |
| "All MCPs configured" | Nothing more to configure | No action needed |

## OSS Users

MCP configuration is not available for OSS users. For manual MCP setup, refer to the Claude Code documentation.
