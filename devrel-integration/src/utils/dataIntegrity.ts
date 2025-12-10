import fs from 'fs';
import path from 'path';
import crypto from 'crypto';
import { logger } from './logger';

/**
 * Data Integrity Utilities
 *
 * SECURITY FIX: MEDIUM #13
 * - JSON schema validation for user preferences
 * - Atomic writes to prevent corruption
 * - Data backups before modifications
 * - Integrity checksums
 */

export interface UserPreference {
  userId: string;
  notificationPreferences: {
    dailyDigest: boolean;
    mentionAlerts: boolean;
    statusUpdates: boolean;
  };
  timezone?: string;
  createdAt: string;
  updatedAt: string;
}

export interface UserPreferencesData {
  version: string;
  users: Record<string, UserPreference>;
  checksum?: string;
}

const PREFERENCES_FILE = path.join(__dirname, '../../data/user-preferences.json');
const BACKUP_DIR = path.join(__dirname, '../../data/backups');

/**
 * Ensure data directory and backups exist
 */
function ensureDataDirectories(): void {
  const dataDir = path.dirname(PREFERENCES_FILE);

  if (!fs.existsSync(dataDir)) {
    fs.mkdirSync(dataDir, { recursive: true, mode: 0o700 });
  }

  if (!fs.existsSync(BACKUP_DIR)) {
    fs.mkdirSync(BACKUP_DIR, { recursive: true, mode: 0o700 });
  }
}

/**
 * Calculate checksum for data integrity
 */
function calculateChecksum(data: string): string {
  return crypto.createHash('sha256').update(data).digest('hex');
}

/**
 * Validate user preference object structure
 */
function validateUserPreference(pref: any): pref is UserPreference {
  if (!pref || typeof pref !== 'object') return false;
  if (typeof pref.userId !== 'string') return false;
  if (!pref.notificationPreferences || typeof pref.notificationPreferences !== 'object') return false;
  if (typeof pref.notificationPreferences.dailyDigest !== 'boolean') return false;
  if (typeof pref.notificationPreferences.mentionAlerts !== 'boolean') return false;
  if (typeof pref.notificationPreferences.statusUpdates !== 'boolean') return false;
  if (typeof pref.createdAt !== 'string') return false;
  if (typeof pref.updatedAt !== 'string') return false;

  // Validate date formats
  if (isNaN(Date.parse(pref.createdAt))) return false;
  if (isNaN(Date.parse(pref.updatedAt))) return false;

  return true;
}

/**
 * Validate preferences data structure
 */
function validatePreferencesData(data: any): data is UserPreferencesData {
  if (!data || typeof data !== 'object') return false;
  if (typeof data.version !== 'string') return false;
  if (!data.users || typeof data.users !== 'object') return false;

  // Validate each user preference
  for (const [userId, pref] of Object.entries(data.users)) {
    if (!validateUserPreference(pref)) {
      logger.error(`Invalid user preference for ${userId}`);
      return false;
    }
  }

  return true;
}

/**
 * Create backup of preferences file
 */
function createBackup(): void {
  ensureDataDirectories();

  if (!fs.existsSync(PREFERENCES_FILE)) {
    return; // No file to backup
  }

  const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
  const backupFile = path.join(BACKUP_DIR, `user-preferences-${timestamp}.json`);

  try {
    fs.copyFileSync(PREFERENCES_FILE, backupFile);
    logger.info(`Created backup: ${backupFile}`);

    // Keep only last 10 backups
    const backups = fs.readdirSync(BACKUP_DIR)
      .filter(f => f.startsWith('user-preferences-'))
      .sort()
      .reverse();

    if (backups.length > 10) {
      backups.slice(10).forEach(backup => {
        const oldBackupPath = path.join(BACKUP_DIR, backup);
        fs.unlinkSync(oldBackupPath);
        logger.info(`Deleted old backup: ${backup}`);
      });
    }
  } catch (error) {
    logger.error('Failed to create backup:', error);
  }
}

/**
 * Read user preferences with integrity checks
 */
