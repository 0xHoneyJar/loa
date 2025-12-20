# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an agent-driven development framework that orchestrates a complete product development lifecycle—from requirements gathering through production deployment—using specialized AI agents. The framework is designed for building crypto/blockchain projects but applicable to any software project.

## Architecture

### Agent System

The framework uses eight specialized agents that work together in a structured workflow:

1. **prd-architect** (Product Manager) - Requirements discovery and PRD creation
2. **architecture-designer** (Software Architect) - System design and SDD creation
3. **sprint-planner** (Technical PM) - Sprint planning and task breakdown
4. **sprint-task-implementer** (Senior Engineer) - Implementation with feedback loops
5. **senior-tech-lead-reviewer** (Senior Technical Lead) - Code review and quality gates
6. **devops-crypto-architect** (DevOps Architect) - Production deployment and infrastructure
7. **paranoid-auditor** (Security Auditor) - Comprehensive security and quality audits
8. **devrel-translator** (Developer Relations) - Translates technical work into executive-ready communications

Agents are defined in `.claude/agents/` and invoked via custom slash commands in `.claude/commands/`.

### Document Flow

The workflow produces structured artifacts in the `loa-grimoire/` directory:

- `loa-grimoire/prd.md` - Product Requirements Document
- `loa-grimoire/sdd.md` - Software Design Document
- `loa-grimoire/sprint.md` - Sprint plan with tasks and acceptance criteria
- `loa-grimoire/a2a/index.md` - Sprint audit trail index (auto-maintained)
- `loa-grimoire/a2a/sprint-N/` - Sprint-specific A2A communication (preserves audit trail)
  - `reviewer.md` - Implementation report from engineer
  - `engineer-feedback.md` - Review feedback from senior technical lead
  - `auditor-sprint-feedback.md` - Security audit feedback
  - `COMPLETED` - Completion marker (created by audit-sprint on approval)
- `loa-grimoire/a2a/deployment-report.md` - Infrastructure reports from DevOps
- `loa-grimoire/a2a/deployment-feedback.md` - Security audit feedback for deployment infrastructure
- `loa-grimoire/deployment/` - Production infrastructure documentation and runbooks

### Agent-to-Agent (A2A) Communication

The framework uses three feedback loops for quality assurance:

#### Implementation Feedback Loop (Phases 4-5)
- Engineer writes implementation report to `loa-grimoire/a2a/sprint-N/reviewer.md`
- Senior lead writes feedback to `loa-grimoire/a2a/sprint-N/engineer-feedback.md`
- Engineer reads feedback on next invocation, fixes issues, and updates report
- Cycle continues until senior lead approves with "All good"

#### Sprint Security Audit Feedback Loop (Phase 5.5)
- After senior lead approval, security auditor reviews sprint implementation
- Auditor writes feedback to `loa-grimoire/a2a/sprint-N/auditor-sprint-feedback.md`
- Verdict: "CHANGES_REQUIRED" (with security issues) or "APPROVED - LETS FUCKING GO"
- If changes required:
  - Engineer reads audit feedback on next `/implement sprint-N` invocation (checked FIRST)
  - Engineer addresses all CRITICAL and HIGH security issues
  - Engineer updates report with "Security Audit Feedback Addressed" section
  - Re-run `/audit-sprint sprint-N` to verify fixes
- Cycle continues until auditor approves
- On approval: Creates `loa-grimoire/a2a/sprint-N/COMPLETED` marker file
- After approval, move to next sprint or deployment

#### Deployment Feedback Loop
- DevOps creates infrastructure and writes report to `loa-grimoire/a2a/deployment-report.md`
- Auditor reviews via `/audit-deployment` and writes feedback to `loa-grimoire/a2a/deployment-feedback.md`
- DevOps addresses feedback, updates infrastructure, and regenerates report
- Cycle continues until auditor approves with "APPROVED - LET'S FUCKING GO"

## Development Workflow Commands

### Execution Modes

All slash commands run in **foreground mode by default**, allowing direct interaction with the agent. To run in background mode (for parallel execution), append `background` to the command:

```bash
# Foreground (default) - interactive, agent responds directly
/implement sprint-1

# Background - agent runs as subagent, use /tasks to monitor
/implement sprint-1 background
```

**When to use each mode:**
- **Foreground (default)**: Interactive sessions, when you want to guide the agent, single-task workflows
- **Background**: Running multiple agents in parallel, long-running tasks, automated pipelines

### Phase 0: Setup (First-Time Only)
```bash
/setup
```
Guides new developers through initial Loa configuration with **two distinct pathways**:

**THJ Developers** (internal team):
- Full analytics tracking for framework improvement
- MCP server configuration (Linear, GitHub, Vercel, Discord, web3-stats)
- Access to `/config` (reconfigure MCP) and `/feedback` (submit feedback to Linear)
- Creates `loa-grimoire/analytics/usage.json` with initial data

**OSS Users** (open source community):
- Streamlined welcome experience with documentation pointers
- No analytics tracking (privacy-first)
- No MCP configuration prompts
- Full access to core workflow commands

The command:
1. Asks "Are you a THJ team member?" to determine pathway
2. Displays appropriate welcome message
3. For THJ: Shows analytics notice, initializes analytics, offers MCP multichoice setup
4. For OSS: Points to documentation and community resources
5. Creates `.loa-setup-complete` marker file with `user_type` field
6. Displays next steps

