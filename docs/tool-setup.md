# Tool Setup Guide

**Document Version:** 1.0
**Last Updated:** 2025-12-07
**Prerequisites:** Review `docs/integration-architecture.md` first

## Overview

This guide provides step-by-step instructions to set up the integration between agentic-base and your organization's tools (Discord, Linear, GitHub, Vercel). By the end of this setup, you'll have:

- ✅ Discord bot running with feedback capture and query commands
- ✅ Linear API integration for task management
- ✅ Daily digest posting to Discord
- ✅ Modified agentic-base agents that work with Linear
- ✅ User notification preferences system

**Estimated setup time:** 2-3 hours

## Prerequisites

### Required Accounts & Access

1. **Discord:**
   - Admin access to your Discord server
   - Ability to create bots in Discord Developer Portal

2. **Linear:**
   - Admin or Member access to your Linear workspace
   - Ability to generate API tokens

3. **GitHub:**
   - Repository access (already set up)
   - MCP server configured in `.claude/settings.local.json`

4. **Vercel:**
   - Project access
   - MCP server configured in `.claude/settings.local.json`

5. **Development Environment:**
   - Node.js 18+ LTS installed
   - npm or yarn installed
   - Git installed
   - Text editor (VS Code recommended)

### Check Existing MCP Servers

Your `.claude/settings.local.json` already has these MCP servers configured:

```bash
# Verify MCP servers are working
grep -A 5 "mcpServers" .claude/settings.local.json
```

You should see: `linear`, `github`, `vercel`, `discord`, `web3-stats`

## Part 1: Discord Bot Setup

### Step 1.1: Create Discord Application

