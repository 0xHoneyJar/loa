/**
 * Translate Slash Command Handler
 *
 * Sprint 3 - Task 3.2: /translate Command Handler
 *
 * Handles the Discord slash command for generating stakeholder summaries:
 * /translate <project> <@document> for <audience>
 *
 * Features:
 * - Document shorthand resolution (@prd, @sdd, @sprint, etc.)
 * - Project validation against known projects
 * - Integration with transformation pipeline
 * - Google Docs link response
 * - Permission checking via Discord roles
 * - Comprehensive error handling
 * - Audit logging
 */

import { ChatInputCommandInteraction } from 'discord.js';
import { logger, auditLog } from '../utils/logger';
import { requirePermission } from '../middleware/auth';
import documentResolver from '../services/document-resolver';
import transformationPipeline from '../services/transformation-pipeline';
import googleDocsStorage from '../services/google-docs-storage';
import contentSanitizer from '../services/content-sanitizer';
import secretScanner from '../services/secret-scanner';
import { PersonaType, DocumentType } from '../prompts/persona-prompts';

/**
 * Document types for transformation - extended from persona-prompts DocumentType
 * Used internally for more specific document classification
 */
type ExtendedDocumentType = 'prd' | 'sdd' | 'sprint' | 'audit' | 'reviewer' | 'general' | 'sprint-summary' | 'audit-report' | 'deployment' | 'other';

/**
 * Map extended document type to base DocumentType for transformation pipeline
 */
function toBaseDocumentType(extType: ExtendedDocumentType): DocumentType {
  switch (extType) {
    case 'prd':
    case 'sdd':
    case 'sprint':
    case 'audit':
    case 'reviewer':
    case 'general':
      return extType;
    case 'sprint-summary':
      return 'sprint';
    case 'audit-report':
      return 'audit';
    case 'deployment':
    case 'other':
      return 'general';
  }
}
import { SecurityException } from '../services/review-queue';
import { CircuitBreakerOpenError } from '../services/circuit-breaker';
import * as fs from 'fs';
import * as path from 'path';

// =============================================================================
// Types and Constants
// =============================================================================

/**
 * Known projects (validated against Google Drive folder structure)
 */
const KNOWN_PROJECTS = [
  'mibera',
  'fatbera',
  'interpol',
  'setforgetti',
  'set-and-forgetti',
  'onomancer',
];

/**
 * Document shorthand mappings
 * NOTE: Paths are relative to the 'docs' directory (not project root)
 * because DocumentResolver looks inside docs/ as an allowed base directory
 */
const DOCUMENT_SHORTHANDS: Record<string, string> = {
  '@prd': 'prd.md',
  '@sdd': 'sdd.md',
  '@sprint': 'sprint.md',
  '@reviewer': 'a2a/reviewer.md',
  '@audit': 'SECURITY-AUDIT-REPORT.md',
  '@deployment': 'a2a/deployment-report.md',
};

/**
 * Map audience to persona type
 */
const AUDIENCE_TO_PERSONA: Record<string, PersonaType> = {
  leadership: 'leadership',
  product: 'product',
  marketing: 'marketing',
  devrel: 'devrel',
};

/**
 * Map document shorthand to document type
 */
const SHORTHAND_TO_DOCTYPE: Record<string, ExtendedDocumentType> = {
  '@prd': 'prd',
  '@sdd': 'sdd',
  '@sprint': 'sprint',
  '@reviewer': 'reviewer',
  '@audit': 'audit',
  '@deployment': 'general',
};

// =============================================================================
// Helper Functions
// =============================================================================

/**
 * Resolve document reference to file path
 * Supports shorthands (@prd) and full paths (docs/prd.md)
 */
