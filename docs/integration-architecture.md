# Integration Architecture

**Document Version:** 1.0
**Last Updated:** 2025-12-07
**Status:** Design Complete

## Executive Summary

This document defines the integration architecture for adapting the agentic-base framework to work seamlessly with your organization's existing development workflow. The architecture preserves your natural workflow (Discord → Docs → Linear) while enabling AI agents to collaborate with context continuity across all platforms.

**Key Design Principles:**
- **Linear as source of truth** for task management and status
- **Discord as primary communication layer** for both technical and non-technical team members
- **Minimal friction** for existing workflows (Hivemind methodology)
- **Flexible configuration** for easy adjustments as team needs evolve
- **Context preservation** across all platforms for human and agent access

## Current Workflow Analysis

### Team Structure
- **Size:** 2-4 developers working concurrently
- **Roles:**
  - Developers (code-literate, use Linear + GitHub + Discord)
  - Researcher/Ethnographer (non-technical, uses Discord + Docs + Vercel previews)

### Natural Information Flow
```
1. Initial discussions → Discord threads
2. Design stabilization → Google Docs / Notion
3. Implementation tracking → Linear issues
4. Code review → GitHub PRs
5. Deployment previews → Vercel
6. Researcher feedback → Discord (on docs/previews)
```

### Pain Points Addressed
- **Manual transcription:** Discord discussions don't automatically flow to Linear
- **Context loss:** Researcher feedback in Discord gets lost or manually copied
- **Visibility gaps:** Developers don't always know what others are working on
- **Agent blindness:** Agents can't access researcher rationale or team discussions

## Integration Architecture Overview

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         DISCORD LAYER                            │
│  (Team communication, researcher feedback, bot interactions)     │
│                                                                   │
│  • Feedback capture (📌 reactions)                              │
│  • Daily digest notifications                                    │
│  • Query commands (/show-sprint, /preview, /doc)                │
│  • Natural language bot interactions                             │
└────────────┬────────────────────────────────────┬───────────────┘
             │                                    │
             ▼                                    ▼
┌─────────────────────────┐          ┌─────────────────────────┐
│    LINEAR (Source of    │◄────────►│   GITHUB (Code & PRs)   │
│        Truth)           │          │                         │
│                         │          │  • Pull requests        │
│  • Sprint tasks (issues)│          │  • Code review          │
│  • Status tracking      │          │  • Branch management    │
│  • Assignee & ownership │          └─────────────────────────┘
│  • Draft feedback issues│                     │
└────────────┬────────────┘                     │
             │                                  │
             ▼                                  ▼
┌─────────────────────────────────────────────────────────────────┐
│                    AGENTIC-BASE FRAMEWORK                        │
│                                                                   │
│  • Reads Linear API for task context                             │
│  • Implements tasks (/implement THJ-123)                         │
│  • Generates reports (docs/a2a/reviewer.md)                      │
│  • Reviews code (/review-sprint)                                 │
│  • Updates Linear statuses automatically                         │
└─────────────────────────────────────────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────────────────────────────┐
│                    VERCEL (Deployment)                           │
│                                                                   │
│  • Preview deployments                                           │
│  • Production releases                                           │
│  • Linked to Linear issues & Discord notifications              │
└─────────────────────────────────────────────────────────────────┘
```

## Component Design

### 1. Linear-First Task Management

**Design Decision:** Linear is the single source of truth for all sprint tasks, assignments, and status.

#### Sprint Planning Flow

```
User runs: /sprint-plan

┌─────────────────────────────────────────────────────────────────┐
│ Sprint Planner Agent                                             │
│                                                                   │
│ 1. Reads docs/prd.md and docs/sdd.md                            │
│ 2. Generates docs/sprint.md with task breakdown                 │
│ 3. Creates DRAFT Linear issues via Linear API                   │
│    - Title: [Sprint 1 Task 1] Set up Next.js structure         │
│    - Description: Includes acceptance criteria, dependencies    │
│    - Labels: sprint-1, backend, setup                           │
│    - Status: "Todo"                                             │
│    - Draft: true (requires dev review)                          │
│ 4. Updates docs/sprint.md with Linear IDs:                      │
│                                                                   │
│    ### Sprint 1, Task 1: Set up Next.js project structure      │
│    **Linear Issue:** THJ-123                                    │
│    **Status:** Draft                                            │
│    **Assignee:** Unassigned                                     │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
         │
         ▼
