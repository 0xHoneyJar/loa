/**
 * Discord Command Handlers
 *
 * Handles Discord slash commands:
 * - /show-sprint - Display current sprint status
 * - /doc <type> - Fetch project documentation
 * - /my-tasks - Show user's assigned Linear tasks
 * - /preview <issue-id> - Get Vercel preview URL
 * - /my-notifications - User notification preferences
 * - /translate - Generate DevRel translation (CRITICAL-001, CRITICAL-002 security)
 */

import { Message } from 'discord.js';
import fs from 'fs';
import path from 'path';
import { logger, auditLog } from '../utils/logger';
import { requirePermission } from '../middleware/auth';
import { handleError } from '../utils/errors';
import { getCurrentSprint, getTeamIssues } from '../services/linearService';
import { checkRateLimit } from '../middleware/auth';
import { handleTranslate, handleTranslateHelp } from './translation-commands';
import { validateCommandInput, validateParameterLength, INPUT_LIMITS } from '../validators/document-size-validator';

/**
 * Main command router
 */
export async function handleCommand(message: Message): Promise<void> {
  try {
    const content = message.content.trim();

    // HIGH-003: Validate command input length (DoS prevention)
    const inputValidation = validateCommandInput(content);
    if (!inputValidation.valid) {
      await message.reply(
        `❌ Command too long. Maximum ${INPUT_LIMITS.MAX_COMMAND_LENGTH} characters allowed.\n\n` +
        `Your command: ${inputValidation.details?.currentValue} characters\n\n` +
        `Please shorten your command and try again.`
      );

      logger.warn('Command rejected due to length limit', {
        userId: message.author.id,
        userTag: message.author.tag,
        commandLength: content.length,
        maxLength: INPUT_LIMITS.MAX_COMMAND_LENGTH
      });

      return;
    }

    const [command, ...args] = content.slice(1).split(/\s+/);

    // Rate limiting
    const rateLimit = checkRateLimit(message.author.id, 'command');
    if (!rateLimit.allowed) {
      await message.reply(
        `⏱️ Rate limit exceeded. Please wait ${Math.ceil((rateLimit.resetAt - Date.now()) / 1000)}s before trying again.`
      );
      return;
    }

    // Audit log
    auditLog.command(message.author.id, message.author.tag, command || '', args || '');

    // Route to appropriate handler
    if (!command) return;

    switch (command.toLowerCase()) {
      case 'show-sprint':
        await handleShowSprint(message);
        break;

      case 'doc':
        await handleDoc(message, args);
        break;

      case 'my-tasks':
        await handleMyTasks(message);
        break;

      case 'preview':
        await handlePreview(message, args);
        break;

      case 'my-notifications':
        await handleMyNotifications(message);
        break;

      case 'translate':
        await handleTranslate(message, args);
        break;

      case 'translate-help':
        await handleTranslateHelp(message);
        break;

      case 'help':
        await handleHelp(message);
        break;

      default:
        await message.reply(`❌ Unknown command: \`/${command}\`\n\nUse \`/help\` to see available commands.`);
    }
  } catch (error) {
    logger.error('Error handling command:', error);
    const errorMessage = handleError(error, message.author.id, 'command');
    await message.reply(errorMessage);
  }
}

/**
 * /show-sprint - Display current sprint status
 */
async function handleShowSprint(message: Message): Promise<void> {
  try {
    // Check permission
    await requirePermission(message.author, message.guild, 'show-sprint');

    await message.reply('🔄 Fetching sprint status from Linear...');

    // Get current sprint
    const sprint = await getCurrentSprint();

    if (!sprint) {
      await message.reply('ℹ️ No active sprint found.');
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

    await message.reply(response);

    logger.info(`Sprint status displayed to ${message.author.tag}`);
  } catch (error) {
    throw error;
  }
}

/**
 * /doc <type> - Fetch project documentation
 */
async function handleDoc(message: Message, args: string[]): Promise<void> {
  try {
    // Check permission
    await requirePermission(message.author, message.guild, 'doc');

    if (args.length === 0) {
      await message.reply('❌ Usage: `/doc <type>`\n\nAvailable types: `prd`, `sdd`, `sprint`');
      return;
    }

    const docType = args[0]?.toLowerCase() || '';
    const validTypes = ['prd', 'sdd', 'sprint'];

    if (!validTypes.includes(docType)) {
      await message.reply(`❌ Invalid document type: \`${docType}\`\n\nAvailable types: ${validTypes.map(t => `\`${t}\``).join(', ')}`);
      return;
    }

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
      await message.reply('Invalid document type');
      return;
    }

    // Construct and validate path
    const docPath = path.resolve(DOC_ROOT, requestedFile);

    // CRITICAL: Verify the resolved path is within DOC_ROOT (prevent path traversal)
    if (!docPath.startsWith(DOC_ROOT)) {
      logger.error('Path traversal attempt detected', {
        user: message.author.id,
        docType,
        resolvedPath: docPath,
      });
      auditLog.permissionDenied(message.author.id, message.author.tag, 'path_traversal_attempt');
      await message.reply('Invalid document path');
      return;
    }

    // Check if file exists
    if (!fs.existsSync(docPath)) {
      await message.reply(`ℹ️ Document not found: \`${docType}.md\`\n\nThe document may not have been created yet.`);
      return;
    }

    // Additional security: verify no symlink shenanigans
    const realPath = fs.realpathSync(docPath);
    if (!realPath.startsWith(DOC_ROOT)) {
      logger.error('Symlink traversal attempt detected', {
        user: message.author.id,
        docPath,
        realPath,
      });
      auditLog.permissionDenied(message.author.id, message.author.tag, 'symlink_traversal_attempt');
      await message.reply('Invalid document path');
      return;
    }

    // Read file (now safely validated)
    const content = fs.readFileSync(realPath, 'utf-8');

    // Split into chunks (Discord message limit is 2000 chars)
    const maxLength = 1900; // Leave room for formatting
    const chunks = [];

    for (let i = 0; i < content.length; i += maxLength) {
      chunks.push(content.slice(i, i + maxLength));
    }

    // Send first chunk as reply
    if (chunks.length > 0) {
      await message.reply(`📄 **${docType.toUpperCase()} Document** (Part 1/${chunks.length})\n\n\`\`\`markdown\n${chunks[0]}\n\`\`\``);
    }

    // Send remaining chunks as follow-ups
    if (message.channel && 'send' in message.channel) {
      for (let i = 1; i < chunks.length; i++) {
        await message.channel.send(`📄 **${docType.toUpperCase()} Document** (Part ${i + 1}/${chunks.length})\n\n\`\`\`markdown\n${chunks[i]}\n\`\`\``);
      }
    }

    logger.info(`Document ${docType} sent to ${message.author.tag}`);
  } catch (error) {
    throw error;
  }
}

