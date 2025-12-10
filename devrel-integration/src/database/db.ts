/**
 * Database Connection Wrapper
 *
 * Implements HIGH-005: Immutable user-role mappings with SQLite backend.
 * Provides secure access to authentication and authorization database.
 */

import sqlite3 from 'sqlite3';
import { open, Database } from 'sqlite';
import path from 'path';
import fs from 'fs';
import { logger } from '../utils/logger';

export class AuthDatabase {
  private db: Database | null = null;
  private readonly dbPath: string;

  constructor() {
    this.dbPath = path.resolve(__dirname, '../../data/auth.db');
  }

  /**
   * Initialize database connection and schema
   */
  async initialize(): Promise<void> {
    try {
      const dbDir = path.dirname(this.dbPath);

      // Create data directory if it doesn't exist
      if (!fs.existsSync(dbDir)) {
        fs.mkdirSync(dbDir, { recursive: true, mode: 0o700 });
        logger.info('Created database directory', { path: dbDir });
      }

      // Verify directory permissions (should be 0700)
      const stats = fs.statSync(dbDir);
      const mode = stats.mode & parseInt('777', 8);
      if (mode !== parseInt('700', 8)) {
        logger.warn('Database directory has insecure permissions', {
          path: dbDir,
          mode: mode.toString(8),
          expected: '700'
        });
      }

      // Open database connection
      this.db = await open({
        filename: this.dbPath,
        driver: sqlite3.Database
      });

      logger.info('Database connection opened', { path: this.dbPath });

      // Enable foreign keys
      await this.db.exec('PRAGMA foreign_keys = ON;');

      // Enable WAL mode for better concurrency
      await this.db.exec('PRAGMA journal_mode = WAL;');

      // Run schema initialization
      await this.initializeSchema();

      logger.info('✅ Database initialized successfully');
    } catch (error) {
      logger.error('❌ Failed to initialize database', {
        error: error instanceof Error ? error.message : String(error)
      });
      throw new Error(`Database initialization failed: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  /**
   * Initialize database schema from schema.sql file
   */
  private async initializeSchema(): Promise<void> {
    const schemaPath = path.resolve(__dirname, './schema.sql');

    if (!fs.existsSync(schemaPath)) {
      throw new Error(`Schema file not found: ${schemaPath}`);
    }

    const schema = fs.readFileSync(schemaPath, 'utf8');
    await this.db!.exec(schema);

    logger.info('Database schema initialized');
  }

  /**
   * Get database connection (throws if not initialized)
   */
  getConnection(): Database {
    if (!this.db) {
      throw new Error('Database not initialized. Call initialize() first.');
    }
    return this.db;
  }

  /**
   * Close database connection
   */
  async close(): Promise<void> {
    if (this.db) {
      await this.db.close();
      this.db = null;
      logger.info('Database connection closed');
    }
  }

  /**
   * Check if database is initialized
   */
  isInitialized(): boolean {
    return this.db !== null;
  }

  /**
   * Run database health check
   */
  async healthCheck(): Promise<{ healthy: boolean; error?: string }> {
    try {
      if (!this.db) {
        return { healthy: false, error: 'Database not initialized' };
      }

      // Simple query to verify connection
      await this.db.get('SELECT 1 as test');

      return { healthy: true };
    } catch (error) {
      return {
        healthy: false,
        error: error instanceof Error ? error.message : String(error)
      };
    }
  }

  /**
   * Get database file path (for debugging/monitoring)
   */
  getDatabasePath(): string {
    return this.dbPath;
  }
}

// Singleton instance
export const authDb = new AuthDatabase();

// Graceful shutdown handler
process.on('SIGINT', async () => {
  logger.info('Closing database connection on SIGINT...');
  await authDb.close();
  process.exit(0);
});

process.on('SIGTERM', async () => {
  logger.info('Closing database connection on SIGTERM...');
  await authDb.close();
  process.exit(0);
});
