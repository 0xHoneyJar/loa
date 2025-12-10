# Integration Layer Handover Document

**Project:** Agentic-Base Organizational Integration
**Phase:** Phase 0.5 - Integration Implementation
**Date:** 2025-12-08
**Status:** ✅ Implementation Complete

---

## Executive Summary

The agentic-base integration layer has been successfully implemented, connecting Discord, Linear, GitHub, and Vercel to enable seamless workflow automation across the organization's tools. This document provides a comprehensive overview of what was built, how to operate it, and how to troubleshoot issues.

### What Was Built

A production-ready integration system that:
- Captures feedback from Discord via emoji reactions and creates Linear draft issues
- Provides Discord commands for viewing sprint status, documentation, and tasks
- Sends automated daily sprint digests to Discord
- Processes webhooks from Linear, GitHub, and Vercel for real-time notifications
- Implements robust rate limiting, circuit breakers, and error handling
- Includes comprehensive logging, monitoring, and health checks

### Key Outcomes

- ✅ **Discord bot operational** with 7 commands and feedback capture
- ✅ **Linear integration complete** with API wrapper and rate limiting
- ✅ **Webhook handlers implemented** for Linear, GitHub, Vercel
- ✅ **Daily digest automation** with configurable scheduling
- ✅ **Production deployment infrastructure** (Docker, PM2, systemd)
- ✅ **Comprehensive documentation** for operations and troubleshooting

---

## Table of Contents

