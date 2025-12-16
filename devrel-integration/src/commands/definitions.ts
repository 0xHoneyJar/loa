/**
 * Discord Slash Command Definitions
 *
 * Defines all application commands that will be registered with Discord.
 * These will appear in Discord's UI with autocomplete.
 *
 * Sprint 3 - Task 3.1: Updated command definitions for MVP commands
 */

import { SlashCommandBuilder } from 'discord.js';

/**
 * All command definitions for the bot
 */
export const commands = [
  // /show-sprint - Display current sprint status (enhanced with Google Docs links)
  new SlashCommandBuilder()
    .setName('show-sprint')
    .setDescription('Display sprint status with links to reports and summaries')
    .addStringOption(option =>
      option
        .setName('sprint-id')
        .setDescription('Sprint identifier (e.g., sprint-1). Defaults to current sprint.')
        .setRequired(false)
    )
    .toJSON(),

  // /translate - Generate stakeholder summary from technical document
  new SlashCommandBuilder()
    .setName('translate')
    .setDescription('Generate stakeholder summary from technical document')
    .addStringOption(option =>
      option
        .setName('project')
        .setDescription('Project name (e.g., mibera, fatbera)')
        .setRequired(true)
    )
    .addStringOption(option =>
      option
        .setName('document')
        .setDescription('Document reference (e.g., @prd, @sdd, docs/sprint.md)')
        .setRequired(true)
    )
    .addStringOption(option =>
      option
        .setName('audience')
        .setDescription('Target audience')
        .setRequired(true)
        .addChoices(
          { name: 'Leadership', value: 'leadership' },
          { name: 'Product', value: 'product' },
          { name: 'Marketing', value: 'marketing' },
          { name: 'DevRel', value: 'devrel' }
        )
    )
    .toJSON(),

  // /exec-summary - Get executive summary for a sprint
  new SlashCommandBuilder()
    .setName('exec-summary')
    .setDescription('Get executive summary for a sprint')
    .addStringOption(option =>
      option
        .setName('sprint-id')
        .setDescription('Sprint identifier (e.g., sprint-1, mibera-sprint-1)')
        .setRequired(true)
    )
    .toJSON(),

  // /audit-summary - Get security audit summary for a sprint
  new SlashCommandBuilder()
    .setName('audit-summary')
    .setDescription('Get security audit summary for a sprint')
    .addStringOption(option =>
      option
        .setName('sprint-id')
        .setDescription('Sprint identifier (e.g., sprint-1, sprint-1-remediation)')
        .setRequired(true)
    )
    .toJSON(),

  // /doc - Fetch project documentation
  new SlashCommandBuilder()
    .setName('doc')
    .setDescription('Fetch project documentation')
    .addStringOption(option =>
      option
        .setName('type')
        .setDescription('Type of document to fetch')
        .setRequired(true)
        .addChoices(
          { name: 'Product Requirements (PRD)', value: 'prd' },
          { name: 'Software Design (SDD)', value: 'sdd' },
          { name: 'Sprint Plan', value: 'sprint' }
        )
    )
    .toJSON(),

  // /my-tasks - Show user's assigned Linear tasks
  new SlashCommandBuilder()
    .setName('my-tasks')
    .setDescription('Show your assigned Linear tasks')
    .toJSON(),

  // /preview - Get Vercel preview URL for an issue
  new SlashCommandBuilder()
    .setName('preview')
    .setDescription('Get Vercel preview URL for a Linear issue')
    .addStringOption(option =>
      option
        .setName('issue-id')
        .setDescription('Linear issue ID (e.g., DEV-123)')
        .setRequired(true)
    )
    .toJSON(),

  // /my-notifications - Manage notification preferences
  new SlashCommandBuilder()
    .setName('my-notifications')
    .setDescription('Manage your notification preferences')
    .toJSON(),

  // /mfa-enroll - Enroll in multi-factor authentication
  new SlashCommandBuilder()
    .setName('mfa-enroll')
    .setDescription('Set up two-factor authentication for secure operations')
    .toJSON(),

  // /mfa-verify - Verify MFA token
  new SlashCommandBuilder()
    .setName('mfa-verify')
    .setDescription('Verify your two-factor authentication token')
    .addStringOption(option =>
      option
        .setName('token')
        .setDescription('6-digit MFA token from your authenticator app')
        .setRequired(true)
        .setMinLength(6)
        .setMaxLength(6)
    )
    .toJSON(),

  // /mfa-status - Check MFA enrollment status
  new SlashCommandBuilder()
    .setName('mfa-status')
    .setDescription('Check your multi-factor authentication status')
    .toJSON(),

  // /mfa-disable - Disable MFA
  new SlashCommandBuilder()
    .setName('mfa-disable')
    .setDescription('Disable two-factor authentication')
    .toJSON(),

  // /mfa-backup - Get backup codes
  new SlashCommandBuilder()
    .setName('mfa-backup')
    .setDescription('Generate new MFA backup codes')
    .toJSON(),

  // /help - Show available commands
  new SlashCommandBuilder()
    .setName('help')
    .setDescription('Show available commands and usage information')
    .toJSON(),
];

/**
 * Command names for easy reference
 */
export const commandNames = commands.map(cmd => cmd.name);
