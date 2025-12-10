/**
 * Google Docs Monitor
 *
 * Monitors Google Drive folders for document changes and fetches content.
 * Includes runtime folder validation to prevent scanning unauthorized folders.
 *
 * This implements CRITICAL-004 remediation (runtime validation).
 */

import { google, drive_v3, docs_v1 } from 'googleapis';
import { logger } from '../utils/logger';
import { configLoader } from '../utils/config-loader';
import { drivePermissionValidator } from './drive-permission-validator';
import { SecurityException } from '../utils/errors';
import { secretScanner, ScanResult } from './secret-scanner';
import { validateDocumentSize, ValidationError, DOCUMENT_LIMITS } from '../validators/document-size-validator';

export interface Document {
  id: string;
  name: string;
  content: string;
  folderPath: string;
  modifiedTime: Date;
  createdTime: Date;
  webViewLink: string;
  type: 'google-doc' | 'markdown' | 'text';
  secretsDetected?: boolean;
  secretsRedacted?: number;
  scanResult?: ScanResult;
}

export interface ScanOptions {
  windowDays?: number;
  includeArchived?: boolean;
  maxDocuments?: number;
}

/**
 * Google Docs Monitor
 *
 * Security Controls:
 * 1. Validates Drive permissions before every scan
 * 2. Double-checks each folder is whitelisted before scanning
 * 3. Blocks scanning of non-whitelisted folders
 * 4. Enforces read-only access
 * 5. Logs all folder access for audit trail
 */
export class GoogleDocsMonitor {
  private auth: any;
  private drive: drive_v3.Drive | null = null;
  private docs: docs_v1.Docs | null = null;

  constructor(auth?: any) {
    this.auth = auth;
  }

  /**
   * Initialize Google APIs
   */
  async initialize(auth: any): Promise<void> {
    this.auth = auth;
    this.drive = google.drive({ version: 'v3', auth: this.auth });
    this.docs = google.docs({ version: 'v1', auth: this.auth });

    // Initialize permission validator
    await drivePermissionValidator.initialize(this.auth);

    logger.info('GoogleDocsMonitor initialized');
  }

