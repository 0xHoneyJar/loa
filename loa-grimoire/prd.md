# Product Requirements Document: Loa Setup, Analytics & Feedback System

**Version**: 1.0
**Date**: 2025-12-19
**Author**: PRD Architect Agent
**Status**: Draft

---

## 1. Executive Summary

### 1.1 Problem Statement

The Honey Jar (0xHoneyJar) has 6 developers using AI-assisted development, but each works solo with their own conventions. This creates:

- **Knowledge silos** - No shared patterns or workflows
- **Cognitive overhead** - High context-switching when reviewing others' work
- **Handoff friction** - Marketing, ops, and devrel teams struggle to access materials they need
- **Non-deterministic outcomes** - AI usage varies wildly, producing inconsistent artifacts

### 1.2 Solution

Extend Loa with three new capabilities:

1. **Onboarding flow** (`/setup`) - Guided MCP configuration, project initialization, welcome experience
2. **Analytics capture** - Automatic tracking of usage metrics throughout the build lifecycle
3. **Feedback flow** (`/feedback`) - Lightweight dev survey with auto-attached analytics, posted to Linear

### 1.3 Success Criteria

- 100% of developers using Loa within 2 months
- Downstream teams (marketing, ops, devrel) can access raw materials with minimal dev input
- Reduced drift in conventions across projects
- Continuous improvement of Loa via feedback data

---

## 2. Goals & Objectives

### 2.1 Primary Goals

| Goal | Metric | Target |
|------|--------|--------|
| Universal adoption | % of active devs using Loa | 100% within 2 months |
| Reduced handoff friction | Time for downstream teams to find materials | Minimal dev involvement required |
| Convention consistency | Documentation quality variance | Standardized across all projects |
| Framework improvement | Feedback submissions analyzed | 100% reviewed by stakeholder |

### 2.2 Secondary Goals

- Faster onboarding for new team members
- Fewer questions during project handoffs
- Data-driven decisions for Loa improvements
- Identification of training needs across the team

---

## 3. User & Stakeholder Context

### 3.1 Primary Users

**Developers (6 total)**
- Already using Claude Code CLI
- Most have MCP servers configured
- Currently using vanilla Claude Code without custom agents/commands
- Need guided setup and consistent workflows

### 3.2 Secondary Stakeholders

**Marketing, Ops, DevRel Teams**
- Need access to: READMEs, architecture docs, changelogs, deployment info
- Current pain: High barrier to entry, lots of prep work before shipping
- Success: Self-service access to best-in-class GTM materials

**Framework Owner (Reviewer)**
- Reviews all feedback submissions
- Uses data to improve Loa
- Identifies training needs and productivity patterns

### 3.3 Environment

- All devs on Claude Code CLI
- Linear workspace: THJ (The Honey Jar)
- MCP integrations: GitHub, Linear, Vercel, Discord, web3-stats

---

## 4. Functional Requirements

### 4.1 Onboarding Flow (`/setup`)

#### 4.1.1 Trigger Conditions

| ID | Requirement | Priority |
|----|-------------|----------|
| ONB-001 | `/setup` command available as explicit invocation | P0 |
| ONB-002 | First-time `claude` launch in new environment suggests running `/setup` | P0 |
| ONB-003 | Setup must complete before `/plan-and-analyze` is allowed | P0 |

#### 4.1.2 Welcome Experience

| ID | Requirement | Priority |
|----|-------------|----------|
| ONB-010 | Display welcome message explaining Loa's purpose and workflow | P0 |
| ONB-011 | Show overview of what setup will configure | P0 |
| ONB-012 | Mention analytics collection with opt-out option | P0 |

#### 4.1.3 MCP Configuration Wizard

