/**
 * Discord Slash Command Registration
 *
 * This script registers all application commands with Discord.
 * Run this once after deployment or when commands change.
 *
 * Usage:
 *   npm run register-commands
 *   or
 *   node dist/commands/register.js
 */

import { REST, Routes } from 'discord.js';
import { commands } from './definitions';
import dotenv from 'dotenv';
import path from 'path';

// Load environment variables
dotenv.config({ path: path.resolve(__dirname, '../../secrets/.env.local') });

const TOKEN = process.env.DISCORD_BOT_TOKEN;
const CLIENT_ID = process.env.DISCORD_CLIENT_ID;
const GUILD_ID = process.env.DISCORD_GUILD_ID;

/**
 * Register commands with Discord
 */
async function registerCommands() {
  if (!TOKEN) {
    console.error('❌ DISCORD_BOT_TOKEN not found in environment variables');
    process.exit(1);
  }

  if (!CLIENT_ID) {
    console.error('❌ DISCORD_CLIENT_ID not found in environment variables');
    process.exit(1);
  }

  const rest = new REST({ version: '10' }).setToken(TOKEN);

  try {
    console.log(`🔄 Started refreshing ${commands.length} application (/) commands...`);
    console.log(`📋 Commands to register: ${commands.map(c => c.name).join(', ')}`);

    if (GUILD_ID) {
      // Register guild-specific commands (instant deployment, for testing)
      console.log(`🎯 Registering commands for guild: ${GUILD_ID}`);

      const data = await rest.put(
        Routes.applicationGuildCommands(CLIENT_ID, GUILD_ID),
        { body: commands }
      ) as any[];

      console.log(`✅ Successfully registered ${data.length} guild commands`);
      console.log('   Commands are available immediately in your Discord server');
    } else {
      // Register global commands (takes up to 1 hour to propagate)
      console.log('🌍 Registering global commands (may take up to 1 hour to appear)');

      const data = await rest.put(
        Routes.applicationCommands(CLIENT_ID),
        { body: commands }
      ) as any[];

      console.log(`✅ Successfully registered ${data.length} global commands`);
      console.log('   ⚠️ Global commands may take up to 1 hour to appear in Discord');
    }

    console.log('\n📊 Registered Commands:');
    commands.forEach(cmd => {
      console.log(`   /${cmd.name} - ${cmd.description}`);
    });

    console.log('\n✅ Command registration complete!');
    console.log('   Try typing "/" in your Discord server to see the commands');
  } catch (error) {
    console.error('❌ Failed to register commands:', error);
    process.exit(1);
  }
}

// Run registration
registerCommands();
