/**
 * User Preferences Management with JSON Schema Validation
 *
 * SECURITY FIX (MEDIUM-013): Add database integrity checks for user preferences
 * - JSON schema validation
 * - Atomic writes
 * - Data backup
 * - Validation before save/load
 */

import fs from 'fs';
import path from 'path';
import Ajv from 'ajv';
import { logger } from './logger';

/**
 * User notification preferences
 */
export interface UserNotificationPreferences {
  issue_assigned: boolean;
  issue_mentioned: boolean;
  issue_completed: boolean;
  comment_added: boolean;
  sprint_started: boolean;
  sprint_completed: boolean;
  daily_digest: boolean;
}

/**
 * User notification methods
 */
export interface UserNotificationMethods {
  discord_dm: boolean;
  discord_mention: boolean;
}

/**
 * Quiet hours configuration
 */
export interface QuietHours {
  enabled: boolean;
  start_hour: number;  // 0-23
  end_hour: number;    // 0-23
  timezone: string;    // IANA timezone
}

/**
 * User preferences
 */
export interface UserPreference {
  discord_user_id: string;
  linear_user_email?: string;
  notifications: UserNotificationPreferences;
  notification_methods: UserNotificationMethods;
  quiet_hours: QuietHours;
  updated_at: string;  // ISO 8601
}

/**
 * Preferences database structure
 */
export interface PreferencesDatabase {
  users: Record<string, UserPreference>;
  defaults: {
    notifications: UserNotificationPreferences;
    notification_methods: UserNotificationMethods;
    quiet_hours: QuietHours;
  };
}

/**
 * JSON Schema for user preferences (MEDIUM #13)
 */
const userPreferenceSchema: any = {
  type: 'object',
  properties: {
    discord_user_id: { type: 'string', minLength: 17, maxLength: 19 },
    linear_user_email: { type: 'string', format: 'email', nullable: true },
    notifications: {
      type: 'object',
      properties: {
        issue_assigned: { type: 'boolean' },
        issue_mentioned: { type: 'boolean' },
        issue_completed: { type: 'boolean' },
        comment_added: { type: 'boolean' },
        sprint_started: { type: 'boolean' },
        sprint_completed: { type: 'boolean' },
        daily_digest: { type: 'boolean' },
      },
      required: [
        'issue_assigned',
        'issue_mentioned',
        'issue_completed',
        'comment_added',
        'sprint_started',
        'sprint_completed',
        'daily_digest',
      ],
    },
    notification_methods: {
      type: 'object',
      properties: {
        discord_dm: { type: 'boolean' },
        discord_mention: { type: 'boolean' },
      },
      required: ['discord_dm', 'discord_mention'],
    },
    quiet_hours: {
      type: 'object',
      properties: {
        enabled: { type: 'boolean' },
        start_hour: { type: 'number', minimum: 0, maximum: 23 },
        end_hour: { type: 'number', minimum: 0, maximum: 23 },
        timezone: { type: 'string' },
      },
      required: ['enabled', 'start_hour', 'end_hour', 'timezone'],
    },
    updated_at: { type: 'string', format: 'date-time' },
  },
  required: [
    'discord_user_id',
    'notifications',
    'notification_methods',
    'quiet_hours',
    'updated_at',
  ],
};

const databaseSchema: any = {
  type: 'object',
  properties: {
    users: {
      type: 'object',
      required: [],
      additionalProperties: userPreferenceSchema,
    },
    defaults: {
      type: 'object',
      properties: {
        notifications: userPreferenceSchema.properties.notifications,
        notification_methods: userPreferenceSchema.properties.notification_methods,
        quiet_hours: userPreferenceSchema.properties.quiet_hours,
      },
      required: ['notifications', 'notification_methods', 'quiet_hours'],
    },
  },
  required: ['users', 'defaults'],
};

/**
 * User Preferences Manager
 */
export class UserPreferencesManager {
  private readonly filePath: string;
  private readonly backupPath: string;
  private readonly ajv: any;
  private readonly validateDatabase: any;
  private cache: PreferencesDatabase | null = null;

  constructor(configDir: string = path.join(__dirname, '../../config')) {
    this.filePath = path.join(configDir, 'user-preferences.json');
    this.backupPath = path.join(configDir, 'user-preferences.backup.json');
    this.ajv = new Ajv({ allErrors: true });
    this.validateDatabase = this.ajv.compile(databaseSchema);
  }

