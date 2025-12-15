# Integration Implementation Handover

**From**: context-engineering-expert agent (Phase 0)
**To**: devops-crypto-architect agent (Phase 0.5)
**Date**: 2025-12-08
**Status**: Ready for Implementation

---

## Executive Summary

The context-engineering-expert has completed Phase 0 (organizational integration design) with comprehensive architecture documentation located in `docs/hivemind/`. This handover provides the DevOps architect with everything needed to implement the Discord bot, Linear webhooks, sync scripts, and integration infrastructure.

**Your Mission**: Implement the integration layer based on the design specifications, creating a production-ready system in the `integration/` directory.

---

## Integration Architecture Location

All integration design documentation is in `docs/hivemind/`:

### Primary Documents (Must Read)
1. **`docs/hivemind/integration-architecture.md`** (982 lines)
   - Complete system architecture and data flow diagrams
   - Component specifications for all integration points
   - Security requirements and patterns
   - **Read sections**: Executive Summary, Architecture Overview, Component Design

2. **`docs/hivemind/tool-setup.md`** (1,371 lines)
   - API configuration requirements (Discord bot, Linear API)
   - Webhook setup specifications
   - Environment variable requirements
   - Testing procedures
   - **Read sections**: Prerequisites, Discord Bot Setup, Linear Integration, Secrets Management

3. **`docs/hivemind/team-playbook.md`** (912 lines)
   - How the team will use the integrated system
   - Command specifications and workflows
   - User interaction patterns
   - **Read sections**: Workflow Overview, Commands Reference

### Supporting Documents
4. **`docs/hivemind/INTEGRATION_SUMMARY.md`** (414 lines)
   - High-level summary of what was designed
   - Key design decisions and rationale
   - Implementation timeline and success criteria

5. **`docs/hivemind/adoption-plan.md`** (709 lines)
   - Phased rollout strategy (4-6 weeks)
   - Testing and validation requirements

6. **`docs/a2a/integration-context.md.template`** (274 lines)
   - Template for agent integration context
   - **Note**: This template should be filled out after implementation

---

## What Was Designed (Phase 0 Output)

### Integration Type
**Hivemind Laboratory Methodology** - A workflow integration approach that:
- Preserves natural team workflows (Discord → Docs → Linear)
- Minimal friction for non-technical team members
- Linear as single source of truth for task management
- Context preservation across all platforms

### Team Structure
- **Size**: 2-4 developers working concurrently
- **Roles**:
  - Developers (code-literate, use Linear + GitHub + Discord)
  - Researcher/Ethnographer (non-technical, uses Discord + Docs + Vercel previews)

### Key Integration Points

#### 1. Discord Bot
- **Primary Functions**:
  - Feedback capture (📌 emoji reaction → Linear draft issue)
  - Daily sprint digest (automated status summary every morning)
  - Query commands (`/show-sprint`, `/preview`, `/doc`, `/task`)
  - Natural language bot interactions (keyword-based)

#### 2. Linear Integration
- **Primary Functions**:
  - Linear is single source of truth for sprint tasks
  - Sprint planner creates Linear issues after generating sprint.md
  - Agents read from Linear API for task details (via Linear issue IDs)
  - Status updates sync automatically between agents and Linear

#### 3. GitHub Integration
- **Primary Functions**:
  - Standard git operations via GitHub MCP server (already available)
  - PR links posted to Discord and Linear
  - Deployment tracking

#### 4. Vercel Integration
- **Primary Functions**:
  - Preview deployment URLs posted to Discord
  - Deployment status notifications
  - Preview environment testing workflow

---

## Implementation Scope

Based on the architecture documents, you need to implement:

### Core Components (Must Implement)

#### 1. Discord Bot Entry Point
**Location**: `integration/src/bot.ts`

**Requirements** (from architecture):
- Initialize Discord.js client with proper intents
- Event listeners: `messageCreate`, `messageReactionAdd`, `ready`
- Graceful shutdown handling
- Reconnection logic for network issues
- Rate limit handling

**Configuration** (from tool-setup.md):
- Discord bot token (from secrets/.env.local)
- Guild ID (server ID)
- Logging setup

#### 2. Feedback Capture Handler
**Location**: `integration/src/handlers/feedbackCapture.ts`

**Requirements** (from architecture):
- Listen for 📌 emoji reactions on messages
- Extract full message context:
  - Message content (text)
  - Discord thread link (for traceability)
  - Timestamp, author, channel info
  - Any attachments or URLs
- Create draft Linear issue with context
- Reply to user with confirmation message
- Handle rate limiting and errors gracefully

