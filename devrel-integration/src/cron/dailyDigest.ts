/**
 * Daily Digest Cron Job
 *
 * Sends a daily sprint status digest to configured Discord channel
 */

import cron from 'node-cron';
import { Client, TextChannel } from 'discord.js';
import yaml from 'js-yaml';
import fs from 'fs';
import path from 'path';
import { logger } from '../utils/logger';
import { getCurrentSprint, getTeamIssues } from '../services/linearService';

interface DigestConfig {
  schedule: string;
  channel_id: string;
  enabled: boolean;
  detail_level: 'minimal' | 'summary' | 'full';
  timezone?: string;
}

/**
 * Load digest configuration
 */
function loadDigestConfig(): DigestConfig {
  const configPath = path.join(__dirname, '../../config/discord-digest.yml');

  try {
    if (fs.existsSync(configPath)) {
      const configFile = fs.readFileSync(configPath, 'utf-8');
      return yaml.load(configFile) as DigestConfig;
    }
  } catch (error) {
    logger.warn('Failed to load digest config, using defaults:', error);
  }

  // Default configuration
  return {
    schedule: '0 9 * * *', // 9am daily
    channel_id: process.env['DISCORD_DIGEST_CHANNEL_ID'] || '',
    enabled: true,
    detail_level: 'full',
  };
}

/**
 * Generate daily digest message
 */
async function generateDigest(detailLevel: 'minimal' | 'summary' | 'full'): Promise<string> {
  try {
    // Get current sprint
    const sprint = await getCurrentSprint();

    if (!sprint) {
      return '📊 **Daily Sprint Digest**\n\nℹ️ No active sprint found.';
    }

    // Get all issues
    const issues = await getTeamIssues();

    // Group by status
    const byStatus: Record<string, typeof issues> = {
      'In Progress': [],
      'Todo': [],
      'In Review': [],
      'Done': [],
      'Blocked': [],
    };

    issues.forEach(issue => {
      const status = issue.state?.name || 'Unknown';
      if (!byStatus[status]) {
        byStatus[status] = [];
      }
      byStatus[status].push(issue);
    });

    // Calculate progress
    const total = issues.length;
    const done = byStatus['Done']?.length || 0;
    const progress = total > 0 ? Math.round((done / total) * 100) : 0;

    // Format message based on detail level
    const today = new Date().toLocaleDateString('en-US', {
      weekday: 'long',
      year: 'numeric',
      month: 'long',
      day: 'numeric',
    });

    let message = `📊 **Daily Sprint Digest** - ${today}\n\n`;

    if (sprint.name) {
      message += `**Sprint:** ${sprint.name}\n`;
    }

    message += `**Progress:** ${done}/${total} tasks complete (${progress}%)\n\n`;

    if (detailLevel === 'minimal') {
      // Minimal: Just counts
      message += `🔵 In Progress: ${byStatus['In Progress']?.length || 0}\n`;
      message += `⚪ Todo: ${byStatus['Todo']?.length || 0}\n`;
      message += `🟡 In Review: ${byStatus['In Review']?.length || 0}\n`;
      message += `✅ Done: ${byStatus['Done']?.length || 0}\n`;
      if ((byStatus['Blocked']?.length || 0) > 0) {
        message += `🔴 Blocked: ${byStatus['Blocked']?.length || 0}\n`;
      }
    } else if (detailLevel === 'summary') {
      // Summary: Counts + task IDs
      const showTasks = (statusName: string, emoji: string) => {
        const tasks = byStatus[statusName];
        if (!tasks || tasks.length === 0) return '';

        let section = `${emoji} **${statusName}** (${tasks.length})\n`;
        tasks.slice(0, 3).forEach(issue => {
          section += `  • [${issue.identifier}] ${issue.title.slice(0, 50)}${issue.title.length > 50 ? '...' : ''}\n`;
        });
        if (tasks.length > 3) {
          section += `  ... and ${tasks.length - 3} more\n`;
        }
        return section + '\n';
      };

      message += showTasks('In Progress', '🔵');
      message += showTasks('Blocked', '🔴');
      message += showTasks('In Review', '🟡');
    } else {
      // Full: Detailed breakdown
      const showDetailedTasks = (statusName: string, emoji: string) => {
        const tasks = byStatus[statusName];
        if (!tasks || tasks.length === 0) return '';

        let section = `${emoji} **${statusName}** (${tasks.length})\n`;
        tasks.slice(0, 5).forEach(issue => {
          const assignee = issue.assignee?.name || 'Unassigned';
          section += `  • [${issue.identifier}] ${issue.title}\n`;
          section += `    Assignee: @${assignee}\n`;
        });
        if (tasks.length > 5) {
          section += `  ... and ${tasks.length - 5} more\n`;
        }
        return section + '\n';
      };

      message += showDetailedTasks('In Progress', '🔵');

      // Show blocked tasks prominently if any
      if ((byStatus['Blocked']?.length || 0) > 0) {
        message += showDetailedTasks('Blocked', '🔴');
      }

      message += showDetailedTasks('In Review', '🟡');

      // Show recently completed (Done tasks)
      const doneLength = byStatus['Done']?.length || 0;
      if (doneLength > 0) {
        message += `✅ **Completed Recently** (${doneLength})\n`;
        (byStatus['Done'] || []).slice(0, 3).forEach(issue => {
          message += `  • [${issue.identifier}] ${issue.title}\n`;
        });
        if (doneLength > 3) {
          message += `  ... and ${doneLength - 3} more\n`;
        }
        message += '\n';
      }

      // Show pending tasks
      const todoLength = byStatus['Todo']?.length || 0;
      if (todoLength > 0) {
        message += `⚪ **Todo** (${todoLength} remaining)\n\n`;
      }
    }

    message += `\n🔗 View full sprint in [Linear](https://linear.app/)\n`;
    message += `💬 Need help? Use \`/help\` for bot commands\n`;

    return message;
  } catch (error) {
    logger.error('Error generating digest:', error);
    return `📊 **Daily Sprint Digest**\n\n❌ Failed to generate digest. Check bot logs for details.`;
  }
}

