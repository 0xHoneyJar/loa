---
description: Configure MCP integrations for THJ team members (post-setup)
---

# MCP Configuration

This command allows THJ developers to configure MCP integrations after the initial setup.

---

## Phase 0: User Type Check

Read and parse the setup marker file:

```bash
cat .loa-setup-complete 2>/dev/null
```

Extract the `user_type` field from the JSON response.

**If the file doesn't exist:**
Display this error and STOP:
```
Loa setup has not been completed for this project.

Please run `/setup` first to initialize Loa.
```

**If user_type is "oss":**
Display this error and STOP:
```
MCP configuration is only available for THJ team members.

If you are a THJ team member and need to reconfigure, please delete
the .loa-setup-complete file and run /setup again.

For issues or feature requests, please open a GitHub issue at:
https://github.com/0xHoneyJar/loa/issues
```

**If user_type is "thj":**
Proceed to Phase 1.

---

## Phase 1: Current Configuration Status

Read the `.loa-setup-complete` file and extract the `mcp_servers` array.

Display the current configuration status:

```
## Current MCP Configuration

### Configured Servers
{list each configured MCP server, or "None configured yet"}

### Available Servers
{list MCPs that are NOT in the configured list}
```

**Available MCP servers**:
- linear - Issue tracking for developer feedback
- github - Repository operations, PRs, issues
- vercel - Deployment and hosting
- discord - Community/team communication
- web3-stats - Blockchain data (Dune API, Blockscout)

---

## Phase 2: Check for Unconfigured MCPs

Compare the `mcp_servers` array against the full list of available MCPs.

**If ALL MCPs are already configured:**
Display:
```
All MCP integrations are already configured!

Configured servers:
- linear
- github
- vercel
- discord
- web3-stats

No additional configuration needed.
```
**STOP** - Nothing more to configure.

**If some MCPs are NOT configured:**
Proceed to Phase 3.

---

## Phase 3: MCP Selection

**Use the `AskUserQuestion` tool** with multiSelect enabled to ask:

**Question**: "Which additional MCP integrations would you like to configure?"

**Options** (multiSelect: true) - Only include MCPs that are NOT already configured:
- **Linear** (if not configured) - "Issue tracking for developer feedback"
- **GitHub** (if not configured) - "Repository operations, PRs, issues"
- **Vercel** (if not configured) - "Deployment and hosting"
- **Discord** (if not configured) - "Community/team communication"
- **web3-stats** (if not configured) - "Blockchain data (Dune API, Blockscout)"
- **All remaining** - "Configure all unconfigured integrations"
- **Skip** - "Exit without configuring"

If user selects "Skip", display "No changes made." and **STOP**.
If user selects "All remaining", treat it as selecting all unconfigured MCPs.

---

## Phase 4: MCP Configuration

For each selected MCP, provide guided setup:

**GitHub MCP** (if selected):
```
GitHub MCP Setup:
1. Create a Personal Access Token at https://github.com/settings/tokens
2. Token scopes needed: repo, read:org, read:user
3. Add "github" to enabledMcpjsonServers in .claude/settings.local.json
4. Restart Claude Code to apply changes
```

**Linear MCP** (if selected):
```
Linear MCP Setup:
1. Get your API key from Linear: Settings > API > Personal API keys
2. Add "linear" to enabledMcpjsonServers in .claude/settings.local.json
3. Restart Claude Code to apply changes
```

**Vercel MCP** (if selected):
```
Vercel MCP Setup:
1. Connect via Vercel OAuth at https://vercel.com/integrations
2. Add "vercel" to enabledMcpjsonServers in .claude/settings.local.json
3. Restart Claude Code to apply changes
```

**Discord MCP** (if selected):
```
Discord MCP Setup:
1. Create a Discord bot at https://discord.com/developers/applications
2. Get the bot token from Bot > Token
3. Add "discord" to enabledMcpjsonServers in .claude/settings.local.json
4. Restart Claude Code to apply changes
```

**web3-stats MCP** (if selected):
```
web3-stats MCP Setup:
1. Get a Dune API key at https://dune.com/settings/api
2. Add "web3-stats" to enabledMcpjsonServers in .claude/settings.local.json
3. Restart Claude Code to apply changes
```

---

## Phase 5: Update Marker File

Read the current `.loa-setup-complete` file and update the `mcp_servers` array to include the newly configured MCPs.

Use jq or manual JSON update:

```bash
# Example: Add new MCPs to existing list
CURRENT_MCPS=$(cat .loa-setup-complete | jq -r '.mcp_servers | join(",")')
# Append new MCPs and update file
```

Write the updated JSON back to `.loa-setup-complete`.

---

## Phase 6: Update Analytics

If `loa-grimoire/analytics/usage.json` exists, update `setup.mcp_servers_configured` to include the newly configured MCPs.

---

## Phase 7: Completion Summary

Display:

```
## Configuration Complete!

### Newly Configured
{list of MCPs just configured}

### All Configured Servers
{complete list of all configured MCPs}

### Next Steps
- Restart Claude Code to apply MCP changes
- Run `/plan-and-analyze` to continue your project workflow
```

---

## END

Configuration is complete.