  /**
   * Scan monitored folders for changed documents
   *
   * CRITICAL-004: Validates permissions BEFORE scanning
   */
  async scanForChanges(options: ScanOptions = {}): Promise<Document[]> {
    if (!this.drive || !this.docs) {
      throw new Error('Google APIs not initialized. Call initialize() first.');
    }

    const {
      windowDays = 7,
      includeArchived = false,
      maxDocuments = 100
    } = options;

    logger.info(`Scanning for documents changed in last ${windowDays} days...`);

    try {
      // STEP 1: Validate permissions BEFORE scanning (CRITICAL-004)
      const validation = await drivePermissionValidator.validatePermissions();

      if (!validation.valid) {
        throw new SecurityException(
          `Drive permission validation failed: ${validation.errors.join(', ')}`
        );
      }

      if (validation.warnings && validation.warnings.length > 0) {
        logger.warn('Permission validation warnings:', validation.warnings);
      }

      // STEP 2: Get monitored folders from config
      const config = configLoader.getConfig();
      const monitoredFolders = config.google_docs?.monitored_folders || [];

      if (monitoredFolders.length === 0) {
        logger.warn('No monitored folders configured');
        return [];
      }

      logger.info(`Monitoring ${monitoredFolders.length} folders: ${monitoredFolders.join(', ')}`);

      // STEP 3: Calculate cutoff date
      const cutoffDate = new Date();
      cutoffDate.setDate(cutoffDate.getDate() - windowDays);

      // STEP 4: Scan each folder
      const documents: Document[] = [];

      for (const folderPath of monitoredFolders) {
        // STEP 5: Double-check folder is whitelisted (CRITICAL-004)
        if (!this.isFolderWhitelisted(folderPath)) {
          logger.error(`Attempted to scan non-whitelisted folder: ${folderPath}`);
          throw new SecurityException(
            `Folder not whitelisted: ${folderPath}. This may indicate a configuration error or attack.`
          );
        }

        logger.info(`Scanning folder: ${folderPath}`);

        // STEP 6: Scan folder for documents
        const folderDocs = await this.scanFolder(folderPath, cutoffDate, {
          includeArchived,
          maxDocuments
        });

        documents.push(...folderDocs);

        logger.info(`Found ${folderDocs.length} documents in ${folderPath}`);

        // Enforce max documents limit
        if (documents.length >= maxDocuments) {
          logger.warn(`Reached maximum document limit: ${maxDocuments}`);
          break;
        }
      }

      logger.info(`✅ Scan complete: ${documents.length} documents found`);

      // HIGH-003: Validate digest size limits (DoS prevention)
      const { validateDigest } = await import('../validators/document-size-validator');
      const digestValidation = validateDigest(documents);

      if (!digestValidation.valid) {
        logger.warn(`Digest validation failed - too many documents or content too large`, {
          error: digestValidation.error,
          details: digestValidation.details,
          documentCount: documents.length
        });

        // If we have too many documents, prioritize by recency
        if (digestValidation.details?.metric === 'documents') {
          const { prioritizeDocumentsByRecency, DIGEST_LIMITS } = await import('../validators/document-size-validator');
          const prioritized = prioritizeDocumentsByRecency(
            documents,
            (doc) => doc.modifiedTime
          );

          logger.info(`Prioritized ${prioritized.length} most recent documents (limit: ${DIGEST_LIMITS.MAX_DOCUMENTS})`);
          return prioritized;
        }

        // For total character limit, return as many as possible until we hit the limit
        if (digestValidation.details?.metric === 'total_characters') {
          const { DIGEST_LIMITS } = await import('../validators/document-size-validator');
          let totalChars = 0;
          const accepted: Document[] = [];

          // Sort by recency first
          const sorted = [...documents].sort((a, b) =>
            b.modifiedTime.getTime() - a.modifiedTime.getTime()
          );

          for (const doc of sorted) {
            if (totalChars + doc.content.length <= DIGEST_LIMITS.MAX_TOTAL_CHARACTERS) {
              accepted.push(doc);
              totalChars += doc.content.length;
            } else {
              logger.info(`Skipping document ${doc.name} - would exceed total character limit`);
              break;
            }
          }

          logger.info(`Accepted ${accepted.length}/${documents.length} documents within character limit`);
          return accepted;
        }
      }

      return documents;

    } catch (error) {
      if (error instanceof SecurityException) {
        // Re-throw security exceptions
        throw error;
      }

      logger.error('Failed to scan for changes', { error: error.message, stack: error.stack });
      throw new Error(`Failed to scan for changes: ${error.message}`);
    }
  }

