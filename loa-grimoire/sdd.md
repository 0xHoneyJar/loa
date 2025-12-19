# Software Design Document: Loa Setup, Analytics & Feedback System

**Version**: 1.0
**Date**: 2025-12-19
**Author**: Architecture Designer Agent
**Status**: Draft
**PRD Reference**: loa-grimoire/prd.md v1.0

---

## 1. Executive Summary

This document defines the technical architecture for extending Loa with three new capabilities: an onboarding flow (`/setup`), analytics capture system, and feedback flow (`/feedback`). The design prioritizes seamless integration with the existing Loa framework while maintaining non-blocking, low-friction experiences for developers.

### 1.1 Design Principles

1. **Non-Blocking**: Analytics and tracking never impede the primary workflow
2. **Progressive Enhancement**: MCPs are optional; core functionality works without them
3. **Stateless Agents**: Context maintained through files, not agent memory
4. **Convention Over Configuration**: Sensible defaults, minimal required decisions
5. **Transparency**: Clear feedback about what's being tracked and where

### 1.2 Key Architectural Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| First-launch detection | Marker file (`.loa-setup-complete`) | Simple, explicit, easy to reset |
| Token tracking | Session-based estimation | Claude Code doesn't expose metrics; estimation captures trends |
| Developer identifier | Git `user.name` + `user.email` | Already available, consistent with commits |
| Update behavior | Require clean working tree | Safest, forces explicit decision |
| MCP detection | Read `settings.local.json` | Non-intrusive, fast |
| Linear project naming | Git repo name | Automatic, consistent |
| Feedback project | Pre-existing "Loa Feedback" | Reduces complexity, clear ownership |
| Setup enforcement | Check in `/plan-and-analyze` command | Simple, no hooks required |
| Analytics timing | Phase boundaries | Balanced I/O vs. granularity |
| Update merge strategy | Prefer upstream for `.claude/` | Preserves app code, updates framework |
| Summary format | Markdown tables | Readable everywhere |

---

## 2. System Architecture

### 2.1 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Loa Framework                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │                        New Components (This SDD)                      │  │
│  │                                                                        │  │
│  │  ┌─────────────┐    ┌─────────────────┐    ┌─────────────────┐       │  │
│  │  │   /setup    │    │   Analytics     │    │   /feedback     │       │  │
│  │  │   Command   │    │   System        │    │   Command       │       │  │
│  │  │             │    │                 │    │                 │       │  │
│  │  │ - Welcome   │    │ - Capture       │    │ - Survey        │       │  │
│  │  │ - MCP Wizard│    │ - Storage       │    │ - Submission    │       │  │
│  │  │ - Project   │    │ - Summary Gen   │    │ - Linear Post   │       │  │
│  │  │   Init      │    │                 │    │                 │       │  │
│  │  └──────┬──────┘    └────────┬────────┘    └────────┬────────┘       │  │
│  │         │                    │                      │                 │  │
│  │         └────────────────────┼──────────────────────┘                 │  │
│  │                              │                                        │  │
│  │  ┌───────────────────────────┴───────────────────────────────────┐   │  │
│  │  │                    /update Command                              │   │  │
│  │  │                    - Git upstream fetch                         │   │  │
│  │  │                    - Merge with strategy                        │   │  │
│  │  └─────────────────────────────────────────────────────────────────┘   │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │                     Existing Loa Framework                            │  │
│  │                                                                        │  │
│  │  /plan-and-analyze → /architect → /sprint-plan → /implement →         │  │
│  │  /review-sprint → /audit-sprint → /deploy-production                  │  │
│  │                                                                        │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                           Data Layer                                         │
│                                                                             │
│  ┌────────────────────┐  ┌────────────────────┐  ┌───────────────────────┐ │
│  │ .loa-setup-complete│  │ loa-grimoire/      │  │ .claude/              │ │
│  │ (marker file)      │  │ analytics/         │  │ settings.local.json   │ │
│  │                    │  │ - usage.json       │  │ (MCP config)          │ │
│  │                    │  │ - summary.md       │  │                       │ │
│  └────────────────────┘  └────────────────────┘  └───────────────────────┘ │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                       External Integrations                                  │
│                                                                             │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────────┐ │
│  │  GitHub  │  │  Linear  │  │  Vercel  │  │ Discord  │  │  web3-stats  │ │
│  │   MCP    │  │   MCP    │  │   MCP    │  │   MCP    │  │     MCP      │ │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘  └──────────────┘ │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Component Interactions

