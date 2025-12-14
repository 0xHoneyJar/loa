# Discord Slash Commands Deployment Guide

This guide walks you through deploying the modern Discord slash commands to your production server (ainmdilis.com).

## What Changed

Your bot now supports **both** command systems during the transition:

1. **Legacy Text Commands** - Type `/show-sprint` as a regular message (still works)
2. **Modern Slash Commands** - Type `/` and see autocomplete in Discord UI (NEW!)

## Files Created

- `src/commands/definitions.ts` - Command definitions with autocomplete options
- `src/commands/register.ts` - Script to register commands with Discord API
- `src/handlers/interactions.ts` - Handles slash command interactions
- Updated `src/bot.ts` - Listens for both text and slash commands

## Deployment Steps

### Step 1: Upload New Code to Server (5 minutes)

```bash
# From your local machine, copy the new files to the server
cd /home/merlin/Documents/thj/code/agentic-base

# Option A: Using rsync (recommended)
rsync -avz --exclude='node_modules' --exclude='.git' \
  devrel-integration/ \
  debian@15.235.228.10:/opt/devrel-integration/

# Option B: Using scp
scp -r devrel-integration/src debian@15.235.228.10:/opt/devrel-integration/
scp devrel-integration/package.json debian@15.235.228.10:/opt/devrel-integration/
```

### Step 2: SSH to Server and Rebuild (3 minutes)

```bash
# SSH into your server
ssh debian@15.235.228.10

# Switch to devrel user
sudo su - devrel

# Navigate to application directory
cd /opt/devrel-integration

# Rebuild application
npm run build

# Verify build succeeded
ls -lh dist/commands/
# Should show: definitions.js and register.js
```

### Step 3: Register Commands with Discord (2 minutes)

**IMPORTANT**: This step registers your commands with Discord's API. Commands will appear immediately in your Discord server.

```bash
# Still as devrel user on the server
cd /opt/devrel-integration

# Register slash commands
npm run register-commands
```

**Expected output**:
```
🔄 Started refreshing 11 application (/) commands...
📋 Commands to register: show-sprint, doc, my-tasks, preview, my-notifications, mfa-enroll, mfa-verify, mfa-status, mfa-disable, mfa-backup, help
🎯 Registering commands for guild: YOUR_GUILD_ID
✅ Successfully registered 11 guild commands
   Commands are available immediately in your Discord server

📊 Registered Commands:
   /show-sprint - Display current sprint status from Linear
   /doc - Fetch project documentation
   /my-tasks - Show your assigned Linear tasks
   /preview - Get Vercel preview URL for a Linear issue
   /my-notifications - Manage your notification preferences
   /mfa-enroll - Set up two-factor authentication for secure operations
   /mfa-verify - Verify your two-factor authentication token
   /mfa-status - Check your multi-factor authentication status
   /mfa-disable - Disable two-factor authentication
   /mfa-backup - Generate new MFA backup codes
   /help - Show available commands and usage information

✅ Command registration complete!
   Try typing "/" in your Discord server to see the commands
```

### Step 4: Restart Bot (1 minute)

```bash
# Still as devrel user
pm2 restart agentic-base-bot

# Verify bot restarted successfully
pm2 status

# Check logs for any errors
pm2 logs agentic-base-bot --lines 50
```

**Expected log output**:
```
Discord bot logged in as Onomancer#6505
Connected to 1 guilds
✅ Authentication database initialized
✅ Role validation successful
Bot initialization complete
```

### Step 5: Test in Discord (2 minutes)

1. Open your Discord server
2. Type `/` in any channel
3. **You should see your commands appear with autocomplete!**

**Test commands**:
- `/help` - Shows help message
- `/show-sprint` - Displays sprint status
- `/doc` - Shows autocomplete with options (prd, sdd, sprint)

## Troubleshooting

### Commands don't appear in Discord

**Symptom**: Typing `/` doesn't show your bot's commands

**Solutions**:
1. Check registration succeeded:
   ```bash
   # On server
   cd /opt/devrel-integration
   npm run register-commands
   ```

2. Verify `DISCORD_CLIENT_ID` is set:
   ```bash
   grep DISCORD_CLIENT_ID secrets/.env.local
   # Should show your bot's client ID
   ```

3. Verify `DISCORD_GUILD_ID` is set:
   ```bash
   grep DISCORD_GUILD_ID secrets/.env.local
   # Should show your Discord server's guild ID
   ```

4. Try kicking and re-inviting the bot to your server

### Commands show but don't work

**Symptom**: Commands appear but clicking them gives an error

**Solutions**:
1. Check bot logs:
   ```bash
   pm2 logs agentic-base-bot --lines 100
   ```

2. Verify bot restarted after code deploy:
   ```bash
   pm2 restart agentic-base-bot
   ```

