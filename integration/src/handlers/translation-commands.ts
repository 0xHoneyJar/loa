/**
 * DevRel Translation Command Handlers
 *
 * Handles Discord commands for DevRel translation feature:
 * - /translate <doc-paths> [format] [audience] - Generate translation from documents
 *
 * This implements CRITICAL-001 and CRITICAL-002 security controls.
 */

import { Message } from 'discord.js';
import { logger, auditLog } from '../utils/logger';
import { requirePermission } from '../middleware/auth';
import { handleError } from '../utils/errors';
import inputValidator from '../validators/input-validator';
import documentResolver from '../services/document-resolver';
import secureTranslationInvoker from '../services/translation-invoker-secure';
import { SecurityException } from '../services/review-queue';
import { validateParameterLength, validateDocumentNames, INPUT_LIMITS } from '../validators/document-size-validator';

/**
 * /translate - Generate secure translation from documents
 *
 * Usage:
 *   /translate docs/prd.md executive "COO, Head of BD"
 *   /translate docs/sprint.md,docs/sdd.md unified "Product team"
 *
 * Format options: executive, marketing, product, engineering, unified
 */
export async function handleTranslate(message: Message, args: string[]): Promise<void> {
  try {
    // Check permission
    await requirePermission(message.author, message.guild, 'translate');

    // Parse arguments
    if (args.length < 1) {
      await message.reply(
        '❌ **Usage:** `/translate <doc-paths> [format] [audience]`\n\n' +
        '**Examples:**\n' +
        '  • `/translate docs/prd.md executive "COO, Head of BD"`\n' +
        '  • `/translate docs/sprint.md unified "Product team"`\n' +
        '  • `/translate docs/sdd.md,docs/audit.md engineering "Dev team"`\n\n' +
        '**Formats:** executive, marketing, product, engineering, unified\n' +
        '**Default:** unified format for "all stakeholders"'
      );
      return;
    }

    // Extract arguments
    const docPathsArg = args[0] || '';
    const format = args[1] || 'unified';
    const audience = args.slice(2).join(' ') || 'all stakeholders';

    // HIGH-003: Validate parameter lengths (DoS prevention)
    const formatValidation = validateParameterLength('format', format);
    if (!formatValidation.valid) {
      await message.reply(
        `❌ Format parameter too long. Maximum ${INPUT_LIMITS.MAX_PARAMETER_LENGTH} characters allowed.\n\n` +
        `Your format: ${formatValidation.details?.currentValue} characters`
      );
      return;
    }

    const audienceValidation = validateParameterLength('audience', audience);
    if (!audienceValidation.valid) {
      await message.reply(
        `❌ Audience parameter too long. Maximum ${INPUT_LIMITS.MAX_PARAMETER_LENGTH} characters allowed.\n\n` +
        `Your audience: ${audienceValidation.details?.currentValue} characters`
      );
      return;
    }

    // HIGH-003: Validate document names count
    const docPaths = docPathsArg.split(',').map(p => p.trim());
    const docNamesValidation = validateDocumentNames(docPaths);
    if (!docNamesValidation.valid) {
      await message.reply(
        `❌ Too many document names specified. Maximum ${INPUT_LIMITS.MAX_DOCUMENT_NAMES} documents per command.\n\n` +
        `You specified: ${docNamesValidation.details?.currentValue} documents\n\n` +
        `Please specify at most ${INPUT_LIMITS.MAX_DOCUMENT_NAMES} documents.`
      );

      logger.warn('Too many documents requested', {
        userId: message.author.id,
        userTag: message.author.tag,
        documentCount: docPaths.length,
        maxAllowed: INPUT_LIMITS.MAX_DOCUMENT_NAMES
      });

      return;
    }

    logger.info('Translation requested', {
      user: message.author.tag,
      userId: message.author.id,
      docPaths: docPathsArg,
      format,
      audience
    });

    // STEP 1: Validate command arguments (CRITICAL-002)
    const commandValidation = inputValidator.validateCommandArgs('translate', args);
    if (!commandValidation.valid) {
      logger.warn('Invalid command arguments detected', {
        user: message.author.id,
        errors: commandValidation.errors
      });
      await message.reply(`❌ **Invalid command arguments:**\n${commandValidation.errors.map(e => `  • ${e}`).join('\n')}`);
      return;
    }

    // STEP 2: Validate document paths (already parsed above)

    const pathValidation = inputValidator.validateDocumentPaths(docPaths);
    if (!pathValidation.valid) {
      logger.warn('Invalid document paths detected', {
        user: message.author.id,
        paths: docPaths,
        errors: pathValidation.errors
      });
      auditLog.permissionDenied(message.author.id, message.author.tag, 'invalid_document_paths');
      await message.reply(
        `❌ **Invalid document paths:**\n${pathValidation.errors.map(e => `  • ${e}`).join('\n')}\n\n` +
        '**Allowed:**\n' +
        '  • Relative paths only (e.g., `docs/file.md`)\n' +
        '  • Extensions: .md, .gdoc\n' +
        '  • Max 10 documents per request'
      );
      return;
    }

    // STEP 3: Validate format
    const formatValidation = inputValidator.validateFormat(format);
    if (!formatValidation.valid) {
      await message.reply(
        `❌ **Invalid format:** \`${format}\`\n\n` +
        '**Available formats:** executive, marketing, product, engineering, unified'
      );
      return;
    }

    // STEP 4: Validate audience
    const audienceValidation = inputValidator.validateAudience(audience);
    if (!audienceValidation.valid) {
      await message.reply(
        `❌ **Invalid audience:**\n${audienceValidation.errors.map(e => `  • ${e}`).join('\n')}`
      );
      return;
    }

    // STEP 5: Resolve document paths
    await message.reply('🔄 Validating document paths...');

    const resolvedDocs = await documentResolver.resolveDocuments(pathValidation.resolvedPaths || []);

    // Check if all documents exist
    const missingDocs = resolvedDocs.filter(doc => !doc.exists);
    if (missingDocs.length > 0) {
      await message.reply(
        `❌ **Documents not found:**\n${missingDocs.map(d => `  • ${d.originalPath}: ${d.error}`).join('\n')}\n\n` +
        '**Allowed directories:**\n' +
        documentResolver.getAllowedDirectories().map(d => `  • ${d}`).join('\n')
      );
      return;
    }

    // STEP 6: Read documents
    await message.reply('📄 Reading documents...');

    let documents: Array<{ name: string; content: string }>;
    try {
      documents = await documentResolver.readDocuments(resolvedDocs);
    } catch (error) {
      logger.error('Failed to read documents', {
        user: message.author.id,
        error: error.message
      });
      await message.reply(`❌ **Failed to read documents:** ${error.message}`);
      return;
    }

    logger.info('Documents read successfully', {
      user: message.author.id,
      documentCount: documents.length,
      totalSize: documents.reduce((sum, d) => sum + d.content.length, 0)
    });

    // STEP 7: Generate secure translation (CRITICAL-001)
    await message.reply('🔒 Generating secure translation with security controls...');

    let translation;
    try {
      translation = await secureTranslationInvoker.generateSecureTranslation({
        documents: documents.map(doc => ({
          name: doc.name,
          content: doc.content,
          context: {}
        })),
        format: formatValidation.sanitized || format,
        audience: audienceValidation.sanitized || audience,
        requestedBy: message.author.id
      });
    } catch (error) {
      // Handle security exceptions (manual review required)
      if (error instanceof SecurityException) {
        logger.error('Translation blocked by security review', {
          user: message.author.id,
          error: error.message
        });
        await message.reply(
          '🚨 **SECURITY ALERT**\n\n' +
          'The generated translation was flagged for security review and has been blocked from distribution.\n\n' +
          '**Reason:**\n' +
          `${error.message}\n\n` +
          '**Next steps:**\n' +
          '  • A security reviewer will examine the flagged content\n' +
          '  • You will be notified when review is complete\n' +
          '  • If approved, the translation will be made available\n\n' +
          '**This is a security feature to prevent:**\n' +
          '  • Leaked credentials and API keys\n' +
          '  • Prompt injection attacks\n' +
          '  • Sensitive technical details in executive summaries'
        );
        return;
      }

      // Other errors
      logger.error('Translation generation failed', {
        user: message.author.id,
        error: error.message
      });
      await message.reply(`❌ **Translation generation failed:** ${error.message}`);
      return;
    }

    // STEP 8: Send translation to user
    const metadata = translation.metadata;

    // Security warnings
    let warnings = '';
    if (metadata.contentSanitized) {
      warnings += '⚠️ **Content sanitized:** Suspicious patterns removed from input documents\n';
      warnings += `  • ${metadata.removedPatterns.length} patterns detected and removed\n\n`;
    }
    if (!metadata.validationPassed) {
      warnings += '⚠️ **Output validation issues detected:** See metadata below\n\n';
    }

    // Split translation into Discord-friendly chunks
    const maxLength = 1900;
    const chunks = [];
    for (let i = 0; i < translation.content.length; i += maxLength) {
      chunks.push(translation.content.slice(i, i + maxLength));
    }

    // Send translation
    await message.reply(
      `✅ **Translation Generated**\n\n` +
      `**Format:** ${translation.format}\n` +
      `**Audience:** ${audienceValidation.sanitized}\n` +
      `**Documents:** ${documents.length}\n` +
      `**Generated:** ${new Date(metadata.generatedAt).toLocaleString()}\n\n` +
      warnings +
      '---\n\n' +
      `\`\`\`markdown\n${chunks[0]}\n\`\`\``
    );

    // Send remaining chunks
    if (message.channel && 'send' in message.channel) {
      for (let i = 1; i < chunks.length; i++) {
        await message.channel.send(
          `**Translation (continued - part ${i + 1}/${chunks.length})**\n\n` +
          `\`\`\`markdown\n${chunks[i]}\n\`\`\``
        );
      }
    }

    // Send metadata summary
    if (message.channel && 'send' in message.channel) {
      let metadataSummary = '**🔒 Security Metadata:**\n';
      metadataSummary += `  • Content sanitized: ${metadata.contentSanitized ? 'Yes' : 'No'}\n`;
      metadataSummary += `  • Validation passed: ${metadata.validationPassed ? 'Yes' : 'No'}\n`;
      metadataSummary += `  • Manual review required: ${metadata.requiresManualReview ? 'Yes' : 'No'}\n`;

      if (metadata.removedPatterns.length > 0) {
        metadataSummary += `\n**Removed patterns:**\n`;
        metadata.removedPatterns.slice(0, 5).forEach(pattern => {
          metadataSummary += `  • ${pattern}\n`;
        });
        if (metadata.removedPatterns.length > 5) {
          metadataSummary += `  ... and ${metadata.removedPatterns.length - 5} more\n`;
        }
      }

      if (metadata.validationIssues.length > 0) {
        metadataSummary += `\n**Validation issues:**\n`;
        metadata.validationIssues.slice(0, 3).forEach(issue => {
          metadataSummary += `  • [${issue.severity}] ${issue.description}\n`;
        });
        if (metadata.validationIssues.length > 3) {
          metadataSummary += `  ... and ${metadata.validationIssues.length - 3} more\n`;
        }
      }

      await message.channel.send(metadataSummary);
    }

    logger.info('Translation delivered successfully', {
      user: message.author.tag,
      userId: message.author.id,
      format: translation.format,
      documentCount: documents.length,
      contentLength: translation.content.length,
      sanitized: metadata.contentSanitized,
      validationPassed: metadata.validationPassed
    });

    auditLog.command(message.author.id, message.author.tag, 'translate', {
      documents: docPaths,
      format: translation.format,
      audience: audienceValidation.sanitized,
      sanitized: metadata.contentSanitized,
      validationPassed: metadata.validationPassed
    });

  } catch (error) {
    logger.error('Error in translate command', {
      user: message.author.id,
      error: error.message,
      stack: error.stack
    });
    const errorMessage = handleError(error, message.author.id, 'translate');
    await message.reply(errorMessage);
  }
}

