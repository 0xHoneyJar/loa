/**
 * Context Compiler ("ContextPack Lite")
 *
 * Task-aware context assembly with compilation trace. Informed by MLP v0.2's
 * ContextPack concept, adapted for Loa's development framework use case.
 *
 * The compiler answers: "Given a token budget and a target task, which beads
 * should an agent receive as context, and why?"
 *
 * This is the same problem Webpack's tree-shaking solves: you don't ship all
 * code to the browser — you analyze the dependency graph, include what's
 * reachable, and report what was eliminated. Without a compilation trace,
 * you can't debug bundle size. Without a context compilation trace, you
 * can't debug agent behavior.
 *
 * @module beads/context-compiler
 * @version 1.0.0
 * @see https://github.com/0xHoneyJar/loa/issues/208
 */

import type { Bead, IBrExecutor } from "./interfaces";
import {
  LABELS,
  getLabelsWithPrefix,
  hasLabel,
  hasLabelWithPrefix,
  deriveClassification,
  deriveConfidence,
  classificationPriority,
  type BeadClassification,
  type ConfidenceLevel,
} from "./labels";
import { validateBeadId, validateLabel } from "./validation";

// =============================================================================
// Types
// =============================================================================

/**
 * Reason a bead was excluded from the context window.
 */
export type ExclusionReason =
  | "over_token_budget"
  | "stale_confidence"
  | "routine_classification"
  | "irrelevant_to_task"
  | "duplicate_superseded";

/**
 * A bead scored and annotated for context inclusion.
 */
export interface ScoredBead {
  /** The original bead */
  bead: Bead;

  /** Computed priority score (higher = more important) */
  score: number;

  /** Derived classification (null if unclassified) */
  classification: BeadClassification | null;

  /** Derived confidence (null if no confidence label) */
  confidence: ConfidenceLevel | null;

  /** Estimated token count for this bead's content */
  estimatedTokens: number;

  /** Why this bead was included or excluded */
  reason: string;
}

/**
 * Result of context compilation.
 *
 * The trace pattern makes context assembly debuggable — you can see
 * exactly what was considered, included, and excluded, like Webpack's
 * stats output.
 */
export interface ContextCompilationResult {
  /** Beads included in the context window, sorted by priority */
  included: ScoredBead[];

  /** Beads that were considered but excluded */
  excluded: Array<ScoredBead & { exclusionReason: ExclusionReason }>;

  /** Compilation statistics */
  stats: {
    /** Total beads considered */
    considered: number;
    /** Number included in context */
    included: number;
    /** Exclusions by reason */
    excludedByReason: Record<string, number>;
    /** Estimated total tokens of included beads */
    estimatedTokens: number;
    /** Token budget that was specified */
    tokenBudget: number;
    /** Token budget utilization (0-1) */
    utilization: number;
  };

  /** ISO timestamp of compilation */
  compiledAt: string;
}

/**
 * Configuration for context compilation.
 */
export interface ContextCompilerConfig {
  /**
   * Maximum estimated tokens for the compiled context.
   * Default: 4000 (roughly 1/4 of a typical 16K context window,
   * leaving room for system prompt, tools, and response).
   */
  tokenBudget?: number;

  /**
   * Average characters per token for estimation.
   * Default: 4 (conservative estimate for English text).
   *
   * Claude's actual tokenizer averages ~3.5 chars/token for code
   * and ~4.5 for prose. 4 is a reasonable middle ground.
   */
  charsPerToken?: number;

  /**
   * Whether to include superseded beads.
   * Default: false (only include the latest in a supersession chain).
   */
  includeSuperseded?: boolean;

  /**
   * Whether to include beads with stale confidence.
   * Default: false.
   */
  includeStale?: boolean;

  /** Enable verbose logging */
  verbose?: boolean;
}

// =============================================================================
// Constants
// =============================================================================

const DEFAULT_TOKEN_BUDGET = 4000;
const DEFAULT_CHARS_PER_TOKEN = 4;

// =============================================================================
// ContextCompiler
// =============================================================================

/**
 * Compiles task-aware context from beads with priority-based inclusion.
 *
 * Compilation strategy (priority-ordered):
 * 1. Current task bead + its dependency chain (always included)
 * 2. Active circuit breakers (always included — safety critical)
 * 3. Recent class:decision beads from same sprint
 * 4. Previous session's handoff for this task
 * 5. class:discovery beads tagged with related labels
 * 6. class:context beads within token budget
 * 7. Everything else: excluded with reason
 *
 * @example
 * ```typescript
 * const compiler = new ContextCompiler(executor);
 * const result = await compiler.compile("task-123");
 *
 * // Use included beads as agent context
 * for (const { bead, reason } of result.included) {
 *   console.log(`Including ${bead.title}: ${reason}`);
 * }
 *
 * // Debug what was excluded
 * console.log(`Budget: ${result.stats.estimatedTokens}/${result.stats.tokenBudget}`);
 * ```
 */
