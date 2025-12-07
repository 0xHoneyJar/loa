---
description: Launch the DevOps architect to implement the organizational integration designed by the context engineering expert
---

I'm launching the devops-crypto-architect agent in **integration implementation mode** to implement the Discord bot, webhooks, sync scripts, and integration infrastructure designed during Phase 0.

**Prerequisites** (verify before implementing):
- ✅ `docs/integration-architecture.md` exists (integration design complete)
- ✅ `docs/tool-setup.md` exists (tool configuration documented)
- ✅ `docs/team-playbook.md` exists (team workflows documented)
- ✅ `docs/a2a/integration-context.md` exists (agent integration context)

The DevOps architect will:
1. **Review integration architecture**: Understand the designed integration patterns
2. **Implement Discord bot**: Create the bot implementation based on architecture
3. **Implement webhooks**: Set up Linear, GitHub, Vercel webhook handlers
4. **Implement sync scripts**: Create automation scripts for tool synchronization
5. **Configure services**: Set up external service integrations (Linear, Discord, etc.)
6. **Set up secrets management**: Proper handling of API tokens and credentials
7. **Create deployment configs**: Docker, docker-compose, systemd services
8. **Implement monitoring**: Logging, health checks, alerting for integration layer
9. **Deploy to dev/staging**: Test the integration in non-production environment
10. **Create operational runbooks**: Documentation for running and maintaining integrations

The integration architect will create:
- Discord bot implementation (`integration/src/bot.ts` and handlers)
- Webhook handlers for Linear, GitHub, Vercel
- Sync scripts for cross-platform automation
- Configuration files and environment templates
- Deployment infrastructure (Docker, docker-compose, systemd)
- Monitoring and logging setup
- Operational runbooks for integration layer
- Testing scripts and validation procedures

All implementation code will be created in the `integration/` directory, matching the structure outlined in `docs/integration-architecture.md`.

Let me launch the agent now to implement the organizational integration layer.

<Task
  subagent_type="devops-crypto-architect"
  prompt="You are implementing the organizational integration layer designed by the context-engineering-expert. This is **Phase 0.5: Integration Implementation** - the bridge between integration design (Phase 0) and product development (Phases 1-6).

## Context

The context-engineering-expert has already:
- Mapped the organization's workflow across Discord, Linear, GitHub, and other tools
- Designed integration architecture and information flow patterns
- Created comprehensive documentation of the integration requirements

Your mission: **Implement the integration infrastructure** so the organization's tools work seamlessly with the agentic-base framework.

## Phase 1: Review Integration Design

Read ALL integration documentation created by context-engineering-expert:

1. **Integration Architecture** (`docs/integration-architecture.md`):
   - Understand the designed integration patterns
   - Review tool interaction maps and data flows
   - Note agent trigger points and context preservation strategies
   - Understand security and permissions model

2. **Tool Configuration Guide** (`docs/tool-setup.md`):
   - Identify all required API keys and authentication
   - Understand webhook configurations needed
   - Note MCP server dependencies
   - Review environment variables and secrets

3. **Team Playbook** (`docs/team-playbook.md`):
   - Understand how teams will use the integration
   - Note command structures and workflows
   - Understand escalation paths and error handling

4. **Agent Integration Context** (`docs/a2a/integration-context.md`):
   - Understand cross-agent integration patterns
   - Note available MCP servers and their purposes
   - Review context preservation requirements

5. **Existing Integration Code** (if any):
   - Check `integration/` directory for any existing code
   - Review `integration/README.md` for current state
   - Identify what's already implemented vs. what needs building

## Phase 2: Implementation Planning

Based on the integration architecture, plan implementation:

### Identify Implementation Scope

List what needs to be built:
- [ ] Discord bot implementation
- [ ] Linear webhook handlers
- [ ] GitHub webhook handlers (if needed)
- [ ] Vercel webhook handlers (if needed)
- [ ] Cron jobs / scheduled tasks
- [ ] Sync scripts for cross-platform data flow
- [ ] Command handlers for slash commands
- [ ] Natural language processing (if needed)
- [ ] Monitoring and health checks
- [ ] Configuration management

