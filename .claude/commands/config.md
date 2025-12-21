---
name: "config"
version: "1.0.0"
description: |
  Configure MCP integrations for THJ team members post-setup.
  Add or modify Linear, GitHub, Vercel, Discord, web3-stats connections.

command_type: "wizard"

arguments: []

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

Offer multiSelect choice of unconfigured MCPs:
- Linear - Issue tracking for developer feedback
- GitHub - Repository operations, PRs, issues
- Vercel - Deployment and hosting
- Discord - Community/team communication
- web3-stats - Blockchain data (Dune API, Blockscout)
- All remaining - Configure all unconfigured integrations
- Skip - Exit without configuring

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

### GitHub MCP
1. Create a Personal Access Token at https://github.com/settings/tokens
2. Token scopes needed: repo, read:org, read:user
3. Add "github" to enabledMcpjsonServers in .claude/settings.local.json
4. Restart Claude Code to apply changes

### Linear MCP
1. Get your API key from Linear: Settings > API > Personal API keys
2. Add "linear" to enabledMcpjsonServers in .claude/settings.local.json
3. Restart Claude Code to apply changes

### Vercel MCP
1. Connect via Vercel OAuth at https://vercel.com/integrations
2. Add "vercel" to enabledMcpjsonServers in .claude/settings.local.json
3. Restart Claude Code to apply changes

### Discord MCP
1. Create a Discord bot at https://discord.com/developers/applications
2. Get the bot token from Bot > Token
3. Add "discord" to enabledMcpjsonServers in .claude/settings.local.json
4. Restart Claude Code to apply changes

### web3-stats MCP
1. Get a Dune API key at https://dune.com/settings/api
2. Add "web3-stats" to enabledMcpjsonServers in .claude/settings.local.json
3. Restart Claude Code to apply changes

## Error Handling

| Error | Cause | Resolution |
|-------|-------|------------|
| "Setup not completed" | Missing `.loa-setup-complete` | Run `/setup` first |
| "Only available for THJ" | User type is `oss` | Delete marker and re-run `/setup` |
| "All MCPs configured" | Nothing more to configure | No action needed |

## OSS Users

MCP configuration is not available for OSS users. For manual MCP setup, refer to the Claude Code documentation.