function resolveDocumentReference(docRef: string): {
  path: string;
  documentType: ExtendedDocumentType;
  isShorthand: boolean;
} | null {
  // Check if it's a shorthand
  const normalizedRef = docRef.toLowerCase().trim();

  if (DOCUMENT_SHORTHANDS[normalizedRef]) {
    return {
      path: DOCUMENT_SHORTHANDS[normalizedRef],
      documentType: SHORTHAND_TO_DOCTYPE[normalizedRef] || 'other',
      isShorthand: true,
    };
  }

  // Check if it starts with @ but has a path (e.g., @docs/a2a/engineer-feedback.md)
  if (normalizedRef.startsWith('@') && normalizedRef.includes('/')) {
    const pathWithoutAt = normalizedRef.substring(1);
    return {
      path: pathWithoutAt,
      documentType: inferDocumentType(pathWithoutAt),
      isShorthand: false,
    };
  }

  // Assume it's a direct path
  if (!normalizedRef.startsWith('@')) {
    return {
      path: normalizedRef,
      documentType: inferDocumentType(normalizedRef),
      isShorthand: false,
    };
  }

  return null;
}

/**
 * Infer document type from file path
 */
function inferDocumentType(filePath: string): ExtendedDocumentType {
  const lowerPath = filePath.toLowerCase();

  if (lowerPath.includes('prd')) return 'prd';
  if (lowerPath.includes('sdd')) return 'sdd';
  if (lowerPath.includes('sprint')) return 'sprint';
  if (lowerPath.includes('audit')) return 'audit';
  if (lowerPath.includes('deployment')) return 'general';
  if (lowerPath.includes('reviewer')) return 'reviewer';

  return 'general';
}

/**
 * Validate project name
 */
function isValidProject(project: string): boolean {
  return KNOWN_PROJECTS.includes(project.toLowerCase());
}

/**
 * Format project name for display
 */
function formatProjectName(project: string): string {
  // Special cases
  const specialNames: Record<string, string> = {
    mibera: 'MiBera',
    fatbera: 'FatBera',
    interpol: 'Interpol',
    setforgetti: 'Set & Forgetti',
    'set-and-forgetti': 'Set & Forgetti',
    onomancer: 'Onomancer',
  };

  return specialNames[project.toLowerCase()] || project.charAt(0).toUpperCase() + project.slice(1);
}

/**
 * Load folder configuration
 */
async function loadFolderConfig(): Promise<Record<string, string> | null> {
  try {
    const configPath = path.join(process.cwd(), 'config', 'folder-ids.json');
    if (fs.existsSync(configPath)) {
      return JSON.parse(fs.readFileSync(configPath, 'utf-8'));
    }
    return null;
  } catch (error) {
    logger.warn('Failed to load folder config', {
      error: error instanceof Error ? error.message : String(error),
    });
    return null;
  }
}

// =============================================================================
// Command Handler
// =============================================================================

/**
 * /translate <project> <document> for <audience>
 *
 * Generate stakeholder summary from technical document
 */