  /**
   * Load preferences from disk with validation
   */
  async load(): Promise<PreferencesDatabase> {
    try {
      // Read file
      const content = await fs.promises.readFile(this.filePath, 'utf-8');
      const data = JSON.parse(content) as PreferencesDatabase;

      // Validate schema
      const valid = this.validateDatabase(data);
      if (!valid) {
        const errors = this.ajv.errorsText(this.validateDatabase.errors);
        throw new Error(`Invalid preferences schema: ${errors}`);
      }

      this.cache = data;
      logger.info('User preferences loaded successfully');
      return data;
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === 'ENOENT') {
        // File doesn't exist, create default
        logger.warn('Preferences file not found, creating default');
        return this.createDefault();
      }
      logger.error('Failed to load user preferences:', error);
      throw error;
    }
  }

  /**
   * Save preferences to disk with atomic write and backup
   */
  async save(data: PreferencesDatabase): Promise<void> {
    // Validate before saving
    const valid = this.validateDatabase(data);
    if (!valid) {
      const errors = this.ajv.errorsText(this.validateDatabase.errors);
      throw new Error(`Cannot save invalid preferences: ${errors}`);
    }

    try {
      // Create backup of existing file
      if (fs.existsSync(this.filePath)) {
        await fs.promises.copyFile(this.filePath, this.backupPath);
      }

      // Atomic write: write to temp file, then rename
      const tempPath = `${this.filePath}.tmp`;
      const content = JSON.stringify(data, null, 2);
      await fs.promises.writeFile(tempPath, content, {
        encoding: 'utf-8',
        mode: 0o600, // Secure permissions
      });

      // Atomic rename
      await fs.promises.rename(tempPath, this.filePath);

      this.cache = data;
      logger.info('User preferences saved successfully');
    } catch (error) {
      logger.error('Failed to save user preferences:', error);

      // Restore from backup if available
      if (fs.existsSync(this.backupPath)) {
        try {
          await fs.promises.copyFile(this.backupPath, this.filePath);
          logger.info('Restored preferences from backup');
        } catch (restoreError) {
          logger.error('Failed to restore from backup:', restoreError);
        }
      }

      throw error;
    }
  }

  /**
   * Get user preferences (create if not exists)
   */
  async getUserPreferences(discordUserId: string): Promise<UserPreference> {
    const db = this.cache || (await this.load());

    if (db.users[discordUserId]) {
      return db.users[discordUserId];
    }

    // Create default preferences for new user
    const defaults = this.createUserDefaults(discordUserId);
    db.users[discordUserId] = defaults;
    await this.save(db);

    return defaults;
  }

  /**
   * Update user preferences
   */
  async updateUserPreferences(
    discordUserId: string,
    updates: Partial<Omit<UserPreference, 'discord_user_id' | 'updated_at'>>
  ): Promise<UserPreference> {
    const db = this.cache || (await this.load());
    const current = await this.getUserPreferences(discordUserId);

    // Merge updates
    const updated: UserPreference = {
      ...current,
      ...updates,
      discord_user_id: discordUserId,
      updated_at: new Date().toISOString(),
    };

    // Validate updated preferences
    const ajv = new Ajv();
    const validate = ajv.compile(userPreferenceSchema);
    if (!validate(updated)) {
      throw new Error(`Invalid preference update: ${ajv.errorsText(validate.errors)}`);
    }

    db.users[discordUserId] = updated;
    await this.save(db);

    return updated;
  }

  /**
   * Delete user preferences
   */
  async deleteUserPreferences(discordUserId: string): Promise<void> {
    const db = this.cache || (await this.load());

    if (db.users[discordUserId]) {
      delete db.users[discordUserId];
      await this.save(db);
      logger.info(`Deleted preferences for user ${discordUserId}`);
    }
  }

  /**
   * Create default preferences for new user
   */
  private createUserDefaults(discordUserId: string): UserPreference {
    const db = this.cache;
    if (!db) {
      throw new Error('Database not loaded');
    }

    return {
      discord_user_id: discordUserId,
      notifications: { ...db.defaults.notifications },
      notification_methods: { ...db.defaults.notification_methods },
      quiet_hours: { ...db.defaults.quiet_hours },
      updated_at: new Date().toISOString(),
    };
  }

  /**
   * Create default database
   */
  private async createDefault(): Promise<PreferencesDatabase> {
    const defaults: PreferencesDatabase = {
      users: {},
      defaults: {
        notifications: {
          issue_assigned: true,
          issue_mentioned: true,
          issue_completed: false,
          comment_added: false,
          sprint_started: true,
          sprint_completed: true,
          daily_digest: true,
        },
        notification_methods: {
          discord_dm: false,
          discord_mention: true,
        },
        quiet_hours: {
          enabled: false,
          start_hour: 22,
          end_hour: 8,
          timezone: 'UTC',
        },
      },
    };

    await this.save(defaults);
    return defaults;
  }
}

// Global instance
export const userPreferences = new UserPreferencesManager();