| ID | Requirement | Priority |
|----|-------------|----------|
| ONB-020 | Detect which MCP servers are already configured | P0 |
| ONB-021 | For each missing MCP (GitHub, Linear, Vercel, Discord, web3-stats): offer guided setup or documentation link | P0 |
| ONB-022 | Allow dev to choose: guided walkthrough OR self-service with docs | P0 |
| ONB-023 | All MCP servers are optional (dev can skip any) | P1 |
| ONB-024 | Save progress if setup fails partway; allow resume | P1 |
| ONB-025 | Log any setup failures to analytics | P0 |

#### 4.1.4 Project Initialization

| ID | Requirement | Priority |
|----|-------------|----------|
| ONB-030 | Create Linear project for this build (if Linear MCP configured) | P0 |
| ONB-031 | Ensure main branch is protected (if GitHub MCP configured) | P0 |
| ONB-032 | Apply other sane best-practice defaults (labels, branch naming) | P1 |
| ONB-033 | Initialize analytics tracking file (`loa-grimoire/analytics/usage.json`) | P0 |

#### 4.1.5 Setup Completion

| ID | Requirement | Priority |
|----|-------------|----------|
| ONB-040 | Display summary of what was configured | P0 |
| ONB-041 | Mark setup as complete (persist state to allow `/plan-and-analyze`) | P0 |
| ONB-042 | Provide next steps guidance | P0 |

---

### 4.2 Analytics Capture System

#### 4.2.1 Data Collection

| ID | Requirement | Priority |
|----|-------------|----------|
| ANA-001 | Capture token usage (input/output tokens) | P0 |
| ANA-002 | Capture time taken (wall clock per session, total project duration) | P0 |
| ANA-003 | Capture number of commits | P0 |
| ANA-004 | Capture local dev environment (OS, shell) | P0 |
| ANA-005 | Capture hardware info (CPU, RAM, architecture) | P0 |
| ANA-006 | Capture software versions (Claude Code version, Node, etc.) | P0 |
| ANA-007 | Capture phases completed (PRD, SDD, sprints, deployment) | P0 |
| ANA-008 | Capture feedback loop iterations (review cycles, audit cycles) | P0 |

#### 4.2.2 Storage

| ID | Requirement | Priority |
|----|-------------|----------|
| ANA-010 | Store raw data in `loa-grimoire/analytics/usage.json` | P0 |
| ANA-011 | Auto-generate human-readable summary in `loa-grimoire/analytics/summary.md` | P0 |
| ANA-012 | Aggregate metrics at project level (not per-session) | P0 |
| ANA-013 | Update analytics incrementally as work progresses | P0 |

#### 4.2.3 Privacy & Opt-Out

| ID | Requirement | Priority |
|----|-------------|----------|
| ANA-020 | Mention analytics collection during `/setup` | P0 |
| ANA-021 | Document analytics in README | P0 |
| ANA-022 | Provide argument to disable analytics (not default) | P1 |
| ANA-023 | If disabled, Loa still functions normally | P1 |

---

### 4.3 Feedback Flow (`/feedback`)

#### 4.3.1 Trigger Conditions

| ID | Requirement | Priority |
|----|-------------|----------|
| FBK-001 | `/feedback` command available for manual invocation anytime | P0 |
| FBK-002 | Suggest `/feedback` automatically after `/deploy-production` completes | P0 |

#### 4.3.2 Survey Questions

| ID | Requirement | Priority |
|----|-------------|----------|
| FBK-010 | Show progress indicator (n/m or progress bar) throughout survey | P0 |
| FBK-011 | Q1: "What's one thing you would change?" (free text) | P0 |
| FBK-012 | Q2: "What's one thing you loved?" (free text) | P0 |
| FBK-013 | Q3: "Rate your experience compared to other Loa builds" (scale) | P0 |
| FBK-014 | Q4: "How comfortable and intuitive was the process?" (multiple choice) | P0 |

#### 4.3.3 Submission

