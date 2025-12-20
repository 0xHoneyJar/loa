---
description: Launch the Loa setup wizard for onboarding, MCP configuration, and project initialization
---

# Loa Setup Wizard

Welcome to **Loa** - an agent-driven development framework that guides you from requirements through production deployment using specialized AI agents.

---

## Phase 0: User Type Detection

Before we begin, I need to determine which setup pathway to use.

**Use the `AskUserQuestion` tool** to ask:

**Question**: "Are you a THJ team member?"

**Options**:
- **Yes** - "I'm a THJ team member"
- **No** - "I'm using Loa as an open-source tool"

Based on the response:
- If **Yes (THJ)**: Proceed to **Phase 0.5: Template Detection**, then **Phase 1A: THJ Developer Setup**
- If **No (OSS)**: Proceed to **Phase 0.5: Template Detection**, then **Phase 1B: OSS User Setup**

---

## Phase 0.5: Template Detection

This phase detects whether the current repository is a fork or template of the Loa framework. This enables git safety features that prevent accidental pushes to upstream.

### Step 1: Run Detection Layers

Execute the following detection layers in order. Stop at the first positive detection:

**Layer 1: Check origin remote URL**
```bash
# Check if origin points to a known template repository
git remote get-url origin 2>/dev/null
```

Check if the URL contains any of these known template repositories:
- `github.com/0xHoneyJar/loa`
- `github.com/thj-dev/loa`

**Layer 2: Check for upstream/loa remote**
```bash
# Check if an 'upstream' or 'loa' remote exists pointing to template
git remote get-url upstream 2>/dev/null
git remote get-url loa 2>/dev/null
```

Check if either remote URL contains a known template repository.

**Layer 3: GitHub API fork check (if gh CLI available)**
```bash
# Query GitHub API for fork relationship
gh repo view --json parent --jq '.parent.nameWithOwner' 2>/dev/null
```

If this returns `0xHoneyJar/loa` or another known template, it's a fork.

### Step 2: Store Detection Result

Store the template detection result for use in the marker file (created in Phase 1A/1B Step 7/Step 2):

```
template_source:
  detected: {true/false}
  repo: "{detected_template_repo or null}"
  detection_method: "{origin_url|upstream_remote|loa_remote|github_api|none}"
  detected_at: "{ISO_timestamp}"
```

### Step 3: Display Template Notice (if detected)

If a template source was detected, display this notice:

```
## Template Repository Detected

This repository appears to be a fork/template of: {detected_repo}
Detection method: {detection_method}

### Git Safety Features Enabled

Loa will warn you before any push or PR operation targeting the upstream
template repository. This prevents accidentally leaking your project code.

### Your Options

- **Building your own project?**
  Ensure your `origin` remote points to YOUR repository, not the template.
  Check with: `git remote -v`

- **Contributing to Loa?**
  Use the `/contribute` command for a guided contribution flow with
  proper OSS standards (DCO sign-off, secrets scanning, etc.).

See CONTRIBUTING.md for more details on git remote configuration.
```

### Step 4: Continue to User-Specific Setup

Proceed to Phase 1A (THJ) or Phase 1B (OSS) based on the user type detected in Phase 0.

---

## Phase 1A: THJ Developer Setup

### Step 1: Welcome & Documentation

Display this welcome message:

```
Welcome, THJ Developer!

Loa will guide you through the complete product development lifecycle using specialized AI agents:

1. /plan-and-analyze - Define requirements with the PRD architect
2. /architect - Design system architecture
3. /sprint-plan - Break down work into sprints
4. /implement - Execute sprint tasks
5. /review-sprint - Code review and approval
6. /audit-sprint - Security audit
7. /deploy-production - Production deployment

For detailed workflow documentation, see: PROCESS.md
```

### Step 2: Analytics Notice

Display this notice (analytics cannot be disabled for THJ developers):

```
## Analytics Notice

Loa collects usage analytics to improve the framework:
- Session timing and phase completion
- Sprint metrics and feedback iterations
- Environment info (OS, shell, versions)

**Privacy**: Analytics are stored locally in `loa-grimoire/analytics/`.
Data is only shared if you choose to run `/feedback` after deployment.

Analytics tracking is enabled for THJ team members.
```

### Step 3: Initialize Analytics

Create the `loa-grimoire/analytics/` directory if it doesn't exist.

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

Create `loa-grimoire/analytics/usage.json` with:

```json
{
  "schema_version": "1.0.0",
  "framework_version": "0.2.0",
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
    "mcp_servers_configured": []
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
  "feedback_submissions": [],
  "setup_failures": []
}
```

Generate `loa-grimoire/analytics/summary.md` with the initialized data in human-readable format.

### Step 4: MCP Integration Selection

**Use the `AskUserQuestion` tool** with multiSelect enabled to ask:

**Question**: "Which MCP integrations would you like to configure?"

**Options** (multiSelect: true):
- **Linear** - "Issue tracking for developer feedback"
- **GitHub** - "Repository operations, PRs, issues"
- **Vercel** - "Deployment and hosting"
- **Discord** - "Community/team communication"
- **web3-stats** - "Blockchain data (Dune API, Blockscout)"
- **All** - "Configure all integrations"
- **Skip** - "Skip for now (configure later with /config)"