/**
 * /translate-help - Show detailed help for translation command
 */
export async function handleTranslateHelp(message: Message): Promise<void> {
  const response = `
📚 **DevRel Translation Command**

Generate stakeholder-appropriate summaries from technical documentation with built-in security controls.

**Usage:**
  \`/translate <doc-paths> [format] [audience]\`

**Arguments:**
  • **doc-paths** (required): Comma-separated list of document paths
    - Examples: \`docs/prd.md\` or \`docs/sprint.md,docs/sdd.md\`
    - Allowed extensions: .md, .gdoc
    - Max 10 documents per request

  • **format** (optional): Output format
    - Options: executive, marketing, product, engineering, unified
    - Default: unified

  • **audience** (optional): Target audience description
    - Examples: "COO, Head of BD", "Marketing team", "Engineers"
    - Default: "all stakeholders"

**Examples:**
  \`/translate docs/prd.md executive "COO, Head of BD"\`
  → Executive summary for C-suite

  \`/translate docs/sprint.md unified "Product team"\`
  → Unified summary for product managers

  \`/translate docs/sdd.md,docs/audit.md engineering "Dev team"\`
  → Technical deep-dive from multiple docs

**Security Features:**
  ✅ Prompt injection defenses
  ✅ Secret detection and blocking
  ✅ Manual review for suspicious content
  ✅ Path traversal protection
  ✅ Input validation and sanitization

**Format Descriptions:**
  • **executive** - Business-focused, low technical detail (1 page)
  • **marketing** - Customer-friendly, feature-focused (1 page)
  • **product** - User-focused, medium technical depth (2 pages)
  • **engineering** - Technical deep-dive, architecture details (3 pages)
  • **unified** - Balanced for mixed audiences (2 pages)

**Need help?** Contact a team admin or check the DevRel integration playbook.
  `.trim();

  await message.reply(response);
}
