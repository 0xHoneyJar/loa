---
description: Launch the Loa setup wizard for onboarding, MCP configuration, and project initialization
---

# Loa Setup Wizard

Welcome to **Loa** - an agent-driven development framework that guides you from requirements through production deployment using specialized AI agents.

## What /setup Will Do

1. **Phase 1**: Check your MCP server configuration
2. **Phase 2**: Help configure any missing integrations (optional)
3. **Phase 3**: Connect to Hivemind OS (optional - enables organizational memory)
4. **Phase 4**: Select project type (determines mode and skills)
5. **Phase 5**: Link Product Home project (optional - for candidate surfacing)
6. **Phase 6**: Link Experiment from Linear (optional - injects hypothesis context)
7. Initialize project tracking and analytics

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

## Phase 2.5: Hivemind OS Connection (NEW)

After MCP configuration, present the Hivemind connection option:

---

### Connect to Hivemind OS (Optional)

Use the `AskUserQuestion` tool to ask:

**Question**: "Would you like to connect to Hivemind OS?"

**Options**:
1. **Yes, connect** - Enables organizational memory, auto-loads skills, and context injection
2. **Skip for now** - Loa will work standalone without Hivemind integration

If user selects "Yes, connect":

#### 2.5.1 Detect Hivemind Path

Run these commands to detect Hivemind:

```bash
# Check default sibling location
if [ -d "../hivemind-library" ]; then
    echo "FOUND:../hivemind-library"
elif [ -d "../../hivemind-library" ]; then
    echo "FOUND:../../hivemind-library"
else
    echo "NOT_FOUND"
fi
```

If Hivemind is found at the default location, confirm with user:

**Question**: "Hivemind detected at `{path}`. Use this location?"

**Options**:
1. **Yes, use detected path** (Recommended)
2. **Use custom path** - I'll specify a different location

If not found or user wants custom path, use `AskUserQuestion` to prompt for the path.

#### 2.5.2 Create Symlink

```bash
# Create the .hivemind symlink
ln -sfn "{HIVEMIND_PATH}" .hivemind

# Validate the symlink
if [ -d ".hivemind/library" ]; then
    echo "SUCCESS: Hivemind connected"
else
    echo "FAILED: Symlink created but library not found"
fi
```

#### 2.5.3 Add to .gitignore

Check if `.hivemind/` is already in `.gitignore`. If not, append:

```bash
# Check if already present
if ! grep -q "^\.hivemind/$" .gitignore 2>/dev/null; then
    echo "" >> .gitignore
    echo "# Hivemind OS Integration (symlink to organizational memory)" >> .gitignore
    echo ".hivemind/" >> .gitignore
fi
```

#### 2.5.4 Update Integration Context

Create or update `loa-grimoire/a2a/integration-context.md` with Hivemind section:

```markdown
## Hivemind Integration

### Connection Status
- **Hivemind Path**: .hivemind → {resolved_path}
- **Connection Date**: {ISO_timestamp}
- **Status**: Connected

### Loaded Skills
(Will be populated in Phase 3.5)
```

If user skips or symlink fails, add this instead:

```markdown
## Hivemind Integration

### Connection Status
- **Status**: Not Connected
- **Reason**: {User skipped | Path not found | Symlink failed}
```

---

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

### 3.2 Project Type Selection (NEW)

If Hivemind is connected, present project type selection:

Use the `AskUserQuestion` tool:

**Question**: "What type of project is this?"

**Header**: "Project Type"

**Options**:
1. **Frontend** - Web UI, React/Next.js components, design systems
2. **Contracts** - Solidity/smart contracts, on-chain logic
3. **Indexer** - Envio handlers, blockchain data processing
4. **Game Design** - Quest design, game mechanics, XP systems
5. **Backend** - APIs, servers, infrastructure
6. **Cross-Domain** - Spans multiple areas (loads all skills)

Store the selected project type in `loa-grimoire/a2a/integration-context.md`:

```markdown
### Project Configuration
- **Project Type**: {selected_type}
- **Configured At**: {ISO_timestamp}
```

### 3.3 Create Linear Project (if Linear configured)

If Linear MCP is configured:
1. Check if a project with the repo name already exists using `mcp__linear__list_projects`
2. If not, create one using `mcp__linear__create_project` with:
   - Name: {repo_name}
   - Team: Use the team from `loa-grimoire/a2a/integration-context.md` if it exists, otherwise list teams and let user choose
   - Description: "Project tracking for {repo_name} built with Loa framework"

If Linear is not configured, skip this step and note it in the summary.

### 3.4 Initialize Analytics

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

Log any failures (Linear project creation, etc.) to the `setup_failures` array.

### 3.5 Skill Symlink Creation (NEW)

If Hivemind is connected, create skill symlinks based on project type:

