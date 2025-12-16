/**
 * Feedback Capture Handler
 *
 * Handles 📌 emoji reactions on Discord messages to capture feedback
 * and create draft Linear issues with automatic project detection
 * and priority emoji reactions
 */

import { MessageReaction, User, Message } from 'discord.js';
import { logger, auditLog } from '../utils/logger';
import { createLinearIssue, updateLinearIssue, getLinearIssue } from '../services/linearService';
import { hasPermissionForMember } from '../middleware/auth';
import { handleError } from '../utils/errors';
import { detectPII } from '../utils/validation';

// Store mapping of message ID to Linear issue ID for priority reactions
const messageToIssueMap = new Map<string, string>();

/**
 * Detect project label from Discord channel name
 *
 * Patterns:
 * - #project-{name} → project:{name}
 * - #{name}-feedback → project:{name}
 * - #{name}-dev → project:{name}
 */
function detectProjectFromChannel(channelName: string): string | null {
  // Pattern: #project-{name}
  const projectMatch = channelName.match(/^project-(.+)$/);
  if (projectMatch) {
    return `project:${projectMatch[1]}`;
  }

  // Pattern: #{name}-feedback
  const feedbackMatch = channelName.match(/^(.+)-feedback$/);
  if (feedbackMatch) {
    return `project:${feedbackMatch[1]}`;
  }

  // Pattern: #{name}-dev
  const devMatch = channelName.match(/^(.+)-dev$/);
  if (devMatch) {
    return `project:${devMatch[1]}`;
  }

  return null;
}

/**
 * Handle feedback capture (📌 reaction)
 */
