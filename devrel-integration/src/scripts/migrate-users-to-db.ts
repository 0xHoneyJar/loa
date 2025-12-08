/**
 * Migration Script: Backfill Discord Users to Database
 *
 * HIGH-005 Implementation: Migrate existing Discord users into the database
 * with role mappings from Discord roles to database roles.
 *
 * Usage:
 *   npm run migrate-users
 *
 * What it does:
 * 1. Connects to Discord and fetches all guild members
 * 2. Creates user records in database for each member
 * 3. Maps Discord roles to database roles (requires admin approval for non-guest)
 * 4. Generates a report of migrated users
 *
 * IMPORTANT: This is a one-time migration script. Users added after migration
 * will be auto-created when they interact with the bot.
 */

import { Client, GatewayIntentBits } from 'discord.js';
import { authDb } from '../database/db';
import userMappingService from '../services/user-mapping-service';
import { getUserRolesFromMember } from '../middleware/auth';
import { logger } from '../utils/logger';

interface MigrationStats {
  totalMembers: number;
  usersCreated: number;
  usersSkipped: number;
  rolesRequiringApproval: number;
  errors: number;
}

/**
 * Main migration function
 */
async function migrateUsers(): Promise<void> {
  logger.info('='.repeat(60));
  logger.info('Discord User Migration Script - HIGH-005');
  logger.info('='.repeat(60));

  // Initialize database
  logger.info('Initializing database...');
  await authDb.initialize();
  logger.info('✅ Database initialized');

  // Initialize Discord client
  const client = new Client({
    intents: [
      GatewayIntentBits.Guilds,
      GatewayIntentBits.GuildMembers,
    ],
  });

  // Login to Discord
  const token = process.env['DISCORD_BOT_TOKEN'];
  if (!token) {
    throw new Error('DISCORD_BOT_TOKEN not set in environment');
  }

  logger.info('Logging into Discord...');
  await client.login(token);
  logger.info('✅ Discord client logged in');

  // Get guild
  const guildId = process.env['DISCORD_GUILD_ID'];
  if (!guildId) {
    throw new Error('DISCORD_GUILD_ID not set in environment');
  }

  const guild = client.guilds.cache.get(guildId);
  if (!guild) {
    throw new Error(`Guild ${guildId} not found in bot cache`);
  }

  logger.info(`Found guild: ${guild.name} (${guild.id})`);

  // Fetch all members
  logger.info('Fetching all guild members...');
  await guild.members.fetch();
  const members = guild.members.cache;
  logger.info(`Found ${members.size} members`);

  // Migration stats
  const stats: MigrationStats = {
    totalMembers: members.size,
    usersCreated: 0,
    usersSkipped: 0,
    rolesRequiringApproval: 0,
    errors: 0,
  };

  // Migrate each member
  logger.info('Starting user migration...');
  logger.info('-'.repeat(60));

  for (const [memberId, member] of members) {
    // Skip bots
    if (member.user.bot) {
      stats.usersSkipped++;
      logger.debug(`Skipping bot: ${member.user.tag}`);
      continue;
    }

    try {
      // Get Discord roles
      const discordRoles = getUserRolesFromMember(member);

      // Create or get user in database
      const user = await userMappingService.getOrCreateUser(
        member.user.id,
        member.user.tag
      );

      // Check if user was just created or already existed
      const dbRoles = await userMappingService.getUserRoles(member.user.id);

      if (dbRoles.length === 1 && dbRoles[0] === 'guest') {
        stats.usersCreated++;
        logger.info(`✅ Created user: ${member.user.tag} (${member.user.id})`);
        logger.info(`   Discord roles: ${discordRoles.join(', ')}`);

        // Check if user has non-guest Discord roles that need approval
        const nonGuestRoles = discordRoles.filter(role => role !== 'guest');
        if (nonGuestRoles.length > 0) {
          stats.rolesRequiringApproval++;
          logger.warn(`   ⚠️  User has Discord roles requiring approval: ${nonGuestRoles.join(', ')}`);
          logger.warn(`   ⚠️  User must request role grants through /role-request command`);
        }
      } else {
        stats.usersSkipped++;
        logger.debug(`Skipped existing user: ${member.user.tag}`);
      }
    } catch (error) {
      stats.errors++;
      logger.error(`❌ Error migrating user ${member.user.tag}:`, error);
    }
  }

  // Cleanup
  await client.destroy();
  await authDb.close();

  // Print summary
  logger.info('-'.repeat(60));
  logger.info('Migration Complete!');
  logger.info('='.repeat(60));
  logger.info(`Total members processed: ${stats.totalMembers}`);
  logger.info(`Users created: ${stats.usersCreated}`);
  logger.info(`Users skipped (bots or existing): ${stats.usersSkipped}`);
  logger.info(`Users with roles requiring approval: ${stats.rolesRequiringApproval}`);
  logger.info(`Errors: ${stats.errors}`);
  logger.info('='.repeat(60));

  if (stats.rolesRequiringApproval > 0) {
    logger.warn('');
    logger.warn('⚠️  IMPORTANT: Role Grant Approvals Required');
    logger.warn('='.repeat(60));
    logger.warn(`${stats.rolesRequiringApproval} users have Discord roles that require approval.`);
    logger.warn('These users currently have only the guest role in the database.');
    logger.warn('');
    logger.warn('To grant elevated roles, users must:');
    logger.warn('1. Request role grant: /role-request <role> <reason>');
    logger.warn('2. Admin approves: Check pending approvals and approve');
    logger.warn('');
    logger.warn('Alternatively, admins can grant roles directly through the API:');
    logger.warn('  await userMappingService.requestRoleGrant(...)');
    logger.warn('  await userMappingService.approveRoleGrant(...)');
    logger.warn('='.repeat(60));
  }

  logger.info('');
  logger.info('Next Steps:');
  logger.info('1. Review migration logs above');
  logger.info('2. Process any pending role grant requests');
  logger.info('3. Test user authentication with database-backed roles');
  logger.info('4. Monitor auth_audit_log table for authorization checks');
  logger.info('');
}

/**
 * Run migration with error handling
 */
async function main() {
  try {
    await migrateUsers();
    process.exit(0);
  } catch (error) {
    logger.error('❌ Migration failed:', error);
    process.exit(1);
  }
}

// Run migration
main();
