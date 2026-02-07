/**
 * LoaLibError — shared base error class for all .claude/lib/ modules.
 *
 * Each module defines its own error codes using this base class:
 *   SEC_001..099  security/
 *   MEM_001..099  memory/
 *   SCH_001..099  scheduler/
 *   BRG_001..099  bridge/
 *   SYN_001..099  sync/
 *
 * Convention: {PREFIX}_{NNN} (e.g., SEC_001, BRG_002)
 */
export class LoaLibError extends Error {
  constructor(
    message: string,
    public readonly code: string,
    public readonly retryable: boolean,
    public readonly cause?: Error,
  ) {
    super(message);
    this.name = "LoaLibError";
  }

  toJSON(): Record<string, unknown> {
    return {
      name: this.name,
      message: this.message,
      code: this.code,
      retryable: this.retryable,
      cause: this.cause
        ? { name: this.cause.name, message: this.cause.message }
        : undefined,
    };
  }
}