export function readUserPreferences(): UserPreferencesData {
  ensureDataDirectories();

  // Initialize if doesn't exist
  if (!fs.existsSync(PREFERENCES_FILE)) {
    const initialData: UserPreferencesData = {
      version: '1.0.0',
      users: {},
    };
    writeUserPreferences(initialData);
    return initialData;
  }

  try {
    const content = fs.readFileSync(PREFERENCES_FILE, 'utf-8');
    const data = JSON.parse(content) as UserPreferencesData;

    // Validate structure
    if (!validatePreferencesData(data)) {
      throw new Error('Invalid preferences data structure');
    }

    // Verify checksum if present
    if (data.checksum) {
      const dataWithoutChecksum = { ...data };
      delete dataWithoutChecksum.checksum;
      const dataString = JSON.stringify(dataWithoutChecksum, null, 2);
      const calculatedChecksum = calculateChecksum(dataString);

      if (calculatedChecksum !== data.checksum) {
        logger.error('Checksum mismatch - data may be corrupted');
        throw new Error('Data integrity check failed');
      }
    }

    return data;
  } catch (error) {
    logger.error('Failed to read user preferences:', error);

    // Try to restore from backup
    const backups = fs.readdirSync(BACKUP_DIR)
      .filter(f => f.startsWith('user-preferences-'))
      .sort()
      .reverse();

    if (backups.length > 0) {
      const latestBackup = backups[0]!;
      logger.warn(`Attempting to restore from backup: ${latestBackup}`);
      const backupPath = path.join(BACKUP_DIR, latestBackup);
      const backupContent = fs.readFileSync(backupPath, 'utf-8');
      const backupData = JSON.parse(backupContent) as UserPreferencesData;

      if (validatePreferencesData(backupData)) {
        logger.info('Successfully restored from backup');
        writeUserPreferences(backupData);
        return backupData;
      }
    }

    // Last resort: return empty structure
    logger.error('Could not restore data, returning empty structure');
    return {
      version: '1.0.0',
      users: {},
    };
  }
}

/**
 * Write user preferences with atomic operation and integrity checks
 */
export function writeUserPreferences(data: UserPreferencesData): void {
  ensureDataDirectories();

  // Validate before writing
  if (!validatePreferencesData(data)) {
    throw new Error('Invalid data structure - refusing to write');
  }

  // Create backup before modifying
  createBackup();

  try {
    // Add checksum
    const dataWithoutChecksum = { ...data };
    delete dataWithoutChecksum.checksum;
    const dataString = JSON.stringify(dataWithoutChecksum, null, 2);
    const checksum = calculateChecksum(dataString);

    const dataWithChecksum: UserPreferencesData = {
      ...data,
      checksum,
    };

    // Atomic write: write to temp file, then rename
    const tempFile = `${PREFERENCES_FILE}.tmp`;
    fs.writeFileSync(tempFile, JSON.stringify(dataWithChecksum, null, 2), {
      encoding: 'utf-8',
      mode: 0o600,
    });

    // Atomic rename
    fs.renameSync(tempFile, PREFERENCES_FILE);

    logger.info('User preferences saved successfully');
  } catch (error) {
    logger.error('Failed to write user preferences:', error);
    throw error;
  }
}

/**
 * Update single user preference
 */
export function updateUserPreference(
  userId: string,
  updates: Partial<Omit<UserPreference, 'userId' | 'createdAt'>>
): void {
  const data = readUserPreferences();

  const existing = data.users[userId];
  const now = new Date().toISOString();

  if (existing) {
    // Update existing
    data.users[userId] = {
      ...existing,
      ...updates,
      userId,
      updatedAt: now,
    };
  } else {
    // Create new
    data.users[userId] = {
      userId,
      notificationPreferences: {
        dailyDigest: true,
        mentionAlerts: true,
        statusUpdates: true,
      },
      ...updates,
      createdAt: now,
      updatedAt: now,
    };
  }

  writeUserPreferences(data);
}

/**
 * Delete user preference
 */
export function deleteUserPreference(userId: string): void {
  const data = readUserPreferences();

  if (data.users[userId]) {
    delete data.users[userId];
    writeUserPreferences(data);
    logger.info(`Deleted preferences for user ${userId}`);
  }
}

/**
 * Get user preference
 */
export function getUserPreference(userId: string): UserPreference | null {
  const data = readUserPreferences();
  return data.users[userId] || null;
}