```
                                   Developer
                                       │
                                       ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│                              Claude Code CLI                                  │
│                                                                              │
│  ┌────────────────┐                                                          │
│  │ First Launch?  │──Yes──▶ Suggest /setup                                   │
│  └───────┬────────┘                                                          │
│          │ No                                                                │
│          ▼                                                                   │
│  ┌────────────────┐     ┌─────────────────┐     ┌──────────────────────┐    │
│  │ /plan-and-    │────▶│ Setup Complete? │──No─▶│ Block: Run /setup   │    │
│  │   analyze     │     └────────┬────────┘     │ first                │    │
│  └───────────────┘              │ Yes          └──────────────────────┘    │
│                                 ▼                                            │
│                     ┌──────────────────────┐                                 │
│                     │ Proceed with PRD     │                                 │
│                     │ creation             │                                 │
│                     └──────────────────────┘                                 │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                        Analytics System                                 │ │
│  │                                                                         │ │
│  │   On Phase Complete ─────┐                                              │ │
│  │   On Session End ────────┼──▶ Update usage.json ──▶ Regenerate         │ │
│  │   On Commit ─────────────┘                          summary.md          │ │
│  │                                                                         │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │                      /feedback Flow                                      ││
│  │                                                                          ││
│  │  Survey ──▶ Collect Responses ──▶ Load Analytics ──▶ Post to Linear     ││
│  │                                                                          ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Technology Stack

### 3.1 Core Technologies

| Component | Technology | Justification |
|-----------|------------|---------------|
| Command Implementation | Slash commands (`.claude/commands/`) | Native Loa pattern, no additional tooling |
| Agent Implementation | Agent definitions (`.claude/agents/`) | Native Loa pattern for complex logic |
| Data Storage | JSON files + Markdown | Human-readable, git-friendly, no database |
| MCP Detection | JSON parsing | Standard, reliable |
| Git Operations | Git CLI via Bash | Direct, well-understood |

### 3.2 File Structure

```
/project-root/
├── .loa-setup-complete              # Marker file (created by /setup)
├── .claude/
│   ├── agents/
│   │   └── setup-wizard.md          # New agent for /setup (optional)
│   ├── commands/
│   │   ├── setup.md                 # /setup command
│   │   ├── feedback.md              # /feedback command
│   │   ├── update.md                # /update command
│   │   └── plan-and-analyze.md      # Modified to check setup
│   └── settings.local.json          # MCP configuration
├── loa-grimoire/
│   ├── analytics/
│   │   ├── usage.json               # Raw analytics data
│   │   └── summary.md               # Human-readable summary
│   ├── prd.md
│   ├── sdd.md
│   └── sprint.md
└── app/                             # Application code
```

---

## 4. Component Design

### 4.1 Setup Command (`/setup`)

#### 4.1.1 Responsibilities

1. Display welcome message and analytics notice
2. Detect configured MCP servers
3. Guide configuration of missing MCPs (optional)
4. Initialize Linear project (if Linear configured)
5. Set up branch protection (if GitHub configured)
6. Initialize analytics tracking
7. Create marker file

#### 4.1.2 Command Implementation

**File**: `.claude/commands/setup.md`

```markdown
---
description: Launch the Loa setup wizard for onboarding, MCP configuration, and project initialization
---

# Loa Setup Wizard

Welcome to Loa! Let me help you get set up.

## Phase 1: Welcome

**What is Loa?**
Loa is an agent-driven development framework that guides you from requirements through production deployment using specialized AI agents.

**What /setup will do:**
1. Check your MCP server configuration
2. Help configure any missing integrations
3. Initialize project tracking (Linear project, branch protection)
4. Set up analytics tracking

**Analytics Notice:**
Loa collects usage analytics to improve the framework:
- Session timing and phase completion
- Commit counts and feedback iterations
- Environment info (OS, shell, versions)

Analytics are stored locally in `loa-grimoire/analytics/` and optionally shared via `/feedback`. No data is sent automatically.

## Phase 2: MCP Detection

Let me check your current MCP configuration...

Read `.claude/settings.local.json` and identify:
- Which MCPs are configured: github, linear, vercel, discord, web3-stats
- Which are missing

For each MCP, determine if `enabledMcpjsonServers` array contains the server name.

## Phase 3: MCP Configuration (for missing servers)

For each missing MCP, ask:

**[MCP Name] is not configured.**

Options:
1. **Guided Setup** - I'll walk you through configuration
2. **Self-Service** - Get documentation link and configure yourself
3. **Skip** - Don't configure this MCP (it's optional)

### Guided Setup Instructions by MCP:

**GitHub MCP:**
1. Ensure you have a GitHub Personal Access Token
2. Add "github" to enabledMcpjsonServers in settings
3. Token should have: repo, read:org, read:user scopes

**Linear MCP:**
1. Get your Linear API key from Settings → API
2. Add "linear" to enabledMcpjsonServers
3. Ensure you have access to THJ workspace

**Vercel MCP:**
1. Connect via Vercel OAuth
2. Add "vercel" to enabledMcpjsonServers

**Discord MCP:**
1. Create/use a Discord bot token
2. Add "discord" to enabledMcpjsonServers
3. Ensure bot has required permissions

**web3-stats MCP:**
1. Get Dune API key from dune.com
2. Add "web3-stats" to enabledMcpjsonServers

## Phase 4: Project Initialization

### 4.1 Get Project Info

Determine project name from git remote:
```bash
git remote get-url origin
```
Extract repo name from URL.

Get developer identifier:
```bash
git config user.name
git config user.email
```

### 4.2 Linear Project Creation (if Linear configured)

Create a new Linear project:
- Project name: {repo_name}
- Team: THJ (or prompt if multiple teams)

Use `mcp__linear__create_project` to create the project.

### 4.3 Branch Protection (if GitHub configured)

Check if main branch protection exists.
If not, offer to enable:
- Require pull request reviews
- Require status checks

Note: Branch protection requires admin access. If it fails, log to analytics and continue.

### 4.4 Initialize Analytics

Create `loa-grimoire/analytics/` directory if not exists.