/**
 * Send daily digest to Discord channel
 */
async function sendDailyDigest(client: Client, config: DigestConfig): Promise<void> {
  try {
    if (!config.enabled) {
      logger.info('Daily digest is disabled in config');
      return;
    }

    if (!config.channel_id) {
      logger.error('Daily digest channel ID not configured');
      return;
    }

    logger.info('Generating daily digest...');

    // Generate digest message
    const message = await generateDigest(config.detail_level);

    // Get channel
    const channel = await client.channels.fetch(config.channel_id);

    if (!channel || !channel.isTextBased()) {
      logger.error(`Invalid channel ID: ${config.channel_id}`);
      return;
    }

    // Send message
    await (channel as TextChannel).send(message);

    logger.info(`Daily digest sent to channel ${config.channel_id}`);
  } catch (error) {
    logger.error('Error sending daily digest:', error);
  }
}

/**
 * Start daily digest cron job
 */
export function startDailyDigest(client: Client): void {
  const config = loadDigestConfig();

  if (!config.enabled) {
    logger.info('Daily digest cron job is disabled');
    return;
  }

  // Validate cron schedule
  if (!cron.validate(config.schedule)) {
    logger.error(`Invalid cron schedule: ${config.schedule}`);
    return;
  }

  logger.info(`Starting daily digest cron job with schedule: ${config.schedule}`);

  // Schedule cron job
  cron.schedule(config.schedule, async () => {
    logger.info('Daily digest cron job triggered');
    await sendDailyDigest(client, config);
  }, {
    scheduled: true,
    timezone: config.timezone || 'UTC',
  });

  logger.info('Daily digest cron job started');
}

/**
 * Manually trigger digest (for testing)
 */
export async function triggerDigestManually(client: Client): Promise<void> {
  const config = loadDigestConfig();
  await sendDailyDigest(client, config);
}
