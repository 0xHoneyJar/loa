/**
 * Shared types for the Loa persistence framework.
 *
 * All persistence components use these common error types and configuration interfaces.
 */

// ── Error Codes ──────────────────────────────────────────────

export type PersistenceErrorCode =
  | "WAL_CORRUPT"
  | "WAL_LOCK_FAILED"
  | "WAL_APPEND_FAILED"
  | "WAL_REPLAY_FAILED"
  | "WAL_COMPACTION_FAILED"
  | "CHECKPOINT_FAILED"
  | "CHECKPOINT_VERIFY_FAILED"
  | "CHECKPOINT_STALE_INTENT"
  | "RECOVERY_LOOP"
  | "RECOVERY_ALL_SOURCES_FAILED"
  | "RECOVERY_SIGNATURE_INVALID"
  | "RECOVERY_DEGRADED"
  | "CB_OPEN"
  | "CB_HALF_OPEN_REJECTED"
  | "IDENTITY_PARSE_FAILED"
  | "IDENTITY_WATCH_FAILED"
  | "LEARNING_STORE_CORRUPT"
  | "LEARNING_GATE_FAILED"
  | "BEADS_REPLAY_FAILED"
  | "BEADS_SHELL_ESCAPE"
  | "BEADS_WHITELIST_VIOLATION"
  | "DISK_PRESSURE_CRITICAL"
  | "LOCK_CONTENTION";

// ── Error Class ──────────────────────────────────────────────

export class PersistenceError extends Error {
  readonly code: PersistenceErrorCode;
  readonly cause?: Error;

  constructor(code: PersistenceErrorCode, message: string, cause?: Error) {
    super(message);
    this.name = "PersistenceError";
    this.code = code;
    this.cause = cause;
  }
}

// ── Common Config Interfaces ─────────────────────────────────

export interface RetryConfig {
  maxRetries: number;
  baseDelayMs: number;
  maxDelayMs: number;
}

export interface DiskPressureLevel {
  normal: number; // bytes threshold for normal operation
  warning: number; // bytes threshold for warning (trigger compaction)
  critical: number; // bytes threshold for critical (reject writes)
}

// ── Callback Types ───────────────────────────────────────────

export type StateChangeCallback<S extends string> = (
  from: S,
  to: S,
  context?: Record<string, unknown>,
) => void;

export type EventCallback = (event: string, data?: Record<string, unknown>) => void;
