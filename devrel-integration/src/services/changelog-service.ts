/**
 * Changelog Generation Service
 *
 * Sprint 5 - Task 5.2: Changelog Generation Service
 *
 * Auto-generates product changelogs from Linear issue completions.
 * Formats changelogs using semantic versioning with Keep a Changelog format.
 *
 * Storage: Google Docs in `/Products/{Product}/Changelog.md`
 *
 * Features:
 * - Query Linear for completed issues
 * - Group by type (feature, bugfix, refactor, etc.)
 * - Format as semantic changelog (Added, Changed, Fixed, Removed)
 * - Link to Linear issues for traceability
 * - Version-based organization
 */

import { logger } from '../utils/logger';
import { getCurrentTenant } from './tenant-context';
import { tieredCache } from './tiered-cache';

// =============================================================================
// Types
// =============================================================================

export type ChangeType = 'added' | 'changed' | 'fixed' | 'removed' | 'security' | 'deprecated';

export interface ChangelogEntry {
  /** Type of change */
  type: ChangeType;
  /** Description of the change */
  description: string;
  /** Linear issue identifier */
  issueId?: string;
  /** Linear issue URL */
  issueUrl?: string;
  /** Labels from Linear */
  labels?: string[];
  /** Who made the change */
  author?: string;
  /** When the issue was completed */
  completedAt?: Date;
}

export interface ChangelogVersion {
  /** Version string (e.g., "1.0.0", "0.2.0") */
  version: string;
  /** Release date */
  date: Date;
  /** Changes grouped by type */
  changes: {
    added: ChangelogEntry[];
    changed: ChangelogEntry[];
    fixed: ChangelogEntry[];
    removed: ChangelogEntry[];
    security: ChangelogEntry[];
    deprecated: ChangelogEntry[];
  };
  /** Optional release notes/summary */
  summary?: string;
}

export interface Changelog {
  /** Product name */
  product: string;
  /** All versions (newest first) */
  versions: ChangelogVersion[];
  /** Unreleased changes */
  unreleased: {
    added: ChangelogEntry[];
    changed: ChangelogEntry[];
    fixed: ChangelogEntry[];
    removed: ChangelogEntry[];
    security: ChangelogEntry[];
    deprecated: ChangelogEntry[];
  };
  /** Last updated timestamp */
  lastUpdated: Date;
  /** Google Doc URL */
  documentUrl?: string;
}

export interface LinearIssue {
  id: string;
  identifier: string;
  title: string;
  description?: string;
  url: string;
  labels: Array<{ name: string }>;
  state: { name: string; type: string };
  completedAt?: string;
  assignee?: { name: string; email?: string };
}

export interface AddChangeParams {
  product: string;
  type: ChangeType;
  description: string;
  issueId?: string;
  issueUrl?: string;
  labels?: string[];
  author?: string;
}

export interface CreateVersionParams {
  product: string;
  version: string;
  summary?: string;
}

// =============================================================================
// Label to Change Type Mapping
// =============================================================================

const LABEL_TYPE_MAP: Record<string, ChangeType> = {
  'type:feature': 'added',
  'type:enhancement': 'changed',
  'type:bugfix': 'fixed',
  'type:bug': 'fixed',
  'type:fix': 'fixed',
  'type:refactor': 'changed',
  'type:removal': 'removed',
  'type:deprecation': 'deprecated',
  'type:security': 'security',
  'priority:critical': 'security', // Critical issues often security-related
  'feature': 'added',
  'enhancement': 'changed',
  'bug': 'fixed',
  'bugfix': 'fixed',
  'refactor': 'changed',
  'breaking': 'changed',
  'security': 'security',
  'deprecation': 'deprecated',
};

/**
 * Determine change type from Linear labels
 */
function determineChangeType(labels: string[]): ChangeType {
  for (const label of labels) {
    const labelLower = label.toLowerCase();
    if (LABEL_TYPE_MAP[labelLower]) {
      return LABEL_TYPE_MAP[labelLower];
    }
    // Check partial matches
    for (const [key, type] of Object.entries(LABEL_TYPE_MAP)) {
      if (labelLower.includes(key) || key.includes(labelLower)) {
        return type;
      }
    }
  }
  // Default to 'changed' if no specific type found
  return 'changed';
}

// =============================================================================
// Changelog Formatting
// =============================================================================

/**
 * Format changelog to Keep a Changelog markdown format
 */