```bash
# Create skills directory if needed
mkdir -p .claude/skills

# Source directory
SKILL_SOURCE=".hivemind/.claude/skills"
SKILL_TARGET=".claude/skills"
```

Based on project type, symlink the relevant skills:

**Frontend**:
```bash
ln -sfn "$SKILL_SOURCE/lab-frontend-design-systems" "$SKILL_TARGET/"
ln -sfn "$SKILL_SOURCE/lab-creative-mode-operations" "$SKILL_TARGET/"
# Brand skills
ln -sfn "$SKILL_SOURCE/lab-cubquests-brand-identity" "$SKILL_TARGET/" 2>/dev/null || true
ln -sfn "$SKILL_SOURCE/lab-henlo-brand-identity" "$SKILL_TARGET/" 2>/dev/null || true
ln -sfn "$SKILL_SOURCE/lab-mibera-brand-identity" "$SKILL_TARGET/" 2>/dev/null || true
```

**Contracts**:
```bash
ln -sfn "$SKILL_SOURCE/lab-contract-lifecycle-management" "$SKILL_TARGET/"
ln -sfn "$SKILL_SOURCE/lab-security-mode-operations" "$SKILL_TARGET/"
ln -sfn "$SKILL_SOURCE/lib-hitl-gate-patterns" "$SKILL_TARGET/"
```

**Indexer**:
```bash
ln -sfn "$SKILL_SOURCE/lab-envio-indexer-patterns" "$SKILL_TARGET/"
ln -sfn "$SKILL_SOURCE/lab-thj-ecosystem-overview" "$SKILL_TARGET/"
```

**Game Design**:
```bash
ln -sfn "$SKILL_SOURCE/lab-cubquests-game-design" "$SKILL_TARGET/"
ln -sfn "$SKILL_SOURCE/lab-cubquests-visual-identity" "$SKILL_TARGET/"
ln -sfn "$SKILL_SOURCE/lab-creative-mode-operations" "$SKILL_TARGET/"
# Brand skills
ln -sfn "$SKILL_SOURCE/lab-cubquests-brand-identity" "$SKILL_TARGET/" 2>/dev/null || true
ln -sfn "$SKILL_SOURCE/lab-henlo-brand-identity" "$SKILL_TARGET/" 2>/dev/null || true
```

**Backend**:
```bash
ln -sfn "$SKILL_SOURCE/lab-thj-ecosystem-overview" "$SKILL_TARGET/"
ln -sfn "$SKILL_SOURCE/lib-orchestration-patterns" "$SKILL_TARGET/"
```

**Cross-Domain** (all skills):
```bash
# Load all available skills
for skill in "$SKILL_SOURCE"/*; do
    if [ -d "$skill" ]; then
        ln -sfn "$skill" "$SKILL_TARGET/"
    fi
done
```

After creating symlinks, log which were successfully created to `integration-context.md`:

```markdown
### Loaded Skills
- lab-frontend-design-systems ✓
- lab-creative-mode-operations ✓
- lab-cubquests-brand-identity ✓
```

### 3.6 Mode State Initialization (NEW)

Create `.claude/.mode` file based on project type:

**Mode Mapping**:
- `frontend` → `creative`
- `game-design` → `creative`
- `backend` → `creative`
- `cross-domain` → `creative`
- `contracts` → `secure`
- `indexer` → `secure`

```json
{
  "current_mode": "{mode_based_on_project_type}",
  "set_at": "{ISO_timestamp}",
  "project_type": "{selected_project_type}",
  "mode_switches": []
}
```

Add `.claude/.mode` to `.gitignore` if not present:

```bash
if ! grep -q "^\.claude/\.mode$" .gitignore 2>/dev/null; then
    echo "" >> .gitignore
    echo "# Loa mode state (per-developer)" >> .gitignore
    echo ".claude/.mode" >> .gitignore
fi
```

### 3.7 Product Home Linking (NEW)

If Linear MCP is configured, present Product Home linking option:

Use the `AskUserQuestion` tool:

**Question**: "Would you like to link a Linear Product Home project?"

**Header**: "Product Home"

**Options**:
1. **Link existing** - Connect to an existing Linear project (Recommended)
2. **Create new** - Create a new Product Home project
3. **Skip for now** - Candidates will use default team project

#### If "Link existing":

Use `AskUserQuestion` to prompt:
```json
{
  "question": "Enter the Linear project ID or issue URL from the Product Home project",
  "header": "Project ID"
}
```

Extract project ID from:
- Direct project ID (e.g., `abc123def456`)
- Issue URL (e.g., `https://linear.app/honeyjar/issue/LAB-123`) - extract project from issue

Validate by fetching project details:
```
mcp__linear__get_project({ id: "{extracted_project_id}" })
```

#### If "Create new":

