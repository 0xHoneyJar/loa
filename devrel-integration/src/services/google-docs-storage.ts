/**
 * Google Docs Storage Service
 *
 * Sprint 2 - Task 2.1: Google Docs API Client Integration
 *
 * Implements GoogleDocsStorageService for creating, reading, and updating
 * Google Docs with proper authentication using service account credentials
 * from Sprint 1.
 *
 * Features:
 * - Service account authentication via google-auth-library
 * - Document creation with markdown support
 * - Document reading and updating
 * - Permission management
 * - Search by folder and name
 * - Error handling with exponential backoff for rate limits
 * - Comprehensive logging
 */

import { google, docs_v1, drive_v3 } from 'googleapis';
import { GoogleAuth, JWT } from 'google-auth-library';
import { logger, auditLog } from '../utils/logger';
import { RetryHandler } from './retry-handler';
import { circuitBreakerRegistry } from './circuit-breaker';
import * as fs from 'fs';
import * as path from 'path';

// =============================================================================
// Types and Interfaces
// =============================================================================

export interface DocumentMetadata {
  title?: string;
  description?: string;
  sourceDocuments?: string[];
  persona?: 'leadership' | 'product' | 'marketing' | 'devrel';
  generatedAt?: Date;
  projectName?: string;
  sprintId?: string;
  originalDocumentId?: string;
  transformationDurationMs?: number;
  version?: string;
}

export interface CreateDocumentParams {
  title: string;
  content: string; // Markdown or plain text
  folderId: string; // From Terraform outputs or folder-ids.json
  metadata?: DocumentMetadata;
}

export interface CreateDocumentResult {
  documentId: string;
  webViewLink: string;
  title: string;
  folderId: string;
}

export interface Document {
  documentId: string;
  title: string;
  content: string;
  webViewLink: string;
  createdTime?: string;
  modifiedTime?: string;
}

export interface Permission {
  email: string;
  role: 'reader' | 'writer' | 'commenter';
  type: 'user' | 'group' | 'domain';
}

export interface SearchResult {
  documents: Document[];
  nextPageToken?: string;
}

// =============================================================================
// Google Docs Storage Service
// =============================================================================

export class GoogleDocsStorageService {
  private auth: GoogleAuth | JWT | null = null;
  private docsClient: docs_v1.Docs | null = null;
  private driveClient: drive_v3.Drive | null = null;
  private initialized = false;

  // Retry handler with exponential backoff for rate limits
  private readonly retryHandler = new RetryHandler({
    maxRetries: 5,
    initialDelayMs: 1000, // 1s, 2s, 4s, 8s, 16s backoff
    backoffMultiplier: 2,
    timeoutMs: 60000, // 60s per attempt
  });

  // Circuit breaker for Google APIs
  private readonly googleCircuitBreaker = circuitBreakerRegistry.getOrCreate('google-docs-api', {
    failureThreshold: 5,
    successThreshold: 2,
    resetTimeoutMs: 60000, // 1 minute
  });