**Linear Issue Format** (from architecture):
```markdown
**Feedback from Discord**

[Original message text]

**Context:**
- Author: @username
- Posted: YYYY-MM-DD HH:MM
- Discord: [Link to message](https://discord.com/...)
- Attachments: [if any]

---
*Captured via 📌 reaction by @developer*
```

#### 3. Linear Service Integration
**Location**: `integration/src/services/linearService.ts`

**Requirements** (from architecture):
- GraphQL API wrapper for Linear
- Functions needed:
  - `createDraftIssue(title, description, teamId)` - Create draft issue
  - `getTeamIssues(teamId, status?)` - Query sprint tasks
  - `getIssueDetails(issueId)` - Get full issue context
  - `updateIssueStatus(issueId, statusId)` - Update status
  - `getCurrentSprint(teamId)` - Get active sprint
- Rate limiting (Linear: 2000 req/hour = ~33/min)
- Error handling and retry logic
- Caching for frequently accessed data

**Configuration** (from tool-setup.md):
- Linear API key (Personal API token)
- Team ID (Linear team UUID)
- Status mapping (Todo, In Progress, In Review, Done)

#### 4. Daily Digest Cron Job
**Location**: `integration/src/cron/dailyDigest.ts`

**Requirements** (from architecture):
- Query Linear API for sprint status
- Aggregate tasks by status (in progress, completed, blocked, pending)
- Format digest message with:
  - Sprint overview
  - Tasks in progress (with assignees)
  - Recently completed tasks
  - Blocked or at-risk tasks
  - Today's priorities
- Post to configured Discord channel
- Schedule based on config (default: 9am daily)

**Format** (from architecture):
```markdown
📊 **Daily Sprint Digest** - December 8, 2025

**In Progress** (3 tasks)
- [THJ-45] Implement auth flow - @alice
- [THJ-46] Fix navigation bug - @bob
- [THJ-47] Update docs - @charlie

**Completed Yesterday** (2 tasks)
- [THJ-43] Add login page ✅
- [THJ-44] Setup CI/CD ✅

**Blocked** (1 task)
- [THJ-42] Deploy to staging ⚠️ (waiting on infra)

**Sprint Progress**: 12/20 tasks complete (60%)
```

#### 5. Discord Command Handlers
**Location**: `integration/src/handlers/commands.ts`

**Requirements** (from team-playbook.md):

**Core Commands** (implement these):
- `/show-sprint` - Display current sprint status (queries Linear)
- `/doc <type>` - Fetch project documentation (reads docs/)
- `/my-tasks` - Show user's assigned Linear tasks
- `/preview <issue-id>` - Get Vercel preview URL for issue

**Optional Commands** (stubs acceptable):
- `/my-notifications` - User notification preferences
- `/task <issue-id>` - Get task details from Linear

**Command Routing**:
- Parse message for command prefix (e.g., `/`)
- Route to appropriate handler function
- Error handling and user feedback
- Rate limiting per user

#### 6. Configuration System
**Location**: `integration/config/`

**Files to Create** (from architecture):

**`discord-digest.yml`**:
```yaml
schedule: "0 9 * * *"  # Cron format (9am daily)
channel_id: "DISCORD_CHANNEL_ID"  # To be configured
enabled: true
detail_level: "full"  # minimal | summary | full
timezone: "UTC"
```

**`linear-sync.yml`**:
```yaml
linear:
  team_id: "LINEAR_TEAM_ID"  # To be configured
  status_mapping:
    todo: "Todo"
    in_progress: "In Progress"
    in_review: "In Review"
    changes_requested: "Changes Requested"
    done: "Done"
  rate_limit:
    requests_per_minute: 33  # Conservative limit
```

**`bot-commands.yml`**:
```yaml
commands:
  show-sprint:
    enabled: true
    description: "Show current sprint status"
    permissions: ["@everyone"]
  doc:
    enabled: true
    description: "Fetch project documentation"
    permissions: ["@everyone"]
  my-tasks:
    enabled: true
    description: "Show your assigned Linear tasks"
    permissions: ["@everyone"]
  preview:
    enabled: true
    description: "Get Vercel preview URL"
    permissions: ["@developers"]
```

**`user-preferences.json`** (default structure):
```json
{
  "users": {},
  "defaults": {
    "daily_digest": true,
    "feedback_updates": true,
    "vercel_previews": true
  }
}
```

#### 7. Secrets Management
**Location**: `integration/secrets/`