Initialize `loa-grimoire/analytics/usage.json` with:
- Project metadata (name, repo, timestamps)
- Environment info (collect via bash commands)
- Empty usage counters
- Setup phase marked complete

Generate initial `loa-grimoire/analytics/summary.md`.

## Phase 5: Completion

Create `.loa-setup-complete` marker file in project root.

Display summary:
- MCPs configured: [list]
- Linear project: {name} (or "skipped")
- Branch protection: enabled/skipped
- Analytics: initialized

**Next Steps:**
1. Run `/plan-and-analyze` to create your PRD
2. Follow the Loa workflow through deployment
3. Run `/feedback` after deployment to share your experience

Setup complete! You can now use all Loa commands.
```

#### 4.1.3 State Machine

```
┌─────────────┐
│   START     │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  WELCOME    │──────▶ Display welcome, analytics notice
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ MCP_DETECT  │──────▶ Read settings.local.json
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ MCP_CONFIG  │──────▶ For each missing: guide/docs/skip
└──────┬──────┘        (repeat for each missing MCP)
       │
       ▼
┌─────────────┐
│ PROJECT_INIT│──────▶ Linear project, branch protection
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ANALYTICS_INIT│─────▶ Create usage.json, summary.md
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  COMPLETE   │──────▶ Create marker, show summary
└─────────────┘
```

#### 4.1.4 Error Handling

| Error | Handling | Analytics Logging |
|-------|----------|-------------------|
| MCP auth failure | Log error, offer retry or skip | Yes - setup_failures array |
| Linear project creation fails | Log error, continue without | Yes |
| Branch protection fails | Log error, continue | Yes |
| Git remote not found | Prompt for project name | No |
| Analytics dir creation fails | Fatal error, stop setup | N/A |

### 4.2 Analytics System

#### 4.2.1 Data Collection Points

| Event | Data Collected | Trigger |
|-------|----------------|---------|
| Setup Complete | Environment info, MCPs configured | End of /setup |
| Session Start | Timestamp | Agent invocation |
| Session End | Duration, estimated tokens | Agent completion |
| Phase Complete | Phase name, timestamp | PRD/SDD/sprint saved |
| Commit | Increment counter | Post-commit (estimated) |
| Sprint Iteration | Review/audit cycle count | Feedback file updates |

#### 4.2.2 Token Estimation Strategy

Since Claude Code CLI doesn't expose token metrics directly:

1. **Input Token Estimation**:
   - Track prompt/command length
   - Track files read (character count → token estimate at ~4 chars/token)

2. **Output Token Estimation**:
   - Track files written (character count → token estimate)
   - Track response length when visible

3. **Aggregation**:
   - Store estimates in `usage.json`
   - Mark as "estimated" in summary

#### 4.2.3 Analytics File Format

**`loa-grimoire/analytics/usage.json`**

```json
{
  "schema_version": "1.0",
  "project": {
    "name": "my-defi-app",
    "repo": "0xHoneyJar/my-defi-app",
    "created_at": "2025-12-19T10:00:00Z",
    "setup_completed_at": "2025-12-19T10:05:00Z"
  },
  "developer": {
    "name": "John Developer",
    "email": "john@thehoneyjar.xyz"
  },
  "environment": {
    "os": "darwin",
    "os_version": "macOS 14.2",
    "shell": "zsh",
    "cpu": "Apple M2 Pro",
    "cpu_cores": 12,
    "ram_gb": 32,
    "architecture": "arm64",
    "claude_code_version": "1.0.0",
    "node_version": "20.10.0"
  },
  "mcp_configured": {
    "github": true,
    "linear": true,
    "vercel": true,
    "discord": false,
    "web3_stats": true
  },
  "usage": {
    "total_sessions": 15,
    "total_tokens_input_estimated": 125000,
    "total_tokens_output_estimated": 85000,
    "total_time_minutes": 480,
    "total_commits": 42
  },
  "phases": {
    "setup": {
      "completed": true,
      "timestamp": "2025-12-19T10:05:00Z"
    },
    "prd": {
      "completed": true,
      "timestamp": "2025-12-19T11:30:00Z",
      "sessions": 3
    },
    "sdd": {
      "completed": true,
      "timestamp": "2025-12-19T14:00:00Z",
      "sessions": 2
    },
    "sprint_plan": {
      "completed": true,
      "timestamp": "2025-12-19T15:00:00Z",
      "sessions": 1
    },
    "sprints": [
      {
        "name": "sprint-1",
        "implementation_iterations": 2,
        "review_iterations": 1,
        "audit_iterations": 1,
        "completed": true,
        "timestamp": "2025-12-20T16:00:00Z"
      },
      {
        "name": "sprint-2",
        "implementation_iterations": 1,
        "review_iterations": 1,
        "audit_iterations": 0,
        "completed": false,
        "timestamp": null
      }
    ],
    "deployment": {
      "completed": false,
      "timestamp": null
    }
  },
  "setup_failures": [
    {
      "step": "branch_protection",
      "error": "Requires admin access",
      "timestamp": "2025-12-19T10:04:30Z"
    }
  ],
  "feedback_submissions": []
}
```

#### 4.2.4 Summary Generation

**`loa-grimoire/analytics/summary.md`**

```markdown
# Project Analytics Summary

**Project**: my-defi-app
**Developer**: John Developer
**Generated**: 2025-12-20T16:30:00Z

