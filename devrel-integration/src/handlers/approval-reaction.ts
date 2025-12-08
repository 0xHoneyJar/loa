/**
 * Approval Reaction Handler
 *
 * Handles Discord reactions for approving DevRel translations:
 * - ✅ emoji = Approve summary
 * - ❌ emoji = Reject summary
 * - Enforces RBAC authorization
 * - Tracks multi-approval workflow
 * - Alerts on unauthorized attempts
 *
 * This implements CRITICAL-003 remediation.
 */

import { MessageReaction, User, PartialMessageReaction, PartialUser } from 'discord.js';
import { logger } from '../utils/logger';
import rbac from '../services/rbac';
import approvalWorkflow, { ApprovalState } from '../services/approval-workflow';

/**
 * Handle approval reaction (✅)
 */
export async function handleApprovalReaction(
  reaction: MessageReaction | PartialMessageReaction,
  user: User | PartialUser
): Promise<void> {
  try {
    // Ignore bot reactions
    if (user.bot) return;

    // Fetch full objects if partial
    if (reaction.partial) {
      await reaction.fetch();
    }
    if (user.partial) {
      await user.fetch();
    }

    const userId = user.id;
    const username = user.username;
    const guildId = reaction.message.guild?.id;

    logger.info('Approval reaction detected', {
      userId,
      username,
      messageId: reaction.message.id,
      guildId
    });

    // STEP 1: Check authorization (CRITICAL-003)
    const canApprove = await rbac.canApprove(userId, guildId);

    if (!canApprove) {
      // Remove reaction
      await reaction.users.remove(userId);

      // Notify user via DM
      try {
        await user.send(
          '❌ **Permission Denied**\n\n' +
          'You do not have permission to approve summaries.\n\n' +
          '**To request approval permissions:**\n' +
          '  • Contact your product manager or team lead\n' +
          '  • Required roles: Product Manager, Tech Lead, or CTO\n\n' +
          '**Authorized approvers:**\n' +
          `  • ${rbac.getApprovalRoles().map(r => `\`${r}\``).join(', ')}`
        );
      } catch (dmError) {
        logger.warn('Failed to send DM to unauthorized user', {
          userId,
          error: dmError.message
        });
      }

      logger.warn('Unauthorized approval attempt blocked', {
        userId,
        username,
        messageId: reaction.message.id
      });

      return;
    }

    // STEP 2: Extract summary ID from message
    const summaryId = extractSummaryId(reaction.message);

    if (!summaryId) {
      logger.warn('Could not extract summary ID from message', {
        messageId: reaction.message.id
      });
      await user.send('⚠️ This message is not a translation that can be approved.');
      return;
    }

    // STEP 3: Check if already approved by this user
    if (approvalWorkflow.hasUserApproved(summaryId, userId)) {
      await user.send('ℹ️ You have already approved this summary.');
      return;
    }

    // STEP 4: Check current state
    const currentState = approvalWorkflow.getState(summaryId);

    if (currentState === ApprovalState.APPROVED) {
      await user.send('ℹ️ This summary is already approved.');
      return;
    }

    if (currentState === ApprovalState.PUBLISHED) {
      await user.send('ℹ️ This summary has already been published.');
      return;
    }

    if (currentState === ApprovalState.REJECTED) {
      await user.send('ℹ️ This summary was rejected. Contact the requester to regenerate.');
      return;
    }

    // STEP 5: Record approval
    await approvalWorkflow.trackApproval(
      summaryId,
      ApprovalState.APPROVED,
      userId,
      username,
      undefined,
      {
        guildId,
        channelId: reaction.message.channel.id,
        messageId: reaction.message.id
      }
    );

    logger.info('Approval recorded', {
      summaryId,
      userId,
      username
    });

    // STEP 6: Check if blog publishing is enabled and requires multi-approval
    if (rbac.requiresMultiApproval('blog_publishing')) {
      const minimumApprovals = rbac.getMinimumApprovals();
      const hasMinimum = await approvalWorkflow.hasMinimumApprovals(summaryId, minimumApprovals);

      if (hasMinimum) {
        // Check if this user can publish
        const canPublish = await rbac.canPublishBlog(userId);

        if (canPublish) {
          // Notify about potential publishing
          if (reaction.message.channel && 'send' in reaction.message.channel) {
            await reaction.message.channel.send(
              `✅ **Approval threshold met (${minimumApprovals}/${minimumApprovals})**\n\n` +
              `Summary approved by multiple reviewers.\n\n` +
              `⚠️ **Blog publishing disabled by default** (CRITICAL-007)\n` +
              `Contact security team to enable blog publishing if required.`
            );
          }

          await user.send(
            '✅ **Summary Approved**\n\n' +
            'This summary has met the approval threshold.\n\n' +
            '**Note:** Blog publishing is currently disabled for security reasons (CRITICAL-007).\n' +
            'Distribution is limited to internal channels (Discord, Google Docs).'
          );
        } else {
          // User doesn't have publishing permission
          if (reaction.message.channel && 'send' in reaction.message.channel) {
            await reaction.message.channel.send(
              `✅ **Approved (${await getCurrentApprovalCount(summaryId)}/${minimumApprovals})**\n\n` +
              'Approval threshold met, but requires publisher permission for final distribution.'
            );
          }

          await user.send(
            '✅ **Summary Approved**\n\n' +
            'Your approval has been recorded.\n\n' +
            '**Status:** Approved but requires publisher permission for distribution.\n' +
            '**Contact:** CTO or designated publisher for final distribution.'
          );
        }
      } else {
        // Need more approvals
        const currentCount = await getCurrentApprovalCount(summaryId);
        const remaining = minimumApprovals - currentCount;

        if (reaction.message.channel && 'send' in reaction.message.channel) {
          await reaction.message.channel.send(
            `✅ **Approved by ${username}** (${currentCount}/${minimumApprovals})\n\n` +
            `Needs ${remaining} more approval${remaining > 1 ? 's' : ''} before distribution.`
          );
        }

        await user.send(
          '✅ **Approval Recorded**\n\n' +
          `Your approval has been recorded for this summary.\n\n` +
          `**Status:** ${currentCount}/${minimumApprovals} approvals\n` +
          `**Remaining:** ${remaining} more approval${remaining > 1 ? 's' : ''} needed`
        );
      }
    } else {
      // Single approval sufficient
      if (reaction.message.channel && 'send' in reaction.message.channel) {
        await reaction.message.channel.send(
          `✅ **Approved by ${username}**\n\n` +
          'Summary approved and ready for distribution to internal channels.'
        );
      }

      await user.send(
        '✅ **Summary Approved**\n\n' +
        'Your approval has been recorded. Summary is ready for internal distribution.'
      );
    }

  } catch (error) {
    logger.error('Error handling approval reaction', {
      error: error.message,
      stack: error.stack,
      userId: user.id
    });
  }
}

/**
 * Handle rejection reaction (❌)
 */
export async function handleRejectionReaction(
  reaction: MessageReaction | PartialMessageReaction,
  user: User | PartialUser
): Promise<void> {
  try {
    // Ignore bot reactions
    if (user.bot) return;

    // Fetch full objects if partial
    if (reaction.partial) {
      await reaction.fetch();
    }
    if (user.partial) {
      await user.fetch();
    }

    const userId = user.id;
    const username = user.username;
    const guildId = reaction.message.guild?.id;

    logger.info('Rejection reaction detected', {
      userId,
      username,
      messageId: reaction.message.id
    });

    // Check authorization
    const canApprove = await rbac.canApprove(userId, guildId);

    if (!canApprove) {
      await reaction.users.remove(userId);
      await user.send('❌ You do not have permission to reject summaries.');
      logger.warn('Unauthorized rejection attempt blocked', { userId, username });
      return;
    }

    // Extract summary ID
    const summaryId = extractSummaryId(reaction.message);

    if (!summaryId) {
      logger.warn('Could not extract summary ID from message');
      return;
    }

    // Record rejection
    await approvalWorkflow.trackApproval(
      summaryId,
      ApprovalState.REJECTED,
      userId,
      username,
      'Rejected via Discord reaction',
      {
        guildId,
        channelId: reaction.message.channel.id,
        messageId: reaction.message.id
      }
    );

    logger.info('Rejection recorded', { summaryId, userId, username });

    // Notify channel
    if (reaction.message.channel && 'send' in reaction.message.channel) {
      await reaction.message.channel.send(
        `❌ **Rejected by ${username}**\n\n` +
        'This summary has been rejected and will not be distributed.\n' +
        'Contact the requester if you need a revised version.'
      );
    }

    await user.send(
      '❌ **Summary Rejected**\n\n' +
      'Your rejection has been recorded. This summary will not be distributed.'
    );

  } catch (error) {
    logger.error('Error handling rejection reaction', {
      error: error.message,
      userId: user.id
    });
  }
}

/**
 * Extract summary ID from Discord message
 */
function extractSummaryId(message: any): string | null {
  try {
    // Look for summary ID in message content or embeds
    // Format: "**Summary ID:** summary-123-456"
    const content = message.content || '';

    // Try to match "Summary ID: xxx" pattern
    const match = content.match(/\*\*Summary ID:\*\*\s*([a-zA-Z0-9-]+)/i);
    if (match) {
      return match[1];
    }

    // Try embeds
    if (message.embeds && message.embeds.length > 0) {
      for (const embed of message.embeds) {
        const embedDescription = embed.description || '';
        const embedMatch = embedDescription.match(/\*\*Summary ID:\*\*\s*([a-zA-Z0-9-]+)/i);
        if (embedMatch) {
          return embedMatch[1];
        }
      }
    }

    // Fallback: use message ID as summary ID
    return `msg-${message.id}`;

  } catch (error) {
    logger.error('Failed to extract summary ID', { error: error.message });
    return null;
  }
}

/**
 * Get current approval count for a summary
 */
async function getCurrentApprovalCount(summaryId: string): Promise<number> {
  const approvals = approvalWorkflow.getApprovals(summaryId);
  const approvedApprovals = approvals.filter(a => a.state === ApprovalState.APPROVED);
  const uniqueApprovers = new Set(approvedApprovals.map(a => a.approvedBy));
  return uniqueApprovers.size;
}
