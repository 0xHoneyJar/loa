/**
 * Summary Command Handlers
 *
 * Sprint 3 - Tasks 3.3 & 3.4: Summary Command Handlers
 *
 * Handles Discord slash commands for fetching pre-generated summaries:
 * - /exec-summary <sprint-id> - Get executive summary for a sprint
 * - /audit-summary <sprint-id> - Get security audit summary for a sprint
 *
 * Features:
 * - Sprint ID parsing (supports multiple formats)
 * - User role detection for persona mapping
 * - Google Docs search for matching summaries
 * - Severity breakdown display for audit summaries
 * - User-friendly error messages
 */

import { ChatInputCommandInteraction } from 'discord.js';
import { logger, auditLog } from '../utils/logger';
import { requirePermission } from '../middleware/auth';
import googleDocsStorage from '../services/google-docs-storage';
import roleMapper from '../services/role-mapper';
import { PersonaType } from '../prompts/persona-prompts';
import * as fs from 'fs';
import * as path from 'path';

// =============================================================================
// Types and Interfaces
// =============================================================================

interface ParsedSprintId {
  project?: string;
  sprintNumber: number;
  isRemediation: boolean;
  originalInput: string;
}

interface SeverityBreakdown {
  critical: number;
  high: number;
  medium: number;
  low: number;
  total: number;
}

interface FolderConfig {
  leadership: string;
  product: string;
  marketing: string;
  devrel: string;
  originals: string;
}

// =============================================================================
// Helper Functions
// =============================================================================

/**
 * Parse sprint ID from various formats
 * Supports: sprint-1, mibera-sprint-1, Sprint-1, sprint1, sprint-1-remediation
 */
function parseSprintId(input: string): ParsedSprintId | null {
  // Normalize input
  const normalized = input.toLowerCase().trim();

  // Check for remediation suffix
  const isRemediation = normalized.includes('-remediation') || normalized.includes('_remediation');
  const baseInput = normalized.replace(/-?_?remediation/g, '');

  // Pattern 1: project-sprint-N (e.g., mibera-sprint-1)
  const projectSprintMatch = baseInput.match(/^([a-z]+)-sprint-?(\d+)$/);
  if (projectSprintMatch) {
    return {
      project: projectSprintMatch[1],
      sprintNumber: parseInt(projectSprintMatch[2], 10),
      isRemediation,
      originalInput: input,
    };
  }

  // Pattern 2: sprint-N or sprintN (e.g., sprint-1, sprint1)
  const sprintMatch = baseInput.match(/^sprint-?(\d+)$/);
  if (sprintMatch) {
    return {
      sprintNumber: parseInt(sprintMatch[1], 10),
      isRemediation,
      originalInput: input,
    };
  }

  // Pattern 3: Just a number
  const numberMatch = baseInput.match(/^(\d+)$/);
  if (numberMatch) {
    return {
      sprintNumber: parseInt(numberMatch[1], 10),
      isRemediation,
      originalInput: input,
    };
  }

  return null;
}

/**
 * Load folder configuration
 */
async function loadFolderConfig(): Promise<FolderConfig | null> {
  try {
    const configPath = path.join(process.cwd(), 'config', 'folder-ids.json');
    if (fs.existsSync(configPath)) {
      const config = JSON.parse(fs.readFileSync(configPath, 'utf-8'));
      return {
        leadership: config.leadership || config.summaries?.leadership || '',
        product: config.product || config.summaries?.product || '',
        marketing: config.marketing || config.summaries?.marketing || '',
        devrel: config.devrel || config.summaries?.devrel || '',
        originals: config.originals || config.products || '',
      };
    }
    return null;
  } catch (error) {
    logger.warn('Failed to load folder config', {
      error: error instanceof Error ? error.message : String(error),
    });
    return null;
  }
}

/**
 * Parse severity breakdown from audit content
 */
function parseSeverityBreakdown(content: string): SeverityBreakdown {
  const breakdown: SeverityBreakdown = {
    critical: 0,
    high: 0,
    medium: 0,
    low: 0,
    total: 0,
  };

  // Count severity mentions in content
  // Look for patterns like "CRITICAL:", "HIGH:", "[CRITICAL]", etc.
  const criticalMatches = content.match(/\b(CRITICAL|Critical)\b[:\s]/g);
  const highMatches = content.match(/\b(HIGH|High)\b[:\s]/g);
  const mediumMatches = content.match(/\b(MEDIUM|Medium)\b[:\s]/g);
  const lowMatches = content.match(/\b(LOW|Low)\b[:\s]/g);

  breakdown.critical = criticalMatches?.length || 0;
  breakdown.high = highMatches?.length || 0;
  breakdown.medium = mediumMatches?.length || 0;
  breakdown.low = lowMatches?.length || 0;
  breakdown.total = breakdown.critical + breakdown.high + breakdown.medium + breakdown.low;

  return breakdown;
}

