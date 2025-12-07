/**
 * Feedback Capture Handler
 *
 * Handles 📌 emoji reactions on Discord messages to capture feedback
 * and create draft Linear issues
 */

import { MessageReaction, User, Message } from 'discord.js';
import { logger, auditLog } from '../utils/logger';
import { createDraftIssue } from '../services/linearService';
import { hasPermissionForMember } from '../middleware/auth';
import { handleError } from '../utils/errors';

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

    // Format Linear issue description
    const issueTitle = `Feedback: ${messageContent.slice(0, 80)}${messageContent.length > 80 ? '...' : ''}`;
    const issueDescription = `
**Feedback captured from Discord**

${messageContent}

---

**Context:**
${threadInfo}- **Author:** ${messageAuthor.tag} (${messageAuthor.id})
- **Posted:** ${timestamp}
- **Discord:** [Link to message](${messageLink})
${attachments.length > 0 ? `- **Attachments:** ${attachments.length} file(s)\n` : ''}
${attachments.map(att => `  - [${att.name}](${att.url})`).join('\n')}

---

*Captured via 📌 reaction by ${user.tag}*
    `.trim();

    // Create draft Linear issue
    logger.info(`Creating draft Linear issue for feedback from ${messageAuthor.tag}`);

    const issue = await createDraftIssue(
      issueTitle,
      issueDescription
    );

    if (!issue) {
      logger.error('Failed to create draft Linear issue');
      await fullMessage.reply(
        `❌ Failed to create Linear issue. Check bot logs for details.`
      );
      return;
    }

    // Audit log
    auditLog.feedbackCaptured(
      user.id,
      user.tag,
      fullMessage.id,
      issue.identifier
    );

    // Reply with confirmation
    const confirmationMessage = `✅ **Feedback captured!**

**Linear Issue:** ${issue.identifier} - ${issue.title}
**URL:** ${issue.url}

The issue has been created as a draft. A team member will triage and assign it.`;

    await fullMessage.reply(confirmationMessage);

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