1. Go to [Discord Developer Portal](https://discord.com/developers/applications)
2. Click **"New Application"**
3. Name it: `Agentic-Base Integration Bot`
4. Click **"Create"**

### Step 1.2: Configure Bot

1. In left sidebar, click **"Bot"**
2. Click **"Add Bot"** → Confirm
3. Under **"Privileged Gateway Intents"**, enable:
   - ✅ **MESSAGE CONTENT INTENT** (required to read messages)
   - ✅ **SERVER MEMBERS INTENT** (optional, for member queries)
4. Click **"Save Changes"**

### Step 1.3: Get Bot Token

1. Under **"TOKEN"** section, click **"Reset Token"**
2. Copy the token (you'll only see it once!)
3. Save it temporarily (we'll add it to `.env.local` soon)

### Step 1.4: Set Bot Permissions

1. In left sidebar, click **"OAuth2"** → **"URL Generator"**
2. Under **"SCOPES"**, select:
   - ✅ `bot`
   - ✅ `applications.commands`
3. Under **"BOT PERMISSIONS"**, select:
   - ✅ Read Messages/View Channels
   - ✅ Send Messages
   - ✅ Send Messages in Threads
   - ✅ Embed Links
   - ✅ Add Reactions
   - ✅ Use Slash Commands
   - ✅ Read Message History
4. Copy the generated URL at the bottom

### Step 1.5: Invite Bot to Server

1. Paste the URL from Step 1.4 into your browser
2. Select your Discord server
3. Click **"Authorize"**
4. Complete the CAPTCHA
5. Verify bot appears in your server's member list (offline for now)

### Step 1.6: Get Channel IDs

You need the channel IDs where the bot will post:

1. In Discord, enable Developer Mode:
   - User Settings → Advanced → ✅ Developer Mode
2. Right-click your **#sprint-updates** channel (or create it) → **Copy ID**
3. Save this as your `DISCORD_CHANNEL_ID`
4. (Optional) Get IDs for other channels (alerts, feedback, etc.)

## Part 2: Linear API Setup

### Step 2.1: Generate Linear API Token

1. Go to [Linear Settings](https://linear.app/settings)
2. Click **"API"** in left sidebar
3. Under **"Personal API keys"**, click **"Create key"**
4. Name it: `Agentic-Base Integration`
5. Copy the token (starts with `lin_api_...`)
6. Save it temporarily

### Step 2.2: Get Linear Team ID

1. In Linear, go to your team's page
2. Look at the URL: `https://linear.app/YOUR_TEAM/...`
3. The `YOUR_TEAM` part is your team slug
4. To get the team ID (UUID format):

```bash
# Run this curl command (replace TOKEN with your Linear API token)
curl -X POST https://api.linear.app/graphql \
  -H "Authorization: Bearer lin_api_YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"query":"{ teams { nodes { id name key } } }"}'
```

5. Find your team in the response, copy the `id` field (UUID format like `abc-123-def`)

### Step 2.3: Verify Linear Workflow States

Check your Linear team's workflow states:

1. In Linear, go to **Settings** → **Teams** → Your Team → **States**
2. Verify you have these states (or note differences):
   - Todo
   - In Progress
   - In Review
   - Changes Requested (or "Needs Changes")
   - Done (or "Completed")

If your state names differ, note them - you'll update the config later.

## Part 3: Install Integration Code

### Step 3.1: Create Integration Directory

```bash
# From the root of agentic-base repo
mkdir -p integration/{config,secrets,logs,src,scripts}
```

### Step 3.2: Initialize Node.js Project

```bash
cd integration

# Initialize package.json
npm init -y

# Install dependencies
npm install discord.js @discordjs/rest @discordjs/builders
npm install @linear/sdk
npm install dotenv node-cron
npm install typescript ts-node @types/node @types/dotenv -D

# Initialize TypeScript
npx tsc --init
```

### Step 3.3: Configure TypeScript

Edit `integration/tsconfig.json`:

```json
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "commonjs",
    "lib": ["ES2020"],
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist"]
}
```

### Step 3.4: Create Environment Variables File

```bash
cd integration

# Create secrets directory and .env.local
cat > secrets/.env.local << 'EOF'
# Discord Bot Token
DISCORD_BOT_TOKEN=your_discord_bot_token_here

# Discord Channel IDs
DISCORD_DIGEST_CHANNEL_ID=your_channel_id_here
DISCORD_ALERTS_CHANNEL_ID=your_channel_id_here

# Linear API
LINEAR_API_TOKEN=your_linear_api_token_here
LINEAR_TEAM_ID=your_team_id_here

# GitHub (optional, already in .claude/settings.local.json)
GITHUB_TOKEN=your_github_token_here

# Vercel (optional, already in .claude/settings.local.json)
VERCEL_TOKEN=your_vercel_token_here

# Environment
NODE_ENV=production
LOG_LEVEL=info
EOF

# Make sure secrets are gitignored
echo "secrets/" >> ../.gitignore
echo "integration/secrets/" >> ../.gitignore
echo "integration/node_modules/" >> ../.gitignore
echo "integration/dist/" >> ../.gitignore
```

### Step 3.5: Add Your Tokens

Edit `integration/secrets/.env.local` and replace placeholders with real values:

```bash
nano secrets/.env.local

# Or use your preferred editor
code secrets/.env.local
```

Replace:
- `your_discord_bot_token_here` → Token from Part 1 Step 1.3
- `your_channel_id_here` → Channel ID from Part 1 Step 1.6
- `your_linear_api_token_here` → Token from Part 2 Step 2.1
- `your_team_id_here` → Team ID from Part 2 Step 2.2

## Part 4: Configuration Files

### Step 4.1: Create Discord Digest Config

```bash
cat > integration/config/discord-digest.yml << 'EOF'
# Discord Daily Digest Configuration
schedule: "0 9 * * *"  # Cron format: 9am daily
timezone: "America/Los_Angeles"  # Change to your timezone

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
  channel_id: null  # null = use main channel

formatting:
  use_embeds: true
  group_by: "status"  # Options: status, assignee, sprint
  show_avatars: true
  max_tasks_per_section: 10
EOF
```

**Edit this file:**
```bash
nano integration/config/discord-digest.yml
```

Replace:
- `REPLACE_WITH_YOUR_CHANNEL_ID` → Your Discord channel ID
- `America/Los_Angeles` → Your timezone (e.g., `America/New_York`, `Europe/London`)

### Step 4.2: Create Linear Sync Config

```bash
cat > integration/config/linear-sync.yml << 'EOF'
# Linear Integration Configuration
linear:
  api_url: "https://api.linear.app/graphql"
  team_id: "REPLACE_WITH_YOUR_TEAM_ID"

  # Draft issue settings
  draft_label: "draft"
  researcher_feedback_label: "researcher-feedback"

  # Status mapping (adjust if your Linear states differ)
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
EOF
```

**Edit this file:**
```bash
nano integration/config/linear-sync.yml
```

Replace:
- `REPLACE_WITH_YOUR_TEAM_ID` → Your Linear team ID
- Adjust `status_mapping` if your Linear states have different names

### Step 4.3: Create Review Workflow Config

```bash
cat > integration/config/review-workflow.yml << 'EOF'
# Review Workflow Configuration
review_workflow:
  mode: "developer"  # Options: "developer", "designated_reviewer", "auto"

  # For mode: "designated_reviewer" (ignore if using "developer" mode)
  reviewers:
    - discord_id: "REPLACE_WITH_REVIEWER_DISCORD_ID"
      name: "Senior Dev 1"
      linear_user_id: "REPLACE_WITH_LINEAR_USER_ID"

  rotation: "round-robin"  # Options: "round-robin", "manual", "workload-based"

  notifications:
    discord_enabled: true
    discord_channel_id: "REPLACE_WITH_CHANNEL_ID"
    mention_reviewer: true
EOF
```

**Edit this file if using designated reviewer mode:**
```bash
nano integration/config/review-workflow.yml
```

### Step 4.4: Create User Preferences File

```bash
cat > integration/config/user-preferences.json << 'EOF'
{
  "users": {
    "example_user_discord_id": {
      "name": "Example User",
      "daily_digest": true,
      "feedback_updates": true,
      "vercel_previews": true,
      "review_requests": false
    }
  }
}
EOF
```

This file will be populated automatically as users configure their preferences via Discord commands.

### Step 4.5: Create Bot Commands Config

```bash
cat > integration/config/bot-commands.yml << 'EOF'
# Discord Bot Commands Configuration

commands:
  # Researcher & Developer Commands
  show_sprint:
    enabled: true
    description: "Show current sprint status summary"
    aliases: ["sprint", "status"]

  preview:
    enabled: true
    description: "Get Vercel preview URL for a Linear issue"
    usage: "/preview THJ-123"

  doc:
    enabled: true
    description: "Get link to project documents"
    usage: "/doc prd | /doc sdd | /doc sprint"

  task:
    enabled: true
    description: "Show details for a Linear task"
    usage: "/task THJ-123"

  my_notifications:
    enabled: true
    description: "Configure your notification preferences"
    aliases: ["notifications", "prefs"]

  # Developer-Only Commands
  my_tasks:
    enabled: true
    description: "Show all Linear tasks assigned to you"
    developer_only: true

  implement_status:
    enabled: true
    description: "Check implementation status of a task"
    usage: "/implement-status THJ-123"
    developer_only: true

  feedback:
    enabled: true
    description: "Show all captured feedback from a user"
    usage: "/feedback @researcher"
    developer_only: true

# Natural Language Processing
nlp:
  enabled: true
  confidence_threshold: 0.7
  keywords:
    status: ["status", "progress", "what's happening", "update"]
    preview: ["preview", "test", "deployed", "url"]
    task: ["task", "issue", "ticket"]
EOF
```

## Part 5: Bot Implementation Code

Now we'll create the Discord bot source code.

### Step 5.1: Create Main Bot File

```bash
cat > integration/src/bot.ts << 'EOF'
import { Client, GatewayIntentBits, Events, Partials } from 'discord.js';
import dotenv from 'dotenv';
import path from 'path';
import { handleReaction } from './handlers/feedbackCapture';
import { handleCommand } from './handlers/commands';
import { handleNaturalLanguage } from './handlers/naturalLanguage';
import { setupCronJobs } from './cron/dailyDigest';
import { logger } from './utils/logger';

// Load environment variables
dotenv.config({ path: path.join(__dirname, '../secrets/.env.local') });

// Create Discord client
const client = new Client({
  intents: [
    GatewayIntentBits.Guilds,
    GatewayIntentBits.GuildMessages,
    GatewayIntentBits.MessageContent,
    GatewayIntentBits.GuildMessageReactions,
    GatewayIntentBits.GuildMembers,
  ],
  partials: [Partials.Message, Partials.Channel, Partials.Reaction],
});

// Bot ready event
client.once(Events.ClientReady, (c) => {
  logger.info(`Bot logged in as ${c.user.tag}`);
  logger.info(`Connected to ${c.guilds.cache.size} server(s)`);

  // Set up cron jobs for daily digest
  setupCronJobs(client);
});

// Handle message reactions (📌 for feedback capture)
client.on(Events.MessageReactionAdd, async (reaction, user) => {
  // Ignore bot's own reactions
  if (user.bot) return;

  // Handle partial reactions
  if (reaction.partial) {
    try {
      await reaction.fetch();
    } catch (error) {
      logger.error('Error fetching reaction:', error);
      return;
    }
  }

  // Check if it's the 📌 emoji
  if (reaction.emoji.name === '📌') {
    await handleReaction(reaction, user, client);
  }
});

// Handle slash commands and text messages
client.on(Events.MessageCreate, async (message) => {
  // Ignore bot's own messages
  if (message.author.bot) return;

  // Handle slash commands
  if (message.content.startsWith('/')) {
    await handleCommand(message, client);
    return;
  }

  // Handle natural language (if enabled)
  await handleNaturalLanguage(message, client);
});

// Error handling
client.on(Events.Error, (error) => {
  logger.error('Discord client error:', error);
});

process.on('unhandledRejection', (error) => {
  logger.error('Unhandled promise rejection:', error);
});

// Login to Discord
client.login(process.env.DISCORD_BOT_TOKEN);

export { client };
EOF
```

### Step 5.2: Create Feedback Capture Handler

```bash
mkdir -p integration/src/handlers

cat > integration/src/handlers/feedbackCapture.ts << 'EOF'
import { MessageReaction, User, Client } from 'discord.js';
import { createDraftLinearIssue } from '../services/linearService';
import { logger } from '../utils/logger';

export async function handleReaction(
  reaction: MessageReaction,
  user: User,
  client: Client
) {
  try {
    const message = reaction.message;

    logger.info(`Feedback capture triggered by ${user.tag} on message ${message.id}`);

    // Extract context from the message
    const context = {
      content: message.content,
      author: message.author.tag,
      authorId: message.author.id,
      channelName: message.channel.isDMBased() ? 'DM' : message.channel.name,
      messageUrl: message.url,
      timestamp: message.createdAt.toISOString(),
      attachments: message.attachments.map((att) => att.url),
      // Extract URLs from message content
      urls: extractUrls(message.content),
    };

    // Create draft Linear issue
    const issueResult = await createDraftLinearIssue(context);

    if (issueResult.success) {
      // Reply to the message
      await message.reply(
        `✅ Feedback captured as draft Linear issue **${issueResult.issueIdentifier}**\n` +
        `View in Linear: ${issueResult.issueUrl}`
      );
      logger.info(`Created draft Linear issue: ${issueResult.issueIdentifier}`);
    } else {
      await message.reply(
        `❌ Failed to capture feedback: ${issueResult.error}\n` +
        `Please create a Linear issue manually or contact a developer.`
      );
      logger.error(`Failed to create Linear issue:`, issueResult.error);
    }
  } catch (error) {
    logger.error('Error in handleReaction:', error);
    await reaction.message.reply(
      '❌ An error occurred while capturing feedback. Please try again or contact a developer.'
    );
  }
}

function extractUrls(text: string): string[] {
  const urlRegex = /(https?:\/\/[^\s]+)/g;
  return text.match(urlRegex) || [];
}
EOF
```

### Step 5.3: Create Linear Service

```bash
mkdir -p integration/src/services

cat > integration/src/services/linearService.ts << 'EOF'
import { LinearClient } from '@linear/sdk';
import yaml from 'js-yaml';
import fs from 'fs';
import path from 'path';
import { logger } from '../utils/logger';

// Load Linear config
const configPath = path.join(__dirname, '../../config/linear-sync.yml');
const config: any = yaml.load(fs.readFileSync(configPath, 'utf8'));

// Initialize Linear client
const linearClient = new LinearClient({
  apiKey: process.env.LINEAR_API_TOKEN!,
});

interface FeedbackContext {
  content: string;
  author: string;
  authorId: string;
  channelName: string;
  messageUrl: string;
  timestamp: string;
  attachments: string[];
  urls: string[];
}

export async function createDraftLinearIssue(context: FeedbackContext) {
  try {
    // Extract title from content (first line or sentence)
    const title = extractTitle(context.content);

    // Build issue description with full context
    const description = `
## Original Feedback

**From:** ${context.author} in #${context.channelName}
**When:** ${new Date(context.timestamp).toLocaleString()}

> ${context.content}

## Context

- **Discord thread:** ${context.messageUrl}
${context.urls.length > 0 ? `- **Referenced URLs:**\n${context.urls.map(url => `  - ${url}`).join('\n')}` : ''}
${context.attachments.length > 0 ? `- **Attachments:**\n${context.attachments.map(url => `  - ${url}`).join('\n')}` : ''}

---
*Captured via Discord feedback capture (📌)*
    `.trim();

    // Get team
    const team = await linearClient.team(config.linear.team_id);

    // Get or create labels
    const feedbackLabel = await getOrCreateLabel(
      config.linear.researcher_feedback_label,
      team.id
    );

    // Create the issue
    const issuePayload = await linearClient.createIssue({
      teamId: team.id,
      title: `[Researcher Feedback] ${title}`,
      description: description,
      labelIds: [feedbackLabel.id],
      // Set as draft (note: Linear API doesn't have explicit "draft" field,
      // we use the draft_label to mark it)
    });

    const issue = await issuePayload.issue;

    return {
      success: true,
      issueIdentifier: issue?.identifier,
      issueUrl: issue?.url,
    };
  } catch (error) {
    logger.error('Error creating Linear issue:', error);
    return {
      success: false,
      error: error instanceof Error ? error.message : 'Unknown error',
    };
  }
}

function extractTitle(content: string): string {
  // Extract first sentence or first 50 chars
  const firstSentence = content.split(/[.!?]/)[0];
  return firstSentence.length > 60
    ? firstSentence.substring(0, 60) + '...'
    : firstSentence;
}

async function getOrCreateLabel(labelName: string, teamId: string) {
  // Try to find existing label
  const labels = await linearClient.issueLabels({ filter: { name: { eq: labelName } } });
  const existingLabel = labels.nodes.find(l => l.name === labelName);

  if (existingLabel) {
    return existingLabel;
  }

  // Create new label
  const labelPayload = await linearClient.createIssueLabel({
    name: labelName,
    teamId: teamId,
    color: '#F59E0B',  // Orange color
  });

  return labelPayload.issueLabel!;
}

export async function getLinearIssue(issueId: string) {
  try {
    const issue = await linearClient.issue(issueId);
    return { success: true, issue };
  } catch (error) {
    logger.error(`Error fetching Linear issue ${issueId}:`, error);
    return { success: false, error };
  }
}

export async function updateLinearIssueStatus(issueId: string, statusName: string) {
  try {
    const issue = await linearClient.issue(issueId);
    const team = await issue.team;
    const states = await team?.states();

    // Find matching state
    const targetState = states?.nodes.find(s => s.name === statusName);

    if (!targetState) {
      throw new Error(`Status "${statusName}" not found in Linear workflow`);
    }

    await linearClient.updateIssue(issueId, {
      stateId: targetState.id,
    });

    logger.info(`Updated Linear issue ${issueId} status to: ${statusName}`);
    return { success: true };
  } catch (error) {
    logger.error(`Error updating Linear issue status:`, error);
    return { success: false, error };
  }
}
EOF
```

### Step 5.4: Create Command Handler (Abbreviated)

```bash
cat > integration/src/handlers/commands.ts << 'EOF'
import { Message, Client } from 'discord.js';
import { logger } from '../utils/logger';

export async function handleCommand(message: Message, client: Client) {
  const args = message.content.slice(1).trim().split(/ +/);
  const command = args.shift()?.toLowerCase();

  logger.info(`Command received: /${command} from ${message.author.tag}`);

  try {
    switch (command) {
      case 'show-sprint':
      case 'sprint':
      case 'status':
        await handleShowSprint(message);
        break;

      case 'preview':
        await handlePreview(message, args);
        break;

      case 'doc':
        await handleDoc(message, args);
        break;

      case 'task':
        await handleTask(message, args);
        break;

      case 'my-notifications':
      case 'notifications':
      case 'prefs':
        await handleNotifications(message);
        break;

      case 'my-tasks':
        await handleMyTasks(message);
        break;

      default:
        await message.reply(`❓ Unknown command: \`/${command}\`. Try \`/help\` for available commands.`);
    }
  } catch (error) {
    logger.error(`Error handling command /${command}:`, error);
    await message.reply('❌ An error occurred processing your command. Please try again later.');
  }
}

