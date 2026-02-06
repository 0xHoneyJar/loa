/**
 * Recovery Source interface — pluggable sources for the recovery cascade.
 */

export interface IRecoverySource {
  /** Human-readable name for logging */
  readonly name: string;
  /** Check if this source is available for restore */
  isAvailable(): Promise<boolean>;
  /** Attempt to restore from this source. Returns file map or null on failure. */
  restore(): Promise<Map<string, Buffer> | null>;
}
