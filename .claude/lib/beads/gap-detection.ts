/**
 * Gap Detection for Session Recovery
 *
 * Detects discontinuities in session history and provides structured
 * recovery guidance. Informed by MLP v0.2's gap protocol concept,
 * adapted for Loa's single-user, local-first architecture.
 *
 * Gap detection answers: "What happened between my last session and now?"
 * This is the same question PostgreSQL's crash recovery answers on startup:
 * determine the recovery point, assess what's known vs unknown, then
 * provide actionable guidance.
 *
 * @module beads/gap-detection
 * @version 1.0.0
 * @see https://github.com/0xHoneyJar/loa/issues/208
 */

import type { Bead, IBrExecutor } from "./interfaces";
import {
  LABELS,
  getLabelsWithPrefix,
  hasLabel,
  hasLabelWithPrefix,
} from "./labels";
import { validateBeadId } from "./validation";

// =============================================================================
// Types
// =============================================================================

/**
 * Severity levels for detected gaps.
 *
 * Modeled after syslog severity — the same pattern Prometheus uses for
 * alert routing. CRITICAL gaps require user intervention. LOW gaps are
 * informational and can be auto-resolved.
 */
export type GapSeverity = "CRITICAL" | "HIGH" | "MEDIUM" | "LOW";

/**
 * A detected gap in session continuity.
 *
 * Each gap includes enough context for an agent or human to understand
 * what happened and what to do about it.
 */
export interface DetectedGap {
  /** Gap type identifier */
  type:
    | "orphaned_task"
    | "stale_handoff"
    | "missing_session_sequence"
    | "unresolved_circuit_breaker";

  /** Severity determines recovery priority */
  severity: GapSeverity;

  /** Human-readable description of the gap */
  description: string;

  /** Bead IDs involved in this gap */
  affectedBeadIds: string[];

  /** Suggested recovery action */
  suggestedAction: string;

  /** Whether this gap can be auto-resolved */
  autoResolvable: boolean;
}

/**
 * Result of a gap detection scan.
 *
 * The compilation trace pattern (borrowed from MLP's ContextPack) makes
 * gap detection debuggable — you can see exactly what was checked and
 * what was found, like Webpack's stats output.
 */
export interface GapDetectionResult {
  /** Timestamp of the scan */
  scannedAt: string;

  /** All detected gaps, sorted by severity */
  gaps: DetectedGap[];

  /** Summary statistics */
  stats: {
    /** Total beads scanned */
    beadsScanned: number;
    /** Number of gaps found */
    gapsFound: number;
    /** Breakdown by severity */
    bySeverity: Record<GapSeverity, number>;
    /** Breakdown by type */
    byType: Record<string, number>;
  };

  /** Whether the session state is healthy (no CRITICAL or HIGH gaps) */
  healthy: boolean;
}

/**
 * Configuration for gap detection.
 */
export interface GapDetectionConfig {
  /**
   * How long (in ms) before a handoff is considered stale.
   * Default: 30 minutes (1800000 ms).
   *
   * This should match the work queue's session timeout.
   */
  staleHandoffThresholdMs?: number;

  /**
   * How long (in ms) before an in-progress task without a session
   * label is considered orphaned.
   * Default: 60 minutes (3600000 ms).
   */
  orphanedTaskThresholdMs?: number;

  /** Enable verbose logging */
  verbose?: boolean;
}

// =============================================================================
// Constants
// =============================================================================

const DEFAULT_STALE_HANDOFF_MS = 30 * 60 * 1000; // 30 minutes
const DEFAULT_ORPHANED_TASK_MS = 60 * 60 * 1000; // 60 minutes

// =============================================================================
// GapDetector
// =============================================================================

/**
 * Detects gaps in session continuity and provides recovery guidance.
 *
 * Like PostgreSQL's startup recovery sequence, the detector:
 * 1. Scans the current state (WAL replay equivalent)
 * 2. Identifies inconsistencies (gap detection)
 * 3. Reports what's known vs unknown (gap report)
 * 4. Suggests recovery actions (recovery plan)
 *
 * @example
 * ```typescript
 * const detector = new GapDetector(executor);
 * const result = await detector.detect();
 *
 * if (!result.healthy) {
 *   for (const gap of result.gaps) {
 *     if (gap.autoResolvable) {
 *       await detector.autoResolve(gap);
 *     } else {
 *       console.log(`Manual resolution needed: ${gap.description}`);
 *     }
 *   }
 * }
 * ```
 */