**Setup is required before `/plan-and-analyze`**. If the marker file is missing, you'll be prompted to run `/setup` first.

### Post-Setup: MCP Configuration (THJ Only)
```bash
/config
```
Allows THJ developers to reconfigure MCP server integrations after initial setup. The command:
- Verifies user is THJ (checks `user_type` in `.loa-setup-complete`)
- Shows currently configured MCP servers
- Offers multichoice selection: Linear, GitHub, Vercel, Discord, web3-stats, All, Skip
- Provides guided setup or documentation links for selected servers
- Updates `.loa-setup-complete` with new MCP configuration

**Note**: This command is only available to THJ developers. OSS users will see an error directing them to manual MCP configuration.

### Phase 1: Requirements
```bash
/plan-and-analyze
```
Launches `prd-architect` agent for structured discovery across 7 phases. Agent asks 2-3 questions at a time to extract complete requirements. Outputs `loa-grimoire/prd.md`.

### Phase 2: Architecture
```bash
/architect
```
Launches `architecture-designer` agent to review PRD and design system architecture. Agent presents proposals for uncertain decisions with pros/cons. Outputs `loa-grimoire/sdd.md`.

### Phase 3: Sprint Planning
```bash
/sprint-plan
```
Launches `sprint-planner` agent to break down work into actionable sprint tasks with acceptance criteria, dependencies, and assignments. Outputs `loa-grimoire/sprint.md`.

### Phase 4: Implementation
```bash
/implement sprint-1
```
Launches `sprint-task-implementer` agent to execute sprint tasks. The agent:
- Creates `loa-grimoire/a2a/sprint-1/` directory if it doesn't exist
- Checks for existing feedback files (audit feedback checked FIRST, then engineer feedback)
- Implements tasks and generates report at `loa-grimoire/a2a/sprint-1/reviewer.md`
- Updates `loa-grimoire/a2a/index.md` with sprint status

On subsequent runs, reads `loa-grimoire/a2a/sprint-1/engineer-feedback.md`, addresses feedback, and regenerates report.

### Phase 5: Review
```bash
/review-sprint sprint-1
```
Launches `senior-tech-lead-reviewer` agent to validate implementation against acceptance criteria. The agent:
- Validates sprint directory exists and contains `reviewer.md`
- Reviews actual code, not just the report
- Either approves (writes "All good" to `loa-grimoire/a2a/sprint-1/engineer-feedback.md`, updates sprint.md with ✅)
- Or requests changes (writes detailed feedback to `loa-grimoire/a2a/sprint-1/engineer-feedback.md`)
- Updates `loa-grimoire/a2a/index.md` with review status

### Phase 5.5: Sprint Security Audit
```bash
/audit-sprint sprint-1
```
Launches `paranoid-auditor` agent to perform security and quality audit of sprint implementation. Run this AFTER `/review-sprint` approval. The agent:
- Validates sprint directory and senior lead approval ("All good" in engineer-feedback.md)
- Reviews implementation for security vulnerabilities (OWASP Top 10, injection, auth issues)
- Audits secrets management and credential handling
- Checks input validation and sanitization
- Verifies error handling and information disclosure
- Writes feedback to `loa-grimoire/a2a/sprint-1/auditor-sprint-feedback.md`
- Verdict: **CHANGES_REQUIRED** or **APPROVED - LETS FUCKING GO**
- On approval: Creates `loa-grimoire/a2a/sprint-1/COMPLETED` marker file
- Updates `loa-grimoire/a2a/index.md` with audit status

**Feedback loop**:
```
/implement sprint-1 → /review-sprint sprint-1 → /audit-sprint sprint-1 → (if changes) → back to /implement sprint-1
                                                        ↓
                                               (if approved: LETS FUCKING GO)
                                                        ↓
                                               Creates COMPLETED marker
                                                        ↓
                                               Move to sprint-2
```

If audit finds issues:
1. Auditor writes "CHANGES_REQUIRED" with detailed security feedback
2. Run `/implement sprint-1` to address audit feedback
3. Engineer fixes issues and updates report
4. Re-run `/audit-sprint sprint-1` to verify fixes
5. Repeat until approved

**Use this proactively**:
- After every sprint review approval
- Before moving to next sprint
- Before production deployment
- After implementing security-sensitive features

### Phase 6: Deployment
```bash
/deploy-production
```
Launches `devops-crypto-architect` agent to design and deploy production infrastructure. Creates IaC, CI/CD pipelines, monitoring, and comprehensive operational documentation in `loa-grimoire/deployment/`.

### Post-Deployment: Developer Feedback (THJ Only)
```bash
/feedback
```
Collects developer feedback on the Loa experience and posts to Linear. **This command is only available to THJ developers.**

The command:
- Verifies user is THJ (checks `user_type` in `.loa-setup-complete`)
- Checks for pending feedback from previous failed submissions
- Runs a 4-question survey with progress indicators:
  1. What would you change about Loa? (free text)
  2. What did you love about using Loa? (free text)
  3. Rate this build vs other approaches (1-5 scale)
  4. How comfortable are you with the process? (A-E multiple choice)
- Loads analytics from `loa-grimoire/analytics/usage.json`
- Searches for existing feedback issue in "Loa Feedback" Linear project
- Creates new issue or adds comment to existing one
- Includes full analytics in collapsible details block
- Records submission in analytics `feedback_submissions` array

**Error handling**: If Linear submission fails, feedback is saved to `loa-grimoire/analytics/pending-feedback.json` and can be retried on next `/feedback` run.

