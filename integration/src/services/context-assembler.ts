/**
 * Context Assembler
 *
 * Implements HIGH-011: Context Assembly Access Control
 *
 * Assembles document context with security controls:
 * - Parses YAML frontmatter for sensitivity levels and relationships
 * - Enforces sensitivity-based access control (public < internal < confidential < restricted)
 * - Validates that context documents have same or lower sensitivity than primary document
 * - Only includes explicitly defined relationships (no fuzzy search)
 * - Prevents information leakage through context inclusion
 * - Provides comprehensive audit logging
 *
 * See docs/DOCUMENT-FRONTMATTER.md for schema specification.
 */

import * as yaml from 'yaml';
import documentResolver, { DocumentResolver } from './document-resolver';
import { logger, auditLog } from '../utils/logger';

/**
 * Sensitivity levels in ascending order
 */
export enum SensitivityLevel {
  PUBLIC = 'public',
  INTERNAL = 'internal',
  CONFIDENTIAL = 'confidential',
  RESTRICTED = 'restricted',
}

/**
 * Document frontmatter schema
 */
export interface DocumentFrontmatter {
  // Required fields
  sensitivity: SensitivityLevel;

  // Optional fields
  title?: string;
  description?: string;
  version?: string;
  created?: string;
  updated?: string;
  owner?: string;
  department?: string;
  tags?: string[];

  // Relationships
  context_documents?: string[];

  // Access control
  allowed_audiences?: string[];
  requires_approval?: boolean;

  // Compliance
  retention_days?: number;
  pii_present?: boolean;
}

/**
 * Parsed document with frontmatter and content
 */
export interface ParsedDocument {
  path: string;
  frontmatter: DocumentFrontmatter;
  body: string;
  rawContent: string;
}

/**
 * Context assembly result
 */
export interface ContextAssemblyResult {
  primaryDocument: ParsedDocument;
  contextDocuments: ParsedDocument[];
  warnings: string[];
  rejectedContexts: Array<{
    path: string;
    reason: string;
  }>;
}

/**
 * Context assembly options
 */
export interface ContextAssemblyOptions {
  /**
   * Maximum number of context documents to include (default: 10)
   */
  maxContextDocuments?: number;

  /**
   * Whether to fail on validation errors (default: false, warnings only)
   */
  failOnValidationError?: boolean;

  /**
   * Whether to include circular references (default: false)
   */
  allowCircularReferences?: boolean;

  /**
   * User/role requesting the context (for audit logging)
   */
  requestedBy?: string;
}

/**
 * Context assembler class
 */
export class ContextAssembler {
  private readonly DEFAULT_SENSITIVITY = SensitivityLevel.INTERNAL;
  private readonly SENSITIVITY_HIERARCHY: Record<SensitivityLevel, number> = {
    [SensitivityLevel.PUBLIC]: 0,
    [SensitivityLevel.INTERNAL]: 1,
    [SensitivityLevel.CONFIDENTIAL]: 2,
    [SensitivityLevel.RESTRICTED]: 3,
  };

  constructor(private resolver: DocumentResolver = documentResolver) {}