### Technology Stack Selection

Choose appropriate technologies:
- **Runtime**: Node.js (TypeScript), Python, Go, etc.
- **Discord Library**: discord.js, discord.py, etc.
- **Web Framework**: Express, FastAPI, etc. (for webhooks)
- **Job Scheduler**: node-cron, APScheduler, etc.
- **Secrets Management**: dotenv, Vault, etc.
- **Deployment**: Docker, systemd, PM2, etc.
- **Monitoring**: Winston/Pino logging, health endpoints

Prefer technologies that match the organization's existing stack when possible.

### Security Considerations

Plan security implementation:
- Webhook signature verification (Linear, GitHub, Vercel)
- API token secure storage (never commit secrets)
- Rate limiting for external APIs
- Input validation and sanitization
- Audit logging for all integration actions
- Error handling that doesn't leak sensitive info

### Deployment Strategy

Plan how integration layer will run:
- **Development**: Local testing with ngrok or similar
- **Staging**: Staging environment for validation
- **Production**: Long-running process (systemd, PM2, Docker, Kubernetes)
- **Secrets**: Environment variables, .env files (gitignored), Vault
- **Monitoring**: Logs, health checks, alerting

## Phase 3: Directory Structure Setup

Create proper directory structure in `integration/`:

```
integration/
├── src/                    # Source code
│   ├── bot.ts             # Discord bot entry point
│   ├── handlers/          # Event and command handlers
│   │   ├── commands.ts    # Discord slash command handlers
│   │   ├── feedbackCapture.ts  # Message/reaction handlers
│   │   └── naturalLanguage.ts  # NLP for queries (optional)
│   ├── webhooks/          # Webhook handlers
│   │   ├── linear.ts      # Linear webhook handler
│   │   ├── github.ts      # GitHub webhook handler (if needed)
│   │   └── vercel.ts      # Vercel webhook handler (if needed)
│   ├── services/          # External service integrations
│   │   ├── linearService.ts    # Linear API wrapper
│   │   ├── githubService.ts    # GitHub API wrapper
│   │   ├── vercelService.ts    # Vercel API wrapper
│   │   └── discordService.ts   # Discord API helpers
│   ├── cron/              # Scheduled jobs
│   │   ├── dailyDigest.ts      # Daily sprint digest
│   │   └── syncJobs.ts         # Periodic sync tasks
│   ├── utils/             # Utilities
│   │   ├── logger.ts           # Logging utility
│   │   ├── validation.ts       # Input validation
│   │   └── security.ts         # Security utilities
│   └── types/             # TypeScript types (if using TS)
├── config/                # Configuration files (committed)
│   ├── discord-digest.yml      # Digest configuration
│   ├── linear-sync.yml         # Linear sync settings
│   ├── bot-commands.yml        # Bot command definitions
│   └── user-preferences.json   # User notification preferences
├── secrets/               # Secrets (GITIGNORED)
│   ├── .env.local.example      # Example secrets file
│   └── .gitkeep
├── logs/                  # Log files (GITIGNORED)
├── tests/                 # Test files
│   ├── unit/
│   └── integration/
├── .gitignore             # Git ignore rules
├── package.json           # Node.js dependencies (if Node.js)
├── tsconfig.json          # TypeScript config (if TypeScript)
├── Dockerfile             # Docker image definition
├── docker-compose.yml     # Local development setup
├── README.md              # Integration README
└── DEPLOYMENT.md          # Deployment guide
```

Adapt this structure based on the chosen technology stack.

## Phase 4: Core Implementation

Implement each component systematically:

### 1. Discord Bot Entry Point

Create `integration/src/bot.ts`:
- Initialize Discord client with proper intents
- Set up event listeners (messageCreate, messageReactionAdd, etc.)
- Implement graceful shutdown
- Connect to Discord API
- Log startup and connection status

