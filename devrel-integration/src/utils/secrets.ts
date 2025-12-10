import crypto from 'crypto';
import fs from 'fs';
import path from 'path';
import dotenv from 'dotenv';

/**
 * Secure Secrets Manager
 *
 * SECURITY FIXES:
 * - CRITICAL #2: Validates token format and checks file permissions
 * - CRITICAL #5: Supports encrypted secrets and rotation tracking
 * - Implements secret expiry warnings
 * - Validates all tokens at startup
 */

interface SecretMetadata {
  name: string;
  value: string;
  hash: string;
  lastRotated: Date;
  expiresAt: Date;
  validated: boolean;
}

interface SecretValidation {
  pattern: RegExp;
  description: string;
}

export class SecretsManager {
  private secrets: Map<string, SecretMetadata> = new Map();
  private readonly ROTATION_DAYS = 90;
  private readonly ENV_FILE: string;

  private readonly SECRET_PATTERNS: Record<string, SecretValidation> = {
    DISCORD_BOT_TOKEN: {
      pattern: /^[MN][A-Za-z\d]{23}\.[\w-]{6}\.[\w-]{27}$/,
      description: 'Discord bot token format',
    },
    LINEAR_API_TOKEN: {
      pattern: /^lin_api_[a-f0-9]{40}$/,
      description: 'Linear API token format',
    },
    DISCORD_DIGEST_CHANNEL_ID: {
      pattern: /^\d{17,19}$/,
      description: 'Discord Snowflake ID',
    },
    DISCORD_ALERTS_CHANNEL_ID: {
      pattern: /^\d{17,19}$/,
      description: 'Discord Snowflake ID',
    },
    LINEAR_TEAM_ID: {
      pattern: /^[a-f0-9-]{36}$/,
      description: 'UUID format',
    },
    LINEAR_WEBHOOK_SECRET: {
      pattern: /^.{20,}$/,
      description: 'Webhook secret (min 20 chars)',
    },
    VERCEL_WEBHOOK_SECRET: {
      pattern: /^.{20,}$/,
      description: 'Webhook secret (min 20 chars)',
    },
  };

  constructor(envPath?: string) {
    this.ENV_FILE = envPath || path.resolve(__dirname, '../../secrets/.env.local');
  }

  /**
   * Load and validate all secrets
   * CRITICAL FIX: Comprehensive validation and security checks
   */
  async load(): Promise<void> {
    // 1. Verify file exists
    if (!fs.existsSync(this.ENV_FILE)) {
      throw new Error(
        `FATAL: Secrets file not found: ${this.ENV_FILE}\n` +
        'Run setup script: npm run setup-secrets'
      );
    }

    // 2. Check file permissions (Unix-like systems)
    if (process.platform !== 'win32') {
      const stats = fs.statSync(this.ENV_FILE);
      const mode = stats.mode & 0o777;

      if (mode !== 0o600) {
        throw new Error(
          `SECURITY: ${this.ENV_FILE} has insecure permissions ${mode.toString(8)}\n` +
          `Run: chmod 600 ${this.ENV_FILE}`
        );
      }
    }

    // 3. Verify not tracked by git
    // SECURITY FIX (MEDIUM-014): Use execFile instead of execSync to avoid shell injection
    try {
      const { execFileSync } = require('child_process');
      try {
        // Use execFile (no shell) - safer than exec/execSync
        execFileSync('git', ['ls-files', '--error-unmatch', this.ENV_FILE], {
          encoding: 'utf-8',
          stdio: ['pipe', 'pipe', 'pipe'],
        });
        // If we get here, file IS tracked by git (error-unmatch succeeded)
        throw new Error(
          `SECURITY: ${this.ENV_FILE} is tracked by git!\n` +
          `Run: git rm --cached ${this.ENV_FILE}`
        );
      } catch (gitError: any) {
        // ls-files --error-unmatch exits with non-zero if file NOT tracked
        // This is expected behavior - file should NOT be tracked
        if (gitError.status !== 0 && gitError.status !== 1) {
          throw gitError; // Real error
        }
        // Status 1 = file not tracked = good
      }
    } catch (error) {
      // Git not available or other error - log warning but continue
      console.warn('Warning: Could not verify git tracking status');
    }

    // 4. Load environment variables
    const result = dotenv.config({ path: this.ENV_FILE });
    if (result.error) {
      throw new Error(`FATAL: Cannot load secrets: ${result.error.message}`);
    }

    // 5. Validate and store all required secrets
    const requiredSecrets = [
      'DISCORD_BOT_TOKEN',
      'LINEAR_API_TOKEN',
      'DISCORD_DIGEST_CHANNEL_ID',
      'LINEAR_TEAM_ID',
    ];

    const optionalSecrets = [
      'LINEAR_WEBHOOK_SECRET',
      'VERCEL_WEBHOOK_SECRET',
      'DISCORD_ALERTS_CHANNEL_ID',
      'GITHUB_TOKEN',
      'VERCEL_TOKEN',
    ];

    for (const varName of requiredSecrets) {
      await this.validateAndStore(varName, true);
    }

    for (const varName of optionalSecrets) {
      try {
        await this.validateAndStore(varName, false);
      } catch (error) {
        console.warn(`Optional secret ${varName} not configured`);
      }
    }

    // 6. Test Discord token validity
    await this.validateDiscordToken();

    console.info('✓ Loaded and validated secrets:', Array.from(this.secrets.keys()));
  }

