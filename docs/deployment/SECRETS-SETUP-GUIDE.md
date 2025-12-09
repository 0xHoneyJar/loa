# Secrets Setup Guide

Complete guide for obtaining and configuring all required secrets for the DevRel Integration Bot.

## Quick Start

```bash
# 1. Copy template
cp devrel-integration/secrets/.env.local.example devrel-integration/secrets/.env.local

# 2. Set secure permissions
chmod 600 devrel-integration/secrets/.env.local

# 3. Fill in secrets following this guide
nano devrel-integration/secrets/.env.local

# 4. Verify secrets
./devrel-integration/scripts/verify-deployment-secrets.sh development
```

---

## Table of Contents

1. [Discord Configuration (REQUIRED)](#1-discord-configuration-required)
2. [Linear Configuration (REQUIRED)](#2-linear-configuration-required)
3. [GitHub Configuration (OPTIONAL)](#3-github-configuration-optional)
4. [Vercel Configuration (OPTIONAL)](#4-vercel-configuration-optional)
5. [Discord Role IDs (REQUIRED for RBAC)](#5-discord-role-ids-required-for-rbac)
6. [Application Configuration](#6-application-configuration)
7. [Security Configuration](#7-security-configuration)
8. [Complete .env.local Template](#8-complete-envlocal-template)

---

## 1. Discord Configuration (REQUIRED)

Discord is the primary interface for the DevRel bot. You need a Discord application with a bot.

### Step 1: Create Discord Application

1. Go to [Discord Developer Portal](https://discord.com/developers/applications)
2. Click **"New Application"**
3. Enter a name (e.g., "DevRel Integration Bot")
4. Click **"Create"**

### Step 2: Get Client ID (Application ID)

1. In your application, go to **"General Information"**
2. Copy the **"Application ID"** - this is your `DISCORD_CLIENT_ID`

```
DISCORD_CLIENT_ID=123456789012345678
```

### Step 3: Create Bot and Get Token

1. Go to **"Bot"** section in left sidebar
2. Click **"Add Bot"** → **"Yes, do it!"**
3. Under **"Token"**, click **"Reset Token"**
4. Copy the token immediately (shown only once) - this is your `DISCORD_BOT_TOKEN`

```
DISCORD_BOT_TOKEN=YOUR_BOT_TOKEN_HERE
```

**Token Format**: Looks like `XXXXXXXXXX.XXXXXX.XXXXXXXXXXXXXXXXXXXXXXXXXXXX` (typically 70+ characters)

### Step 4: Enable Required Intents

In the **"Bot"** section, scroll down to **"Privileged Gateway Intents"**:

- [x] **SERVER MEMBERS INTENT** - Required to read member/role data
- [x] **MESSAGE CONTENT INTENT** - Required to read message content for commands

Click **"Save Changes"**

### Step 5: Configure Bot Permissions

Under **"Bot Permissions"**, select:

| Permission | Value | Purpose |
|------------|-------|---------|
| Read Messages/View Channels | 1024 | View channels |
| Send Messages | 2048 | Send responses |
| Manage Messages | 8192 | Delete/pin messages |
| Embed Links | 16384 | Rich embeds |
| Read Message History | 65536 | Fetch past messages |
| Add Reactions | 64 | React to messages |

**Permissions Integer**: `93248`

### Step 6: Get Guild (Server) ID

1. Open Discord desktop/web app
2. Go to **User Settings** → **App Settings** → **Advanced**
3. Enable **Developer Mode**
4. Right-click your server name → **"Copy Server ID"**

```
DISCORD_GUILD_ID=987654321098765432
```

### Step 7: Invite Bot to Server

1. Go to **"OAuth2"** → **"URL Generator"**
2. Select scopes: `bot`, `applications.commands`
3. Select permissions: `93248` (or select individually)
4. Copy the generated URL and open it
5. Select your server and authorize

### Discord Environment Variables Summary

```bash
# Discord Configuration (REQUIRED)
DISCORD_BOT_TOKEN=YOUR_BOT_TOKEN_HERE
DISCORD_GUILD_ID=YOUR_SERVER_ID_HERE
DISCORD_CLIENT_ID=YOUR_APPLICATION_ID_HERE
```

---

## 2. Linear Configuration (REQUIRED)

Linear is used for issue tracking and sprint management.

### Step 1: Get Personal API Key

1. Go to [Linear Settings → API](https://linear.app/settings/api)
2. Click **"Create new key"** under Personal API Keys
3. Name it (e.g., "DevRel Bot Production")
4. Copy the key - this is your `LINEAR_API_KEY`

```
LINEAR_API_KEY=YOUR_LINEAR_API_KEY_HERE
```

**Key Format**: Always starts with `lin_api_` followed by alphanumeric characters

### Step 2: Get Team ID

1. Go to your workspace in Linear
2. Click on your team name in the sidebar
3. Go to **Team Settings** → **General**
4. Look for **"Team ID"** or check the URL: `linear.app/{workspace}/team/{TEAM_ID}/...`

```
LINEAR_TEAM_ID=12345678-1234-1234-1234-123456789abc
```

**Team ID Format**: UUID (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)

### Step 3: Generate Webhook Secret

Generate a secure random secret for webhook signature verification:

```bash
openssl rand -hex 32
```

This outputs a 64-character hex string:

```
LINEAR_WEBHOOK_SECRET=YOUR_GENERATED_64_CHAR_HEX_SECRET
```

### Step 4: Configure Linear Webhook (After Deployment)

After your server is deployed and accessible:

1. Go to [Linear Settings → API → Webhooks](https://linear.app/settings/api)
2. Click **"Create new webhook"**
3. Configure:
   - **URL**: `https://your-domain.com/webhooks/linear`
   - **Secret**: Use the `LINEAR_WEBHOOK_SECRET` you generated
   - **Events**: Select relevant events (Issue created, updated, comments, etc.)
4. Click **"Create"**

### Linear Environment Variables Summary

```bash
# Linear Configuration (REQUIRED)
LINEAR_API_KEY=YOUR_LINEAR_API_KEY_HERE
LINEAR_TEAM_ID=YOUR_TEAM_UUID_HERE
LINEAR_WEBHOOK_SECRET=YOUR_GENERATED_64_CHAR_HEX_SECRET
```

---

## 3. GitHub Configuration (OPTIONAL)

Required only if you want GitHub integration (PR notifications, issue sync).

### Step 1: Generate Personal Access Token

1. Go to [GitHub Settings → Developer settings → Personal access tokens](https://github.com/settings/tokens)
2. Click **"Generate new token (classic)"**
3. Configure:
   - **Note**: "DevRel Bot Production"
   - **Expiration**: 90 days (or as needed)
   - **Scopes**:
     - [x] `repo` - Full control of private repositories
     - [x] `admin:repo_hook` - Read/write repository webhooks
     - [x] `read:org` - Read organization membership
4. Click **"Generate token"**
5. Copy immediately - this is your `GITHUB_TOKEN`

```
GITHUB_TOKEN=YOUR_GITHUB_TOKEN_HERE
```

**Token Format**: Classic tokens start with `ghp_` followed by alphanumeric characters

### Step 2: Generate Webhook Secret

```bash
openssl rand -hex 32
```

```
GITHUB_WEBHOOK_SECRET=YOUR_GENERATED_64_CHAR_HEX_SECRET
```

### Step 3: Configure GitHub Webhook (After Deployment)

1. Go to your repository → **Settings** → **Webhooks**
2. Click **"Add webhook"**
3. Configure:
   - **Payload URL**: `https://your-domain.com/webhooks/github`
   - **Content type**: `application/json`
   - **Secret**: Use your `GITHUB_WEBHOOK_SECRET`
   - **Events**: Select "Let me select individual events"
     - [x] Pull requests
     - [x] Push
     - [x] Issues
     - [x] Issue comments
4. Click **"Add webhook"**

### GitHub Environment Variables Summary

```bash
# GitHub Configuration (OPTIONAL)
GITHUB_TOKEN=YOUR_GITHUB_TOKEN_HERE
GITHUB_WEBHOOK_SECRET=YOUR_GENERATED_64_CHAR_HEX_SECRET
```

---

## 4. Vercel Configuration (OPTIONAL)

Required only if you want Vercel deployment notifications.

### Step 1: Create Vercel Token

1. Go to [Vercel Account Settings → Tokens](https://vercel.com/account/tokens)
2. Click **"Create"**
3. Configure:
   - **Name**: "DevRel Bot"
   - **Scope**: Full Account (or specific team)
   - **Expiration**: Never (or as needed)
4. Click **"Create"**
5. Copy the token - this is your `VERCEL_TOKEN`

```
VERCEL_TOKEN=xxxxxxxxxxxxxxxxxxxxxxxx
```

### Step 2: Generate Webhook Secret

```bash
openssl rand -hex 32
```

```
VERCEL_WEBHOOK_SECRET=YOUR_GENERATED_64_CHAR_HEX_SECRET
```

### Step 3: Configure Vercel Webhook (After Deployment)

1. Go to your Vercel project → **Settings** → **Git** → **Deploy Hooks** OR
2. Go to **Settings** → **Webhooks**
3. Add webhook:
   - **URL**: `https://your-domain.com/webhooks/vercel`
   - **Events**: Deployment events
4. Note: Vercel uses the URL itself for verification in some cases

### Vercel Environment Variables Summary

```bash
# Vercel Configuration (OPTIONAL)
VERCEL_TOKEN=xxxxxxxxxxxxxxxxxxxxxxxx
VERCEL_WEBHOOK_SECRET=YOUR_GENERATED_64_CHAR_HEX_SECRET
```

---

## 5. Discord Role IDs (REQUIRED for RBAC)

The bot uses Role-Based Access Control (RBAC). You need to create roles in Discord and get their IDs.

### Step 1: Create Roles in Discord

In your Discord server:

1. Go to **Server Settings** → **Roles**
2. Create these roles (or use existing ones):

| Role Name | Purpose | Required |
|-----------|---------|----------|
| Developer | Full development access | **Yes** |
| Admin | Administrative access | **Yes** |
| Researcher | Read + feedback access | Optional |

### Step 2: Get Role IDs

1. Ensure **Developer Mode** is enabled (User Settings → Advanced)
2. Go to **Server Settings** → **Roles**
3. Right-click each role → **"Copy Role ID"**

```bash
# Discord Role IDs (REQUIRED)
DEVELOPER_ROLE_ID=111111111111111111
ADMIN_ROLE_ID=222222222222222222
RESEARCHER_ROLE_ID=333333333333333333
```

### Role Permissions Matrix

| Permission | Guest | Researcher | Developer | Admin |
|------------|-------|------------|-----------|-------|
| show-sprint | ✅ | ✅ | ✅ | ✅ |
| doc | ✅ | ✅ | ✅ | ✅ |
| task | ✅ | ✅ | ✅ | ✅ |
| preview | ❌ | ✅ | ✅ | ✅ |
| my-notifications | ❌ | ✅ | ✅ | ✅ |
| implement | ❌ | ❌ | ✅ | ✅ |
| review-sprint | ❌ | ❌ | ✅ | ✅ |
| my-tasks | ❌ | ❌ | ✅ | ✅ |
| feedback-capture | ❌ | ❌ | ✅ | ✅ |
| config | ❌ | ❌ | ❌ | ✅ |
| manage-users | ❌ | ❌ | ❌ | ✅ |
| manage-roles | ❌ | ❌ | ❌ | ✅ |

---

## 6. Application Configuration

These control the application behavior.

```bash
# Application Configuration
NODE_ENV=production          # development | staging | production
LOG_LEVEL=info               # error | warn | info | debug | trace
PORT=3000                    # HTTP server port (behind nginx proxy)
TZ=UTC                       # Timezone for timestamps
```

### NODE_ENV Values

| Value | Use Case |
|-------|----------|
| `development` | Local development, verbose logging, debug endpoints |
| `staging` | Testing environment, production-like but separate |
| `production` | Live environment, optimized, security enforced |

### LOG_LEVEL Values

| Level | Description | Production Recommendation |
|-------|-------------|---------------------------|
| `error` | Errors only | Not recommended (miss important info) |
| `warn` | Errors + warnings | Acceptable for high-traffic |
| `info` | Normal operations | **Recommended** |
| `debug` | Detailed debugging | Development only |
| `trace` | Everything | Never in production |

---

## 7. Security Configuration

Optional security enhancements.

```bash
# Rate Limiting
RATE_LIMIT_MAX=100           # Max requests per window
RATE_LIMIT_WINDOW_MS=60000   # Window size in ms (1 minute)

# Request Limits
REQUEST_TIMEOUT_MS=30000     # 30 second timeout
MAX_BODY_SIZE=1mb            # Maximum request body size

# Feature Flags
VALIDATE_WEBHOOK_SIGNATURES=true   # ALWAYS true in production
LOG_REQUESTS=false                 # Disable verbose request logging
```

---

## 8. Complete .env.local Template

Copy this template and fill in your values:

```bash
# ============================================================================
# DevRel Integration Bot - Production Environment Configuration
# ============================================================================
# Generated: [DATE]
# Environment: production
# ============================================================================

# ----------------------------------------------------------------------------
# DISCORD CONFIGURATION (REQUIRED)
# ----------------------------------------------------------------------------
# Bot token from Discord Developer Portal → Bot → Reset Token
DISCORD_BOT_TOKEN=

# Server (Guild) ID - Right-click server → Copy Server ID (Developer Mode)
DISCORD_GUILD_ID=

# Application ID from Discord Developer Portal → General Information
DISCORD_CLIENT_ID=

# ----------------------------------------------------------------------------
# DISCORD ROLE IDS (REQUIRED FOR RBAC)
# ----------------------------------------------------------------------------
# Right-click role in Server Settings → Roles → Copy Role ID

# Developer role - Full development access
DEVELOPER_ROLE_ID=

# Admin role - Full administrative access
ADMIN_ROLE_ID=

# Researcher role (optional) - Read + feedback access
# RESEARCHER_ROLE_ID=

# ----------------------------------------------------------------------------
# LINEAR CONFIGURATION (REQUIRED)
# ----------------------------------------------------------------------------
# API Key from Linear Settings → API → Create new key
LINEAR_API_KEY=

# Team ID from Team Settings → General (UUID format)
LINEAR_TEAM_ID=

# Webhook secret - Generate with: openssl rand -hex 32
LINEAR_WEBHOOK_SECRET=

# ----------------------------------------------------------------------------
# GITHUB CONFIGURATION (OPTIONAL)
# ----------------------------------------------------------------------------
# Personal Access Token from GitHub Settings → Developer settings → Tokens
# Scopes: repo, admin:repo_hook, read:org
# GITHUB_TOKEN=

# Webhook secret - Generate with: openssl rand -hex 32
# GITHUB_WEBHOOK_SECRET=

# ----------------------------------------------------------------------------
# VERCEL CONFIGURATION (OPTIONAL)
# ----------------------------------------------------------------------------
# Token from Vercel Account Settings → Tokens
# VERCEL_TOKEN=

# Webhook secret - Generate with: openssl rand -hex 32
# VERCEL_WEBHOOK_SECRET=

# ----------------------------------------------------------------------------
# APPLICATION CONFIGURATION
# ----------------------------------------------------------------------------
NODE_ENV=production
LOG_LEVEL=info
PORT=3000
TZ=UTC

# ----------------------------------------------------------------------------
# SECURITY CONFIGURATION
# ----------------------------------------------------------------------------
VALIDATE_WEBHOOK_SIGNATURES=true
# RATE_LIMIT_MAX=100
# RATE_LIMIT_WINDOW_MS=60000
# REQUEST_TIMEOUT_MS=30000

# ============================================================================
# SECURITY REMINDERS
# ============================================================================
# 1. Set file permissions: chmod 600 secrets/.env.local
# 2. Never commit this file to git
# 3. Rotate secrets quarterly (see docs/deployment/runbooks/secrets-rotation.md)
# 4. Back up encrypted: gpg -c secrets/.env.local
# ============================================================================
```

---

## Verification

After configuring secrets, verify them:

```bash
# Check file permissions
ls -la devrel-integration/secrets/.env.local
# Should show: -rw------- (600)

# Verify secrets are not example values
./devrel-integration/scripts/verify-deployment-secrets.sh production

# Test Discord connection (local)
cd devrel-integration
npm run dev
# Should see: "Discord bot logged in as [bot-name]"
```

---

## Troubleshooting

### Discord Bot Won't Start

1. **Invalid token**: Reset token in Developer Portal, copy fresh
2. **Missing intents**: Enable SERVER MEMBERS and MESSAGE CONTENT intents
3. **Guild not found**: Verify DISCORD_GUILD_ID is correct, bot is in server

### Linear API Errors

1. **401 Unauthorized**: API key invalid or expired, regenerate
2. **Team not found**: Verify LINEAR_TEAM_ID is correct UUID format
3. **Webhook signature failed**: LINEAR_WEBHOOK_SECRET doesn't match Linear config

### Role Validation Failed

1. **Role ID not found**: Verify role exists and ID is correct
2. **Bot can't see roles**: Bot needs to be above the roles it manages
3. **Missing env vars**: Ensure DEVELOPER_ROLE_ID and ADMIN_ROLE_ID are set

---

## Security Best Practices

1. **Never commit secrets** - `.env.local` is in `.gitignore`
2. **Use environment-specific tokens** - Separate dev/staging/prod
3. **Rotate quarterly** - See `docs/deployment/runbooks/secrets-rotation.md`
4. **Restrict file permissions** - `chmod 600` on all secret files
5. **Encrypt backups** - `gpg -c secrets/.env.local`
6. **Audit access** - Review who has access to production secrets
7. **Monitor for leaks** - Use GitHub secret scanning, GitGuardian, etc.
