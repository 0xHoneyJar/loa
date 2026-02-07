/**
 * Recovery Cascade — boot-time multi-source recovery with priority ordering.
 *
 * Sources are tried in priority order (lower = first), each with a per-source
 * timeout that is capped by the remaining total budget. Validation ensures the
 * restored data is usable. Per SDD Section 4.5.1.
 */
import { LoaLibError } from "../errors.js";

// ── Types ────────────────────────────────────────────

export interface IRecoverySource {
  /** Human-readable name for logging */
  name: string;
  /** Lower number = tried first */
  priority: number;
  /** Quick check: is this source available at all? */
  isAvailable(): Promise<boolean>;
  /** Attempt to restore data from this source */
  restore(): Promise<unknown>;
  /** Optional validation of restored data. Default: always valid */
  validate?(data: unknown): Promise<boolean>;
}

export interface RecoveryAttempt {
  source: string;
  success: boolean;
  durationMs: number;
  error?: string;
}

export interface RecoveryResult {
  sourceUsed: string;
  data: unknown;
  attempts: RecoveryAttempt[];
  totalDurationMs: number;
}

export interface RecoveryCascadeConfig {
  /** Per-source timeout in ms. Default: 10_000 */
  perSourceTimeoutMs?: number;
  /** Total budget for all sources in ms. Default: 30_000 */
  totalBudgetMs?: number;
  /** Injectable clock. Default: Date.now */
  now?: () => number;
}

// ── Helpers ──────────────────────────────────────────

function raceTimeout<T>(
  promise: Promise<T>,
  ms: number,
  label: string,
): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const timer = setTimeout(
      () => reject(new Error(`${label} timed out after ${ms}ms`)),
      ms,
    );
    promise.then(
      (v) => { clearTimeout(timer); resolve(v); },
      (e) => { clearTimeout(timer); reject(e); },
    );
  });
}

// ── Implementation ───────────────────────────────────

export class RecoveryCascade {
  private readonly sources: IRecoverySource[];
  private readonly perSourceTimeoutMs: number;
  private readonly totalBudgetMs: number;
  private readonly now: () => number;

  constructor(sources: IRecoverySource[], config?: RecoveryCascadeConfig) {
    this.sources = [...sources].sort((a, b) => a.priority - b.priority);
    this.perSourceTimeoutMs = config?.perSourceTimeoutMs ?? 10_000;
    this.totalBudgetMs = config?.totalBudgetMs ?? 30_000;
    this.now = config?.now ?? Date.now;
  }

  async run(): Promise<RecoveryResult> {
    const attempts: RecoveryAttempt[] = [];
    const startTime = this.now();

    for (const source of this.sources) {
      const elapsed = this.now() - startTime;
      const remaining = this.totalBudgetMs - elapsed;

      if (remaining <= 0) break;

      const timeout = Math.min(this.perSourceTimeoutMs, remaining);
      const attemptStart = this.now();

      try {
        const available = await raceTimeout(
          source.isAvailable(),
          timeout,
          `${source.name}.isAvailable`,
        );
        if (!available) {
          attempts.push({
            source: source.name,
            success: false,
            durationMs: this.now() - attemptStart,
            error: "source unavailable",
          });
          continue;
        }

        const remainingAfterCheck = timeout - (this.now() - attemptStart);
        if (remainingAfterCheck <= 0) {
          attempts.push({
            source: source.name,
            success: false,
            durationMs: this.now() - attemptStart,
            error: "budget exhausted after availability check",
          });
          continue;
        }

        const data = await raceTimeout(
          source.restore(),
          remainingAfterCheck,
          `${source.name}.restore`,
        );

        if (source.validate) {
          const remainingAfterRestore = timeout - (this.now() - attemptStart);
          const valid = remainingAfterRestore > 0
            ? await raceTimeout(
                source.validate(data),
                remainingAfterRestore,
                `${source.name}.validate`,
              )
            : false;

          if (!valid) {
            attempts.push({
              source: source.name,
              success: false,
              durationMs: this.now() - attemptStart,
              error: "validation failed",
            });
            continue;
          }
        }

        attempts.push({
          source: source.name,
          success: true,
          durationMs: this.now() - attemptStart,
        });

        return {
          sourceUsed: source.name,
          data,
          attempts,
          totalDurationMs: this.now() - startTime,
        };
      } catch (err) {
        attempts.push({
          source: source.name,
          success: false,
          durationMs: this.now() - attemptStart,
          error: err instanceof Error ? err.message : String(err),
        });
      }
    }

    throw new LoaLibError(
      `All recovery sources failed (${attempts.length} attempted)`,
      "SYN_001",
      false,
    );
  }
}

// ── Factory ──────────────────────────────────────────

export function createRecoveryCascade(
  sources: IRecoverySource[],
  config?: RecoveryCascadeConfig,
): RecoveryCascade {
  return new RecoveryCascade(sources, config);
}