export async function handleFeedbackCapture(
  reaction: MessageReaction,
  user: User
): Promise<void> {
  try {
    const message = reaction.message;

    // Fetch full message if partial
    let fullMessage: Message;
    if (message.partial) {
      try {
        fullMessage = await message.fetch();
      } catch (error) {
        logger.error('Failed to fetch partial message:', error);
        return;
      }
    } else {
      fullMessage = message as Message;
    }

    // Check permissions
    if (!fullMessage.guild) {
      logger.warn('Feedback capture attempted in DM, ignoring');
      return;
    }

    const member = await fullMessage.guild.members.fetch(user.id);
    if (!hasPermissionForMember(member, 'feedback-capture')) {
      logger.warn(`User ${user.tag} attempted feedback capture without permission`);
      await fullMessage.reply(
        `❌ You don't have permission to capture feedback. Contact an admin to get the developer role.`
      );
      return;
    }

    // Extract message context
    const messageContent = fullMessage.content || '[No text content]';
    const messageAuthor = fullMessage.author;
    const messageLink = `https://discord.com/channels/${fullMessage.guild.id}/${fullMessage.channel.id}/${fullMessage.id}`;
    const timestamp = fullMessage.createdAt.toISOString();

    // SECURITY FIX: Detect PII before sending to Linear
    const piiCheck = detectPII(messageContent);

    if (piiCheck.hasPII) {
      logger.warn('PII detected in feedback capture', {
        userId: user.id,
        messageId: fullMessage.id,
        piiTypes: piiCheck.types,
      });

      // Block feedback capture with PII
      await fullMessage.reply(
        `⚠️ **Cannot capture feedback: Sensitive information detected**\n\n` +
        `This message appears to contain: **${piiCheck.types.join(', ')}**\n\n` +
        `Please edit the message to remove sensitive information (emails, phone numbers, SSNs, etc.), then try again with 📌\n\n` +
        `*This protection prevents accidental exposure of private information to Linear.*`
      );

      auditLog.permissionDenied(user.id, user.tag, 'pii_in_feedback');
      return;
    }

    // Get attachments
    const attachments = fullMessage.attachments.map(att => ({
      name: att.name,
      url: att.url,
      type: att.contentType || 'unknown',
    }));

    // Check for thread context
    let threadInfo = '';
    if (fullMessage.channel.isThread()) {
      const thread = fullMessage.channel;
      threadInfo = `**Thread:** ${thread.name}\n`;
    }

    // Sanitize author info (don't expose full Discord IDs)
    const authorDisplay = messageAuthor.tag.replace(/#\d{4}$/, '#****');
    const authorIdPartial = messageAuthor.id.slice(0, 8) + '...';

    // Detect project from channel name
    const channelName = fullMessage.channel.isTextBased() && 'name' in fullMessage.channel
      ? (fullMessage.channel.name ?? '')
      : '';
    const projectLabel = detectProjectFromChannel(channelName);

    // Format Linear issue description
    const issueTitle = `Feedback: ${messageContent.slice(0, 80)}${messageContent.length > 80 ? '...' : ''}`;
    const issueDescription = `
**Feedback captured from Discord**

${messageContent}

---

**Context:**
${threadInfo}- **Author:** ${authorDisplay} (ID: ${authorIdPartial})
- **Posted:** ${timestamp}
- **Discord:** [Link to message](${messageLink})
${projectLabel ? `- **Project:** ${projectLabel}\n` : ''}${attachments.length > 0 ? `- **Attachments:** ${attachments.length} file(s)\n` : ''}
${attachments.map(att => `  - [${att.name}](${att.url})`).join('\n')}

---

*Captured via 📌 reaction by ${user.tag}*
*Note: PII automatically checked and blocked*
    `.trim();

    // Get team ID from environment
    const teamId = process.env['LINEAR_TEAM_ID'];
    if (!teamId) {
      logger.error('LINEAR_TEAM_ID not configured');
      await fullMessage.reply(
        `❌ Linear integration not configured. Contact an admin.`
      );
      return;
    }

    // Get label IDs for source:discord and project label (if detected)
    // Note: We'll create labels if they don't exist using the label name directly
    const labelNames = ['source:discord'];
    if (projectLabel) {
      labelNames.push(projectLabel);
    }

    // Create Linear issue with labels
    logger.info(`Creating Linear issue for feedback from ${messageAuthor.tag}`);

    const issueResult = await createLinearIssue({
      title: issueTitle,
      description: issueDescription,
      teamId: teamId,
      // Linear SDK accepts label names directly when creating issues
      // @ts-ignore - labelIds can accept names
      labelIds: labelNames,
    });

    if (!issueResult || !issueResult.issue) {
      logger.error('Failed to create Linear issue');
      await fullMessage.reply(
        `❌ Failed to create Linear issue. Check bot logs for details.`
      );
      return;
    }

    const issue = await issueResult.issue;

    // Audit log
    auditLog.feedbackCaptured(
      user.id,
      user.tag,
      fullMessage.id,
      issue.identifier
    );

    // Store message-to-issue mapping for priority reactions
    messageToIssueMap.set(fullMessage.id, issue.id);

    // Reply with confirmation
    const labelsText = projectLabel
      ? `\n**Labels:** \`source:discord\`, \`${projectLabel}\``
      : `\n**Labels:** \`source:discord\``;

    const confirmationMessage = `✅ **Feedback captured!**

**Linear Issue:** ${issue.identifier} - ${issue.title}
**URL:** ${issue.url}${labelsText}

The issue has been created. React with priority emojis to set urgency:
🔴 Critical | 🟠 High | 🟡 Normal | 🟢 Low`;

    const reply = await fullMessage.reply(confirmationMessage);

    // Add priority emoji reactions to the confirmation message
    try {
      await reply.react('🔴');
      await reply.react('🟠');
      await reply.react('🟡');
      await reply.react('🟢');
      logger.info(`Added priority reactions to confirmation message ${reply.id}`);
    } catch (reactionError) {
      logger.error('Failed to add priority reactions:', reactionError);
      // Non-critical error, don't fail the whole operation
    }

    logger.info(`Feedback captured: ${issue.identifier} from message ${fullMessage.id}`);
  } catch (error) {
    logger.error('Error in feedback capture:', error);
    const errorMessage = handleError(error, user.id, 'feedback_capture');

    try {
      const message = reaction.message;
      if (!message.partial) {
        await (message as Message).reply(errorMessage);
      }
    } catch (replyError) {
      logger.error('Failed to send error reply:', replyError);
    }
  }
}

/**
 * Handle priority emoji reactions (🔴🟠🟡🟢)
 *
 * Updates Linear issue priority when users react to the confirmation message
 */
export async function handlePriorityReaction(
  reaction: MessageReaction,
  user: User
): Promise<void> {
  try {
    const message = reaction.message;

    // Fetch full message if partial
    let fullMessage: Message;
    if (message.partial) {
      try {
        fullMessage = await message.fetch();
      } catch (error) {
        logger.error('Failed to fetch partial message:', error);
        return;
      }
    } else {
      fullMessage = message as Message;
    }

    // Check if this message is a bot confirmation message
    if (!fullMessage.author.bot) {
      return;
    }

    // Check if message content contains Linear issue reference
    const issueMatch = fullMessage.content.match(/\*\*Linear Issue:\*\* ([A-Z]+-\d+)/);
    if (!issueMatch) {
      return;
    }

    const issueIdentifier = issueMatch[1];

    // Check permissions
    if (!fullMessage.guild) {
      logger.warn('Priority reaction attempted in DM, ignoring');
      return;
    }

    const member = await fullMessage.guild.members.fetch(user.id);
    if (!hasPermissionForMember(member, 'feedback-capture')) {
      logger.warn(`User ${user.tag} attempted priority reaction without permission`);
      return;
    }

    // Map emoji to priority
    const emoji = reaction.emoji.name;
    let priority: number;
    let priorityLabel: string;

    switch (emoji) {
      case '🔴':
        priority = 1; // Urgent
        priorityLabel = 'Critical';
        break;
      case '🟠':
        priority = 2; // High
        priorityLabel = 'High';
        break;
      case '🟡':
        priority = 3; // Normal
        priorityLabel = 'Normal';
        break;
      case '🟢':
        priority = 4; // Low
        priorityLabel = 'Low';
        break;
      default:
        return; // Not a priority emoji
    }

    // Get the Linear issue
    const issue = await getLinearIssue(issueIdentifier);
    if (!issue) {
      logger.error(`Issue ${issueIdentifier} not found`);
      return;
    }

    // Update issue priority
    await updateLinearIssue(issue.id, { priority });

    logger.info(
      `Priority updated for ${issueIdentifier}: ${priorityLabel} (${priority}) by ${user.tag}`
    );

    // Audit log
    auditLog.feedbackCaptured(
      user.id,
      user.tag,
      fullMessage.id,
      `${issueIdentifier} priority updated to ${priorityLabel}`
    );

    // Reply to user
    await fullMessage.reply(
      `✅ **Priority updated:** ${issueIdentifier} set to **${priorityLabel}** by ${user.tag}`
    );
  } catch (error) {
    logger.error('Error in priority reaction handler:', error);
    // Don't send error messages for reaction failures (too noisy)
  }
}