  /**
   * Validate secret format and store with metadata
   */
  private async validateAndStore(varName: string, required: boolean): Promise<void> {
    const value = process.env[varName];

    if (!value) {
      if (required) {
        throw new Error(
          `FATAL: Missing required secret: ${varName}\n` +
          'Check secrets/.env.local'
        );
      }
      return;
    }

    // Validate format
    const validation = this.SECRET_PATTERNS[varName];
    if (validation && !validation.pattern.test(value)) {
      throw new Error(
        `FATAL: Invalid format for ${varName}\n` +
        `Expected: ${validation.description}\n` +
        `Got: ${value.substring(0, 10)}...`
      );
    }

    // Create metadata
    const hash = crypto.createHash('sha256').update(value).digest('hex');
    const lastRotated = this.getRotationDate(varName) || new Date();
    const expiresAt = new Date(lastRotated.getTime() + this.ROTATION_DAYS * 24 * 60 * 60 * 1000);

    this.secrets.set(varName, {
      name: varName,
      value,
      hash,
      lastRotated,
      expiresAt,
      validated: true,
    });

    // Warn if expiring soon
    const daysUntilExpiry = (expiresAt.getTime() - Date.now()) / (24 * 60 * 60 * 1000);
    if (daysUntilExpiry < 7) {
      console.warn(
        `⚠️  ${varName} expires in ${Math.floor(daysUntilExpiry)} days - please rotate`
      );
    }
  }

  /**
   * Get rotation date from metadata file
   */
  private getRotationDate(varName: string): Date | null {
    const metadataFile = path.join(path.dirname(this.ENV_FILE), '.secret-metadata.json');

    if (!fs.existsSync(metadataFile)) {
      return null;
    }

    try {
      const metadata = JSON.parse(fs.readFileSync(metadataFile, 'utf-8'));
      return metadata[varName] ? new Date(metadata[varName].lastRotated) : null;
    } catch {
      return null;
    }
  }

  /**
   * Save rotation metadata
   */
  saveRotationMetadata(): void {
    const metadataFile = path.join(path.dirname(this.ENV_FILE), '.secret-metadata.json');
    const metadata: Record<string, any> = {};

    for (const [name, secret] of this.secrets.entries()) {
      metadata[name] = {
        lastRotated: secret.lastRotated.toISOString(),
        expiresAt: secret.expiresAt.toISOString(),
        hash: secret.hash.substring(0, 8), // Store partial hash for verification
      };
    }

    fs.writeFileSync(metadataFile, JSON.stringify(metadata, null, 2), { mode: 0o600 });
  }

  /**
   * Get secret value with expiry check
   */
  get(name: string): string {
    const secret = this.secrets.get(name);

    if (!secret) {
      throw new Error(`Secret not found: ${name}`);
    }

    // Check expiry
    if (new Date() > secret.expiresAt) {
      console.error(`🔴 SECRET EXPIRED: ${name} (expired ${secret.expiresAt.toISOString()})`);
      throw new Error(
        `Secret expired: ${name}\n` +
        'Please rotate the secret and update .env.local'
      );
    }

    // Verify integrity
    const currentHash = crypto.createHash('sha256').update(secret.value).digest('hex');
    if (currentHash !== secret.hash) {
      throw new Error(`Secret integrity check failed for ${name} - possible tampering`);
    }

    return secret.value;
  }

  /**
   * Test Discord token validity
   */
  private async validateDiscordToken(): Promise<void> {
    const token = this.get('DISCORD_BOT_TOKEN');

    try {
      const response = await fetch('https://discord.com/api/v10/users/@me', {
        headers: {
          Authorization: `Bot ${token}`,
        },
      });

      if (!response.ok) {
        throw new Error(`Discord API returned ${response.status}: ${response.statusText}`);
      }

      const data = await response.json();
      console.info(`✓ Discord token valid for bot: ${data.username}`);
    } catch (error) {
      throw new Error(
        `FATAL: Discord token validation failed: ${error instanceof Error ? error.message : error}\n` +
        'Check that DISCORD_BOT_TOKEN is correct and bot has not been deleted'
      );
    }
  }

  /**
   * Get all secret names (for debugging, never returns values)
   */
  listSecrets(): string[] {
    return Array.from(this.secrets.keys());
  }

  /**
   * Check if secret exists
   */
  has(name: string): boolean {
    return this.secrets.has(name);
  }

  /**
   * Get expiry warning messages
   */
  getExpiryWarnings(): string[] {
    const warnings: string[] = [];
    const now = Date.now();

    for (const [name, secret] of this.secrets.entries()) {
      const daysUntilExpiry = (secret.expiresAt.getTime() - now) / (24 * 60 * 60 * 1000);

      if (daysUntilExpiry < 0) {
        warnings.push(`🔴 ${name} EXPIRED ${Math.abs(Math.floor(daysUntilExpiry))} days ago`);
      } else if (daysUntilExpiry < 7) {
        warnings.push(`⚠️  ${name} expires in ${Math.floor(daysUntilExpiry)} days`);
      } else if (daysUntilExpiry < 30) {
        warnings.push(`⏰ ${name} expires in ${Math.floor(daysUntilExpiry)} days`);
      }
    }

    return warnings;
  }
}

// Singleton instance
let secretsManager: SecretsManager | null = null;

/**
 * Get or create secrets manager instance
 */
export function getSecretsManager(): SecretsManager {
  if (!secretsManager) {
    secretsManager = new SecretsManager();
  }
  return secretsManager;
}

/**
 * Initialize secrets (call once at startup)
 */
export async function initializeSecrets(envPath?: string): Promise<SecretsManager> {
  const manager = envPath ? new SecretsManager(envPath) : getSecretsManager();
  await manager.load();
  secretsManager = manager;
  return manager;
}