**OSS users**: For issues or feature requests, please open a GitHub issue at https://github.com/0xHoneyJar/loa/issues

### Maintenance: Framework Updates
```bash
/update
```
Pulls the latest Loa framework updates from the upstream repository. The command:
- **Pre-flight checks**:
  - Verifies working tree is clean (no uncommitted changes)
  - Checks for `loa` or `upstream` remote
- **Fetch and preview**:
  - Fetches from `loa main`
  - Shows list of new commits and files that will change
- **Confirmation**:
  - Asks for confirmation before merging
  - Notes which files will be updated vs preserved
- **Merge with guidance**:
  - Performs standard `git merge loa/main`
  - If conflicts occur, provides resolution guidance:
    - `.claude/` files: recommend accepting upstream
    - Other files: manual resolution steps
- **Post-merge**:
  - Shows CHANGELOG.md excerpt
  - Suggests reviewing new features

### Ad-Hoc: Deployment Infrastructure Audit
```bash
/audit-deployment
```
Launches `paranoid-auditor` agent to review deployment infrastructure. Use this to audit:
- Server setup scripts for security vulnerabilities
- Deployment configurations and procedures
- Infrastructure security hardening (SSH, firewall, fail2ban)
- Secrets management and credential handling
- PM2/systemd/nginx configurations
- Backup and disaster recovery procedures

The agent:
- Reads `loa-grimoire/a2a/deployment-report.md` for context (if exists)
- Audits all scripts, configs, and documentation in `loa-grimoire/deployment/`
- Writes feedback to `loa-grimoire/a2a/deployment-feedback.md`
- Verdict: **CHANGES_REQUIRED** or **APPROVED - LET'S FUCKING GO**

### Ad-Hoc: Security Audit (Codebase)
```bash
/audit
```
Launches `paranoid-auditor` agent to perform comprehensive security and quality audit of the codebase. Use this proactively:
- Before production deployment
- After major code changes or new integrations
- When implementing security-sensitive features (auth, payments, data handling)
- Periodically for ongoing projects

The agent performs:
- OWASP Top 10 vulnerability assessment
- Cryptographic implementation review
- Secrets and credential management audit
- Input validation and sanitization review
- Authentication and authorization analysis
- Data privacy and PII handling review
- Infrastructure security assessment
- Dependency and supply chain analysis

Outputs `SECURITY-AUDIT-REPORT.md` with prioritized findings (CRITICAL/HIGH/MEDIUM/LOW) and actionable remediation guidance.

### Ad-Hoc: Executive Translation
```bash
/translate @document.md for [audience]
```
Launches `devrel-translator` agent to translate technical documentation into executive-ready communications. Use this to:
- Create executive summaries from technical docs (PRD, SDD, audit reports, sprint updates)
- Prepare board presentations and investor updates
- Brief non-technical stakeholders on technical progress
- Explain architecture decisions to business stakeholders
- Translate security audits into risk assessments for executives

**Example invocations**:
```bash
/translate @SECURITY-AUDIT-REPORT.md for board of directors
/translate @loa-grimoire/sdd.md for executives
/translate @loa-grimoire/sprint.md for investors
/translate @loa-grimoire/audits/2025-12-08/FINAL-AUDIT-REMEDIATION-REPORT.md for CEO
```

The agent creates:
- **Executive summaries** (1-2 pages, plain language, business-focused)
- **Stakeholder briefings** (tailored by audience: execs, board, investors, product, compliance)
- **Visual communication** (diagram suggestions, flowcharts, risk matrices)
- **FAQs** (anticipating stakeholder questions)
- **Risk assessments** (honest, transparent, actionable)

The agent focuses on:
- **Business value** over technical details
- **Clear analogies** for complex concepts
- **Specific metrics** and quantified impact
- **Honest risk** communication
- **Actionable next steps** with decision points

### Ad-Hoc: OSS Contribution
```bash
/contribute
```
Guides intentional contributions back to the Loa framework. This command bypasses normal Git Safety warnings because it includes its own comprehensive safeguards:

**Phase 1 - Pre-flight Checks**:
- Verifies you're on a feature branch (not main/master)
- Checks working tree is clean (no uncommitted changes)
- Confirms upstream remote is configured (loa or upstream pointing to 0xHoneyJar/loa)

**Phase 2 - Standards Checklist**:
- Interactive confirmation of clean commit history
- No sensitive data in commits
- Tests passing (if applicable)
- DCO sign-off present

**Phase 3 - Automated Checks**:
- Secrets scanning (API keys, tokens, private keys, passwords)
- DCO sign-off verification
- Soft blocking with user acknowledgment

**Phase 4 - PR Creation**:
- Prompts for PR title and description
- Creates PR to `0xHoneyJar/loa:main` via GitHub MCP or `gh` CLI
- Includes OSS checklist and Claude Code attribution

**Note**: This is the only command authorized to create PRs to upstream without triggering Git Safety warnings.

## Key Architectural Patterns

### Feedback-Driven Implementation

Implementation uses an iterative cycle:
1. Engineer implements → generates report
2. Senior lead reviews → provides feedback or approval
3. If feedback: engineer addresses issues → generates updated report
4. Repeat until approved

This ensures quality without blocking progress.

### Stateless Agent Invocations

Each agent invocation is stateless. Context is maintained through:
- Document artifacts in `loa-grimoire/`
- A2A communication files in `loa-grimoire/a2a/`
- Explicit reading of previous outputs

