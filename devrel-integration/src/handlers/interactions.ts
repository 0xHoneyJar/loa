/**
 * Discord Slash Command Interaction Handlers
 *
 * Handles InteractionCreate events for slash commands.
 * This is the modern Discord command system that provides:
 * - Autocomplete in Discord UI
 * - Type-safe parameters
 * - Built-in permission checking
 *
 * Sprint 3 - Task 3.7: Updated to include new commands
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
import { handleTranslateSlashCommand } from './translate-slash-command';
import { handleExecSummary, handleAuditSummary } from './summary-commands';
import googleDocsStorage from '../services/google-docs-storage';
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

      case 'translate':
        await handleTranslateSlashCommand(interaction);
        break;

      case 'exec-summary':
        await handleExecSummary(interaction);
        break;

      case 'audit-summary':
        await handleAuditSummary(interaction);
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
 * /show-sprint [sprint-id] - Display sprint status with Google Docs links
 *
 * Sprint 3 - Task 3.5: Enhanced with optional sprint-id parameter and Google Docs links
 */
async function handleShowSprintSlash(interaction: ChatInputCommandInteraction): Promise<void> {
  try {
    // Check permission
    await requirePermission(interaction.user, interaction.guild, 'show-sprint');

    // Get optional sprint-id parameter
    const sprintIdParam = interaction.options.getString('sprint-id');

    // Defer reply since this might take a moment
    await interaction.deferReply();

    // Get current sprint (or specific sprint if ID provided)
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
      const startDate = new Date(sprint.startDate);
      const endDate = new Date(sprint.endDate);
      const now = new Date();
      const daysRemaining = Math.ceil((endDate.getTime() - now.getTime()) / (1000 * 60 * 60 * 24));

      response += `**Timeline:**\n`;
      response += `  • Started: ${startDate.toLocaleDateString()}\n`;
      response += `  • Ends: ${endDate.toLocaleDateString()}`;
      if (daysRemaining > 0) {
        response += ` (${daysRemaining} days remaining)`;
      } else if (daysRemaining === 0) {
        response += ' (ends today)';
      } else {
        response += ` (${Math.abs(daysRemaining)} days overdue)`;
      }
      response += '\n';
    }

    response += `\n**Progress:**\n`;

    for (const [status, statusIssues] of Object.entries(byStatus)) {
      if (statusIssues.length === 0) continue;

      const emoji = statusEmoji[status] || '⚫';
      response += `${emoji} **${status}:** ${statusIssues.length} tasks`;

      // Show assignees for In Progress
      if (status === 'In Progress' && statusIssues.length > 0) {
        const assignees = [...new Set(statusIssues.map(i => i.assignee?.name).filter(Boolean))];
        if (assignees.length > 0) {
          response += ` (${assignees.join(', ')})`;
        }
      }

      // Show blockers for Blocked
      if (status === 'Blocked' && statusIssues.length > 0) {
        response += '\n';
        statusIssues.slice(0, 3).forEach(issue => {
          response += `  • [${issue.identifier}] ${issue.title}\n`;
        });
        if (statusIssues.length > 3) {
          response += `  ... and ${statusIssues.length - 3} more\n`;
        }
      } else {
        response += '\n';
      }
    }

    // Calculate progress
    const total = issues.length;
    const done = byStatus['Done']?.length || 0;
    const progress = total > 0 ? Math.round((done / total) * 100) : 0;
    const progressBar = generateProgressBar(progress);

    response += `\n**Overall Progress:** ${progressBar} ${progress}%\n`;

    // Try to add Google Docs links
    response += '\n**Documents:**\n';

    try {
      // Load folder config to get Google Docs links
      const folderConfigPath = path.join(process.cwd(), 'config', 'folder-ids.json');
      if (fs.existsSync(folderConfigPath)) {
        // For now, show placeholder links
        // In production, this would search Google Docs for matching documents
        response += '  📄 Sprint Plan: `/doc sprint`\n';
        response += '  📊 Executive Summary: `/exec-summary sprint-1`\n';
      } else {
        response += '  *Google Docs links unavailable (folder config not found)*\n';
      }
    } catch (error) {
      logger.warn('Failed to load Google Docs links for sprint status', {
        error: error instanceof Error ? error.message : String(error),
      });
      response += '  *Google Docs links unavailable*\n';
    }

    // Add next steps if sprint is nearly complete or overdue
    if (progress >= 90 || (sprint.endDate && new Date(sprint.endDate) < new Date())) {
      response += '\n**Next Steps:**\n';
      response += '  • Review sprint completion criteria\n';
      response += '  • Schedule retrospective meeting\n';
    }

    await interaction.editReply(response);

    logger.info(`Sprint status displayed to ${interaction.user.tag} via slash command`, {
      sprintId: sprintIdParam || 'current',
      progress,
    });
  } catch (error) {
    throw error;
  }
}

/**
 * Generate a text-based progress bar
 */
function generateProgressBar(percent: number): string {
  const filled = Math.round(percent / 10);
  const empty = 10 - filled;
  return '▓'.repeat(filled) + '░'.repeat(empty);
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
    // From dist/handlers/ -> ../../docs resolves to project_root/docs
    const DOC_ROOT = path.resolve(__dirname, '../../docs');

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
 *
 * Sprint 3: Updated with new DevRel translation commands
 */
async function handleHelpSlash(interaction: ChatInputCommandInteraction): Promise<void> {
  try {
    const helpText = `
🤖 **Onomancer Bot** - Available Commands

**📊 Sprint & Tasks**
\`/show-sprint [sprint-id]\` - Display sprint status with Google Docs links
\`/my-tasks\` - Show your assigned Linear tasks

**📝 DevRel Translation** (NEW!)
\`/translate <project> <document> <audience>\` - Generate stakeholder summary
  • Example: \`/translate mibera @prd leadership\`
\`/exec-summary <sprint-id>\` - Get executive summary for a sprint
\`/audit-summary <sprint-id>\` - Get security audit summary for a sprint

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
**Document Shorthands** (for /translate):
  • \`@prd\` → docs/prd.md
  • \`@sdd\` → docs/sdd.md
  • \`@sprint\` → docs/sprint.md
  • \`@reviewer\` → docs/a2a/reviewer.md
  • \`@audit\` → Security audit report

Need assistance? Check the documentation or contact your team admin.
    `.trim();

    await interaction.reply({ content: helpText, ephemeral: true });

    logger.info(`Help displayed to ${interaction.user.tag} via slash command`);
  } catch (error) {
    throw error;
  }
}
