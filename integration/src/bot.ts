/**
 * Discord Bot Entry Point
 *
 * Main Discord bot that coordinates:
 * - Feedback capture (📌 emoji reactions)
 * - Discord command handlers
 * - Daily digest cron job
 * - Health monitoring
 */

import { Client, GatewayIntentBits, Events, Message, MessageReaction, User, PartialUser, PartialMessageReaction } from 'discord.js';
import express from 'express';
import { logger, logStartup } from './utils/logger';
import { setupGlobalErrorHandlers } from './utils/errors';
import { validateRoleConfiguration } from './middleware/auth';
import { createWebhookRouter } from './handlers/webhooks';
import { createMonitoringRouter, startHealthMonitoring } from './utils/monitoring';
import { handleFeedbackCapture } from './handlers/feedbackCapture';
import { handleCommand } from './handlers/commands';
import { startDailyDigest } from './cron/dailyDigest';
import { SecretsManager } from './utils/secrets';

// Setup global error handlers
setupGlobalErrorHandlers();

// Global secrets manager instance
let secretsManager: SecretsManager;

/**
 * Initialize Discord client
 */
const client = new Client({
  intents: [
    GatewayIntentBits.Guilds,
    GatewayIntentBits.GuildMessages,
    GatewayIntentBits.MessageContent,
    GatewayIntentBits.GuildMessageReactions,
    GatewayIntentBits.GuildMembers,
  ],
});

/**
 * Bot ready event
 */
client.once(Events.ClientReady, async (readyClient) => {
  logStartup();
  logger.info(`Discord bot logged in as ${readyClient.user.tag}`);
  logger.info(`Connected to ${readyClient.guilds.cache.size} guilds`);

  try {
    // SECURITY FIX (HIGH-004): Validate role configuration and fail if missing
    await validateRoleConfiguration(readyClient);
  } catch (error) {
    logger.error('❌ Role validation failed, shutting down bot:', error);
    logger.error('Please configure required Discord roles:');
    logger.error('1. Set DISCORD_GUILD_ID environment variable');
    logger.error('2. Set DEVELOPER_ROLE_ID with valid Discord role ID');
    logger.error('3. Set ADMIN_ROLE_ID with valid Discord role ID');
    logger.error('4. Ensure roles exist in the Discord server');
    process.exit(1);
  }

  // Start daily digest cron job
  startDailyDigest(client);

  // Start health monitoring
  startHealthMonitoring();

  logger.info('Bot initialization complete');
});

/**
 * Message create event (for commands)
 */
client.on(Events.MessageCreate, async (message: Message) => {
  try {
    // Ignore bot messages
    if (message.author.bot) return;

    // Check if message starts with command prefix
    if (message.content.startsWith('/')) {
      await handleCommand(message);
    }
  } catch (error) {
    logger.error('Error handling message:', error);
  }
});

/**
 * Message reaction add event (for feedback capture)
 */
client.on(Events.MessageReactionAdd, async (
  reaction: MessageReaction | PartialMessageReaction,
  user: User | PartialUser
) => {
  try {
    // Ignore bot reactions
    if (user.bot) return;

    // Fetch partial data if needed
    if (reaction.partial) {
      try {
        await reaction.fetch();
      } catch (error) {
        logger.error('Failed to fetch reaction:', error);
        return;
      }
    }

    // Handle feedback capture (📌 emoji)
    if (reaction.emoji.name === '📌') {
      await handleFeedbackCapture(reaction as MessageReaction, user as User);
    }
  } catch (error) {
    logger.error('Error handling reaction:', error);
  }
});

/**
 * Error event
 */
client.on(Events.Error, (error) => {
  logger.error('Discord client error:', error);
});

/**
 * Warning event
 */
client.on(Events.Warn, (info) => {
  logger.warn('Discord client warning:', info);
});

/**
 * Debug event (only in development)
 */
if (process.env['NODE_ENV'] !== 'production') {
  client.on(Events.Debug, (info) => {
    logger.debug('Discord debug:', info);
  });
}

/**
 * Rate limit warning event
 */
client.on('rateLimit' as any, (rateLimitData: any) => {
  logger.warn('Discord rate limit hit:', {
    timeout: rateLimitData.timeout,
    limit: rateLimitData.limit,
    method: rateLimitData.method,
    path: rateLimitData.path,
    route: rateLimitData.route,
  });
});

/**
 * Setup Express server for webhooks and health checks
 */
const app = express();
const port = process.env['PORT'] || 3000;

// Body parser middleware
app.use(express.json());

// Webhooks (Linear, Vercel)
app.use('/webhooks', createWebhookRouter());

// Monitoring endpoints (/health, /metrics, /ready, /live)
app.use(createMonitoringRouter());

// Start Express server
const server = app.listen(port, () => {
  logger.info(`HTTP server listening on port ${port}`);
  logger.info(`Health check: http://localhost:${port}/health`);
  logger.info(`Metrics: http://localhost:${port}/metrics`);
});

/**
 * Graceful shutdown
 */
async function shutdown(signal: string): Promise<void> {
  logger.info(`${signal} received, shutting down gracefully...`);

  // Stop accepting new connections
  server.close(() => {
    logger.info('HTTP server closed');
  });

  // Disconnect Discord client
  if (client.isReady()) {
    await client.destroy();
    logger.info('Discord client destroyed');
  }

  // Exit process
  logger.info('Shutdown complete');
  process.exit(0);
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

/**
 * Start Discord bot with secrets validation
 */
async function startBot() {
  try {
    logger.info('🔐 Initializing and validating secrets...');

    // Initialize secrets manager with comprehensive validation
    secretsManager = new SecretsManager();
    await secretsManager.load();

    logger.info('✅ Secrets validated successfully');

    // Get validated Discord token
    const token = secretsManager.get('DISCORD_BOT_TOKEN');

    if (!token) {
      throw new Error('DISCORD_BOT_TOKEN not found after secrets validation');
    }

    logger.info('🤖 Connecting to Discord...');
    await client.login(token);

  } catch (error) {
    logger.error('❌ Failed to start bot:', error);
    logger.error('Please check:');
    logger.error('1. secrets/.env.local exists');
    logger.error('2. File permissions are 600 (chmod 600 secrets/.env.local)');
    logger.error('3. All required secrets are configured');
    logger.error('4. Tokens have valid format');
    process.exit(1);
  }
}

// Start the bot
startBot();