function formatChangelog(changelog: Changelog): string {
  const lines: string[] = [];

  lines.push(`# Changelog - ${changelog.product}`);
  lines.push('');
  lines.push('All notable changes to this project will be documented in this file.');
  lines.push('');
  lines.push('The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),');
  lines.push('and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).');
  lines.push('');

  // Unreleased section
  const hasUnreleased = Object.values(changelog.unreleased).some(arr => arr.length > 0);
  if (hasUnreleased) {
    lines.push('## [Unreleased]');
    lines.push('');
    lines.push(...formatChangeGroup(changelog.unreleased));
    lines.push('');
  }

  // Version sections
  for (const version of changelog.versions) {
    const dateStr = version.date.toISOString().split('T')[0];
    lines.push(`## [${version.version}] - ${dateStr}`);
    lines.push('');

    if (version.summary) {
      lines.push(version.summary);
      lines.push('');
    }

    lines.push(...formatChangeGroup(version.changes));
    lines.push('');
  }

  lines.push('---');
  lines.push(`*Last updated: ${changelog.lastUpdated.toISOString()}*`);

  return lines.join('\n');
}

/**
 * Format a group of changes by type
 */
function formatChangeGroup(changes: Changelog['unreleased']): string[] {
  const lines: string[] = [];
  const sections: Array<{ title: string; key: keyof typeof changes }> = [
    { title: 'Added', key: 'added' },
    { title: 'Changed', key: 'changed' },
    { title: 'Deprecated', key: 'deprecated' },
    { title: 'Removed', key: 'removed' },
    { title: 'Fixed', key: 'fixed' },
    { title: 'Security', key: 'security' },
  ];

  for (const section of sections) {
    const entries = changes[section.key];
    if (entries.length > 0) {
      lines.push(`### ${section.title}`);
      lines.push('');
      for (const entry of entries) {
        let line = `- ${entry.description}`;
        if (entry.issueUrl && entry.issueId) {
          line += ` ([${entry.issueId}](${entry.issueUrl}))`;
        } else if (entry.issueId) {
          line += ` (${entry.issueId})`;
        }
        lines.push(line);
      }
      lines.push('');
    }
  }

  return lines;
}

// =============================================================================
// Changelog Service Implementation
// =============================================================================

export class ChangelogService {
  private static instance: ChangelogService;

  /** In-memory storage for MVP (replace with Google Docs in production) */
  private changelogStore = new Map<string, Changelog>();

  /** Linear client (injected) */
  private linearClient?: {
    issues: {
      list(params: { filter: Record<string, unknown>; first?: number }): Promise<{ nodes: LinearIssue[] }>;
    };
  };

  /** Google Docs storage service (injected) */
  private googleDocsService?: {
    createDocument(title: string, content: string, folderId?: string): Promise<{ id: string; url: string }>;
    updateDocument(docId: string, content: string): Promise<void>;
  };

  constructor() {
    // Initialize with empty stores
  }

  /**
   * Get singleton instance
   */
  static getInstance(): ChangelogService {
    if (!ChangelogService.instance) {
      ChangelogService.instance = new ChangelogService();
    }
    return ChangelogService.instance;
  }

  /**
   * Inject Linear client for issue queries
   */
  setLinearClient(client: typeof this.linearClient): void {
    this.linearClient = client;
  }

  /**
   * Inject Google Docs service for persistence
   */
  setGoogleDocsService(service: typeof this.googleDocsService): void {
    this.googleDocsService = service;
  }

  // ===========================================================================
  // Public API
  // ===========================================================================

  /**
   * Get or create changelog for a product
   */
  async getChangelog(product: string): Promise<Changelog> {
    const tenant = getCurrentTenant();
    const tenantId = tenant.tenantId;
    const cacheKey = `changelog:${product}`;

    return await tieredCache.getOrFetch(
      tenantId,
      cacheKey,
      async () => {
        const key = this.getProductKey(tenantId, product);
        let changelog = this.changelogStore.get(key);

        if (!changelog) {
          changelog = this.createEmptyChangelog(product);
          this.changelogStore.set(key, changelog);
        }

        return changelog;
      },
      { cacheType: 'changelog', l2TtlSeconds: 10 * 60 }
    );
  }