export class GapDetector {
  private readonly executor: IBrExecutor;
  private readonly staleHandoffMs: number;
  private readonly orphanedTaskMs: number;
  private readonly verbose: boolean;

  constructor(executor: IBrExecutor, config?: GapDetectionConfig) {
    this.executor = executor;
    this.staleHandoffMs =
      config?.staleHandoffThresholdMs ?? DEFAULT_STALE_HANDOFF_MS;
    this.orphanedTaskMs =
      config?.orphanedTaskThresholdMs ?? DEFAULT_ORPHANED_TASK_MS;
    this.verbose = config?.verbose ?? false;
  }

  /**
   * Run a full gap detection scan.
   *
   * Checks for:
   * 1. Orphaned in-progress tasks (no active session)
   * 2. Stale handoffs (handoff labels past timeout)
   * 3. Unresolved circuit breakers
   * 4. Missing session sequences (gaps in session timeline)
   */
  async detect(): Promise<GapDetectionResult> {
    const gaps: DetectedGap[] = [];
    let beadsScanned = 0;
    const now = Date.now();

    // Phase 1: Detect orphaned in-progress tasks
    const orphanedGaps = await this.detectOrphanedTasks(now);
    gaps.push(...orphanedGaps.gaps);
    beadsScanned += orphanedGaps.scanned;

    // Phase 2: Detect stale handoffs
    const staleGaps = await this.detectStaleHandoffs(now);
    gaps.push(...staleGaps.gaps);
    beadsScanned += staleGaps.scanned;

    // Phase 3: Detect unresolved circuit breakers
    const cbGaps = await this.detectUnresolvedCircuitBreakers();
    gaps.push(...cbGaps.gaps);
    beadsScanned += cbGaps.scanned;

    // Phase 4: Detect missing session sequences
    const seqGaps = await this.detectSessionSequenceGaps();
    gaps.push(...seqGaps.gaps);
    beadsScanned += seqGaps.scanned;

    // Sort by severity (CRITICAL first)
    const severityOrder: Record<GapSeverity, number> = {
      CRITICAL: 0,
      HIGH: 1,
      MEDIUM: 2,
      LOW: 3,
    };
    gaps.sort((a, b) => severityOrder[a.severity] - severityOrder[b.severity]);

    // Compile statistics
    const bySeverity: Record<GapSeverity, number> = {
      CRITICAL: 0,
      HIGH: 0,
      MEDIUM: 0,
      LOW: 0,
    };
    const byType: Record<string, number> = {};

    for (const gap of gaps) {
      bySeverity[gap.severity]++;
      byType[gap.type] = (byType[gap.type] || 0) + 1;
    }

    const healthy = bySeverity.CRITICAL === 0 && bySeverity.HIGH === 0;

    return {
      scannedAt: new Date().toISOString(),
      gaps,
      stats: {
        beadsScanned,
        gapsFound: gaps.length,
        bySeverity,
        byType,
      },
      healthy,
    };
  }

  /**
   * Detect tasks marked in-progress but with no active session.
   *
   * An orphaned task indicates a session crashed or timed out without
   * recording a handoff — the agent equivalent of a dangling mutex.
   */
  private async detectOrphanedTasks(
    nowMs: number,
  ): Promise<{ gaps: DetectedGap[]; scanned: number }> {
    const gaps: DetectedGap[] = [];

    try {
      const inProgressTasks = await this.queryBeads(
        `list --label '${LABELS.SPRINT_IN_PROGRESS}' --type task --json`,
      );

      if (!inProgressTasks) return { gaps: [], scanned: 0 };

      for (const task of inProgressTasks) {
        const labels = task.labels || [];
        const sessionLabels = getLabelsWithPrefix(
          labels,
          LABELS.SESSION_PREFIX,
        );

        // Task is in-progress but has no session label
        if (sessionLabels.length === 0) {
          const taskAge = nowMs - new Date(task.updated_at).getTime();

          if (taskAge > this.orphanedTaskMs) {
            gaps.push({
              type: "orphaned_task",
              severity: "HIGH",
              description: `Task "${task.title}" (${task.id}) has been in-progress for ${Math.round(taskAge / 60000)}min with no active session`,
              affectedBeadIds: [task.id],
              suggestedAction:
                "Reset task to ready state, or resume with a new session",
              autoResolvable: true,
            });
          }
        }
      }

      return { gaps, scanned: inProgressTasks.length };
    } catch (e) {
      if (this.verbose) {
        console.error(`[gap-detection] Error detecting orphaned tasks: ${e}`);
      }
      return { gaps: [], scanned: 0 };
    }
  }