export class ContextCompiler {
  private readonly executor: IBrExecutor;
  private readonly tokenBudget: number;
  private readonly charsPerToken: number;
  private readonly includeSuperseded: boolean;
  private readonly includeStale: boolean;
  private readonly verbose: boolean;

  constructor(executor: IBrExecutor, config?: ContextCompilerConfig) {
    this.executor = executor;
    this.tokenBudget = config?.tokenBudget ?? DEFAULT_TOKEN_BUDGET;
    this.charsPerToken = config?.charsPerToken ?? DEFAULT_CHARS_PER_TOKEN;
    this.includeSuperseded = config?.includeSuperseded ?? false;
    this.includeStale = config?.includeStale ?? false;
    this.verbose = config?.verbose ?? false;
  }

  /**
   * Compile context for a specific task.
   *
   * @param taskBeadId - The bead ID of the task to compile context for
   * @returns Compilation result with included/excluded beads and trace
   */
  async compile(taskBeadId: string): Promise<ContextCompilationResult> {
    validateBeadId(taskBeadId);

    const allBeads = await this.fetchRelevantBeads(taskBeadId);
    const scored = this.scoreBeads(allBeads, taskBeadId);

    // Sort by score descending (highest priority first)
    scored.sort((a, b) => b.score - a.score);

    // Fill context window within token budget
    const included: ScoredBead[] = [];
    const excluded: Array<ScoredBead & { exclusionReason: ExclusionReason }> =
      [];
    let usedTokens = 0;

    for (const scoredBead of scored) {
      // Check exclusion rules first
      const exclusion = this.checkExclusion(scoredBead);
      if (exclusion) {
        excluded.push({ ...scoredBead, exclusionReason: exclusion });
        continue;
      }

      // Check token budget
      if (usedTokens + scoredBead.estimatedTokens > this.tokenBudget) {
        excluded.push({
          ...scoredBead,
          exclusionReason: "over_token_budget",
        });
        continue;
      }

      included.push(scoredBead);
      usedTokens += scoredBead.estimatedTokens;
    }

    // Compile statistics
    const excludedByReason: Record<string, number> = {};
    for (const ex of excluded) {
      excludedByReason[ex.exclusionReason] =
        (excludedByReason[ex.exclusionReason] || 0) + 1;
    }

    return {
      included,
      excluded,
      stats: {
        considered: scored.length,
        included: included.length,
        excludedByReason,
        estimatedTokens: usedTokens,
        tokenBudget: this.tokenBudget,
        utilization:
          this.tokenBudget > 0 ? usedTokens / this.tokenBudget : 0,
      },
      compiledAt: new Date().toISOString(),
    };
  }

  /**
   * Fetch all beads that could be relevant to the target task.
   */
  private async fetchRelevantBeads(taskBeadId: string): Promise<Bead[]> {
    const beads: Bead[] = [];
    const seenIds = new Set<string>();

    const addBead = (bead: Bead) => {
      if (!seenIds.has(bead.id)) {
        seenIds.add(bead.id);
        beads.push(bead);
      }
    };

    // 1. The target task itself
    const task = await this.fetchBead(taskBeadId);
    if (task) addBead(task);

    // 2. Active circuit breakers (always safety-critical)
    const circuitBreakers = await this.queryBeads(
      `list --label '${LABELS.CIRCUIT_BREAKER}' --status open --json`,
    );
    if (circuitBreakers) {
      for (const cb of circuitBreakers) addBead(cb);
    }

    // 3. Same-sprint beads (decisions, discoveries, context from current work)
    if (task) {
      const taskLabels = task.labels || [];
      // Find sprint/epic labels to scope the query
      const epicLabels = getLabelsWithPrefix(taskLabels, "epic:");
      for (const epicLabel of epicLabels) {
        validateLabel(epicLabel); // Defense-in-depth: label from store interpolated into shell cmd
        const sprintBeads = await this.queryBeads(
          `list --label '${epicLabel}' --json`,
        );
        if (sprintBeads) {
          for (const b of sprintBeads) addBead(b);
        }
      }
    }

    // 4. Beads with handoff labels (session continuity)
    const handoffBeads = await this.queryBeads(`list --status open --json`);
    if (handoffBeads) {
      for (const b of handoffBeads) {
        if (hasLabelWithPrefix(b.labels || [], LABELS.HANDOFF_PREFIX)) {
          addBead(b);
        }
      }
    }

    // 5. Recent classified beads (decisions and blockers are always relevant)
    const decisionBeads = await this.queryBeads(
      `list --label '${LABELS.CLASS_DECISION}' --status open --json`,
    );
    if (decisionBeads) {
      for (const b of decisionBeads) addBead(b);
    }

    const blockerBeads = await this.queryBeads(
      `list --label '${LABELS.CLASS_BLOCKER}' --status open --json`,
    );
    if (blockerBeads) {
      for (const b of blockerBeads) addBead(b);
    }

    return beads;
  }