---

## Overview

| Metric | Value |
|--------|-------|
| Total Sessions | 15 |
| Total Time | 8h 0m |
| Total Commits | 42 |
| Tokens (Input, est.) | ~125,000 |
| Tokens (Output, est.) | ~85,000 |

---

## Environment

| Component | Value |
|-----------|-------|
| OS | macOS 14.2 (darwin/arm64) |
| CPU | Apple M2 Pro (12 cores) |
| RAM | 32 GB |
| Shell | zsh |
| Claude Code | v1.0.0 |
| Node.js | v20.10.0 |

---

## MCP Integrations

| Server | Status |
|--------|--------|
| GitHub | Configured |
| Linear | Configured |
| Vercel | Configured |
| Discord | Not Configured |
| web3-stats | Configured |

---

## Phase Progress

| Phase | Status | Completed | Sessions |
|-------|--------|-----------|----------|
| Setup | Complete | 2025-12-19 | 1 |
| PRD | Complete | 2025-12-19 | 3 |
| SDD | Complete | 2025-12-19 | 2 |
| Sprint Plan | Complete | 2025-12-19 | 1 |
| Sprint 1 | Complete | 2025-12-20 | - |
| Sprint 2 | In Progress | - | - |
| Deployment | Not Started | - | - |

---

## Sprint Details

### Sprint 1
- **Implementation Iterations**: 2
- **Review Iterations**: 1
- **Audit Iterations**: 1
- **Status**: Complete

### Sprint 2
- **Implementation Iterations**: 1
- **Review Iterations**: 1
- **Audit Iterations**: 0
- **Status**: In Progress

---

## Setup Issues

| Step | Error | Timestamp |
|------|-------|-----------|
| branch_protection | Requires admin access | 2025-12-19 10:04 |

---

*Analytics are estimates. Token counts are approximations based on input/output sizes.*
```

#### 4.2.5 Analytics Update Integration

Analytics updates happen at these integration points:

1. **In `/setup` command**: Initialize and mark setup complete
2. **In each phase command**: Update on phase completion
3. **In `/implement`**: Track iterations
4. **In `/review-sprint`**: Track review iterations
5. **In `/audit-sprint`**: Track audit iterations
6. **In `/feedback`**: Record submission

**Implementation approach**: Each command includes analytics update logic at appropriate points. Updates are:
- Non-blocking (failures logged but don't stop workflow)
- Incremental (read-modify-write pattern)
- Idempotent where possible

### 4.3 Feedback Command (`/feedback`)

#### 4.3.1 Responsibilities

1. Display survey questions with progress indicators
2. Collect developer responses
3. Load analytics data
4. Create/update Linear issue in "Loa Feedback" project
5. Record submission in analytics

#### 4.3.2 Command Implementation

**File**: `.claude/commands/feedback.md`

```markdown
---
description: Submit feedback about your Loa experience with auto-attached analytics
---

# Loa Feedback

Thank you for taking a moment to share your feedback! This helps improve Loa for everyone.

Your responses will be posted to Linear with your project analytics attached.

## Survey

### Question 1 of 4

**What's one thing you would change about Loa?**

(Free text response - be specific!)

---

### Question 2 of 4

**What's one thing you loved about using Loa?**

(Free text response - what worked well?)

---

### Question 3 of 4

**How does this build compare to your other Loa builds?**

Rate from 1-5:
1. Much worse
2. Somewhat worse
3. About the same
4. Somewhat better
5. Much better

(If this is your first build, select "3 - About the same")

---

### Question 4 of 4

**How comfortable and intuitive was the overall process?**

Select one:
- Very intuitive - I always knew what to do next
- Somewhat intuitive - Mostly clear with occasional confusion
- Neutral - Neither particularly clear nor confusing
- Somewhat confusing - Often unsure of next steps
- Very confusing - Frequently lost or frustrated

---

## Submission

### Load Analytics

Read `loa-grimoire/analytics/usage.json` for project analytics.
If file doesn't exist, note "Analytics not available".

### Prepare Linear Issue

**Project**: Loa Feedback (in THJ workspace)
**Issue Title**: `[{project_name}] - Feedback`

**Search for existing issue** with this title in "Loa Feedback" project.
- If found: Append new feedback as comment
- If not found: Create new issue

### Issue Body / Comment Format

```markdown
---
## Feedback Submission - {timestamp}

**Developer**: {developer_name} ({developer_email})
**Project**: {project_name}

### Survey Responses

1. **What would you change?**
   {response_1}

2. **What did you love?**
   {response_2}

3. **Rating vs other builds**: {rating}/5

4. **Process comfort level**: {comfort_choice}

### Analytics Summary

| Metric | Value |
|--------|-------|
| Total Time | {hours}h {minutes}m |
| Total Sessions | {sessions} |
| Tokens (Input, est.) | ~{input_tokens} |
| Tokens (Output, est.) | ~{output_tokens} |
| Commits | {commits} |
| Phases Completed | {phase_list} |
| Total Review Iterations | {review_count} |
| Total Audit Iterations | {audit_count} |

### Environment

- OS: {os} {os_version}
- Architecture: {architecture}
- Claude Code: {claude_version}

<details>
<summary>Full Analytics JSON</summary>

```json
{full_analytics_json}
```

</details>
---
```

### Update Analytics