  /**
   * Add a change to the unreleased section
   */
  async addChange(params: AddChangeParams): Promise<void> {
    const tenant = getCurrentTenant();
    const tenantId = tenant.tenantId;

    logger.info('Adding changelog entry', {
      tenantId,
      product: params.product,
      type: params.type,
    });

    const changelog = await this.getChangelogMutable(tenantId, params.product);

    const entry: ChangelogEntry = {
      type: params.type,
      description: params.description,
      issueId: params.issueId,
      issueUrl: params.issueUrl,
      labels: params.labels,
      author: params.author,
      completedAt: new Date(),
    };

    changelog.unreleased[params.type].push(entry);
    changelog.lastUpdated = new Date();

    // Invalidate cache
    await tieredCache.invalidate(tenantId, `changelog:${params.product}`);

    logger.info('Changelog entry added', {
      tenantId,
      product: params.product,
      type: params.type,
      description: params.description.substring(0, 50),
    });
  }

  /**
   * Create a new version from unreleased changes
   */
  async createVersion(params: CreateVersionParams): Promise<ChangelogVersion> {
    const tenant = getCurrentTenant();
    const tenantId = tenant.tenantId;

    logger.info('Creating changelog version', {
      tenantId,
      product: params.product,
      version: params.version,
    });

    const changelog = await this.getChangelogMutable(tenantId, params.product);

    // Create version from unreleased changes
    const version: ChangelogVersion = {
      version: params.version,
      date: new Date(),
      changes: { ...changelog.unreleased },
      summary: params.summary,
    };

    // Add to versions list (newest first)
    changelog.versions.unshift(version);

    // Clear unreleased
    changelog.unreleased = this.createEmptyChanges();
    changelog.lastUpdated = new Date();

    // Update Google Docs if available
    await this.persistChangelog(changelog);

    // Invalidate cache
    await tieredCache.invalidate(tenantId, `changelog:${params.product}`);

    logger.info('Changelog version created', {
      tenantId,
      product: params.product,
      version: params.version,
      changesCount: this.countChanges(version.changes),
    });

    return version;
  }

  /**
   * Process completed Linear issues into changelog entries
   */
  async processLinearIssues(product: string, issues: LinearIssue[]): Promise<number> {
    const tenant = getCurrentTenant();
    const tenantId = tenant.tenantId;

    logger.info('Processing Linear issues for changelog', {
      tenantId,
      product,
      issueCount: issues.length,
    });

    let addedCount = 0;

    for (const issue of issues) {
      const labels = issue.labels.map(l => l.name);
      const type = determineChangeType(labels);

      await this.addChange({
        product,
        type,
        description: issue.title,
        issueId: issue.identifier,
        issueUrl: issue.url,
        labels,
        author: issue.assignee?.name,
      });

      addedCount++;
    }

    logger.info('Linear issues processed', {
      tenantId,
      product,
      addedCount,
    });

    return addedCount;
  }

  /**
   * Query Linear for completed issues and add to changelog
   * Requires Linear client to be injected
   */
  async syncFromLinear(product: string, projectId: string): Promise<number> {
    if (!this.linearClient) {
      logger.warn('Linear client not configured, skipping sync');
      return 0;
    }

    const tenant = getCurrentTenant();
    logger.info('Syncing changelog from Linear', {
      tenantId: tenant.tenantId,
      product,
      projectId,
    });

    try {
      const response = await this.linearClient.issues.list({
        filter: {
          project: { id: { eq: projectId } },
          state: { type: { eq: 'completed' } },
        },
        first: 100,
      });

      return await this.processLinearIssues(product, response.nodes);
    } catch (error) {
      logger.error('Failed to sync from Linear', {
        error: error instanceof Error ? error.message : String(error),
      });
      throw error;
    }
  }

  /**
   * Get changelog for a specific version
   */
  async getVersion(product: string, version: string): Promise<ChangelogVersion | null> {
    const changelog = await this.getChangelog(product);
    return changelog.versions.find(v => v.version === version) || null;
  }

  /**
   * Get all changes between two versions
   */
  async getChangesBetweenVersions(
    product: string,
    fromVersion: string,
    toVersion: string
  ): Promise<ChangelogVersion[]> {
    const changelog = await this.getChangelog(product);

    const fromIndex = changelog.versions.findIndex(v => v.version === fromVersion);
    const toIndex = changelog.versions.findIndex(v => v.version === toVersion);

    if (fromIndex === -1 || toIndex === -1) {
      return [];
    }

    // Versions are stored newest first, so we need to handle the order
    const start = Math.min(fromIndex, toIndex);
    const end = Math.max(fromIndex, toIndex);

    return changelog.versions.slice(start, end + 1);
  }

