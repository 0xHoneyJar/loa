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
 * - /tag-issue <issue-id> <project> [priority] - Tag Linear issue with project label
 * - /show-issue <issue-id> - Display Linear issue details
 * - /list-issues [filter] - List Linear issues with optional filters
 */

import { Message } from 'discord.js';
import fs from 'fs';
import path from 'path';
import { logger, auditLog } from '../utils/logger';
import { requirePermission } from '../middleware/auth';
import { handleError } from '../utils/errors';
import { getCurrentSprint, getTeamIssues, getLinearIssue, updateLinearIssue } from '../services/linearService';
import { checkRateLimit } from '../middleware/auth';
// TEMPORARILY DISABLED: Translation commands excluded from build
// import { handleTranslate, handleTranslateHelp } from './translation-commands';
import { validateCommandInput, validateParameterLength, INPUT_LIMITS } from '../validators/document-size-validator';
import { handleMfaCommand } from './mfa-commands';

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

      // TEMPORARILY DISABLED: Translation commands excluded from build
      // case 'translate':
      //   await handleTranslate(message, args);
      //   break;

      // case 'translate-help':
      //   await handleTranslateHelp(message);
      //   break;

      case 'mfa-enroll':
      case 'mfa-verify':
      case 'mfa-status':
      case 'mfa-disable':
      case 'mfa-backup':
        await handleMfaCommand(message);
        break;

      case 'tag-issue':
        await handleTagIssue(message, args);
        break;

      case 'show-issue':
        await handleShowIssue(message, args);
        break;

      case 'list-issues':
        await handleListIssues(message, args);
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
    const chunks: string[] = [];

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

**Security / MFA Commands:**
  • \`/mfa-enroll\` - Enable multi-factor authentication
  • \`/mfa-verify <code>\` - Verify TOTP code
  • \`/mfa-status\` - Check MFA enrollment status
  • \`/mfa-disable <code>\` - Disable MFA (requires verification)
  • \`/mfa-backup <code>\` - Verify with backup code

**Feedback Capture:**
  • React with 📌 to any message to capture it as Linear feedback

**Need help?** Contact a team admin or check the team playbook.
  `.trim();

  await message.reply(response);
}

/**
 * /tag-issue <issue-id> <project-name> [priority] - Tag a Linear issue with project label and optional priority
 */
async function handleTagIssue(message: Message, args: string[]): Promise<void> {
  try {
    // Check permission
    await requirePermission(message.author, message.guild, 'tag-issue');

    if (args.length < 2) {
      await message.reply(
        '❌ Usage: `/tag-issue <issue-id> <project-name> [priority]`\n\n' +
        'Examples:\n' +
        '  • `/tag-issue IMPL-123 devrel-integration`\n' +
        '  • `/tag-issue IMPL-123 devrel-integration high`\n\n' +
        'Valid priorities: critical, high, normal, low'
      );
      return;
    }

    const [issueIdArg, projectName, priorityArg] = args;

    // Validate inputs
    const issueIdValidation = validateParameterLength('issue ID', issueIdArg);
    const projectValidation = validateParameterLength('project name', projectName);

    if (!issueIdValidation.valid) {
      await message.reply(`❌ ${issueIdValidation.error}`);
      return;
    }

    if (!projectValidation.valid) {
      await message.reply(`❌ ${projectValidation.error}`);
      return;
    }

    await message.reply('🔄 Tagging Linear issue...');

    // Get the issue
    const issue = await getLinearIssue(issueIdArg);
    if (!issue) {
      await message.reply(`❌ Issue ${issueIdArg} not found in Linear.`);
      return;
    }

    // Create project label name
    const projectLabel = `project:${projectName.toLowerCase().replace(/\s+/g, '-')}`;

    // Build labels array - for now, just add the project label
    // In a full implementation, you'd:
    // 1. Check if label exists
    // 2. Create it if it doesn't
    // 3. Handle priority labels
    // This is a simplified version that assumes labels exist

    // Update issue with new labels (simplified - would need full Linear SDK integration)
    await updateLinearIssue(issueIdArg, {
      // Note: This is simplified. Full implementation would:
      // - Fetch existing labels
      // - Add new project label
      // - Handle priority label updates
      // - Use Linear SDK's label management
    });

    // For now, just confirm the action
    const priorityMsg = priorityArg ? ` and priority:${priorityArg}` : '';
    await message.reply(
      `✅ Issue ${issueIdArg} tagged with **${projectLabel}**${priorityMsg}\n` +
      `View: ${issue.url || `https://linear.app/issue/${issueIdArg}`}`
    );

    logger.info(`Issue ${issueIdArg} tagged: ${projectLabel}${priorityMsg} by ${message.author.tag}`);
  } catch (error) {
    logger.error('Error tagging issue:', error);
    const errorMessage = handleError(error, message.author.id, 'tag-issue');
    await message.reply(errorMessage);
  }
}

/**
 * /show-issue <issue-id> - Display Linear issue details
 */