### Proactive Agent Invocation

Claude Code will automatically suggest relevant agents when:
- User describes a product idea → `prd-architect`
- User mentions architecture decisions → `architecture-designer`
- User wants to break down work → `sprint-planner`
- User mentions infrastructure/deployment → `devops-crypto-architect`

## MCP Server Integrations

The framework has pre-configured MCP servers for common tools:

- **linear** - Issue tracking for developer feedback (`/feedback` command only)
- **github** - Repository operations, PRs, issues
- **vercel** - Deployment and hosting
- **discord** - Community/team communication
- **web3-stats** - Blockchain data (Dune API, Blockscout)

These are enabled in `.claude/settings.local.json` and available for agents to use.

## Important Conventions

### Analytics Helper Functions

The analytics system uses bash commands for environment detection and data collection. These commands are designed to work across platforms and fail gracefully.

#### Environment Detection Commands

```bash
# Get framework version from package.json or CHANGELOG.md
get_framework_version() {
    if [ -f "package.json" ]; then
        grep -o '"version": *"[^"]*"' package.json | head -1 | cut -d'"' -f4
    elif [ -f "CHANGELOG.md" ]; then
        grep -o '\[[0-9]\+\.[0-9]\+\.[0-9]\+\]' CHANGELOG.md | head -1 | tr -d '[]'
    else
        echo "0.0.0"
    fi
}

# Get git user identity
get_git_user() {
    local name=$(git config user.name 2>/dev/null || echo "Unknown")
    local email=$(git config user.email 2>/dev/null || echo "unknown@unknown")
    echo "${name}|${email}"
}

# Get project name from git remote or directory
get_project_name() {
    local remote=$(git remote get-url origin 2>/dev/null)
    if [ -n "$remote" ]; then
        basename -s .git "$remote"
    else
        basename "$(pwd)"
    fi
}

# Get current timestamp in ISO-8601 format
get_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}
```

#### MCP Server Detection

```bash
# Check which MCP servers are configured
get_configured_mcp_servers() {
    local settings=".claude/settings.local.json"
    if [ -f "$settings" ]; then
        # Extract server names from enabledMcpjsonServers array
        grep -o '"[^"]*"' "$settings" | grep -v "enabledMcpjsonServers" | tr -d '"' | tr '\n' ','
    else
        echo "none"
    fi
}

# Validate MCP server connectivity (returns 0 if responsive)
test_mcp_server() {
    local server="$1"
    case "$server" in
        linear)
            # Test Linear by listing teams
            mcp__linear__list_teams 2>/dev/null && return 0
            ;;
        github)
            # Test GitHub by searching for a known repo
            mcp__github__search_repositories query="test" 2>/dev/null && return 0
            ;;
        *)
            return 1
            ;;
    esac
    return 1
}
```

#### Analytics File Operations

```bash
# Initialize analytics file if missing
init_analytics() {
    local analytics_file="loa-grimoire/analytics/usage.json"
    local analytics_dir="loa-grimoire/analytics"

    mkdir -p "$analytics_dir"

    if [ ! -f "$analytics_file" ]; then
        cat > "$analytics_file" << 'EOF'
{
  "schema_version": "1.0.0",
  "framework_version": null,
  "project_name": null,
  "developer": {"git_user_name": null, "git_user_email": null},
  "setup": {"completed_at": null, "mcp_servers_configured": []},
  "phases": {},
  "sprints": [],
  "reviews": [],
  "audits": [],
  "deployments": [],
  "totals": {"commands_executed": 0, "phases_completed": 0}
}
EOF
    fi
}

# Update a field in the analytics JSON (requires jq)
update_analytics_field() {
    local field="$1"
    local value="$2"
    local file="loa-grimoire/analytics/usage.json"

    if command -v jq &>/dev/null; then
        local tmp=$(mktemp)
        jq "$field = $value" "$file" > "$tmp" && mv "$tmp" "$file"
    fi
}
```

### Setup Marker File Convention

The framework uses a marker file `.loa-setup-complete` to detect first-launch vs returning users and determine user type:

**File Location**: Repository root (`.loa-setup-complete`)

**Detection Logic**:
```bash
# Check if setup has been completed
if [ -f ".loa-setup-complete" ]; then
    echo "Setup complete - returning user"
else
    echo "First launch - needs setup"
fi

# Check user type for feature gating
USER_TYPE=$(cat .loa-setup-complete 2>/dev/null | grep -o '"user_type": *"[^"]*"' | cut -d'"' -f4)
if [ "$USER_TYPE" = "thj" ]; then
    echo "THJ developer - full features"
else
    echo "OSS user - core features only"
fi
```

**File Contents** (JSON):
```json
{
  "completed_at": "2025-01-15T10:30:00Z",
  "framework_version": "0.2.0",
  "user_type": "thj",
  "mcp_servers": ["linear", "github"],
  "git_user": "developer@example.com",
  "template_source": {
    "detected": true,
    "repo": "0xHoneyJar/loa",
    "detection_method": "origin_url",
    "detected_at": "2025-01-15T10:30:00Z"
  }
}
```

**User Types**:
- `"thj"` - THJ team member with full analytics, MCP config, and feedback access
- `"oss"` - Open source user with streamlined experience, no analytics

**Template Source Detection**:
- `detected` - Whether the repo is a fork/template of a known Loa source
- `repo` - The detected upstream repository (e.g., `0xHoneyJar/loa`) or `null`
- `detection_method` - How the template was detected: `origin_url`, `upstream_remote`, `loa_remote`, `github_api`, or `none`
- `detected_at` - ISO-8601 timestamp of detection