/**
 * Format severity breakdown for display
 */
function formatSeverityBreakdown(breakdown: SeverityBreakdown): string {
  const lines = [
    `  \u2022 \ud83d\udd34 CRITICAL: ${breakdown.critical} issues`,
    `  \u2022 \ud83d\udfe0 HIGH: ${breakdown.high} issues`,
    `  \u2022 \ud83d\udfe1 MEDIUM: ${breakdown.medium} issues`,
    `  \u2022 \ud83d\udfe2 LOW: ${breakdown.low} issues`,
  ];
  return lines.join('\n');
}

// =============================================================================
// Command Handlers
// =============================================================================

/**
 * /exec-summary <sprint-id> - Get executive summary for a sprint
 */
export async function handleExecSummary(interaction: ChatInputCommandInteraction): Promise<void> {
  try {
    // Check permission
    await requirePermission(interaction.user, interaction.guild, 'doc');

    const sprintIdInput = interaction.options.getString('sprint-id', true);

    // Defer reply since this may take a moment
    await interaction.deferReply();

    logger.info('Executive summary requested', {
      userId: interaction.user.id,
      userTag: interaction.user.tag,
      sprintId: sprintIdInput,
    });

    // Parse sprint ID
    const parsedSprintId = parseSprintId(sprintIdInput);
    if (!parsedSprintId) {
      await interaction.editReply(
        `\u274c **Invalid sprint ID format:** \`${sprintIdInput}\`\n\n` +
          '**Expected formats:**\n' +
          '  \u2022 `sprint-1`\n' +
          '  \u2022 `mibera-sprint-1`\n' +
          '  \u2022 `sprint1`\n\n' +
          'Please try again with a valid sprint identifier.'
      );
      return;
    }

    // Detect user persona from Discord roles
    let userPersona: PersonaType = 'product';
    if (interaction.guild) {
      try {
        const member = await interaction.guild.members.fetch(interaction.user.id);
        userPersona = await roleMapper.detectPersona(member);
      } catch (error) {
        logger.warn('Failed to detect user persona', {
          userId: interaction.user.id,
          error: error instanceof Error ? error.message : String(error),
        });
      }
    }

    // Load folder configuration
    const folderConfig = await loadFolderConfig();
    if (!folderConfig) {
      await interaction.editReply(
        '\u26a0\ufe0f **Configuration not found**\n\n' +
          'Google Drive folder configuration is missing. Please contact your administrator to set up folder mappings.'
      );
      return;
    }

    // Get folder ID for user's persona
    const folderId = folderConfig[userPersona];
    if (!folderId) {
      await interaction.editReply(
        `\u26a0\ufe0f **Folder not configured for persona:** ${userPersona}\n\n` +
          'Please contact your administrator to configure the folder mapping.'
      );
      return;
    }

    // Initialize Google Docs service
    await googleDocsStorage.initialize();

    // Search for matching summary document
    const searchQuery = `Sprint ${parsedSprintId.sprintNumber}`;
    const projectFilter = parsedSprintId.project ? ` ${parsedSprintId.project}` : '';

    try {
      const searchResults = await googleDocsStorage.searchDocuments(
        folderId,
        `${searchQuery}${projectFilter}`
      );

      if (!searchResults || searchResults.documents.length === 0) {
        await interaction.editReply(
          `\u2139\ufe0f **Executive summary not found for Sprint ${parsedSprintId.sprintNumber}**\n\n` +
            `No ${userPersona} summary found for this sprint.\n\n` +
            '**To generate a summary:**\n' +
            `  \`/translate ${parsedSprintId.project || 'project'} @sprint for ${userPersona}\`\n\n` +
            '*This will generate a new summary from the sprint documentation.*'
        );
        return;
      }

      // Get the first matching document
      const summaryDoc = searchResults.documents[0];

      // Format response
      const response =
        `\u2705 **Sprint ${parsedSprintId.sprintNumber} Executive Summary**\n\n` +
        (parsedSprintId.project ? `**Project:** ${parsedSprintId.project.charAt(0).toUpperCase() + parsedSprintId.project.slice(1)}\n` : '') +
        `**Sprint:** Sprint ${parsedSprintId.sprintNumber}\n` +
        `**Your Role:** ${userPersona.charAt(0).toUpperCase() + userPersona.slice(1)}\n\n` +
        `\ud83d\udcc4 [View Executive Summary in Google Docs](${summaryDoc.webViewLink})\n\n`;

      // Add summary preview if available
      let fullResponse = response;
      if (summaryDoc.content && summaryDoc.content.length > 0) {
        const preview = summaryDoc.content.substring(0, 300).trim();
        fullResponse +=
          '**Summary Preview:**\n' +
          `> ${preview.replace(/\n/g, '\n> ')}${summaryDoc.content.length > 300 ? '...' : ''}\n`;
      }

      await interaction.editReply(fullResponse);

      auditLog.command(interaction.user.id, interaction.user.tag, 'exec-summary', [
        `sprint-id=${sprintIdInput}`,
        `persona=${userPersona}`,
        `documentId=${summaryDoc.documentId}`,
      ]);

      logger.info('Executive summary delivered', {
        userId: interaction.user.id,
        sprintNumber: parsedSprintId.sprintNumber,
        persona: userPersona,
        documentId: summaryDoc.documentId,
      });
    } catch (error) {
      logger.error('Failed to search for executive summary', {
        userId: interaction.user.id,
        sprintId: sprintIdInput,
        error: error instanceof Error ? error.message : String(error),
      });

      await interaction.editReply(
        '\u274c **Failed to fetch executive summary**\n\n' +
          'An error occurred while searching for the summary. Please try again later.\n\n' +
          `*Error: ${error instanceof Error ? error.message : 'Unknown error'}*`
      );
    }
  } catch (error) {
    logger.error('Error in exec-summary command', {
      userId: interaction.user.id,
      error: error instanceof Error ? error.message : String(error),
    });

    if (interaction.deferred) {
      await interaction.editReply(
        `\u274c **Error:** ${error instanceof Error ? error.message : 'An unexpected error occurred'}`
      );
    } else {
      await interaction.reply({
        content: `\u274c **Error:** ${error instanceof Error ? error.message : 'An unexpected error occurred'}`,
        ephemeral: true,
      });
    }
  }
}

