/**
 * MFA Commands Handler
 *
 * HIGH-005 Implementation: Discord commands for MFA enrollment and verification
 *
 * Commands:
 * - /mfa-enroll - Start MFA enrollment (generates QR code and backup codes)
 * - /mfa-verify <code> - Verify TOTP code to activate MFA
 * - /mfa-status - Check MFA enrollment status
 * - /mfa-disable <code> - Disable MFA (requires verification)
 * - /mfa-backup <code> - Verify using a backup code
 *
 * Security:
 * - QR codes and secrets sent via DM only
 * - Rate limiting on verification attempts
 * - Complete audit logging of all MFA operations
 */

import { Message, EmbedBuilder, AttachmentBuilder } from 'discord.js';
import mfaVerifier from '../services/mfa-verifier';
import userMappingService from '../services/user-mapping-service';
import { logger } from '../utils/logger';

/**
 * Handle /mfa-enroll command
 */
export async function handleMfaEnroll(message: Message): Promise<void> {
  try {
    // Check if already enrolled
    const isEnrolled = await mfaVerifier.isMfaEnabled(message.author.id);
    if (isEnrolled) {
      await message.reply('❌ You are already enrolled in MFA. Use `/mfa-disable` first if you want to re-enroll.');
      return;
    }

    // Generate MFA enrollment
    const enrollment = await mfaVerifier.enrollMfa(message.author.id);

    // Create QR code attachment
    const qrBuffer = Buffer.from(enrollment.qrCodeUrl.split(',')[1]!, 'base64');
    const qrAttachment = new AttachmentBuilder(qrBuffer, { name: 'mfa-qr-code.png' });

    // Create enrollment embed
    const embed = new EmbedBuilder()
      .setTitle('🔐 MFA Enrollment')
      .setDescription(
        '**Multi-Factor Authentication Setup**\n\n' +
        '1. Install an authenticator app (Google Authenticator, Authy, etc.)\n' +
        '2. Scan the QR code below with your authenticator app\n' +
        '3. Verify with `/mfa-verify <code>` to activate MFA\n\n' +
        '**Important:** Save your backup codes in a secure location. ' +
        'You will need them if you lose access to your authenticator app.'
      )
      .setColor('#0099ff')
      .addFields(
        { name: 'Secret Key (Manual Entry)', value: `\`${enrollment.secret}\``, inline: false },
        { name: 'Backup Codes', value: enrollment.backupCodes.map(code => `\`${code}\``).join('\n'), inline: false }
      )
      .setImage('attachment://mfa-qr-code.png')
      .setFooter({ text: 'MFA enrollment is pending until you verify with a code' });

    // Send via DM for security
    try {
      await message.author.send({ embeds: [embed], files: [qrAttachment] });
      await message.reply('✅ MFA enrollment started! Check your DMs for setup instructions. **Save your backup codes securely!**');
    } catch (error) {
      // User has DMs disabled
      await message.reply('❌ Cannot send MFA setup instructions. Please enable DMs and try again.');
      logger.error('Failed to send MFA enrollment DM:', error);
    }
  } catch (error) {
    logger.error('Error in /mfa-enroll:', error);
    await message.reply(`❌ MFA enrollment failed: ${error instanceof Error ? error.message : 'Unknown error'}`);
  }
}

/**
 * Handle /mfa-verify <code> command
 */
export async function handleMfaVerify(message: Message, args: string[]): Promise<void> {
  try {
    if (args.length < 1) {
      await message.reply('❌ Usage: `/mfa-verify <code>`\nExample: `/mfa-verify 123456`');
      return;
    }

    const code = args[0]!.trim();

    // Check if user is in pending enrollment
    const user = await userMappingService.getUserByDiscordId(message.author.id);
    if (!user) {
      await message.reply('❌ User not found in database.');
      return;
    }

    // Try to verify enrollment
    const verified = await mfaVerifier.verifyEnrollment(message.author.id, code);

    if (verified) {
      await message.reply(
        '✅ **MFA activated successfully!**\n\n' +
        'Your account is now protected with multi-factor authentication.\n' +
        'You will be prompted to verify with a code for sensitive operations.\n\n' +
        '**Remember to save your backup codes!**'
      );

      logger.info('MFA activated', {
        userId: user.id,
        discordUserId: message.author.id,
        discordUsername: message.author.tag
      });
    } else {
      await message.reply('❌ Invalid verification code. Please try again.');
    }
  } catch (error) {
    logger.error('Error in /mfa-verify:', error);

    if (error instanceof Error && error.message.includes('No pending MFA enrollment')) {
      await message.reply('❌ No pending MFA enrollment found. Use `/mfa-enroll` first.');
    } else {
      await message.reply(`❌ Verification failed: ${error instanceof Error ? error.message : 'Unknown error'}`);
    }
  }
}

/**
 * Handle /mfa-status command
 */