  /**
   * Initialize the service with authentication
   */
  async initialize(): Promise<void> {
    if (this.initialized) {
      return;
    }

    logger.info('Initializing Google Docs Storage Service');

    try {
      // Check for service account credentials
      const keyFilePath = process.env.GOOGLE_SERVICE_ACCOUNT_KEY_PATH;
      const serviceAccountEmail = process.env.GOOGLE_SERVICE_ACCOUNT_EMAIL;

      if (keyFilePath && fs.existsSync(keyFilePath)) {
        // Use service account key file
        logger.info('Using service account key file for authentication', { keyFilePath });

        const keyFileContent = JSON.parse(fs.readFileSync(keyFilePath, 'utf-8'));

        this.auth = new JWT({
          email: keyFileContent.client_email,
          key: keyFileContent.private_key,
          scopes: [
            'https://www.googleapis.com/auth/drive',
            'https://www.googleapis.com/auth/documents',
          ],
        });
      } else if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
        // Use Application Default Credentials
        logger.info('Using Application Default Credentials');

        this.auth = new GoogleAuth({
          scopes: [
            'https://www.googleapis.com/auth/drive',
            'https://www.googleapis.com/auth/documents',
          ],
        });
      } else {
        throw new Error(
          'No Google authentication credentials found. ' +
            'Set GOOGLE_SERVICE_ACCOUNT_KEY_PATH or GOOGLE_APPLICATION_CREDENTIALS.'
        );
      }

      // Initialize API clients
      this.docsClient = google.docs({ version: 'v1', auth: this.auth as any });
      this.driveClient = google.drive({ version: 'v3', auth: this.auth as any });

      // Verify authentication by making a simple API call
      await this.verifyAuthentication();

      this.initialized = true;
      logger.info('Google Docs Storage Service initialized successfully');
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error('Failed to initialize Google Docs Storage Service', { error: errorMessage });
      throw new Error(`Google Docs initialization failed: ${errorMessage}`);
    }
  }

  /**
   * Verify authentication is working
   */
  private async verifyAuthentication(): Promise<void> {
    try {
      // Try to get about info from Drive API
      const response = await this.driveClient!.about.get({
        fields: 'user(displayName,emailAddress)',
      });

      logger.info('Authentication verified', {
        user: response.data.user?.displayName,
        email: response.data.user?.emailAddress,
      });
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error('Authentication verification failed', { error: errorMessage });
      throw new Error(`Authentication verification failed: ${errorMessage}`);
    }
  }

  /**
   * Create a new document in the specified folder
   */
  async createDocument(params: CreateDocumentParams): Promise<CreateDocumentResult> {
    await this.ensureInitialized();

    const { title, content, folderId, metadata } = params;

    logger.info('Creating new document', { title, folderId });

    return this.googleCircuitBreaker.execute(async () => {
      const result = await this.retryHandler.execute(
        async () => {
          // Step 1: Create Google Doc in Drive
          const fileMetadata: drive_v3.Schema$File = {
            name: title,
            mimeType: 'application/vnd.google-apps.document',
            parents: [folderId],
            description: metadata?.description || `Generated by Onomancer Bot`,
            properties: this.metadataToProperties(metadata),
          };

          const createResponse = await this.driveClient!.files.create({
            requestBody: fileMetadata,
            fields: 'id,name,webViewLink,parents',
          });

          const documentId = createResponse.data.id!;
          const webViewLink = createResponse.data.webViewLink!;

          logger.info('Document created in Drive', { documentId, title });

          // Step 2: Add content to the document
          await this.updateDocumentContent(documentId, content);

          logger.info('Document content added', { documentId });

          // Audit log
          auditLog.documentOperation('system', 'create', {
            documentId,
            title,
            folderId,
            metadata,
          });

          return {
            documentId,
            webViewLink,
            title,
            folderId,
          };
        },
        'createDocument'
      );

      if (!result.success) {
        throw result.error || new Error('Failed to create document');
      }

      return result.result!;
    });
  }

  /**
   * Read document content
   */
  async getDocument(documentId: string): Promise<Document> {
    await this.ensureInitialized();

    logger.info('Reading document', { documentId });

    return this.googleCircuitBreaker.execute(async () => {
      const result = await this.retryHandler.execute(
        async () => {
          // Get document content from Docs API
          const docsResponse = await this.docsClient!.documents.get({
            documentId,
          });

          // Get file metadata from Drive API
          const driveResponse = await this.driveClient!.files.get({
            fileId: documentId,
            fields: 'id,name,webViewLink,createdTime,modifiedTime',
          });

          // Extract text content from document
          const content = this.extractTextFromDocument(docsResponse.data);

          return {
            documentId,
            title: docsResponse.data.title || driveResponse.data.name || 'Untitled',
            content,
            webViewLink: driveResponse.data.webViewLink || '',
            createdTime: driveResponse.data.createdTime || undefined,
            modifiedTime: driveResponse.data.modifiedTime || undefined,
          };
        },
        'getDocument'
      );

      if (!result.success) {
        throw result.error || new Error('Failed to read document');
      }

      return result.result!;
    });
  }

  /**
   * Update existing document content
   */
  async updateDocument(documentId: string, content: string): Promise<void> {
    await this.ensureInitialized();

    logger.info('Updating document', { documentId });

    return this.googleCircuitBreaker.execute(async () => {
      const result = await this.retryHandler.execute(
        async () => {
          // First, get the document to find its length
          const doc = await this.docsClient!.documents.get({ documentId });
          const endIndex = this.getDocumentEndIndex(doc.data);

          // Clear existing content (if any) and add new content
          const requests: docs_v1.Schema$Request[] = [];

          // Delete all content if document has content
          if (endIndex > 1) {
            requests.push({
              deleteContentRange: {
                range: {
                  startIndex: 1,
                  endIndex: endIndex,
                },
              },
            });
          }

          // Insert new content
          requests.push({
            insertText: {
              location: { index: 1 },
              text: content,
            },
          });

          // Apply formatting for markdown-like syntax
          const formattingRequests = this.generateFormattingRequests(content);
          requests.push(...formattingRequests);

          await this.docsClient!.documents.batchUpdate({
            documentId,
            requestBody: { requests },
          });

          // Audit log
          auditLog.documentOperation('system', 'update', { documentId });

          logger.info('Document updated successfully', { documentId });
        },
        'updateDocument'
      );

      if (!result.success) {
        throw result.error || new Error('Failed to update document');
      }
    });
  }

  /**
   * Set document permissions
   */
  async setPermissions(documentId: string, permissions: Permission[]): Promise<void> {
    await this.ensureInitialized();

    logger.info('Setting document permissions', { documentId, permissionCount: permissions.length });

    return this.googleCircuitBreaker.execute(async () => {
      const result = await this.retryHandler.execute(
        async () => {
          for (const permission of permissions) {
            await this.driveClient!.permissions.create({
              fileId: documentId,
              requestBody: {
                type: permission.type,
                role: permission.role,
                emailAddress: permission.email,
              },
              sendNotificationEmail: false,
            });

            logger.debug('Permission set', {
              documentId,
              email: permission.email,
              role: permission.role,
            });
          }

          // Audit log
          auditLog.documentOperation('system', 'setPermissions', {
            documentId,
            permissions: permissions.map(p => ({ email: p.email, role: p.role })),
          });

          logger.info('Permissions set successfully', { documentId });
        },
        'setPermissions'
      );

      if (!result.success) {
        throw result.error || new Error('Failed to set permissions');
      }
    });
  }

  /**
   * Search for documents by folder and query
   */
  async searchDocuments(
    folderId: string,
    query?: string,
    pageSize = 50,
    pageToken?: string
  ): Promise<SearchResult> {
    await this.ensureInitialized();

    logger.info('Searching documents', { folderId, query, pageSize });

    return this.googleCircuitBreaker.execute(async () => {
      const result = await this.retryHandler.execute(
        async () => {
          // Build search query
          let searchQuery = `'${folderId}' in parents and mimeType = 'application/vnd.google-apps.document' and trashed = false`;
          if (query) {
            searchQuery += ` and name contains '${query.replace(/'/g, "\\'")}'`;
          }

          const response = await this.driveClient!.files.list({
            q: searchQuery,
            pageSize,
            pageToken,
            fields: 'nextPageToken, files(id, name, webViewLink, createdTime, modifiedTime)',
            orderBy: 'modifiedTime desc',
          });

          const documents: Document[] = (response.data.files || []).map(file => ({
            documentId: file.id!,
            title: file.name || 'Untitled',
            content: '', // Content not fetched in search
            webViewLink: file.webViewLink || '',
            createdTime: file.createdTime || undefined,
            modifiedTime: file.modifiedTime || undefined,
          }));

          return {
            documents,
            nextPageToken: response.data.nextPageToken || undefined,
          };
        },
        'searchDocuments'
      );

      if (!result.success) {
        throw result.error || new Error('Failed to search documents');
      }

      return result.result!;
    });
  }

  /**
   * Delete a document
   */
  async deleteDocument(documentId: string): Promise<void> {
    await this.ensureInitialized();

    logger.info('Deleting document', { documentId });

    return this.googleCircuitBreaker.execute(async () => {
      const result = await this.retryHandler.execute(
        async () => {
          await this.driveClient!.files.delete({ fileId: documentId });

          // Audit log
          auditLog.documentOperation('system', 'delete', { documentId });

          logger.info('Document deleted successfully', { documentId });
        },
        'deleteDocument'
      );

      if (!result.success) {
        throw result.error || new Error('Failed to delete document');
      }
    });
  }

  /**
   * Add a link/relationship between documents
   */
  async linkDocuments(
    sourceDocumentId: string,
    targetDocumentId: string,
    linkText: string
  ): Promise<void> {
    await this.ensureInitialized();

    logger.info('Linking documents', { sourceDocumentId, targetDocumentId });

    // Get target document link
    const targetDoc = await this.getDocument(targetDocumentId);

    // Append link to source document
    const doc = await this.docsClient!.documents.get({ documentId: sourceDocumentId });
    const endIndex = this.getDocumentEndIndex(doc.data);

    const linkContent = `\n\n---\nRelated Document: [${linkText}](${targetDoc.webViewLink})\n`;

    await this.docsClient!.documents.batchUpdate({
      documentId: sourceDocumentId,
      requestBody: {
        requests: [
          {
            insertText: {
              location: { index: endIndex },
              text: linkContent,
            },
          },
        ],
      },
    });

    logger.info('Documents linked successfully', { sourceDocumentId, targetDocumentId });
  }

  // =============================================================================
  // Private Helper Methods
  // =============================================================================

  /**
   * Ensure service is initialized before operations
   */
  private async ensureInitialized(): Promise<void> {
    if (!this.initialized) {
      await this.initialize();
    }
  }

  /**
   * Update document content (internal helper)
   */
  private async updateDocumentContent(documentId: string, content: string): Promise<void> {
    const requests: docs_v1.Schema$Request[] = [
      {
        insertText: {
          location: { index: 1 },
          text: content,
        },
      },
    ];

    // Apply basic formatting for markdown-like syntax
    const formattingRequests = this.generateFormattingRequests(content);
    requests.push(...formattingRequests);

    await this.docsClient!.documents.batchUpdate({
      documentId,
      requestBody: { requests },
    });
  }

  /**
   * Generate formatting requests for markdown-like content
   */
  private generateFormattingRequests(content: string): docs_v1.Schema$Request[] {
    const requests: docs_v1.Schema$Request[] = [];
    const lines = content.split('\n');
    let currentIndex = 1; // Google Docs indices start at 1

    for (const line of lines) {
      const lineLength = line.length + 1; // +1 for newline

      // Format headings
      if (line.startsWith('# ')) {
        requests.push({
          updateParagraphStyle: {
            range: {
              startIndex: currentIndex,
              endIndex: currentIndex + lineLength,
            },
            paragraphStyle: {
              namedStyleType: 'HEADING_1',
            },
            fields: 'namedStyleType',
          },
        });
      } else if (line.startsWith('## ')) {
        requests.push({
          updateParagraphStyle: {
            range: {
              startIndex: currentIndex,
              endIndex: currentIndex + lineLength,
            },
            paragraphStyle: {
              namedStyleType: 'HEADING_2',
            },
            fields: 'namedStyleType',
          },
        });
      } else if (line.startsWith('### ')) {
        requests.push({
          updateParagraphStyle: {
            range: {
              startIndex: currentIndex,
              endIndex: currentIndex + lineLength,
            },
            paragraphStyle: {
              namedStyleType: 'HEADING_3',
            },
            fields: 'namedStyleType',
          },
        });
      }

      // Format bold text (**text**)
      const boldRegex = /\*\*([^*]+)\*\*/g;
      let boldMatch;
      while ((boldMatch = boldRegex.exec(line)) !== null) {
        const startOffset = currentIndex + boldMatch.index;
        const endOffset = startOffset + boldMatch[0].length;
        requests.push({
          updateTextStyle: {
            range: {
              startIndex: startOffset,
              endIndex: endOffset,
            },
            textStyle: {
              bold: true,
            },
            fields: 'bold',
          },
        });
      }

      // Format code blocks (```text```)
      if (line.startsWith('```')) {
        requests.push({
          updateTextStyle: {
            range: {
              startIndex: currentIndex,
              endIndex: currentIndex + lineLength,
            },
            textStyle: {
              weightedFontFamily: {
                fontFamily: 'Courier New',
              },
              backgroundColor: {
                color: {
                  rgbColor: { red: 0.95, green: 0.95, blue: 0.95 },
                },
              },
            },
            fields: 'weightedFontFamily,backgroundColor',
          },
        });
      }

      currentIndex += lineLength;
    }

    return requests;
  }

  /**
   * Extract text content from Google Docs document
   */
  private extractTextFromDocument(doc: docs_v1.Schema$Document): string {
    if (!doc.body?.content) {
      return '';
    }

    let text = '';

    for (const element of doc.body.content) {
      if (element.paragraph?.elements) {
        for (const elem of element.paragraph.elements) {
          if (elem.textRun?.content) {
            text += elem.textRun.content;
          }
        }
      }
      if (element.table) {
        // Handle tables if needed
        text += '[Table]\n';
      }
    }

    return text;
  }

  /**
   * Get the end index of document content
   */
  private getDocumentEndIndex(doc: docs_v1.Schema$Document): number {
    if (!doc.body?.content) {
      return 1;
    }

    const lastElement = doc.body.content[doc.body.content.length - 1];
    return lastElement?.endIndex ? lastElement.endIndex - 1 : 1;
  }

  /**
   * Convert metadata to Google Drive properties
   */
  private metadataToProperties(
    metadata?: DocumentMetadata
  ): Record<string, string> | undefined {
    if (!metadata) {
      return undefined;
    }

    const properties: Record<string, string> = {};

    if (metadata.persona) properties.persona = metadata.persona;
    if (metadata.projectName) properties.projectName = metadata.projectName;
    if (metadata.sprintId) properties.sprintId = metadata.sprintId;
    if (metadata.originalDocumentId) properties.originalDocumentId = metadata.originalDocumentId;
    if (metadata.version) properties.version = metadata.version;
    if (metadata.generatedAt) properties.generatedAt = metadata.generatedAt.toISOString();
    if (metadata.transformationDurationMs) {
      properties.transformationDurationMs = metadata.transformationDurationMs.toString();
    }
    if (metadata.sourceDocuments) {
      properties.sourceDocuments = JSON.stringify(metadata.sourceDocuments);
    }

    return Object.keys(properties).length > 0 ? properties : undefined;
  }

  /**
   * Get circuit breaker state (for monitoring)
   */
  getCircuitBreakerState(): string {
    return this.googleCircuitBreaker.getState();
  }

  /**
   * Check if service is healthy
   */
  async healthCheck(): Promise<{ healthy: boolean; details: string }> {
    try {
      await this.ensureInitialized();

      // Verify we can make API calls
      await this.driveClient!.about.get({
        fields: 'user(emailAddress)',
      });

      return {
        healthy: true,
        details: 'Google Docs API connection is healthy',
      };
    } catch (error) {
      return {
        healthy: false,
        details: `Health check failed: ${error instanceof Error ? error.message : String(error)}`,
      };
    }
  }
}

// =============================================================================
// Export Singleton Instance
// =============================================================================

export const googleDocsStorage = new GoogleDocsStorageService();
export default googleDocsStorage;