| ID | Requirement | Priority |
|----|-------------|----------|
| FBK-020 | Auto-attach analytics from `loa-grimoire/analytics/` | P0 |
| FBK-021 | Create/update issue in "Loa Feedback" Linear project | P0 |
| FBK-022 | One issue per project (repo) - multiple feedback submissions append to same issue | P0 |
| FBK-023 | Include: project name, dev identifier, rating, responses, full analytics | P0 |
| FBK-024 | Link to project's Linear project if one was created during setup | P1 |

---

### 4.4 CI Distribution & Updates

#### 4.4.1 Git Remote Strategy

| ID | Requirement | Priority |
|----|-------------|----------|
| UPD-001 | Loa repository serves as upstream remote | P0 |
| UPD-002 | Devs can `git pull` updates from Loa remote | P0 |
| UPD-003 | Document merge strategy for pulling updates | P0 |

#### 4.4.2 Update Command

| ID | Requirement | Priority |
|----|-------------|----------|
| UPD-010 | `/update` command fetches latest from Loa upstream | P0 |
| UPD-011 | Show changelog/diff summary of what changed | P1 |
| UPD-012 | Handle merge conflicts gracefully with guidance | P1 |

---

## 5. Non-Functional Requirements

### 5.1 Usability

| ID | Requirement | Priority |
|----|-------------|----------|
| NFR-001 | Setup wizard should complete in under 10 minutes (excluding MCP auth) | P1 |
| NFR-002 | Feedback survey should complete in under 2 minutes | P0 |
| NFR-003 | All prompts should be clear and jargon-free | P0 |
| NFR-004 | Progress indicators for multi-step flows | P0 |

### 5.2 Reliability

| ID | Requirement | Priority |
|----|-------------|----------|
| NFR-010 | Setup failures logged and resumable | P0 |
| NFR-011 | Analytics capture should not block main workflow | P0 |
| NFR-012 | Feedback submission failure should not lose survey responses | P1 |

### 5.3 Compatibility

| ID | Requirement | Priority |
|----|-------------|----------|
| NFR-020 | Support macOS and Linux development environments | P0 |
| NFR-021 | Work with Claude Code CLI current stable version | P0 |

---

## 6. Scope

### 6.1 In Scope (MVP)

- `/setup` command with full MCP wizard
- First-launch detection and setup suggestion
- Setup enforcement before `/plan-and-analyze`
- Analytics capture (all specified metrics)
- Dual storage (JSON + Markdown summary)
- `/feedback` command with survey
- Linear integration for feedback (Loa Feedback project)
- `/update` command for pulling Loa updates
- Git remote distribution strategy
- README documentation updates

### 6.2 Out of Scope (Deferred)

- Advanced analytics dashboards
- Automated Loa update checks (proactive notifications)
- Integration with tools beyond the five MCP servers (GitHub, Linear, Vercel, Discord, web3-stats)
- Analytics opt-out UI (argument-only for now)

### 6.3 Unchanged

The existing Loa workflow remains intact:
- `/plan-and-analyze` (PRD creation)
- `/architect` (SDD creation)
- `/sprint-plan` (Sprint planning)
- `/implement` (Sprint implementation)
- `/review-sprint` (Code review)
- `/audit-sprint` (Security audit)
- `/deploy-production` (Production deployment)
- `/audit` (Ad-hoc security audit)
- `/audit-deployment` (Deployment audit)
- `/translate` (Executive translation)

---

## 7. User Flows

### 7.1 New Project Setup Flow

```
Developer clones Loa template
         │
         ▼
    Runs `claude`
         │
         ▼
┌────────────────────────┐
│ First launch detected? │
└────────────────────────┘
         │ Yes
         ▼
  Suggest `/setup`
         │
         ▼
┌────────────────────────┐
│   Welcome Message      │
│   - Loa overview       │
│   - Analytics notice   │
└────────────────────────┘
         │
         ▼
┌────────────────────────┐
│   MCP Detection        │
│   - Check configured   │
│   - List missing       │
└────────────────────────┘
         │
         ▼
  For each missing MCP:
┌────────────────────────┐
│  Guide or Docs?        │
│  [Guided] [Self-serve] │
└────────────────────────┘
         │
         ▼
┌────────────────────────┐
│  Project Init          │
│  - Linear project      │
│  - Branch protection   │
│  - Analytics file      │
└────────────────────────┘
         │
         ▼
┌────────────────────────┐
│  Setup Complete        │
│  - Summary             │
│  - Next steps          │
└────────────────────────┘
         │
         ▼
  `/plan-and-analyze` unlocked
```