export async function handleMfaStatus(message: Message): Promise<void> {
  try {
    const isEnrolled = await mfaVerifier.isMfaEnabled(message.author.id);

    if (isEnrolled) {
      const embed = new EmbedBuilder()
        .setTitle('🔐 MFA Status')
        .setDescription('**Multi-Factor Authentication: ENABLED** ✅')
        .setColor('#00ff00')
        .addFields(
          { name: 'Status', value: 'Active', inline: true },
          { name: 'Type', value: 'TOTP (Time-based)', inline: true },
          { name: 'Protected Operations', value: '• Role management\n• Configuration changes\n• User management', inline: false }
        )
        .setFooter({ text: 'Use /mfa-disable to disable MFA' });

      await message.reply({ embeds: [embed] });
    } else {
      const embed = new EmbedBuilder()
        .setTitle('🔐 MFA Status')
        .setDescription('**Multi-Factor Authentication: DISABLED** ❌')
        .setColor('#ff0000')
        .addFields(
          { name: 'Status', value: 'Not enrolled', inline: true },
          { name: 'Risk Level', value: 'Elevated', inline: true },
          { name: 'Recommendation', value: 'Enable MFA to protect sensitive operations', inline: false }
        )
        .setFooter({ text: 'Use /mfa-enroll to enable MFA' });

      await message.reply({ embeds: [embed] });
    }
  } catch (error) {
    logger.error('Error in /mfa-status:', error);
    await message.reply(`❌ Failed to check MFA status: ${error instanceof Error ? error.message : 'Unknown error'}`);
  }
}

/**
 * Handle /mfa-disable <code> command
 */
export async function handleMfaDisable(message: Message, args: string[]): Promise<void> {
  try {
    // Check if MFA is enabled
    const isEnrolled = await mfaVerifier.isMfaEnabled(message.author.id);
    if (!isEnrolled) {
      await message.reply('❌ MFA is not enabled for your account.');
      return;
    }

    if (args.length < 1) {
      await message.reply('❌ Usage: `/mfa-disable <code>`\nYou must verify with your authenticator code to disable MFA.');
      return;
    }

    const code = args[0]!.trim();

    // Verify TOTP code before disabling
    const verificationResult = await mfaVerifier.verifyTotp(
      message.author.id,
      code,
      {
        operation: 'mfa_disable',
        context: { requestedBy: message.author.tag }
      }
    );

    if (!verificationResult.success) {
      await message.reply(
        `❌ Verification failed: ${verificationResult.failureReason}\n\n` +
        'You must verify with your authenticator code to disable MFA.'
      );
      return;
    }

    // Disable MFA
    await mfaVerifier.disableMfa(
      message.author.id,
      {
        discordUserId: message.author.id,
        discordUsername: message.author.tag,
        reason: 'User requested MFA disable'
      }
    );

    await message.reply(
      '✅ **MFA disabled successfully**\n\n' +
      'Your account is no longer protected by multi-factor authentication.\n' +
      'You can re-enable it anytime with `/mfa-enroll`.\n\n' +
      '⚠️  **Warning:** Your account is now less secure.'
    );

    logger.warn('MFA disabled', {
      discordUserId: message.author.id,
      discordUsername: message.author.tag
    });
  } catch (error) {
    logger.error('Error in /mfa-disable:', error);
    await message.reply(`❌ Failed to disable MFA: ${error instanceof Error ? error.message : 'Unknown error'}`);
  }
}

/**
 * Handle /mfa-backup <code> command
 */
export async function handleMfaBackup(message: Message, args: string[]): Promise<void> {
  try {
    if (args.length < 1) {
      await message.reply(
        '❌ Usage: `/mfa-backup <code>`\n' +
        'Use one of your backup codes to verify. Backup codes are one-time use.'
      );
      return;
    }

    const backupCode = args[0]!.trim().toUpperCase();

    // Verify backup code
    const verificationResult = await mfaVerifier.verifyBackupCode(
      message.author.id,
      backupCode,
      {
        operation: 'backup_code_verification',
        context: { requestedBy: message.author.tag }
      }
    );

    if (verificationResult.success) {
      await message.reply(
        '✅ **Backup code verified successfully**\n\n' +
        '⚠️  **Important:** This backup code has been used and is no longer valid.\n\n' +
        'If you are running low on backup codes, consider disabling and re-enrolling in MFA to generate new backup codes.'
      );

      logger.info('Backup code used', {
        discordUserId: message.author.id,
        discordUsername: message.author.tag
      });
    } else {
      await message.reply(
        `❌ Verification failed: ${verificationResult.failureReason}\n\n` +
        'Make sure you are using a valid backup code. Backup codes are one-time use only.'
      );
    }
  } catch (error) {
    logger.error('Error in /mfa-backup:', error);
    await message.reply(`❌ Backup code verification failed: ${error instanceof Error ? error.message : 'Unknown error'}`);
  }
}

/**
 * Main MFA command router
 */
export async function handleMfaCommand(message: Message): Promise<void> {
  const args = message.content.slice(1).trim().split(/\s+/);
  const command = args.shift()?.toLowerCase();

  switch (command) {
    case 'mfa-enroll':
      await handleMfaEnroll(message);
      break;

    case 'mfa-verify':
      await handleMfaVerify(message, args);
      break;

    case 'mfa-status':
      await handleMfaStatus(message);
      break;

    case 'mfa-disable':
      await handleMfaDisable(message, args);
      break;

    case 'mfa-backup':
      await handleMfaBackup(message, args);
      break;

    default:
      await message.reply(
        '❌ Unknown MFA command. Available commands:\n' +
        '• `/mfa-enroll` - Start MFA enrollment\n' +
        '• `/mfa-verify <code>` - Verify TOTP code\n' +
        '• `/mfa-status` - Check MFA status\n' +
        '• `/mfa-disable <code>` - Disable MFA\n' +
        '• `/mfa-backup <code>` - Verify with backup code'
      );
  }
}
