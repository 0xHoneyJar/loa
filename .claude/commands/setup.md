---
description: Launch the Loa setup wizard for onboarding, MCP configuration, and project initialization
---

# Loa Setup Wizard

Welcome to **Loa** - an agent-driven development framework that guides you from requirements through production deployment using specialized AI agents.

## What /setup Will Do

1. Check your MCP server configuration
2. Help configure any missing integrations (optional)
3. Initialize project tracking
4. Set up analytics

## Analytics Notice

Loa collects usage analytics to improve the framework:
- Session timing and phase completion
- Commit counts and feedback iterations
- Environment info (OS, shell, versions)

**Privacy**: Analytics are stored locally in `loa-grimoire/analytics/`. No data is sent automatically - you choose to share via `/feedback` after deployment.

---

## Phase 1: MCP Detection

Let me check your current MCP configuration by reading `.claude/settings.local.json`.

The following MCP servers are used by Loa:
- **github** - Repository operations, PRs, issues
- **linear** - Issue and project management
- **vercel** - Deployment and hosting
- **discord** - Community/team communication
- **web3-stats** - Blockchain data (Dune, Blockscout)

Read the settings file and determine which servers are configured in `enabledMcpjsonServers`. Report:
1. Which MCPs are already configured
2. Which MCPs are missing (not in the array)

If `.claude/settings.local.json` doesn't exist, inform the user they need to create it first and provide instructions.

## Phase 2: MCP Configuration Wizard

For each **missing** MCP server, present these options:

**[MCP_NAME] is not configured.**

1. **Guided Setup** - Step-by-step configuration instructions
2. **Documentation** - Link to official docs
3. **Skip** - This MCP is optional

### Guided Setup Instructions

**GitHub MCP** (if missing):
```
1. Create a Personal Access Token at https://github.com/settings/tokens
2. Token scopes needed: repo, read:org, read:user
3. Add "github" to enabledMcpjsonServers in .claude/settings.local.json
4. Restart Claude Code to apply changes
```

**Linear MCP** (if missing):
```
1. Get your API key from Linear: Settings > API > Personal API keys
2. Add "linear" to enabledMcpjsonServers in .claude/settings.local.json
3. Restart Claude Code to apply changes
```

**Vercel MCP** (if missing):
```
1. Connect via Vercel OAuth at https://vercel.com/integrations
2. Add "vercel" to enabledMcpjsonServers in .claude/settings.local.json
3. Restart Claude Code to apply changes
```

**Discord MCP** (if missing):
```
1. Create a Discord bot at https://discord.com/developers/applications
2. Get the bot token from Bot > Token
3. Add "discord" to enabledMcpjsonServers in .claude/settings.local.json
4. Restart Claude Code to apply changes
```

**web3-stats MCP** (if missing):
```
1. Get a Dune API key at https://dune.com/settings/api
2. Add "web3-stats" to enabledMcpjsonServers in .claude/settings.local.json
3. Restart Claude Code to apply changes
```

Use the `AskUserQuestion` tool to let the user choose for each missing MCP. Track which were configured, skipped, or deferred.

## Phase 3: Project Initialization

### 3.1 Get Project Info

Run these commands to gather project information:

```bash
# Get project name from git remote
git remote get-url origin 2>/dev/null | sed 's/.*\///' | sed 's/\.git$//' || basename "$(pwd)"

# Get developer info
git config user.name
git config user.email

# Get environment info
uname -s  # OS
uname -r  # OS version
echo $SHELL  # Shell
uname -m  # Architecture
```

### 3.2 Initialize Analytics

Create/update `loa-grimoire/analytics/usage.json` with full project data:

```json
{
  "schema_version": "1.0.0",
  "framework_version": "0.1.0",
  "project_name": "{extracted_project_name}",
  "developer": {
    "git_user_name": "{git_user_name}",
    "git_user_email": "{git_user_email}"
  },
  "environment": {
    "os": "{uname_s}",
    "os_version": "{uname_r}",
    "shell": "{shell}",
    "architecture": "{uname_m}"
  },
  "setup": {
    "completed_at": "{ISO_timestamp}",
    "mcp_servers_configured": ["{list_of_configured_mcps}"]
  },
  "phases": {
    "prd": {"started_at": null, "completed_at": null, "questions_asked": 0, "revisions": 0},
    "sdd": {"started_at": null, "completed_at": null, "questions_asked": 0, "revisions": 0},
    "sprint_planning": {"started_at": null, "completed_at": null, "total_sprints": 0, "total_tasks": 0}
  },
  "sprints": [],
  "reviews": [],
  "audits": [],
  "deployments": [],
  "totals": {
    "commands_executed": 1,
    "phases_completed": 0,
    "sprints_completed": 0,
    "reviews_completed": 0,
    "audits_completed": 0,
    "feedback_submitted": false
  },
  "setup_failures": []
}
```

Log any failures to the `setup_failures` array.

### 3.3 Generate Summary.md

Update `loa-grimoire/analytics/summary.md` with the initialized data in a human-readable format.

### 3.4 Create Marker File

Create `.loa-setup-complete` in the project root with:

```json
{
  "completed_at": "{ISO_timestamp}",
  "framework_version": "0.1.0",
  "mcp_servers": ["{list_of_configured_mcps}"],
  "git_user": "{git_user_email}"
}
```

## Phase 4: Completion Summary

Display a clear summary of what was configured:

---

## Setup Complete!

### MCP Servers

| Server | Status |
|--------|--------|
| github | {Configured/Skipped} |
| linear | {Configured/Skipped} |
| vercel | {Configured/Skipped} |
| discord | {Configured/Skipped} |
| web3-stats | {Configured/Skipped} |

### Project Initialization

- **Project Name**: {project_name}
- **Analytics**: Initialized

### Next Steps

1. Run `/plan-and-analyze` to create your Product Requirements Document
2. Follow the Loa workflow: `/architect` > `/sprint-plan` > `/implement`
3. After deployment, run `/feedback` to share your experience

**Tip**: Check `loa-grimoire/analytics/summary.md` for your usage statistics at any time.

---

You're all set! Let me know when you're ready to start with `/plan-and-analyze`.