  /**
   * Scan a specific folder for documents
   */
  private async scanFolder(
    folderPath: string,
    cutoffDate: Date,
    options: { includeArchived?: boolean; maxDocuments?: number }
  ): Promise<Document[]> {
    if (!this.drive || !this.docs) {
      throw new Error('Google APIs not initialized');
    }

    try {
      // Find folder by path
      const folderId = await this.resolveFolderPath(folderPath);

      if (!folderId) {
        logger.warn(`Folder not found: ${folderPath}`);
        return [];
      }

      // Build query
      const query = [
        `'${folderId}' in parents`,
        `modifiedTime >= '${cutoffDate.toISOString()}'`,
        `(mimeType='application/vnd.google-apps.document' or mimeType='text/markdown' or mimeType='text/plain')`
      ];

      if (!options.includeArchived) {
        query.push('trashed=false');
      }

      // List files
      const response = await this.drive.files.list({
        q: query.join(' and '),
        fields: 'nextPageToken, files(id, name, mimeType, modifiedTime, createdTime, webViewLink)',
        pageSize: options.maxDocuments || 100,
        orderBy: 'modifiedTime desc'
      });

      const files = response.data.files || [];

      logger.info(`Found ${files.length} files in folder: ${folderPath}`);

      // Fetch document content
      const documents: Document[] = [];

      for (const file of files) {
        try {
          let content = await this.fetchDocumentContent(file);

          // HIGH-003: Validate document size BEFORE processing (DoS prevention)
          const validationResult = validateDocumentSize({
            id: file.id!,
            name: file.name!,
            content,
            pageCount: undefined, // Page count not available for Google Docs
          });

          if (!validationResult.valid) {
            logger.warn(`Document rejected due to size limits: ${file.name}`, {
              error: validationResult.error,
              details: validationResult.details
            });

            // Skip this document - don't process oversized documents
            continue;
          }

          // CRITICAL-005: Scan for secrets BEFORE processing
          const scanResult = secretScanner.scanForSecrets(content, {
            skipFalsePositives: true,
            contextLength: 100
          });

          let secretsDetected = false;
          let secretsRedacted = 0;

          if (scanResult.hasSecrets) {
            secretsDetected = true;
            secretsRedacted = scanResult.totalSecretsFound;

            logger.error(`🚨 Secrets detected in document: ${file.name}`, {
              docId: file.id,
              docName: file.name,
              secretCount: scanResult.totalSecretsFound,
              criticalSecrets: scanResult.criticalSecretsFound,
              secretTypes: scanResult.secrets.map(s => s.type).join(', ')
            });

            // Alert security team immediately
            await this.alertSecurityTeamAboutSecrets({
              documentId: file.id!,
              documentName: file.name!,
              webViewLink: file.webViewLink!,
              folderPath,
              scanResult
            });

            // Redact secrets automatically
            content = scanResult.redactedContent;

            logger.info(`✅ Secrets redacted from document: ${file.name}`);
          }

          documents.push({
            id: file.id!,
            name: file.name!,
            content,
            folderPath,
            modifiedTime: new Date(file.modifiedTime!),
            createdTime: new Date(file.createdTime!),
            webViewLink: file.webViewLink!,
            type: this.getDocumentType(file.mimeType!),
            secretsDetected,
            secretsRedacted,
            scanResult: secretsDetected ? scanResult : undefined
          });

        } catch (error) {
          logger.error(`Failed to fetch document: ${file.name}`, { error: error.message });
          // Continue with next document
        }
      }

      return documents;

    } catch (error) {
      logger.error(`Failed to scan folder: ${folderPath}`, { error: error.message });
      return [];
    }
  }

  /**
   * Fetch document content
   */
  private async fetchDocumentContent(file: drive_v3.Schema$File): Promise<string> {
    if (!this.drive || !this.docs) {
      throw new Error('Google APIs not initialized');
    }

    const mimeType = file.mimeType!;

    try {
      if (mimeType === 'application/vnd.google-apps.document') {
        // Google Doc - use Docs API
        const response = await this.docs.documents.get({
          documentId: file.id!
        });

        return this.extractTextFromGoogleDoc(response.data);

      } else if (mimeType === 'text/markdown' || mimeType === 'text/plain') {
        // Markdown or plain text - use Drive export
        const response = await this.drive.files.export({
          fileId: file.id!,
          mimeType: 'text/plain'
        }, { responseType: 'text' });

        return response.data as string;

      } else {
        logger.warn(`Unsupported mime type: ${mimeType}`);
        return '';
      }

    } catch (error) {
      logger.error(`Failed to fetch content for ${file.name}`, { error: error.message });
      throw error;
    }
  }

  /**
   * Extract plain text from Google Doc
   */
  private extractTextFromGoogleDoc(doc: docs_v1.Schema$Document): string {
    if (!doc.body || !doc.body.content) {
      return '';
    }

    const textParts: string[] = [];

    for (const element of doc.body.content) {
      if (element.paragraph && element.paragraph.elements) {
        for (const el of element.paragraph.elements) {
          if (el.textRun && el.textRun.content) {
            textParts.push(el.textRun.content);
          }
        }
      }
    }

    return textParts.join('');
  }