When `template_source.detected` is `true`, git safety features are enabled to warn before push/PR operations targeting upstream.

**Behavior**:
- `/plan-and-analyze` checks for this file and prompts `/setup` if missing
- `/setup` creates this file upon successful completion with template detection results
- `/config` and `/feedback` check `user_type` and restrict to THJ only
- All phase commands check `user_type` to skip analytics for OSS users
- Git Safety Protocol checks `template_source` before push/PR operations
- File is gitignored (each developer runs setup independently)
- Contains minimal metadata for analytics correlation

### Analytics System

The framework automatically tracks usage metrics to help improve Loa and provide context for feedback submissions. **Analytics are only enabled for THJ developers.**

#### User Type Behavior

| User Type | Analytics | `/feedback` | `/config` |
|-----------|-----------|-------------|-----------|
| **THJ** | Full tracking | Available | Available |
| **OSS** | None (skipped) | Unavailable | Unavailable |

#### What's Tracked (THJ Only)

| Category | Metrics |
|----------|---------|
| **Environment** | Framework version, project name, developer (git user) |
| **Setup** | Completion timestamp, configured MCP servers |
| **Phases** | Start/completion timestamps for PRD, SDD, sprint planning, deployment |
| **Sprints** | Sprint number, start/end times, review iterations, audit iterations |
| **Feedback** | Submission timestamps, Linear issue IDs |

#### Files

- `loa-grimoire/analytics/usage.json` - Raw usage data (JSON) - **THJ only**
- `loa-grimoire/analytics/summary.md` - Human-readable summary (regenerated after updates) - **THJ only**
- `loa-grimoire/analytics/pending-feedback.json` - Pending feedback (only if submission failed) - **THJ only**

#### How It Works

1. **Initialization**: `/setup` creates `usage.json` with environment info (THJ only)
2. **Phase tracking**: Each phase command checks `user_type` first, skips analytics for OSS users
3. **Non-blocking**: Analytics failures are logged but don't stop workflows
4. **Opt-in sharing**: Analytics stay local; only shared via `/feedback` if you choose

#### Updating Analytics (THJ Only)

Each phase command follows this pattern:
1. Check `user_type` in `.loa-setup-complete`
2. If OSS: Skip analytics entirely, continue with main workflow
3. If THJ: Check if `usage.json` exists (create if missing)
4. Update relevant phase/sprint data
5. Regenerate `summary.md`
6. Continue with main workflow

### Document Structure

All planning documents live in `loa-grimoire/`:
- Primary docs: `prd.md`, `sdd.md`, `sprint.md`
- A2A communication: `loa-grimoire/a2a/`
- Deployment docs: `loa-grimoire/deployment/`
- Analytics: `loa-grimoire/analytics/`

**Note**: This is a base framework repository. When using as a template for a new project, uncomment the generated artifacts section in `.gitignore` to avoid committing generated documentation (prd.md, sdd.md, sprint.md, a2a/, deployment/, analytics/).

## Git Safety Protocol

When working in repositories that may be forks or templates of the Loa framework, Claude Code follows this protocol to prevent accidental pushes to upstream. This is a **soft block** - users can always proceed after explicit confirmation.

### Known Template Repositories

The following are known Loa template sources:
- `github.com/0xHoneyJar/loa`
- `github.com/thj-dev/loa`

### Warning Message Templates

When a template repository is detected, display this warning with filled placeholders:

```
⚠️  UPSTREAM TEMPLATE DETECTED

You appear to be pushing to the Loa template repository.

┌─────────────────────────────────────────────────────────────────┐
│  Detection Method: {DETECTION_METHOD}                           │
│  Target Remote:    {REMOTE_NAME} → {REMOTE_URL}                 │
│  Operation:        {OPERATION_TYPE}                             │
└─────────────────────────────────────────────────────────────────┘

⚠️  CONSEQUENCES OF PROCEEDING:
• Your code will be pushed to the PUBLIC Loa repository
• Your commits (including author info) will be visible publicly
• This may expose proprietary code, API keys, or personal data
• An unintentional PR may clutter the upstream project

Choose an option:
  1. [Proceed anyway]     - I understand the risks and want to continue
  2. [Cancel]             - Stop this operation
  3. [Fix my remotes]     - Show me how to fix my git configuration
```

**Placeholder Values**:
- `{DETECTION_METHOD}`: One of "Cached from setup", "Origin URL match", "Upstream remote match", "GitHub API fork check"
- `{REMOTE_NAME}`: The remote name (e.g., "origin", "upstream")
- `{REMOTE_URL}`: The full URL (e.g., "git@github.com:0xHoneyJar/loa.git")
- `{OPERATION_TYPE}`: The operation (e.g., "git push origin main", "Create PR to 0xHoneyJar/loa")

### Step-by-Step Detection Procedure

Before executing ANY `git push`, `gh pr create`, or GitHub MCP PR creation, follow this procedure:

```
START Detection Procedure
│
├─► Step 1: Identify target remote
│   Run: git remote -v
│   Extract the URL for the remote being pushed to
│
├─► Step 2: Check against known templates
│   Does URL contain "(0xHoneyJar|thj-dev)/loa"?
│   ├── YES → Template detected, proceed to Warning
│   └── NO  → Safe to proceed, skip to Step 6
│
├─► Step 3: Display warning message (see template above)
│   Fill all placeholders with actual values
│   NEVER proceed without showing this warning
│
├─► Step 4: Wait for user response (MANDATORY)
│   Use AskUserQuestion tool
│   DO NOT auto-proceed under any circumstances
│
├─► Step 5: Handle user response
│   ├── "Proceed anyway" → Execute operation with single confirmation
│   ├── "Cancel"         → Stop, do nothing further
│   └── "Fix remotes"    → Display remediation steps, then stop
│
└─► Step 6: Execute or stop based on user choice
    END Detection Procedure
```

**Decision Logic**:
- Cache-first: Check `.loa-setup-complete` before running bash commands
- Fallback chain: If Layer N fails, try Layer N+1
- Offline mode: Layers 1-3 work without network; Layer 4 requires `gh` CLI
- Error handling: All commands use `2>/dev/null` for graceful failures

### Template Detection Layers

Detection uses a 4-layer approach with fallback behavior:

**Layer 1: Cached Detection (Fastest, < 100ms)**
```bash
# Check .loa-setup-complete for cached template_source
if [ -f ".loa-setup-complete" ]; then
    CACHED=$(cat .loa-setup-complete 2>/dev/null | grep -o '"detected": *true')
    if [ -n "$CACHED" ]; then
        DETECTION_METHOD="Cached from setup"
        # Use cached result - template was detected during /setup
    fi
fi
```
**When to use**: Always check first. If `template_source.detected` is `true`, use this result.
**Fallback**: If file missing, corrupted, or no `template_source` field, proceed to Layer 2.

**Layer 2: Origin URL Check (Local, Fast, < 1s)**
```bash
ORIGIN_URL=$(git remote get-url origin 2>/dev/null)
if echo "$ORIGIN_URL" | grep -qE "(0xHoneyJar|thj-dev)/loa"; then
    DETECTION_METHOD="Origin URL match"
    IS_TEMPLATE="true"
fi
```
**When to use**: When cache miss or verifying cache.
**Fallback**: If origin doesn't match but you suspect a template, proceed to Layer 3.

**Layer 3: Upstream Remote Check (Local, Fast, < 1s)**
```bash
if git remote -v | grep -E "^(upstream|loa)\s" | grep -qE "(0xHoneyJar|thj-dev)/loa"; then
    DETECTION_METHOD="Upstream remote match"
    IS_TEMPLATE="true"
fi
```
**When to use**: Catches forks where origin is user's repo but upstream points to template.
**Fallback**: If still uncertain, proceed to Layer 4 for authoritative check.

**Layer 4: GitHub API Check (Network, Authoritative, < 3s)**
```bash
if command -v gh &>/dev/null; then
    PARENT=$(gh repo view --json parent -q '.parent.nameWithOwner' 2>/dev/null)
    if echo "$PARENT" | grep -qE "(0xHoneyJar|thj-dev)/loa"; then
        DETECTION_METHOD="GitHub API fork check"
        IS_TEMPLATE="true"
    fi
else
    echo "Note: gh CLI not available, using local detection only"
fi
```
**When to use**: When local detection is inconclusive, or for authoritative verification.
**Fallback**: If `gh` unavailable or API fails, rely on Layers 1-3 results.

**Timeout/Error Handling**:
- All commands include `2>/dev/null` to suppress errors
- Layer 4 is skipped if `gh` CLI is not installed
- Network failures in Layer 4 fall back to local detection
- Missing `.loa-setup-complete` does NOT disable safety checks

### Remediation Steps

When user selects "Fix my remotes", display these comprehensive instructions:

```
📋 GIT REMOTE CONFIGURATION GUIDE

First, let's see your current setup:

  $ git remote -v

┌─────────────────────────────────────────────────────────────────┐
│ COMMON MISTAKE: Origin pointing to upstream template            │
├─────────────────────────────────────────────────────────────────┤
│ BEFORE (problematic):                                           │
│   origin    git@github.com:0xHoneyJar/loa.git (fetch)          │
│   origin    git@github.com:0xHoneyJar/loa.git (push)           │
│                                                                 │
│ AFTER (correct):                                                │
│   origin    git@github.com:YOUR_ORG/YOUR_PROJECT.git (fetch)   │
│   origin    git@github.com:YOUR_ORG/YOUR_PROJECT.git (push)    │
│   loa       git@github.com:0xHoneyJar/loa.git (fetch)          │
└─────────────────────────────────────────────────────────────────┘

OPTION A: Change origin to your repo (recommended for new projects)
───────────────────────────────────────────────────────────────────
  # Step 1: Rename current origin to 'loa' (keeps it for updates)
  git remote rename origin loa

  # Step 2: Add your repository as origin
  git remote add origin git@github.com:YOUR_ORG/YOUR_PROJECT.git

  # Step 3: Set your branch to track your origin
  git branch --set-upstream-to=origin/main main

  # Step 4: Push to your repo
  git push -u origin main

OPTION B: Just change the origin URL (if you have an existing repo)
───────────────────────────────────────────────────────────────────
  # Change origin to point to your repository
  git remote set-url origin git@github.com:YOUR_ORG/YOUR_PROJECT.git

  # Optionally add loa remote for framework updates
  git remote add loa https://github.com/0xHoneyJar/loa.git

COMMON MISTAKES TO AVOID:
─────────────────────────
✗ DON'T push to origin without checking where it points
✗ DON'T assume origin is your repo just because you cloned it
✗ DON'T delete the loa/upstream remote if you want framework updates

VERIFY YOUR SETUP:
─────────────────────────
  $ git remote -v
  origin    git@github.com:YOUR_ORG/YOUR_PROJECT.git (fetch)
  origin    git@github.com:YOUR_ORG/YOUR_PROJECT.git (push)
  loa       https://github.com/0xHoneyJar/loa.git (fetch)

After fixing, you can safely run your push/PR command again.
```