  /**
   * Score each bead for context priority.
   *
   * Scoring factors:
   * - Classification priority (0-5)
   * - Is target task or direct dependency (+10)
   * - Is circuit breaker (+8)
   * - Has handoff for target (+6)
   * - Confidence level modifier (+2 explicit, +1 derived, -1 stale)
   * - Recency bonus (more recent = higher, max +3)
   */
  private scoreBeads(beads: Bead[], taskBeadId: string): ScoredBead[] {
    const now = Date.now();

    return beads.map((bead) => {
      const labels = bead.labels || [];
      const classification = deriveClassification(labels);
      const confidence = deriveConfidence(labels);

      let score = classificationPriority(classification);
      let reason = "";

      // Target task or dependency — always highest priority
      if (bead.id === taskBeadId) {
        score += 10;
        reason = "Target task";
      } else if (bead.depends_on?.includes(taskBeadId)) {
        score += 10;
        reason = "Direct dependency of target task";
      }

      // Circuit breaker — safety critical
      if (hasLabel(labels, LABELS.CIRCUIT_BREAKER)) {
        score += 8;
        reason = reason || "Active circuit breaker";
      }

      // Handoff — session continuity
      if (hasLabelWithPrefix(labels, LABELS.HANDOFF_PREFIX)) {
        score += 6;
        reason = reason || "Session handoff context";
      }

      // Confidence modifier
      switch (confidence) {
        case "explicit":
          score += 2;
          break;
        case "derived":
          score += 1;
          break;
        case "stale":
          score -= 1;
          break;
      }

      // Recency bonus (max +3 for beads updated in last hour)
      const ageMs = now - new Date(bead.updated_at).getTime();
      const ageHours = ageMs / (60 * 60 * 1000);
      if (ageHours < 1) {
        score += 3;
      } else if (ageHours < 8) {
        score += 2;
      } else if (ageHours < 24) {
        score += 1;
      }

      if (!reason) {
        reason = classification
          ? `Classified as ${classification}`
          : "Unclassified bead";
      }

      const estimatedTokens = this.estimateTokens(bead);

      return {
        bead,
        score,
        classification,
        confidence,
        estimatedTokens,
        reason,
      };
    });
  }

  /**
   * Check if a scored bead should be excluded.
   */
  private checkExclusion(scored: ScoredBead): ExclusionReason | null {
    // Exclude stale beads unless configured otherwise
    if (!this.includeStale && scored.confidence === "stale") {
      return "stale_confidence";
    }

    // Exclude routine beads with low scores
    if (scored.classification === "routine" && scored.score < 3) {
      return "routine_classification";
    }

    // Exclude superseded beads unless configured otherwise
    if (!this.includeSuperseded) {
      const labels = scored.bead.labels || [];
      // If this bead has been superseded by another, exclude it
      // (we detect this by checking if any OTHER bead has a supersedes:thisId label)
      // For now, check if this bead is closed — closed + superseded = skip
      if (
        scored.bead.status === "closed" &&
        hasLabelWithPrefix(labels, LABELS.SUPERSEDES_PREFIX)
      ) {
        return "duplicate_superseded";
      }
    }

    return null;
  }

  /**
   * Estimate token count for a bead.
   *
   * Uses a simple heuristic: (title + description) / chars_per_token.
   * Claude's actual tokenizer averages ~3.5 chars/token for code
   * and ~4.5 for prose.
   */
  private estimateTokens(bead: Bead): number {
    const title = bead.title || "";
    const description = bead.description || "";
    const labels = (bead.labels || []).join(" ");
    const totalChars = title.length + description.length + labels.length;
    return Math.max(1, Math.ceil(totalChars / this.charsPerToken));
  }

  /**
   * Fetch a single bead by ID.
   */
  private async fetchBead(beadId: string): Promise<Bead | null> {
    try {
      return await this.executor.execJson<Bead>(`show '${beadId}' --json`);
    } catch {
      return null;
    }
  }

  /**
   * Query beads with error handling.
   */
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
 * Create a ContextCompiler instance.
 *
 * @param executor - BR command executor (or mock for testing)
 * @param config - Optional configuration
 */
export function createContextCompiler(
  executor: IBrExecutor,
  config?: ContextCompilerConfig,
): ContextCompiler {
  return new ContextCompiler(executor, config);
}