If user selects "All", treat it as selecting all 5 MCPs.
If user selects "Skip", proceed to Step 6 with empty MCP list.

### Step 5: MCP Configuration

For each selected MCP, provide guided setup:

**GitHub MCP**:
```
GitHub MCP Setup:
1. Create a Personal Access Token at https://github.com/settings/tokens
2. Token scopes needed: repo, read:org, read:user
3. Add "github" to enabledMcpjsonServers in .claude/settings.local.json
4. Restart Claude Code to apply changes
```

**Linear MCP**:
```
Linear MCP Setup:
1. Get your API key from Linear: Settings > API > Personal API keys
2. Add "linear" to enabledMcpjsonServers in .claude/settings.local.json
3. Restart Claude Code to apply changes
```

**Vercel MCP**:
```
Vercel MCP Setup:
1. Connect via Vercel OAuth at https://vercel.com/integrations
2. Add "vercel" to enabledMcpjsonServers in .claude/settings.local.json
3. Restart Claude Code to apply changes
```

**Discord MCP**:
```
Discord MCP Setup:
1. Create a Discord bot at https://discord.com/developers/applications
2. Get the bot token from Bot > Token
3. Add "discord" to enabledMcpjsonServers in .claude/settings.local.json
4. Restart Claude Code to apply changes
```

**web3-stats MCP**:
```
web3-stats MCP Setup:
1. Get a Dune API key at https://dune.com/settings/api
2. Add "web3-stats" to enabledMcpjsonServers in .claude/settings.local.json
3. Restart Claude Code to apply changes
```

Track which MCPs were configured.

### Step 6: Update Analytics with MCP Info

Update `loa-grimoire/analytics/usage.json` to include the configured MCPs in `setup.mcp_servers_configured`.

### Step 7: Create Marker File

Create `.loa-setup-complete` in the project root with:

```json
{
  "completed_at": "{ISO_timestamp}",
  "framework_version": "0.2.0",
  "user_type": "thj",
  "mcp_servers": ["{list_of_configured_mcps}"],
  "git_user": "{git_user_email}",
  "template_source": {
    "detected": "{true/false from Phase 0.5}",
    "repo": "{detected_repo or null}",
    "detection_method": "{detection_method or none}",
    "detected_at": "{ISO_timestamp}"
  }
}
```

### Step 8: Completion Summary (THJ)

Display:

```
## Setup Complete!

### User Type
THJ Developer (analytics enabled)

### MCP Servers Configured
{list configured MCPs or "None - run /config to add later"}

### Project Initialization
- **Project Name**: {project_name}
- **Analytics**: Initialized at loa-grimoire/analytics/

### Next Steps

1. Run `/plan-and-analyze` to create your Product Requirements Document
2. Follow the Loa workflow: `/architect` > `/sprint-plan` > `/implement`
3. Need to add MCP integrations later? Run `/config`
4. After deployment, run `/feedback` to share your experience

**Tip**: Check `loa-grimoire/analytics/summary.md` for your usage statistics at any time.
```

**Proceed to END** - Setup complete.

---

## Phase 1B: OSS User Setup

### Step 1: Welcome & Documentation

Display this welcome message:

```
Welcome to Loa!

Loa is an agent-driven development framework that guides you through the complete
product development lifecycle using specialized AI agents:

1. /plan-and-analyze - Define requirements with the PRD architect
2. /architect - Design system architecture
3. /sprint-plan - Break down work into sprints
4. /implement - Execute sprint tasks
5. /review-sprint - Code review and approval
6. /audit-sprint - Security audit
7. /deploy-production - Production deployment

For detailed workflow documentation, see: PROCESS.md
```

### Step 2: Create Marker File (OSS)

**Do NOT initialize analytics** - skip the `loa-grimoire/analytics/` directory entirely.

Run these commands to get basic project info:

```bash
# Get developer email for marker file
git config user.email
```

Create `.loa-setup-complete` in the project root with:

```json
{
  "completed_at": "{ISO_timestamp}",
  "framework_version": "0.2.0",
  "user_type": "oss",
  "mcp_servers": [],
  "git_user": "{git_user_email}",
  "template_source": {
    "detected": "{true/false from Phase 0.5}",
    "repo": "{detected_repo or null}",
    "detection_method": "{detection_method or none}",
    "detected_at": "{ISO_timestamp}"
  }
}
```

### Step 3: Completion Summary (OSS)

Display:

```
## Setup Complete!

### User Type
Open Source User

### Next Steps

1. Run `/plan-and-analyze` to create your Product Requirements Document
2. Follow the Loa workflow: `/architect` > `/sprint-plan` > `/implement`
3. Review PROCESS.md for detailed workflow documentation

**Note**: MCP integrations and analytics are not enabled for open-source users.
For issues or feature requests, please open a GitHub issue at:
https://github.com/0xHoneyJar/loa/issues
```

**Proceed to END** - Setup complete.

---

## END

Setup is complete. The user can now proceed with `/plan-and-analyze` to begin their project.