Create a new Product Home project:
```
mcp__linear__create_project({
  name: "{project_name} - Product Home",
  teamId: "{team_id}",
  description: "Product Home for {project_name}. Contains epics, experiments, and feature tracking."
})
```

#### Store in integration-context.md:

```markdown
### Product Home

- **Project ID**: {project_id}
- **Project Name**: {project_name}
- **Linked At**: {ISO_timestamp}
- **Link Type**: {linked | created}
```

If user skips, add:
```markdown
### Product Home

- **Status**: Not Linked
- **Note**: Candidates will use team default project
```

---

### 3.8 Experiment Linking (NEW)

If Hivemind is connected and Linear is configured, offer experiment linking:

Use the `AskUserQuestion` tool:

**Question**: "Would you like to link a Hivemind experiment from Linear?"

**Header**: "Experiment"

**Options**:
1. **Link experiment** - Connect to an existing experiment issue
2. **Skip for now** - No experiment context will be injected

#### If "Link experiment":

Use `AskUserQuestion` to prompt for the Linear issue URL:
```json
{
  "question": "Enter the Linear experiment issue URL (e.g., https://linear.app/honeyjar/issue/LAB-123)",
  "header": "Experiment URL"
}
```

Extract issue ID and fetch experiment details:
```
mcp__linear__get_issue({ id: "{issue_id}" })
```

Parse the issue for:
- **Title**: Experiment name
- **Description**: Look for "Hypothesis:" or "Success Criteria:" sections
- **Labels**: Check for `experiment` label to validate

Store in integration-context.md:

```markdown
### Linked Experiment

- **Issue ID**: {issue_id}
- **Issue URL**: {issue_url}
- **Title**: {experiment_title}
- **Hypothesis**: {extracted_hypothesis}
- **Success Criteria**: {extracted_criteria}
- **Linked At**: {ISO_timestamp}
```

This experiment context will be injected during `/plan-and-analyze` to inform the PRD.

If user skips:
```markdown
### Linked Experiment

- **Status**: Not Linked
```

---

### 3.9 Generate Summary.md

Update `loa-grimoire/analytics/summary.md` with the initialized data in a human-readable format.

### 3.10 Create Marker File

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

Display a clear, polished summary of what was configured with progress indication:

---

```
╔════════════════════════════════════════════════════════════════╗
║                     🎉 Setup Complete!                         ║
╚════════════════════════════════════════════════════════════════╝
```

### MCP Servers (Phase 1/6 ✓)

| Server | Status |
|--------|--------|
| github | {Configured ✓ / Skipped} |
| linear | {Configured ✓ / Skipped} |
| vercel | {Configured ✓ / Skipped} |
| discord | {Configured ✓ / Skipped} |
| web3-stats | {Configured ✓ / Skipped} |

### Hivemind Connection (Phase 2/6 ✓)

| Setting | Value |
|---------|-------|
| Connection | {Connected ✓ → ../hivemind-library / Not Connected} |
| Project Type | {frontend / contracts / indexer / game-design / backend / cross-domain / N/A} |
| Mode | {Creative / Secure / N/A} |
| Skills Loaded | {count} skills |

### Project Initialization (Phase 3/6 ✓)

| Setting | Value |
|---------|-------|
| Project Name | {project_name} |
| Linear Project | {Created ✓ / Linked ✓ / Skipped} |
| Analytics | Initialized ✓ |

### Product Home (Phase 4/6 ✓)

| Setting | Value |
|---------|-------|
| Status | {Linked ✓ / Created ✓ / Not Linked} |
| Project | {project_name if linked/created / N/A} |

### Experiment (Phase 5/6 ✓)

| Setting | Value |
|---------|-------|
| Status | {Linked ✓ / Not Linked} |
| Experiment | {experiment_title if linked / N/A} |
| Hypothesis | {first 50 chars of hypothesis...} |

### Configuration Summary (Phase 6/6 ✓)

```
┌─────────────────────────────────────────────────────────────┐
│ Hivemind:      {Connected (../hivemind-library) / Not Connected}
│ Project Type:  {game-design / frontend / contracts / etc.}
│ Mode:          {Creative / Secure}
│ Skills:        {count} loaded
│ Product Home:  {project_name (linked) / Not linked}
│ Experiment:    {experiment_title (LAB-XXX) / Not linked}
└─────────────────────────────────────────────────────────────┘
```

### Next Steps

1. **Run `/plan-and-analyze`** to create your Product Requirements Document
   {If experiment linked: "Your experiment hypothesis will be injected as context."}
2. Follow the Loa workflow: `/architect` → `/sprint-plan` → `/implement`
3. After deployment, run `/feedback` to share your experience

**Tip**: Check `loa-grimoire/analytics/summary.md` for your usage statistics at any time.

---

You're all set! Let me know when you're ready to start with `/plan-and-analyze`.