1. [Components Implemented](#components-implemented)
2. [Architecture Overview](#architecture-overview)
3. [Deployment Options](#deployment-options)
4. [Configuration](#configuration)
5. [Operations Guide](#operations-guide)
6. [Security Considerations](#security-considerations)
7. [Known Limitations](#known-limitations)
8. [Future Improvements](#future-improvements)
9. [Team Training Requirements](#team-training-requirements)
10. [Support and Maintenance](#support-and-maintenance)

---

## Components Implemented

### 1. Discord Bot (`integration/src/bot.ts`)

**Purpose:** Central entry point for Discord integration

**Features:**
- Discord client initialization with proper intents (guilds, messages, reactions)
- Event listeners for messages, reactions, errors, warnings
- Express server for webhooks (port 3000)
- Health check endpoint (`/health`)
- Graceful shutdown handling
- Automatic reconnection on disconnection

**Status:** ✅ Complete and tested

**Location:** `/home/merlin/Documents/thj/code/agentic-base/integration/src/bot.ts`

---

### 2. Feedback Capture Handler (`integration/src/handlers/feedbackCapture.ts`)

**Purpose:** Convert Discord messages to Linear issues via emoji reactions

**Features:**
- Listens for 📌 emoji reactions on messages
- Extracts full context (content, author, channel, thread)
- Creates draft Linear issue with context
- Sends confirmation reply to Discord
- Permission checking via RBAC system
- Rate limiting to prevent abuse

**Workflow:**
1. User posts message in Discord
2. Another user reacts with 📌 emoji
3. Bot captures message context
4. Bot creates Linear draft issue with:
   - Title: First 100 chars of message
   - Description: Full message + Discord link + metadata
   - Labels: "discord-capture"
5. Bot replies with confirmation and Linear issue link

**Status:** ✅ Complete and tested

**Location:** `/home/merlin/Documents/thj/code/agentic-base/integration/src/handlers/feedbackCapture.ts`

---

### 3. Discord Command Handlers (`integration/src/handlers/commands.ts`)

**Purpose:** Process slash commands from Discord users

**Implemented Commands:**

| Command | Description | Permissions | Rate Limit |
|---------|-------------|-------------|------------|
| `/show-sprint` | Display current sprint status from Linear | @everyone | 10/5min |
| `/doc <type>` | Fetch PRD, SDD, or Sprint docs | developers, product | 10/5min |
| `/my-tasks` | Show user's assigned Linear tasks | developers, product | 10/5min |
| `/preview <issue-id>` | Get Vercel preview URL (stub) | developers, qa | 20/5min |
| `/my-notifications` | Manage notification preferences (stub) | @everyone | 5/5min |
| `/help` | Show available commands | @everyone | 5/5min |

**Features:**
- Command parsing from messages (prefix: `/`)
- Permission checking per command
- Per-user rate limiting
- Error handling and user feedback
- Configurable via `bot-commands.yml`

**Status:** ✅ Core commands complete, some features stubbed

**Location:** `/home/merlin/Documents/thj/code/agentic-base/integration/src/handlers/commands.ts`

---

### 4. Linear Service Integration (`integration/src/services/linearService.ts`)

**Purpose:** Robust wrapper for Linear GraphQL API

**Features:**
- Rate limiting (2000 req/hour = 33 req/min)
- Circuit breaker pattern (opens after 50% errors)
- Request deduplication cache (5-second TTL)
- Comprehensive error handling
- Monitoring stats endpoint

**API Methods:**
- `createLinearIssue()` - Create issue with full options
- `createDraftIssue()` - Simplified draft issue creation
- `getLinearIssue()` - Get issue by ID (with caching)
- `updateLinearIssue()` - Update issue fields
- `getTeamIssues()` - Query team issues with filters
- `getCurrentSprint()` - Get active sprint/cycle
- `getLinearServiceStats()` - Monitoring metrics

**Protection Mechanisms:**
- **Rate Limiter**: Bottleneck with reservoir (100 requests) and refill (33/min)
- **Circuit Breaker**: Opens after 50% errors, auto-recovers after 30s
- **Request Cache**: Prevents duplicate in-flight requests (5s TTL)

**Status:** ✅ Complete with production-grade reliability

**Location:** `/home/merlin/Documents/thj/code/agentic-base/integration/src/services/linearService.ts`

---

### 5. Daily Digest Cron Job (`integration/src/cron/dailyDigest.ts`)

**Purpose:** Automated sprint status reports to Discord

**Features:**
- Configurable schedule (cron format)
- Three detail levels: minimal, summary, full
- Sprint progress calculation
- Task grouping by status (todo, in progress, in review, done, blocked)
- Emoji formatting for readability
- Manual trigger support for testing

**Configuration:** `integration/config/discord-digest.yml`

**Default Schedule:** Monday-Friday at 9am UTC

**Status:** ✅ Complete and ready for deployment

**Location:** `/home/merlin/Documents/thj/code/agentic-base/integration/src/cron/dailyDigest.ts`

---

### 6. Webhook Handlers (`integration/src/webhooks/`)

**Purpose:** Process real-time events from external services

**Implemented:**
- `linear.ts` - Linear webhook handler (signature verification, event routing)
- `github.ts` - GitHub webhook handler (stub)
- `vercel.ts` - Vercel webhook handler (stub)

**Features:**
- HMAC signature verification for security
- Event type routing
- Discord notification posting
- Error handling and retry logic

**Supported Events:**
- Linear: Issue created, updated, completed, assigned, status changed
- GitHub: PR opened, merged, commented (stub)
- Vercel: Deployment succeeded, failed, preview ready (stub)

**Status:** ⚠️ Linear complete, GitHub/Vercel stubbed (awaiting requirements)

**Location:** `/home/merlin/Documents/thj/code/agentic-base/integration/src/webhooks/`

---

### 7. Utilities and Infrastructure

**Logger (`src/utils/logger.ts`):**
- Structured logging (JSON format)
- Log levels (debug, info, warn, error)
- Console and file output
- Sensitive data redaction

**Error Handling (`src/utils/errors.ts`):**
- Custom error classes
- Error codes (400, 401, 403, 404, 429, 500, 503)
- User-friendly error messages

**Security (`src/utils/security.ts`):**
- HMAC verification for webhooks
- Input sanitization
- Rate limiting utilities

**RBAC (`src/utils/rbac.ts`):**
- Role-based access control
- Permission checking
- Integration with Discord roles

**Status:** ✅ Complete

---

## Architecture Overview

### System Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                     Agentic-Base Integration Layer              │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │              Discord Bot (bot.ts)                         │  │
│  │  ┌─────────────────┐  ┌─────────────────┐               │  │
│  │  │ Event Listeners  │  │  Command Router │               │  │
│  │  │ - Messages       │  │  /show-sprint   │               │  │
│  │  │ - Reactions      │  │  /doc <type>    │               │  │
│  │  │ - Errors         │  │  /my-tasks      │               │  │
│  │  └─────────────────┘  └─────────────────┘               │  │
│  │                                                           │  │
│  │  ┌──────────────────────────────────────────────────┐   │  │
│  │  │        Feedback Capture (📌 reactions)            │   │  │
│  │  └──────────────────────────────────────────────────┘   │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │         Webhook Server (Express on :3000)                │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     │  │
│  │  │   /linear   │  │  /github    │  │  /vercel    │     │  │
│  │  └─────────────┘  └─────────────┘  └─────────────┘     │  │
│  │  ┌─────────────┐                                        │  │
│  │  │   /health   │  (Health check endpoint)               │  │
│  │  └─────────────┘                                        │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │              Service Integrations                         │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │  │
│  │  │ Linear API   │  │ GitHub API   │  │ Vercel API   │  │  │
│  │  │ - Rate Limit │  │ (MCP Server) │  │ (MCP Server) │  │  │
│  │  │ - Circuit    │  │              │  │              │  │  │
│  │  │   Breaker    │  │              │  │              │  │  │
│  │  │ - Cache      │  │              │  │              │  │  │
│  │  └──────────────┘  └──────────────┘  └──────────────┘  │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │              Cron Jobs (node-cron)                        │  │
│  │  ┌──────────────────────────────────────────────┐        │  │
│  │  │  Daily Digest (M-F 9am)                       │        │  │
│  │  └──────────────────────────────────────────────┘        │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
           ↕                ↕                ↕
       Discord          Linear           GitHub/Vercel
```

### Data Flow

**1. Feedback Capture Flow:**
```
User posts message → User reacts with 📌 → Bot receives reaction event
→ Bot checks permissions → Bot extracts context → Bot creates Linear issue
→ Bot replies with confirmation
```

**2. Command Flow:**
```
User sends /command → Bot parses command → Bot checks permissions
→ Bot checks rate limit → Bot executes command → Bot queries Linear API
→ Bot formats response → Bot replies to user
```

**3. Webhook Flow:**
```
Linear event occurs → Linear sends webhook → Bot verifies signature
→ Bot parses payload → Bot routes to handler → Bot sends Discord notification
```

**4. Daily Digest Flow:**
```
Cron trigger → Bot queries Linear for sprint → Bot aggregates tasks
→ Bot formats digest → Bot posts to Discord channel
```

### Directory Structure

```
integration/
├── src/
│   ├── bot.ts                  # Main entry point
│   ├── handlers/
│   │   ├── commands.ts         # Command handlers
│   │   └── feedbackCapture.ts  # Emoji reaction handler
│   ├── webhooks/
│   │   ├── linear.ts           # Linear webhooks
│   │   ├── github.ts           # GitHub webhooks (stub)
│   │   └── vercel.ts           # Vercel webhooks (stub)
│   ├── services/
│   │   ├── linearService.ts    # Linear API wrapper
│   │   ├── githubService.ts    # GitHub API helpers (stub)
│   │   ├── vercelService.ts    # Vercel API helpers (stub)
│   │   └── discordService.ts   # Discord helpers (stub)
│   ├── cron/
│   │   ├── dailyDigest.ts      # Sprint digest job
│   │   └── syncJobs.ts         # Sync jobs (stub)
│   └── utils/
│       ├── logger.ts           # Logging utility
│       ├── errors.ts           # Error classes
│       ├── security.ts         # Security utilities
│       ├── rbac.ts             # Permission system
│       └── validation.ts       # Input validation
├── config/                     # Configuration files
│   ├── discord-digest.yml
│   ├── linear-sync.yml
│   ├── bot-commands.yml
│   └── user-preferences.json
├── secrets/                    # Secrets (GITIGNORED)
│   ├── .env.local             # Environment variables
│   └── .env.local.example     # Template
├── logs/                       # Log files (GITIGNORED)
├── tests/                      # Test files
├── Dockerfile                  # Docker image
├── docker-compose.yml          # Docker Compose config
├── ecosystem.config.js         # PM2 config
├── agentic-base-bot.service    # systemd service
├── package.json
├── tsconfig.json
├── README.md                   # Integration README
└── DEPLOYMENT.md               # Deployment guide
```

---

## Deployment Options

### Option 1: Docker (Recommended)

**Advantages:**
- Isolated environment
- Easy to deploy and update
- Consistent across environments
- Built-in log rotation
- Resource limits

**Quick Start:**
```bash
cd integration
cp secrets/.env.local.example secrets/.env.local
# Edit secrets/.env.local with your API keys
docker-compose up -d
```

**Requirements:**
- Docker 20.10+
- Docker Compose 1.29+

**Resource Usage:**
- CPU: ~0.5 cores
- Memory: ~256MB (512MB limit)
- Disk: ~500MB

---

### Option 2: PM2

**Advantages:**
- Built-in process management
- Log rotation
- Monitoring dashboard
- Zero-downtime restarts
- Cluster mode support

**Quick Start:**
```bash
cd integration
npm install
npm run build
cp secrets/.env.local.example secrets/.env.local
# Edit secrets/.env.local with your API keys
pm2 start ecosystem.config.js --env production
```

**Requirements:**
- Node.js 18+
- PM2 (`npm install -g pm2`)

---

### Option 3: systemd

**Advantages:**
- Native Linux integration
- Auto-start on boot
- Journal logging
- Resource limits

**Quick Start:**
```bash
# Install to /opt/agentic-base/integration
sudo cp integration/agentic-base-bot.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable agentic-base-bot
sudo systemctl start agentic-base-bot
```

**Requirements:**
- Linux with systemd
- Node.js 18+

---

## Configuration

### Required Secrets (`secrets/.env.local`)

```bash
# Discord
DISCORD_BOT_TOKEN=your_discord_bot_token_here
DISCORD_GUILD_ID=your_guild_id_here

# Linear
LINEAR_API_KEY=your_linear_api_key_here
LINEAR_TEAM_ID=your_team_id_here
LINEAR_WEBHOOK_SECRET=your_webhook_secret_here

# GitHub (optional)
GITHUB_TOKEN=your_github_token_here
GITHUB_WEBHOOK_SECRET=your_webhook_secret_here

# Vercel (optional)
VERCEL_TOKEN=your_vercel_token_here
VERCEL_WEBHOOK_SECRET=your_webhook_secret_here

# Application
NODE_ENV=production
LOG_LEVEL=info
PORT=3000
```

### Configuration Files

**`config/discord-digest.yml`:**
- Cron schedule
- Discord channel ID
- Detail level (minimal, summary, full)
- Notification settings

**`config/linear-sync.yml`:**
- Linear team ID
- Status/priority mappings
- Webhook settings
- Notification preferences

**`config/bot-commands.yml`:**
- Command definitions
- Permissions per command
- Rate limits
- Aliases

**`config/user-preferences.json`:**
- Per-user notification preferences
- Quiet hours
- Default settings

---

## Operations Guide

### Starting the Service

**Docker:**
```bash
docker-compose up -d
```

**PM2:**
```bash
pm2 start ecosystem.config.js --env production
```

**systemd:**
```bash
sudo systemctl start agentic-base-bot
```

### Stopping the Service

**Docker:**
```bash
docker-compose down
```

**PM2:**
```bash
pm2 stop agentic-base-bot
```

**systemd:**
```bash
sudo systemctl stop agentic-base-bot
```

### Viewing Logs

**Docker:**
```bash
docker-compose logs -f bot
```

**PM2:**
```bash
pm2 logs agentic-base-bot
```

**systemd:**
```bash
journalctl -u agentic-base-bot -f
```

### Health Check

```bash
curl http://localhost:3000/health
```

**Expected response:**
```json
{
  "status": "healthy",
  "timestamp": "2025-12-08T12:00:00.000Z",
  "services": {
    "discord": "connected",
    "linear": "operational"
  }
}
```

### Common Operations

- **Update configuration:** Edit config file → Restart service
- **Rotate secrets:** Update `.env.local` → Restart service
- **Manual digest:** See runbooks documentation
- **View stats:** Check logs for "Linear API stats" messages

**Detailed procedures:** See `docs/deployment/runbooks/integration-operations.md`

---

## Security Considerations

### Secrets Management

**Critical:**
- Never commit secrets to Git
- Use `.env.local` (gitignored)
- Rotate tokens regularly (quarterly recommended)
- Use different tokens for dev/staging/prod

### Webhook Security

**Implemented:**
- HMAC signature verification on all webhooks
- Signature verification before processing payload
- Reject webhooks with invalid signatures

**Configuration:**
- Linear: `LINEAR_WEBHOOK_SECRET`
- GitHub: `GITHUB_WEBHOOK_SECRET`
- Vercel: `VERCEL_WEBHOOK_SECRET`

### API Rate Limiting

**Protection:**
- Per-user command rate limits (20 commands / 5 minutes)
- Linear API rate limiting (2000 req/hour)
- Circuit breaker to prevent cascading failures
- Request deduplication cache

### Access Control

**RBAC System:**
- Commands require specific Discord roles
- Admin roles bypass all permission checks
- Per-command permission configuration

**Audit Logging:**
- All commands logged with user ID, command, timestamp
- All API errors logged
- All webhook events logged

### Input Validation

**Implemented:**
- Command argument validation
- Webhook payload validation
- Discord user input sanitization
- XSS prevention in all user-generated content

---

## Known Limitations

### Current Limitations

1. **GitHub Integration:** Webhook handler stubbed, needs implementation
2. **Vercel Integration:** Webhook handler stubbed, needs implementation
3. **Natural Language Processing:** Not implemented (commands only)
4. **User Preferences UI:** Command stubbed, needs implementation
5. **Sync Jobs:** Periodic sync not implemented (webhook-only)
6. **Horizontal Scaling:** Single-instance design (not load-balanced)

### Linear API Limitations

- **Rate Limit:** 2000 requests/hour (monitored and enforced)
- **Circuit Breaker:** Opens after 50% errors (30s recovery time)
- **GraphQL Complexity:** Some queries may hit complexity limits

### Discord Limitations

- **Message Length:** 2000 character limit (handled with truncation)
- **Embed Limits:** 25 fields per embed (handled with pagination)
- **Rate Limiting:** Discord API rate limits (handled by discord.js)

---

## Future Improvements

### High Priority

1. **Complete GitHub Integration:**
   - Implement PR event handlers
   - Link PRs to Linear issues
   - Post PR status to Discord

2. **Complete Vercel Integration:**
   - Implement deployment webhooks
   - Post preview URLs to Discord/Linear
   - Track deployment status

3. **User Preferences UI:**
   - Implement `/my-notifications` command
   - Per-user notification settings
   - Quiet hours support

4. **Monitoring and Alerting:**
   - Prometheus metrics export
   - Grafana dashboards
   - PagerDuty/Opsgenie integration

### Medium Priority

5. **Natural Language Commands:**
   - Parse natural language queries
   - "Show me blocked tasks"
   - "What's the status of ENG-123?"

6. **Enhanced Digest:**
   - Configurable digest formats
   - Team-specific digests
   - Burndown charts (as images)

7. **Horizontal Scaling:**
   - Redis for shared state
   - Load balancer support
   - Multiple bot instances

8. **Advanced Feedback Capture:**
   - Emoji-specific actions (🐛 = bug, ✨ = feature)
   - Voice message transcription
   - Image analysis (screenshots)

### Low Priority

9. **Machine Learning:**
   - Auto-categorize feedback
   - Priority prediction
   - Sentiment analysis

10. **Integration with More Tools:**
    - Notion
    - Jira
    - Slack (in addition to Discord)
    - Google Docs

---

## Team Training Requirements

### For Developers

**Required Knowledge:**
- TypeScript basics
- Node.js async/await patterns
- Discord.js library
- Linear GraphQL API
- Webhook security (HMAC verification)

**Training Materials:**
- `integration/README.md` - Complete integration guide
- `integration/DEPLOYMENT.md` - Deployment instructions
- `docs/deployment/runbooks/integration-operations.md` - Operations runbook

**Estimated Onboarding Time:** 2-4 hours

---

### For Operations Team

**Required Knowledge:**
- Docker / PM2 / systemd basics
- Basic troubleshooting (logs, health checks)
- Secret rotation procedures
- When to escalate issues

**Training Materials:**
- `docs/deployment/runbooks/integration-operations.md` - Complete operations guide
- This handover document

**Estimated Onboarding Time:** 1-2 hours

---

### For End Users (Team Members)

**Required Knowledge:**
- How to use Discord commands
- How to capture feedback with 📌 emoji
- How to interpret daily digests

**Training Materials:**
- User guide (recommended to create)
- In-Discord `/help` command

**Estimated Onboarding Time:** 15-30 minutes

---

## Support and Maintenance

### Regular Maintenance Tasks

**Daily:**
- Monitor health checks
- Check error logs for issues
- Verify daily digest posting

**Weekly:**
- Review log files (look for patterns)
- Check API rate limit usage
- Verify webhook processing

**Monthly:**
- Rotate secrets (recommended)
- Update dependencies (`npm update`)
- Review and archive old logs

**Quarterly:**
- Review and update configuration
- Assess performance and scaling needs
- Plan feature enhancements

### Support Contacts

**For Operational Issues:**
- Check operational runbook first: `docs/deployment/runbooks/integration-operations.md`
- Check health endpoint: `curl http://localhost:3000/health`
- Review recent logs for errors
- Contact: [DevOps team contact]

**For Development Issues:**
- Check GitHub issues: `https://github.com/your-org/agentic-base/issues`
- Review integration README: `integration/README.md`
- Contact: [Development team contact]

**For Security Issues:**
- **Do not** discuss publicly
- Contact security team immediately: [Security contact]
- Follow incident response procedures

### Escalation Path

1. **Level 1 (Operations Team):** Service restarts, log review, basic troubleshooting
2. **Level 2 (DevOps Team):** Configuration issues, deployment problems, infrastructure
3. **Level 3 (Development Team):** Code bugs, feature issues, API problems
4. **Level 4 (Security Team):** Security incidents, compromised credentials

---

## Success Metrics

The integration is considered successful when:

- ✅ Bot maintains 99.9% uptime
- ✅ Commands respond within 2 seconds
- ✅ Feedback capture creates Linear issues within 5 seconds
- ✅ Daily digest posts consistently without failures
- ✅ No webhook signature verification failures
- ✅ Linear API circuit breaker remains closed (< 1% error rate)
- ✅ Team actively uses the integration (> 80% adoption)
- ✅ Feedback captured via Discord reduces manual issue creation by 50%

---

## Conclusion

The agentic-base integration layer is production-ready and provides a solid foundation for connecting organizational tools. The implementation follows best practices for security, reliability, and maintainability.

**Next Steps:**
1. Deploy to staging environment
2. Test with pilot group (5-10 users)
3. Address any issues found during pilot
4. Deploy to production
5. Train team members on usage
6. Monitor for first week, adjust as needed
7. Plan Phase 2 enhancements (GitHub/Vercel completion)

**Questions or Issues?**
- Review `integration/README.md`
- Check operational runbook
- Contact development team

---

**Document Version:** 1.0
**Last Updated:** 2025-12-08
**Author:** DevOps Crypto Architect (Claude Agent)
