/**
 * MFA Verifier
 *
 * Implements HIGH-005: Multi-Factor Authentication for sensitive operations.
 * Provides TOTP (Time-based One-Time Password) enrollment and verification.
 *
 * Security Features:
 * - TOTP-based MFA (Google Authenticator, Authy, etc.)
 * - Backup codes for account recovery
 * - Rate limiting on verification attempts
 * - Complete audit logging of MFA challenges
 */

import speakeasy from 'speakeasy';
import qrcode from 'qrcode';
import bcrypt from 'bcryptjs';
import { authDb } from '../database/db';
import { logger, auditLog } from '../utils/logger';
import userMappingService from './user-mapping-service';

export interface MfaEnrollment {
  id: number;
  userId: number;
  mfaType: 'totp' | 'sms' | 'email';
  totpSecret?: string;
  backupCodes?: string;
  status: 'pending' | 'active' | 'disabled';
  verifiedAt?: string;
  lastUsedAt?: string;
  enrolledAt: string;
  createdAt: string;
  updatedAt: string;
}

export interface MfaChallenge {
  id: number;
  userId: number;
  challengeType: 'totp' | 'backup_code' | 'sms' | 'email';
  operation: string;
  operationContext?: string;
  success: boolean;
  failureReason?: string;
  ipAddress?: string;
  userAgent?: string;
  challengedAt: string;
}

export interface EnrollmentResult {
  secret: string;
  qrCodeUrl: string;
  backupCodes: string[];
}

export interface VerificationResult {
  success: boolean;
  challengeId: number;
  failureReason?: string;
}

/**
 * Rate limiting for MFA attempts
 */
interface RateLimitEntry {
  attempts: number;
  resetAt: number;
}

const mfaRateLimits = new Map<string, RateLimitEntry>();
const MAX_ATTEMPTS = 5;
const RATE_LIMIT_WINDOW_MS = 15 * 60 * 1000; // 15 minutes

/**
 * Mapping functions to convert snake_case database columns to camelCase TypeScript
 */

