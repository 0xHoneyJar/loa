# Agentic-Base Integration

This directory contains the integration code that connects agentic-base with your organization's tools: Discord, Linear, GitHub, and Vercel.

## What's In This Directory

```
integration/
├── config/              # Configuration files (YAML/JSON, committed to git)
│   ├── discord-digest.yml        # Daily digest settings
│   ├── linear-sync.yml           # Linear API configuration
│   ├── review-workflow.yml       # Review assignment logic
│   ├── bot-commands.yml          # Discord bot commands config
│   └── user-preferences.json     # Per-user notification preferences
├── secrets/             # Secrets and API tokens (GITIGNORED)
│   ├── .env.local                # All API tokens and secrets
│   └── .gitkeep
├── src/                 # TypeScript source code
│   ├── bot.ts                    # Main Discord bot entry point
│   ├── handlers/                 # Command and event handlers
│   │   ├── feedbackCapture.ts   # 📌 reaction → Linear draft issue
│   │   ├── commands.ts           # Discord slash command handlers
│   │   └── naturalLanguage.ts   # NLP for natural queries (stub)
│   ├── services/                 # External service integrations
│   │   ├── linearService.ts     # Linear API wrapper
│   │   ├── githubService.ts     # GitHub API wrapper (stub)
│   │   └── vercelService.ts     # Vercel API wrapper (stub)
│   ├── cron/                     # Scheduled jobs
│   │   └── dailyDigest.ts       # Daily sprint status digest
│   └── utils/                    # Utilities
│       └── logger.ts             # Logging utility
├── logs/                # Log files (GITIGNORED)
│   ├── discord-bot.log
│   └── linear-sync.log
├── package.json         # Node.js dependencies
├── tsconfig.json        # TypeScript configuration
└── README.md            # This file
```

## Quick Start

### Prerequisites

- Node.js 18+ LTS
- npm or yarn
- Discord bot token (see `docs/tool-setup.md`)
- Linear API token (see `docs/tool-setup.md`)

### Installation

```bash
cd integration
npm install
```

### Configuration

1. Create `secrets/.env.local` file:
```bash
cp secrets/.env.local.example secrets/.env.local
# Edit secrets/.env.local with your tokens
```

2. Update config files in `config/` directory:
- `discord-digest.yml` - Set your channel ID and schedule
- `linear-sync.yml` - Set your Linear team ID
- `review-workflow.yml` - Configure review workflow
- `bot-commands.yml` - Enable/disable commands

### Build & Run

```bash
# Development mode (hot reload)
npm run dev

# Production mode
npm run build
npm start

# Or with PM2 (recommended for production)
pm2 start dist/bot.js --name agentic-base-bot
```

### Test

```bash
# Test feedback capture
1. Post a test message in Discord
2. React with 📌 emoji
3. Check if draft Linear issue was created

# Test commands
/show-sprint
/doc prd
/my-notifications
```

## Architecture Overview

### Flow: Feedback Capture (📌 Reaction)

```
User posts message in Discord
  ↓
Developer reacts with 📌
  ↓
src/bot.ts detects MessageReactionAdd event
  ↓
handlers/feedbackCapture.ts processes reaction
  ↓
services/linearService.ts creates draft Linear issue
  ↓
Bot replies in Discord with confirmation
```

### Flow: Daily Digest

```
Cron scheduler triggers at configured time
  ↓
cron/dailyDigest.ts executes
  ↓
services/linearService.ts queries Linear API for tasks
  ↓
Format digest message (in progress, completed, blocked)
  ↓
Post to configured Discord channel
```

### Flow: Slash Commands

```
User types /show-sprint in Discord
  ↓
src/bot.ts detects MessageCreate event
  ↓
handlers/commands.ts routes to appropriate handler
  ↓
Service layer fetches data (Linear, GitHub, Vercel)
  ↓
Reply to user with formatted response
```

## Configuration Reference

### discord-digest.yml

```yaml
schedule: "0 9 * * *"     # Cron format (9am daily)
channel_id: "123..."      # Discord channel ID
enabled: true             # Enable/disable digest
detail_level: "full"      # minimal | summary | full
```

### linear-sync.yml

```yaml
linear:
  team_id: "abc-123..."   # Linear team UUID
  status_mapping:         # Map agent statuses to Linear states
    todo: "Todo"
    in_progress: "In Progress"
    in_review: "In Review"
    changes_requested: "Changes Requested"
    done: "Done"
```

### review-workflow.yml

```yaml
review_workflow:
  mode: "developer"       # developer | designated_reviewer | auto
  reviewers:              # For designated_reviewer mode
    - discord_id: "..."
      linear_user_id: "..."
```

### user-preferences.json

```json
{
  "users": {
    "discord_user_id": {
      "daily_digest": true,
      "feedback_updates": true,
      "vercel_previews": true
    }
  }
}
```

## Development Guide

### Adding a New Command

1. **Add to config:** Edit `config/bot-commands.yml`
```yaml
my_command:
  enabled: true
  description: "My new command"
  usage: "/my-command [args]"
```

2. **Implement handler:** Edit `src/handlers/commands.ts`
```typescript
case 'my-command':
  await handleMyCommand(message, args);
  break;

async function handleMyCommand(message: Message, args: string[]) {
  // Your implementation
  await message.reply('Response');
}
```

3. **Rebuild and restart:**
```bash
npm run build
pm2 restart agentic-base-bot
```

### Adding a New Service Integration

