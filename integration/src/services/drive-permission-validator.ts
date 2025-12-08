/**
 * Google Drive Permission Validator
 *
 * Validates that the service account has ONLY intended folder access.
 * Prevents accidental leaks from over-permissioned service accounts.
 *
 * This implements CRITICAL-004 remediation.
 */

import { google, drive_v3 } from 'googleapis';
import { logger } from '../utils/logger';
import { configLoader } from '../utils/config-loader';
import path from 'path';

export interface ValidationResult {
  valid: boolean;
  errors: string[];
  warnings?: string[];
  unexpectedFolders?: FolderInfo[];
  missingFolders?: string[];
}

export interface FolderInfo {
  id: string;
  name: string;
  path: string;
  webViewLink?: string;
  parents?: string[];
}

export interface AlertPayload {
  subject: string;
  body: string;
  severity: 'CRITICAL' | 'HIGH' | 'MEDIUM';
  unexpectedFolders?: FolderInfo[];
}

/**
 * Google Drive Permission Validator
 *
 * Security Controls:
 * 1. Validates service account has ONLY whitelisted folder access
 * 2. Detects unexpected folder access (security breach indicator)
 * 3. Verifies expected folders are accessible
 * 4. Alerts security team on permission violations
 * 5. Blocks operations when unexpected access detected
 */
export class DrivePermissionValidator {
  private auth: any;
  private drive: drive_v3.Drive | null = null;
  private folderCache: Map<string, FolderInfo> = new Map();

  constructor(auth?: any) {
    this.auth = auth;
  }

  /**
   * Initialize Google Drive API client
   */
  async initialize(auth: any): Promise<void> {
    this.auth = auth;
    this.drive = google.drive({ version: 'v3', auth: this.auth });
    logger.info('DrivePermissionValidator initialized');
  }

  /**
   * Validate service account has ONLY intended folder access
   *
   * This is the primary security control for CRITICAL-004.
   */
  async validatePermissions(): Promise<ValidationResult> {
    if (!this.drive) {
      throw new Error('Drive API not initialized. Call initialize() first.');
    }

    logger.info('Starting Drive permission validation...');

    try {
      const config = configLoader.getConfig();
      const expectedFolders = config.google_docs?.monitored_folders || [];

      if (expectedFolders.length === 0) {
        logger.warn('No monitored folders configured');
        return {
          valid: true,
          errors: [],
          warnings: ['No monitored folders configured']
        };
      }

      // Get all folders service account has access to
      const accessibleFolders = await this.getAllAccessibleFolders();

      logger.info(`Found ${accessibleFolders.length} accessible folders`);

      // Check for unexpected access (security violation)
      const unexpectedFolders = accessibleFolders.filter(
        folder => !this.isExpectedFolder(folder, expectedFolders)
      );

      if (unexpectedFolders.length > 0) {
        const folderNames = unexpectedFolders.map(f => f.path).join(', ');
        logger.error(`Service account has unexpected folder access: ${folderNames}`);

        // Alert security team immediately
        await this.alertSecurityTeam({
          subject: '🚨 SECURITY ALERT: Google Drive Permission Violation',
          body: `Service account has unexpected folder access:\n${unexpectedFolders.map(f => `  - ${f.path} (${f.webViewLink})`).join('\n')}\n\nThis may indicate:\n1. Accidental folder sharing\n2. Compromised service account\n3. Misconfigured Google Drive sharing\n\nACTION REQUIRED: Review and revoke unexpected access immediately.`,
          severity: 'CRITICAL',
          unexpectedFolders
        });

        return {
          valid: false,
          errors: [
            `Unexpected folder access detected: ${folderNames}`,
            'Service account has access to folders outside whitelist',
            'Review Google Drive sharing permissions immediately'
          ],
          unexpectedFolders
        };
      }

      // Check for missing expected access (warning only)
      const missingFolders = expectedFolders.filter(
        expected => !accessibleFolders.some(actual => this.matchesPattern(actual.path, expected))
      );

      if (missingFolders.length > 0) {
        logger.warn(`Service account missing expected access: ${missingFolders.join(', ')}`);
      }

      logger.info('✅ Drive permission validation passed');

      return {
        valid: true,
        errors: [],
        warnings: missingFolders.length > 0 ? [`Missing access to: ${missingFolders.join(', ')}`] : [],
        missingFolders
      };

    } catch (error) {
      logger.error('Failed to validate Drive permissions', { error: error.message, stack: error.stack });

      return {
        valid: false,
        errors: [`Permission validation failed: ${error.message}`]
      };
    }
  }

