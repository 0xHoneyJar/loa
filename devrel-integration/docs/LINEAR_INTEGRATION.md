# Linear Integration Guide

Complete guide to the agentic-base Linear integration for automated issue tracking, Discord feedback capture, and agent audit trails.

## Table of Contents

- [Overview](#overview)
- [Setup](#setup)
- [Discord Commands](#discord-commands)
- [Feedback Capture](#feedback-capture)
- [Priority Management](#priority-management)
- [Label System](#label-system)
- [Agent Integration](#agent-integration)
- [Testing](#testing)
- [Troubleshooting](#troubleshooting)

## Overview

The Linear integration provides a complete audit trail for all code changes and team feedback through automated issue creation, tracking, and updates. It connects three systems:

1. **Discord** - Team communication and feedback capture
2. **Linear** - Issue tracking and project management
3. **AI Agents** - Automated code changes with full traceability

### Key Features

- **📌 Feedback Capture**: React with 📌 on Discord messages to create Linear issues
- **🏷️ Auto Project Detection**: Automatically tags issues based on Discord channel names
- **🎯 Priority Emoji Reactions**: Set issue priority with 🔴🟠🟡🟢 reactions
- **🤖 Agent Audit Trail**: All agent work automatically tracked in Linear
- **💬 Discord Commands**: Query and tag Linear issues from Discord
- **🔍 Bidirectional Linking**: Links between Discord, Linear, and audit findings

## Setup

### 1. Run Label Setup Script

First, initialize the base label taxonomy in Linear:

```bash
cd devrel-integration
npx ts-node scripts/setup-linear-labels.ts

# Or specify a team ID
npx ts-node scripts/setup-linear-labels.ts --team-id team_abc123xyz
```

This creates 18 base labels:
- **Agent labels**: `agent:implementer`, `agent:devops`, `agent:auditor`
- **Type labels**: `type:feature`, `type:bugfix`, `type:infrastructure`, `type:security`, `type:audit-finding`, `type:refactor`, `type:docs`
- **Source labels**: `source:discord`, `source:github`, `source:internal`
- **Priority labels**: `priority:critical`, `priority:high`, `priority:normal`, `priority:low`

See `scripts/README.md` for details.

### 2. Configure Environment

Ensure your `.env` contains:

```bash
# Linear Configuration
LINEAR_API_TOKEN=lin_api_xxxxxxxxxxxxxxxxxxxxxxxxxx
LINEAR_TEAM_ID=team_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

# Discord Configuration
DISCORD_BOT_TOKEN=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
DISCORD_GUILD_ID=1234567890123456789
DEVELOPER_ROLE_ID=1234567890123456789
ADMIN_ROLE_ID=1234567890123456789
```

### 3. Configure Channel Naming

For automatic project detection, name your Discord channels using these patterns:

- `#project-{name}` → Creates `project:{name}` label
- `#{name}-feedback` → Creates `project:{name}` label
- `#{name}-dev` → Creates `project:{name}` label

Examples:
- `#project-onomancer-bot` → `project:onomancer-bot`
- `#nft-marketplace-feedback` → `project:nft-marketplace`
- `#defi-protocol-dev` → `project:defi-protocol`

## Discord Commands

### `/tag-issue <issue-id> <project-name> [priority]`

Tag a Linear issue with project label and optional priority from Discord.

**Parameters:**
- `issue-id` (required): Linear issue identifier (e.g., PRJ-123)
- `project-name` (required): Project name for label (e.g., onomancer-bot)
- `priority` (optional): critical, high, normal, or low

**Examples:**
```
/tag-issue PRJ-123 onomancer-bot
/tag-issue PRJ-456 nft-marketplace high
/tag-issue SEC-789 defi-protocol critical
```

**Permissions:** Requires `developer` or `admin` role.

**What it does:**
1. Validates issue exists in Linear
2. Creates `project:{project-name}` label if needed
3. Adds project label to issue
4. Optionally sets priority (1=critical, 2=high, 3=normal, 4=low)
5. Confirms action in Discord

### `/show-issue <issue-id>`

Display Linear issue details in Discord with formatted output.

**Parameters:**
- `issue-id` (required): Linear issue identifier (e.g., PRJ-123)

**Examples:**
```
/show-issue PRJ-123
/show-issue SEC-456
```

**Output format:**
```
🔄 **PRJ-123: Implement user authentication flow**

**Status:** In Progress
**Priority:** 🟠 High
**Assignee:** @alice
**Labels:** `agent:implementer`, `type:feature`, `source:discord`

**Description:**
Implement JWT-based authentication with refresh tokens...

🔗 [View in Linear](https://linear.app/...)
```

### `/list-issues [filter]`

List Linear issues grouped by status with optional filtering.

**Parameters:**
- `filter` (optional): Label name to filter by (e.g., agent:implementer)

**Examples:**
```
/list-issues
/list-issues agent:implementer
/list-issues type:security
/list-issues project:onomancer-bot
```

**Output format:**
```
**Linear Issues**

Showing 15 issues:

📋 **Todo (3)**
- PRJ-123: Implement user authentication
- PRJ-124: Add rate limiting
- PRJ-125: Setup monitoring

🔄 **In Progress (2)**
- PRJ-120: Database migration
- PRJ-121: API refactoring

... (truncated for space)
```

## Feedback Capture

### How It Works

1. User posts feedback message in Discord
2. Team member reacts with 📌 emoji
3. Bot automatically:
   - Checks for PII (blocks if found)
   - Detects project from channel name
   - Creates Linear issue with labels
   - Adds priority emoji reactions
   - Stores message-to-issue mapping

### Feedback Capture Flow

```
Discord Message
    ↓
📌 Reaction by team member
    ↓
PII Detection (blocks if detected)
    ↓
Project Detection from channel name
    ↓
Linear Issue Created
    - Title: "Feedback: {first 80 chars}..."
    - Description: Full message + context
    - Labels: source:discord, project:{name}
    - State: Todo
    ↓
Confirmation Message with Priority Reactions
    🔴 🟠 🟡 🟢
```

### Example Feedback Capture

**Discord Message (in #project-onomancer-bot):**
```
The bot should support multiple languages for spell names.
Currently only English works, but users are requesting
Spanish, French, and Japanese support.
```

**After 📌 reaction:**
```
✅ **Feedback captured!**

**Linear Issue:** ONO-45 - Feedback: The bot should support multiple...
**URL:** https://linear.app/your-team/issue/ONO-45
**Labels:** `source:discord`, `project:onomancer-bot`

The issue has been created. React with priority emojis to set urgency:
🔴 Critical | 🟠 High | 🟡 Normal | 🟢 Low
```

### What Gets Captured

The Linear issue includes:
- Full message content
- Author info (sanitized Discord username)
- Timestamp
- Discord message link (for context)
- Thread context (if in thread)
- Attachments (links to Discord CDN)
- Project label (if detected)
- Source label (`source:discord`)
- Capture attribution

### PII Protection

The system automatically detects and blocks feedback capture if the message contains:
- Email addresses
- Phone numbers
- Social Security Numbers (SSN)
- Credit card numbers
- IP addresses

If PII is detected:
```
⚠️ **Cannot capture feedback: Sensitive information detected**

This message appears to contain: **email addresses, phone numbers**

Please edit the message to remove sensitive information, then try again with 📌

*This protection prevents accidental exposure of private information to Linear.*
```

## Priority Management

### Using Priority Emojis

After feedback is captured, the confirmation message includes 4 priority reaction emojis. Team members can click any emoji to set the issue priority:

- 🔴 **Critical** (Priority 1 - Urgent) - Drop everything, fix immediately
- 🟠 **High** (Priority 2) - Important, handle ASAP
- 🟡 **Normal** (Priority 3) - Standard priority
- 🟢 **Low** (Priority 4) - Nice to have, when time permits

### Priority Reaction Flow

```
User reacts with 🔴 on confirmation message
    ↓
Bot validates permission
    ↓
Bot extracts issue ID from message
    ↓
Bot updates Linear issue priority
    ↓
Confirmation message posted
```

**Example:**
```
✅ **Priority updated:** ONO-45 set to **Critical** by @alice
```

### Priority in Commands

You can also set priority via `/tag-issue` command:

```
/tag-issue ONO-45 onomancer-bot critical
```

### Priority Mapping

| Emoji | Label | Linear Priority | Use Case |
|-------|-------|----------------|----------|
| 🔴 | Critical | 1 (Urgent) | Security issues, production down, data loss |
| 🟠 | High | 2 (High) | Important features, major bugs, blockers |
| 🟡 | Normal | 3 (Medium) | Standard work, minor bugs, improvements |
| 🟢 | Low | 4 (Low) | Nice-to-haves, tech debt, documentation |

## Label System

### Base Label Categories

The system uses a hierarchical label taxonomy with 4 main categories:

#### 1. Agent Labels (Who did the work)
- `agent:implementer` - Work by sprint-task-implementer
- `agent:devops` - Work by devops-crypto-architect
- `agent:auditor` - Work by paranoid-auditor

#### 2. Type Labels (What kind of work)
- `type:feature` - New feature implementation
- `type:bugfix` - Bug fix
- `type:infrastructure` - Infrastructure/deployment work
- `type:security` - Security-related work
- `type:audit-finding` - Security audit finding
- `type:refactor` - Code refactoring
- `type:docs` - Documentation

#### 3. Source Labels (Where work originated)
- `source:discord` - Originated from Discord feedback
- `source:github` - Originated from GitHub (PRs, issues)
- `source:internal` - Agent-created (self-discovered)

#### 4. Priority Labels (Human-assigned urgency)
- `priority:critical` - Drop everything
- `priority:high` - Important, ASAP
- `priority:normal` - Standard priority
- `priority:low` - Nice to have

### Dynamic Labels

In addition to base labels, the system creates labels dynamically:

#### Sprint Labels
Created by agents for each sprint:
- `sprint:sprint-1`, `sprint:sprint-2`, etc.

#### Project Labels
Created by humans via Discord or auto-detected from channels:
- `project:onomancer-bot`
- `project:nft-marketplace`
- `project:defi-protocol`

### Querying by Labels

Use Linear's filter syntax or the `/list-issues` command:

```bash
# Via Discord
/list-issues agent:implementer
/list-issues type:security
/list-issues project:onomancer-bot

# Via Linear GraphQL
{
  issues(filter: {
    labels: {
      some: { name: { eq: "agent:implementer" } }
    }
  }) {
    nodes {
      identifier
      title
    }
  }
}
```

## Agent Integration

All code-touching agents automatically create and track Linear issues. See agent-specific documentation:

### Sprint Task Implementer

**Creates:**
- Parent issue for each sprint task
- Sub-issues for major components (>3 files, complex logic, external integrations)

**Status Transitions:**
- Creates issue → Status: Todo
- Starts work → Status: In Progress
- Completes component → Sub-issue: Done
- Completes all work → Parent: In Review
- Senior lead approves → Parent: Done

**Example:**
```
Parent: IMPL-123 "Implement user authentication flow"
  Labels: agent:implementer, type:feature, sprint:sprint-1

  Sub-issues:
  - IMPL-124 "Authentication middleware implementation"
  - IMPL-125 "JWT token service"
  - IMPL-126 "User session management"
```

### DevOps Crypto Architect

**Modes:**

1. **Integration Mode** (Phase 0.5)
   - Creates parent issue for integration implementation
   - Sub-issues per component (Discord bot, Linear webhooks, GitHub sync, cron jobs)
   - Labels: `agent:devops`, `type:infrastructure`

2. **Deployment Mode** (Phase 6)
   - Creates parent issue for production deployment
   - Sub-issues per infrastructure component (compute, database, networking, monitoring)
   - Labels: `agent:devops`, `type:infrastructure`, `sprint:{sprint-name}`

### Paranoid Auditor

**Severity-Based Hierarchy:**

- **CRITICAL/HIGH**: Standalone parent issues
  - Labels: `agent:auditor`, `type:security`, `type:audit-finding`, `priority:critical` or `priority:high`
  - Linked to implementation issues for remediation tracking

- **MEDIUM**: Grouped by category with sub-issues
  - Parent: "MEDIUM Security Findings - {Category}"
  - Sub-issues per finding
  - Labels: `agent:auditor`, `type:security`, `type:audit-finding`

- **LOW**: Comments on related implementation issues
  - Preserves context without creating noise

**Example:**
```
AUDIT-45 "[CRITICAL] SQL Injection in user search endpoint"
  Labels: agent:auditor, type:security, type:audit-finding, priority:critical
  Priority: 1 (Urgent)
  Linked to: IMPL-123 (implementation issue)

  Description includes:
  - Severity: CRITICAL
  - Component: src/api/users.ts:45
  - OWASP/CWE references
  - Proof of Concept
  - Remediation steps with exact code changes
```

## Testing

### Testing Feedback Capture

1. **Create test channel:**
   ```
   #project-test-bot
   ```

2. **Post test message:**
   ```
   Test feedback: The bot should validate input parameters.
   ```

3. **React with 📌**

4. **Verify:**
   - Confirmation message appears
   - Linear issue created with `source:discord` and `project:test-bot` labels
   - Priority emojis added to confirmation

5. **Test priority:**
   - Click 🟠 (High priority)
   - Verify confirmation message
   - Check Linear issue priority updated to 2

### Testing Discord Commands

1. **Test `/show-issue`:**
   ```
   /show-issue TEST-1
   ```
   - Should display formatted issue details

2. **Test `/list-issues`:**
   ```
   /list-issues
   /list-issues project:test-bot
   ```
   - Should show grouped issues
   - Filter should work correctly

3. **Test `/tag-issue`:**
   ```
   /tag-issue TEST-1 test-bot high
   ```
   - Should add `project:test-bot` label
   - Should set priority to 2 (High)
   - Should confirm in Discord

### Testing Agent Integration

1. **Test sprint-task-implementer:**
   - Create test sprint task in `docs/sprint.md`
   - Run `/implement test-sprint`
   - Verify Linear parent issue created
   - Verify sub-issues for components
   - Verify status transitions (Todo → In Progress → In Review → Done)

2. **Test paranoid-auditor:**
   - Run security audit on test code
   - Verify CRITICAL findings create standalone issues
   - Verify MEDIUM findings grouped by category
   - Verify LOW findings as comments
   - Verify bidirectional linking

### Performance Testing

Monitor Linear API usage:

```bash
# Check Linear API stats endpoint
curl http://localhost:3000/metrics | grep linear

# Expected metrics:
# - linear_api_requests_total
# - linear_api_errors_total
# - linear_circuit_breaker_state (closed/open/half-open)
# - linear_rate_limiter_queued
```

## Troubleshooting

### Common Issues

#### 1. "LINEAR_TEAM_ID not configured"

**Problem:** Linear team ID not set in environment variables.

**Solution:**
```bash
# Get your team ID from Linear
1. Go to Linear Settings → API
2. Copy your Team ID (starts with "team_")
3. Add to .env:
LINEAR_TEAM_ID=team_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

#### 2. Feedback capture not working

**Symptoms:** 📌 reaction doesn't create Linear issue.

**Debugging:**
1. Check bot logs: `tail -f logs/discord-bot.log`
2. Verify permissions: User must have `developer` or `admin` role
3. Check LINEAR_API_TOKEN is valid
4. Verify PII detection didn't block (check for warning message)

**Common causes:**
- Missing LINEAR_API_TOKEN
- User lacks permissions
- PII detected in message
- Linear API rate limit hit

#### 3. Priority reactions not working

**Symptoms:** Clicking priority emoji doesn't update Linear issue.

**Debugging:**
1. Check if message is bot confirmation (must contain "Linear Issue:")
2. Verify user has `feedback-capture` permission
3. Check if issue ID is extractable from message
4. Look for errors in bot logs

**Solution:**
```bash
# Verify permissions in Discord
/show-permissions @username

# Check logs
tail -f logs/discord-bot.log | grep "Priority updated"
```

#### 4. Project label not auto-detected

**Symptoms:** Issues created without `project:{name}` label.

**Cause:** Channel name doesn't match expected patterns.

**Solution:** Rename channel to one of these patterns:
- `#project-{name}`
- `#{name}-feedback`
- `#{name}-dev`

Examples:
- ✅ `#project-onomancer-bot`
- ✅ `#nft-marketplace-feedback`
- ✅ `#defi-protocol-dev`
- ❌ `#general-discussion` (no pattern match)

#### 5. "Label not found" error

**Problem:** System trying to use labels that don't exist.

**Solution:**
```bash
# Re-run label setup script
npx ts-node scripts/setup-linear-labels.ts

# Or create missing labels manually in Linear
```

#### 6. Circuit breaker open (Linear API unavailable)

**Symptoms:** Error messages saying "Linear integration temporarily unavailable"

**Cause:** Too many failures to Linear API (70% error rate over 1 minute window)

**Solution:**
1. Wait 30 seconds for circuit breaker to reset
2. Check Linear API status: https://linear.app/status
3. Verify LINEAR_API_TOKEN is valid
4. Check network connectivity
5. Review logs for specific API errors

**Circuit breaker behavior:**
- Opens after 70% errors in 1 minute window (minimum 20 requests)
- Half-opens after 30 seconds to test recovery
- Closes automatically if test succeeds

#### 7. Rate limit hit

**Symptoms:** "Linear rate limit hit, retrying after Xs" in logs

**Cause:** Linear API allows 2000 requests/hour (~33/minute)

**Solution:**
- System automatically retries after specified time
- Reduce concurrent agent invocations
- Check for infinite loops creating issues

**Rate limiting protections:**
- Bottleneck rate limiter: 33 requests/minute
- Request deduplication cache (5 second TTL)
- Circuit breaker for cascading failures

### Debug Mode

Enable verbose logging:

```bash
# Set in .env
NODE_ENV=development
LOG_LEVEL=debug

# Or run with debug flag
DEBUG=* npm run dev
```

### Health Check Endpoints

Monitor integration health:

```bash
# Overall health
curl http://localhost:3000/health

# Detailed metrics
curl http://localhost:3000/metrics

# Readiness check
curl http://localhost:3000/ready

# Liveness check
curl http://localhost:3000/live
```

### Getting Help

1. **Check logs:**
   ```bash
   tail -f logs/discord-bot.log
   tail -f logs/error.log
   ```

2. **Review audit logs:**
   ```bash
   tail -f logs/audit.log
   ```

3. **Test Linear API directly:**
   ```bash
   curl -H "Authorization: $LINEAR_API_TOKEN" \
        https://api.linear.app/graphql \
        -d '{"query":"{ viewer { id name email } }"}'
   ```

4. **Check Discord permissions:**
   - Verify bot has "Read Messages" permission
   - Verify bot has "Add Reactions" permission
   - Verify bot has "Send Messages" permission
   - Verify bot has "Read Message History" permission

5. **Validate environment:**
   ```bash
   npm run validate-env  # If script exists
   # Or manually check all required vars are set
   echo $LINEAR_API_TOKEN | cut -c1-10  # Should show "lin_api_xx"
   echo $LINEAR_TEAM_ID | cut -c1-5     # Should show "team_"
   ```

### Support Channels

- **GitHub Issues**: Report bugs at https://github.com/your-org/agentic-base/issues
- **Discord**: Join #integration-support channel
- **Documentation**: https://docs.agentic-base.io

## Best Practices

### For Team Members

1. **Use descriptive feedback messages** - Agents and teammates need context
2. **React with 📌 promptly** - Capture feedback while fresh
3. **Set priorities thoughtfully** - Use emoji reactions to prioritize
4. **Use correct channels** - Follow naming conventions for auto project detection
5. **Review Linear regularly** - Check implementation progress

### For Project Setup

1. **Run label setup first** - Initialize taxonomy before capturing feedback
2. **Use consistent naming** - Follow channel naming conventions
3. **Configure permissions** - Limit feedback-capture to trusted roles
4. **Monitor API usage** - Watch rate limits and circuit breaker
5. **Test in staging first** - Validate integration before production

### For Agents

1. **Always create parent issues** - Track all work in Linear
2. **Use descriptive titles** - Include context and scope
3. **Link to source** - Include Discord/GitHub URLs
4. **Update status promptly** - Keep Linear in sync with actual state
5. **Add comprehensive descriptions** - Future you will thank present you

## FAQ

**Q: Can I capture feedback from DMs?**
A: No, feedback capture only works in guild channels (not DMs) for security and audit trail purposes.

**Q: What happens if I delete the Discord message after capturing?**
A: The Linear issue remains. Issue description includes a link to the message, but content is preserved in Linear.

**Q: Can I capture my own messages?**
A: Yes, any team member with permissions can capture any message (including their own) by reacting with 📌.

**Q: How do I remove a project label?**
A: Use Linear's web interface or API to remove labels. The Discord bot currently only adds labels.

**Q: Can multiple people set priority with emojis?**
A: Yes, the last person to react sets the priority. All updates are audit logged.

**Q: What if the channel doesn't match naming patterns?**
A: Issues are still created with `source:discord` label, but won't get auto project label. Use `/tag-issue` to add manually.

**Q: How do I query all work by a specific agent?**
A: Use `/list-issues agent:implementer` or query Linear with the agent label filter.

**Q: Can I customize the label colors?**
A: Yes, edit the `BASE_LABELS` array in `scripts/setup-linear-labels.ts` and re-run the script. Existing labels won't be affected.

**Q: What's the maximum feedback message length?**
A: Discord messages are limited to 2000 characters. The entire message is captured in Linear.

**Q: How do I see all feedback from a specific project?**
A: Use `/list-issues project:your-project` or query Linear with the project label.

**Q: What happens if Linear is down?**
A: Circuit breaker opens after failures. Bot will report "temporarily unavailable" and retry automatically.
