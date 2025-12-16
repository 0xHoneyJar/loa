# Credentials Setup Guide

> Complete step-by-step guide to create all required tokens and credentials for Onomancer Bot deployment.

**Document Version:** 1.0
**Last Updated:** December 2024
**Estimated Time:** 1-2 hours

## Table of Contents

1. [Overview](#overview)
2. [Discord Setup](#discord-setup)
3. [Google Cloud Setup](#google-cloud-setup)
4. [Linear Setup](#linear-setup)
5. [Anthropic Setup](#anthropic-setup)
6. [Verification Checklist](#verification-checklist)
7. [Security Best Practices](#security-best-practices)
8. [Troubleshooting](#troubleshooting)

---

## Overview

Before deploying the Onomancer Bot, you need credentials from four services:

| Service | What You'll Create | Used For |
|---------|-------------------|----------|
| **Discord** | Bot Token, Client ID, Guild ID, Role IDs, Channel IDs | Bot authentication, RBAC, message posting |
| **Google Cloud** | Service Account + JSON Key, Folder IDs | Google Docs creation, Drive storage |
| **Linear** | API Token, Team ID | Issue tracking, sprint management |
| **Anthropic** | API Key | AI-powered document transformation |

### Prerequisites

- Email address for account creation
- Credit card (Google Cloud requires it but offers $300 free credit)
- Access to the Discord server where bot will run (with admin permissions)
- ~1-2 hours of uninterrupted time

### What You'll Have at the End

A completed `secrets/.env.local` file with all required values:

```bash
# Discord
DISCORD_BOT_TOKEN=YOUR_BOT_TOKEN_HERE
DISCORD_CLIENT_ID=1097...
DISCORD_GUILD_ID=1234...
DISCORD_DIGEST_CHANNEL_ID=1234...
ADMIN_ROLE_ID=1234...
DEVELOPER_ROLE_ID=1234...

# Google Cloud
GOOGLE_SERVICE_ACCOUNT_EMAIL=bot@project.iam.gserviceaccount.com
GOOGLE_SERVICE_ACCOUNT_KEY_PATH=/path/to/service-account.json
GOOGLE_FOLDER_LEADERSHIP=1abc...
GOOGLE_FOLDER_PRODUCT=2def...
GOOGLE_FOLDER_MARKETING=3ghi...
GOOGLE_FOLDER_DEVREL=4jkl...
GOOGLE_FOLDER_ORIGINALS=5mno...

# Linear
LINEAR_API_TOKEN=lin_api_...
LINEAR_TEAM_ID=abc-123-def

# Anthropic
ANTHROPIC_API_KEY=sk-ant-...
```

---

## Discord Setup

> Time: ~20 minutes

### Step 1: Access Discord Developer Portal

1. Open your web browser
2. Go to: **https://discord.com/developers/applications**
3. Log in with your Discord account (or create one if needed)

### Step 2: Create New Application

1. Click the **"New Application"** button (top right)
2. Enter application name: `Onomancer Bot` (or your preferred name)
3. Check the box to agree to Discord's Terms of Service
4. Click **"Create"**

You'll be taken to the application's General Information page.

### Step 3: Note the Application ID (Client ID)

1. On the **General Information** page
2. Find **"APPLICATION ID"**
3. Click **"Copy"** button next to it
4. Save this as `DISCORD_CLIENT_ID`:

```bash
DISCORD_CLIENT_ID=1097123456789012345
```

### Step 4: Create Bot User

1. In the left sidebar, click **"Bot"**
2. Click **"Add Bot"** button
3. Click **"Yes, do it!"** to confirm
4. Your bot is now created

### Step 5: Configure Bot Settings

On the Bot page, configure these settings:

**Public Bot:**
- [ ] Uncheck "Public Bot" (recommended - prevents others from adding your bot)

**Privileged Gateway Intents** (CRITICAL - enable all three):
- [x] **PRESENCE INTENT** - Optional but recommended
- [x] **SERVER MEMBERS INTENT** - Required for role checks
- [x] **MESSAGE CONTENT INTENT** - Required to read messages

Click **"Save Changes"** at the bottom.

### Step 6: Get Bot Token

1. On the Bot page, find the **"TOKEN"** section
2. Click **"Reset Token"** (or "View Token" if first time)
3. If prompted, complete 2FA verification
4. Click **"Copy"** to copy the token

**CRITICAL**: This token is shown only once. Save it immediately:

```bash
DISCORD_BOT_TOKEN=YOUR_BOT_TOKEN_HERE
```

**Security Warning**: Never share this token. Anyone with it can control your bot.

### Step 7: Configure OAuth2 Permissions

1. In left sidebar, click **"OAuth2"** → **"URL Generator"**
2. Under **SCOPES**, check:
   - [x] `bot`
   - [x] `applications.commands`

3. Under **BOT PERMISSIONS**, check:
   - [x] Read Messages/View Channels
   - [x] Send Messages
   - [x] Send Messages in Threads
   - [x] Create Public Threads
   - [x] Embed Links
   - [x] Attach Files
   - [x] Add Reactions
   - [x] Use Slash Commands
   - [x] Read Message History
   - [x] Mention Everyone (optional, for alerts)

4. Copy the **Generated URL** at the bottom of the page

### Step 8: Invite Bot to Your Server

1. Paste the generated URL into your browser
2. Select your Discord server from the dropdown
3. Click **"Continue"**
4. Review permissions and click **"Authorize"**
5. Complete the CAPTCHA

Your bot should now appear in your server's member list (offline until deployed).

### Step 9: Enable Developer Mode in Discord

To copy IDs, you need Developer Mode enabled:

1. Open Discord (desktop app or browser)
2. Click the **gear icon** (User Settings) at bottom left
3. Scroll down to **"Advanced"** in left sidebar
4. Toggle **"Developer Mode"** ON

### Step 10: Get Guild ID (Server ID)

1. In Discord, right-click on your **server name** (top of channel list)
2. Click **"Copy Server ID"**
3. Save this value:

```bash
DISCORD_GUILD_ID=1234567890123456789
```

### Step 11: Create Required Roles

If your server doesn't already have these roles, create them:

1. Go to **Server Settings** → **Roles**
2. Click **"Create Role"**
3. Create three roles:
   - **Admin** - Full bot control
   - **Developer** - Can use dev commands
   - **Researcher** - Can capture feedback (optional)

### Step 12: Get Role IDs

1. Go to **Server Settings** → **Roles**
2. Right-click on **Admin** role → **"Copy Role ID"**
3. Save as `ADMIN_ROLE_ID`
4. Repeat for **Developer** role → save as `DEVELOPER_ROLE_ID`
5. Repeat for **Researcher** role → save as `RESEARCHER_ROLE_ID` (optional)

```bash
ADMIN_ROLE_ID=1234567890123456789
DEVELOPER_ROLE_ID=1234567890123456790
RESEARCHER_ROLE_ID=1234567890123456791
```

### Step 13: Create Required Channels

Create these channels if they don't exist:

1. **#sprint-digest** - For daily sprint updates
2. **#alerts** - For critical notifications (optional)

### Step 14: Get Channel IDs

1. Right-click on **#sprint-digest** channel → **"Copy Channel ID"**
2. Save as `DISCORD_DIGEST_CHANNEL_ID`
3. Right-click on **#alerts** channel → **"Copy Channel ID"**
4. Save as `DISCORD_ALERTS_CHANNEL_ID`

```bash
DISCORD_DIGEST_CHANNEL_ID=1234567890123456792
DISCORD_ALERTS_CHANNEL_ID=1234567890123456793
```

### Discord Setup Complete!

You should now have these values:
- [x] `DISCORD_BOT_TOKEN`
- [x] `DISCORD_CLIENT_ID`
- [x] `DISCORD_GUILD_ID`
- [x] `DISCORD_DIGEST_CHANNEL_ID`
- [x] `DISCORD_ALERTS_CHANNEL_ID` (optional)
- [x] `ADMIN_ROLE_ID`
- [x] `DEVELOPER_ROLE_ID`
- [x] `RESEARCHER_ROLE_ID` (optional)

---

## Google Cloud Setup

> Time: ~30-45 minutes (longer for brand new accounts)

This section assumes a **brand new Google Cloud account**. If you already have Google Cloud set up, skip to [Step 5](#step-5-enable-required-apis).

### Step 1: Create Google Account (if needed)

If you don't have a Google account:

1. Go to **https://accounts.google.com/signup**
2. Follow the prompts to create an account
3. Verify your email and phone number

### Step 2: Access Google Cloud Console

1. Go to **https://console.cloud.google.com/**
2. Sign in with your Google account
3. Accept the Terms of Service

### Step 3: Set Up Billing (Required)

Google Cloud requires a billing account, but offers **$300 free credit** for new accounts.

1. Click **"Activate"** or go to **Billing** in the left menu
2. Click **"Create Billing Account"**
3. Select your country
4. Enter payment method (credit card required, but won't be charged for free tier)
5. Complete the setup

**Note**: The free tier includes 2 million Drive API requests/month - more than enough for this bot.

### Step 4: Create a New Project

1. Click the project dropdown at the top (may say "Select a project")
2. Click **"NEW PROJECT"**
3. Enter project name: `onomancer-bot` (or your preferred name)
4. Leave organization as default (or select if applicable)
5. Click **"Create"**
6. Wait for project creation (notification bell will show when done)
7. Select your new project from the dropdown

### Step 5: Enable Required APIs

You need to enable Google Drive API and Google Docs API.

**Enable Google Drive API:**

1. Go to **APIs & Services** → **Library** (left sidebar)
2. Search for **"Google Drive API"**
3. Click on **Google Drive API**
4. Click **"Enable"**
5. Wait for it to enable

**Enable Google Docs API:**

1. Go back to **APIs & Services** → **Library**
2. Search for **"Google Docs API"**
3. Click on **Google Docs API**
4. Click **"Enable"**

### Step 6: Create Service Account

1. Go to **IAM & Admin** → **Service Accounts** (left sidebar)
2. Click **"+ CREATE SERVICE ACCOUNT"** at the top
3. Enter service account details:
   - **Service account name**: `onomancer-bot`
   - **Service account ID**: (auto-generated, e.g., `onomancer-bot@project.iam.gserviceaccount.com`)
   - **Description**: `Service account for Onomancer Discord bot`
4. Click **"CREATE AND CONTINUE"**

### Step 7: Grant Service Account Permissions

On the "Grant this service account access to project" step:

1. Click **"Select a role"** dropdown
2. Search for and select **"Editor"** (under Basic)
   - Or for more restrictive: "Drive API" + "Docs API" specific roles
3. Click **"CONTINUE"**
4. Skip "Grant users access" (click **"DONE"**)

### Step 8: Create and Download JSON Key

1. In the Service Accounts list, find your new service account
2. Click on the service account email
3. Go to the **"KEYS"** tab
4. Click **"ADD KEY"** → **"Create new key"**
5. Select **"JSON"** format
6. Click **"CREATE"**

A JSON file will automatically download. This is your service account key.

**CRITICAL**:
- This file is downloaded only once
- Store it securely
- Never commit it to git

### Step 9: Secure the Key File

1. Rename the downloaded file to something memorable:
   ```bash
   mv ~/Downloads/project-name-abc123.json ~/secure-location/gcp-service-account.json
   ```

2. Set restrictive permissions:
   ```bash
   chmod 600 ~/secure-location/gcp-service-account.json
   ```

3. Note the full path for your `.env.local`:
   ```bash
   GOOGLE_SERVICE_ACCOUNT_KEY_PATH=/home/user/secure-location/gcp-service-account.json
   ```

### Step 10: Get Service Account Email

1. Go back to **IAM & Admin** → **Service Accounts**
2. Copy the **Email** of your service account (e.g., `onomancer-bot@project-id.iam.gserviceaccount.com`)
3. Save this value:

```bash
GOOGLE_SERVICE_ACCOUNT_EMAIL=onomancer-bot@project-id.iam.gserviceaccount.com
```

### Step 11: Create Google Drive Folders

Now you need to create folders in Google Drive and share them with the service account.

1. Go to **https://drive.google.com/**
2. Create a parent folder: **"Onomancer Bot Documents"** (optional, for organization)
3. Inside that folder (or at root), create these 5 folders:
   - **Leadership** - For leadership/exec translations
   - **Product** - For product team translations
   - **Marketing** - For marketing translations
   - **DevRel** - For developer relations translations
   - **Originals** - For storing source document copies

### Step 12: Share Folders with Service Account

For **each** folder you created:

1. Right-click the folder → **"Share"**
2. In the "Add people and groups" field, paste your service account email:
   ```
   onomancer-bot@project-id.iam.gserviceaccount.com
   ```
3. Set permission to **"Editor"**
4. Uncheck "Notify people" (service accounts can't receive emails)
5. Click **"Share"**

Repeat for all 5 folders.

### Step 13: Get Folder IDs

For **each** folder:

1. Open the folder in Google Drive
2. Look at the URL in your browser:
   ```
   https://drive.google.com/drive/folders/1AbCdEfGhIjKlMnOpQrStUvWxYz
                                          ^^^^^^^^^^^^^^^^^^^^^^^^
                                          This is the Folder ID
   ```
3. Copy the folder ID (the long string after `/folders/`)

Save each folder ID:

```bash
GOOGLE_FOLDER_LEADERSHIP=1AbCdEfGhIjKlMnOpQrStUvWxYz
GOOGLE_FOLDER_PRODUCT=2BcDeFgHiJkLmNoPqRsTuVwXyZa
GOOGLE_FOLDER_MARKETING=3CdEfGhIjKlMnOpQrStUvWxYzAb
GOOGLE_FOLDER_DEVREL=4DeFgHiJkLmNoPqRsTuVwXyZaBc
GOOGLE_FOLDER_ORIGINALS=5EfGhIjKlMnOpQrStUvWxYzAbCd
```

### Google Cloud Setup Complete!

You should now have these values:
- [x] `GOOGLE_SERVICE_ACCOUNT_EMAIL`
- [x] `GOOGLE_SERVICE_ACCOUNT_KEY_PATH` (and the actual JSON file)
- [x] `GOOGLE_FOLDER_LEADERSHIP`
- [x] `GOOGLE_FOLDER_PRODUCT`
- [x] `GOOGLE_FOLDER_MARKETING`
- [x] `GOOGLE_FOLDER_DEVREL`
- [x] `GOOGLE_FOLDER_ORIGINALS`

---

## Linear Setup

> Time: ~10 minutes

### Step 1: Create Linear Account (if needed)

1. Go to **https://linear.app/**
2. Click **"Get started"** or **"Sign up"**
3. Sign up with Google, email, or SSO
4. Create or join a workspace

### Step 2: Navigate to API Settings

1. Click your **profile icon** (bottom left)
2. Click **"Settings"**
3. In the left sidebar, click **"API"**

### Step 3: Create Personal API Key

1. Under **"Personal API keys"**, click **"Create key"**
2. Enter a label: `Onomancer Bot` (or your preferred name)
3. Click **"Create"**
4. **IMPORTANT**: Copy the key immediately (shown only once!)

Save the token:

```bash
LINEAR_API_TOKEN=lin_api_YOUR_TOKEN_HERE
```

**Note**: The token starts with `lin_api_` followed by ~40 alphanumeric characters.

### Step 4: Get Team ID

You need your Linear team's UUID. There are two ways to get it:

**Option A: Via GraphQL Query**

Run this curl command (replace `YOUR_TOKEN` with your API token):

```bash
curl -X POST https://api.linear.app/graphql \
  -H "Authorization: YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"query":"{ teams { nodes { id name key } } }"}'
```

Look for your team in the response:
```json
{
  "data": {
    "teams": {
      "nodes": [
        {
          "id": "abc12345-6789-0abc-def1-234567890abc",
          "name": "Your Team Name",
          "key": "TEAM"
        }
      ]
    }
  }
}
```

Copy the `id` value.

**Option B: Via Linear UI**

1. Go to your team's page in Linear
2. Click on **Settings** (gear icon) for the team
3. The team ID is in the URL or in the team settings

Save the team ID:

```bash
LINEAR_TEAM_ID=abc12345-6789-0abc-def1-234567890abc
```

### Step 5: (Optional) Configure Webhook Secret

If you plan to use Linear webhooks:

1. In Linear Settings → API
2. Scroll to **"Webhooks"**
3. Click **"New webhook"**
4. Configure the webhook URL (your server endpoint)
5. Generate and copy the signing secret

```bash
LINEAR_WEBHOOK_SECRET=your_webhook_signing_secret
```

### Step 6: Verify API Access

Test that your token works:

```bash
curl -X POST https://api.linear.app/graphql \
  -H "Authorization: YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"query":"{ viewer { id name email } }"}'
```

Expected response:
```json
{
  "data": {
    "viewer": {
      "id": "...",
      "name": "Your Name",
      "email": "your@email.com"
    }
  }
}
```

### Linear Setup Complete!

You should now have these values:
- [x] `LINEAR_API_TOKEN`
- [x] `LINEAR_TEAM_ID`
- [x] `LINEAR_WEBHOOK_SECRET` (optional)

---

## Anthropic Setup

> Time: ~10 minutes

### Step 1: Create Anthropic Account

1. Go to **https://console.anthropic.com/**
2. Click **"Sign up"** (or "Get started")
3. Sign up with Google or email
4. Verify your email address

### Step 2: Complete Account Setup

1. Complete any required verification steps
2. You may need to:
   - Verify phone number
   - Accept terms of service
   - Complete a brief questionnaire

### Step 3: Add Payment Method (if required)

Anthropic requires a payment method for API access:

1. Go to **Settings** → **Billing**
2. Add a credit card
3. (Optional) Set usage limits to prevent surprises

**Pricing Note**: Claude API costs vary by model:
- Claude 3 Haiku: ~$0.25 per million input tokens
- Claude 3 Sonnet: ~$3 per million input tokens
- Claude 3 Opus: ~$15 per million input tokens

The bot uses Sonnet by default. Typical usage: $5-20/month depending on volume.

### Step 4: Navigate to API Keys

1. Click on your **profile/organization name** (top right or left sidebar)
2. Click **"API Keys"** (or go to https://console.anthropic.com/settings/keys)

### Step 5: Create API Key

1. Click **"Create Key"**
2. Enter a name: `Onomancer Bot`
3. Click **"Create Key"**
4. **IMPORTANT**: Copy the key immediately (shown only once!)

Save the key:

```bash
ANTHROPIC_API_KEY=sk-ant-api03-YOUR_KEY_HERE
```

**Note**: The key starts with `sk-ant-` and is quite long (~100+ characters).

### Step 6: Verify API Access

Test that your key works:

```bash
curl https://api.anthropic.com/v1/messages \
  -H "x-api-key: YOUR_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{
    "model": "claude-3-haiku-20240307",
    "max_tokens": 100,
    "messages": [{"role": "user", "content": "Say hello"}]
  }'
```

Expected response:
```json
{
  "content": [{"type": "text", "text": "Hello! How can I help you today?"}],
  ...
}
```

### Step 7: (Optional) Set Usage Limits

To prevent unexpected charges:

1. Go to **Settings** → **Limits**
2. Set monthly spend limit
3. Set per-minute rate limits if needed

### Anthropic Setup Complete!

You should now have:
- [x] `ANTHROPIC_API_KEY`

---

## Verification Checklist

Use this checklist to verify all credentials are ready before deployment.

### Create Your Environment File

1. Copy the example file:
   ```bash
   cp secrets/.env.local.example secrets/.env.local
   ```

2. Fill in all values from the previous sections:

```bash
# === DISCORD (Required) ===
DISCORD_BOT_TOKEN=YOUR_BOT_TOKEN_HERE
DISCORD_CLIENT_ID=1097612345678901234
DISCORD_GUILD_ID=1234567890123456789
DISCORD_DIGEST_CHANNEL_ID=1234567890123456792
DISCORD_ALERTS_CHANNEL_ID=1234567890123456793

# === DISCORD ROLES (Required for RBAC) ===
ADMIN_ROLE_ID=1234567890123456789
DEVELOPER_ROLE_ID=1234567890123456790
RESEARCHER_ROLE_ID=1234567890123456791

# === LINEAR (Required) ===
LINEAR_API_TOKEN=lin_api_YOUR_TOKEN_HERE
LINEAR_TEAM_ID=abc12345-6789-0abc-def1-234567890abc

# === ANTHROPIC (Required) ===
ANTHROPIC_API_KEY=sk-ant-api03-YOUR_KEY_HERE

# === GOOGLE CLOUD (Required) ===
GOOGLE_SERVICE_ACCOUNT_EMAIL=onomancer-bot@project.iam.gserviceaccount.com
GOOGLE_SERVICE_ACCOUNT_KEY_PATH=/opt/devrel-integration/secrets/gcp-service-account.json

# === GOOGLE DRIVE FOLDERS (Required) ===
GOOGLE_FOLDER_LEADERSHIP=1AbCdEfGhIjKlMnOpQrStUvWxYz
GOOGLE_FOLDER_PRODUCT=2BcDeFgHiJkLmNoPqRsTuVwXyZa
GOOGLE_FOLDER_MARKETING=3CdEfGhIjKlMnOpQrStUvWxYzAb
GOOGLE_FOLDER_DEVREL=4DeFgHiJkLmNoPqRsTuVwXyZaBc
GOOGLE_FOLDER_ORIGINALS=5EfGhIjKlMnOpQrStUvWxYzAbCd

# === ENVIRONMENT ===
NODE_ENV=production
LOG_LEVEL=info
PORT=3000
```

### Verification Tests

Run these tests to verify each credential:

**1. Discord Bot Token:**
```bash
curl -H "Authorization: Bot YOUR_DISCORD_BOT_TOKEN" \
  https://discord.com/api/v10/users/@me

# Expected: JSON with bot username and ID
```

**2. Linear API Token:**
```bash
curl -X POST https://api.linear.app/graphql \
  -H "Authorization: YOUR_LINEAR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"query":"{ viewer { id name } }"}'

# Expected: JSON with your name
```

**3. Anthropic API Key:**
```bash
curl https://api.anthropic.com/v1/messages \
  -H "x-api-key: YOUR_ANTHROPIC_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{"model":"claude-3-haiku-20240307","max_tokens":10,"messages":[{"role":"user","content":"Hi"}]}'

# Expected: JSON with Claude response
```

**4. Google Service Account:**
```bash
# From your local machine with Node.js installed
node -e "
const {google} = require('googleapis');
const auth = new google.auth.GoogleAuth({
  keyFile: 'path/to/service-account.json',
  scopes: ['https://www.googleapis.com/auth/drive.readonly']
});
auth.getClient().then(c => console.log('Google Auth OK')).catch(e => console.error(e));
"

# Expected: "Google Auth OK"
```

### Final Checklist

Before proceeding to deployment:

- [ ] Discord bot token copied and saved
- [ ] Discord bot invited to server
- [ ] Discord bot appears in server member list
- [ ] Discord Developer Mode enabled
- [ ] All Discord IDs copied (guild, channels, roles)
- [ ] Google Cloud project created
- [ ] Google Drive API enabled
- [ ] Google Docs API enabled
- [ ] Service account created
- [ ] Service account JSON key downloaded
- [ ] JSON key file permissions set to 600
- [ ] All 5 Google Drive folders created
- [ ] All folders shared with service account email
- [ ] All folder IDs copied
- [ ] Linear API token created
- [ ] Linear team ID obtained
- [ ] Anthropic account created
- [ ] Anthropic API key created
- [ ] All values added to `secrets/.env.local`
- [ ] `secrets/.env.local` has 600 permissions
- [ ] Service account JSON file copied to server (if deploying remotely)

---

## Security Best Practices

### Protect Your Credentials

1. **Never commit credentials to git**
   ```bash
   # Verify .gitignore includes:
   secrets/
   *.json  # For service account keys
   .env*
   ```

2. **Set restrictive file permissions**
   ```bash
   chmod 600 secrets/.env.local
   chmod 600 secrets/gcp-service-account.json
   ```

3. **Use environment-specific files**
   - `secrets/.env.local` for production
   - `secrets/.env.dev` for development
   - Never use production credentials in development

4. **Rotate credentials regularly**
   - See `docs/secrets-rotation.md` for rotation procedures
   - Recommended: every 90 days

### If a Credential is Compromised

**Immediate actions:**

1. **Discord Token**: Reset immediately in Discord Developer Portal → Bot → Reset Token
2. **Linear Token**: Delete in Linear Settings → API → Delete key
3. **Anthropic Key**: Delete in Anthropic Console → API Keys → Delete
4. **Google Key**: Delete in GCP Console → IAM → Service Accounts → Keys → Delete

Then create new credentials and update your deployment.

### Audit Your Credentials

Periodically check:

1. **Discord**: Developer Portal → Bot → Check for unauthorized activity
2. **Linear**: Settings → API → Review active keys
3. **Anthropic**: Console → Usage → Review API calls
4. **Google Cloud**: IAM → Audit Logs → Review service account activity

---

## Troubleshooting

### Discord Issues

**"Invalid Token" error:**
- Token may have been reset - generate a new one
- Check for extra spaces or newlines in the token
- Ensure you're using the Bot token, not Client Secret

**Bot not responding:**
- Verify MESSAGE CONTENT INTENT is enabled
- Check bot has required permissions in the channel
- Verify DISCORD_GUILD_ID matches your server

**Commands not appearing:**
- Run `npm run register-commands` after deployment
- Check bot has `applications.commands` scope
- Wait a few minutes for Discord to propagate

### Google Cloud Issues

**"Permission denied" errors:**
- Verify service account has Editor role
- Check Drive/Docs APIs are enabled
- Verify folders are shared with service account email

**"Could not load credentials" error:**
- Check JSON key file path is correct
- Verify file permissions (should be readable)
- Check JSON file is not corrupted

**"Quota exceeded" error:**
- Free tier: 2M requests/month should be plenty
- Check GCP Console → APIs → Quotas

### Linear Issues

**"Unauthorized" error:**
- Token may have expired - create a new one
- Check token format starts with `lin_api_`
- Verify token has not been revoked

**"Team not found" error:**
- Verify LINEAR_TEAM_ID is the UUID, not the team key
- Run the GraphQL query to get correct team ID

### Anthropic Issues

**"Invalid API key" error:**
- Check key format starts with `sk-ant-`
- Verify key has not been revoked
- Check for extra whitespace

**"Insufficient credits" error:**
- Add payment method in Anthropic Console
- Check billing status and limits

**Rate limit errors:**
- Anthropic has per-minute limits
- Bot includes rate limiting, but check logs

---

## Next Steps

Once all credentials are verified:

1. **Deploy the bot** - Follow `DEPLOYMENT_RUNBOOK.md`
2. **Register Discord commands** - Run `npm run register-commands`
3. **Verify functionality** - Test each feature
4. **Set up monitoring** - Configure alerts for errors

---

## Quick Reference

### Where to Find Each Credential

| Credential | Location |
|------------|----------|
| Discord Bot Token | https://discord.com/developers/applications → Your App → Bot |
| Discord IDs | Right-click in Discord (Developer Mode enabled) |
| Google Service Account | https://console.cloud.google.com → IAM → Service Accounts |
| Google Folder IDs | URL bar when viewing folder in Drive |
| Linear API Token | https://linear.app/settings → API |
| Linear Team ID | GraphQL query or team settings URL |
| Anthropic API Key | https://console.anthropic.com/settings/keys |

### Support Links

- Discord Developer Portal: https://discord.com/developers/applications
- Google Cloud Console: https://console.cloud.google.com
- Linear API Docs: https://developers.linear.app
- Anthropic Console: https://console.anthropic.com

---

*This guide created: December 2024*
*For deployment procedures, see: `DEPLOYMENT_RUNBOOK.md`*