### User Confirmation Flow (CRITICAL)

**NEVER auto-proceed without explicit user confirmation.** This is a core safety requirement.

When warning is displayed, use `AskUserQuestion` tool with these exact options:

```javascript
AskUserQuestion({
  questions: [{
    question: "This appears to be a push to the Loa template repository. How would you like to proceed?",
    header: "Git Safety",
    multiSelect: false,
    options: [
      {
        label: "Proceed anyway",
        description: "I understand the risks and want to push to the upstream template"
      },
      {
        label: "Cancel",
        description: "Stop this operation, I'll reconsider"
      },
      {
        label: "Fix my remotes",
        description: "Show me how to configure my git remotes correctly"
      }
    ]
  }]
})
```

**Response Handling**:

| User Selection | Behavior |
|----------------|----------|
| "Proceed anyway" | Log confirmation, then execute the original operation ONCE |
| "Cancel" | Stop immediately, inform user operation was cancelled |
| "Fix my remotes" | Display remediation steps (above), then stop - do NOT proceed |

**Edge Cases**:

1. **User explicitly requests push in initial message**: Still show warning. User saying "push to origin" doesn't override safety - they may not realize origin points to upstream.

2. **User says "yes" or "proceed" without seeing options**: Use AskUserQuestion anyway. Free-text confirmation is not sufficient.

3. **User asks to bypass all warnings**: Explain this is a soft block that requires per-operation confirmation. There is no global disable.

4. **Same session, same remote**: Show warning each time. Don't assume previous confirmation applies to new operations.

5. **`/contribute` command is running**: Skip this check - `/contribute` has its own safeguards for intentional upstream PRs.

### Exceptions

- The `/contribute` command handles upstream PRs properly with its own safeguards
- User explicit "proceed anyway" confirmation (via AskUserQuestion) allows the operation
- If `.loa-setup-complete` shows `template_source.detected: false`, skip warnings (explicitly checked during setup)
- Operations targeting remotes that don't match known templates proceed without warning

### Sprint Status Tracking

In `loa-grimoire/sprint.md`, sprint tasks are marked with:
- No emoji = Not started
- ✅ = Completed and approved

The senior tech lead updates these after approval.

### Agent Prompts

Agent definitions in `.claude/agents/` include:
- `name` - Agent identifier
- `description` - When to invoke the agent
- `model` - AI model to use
- `color` - UI color coding

Command definitions in `.claude/commands/` contain the slash command expansion text.

## Working with Agents

### When to Use Each Agent

- **prd-architect**: Starting new features, unclear requirements (Phase 1 via `/plan-and-analyze`)
- **architecture-designer**: Technical design decisions, choosing tech stack (Phase 2 via `/architect`)
- **sprint-planner**: Breaking down work, planning implementation (Phase 3 via `/sprint-plan`)
- **sprint-task-implementer**: Writing production code (Phase 4 via `/implement`)
- **senior-tech-lead-reviewer**: Validating implementation quality (Phase 5 via `/review-sprint`)
- **devops-crypto-architect**: Production infrastructure, CI/CD pipelines, blockchain nodes, monitoring (Phase 6 via `/deploy-production`)
- **paranoid-auditor**:
  - **Code audit mode**: Security audits, vulnerability assessment, OWASP Top 10 review (Ad-hoc via `/audit`)
  - **Sprint audit mode**: Security review of sprint implementation after senior lead approval (Phase 5.5 via `/audit-sprint`)
  - **Deployment audit mode**: Infrastructure security, server hardening, deployment script review (Ad-hoc via `/audit-deployment`)
- **devrel-translator**: Translating technical documentation for executives, board, investors; creating executive summaries, stakeholder briefings, board presentations from PRDs, SDDs, audit reports (Ad-hoc via `/translate`)

### Agent Communication Style

Agents are instructed to:
- Ask clarifying questions rather than making assumptions
- Present proposals with pros/cons for uncertain decisions
- Never generate documents until confident they have complete information
- Be thorough and professional in their domain expertise

### Feedback Guidelines

When providing feedback in `loa-grimoire/a2a/sprint-N/engineer-feedback.md`:
- Be specific with file paths and line numbers
- Explain the reasoning, not just what to fix
- Distinguish critical issues from nice-to-haves
- Test the implementation before approving

## Repository Structure

