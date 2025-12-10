/**
 * Discord Slash Command Interaction Handlers
 *
 * Handles InteractionCreate events for slash commands.
 * This is the modern Discord command system that provides:
 * - Autocomplete in Discord UI
 * - Type-safe parameters
 * - Built-in permission checking
 */

import {
  ChatInputCommandInteraction,
  Interaction,
  Message,
  User,
  Guild,
} from 'discord.js';
import { logger, auditLog } from '../utils/logger';
import { requirePermission, checkRateLimit } from '../middleware/auth';
import { handleError } from '../utils/errors';
import { getCurrentSprint, getTeamIssues } from '../services/linearService';
import { validateCommandInput, INPUT_LIMITS } from '../validators/document-size-validator';
import { handleMfaCommand } from './mfa-commands';
import fs from 'fs';
import path from 'path';

/**
 * Main interaction router
 */
export async function handleInteraction(interaction: Interaction): Promise<void> {
  // Only handle slash commands
  if (!interaction.isChatInputCommand()) return;

  try {
    // Rate limiting
    const rateLimit = checkRateLimit(interaction.user.id, 'command');
    if (!rateLimit.allowed) {
      await interaction.reply({
        content: `⏱️ Rate limit exceeded. Please wait ${Math.ceil((rateLimit.resetAt - Date.now()) / 1000)}s before trying again.`,
        ephemeral: true,
      });
      return;
    }

    // Audit log
    const commandName = interaction.commandName;
    const options = interaction.options.data.map(opt => `${opt.name}=${opt.value}`);
    auditLog.command(interaction.user.id, interaction.user.tag, commandName, options);

    // Route to appropriate handler
    switch (commandName) {
      case 'show-sprint':
        await handleShowSprintSlash(interaction);
        break;

      case 'doc':
        await handleDocSlash(interaction);
        break;

      case 'my-tasks':
        await handleMyTasksSlash(interaction);
        break;

      case 'preview':
        await handlePreviewSlash(interaction);
        break;

      case 'my-notifications':
        await handleMyNotificationsSlash(interaction);
        break;

      case 'mfa-enroll':
      case 'mfa-verify':
      case 'mfa-status':
      case 'mfa-disable':
      case 'mfa-backup':
        await handleMfaSlash(interaction);
        break;

      case 'help':
        await handleHelpSlash(interaction);
        break;

      default:
        await interaction.reply({
          content: `❌ Unknown command: \`/${commandName}\``,
          ephemeral: true,
        });
    }
  } catch (error) {
    logger.error('Error handling interaction:', error);
    const errorMessage = handleError(error, interaction.user.id, 'command');

    if (interaction.replied || interaction.deferred) {
      await interaction.followUp({ content: errorMessage, ephemeral: true });
    } else {
      await interaction.reply({ content: errorMessage, ephemeral: true });
    }
  }
}

/**
 * /show-sprint - Display current sprint status
 */
async function handleShowSprintSlash(interaction: ChatInputCommandInteraction): Promise<void> {
  try {
    // Check permission
    await requirePermission(interaction.user, interaction.guild, 'show-sprint');

    // Defer reply since this might take a moment
    await interaction.deferReply();

    // Get current sprint
    const sprint = await getCurrentSprint();

    if (!sprint) {
      await interaction.editReply('ℹ️ No active sprint found.');
      return;
    }

    // Get issues in sprint
    const issues = await getTeamIssues(undefined, undefined);

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

    // Format response
    const statusEmoji: Record<string, string> = {
      'In Progress': '🔵',
      'Todo': '⚪',
      'In Review': '🟡',
      'Done': '✅',
      'Blocked': '🔴',
    };

    let response = `📊 **Sprint Status**\n\n`;

    if (sprint.name) {
      response += `**Sprint:** ${sprint.name}\n`;
    }
    if (sprint.startDate && sprint.endDate) {
      response += `**Duration:** ${new Date(sprint.startDate).toLocaleDateString()} - ${new Date(sprint.endDate).toLocaleDateString()}\n`;
    }

    response += `\n`;

    for (const [status, statusIssues] of Object.entries(byStatus)) {
      if (statusIssues.length === 0) continue;

      const emoji = statusEmoji[status] || '⚫';
      response += `\n${emoji} **${status}** (${statusIssues.length})\n`;

      statusIssues.slice(0, 5).forEach(issue => {
        const assignee = issue.assignee?.name || 'Unassigned';
        response += `  • [${issue.identifier}] ${issue.title} - @${assignee}\n`;
      });

      if (statusIssues.length > 5) {
        response += `  ... and ${statusIssues.length - 5} more\n`;
      }
    }

    // Calculate progress
    const total = issues.length;
    const done = byStatus['Done']?.length || 0;
    const progress = total > 0 ? Math.round((done / total) * 100) : 0;

    response += `\n📈 **Progress:** ${done}/${total} tasks complete (${progress}%)\n`;

    await interaction.editReply(response);

    logger.info(`Sprint status displayed to ${interaction.user.tag} via slash command`);
  } catch (error) {
    throw error;
  }
}

/**
 * /doc <type> - Fetch project documentation
 */