  /**
   * Assemble context for a primary document
   */
  async assembleContext(
    primaryDocPath: string,
    options: ContextAssemblyOptions = {}
  ): Promise<ContextAssemblyResult> {
    const {
      maxContextDocuments = 10,
      failOnValidationError = false,
      allowCircularReferences = false,
      requestedBy = 'unknown',
    } = options;

    logger.info('Assembling context for document', {
      primaryDocPath,
      maxContextDocuments,
      requestedBy,
    });

    const warnings: string[] = [];
    const rejectedContexts: Array<{ path: string; reason: string }> = [];

    // STEP 1: Parse primary document
    const primaryDoc = await this.parseDocument(primaryDocPath);

    if (!primaryDoc) {
      const error = `Primary document not found or invalid: ${primaryDocPath}`;
      logger.error(error);
      throw new Error(error);
    }

    // STEP 2: Validate primary document frontmatter
    const primaryValidation = this.validateFrontmatter(primaryDoc.frontmatter, primaryDocPath);
    if (!primaryValidation.valid) {
      const error = `Primary document has invalid frontmatter: ${primaryValidation.errors.join(', ')}`;
      logger.error(error, { path: primaryDocPath });

      if (failOnValidationError) {
        throw new Error(error);
      }

      warnings.push(error);
    }

    // STEP 3: Get context document paths from frontmatter
    const contextPaths = primaryDoc.frontmatter.context_documents || [];

    if (contextPaths.length === 0) {
      logger.info('No context documents specified', { primaryDocPath });

      auditLog.contextAssembly(requestedBy, primaryDocPath, {
        contextCount: 0,
        sensitivity: primaryDoc.frontmatter.sensitivity,
      });

      return {
        primaryDocument: primaryDoc,
        contextDocuments: [],
        warnings,
        rejectedContexts,
      };
    }

    // STEP 4: Limit number of context documents
    const limitedContextPaths = contextPaths.slice(0, maxContextDocuments);

    if (contextPaths.length > maxContextDocuments) {
      const warning = `Context documents limited to ${maxContextDocuments} (${contextPaths.length} specified)`;
      logger.warn(warning, { primaryDocPath });
      warnings.push(warning);
    }

    // STEP 5: Parse and validate context documents
    const contextDocuments: ParsedDocument[] = [];
    const processedPaths = new Set<string>([primaryDocPath]); // Track to detect circular refs

    for (const contextPath of limitedContextPaths) {
      // Check for circular reference
      if (processedPaths.has(contextPath)) {
        if (!allowCircularReferences) {
          const warning = `Circular reference detected: ${contextPath}`;
          logger.warn(warning, { primaryDocPath });
          warnings.push(warning);
          rejectedContexts.push({
            path: contextPath,
            reason: 'Circular reference',
          });
          continue;
        }
      }

      // Parse context document
      const contextDoc = await this.parseDocument(contextPath);

      if (!contextDoc) {
        const warning = `Context document not found: ${contextPath}`;
        logger.warn(warning, { primaryDocPath });
        warnings.push(warning);
        rejectedContexts.push({
          path: contextPath,
          reason: 'Document not found or invalid',
        });
        continue;
      }

      // Validate context document frontmatter
      const contextValidation = this.validateFrontmatter(contextDoc.frontmatter, contextPath);
      if (!contextValidation.valid) {
        const warning = `Context document has invalid frontmatter: ${contextPath} - ${contextValidation.errors.join(', ')}`;
        logger.warn(warning, { primaryDocPath });
        warnings.push(warning);

        if (failOnValidationError) {
          rejectedContexts.push({
            path: contextPath,
            reason: `Invalid frontmatter: ${contextValidation.errors.join(', ')}`,
          });
          continue;
        }
      }

      // HIGH-011: Validate sensitivity hierarchy
      const canAccess = this.canAccessContext(
        primaryDoc.frontmatter.sensitivity,
        contextDoc.frontmatter.sensitivity
      );

      if (!canAccess) {
        const reason = `Sensitivity violation: ${primaryDoc.frontmatter.sensitivity} document cannot access ${contextDoc.frontmatter.sensitivity} context`;
        logger.error('HIGH-011: Context access denied', {
          primaryDoc: primaryDocPath,
          primarySensitivity: primaryDoc.frontmatter.sensitivity,
          contextDoc: contextPath,
          contextSensitivity: contextDoc.frontmatter.sensitivity,
          requestedBy,
        });

        auditLog.permissionDenied(requestedBy, contextPath, reason);

        warnings.push(`⚠️ SECURITY: ${reason} for ${contextPath}`);
        rejectedContexts.push({
          path: contextPath,
          reason,
        });
        continue;
      }

      // Valid context document
      contextDocuments.push(contextDoc);
      processedPaths.add(contextPath);

      logger.debug('Context document included', {
        primaryDoc: primaryDocPath,
        contextDoc: contextPath,
        contextSensitivity: contextDoc.frontmatter.sensitivity,
      });
    }

    // STEP 6: Audit log the context assembly
    auditLog.contextAssembly(requestedBy, primaryDocPath, {
      contextCount: contextDocuments.length,
      requestedCount: contextPaths.length,
      rejectedCount: rejectedContexts.length,
      sensitivity: primaryDoc.frontmatter.sensitivity,
      contextPaths: contextDocuments.map(d => d.path),
      rejectedPaths: rejectedContexts.map(r => r.path),
    });

    logger.info('Context assembly complete', {
      primaryDoc: primaryDocPath,
      contextCount: contextDocuments.length,
      rejectedCount: rejectedContexts.length,
      warningCount: warnings.length,
    });

    return {
      primaryDocument: primaryDoc,
      contextDocuments,
      warnings,
      rejectedContexts,
    };
  }