```
.claude/
├── agents/              # Agent definitions (8 agents)
├── commands/            # Slash command definitions (14 commands)
└── settings.local.json  # MCP server configuration

loa-grimoire/
├── prd.md               # Product Requirements Document
├── sdd.md               # Software Design Document
├── sprint.md            # Sprint plan with tasks
├── a2a/                 # Agent-to-agent communication (preserves audit trail)
│   ├── index.md                    # Sprint audit trail index (auto-maintained)
│   ├── integration-context.md      # Feedback configuration for /feedback command
│   ├── sprint-1/                   # Sprint 1 A2A files
│   │   ├── reviewer.md             # Engineer implementation report
│   │   ├── engineer-feedback.md    # Senior lead feedback
│   │   ├── auditor-sprint-feedback.md # Security audit feedback
│   │   └── COMPLETED               # Completion marker (created by audit-sprint)
│   ├── sprint-N/                   # Additional sprints (same structure)
│   ├── deployment-report.md        # DevOps infrastructure reports
│   └── deployment-feedback.md      # Deployment security audit feedback
├── analytics/           # Usage tracking (local, opt-in sharing)
│   ├── usage.json       # Raw usage metrics
│   ├── summary.md       # Human-readable summary
│   └── pending-feedback.json # Pending feedback (if submission failed)
└── deployment/          # Production infrastructure docs
    ├── scripts/         # Server setup scripts
    ├── runbooks/        # Operational procedures
    └── ...

app/                     # Application source code (generated by sprints)
├── src/                 # Source code
├── tests/               # Test files
└── ...                  # Project-specific structure

.loa-setup-complete      # Setup marker file (gitignored)
PROCESS.md               # Comprehensive workflow documentation
CLAUDE.md                # This file
```

## Parallel Execution Guidelines

Agents are designed to handle large contexts by splitting work into parallel sub-tasks. This prevents context overflow and improves performance.

### Context Assessment (Phase -1)

All agents begin with a context assessment phase:

```bash
# Quick size check
wc -l loa-grimoire/prd.md loa-grimoire/sdd.md loa-grimoire/sprint.md loa-grimoire/a2a/*.md 2>/dev/null
```

**Thresholds vary by agent type:**

| Agent | SMALL | MEDIUM | LARGE |
|-------|-------|--------|-------|
| senior-tech-lead-reviewer | <3,000 | 3,000-6,000 | >6,000 |
| paranoid-auditor | <2,000 | 2,000-5,000 | >5,000 |
| sprint-task-implementer | <3,000 | 3,000-8,000 | >8,000 |
| devops-crypto-architect | <2,000 | 2,000-5,000 | >5,000 |

### Splitting Strategies by Agent

**senior-tech-lead-reviewer**: Split by sprint task
- Each task gets its own parallel Explore agent
- Results consolidated into single verdict

**paranoid-auditor**: Split by audit category
- 5 parallel agents: Security, Architecture, Code Quality, DevOps, Blockchain/Crypto
- Results consolidated with combined findings

**sprint-task-implementer**: Split by task or feedback source
- Option A: Parallel feedback checking (audit + senior lead)
- Option B: Parallel task implementation (independent tasks)

**devops-crypto-architect**: Split by infrastructure component
- Group components by dependency level
- Batch 1: Network + Security (no dependencies)
- Batch 2: Compute + Database + Storage (depend on network)
- Batch 3: Monitoring + CI/CD (depend on compute)

### Parallel Execution Pattern

Agents use the Task tool with `subagent_type="Explore"` for parallel work:

```
Spawn N parallel Explore agents, one per {task/category/component}:

Agent 1: "{Specific instructions for task 1}
- Reference specific files and requirements
- Define exact deliverables
- Return: structured summary for consolidation"

Agent 2: "{Specific instructions for task 2}
- Reference specific files and requirements
- Define exact deliverables
- Return: structured summary for consolidation"

... (similar for remaining tasks)
```

### Consolidation Requirements

After parallel execution, agents must:
1. Collect results from all sub-agents
2. Check for conflicts or inconsistencies
3. Generate unified output (report, verdict, implementation)
4. Ensure no gaps in coverage

### When NOT to Split

- **SMALL contexts**: Always proceed sequentially
- **Highly interdependent tasks**: Dependencies require sequential execution
- **Single-focus work**: One task with no natural divisions
- **User explicitly requests sequential**: Honor user preference

### Decision Matrix

| Context | Independence | Strategy |
|---------|--------------|----------|
| SMALL | Any | Sequential |
| MEDIUM | Low | Sequential with ordering |
| MEDIUM | High | Parallel by task/component |
| LARGE | Any | MUST split into parallel |

## Notes for Claude Code

- Always read `loa-grimoire/prd.md`, `loa-grimoire/sdd.md`, and `loa-grimoire/sprint.md` for context when working on implementation tasks
- When `/implement sprint-N` is invoked:
  - Validate sprint name format (must be `sprint-N` where N is positive integer)
  - Create `loa-grimoire/a2a/sprint-N/` directory if it doesn't exist
  - Check for audit feedback first (`loa-grimoire/a2a/sprint-N/auditor-sprint-feedback.md`)
  - Then check for engineer feedback (`loa-grimoire/a2a/sprint-N/engineer-feedback.md`)
  - Address all feedback before proceeding with new work
- When `/review-sprint sprint-N` is invoked:
  - Validate sprint directory and `reviewer.md` exist
  - Check for `COMPLETED` marker (skip if already completed)
- When `/audit-sprint sprint-N` is invoked:
  - Validate senior lead approval exists ("All good" in engineer-feedback.md)
  - Create `COMPLETED` marker on approval
- All sprint A2A files are preserved in `loa-grimoire/a2a/sprint-N/` for audit trail
- The `loa-grimoire/a2a/index.md` provides organizational memory across sprints
- The senior tech lead role is played by the human user during review phases
- Never skip phases—each builds on the previous
- The process is designed for thorough discovery and iterative refinement, not speed
- Security is paramount, especially for crypto/blockchain projects
- **Parallel execution**: Agents should assess context size first and split into parallel sub-tasks when context exceeds thresholds
