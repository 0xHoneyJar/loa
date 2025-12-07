import fs from 'fs';
import path from 'path';
import {
  readUserPreferences,
  writeUserPreferences,
  updateUserPreference,
  getUserPreference,
  deleteUserPreference,
  UserPreferencesData
} from '../dataIntegrity';

describe('Data Integrity', () => {
  const testDataDir = path.join(__dirname, '../../__tests__/test-data');
  const testPrefsFile = path.join(testDataDir, 'user-preferences.json');
  const testBackupDir = path.join(testDataDir, 'backups');

  beforeAll(() => {
    // Create test directories
    if (!fs.existsSync(testDataDir)) {
      fs.mkdirSync(testDataDir, { recursive: true });
    }
    if (!fs.existsSync(testBackupDir)) {
      fs.mkdirSync(testBackupDir, { recursive: true });
    }
  });

  afterAll(() => {
    // Clean up test directories
    if (fs.existsSync(testDataDir)) {
      fs.rmSync(testDataDir, { recursive: true, force: true });
    }
  });

  beforeEach(() => {
    // Clean up before each test
    if (fs.existsSync(testPrefsFile)) {
      fs.unlinkSync(testPrefsFile);
    }
    // Clean backups
    if (fs.existsSync(testBackupDir)) {
      fs.readdirSync(testBackupDir).forEach(file => {
        fs.unlinkSync(path.join(testBackupDir, file));
      });
    }
  });

  describe('writeUserPreferences', () => {
    it('should write valid preferences data', () => {
      const data: UserPreferencesData = {
        version: '1.0.0',
        users: {
          'user1': {
            userId: 'user1',
            notificationPreferences: {
              dailyDigest: true,
              mentionAlerts: true,
              statusUpdates: false
            },
            timezone: 'UTC',
            createdAt: new Date().toISOString(),
            updatedAt: new Date().toISOString()
          }
        }
      };

      expect(() => writeUserPreferences(data)).not.toThrow();
    });

    it('should reject invalid data structure', () => {
      const invalidData = {
        version: '1.0.0',
        users: {
          'user1': {
            userId: 'user1',
            // Missing required notificationPreferences
          }
        }
      } as any;

      expect(() => writeUserPreferences(invalidData))
        .toThrow('Invalid data structure');
    });

    it('should add checksum to written data', () => {
      const data: UserPreferencesData = {
        version: '1.0.0',
        users: {}
      };

      writeUserPreferences(data);

      const written = JSON.parse(fs.readFileSync(testPrefsFile, 'utf-8'));
      expect(written.checksum).toBeDefined();
      expect(typeof written.checksum).toBe('string');
      expect(written.checksum.length).toBe(64); // SHA256 hex length
    });

    it('should perform atomic write operation', () => {
      const data: UserPreferencesData = {
        version: '1.0.0',
        users: {}
      };

      writeUserPreferences(data);

      // Verify no temp file left behind
      expect(fs.existsSync(`${testPrefsFile}.tmp`)).toBe(false);
      // Verify actual file exists
      expect(fs.existsSync(testPrefsFile)).toBe(true);
    });
  });

  describe('readUserPreferences', () => {
    it('should read and validate preferences', () => {
      const data: UserPreferencesData = {
        version: '1.0.0',
        users: {
          'user1': {
            userId: 'user1',
            notificationPreferences: {
              dailyDigest: true,
              mentionAlerts: true,
              statusUpdates: false
            },
            createdAt: new Date().toISOString(),
            updatedAt: new Date().toISOString()
          }
        }
      };

      writeUserPreferences(data);
      const read = readUserPreferences();

      expect(read.version).toBe('1.0.0');
      expect(read.users['user1']).toBeDefined();
      expect(read.users['user1'].notificationPreferences.dailyDigest).toBe(true);
    });

    it('should verify checksum integrity', () => {
      const data: UserPreferencesData = {
        version: '1.0.0',
        users: {}
      };

      writeUserPreferences(data);

      // Tamper with file (change version but not checksum)
      const written = JSON.parse(fs.readFileSync(testPrefsFile, 'utf-8'));
      written.version = '2.0.0'; // Changed
      // Keep old checksum (integrity violation)
      fs.writeFileSync(testPrefsFile, JSON.stringify(written, null, 2));

      expect(() => readUserPreferences()).toThrow('Data integrity check failed');
    });

    it('should create empty structure if file missing', () => {
      const prefs = readUserPreferences();

      expect(prefs.version).toBe('1.0.0');
      expect(prefs.users).toEqual({});
    });
  });

  describe('updateUserPreference', () => {
    it('should create new user preference', () => {
      updateUserPreference('user1', {
        notificationPreferences: {
          dailyDigest: true,
          mentionAlerts: false,
          statusUpdates: true
        },
        timezone: 'America/New_York'
      });

      const pref = getUserPreference('user1');
      expect(pref).not.toBeNull();
      expect(pref?.userId).toBe('user1');
      expect(pref?.timezone).toBe('America/New_York');
      expect(pref?.notificationPreferences.dailyDigest).toBe(true);
    });

    it('should update existing user preference', () => {
      updateUserPreference('user1', {
        notificationPreferences: {
          dailyDigest: true,
          mentionAlerts: true,
          statusUpdates: true
        }
      });

      const before = getUserPreference('user1');
      expect(before?.notificationPreferences.dailyDigest).toBe(true);

      updateUserPreference('user1', {
        notificationPreferences: {
          dailyDigest: false,
          mentionAlerts: true,
          statusUpdates: true
        }
      });

      const after = getUserPreference('user1');
      expect(after?.notificationPreferences.dailyDigest).toBe(false);
      expect(after?.updatedAt).not.toBe(before?.updatedAt);
    });
  });

  describe('deleteUserPreference', () => {
    it('should delete user preference', () => {
      updateUserPreference('user1', {
        notificationPreferences: {
          dailyDigest: true,
          mentionAlerts: true,
          statusUpdates: true
        }
      });

      expect(getUserPreference('user1')).not.toBeNull();

      deleteUserPreference('user1');

      expect(getUserPreference('user1')).toBeNull();
    });

    it('should not throw when deleting non-existent user', () => {
      expect(() => deleteUserPreference('nonexistent')).not.toThrow();
    });
  });

  describe('Backup System', () => {
    it('should create backup before modifications', () => {
      const data: UserPreferencesData = {
        version: '1.0.0',
        users: {}
      };

      writeUserPreferences(data);

      // Second write should create backup
      writeUserPreferences(data);

      const backups = fs.readdirSync(testBackupDir);
      expect(backups.length).toBeGreaterThan(0);
      expect(backups[0]).toContain('user-preferences-');
    });

    it('should limit number of backups to 10', () => {
      const data: UserPreferencesData = {
        version: '1.0.0',
        users: {}
      };

      // Create 15 backups
      for (let i = 0; i < 15; i++) {
        writeUserPreferences(data);
        // Small delay to ensure different timestamps
        const delay = (ms: number) => new Promise(resolve => setTimeout(resolve, ms));
        delay(10);
      }

      const backups = fs.readdirSync(testBackupDir);
      expect(backups.length).toBeLessThanOrEqual(10);
    });
  });

  describe('Schema Validation', () => {
    it('should reject preferences with invalid date formats', () => {
      const invalidData = {
        version: '1.0.0',
        users: {
          'user1': {
            userId: 'user1',
            notificationPreferences: {
              dailyDigest: true,
              mentionAlerts: true,
              statusUpdates: true
            },
            createdAt: 'invalid-date',
            updatedAt: new Date().toISOString()
          }
        }
      } as any;

      expect(() => writeUserPreferences(invalidData))
        .toThrow('Invalid data structure');
    });

    it('should reject preferences with missing required fields', () => {
      const invalidData = {
        version: '1.0.0',
        users: {
          'user1': {
            userId: 'user1',
            notificationPreferences: {
              dailyDigest: true
              // Missing mentionAlerts and statusUpdates
            },
            createdAt: new Date().toISOString(),
            updatedAt: new Date().toISOString()
          }
        }
      } as any;

      expect(() => writeUserPreferences(invalidData))
        .toThrow('Invalid data structure');
    });
  });
});