**`.env.local.example`** (from tool-setup.md):
```bash
# Discord Configuration
DISCORD_BOT_TOKEN=your_discord_bot_token_here
DISCORD_GUILD_ID=your_guild_id_here
DISCORD_DIGEST_CHANNEL_ID=your_channel_id_here

# Linear Configuration
LINEAR_API_KEY=your_linear_api_key_here
LINEAR_TEAM_ID=your_team_id_here
LINEAR_WEBHOOK_SECRET=your_webhook_secret_here

# GitHub Configuration (optional, uses MCP)
GITHUB_TOKEN=your_github_token_here

# Vercel Configuration (optional, uses MCP)
VERCEL_TOKEN=your_vercel_token_here

# Application Configuration
NODE_ENV=development
LOG_LEVEL=info
PORT=3000  # Health check endpoint
```

**`.gitignore`** updates (critical):
```
# Secrets (CRITICAL - NEVER COMMIT)
secrets/
.env
.env.*
!.env.local.example
*.key
*.pem

# Logs
logs/
*.log

# Dependencies
node_modules/

# Build
dist/
build/
```

#### 8. Logging and Monitoring
**Location**: `integration/src/utils/logger.ts`

**Requirements** (from architecture):
- Structured logging (JSON format for parsing)
- Log levels: debug, info, warn, error
- Log to console (stdout) and file (logs/discord-bot.log)
- Redact sensitive information (tokens, secrets)
- Include context (timestamp, component, request ID)

**Health Check Endpoint**:
- HTTP endpoint on port 3000 (configurable)
- `GET /health` returns 200 OK if healthy, 503 if unhealthy
- Checks:
  - Discord connection status
  - Linear API accessibility
  - Configuration validity

#### 9. Deployment Infrastructure

**Docker Setup** (from architecture):
**`Dockerfile`**:
```dockerfile
FROM node:18-alpine

WORKDIR /app

# Install dependencies
COPY package*.json ./
RUN npm ci --only=production

# Copy source
COPY . .

# Build TypeScript
RUN npm run build

# Non-root user
USER node

EXPOSE 3000

CMD ["node", "dist/bot.js"]
```

**`docker-compose.yml`** (for local dev):
```yaml
version: '3.8'

services:
  bot:
    build: .
    env_file:
      - ./secrets/.env.local
    volumes:
      - ./logs:/app/logs
      - ./config:/app/config:ro
    restart: unless-stopped
    ports:
      - "3000:3000"
```

**Alternative: PM2 Configuration** (from architecture):
**`ecosystem.config.js`**:
```javascript
module.exports = {
  apps: [{
    name: 'agentic-base-bot',
    script: 'dist/bot.js',
    instances: 1,
    autorestart: true,
    watch: false,
    max_memory_restart: '500M',
    env_file: './secrets/.env.local',
    error_file: './logs/error.log',
    out_file: './logs/out.log',
    log_date_format: 'YYYY-MM-DD HH:mm:ss Z'
  }]
};
```

---

## Stub Components (Optional, Low Priority)

These can be implemented as stubs with TODO comments:

1. **Natural Language Handler** (`integration/src/handlers/naturalLanguage.ts`)
   - Keyword-based for now, full NLP later
   - Stub: Detect "status", "sprint", "preview" keywords

2. **GitHub Service** (`integration/src/services/githubService.ts`)
   - Stub: Use GitHub MCP server directly (already available)
   - No custom wrapper needed initially

3. **Vercel Service** (`integration/src/services/vercelService.ts`)
   - Stub: Use Vercel MCP server directly (already available)
   - Function for preview URL lookup (can be added later)

4. **Webhook Handlers** (`integration/src/webhooks/`)
   - Linear webhook: Implement signature verification, stub event handlers
   - GitHub webhook: Stub (use GitHub MCP)
   - Vercel webhook: Stub (use Vercel MCP)

---

## Technology Stack (Specified in Architecture)

**Runtime**: Node.js 18+ LTS
**Language**: TypeScript (strict mode)
**Discord Library**: discord.js (latest stable)
**Linear API**: GraphQL (custom wrapper using `node-fetch` or `axios`)
**Scheduler**: node-cron (for daily digest)
**Logging**: Winston or Pino (structured JSON logging)
**Testing**: Jest (unit and integration tests)
**Deployment**: Docker + docker-compose (primary), PM2 (alternative)

---

## Security Requirements (from Architecture)

### Critical Security Controls

1. **Webhook Signature Verification**:
   - Linear webhooks: HMAC SHA256 verification
   - Verify signature before processing any webhook payload

2. **Secrets Management**:
   - NEVER commit secrets to git
   - Use environment variables (.env.local, gitignored)
   - Provide .env.local.example template
   - Consider secrets rotation schedule (quarterly)

