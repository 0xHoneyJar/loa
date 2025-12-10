#!/usr/bin/env ts-node
/**
 * Sync Discord Roles to Database
 *
 * One-time admin script to grant database roles to users based on their Discord roles.
 * Run this after initial deployment to sync existing Discord users.
 */

import { Client, GatewayIntentBits } from 'discord.js';
import { authDb } from '../database/db';
import dotenv from 'dotenv';
import path from 'path';

// Load secrets
dotenv.config({ path: path.resolve(__dirname, '../../secrets/.env.local') });

const DISCORD_TOKEN = process.env['DISCORD_BOT_TOKEN'];
const GUILD_ID = process.env['DISCORD_GUILD_ID'];
const DEVELOPER_ROLE_ID = process.env['DEVELOPER_ROLE_ID'];
const ADMIN_ROLE_ID = process.env['ADMIN_ROLE_ID'];
const RESEARCHER_ROLE_ID = process.env['RESEARCHER_ROLE_ID'];

if (!DISCORD_TOKEN || !GUILD_ID) {
  console.error('❌ Missing required environment variables');
  console.error('   Required: DISCORD_BOT_TOKEN, DISCORD_GUILD_ID');
  process.exit(1);
}

async function syncRoles() {
  console.log('🔄 Starting Discord role sync...\n');

  // Initialize database
  await authDb.initialize();
  const db = authDb.getConnection();

  // Initialize Discord client
  const client = new Client({
    intents: [
      GatewayIntentBits.Guilds,
      GatewayIntentBits.GuildMembers,
    ],
  });

  await client.login(DISCORD_TOKEN);
  console.log('✅ Connected to Discord\n');

  const guild = await client.guilds.fetch(GUILD_ID!);
  const members = await guild.members.fetch();

  console.log(`Found ${members.size} members in server\n`);

  let synced = 0;
  let skipped = 0;

  for (const [memberId, member] of members) {
    if (member.user.bot) {
      continue; // Skip bots
    }

    // Check if user exists in database
    const userRow = await db.get<{ id: number; discord_user_id: string }>(
      'SELECT id, discord_user_id FROM users WHERE discord_user_id = ?',
      memberId
    );

    if (!userRow) {
      console.log(`⏭️  Skipping ${member.user.tag} (not in database)`);
      skipped++;
      continue;
    }

    // Determine role from Discord
    let roleToGrant: 'admin' | 'developer' | 'researcher' | null = null;

    if (ADMIN_ROLE_ID && member.roles.cache.has(ADMIN_ROLE_ID)) {
      roleToGrant = 'admin';
    } else if (DEVELOPER_ROLE_ID && member.roles.cache.has(DEVELOPER_ROLE_ID)) {
      roleToGrant = 'developer';
    } else if (RESEARCHER_ROLE_ID && member.roles.cache.has(RESEARCHER_ROLE_ID)) {
      roleToGrant = 'researcher';
    }

    if (!roleToGrant) {
      console.log(`⏭️  ${member.user.tag}: No privileged Discord roles`);
      skipped++;
      continue;
    }

    // Check if user already has this role
    const existingRole = await db.get(
      `SELECT role FROM user_roles
       WHERE user_id = ? AND role = ? AND action = 'grant'
       ORDER BY created_at DESC LIMIT 1`,
      userRow.id,
      roleToGrant
    );

    if (existingRole) {
      console.log(`✓ ${member.user.tag}: Already has ${roleToGrant} role`);
      continue;
    }

    // Grant role
    const now = new Date().toISOString();
    await db.run(
      `INSERT INTO user_roles (
        user_id, role, action, granted_by_user_id, granted_by_discord_id,
        reason, effective_at, created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
      userRow.id,
      roleToGrant,
      'grant',
      null,
      'system',
      'Synced from Discord roles (initial setup)',
      now,
      now
    );

    console.log(`✅ ${member.user.tag}: Granted ${roleToGrant} role`);
    synced++;
  }

  console.log(`\n📊 Sync complete:`);
  console.log(`   - Synced: ${synced}`);
  console.log(`   - Skipped: ${skipped}`);

  await client.destroy();
  process.exit(0);
}

syncRoles().catch((error) => {
  console.error('❌ Error syncing roles:', error);
  process.exit(1);
});