1. **Create service file:** `src/services/myService.ts`
```typescript
export async function fetchData() {
  // Call external API
  return data;
}
```

2. **Use in handlers:**
```typescript
import { fetchData } from '../services/myService';

async function handleCommand(message: Message) {
  const data = await fetchData();
  await message.reply(data);
}
```

### Logging

Use the logger utility in all files:

```typescript
import { logger } from '../utils/logger';

logger.info('Information message');
logger.warn('Warning message');
logger.error('Error message', error);
```

Logs are written to:
- Console (stdout)
- `logs/discord-bot.log` (persistent)

## Troubleshooting

### Bot won't start

```bash
# Check logs
cat logs/discord-bot.log

# Verify token
echo $DISCORD_BOT_TOKEN  # Should not be empty

# Test Discord API
curl -H "Authorization: Bot YOUR_TOKEN" \
  https://discord.com/api/users/@me
```

### Linear API errors

```bash
# Check Linear API status
curl https://status.linear.app

# Test your token
curl -X POST https://api.linear.app/graphql \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"query":"{ viewer { name } }"}'
```

### Daily digest not posting

```bash
# Check cron schedule syntax
# "0 9 * * *" = 9am daily
# Remember: Times are in UTC by default

# Manually trigger digest (for testing)
npm run dev
# Then manually call the digest function

# Check bot has permission to post in channel
# Bot needs "Send Messages" permission
```

### Command not working

```bash
# Check if command is enabled in bot-commands.yml
grep -A 3 "my-command" config/bot-commands.yml

# Check handler is implemented in commands.ts
grep "my-command" src/handlers/commands.ts

# Check bot logs for errors
tail -f logs/discord-bot.log
```

## Deployment Options

### Option 1: Local Server / VPS

```bash
# Install PM2 globally
npm install -g pm2

# Start bot
cd integration
pm2 start dist/bot.js --name agentic-base-bot

# Auto-restart on reboot
pm2 startup
pm2 save

# Monitor
pm2 logs agentic-base-bot
pm2 monit
```

### Option 2: Docker

```bash
# Build image
docker build -t agentic-base-bot .

# Run container
docker run -d \
  --name agentic-base-bot \
  --env-file secrets/.env.local \
  --restart unless-stopped \
  agentic-base-bot

# View logs
docker logs -f agentic-base-bot
```

### Option 3: GitHub Actions (Serverless)

See `.github/workflows/discord-bot.yml` for scheduled job setup.

Note: Full bot won't work serverless (needs to be always running), but daily digest can be triggered via GitHub Actions.

## Maintenance

### Regular Tasks

**Daily:**
- Monitor logs for errors: `tail -f logs/discord-bot.log`
- Verify daily digest posted successfully

**Weekly:**
- Review captured feedback drafts in Linear
- Check bot uptime: `pm2 status`

**Monthly:**
- Rotate logs (logrotate configured in tool-setup.md)
- Update dependencies: `npm outdated && npm update`
- Review and clean up user preferences

**Quarterly:**
- Rotate API tokens (Discord, Linear)
- Audit and optimize configs
- Review and update documentation

### Backup & Recovery

**What to backup:**
- `config/` directory (committed to git, already backed up)
- `secrets/.env.local` (encrypted backup, store securely)
- `logs/` (optional, for debugging)

**Disaster recovery:**
1. Restore secrets/.env.local
2. Run `npm install`
3. Run `npm run build`
4. Start bot: `pm2 start dist/bot.js`

**Data loss scenarios:**
- Discord: Use Discord's message export
- Linear: Linear data is not stored locally (use Linear's API)
- Bot state: Stateless bot, no state to lose

## Security

### Secrets Management

- ✅ All secrets in `secrets/.env.local` (gitignored)
- ✅ Never commit tokens to git
- ✅ Use environment variables for all credentials
- ✅ Rotate tokens every 90 days

### API Permissions

- **Discord bot:** Read messages, send messages, add reactions
- **Linear API:** Read/write issues, read team data
- **GitHub API:** Read repos, read/write issues (via MCP)
- **Vercel API:** Read deployments (via MCP)

### Audit Trail

All actions logged to `logs/discord-bot.log`:
- Feedback captured
- Commands executed
- Linear API calls
- Errors and warnings

## Performance

### Current Scale (2-4 developers)

- **Messages processed:** <100/day
- **Linear API calls:** ~50/hour (2.5% of rate limit)
- **Daily digest:** 1/day, <10 seconds to generate
- **Response time:** <5 seconds for commands

### Scaling Considerations (10+ developers)

If team grows:
- Add caching layer (Redis) for Linear API responses
- Use database (PostgreSQL) instead of JSON for user preferences
- Add job queue (BullMQ) for background tasks
- Consider bot sharding for large Discord servers

## Documentation Links

- **Full architecture:** `../docs/integration-architecture.md`
- **Setup guide:** `../docs/tool-setup.md`
- **Team playbook:** `../docs/team-playbook.md`
- **Adoption plan:** `../docs/adoption-plan.md`

## Support

**Issues or questions?**
1. Check troubleshooting section above
2. Check logs: `logs/discord-bot.log`
3. Review tool-setup.md for configuration issues
4. Check Discord API status: https://discordstatus.com
5. Check Linear API status: https://status.linear.app
6. Open an issue in this repository

## License

Same as parent agentic-base project.

---

**Last Updated:** 2025-12-07
**Version:** 1.0