### 7.2 Analytics Capture Flow

```
Throughout build lifecycle:
         │
         ▼
┌────────────────────────┐
│  On each claude session│
│  - Increment tokens    │
│  - Track time          │
│  - Log environment     │
└────────────────────────┘
         │
         ▼
┌────────────────────────┐
│  On phase completion   │
│  - Mark phase done     │
│  - Record iterations   │
└────────────────────────┘
         │
         ▼
┌────────────────────────┐
│  On commit             │
│  - Increment counter   │
└────────────────────────┘
         │
         ▼
  Update loa-grimoire/analytics/usage.json
  Regenerate loa-grimoire/analytics/summary.md
```

### 7.3 Feedback Submission Flow

```
After `/deploy-production` OR manual `/feedback`:
         │
         ▼
┌────────────────────────┐
│  Progress: 1/4         │
│  "What's one thing     │
│   you would change?"   │
└────────────────────────┘
         │
         ▼
┌────────────────────────┐
│  Progress: 2/4         │
│  "What's one thing     │
│   you loved?"          │
└────────────────────────┘
         │
         ▼
┌────────────────────────┐
│  Progress: 3/4         │
│  "Rate vs other Loa    │
│   builds" [1-5 scale]  │
└────────────────────────┘
         │
         ▼
┌────────────────────────┐
│  Progress: 4/4         │
│  "How comfortable was  │
│   the process?"        │
│  [ ] Very intuitive    │
│  [ ] Somewhat intuitive│
│  [ ] Neutral           │
│  [ ] Somewhat confusing│
│  [ ] Very confusing    │
└────────────────────────┘
         │
         ▼
┌────────────────────────┐
│  Load analytics from   │
│  loa-grimoire/analytics/       │
└────────────────────────┘
         │
         ▼
┌────────────────────────┐
│  Submit to Linear      │
│  - Find/create issue   │
│  - Append feedback     │
│  - Attach analytics    │
└────────────────────────┘
         │
         ▼
  Confirmation message
```

---

## 8. Data Models

### 8.1 Analytics Schema (`loa-grimoire/analytics/usage.json`)

```json
{
  "project": {
    "name": "string",
    "repo": "string",
    "created_at": "ISO8601",
    "setup_completed_at": "ISO8601"
  },
  "environment": {
    "os": "string",
    "os_version": "string",
    "shell": "string",
    "cpu": "string",
    "cpu_cores": "number",
    "ram_gb": "number",
    "architecture": "string",
    "claude_code_version": "string",
    "node_version": "string"
  },
  "mcp_configured": {
    "github": "boolean",
    "linear": "boolean",
    "vercel": "boolean",
    "discord": "boolean",
    "web3_stats": "boolean"
  },
  "usage": {
    "total_sessions": "number",
    "total_tokens_input": "number",
    "total_tokens_output": "number",
    "total_time_minutes": "number",
    "total_commits": "number"
  },
  "phases": {
    "setup": { "completed": "boolean", "timestamp": "ISO8601" },
    "prd": { "completed": "boolean", "timestamp": "ISO8601" },
    "sdd": { "completed": "boolean", "timestamp": "ISO8601" },
    "sprint_plan": { "completed": "boolean", "timestamp": "ISO8601" },
    "sprints": [
      {
        "name": "sprint-1",
        "implementation_iterations": "number",
        "review_iterations": "number",
        "audit_iterations": "number",
        "completed": "boolean",
        "timestamp": "ISO8601"
      }
    ],
    "deployment": { "completed": "boolean", "timestamp": "ISO8601" }
  },
  "setup_failures": [
    {
      "step": "string",
      "error": "string",
      "timestamp": "ISO8601"
    }
  ],
  "feedback_submissions": [
    {
      "timestamp": "ISO8601",
      "linear_issue_id": "string"
    }
  ]
}
```