3. Check permissions - bot needs same roles as before (DEVELOPER_ROLE_ID or ADMIN_ROLE_ID)

### Permission errors

**Symptom**: "❌ You don't have permission to use this command"

**Solutions**:
1. Verify you have the required Discord role (Developer or Admin)
2. Check role IDs in environment:
   ```bash
   grep "ROLE_ID" secrets/.env.local
   ```

3. Verify roles exist in Discord:
   - Server Settings > Roles
   - Copy role ID (enable Developer Mode in Discord)
   - Ensure ID matches environment variable

### Build errors

**Symptom**: `npm run build` fails

**Solutions**:
1. Check Node.js version (must be 20+):
   ```bash
   node --version
   # Should show v20.x.x
   ```

2. Reinstall dependencies:
   ```bash
   rm -rf node_modules
   npm install
   npm run build
   ```

3. Check TypeScript errors:
   ```bash
   npm run build 2>&1 | grep error
   ```

## Rollback Plan

If slash commands cause issues, you can easily rollback:

```bash
# On server as devrel user
cd /opt/devrel-integration

# Revert to previous version (if using git)
git checkout HEAD~1

# Or just comment out the interaction handler in bot.ts
nano src/bot.ts
# Comment out lines 86-98 (InteractionCreate event handler)

# Rebuild and restart
npm run build
pm2 restart agentic-base-bot
```

Text-based commands will continue to work during rollback.

## Next Steps After Deployment

### 1. Test All Commands (10 minutes)

Go through each command and verify it works:
- [ ] `/help` - Shows help message
- [ ] `/show-sprint` - Displays Linear sprint
- [ ] `/doc prd` - Returns PRD document
- [ ] `/doc sdd` - Returns SDD document
- [ ] `/doc sprint` - Returns sprint plan
- [ ] `/my-tasks` - Shows placeholder (not yet implemented)
- [ ] `/preview DEV-123` - Shows placeholder (not yet implemented)
- [ ] `/my-notifications` - Shows placeholder (not yet implemented)
- [ ] `/mfa-enroll` - Starts MFA enrollment
- [ ] `/mfa-status` - Shows MFA status

### 2. Update Team Documentation

Inform your team:
- Slash commands are now available
- Type `/` to see all commands
- Old text commands still work during transition
- Autocomplete makes commands easier to discover

### 3. Monitor for Issues (First 24 hours)

```bash
# Check logs regularly
pm2 logs agentic-base-bot --lines 50

# Watch for errors
pm2 logs agentic-base-bot | grep -i error

# Check bot status
pm2 status
```

### 4. Remove Legacy Commands (After 1-2 weeks)

Once slash commands are stable, remove text-based command support:

```bash
# Edit bot.ts and remove the MessageCreate handler
nano src/bot.ts
# Delete lines 100-118 (Message create event for legacy commands)

# Rebuild and restart
npm run build
pm2 restart agentic-base-bot
```

## Benefits of Slash Commands

✅ **Discoverability** - Users can see all commands by typing `/`
✅ **Autocomplete** - Discord suggests options while typing
✅ **Type Safety** - Parameters are validated by Discord
✅ **Better UX** - No need to remember exact command syntax
✅ **Permissions** - Discord handles permission checks natively
✅ **Ephemeral Replies** - Can send private responses only visible to command user

## FAQ

**Q: Do I need to register commands every time I restart the bot?**
A: No! Commands only need to be registered once or when you add/modify commands.

**Q: Can I add more commands later?**
A: Yes! Add them to `src/commands/definitions.ts`, rebuild, and run `npm run register-commands` again.

**Q: What happens to my text-based commands?**
A: They continue to work during the transition. Both systems work simultaneously.

**Q: How do I remove a command?**
A: Remove it from `definitions.ts`, rebuild, and run `npm run register-commands` again.

**Q: Can I use slash commands in DMs with the bot?**
A: Not by default. Guild commands only work in your Discord server. To enable DMs, register global commands instead (see `register.ts` for instructions).

## Support

If you encounter issues:
1. Check this guide's troubleshooting section
2. Review bot logs: `pm2 logs agentic-base-bot`
3. Test health endpoint: `curl https://ainmdilis.com/health`
4. Check Discord API status: https://discordstatus.com

---

**Deployment Checklist**:
- [ ] Upload new code to server
- [ ] Rebuild application (`npm run build`)
- [ ] Register commands (`npm run register-commands`)
- [ ] Restart bot (`pm2 restart agentic-base-bot`)
- [ ] Test commands in Discord (type `/`)
- [ ] Verify all commands work
- [ ] Monitor logs for 24 hours
- [ ] Update team documentation

**Ready?** Follow the steps above to deploy slash commands to production!