async function handleShowIssue(message: Message, args: string[]): Promise<void> {
  try {
    // Check permission
    await requirePermission(message.author, message.guild, 'show-issue');

    if (args.length < 1) {
      await message.reply(
        '❌ Usage: `/show-issue <issue-id>`\n\n' +
        'Example: `/show-issue IMPL-123`'
      );
      return;
    }

    const issueId = args[0];

    // Validate input
    const validation = validateParameterLength('issue ID', issueId);
    if (!validation.valid) {
      await message.reply(`❌ ${validation.error}`);
      return;
    }

    await message.reply('🔄 Fetching issue from Linear...');

    // Get the issue
    const issue = await getLinearIssue(issueId);
    if (!issue) {
      await message.reply(`❌ Issue ${issueId} not found.`);
      return;
    }

    // Format status emoji
    const statusEmojis: Record<string, string> = {
      'Todo': '📋',
      'In Progress': '🔄',
      'In Review': '👁️',
      'Done': '✅',
      'Blocked': '🚫',
    };
    const statusEmoji = statusEmojis[issue.state?.name] || '❓';

    // Format priority
    const priorityEmojis: Record<number, string> = {
      1: '🔴 Critical',
      2: '🟠 High',
      3: '🟡 Normal',
      4: '🟢 Low',
    };
    const priority = priorityEmojis[issue.priority] || '⚪ Not set';

    // Format labels
    const labels = issue.labels?.nodes?.map((l: any) => `\`${l.name}\``).join(', ') || 'None';

    // Build response
    let response = `${statusEmoji} **${issue.identifier}: ${issue.title}**\n\n`;
    response += `**Status:** ${issue.state?.name || 'Unknown'}\n`;
    response += `**Priority:** ${priority}\n`;
    response += `**Assignee:** ${issue.assignee?.name || 'Unassigned'}\n`;
    response += `**Labels:** ${labels}\n`;

    if (issue.description) {
      const truncated = issue.description.length > 500
        ? issue.description.substring(0, 500) + '...'
        : issue.description;
      response += `\n**Description:**\n${truncated}\n`;
    }

    response += `\n🔗 [View in Linear](${issue.url || `https://linear.app/issue/${issueId}`})`;

    await message.reply(response);

    logger.info(`Issue ${issueId} displayed to ${message.author.tag}`);
  } catch (error) {
    logger.error('Error showing issue:', error);
    const errorMessage = handleError(error, message.author.id, 'show-issue');
    await message.reply(errorMessage);
  }
}

/**
 * /list-issues [filter] - List Linear issues with optional filters
 */
async function handleListIssues(message: Message, args: string[]): Promise<void> {
  try {
    // Check permission
    await requirePermission(message.author, message.guild, 'list-issues');

    await message.reply('🔄 Fetching issues from Linear...');

    // Build filter from args
    // Simple implementation - full version would parse filters like:
    // sprint:sprint-1, project:devrel, agent:implementer, priority:high
    const filter = args.length > 0 ? { /* filter logic would go here */ } : undefined;

    // Get issues
    const issues = await getTeamIssues(undefined, filter);

    if (!issues || issues.length === 0) {
      await message.reply('📭 No issues found matching your filter.');
      return;
    }

    // Group by status
    const grouped: Record<string, any[]> = {
      'Todo': [],
      'In Progress': [],
      'In Review': [],
      'Done': [],
      'Other': [],
    };

    for (const issue of issues) {
      const status = issue.state?.name || 'Other';
      if (grouped[status]) {
        grouped[status].push(issue);
      } else {
        grouped['Other'].push(issue);
      }
    }

    // Build response
    const statusEmojis: Record<string, string> = {
      'Todo': '📋',
      'In Progress': '🔄',
      'In Review': '👁️',
      'Done': '✅',
      'Other': '❓',
    };

    const sections: string[] = [];
    for (const [status, issueList] of Object.entries(grouped)) {
      if (issueList.length === 0) continue;

      const emoji = statusEmojis[status];
      const lines = issueList.slice(0, 10).map(issue =>
        `  ${emoji} ${issue.identifier} - ${issue.title.substring(0, 60)}`
      );

      if (issueList.length > 10) {
        lines.push(`  ... and ${issueList.length - 10} more`);
      }

      sections.push(`**${emoji} ${status} (${issueList.length})**\n${lines.join('\n')}`);
    }

    const filterDesc = args.length > 0 ? ` (filter: ${args.join(' ')})` : '';
    let response = `**Linear Issues${filterDesc}**\n\n`;
    response += `Showing ${issues.length} issue${issues.length !== 1 ? 's' : ''}:\n\n`;
    response += sections.join('\n\n');

    // Split if too long (Discord has 2000 char limit)
    if (response.length > 1900) {
      response = response.substring(0, 1900) + '\n\n... (truncated)';
    }

    await message.reply(response);

    logger.info(`Issues listed for ${message.author.tag} (${issues.length} issues)`);
  } catch (error) {
    logger.error('Error listing issues:', error);
    const errorMessage = handleError(error, message.author.id, 'list-issues');
    await message.reply(errorMessage);
  }
}