Add entry to `feedback_submissions` array in `usage.json`:
```json
{
  "timestamp": "{ISO8601}",
  "linear_issue_id": "{issue_id}"
}
```

### Confirmation

Display:
- "Feedback submitted successfully!"
- Link to Linear issue
- "Thank you for helping improve Loa!"
```

#### 4.3.3 Linear Integration

```
┌─────────────────┐
│ Collect Survey  │
│ Responses       │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Load Analytics  │
│ from usage.json │
└────────┬────────┘
         │
         ▼
┌─────────────────┐     ┌─────────────────┐
│ Search Linear   │────▶│ Issue exists?   │
│ for existing    │     └────────┬────────┘
│ issue           │              │
└─────────────────┘              │
                        ┌────────┴────────┐
                        │                 │
                        ▼                 ▼
               ┌─────────────┐   ┌─────────────┐
               │ Create new  │   │ Add comment │
               │ issue       │   │ to existing │
               └──────┬──────┘   └──────┬──────┘
                      │                 │
                      └────────┬────────┘
                               │
                               ▼
                      ┌─────────────────┐
                      │ Update local    │
                      │ analytics       │
                      └────────┬────────┘
                               │
                               ▼
                      ┌─────────────────┐
                      │ Show confirm-   │
                      │ ation           │
                      └─────────────────┘
```

### 4.4 Update Command (`/update`)

#### 4.4.1 Responsibilities

1. Check for clean working tree
2. Fetch from Loa upstream remote
3. Show changelog/diff summary
4. Merge with strategy (prefer upstream for `.claude/`)
5. Handle conflicts with guidance

#### 4.4.2 Command Implementation

**File**: `.claude/commands/update.md`

```markdown
---
description: Update Loa framework from upstream repository
---

# Loa Update

This command pulls the latest Loa framework updates from the upstream repository.

## Pre-flight Checks

### Check Working Tree

```bash
git status --porcelain
```

If output is not empty:
- Display: "Your working tree has uncommitted changes."
- Display: "Please commit or stash your changes before updating."
- Display list of changed files
- Stop here - do not proceed

### Check Upstream Remote

```bash
git remote -v
```

Look for `loa` remote (or `upstream`). If not found:

Display:
"The Loa upstream remote is not configured."
"To add it, run:"
"  git remote add loa https://github.com/0xHoneyJar/loa.git"

Stop here.

## Fetch Updates

```bash
git fetch loa main
```

### Show Changes

```bash
git log HEAD..loa/main --oneline
```

If no commits:
- Display: "You're already up to date with Loa!"
- Stop here

Display:
- Number of new commits
- List of commits (abbreviated)
- Files changed summary

### Confirm Update

Ask: "Would you like to merge these updates?"
- Yes: Proceed
- No: Stop here

## Merge Strategy

The merge uses a strategy that prefers upstream for framework files:

1. **For `.claude/` directory**: Prefer upstream (Loa) versions
   - Agents get updated
   - Commands get updated
   - Local customizations may be overwritten

2. **For all other files**: Standard merge
   - Your app code preserved
   - Conflicts handled normally

```bash
git merge loa/main -m "chore: update Loa framework"
```

### Handle Conflicts

If conflicts occur:

1. List conflicted files
2. For each file in `.claude/`:
   - Recommend accepting upstream version
   - Explain: "This is a framework file. Accept Loa's version unless you have intentional customizations."

3. For conflicts in other files:
   - Display conflict markers
   - Provide guidance on resolution

4. After resolution instructions:
   - "After resolving conflicts, run: git add . && git commit"

## Post-Update

If merge successful:
- Display: "Loa updated successfully!"
- Show new commands or features (if detectable from changelog)
- Recommend: "Review CHANGELOG.md for details on what's new"
```

#### 4.4.3 Merge Strategy Details

```
Incoming from Loa upstream:
┌─────────────────────────────────────────┐
│ .claude/agents/new-agent.md     (new)   │ → Accept
│ .claude/agents/existing.md      (mod)   │ → Accept (prefer upstream)
│ .claude/commands/setup.md       (new)   │ → Accept
│ .claude/commands/existing.md    (mod)   │ → Accept (prefer upstream)
│ PROCESS.md                      (mod)   │ → Standard merge
│ README.md                       (mod)   │ → Standard merge
│ loa-grimoire/template.md        (mod)   │ → Standard merge
└─────────────────────────────────────────┘

Local repository:
┌─────────────────────────────────────────┐
│ app/                            (local) │ → Preserve
│ loa-grimoire/prd.md             (local) │ → Preserve
│ loa-grimoire/sdd.md             (local) │ → Preserve
│ loa-grimoire/analytics/         (local) │ → Preserve
│ .loa-setup-complete             (local) │ → Preserve
└─────────────────────────────────────────┘
```

### 4.5 Modified `/plan-and-analyze` Command

The existing command needs modification to enforce setup:

**Changes to `.claude/commands/plan-and-analyze.md`**:

Add at the beginning:

```markdown
## Setup Check

First, verify Loa setup is complete:

Check if `.loa-setup-complete` file exists in project root.

If NOT exists:
- Display: "Loa setup has not been completed for this project."
- Display: "Please run `/setup` first to configure your environment."
- Display: "This ensures proper MCP configuration and project initialization."
- Stop here - do not proceed with PRD creation.