  /**
   * Get all folders accessible to service account
   */
  private async getAllAccessibleFolders(): Promise<FolderInfo[]> {
    if (!this.drive) {
      throw new Error('Drive API not initialized');
    }

    try {
      logger.info('Fetching all accessible folders...');

      const response = await this.drive.files.list({
        q: "mimeType='application/vnd.google-apps.folder' and trashed=false",
        fields: 'nextPageToken, files(id, name, parents, webViewLink, createdTime, modifiedTime)',
        pageSize: 1000,
        spaces: 'drive'
      });

      const files = response.data.files || [];
      logger.info(`Found ${files.length} folders`);

      // Build folder hierarchy
      const folders: FolderInfo[] = [];

      for (const file of files) {
        const folderPath = await this.resolveFullPath(file);

        const folderInfo: FolderInfo = {
          id: file.id!,
          name: file.name!,
          path: folderPath,
          webViewLink: file.webViewLink,
          parents: file.parents
        };

        folders.push(folderInfo);
        this.folderCache.set(file.id!, folderInfo);
      }

      return folders;

    } catch (error) {
      logger.error('Failed to list folders', { error: error.message });
      throw new Error(`Failed to list folders: ${error.message}`);
    }
  }

  /**
   * Resolve full path of a folder by traversing parent hierarchy
   */
  private async resolveFullPath(file: drive_v3.Schema$File): Promise<string> {
    if (!file.name) return 'Unknown';

    // If no parents, it's a root-level shared folder
    if (!file.parents || file.parents.length === 0) {
      return file.name;
    }

    try {
      // Check cache first
      const parentId = file.parents[0];
      if (this.folderCache.has(parentId)) {
        const parent = this.folderCache.get(parentId)!;
        return `${parent.path}/${file.name}`;
      }

      // Fetch parent folder
      if (this.drive) {
        const parentResponse = await this.drive.files.get({
          fileId: parentId,
          fields: 'id, name, parents'
        });

        const parentFile = parentResponse.data;
        const parentPath = await this.resolveFullPath(parentFile);

        return `${parentPath}/${file.name}`;
      }

      return file.name;

    } catch (error) {
      logger.warn(`Failed to resolve parent for folder: ${file.name}`, { error: error.message });
      return file.name; // Fallback to just the name
    }
  }

  /**
   * Check if folder is expected (in whitelist)
   */
  private isExpectedFolder(folder: FolderInfo, expectedFolders: string[]): boolean {
    // Check exact match or pattern match
    return expectedFolders.some(expected => {
      return this.matchesPattern(folder.path, expected);
    });
  }

  /**
   * Check if folder path matches expected pattern
   *
   * Supports:
   * - Exact match: "Engineering/Projects"
   * - Wildcard: "Engineering/*" (matches "Engineering/Projects", "Engineering/Docs", etc.)
   * - Recursive wildcard: "Engineering/**" (matches all descendants)
   */
  private matchesPattern(actualPath: string, expectedPattern: string): boolean {
    // Normalize paths
    const normalized = actualPath.toLowerCase().replace(/\\/g, '/');
    const pattern = expectedPattern.toLowerCase().replace(/\\/g, '/');

    // Exact match
    if (normalized === pattern) {
      return true;
    }

    // Wildcard match: "Engineering/*"
    if (pattern.endsWith('/*')) {
      const prefix = pattern.slice(0, -2);
      // Check if actualPath starts with prefix and is direct child
      if (normalized.startsWith(prefix + '/')) {
        const remaining = normalized.slice(prefix.length + 1);
        return !remaining.includes('/'); // Direct child only
      }
    }

    // Recursive wildcard: "Engineering/**"
    if (pattern.endsWith('/**')) {
      const prefix = pattern.slice(0, -3);
      // Check if actualPath starts with prefix (any descendant)
      return normalized.startsWith(prefix + '/') || normalized === prefix;
    }

    return false;
  }

  /**
   * Check if a specific folder is whitelisted
   *
   * Used for runtime validation before scanning
   */
  isFolderWhitelisted(folderPath: string): boolean {
    const config = configLoader.getConfig();
    const expectedFolders = config.google_docs?.monitored_folders || [];

    return expectedFolders.some(expected => this.matchesPattern(folderPath, expected));
  }

  /**
   * Alert security team on permission violations
   */
  private async alertSecurityTeam(alert: AlertPayload): Promise<void> {
    logger.error('SECURITY ALERT', {
      subject: alert.subject,
      severity: alert.severity,
      unexpectedFolders: alert.unexpectedFolders?.map(f => f.path)
    });

    // TODO: Integrate with alerting system (Discord, Slack, PagerDuty, email)
    // For now, log to security audit trail

    console.error('\n' + '='.repeat(80));
    console.error(`🚨 ${alert.subject}`);
    console.error('='.repeat(80));
    console.error(alert.body);
    console.error('='.repeat(80) + '\n');

    // Write to security events log
    logger.security({
      eventType: 'PERMISSION_VIOLATION',
      severity: alert.severity,
      details: alert.body,
      unexpectedFolders: alert.unexpectedFolders,
      timestamp: new Date().toISOString()
    });
  }

  /**
   * Get validation statistics
   */
  getStatistics(): {
    totalAccessibleFolders: number;
    cacheSize: number;
    lastValidation?: Date;
  } {
    return {
      totalAccessibleFolders: this.folderCache.size,
      cacheSize: this.folderCache.size,
      lastValidation: undefined // TODO: Track last validation time
    };
  }

  /**
   * Clear folder cache
   */
  clearCache(): void {
    this.folderCache.clear();
    logger.info('Drive folder cache cleared');
  }
}

// Singleton instance
export const drivePermissionValidator = new DrivePermissionValidator();
export default drivePermissionValidator;