/**
 * /audit-summary <sprint-id> - Get security audit summary for a sprint
 */
export async function handleAuditSummary(interaction: ChatInputCommandInteraction): Promise<void> {
  try {
    // Check permission
    await requirePermission(interaction.user, interaction.guild, 'doc');

    const sprintIdInput = interaction.options.getString('sprint-id', true);

    // Defer reply since this may take a moment
    await interaction.deferReply();

    logger.info('Audit summary requested', {
      userId: interaction.user.id,
      userTag: interaction.user.tag,
      sprintId: sprintIdInput,
    });

    // Parse sprint ID
    const parsedSprintId = parseSprintId(sprintIdInput);
    if (!parsedSprintId) {
      await interaction.editReply(
        `\u274c **Invalid sprint ID format:** \`${sprintIdInput}\`\n\n` +
          '**Expected formats:**\n' +
          '  \u2022 `sprint-1`\n' +
          '  \u2022 `sprint-1-remediation`\n' +
          '  \u2022 `mibera-sprint-1-audit`\n\n' +
          'Please try again with a valid sprint identifier.'
      );
      return;
    }

    // Detect user persona from Discord roles
    let userPersona: PersonaType = 'product';
    if (interaction.guild) {
      try {
        const member = await interaction.guild.members.fetch(interaction.user.id);
        userPersona = await roleMapper.detectPersona(member);
      } catch (error) {
        logger.warn('Failed to detect user persona', {
          userId: interaction.user.id,
          error: error instanceof Error ? error.message : String(error),
        });
      }
    }

    // Load folder configuration
    const folderConfig = await loadFolderConfig();
    if (!folderConfig) {
      await interaction.editReply(
        '\u26a0\ufe0f **Configuration not found**\n\n' +
          'Google Drive folder configuration is missing. Please contact your administrator.'
      );
      return;
    }

    // Get folder ID for user's persona
    const folderId = folderConfig[userPersona];
    if (!folderId) {
      await interaction.editReply(
        `\u26a0\ufe0f **Folder not configured for persona:** ${userPersona}\n\n` +
          'Please contact your administrator to configure the folder mapping.'
      );
      return;
    }

    // Initialize Google Docs service
    await googleDocsStorage.initialize();

    // Search for matching audit document
    const searchQuery = parsedSprintId.isRemediation
      ? `Sprint ${parsedSprintId.sprintNumber} Remediation Audit`
      : `Sprint ${parsedSprintId.sprintNumber} Audit`;
    const projectFilter = parsedSprintId.project ? ` ${parsedSprintId.project}` : '';

    try {
      const searchResults = await googleDocsStorage.searchDocuments(
        folderId,
        `${searchQuery}${projectFilter}`
      );

      if (!searchResults || searchResults.documents.length === 0) {
        await interaction.editReply(
          `\u2139\ufe0f **Audit summary not found for Sprint ${parsedSprintId.sprintNumber}**\n\n` +
            `No ${parsedSprintId.isRemediation ? 'remediation ' : ''}audit summary found.\n\n` +
            'The security audit may not have been performed yet, or the summary has not been generated.\n\n' +
            '**Need an audit?**\n' +
            '  Contact your security team to schedule a sprint audit.'
        );
        return;
      }

      // Get the first matching document
      const auditDoc = searchResults.documents[0];

      // Parse severity breakdown from content
      const severityBreakdown = parseSeverityBreakdown(auditDoc.content || '');

      // Determine overall status
      let status = '\u2705 All CRITICAL and HIGH issues resolved';
      if (severityBreakdown.critical > 0) {
        status = '\ud83d\udea8 CRITICAL issues require immediate attention';
      } else if (severityBreakdown.high > 0) {
        status = '\u26a0\ufe0f HIGH priority issues pending';
      }

      // Format response
      const response =
        `\u2705 **Sprint ${parsedSprintId.sprintNumber} Security Audit Summary**\n\n` +
        (parsedSprintId.project ? `**Project:** ${parsedSprintId.project.charAt(0).toUpperCase() + parsedSprintId.project.slice(1)}\n` : '') +
        `**Sprint:** Sprint ${parsedSprintId.sprintNumber}\n` +
        (parsedSprintId.isRemediation ? '**Type:** Remediation Report\n' : '') +
        `**Audit Date:** ${auditDoc.modifiedTime ? new Date(auditDoc.modifiedTime).toLocaleDateString() : 'Unknown'}\n\n` +
        `\ud83d\udcc4 [View Audit Summary in Google Docs](${auditDoc.webViewLink})\n\n` +
        '**Severity Breakdown:**\n' +
        formatSeverityBreakdown(severityBreakdown) +
        '\n\n' +
        `**Status:** ${status}\n`;

      await interaction.editReply(response);

      auditLog.command(interaction.user.id, interaction.user.tag, 'audit-summary', [
        `sprint-id=${sprintIdInput}`,
        `persona=${userPersona}`,
        `documentId=${auditDoc.documentId}`,
        `severities=c${severityBreakdown.critical}/h${severityBreakdown.high}/m${severityBreakdown.medium}/l${severityBreakdown.low}`,
      ]);

      logger.info('Audit summary delivered', {
        userId: interaction.user.id,
        sprintNumber: parsedSprintId.sprintNumber,
        isRemediation: parsedSprintId.isRemediation,
        persona: userPersona,
        documentId: auditDoc.documentId,
        severityBreakdown,
      });
    } catch (error) {
      logger.error('Failed to search for audit summary', {
        userId: interaction.user.id,
        sprintId: sprintIdInput,
        error: error instanceof Error ? error.message : String(error),
      });

      await interaction.editReply(
        '\u274c **Failed to fetch audit summary**\n\n' +
          'An error occurred while searching for the audit summary. Please try again later.\n\n' +
          `*Error: ${error instanceof Error ? error.message : 'Unknown error'}*`
      );
    }
  } catch (error) {
    logger.error('Error in audit-summary command', {
      userId: interaction.user.id,
      error: error instanceof Error ? error.message : String(error),
    });

    if (interaction.deferred) {
      await interaction.editReply(
        `\u274c **Error:** ${error instanceof Error ? error.message : 'An unexpected error occurred'}`
      );
    } else {
      await interaction.reply({
        content: `\u274c **Error:** ${error instanceof Error ? error.message : 'An unexpected error occurred'}`,
        ephemeral: true,
      });
    }
  }
}

// =============================================================================
// Exports
// =============================================================================

export { parseSprintId, parseSeverityBreakdown, formatSeverityBreakdown };