  /**
   * Detect handoff labels that have expired without being picked up.
   *
   * A stale handoff means a session recorded its context but no
   * subsequent session claimed the work — like an undelivered message
   * in a dead letter queue.
   */
  private async detectStaleHandoffs(
    nowMs: number,
  ): Promise<{ gaps: DetectedGap[]; scanned: number }> {
    const gaps: DetectedGap[] = [];

    try {
      // Query all open beads that have handoff labels
      const allOpen = await this.queryBeads(`list --status open --json`);

      if (!allOpen) return { gaps: [], scanned: 0 };

      const withHandoffs = allOpen.filter((b) =>
        hasLabelWithPrefix(b.labels || [], LABELS.HANDOFF_PREFIX),
      );

      for (const bead of withHandoffs) {
        const beadAge = nowMs - new Date(bead.updated_at).getTime();

        if (beadAge > this.staleHandoffMs) {
          // Check if there's a newer session that picked this up
          const sessionLabels = getLabelsWithPrefix(
            bead.labels || [],
            LABELS.SESSION_PREFIX,
          );
          const handoffLabels = getLabelsWithPrefix(
            bead.labels || [],
            LABELS.HANDOFF_PREFIX,
          );

          // If handoff count >= session count, no new session claimed it
          if (handoffLabels.length >= sessionLabels.length) {
            gaps.push({
              type: "stale_handoff",
              severity: "MEDIUM",
              description: `Bead "${bead.title}" (${bead.id}) has unclaimed handoff (${Math.round(beadAge / 60000)}min old)`,
              affectedBeadIds: [bead.id],
              suggestedAction:
                "Claim handoff with a new session, or reset task state",
              autoResolvable: false,
            });
          }
        }
      }

      return { gaps, scanned: allOpen.length };
    } catch (e) {
      if (this.verbose) {
        console.error(`[gap-detection] Error detecting stale handoffs: ${e}`);
      }
      return { gaps: [], scanned: 0 };
    }
  }

  /**
   * Detect unresolved circuit breakers.
   *
   * An open circuit breaker means a previous run halted and was never
   * resumed — the system is in a known-bad state that requires attention.
   */
  private async detectUnresolvedCircuitBreakers(): Promise<{
    gaps: DetectedGap[];
    scanned: number;
  }> {
    const gaps: DetectedGap[] = [];

    try {
      const circuitBreakers = await this.queryBeads(
        `list --label '${LABELS.CIRCUIT_BREAKER}' --status open --json`,
      );

      if (!circuitBreakers) return { gaps: [], scanned: 0 };

      for (const cb of circuitBreakers) {
        gaps.push({
          type: "unresolved_circuit_breaker",
          severity: "CRITICAL",
          description: `Unresolved circuit breaker "${cb.title}" (${cb.id}) — run is halted`,
          affectedBeadIds: [cb.id],
          suggestedAction:
            "Investigate failure cause, then resolve circuit breaker to resume",
          autoResolvable: false,
        });
      }

      return { gaps, scanned: circuitBreakers.length };
    } catch (e) {
      if (this.verbose) {
        console.error(
          `[gap-detection] Error detecting circuit breakers: ${e}`,
        );
      }
      return { gaps: [], scanned: 0 };
    }
  }