/**
 * /my-tasks - Show user's assigned Linear tasks
 */
async function handleMyTasks(message: Message): Promise<void> {
  try {
    // Check permission
    await requirePermission(message.author, message.guild, 'my-tasks');

    await message.reply('🔄 Fetching your tasks from Linear...');

    // Get user's Linear ID (would need to map Discord ID to Linear ID)
    // For now, we'll show all tasks - in production, implement user mapping

    const issues = await getTeamIssues();

    if (issues.length === 0) {
      await message.reply('ℹ️ No tasks found.');
      return;
    }

    // TODO: Filter by actual user's Linear ID
    // For now, show all tasks as placeholder
    let response = `📋 **Your Tasks**\n\n`;

    issues.slice(0, 10).forEach(issue => {
      const status = issue.state?.name || 'Unknown';
      const emoji = status === 'Done' ? '✅' : status === 'In Progress' ? '🔵' : '⚪';
      response += `${emoji} [${issue.identifier}] ${issue.title}\n`;
      response += `   Status: ${status}\n\n`;
    });

    if (issues.length > 10) {
      response += `... and ${issues.length - 10} more tasks\n\n`;
    }

    response += `View all tasks in Linear: https://linear.app/\n`;

    await message.reply(response);

    logger.info(`My tasks displayed to ${message.author.tag}`);
  } catch (error) {
    throw error;
  }
}

/**
 * /preview <issue-id> - Get Vercel preview URL
 */
async function handlePreview(message: Message, args: string[]): Promise<void> {
  try {
    // Check permission
    await requirePermission(message.author, message.guild, 'preview');

    if (args.length === 0) {
      await message.reply('❌ Usage: `/preview <issue-id>`\n\nExample: `/preview THJ-123`');
      return;
    }

    const issueId = args[0]?.toUpperCase() || '';

    // TODO: Implement Vercel preview URL lookup via MCP or API
    // For now, provide stub response
    await message.reply(`🔄 Looking up preview deployment for ${issueId}...\n\n⚠️ **Preview lookup not yet implemented**\n\nThis feature will query Vercel deployments linked to Linear issues.`);

    logger.info(`Preview requested for ${issueId} by ${message.author.tag}`);
  } catch (error) {
    throw error;
  }
}

/**
 * /my-notifications - User notification preferences
 */
async function handleMyNotifications(message: Message): Promise<void> {
  try {
    // Check permission
    await requirePermission(message.author, message.guild, 'my-notifications');

    // TODO: Implement user preferences management
    // For now, provide stub response
    await message.reply(`🔔 **Your Notification Preferences**\n\n✅ Daily digest: Enabled\n✅ Status updates: Enabled\n✅ Mentions: Enabled\n\n⚠️ **Note:** Notification preference management not yet fully implemented.`);

    logger.info(`Notification preferences viewed by ${message.author.tag}`);
  } catch (error) {
    throw error;
  }
}

/**
 * /help - Show available commands
 */
async function handleHelp(message: Message): Promise<void> {
  const response = `
🤖 **Agentic-Base Bot Commands**

**Public Commands:**
  • \`/show-sprint\` - Display current sprint status
  • \`/doc <type>\` - Fetch project documentation (prd, sdd, sprint)
  • \`/help\` - Show this help message

**Developer Commands:**
  • \`/my-tasks\` - Show your assigned Linear tasks
  • \`/preview <issue-id>\` - Get Vercel preview URL for issue
  • \`/my-notifications\` - View/update notification preferences

**DevRel Commands:**
  • \`/translate <docs> [format] [audience]\` - Generate stakeholder translation
  • \`/translate-help\` - Detailed help for translation feature

**Feedback Capture:**
  • React with 📌 to any message to capture it as Linear feedback

**Need help?** Contact a team admin or check the team playbook.
  `.trim();

  await message.reply(response);
}