async function handleDocSlash(interaction: ChatInputCommandInteraction): Promise<void> {
  try {
    // Check permission
    await requirePermission(interaction.user, interaction.guild, 'doc');

    const docType = interaction.options.getString('type', true);

    await interaction.deferReply();

    // SECURITY FIX: Use absolute path for docs root and validate
    const DOC_ROOT = path.resolve(__dirname, '../../../docs');

    // Map doc type to filename (not path)
    const docFiles: Record<string, string> = {
      'prd': 'prd.md',
      'sdd': 'sdd.md',
      'sprint': 'sprint.md',
    };

    const requestedFile = docFiles[docType];
    if (!requestedFile) {
      await interaction.editReply('Invalid document type');
      return;
    }

    // Construct and validate path
    const docPath = path.resolve(DOC_ROOT, requestedFile);

    // Security: Ensure path is within DOC_ROOT
    if (!docPath.startsWith(DOC_ROOT)) {
      logger.warn('Path traversal attempt detected', {
        userId: interaction.user.id,
        userTag: interaction.user.tag,
        requestedType: docType,
        resolvedPath: docPath,
      });
      await interaction.editReply('❌ Invalid document path');
      return;
    }

    // Check if file exists
    if (!fs.existsSync(docPath)) {
      await interaction.editReply(`❌ Document not found: \`${docType}\`\n\nAvailable types: \`prd\`, \`sdd\`, \`sprint\``);
      return;
    }

    // Read file
    const content = fs.readFileSync(docPath, 'utf-8');

    // Discord message limit is 2000 chars
    if (content.length <= 1900) {
      await interaction.editReply(`📄 **${docType.toUpperCase()} Document**\n\n${content}`);
    } else {
      // Send as file attachment
      const buffer = Buffer.from(content, 'utf-8');
      await interaction.editReply({
        content: `📄 **${docType.toUpperCase()} Document** (attached as file, too long for message)`,
        files: [{
          attachment: buffer,
          name: `${docType}.md`,
        }],
      });
    }

    logger.info(`Document ${docType} fetched by ${interaction.user.tag} via slash command`);
  } catch (error) {
    throw error;
  }
}

/**
 * /my-tasks - Show user's assigned Linear tasks
 */
async function handleMyTasksSlash(interaction: ChatInputCommandInteraction): Promise<void> {
  try {
    await requirePermission(interaction.user, interaction.guild, 'my-tasks');

    await interaction.deferReply({ ephemeral: true });

    // TODO: Implement user mapping Discord ID -> Linear user
    await interaction.editReply('🚧 This feature is under development.\n\nFor now, use Linear directly to view your tasks.');

    logger.info(`My tasks requested by ${interaction.user.tag} via slash command`);
  } catch (error) {
    throw error;
  }
}

/**
 * /preview <issue-id> - Get Vercel preview URL
 */
async function handlePreviewSlash(interaction: ChatInputCommandInteraction): Promise<void> {
  try {
    await requirePermission(interaction.user, interaction.guild, 'preview');

    const issueId = interaction.options.getString('issue-id', true);

    await interaction.deferReply();

    // TODO: Implement Vercel integration
    await interaction.editReply(`🚧 Preview feature under development.\n\nIssue: \`${issueId}\``);

    logger.info(`Preview requested for ${issueId} by ${interaction.user.tag} via slash command`);
  } catch (error) {
    throw error;
  }
}

/**
 * /my-notifications - Manage notification preferences
 */
async function handleMyNotificationsSlash(interaction: ChatInputCommandInteraction): Promise<void> {
  try {
    await interaction.deferReply({ ephemeral: true });

    // TODO: Implement user preferences UI
    await interaction.editReply('🚧 Notification preferences feature under development.');

    logger.info(`Notification preferences requested by ${interaction.user.tag} via slash command`);
  } catch (error) {
    throw error;
  }
}

/**
 * MFA commands - Delegate to existing handler
 */
async function handleMfaSlash(interaction: ChatInputCommandInteraction): Promise<void> {
  try {
    // Convert interaction to a pseudo-message object for compatibility
    // This is a temporary bridge until MFA handler is refactored for interactions
    const pseudoMessage = {
      author: interaction.user,
      guild: interaction.guild,
      content: `/${interaction.commandName}`,
      reply: async (content: string) => {
        if (interaction.replied || interaction.deferred) {
          await interaction.followUp({ content, ephemeral: true });
        } else {
          await interaction.reply({ content, ephemeral: true });
        }
      },
    } as any as Message;

    await handleMfaCommand(pseudoMessage);
  } catch (error) {
    throw error;
  }
}

/**
 * /help - Show available commands
 */
async function handleHelpSlash(interaction: ChatInputCommandInteraction): Promise<void> {
  try {
    const helpText = `
🤖 **Agentic-Base Integration Bot** - Available Commands

**📊 Sprint & Tasks**
\`/show-sprint\` - Display current Linear sprint status
\`/my-tasks\` - Show your assigned Linear tasks

**📄 Documentation**
\`/doc prd\` - Product Requirements Document
\`/doc sdd\` - Software Design Document
\`/doc sprint\` - Sprint plan and tasks

**🚀 Vercel**
\`/preview <issue-id>\` - Get Vercel preview URL for an issue

**🔔 Notifications**
\`/my-notifications\` - Manage your notification preferences

**🔐 Security (MFA)**
\`/mfa-enroll\` - Set up two-factor authentication
\`/mfa-verify <token>\` - Verify MFA token
\`/mfa-status\` - Check MFA enrollment status
\`/mfa-disable\` - Disable MFA
\`/mfa-backup\` - Get backup codes

**📌 Feedback Capture**
React with 📌 emoji to any message to create a Linear draft issue

**ℹ️ Help**
\`/help\` - Show this help message

---
Need assistance? Check the documentation or contact your team admin.
    `.trim();

    await interaction.reply({ content: helpText, ephemeral: true });

    logger.info(`Help displayed to ${interaction.user.tag} via slash command`);
  } catch (error) {
    throw error;
  }
}