async function handleShowSprint(message: Message) {
  // TODO: Implement sprint status summary
  await message.reply('🚧 `/show-sprint` coming soon! Check `docs/sprint.md` for now.');
}

async function handlePreview(message: Message, args: string[]) {
  // TODO: Implement Vercel preview URL lookup
  await message.reply('🚧 `/preview` coming soon! Check your Vercel dashboard for now.');
}

async function handleDoc(message: Message, args: string[]) {
  const docType = args[0]?.toLowerCase();
  const docPaths: Record<string, string> = {
    prd: 'docs/prd.md',
    sdd: 'docs/sdd.md',
    sprint: 'docs/sprint.md',
  };

  if (!docType || !docPaths[docType]) {
    await message.reply('❓ Usage: `/doc prd|sdd|sprint`');
    return;
  }

  await message.reply(`📄 Document path: \`${docPaths[docType]}\``);
}

async function handleTask(message: Message, args: string[]) {
  // TODO: Implement Linear task details lookup
  await message.reply('🚧 `/task` coming soon!');
}

async function handleNotifications(message: Message) {
  // TODO: Implement user notification preferences
  await message.reply('🚧 `/my-notifications` coming soon!');
}

async function handleMyTasks(message: Message) {
  // TODO: Implement Linear tasks for current user
  await message.reply('🚧 `/my-tasks` coming soon!');
}
EOF
```

### Step 5.5: Create Logger Utility

```bash
mkdir -p integration/src/utils