  /**
   * Detect gaps in session sequence timeline.
   *
   * Looks for beads that were modified between sessions without any
   * session label — indicating out-of-band changes that may not be
   * tracked in the handoff chain.
   */
  private async detectSessionSequenceGaps(): Promise<{
    gaps: DetectedGap[];
    scanned: number;
  }> {
    const gaps: DetectedGap[] = [];

    try {
      // Find all beads with session labels to build timeline
      const allBeads = await this.queryBeads(`list --json`);

      if (!allBeads || allBeads.length === 0) return { gaps: [], scanned: 0 };

      // Collect all session IDs and their timestamps
      const sessions = new Map<string, { beadIds: string[]; latest: string }>();

      for (const bead of allBeads) {
        const sessionLabels = getLabelsWithPrefix(
          bead.labels || [],
          LABELS.SESSION_PREFIX,
        );
        for (const label of sessionLabels) {
          const sessionId = label.slice(LABELS.SESSION_PREFIX.length);
          const existing = sessions.get(sessionId);
          if (existing) {
            existing.beadIds.push(bead.id);
            if (bead.updated_at > existing.latest) {
              existing.latest = bead.updated_at;
            }
          } else {
            sessions.set(sessionId, {
              beadIds: [bead.id],
              latest: bead.updated_at,
            });
          }
        }
      }

      // Find beads modified recently that have NO session labels
      // (indicates out-of-band modification)
      if (sessions.size > 0) {
        const latestSessionTime = Math.max(
          ...Array.from(sessions.values()).map((s) =>
            new Date(s.latest).getTime(),
          ),
        );

        const unsessioned = allBeads.filter((b) => {
          const labels = b.labels || [];
          const hasSession = hasLabelWithPrefix(labels, LABELS.SESSION_PREFIX);
          const modifiedAfterLastSession =
            new Date(b.updated_at).getTime() > latestSessionTime;
          return (
            !hasSession && modifiedAfterLastSession && b.status === "open"
          );
        });

        if (unsessioned.length > 0) {
          gaps.push({
            type: "missing_session_sequence",
            severity: "LOW",
            description: `${unsessioned.length} bead(s) modified after last session without session tracking`,
            affectedBeadIds: unsessioned.map((b) => b.id),
            suggestedAction:
              "Review out-of-band changes and attach to current session if relevant",
            autoResolvable: false,
          });
        }
      }

      return { gaps, scanned: allBeads.length };
    } catch (e) {
      if (this.verbose) {
        console.error(
          `[gap-detection] Error detecting session sequence gaps: ${e}`,
        );
      }
      return { gaps: [], scanned: 0 };
    }
  }

  /**
   * Auto-resolve a gap that's marked as auto-resolvable.
   *
   * Currently supports:
   * - orphaned_task: Removes in-progress label, adds ready label
   *
   * @returns true if resolution was successful
   */
  async autoResolve(gap: DetectedGap): Promise<boolean> {
    if (!gap.autoResolvable) {
      return false;
    }

    try {
      switch (gap.type) {
        case "orphaned_task": {
          for (const beadId of gap.affectedBeadIds) {
            validateBeadId(beadId);
            // Reset task from in-progress back to ready
            await this.executor.exec(
              `label remove '${beadId}' '${LABELS.SPRINT_IN_PROGRESS}'`,
            );
            await this.executor.exec(
              `label add '${beadId}' '${LABELS.STATUS_READY}'`,
            );
          }
          return true;
        }
        default:
          return false;
      }
    } catch (e) {
      if (this.verbose) {
        console.error(`[gap-detection] Auto-resolve failed: ${e}`);
      }
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Private Helpers
  // ---------------------------------------------------------------------------

  private async queryBeads(args: string): Promise<Bead[] | null> {
    try {
      return await this.executor.execJson<Bead[]>(args);
    } catch {
      return null;
    }
  }
}

// =============================================================================
// Factory Function
// =============================================================================

/**
 * Create a GapDetector instance.
 *
 * @param executor - BR command executor (or mock for testing)
 * @param config - Optional configuration
 */
export function createGapDetector(
  executor: IBrExecutor,
  config?: GapDetectionConfig,
): GapDetector {
  return new GapDetector(executor, config);
}