export async function handleTranslateSlashCommand(
  interaction: ChatInputCommandInteraction
): Promise<void> {
  const startTime = Date.now();

  try {
    // Check permission
    await requirePermission(interaction.user, interaction.guild, 'doc');

    // Extract parameters
    const project = interaction.options.getString('project', true);
    const documentRef = interaction.options.getString('document', true);
    const audience = interaction.options.getString('audience', true) as PersonaType;

    logger.info('Translate command received', {
      userId: interaction.user.id,
      userTag: interaction.user.tag,
      project,
      documentRef,
      audience,
    });

    // Defer reply (transformation may take up to 60 seconds)
    await interaction.deferReply();

    // Update with loading message
    await interaction.editReply(
      '\ud83d\udd04 **Generating summary...** This may take up to 60 seconds.\n\n' +
        `**Project:** ${formatProjectName(project)}\n` +
        `**Document:** ${documentRef}\n` +
        `**Audience:** ${audience.charAt(0).toUpperCase() + audience.slice(1)}`
    );

    // ==========================================================================
    // Step 1: Validate project name
    // ==========================================================================
    if (!isValidProject(project)) {
      const suggestedProjects = KNOWN_PROJECTS.map(p => `\`${p}\``).join(', ');
      await interaction.editReply(
        `\u274c **Invalid project name:** \`${project}\`\n\n` +
          '**Known projects:**\n' +
          `${suggestedProjects}\n\n` +
          '*If your project is not listed, contact your administrator to add it.*'
      );
      return;
    }

    // ==========================================================================
    // Step 2: Resolve document reference
    // ==========================================================================
    const resolvedDoc = resolveDocumentReference(documentRef);
    if (!resolvedDoc) {
      await interaction.editReply(
        `\u274c **Invalid document reference:** \`${documentRef}\`\n\n` +
          '**Available shorthands:**\n' +
          '  \u2022 `@prd` \u2192 docs/prd.md\n' +
          '  \u2022 `@sdd` \u2192 docs/sdd.md\n' +
          '  \u2022 `@sprint` \u2192 docs/sprint.md\n' +
          '  \u2022 `@reviewer` \u2192 docs/a2a/reviewer.md\n' +
          '  \u2022 `@audit` \u2192 Latest security audit report\n\n' +
          '**Full paths also accepted:**\n' +
          '  \u2022 `@docs/a2a/engineer-feedback.md`\n' +
          '  \u2022 `docs/deployment/runbook.md`'
      );
      return;
    }

    // ==========================================================================
    // Step 3: Read document content
    // ==========================================================================
    const docResolution = await documentResolver.resolveDocument(resolvedDoc.path);

    if (!docResolution.exists) {
      await interaction.editReply(
        `\u274c **Document not found:** \`${resolvedDoc.path}\`\n\n` +
          (docResolution.error ? `*Error: ${docResolution.error}*\n\n` : '') +
          '**Allowed directories:**\n' +
          documentResolver.getAllowedDirectories().map(d => `  \u2022 ${d}`).join('\n')
      );
      return;
    }

    let documentContent: string;
    try {
      documentContent = await documentResolver.readDocument(docResolution);
    } catch (error) {
      await interaction.editReply(
        `\u274c **Failed to read document:** \`${resolvedDoc.path}\`\n\n` +
          `*Error: ${error instanceof Error ? error.message : 'Unknown error'}*`
      );
      return;
    }

    // ==========================================================================
    // Step 4: Security checks (sanitization + secret scanning)
    // ==========================================================================
    const sanitizationResult = contentSanitizer.sanitizeContent(documentContent);
    const secretScanResult = secretScanner.scanForSecrets(sanitizationResult.sanitized);

    if (secretScanResult.criticalSecretsFound > 0) {
      logger.warn('Critical secrets detected in document', {
        userId: interaction.user.id,
        documentPath: resolvedDoc.path,
        criticalSecrets: secretScanResult.criticalSecretsFound,
      });

      await interaction.editReply(
        '\ud83d\udea8 **Security Alert: Critical secrets detected**\n\n' +
          `The document \`${resolvedDoc.path}\` contains ${secretScanResult.criticalSecretsFound} critical secret(s) that must be removed before translation.\n\n` +
          '**What to do:**\n' +
          '  1. Remove sensitive credentials from the document\n' +
          '  2. Use environment variables instead of hardcoded secrets\n' +
          '  3. Try the translation again\n\n' +
          '*This is a security feature to prevent credential leaks in stakeholder summaries.*'
      );
      return;
    }

    // Use redacted content
    const sanitizedContent = secretScanResult.redactedContent;

    // ==========================================================================
    // Step 5: Load folder configuration
    // ==========================================================================
    const folderConfig = await loadFolderConfig();
    if (!folderConfig) {
      await interaction.editReply(
        '\u26a0\ufe0f **Configuration not found**\n\n' +
          'Google Drive folder configuration is missing. Please contact your administrator.'
      );
      return;
    }

    const targetFolderId = folderConfig[audience];
    if (!targetFolderId) {
      await interaction.editReply(
        `\u26a0\ufe0f **Folder not configured for audience:** ${audience}\n\n` +
          'Please contact your administrator to configure the folder mapping.'
      );
      return;
    }

    // ==========================================================================
    // Step 6: Initialize services and transform
    // ==========================================================================
    await transformationPipeline.initialize();

    let transformResult;
    try {
      transformResult = await transformationPipeline.transformForPersona(
        {
          name: path.basename(resolvedDoc.path),
          content: sanitizedContent,
          path: resolvedDoc.path,
        },
        project,
        toBaseDocumentType(resolvedDoc.documentType),
        audience,
        {
          folderId: targetFolderId,
          requestedBy: interaction.user.id,
        }
      );
    } catch (error) {
      // Handle security exceptions
      if (error instanceof SecurityException) {
        logger.warn('Translation blocked by security review', {
          userId: interaction.user.id,
          error: error.message,
        });

        await interaction.editReply(
          '\ud83d\udea8 **Security Alert**\n\n' +
            'The generated translation was flagged for security review and has been blocked.\n\n' +
            `**Reason:** ${error.message}\n\n` +
            '**Next steps:**\n' +
            '  \u2022 A security reviewer will examine the flagged content\n' +
            '  \u2022 You will be notified when review is complete\n' +
            '  \u2022 If approved, the translation will be made available'
        );
        return;
      }

      // Handle circuit breaker errors
      if (error instanceof CircuitBreakerOpenError) {
        await interaction.editReply(
          '\u26a0\ufe0f **Translation Service Temporarily Unavailable**\n\n' +
            'The translation service is experiencing issues and has been temporarily disabled to prevent further failures.\n\n' +
            '**What to do:**\n' +
            '  \u2022 Wait 1-2 minutes and try again\n' +
            '  \u2022 Check service status if issue persists\n' +
            '  \u2022 Contact support if urgent'
        );
        return;
      }

      throw error;
    }

    // ==========================================================================
    // Step 7: Format and send response
    // ==========================================================================
    const durationMs = Date.now() - startTime;
    const durationSec = Math.round(durationMs / 1000);

    const response =
      `\u2705 **${audience.charAt(0).toUpperCase() + audience.slice(1)} Summary Generated**\n\n` +
      `**Document:** ${formatProjectName(project)} ${resolvedDoc.documentType.toUpperCase()}\n` +
      `**Audience:** ${audience.charAt(0).toUpperCase() + audience.slice(1)}\n` +
      `**Generated:** ${new Date().toLocaleString()}\n\n` +
      `\ud83d\udcc4 [View Summary in Google Docs](${transformResult.webViewLink})\n\n` +
      '**Metadata:**\n' +
      `  \u2022 Source: ${resolvedDoc.path}\n` +
      (sanitizationResult.flagged ? `  \u2022 \u26a0\ufe0f Content sanitization applied\n` : '') +
      (secretScanResult.totalSecretsFound > 0
        ? `  \u2022 \ud83d\udd12 ${secretScanResult.totalSecretsFound} secret(s) redacted\n`
        : '  \u2022 \u2705 Security scan passed\n') +
      `  \u2022 Generated in ${durationSec} seconds`;

    await interaction.editReply(response);

    // Audit log
    auditLog.command(interaction.user.id, interaction.user.tag, 'translate', [
      `project=${project}`,
      `document=${documentRef}`,
      `resolved=${resolvedDoc.path}`,
      `audience=${audience}`,
      `doc-id=${transformResult.documentId}`,
      `duration=${durationMs}ms`,
      `sanitized=${sanitizationResult.flagged}`,
      `secrets-redacted=${secretScanResult.totalSecretsFound}`,
    ]);

    logger.info('Translation completed successfully', {
      userId: interaction.user.id,
      project,
      audience,
      documentId: transformResult.documentId,
      durationMs,
    });
  } catch (error) {
    logger.error('Error in translate command', {
      userId: interaction.user.id,
      error: error instanceof Error ? error.message : String(error),
      stack: error instanceof Error ? error.stack : undefined,
    });

    const errorMessage = error instanceof Error ? error.message : 'An unexpected error occurred';

    if (interaction.deferred) {
      await interaction.editReply(
        `\u274c **Translation failed**\n\n${errorMessage}\n\n` +
          '*If this persists, please contact support.*'
      );
    } else {
      await interaction.reply({
        content: `\u274c **Error:** ${errorMessage}`,
        ephemeral: true,
      });
    }
  }
}

// =============================================================================
// Exports
// =============================================================================

export {
  resolveDocumentReference,
  isValidProject,
  formatProjectName,
  KNOWN_PROJECTS,
  DOCUMENT_SHORTHANDS,
};