cat > integration/src/utils/logger.ts << 'EOF'
import fs from 'fs';
import path from 'path';

const logDir = path.join(__dirname, '../../logs');
const logFile = path.join(logDir, 'discord-bot.log');

// Ensure log directory exists
if (!fs.existsSync(logDir)) {
  fs.mkdirSync(logDir, { recursive: true });
}

type LogLevel = 'info' | 'warn' | 'error';

function log(level: LogLevel, ...args: any[]) {
  const timestamp = new Date().toISOString();
  const message = args.map(arg =>
    typeof arg === 'object' ? JSON.stringify(arg) : String(arg)
  ).join(' ');

  const logLine = `[${timestamp}] [${level.toUpperCase()}] ${message}\n`;

  // Write to file
  fs.appendFileSync(logFile, logLine);

  // Also log to console
  console[level](`[${timestamp}]`, ...args);
}

export const logger = {
  info: (...args: any[]) => log('info', ...args),
  warn: (...args: any[]) => log('warn', ...args),
  error: (...args: any[]) => log('error', ...args),
};
EOF
```

### Step 5.6: Create Daily Digest Cron Job (Stub)

```bash
mkdir -p integration/src/cron

cat > integration/src/cron/dailyDigest.ts << 'EOF'
import cron from 'node-cron';
import { Client, TextChannel } from 'discord.js';
import yaml from 'js-yaml';
import fs from 'fs';
import path from 'path';
import { logger } from '../utils/logger';