function mapMfaEnrollment(row: any): MfaEnrollment {
  return {
    id: row.id,
    userId: row.user_id,
    mfaType: row.mfa_type,
    totpSecret: row.totp_secret,
    backupCodes: row.backup_codes,
    status: row.status,
    verifiedAt: row.verified_at,
    lastUsedAt: row.last_used_at,
    enrolledAt: row.enrolled_at,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function mapMfaChallenge(row: any): MfaChallenge {
  return {
    id: row.id,
    userId: row.user_id,
    challengeType: row.challenge_type,
    operation: row.operation,
    operationContext: row.operation_context,
    success: row.success === 1,
    failureReason: row.failure_reason,
    ipAddress: row.ip_address,
    userAgent: row.user_agent,
    challengedAt: row.challenged_at,
  };
}

export class MfaVerifier {
  /**
   * Enroll user in MFA (generates TOTP secret and backup codes)
   */
  async enrollMfa(discordUserId: string): Promise<EnrollmentResult> {
    const db = authDb.getConnection();
    const now = new Date().toISOString();

    // Get user
    const user = await userMappingService.getUserByDiscordId(discordUserId);
    if (!user) {
      throw new Error('User not found');
    }

    // Check if already enrolled
    const existingRow = await db.get(
      'SELECT * FROM mfa_enrollments WHERE user_id = ?',
      user.id
    );

    if (existingRow) {
      const existingEnrollment = mapMfaEnrollment(existingRow);
      if (existingEnrollment.status === 'active') {
        throw new Error('User already enrolled in MFA');
      }
    }

    // Generate TOTP secret
    const secret = speakeasy.generateSecret({
      name: `Agentic-Base (${user.discordUsername})`,
      issuer: 'Agentic-Base',
      length: 32
    });

    // Generate backup codes
    const backupCodes = this.generateBackupCodes(10);
    const hashedBackupCodes = await Promise.all(
      backupCodes.map(code => bcrypt.hash(code, 10))
    );

    // Generate QR code
    const qrCodeUrl = await qrcode.toDataURL(secret.otpauth_url!);

    // Store enrollment (pending until verified)
    if (existingRow) {
      // Update existing pending enrollment
      await db.run(
        `UPDATE mfa_enrollments
         SET totp_secret = ?, backup_codes = ?, status = ?, updated_at = ?
         WHERE user_id = ?`,
        secret.base32,
        JSON.stringify(hashedBackupCodes),
        'pending',
        now,
        user.id
      );
    } else {
      // Create new enrollment
      await db.run(
        `INSERT INTO mfa_enrollments (
          user_id, mfa_type, totp_secret, backup_codes, status,
          enrolled_at, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
        user.id,
        'totp',
        secret.base32,
        JSON.stringify(hashedBackupCodes),
        'pending',
        now,
        now,
        now
      );
    }

    logger.info('MFA enrollment initiated', {
      userId: user.id,
      discordUserId: user.discordUserId
    });

    return {
      secret: secret.base32!,
      qrCodeUrl,
      backupCodes
    };
  }

  /**
   * Verify TOTP code and activate MFA enrollment
   */
  async verifyEnrollment(discordUserId: string, totpCode: string): Promise<boolean> {
    const db = authDb.getConnection();
    const now = new Date().toISOString();

    // Get user
    const user = await userMappingService.getUserByDiscordId(discordUserId);
    if (!user) {
      throw new Error('User not found');
    }

    // Get pending enrollment
    const enrollmentRow = await db.get(
      'SELECT * FROM mfa_enrollments WHERE user_id = ? AND status = ?',
      user.id,
      'pending'
    );

    if (!enrollmentRow) {
      throw new Error('No pending MFA enrollment found');
    }

    const enrollment = mapMfaEnrollment(enrollmentRow);

    // Verify TOTP code
    const verified = speakeasy.totp.verify({
      secret: enrollment.totpSecret!,
      encoding: 'base32',
      token: totpCode,
      window: 2 // Allow 2 time steps before/after for clock skew
    });

    if (!verified) {
      logger.warn('MFA enrollment verification failed', {
        userId: user.id,
        discordUserId: user.discordUserId
      });
      return false;
    }

    // Activate enrollment
    await db.run(
      `UPDATE mfa_enrollments
       SET status = ?, verified_at = ?, updated_at = ?
       WHERE user_id = ?`,
      'active',
      now,
      now,
      user.id
    );

    logger.info('MFA enrollment verified and activated', {
      userId: user.id,
      discordUserId: user.discordUserId
    });

    auditLog.command(
      discordUserId,
      user.discordUsername,
      'mfa_enrollment_verified',
      []
    );

    return true;
  }

  /**
   * Verify TOTP code for authentication
   */
  async verifyTotp(
    discordUserId: string,
    totpCode: string,
    operation: {
      operation: string;
      context?: Record<string, any>;
      ipAddress?: string;
      userAgent?: string;
    }
  ): Promise<VerificationResult> {
    const db = authDb.getConnection();
    const now = new Date().toISOString();

    // Get user
    const user = await userMappingService.getUserByDiscordId(discordUserId);
    if (!user) {
      return this.logFailedChallenge(
        0,
        'totp',
        operation,
        'User not found'
      );
    }

    // Check rate limit
    const rateLimitCheck = this.checkRateLimit(discordUserId);
    if (!rateLimitCheck.allowed) {
      return this.logFailedChallenge(
        user.id,
        'totp',
        operation,
        `Rate limit exceeded. Try again in ${Math.ceil(rateLimitCheck.resetIn / 60)} minutes.`
      );
    }

    // Get active MFA enrollment
    const enrollmentRow = await db.get(
      'SELECT * FROM mfa_enrollments WHERE user_id = ? AND status = ?',
      user.id,
      'active'
    );

    if (!enrollmentRow) {
      return this.logFailedChallenge(
        user.id,
        'totp',
        operation,
        'MFA not enrolled or not active'
      );
    }

    const enrollment = mapMfaEnrollment(enrollmentRow);

    // Verify TOTP code
    const verified = speakeasy.totp.verify({
      secret: enrollment.totpSecret!,
      encoding: 'base32',
      token: totpCode,
      window: 2
    });

    if (!verified) {
      this.incrementRateLimit(discordUserId);
      return this.logFailedChallenge(
        user.id,
        'totp',
        operation,
        'Invalid TOTP code'
      );
    }

    // Success - update last used timestamp
    await db.run(
      'UPDATE mfa_enrollments SET last_used_at = ?, updated_at = ? WHERE user_id = ?',
      now,
      now,
      user.id
    );

    // Reset rate limit on success
    this.resetRateLimit(discordUserId);

    // Log successful challenge
    const challengeId = await this.logSuccessfulChallenge(
      user.id,
      'totp',
      operation
    );

    logger.info('MFA verification successful', {
      userId: user.id,
      discordUserId: user.discordUserId,
      operation: operation.operation
    });

    return {
      success: true,
      challengeId
    };
  }

  /**
   * Verify backup code for authentication
   */
  async verifyBackupCode(
    discordUserId: string,
    backupCode: string,
    operation: {
      operation: string;
      context?: Record<string, any>;
      ipAddress?: string;
      userAgent?: string;
    }
  ): Promise<VerificationResult> {
    const db = authDb.getConnection();
    const now = new Date().toISOString();

    // Get user
    const user = await userMappingService.getUserByDiscordId(discordUserId);
    if (!user) {
      return this.logFailedChallenge(
        0,
        'backup_code',
        operation,
        'User not found'
      );
    }

    // Check rate limit
    const rateLimitCheck = this.checkRateLimit(discordUserId);
    if (!rateLimitCheck.allowed) {
      return this.logFailedChallenge(
        user.id,
        'backup_code',
        operation,
        `Rate limit exceeded. Try again in ${Math.ceil(rateLimitCheck.resetIn / 60)} minutes.`
      );
    }

    // Get active MFA enrollment
    const enrollmentRow = await db.get(
      'SELECT * FROM mfa_enrollments WHERE user_id = ? AND status = ?',
      user.id,
      'active'
    );

    if (!enrollmentRow) {
      return this.logFailedChallenge(
        user.id,
        'backup_code',
        operation,
        'MFA not enrolled or backup codes not available'
      );
    }

    const enrollment = mapMfaEnrollment(enrollmentRow);

    if (!enrollment.backupCodes) {
      return this.logFailedChallenge(
        user.id,
        'backup_code',
        operation,
        'MFA not enrolled or backup codes not available'
      );
    }

    // Parse backup codes
    const hashedBackupCodes: string[] = JSON.parse(enrollment.backupCodes);

    // Check if backup code matches any hashed code
    let matchIndex = -1;
    for (let i = 0; i < hashedBackupCodes.length; i++) {
      const matches = await bcrypt.compare(backupCode, hashedBackupCodes[i]!);
      if (matches) {
        matchIndex = i;
        break;
      }
    }

    if (matchIndex === -1) {
      this.incrementRateLimit(discordUserId);
      return this.logFailedChallenge(
        user.id,
        'backup_code',
        operation,
        'Invalid backup code'
      );
    }

    // Remove used backup code
    hashedBackupCodes.splice(matchIndex, 1);
    await db.run(
      'UPDATE mfa_enrollments SET backup_codes = ?, last_used_at = ?, updated_at = ? WHERE user_id = ?',
      JSON.stringify(hashedBackupCodes),
      now,
      now,
      user.id
    );

    // Reset rate limit on success
    this.resetRateLimit(discordUserId);

    // Log successful challenge
    const challengeId = await this.logSuccessfulChallenge(
      user.id,
      'backup_code',
      operation
    );

    logger.info('MFA verification successful (backup code)', {
      userId: user.id,
      discordUserId: user.discordUserId,
      operation: operation.operation,
      remainingBackupCodes: hashedBackupCodes.length
    });

    // Warn if running low on backup codes
    if (hashedBackupCodes.length <= 2) {
      logger.warn('User running low on backup codes', {
        userId: user.id,
        discordUserId: user.discordUserId,
        remainingCodes: hashedBackupCodes.length
      });
    }

    return {
      success: true,
      challengeId
    };
  }

  /**
   * Check if user has MFA enabled
   */
  async isMfaEnabled(discordUserId: string): Promise<boolean> {
    const db = authDb.getConnection();

    const user = await userMappingService.getUserByDiscordId(discordUserId);
    if (!user) {
      return false;
    }

    const enrollmentRow = await db.get(
      'SELECT * FROM mfa_enrollments WHERE user_id = ? AND status = ?',
      user.id,
      'active'
    );

    return !!enrollmentRow;
  }

  /**
   * Disable MFA for user (admin only)
   */
  async disableMfa(
    discordUserId: string,
    disabledBy: {
      discordUserId: string;
      discordUsername: string;
      reason: string;
    }
  ): Promise<void> {
    const db = authDb.getConnection();
    const now = new Date().toISOString();

    const user = await userMappingService.getUserByDiscordId(discordUserId);
    if (!user) {
      throw new Error('User not found');
    }

    await db.run(
      'UPDATE mfa_enrollments SET status = ?, updated_at = ? WHERE user_id = ?',
      'disabled',
      now,
      user.id
    );

    logger.info('MFA disabled', {
      userId: user.id,
      discordUserId: user.discordUserId,
      disabledByDiscordId: disabledBy.discordUserId,
      reason: disabledBy.reason
    });

    auditLog.command(
      disabledBy.discordUserId,
      disabledBy.discordUsername,
      'mfa_disabled',
      [discordUserId, disabledBy.reason || 'no reason provided']
    );
  }

  /**
   * Generate backup codes
   */
  private generateBackupCodes(count: number): string[] {
    const codes: string[] = [];
    for (let i = 0; i < count; i++) {
      // Generate 8-character alphanumeric code
      const code = Array.from({ length: 8 }, () =>
        '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ'[Math.floor(Math.random() * 36)]
      ).join('');
      codes.push(code);
    }
    return codes;
  }

  /**
   * Rate limiting check
   */
  private checkRateLimit(discordUserId: string): { allowed: boolean; resetIn: number } {
    const now = Date.now();
    const entry = mfaRateLimits.get(discordUserId);

    if (!entry || entry.resetAt <= now) {
      return { allowed: true, resetIn: 0 };
    }

    if (entry.attempts >= MAX_ATTEMPTS) {
      return { allowed: false, resetIn: entry.resetAt - now };
    }

    return { allowed: true, resetIn: 0 };
  }

  /**
   * Increment rate limit counter
   */
  private incrementRateLimit(discordUserId: string): void {
    const now = Date.now();
    const entry = mfaRateLimits.get(discordUserId);

    if (!entry || entry.resetAt <= now) {
      mfaRateLimits.set(discordUserId, {
        attempts: 1,
        resetAt: now + RATE_LIMIT_WINDOW_MS
      });
    } else {
      entry.attempts++;
    }
  }

  /**
   * Reset rate limit counter
   */
  private resetRateLimit(discordUserId: string): void {
    mfaRateLimits.delete(discordUserId);
  }

  /**
   * Log successful MFA challenge
   */
  private async logSuccessfulChallenge(
    userId: number,
    challengeType: 'totp' | 'backup_code',
    operation: {
      operation: string;
      context?: Record<string, any>;
      ipAddress?: string;
      userAgent?: string;
    }
  ): Promise<number> {
    const db = authDb.getConnection();
    const now = new Date().toISOString();

    const result = await db.run(
      `INSERT INTO mfa_challenges (
        user_id, challenge_type, operation, operation_context,
        success, ip_address, user_agent, challenged_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
      userId,
      challengeType,
      operation.operation,
      operation.context ? JSON.stringify(operation.context) : null,
      1,
      operation.ipAddress || null,
      operation.userAgent || null,
      now
    );

    return result.lastID!;
  }

  /**
   * Log failed MFA challenge
   */
  private async logFailedChallenge(
    userId: number,
    challengeType: 'totp' | 'backup_code',
    operation: {
      operation: string;
      context?: Record<string, any>;
      ipAddress?: string;
      userAgent?: string;
    },
    failureReason: string
  ): Promise<VerificationResult> {
    const db = authDb.getConnection();
    const now = new Date().toISOString();

    const result = await db.run(
      `INSERT INTO mfa_challenges (
        user_id, challenge_type, operation, operation_context,
        success, failure_reason, ip_address, user_agent, challenged_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      userId,
      challengeType,
      operation.operation,
      operation.context ? JSON.stringify(operation.context) : null,
      0,
      failureReason,
      operation.ipAddress || null,
      operation.userAgent || null,
      now
    );

    return {
      success: false,
      challengeId: result.lastID!,
      failureReason
    };
  }

  /**
   * Get MFA challenge history for user
   */
  async getChallengeHistory(
    discordUserId: string,
    limit: number = 50
  ): Promise<MfaChallenge[]> {
    const db = authDb.getConnection();

    const user = await userMappingService.getUserByDiscordId(discordUserId);
    if (!user) {
      return [];
    }

    const rows = await db.all(
      `SELECT * FROM mfa_challenges
       WHERE user_id = ?
       ORDER BY challenged_at DESC
       LIMIT ?`,
      user.id,
      limit
    );

    return rows.map(mapMfaChallenge);
  }
}

export default new MfaVerifier();