If exists:
- Proceed with normal PRD creation flow.
```

---

## 5. Data Architecture

### 5.1 File-Based Storage

All data is stored in files for simplicity, portability, and git-friendliness:

| Data | Location | Format | Git Tracked |
|------|----------|--------|-------------|
| Setup completion | `.loa-setup-complete` | Empty marker | Yes |
| Analytics raw | `loa-grimoire/analytics/usage.json` | JSON | Optional* |
| Analytics summary | `loa-grimoire/analytics/summary.md` | Markdown | Optional* |
| MCP configuration | `.claude/settings.local.json` | JSON | No |

*Recommended to gitignore for privacy, but may be included for team visibility.

### 5.2 Data Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Data Flow                                       │
│                                                                             │
│  /setup ────────▶ .loa-setup-complete (marker)                              │
│          ────────▶ loa-grimoire/analytics/usage.json (initialize)           │
│          ────────▶ loa-grimoire/analytics/summary.md (generate)             │
│          ────────▶ Linear project (if configured)                           │
│          ────────▶ Branch protection (if configured)                        │
│                                                                             │
│  /plan-and-analyze ──▶ Check .loa-setup-complete                            │
│                   ──▶ Update usage.json (phase: prd)                        │
│                   ──▶ Regenerate summary.md                                 │
│                                                                             │
│  /architect ──────▶ Update usage.json (phase: sdd)                          │
│              ──────▶ Regenerate summary.md                                  │
│                                                                             │
│  /sprint-plan ────▶ Update usage.json (phase: sprint_plan)                  │
│                ────▶ Regenerate summary.md                                  │
│                                                                             │
│  /implement ──────▶ Update usage.json (sprint iterations)                   │
│              ──────▶ Regenerate summary.md                                  │
│                                                                             │
│  /review-sprint ──▶ Update usage.json (review iterations)                   │
│                 ──▶ Regenerate summary.md                                   │
│                                                                             │
│  /audit-sprint ───▶ Update usage.json (audit iterations)                    │
│                ───▶ Regenerate summary.md                                   │
│                                                                             │
│  /deploy-production ▶ Update usage.json (phase: deployment)                 │
│                    ──▶ Regenerate summary.md                                │
│                    ──▶ Suggest /feedback                                    │
│                                                                             │
│  /feedback ───────▶ Read usage.json                                         │
│            ───────▶ Post to Linear (Loa Feedback project)                   │
│            ───────▶ Update usage.json (feedback_submissions)                │
│                                                                             │
│  /update ─────────▶ Git fetch/merge from loa upstream                       │
│          ─────────▶ No analytics impact                                     │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 5.3 Schema Versioning

The `usage.json` file includes a `schema_version` field to handle future changes:

```json
{
  "schema_version": "1.0",
  ...
}
```

Migration strategy:
1. Check `schema_version` on read
2. If older version, migrate in-place
3. Update `schema_version` after migration
4. Log migration in analytics (optional)

---

## 6. API Design

### 6.1 MCP Tool Usage

#### 6.1.1 Linear MCP

**Project Creation** (in /setup):
```
mcp__linear__create_project({
  name: "{repo_name}",
  team: "THJ"
})
```

**Issue Search** (in /feedback):
```
mcp__linear__list_issues({
  project: "Loa Feedback",
  query: "[{project_name}] - Feedback"
})
```

**Issue Creation** (in /feedback):
```
mcp__linear__create_issue({
  title: "[{project_name}] - Feedback",
  project: "Loa Feedback",
  team: "THJ",
  description: "{formatted_feedback}"
})
```

**Comment Creation** (in /feedback, if issue exists):
```
mcp__linear__create_comment({
  issueId: "{existing_issue_id}",
  body: "{formatted_feedback}"
})
```

#### 6.1.2 GitHub MCP

**Branch Protection** (in /setup):
```
# Note: Branch protection via MCP may be limited
# Fall back to documentation link if not supported
```

### 6.2 Internal File APIs

All file operations use standard Claude Code tools:

| Operation | Tool |
|-----------|------|
| Read JSON/Markdown | `Read` tool |
| Write JSON/Markdown | `Write` tool |
| Check file exists | `Bash` with `test -f` |
| Create directory | `Bash` with `mkdir -p` |
| Git operations | `Bash` with git commands |

---

## 7. Security Architecture

### 7.1 Data Privacy

| Data Type | Sensitivity | Handling |
|-----------|-------------|----------|
| Developer email | Low-Medium | Stored locally, shared only via /feedback |
| Token estimates | Low | Aggregated, not detailed |
| Environment info | Low | OS/version only, no paths |
| Session timing | Low | Durations only |
| Git commits | Low | Count only, not content |

### 7.2 MCP Credentials

MCP credentials are never stored in Loa files:
- Managed by Claude Code CLI
- Stored in user's home directory
- Not accessible to Loa commands

### 7.3 Linear Data

Feedback submissions include:
- Survey responses (user-provided)
- Analytics summary (user consents by running /feedback)
- No automatic data transmission

### 7.4 Git Remote Security

The `/update` command:
- Only fetches from configured remotes
- Requires explicit confirmation before merge
- Does not auto-commit
- Preserves local branches

---

## 8. Integration Points

### 8.1 Existing Loa Integration

| Existing Component | Integration | Changes Required |
|--------------------|-------------|------------------|
| `/plan-and-analyze` | Check setup marker | Add setup check logic |
| `/architect` | Update analytics | Add phase completion tracking |
| `/sprint-plan` | Update analytics | Add phase completion tracking |
| `/implement` | Update analytics | Add iteration tracking |
| `/review-sprint` | Update analytics | Add review iteration tracking |
| `/audit-sprint` | Update analytics | Add audit iteration tracking |
| `/deploy-production` | Update analytics, suggest feedback | Add completion + suggestion |

### 8.2 MCP Integration Matrix

| MCP | /setup | /feedback | /update |
|-----|--------|-----------|---------|
| GitHub | Branch protection | - | - |
| Linear | Project creation | Issue creation/comment | - |
| Vercel | Detection only | - | - |
| Discord | Detection only | - | - |
| web3-stats | Detection only | - | - |

### 8.3 External Dependencies

| Dependency | Usage | Fallback |
|------------|-------|----------|
| Linear API | Project/issue creation | Skip with warning |
| GitHub API | Branch protection | Skip with warning |
| Git CLI | Update command | Required (fail if unavailable) |

---

## 9. Scalability & Performance

### 9.1 Performance Considerations

| Operation | Consideration | Mitigation |
|-----------|---------------|------------|
| Analytics read/write | File I/O on every phase | Non-blocking, async where possible |
| Summary generation | Markdown generation | Simple template, fast |
| MCP calls | Network latency | Timeout handling, skip on failure |
| Git operations | Disk I/O | Already fast for small repos |

### 9.2 File Size Management

| File | Expected Size | Growth |
|------|---------------|--------|
| usage.json | 5-20 KB | Linear with sprints |
| summary.md | 2-5 KB | Linear with sprints |

No size concerns expected for typical projects (10-20 sprints).

### 9.3 Non-Blocking Design

All analytics operations should be non-blocking:

```
┌──────────────────────────────────────────────────────────────────────────┐
│                        Non-Blocking Analytics                            │
│                                                                          │
│  Main Workflow                      Analytics (non-blocking)             │
│  ─────────────                      ─────────────────────────            │
│                                                                          │
│  /plan-and-analyze starts                                                │
│         │                                                                │
│         ▼                                                                │
│  PRD creation in progress ─────────▶ (deferred: update analytics)       │
│         │                                                                │
│         ▼                                                                │
│  PRD saved to prd.md                                                     │
│         │                                                                │
│         ▼                                                                │
│  Display completion ───────────────▶ Update usage.json (async)          │
│         │                           │                                    │
│         │                           ▼                                    │
│  User sees success             Regenerate summary.md                     │
│                                     │                                    │
│                                     ▼                                    │
│                               (If failure, log and continue)             │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## 10. Deployment Architecture

