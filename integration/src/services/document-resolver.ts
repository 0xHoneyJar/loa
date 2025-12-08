/**
 * Document Resolver
 *
 * Safely resolves document paths and prevents directory traversal.
 * Supports both local file system paths and Google Drive file IDs.
 *
 * This implements CRITICAL-002 remediation.
 */

import * as path from 'path';
import * as fs from 'fs';

export interface ResolvedDocument {
  type: 'filesystem' | 'gdrive';
  originalPath: string;
  resolvedPath?: string;  // For filesystem
  fileId?: string;        // For Google Drive
  exists: boolean;
  error?: string;
}

export class DocumentResolver {
  // Safe base directories (relative to project root)
  private readonly ALLOWED_BASE_DIRS = [
    'docs',
    'integration/docs',
    'examples'
  ];

  // Project root (absolute path)
  private readonly PROJECT_ROOT: string;

  constructor() {
    // Resolve project root (2 levels up from this file)
    this.PROJECT_ROOT = path.resolve(__dirname, '../../..');
  }

  /**
   * Resolve a document path to an absolute path
   * Returns null if path is invalid or outside allowed directories
   */
  async resolveDocument(relativePath: string): Promise<ResolvedDocument> {
    // Check if this is a Google Drive file ID
    if (this.isGoogleDriveId(relativePath)) {
      return this.resolveGoogleDriveDocument(relativePath);
    }

    // Resolve as filesystem path
    return this.resolveFilesystemDocument(relativePath);
  }

  /**
   * Resolve multiple documents
   */
  async resolveDocuments(relativePaths: string[]): Promise<ResolvedDocument[]> {
    const promises = relativePaths.map(p => this.resolveDocument(p));
    return Promise.all(promises);
  }

  /**
   * Resolve a filesystem document
   */
  private async resolveFilesystemDocument(relativePath: string): Promise<ResolvedDocument> {
    try {
      // Try each allowed base directory
      for (const baseDir of this.ALLOWED_BASE_DIRS) {
        const basePath = path.join(this.PROJECT_ROOT, baseDir);
        const fullPath = path.resolve(basePath, relativePath);

        // CRITICAL: Ensure resolved path is within allowed directory
        if (!this.isPathSafe(fullPath, basePath)) {
          continue; // Try next base directory
        }

        // Check if file exists
        if (fs.existsSync(fullPath)) {
          return {
            type: 'filesystem',
            originalPath: relativePath,
            resolvedPath: fullPath,
            exists: true
          };
        }
      }

      // File not found in any allowed directory
      return {
        type: 'filesystem',
        originalPath: relativePath,
        exists: false,
        error: 'File not found in allowed directories'
      };

    } catch (error) {
      return {
        type: 'filesystem',
        originalPath: relativePath,
        exists: false,
        error: `Resolution failed: ${error instanceof Error ? error.message : String(error)}`
      };
    }
  }

  /**
   * Resolve a Google Drive document
   */
  private async resolveGoogleDriveDocument(fileId: string): Promise<ResolvedDocument> {
    // Validate Google Drive file ID format
    // Format: alphanumeric + hyphens + underscores, typically 20-40 chars
    const validIdPattern = /^[a-zA-Z0-9_-]{20,50}$/;

    if (!validIdPattern.test(fileId)) {
      return {
        type: 'gdrive',
        originalPath: fileId,
        exists: false,
        error: 'Invalid Google Drive file ID format'
      };
    }

    // Note: Actual existence check would require Google Drive API call
    // For now, assume valid format = potentially valid ID
    return {
      type: 'gdrive',
      originalPath: fileId,
      fileId,
      exists: true // Will be validated during actual fetch
    };
  }

  /**
   * Check if a resolved path is safe (within allowed directory)
   */
  private isPathSafe(resolvedPath: string, basePath: string): boolean {
    // Normalize paths for comparison
    const normalizedResolved = path.normalize(resolvedPath);
    const normalizedBase = path.normalize(basePath);

    // Check if resolved path starts with base path
    // This prevents directory traversal attacks
    return normalizedResolved.startsWith(normalizedBase);
  }

  /**
   * Check if string looks like a Google Drive file ID
   */
  private isGoogleDriveId(str: string): boolean {
    // Google Drive file IDs:
    // - No slashes or dots
    // - Alphanumeric with hyphens/underscores
    // - Typically 20-40 characters
    const gdrivePattern = /^[a-zA-Z0-9_-]{20,50}$/;
    return gdrivePattern.test(str) && !str.includes('/') && !str.includes('.');
  }

  /**
   * Get list of allowed base directories (for display/debugging)
   */
  getAllowedDirectories(): string[] {
    return this.ALLOWED_BASE_DIRS.map(dir =>
      path.join(this.PROJECT_ROOT, dir)
    );
  }

  /**
   * Check if a path would be allowed (without resolving)
   */
  isPathAllowed(relativePath: string): boolean {
    for (const baseDir of this.ALLOWED_BASE_DIRS) {
      const basePath = path.join(this.PROJECT_ROOT, baseDir);
      const fullPath = path.resolve(basePath, relativePath);

      if (this.isPathSafe(fullPath, basePath)) {
        return true;
      }
    }
    return false;
  }

  /**
   * Read document content (if resolved successfully)
   */
  async readDocument(resolved: ResolvedDocument): Promise<string> {
    if (!resolved.exists) {
      throw new Error(`Document does not exist: ${resolved.error || 'unknown error'}`);
    }

    if (resolved.type === 'filesystem') {
      if (!resolved.resolvedPath) {
        throw new Error('Resolved path is missing');
      }

      try {
        return fs.readFileSync(resolved.resolvedPath, 'utf8');
      } catch (error) {
        throw new Error(`Failed to read file: ${error instanceof Error ? error.message : String(error)}`);
      }
    }

    if (resolved.type === 'gdrive') {
      // Google Drive reading would be implemented here
      // For now, throw an error indicating feature not yet implemented
      throw new Error('Google Drive document reading not yet implemented. Use MCP server for Google Drive access.');
    }

    throw new Error(`Unknown document type: ${resolved.type}`);
  }

  /**
   * Read multiple documents
   */
  async readDocuments(resolved: ResolvedDocument[]): Promise<Array<{ name: string; content: string }>> {
    const results: Array<{ name: string; content: string }> = [];

    for (const doc of resolved) {
      if (!doc.exists) {
        throw new Error(`Document not found: ${doc.originalPath} - ${doc.error}`);
      }

      try {
        const content = await this.readDocument(doc);
        results.push({
          name: doc.originalPath,
          content
        });
      } catch (error) {
        throw new Error(`Failed to read ${doc.originalPath}: ${error instanceof Error ? error.message : String(error)}`);
      }
    }

    return results;
  }
}

export default new DocumentResolver();