3. **Rate Limiting**:
   - Linear API: 33 requests/minute (conservative)
   - Discord API: Respect rate limits (built into discord.js)
   - Implement exponential backoff for retries

4. **Input Validation**:
   - Sanitize all user input before processing
   - Validate Discord message content
   - Validate Linear API responses

5. **Error Handling**:
   - Never expose secrets in error messages or logs
   - Log errors with context but redact sensitive data
   - Graceful degradation (bot continues running on errors)

6. **Audit Logging**:
   - Log all integration actions (feedback capture, status updates)
   - Log authentication attempts
   - Log configuration changes

---

## Testing Requirements (from Architecture)

### Manual Testing Checklist

Before considering implementation complete, test:

- [ ] Discord bot connects successfully
- [ ] Bot responds to 📌 reaction (creates Linear draft issue)
- [ ] Bot confirms feedback capture in Discord
- [ ] Daily digest posts at scheduled time
- [ ] `/show-sprint` command works (queries Linear)
- [ ] `/doc` command fetches documentation
- [ ] `/my-tasks` command shows user's Linear tasks
- [ ] Logs are written correctly (no secrets leaked)
- [ ] Health check endpoint responds (GET /health)
- [ ] Error handling works (test with invalid inputs)
- [ ] Rate limiting prevents API abuse
- [ ] Bot reconnects after network interruption

### Integration Testing

Test end-to-end workflows:

1. **Feedback Capture Flow**:
   - Post test message in Discord
   - React with 📌 emoji
   - Verify Linear draft issue created with full context
   - Check confirmation message posted in Discord

2. **Daily Digest Flow**:
   - Manually trigger digest (or wait for scheduled time)
   - Verify it queries Linear for sprint tasks
   - Check digest posted to configured Discord channel
   - Validate formatting and completeness

3. **Command Flow**:
   - Execute `/show-sprint` in Discord
   - Verify bot queries Linear API
   - Check response formatting
   - Test error cases (no active sprint, API failure)

---

## Documentation Requirements

### Files to Create

1. **`integration/README.md`** - Integration guide
   - Quick start instructions
   - Configuration reference
   - Development guide
   - Architecture overview
   - Troubleshooting guide

2. **`integration/DEPLOYMENT.md`** - Deployment guide
   - Prerequisites (Node.js, Discord bot setup, API keys)
   - Installation steps
   - Configuration guide
   - Secrets setup
   - Deployment options (Docker, PM2, systemd)
   - Monitoring and logging
   - Troubleshooting

3. **`docs/deployment/runbooks/integration-operations.md`** - Operational runbook
   - Starting and stopping the bot
   - Checking health and logs
   - Rotating API tokens
   - Responding to integration failures
   - Debugging webhook issues
   - Rate limit handling
   - Scaling considerations

4. **`docs/deployment/integration-layer-handover.md`** - Handover document
   - What was implemented (components list)
   - How it's deployed (method, location)
   - How to operate it (start, stop, monitor)
   - How to troubleshoot (common issues, logs, health checks)
   - Security considerations (secrets, API limits, permissions)
   - Future improvements and known limitations
   - Team training requirements

5. **`docs/a2a/integration-context.md`** - Agent integration context (fill template)
   - Use template at `docs/a2a/integration-context.md.template`
   - Fill in with actual implementation details
   - Document how downstream agents should use this integration

---

## Success Criteria (from Adoption Plan)

Your implementation is successful when:

### Phase 1: Pilot Sprint (Week 1-2)
- ✅ Bot runs without crashes for 48+ hours
- ✅ Feedback capture works (📌 → Linear draft issue)
- ✅ Developer completes 2+ tasks using `/implement THJ-123` workflow
- ✅ Daily digest posts successfully every day
- ✅ Commands respond correctly (`/show-sprint`, `/doc`)

### Technical Quality
- ✅ All security controls implemented (secrets, rate limiting, validation)
- ✅ Comprehensive logging (no secrets leaked, full audit trail)
- ✅ Error handling prevents crashes
- ✅ Health check endpoint operational
- ✅ Documentation complete (README, DEPLOYMENT, runbooks)
- ✅ Tests passing (manual integration tests)

---

## Known Limitations and Future Enhancements

### Current Scope (MVP)
- Discord bot with core commands
- Linear integration (feedback capture, sprint queries)
- Daily digest automation
- Basic monitoring (logs, health checks)

### Future Enhancements (Out of Scope for Phase 0.5)
- Full natural language processing (currently keyword-based)
- Advanced webhook handlers (Linear, GitHub, Vercel event routing)
- User notification preference UI (config exists, needs Discord commands)
- GitHub/Vercel deep integrations (use MCP for now)
- Multi-server Discord support (single server for MVP)
- Advanced analytics and metrics