### 10.1 Distribution Model

Loa is distributed as a git repository template:

```
Developer                         Loa Repository
    │                                   │
    │  git clone / Use as template      │
    ◄───────────────────────────────────┤
    │                                   │
    │  git remote add loa               │
    ├───────────────────────────────────►
    │                                   │
    │  /update (git pull from loa)      │
    ◄───────────────────────────────────┤
    │                                   │
```

### 10.2 Version Management

| Component | Versioning | Update Mechanism |
|-----------|------------|------------------|
| Agents | In-file comments | `/update` command |
| Commands | In-file comments | `/update` command |
| Schemas | `schema_version` field | Migration on read |
| Documentation | CHANGELOG.md | `/update` command |

### 10.3 Backwards Compatibility

| Change Type | Handling |
|-------------|----------|
| New command added | No impact on existing projects |
| Command modified | `/update` pulls new version |
| Schema field added | Defaults applied on read |
| Schema field removed | Ignored on read |
| Schema structure change | Migration function |

---

## 11. Development Workflow

### 11.1 Adding to Loa Repository

New commands follow this structure:

1. Create command file in `.claude/commands/`
2. Optionally create agent in `.claude/agents/`
3. Update CLAUDE.md with command documentation
4. Update PROCESS.md with workflow integration
5. Update README.md with quick reference
6. Add CHANGELOG.md entry

### 11.2 Testing Strategy

| Component | Test Approach |
|-----------|---------------|
| Commands | Manual testing in Claude Code |
| Analytics | Verify JSON schema, file creation |
| MCP integration | Test with configured MCPs |
| Update command | Test merge scenarios |

### 11.3 Git Strategy for Loa Development

```
main ─────────────────────────────────────────────────────►
       │                    │
       │ feature branch     │ feature branch
       ▼                    ▼
   feat/setup           feat/feedback
       │                    │
       │ PR + Review        │ PR + Review
       ▼                    ▼
   merge to main        merge to main
```

---

## 12. Technical Risks & Mitigation

### 12.1 Risk Matrix

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| MCP auth failures during setup | Medium | Medium | Save progress, allow skip, provide docs |
| Token estimation inaccuracy | High | Low | Clearly mark as "estimated" |
| Analytics file corruption | Low | Medium | Schema validation, backup before write |
| Merge conflicts on update | Medium | Medium | Clear guidance, prefer upstream for framework files |
| Linear "Loa Feedback" project missing | Low | Medium | Clear error message, documentation |
| Setup marker deleted accidentally | Low | Low | Easy to re-run /setup |