### 8.2 Linear Feedback Issue Structure

**Project**: Loa Feedback
**Issue Title**: `[Project Name] - Feedback`

**Issue Body** (appended on each submission):
```markdown
---
## Feedback Submission - {timestamp}

**Developer**: {dev_identifier}

### Survey Responses
1. **What would you change?**: {response}
2. **What did you love?**: {response}
3. **Rating vs other builds**: {1-5}
4. **Process comfort level**: {choice}

### Analytics Summary
- **Total Time**: {hours}h {minutes}m
- **Total Tokens**: {input} in / {output} out
- **Commits**: {count}
- **Phases Completed**: {list}
- **Review Iterations**: {count}
- **Audit Iterations**: {count}

<details>
<summary>Full Analytics JSON</summary>

{full_json}

</details>
---
```

---

## 9. Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Dev skips setup, can't use Loa | Low | Medium | Enforce setup before `/plan-and-analyze` with clear messaging |
| MCP auth failures frustrate devs | Medium | Medium | Save progress, allow resume, provide clear error messages |
| Analytics capture impacts performance | Low | High | Async writes, non-blocking design |
| Feedback gets skipped | Medium | Low | Auto-suggest after deploy, keep survey short (4 questions) |
| Merge conflicts when pulling Loa updates | Medium | Medium | Document merge strategy, `/update` command handles gracefully |

---

## 10. Dependencies

| Dependency | Owner | Status |
|------------|-------|--------|
| Linear workspace (THJ) | The Honey Jar | Exists |
| "Loa Feedback" Linear project | To be created | Pending |
| Claude Code CLI | Anthropic | Available |
| MCP servers (5) | Various | Available |
| Git hosting (GitHub) | The Honey Jar | Exists |

---

## 11. Timeline & Milestones

| Milestone | Description |
|-----------|-------------|
| M1: Architecture | SDD complete with technical design |
| M2: Sprint Plan | Implementation broken into sprints |
| M3: MVP Complete | All three flows functional |
| M4: Team Rollout | 100% dev adoption |

**Target**: 100% adoption within 2 months of MVP completion.

---

## 12. Open Questions

1. **Dev identifier for feedback**: Use GitHub username, Linear user, or something else?
2. **Analytics granularity**: Should we track per-agent token usage or just totals?
3. **Update command behavior**: Auto-stash changes before pull, or require clean working tree?

---

## 13. Appendix

### A. MCP Servers Reference

| Server | Purpose | Auth Method |
|--------|---------|-------------|
| GitHub | Repository operations, PRs, issues | OAuth / PAT |
| Linear | Issue and project management | API key |
| Vercel | Deployment and hosting | OAuth |
| Discord | Community/team communication | Bot token |
| web3-stats | Blockchain data (Dune, Blockscout) | API keys |

### B. Existing Loa Commands

| Command | Purpose |
|---------|---------|
| `/plan-and-analyze` | Create PRD |
| `/architect` | Create SDD |
| `/sprint-plan` | Plan sprints |
| `/implement sprint-N` | Implement sprint |
| `/review-sprint sprint-N` | Review sprint |
| `/audit-sprint sprint-N` | Security audit sprint |
| `/deploy-production` | Deploy to production |
| `/audit` | Ad-hoc security audit |
| `/audit-deployment` | Deployment security audit |
| `/translate` | Executive translation |

### C. New Commands (This PRD)

| Command | Purpose |
|---------|---------|
| `/setup` | Onboarding wizard |
| `/feedback` | Dev feedback survey |
| `/update` | Pull Loa framework updates |
