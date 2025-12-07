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
import { config } from 'dotenv';
import express from 'express';
import { logger, logStartup } from './utils/logger';
import { setupGlobalErrorHandlers } from './utils/errors';
import { validateRoleConfiguration } from './middleware/auth';
import { createWebhookRouter } from './handlers/webhooks';
import { createMonitoringRouter, startHealthMonitoring } from './utils/monitoring';
import { handleFeedbackCapture } from './handlers/feedbackCapture';
import { handleCommand } from './handlers/commands';
import { startDailyDigest } from './cron/dailyDigest';

// Load environment variables
config({ path: './secrets/.env.local' });

// Setup global error handlers
setupGlobalErrorHandlers();

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

  // Validate role configuration
  const roleValidation = validateRoleConfiguration();
  if (!roleValidation.valid) {
    logger.error('Role configuration validation failed:');
    roleValidation.errors.forEach(error => logger.error(`  - ${error}`));
    logger.warn('Bot will continue but some features may not work correctly');
  } else {
    logger.info('Role configuration validated successfully');
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
 * Start Discord bot
 */
const token = process.env['DISCORD_BOT_TOKEN'];

if (!token) {
  logger.error('DISCORD_BOT_TOKEN not found in environment variables');
  logger.error('Please create secrets/.env.local file with your Discord bot token');
  process.exit(1);
}

logger.info('Connecting to Discord...');
client.login(token).catch((error) => {
  logger.error('Failed to login to Discord:', error);
  process.exit(1);
});