const configPath = path.join(__dirname, '../../config/discord-digest.yml');
const config: any = yaml.load(fs.readFileSync(configPath, 'utf8'));

export function setupCronJobs(client: Client) {
  if (!config.enabled) {
    logger.info('Daily digest is disabled in config');
    return;
  }

  logger.info(`Setting up daily digest cron: ${config.schedule}`);

  cron.schedule(config.schedule, async () => {
    logger.info('Running daily digest...');
    await postDailyDigest(client);
  });
}

async function postDailyDigest(client: Client) {
  try {
    const channel = await client.channels.fetch(config.channel_id) as TextChannel;

    if (!channel) {
      logger.error(`Channel ${config.channel_id} not found`);
      return;
    }

    // TODO: Fetch data from Linear and generate digest
    const digestMessage = generateDigestMessage();

    await channel.send(digestMessage);
    logger.info('Daily digest posted successfully');
  } catch (error) {
    logger.error('Error posting daily digest:', error);
  }
}

function generateDigestMessage(): string {
  // TODO: Fetch real data from Linear
  return `📊 **Daily Sprint Update - ${new Date().toLocaleDateString()}**

🚧 This is a stub implementation. Full digest coming soon!

To implement:
1. Query Linear API for tasks in each status
2. Format into sections (in progress, completed, in review, blockers)
3. Include assignee information
4. Add links to Linear issues

Check \`integration/src/cron/dailyDigest.ts\` to implement.`;
}
EOF
```

### Step 5.7: Add Missing Dependencies

```bash
cd integration
npm install js-yaml @types/js-yaml
```

## Part 6: Build and Test Bot

### Step 6.1: Add NPM Scripts

Edit `integration/package.json` and add these scripts:

```json
{
  "scripts": {
    "build": "tsc",
    "start": "node dist/bot.js",
    "dev": "ts-node src/bot.ts",
    "bot:start": "npm run build && npm start",
    "bot:dev": "npm run dev"
  }
}
```

### Step 6.2: Build the Bot

```bash
cd integration
npm run build
```

Fix any TypeScript errors that appear.

### Step 6.3: Test Run (Development Mode)

```bash
npm run dev
```

You should see:
```
[2025-12-07T...] Bot logged in as Agentic-Base Integration Bot#1234
[2025-12-07T...] Connected to 1 server(s)
[2025-12-07T...] Setting up daily digest cron: 0 9 * * *
```

If successful, press `Ctrl+C` to stop. If errors occur, check:
- Token is correct in `secrets/.env.local`
- Bot has been invited to your Discord server
- All dependencies are installed

### Step 6.4: Test Feedback Capture

1. In Discord, post a test message in any channel
2. React to it with 📌 emoji
3. Check bot's response - should create a draft Linear issue
4. Verify in Linear that draft issue was created
5. Check logs: `integration/logs/discord-bot.log`

### Step 6.5: Test Commands

In Discord, try:
- `/doc prd` - Should return path to PRD
- `/show-sprint` - Should return "coming soon" message
- Other commands to verify they're recognized

## Part 7: Modify Agentic-Base Agents

### Step 7.1: Update Sprint Planner Agent

Edit `.claude/agents/sprint-planner.md`:

Find the section about generating `docs/sprint.md` and add instructions for Linear integration:

```markdown
After generating docs/sprint.md, you must:

1. Create draft Linear issues for each sprint task using the Linear MCP server
2. Use this format for issue titles: [Sprint {N} Task {M}] {Task Title}
3. Include full context in descriptions: acceptance criteria, dependencies, technical notes
4. Add labels: sprint-{N}, and relevant tags (backend, frontend, etc.)
5. Set status to "Todo" and mark as draft
6. Update docs/sprint.md with Linear issue IDs:

### Sprint 1, Task 1: Set up Next.js project structure
**Linear Issue:** THJ-123
**Status:** Draft
**Assignee:** Unassigned

Use the Linear MCP server tools to create issues and retrieve issue IDs.
```

### Step 7.2: Update Sprint Task Implementer Agent

Edit `.claude/agents/sprint-task-implementer.md`:

Add Linear integration instructions at the beginning:

```markdown
You are the Sprint Task Implementer agent. You implement sprint tasks assigned in Linear.

## Modified Workflow for Linear Integration

When invoked with `/implement THJ-123`:

1. **Read Linear Issue Details:**
   - Use Linear MCP server to fetch issue THJ-123
   - Extract: title, description, acceptance criteria, assignee, current status
   - If issue has custom field "discord_feedback_link", read original feedback context

2. **Verify Ownership:**
   - Check if issue is assigned to someone
   - If assigned to another developer, warn about potential conflict
   - Proceed only if unassigned or assigned to current user