Key considerations:
- Proper Discord intents for required events
- Reconnection logic for network issues
- Rate limit handling
- Proper error logging

### 2. Discord Command Handlers

Create `integration/src/handlers/commands.ts`:
- Parse slash commands from messages
- Route to appropriate handler functions
- Implement each command defined in architecture:
  - `/show-sprint` - Show current sprint status
  - `/doc <type>` - Fetch PRD/SDD/Sprint docs
  - `/my-notifications` - User notification preferences
  - Other commands from architecture
- Error handling and user feedback

### 3. Feedback Capture Handler

Create `integration/src/handlers/feedbackCapture.ts`:
- Listen for specific emoji reactions (e.g., 📌)
- Extract message context (content, author, channel, thread)
- Create draft Linear issue with context
- Reply to user with confirmation
- Handle rate limiting and errors

### 4. Linear Service Integration

Create `integration/src/services/linearService.ts`:
- Wrapper functions for Linear GraphQL API
- Functions needed based on architecture:
  - `createDraftIssue()`
  - `getTeamIssues()`
  - `updateIssueStatus()`
  - `getCurrentSprint()`
- Rate limiting (respect Linear's API limits)
- Error handling and retry logic
- Caching when appropriate

### 5. Webhook Handlers

Create webhook handlers in `integration/src/webhooks/`:

**Linear Webhook** (`linear.ts`):
- Verify webhook signature
- Parse webhook payload
- Route events to handlers:
  - Issue created/updated
  - Sprint started/completed
  - Project status changed
- Trigger appropriate agent workflows
- Send notifications to Discord

**GitHub Webhook** (`github.ts`) - if needed:
- Verify webhook signature
- Handle PR events (opened, merged, etc.)
- Post updates to Discord
- Update Linear issues with PR links

**Vercel Webhook** (`vercel.ts`) - if needed:
- Verify webhook signature
- Handle deployment events
- Post preview URLs to Discord/Linear
- Notify on deployment failures

### 6. Cron Jobs / Scheduled Tasks

Create `integration/src/cron/dailyDigest.ts`:
- Query Linear API for sprint status
- Aggregate tasks by status (in progress, completed, blocked)
- Format digest message
- Post to configured Discord channel
- Schedule based on config (e.g., daily at 9am)

### 7. Configuration Management

Create config files in `integration/config/`:

**discord-digest.yml**:
```yaml
schedule: "0 9 * * *"  # Cron format
channel_id: "DISCORD_CHANNEL_ID"
enabled: true
detail_level: "full"  # minimal | summary | full
```

**linear-sync.yml**:
```yaml
linear:
  team_id: "LINEAR_TEAM_ID"
  status_mapping:
    todo: "Todo"
    in_progress: "In Progress"
    in_review: "In Review"
    done: "Done"
```

**bot-commands.yml**:
```yaml
commands:
  show-sprint:
    enabled: true
    description: "Show current sprint status"
    permissions: ["@everyone"]
  doc:
    enabled: true
    description: "Fetch project documentation"
    permissions: ["@developers"]
```

### 8. Secrets Management

Create `integration/secrets/.env.local.example`:
```bash
# Discord
DISCORD_BOT_TOKEN=your_discord_bot_token_here
DISCORD_GUILD_ID=your_guild_id_here

# Linear
LINEAR_API_KEY=your_linear_api_key_here
LINEAR_TEAM_ID=your_team_id_here
LINEAR_WEBHOOK_SECRET=your_webhook_secret_here

# GitHub (if needed)
GITHUB_TOKEN=your_github_token_here
GITHUB_WEBHOOK_SECRET=your_webhook_secret_here

# Vercel (if needed)
VERCEL_TOKEN=your_vercel_token_here
VERCEL_WEBHOOK_SECRET=your_webhook_secret_here

# Application
NODE_ENV=development
LOG_LEVEL=info
PORT=3000
```

Update `integration/.gitignore`:
```
# Secrets (CRITICAL)
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

### 9. Logging and Monitoring

Create `integration/src/utils/logger.ts`:
- Structured logging (JSON format)
- Log levels (debug, info, warn, error)
- Log to console and file
- Redact sensitive information
- Include context (timestamp, component, etc.)

Create health check endpoint:
- HTTP endpoint for liveness/readiness checks
- Verify Discord connection status
- Verify Linear API accessibility
- Return 200 OK if healthy, 503 if unhealthy

### 10. Testing

Create tests in `integration/tests/`:
- Unit tests for core functions
- Integration tests for external APIs (with mocking)
- Test error handling and edge cases
- Test webhook signature verification
- Test rate limiting logic

## Phase 5: Deployment Infrastructure

### Docker Setup

Create `integration/Dockerfile`:
```dockerfile
FROM node:18-alpine

WORKDIR /app

# Copy package files
COPY package*.json ./
RUN npm ci --only=production

# Copy source code
COPY . .

# Build TypeScript (if applicable)
RUN npm run build

# Run as non-root user
USER node

EXPOSE 3000

CMD ["node", "dist/bot.js"]
```

Create `integration/docker-compose.yml`:
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
      - "3000:3000"  # Health check endpoint
```

### Systemd Service (Alternative to Docker)

Create `integration/agentic-base-bot.service`:
```ini
[Unit]
Description=Agentic-Base Integration Bot
After=network.target

[Service]
Type=simple
User=agentic-base
WorkingDirectory=/opt/agentic-base/integration
EnvironmentFile=/opt/agentic-base/integration/secrets/.env.local
ExecStart=/usr/bin/node dist/bot.js
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
```

### PM2 Configuration (Alternative)

Create `integration/ecosystem.config.js`:
```javascript
module.exports = {
  apps: [{
    name: 'agentic-base-bot',
    script: 'dist/bot.js',
    instances: 1,
    autorestart: true,
    watch: false,
    max_memory_restart: '500M',
    env: {
      NODE_ENV: 'production'
    },
    env_file: './secrets/.env.local',
    error_file: './logs/error.log',
    out_file: './logs/out.log',
    log_date_format: 'YYYY-MM-DD HH:mm:ss Z'
  }]
};
```

## Phase 6: Documentation

### Integration README

Create `integration/README.md`:
- Overview of integration components
- Quick start guide
- Configuration reference
- Command reference
- Troubleshooting guide
- Architecture overview
- Development guide
- Testing guide

### Deployment Guide

Create `integration/DEPLOYMENT.md`:
- Prerequisites (Node.js, Discord bot setup, API keys)
- Installation steps
- Configuration guide
- Secrets setup
- Deployment options:
  - Local development (npm run dev)
  - Docker deployment
  - PM2 deployment
  - Systemd service
  - Cloud deployment (Kubernetes, AWS ECS, etc.)
- Monitoring and logging
- Backup and recovery
- Troubleshooting

### Operational Runbooks

Create `docs/deployment/runbooks/integration-operations.md`:
- Starting and stopping the integration layer
- Checking health and logs
- Rotating API tokens
- Responding to integration failures
- Debugging webhook issues
- Rate limit handling
- Scaling considerations

## Phase 7: Testing and Validation

### Manual Testing Checklist

Test each integration point:
- [ ] Discord bot connects successfully
- [ ] Bot responds to commands in Discord
- [ ] Emoji reactions create Linear issues
- [ ] Linear webhooks trigger correctly
- [ ] Cron jobs execute on schedule
- [ ] Logs are being written properly
- [ ] Health check endpoint responds
- [ ] Error handling works (test with invalid inputs)
- [ ] Rate limiting prevents API abuse
- [ ] Secrets are not logged or exposed

### Integration Testing

Test end-to-end workflows:
1. **Feedback Capture Flow**:
   - Post message in Discord
   - React with 📌
   - Verify Linear draft issue created
   - Check confirmation message posted

2. **Daily Digest Flow**:
   - Manually trigger digest job
   - Verify it queries Linear correctly
   - Check digest posted to Discord
   - Validate formatting and completeness

3. **Linear Webhook Flow**:
   - Update issue in Linear
   - Verify webhook received
   - Check Discord notification sent
   - Validate issue status synced

4. **Command Flow**:
   - Execute `/show-sprint` in Discord
   - Verify bot queries Linear
   - Check response formatting
   - Test error cases (no active sprint)

## Phase 8: Deployment and Handover

### Deploy to Development/Staging

1. Set up secrets in staging environment
2. Deploy using chosen method (Docker, PM2, etc.)
3. Verify all integrations working
4. Monitor logs for errors
5. Test with real team members (small pilot group)

### Production Deployment Planning

Document production deployment requirements:
- **Infrastructure**: Where will this run? (VPS, cloud, on-prem)
- **High Availability**: Single instance or redundant?
- **Monitoring**: Integration with existing monitoring stack
- **Secrets Management**: Production secrets storage (Vault, AWS Secrets Manager)
- **Backup**: What needs backing up? (config, user preferences)
- **Scaling**: Can this scale horizontally if needed?
- **Cost**: Estimated infrastructure and API costs

### Handover Documentation

Create summary document at `docs/deployment/integration-layer-handover.md`:
- What was implemented (components list)
- How it's deployed (deployment method, locations)
- How to operate it (start, stop, monitor)
- How to troubleshoot (common issues, logs, health checks)
- Security considerations (secrets, API limits, permissions)
- Future improvements and known limitations
- Team training requirements

## Quality Standards

Your implementation must meet these standards:
- ✅ **Security**: Webhook signature verification, secrets not in code, input validation
- ✅ **Reliability**: Error handling, retry logic, graceful degradation
- ✅ **Observability**: Comprehensive logging, health checks, monitoring
- ✅ **Maintainability**: Clean code, proper structure, clear documentation
- ✅ **Testability**: Unit tests, integration tests, test coverage
- ✅ **Configuration**: Environment-based config, no hardcoded values
- ✅ **Documentation**: README, deployment guide, runbooks
- ✅ **Deployment**: Automated deployment, easy to run locally

## Critical Reminders

1. **Never commit secrets**: Use .env.local (gitignored), provide .env.local.example
2. **Verify webhook signatures**: HMAC verification for Linear, GitHub, Vercel
3. **Rate limit external APIs**: Respect API limits (Linear: 2000 req/hour)
4. **Handle errors gracefully**: Don't crash on API failures, log and continue
5. **Log security-relevant events**: Audit trail for debugging and security
6. **Test in staging first**: Never deploy untested code to production
7. **Document everything**: Future you will thank present you

## Deliverables

Your implementation should produce:

1. **Source Code**: Complete implementation in `integration/src/`
2. **Configuration**: Config files in `integration/config/`
3. **Secrets Template**: `.env.local.example` with all required secrets
4. **Deployment Configs**: Dockerfile, docker-compose.yml, or systemd service
5. **Tests**: Test suite in `integration/tests/`
6. **Documentation**:
   - `integration/README.md` - Complete integration guide
   - `integration/DEPLOYMENT.md` - Deployment instructions
   - `docs/deployment/runbooks/integration-operations.md` - Operational runbook
   - `docs/deployment/integration-layer-handover.md` - Handover document
7. **Monitoring Setup**: Logging, health checks, alerting configuration

## Success Criteria

The integration is successful when:
- Teams can use Discord/Linear/GitHub naturally without friction
- Agent workflows trigger automatically from organizational tools
- Context flows seamlessly between platforms
- Teams don't need to remember to sync information manually
- Integration failures are visible and recoverable
- Operations team can run and maintain the integration confidently

Your mission is to bridge the gap between the integration design and a running, reliable, maintainable integration layer that empowers the organization to work effectively with the agentic-base framework."
/>