---

## Integration with Agentic-Base Agents

### Agent Modifications (from Architecture)

The following agentic-base agents will need updates to work with Linear integration. **This is documented but NOT your responsibility** - the updates will be made by the agent owners:

1. **sprint-planner**: Create Linear issues after generating sprint.md
2. **sprint-task-implementer**: Accept Linear IDs (`/implement THJ-123`), read from Linear API
3. **senior-tech-lead-reviewer**: Update Linear statuses after review

These modifications are detailed in `docs/hivemind/integration-architecture.md` section "Agent Integration Points".

---

## Configuration Values to Request from User

During implementation, you'll need these values (they're not in the architecture docs):

### Discord Configuration
- [ ] Discord bot token (from Discord Developer Portal)
- [ ] Discord guild ID (server ID)
- [ ] Discord digest channel ID (where to post daily digest)

### Linear Configuration
- [ ] Linear API key (Personal API token)
- [ ] Linear team ID (team UUID)
- [ ] Linear webhook secret (for webhook signature verification)

### Optional Configuration
- [ ] GitHub token (if not using MCP)
- [ ] Vercel token (if not using MCP)

**Note**: You can provide instructions for obtaining these values in DEPLOYMENT.md, referencing `docs/hivemind/tool-setup.md`.

---

## Reference Documentation

### Must Read (in order)
1. `docs/hivemind/integration-architecture.md` - System design (read first)
2. `docs/hivemind/tool-setup.md` - API setup and configuration
3. `docs/hivemind/team-playbook.md` - Usage workflows
4. `docs/hivemind/INTEGRATION_SUMMARY.md` - Quick reference

### Supporting References
5. `docs/hivemind/adoption-plan.md` - Rollout strategy and testing
6. `docs/a2a/integration-context.md.template` - Template to fill

### Existing Integration Code (Partial)
- `integration/README.md` - May have skeleton structure
- `integration/` directory - May have partial implementation

**Note**: The integration directory may have partial or stub code from Phase 0. Review and complete/replace as needed based on the architecture specifications.

---

## Deployment Targets

### Primary Target: Docker + docker-compose
- Easy local development
- Reproducible environments
- Simple deployment to VPS/cloud

### Alternative: PM2
- If Docker not preferred by team
- Good for simple VPS deployments
- Auto-restart and log management

### Future: Kubernetes
- Not needed for 2-4 developers
- Consider if scaling beyond 10+ developers

---

## Questions to Clarify Before Implementation

If you encounter ambiguities during implementation, refer back to the architecture documents. If still unclear:

1. **Technology choices**: Prefer technologies specified in architecture (Node.js, discord.js, TypeScript)
2. **Security patterns**: Always err on side of more security (verify, validate, log)
3. **Feature scope**: Implement core features fully, stub optional features with TODOs
4. **Configuration**: Make everything configurable (YAML files, not hardcoded)

---

## Handover Checklist

Before marking Phase 0.5 complete, ensure:

- [ ] All core components implemented
- [ ] Configuration files created and documented
- [ ] Secrets management setup (.env.local.example, .gitignore)
- [ ] Deployment infrastructure created (Dockerfile, docker-compose.yml)
- [ ] Logging and monitoring operational
- [ ] Health check endpoint working
- [ ] Manual integration tests passing
- [ ] Documentation complete (README, DEPLOYMENT, runbooks)
- [ ] Agent integration context filled (`docs/a2a/integration-context.md`)
- [ ] Handover document created (`docs/deployment/integration-layer-handover.md`)

---

## Final Notes

**Integration Philosophy**: This integration was designed with the Hivemind Laboratory methodology in mind:

- **Habitual over forced**: Team uses naturally, not mandated
- **Minimal friction**: Researcher posts feedback normally, no special format
- **Flexible configuration**: Easy to adjust as team learns what works
- **Context preservation**: Discord → Linear → Agents with full traceability
- **Async-first**: Anyone can pick up where things left off

**Your Implementation Should Embody These Principles:**
- Simple, clear code that team can maintain
- Comprehensive logging for debugging and accountability
- Graceful error handling (bot keeps running)
- Flexible configuration (no code changes for tweaks)

---

**This handover document was created by reviewing all Phase 0 deliverables and extracting implementation-specific requirements. All references point to actual documentation created by context-engineering-expert.**

**Ready to implement!** 🚀

---

**Generated**: 2025-12-08
**For**: `/implement-org-integration` command (Phase 0.5)
**Status**: Ready for DevOps Architect Implementation