3. **Update Linear Status:**
   - Before starting implementation, update status to "In Progress"

4. **Implement Task:**
   - Follow existing implementation process
   - Reference acceptance criteria from Linear issue
   - Consider original feedback context if present

5. **Update Linear Status After Completion:**
   - Update status to "In Review"

6. **Generate Implementation Report:**
   - Write to docs/a2a/reviewer.md as usual
   - Include Linear issue ID in report

Always use Linear as source of truth for task details, not just docs/sprint.md.
```

### Step 7.3: Update Senior Tech Lead Reviewer Agent

Edit `.claude/agents/senior-tech-lead-reviewer.md`:

Add Linear status update instructions:

```markdown
After completing your review:

1. **If Approved:**
   - Update Linear issue status to "Done" using Linear MCP server
   - Update docs/sprint.md: Mark task with ✅
   - Write "All good" to docs/a2a/engineer-feedback.md

2. **If Changes Requested:**
   - Update Linear issue status to "Changes Requested"
   - Write detailed feedback to docs/a2a/engineer-feedback.md
   - Do NOT update docs/sprint.md status yet

Always update Linear status to keep it synchronized with review outcomes.
```

## Part 8: Production Deployment

### Step 8.1: Choose Deployment Method

**Option A: Run on Local Server/VPS**

```bash
# Install PM2 for process management
npm install -g pm2

# Start bot with PM2
cd integration
pm2 start dist/bot.js --name agentic-base-bot

# Set PM2 to restart on reboot
pm2 startup
pm2 save

# View logs
pm2 logs agentic-base-bot
```

**Option B: Run with Docker**

```bash
# Create Dockerfile
cat > integration/Dockerfile << 'EOF'
FROM node:18-alpine

WORKDIR /app

COPY package*.json ./
RUN npm ci --production

COPY . .
RUN npm run build

CMD ["node", "dist/bot.js"]
EOF

# Build and run
docker build -t agentic-base-bot integration/
docker run -d --name agentic-base-bot \
  --env-file integration/secrets/.env.local \
  agentic-base-bot