### 12.2 Mitigation Details

**MCP Auth Failures**:
- Log failure to `setup_failures` array
- Offer retry, docs link, or skip
- Never block setup completion entirely

**Token Estimation Inaccuracy**:
- Display "estimated" label in UI
- Document estimation methodology
- Focus on trends, not absolute values

**Analytics File Corruption**:
- Validate JSON before write
- Create backup on read (optional)
- Graceful handling of parse errors

**Merge Conflicts**:
- Detect conflicts before completing
- Provide file-by-file guidance
- Recommend accepting upstream for `.claude/`

---

## 13. Future Considerations

### 13.1 Potential Enhancements (Out of Scope)

| Enhancement | Value | Complexity |
|-------------|-------|------------|
| Analytics dashboard | High | High (requires web UI) |
| Automatic update checks | Medium | Medium (background process) |
| Team analytics aggregation | High | High (requires server) |
| Custom MCP support | Medium | Medium |
| Analytics opt-in/opt-out UI | Low | Low |

### 13.2 Schema Evolution Path

Future `usage.json` versions might include:
- Per-agent token tracking
- Detailed file change tracking
- Team member contributions
- Cost estimates

Migration path:
1. Increment `schema_version`
2. Add migration function
3. Apply on read if version mismatch

### 13.3 Integration Expansion

Potential future integrations:
- Slack for feedback
- Notion for documentation
- Custom webhooks for analytics

---

## 14. Implementation Checklist

### 14.1 New Files to Create

- [ ] `.claude/commands/setup.md`
- [ ] `.claude/commands/feedback.md`
- [ ] `.claude/commands/update.md`

### 14.2 Existing Files to Modify

- [ ] `.claude/commands/plan-and-analyze.md` - Add setup check
- [ ] `CLAUDE.md` - Document new commands
- [ ] `PROCESS.md` - Add new command workflows
- [ ] `README.md` - Add quick reference
- [ ] `.gitignore` - Consider analytics files

### 14.3 Infrastructure Setup

- [ ] Create "Loa Feedback" project in Linear (THJ workspace)
- [ ] Document project ID for reference

### 14.4 Documentation Updates

- [ ] CHANGELOG.md entry for this release
- [ ] MCP setup documentation links
- [ ] Analytics schema documentation

---

## Appendix A: Environment Detection Commands

```bash
# OS and version
uname -s                    # darwin, linux
uname -r                    # kernel version
sw_vers -productVersion     # macOS version (macOS only)
cat /etc/os-release         # Linux distro info (Linux only)

# Shell
echo $SHELL

# CPU
sysctl -n machdep.cpu.brand_string  # macOS
cat /proc/cpuinfo | grep "model name" | head -1  # Linux
nproc                       # CPU cores

# RAM
sysctl -n hw.memsize        # macOS (bytes)
free -b | grep Mem | awk '{print $2}'  # Linux (bytes)

# Architecture
uname -m                    # arm64, x86_64

# Claude Code version
claude --version            # If available

# Node version
node --version

# Git user info
git config user.name
git config user.email

# Git repo info
git remote get-url origin
basename $(git rev-parse --show-toplevel)
```

---

## Appendix B: Linear API Reference

### Create Project

```
mcp__linear__create_project
  name: string (required)
  team: string (required) - Team name or ID
  description: string (optional)
  state: string (optional)
```

### Search Issues

```
mcp__linear__list_issues
  project: string (optional) - Project name or ID
  query: string (optional) - Search in title/description
  state: string (optional)
  limit: number (optional, default 50)
```

### Create Issue

```
mcp__linear__create_issue
  title: string (required)
  team: string (required)
  project: string (optional)
  description: string (optional)
  labels: string[] (optional)
```

### Create Comment

```
mcp__linear__create_comment
  issueId: string (required)
  body: string (required) - Markdown content
```

---

## Appendix C: Error Messages

### Setup Errors

| Error | Message |
|-------|---------|
| No git repo | "This directory is not a git repository. Please initialize git first." |
| No git remote | "No git remote found. Please add a remote or enter the project name manually." |
| MCP auth failed | "[MCP] authentication failed. You can retry, skip this MCP, or configure manually." |
| Linear project exists | "A Linear project with this name already exists. Using existing project." |
| Analytics dir creation failed | "Failed to create analytics directory. Please check permissions." |

### Feedback Errors

| Error | Message |
|-------|---------|
| Linear MCP not configured | "Linear MCP is not configured. Feedback cannot be submitted. Please configure Linear and try again." |
| Loa Feedback project not found | "The 'Loa Feedback' project was not found in Linear. Please ensure it exists in the THJ workspace." |
| Analytics not found | "Analytics file not found. Feedback will be submitted without analytics data." |
| Issue creation failed | "Failed to create Linear issue. Your responses have been saved locally." |

### Update Errors

| Error | Message |
|-------|---------|
| Uncommitted changes | "Your working tree has uncommitted changes. Please commit or stash before updating." |
| No upstream remote | "The Loa upstream remote is not configured. Run: git remote add loa https://github.com/0xHoneyJar/loa.git" |
| Merge conflict | "Merge conflict detected. Please resolve conflicts manually and commit." |
| Already up to date | "You're already up to date with the latest Loa version." |

---

*Document generated by architecture-designer agent. Last updated: 2025-12-19*