  /**
   * Format changelog as markdown
   */
  async formatAsMarkdown(product: string): Promise<string> {
    const changelog = await this.getChangelog(product);
    return formatChangelog(changelog);
  }

  /**
   * Get recent changes (last N entries across all types)
   */
  async getRecentChanges(product: string, limit: number = 10): Promise<ChangelogEntry[]> {
    const changelog = await this.getChangelog(product);

    // Collect all unreleased changes
    const allChanges: ChangelogEntry[] = [
      ...changelog.unreleased.added,
      ...changelog.unreleased.changed,
      ...changelog.unreleased.fixed,
      ...changelog.unreleased.removed,
      ...changelog.unreleased.security,
      ...changelog.unreleased.deprecated,
    ];

    // Add changes from recent versions
    for (const version of changelog.versions.slice(0, 3)) {
      allChanges.push(
        ...version.changes.added,
        ...version.changes.changed,
        ...version.changes.fixed,
        ...version.changes.removed,
        ...version.changes.security,
        ...version.changes.deprecated
      );
    }

    // Sort by completedAt (most recent first) and limit
    return allChanges
      .sort((a, b) => {
        const dateA = a.completedAt?.getTime() || 0;
        const dateB = b.completedAt?.getTime() || 0;
        return dateB - dateA;
      })
      .slice(0, limit);
  }

  /**
   * Clear all changelogs (for testing)
   */
  clearAll(): void {
    this.changelogStore.clear();
  }

  // ===========================================================================
  // Private Methods
  // ===========================================================================

  /**
   * Get product-scoped key
   */
  private getProductKey(tenantId: string, product: string): string {
    return `${tenantId}:${product}`;
  }

  /**
   * Get changelog with direct mutation access (bypasses cache)
   */
  private async getChangelogMutable(tenantId: string, product: string): Promise<Changelog> {
    const key = this.getProductKey(tenantId, product);
    let changelog = this.changelogStore.get(key);

    if (!changelog) {
      changelog = this.createEmptyChangelog(product);
      this.changelogStore.set(key, changelog);
    }

    return changelog;
  }

  /**
   * Create empty changelog
   */
  private createEmptyChangelog(product: string): Changelog {
    return {
      product,
      versions: [],
      unreleased: this.createEmptyChanges(),
      lastUpdated: new Date(),
    };
  }

  /**
   * Create empty changes object
   */
  private createEmptyChanges(): Changelog['unreleased'] {
    return {
      added: [],
      changed: [],
      fixed: [],
      removed: [],
      security: [],
      deprecated: [],
    };
  }

  /**
   * Count total changes in a change group
   */
  private countChanges(changes: Changelog['unreleased']): number {
    return (
      changes.added.length +
      changes.changed.length +
      changes.fixed.length +
      changes.removed.length +
      changes.security.length +
      changes.deprecated.length
    );
  }

  /**
   * Persist changelog to Google Docs
   */
  private async persistChangelog(changelog: Changelog): Promise<void> {
    if (!this.googleDocsService) {
      return;
    }

    try {
      const content = formatChangelog(changelog);

      if (changelog.documentUrl) {
        // Update existing document
        // Note: Would need to extract doc ID from URL
        logger.debug('Changelog Google Doc update would happen here');
      } else {
        // Create new document
        const doc = await this.googleDocsService.createDocument(
          `Changelog - ${changelog.product}`,
          content
        );
        changelog.documentUrl = doc.url;
        logger.info('Changelog stored in Google Docs', {
          product: changelog.product,
          documentUrl: doc.url,
        });
      }
    } catch (error) {
      logger.warn('Failed to persist changelog to Google Docs', {
        error: error instanceof Error ? error.message : String(error),
      });
    }
  }
}

// =============================================================================
// Export Singleton Instance
// =============================================================================

export const changelogService = ChangelogService.getInstance();
export default changelogService;

// =============================================================================
// Convenience Functions
// =============================================================================

/**
 * Get changelog for a product
 */
export async function getChangelog(product: string): Promise<Changelog> {
  return changelogService.getChangelog(product);
}

/**
 * Add a change entry
 */
export async function addChange(params: AddChangeParams): Promise<void> {
  return changelogService.addChange(params);
}

/**
 * Create a new version
 */
export async function createVersion(params: CreateVersionParams): Promise<ChangelogVersion> {
  return changelogService.createVersion(params);
}

/**
 * Format changelog as markdown
 */
export async function formatChangelogAsMarkdown(product: string): Promise<string> {
  return changelogService.formatAsMarkdown(product);
}