  /**
   * Parse a document and extract frontmatter
   */
  private async parseDocument(relativePath: string): Promise<ParsedDocument | null> {
    try {
      // Resolve document path
      const resolved = await this.resolver.resolveDocument(relativePath);

      if (!resolved.exists) {
        logger.warn('Document does not exist', { path: relativePath, error: resolved.error });
        return null;
      }

      // Read document content
      const content = await this.resolver.readDocument(resolved);

      // Parse frontmatter
      const { frontmatter, body } = this.parseFrontmatter(content);

      // Apply defaults if frontmatter is missing or incomplete
      const completeFrontmatter: DocumentFrontmatter = {
        sensitivity: frontmatter.sensitivity || this.DEFAULT_SENSITIVITY,
        ...frontmatter,
      };

      return {
        path: relativePath,
        frontmatter: completeFrontmatter,
        body,
        rawContent: content,
      };
    } catch (error) {
      logger.error('Failed to parse document', {
        path: relativePath,
        error: error instanceof Error ? error.message : String(error),
      });
      return null;
    }
  }

  /**
   * Parse YAML frontmatter from document content
   */
  private parseFrontmatter(content: string): { frontmatter: Partial<DocumentFrontmatter>; body: string } {
    // Match YAML frontmatter (--- ... ---)
    const frontmatterRegex = /^---\s*\n([\s\S]*?)\n---\s*\n/;
    const match = content.match(frontmatterRegex);

    if (!match) {
      // No frontmatter found
      return { frontmatter: {}, body: content };
    }

    try {
      const frontmatterText = match[1]!;
      const body = content.slice(match[0]!.length);
      const frontmatter = yaml.parse(frontmatterText) || {};

      return { frontmatter, body };
    } catch (error) {
      logger.error('Failed to parse YAML frontmatter', {
        error: error instanceof Error ? error.message : String(error),
      });
      return { frontmatter: {}, body: content };
    }
  }

  /**
   * Validate frontmatter schema
   */
  private validateFrontmatter(
    frontmatter: DocumentFrontmatter,
    _path: string
  ): { valid: boolean; errors: string[] } {
    const errors: string[] = [];

    // Validate required field: sensitivity
    if (!frontmatter.sensitivity) {
      errors.push('Missing required field: sensitivity');
    } else {
      // Validate sensitivity value
      const validLevels = Object.values(SensitivityLevel);
      if (!validLevels.includes(frontmatter.sensitivity)) {
        errors.push(
          `Invalid sensitivity level: ${frontmatter.sensitivity}. Must be one of: ${validLevels.join(', ')}`
        );
      }
    }

    // Validate optional fields
    if (frontmatter.context_documents && !Array.isArray(frontmatter.context_documents)) {
      errors.push('context_documents must be an array');
    }

    if (frontmatter.tags && !Array.isArray(frontmatter.tags)) {
      errors.push('tags must be an array');
    }

    if (frontmatter.allowed_audiences && !Array.isArray(frontmatter.allowed_audiences)) {
      errors.push('allowed_audiences must be an array');
    }

    if (frontmatter.requires_approval !== undefined && typeof frontmatter.requires_approval !== 'boolean') {
      errors.push('requires_approval must be a boolean');
    }

    if (frontmatter.retention_days !== undefined) {
      if (typeof frontmatter.retention_days !== 'number' || frontmatter.retention_days < 0) {
        errors.push('retention_days must be a positive number');
      }
    }

    if (frontmatter.pii_present !== undefined && typeof frontmatter.pii_present !== 'boolean') {
      errors.push('pii_present must be a boolean');
    }

    return {
      valid: errors.length === 0,
      errors,
    };
  }

  /**
   * Check if a document can access another document based on sensitivity hierarchy
   *
   * HIGH-011: Sensitivity-based access control
   *
   * Rules:
   * - A document can only reference context documents with SAME or LOWER sensitivity
   * - public (0) < internal (1) < confidential (2) < restricted (3)
   *
   * Examples:
   * - restricted → can access: restricted, confidential, internal, public
   * - confidential → can access: confidential, internal, public
   * - internal → can access: internal, public
   * - public → can access: public only
   */
  canAccessContext(primarySensitivity: SensitivityLevel, contextSensitivity: SensitivityLevel): boolean {
    const primaryLevel = this.SENSITIVITY_HIERARCHY[primarySensitivity];
    const contextLevel = this.SENSITIVITY_HIERARCHY[contextSensitivity];

    // Primary must have >= level to access context
    return primaryLevel >= contextLevel;
  }

  /**
   * Get sensitivity level as number (for comparison)
   */
  getSensitivityLevel(sensitivity: SensitivityLevel): number {
    return this.SENSITIVITY_HIERARCHY[sensitivity];
  }

  /**
   * Check if one sensitivity level is higher than another
   */
  isHigherSensitivity(level1: SensitivityLevel, level2: SensitivityLevel): boolean {
    return this.SENSITIVITY_HIERARCHY[level1] > this.SENSITIVITY_HIERARCHY[level2];
  }
}

/**
 * Export singleton instance
 */
export default new ContextAssembler();
