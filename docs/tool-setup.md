# DevRel Integration Tool Setup Guide

This guide provides step-by-step instructions for setting up the infrastructure required for the DevRel integration system.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Google Drive MCP Setup](#google-drive-mcp-setup)
3. [Discord Bot Setup](#discord-bot-setup)
4. [Configuration File Setup](#configuration-file-setup)
5. [Scheduling Setup](#scheduling-setup)
6. [Mirror/Paragraph Blog Integration (Optional)](#mirrorparagraph-blog-integration-optional)
7. [Testing Your Setup](#testing-your-setup)
8. [Troubleshooting](#troubleshooting)

---

## Prerequisites

Before starting, ensure you have:

- [ ] Node.js 18+ installed
- [ ] Access to your Google Workspace (admin rights to create service accounts)
- [ ] Discord server with admin permissions
- [ ] Claude Code installed and configured
- [ ] GitHub repository access (for GitHub Actions scheduling)

---

## Google Drive MCP Setup

### Step 1: Enable Google Drive API

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select existing project
3. Navigate to **APIs & Services** > **Library**
4. Search for "Google Drive API"
5. Click **Enable**

### Step 2: Create Service Account

1. Navigate to **APIs & Services** > **Credentials**
2. Click **Create Credentials** > **Service Account**
3. Fill in details:
   - **Service account name**: `devrel-integration`
   - **Service account ID**: `devrel-integration@your-project.iam.gserviceaccount.com`
   - **Description**: "Service account for DevRel integration to read Google Docs"
4. Click **Create and Continue**
5. Skip optional steps (no roles needed)
6. Click **Done**

### Step 3: Generate JSON Key

1. Click on the newly created service account
2. Go to **Keys** tab
3. Click **Add Key** > **Create new key**
4. Select **JSON**
5. Click **Create** - This downloads the JSON key file
6. **IMPORTANT**: Store this file securely (e.g., `~/.config/agentic-base/google-service-account.json`)

### Step 4: Share Google Drive Folders with Service Account

1. Open Google Drive
2. Navigate to the folders you want to monitor (e.g., "Engineering/Projects", "Product/PRDs")
3. Right-click the folder > **Share**
4. Enter the service account email: `devrel-integration@your-project.iam.gserviceaccount.com`
5. Set permission to **Viewer** (read-only)
6. Click **Share**
7. Repeat for all monitored folders

### Step 5: Configure MCP Server

1. Open `.claude/settings.local.json`
2. Add the Google Drive MCP server configuration:

```json
{
  "mcpServers": {
    "gdrive": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-gdrive"],
      "env": {
        "GOOGLE_APPLICATION_CREDENTIALS": "/home/your-user/.config/agentic-base/google-service-account.json"
      }
    }
  }
}
```

3. Replace `/home/your-user/.config/agentic-base/google-service-account.json` with the actual path to your JSON key file

### Step 6: Test Google Drive Access

```bash
# Test MCP server
claude-code mcp test gdrive

# Or manually test with Node.js
node -e "
const { google } = require('googleapis');
const auth = new google.auth.GoogleAuth({
  keyFile: process.env.GOOGLE_APPLICATION_CREDENTIALS,
  scopes: ['https://www.googleapis.com/auth/drive.readonly'],
});
const drive = google.drive({ version: 'v3', auth });
drive.files.list({ pageSize: 10 }).then(res => {
  console.log('Files:', res.data.files.map(f => f.name));
});
"
```

---

## Discord Bot Setup

### Step 1: Create Discord Application

1. Go to [Discord Developer Portal](https://discord.com/developers/applications)
2. Click **New Application**
3. Enter name: "DevRel Integration Bot"
4. Accept terms and click **Create**

### Step 2: Configure Bot

1. Navigate to **Bot** tab in left sidebar
2. Click **Add Bot** > **Yes, do it!**
3. Under **Privileged Gateway Intents**, enable:
   - ✅ **Message Content Intent** (to read messages)
4. Click **Reset Token** to get your bot token
5. **IMPORTANT**: Copy the token immediately and store securely (you won't see it again)

### Step 3: Set Bot Permissions

1. Navigate to **OAuth2** > **URL Generator**
2. Under **Scopes**, select:
   - ✅ `bot`
3. Under **Bot Permissions**, select:
   - ✅ Send Messages
   - ✅ Create Public Threads
   - ✅ Send Messages in Threads
   - ✅ Add Reactions
   - ✅ Read Message History
4. Copy the generated URL at the bottom

### Step 4: Invite Bot to Server

1. Paste the URL from Step 3 into your browser
2. Select your Discord server
3. Click **Authorize**
4. Complete the CAPTCHA

### Step 5: Create Discord Channels

1. In your Discord server, create a new channel: **#exec-summary**
2. Right-click the channel > **Edit Channel**
3. Go to **Permissions**
4. Ensure the bot has permissions:
   - ✅ View Channel
   - ✅ Send Messages
   - ✅ Create Public Threads
   - ✅ Add Reactions

### Step 6: Configure MCP Server

1. Open `.claude/settings.local.json`
2. Add Discord MCP server configuration:

```json
{
  "mcpServers": {
    "gdrive": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-gdrive"],
      "env": {
        "GOOGLE_APPLICATION_CREDENTIALS": "/home/your-user/.config/agentic-base/google-service-account.json"
      }
    },
    "discord": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-discord"],
      "env": {
        "DISCORD_BOT_TOKEN": "${DISCORD_BOT_TOKEN}",
        "DISCORD_DEFAULT_SERVER_ID": "your-server-id"
      }
    }
  }
}
```

3. Replace `your-server-id` with your Discord server ID
   - To get server ID: Right-click server icon > **Copy Server ID** (enable Developer Mode in Discord settings if not visible)

### Step 7: Store Discord Bot Token Securely

1. Create `.env` file in the root of your project:

```bash
# .env
DISCORD_BOT_TOKEN=your_discord_bot_token_here
DISCORD_EXEC_SUMMARY_CHANNEL_ID=your_channel_id_here
```

2. Get the channel ID:
   - Right-click #exec-summary channel > **Copy Channel ID**
   - Paste into `.env` file

3. **IMPORTANT**: Add `.env` to `.gitignore` to avoid committing secrets

### Step 8: Test Discord Bot

```bash
# Test MCP server
claude-code mcp test discord

# Or manually test with Discord.js
node -e "
const { Client, GatewayIntentBits } = require('discord.js');
const client = new Client({ intents: [GatewayIntentBits.Guilds, GatewayIntentBits.GuildMessages] });
client.on('ready', () => {
  console.log('Bot is ready!');
  console.log('Servers:', client.guilds.cache.map(g => g.name));
  process.exit(0);
});
client.login(process.env.DISCORD_BOT_TOKEN);
"
```

---

## Configuration File Setup

### Step 1: Create Configuration File

1. Copy the example configuration:

```bash
cp integration/config/devrel-integration.config.example.yaml integration/config/devrel-integration.config.yaml
```

2. If example doesn't exist yet, create the file manually:

```bash
mkdir -p integration/config
touch integration/config/devrel-integration.config.yaml
```

### Step 2: Configure Monitored Folders

1. Open `integration/config/devrel-integration.config.yaml`
2. Update `google_docs.monitored_folders` with your Google Drive folder paths:

```yaml
google_docs:
  monitored_folders:
    - "Engineering/Projects"
    - "Product/PRDs"
    - "Security/Audits"
  exclude_patterns:
    - "**/Meeting Notes/**"
    - "**/Draft/**"
    - "**/Archive/**"
  change_detection_window_days: 7
```

3. To get folder paths:
   - Open Google Drive
   - Navigate to the folder
   - Copy the path from the URL or breadcrumb

### Step 3: Configure Department Mapping

1. Map user IDs to departments:

```yaml
department_mapping:
  user_id_to_department:
    "123456789": "product"        # Your PM's Discord user ID
    "987654321": "executive"      # Your COO's Discord user ID
    "555555555": "marketing"      # Marketing lead's Discord user ID

  role_to_department:
    "@leadership": "executive"
    "@product": "product"
    "@marketing": "marketing"
    "@engineering": "engineering"

  default_format: "unified"
  allow_format_override: true
```

2. To get Discord user IDs:
   - Right-click user in Discord > **Copy User ID** (Developer Mode must be enabled)

### Step 4: Configure Schedule

```yaml
schedule:
  weekly_digest: "0 9 * * FRI"  # Every Friday at 9am UTC
  timezone: "UTC"
```

Cron format: `minute hour day-of-month month day-of-week`
- `0 9 * * FRI` = Every Friday at 9:00am
- `0 17 * * *` = Every day at 5:00pm
- `0 9 * * MON,FRI` = Every Monday and Friday at 9:00am

### Step 5: Validate Configuration

```bash
# Install dependencies
npm install js-yaml

# Validate YAML syntax
node -e "
const yaml = require('js-yaml');
const fs = require('fs');
try {
  const config = yaml.load(fs.readFileSync('integration/config/devrel-integration.config.yaml', 'utf8'));
  console.log('✅ Configuration is valid');
  console.log(JSON.stringify(config, null, 2));
} catch (e) {
  console.error('❌ Configuration error:', e.message);
}
"
```

---

## Scheduling Setup

You have two options for scheduling weekly digests:

### Option A: GitHub Actions (Recommended)

**Pros**: No server needed, runs in the cloud, easy to manage
**Cons**: Requires GitHub repository

#### Step 1: Create Workflow File

1. Create `.github/workflows/weekly-digest.yml`:

```yaml
name: Weekly DevRel Digest

on:
  schedule:
    - cron: '0 9 * * FRI'  # Every Friday 9am UTC
  workflow_dispatch:  # Allow manual trigger

jobs:
  generate-digest:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout repository
        uses: actions/checkout@v3

      - name: Setup Node.js
        uses: actions/setup-node@v3
        with:
          node-version: '18'

      - name: Install dependencies
        run: |
          cd integration
          npm ci

      - name: Generate Weekly Digest
        env:
          GOOGLE_APPLICATION_CREDENTIALS_JSON: ${{ secrets.GOOGLE_SERVICE_ACCOUNT_KEY }}
          DISCORD_BOT_TOKEN: ${{ secrets.DISCORD_BOT_TOKEN }}
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
        run: |
          # Write service account key to file
          echo "$GOOGLE_APPLICATION_CREDENTIALS_JSON" > /tmp/google-sa-key.json
          export GOOGLE_APPLICATION_CREDENTIALS=/tmp/google-sa-key.json

          # Run weekly digest
          cd integration
          npm run weekly-digest

      - name: Notify on Failure
        if: failure()
        run: |
          curl -X POST "${{ secrets.DISCORD_WEBHOOK_URL }}" \
            -H "Content-Type: application/json" \
            -d '{"content": "❌ Weekly digest generation failed. Check GitHub Actions logs."}'
```

#### Step 2: Add GitHub Secrets

1. Go to your GitHub repository > **Settings** > **Secrets and variables** > **Actions**
2. Click **New repository secret** for each:

| Secret Name | Value |
|------------|-------|
| `GOOGLE_SERVICE_ACCOUNT_KEY` | Base64-encoded JSON key file (see below) |
| `DISCORD_BOT_TOKEN` | Your Discord bot token |
| `ANTHROPIC_API_KEY` | Your Anthropic API key |
| `DISCORD_WEBHOOK_URL` | (Optional) Webhook URL for failure alerts |

3. To base64-encode the Google service account key:

```bash
cat ~/.config/agentic-base/google-service-account.json | base64 -w 0
```

4. Copy the output and paste as `GOOGLE_SERVICE_ACCOUNT_KEY`

#### Step 3: Test Workflow

1. Go to **Actions** tab in GitHub
2. Select "Weekly DevRel Digest" workflow
3. Click **Run workflow** > **Run workflow** (manual trigger)
4. Monitor the logs to ensure it runs successfully

---

### Option B: Cron Job (Local/Server)

**Pros**: Full control, can run on your own server
**Cons**: Requires a server to be always running

#### Step 1: Create Cron Script

1. Create `integration/scripts/run-weekly-digest.sh`:

```bash
#!/bin/bash

# Load environment variables
export $(cat /path/to/.env | xargs)

# Set Google credentials
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/google-service-account.json

# Navigate to integration directory
cd /path/to/agentic-base/integration

# Run weekly digest
npm run weekly-digest

# Check exit code
if [ $? -ne 0 ]; then
  # Send failure notification to Discord
  curl -X POST "$DISCORD_WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d '{"content": "❌ Weekly digest generation failed."}'
fi
```

2. Make script executable:

```bash
chmod +x integration/scripts/run-weekly-digest.sh
```

#### Step 2: Setup Cron Job

1. Edit crontab:

```bash
crontab -e
```

2. Add the following line:

```cron
# Weekly DevRel Digest - Every Friday at 9am
0 9 * * FRI /path/to/agentic-base/integration/scripts/run-weekly-digest.sh >> /var/log/devrel-digest.log 2>&1
```

3. Save and exit

#### Step 3: Test Cron Job

```bash
# Test script manually
./integration/scripts/run-weekly-digest.sh

# Check cron logs
tail -f /var/log/devrel-digest.log
```

---

## Mirror/Paragraph Blog Integration (Optional)

If you want to auto-publish approved summaries to your crypto blog:

### Step 1: Create Mirror/Paragraph Account

1. Go to [Mirror.xyz](https://mirror.xyz/) or [Paragraph.xyz](https://paragraph.xyz/)
2. Create account or sign in with wallet
3. Create your publication

### Step 2: Get API Key

1. Go to **Settings** > **API Keys** (or equivalent)
2. Generate a new API key
3. Copy the API key

### Step 3: Add to Environment Variables

1. Open `.env` file
2. Add:

```bash
MIRROR_API_KEY=your_mirror_api_key_here
```

3. If using GitHub Actions, add `MIRROR_API_KEY` to GitHub Secrets

### Step 4: Enable in Configuration

1. Open `integration/config/devrel-integration.config.yaml`
2. Update blog settings:

```yaml
distribution:
  blog:
    enabled: true  # Set to true
    platforms:
      - "mirror"  # or "paragraph" or "company_website"
    auto_publish: false  # Keep false for manual approval
```

---

## Testing Your Setup

### Test 1: Google Docs Access

```bash
# Run test script
npm run test-google-docs

# Or manually:
node integration/tests/test-google-docs.js
```

Expected output:
```
✅ Google Docs API connected
✅ Found 15 documents in monitored folders
✅ Successfully fetched document: "PRD - Feature X"
```

### Test 2: Discord Bot

```bash
# Run test script
npm run test-discord

# Or manually:
node integration/tests/test-discord.js
```

Expected output:
```
✅ Discord bot connected
✅ Found server: "Your Server Name"
✅ Found channel: "exec-summary"
✅ Successfully posted test message
```

### Test 3: Configuration Validation

```bash
# Run validation script
npm run validate-config

# Or manually:
node integration/scripts/validate-config.js
```

Expected output:
```
✅ Configuration file is valid
✅ All required fields present
✅ Department mappings valid
✅ Schedule format valid (cron)
```

### Test 4: End-to-End Dry Run

```bash
# Run weekly digest in dry-run mode (doesn't post to Discord)
npm run weekly-digest -- --dry-run
```

Expected output:
```
✅ Scanned Google Docs: 5 documents changed
✅ Classified documents: 2 PRDs, 1 sprint update, 2 audits
✅ Generated translations: unified format
✅ [DRY RUN] Would create Google Doc: "Weekly Digest - 2025-12-08"
✅ [DRY RUN] Would post to Discord: #exec-summary
```

### Test 5: Manual Summary Generation

```bash
# Test manual trigger (CLI)
npm run generate-summary -- --format=executive --docs=docs/sprint.md

# Or via Discord (in #exec-summary channel):
/generate-summary --format=executive
```

Expected output:
```
✅ Department detected: executive
✅ Format loaded: executive (1-page, low technical)
✅ Translation generated
✅ Google Doc created: https://docs.google.com/document/d/...
✅ Discord thread created: https://discord.com/channels/...
```

---

## Troubleshooting

### Issue: "Google Docs API authentication failed"

**Solution**:
1. Check that `GOOGLE_APPLICATION_CREDENTIALS` environment variable is set correctly
2. Verify the JSON key file exists and is readable
3. Ensure the service account has access to the monitored folders:
   - Open Google Drive
   - Navigate to folder
   - Check that `devrel-integration@your-project.iam.gserviceaccount.com` is listed in **Share** settings

### Issue: "Discord bot not responding"

**Solution**:
1. Check that bot is online in Discord (should have green status)
2. Verify `DISCORD_BOT_TOKEN` is correct
3. Ensure bot has correct permissions in #exec-summary channel:
   ```bash
   # Check bot permissions
   node -e "
   const { Client } = require('discord.js');
   const client = new Client({ intents: ['Guilds'] });
   client.on('ready', async () => {
     const channel = await client.channels.fetch(process.env.DISCORD_EXEC_SUMMARY_CHANNEL_ID);
     const permissions = channel.permissionsFor(client.user);
     console.log('Bot permissions:', permissions.toArray());
     process.exit(0);
   });
   client.login(process.env.DISCORD_BOT_TOKEN);
   "
   ```

### Issue: "Configuration file not found"

**Solution**:
1. Ensure file exists: `integration/config/devrel-integration.config.yaml`
2. Check that the path in your code matches:
   ```javascript
   const configPath = path.join(__dirname, '../config/devrel-integration.config.yaml');
   ```

### Issue: "Department detection not working"

**Solution**:
1. Verify user ID mapping in config:
   ```yaml
   department_mapping:
     user_id_to_department:
       "123456789": "product"  # Correct user ID?
   ```
2. Enable Discord Developer Mode to copy user IDs:
   - Discord > Settings > Advanced > Developer Mode (toggle on)
3. Test detection:
   ```bash
   npm run test-department-detection -- --user-id=123456789
   ```

### Issue: "Weekly digest not running on schedule"

**GitHub Actions**:
1. Check workflow is enabled:
   - Go to Actions tab > Select workflow > Check if disabled
2. View workflow logs:
   - Actions tab > Select run > View logs
3. Verify secrets are set:
   - Settings > Secrets and variables > Actions

**Cron**:
1. Check cron service is running:
   ```bash
   systemctl status cron
   ```
2. View cron logs:
   ```bash
   grep CRON /var/log/syslog
   ```
3. Verify crontab entry:
   ```bash
   crontab -l
   ```

### Issue: "Translation generation timeout"

**Solution**:
1. Check Anthropic API key is valid:
   ```bash
   curl -H "x-api-key: $ANTHROPIC_API_KEY" https://api.anthropic.com/v1/models
   ```
2. Increase timeout in config:
   ```yaml
   translation:
     timeout_seconds: 300  # Increase from default 120
   ```
3. Check if documents are too large (>50 pages):
   - Consider splitting large documents or summarizing them first

### Issue: "Mirror/Paragraph publishing failed"

**Solution**:
1. Verify API key is correct
2. Check API rate limits (may need to wait)
3. Ensure content format is valid markdown
4. Test API directly:
   ```bash
   curl -X POST https://mirror.xyz/api/publish \
     -H "Authorization: Bearer $MIRROR_API_KEY" \
     -H "Content-Type: application/json" \
     -d '{"title": "Test", "content": "Test content"}'
   ```

---

## Next Steps

After completing this setup:

1. ✅ Test all components individually
2. ✅ Run end-to-end dry-run test
3. ✅ Generate first manual summary for review
4. ✅ Schedule first automated weekly digest
5. ✅ Read the [Team Playbook](team-playbook.md) for usage instructions
6. ✅ Review the [Integration Architecture](devrel-integration-architecture.md) for design details

---

## Support

If you encounter issues not covered in this guide:

1. Check implementation logs: `tail -f integration/logs/devrel.log`
2. Run diagnostics: `npm run diagnose`
3. Review the [Integration Architecture](devrel-integration-architecture.md) for design context
4. Consult the implementation team for custom troubleshooting

---

**Setup complete!** 🎉

You're now ready to run `/implement-org-integration` to build the actual integration code.