  /**
   * Resolve folder path to folder ID
   */
  private async resolveFolderPath(folderPath: string): Promise<string | null> {
    if (!this.drive) {
      throw new Error('Drive API not initialized');
    }

    try {
      // Split path into components
      const components = folderPath.split('/').filter(c => c.length > 0);

      if (components.length === 0) {
        return null;
      }

      // Start with root folder
      let currentFolderId: string | null = null;

      for (const component of components) {
        // Search for folder with this name
        const query = [
          `name='${component}'`,
          `mimeType='application/vnd.google-apps.folder'`,
          `trashed=false`
        ];

        if (currentFolderId) {
          query.push(`'${currentFolderId}' in parents`);
        }

        const response = await this.drive.files.list({
          q: query.join(' and '),
          fields: 'files(id, name)',
          pageSize: 1
        });

        if (!response.data.files || response.data.files.length === 0) {
          logger.warn(`Folder not found: ${component} in path ${folderPath}`);
          return null;
        }

        currentFolderId = response.data.files[0].id!;
      }

      return currentFolderId;

    } catch (error) {
      logger.error(`Failed to resolve folder path: ${folderPath}`, { error: error.message });
      return null;
    }
  }

  /**
   * Check if folder is whitelisted (CRITICAL-004)
   */
  private isFolderWhitelisted(folderPath: string): boolean {
    return drivePermissionValidator.isFolderWhitelisted(folderPath);
  }

  /**
   * Get document type from mime type
   */
  private getDocumentType(mimeType: string): 'google-doc' | 'markdown' | 'text' {
    if (mimeType === 'application/vnd.google-apps.document') {
      return 'google-doc';
    } else if (mimeType === 'text/markdown') {
      return 'markdown';
    } else {
      return 'text';
    }
  }

  /**
   * Alert security team about secrets detected in document (CRITICAL-005)
   */
  private async alertSecurityTeamAboutSecrets(alert: {
    documentId: string;
    documentName: string;
    webViewLink: string;
    folderPath: string;
    scanResult: ScanResult;
  }): Promise<void> {
    const message = `
🚨 SECURITY ALERT: Secrets Detected in Google Doc

Document: ${alert.documentName}
Folder: ${alert.folderPath}
Document ID: ${alert.documentId}
Link: ${alert.webViewLink}

Secrets Found: ${alert.scanResult.totalSecretsFound}
Critical Secrets: ${alert.scanResult.criticalSecretsFound}

Secret Types:
${alert.scanResult.secrets.map(s => `  • ${s.type} (${s.severity})`).join('\n')}

ACTION TAKEN:
✅ Secrets automatically redacted from content
✅ Document flagged for security review
⚠️  Original document still contains secrets!

NEXT STEPS:
1. Review the original document in Google Drive
2. Remove secrets from the document
3. Rotate any exposed credentials as a precaution
4. Educate document author on secret management
5. Review other documents in same folder

Timestamp: ${new Date().toISOString()}
    `;

    // Console alert
    console.error('\n' + '='.repeat(80));
    console.error('🚨 SECRETS DETECTED IN DOCUMENT');
    console.error('='.repeat(80));
    console.error(message);
    console.error('='.repeat(80) + '\n');

    // Write to security events log
    logger.security({
      eventType: 'SECRET_DETECTED_IN_DOCUMENT',
      severity: 'CRITICAL',
      documentId: alert.documentId,
      documentName: alert.documentName,
      folderPath: alert.folderPath,
      webViewLink: alert.webViewLink,
      totalSecrets: alert.scanResult.totalSecretsFound,
      criticalSecrets: alert.scanResult.criticalSecretsFound,
      secretTypes: alert.scanResult.secrets.map(s => s.type),
      details: message,
      timestamp: new Date().toISOString()
    });

    // TODO: Integrate with alerting systems
    // - Discord webhook to #security-alerts
    // - Slack webhook
    // - Email (SendGrid, AWS SES)
    // - Linear ticket creation
    // - PagerDuty for critical secrets
  }

  /**
   * Get monitoring statistics
   */
  getStatistics(): {
    initialized: boolean;
    monitoredFolders: number;
  } {
    const config = configLoader.getConfig();
    return {
      initialized: this.drive !== null && this.docs !== null,
      monitoredFolders: config.google_docs?.monitored_folders?.length || 0
    };
  }
}

// Singleton instance
export const googleDocsMonitor = new GoogleDocsMonitor();
export default googleDocsMonitor;