Developer reviews draft Linear issues, edits if needed, publishes
```

#### Implementation Flow

```
Developer assigns Linear issue THJ-123 to themselves
   ↓
Linear status: Todo → In Progress (automatic via Linear API)
   ↓
Developer runs: /implement THJ-123
   ↓
┌─────────────────────────────────────────────────────────────────┐
│ Sprint Task Implementer Agent                                    │
│                                                                   │
│ 1. Reads Linear API for THJ-123:                                │
│    - Task description & acceptance criteria                      │
│    - Assignee (verify it's assigned)                            │
│    - Current status                                             │
│    - Any comments or context from Linear                        │
│    - Original feedback context (if from Discord 📌)             │
│                                                                   │
│ 2. Checks for previous feedback:                                │
│    - Reads docs/a2a/engineer-feedback.md                        │
│    - Addresses any outstanding review comments                  │
│                                                                   │
│ 3. Implements the task:                                         │
│    - Writes code                                                │
│    - Runs tests                                                 │
│    - Validates against acceptance criteria                      │
│                                                                   │
│ 4. Generates implementation report:                             │
│    - Writes to docs/a2a/reviewer.md                             │
│    - Includes changes, rationale, testing notes                 │
│                                                                   │
│ 5. Updates Linear status:                                       │
│    - In Progress → In Review (via Linear API)                   │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

#### Linear Status Workflow

```
Todo
  ↓ (Developer self-assigns in Linear)
In Progress
  ↓ (/implement THJ-123 completes)
In Review
  ↓ (Reviewer finds issues)
Changes Requested
  ↓ (Developer re-runs /implement THJ-123)
In Review
  ↓ (/review-sprint approves)
Done ✅
```

**Status Automation:**
- Agent automatically updates Linear statuses via API
- Developers can manually override if needed
- Status changes trigger Discord notifications (configurable)

### 2. Researcher Integration (Discord Feedback Capture)

**Design Decision:** Option A+ (Smart Automated Capture with 📌 reaction)

#### Feedback Capture Flow

```
Researcher posts in Discord:
  "The login flow on the Vercel preview is confusing -
   users don't know where to click after entering email.
   Preview: https://myapp-abc123.vercel.app"

Developer or team member reacts with 📌
   ↓
┌─────────────────────────────────────────────────────────────────┐
│ Discord Bot (Feedback Capture)                                   │
│                                                                   │
│ 1. Detects 📌 reaction on message                               │
│ 2. Extracts context:                                            │
│    - Message content                                            │
│    - Author (@researcher)                                       │
│    - Thread/channel link                                        │
│    - Timestamp                                                  │
│    - Any URLs (Vercel previews, docs)                           │
│    - Attached images/recordings                                 │
│                                                                   │
│ 3. Creates DRAFT Linear issue:                                  │
│                                                                   │
│    Title: [Researcher Feedback] Login flow confusing            │
│                                                                   │
│    Description:                                                  │
│    **Original feedback from @researcher in #design-review:**    │
│    > "The login flow on the Vercel preview is confusing -       │
│    > users don't know where to click after entering email."     │
│                                                                   │
│    **Context:**                                                  │
│    - Discord thread: [link to message]                          │
│    - Vercel preview: https://myapp-abc123.vercel.app           │
│    - Timestamp: Dec 7, 2025 at 2:34pm                          │
│    - Attachments: [links if any]                               │
│                                                                   │
│    Labels: researcher-feedback, ux                              │
│    Status: Todo                                                 │
│    Draft: true                                                  │
│                                                                   │
│ 4. Replies in Discord thread:                                   │
│    "✅ Feedback captured as draft Linear issue [THJ-145]"       │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
         │
         ▼
Developer reviews draft issues periodically (daily triage)
         │
         ▼
Developer publishes issue, assigns to sprint, or merges with existing task
```

#### Why 📌 Reaction?

- **Low friction:** Single click, no commands to remember
- **Intentional:** Dev explicitly decides "this is actionable feedback"
- **Preserves flow:** Researcher never changes behavior
- **Batched triage:** Dev reviews drafts in batch, not per-message interrupt
- **Noise filtering:** Casual chat doesn't become Linear issues

### 3. Discord Visibility & Query System

#### Daily Digest (Batch Notifications)

**Configuration:** `integration/config/discord-digest.yml`

```yaml
schedule: "0 9 * * *"  # Daily at 9am (cron format)
channel_id: "1234567890"  # #sprint-updates channel
detail_level: "full"  # Options: minimal, summary, full
enabled: true

include:
  in_progress: true
  completed_today: true
  in_review: true
  blockers: true

immediate_alerts:
  enabled: true
  severity: ["critical", "blocker"]
  channel_id: "1234567891"  # Optional separate alert channel
```

**Example Digest Post:**

```markdown
📊 **Daily Sprint Update - December 7, 2025**

**🚀 In Progress (3 tasks)**
• THJ-123: Set up Next.js structure - @alice (started 2d ago)
• THJ-125: Implement auth flow - @bob (started 1d ago)
• THJ-128: Design API schema - @charlie (started 4h ago)

**✅ Completed Today (2 tasks)**
• THJ-122: Configure ESLint - @alice → Approved by @reviewer
• THJ-124: Set up CI/CD - @bob → Approved by @reviewer

**🔄 In Review (1 task)**
• THJ-126: Database migrations - @alice (waiting for review)

**⚠️ Blockers (1 task)**
• THJ-127: Payment integration - @bob (blocked: awaiting API keys)

**📌 New Feedback Captured (2 drafts)**
• Draft THJ-145: Login flow confusing - from @researcher
• Draft THJ-146: Color contrast too low - from @researcher

Use /show-sprint for real-time status or /task <ID> for details.
```

#### Query Commands

**For Researchers (Non-technical):**

| Command | Description | Example Output |
|---------|-------------|----------------|
| `/show-sprint` | Current sprint status summary | Shows in-progress, completed, blocked tasks |
| `/preview THJ-123` | Get Vercel preview URL | Returns: `https://myapp-abc123.vercel.app` |
| `/doc prd` | Link to PRD document | Returns Google Doc or file path |
| `/doc sdd` | Link to SDD document | Returns Google Doc or file path |
| `/task THJ-123` | Simple task summary | Title, status, assignee, preview link |
| Natural language | "what's the status on auth?" | Bot detects intent, shows THJ-125 status |

**For Developers:**

| Command | Description | Example Output |
|---------|-------------|----------------|
| All researcher commands | Same as above | Same as above |
| `/implement-status THJ-123` | Who's working on this task? | "In progress by @alice since 2h ago" |
| `/my-tasks` | My assigned tasks | Lists all Linear issues assigned to you |
| `/feedback @researcher` | All feedback from specific user | Lists all captured researcher feedback |

#### Natural Language Processing

Bot detects common patterns in casual conversation:

```
Researcher: "Hey, what's happening with the login work?"
Bot: 🔍 I found these related tasks:
     • THJ-125: Implement auth flow - @bob (In Progress)
     • THJ-145: Login flow UX feedback - Unassigned (Draft)

Researcher: "Is the dashboard ready to test?"
Bot: 🔍 Dashboard-related tasks:
     • THJ-130: Dashboard UI - @charlie (In Review)
     • Preview: https://myapp-xyz789.vercel.app
```

**Implementation:** Uses simple keyword matching initially, can be enhanced with LLM later.

### 4. Researcher Notification Preferences

**User-Controlled Configuration via Discord:**

```
Researcher types: /my-notifications

Bot replies:
┌─────────────────────────────────────────────────────────────┐
│ 📬 Your Notification Preferences                             │
│                                                              │
│ Daily Digest: ✅ Enabled (9am in #sprint-updates)           │
│ My Feedback Updates: ✅ Enabled                             │
│   └─ Notifies when tasks from your feedback are completed   │
│                                                              │
│ Vercel Previews: ✅ Enabled                                 │
│   └─ Notifies when preview deployments are ready to test    │
│                                                              │
│ Review Requests: ❌ Disabled                                │
│   └─ Notifies when your review/testing is needed            │
│                                                              │
│ React to change settings:                                   │
│ 📊 = Toggle daily digest                                    │
│ 🔔 = Toggle feedback updates                                │
│ 🚀 = Toggle Vercel preview notifications                    │
│ 👀 = Toggle review requests                                 │
│                                                              │
│ Or use commands:                                            │
│ /notifications digest off                                   │
│ /notifications feedback-updates on                          │
└─────────────────────────────────────────────────────────────┘
```

**Storage:** `integration/config/user-preferences.json`

```json
{
  "users": {
    "researcher_discord_id": {
      "name": "Researcher Name",
      "daily_digest": true,
      "feedback_updates": true,
      "vercel_previews": true,
      "review_requests": false
    },
    "developer_discord_id": {
      "name": "Developer Name",
      "daily_digest": true,
      "feedback_updates": false,
      "vercel_previews": true,
      "review_requests": true
    }
  }
}
```

### 5. Agent Modifications for Linear Integration

#### Modified Agents

**1. sprint-planner (sprint-planner.md)**

**New responsibilities:**
- After generating `docs/sprint.md`, create draft Linear issues
- Embed Linear issue IDs back into `docs/sprint.md`
- Use Linear API to create issues with proper labels, descriptions, and status

**Implementation changes:**
- Add Linear API client initialization
- Add function to create draft Linear issues
- Add function to update sprint.md with Linear IDs
- Include error handling for Linear API failures

**2. sprint-task-implementer (sprint-task-implementer.md)**

**New responsibilities:**
- Accept Linear issue ID as parameter (e.g., `/implement THJ-123`)
- Read task details from Linear API instead of only sprint.md
- Check if task is already assigned to someone else (conflict detection)
- Update Linear status automatically (In Progress → In Review)
- Include original researcher feedback context if task originated from Discord

**Implementation changes:**
- Modify prompt to accept Linear ID parameter
- Add Linear API integration for reading issue details
- Add ownership check before starting work
- Add status update function after implementation
- Parse and display Discord feedback context if present

**3. senior-tech-lead-reviewer (senior-tech-lead-reviewer.md)**

**New responsibilities:**
- Update Linear status based on review outcome
- Mark sprint.md tasks with ✅ when approved
- Optionally notify assignee via Discord when changes requested

**Implementation changes:**
- Add Linear API status update (In Review → Done or Changes Requested)
- Add Discord notification trigger (optional, configurable)

#### Agent Communication Flow with Linear

```
Developer: /implement THJ-123

sprint-task-implementer agent:
  1. Calls Linear API: GET /issues/THJ-123
  2. Parses response:
     {
       "id": "THJ-123",
       "title": "Implement auth flow",
       "description": "...",
       "state": { "name": "In Progress" },
       "assignee": { "name": "Alice" },
       "labels": ["sprint-1", "backend"],
       "parent": null,
       "comments": [...],
       "custom_fields": {
         "discord_feedback_link": "https://discord.com/...",
         "vercel_preview": "https://myapp-abc123.vercel.app"
       }
     }
  3. Checks assignee (if not current user, warns about conflict)
  4. Reads acceptance criteria from description
  5. Implements task
  6. Calls Linear API: PATCH /issues/THJ-123
     { "state": "In Review" }
  7. Writes docs/a2a/reviewer.md
```

### 6. Review Workflow Configuration

**Design Decision:** Flexible manual trigger (Mode B or Mode C)

**Configuration:** `integration/config/review-workflow.yml`

```yaml
review_workflow:
  mode: "developer"  # Options: "developer" (B), "designated_reviewer" (C), "auto" (A)

  # For mode: "designated_reviewer"
  reviewers:
    - discord_id: "1234567890"
      name: "Senior Dev 1"
      linear_user_id: "abc-123"
    - discord_id: "0987654321"
      name: "Senior Dev 2"
      linear_user_id: "def-456"

  rotation: "round-robin"  # Options: "round-robin", "manual", "workload-based"

  notifications:
    discord_enabled: true
    discord_channel_id: "1234567890"  # #code-review channel
    mention_reviewer: true
```

**Mode B (Developer-triggered):**
```
Developer: /implement THJ-123
  → Completes implementation
  → Linear status: In Progress → In Review

Developer: /review-sprint THJ-123
  → Launches senior-tech-lead-reviewer agent
  → Agent reviews code, provides feedback or approval
```

**Mode C (Designated reviewer):**
```
Developer: /implement THJ-123
  → Completes implementation
  → Linear status: In Progress → In Review
  → Linear webhook triggers
  → Bot posts in Discord: "@senior-dev-1 THJ-123 ready for review"

Senior Dev 1: /review-sprint THJ-123
  → Launches senior-tech-lead-reviewer agent
  → Agent reviews code, provides feedback or approval
```

**Switching modes:** Edit `integration/config/review-workflow.yml` and restart Discord bot.

## Configuration Files

All integration settings are stored in editable configuration files for easy adjustment:

```
integration/
├── config/
│   ├── discord-digest.yml          # Daily digest settings
│   ├── review-workflow.yml         # Review assignment logic
│   ├── user-preferences.json       # Per-user notification prefs
│   ├── linear-sync.yml            # Linear API settings
│   └── bot-commands.yml           # Discord bot command config
├── secrets/
│   ├── .env.local                 # API keys (gitignored)
│   └── linear-token.txt           # Linear API token (gitignored)
└── logs/
    ├── discord-bot.log            # Bot activity logs
    └── linear-sync.log            # Linear API sync logs
```

### Example: discord-digest.yml

```yaml
# Discord Daily Digest Configuration
schedule: "0 9 * * *"  # Cron format: 9am daily
timezone: "America/Los_Angeles"  # Adjust to your timezone

channel_id: "REPLACE_WITH_YOUR_CHANNEL_ID"
enabled: true

detail_level: "full"  # Options: minimal, summary, full

sections:
  in_progress: true
  completed_today: true
  in_review: true
  blockers: true
  new_feedback_drafts: true

immediate_alerts:
  enabled: true
  severity: ["critical", "blocker"]
  channel_id: null  # null = use main channel, or specify different channel

formatting:
  use_embeds: true  # Discord rich embeds vs plain text
  group_by: "status"  # Options: status, assignee, sprint
  show_avatars: true
  max_tasks_per_section: 10
```

### Example: linear-sync.yml

```yaml
# Linear Integration Configuration
linear:
  api_url: "https://api.linear.app/graphql"
  team_id: "REPLACE_WITH_YOUR_TEAM_ID"

  # Draft issue settings
  draft_label: "draft"
  researcher_feedback_label: "researcher-feedback"

  # Status mapping
  status_mapping:
    todo: "Todo"
    in_progress: "In Progress"
    in_review: "In Review"
    changes_requested: "Changes Requested"
    done: "Done"

  # Sprint issue template
  issue_template:
    description_prefix: |
      ## Acceptance Criteria
      {acceptance_criteria}

      ## Dependencies
      {dependencies}

      ## Technical Notes
      {technical_notes}

      ---
      *Generated by agentic-base sprint planner*

  # Sync settings
  sync:
    auto_update_sprint_md: true
    poll_interval_seconds: 60
    conflict_resolution: "linear_wins"  # Options: linear_wins, sprint_md_wins, manual
```

## Data Flow Diagrams

### Scenario 1: Researcher Feedback → Implementation

```
1. Researcher posts feedback in Discord
   "Login button is hard to find on mobile"
   ↓
2. Developer reacts with 📌
   ↓
3. Discord bot creates draft Linear issue THJ-150
   - Title: [Researcher Feedback] Login button visibility
   - Description: Includes Discord link, context, timestamp
   - Labels: researcher-feedback, ux, mobile
   - Status: Todo (Draft)
   ↓
4. Daily digest notifies team of new draft feedback
   ↓
5. Developer reviews drafts, publishes THJ-150 to sprint
   ↓
6. Developer assigns THJ-150 to themselves
   - Linear status: Todo → In Progress
   ↓
7. Developer runs: /implement THJ-150
   - Agent reads Linear API
   - Agent sees original Discord feedback context
   - Agent implements fix
   - Agent updates Linear: In Progress → In Review
   - Agent writes docs/a2a/reviewer.md
   ↓
8. Developer runs: /review-sprint THJ-150
   - Reviewer agent approves
   - Linear status: In Review → Done
   - sprint.md marked with ✅
   ↓
9. Vercel preview deployed
   ↓
10. Bot notifies researcher (per their preferences)
    "✅ Your feedback on login button visibility has been addressed!
     Preview: https://myapp-abc123.vercel.app"
    ↓
11. Researcher tests preview, confirms fix or provides more feedback
```

### Scenario 2: Concurrent Development (2 developers)

```
Developer A:
  1. Assigns THJ-123 (Auth flow) to self in Linear
  2. Runs /implement THJ-123
  3. Agent updates Linear: In Progress
  4. Works on implementation...

Developer B:
  1. Checks /show-sprint in Discord
     - Sees THJ-123 is "In Progress by @alice"
  2. Assigns THJ-125 (API schema) to self in Linear
  3. Runs /implement THJ-125
  4. Agent checks Linear API:
     - THJ-125 assigned to Bob ✓
     - No conflicts
  5. Agent updates Linear: In Progress
  6. Works on implementation...

Daily Digest (9am):
  📊 Daily Sprint Update
  🚀 In Progress (2 tasks)
  • THJ-123: Auth flow - @alice (6h ago)
  • THJ-125: API schema - @bob (2h ago)

Developer A:
  1. Completes THJ-123
  2. Linear: In Progress → In Review
  3. Runs /review-sprint THJ-123
  4. Reviewer approves
  5. Linear: In Review → Done ✅
  6. Creates GitHub PR, merges

Developer B:
  1. Completes THJ-125
  2. Linear: In Progress → In Review
  3. Runs /review-sprint THJ-125
  4. Reviewer requests changes
  5. Linear: In Review → Changes Requested
  6. Reads docs/a2a/engineer-feedback.md
  7. Runs /implement THJ-125 again (addresses feedback)
  8. Linear: Changes Requested → In Review
  9. Runs /review-sprint THJ-125
  10. Reviewer approves
  11. Linear: In Review → Done ✅
```

## Security & Permissions

### API Access

**Linear API:**
- **Scope:** Read and write access to issues, comments, labels
- **Token storage:** `integration/secrets/.env.local` (gitignored)
- **Rotation:** Rotate token every 90 days (documented in runbook)

**Discord Bot:**
- **Permissions:** Read messages, send messages, add reactions, manage threads
- **Token storage:** `integration/secrets/.env.local` (gitignored)
- **Scopes:** `bot`, `applications.commands`

**GitHub API:**
- **Scope:** Read repos, read/write issues and PRs
- **Token:** Use GitHub App or personal access token
- **Storage:** `integration/secrets/.env.local` (gitignored)

**Vercel API:**
- **Scope:** Read deployments, read projects
- **Token storage:** `.claude/settings.local.json` (already configured)

### Access Control

**Discord Bot Permissions:**
- All team members can use query commands (`/show-sprint`, `/task`)
- Only developers can capture feedback (📌 reaction requires specific role)
- Only designated reviewers can run `/review-sprint` (if Mode C)
- Bot maintains audit log of all actions

**Linear Access:**
- Agents use service account token (not individual user tokens)
- Service account has standard member permissions (create/edit issues)
- Cannot delete issues or modify team settings

**Configuration Files:**
- `integration/config/*.yml` - Committed to git, team-editable
- `integration/secrets/*` - Gitignored, contain API tokens
- `integration/config/user-preferences.json` - Committed but user-modifiable via bot

### Audit Trail

All integration actions logged to `integration/logs/`:

```
[2025-12-07 09:00:01] Discord bot: Daily digest posted to #sprint-updates
[2025-12-07 10:23:45] Feedback captured: Message ID 123456 → Linear draft THJ-150
[2025-12-07 11:15:22] Developer @alice: /implement THJ-123 started
[2025-12-07 11:15:23] Linear API: THJ-123 status updated In Progress
[2025-12-07 13:42:10] Developer @alice: /review-sprint THJ-123 completed
[2025-12-07 13:42:11] Linear API: THJ-123 status updated Done
[2025-12-07 13:42:12] sprint.md: THJ-123 marked ✅
```

## Scalability & Performance

### Current Design (2-4 developers)

- **Discord bot:** Single instance, handles <100 messages/day
- **Linear API:** ~50 requests/hour (well within rate limits)
- **Daily digest:** One cron job, completes in <10 seconds
- **User preferences:** JSON file adequate for <10 users

### Future Scaling (10+ developers)

If team grows beyond 10 developers:

**Recommendations:**
1. **Database:** Migrate user preferences from JSON to PostgreSQL or SQLite
2. **Queue system:** Add job queue (Bull, BullMQ) for background tasks
3. **Caching:** Cache Linear API responses (Redis) to reduce API calls
4. **Multiple digests:** Split into team-specific digests if >20 active tasks
5. **Bot sharding:** Use Discord bot sharding if >1000 server members

### Rate Limits

**Linear API:**
- **Limit:** 2000 requests/hour per API token
- **Current usage:** ~50 requests/hour (2.5% of limit)
- **Monitoring:** Log API usage, alert if >50% of limit

**Discord API:**
- **Limit:** 50 requests/second per bot
- **Current usage:** <1 request/second average
- **Burst protection:** Built into Discord.js library

## Disaster Recovery

### Backup Strategy

**Configuration backups:**
- All config files in git (already backed up)
- User preferences JSON committed to git (except secrets)

**Data loss scenarios:**

1. **Linear data loss:** Not applicable (Linear is external SaaS)
2. **Discord message loss:** Use Discord's message history export
3. **Local files (`docs/`) loss:** Recover from git history
4. **Bot token compromise:** Rotate immediately, update `.env.local`

### Recovery Procedures

**Discord bot down:**
1. Check logs: `integration/logs/discord-bot.log`
2. Verify token validity: `curl -H "Authorization: Bot TOKEN" https://discord.com/api/users/@me`
3. Restart bot: `npm run bot:start`
4. If persistent: Check Discord API status page

**Linear API errors:**
1. Check Linear API status: https://status.linear.app
2. Verify token: Test with GraphQL playground
3. Check rate limits in logs
4. Fallback: Manual Linear operations until resolved

**Sprint.md out of sync with Linear:**
1. Run sync command: `npm run sync:linear-to-sprint`
2. Or manually update sprint.md with Linear IDs
3. Worst case: Regenerate sprint.md from Linear data

## Integration Testing Strategy

### Pre-Deployment Testing

**Test Scenarios:**

1. **Feedback Capture:**
   - Post message in Discord, react with 📌
   - Verify draft Linear issue created
   - Verify Discord reply confirmation
   - Check issue contains full context (link, timestamp, URLs)

2. **Sprint Planning:**
   - Run `/sprint-plan`
   - Verify `docs/sprint.md` generated
   - Verify draft Linear issues created
   - Verify Linear IDs embedded in sprint.md

3. **Implementation Flow:**
   - Assign Linear issue to self
   - Run `/implement THJ-XXX`
   - Verify agent reads Linear API
   - Verify Linear status updates
   - Verify implementation report generated

4. **Review Flow:**
   - Run `/review-sprint THJ-XXX`
   - Verify reviewer agent provides feedback
   - Verify Linear status updates
   - Verify sprint.md ✅ when approved

5. **Discord Commands:**
   - Test `/show-sprint`
   - Test `/preview THJ-XXX`
   - Test `/doc prd`
   - Test `/my-notifications`
   - Test natural language queries

6. **Daily Digest:**
   - Trigger manually (not wait for cron)
   - Verify correct format
   - Verify all sections populated
   - Verify configurable settings work

7. **Concurrent Development:**
   - Two developers implement different tasks simultaneously
   - Verify no race conditions on Linear API
   - Verify status updates don't conflict
   - Verify both implementations complete successfully

### Post-Deployment Monitoring

**Health Checks:**
- Discord bot uptime (ping endpoint)
- Linear API connectivity (periodic test query)
- Daily digest posted successfully (verify in channel)
- Error rate in logs (<1% of operations)

**Alerts:**
- Discord bot offline >5 minutes
- Linear API errors >10 in 1 hour
- Daily digest failed to post
- User notification delivery failures

## Migration Path & Rollout

See `docs/adoption-plan.md` for detailed rollout strategy.

**High-level phases:**
1. **Week 1:** Set up infrastructure (Discord bot, Linear API, configs)
2. **Week 2:** Test with 1 developer on pilot sprint
3. **Week 3:** Expand to full 2-4 developer team
4. **Week 4:** Onboard researcher, enable feedback capture
5. **Ongoing:** Iterate on configs based on team feedback

## Appendix

### Technology Stack

**Discord Bot:**
- **Language:** Node.js (TypeScript)
- **Library:** Discord.js v14
- **Runtime:** Node.js 18+ LTS

**Linear Integration:**
- **API:** Linear GraphQL API
- **Client:** @linear/sdk (official TypeScript SDK)

**Cron Jobs:**
- **Scheduler:** node-cron or system cron
- **Deployment:** Running on VPS or GitHub Actions

**Agents:**
- **Framework:** Agentic-base (existing)
- **Modifications:** Updated prompts in `.claude/agents/`

### API Endpoints Used

**Linear GraphQL API:**
```graphql
# Create draft issue
mutation CreateIssue($input: IssueCreateInput!) {
  issueCreate(input: $input) {
    issue { id identifier title description state { name } }
  }
}

# Read issue details
query GetIssue($id: String!) {
  issue(id: $id) {
    id identifier title description
    state { name }
    assignee { name email }
    labels { nodes { name } }
    comments { nodes { body user { name } createdAt } }
  }
}

# Update issue status
mutation UpdateIssue($id: String!, $input: IssueUpdateInput!) {
  issueUpdate(id: $id, input: $input) {
    issue { id state { name } }
  }
}
```

**Discord API (via Discord.js):**
- `client.on('messageReactionAdd')` - Detect 📌 reactions
- `client.on('messageCreate')` - Detect commands and natural language
- `interaction.reply()` - Respond to slash commands
- `channel.send()` - Post daily digests

### Configuration Schema

Full JSON schemas available in `integration/schemas/`:
- `discord-digest.schema.json`
- `review-workflow.schema.json`
- `user-preferences.schema.json`
- `linear-sync.schema.json`

### Glossary

- **A2A:** Agent-to-Agent communication (feedback loop between engineer and reviewer agents)
- **Draft issue:** Linear issue created by automation but requiring human review before becoming active
- **Feedback capture:** Process of converting Discord messages to Linear issues via 📌 reaction
- **Hivemind methodology:** Design principle prioritizing context continuity and minimal friction across tools
- **Linear-first:** Architecture where Linear is the single source of truth for task state
- **Sprint.md:** Primary sprint planning document in `docs/sprint.md`

---

**Next Steps:**
1. Review this architecture document with the team
2. Proceed to `docs/tool-setup.md` for implementation instructions
3. Proceed to `docs/team-playbook.md` for team usage guidelines