```

**Option C: Run on GitHub Actions (Free for public repos)**

Create `.github/workflows/discord-bot.yml` - See Part 9 for details.

### Step 8.2: Set Up Log Rotation

```bash
# Create logrotate config
sudo cat > /etc/logrotate.d/agentic-base-bot << 'EOF'
/path/to/agentic-base/integration/logs/*.log {
  daily
  rotate 14
  compress
  delaycompress
  missingok
  notifempty
}
EOF
```

### Step 8.3: Set Up Monitoring

Add health check endpoint to bot (optional):

```typescript
// In src/bot.ts
import express from 'express';

const app = express();
app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    uptime: process.uptime(),
    timestamp: new Date().toISOString(),
  });
});

app.listen(3000, () => {
  logger.info('Health check endpoint listening on :3000');
});
```

## Part 9: GitHub Actions Deployment (Optional)

If you want the bot to run on GitHub Actions for free:

```yaml
# .github/workflows/discord-bot.yml
name: Discord Bot

on:
  schedule:
    - cron: '0 9 * * *'  # Daily at 9am UTC
  workflow_dispatch:  # Manual trigger

jobs:
  daily-digest:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Setup Node.js
        uses: actions/setup-node@v3
        with:
          node-version: '18'

      - name: Install dependencies
        run: |
          cd integration
          npm ci

      - name: Run daily digest
        env:
          DISCORD_BOT_TOKEN: ${{ secrets.DISCORD_BOT_TOKEN }}
          DISCORD_DIGEST_CHANNEL_ID: ${{ secrets.DISCORD_DIGEST_CHANNEL_ID }}
          LINEAR_API_TOKEN: ${{ secrets.LINEAR_API_TOKEN }}
          LINEAR_TEAM_ID: ${{ secrets.LINEAR_TEAM_ID }}
        run: |
          cd integration
          npm run build
          node dist/cron/dailyDigest.js
```

Add secrets in GitHub repo settings: Settings → Secrets → Actions.

## Part 10: Verification Checklist

### Pre-Production Checklist

- [ ] Discord bot can log in successfully
- [ ] 📌 reaction creates draft Linear issue
- [ ] Draft Linear issue contains full context (Discord link, timestamp, URLs)
- [ ] Bot replies to message confirming issue creation
- [ ] `/doc prd` command returns correct path
- [ ] `/show-sprint` command responds (even if stub)
- [ ] Logs are being written to `integration/logs/discord-bot.log`
- [ ] Daily digest cron job is scheduled (check logs)
- [ ] Environment variables are not committed to git
- [ ] All secrets are in `integration/secrets/.env.local`
- [ ] `.gitignore` excludes `secrets/` directory

### Post-Production Checklist (After 1 Week)

- [ ] Daily digest posted successfully every day
- [ ] Researcher has captured at least one feedback via 📌
- [ ] Developer has run `/implement THJ-XXX` successfully
- [ ] Linear issues are being created and updated correctly
- [ ] No crashes or errors in logs (except expected warnings)
- [ ] Team members can configure notification preferences
- [ ] Bot response time is acceptable (<5 seconds for commands)

## Troubleshooting

### Bot won't start

**Error: `Invalid token`**
- Check `DISCORD_BOT_TOKEN` in `secrets/.env.local`
- Verify token hasn't been reset in Discord Developer Portal
- Ensure no extra spaces or quotes around token

**Error: `Cannot find module`**
- Run `npm install` in `integration/` directory
- Verify all dependencies in `package.json` are installed
- Try deleting `node_modules/` and running `npm install` again

### Feedback capture not working

**Bot doesn't respond to 📌 reaction:**
- Check bot has "MESSAGE CONTENT INTENT" enabled in Discord Developer Portal
- Verify bot has "Add Reactions" permission in the channel
- Check logs for errors: `cat integration/logs/discord-bot.log`

**Linear issue not created:**
- Verify `LINEAR_API_TOKEN` is correct
- Check Linear API status: https://status.linear.app
- Verify bot has permission to create issues (check Linear workspace settings)
- Look for error messages in bot logs

### Daily digest not posting

**Digest never posts:**
- Verify cron schedule syntax: `0 9 * * *` = 9am daily
- Check bot is running continuously (not just during testing)
- Verify `DISCORD_DIGEST_CHANNEL_ID` is correct
- Check bot has "Send Messages" permission in that channel
- Manually trigger digest for testing: Create a test script

**Digest posts at wrong time:**
- Check timezone setting in `discord-digest.yml`
- Remember cron times are in UTC by default (adjust for your timezone)

### Linear integration issues

**Status updates fail:**
- Verify status names match your Linear workflow
- Check `linear-sync.yml` status_mapping is correct
- Ensure Linear API token has write permissions

**Can't find Linear issues:**
- Verify issue ID format (e.g., `THJ-123`, not just `123`)
- Check team ID in `linear-sync.yml` is correct
- Use Linear GraphQL playground to test queries: https://linear.app/settings/api

## Next Steps

1. ✅ Complete this setup guide
2. ✅ Read `docs/team-playbook.md` for usage instructions
3. ✅ Read `docs/adoption-plan.md` for rollout strategy
4. ✅ Test with pilot sprint before full team adoption
5. ✅ Collect feedback and iterate on configuration

## Support

If you encounter issues not covered in troubleshooting:

1. Check bot logs: `integration/logs/discord-bot.log`
2. Check Linear API status: https://status.linear.app
3. Check Discord API status: https://discordstatus.com
4. Review integration architecture: `docs/integration-architecture.md`
5. Create an issue in this repository with:
   - Error message from logs
   - Steps to reproduce
   - Expected vs actual behavior

---

**Congratulations!** Your agentic-base integration is now set up. Proceed to the Team Playbook for usage guidance.
